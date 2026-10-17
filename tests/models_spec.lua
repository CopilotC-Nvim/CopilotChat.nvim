describe('CopilotChat copilot provider models', function()
  local curl = require('CopilotChat.utils.curl')
  local providers = require('CopilotChat.config.providers')
  local original_get = curl.get
  local original_post = curl.post

  before_each(function()
    curl.get = function()
      return { body = { data = {} } }
    end
    curl.post = function()
      return { body = {} }
    end
  end)

  after_each(function()
    curl.get = original_get
    curl.post = original_post
  end)

  local function model(id, picker, supported_endpoints)
    return {
      id = id,
      name = id,
      version = '1',
      model_picker_enabled = picker,
      capabilities = {
        type = 'chat',
        tokenizer = 'o200k_base',
        limits = { max_prompt_tokens = 1000, max_output_tokens = 100 },
        supports = { streaming = true, tool_calls = true },
      },
      supported_endpoints = supported_endpoints,
    }
  end

  it('includes picker-disabled chat models with full metadata and auto', function()
    curl.get = function()
      return {
        body = {
          data = {
            model('gpt-5.4-mini', false, { '/chat/completions' }),
            model('gpt-5.4-responses', false, { '/responses' }),
            { id = 'embedding', capabilities = { type = 'embeddings' } },
          },
        },
      }
    end

    local models = providers.copilot.get_models({})
    local by_id = {}
    for _, item in ipairs(models) do
      by_id[item.id] = item
    end

    assert.is_false(by_id['gpt-5.4-mini'].picker)
    assert.is_false(by_id['gpt-5.4-mini'].use_responses)
    assert.equals('o200k_base', by_id['gpt-5.4-mini'].tokenizer)
    assert.is_true(by_id['gpt-5.4-responses'].use_responses)
    assert.is_nil(by_id.embedding)
    assert.is_not_nil(by_id.auto)
  end)

  it('includes both picker-enabled and picker-disabled chat models', function()
    curl.get = function()
      return {
        body = {
          data = {
            model('gpt-5.4-mini', true, { '/responses' }),
            model('gpt-5.4-restricted', false, { '/chat/completions' }),
          },
        },
      }
    end

    local models = providers.copilot.get_models({})
    local by_id = {}
    for _, item in ipairs(models) do
      by_id[item.id] = item
    end

    assert.is_true(by_id['gpt-5.4-mini'].picker)
    assert.is_true(by_id['gpt-5.4-mini'].use_responses)
    assert.is_false(by_id['gpt-5.4-restricted'].picker)
    assert.is_false(by_id['gpt-5.4-restricted'].use_responses)
  end)

  it('returns the selected model and session token for auto', function()
    curl.post = function()
      return { body = { selected_model = 'gpt-5.4-mini', session_token = 'session-token' } }
    end

    local selected, headers = providers.copilot.resolve_model({}, 'auto')

    assert.equals('gpt-5.4-mini', selected)
    assert.same({ ['Copilot-Session-Token'] = 'session-token' }, headers)
  end)

  it('returns non-auto models unchanged without headers', function()
    local selected, headers = providers.copilot.resolve_model({}, 'gpt-5.4-mini')

    assert.equals('gpt-5.4-mini', selected)
    assert.is_nil(headers)
  end)

  it('provides auto fallback when all models are picker-disabled', function()
    -- Restricted accounts have model_picker_enabled=false for every model.
    -- The default config model (e.g. gpt-5-mini) is found in the cache but
    -- cannot be called directly; the client must fall back to auto mode,
    -- which resolves via /models/session and returns a session token.
    curl.get = function()
      return {
        body = {
          data = {
            model('gpt-5-mini', false, { '/chat/completions' }),
          },
        },
      }
    end
    curl.post = function()
      return { body = { selected_model = 'gpt-5-mini', session_token = 'restricted-session-token' } }
    end

    local models = providers.copilot.get_models({})
    local by_id = {}
    for _, item in ipairs(models) do
      by_id[item.id] = item
    end

    -- Every chat model is picker-disabled, but auto is still available
    assert.is_false(by_id['gpt-5-mini'].picker)
    assert.is_not_nil(by_id.auto)

    -- Auto resolution returns a session token that authorizes the request
    local selected, headers = providers.copilot.resolve_model({}, 'auto')
    assert.equals('gpt-5-mini', selected)
    assert.same({ ['Copilot-Session-Token'] = 'restricted-session-token' }, headers)
  end)

  it('returns a descriptive error when auto session endpoint fails', function()
    -- The real async curl.post returns (response, err); the mock must match.
    curl.post = function()
      return { status = 403, body = '{"error":"forbidden"}' }, '{"error":"forbidden"}'
    end

    local ok, err = pcall(providers.copilot.resolve_model, {}, 'auto')
    assert.is_false(ok)
    assert.truthy(string.find(err, '403'))
    assert.truthy(string.find(err, 'forbidden'))
  end)

  it('returns a descriptive error when auto returns no selected_model', function()
    curl.post = function()
      return { body = {} }
    end

    local ok, err = pcall(providers.copilot.resolve_model, {}, 'auto')
    assert.is_false(ok)
    assert.truthy(string.find(err, 'no selected_model'))
  end)

  it('generates reasoning effort variants when model supports reasoning_effort', function()
    local m = model('gpt-5.4', true, { '/responses' })
    m.capabilities.supports.reasoning_effort = { 'low', 'medium', 'high' }

    curl.get = function()
      return {
        body = {
          data = { m },
        },
      }
    end

    local models = providers.copilot.get_models({})
    local by_id = {}
    for _, item in ipairs(models) do
      by_id[item.id] = item
    end

    assert.is_not_nil(by_id['gpt-5.4'])
    assert.is_nil(by_id['gpt-5.4'].reasoning_effort)
    assert.same({ 'low', 'medium', 'high' }, by_id['gpt-5.4'].reasoning_efforts)

    assert.is_not_nil(by_id['gpt-5.4:low'])
    assert.equals('low', by_id['gpt-5.4:low'].reasoning_effort)
    assert.equals('gpt-5.4', by_id['gpt-5.4:low'].request_model)

    assert.is_not_nil(by_id['gpt-5.4:medium'])
    assert.equals('medium', by_id['gpt-5.4:medium'].reasoning_effort)

    assert.is_not_nil(by_id['gpt-5.4:high'])
    assert.equals('high', by_id['gpt-5.4:high'].reasoning_effort)
  end)

  it('serializes reasoning effort in prepare_input for responses and chat APIs', function()
    local base_model = {
      id = 'gpt-5.4',
      request_model = 'gpt-5.4',
      streaming = false,
      use_responses = true,
    }

    -- With reasoning effort for Responses API
    local with_effort = vim.tbl_extend('force', base_model, { reasoning_effort = 'high' })
    local req = providers.copilot.prepare_input({}, { model = with_effort })
    assert.is_not_nil(req.reasoning)
    assert.equals('high', req.reasoning.effort)

    -- With invalid/arbitrary reasoning effort for Responses API
    local with_invalid = vim.tbl_extend('force', base_model, { reasoning_effort = 'invalid' })
    req = providers.copilot.prepare_input({}, { model = with_invalid })
    assert.is_not_nil(req.reasoning)
    assert.equals('invalid', req.reasoning.effort)

    -- Without reasoning effort for Responses API (default effort)
    local no_effort = vim.tbl_extend('force', base_model, { reasoning_effort = nil })
    req = providers.copilot.prepare_input({}, { model = no_effort })
    assert.is_nil(req.reasoning)

    -- With reasoning effort for Chat Completions API
    local chat_model = vim.tbl_extend('force', base_model, { use_responses = false, reasoning_effort = 'high' })
    req = providers.copilot.prepare_input({}, { model = chat_model })
    assert.equals('high', req.reasoning_effort)

    -- With invalid reasoning effort for Chat Completions API
    local chat_invalid = vim.tbl_extend('force', base_model, { use_responses = false, reasoning_effort = 'invalid' })
    req = providers.copilot.prepare_input({}, { model = chat_invalid })
    assert.equals('invalid', req.reasoning_effort)

    -- Without reasoning effort for Chat Completions API (default effort)
    local chat_no_effort = vim.tbl_extend('force', base_model, { use_responses = false, reasoning_effort = nil })
    req = providers.copilot.prepare_input({}, { model = chat_no_effort })
    assert.is_nil(req.reasoning_effort)
  end)

  it('allows setting custom or invalid reasoning effort and propagates API error', function()
    local client = require('CopilotChat.client')
    local m = model('gpt-5.4', true, { '/responses' })
    m.capabilities.supports.reasoning_effort = { 'low', 'medium', 'high' }
    m.capabilities.limits = {}

    curl.get = function()
      return {
        body = {
          data = { m },
        },
      }
    end

    client.provider_cache['copilot'] = {
      headers = { ['Authorization'] = 'Bearer test-token' },
      expires_at = os.time() + 3600,
    }

    local captured_args = nil
    curl.post = function(url, args)
      captured_args = args
      return {
        status = 400,
        body = '{"error":{"message":"Invalid reasoning effort: invalid. Supported values: low, medium, high"}}',
      }, '{"error":{"message":"Invalid reasoning effort: invalid. Supported values: low, medium, high"}}'
    end

    local ok, err = pcall(function()
      client:ask({
        headless = true,
        model = 'gpt-5.4:invalid',
        history = {},
      })
    end)

    assert.is_false(ok)
    assert.truthy(string.find(err, '400'))
    assert.truthy(string.find(err, 'Invalid reasoning effort: invalid'))

    assert.is_not_nil(captured_args)
    assert.equals('gpt-5.4', captured_args.body.model)
    assert.equals('invalid', captured_args.body.reasoning.effort)
  end)

  it('sends no reasoning parameter when no effort is specified (model default)', function()
    local client = require('CopilotChat.client')
    local m = model('gpt-5.4', true, { '/responses' })
    m.capabilities.supports.reasoning_effort = { 'low', 'medium', 'high' }
    m.capabilities.limits = {}

    curl.get = function()
      return {
        body = {
          data = { m },
        },
      }
    end

    client.provider_cache['copilot'] = {
      headers = { ['Authorization'] = 'Bearer test-token' },
      expires_at = os.time() + 3600,
    }

    local captured_args = nil
    curl.post = function(url, args)
      captured_args = args
      return {
        status = 200,
        body = vim.json.encode({
          response = {
            output = { { content = 'Hello' } },
            status = 'completed',
          },
        }),
      }
    end

    local resp = client:ask({
      headless = true,
      model = 'gpt-5.4',
      history = {},
    })

    assert.is_not_nil(resp)
    assert.is_not_nil(captured_args)
    assert.equals('gpt-5.4', captured_args.body.model)
    assert.is_nil(captured_args.body.reasoning)
  end)

  it('resolves model with reasoning effort from config and prompt colon syntax', function()
    local prompts = require('CopilotChat.prompts')
    local client = require('CopilotChat.client')
    local m = model('gpt-5.4', true, { '/responses' })
    m.capabilities.supports.reasoning_effort = { 'low', 'medium', 'high' }

    curl.get = function()
      return {
        body = {
          data = { m },
        },
      }
    end

    client.provider_cache['copilot'] = {
      headers = { ['Authorization'] = 'Bearer test-token' },
      expires_at = os.time() + 3600,
    }

    -- Configured with model = 'gpt-5.4:high'
    local resolved, prompt = prompts.resolve_model('Hello', { model = 'gpt-5.4:high' })
    assert.equals('gpt-5.4:high', resolved)
    assert.equals('Hello', prompt)

    -- Overridden in prompt with $gpt-5.4:low
    resolved, prompt = prompts.resolve_model('Hello $gpt-5.4:low', { model = 'gpt-5.4:high' })
    assert.equals('gpt-5.4:low', resolved)
    assert.equals('Hello', vim.trim(prompt))

    -- Overridden in prompt with arbitrary/invalid effort $gpt-5.4:custom
    resolved, prompt = prompts.resolve_model('Hello $gpt-5.4:custom', { model = 'gpt-5.4' })
    assert.equals('gpt-5.4:custom', resolved)
    assert.equals('Hello', vim.trim(prompt))
  end)
end)
