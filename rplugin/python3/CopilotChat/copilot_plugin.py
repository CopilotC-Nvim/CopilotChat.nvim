import pynvim
from CopilotChat.handlers.inplace_chat_handler import InPlaceChatHandler
from CopilotChat.handlers.vsplit_chat_handler import VSplitChatHandler
from CopilotChat.mypynvim.core.nvim import MyNvim

PLUGIN_MAPPING_CMD = "CopilotChatMapping"
PLUGIN_AUTOCMD_CMD = "CopilotChatAutocmd"


@pynvim.plugin
class CopilotPlugin(object):
    def __init__(self, nvim: pynvim.Nvim):
        self.nvim: MyNvim = MyNvim(nvim, PLUGIN_MAPPING_CMD, PLUGIN_AUTOCMD_CMD)
        self.vsplit_chat_handler = None
        self.inplace_chat_handler = None

    def init_vsplit_chat_handler(self):
        if self.vsplit_chat_handler is None:
            self.vsplit_chat_handler = VSplitChatHandler(self.nvim)

    @pynvim.command("CopilotChatVsplitToggle")
    def copilot_chat_toggle_cmd(self):
        self.init_vsplit_chat_handler()
        if self.vsplit_chat_handler:
            self.vsplit_chat_handler.toggle_vsplit()

    @pynvim.command("CopilotChat", nargs="1")
    def copilot_agent_cmd(self, args: list[str]):
        self.init_vsplit_chat_handler()
        if self.vsplit_chat_handler:
            file_type = self.nvim.current.buffer.options["filetype"]
            self.vsplit_chat_handler.vsplit()
            # Get code from the unnamed register
            code = self.nvim.eval("getreg('\"')")
            self.vsplit_chat_handler.chat(args[0], file_type, code)

    @pynvim.command("CopilotChatReset")
    def copilot_agent_reset_cmd(self):
        if self.vsplit_chat_handler:
            self.vsplit_chat_handler.copilot.reset()
            self.vsplit_chat_handler.reset_buffer()

    @pynvim.command("CopilotChatVisual", nargs="1", range="")
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

    # Those commands are used by the plugin, internal use only
    @pynvim.command(PLUGIN_MAPPING_CMD, nargs="*")
    def plugin_mapping_cmd(self, args):
        bufnr, mapping = args
        self.nvim.key_mapper.execute(bufnr, mapping)

    @pynvim.command(PLUGIN_AUTOCMD_CMD, nargs="*")
    def plugin_autocmd_cmd(self, args):
        event, id, bufnr = args
        self.nvim.autocmd_mapper.execute(event, id, bufnr)

    @pynvim.command("CopilotChatInPlace", nargs="*", range="")
    def inplace_cmd(self, args: list[str], range: list[int]):
        self.init_inplace_chat_handler()
        if self.inplace_chat_handler:
            file_type = self.nvim.current.buffer.options["filetype"]
            code_lines = self.nvim.current.buffer[range[0] - 1 : range[1]]
            code = "\n".join(code_lines)
            user_buffer = self.nvim.current.buffer
            self.inplace_chat_handler.mount(code, file_type, range, user_buffer)
