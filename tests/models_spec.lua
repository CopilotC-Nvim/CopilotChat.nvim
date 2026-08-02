describe('CopilotChat copilot provider models', function()
  local curl_mock
  local providers

  local function reload_providers()
    package.loaded['CopilotChat.utils.curl'] = curl_mock
    package.loaded['CopilotChat.config.providers'] = nil
    providers = require('CopilotChat.config.providers')
  end

  before_each(function()
    curl_mock = {
      get = function()
        return { body = { data = {} } }
      end,
      post = function()
        return { body = {} }
      end,
    }
    reload_providers()
  end)

  after_each(function()
    package.loaded['CopilotChat.utils.curl'] = nil
    package.loaded['CopilotChat.config.providers'] = nil
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
    curl_mock.get = function()
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

  it('sets picker=true for picker-enabled models', function()
    curl_mock.get = function()
      return { body = { data = { model('gpt-5.4-mini', true, { '/responses' }) } } }
    end

    local models = providers.copilot.get_models({})
    local mapped
    for _, item in ipairs(models) do
      if item.id == 'gpt-5.4-mini' then
        mapped = item
      end
    end

    assert.is_true(mapped.picker)
    assert.is_true(mapped.use_responses)
  end)

  it('returns the selected model and session token for auto', function()
    curl_mock.post = function()
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
end)
