import time
from datetime import datetime
from typing import Optional, cast

import prompts as system_prompts
from copilot import Copilot
from mypynvim.core.buffer import MyBuffer
from mypynvim.core.nvim import MyNvim


def is_module_installed(name):
    try:
        __import__(name)
        return True
    except ImportError:
        return False


# TODO: Abort request if the user closes the layout
class ChatHandler:
    has_show_extra_info = False

    def __init__(self, nvim: MyNvim, buffer: MyBuffer):
        self.nvim: MyNvim = nvim
        self.copilot: Copilot = None
        self.buffer: MyBuffer = buffer
        self.proxy: str = None

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
        disable_separators = (
            self.nvim.eval("g:copilot_chat_disable_separators") == "yes"
        )
        self.proxy = self.nvim.eval("g:copilot_chat_proxy")
        if "://" not in self.proxy:
            self.proxy = None

        if system_prompt is None:
            system_prompt = self._construct_system_prompt(prompt)
        # Start the spinner
        self.nvim.exec_lua('require("CopilotChat.spinner").show()')

        self.nvim.exec_lua(
            'require("CopilotChat.utils").log_info(...)', f"Chatting with {model} model"
        )

        if not disable_start_separator:
            self._add_start_separator(
                system_prompt, prompt, code, filetype, winnr, disable_separators
            )

        self._add_chat_messages(system_prompt, prompt, code, filetype, model)

        # Stop the spinner
        self.nvim.exec_lua('require("CopilotChat.spinner").hide()')

        if not disable_end_separator:
            self._add_end_separator(model, disable_separators)

    # private

    def _construct_system_prompt(self, prompt: str):
        system_prompt = system_prompts.COPILOT_INSTRUCTIONS
        if prompt == system_prompts.FIX_SHORTCUT:
            system_prompt = system_prompts.COPILOT_FIX
        elif prompt == system_prompts.TEST_SHORTCUT:
            system_prompt = system_prompts.COPILOT_TESTS
        elif prompt == system_prompts.EXPLAIN_SHORTCUT:
            system_prompt = system_prompts.COPILOT_EXPLAIN
        return system_prompt

    def _add_start_separator(
        self,
        system_prompt: str,
        prompt: str,
        code: str,
        file_type: str,
        winnr: int,
        no_annoyance: bool = False,
    ):
        if is_module_installed("tiktoken") and not no_annoyance:
            self._add_start_separator_with_token_count(
                system_prompt, prompt, code, file_type, winnr
            )
        else:
            self._add_regular_start_separator(
                system_prompt, prompt, code, file_type, winnr, no_annoyance
            )

    def _add_regular_start_separator(
        self,
        system_prompt: str,
        prompt: str,
        code: str,
        file_type: str,
        winnr: int,
        no_annoyance: bool = False,
    ):
        if code and not no_annoyance:
            code = f"\n        \nCODE:\n```{file_type}\n{code}\n```"

        last_row_before = len(self.buffer.lines())
        system_prompt_height = len(system_prompt.split("\n"))
        code_height = len(code.split("\n"))

        start_separator = (
            f"""### User

SYSTEM PROMPT:
```
{system_prompt}
```
{prompt}{code}

### Copilot

"""
            if not no_annoyance
            else f"### User\n{prompt}\n\n### Copilot\n\n"
        )
        self.buffer.append(start_separator.split("\n"))

        if no_annoyance:
            return
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
        self.nvim.command("set foldmethod=manual")
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
            self.copilot = Copilot(proxy=self.proxy)
            if self.copilot.github_token is None:
                req = self.copilot.request_auth()
                self.nvim.out_write(
                    f"Please visit {req['verification_uri']} and enter the code {req['user_code']}\n"
                )
                current_time = time.time()
                wait_until = current_time + req["expires_in"]
                while self.copilot.github_token is None:
                    self.copilot.poll_auth(req["device_code"])
                    time.sleep(req["interval"])
                    if time.time() > wait_until:
                        self.nvim.out_write("Timed out waiting for authentication\n")
                        return
                self.nvim.out_write("Successfully authenticated with Copilot\n")
            self.copilot.authenticate()

        last_line_col = 0
        for token in self.copilot.ask(
            system_prompt, prompt, code, language=cast(str, file_type), model=model
        ):
            self.nvim.exec_lua(
                'require("CopilotChat.utils").log_info(...)', f"Token: {token}"
            )
            buffer_lines = cast(list[str], self.buffer.lines())
            last_line_row = len(buffer_lines) - 1
            self.nvim.api.buf_set_text(
                self.buffer.number,
                last_line_row,
                last_line_col,
                last_line_row,
                last_line_col,
                token.split("\n"),
            )
            last_line_col += len(token.encode("utf-8"))
            if "\n" in token:
                last_line_col = 0

    def _add_end_separator(self, model: str, disable_separators: bool = False):
        current_datetime = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        model_info = f"\n#### Answer provided by Copilot (Model: `{model}`) on {current_datetime}."
        additional_instructions = (
            "\n> For additional queries, please use the `CopilotChat` command."
        )
        disclaimer = "\n> Please be aware that the AI's output may not always be accurate. Always cross-verify the output."

        end_message = model_info + additional_instructions + disclaimer

        show_extra = disable_separators or ChatHandler.has_show_extra_info

        if show_extra:
            end_message = "\n" + current_datetime + "\n\n---\n"

        ChatHandler.has_show_extra_info = True

        self.buffer.append(end_message.split("\n"))
