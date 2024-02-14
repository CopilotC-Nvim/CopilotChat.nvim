from __future__ import annotations

from typing import TYPE_CHECKING

from CopilotChat.mypynvim.core.buffer import MyBuffer
from pynvim.api import Window

if TYPE_CHECKING:
    from CopilotChat.mypynvim.core.nvim import MyNvim


class MyWindow(Window):
    def __init__(self, nvim: MyNvim, window: Window):
        self.win: Window = window
        self.nvim: MyNvim = nvim

    def __getattr__(self, attr):
        return getattr(self.win, attr)

    def command(self, command: str):
        full_command = f"call win_execute({self.win.handle}, '{command}')"
        self.nvim.command(full_command)

    @property
    def buffer(self) -> MyBuffer:
        return MyBuffer(
            self.nvim, self.nvim.request("nvim_win_get_buf", self.win.handle)
        )

    @buffer.setter
    def buffer(self, buffer: MyBuffer):
        return self.nvim.request("nvim_win_set_buf", self.win.handle, buffer.handle)
