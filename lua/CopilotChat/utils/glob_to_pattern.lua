local M = {}

--- Convert glob pattern to regex pattern
--- https://github.com/davidm/lua-glob-pattern/blob/master/lua/globtopattern.lua
---@param g string The glob pattern
---@return string
function M.glob_to_pattern(g)
  -- Handle ** patterns by preprocessing them
  -- Replace ** with a special placeholder to distinguish from single *
  local DOUBLESTAR_PLACEHOLDER = '\001DOUBLESTAR\001'

  -- Replace ** with placeholder, but be careful not to replace *** or other patterns
  g = g:gsub('%*%*', DOUBLESTAR_PLACEHOLDER)

  local p = '^' -- pattern being built
  local i = 0 -- index in g
  local c -- char at index i in g

  -- unescape glob char
  local function unescape()
    if c == '\\' then
      i = i + 1
      c = g:sub(i, i)
      if c == '' then
        p = '[^]'
        return false
      end
    end
    return true
  end

  -- escape pattern char
  local function escape(c)
    return c:match('^%w$') and c or '%' .. c
  end

  -- Convert tokens at end of charset.
  local function charset_end()
    while 1 do
      if c == '' then
        p = '[^]'
        return false
      elseif c == ']' then
        p = p .. ']'
        break
      else
        if not unescape() then
          break
        end
        local c1 = c
        i = i + 1
        c = g:sub(i, i)
        if c == '' then
          p = '[^]'
          return false
        elseif c == '-' then
          i = i + 1
          c = g:sub(i, i)
          if c == '' then
            p = '[^]'
            return false
          elseif c == ']' then
            p = p .. escape(c1) .. '%-]'
            break
          else
            if not unescape() then
              break
            end
            p = p .. escape(c1) .. '-' .. escape(c)
          end
        elseif c == ']' then
          p = p .. escape(c1) .. ']'
          break
        else
          p = p .. escape(c1)
          i = i - 1 -- put back
        end
      end
      i = i + 1
      c = g:sub(i, i)
    end
    return true
  end

  -- Convert tokens in charset.
  local function charset()
    i = i + 1
    c = g:sub(i, i)
    if c == '' or c == ']' then
      p = '[^]'
      return false
    elseif c == '^' or c == '!' then
      i = i + 1
      c = g:sub(i, i)
      if c == ']' then
        -- ignored
      else
        p = p .. '[^'
        if not charset_end() then
          return false
        end
      end
    else
      p = p .. '['
      if not charset_end() then
        return false
      end
    end
    return true
  end

  -- Convert tokens.
  while 1 do
    i = i + 1
    c = g:sub(i, i)
    if c == '' then
      p = p .. '$'
      break
    elseif g:sub(i, i + #DOUBLESTAR_PLACEHOLDER - 1) == DOUBLESTAR_PLACEHOLDER then
      p = p .. DOUBLESTAR_PLACEHOLDER
      i = i + #DOUBLESTAR_PLACEHOLDER - 1
    elseif c == '?' then
      p = p .. '[^/]' -- ? matches any single character except directory separator
    elseif c == '*' then
      p = p .. '[^/]*' -- * matches any characters except directory separator
    elseif c == '[' then
      if not charset() then
        break
      end
    elseif c == '\\' then
      i = i + 1
      c = g:sub(i, i)
      if c == '' then
        p = p .. '\\$'
        break
      end
      p = p .. escape(c)
    else
      p = p .. escape(c)
    end
  end

  -- Now handle the ** placeholder
  local placeholder_pesc = vim.pesc(DOUBLESTAR_PLACEHOLDER)

  -- Case 1: Standalone **
  if p == '^' .. placeholder_pesc .. '$' then
    return '^.-$'
  end

  -- Case 2: Starts with **/something
  -- **/ at the beginning should match:
  -- - nothing (for files in current directory)
  -- - any path ending with / (for files in subdirectories)
  local start_pattern = '^' .. placeholder_pesc .. '/'
  if p:match(start_pattern) then
    local rest_of_p = p:sub(#start_pattern + 1)
    -- **/ at the beginning means match any number of directories (including zero)
    -- So we need to match either:
    -- 1. The rest of the pattern directly (zero directories)
    -- 2. Any path followed by / and then the rest of the pattern (one or more directories)
    p = '^(.-/)?' .. rest_of_p
  end

  -- Case 3: Ends with /**
  local end_pattern = '/' .. placeholder_pesc .. '$'
  p = p:gsub(end_pattern, '/.-$')

  -- Case 4: /**/ in the middle (a/**/b)
  -- This should match a/b, a/x/b, a/x/y/b, etc.
  p = p:gsub('/' .. placeholder_pesc .. '/', '/(.-/)?')

  -- Case 5: Starts with ** without / (edge case, but handle it)
  -- This is already handled by Case 1 if it's standalone
  -- If it's followed by something else without /, treat it as .*
  p = p:gsub('^' .. placeholder_pesc, '^.-')

  -- Case 6: Ends with ** without / (a/**)
  p = p:gsub(placeholder_pesc .. '$', '.-$')

  -- Case 7: Handle any remaining ** (shouldn't happen with valid globs, but be safe)
  p = p:gsub(placeholder_pesc, '.-')

  return p
end

return M
