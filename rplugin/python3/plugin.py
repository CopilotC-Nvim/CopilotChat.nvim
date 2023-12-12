import pynvim
import copilot
import dotenv
import os
dotenv.load_dotenv()


@pynvim.plugin
class TestPlugin(object):
    def __init__(self, nvim: pynvim.Nvim):
        self.nvim = nvim
        self.copilot = copilot.Copilot(os.getenv("GITHUB_TOKEN"))
        self.copilot.authenticate()

    @pynvim.function("TestFunction")
    def testFunction(self, args):
        self.nvim.out_write(self.nvim.eval("getreg('\"')"))

    @pynvim.command("CopilotChat", nargs="1")
    def copilotChat(self, args: list[str]):
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


