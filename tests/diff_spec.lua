local diff = require('CopilotChat.utils.diff')

describe('CopilotChat.utils.diff', function()
  it('parses unified diff', function()
    local diff_text = [[
--- a/foo.txt
+++ b/foo.txt
@@ ... @@
-context line
-old line
+new line
]]
    local file_path, hunks = diff.parse_unified_diff(diff_text)
    assert.equals('b/foo.txt', file_path)
    assert.equals('context line', hunks[1].context[1])
    assert.equals('old line', hunks[1].minus[1])
    assert.equals('new line', hunks[1].plus[1])
  end)

  it('applies unified diff', function()
    local diff_text = [[
--- a/foo.txt
+++ b/foo.txt
@@ ... @@
-context
-old
+new
]]
    local original = { 'context', 'old', 'other' }
    local result, applied = diff.apply_unified_diff(diff_text, original)
    assert.is_true(applied)
    assert.are.same({ 'context', 'new', 'other' }, result)
  end)

  it('gets unified diff region', function()
    local diff_text = [[
--- a/foo.txt
+++ b/foo.txt
@@ ... @@
-context
-old
+new
]]
    local original = { 'context', 'old', 'other' }
    local first, last = diff.get_unified_diff_region(diff_text, original)
    assert.equals(2, first)
    assert.equals(2, last)
  end)
end)
