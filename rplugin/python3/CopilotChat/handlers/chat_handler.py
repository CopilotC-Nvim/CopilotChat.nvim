import os
import time
from datetime import datetime
from typing import Optional, cast

import CopilotChat.prompts as system_prompts
from CopilotChat.copilot import Copilot
from CopilotChat.mypynvim.core.buffer import MyBuffer
from CopilotChat.mypynvim.core.nvim import MyNvim


def is_module_installed(name):
    try:
        __import__(name)
        return True
    except ImportError:
        return False


DEFAULT_TEMPERATURE = 0.1


# TODO: Support Custom Instructions when this issue has been resolved https://github.com/microsoft/vscode-copilot-release/issues/563
class ChatHandler:
    has_show_extra_info = False

    def __init__(self, nvim: MyNvim, buffer: MyBuffer):
        self.nvim: MyNvim = nvim
        self.copilot: Copilot = None
        self.buffer: MyBuffer = buffer
        self.proxy: str = os.getenv("HTTPS_PROXY") or os.getenv("ALL_PROXY") or ""
        self.language = self.nvim.eval("g:copilot_chat_language")

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

        # Validate and set temperature
        temperature = self._get_temperature()

        # Set proxy
        self._set_proxy()

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

        self._add_chat_messages(
            system_prompt, prompt, code, filetype, model, temperature=temperature
        )

        # Stop the spinner
        self.nvim.exec_lua('require("CopilotChat.spinner").hide()')

        if not disable_end_separator:
            self._add_end_separator(model, disable_separators)

    # private
    def _set_proxy(self):
        self.proxy = self.nvim.eval("g:copilot_chat_proxy")
        if "://" not in self.proxy:
            self.proxy = None

    def _get_temperature(self):
        temperature = self.nvim.eval("g:copilot_chat_temperature")
        try:
            temperature = float(temperature)
            if not 0 <= temperature <= 1:
                raise ValueError
        except ValueError:
            self.nvim.exec_lua(
                'require("CopilotChat.utils").log_error(...)',
                "Invalid temperature value. Please provide a numeric value between 0 and 1.",
            )
            temperature = DEFAULT_TEMPERATURE
        return temperature

    def _construct_system_prompt(self, prompt: str):
        system_prompt = system_prompts.COPILOT_INSTRUCTIONS
        if prompt == system_prompts.FIX_SHORTCUT:
            system_prompt = system_prompts.COPILOT_FIX
        elif prompt == system_prompts.TEST_SHORTCUT:
            system_prompt = system_prompts.COPILOT_TESTS
        elif prompt == system_prompts.EXPLAIN_SHORTCUT:
            system_prompt = system_prompts.COPILOT_EXPLAIN
        if self.language != "":
            system_prompt = (
                system_prompts.PROMPT_ANSWER_LANGUAGE_TEMPLATE.substitute(
                    language=self.language
                )
                + "\n"
                + system_prompt
            )
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
        hide_system_prompt = (
            self.nvim.eval("g:copilot_chat_hide_system_prompt") == "yes"
        )

        if hide_system_prompt:
            system_prompt = "...System prompt hidden..."

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

        hide_system_prompt = (
            self.nvim.eval("g:copilot_chat_hide_system_prompt") == "yes"
        )
        num_total_tokens = len(encoding.encode(f"{system_prompt}\n{prompt}\n{code}"))
        num_system_tokens = len(encoding.encode(system_prompt))
        num_prompt_tokens = len(encoding.encode(prompt))
        num_code_tokens = len(encoding.encode(code))

        if hide_system_prompt:
            system_prompt = "... System prompt hidden ..."

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
        self,
        system_prompt: str,
        prompt: str,
        code: str,
        file_type: str,
        model: str,
        temperature: float = DEFAULT_TEMPERATURE,
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
        self.nvim.exec_lua(
            'require("CopilotChat.utils").log_info(...)',
            f"System prompt: {system_prompt}",
        )
        self.nvim.exec_lua(
            'require("CopilotChat.utils").log_info(...)', f"Prompt: {prompt}"
        )
        self.nvim.exec_lua(
            'require("CopilotChat.utils").log_info(...)', f"Code: {code}"
        )
        self.nvim.exec_lua(
            'require("CopilotChat.utils").log_info(...)', f"File type: {file_type}"
        )
        self.nvim.exec_lua(
            'require("CopilotChat.utils").log_info(...)', f"Model: {model}"
        )
        self.nvim.exec_lua(
            'require("CopilotChat.utils").log_info(...)', f"Temperature: {temperature}"
        )
        self.nvim.exec_lua(
            'require("CopilotChat.utils").log_info(...)', "Asking Copilot"
        )
        # TODO: Abort request if the user closes the layout
        for token in self.copilot.ask(
            system_prompt,
            prompt,
            code,
            language=cast(str, file_type),
            model=model,
            temperature=temperature,
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
        self.nvim.exec_lua(
            'require("CopilotChat.utils").log_info(...)', "Copilot answered"
        )

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
