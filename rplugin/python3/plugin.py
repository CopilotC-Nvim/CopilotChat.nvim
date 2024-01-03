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
        code = self.nvim.current.buffer[:]
        file_type = self.nvim.eval("expand('%')").split(".")[-1]
        # Check if we're already in a chat buffer
        if self.nvim.eval("getbufvar(bufnr(), '&buftype')") != "nofile":
            # Create a new scratch buffer to hold the chat
            self.nvim.command("vnew")
            # Set it to the left side of the screen
            self.nvim.command("wincmd L")
            self.nvim.command("vertical resize 50%")
            # Set the buffer type to nofile and hide it when it's not active
            self.nvim.command("setlocal buftype=nofile bufhidden=hide noswapfile")
            # Set filetype as markdown and wrap with linebreaks
            self.nvim.command("setlocal filetype=markdown wrap linebreak")

        # if self.nvim.current.line != "":
        self.nvim.command("normal Go")
        self.nvim.current.line += "### User"
        self.nvim.command("normal o")
        self.nvim.current.line += prompt
        self.nvim.command("normal o")
        self.nvim.current.line += "### Copilot"
        self.nvim.command("normal o")

        for token in self.copilot.ask(prompt, code, language=file_type):
            if "\n" not in token:
                self.nvim.current.line += token
                continue
            lines = token.split("\n")
            for i in range(len(lines)):
                self.nvim.current.line += lines[i]
                if i != len(lines) - 1:
                    self.nvim.command("normal o")

        self.nvim.command("normal o")
        self.nvim.current.line += ""
        self.nvim.command("normal o")
        self.nvim.current.line += "---"
