return [[
<editFileInstructions>
Return edits similar to unified diffs that `diff -U0` would produce.

- Always include the first 2 lines with the file paths (no timestamps).
- Start each hunk of changes with a `@@ ... @@` line.
- Do not include line numbers in the hunk header.
- The user's patch tool needs CORRECT patches that apply cleanly against the current contents of the file.
- Indentation matters in the diffs!

Context lines:
- For each hunk that contains changes, you MUST always include 2-3 context lines before the change.
- ALWAYS prefix every context line with a single space character.
- Context lines MUST ONLY appear BEFORE changes, NEVER after changes.
- MISSING CONTEXT LINES WILL CAUSE PATCH FAILURES - they are mandatory, not optional.
- MISSING SPACE PREFIXES WILL CAUSE PATCH FAILURES - they are mandatory, not optional.

Change lines:
- Mark all lines to be removed or changed with `-`.
- Mark all new or modified lines with `+`.
- Only output hunks that specify changes with `+` or `-` lines.

Other instructions:
- Start a new hunk for each section of the file that needs changes.
- When editing a function, method, loop, etc., replace the entire code block: delete the entire existing version with `-` lines, then add the new, updated version with `+` lines.
- To move code within a file, use 2 hunks: one to delete it from its current location, one to insert it in the new location.
- To make a new file, show a diff from `--- /dev/null` to `+++ path/to/new/file.ext`.

Example:

```diff
--- mathweb/flask/app.py
+++ mathweb/flask/app.py
@@ ... @@
-class MathWeb:
+import sympy
+
+class MathWeb:
@@ ... @@
-def is_prime(x):
-    if x < 2:
-        return False
-    for i in range(2, int(math.sqrt(x)) + 1):
-        if x % i == 0:
-            return False
-    return True
@@ ... @@
-@app.route('/prime/<int:n>')
-def nth_prime(n):
-    count = 0
-    num = 1
-    while count < n:
-        num += 1
-        if is_prime(num):
-            count += 1
-    return str(num)
+@app.route('/prime/<int:n>')
+def nth_prime(n):
+    count = 0
+    num = 1
+    while count < n:
+        num += 1
+        if sympy.isprime(num):
+            count += 1
+    return str(num)
```
</editFileInstructions>
]]
