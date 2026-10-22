local client = require('CopilotChat.client')
local curl = require('CopilotChat.utils.curl')
local copilot = require('CopilotChat.config.providers').copilot
local utils = require('CopilotChat.utils')

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
  end)

  it('caches a successful first fetch for five minutes', function()
    assert.equals('copilot', client:models().auto.provider)
    assert.equals(1300, client.provider_cache.copilot.models_expires_at)
    now = 1299
    assert.is_not_nil(client:models().auto)
    assert.equals(1, calls)
  end)

  it('retries on the next call after an initial fetch failure', function()
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
    assert.is_not_nil(client:models().auto)
    assert.equals(2, calls)
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
    assert.equals(3, calls)
    assert.equals(1600, client.provider_cache.copilot.models_expires_at)
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

  it('does not add an internal retry loop during a persistent failure', function()
    provider.get_models = function()
      calls = calls + 1
      error('model API unavailable')
    end
    for _ = 1, 3 do
      assert.are.same({}, client:models())
    end
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

  it('does not cache a missing provider result as a successful empty list', function()
    provider.get_models = function()
      calls = calls + 1
    end
    assert.are.same({}, client:models())
    assert.is_nil(client.provider_cache.copilot.models_expires_at)
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
end)
