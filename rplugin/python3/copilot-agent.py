import pynvim
from mypynvim.core.nvim import MyNvim

from handlers.vsplit_chat_handler import VSplitChatHandler
from handlers.inplace_chat_handler import InPlaceChatHandler
from tools.priority_matrix import PriorityMatrix

from mycopilot.mycopilot import Copilot

PLUGIN_MAPPING_CMD = "CopilotChatMapping"
PLUGIN_AUTOCMD_CMD = "CopilotChatAutocmd"


@pynvim.plugin
class CopilotAgentPlugin(object):
    def __init__(self, nvim: pynvim.Nvim):
        self.nvim: MyNvim = MyNvim(nvim, PLUGIN_MAPPING_CMD, PLUGIN_AUTOCMD_CMD)

        self.matrix = None
        self.vsplit_chat_handler = None
        self.inplace_chat_handler = None

    @pynvim.command("EchoPark")
    def my_command(self):
        copilot = Copilot()
        copilot.function_calling_test()
        self.nvim.notify("done")

    def init_matrix(self):
        if self.matrix is None:
            self.matrix = PriorityMatrix(self.nvim)

    @pynvim.command("PriorityMatrix")
    def priority_matrix(self):
        self.init_matrix()
        if self.matrix:
            self.matrix.layout.mount()

    def init_vsplit_chat_handler(self):
        if self.vsplit_chat_handler is None:
            self.vsplit_chat_handler = VSplitChatHandler(self.nvim)

    @pynvim.command("CopilotChatVsplit", nargs="1")
    def copilot_agent_cmd(self, args: list[str]):
        self.init_vsplit_chat_handler()
        if self.vsplit_chat_handler:
            file_type = self.nvim.current.buffer.options["filetype"]
            self.vsplit_chat_handler.vsplit()
            self.vsplit_chat_handler.chat(args[0], file_type)

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

    @pynvim.command(PLUGIN_MAPPING_CMD, nargs="*")
    def plugin_mapping_cmd(self, args):
        bufnr, mapping = args
        self.nvim.key_mapper.execute(bufnr, mapping)

    @pynvim.command(PLUGIN_AUTOCMD_CMD, nargs="*")
    def plugin_autocmd_cmd(self, args):
        event, id, bufnr = args
        self.nvim.autocmd_mapper.execute(event, id, bufnr)
