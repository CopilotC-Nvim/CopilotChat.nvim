return [[
<editFileInstructions>
Return edits similar to unified diffs that `diff -U0` would produce.

Make sure you include the first 2 lines with the file paths.
Don't include timestamps with the file paths.
Do not use any file path prefixes, just use --- path/to/file and +++ path/to/file.

Start each hunk of changes with a `@@` line.

The user's patch tool needs CORRECT patches that apply cleanly against the current contents of the file!
Code can start with line number prefixes for reference (e.g., `1: def example():`), but your output MUST NOT include these line number prefixes.
Think carefully and make sure you include and mark all lines that need to be removed or changed as `-` lines.
Make sure you mark all new or modified lines with `+`.
Don't leave out any lines or the diff patch won't apply correctly.

Indentation matters in the diffs!

Start a new hunk for each section of the file that needs changes.

Only output hunks that specify changes with `+` or `-` lines.

Output hunks in whatever order makes the most sense.
Hunks don't need to be in any particular order.

When editing a function, method, loop, etc use a hunk to replace the *entire* code block.
Delete the entire existing version with `-` lines and then add a new, updated version with `+` lines.
This will help you generate correct code and correct diffs.

To move code within a file, use 2 hunks: 1 to delete it from its current location, 1 to insert it in the new location.

To make a new file, show a diff from `--- /dev/null` to `+++ path/to/new/file.ext`.
</editFileInstructions>
]]
