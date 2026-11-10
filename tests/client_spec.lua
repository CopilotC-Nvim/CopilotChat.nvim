local client = require('CopilotChat.client')
local curl = require('CopilotChat.utils.curl')
local copilot = require('CopilotChat.config.providers').copilot
local utils = require('CopilotChat.utils')
local async = require('plenary.async')
local notify = require('CopilotChat.utils.notify')

describe('CopilotChat.client model cache', function()
  local saved
  local now
  local calls
  local provider

  before_each(function()
    saved = {
      time = os.time,
      resolver = client.provider_resolver,
      cache = client.provider_cache,
      get = curl.get,
      post = curl.post,
      publish = notify.publish,
    }
    now = 1000
    os.time = function()
      return now
    end
    calls = 0
    provider = {
      get_models = function()
        calls = calls + 1
        return { { id = 'auto', name = 'Auto' } }
      end,
    }
    client.provider_cache = vim.defaulttable(function()
      return {}
    end)
    client:set_providers(function()
      return { copilot = provider }
    end)
  end)

  after_each(function()
    os.time = saved.time
    client.provider_resolver = saved.resolver
    client.provider_cache = saved.cache
    curl.get = saved.get
    curl.post = saved.post
    notify.publish = saved.publish
  end)

  it('caches a successful first fetch for five minutes', function()
    assert.equals('copilot', client:models().auto.provider)
    assert.equals(1300, client.provider_cache.copilot.models_expires_at)
    now = 1299
    assert.is_not_nil(client:models().auto)
    assert.equals(1, calls)
  end)

  it('retries after a cooldown following an initial fetch failure', function()
    local get_models = provider.get_models
    provider.get_models = function()
      calls = calls + 1
      error('temporary model API failure')
    end
    assert.are.same({}, client:models())
    assert.equals(1, calls)
    assert.is_nil(client.provider_cache.copilot.models)
    assert.is_nil(client.provider_cache.copilot.models_expires_at)

    provider.get_models = get_models
    for _ = 1, 20 do
      assert.are.same({}, client:models())
    end
    now = 1059
    assert.are.same({}, client:models())
    assert.equals(1, calls)
    now = 1060
    assert.is_not_nil(client:models().auto)
    assert.equals(2, calls)
    assert.is_nil(client.provider_cache.copilot.models_retry_at)
  end)

  it('retries authentication without caching an empty model list', function()
    local auth_calls = 0
    provider.get_headers = function()
      auth_calls = auth_calls + 1
      if auth_calls == 1 then
        error('temporary authentication failure')
      end
      return {}
    end
    assert.are.same({}, client:models())
    assert.equals(0, calls)
    assert.is_nil(client.provider_cache.copilot.models)
    assert.are.same({}, client:models())
    assert.equals(1, auth_calls)
    now = 1060
    assert.is_not_nil(client:models().auto)
    assert.equals(2, auth_calls)
    assert.equals(1, calls)
  end)

  it('refreshes at the cache expiration boundary', function()
    client:models()
    now = 1300
    assert.is_not_nil(client:models().auto)
    assert.equals(2, calls)
    assert.equals(1600, client.provider_cache.copilot.models_expires_at)
  end)

  it('preserves stale models and their expiry after a failed refresh, then recovers', function()
    client:models()
    local models = client.provider_cache.copilot.models
    local get_models = provider.get_models
    now = 1300
    provider.get_models = function()
      calls = calls + 1
      error('temporary model API failure')
    end
    assert.is_not_nil(client:models().auto)
    assert.equals(models, client.provider_cache.copilot.models)
    assert.equals(1300, client.provider_cache.copilot.models_expires_at)
    assert.equals(2, calls)

    provider.get_models = get_models
    assert.is_not_nil(client:models().auto)
    assert.equals(2, calls)
    now = 1360
    assert.is_not_nil(client:models().auto)
    assert.equals(3, calls)
    assert.equals(1660, client.provider_cache.copilot.models_expires_at)
  end)

  it('preserves stale models when authentication refresh fails', function()
    provider.get_headers = function()
      return {}, 1300
    end
    client:models()
    now = 1300
    provider.get_headers = function()
      error('temporary authentication failure')
    end
    assert.is_not_nil(client:models().auto)
    assert.equals(1, calls)
    assert.equals(1300, client.provider_cache.copilot.models_expires_at)
  end)

  it('limits persistent failures to one provider call per cooldown', function()
    provider.get_models = function()
      calls = calls + 1
      error('model API unavailable')
    end
    for _ = 1, 3 do
      assert.are.same({}, client:models())
    end
    assert.equals(1, calls)
    now = 1060
    assert.are.same({}, client:models())
    assert.equals(2, calls)
    now = 1119
    assert.are.same({}, client:models())
    assert.equals(2, calls)
    now = 1120
    assert.are.same({}, client:models())
    assert.equals(3, calls)
  end)

  it('caches a genuinely successful empty list', function()
    provider.get_models = function()
      calls = calls + 1
      return {}
    end
    assert.are.same({}, client:models())
    assert.are.same({}, client:models())
    assert.equals(1, calls)
    assert.equals(1300, client.provider_cache.copilot.models_expires_at)
  end)

  it('replaces stale models when the provider successfully returns an empty list', function()
    client:models()
    now = 1300
    provider.get_models = function()
      calls = calls + 1
      return {}
    end
    assert.are.same({}, client:models())
    assert.are.same({}, client:models())
    assert.equals(2, calls)
    assert.equals(1600, client.provider_cache.copilot.models_expires_at)
    assert.is_nil(client.provider_cache.copilot.models_retry_at)
  end)

  it('keeps the shared provider info cache working', function()
    local infos = 0
    provider.get_info = function()
      infos = infos + 1
      return { 'Provider info' }
    end
    assert.are.same({ copilot = { 'Provider info' } }, client:info())
    assert.are.same({ copilot = { 'Provider info' } }, client:info())
    assert.equals(1, infos)
    now = 1300
    assert.are.same({ copilot = { 'Provider info' } }, client:info())
    assert.equals(2, infos)
  end)

  it('does not cache a missing provider result as a successful empty list', function()
    provider.get_models = function()
      calls = calls + 1
    end
    assert.are.same({}, client:models())
    assert.is_nil(client.provider_cache.copilot.models_expires_at)
    assert.are.same({}, client:models())
    assert.equals(1, calls)
    now = 1060
    assert.are.same({}, client:models())
    assert.equals(2, calls)
  end)

  it('keeps other providers usable and independently cached after a failure', function()
    local other_calls = 0
    provider.get_models = function()
      calls = calls + 1
      error('model API unavailable')
    end
    client:set_providers(function()
      return {
        copilot = provider,
        other = {
          get_models = function()
            other_calls = other_calls + 1
            return { { id = 'other-model' } }
          end,
        },
      }
    end)
    assert.equals('other', client:models()['other-model'].provider)
    assert.equals('other', client:models()['other-model'].provider)
    assert.equals(1, calls)
    now = 1060
    assert.equals('other', client:models()['other-model'].provider)
    assert.equals(2, calls)
    assert.equals(1, other_calls)
  end)

  it('recovers auto selection through the Copilot provider after invalid JSON', function()
    local fetches = 0
    provider.get_models = copilot.get_models
    provider.resolve_model = copilot.resolve_model
    provider.prepare_input = copilot.prepare_input
    provider.prepare_output = copilot.prepare_output
    provider.get_url = copilot.get_url
    curl.get = function(url)
      assert.equals('https://api.githubcopilot.com/models', url)
      fetches = fetches + 1
      if fetches == 1 then
        local _, err = utils.json_decode('not JSON')
        return { status = 200, body = 'not JSON' }, err
      end
      return {
        status = 200,
        body = {
          data = {
            {
              id = 'selected-model',
              name = 'Selected model',
              version = '1',
              model_picker_enabled = false,
              capabilities = { type = 'chat', limits = {}, supports = {} },
            },
          },
        },
      }
    end
    local sessions = 0
    local chats = 0
    curl.post = function(url, opts)
      if url == 'https://api.githubcopilot.com/models/session' then
        sessions = sessions + 1
        assert.are.same({ auto_mode = { model_hints = { 'auto' } } }, opts.body)
        return { status = 200, body = { selected_model = 'selected-model' } }
      end
      assert.equals('https://api.githubcopilot.com/chat/completions', url)
      assert.equals('selected-model', opts.body.model)
      chats = chats + 1
      return { status = 200, body = '{"choices":[{"message":{"content":"Recovered"}}]}' }
    end

    assert.are.same({}, client:models())
    now = 1060
    local response = client:ask({
      headless = true,
      model = 'auto',
      system_prompt = '',
      history = {},
      resources = {},
      tools = {},
    })
    assert.equals('Recovered', response.message.content)
    assert.equals(2, fetches)
    assert.equals(1, sessions)
    assert.equals(1, chats)
    assert.is_false(client:models()['selected-model'].picker)
  end)

  it('shares a pending first fetch even when it outlasts the cooldown', function()
    local pending = {}
    provider.get_models = async.wrap(function(_, callback)
      calls = calls + 1
      table.insert(pending, callback)
    end, 2)
    local results = {}
    async.run(function()
      results[1] = client:models()
    end)
    now = 1100
    for i = 2, 3 do
      async.run(function()
        results[i] = client:models()
      end)
    end
    local attempts = calls
    for _, callback in ipairs(pending) do
      callback({ { id = 'auto' } })
    end
    assert.equals(1, attempts)
    for i = 1, 3 do
      assert.is_not_nil(results[i].auto)
    end
    assert.equals(1400, client.provider_cache.copilot.models_expires_at)
    assert.is_nil(client.provider_cache.copilot.models_pending)
  end)

  it('shares pending authentication instead of requesting several tokens', function()
    local pending = {}
    provider.get_headers = async.wrap(function(callback)
      table.insert(pending, callback)
    end, 1)
    local results = {}
    for i = 1, 3 do
      async.run(function()
        results[i] = client:models()
      end)
    end
    local attempts = #pending
    for _, callback in ipairs(pending) do
      callback({}, 2000)
    end
    assert.equals(1, attempts)
    assert.equals(1, calls)
    for i = 1, 3 do
      assert.is_not_nil(results[i].auto)
    end
  end)

  it('releases waiting callers on failure and starts the cooldown when the request ends', function()
    local pending = {}
    local wait = async.wrap(function(callback)
      table.insert(pending, callback)
    end, 1)
    provider.get_models = function()
      calls = calls + 1
      wait()
      error('temporary model API failure')
    end
    local results = {}
    for i = 1, 3 do
      async.run(function()
        results[i] = client:models()
      end)
    end
    now = 1100
    for _, callback in ipairs(pending) do
      callback()
    end
    assert.equals(1, calls)
    for i = 1, 3 do
      assert.are.same({}, results[i])
    end
    assert.is_nil(client.provider_cache.copilot.models_pending)
    assert.equals(1160, client.provider_cache.copilot.models_retry_at)
    now = 1159
    assert.are.same({}, client:models())
    assert.equals(1, calls)
    provider.get_models = function()
      calls = calls + 1
      return { { id = 'auto' } }
    end
    now = 1160
    assert.is_not_nil(client:models().auto)
    assert.equals(2, calls)
  end)

  it('preserves stale models for callers sharing a failed refresh', function()
    client:models()
    local models = client.provider_cache.copilot.models
    now = 1300
    local pending = {}
    local wait = async.wrap(function(callback)
      table.insert(pending, callback)
    end, 1)
    provider.get_models = function()
      calls = calls + 1
      wait()
      error('temporary model API failure')
    end
    local results = {}
    for i = 1, 3 do
      async.run(function()
        results[i] = client:models()
      end)
    end
    for _, callback in ipairs(pending) do
      callback()
    end
    assert.equals(2, calls)
    for i = 1, 3 do
      assert.is_not_nil(results[i].auto)
    end
    assert.equals(models, client.provider_cache.copilot.models)
    assert.equals(1300, client.provider_cache.copilot.models_expires_at)
    assert.is_not_nil(client:models().auto)
    assert.equals(2, calls)
  end)

  it('releases the pending entry and propagates unexpected filler errors to waiting callers', function()
    local pending = {}
    local wait = async.wrap(function(callback)
      table.insert(pending, callback)
    end, 1)
    notify.publish = function()
      wait()
      error('unexpected notification failure')
    end
    local results = {}
    for i = 1, 2 do
      async.run(function()
        results[i] = { pcall(client.models, client) }
      end)
    end
    for _, callback in ipairs(pending) do
      callback()
    end
    assert.is_nil(client.provider_cache.copilot.models_pending)
    for i = 1, 2 do
      assert.is_false(results[i][1])
      assert.matches('unexpected notification failure', results[i][2])
    end
    notify.publish = saved.publish
    now = 1060
    assert.is_not_nil(client:models().auto)
  end)
end)
