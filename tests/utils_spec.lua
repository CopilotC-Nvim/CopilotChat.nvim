local utils = require('CopilotChat.utils')

describe('CopilotChat.utils', function()
  local cases = {
    { glob = 'abc.*', matches = { 'abc.txt', 'abc.' }, not_matches = { 'abc' } },
    { glob = 'file.lua', matches = { 'file.lua' }, not_matches = { 'another.lua', 'file/lua' } },
    { glob = '*.lua', matches = { 'file.lua', 'another.lua' }, not_matches = { 'file.txt', 'subdir/file.lua' } },
    { glob = 'src/*.lua', matches = { 'src/main.lua', 'src/test.lua' }, not_matches = { 'src/subdir/main.lua' } },
    {
      glob = 'file?.lua',
      matches = { 'file1.lua', 'fileA.lua' },
      not_matches = { 'file.lua', 'file12.lua', 'subdir/file1.lua' },
    },
    { glob = '[abc].lua', matches = { 'a.lua', 'b.lua', 'c.lua' }, not_matches = { 'd.lua' } },
    { glob = '[a-c].lua', matches = { 'a.lua', 'b.lua' }, not_matches = { 'd.lua' } },
    { glob = '[!abc].lua', matches = { 'd.lua' }, not_matches = { 'a.lua' } },
    { glob = '[^abc].lua', matches = { 'd.lua' }, not_matches = { 'a.lua' } },
    {
      glob = '**/*.lua',
      matches = { 'src/file.lua', 'src/subdir/file.lua' },
      not_matches = { 'file.txt', 'src/file.lua.bak' },
    },
    {
      glob = '**/test/*.lua',
      matches = { 'src/test/file.lua', 'src/deep/test/file.lua' },
      not_matches = { 'test/file.lua', 'test/subdir/file.lua', 'src/test.lua' },
    },
    {
      glob = 'src/**/test/*.lua',
      matches = { 'src/subdir/test/file.lua', 'src/deep/subdir/test/file.lua' },
      not_matches = { 'src/test/file.lua', 'src/file.lua', 'test/file.lua', 'src/test/subdir/file.lua' },
    },
    { glob = '**', matches = { '' }, not_matches = {} },
  }

  for _, case in ipairs(cases) do
    it('glob_to_pattern: ' .. case.glob, function()
      local pattern = utils.glob_to_pattern(case.glob)
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
