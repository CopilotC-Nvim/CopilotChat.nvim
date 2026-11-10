local completion = require('CopilotChat.completion')
local utils = require('CopilotChat.utils')

describe('CopilotChat completion triggers', function()
  local saved
  local buffer
  local scheduled

  before_each(function()
    saved = {
      copilot = package.loaded.CopilotChat,
      debounce = utils.debounce,
      buffer = vim.api.nvim_get_current_buf(),
    }
    package.loaded.CopilotChat = {
      chat = {
        get_source = function()
          return {}
        end,
      },
    }
    buffer = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(buffer)
    scheduled = 0
    utils.debounce = function()
      scheduled = scheduled + 1
    end
  end)

  after_each(function()
    package.loaded.CopilotChat = saved.copilot
    utils.debounce = saved.debounce
    vim.api.nvim_set_current_buf(saved.buffer)
    vim.api.nvim_buf_delete(buffer, { force = true })
  end)

  local function complete(text)
    vim.api.nvim_set_current_line(text .. ' ')
    vim.api.nvim_win_set_cursor(0, { 1, #text })
    completion.complete(true)
  end

  it('does not schedule model discovery for ordinary chat text or an empty line', function()
    for _, text in ipairs({ '', 'h', 'he', 'help me', 'help me with this code' }) do
      complete(text)
    end
    assert.equals(0, scheduled)
  end)

  it('still schedules completion for each supported trigger', function()
    for _, text in ipairs({ '@', '/', '#', '$', '$auto' }) do
      complete(text)
    end
    assert.equals(5, scheduled)
  end)

  it('does not schedule completion after leaving a trigger word', function()
    complete('$auto ')
    complete('use @tool then write text')
    assert.equals(0, scheduled)
  end)
end)
