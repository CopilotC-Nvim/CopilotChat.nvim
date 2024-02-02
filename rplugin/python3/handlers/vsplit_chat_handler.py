from handlers.chat_handler import ChatHandler
from mypynvim.core.buffer import MyBuffer
from mypynvim.core.nvim import MyNvim


class VSplitChatHandler(ChatHandler):
    def __init__(self, nvim: MyNvim):
        self.nvim: MyNvim = nvim
        self.copilot = None
        self.buffer: MyBuffer = MyBuffer.new(
            self.nvim,
            {
                "filetype": "markdown",
            },
        )

    def vsplit(self):
        var_key = "copilot_chat"
        for window in self.nvim.windows:
            try:
                if window.vars[var_key]:
                    self.nvim.current.window = window
                    return
            except Exception:
                pass

        self.buffer.vsplit(
            {
                "wrap": True,
                "linebreak": True,
                "conceallevel": 2,
                "concealcursor": "n",
            }
        )
        self.nvim.current.window.vars[var_key] = True

    def chat(self, prompt: str, filetype: str, code: str = ""):
        super().chat(prompt, filetype, code, self.nvim.current.window.handle)
