local utils = require('CopilotChat.utils')

describe('CopilotChat.utils', function()
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
    it('glob_to_pattern: ' .. case.glob, function()
      local pattern = utils.glob_to_pattern(case.glob)
      assert.equals(case.expected, pattern)
      if case.matches then
        for _, str in ipairs(case.matches) do
          assert.is_true(str:match(pattern) ~= nil)
        end
      end
      if case.not_matches then
        for _, str in ipairs(case.not_matches) do
          assert.is_false(str:match(pattern) ~= nil)
        end
      end
    end)
  end

  it('empty', function()
    assert.is_true(utils.empty(nil))
    assert.is_true(utils.empty(''))
    assert.is_true(utils.empty('   '))
    assert.is_true(utils.empty({}))
    assert.is_false(utils.empty({ 1 }))
    assert.is_false(utils.empty('abc'))
    assert.is_false(utils.empty(0))
  end)

  it('split_lines', function()
    assert.are.same(utils.split_lines(''), {})
    assert.are.same(utils.split_lines('a\nb'), { 'a', 'b' })
    assert.are.same(utils.split_lines('a\r\nb'), { 'a', 'b' })
    assert.are.same(utils.split_lines('a\nb\n'), { 'a', 'b', '' })
  end)

  it('make_string', function()
    assert.equals('a b 1', utils.make_string('a', 'b', 1))
    assert.equals(vim.inspect({ x = 1 }), utils.make_string({ x = 1 }))
    assert.equals('msg', utils.make_string('error:1: msg'))
  end)

  it('uuid', function()
    local uuid1 = utils.uuid()
    local uuid2 = utils.uuid()
    assert.equals('string', type(uuid1))
    assert.not_equals(uuid1, uuid2)
    assert.equals(36, #uuid1)
  end)

  it('to_table', function()
    assert.are.same({ 1, 2, 3 }, utils.to_table(1, 2, 3))
    assert.are.same({ 1, 2, 3 }, utils.to_table({ 1, 2 }, 3))
    assert.are.same({ 1 }, utils.to_table(nil, 1))
  end)
end)
