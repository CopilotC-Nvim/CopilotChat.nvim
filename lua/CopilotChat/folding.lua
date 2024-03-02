function CopilotChatFoldExpr(lnum, separator)
  local line = vim.fn.getline(lnum)
  if string.match(line, separator .. '$') then
    return '>1'
  end

  return '='
end

return {
  CopilotChatFoldExpr = CopilotChatFoldExpr,
}
