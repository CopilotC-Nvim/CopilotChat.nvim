from CopilotChat.copilot import Copilot
from CopilotChat.handlers.chat_handler import ChatHandler
from CopilotChat.mypynvim.core.buffer import MyBuffer
from CopilotChat.mypynvim.core.nvim import MyNvim


class VSplitChatHandler(ChatHandler):
    def __init__(self, nvim: MyNvim):
        self.nvim: MyNvim = nvim
        self.copilot: Copilot = None
        self.buffer: MyBuffer = MyBuffer.new(
            self.nvim,
            {
                "filetype": "copilot-chat",
            },
        )
        self.language = self.nvim.eval("g:copilot_chat_language")
        self.clear_chat_on_new_prompt = self.nvim.eval(
            "g:copilot_chat_clear_chat_on_new_prompt"
        ) == "yes"

    def vsplit(self):
        self.buffer.option("filetype", "copilot-chat")
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

    def toggle_vsplit(self):
        """Toggle vsplit chat window."""
        var_key = "copilot_chat"
        for window in self.nvim.windows:
            try:
                if window.vars[var_key]:
                    self.nvim.command("close")
                    return
            except Exception:
                pass

        self.vsplit()
        self.buffer.option("filetype", "markdown")

    def chat(self, prompt: str, filetype: str, code: str = ""):
        if self.clear_chat_on_new_prompt:
            self.reset_buffer()

        self.buffer.option("filetype", "markdown")
        super().chat(prompt, filetype, code, self.nvim.current.window.handle)

    def reset_buffer(self):
        """Reset the chat buffer."""
        if self.copilot:
            self.copilot.reset()
        self.buffer.clear()
