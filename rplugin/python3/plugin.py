import os
import time

import copilot
import prompts
import dotenv
import pynvim

dotenv.load_dotenv()


@pynvim.plugin
class CopilotChatPlugin(object):
    def __init__(self, nvim: pynvim.Nvim):
        self.nvim = nvim
        self.copilot = copilot.Copilot(os.getenv("COPILOT_TOKEN"))
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

    @pynvim.command("CopilotChat", nargs="1")
    def copilotChat(self, args: list[str]):
        if self.copilot.github_token is None:
            self.nvim.out_write("Please authenticate with Copilot first\n")
            return
        prompt = " ".join(args)

        if prompt == "/fix":
            prompt = prompts.FIX_SHORTCUT
        elif prompt == "/test":
            prompt = prompts.TEST_SHORTCUT
        elif prompt == "/explain":
            prompt = prompts.EXPLAIN_SHORTCUT

        # Get code from the unnamed register
        code = self.nvim.eval("getreg('\"')")
        file_type = self.nvim.eval("expand('%')").split(".")[-1]
        # Check if we're already in a chat buffer
        if self.nvim.eval("getbufvar(bufnr(), '&buftype')") != "nofile":
            # Create a new scratch buffer to hold the chat
            self.nvim.command("enew")
            self.nvim.command("setlocal buftype=nofile bufhidden=hide noswapfile")
            # Set filetype as markdown and wrap with linebreaks
            self.nvim.command("setlocal filetype=markdown wrap linebreak")

        # Get the current buffer
        buf = self.nvim.current.buffer
        self.nvim.api.buf_set_option(buf, "fileencoding", "utf-8")

        # Add start separator
        start_separator = f"""### User
{prompt}

### Copilot

"""
        buf.append(start_separator.split("\n"), -1)

        # Add chat messages
        for token in self.copilot.ask(prompt, code, language=file_type):
            buffer_lines = self.nvim.api.buf_get_lines(buf, 0, -1, 0)
            last_line_row = len(buffer_lines) - 1
            last_line = buffer_lines[-1]
            last_line_col = len(last_line.encode('utf-8'))

            self.nvim.api.buf_set_text(
                buf,
                last_line_row,
                last_line_col,
                last_line_row,
                last_line_col,
                token.split("\n"),
            )

        # Add end separator
        end_separator = "\n---\n"
        buf.append(end_separator.split("\n"), -1)
