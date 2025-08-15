-- Mock packages
package.loaded['plenary.async'] = {
  wrap = function(fn)
    return function(...)
      return fn(...)
    end
  end,
}
package.loaded['plenary.curl'] = {}
package.loaded['plenary.log'] = {}
package.loaded['plenary.scandir'] = {}
package.loaded['plenary.filetype'] = {}

local utils = require('CopilotChat.utils')

describe('utils.glob_to_pattern', function()
  local function test_pattern(glob, path, should_match)
    local pattern = utils.glob_to_pattern(glob)
    local matches = path:match(pattern) ~= nil
    if should_match then
      assert.is_true(
        matches,
        string.format("Expected glob '%s' (pattern '%s') to match path '%s', but it didn't.", glob, pattern, path)
      )
    else
      assert.is_false(
        matches,
        string.format("Expected glob '%s' (pattern '%s') to NOT match path '%s', but it did.", glob, pattern, path)
      )
    end
  end

  it('should handle simple filenames', function()
    test_pattern('file.lua', 'file.lua', true)
    test_pattern('file.lua', 'another.lua', false)
    test_pattern('file.lua', 'file/lua', false)
  end)

  it('should handle single asterisk for any characters except slash', function()
    test_pattern('*.lua', 'file.lua', true)
    test_pattern('*.lua', 'another.lua', true)
    test_pattern('*.lua', 'file.txt', false)
    test_pattern('*.lua', 'subdir/file.lua', false)
    test_pattern('src/*.lua', 'src/main.lua', true)
    test_pattern('src/*.lua', 'src/test.lua', true)
    test_pattern('src/*.lua', 'src/subdir/main.lua', false)
  end)

  it('should handle question mark for a single character except slash', function()
    test_pattern('file?.lua', 'file1.lua', true)
    test_pattern('file?.lua', 'fileA.lua', true)
    test_pattern('file?.lua', 'file.lua', false)
    test_pattern('file?.lua', 'file12.lua', false)
    test_pattern('file?.lua', 'subdir/file1.lua', false)
  end)

  it('should handle character sets', function()
    test_pattern('[abc].lua', 'a.lua', true)
    test_pattern('[abc].lua', 'b.lua', true)
    test_pattern('[abc].lua', 'c.lua', true)
    test_pattern('[abc].lua', 'd.lua', false)
    test_pattern('[a-c].lua', 'a.lua', true)
    test_pattern('[a-c].lua', 'b.lua', true)
    test_pattern('[a-c].lua', 'd.lua', false)
  end)

  it('should handle negated character sets', function()
    test_pattern('[!abc].lua', 'd.lua', true)
    test_pattern('[!abc].lua', 'a.lua', false)
    test_pattern('[^abc].lua', 'd.lua', true)
    test_pattern('[^abc].lua', 'a.lua', false)
  end)

  it('should handle double asterisk for zero or more directories', function()
    -- **/*.lua
    test_pattern('**/*.lua', 'file.lua', false)
    test_pattern('**/*.lua', 'src/file.lua', true)
    test_pattern('**/*.lua', 'src/subdir/file.lua', true)
    test_pattern('**/*.lua', 'file.txt', false)
    test_pattern('**/*.lua', 'src/file.lua.bak', false)

    -- **/test/*.lua
    test_pattern('**/test/*.lua', 'test/file.lua', false)
    test_pattern('**/test/*.lua', 'src/test/file.lua', true)
    test_pattern('**/test/*.lua', 'src/deep/test/file.lua', true)
    test_pattern('**/test/*.lua', 'test/subdir/file.lua', false)
    test_pattern('**/test/*.lua', 'src/test.lua', false)

    -- src/**/*.lua
    test_pattern('src/**/*.lua', 'src/file.lua', false)
    test_pattern('src/**/*.lua', 'src/subdir/file.lua', true)
    test_pattern('src/**/*.lua', 'src/deep/subdir/file.lua', true)
    test_pattern('src/**/*.lua', 'file.lua', false)
    test_pattern('src/**/*.lua', 'notsrc/file.lua', false)

    -- src/**/test/*.lua
    test_pattern('src/**/test/*.lua', 'src/test/file.lua', false)
    test_pattern('src/**/test/*.lua', 'src/subdir/test/file.lua', true)
    test_pattern('src/**/test/*.lua', 'src/deep/subdir/test/file.lua', true)
    test_pattern('src/**/test/*.lua', 'src/file.lua', false)
    test_pattern('src/**/test/*.lua', 'test/file.lua', false)
    test_pattern('src/**/test/*.lua', 'src/test/subdir/file.lua', false)

    test_pattern('**', '', true)
  end)
end)
