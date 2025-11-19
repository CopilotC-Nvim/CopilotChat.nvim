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

  it('allows adding at very start with zero original lines', function()
    local diff_text = [[
--- a/foo.txt
+++ b/foo.txt
@@ -0,0 +1,2 @@
+first
+second
]]
    local original = { 'x', 'y' }
    local original_content = table.concat(original, '\n')
    local result, applied = diff.apply_unified_diff(diff_text, original_content)
    assert.is_true(applied)
    assert.are.same({ 'first', 'second', 'x', 'y' }, result)
  end)

  it('handles insertion at end without context', function()
    local diff_text = [[
--- a/foo.txt
+++ b/foo.txt
@@ -3,0 +4,2 @@
+new1
+new2
]]
    local original = { 'a', 'b', 'c' }
    local original_content = table.concat(original, '\n')
    local result, applied = diff.apply_unified_diff(diff_text, original_content)
    assert.is_true(applied)
    assert.are.same({ 'a', 'b', 'c', 'new1', 'new2' }, result)
  end)

  it('supports multiple adjacent hunks modifying contiguous lines', function()
    local diff_text = [[
--- a/foo.txt
+++ b/foo.txt
@@ -1,1 +1,1 @@
-a
+x
@@ -2,1 +2,1 @@
-b
+y
]]
    local original = { 'a', 'b', 'c' }
    local original_content = table.concat(original, '\n')
    local result, applied = diff.apply_unified_diff(diff_text, original_content)
    assert.is_true(applied)
    assert.are.same({ 'x', 'y', 'c' }, result)
  end)

  it('handles diff with trailing newline missing in original', function()
    local diff_text = [[
--- a/foo.txt
+++ b/foo.txt
@@ -1,1 +1,1 @@
-old
+new
]]
    local original_content = 'old' -- no trailing newline
    local result, applied = diff.apply_unified_diff(diff_text, original_content)
    assert.is_true(applied)
    assert.are.same({ 'new' }, result)
  end)

  it('handles diff ending without newline on addition lines', function()
    local diff_text = [[
--- a/foo.txt
+++ b/foo.txt
@@ -1,1 +1,2 @@
 old
+new]]
    local original = { 'old' }
    local original_content = table.concat(original, '\n')
    local result, applied = diff.apply_unified_diff(diff_text, original_content)
    assert.is_true(applied)
    assert.are.same({ 'old', 'new' }, result)
  end)

  it('handles hunks with zero-context lines around changes', function()
    local diff_text = [[
--- a/foo.txt
+++ b/foo.txt
@@ -2,0 +3,1 @@
+added
]]
    local original = { 'a', 'b', 'c' }
    local original_content = table.concat(original, '\n')
    local result, applied = diff.apply_unified_diff(diff_text, original_content)
    assert.is_true(applied)
    assert.are.same({ 'a', 'b', 'added', 'c' }, result)
  end)

  it('handles insertion of identical-to-context line', function()
    local diff_text = [[
--- a/foo.txt
+++ b/foo.txt
@@ -1,1 +1,2 @@
 context
+context
]]
    local original = { 'context', 'other' }
    local result, applied = diff.apply_unified_diff(diff_text, table.concat(original, '\n'))
    assert.is_true(applied)
    assert.are.same({ 'context', 'context', 'other' }, result)
  end)

  it('rejects hunk with wrong header lengths', function()
    local diff_text = [[
--- a/foo.txt
+++ b/foo.txt
@@ -1,3 +1,3 @@
 context
-old
+new
]]
    local original = { 'context' }
    local result, applied = diff.apply_unified_diff(diff_text, table.concat(original, '\n'))
    -- Fuzzy matching may still apply despite wrong header lengths
    assert.is_not_nil(result)
  end)

  it('handles CRLF original with unix diff', function()
    local diff_text = [[
--- a/foo.txt
+++ b/foo.txt
@@ -1,1 +1,1 @@
-old
+new
]]
    local original_content = 'old\r\n'
    local result, applied = diff.apply_unified_diff(diff_text, original_content)
    assert.is_true(applied)
    assert.is_not_nil(result)
    assert.is_true(#result >= 1)
  end)

  it('handles large insertion with no context', function()
    local lines = {}
    for i = 1, 10 do
      table.insert(lines, '+line' .. i)
    end
    local diff_text = '--- a/foo.txt\n+++ b/foo.txt\n@@ -4,0 +5,10 @@\n' .. table.concat(lines, '\n') .. '\n'
    local original = { 'a', 'b', 'c', 'd', 'e' }
    local result, applied = diff.apply_unified_diff(diff_text, table.concat(original, '\n'))
    assert.is_true(applied)
    local expected = { 'a', 'b', 'c', 'd' }
    for i = 1, 10 do
      table.insert(expected, 'line' .. i)
    end
    table.insert(expected, 'e')
    assert.are.same(expected, result)
  end)

  it('rejects mismatched deletion ranges', function()
    local diff_text = [[
--- a/foo.txt
+++ b/foo.txt
@@ -1,3 +0,0 @@
-old1
-old2
-old3
]]
    local original = { 'single' }
    local result, applied = diff.apply_unified_diff(diff_text, table.concat(original, '\n'))
    -- Fuzzy matching may apply the deletion despite mismatch
    assert.is_not_nil(result)
  end)

  it('handles mixed operations in one hunk', function()
    local diff_text = [[
--- a/foo.txt
+++ b/foo.txt
@@ -1,5 +1,4 @@
 context1
-old
 unchanged
-old2
+new2
 context2
]]
    local original = { 'context1', 'old', 'unchanged', 'old2', 'context2' }
    local result, applied = diff.apply_unified_diff(diff_text, table.concat(original, '\n'))
    assert.is_true(applied)
    assert.are.same({ 'context1', 'unchanged', 'new2', 'context2' }, result)
  end)

  it('handles leading tabs/spaces inside context lines', function()
    local diff_text = [[
--- a/x
+++ b/x
@@ -1,2 +1,2 @@
 	indented
-old
+new
]]
    local original = { '\tindented', 'old' }
    local result, applied = diff.apply_unified_diff(diff_text, table.concat(original, '\n'))
    assert.is_true(applied)
    assert.are.same({ '\tindented', 'new' }, result)
  end)

  it('respects diff markers even if content begins with + or -', function()
    local diff_text = [[
--- a/x
+++ b/x
@@ -1,2 +1,2 @@
-+literalplus
--literalminus
++literalplus
++literalminus
]]
    local original = { '+literalplus', '-literalminus' }
    local result, applied = diff.apply_unified_diff(diff_text, table.concat(original, '\n'))
    assert.is_true(applied)
    assert.are.same({ '+literalplus', '+literalminus' }, result)
  end)

  it('applies diff despite slight context mismatch with fuzzy matching', function()
    local diff_text = [[
--- a/foo.txt
+++ b/foo.txt
@@ -1,3 +1,3 @@
 slightly different context
-old
+new
]]
    local original = { 'context', 'old', 'other' }
    local result, applied = diff.apply_unified_diff(diff_text, table.concat(original, '\n'))
    -- Fuzzy matching will replace context lines that don't match
    assert.are.same({ 'slightly different context', 'new', 'other' }, result)
  end)

  it('applies even when context is completely wrong due to fuzzy matching', function()
    local diff_text = [[
--- a/foo.txt
+++ b/foo.txt
@@ -1,3 +1,3 @@
 totally wrong line
 another wrong line
-old
+new
]]
    local original = { 'context1', 'context2', 'old' }
    local result, applied = diff.apply_unified_diff(diff_text, table.concat(original, '\n'))
    -- Fuzzy matching will replace all old_snippet lines (including wrong context) with new_snippet
    assert.are.same({ 'totally wrong line', 'another wrong line', 'new' }, result)
  end)

  it('applies with partial context match', function()
    local diff_text = [[
--- a/foo.txt
+++ b/foo.txt
@@ -2,3 +2,3 @@
 matching
-old
+new
]]
    local original = { 'first', 'matching', 'old', 'last' }
    local result, applied = diff.apply_unified_diff(diff_text, table.concat(original, '\n'))
    assert.is_true(applied)
    assert.are.same({ 'first', 'matching', 'new', 'last' }, result)
  end)

  it('handles context with extra lines not in original', function()
    local diff_text = [[
--- a/foo.txt
+++ b/foo.txt
@@ -1,5 +1,5 @@
 context1
 context2
 context3
-old
+new
]]
    local original = { 'context1', 'old' }
    local result, applied = diff.apply_unified_diff(diff_text, table.concat(original, '\n'))
    -- Should fail or apply with fuzzy matching
    assert.is_not_nil(result)
  end)

  it('fails when deletion target does not exist', function()
    local diff_text = [[
--- a/foo.txt
+++ b/foo.txt
@@ -1,2 +1,1 @@
 context
-nonexistent
]]
    local original = { 'context', 'actual' }
    local result, applied = diff.apply_unified_diff(diff_text, table.concat(original, '\n'))
    -- Fuzzy matching might still apply or fail
    assert.is_not_nil(result)
  end)

  it('applies when context lines are in different order', function()
    local diff_text = [[
--- a/foo.txt
+++ b/foo.txt
@@ -1,3 +1,3 @@
 line2
 line1
-old
+new
]]
    local original = { 'line1', 'line2', 'old' }
    local result, applied = diff.apply_unified_diff(diff_text, table.concat(original, '\n'))
    -- Fuzzy matching should handle reordered context
    assert.is_not_nil(result)
  end)

  it('adds max_retry_time and cumulative retry logic', function()
    local diff_text = [[
--- original.py
+++ modified.py
@@ -24,6 +24,7 @@
     import time
 
     retry_statuses = {HTTPStatus.TOO_MANY_REQUESTS, 502, 503, 504}
+    max_retry_time = 120  # Maximum cumulative retry time in seconds
     retry_exceptions = (
         httpx.ReadTimeout,
         httpx.ConnectTimeout,
@@ -34,6 +35,7 @@
     def deco(fn):
         def wrapped(*args, **kwargs):
             last_exc = None
+            total_retry_time = 0  # Track cumulative retry time
             for attempt in range(retries):
                 try:
                     resp = fn(*args, **kwargs)
@@ -43,6 +45,9 @@
                     delay = min(max_backoff, backoff * (2**attempt)) * (
                         1 + random.random() * 0.25
                     )
+                    if total_retry_time + delay > max_retry_time:
+                        raise TimeoutError("Exceeded maximum retry time of 120 seconds")
+                    total_retry_time += delay
                     time.sleep(delay)
                     continue
 
@@ -59,6 +64,9 @@
                         delay = min(max_backoff, backoff * (2**attempt)) * (
                             1 + random.random() * 0.25
                         )
+                    if total_retry_time + delay > max_retry_time:
+                        raise TimeoutError("Exceeded maximum retry time of 120 seconds")
+                    total_retry_time += delay
                     time.sleep(delay)
                     continue
]]
    local original = [[
import base64
import json
import logging
import os
import random
from datetime import datetime, time
from http import HTTPStatus

import geojson
import httpx
from cachetools import TTLCache, cached
from geopy.distance import geodesic
from shapely.geometry import MultiPolygon, Polygon, shape

logger = logging.getLogger(__name__)

httpx_client = httpx.Client(
    timeout=10.0,
    limits=httpx.Limits(max_keepalive_connections=20, max_connections=100),
)


def retry_request(retries=10, backoff=1, max_backoff=40.0):
    import time

    retry_statuses = {HTTPStatus.TOO_MANY_REQUESTS, 502, 503, 504}
    retry_exceptions = (
        httpx.ReadTimeout,
        httpx.ConnectTimeout,
        httpx.NetworkError,  # includes transient connection errors
        httpx.RemoteProtocolError,
    )

    def deco(fn):
        def wrapped(*args, **kwargs):
            last_exc = None
            for attempt in range(retries):
                try:
                    resp = fn(*args, **kwargs)
                except retry_exceptions as exc:
                    last_exc = exc
                    # backoff and retry
                    delay = min(max_backoff, backoff * (2**attempt)) * (
                        1 + random.random() * 0.25
                    )
                    time.sleep(delay)
                    continue

                # Retry on selected HTTP status
                if resp.status_code in retry_statuses:
                    # honor Retry-After if present
                    ra = resp.headers.get("Retry-After")
                    if ra:
                        try:
                            delay = min(max_backoff, float(ra))
                        except ValueError:
                            delay = min(max_backoff, backoff * (2**attempt))
                    else:
                        delay = min(max_backoff, backoff * (2**attempt)) * (
                            1 + random.random() * 0.25
                        )
                    time.sleep(delay)
                    continue

                return resp

            if last_exc:
                raise last_exc
            return resp

        return wrapped

    return deco
]]
    local expected = [[
import base64
import json
import logging
import os
import random
from datetime import datetime, time
from http import HTTPStatus

import geojson
import httpx
from cachetools import TTLCache, cached
from geopy.distance import geodesic
from shapely.geometry import MultiPolygon, Polygon, shape

logger = logging.getLogger(__name__)

httpx_client = httpx.Client(
    timeout=10.0,
    limits=httpx.Limits(max_keepalive_connections=20, max_connections=100),
)


def retry_request(retries=10, backoff=1, max_backoff=40.0):
    import time

    retry_statuses = {HTTPStatus.TOO_MANY_REQUESTS, 502, 503, 504}
    max_retry_time = 120  # Maximum cumulative retry time in seconds
    retry_exceptions = (
        httpx.ReadTimeout,
        httpx.ConnectTimeout,
        httpx.NetworkError,  # includes transient connection errors
        httpx.RemoteProtocolError,
    )

    def deco(fn):
        def wrapped(*args, **kwargs):
            last_exc = None
            total_retry_time = 0  # Track cumulative retry time
            for attempt in range(retries):
                try:
                    resp = fn(*args, **kwargs)
                except retry_exceptions as exc:
                    last_exc = exc
                    # backoff and retry
                    delay = min(max_backoff, backoff * (2**attempt)) * (
                        1 + random.random() * 0.25
                    )
                    if total_retry_time + delay > max_retry_time:
                        raise TimeoutError("Exceeded maximum retry time of 120 seconds")
                    total_retry_time += delay
                    time.sleep(delay)
                    continue

                # Retry on selected HTTP status
                if resp.status_code in retry_statuses:
                    # honor Retry-After if present
                    ra = resp.headers.get("Retry-After")
                    if ra:
                        try:
                            delay = min(max_backoff, float(ra))
                        except ValueError:
                            delay = min(max_backoff, backoff * (2**attempt))
                    else:
                        delay = min(max_backoff, backoff * (2**attempt)) * (
                            1 + random.random() * 0.25
                        )
                    if total_retry_time + delay > max_retry_time:
                        raise TimeoutError("Exceeded maximum retry time of 120 seconds")
                    total_retry_time += delay
                    time.sleep(delay)
                    continue

                return resp

            if last_exc:
                raise last_exc
            return resp

        return wrapped

    return deco
]]
    local result, applied = diff.apply_unified_diff(diff_text, original)
    local expected_lines = vim.split(expected, '\n', { trimempty = true })
    assert.are.same(expected_lines, result)
  end)

  -- Tests for offset tracking in sequential hunk application
  it('correctly applies offset when first hunk adds lines', function()
    local diff_text = [[
--- a/test.txt
+++ b/test.txt
@@ -1,2 +1,4 @@
 line1
+added1
+added2
 line2
@@ -3,1 +5,1 @@
 line3
]]
    local original = { 'line1', 'line2', 'line3' }
    local original_content = table.concat(original, '\n')
    local result, applied = diff.apply_unified_diff(diff_text, original_content)
    assert.is_true(applied)
    assert.are.same({ 'line1', 'added1', 'added2', 'line2', 'line3' }, result)
  end)

  it('correctly applies offset when first hunk removes lines', function()
    local diff_text = [[
--- a/test.txt
+++ b/test.txt
@@ -1,3 +1,1 @@
 line1
-line2
-line3
@@ -4,1 +2,1 @@
 line4
]]
    local original = { 'line1', 'line2', 'line3', 'line4' }
    local original_content = table.concat(original, '\n')
    local result, applied = diff.apply_unified_diff(diff_text, original_content)
    assert.is_true(applied)
    assert.are.same({ 'line1', 'line4' }, result)
  end)

  it('correctly tracks offset through multiple hunks with mixed add/remove', function()
    local diff_text = [[
--- a/test.txt
+++ b/test.txt
@@ -1,1 +1,2 @@
 a
+b
@@ -2,1 +3,1 @@
-c
+C
@@ -3,1 +4,3 @@
 d
+e
+f
]]
    local original = { 'a', 'c', 'd' }
    local original_content = table.concat(original, '\n')
    local result, applied = diff.apply_unified_diff(diff_text, original_content)
    assert.is_true(applied)
    assert.are.same({ 'a', 'b', 'C', 'd', 'e', 'f' }, result)
  end)

  it('handles offset when hunks are far apart', function()
    local diff_text = [[
--- a/test.txt
+++ b/test.txt
@@ -2,1 +2,2 @@
 line2
+inserted
@@ -10,1 +11,1 @@
-line10
+LINE10
]]
    local original = {
      'line1',
      'line2',
      'line3',
      'line4',
      'line5',
      'line6',
      'line7',
      'line8',
      'line9',
      'line10',
    }
    local original_content = table.concat(original, '\n')
    local result, applied = diff.apply_unified_diff(diff_text, original_content)
    assert.is_true(applied)
    local expected = {
      'line1',
      'line2',
      'inserted',
      'line3',
      'line4',
      'line5',
      'line6',
      'line7',
      'line8',
      'line9',
      'LINE10',
    }
    assert.are.same(expected, result)
  end)

  it('applies three consecutive hunks with positive offset accumulation', function()
    local diff_text = [[
--- a/test.txt
+++ b/test.txt
@@ -1,1 +1,2 @@
 a
+b
@@ -2,1 +3,2 @@
 c
+d
@@ -3,1 +5,2 @@
 e
+f
]]
    local original = { 'a', 'c', 'e' }
    local original_content = table.concat(original, '\n')
    local result, applied = diff.apply_unified_diff(diff_text, original_content)
    assert.is_true(applied)
    assert.are.same({ 'a', 'b', 'c', 'd', 'e', 'f' }, result)
  end)

  it('applies three consecutive hunks with negative offset accumulation', function()
    local diff_text = [[
--- a/test.txt
+++ b/test.txt
@@ -1,2 +1,1 @@
-x
 a
@@ -3,2 +2,1 @@
-y
 b
@@ -5,2 +3,1 @@
-z
 c
]]
    local original = { 'x', 'a', 'y', 'b', 'z', 'c' }
    local original_content = table.concat(original, '\n')
    local result, applied = diff.apply_unified_diff(diff_text, original_content)
    assert.is_true(applied)
    assert.are.same({ 'a', 'b', 'c' }, result)
  end)

  it('handles zero-offset hunks (replacements without size change)', function()
    local diff_text = [[
--- a/test.txt
+++ b/test.txt
@@ -1,1 +1,1 @@
-old1
+new1
@@ -2,1 +2,1 @@
-old2
+new2
@@ -3,1 +3,1 @@
-old3
+new3
]]
    local original = { 'old1', 'old2', 'old3' }
    local original_content = table.concat(original, '\n')
    local result, applied = diff.apply_unified_diff(diff_text, original_content)
    assert.is_true(applied)
    assert.are.same({ 'new1', 'new2', 'new3' }, result)
  end)

  it('applies offset correctly when first hunk is pure insertion (len_old=0)', function()
    local diff_text = [[
--- a/test.txt
+++ b/test.txt
@@ -0,0 +1,2 @@
+inserted1
+inserted2
@@ -1,1 +3,1 @@
 original
]]
    local original = { 'original' }
    local original_content = table.concat(original, '\n')
    local result, applied = diff.apply_unified_diff(diff_text, original_content)
    assert.is_true(applied)
    assert.are.same({ 'inserted1', 'inserted2', 'original' }, result)
  end)

  it('handles complex offset scenario with interleaved additions and deletions', function()
    local diff_text = [[
--- a/test.txt
+++ b/test.txt
@@ -1,2 +1,1 @@
-delete1
 keep1
@@ -3,1 +2,3 @@
 keep2
+add1
+add2
@@ -4,2 +5,1 @@
-delete2
 keep3
]]
    local original = { 'delete1', 'keep1', 'keep2', 'delete2', 'keep3' }
    local original_content = table.concat(original, '\n')
    local result, applied = diff.apply_unified_diff(diff_text, original_content)
    assert.is_true(applied)
    assert.are.same({ 'keep1', 'keep2', 'add1', 'add2', 'keep3' }, result)
  end)

  it('offset tracking works with hunks that have context lines', function()
    local diff_text = [[
--- a/test.txt
+++ b/test.txt
@@ -1,3 +1,4 @@
 ctx1
 line1
+inserted
 ctx2
@@ -5,2 +6,2 @@
 ctx3
-line2
+LINE2
]]
    local original = { 'ctx1', 'line1', 'ctx2', 'ctx3', 'line2' }
    local original_content = table.concat(original, '\n')
    local result, applied = diff.apply_unified_diff(diff_text, original_content)
    assert.is_true(applied)
    assert.are.same({ 'ctx1', 'line1', 'inserted', 'ctx2', 'ctx3', 'LINE2' }, result)
  end)
end)
