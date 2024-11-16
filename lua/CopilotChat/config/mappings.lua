---@class CopilotChat.config.mapping
---@field normal string?
---@field insert string?
---@field detail string?

---@class CopilotChat.config.mapping.yank_diff : CopilotChat.config.mapping
---@field register string?

---@class CopilotChat.config.mapping.show_diff : CopilotChat.config.mapping
---@field full_diff boolean?

---@class CopilotChat.config.mappings
---@field complete CopilotChat.config.mapping?
---@field close CopilotChat.config.mapping?
---@field reset CopilotChat.config.mapping?
---@field submit_prompt CopilotChat.config.mapping?
---@field toggle_sticky CopilotChat.config.mapping?
---@field accept_diff CopilotChat.config.mapping?
---@field jump_to_diff CopilotChat.config.mapping?
---@field quickfix_diffs CopilotChat.config.mapping?
---@field yank_diff CopilotChat.config.mapping.yank_diff?
---@field show_diff CopilotChat.config.mapping.show_diff?
---@field show_info CopilotChat.config.mapping?
---@field show_context CopilotChat.config.mapping?
---@field show_help CopilotChat.config.mapping?

return {
  complete = {
    insert = '<Tab>',
  },
  close = {
    normal = 'q',
    insert = '<C-c>',
  },
  reset = {
    normal = '<C-l>',
    insert = '<C-l>',
  },
  submit_prompt = {
    normal = '<CR>',
    insert = '<C-s>',
  },
  toggle_sticky = {
    detail = 'Makes line under cursor sticky or deletes sticky line.',
    normal = 'gr',
  },
  accept_diff = {
    normal = '<C-y>',
    insert = '<C-y>',
  },
  jump_to_diff = {
    normal = 'gj',
  },
  quickfix_answers = {
    normal = 'gqa',
  },
  quickfix_diffs = {
    normal = 'gqd',
  },
  yank_diff = {
    normal = 'gy',
    register = '"', -- Default register to use for yanking
  },
  show_diff = {
    normal = 'gd',
    full_diff = false, -- Show full diff instead of unified diff when showing diff window
  },
  show_info = {
    normal = 'gi',
  },
  show_context = {
    normal = 'gc',
  },
  show_help = {
    normal = 'gh',
  },
}
