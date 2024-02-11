from __future__ import annotations

from typing import TYPE_CHECKING, Callable, Union

if TYPE_CHECKING:
    from CopilotChat.mypynvim.core.nvim import MyNvim


class Keymapper:
    def __init__(self, nvim: MyNvim):
        self.nvim: MyNvim = nvim
        self._keymap_callback_library = {}

    def buf_set(
        self,
        bufnr: int,
        mode: str,
        lhs: str,
        rhs: Union[str, Callable],
    ):
        if callable(rhs):
            escaped_lhs = lhs.replace("<", "_").replace(">", "_")
            if not self._keymap_callback_library.get(str(bufnr)):
                self._keymap_callback_library[str(bufnr)] = {}
            self._keymap_callback_library[str(bufnr)][escaped_lhs] = rhs
            rhs = f"<cmd>{self.nvim._mapping_command} {bufnr} {escaped_lhs}<CR>"

        self.nvim.api.buf_set_keymap(bufnr, mode, lhs, rhs, {"noremap": True})

    def execute(self, bufnr: int, mapping: str):
        if bufnr is not None:
            callback = self._keymap_callback_library[bufnr][mapping]
            if callable(callback):
                callback()
