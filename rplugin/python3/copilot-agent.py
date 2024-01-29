import pynvim
from handlers.inplace_chat_handler import InPlaceChatHandler
from handlers.vsplit_chat_handler import VSplitChatHandler
from mypynvim.core.nvim import MyNvim

PLUGIN_MAPPING_CMD = "CopilotChatMapping"
PLUGIN_AUTOCMD_CMD = "CopilotChatAutocmd"


@pynvim.plugin
class CopilotAgentPlugin(object):
    def __init__(self, nvim: pynvim.Nvim):
        self.nvim: MyNvim = MyNvim(nvim, PLUGIN_MAPPING_CMD, PLUGIN_AUTOCMD_CMD)
        self.vsplit_chat_handler = None
        self.inplace_chat_handler = None

    def init_vsplit_chat_handler(self):
        if self.vsplit_chat_handler is None:
            self.vsplit_chat_handler = VSplitChatHandler(self.nvim)

    @pynvim.command("CopilotChatVsplitVisual", nargs="1", range="")
    def copilot_agent_visual_cmd(self, args: list[str], range: list[int]):
        self.init_vsplit_chat_handler()
        if self.vsplit_chat_handler:
            file_type = self.nvim.current.buffer.options["filetype"]
            code_lines = self.nvim.current.buffer[range[0] - 1 : range[1]]
            code = "\n".join(code_lines)
            self.vsplit_chat_handler.vsplit()
            self.vsplit_chat_handler.chat(args[0], file_type, code)

    def init_inplace_chat_handler(self):
        if self.inplace_chat_handler is None:
            self.inplace_chat_handler = InPlaceChatHandler(self.nvim)

    @pynvim.command("CopilotChatInPlace", nargs="*", range="")
    def inplace_cmd(self, args: list[str], range: list[int]):
        self.init_inplace_chat_handler()
        if self.inplace_chat_handler:
            file_type = self.nvim.current.buffer.options["filetype"]
            code_lines = self.nvim.current.buffer[range[0] - 1 : range[1]]
            code = "\n".join(code_lines)
            user_buffer = self.nvim.current.buffer
            self.inplace_chat_handler.mount(code, file_type, range, user_buffer)
