local T = MiniTest.new_set()

local cases = {
  { glob = '', expected = '^$' },
  { glob = 'abc', expected = '^abc$' },
  { glob = 'ab#/.', expected = '^ab%#%/%.$' },
  { glob = '\\\\\\ab\\c\\', expected = '^%\\abc\\$' },

  { glob = 'abc.*', expected = '^abc%..*$', matches = { 'abc.txt', 'abc.' }, not_matches = { 'abc' } },
  { glob = '??.txt', expected = '^..%.txt$' },

  { glob = 'a[]', expected = '[^]' },
  { glob = 'a[^]b', expected = '^ab$' },
  { glob = 'a[!]b', expected = '^ab$' },
  { glob = 'a[a][b]z', expected = '^a[a][b]z$' },
  { glob = 'a[a-f]z', expected = '^a[a-f]z$' },
  { glob = 'a[a-f0-9]z', expected = '^a[a-f0-9]z$' },
  { glob = 'a[a-f0-]z', expected = '^a[a-f0%-]z$' },
  { glob = 'a[!a-f]z', expected = '^a[^a-f]z$' },
  { glob = 'a[^a-f]z', expected = '^a[^a-f]z$' },
  { glob = 'a[\\!\\^\\-z\\]]z', expected = '^a[%!%^%-z%]]z$' },
  { glob = 'a[\\a-\\f]z', expected = '^a[a-f]z$' },

  { glob = 'a[', expected = '[^]' },
  { glob = 'a[a-', expected = '[^]' },
  { glob = 'a[a-b', expected = '[^]' },
  { glob = 'a[!', expected = '[^]' },
  { glob = 'a[!a', expected = '[^]' },
  { glob = 'a[!a-', expected = '[^]' },
  { glob = 'a[!a-b', expected = '[^]' },
  { glob = 'a[!a-b\\]', expected = '[^]' },
}

for _, case in ipairs(cases) do
  T['glob_to_pattern: ' .. case.glob] = function()
    local utils = require('CopilotChat.utils')
    local pattern = utils.glob_to_pattern(case.glob)
    MiniTest.expect.equality(pattern, case.expected)
    if case.matches then
      for _, str in ipairs(case.matches) do
        MiniTest.expect.equality(str:match(pattern) ~= nil, true)
      end
    end
    if case.not_matches then
      for _, str in ipairs(case.not_matches) do
        MiniTest.expect.equality(str:match(pattern) ~= nil, false)
      end
    end
  end
end

return T
