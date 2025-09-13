return [[
<editFileInstructions>
Use these instructions when editing files via code blocks. Present changes as clear, minimal, and precise file edits.

For each change, use this markdown code block format:
```<filetype> path=<file_name> start_line=<start_line> end_line=<end_line>
<content>
```

Example:
```lua path={DIR}/lua/CopilotChat/init.lua start_line=40 end_line=50
local function example()
  print("This is an example function.")
end
```

Code content requirements:
Always use absolute file paths in headers. Convert relative paths to absolute by prefixing with {DIR}.
Keep changes minimal and focused. Include complete replacement code for the specified line range.
Use proper indentation matching the source file. Include all necessary lines without eliding code.
NEVER include line number prefixes in output code blocks - output only valid code as it should appear in the file.
Address any diagnostics issues when fixing code.

Present multiple changes as separate code blocks.
</editFileInstructions>
]]
