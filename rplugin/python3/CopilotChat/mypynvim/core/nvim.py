from typing import Iterable, Union

from CopilotChat.mypynvim.core.autocmdmapper import AutocmdMapper
from CopilotChat.mypynvim.core.buffer import MyBuffer
from CopilotChat.mypynvim.core.keymapper import Keymapper
from CopilotChat.mypynvim.core.window import MyWindow
from pynvim import Nvim
from pynvim.api.nvim import Current


class MyNvim(Nvim):
    def __init__(self, nvim: Nvim, mapping_command: str, autocmd_command: str):
        self.nvim: Nvim = nvim
        self.key_mapper = Keymapper(self)
        self.autocmd_mapper = AutocmdMapper(self)
        self.current = MyCurrent(self)
        self._mapping_command = mapping_command
        self._autocmd_command = autocmd_command

    def __getattr__(self, attr):
        return getattr(self.nvim, attr)

    # native api methods

    def notify(
        self, msg: Union[str, int, bool, list[str], list[int]], level: str = "info"
    ):
        if isinstance(msg, str):
            msg = msg.split("\n")
            if len(msg) == 1:
                msg = f'"{msg[0]}"'
                self.nvim.exec_lua(f"vim.notify(({msg}), '{level}')")
                return
            else:
                msg = str(msg)
                msg = "{" + msg[1:-1] + "}"
        elif isinstance(msg, Iterable):
            msg = str(msg)
            msg = "{" + msg[1:-1] + "}"
        else:
            msg = f"{msg}"

        self.nvim.exec_lua(f"vim.notify(vim.inspect({msg}), '{level}')")

    # custom api methods

    def feed(self, keys: str, mode: str = "n"):
        codes = self.nvim.api.replace_termcodes(keys, True, True, True)
        self.nvim.api.feedkeys(codes, mode, False)

    def move_cursor_to_previous_window(self):
        self.feed("<C-w>p")

    # window methods

    @property
    def windows(self) -> list[MyWindow]:
        return [MyWindow(self, win) for win in self.nvim.windows]

    def win(self, winnr: int) -> MyWindow:
        return MyWindow(self, self.nvim.windows[winnr])

    # buffer methods

    @property
    def buffers(self) -> list[MyBuffer]:
        return [MyBuffer(self, buf) for buf in self.nvim.buffers]

    def buf(self, bufnr: int) -> MyBuffer:
        return MyBuffer(self, self.nvim.buffers[bufnr])


class MyCurrent(Current):
    def __init__(self, mynvim: MyNvim):
        self.mynvim: MyNvim = mynvim
        self.nvim = mynvim.nvim

    def __getattr__(self, attr):
        return getattr(self.nvim.current, attr)

    @property
    def buffer(self) -> MyBuffer:
        return MyBuffer(self.mynvim, self.nvim.request("nvim_get_current_buf"))

    @buffer.setter
    def buffer(self, buffer: Union[MyBuffer, int]) -> None:
        return self.nvim.request("nvim_set_current_buf", buffer)

    @property
    def window(self) -> MyWindow:
        return MyWindow(self.mynvim, self.nvim.request("nvim_get_current_win"))

    @window.setter
    def window(self, window: Union[MyWindow, int]) -> None:
        return self.mynvim.request("nvim_set_current_win", window)
