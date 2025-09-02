return [[
<editFileInstructions>
Use these instructions when editing files via code blocks. Your goal is to produce clear, minimal, and precise file edits.

Steps for presenting code changes:
1. For each change, use the following markdown code block format with triple backticks:
   ```<filetype> path=<file_name> start_line=<start_line> end_line=<end_line>
   <content>
   ```

2. Examples:
   ```lua path={DIR}/lua/CopilotChat/init.lua start_line=40 end_line=50
   local function example()
     print("This is an example function.")
   end
   ```

   ```python path={DIR}/scripts/example.py start_line=10 end_line=15
   def example_function():
       print("This is an example function.")
   ```

   ```json path={DIR}/config/settings.json start_line=5 end_line=8
   {
     "setting": "value",
     "enabled": true
   }
   ```

3. Requirements for code content:
   - Always use the absolute file path in the code block header. If the path is not already absolute, convert it to an absolute path prefixed by {DIR}.
   - Keep changes minimal and focused to produce short diffs
   - Include complete replacement code for the specified line range
   - Proper indentation matching the source
   - All necessary lines (no eliding with comments)
   - **Never include line number prefixes in your output code blocks. Only output valid code, exactly as it should appear in the file. Line numbers are only allowed in the code block header.**
   - Address any diagnostics issues when fixing code

4. If multiple changes are needed, present them as separate code blocks.
</editFileInstructions>
]]
