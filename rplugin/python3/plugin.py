import pynvim
import copilot
import dotenv
import os
import time

dotenv.load_dotenv()


@pynvim.plugin
class TestPlugin(object):
    def __init__(self, nvim: pynvim.Nvim):
        self.nvim = nvim
        self.copilot = copilot.Copilot(os.getenv("COPILOT_TOKEN"))
        if self.copilot.github_token is None:
            req = self.copilot.request_auth()
            self.nvim.out_write(
                f"Please visit {req['verification_uri']} and enter the code {req['user_code']}\n")
            current_time = time.time()
            wait_until = current_time + req['expires_in']
            while self.copilot.github_token is None:
                self.copilot.poll_auth(req['device_code'])
                time.sleep(req['interval'])
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

        # Get code from the unnamed register
        code = self.nvim.eval("getreg('\"')")
        file_type = self.nvim.eval("expand('%')").split(".")[-1]
        # Check if we're already in a chat buffer
        if self.nvim.eval("getbufvar(bufnr(), '&buftype')") != "nofile":
            # Create a new scratch buffer to hold the chat
            self.nvim.command("enew")
            self.nvim.command("setlocal buftype=nofile bufhidden=hide noswapfile")
        if self.nvim.current.line != "":
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
