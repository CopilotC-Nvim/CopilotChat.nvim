local diff = require('CopilotChat.utils.diff')

describe('CopilotChat.utils.diff', function()
  it('applies unified diff', function()
    local diff_text = [[
--- a/foo.txt
+++ b/foo.txt
@@ ... @@
 context
-old
+new
]]
    local original = { 'context', 'old', 'other' }
    local original_content = table.concat(original, '\n')
    local result, applied = diff.apply_unified_diff(diff_text, original_content)
    assert.is_true(applied)
    assert.are.same({ 'context', 'new', 'other' }, result)
  end)

  it('applies unified diff with no context', function()
    local diff_text = [[
--- a/foo.txt
+++ b/foo.txt
@@ ... @@
-old
+new
]]
    local original = { 'old', 'other' }
    local original_content = table.concat(original, '\n')
    local result, applied = diff.apply_unified_diff(diff_text, original_content)
    assert.is_true(applied)
    assert.are.same({ 'new', 'other' }, result)
  end)

  it('applies unified diff with multiline edits', function()
    local diff_text = [[
--- a/foo.txt
+++ b/foo.txt
@@ ... @@
 context1
 context2
-old1
-old2
+new1
+new2
]]
    local original = {
      'context1',
      'context2',
      'old1',
      'old2',
      'context3',
      'other',
    }
    local original_content = table.concat(original, '\n')
    local result, applied = diff.apply_unified_diff(diff_text, original_content)
    assert.is_true(applied)
    assert.are.same({
      'context1',
      'context2',
      'new1',
      'new2',
      'context3',
      'other',
    }, result)
  end)

  it('gets unified diff region', function()
    local diff_text = [[
--- a/foo.txt
+++ b/foo.txt
@@ ... @@
 context
-old
+new
]]
    local original = { 'context', 'old', 'other' }
    local original_content = table.concat(original, '\n')
    local _, _, first, last = diff.apply_unified_diff(diff_text, original_content)
    assert.equals(2, first)
    assert.equals(2, last)
  end)

  it('applies unified diff with only additions', function()
    local diff_text = [[
--- a/foo.txt
+++ b/foo.txt
@@ ... @@
 context
+added1
+added2
]]
    local original = { 'context', 'other' }
    local original_content = table.concat(original, '\n')
    local result, applied = diff.apply_unified_diff(diff_text, original_content)
    assert.is_true(applied)
    assert.are.same({ 'context', 'added1', 'added2', 'other' }, result)
  end)

  it('applies unified diff with only deletions', function()
    local diff_text = [[
--- a/foo.txt
+++ b/foo.txt
@@ ... @@
 context
-old1
-old2
]]
    local original = { 'context', 'old1', 'old2', 'other' }
    local original_content = table.concat(original, '\n')
    local result, applied = diff.apply_unified_diff(diff_text, original_content)
    assert.is_true(applied)
    assert.are.same({ 'context', 'other' }, result)
  end)

  it('applies unified diff with changes at start and end', function()
    local diff_text = [[
--- a/foo.txt
+++ b/foo.txt
@@ ... @@
-oldstart
+newstart
 context
-oldend
+newend
]]
    local original = { 'oldstart', 'context', 'oldend' }
    local original_content = table.concat(original, '\n')
    local result, applied = diff.apply_unified_diff(diff_text, original_content)
    assert.is_true(applied)
    assert.are.same({ 'newstart', 'context', 'newend' }, result)
  end)

  it('applies unified diff with multiple hunks', function()
    local diff_text = [[
--- a/foo.txt
+++ b/foo.txt
@@ ... @@
 context1
-old1
+new1
@@ ... @@
 context2
-old2
+new2
]]
    local original = { 'context1', 'old1', 'context2', 'old2', 'other' }
    local original_content = table.concat(original, '\n')
    local result, applied = diff.apply_unified_diff(diff_text, original_content)
    assert.is_true(applied)
    assert.are.same({ 'context1', 'new1', 'context2', 'new2', 'other' }, result)
  end)

  it('applies unified diff with no changes', function()
    local diff_text = [[
--- a/foo.txt
+++ b/foo.txt
@@ ... @@
 context
 unchanged
]]
    local original = { 'context', 'unchanged' }
    local original_content = table.concat(original, '\n')
    local result, applied = diff.apply_unified_diff(diff_text, original_content)
    assert.is_true(applied)
    assert.are.same(original, result)
  end)

  it('applies unified diff with all lines deleted', function()
    local diff_text = [[
--- a/foo.txt
+++ b/foo.txt
@@ ... @@
-old1
-old2
-old3
]]
    local original = { 'old1', 'old2', 'old3' }
    local original_content = table.concat(original, '\n')
    local result, applied = diff.apply_unified_diff(diff_text, original_content)
    assert.is_true(applied)
    assert.are.same({}, result)
  end)

  it('applies unified diff with all lines added to empty file', function()
    local diff_text = [[
--- a/foo.txt
+++ b/foo.txt
@@ ... @@
+new1
+new2
+new3
]]
    local original = {}
    local original_content = table.concat(original, '\n')
    local result, applied = diff.apply_unified_diff(diff_text, original_content)
    assert.is_true(applied)
    assert.are.same({ 'new1', 'new2', 'new3' }, result)
  end)

  it('applies unified diff with changes at end of file', function()
    local diff_text = [[
--- a/foo.txt
+++ b/foo.txt
@@ ... @@
 context
-oldend
+newend
]]
    local original = { 'context', 'oldend' }
    local original_content = table.concat(original, '\n')
    local result, applied = diff.apply_unified_diff(diff_text, original_content)
    assert.is_true(applied)
    assert.are.same({ 'context', 'newend' }, result)
  end)

  it('applies unified diff with changes at start of file', function()
    local diff_text = [[
--- a/foo.txt
+++ b/foo.txt
@@ ... @@
-oldstart
+newstart
 context
]]
    local original = { 'oldstart', 'context' }
    local original_content = table.concat(original, '\n')
    local result, applied = diff.apply_unified_diff(diff_text, original_content)
    assert.is_true(applied)
    assert.are.same({ 'newstart', 'context' }, result)
  end)

  it('may confuse similar variable names', function()
    local diff_text = [[
--- a/foo.txt
+++ b/foo.txt
@@ -1,2 +1,2 @@
-local x = 1
+local x = 10
]]
    local original = {
      'local x = 1',
      'local y = 2',
      'local x = 3',
      'local z = 4',
    }
    local result, applied = diff.apply_unified_diff(diff_text, table.concat(original, '\n'))
    assert.is_true(applied)
    assert.are.same({
      'local x = 10',
      'local y = 2',
      'local x = 3',
      'local z = 4',
    }, result)
  end)

  it('may match wrong substring with partial matches', function()
    local diff_text = [[
--- a/foo.txt
+++ b/foo.txt
@@ -1,2 +1,2 @@
-old_value
+new_value
]]
    local original = {
      'value',
      'old_value',
      'very_old_value',
    }
    local result, applied = diff.apply_unified_diff(diff_text, table.concat(original, '\n'))
    assert.is_false(applied) -- not applied cleanly, but adjusted
    assert.are.same({
      'value',
      'new_value',
      'very_old_value',
    }, result)
  end)

  it('may apply to wrong instance of identical boilerplate code', function()
    local diff_text = [[
--- a/foo.txt
+++ b/foo.txt
@@ -1,3 +1,3 @@
 return {
-  status = "old"
+  status = "new"
]]
    local original = {
      'return {',
      '  status = "old"',
      '}',
      'return {',
      '  status = "old"',
      '}',
    }
    local result, applied = diff.apply_unified_diff(diff_text, table.concat(original, '\n'))
    assert.is_true(applied)
    assert.are.same({
      'return {',
      '  status = "new"',
      '}',
      'return {',
      '  status = "old"',
      '}',
    }, result)
  end)
end)
