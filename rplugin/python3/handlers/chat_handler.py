from typing import Optional, cast

import mycopilot.prompts as prompts
from mycopilot.mycopilot import Copilot
from mypynvim.core.buffer import MyBuffer
from mypynvim.core.nvim import MyNvim


def is_module_installed(name):
    try:
        __import__(name)
        return True
    except ImportError:
        return False


class ChatHandler:
    def __init__(self, nvim: MyNvim, buffer: MyBuffer):
        self.nvim: MyNvim = nvim
        self.copilot = None
        self.buffer: MyBuffer = buffer

    # public

    def chat(
        self,
        prompt: str,
        filetype: str,
        code: str = "",
        winnr: int = 0,
        system_prompt: Optional[str] = None,
        disable_start_separator: bool = False,
        disable_end_separator: bool = False,
        model: str = "gpt-4",
    ):
        if system_prompt is None:
            system_prompt = self._construct_system_prompt(prompt)

        # Start the spinner
        self.nvim.exec_lua('require("CopilotChat.spinner").show()')

        if not disable_start_separator:
            self._add_start_separator(system_prompt, prompt, code, filetype, winnr)

        self._add_chat_messages(system_prompt, prompt, code, filetype, model=model)

        # Stop the spinner
        self.nvim.exec_lua('require("CopilotChat.spinner").hide()')

        if not disable_end_separator:
            self._add_end_separator()

    # private

    def _construct_system_prompt(self, prompt: str):
        system_prompt = prompts.COPILOT_INSTRUCTIONS
        if prompt == prompts.FIX_SHORTCUT:
            system_prompt = prompts.COPILOT_FIX
        elif prompt == prompts.TEST_SHORTCUT:
            system_prompt = prompts.COPILOT_TESTS
        elif prompt == prompts.EXPLAIN_SHORTCUT:
            system_prompt = prompts.COPILOT_EXPLAIN
        return system_prompt

    def _add_start_separator(
        self,
        system_prompt: str,
        prompt: str,
        code: str,
        file_type: str,
        winnr: int,
    ):
        if is_module_installed("tiktoken"):
            self._add_start_separator_with_token_count(
                system_prompt, prompt, code, file_type, winnr
            )
        else:
            self._add_regular_start_separator(
                system_prompt, prompt, code, file_type, winnr
            )

    def _add_regular_start_separator(
        self,
        system_prompt: str,
        prompt: str,
        code: str,
        file_type: str,
        winnr: int,
    ):
        if code:
            code = f"\n        \nCODE:\n```{file_type}\n{code}\n```"

        last_row_before = len(self.buffer.lines())
        system_prompt_height = len(system_prompt.split("\n"))
        code_height = len(code.split("\n"))

        start_separator = f"""### User
                                        
SYSTEM PROMPT:
```
{system_prompt}
```
{prompt}{code}

### Copilot

"""
        self.buffer.append(start_separator.split("\n"))

        self._add_folds(code, code_height, last_row_before, system_prompt_height, winnr)

    def _add_start_separator_with_token_count(
        self,
        system_prompt: str,
        prompt: str,
        code: str,
        file_type: str,
        winnr: int,
    ):
        import tiktoken

        encoding = tiktoken.encoding_for_model("gpt-4")

        num_total_tokens = len(encoding.encode(f"{system_prompt}\n{prompt}\n{code}"))
        num_system_tokens = len(encoding.encode(system_prompt))
        num_prompt_tokens = len(encoding.encode(prompt))
        num_code_tokens = len(encoding.encode(code))

        if code:
            code = f"\n        \nCODE: {num_code_tokens} Tokens \n```{file_type}\n{code}\n```"

        last_row_before = len(self.buffer.lines())
        system_prompt_height = len(system_prompt.split("\n"))
        code_height = len(code.split("\n"))

        start_separator = f"""### User
                                        
SYSTEM PROMPT: {num_system_tokens} Tokens 
```
{system_prompt}
```
{prompt}{code}

### Copilot

"""
        self.buffer.append(start_separator.split("\n"))

        last_row_after = last_row_before + system_prompt_height + 5
        self.buffer.eol(last_row_before, f"{num_total_tokens} Total Tokens", "@float")
        self.buffer.eol(
            last_row_after, f"{num_prompt_tokens} Tokens", "NightflySteelBlue"
        )

        self._add_folds(code, code_height, last_row_before, system_prompt_height, winnr)

    def _add_folds(
        self,
        code: str,
        code_height: int,
        last_row_before: int,
        system_prompt_height: int,
        winnr: int,
    ):
        system_fold_start = last_row_before + 2
        system_fold_end = system_fold_start + system_prompt_height + 3
        main_command = f"{system_fold_start}, {system_fold_end} fold | normal! Gzz"
        full_command = f"call win_execute({winnr}, '{main_command}')"
        self.nvim.command(full_command)

        if code != "":
            code_fold_start = system_fold_end + 2
            code_fold_end = code_fold_start + code_height - 1
            main_command = f"{code_fold_start}, {code_fold_end} fold | normal! G"
            full_command = f"call win_execute({winnr}, '{main_command}')"
            self.nvim.command(full_command)

    def _add_chat_messages(
        self, system_prompt: str, prompt: str, code: str, file_type: str, model: str
    ):
        if self.copilot is None:
            self.copilot = Copilot()

        for token in self.copilot.ask(
            system_prompt, prompt, code, language=cast(str, file_type), model=model
        ):
            buffer_lines = cast(list[str], self.buffer.lines())
            last_line_row = len(buffer_lines) - 1
            last_line_col = len(buffer_lines[-1])

            self.nvim.api.buf_set_text(
                self.buffer.number,
                last_line_row,
                last_line_col,
                last_line_row,
                last_line_col,
                token.split("\n"),
            )

    def _add_end_separator(self):
        end_separator = "\n---\n"
        self.buffer.append(end_separator.split("\n"))
