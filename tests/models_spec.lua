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
end)
