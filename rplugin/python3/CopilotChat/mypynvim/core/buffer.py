from __future__ import annotations

from typing import TYPE_CHECKING, Any, Callable, Dict, Union

from pynvim.api import Buffer

if TYPE_CHECKING:
    from Copilotchat.mypynvim.core.nvim import MyNvim


class MyBuffer(Buffer):
    def __init__(self, nvim: MyNvim, buffer: Buffer, opts: dict[str, Any] = {}):
        self.buf: Buffer = buffer
        self.nvim: MyNvim = nvim
        self.namespace: int = self.nvim.api.create_namespace(str(self.buf.handle))
        self.option(opts)

    def __getattr__(self, attr):
        return getattr(self.buf, attr)

    @classmethod
    def new(cls, nvim: MyNvim, opts: dict[str, Any] = {}):
        buffer = nvim.api.create_buf(False, True)
        return cls(nvim, buffer, opts)

    # mutate methods

    def option(self, option: Union[str, Dict[str, Any]], value: Any = None):
        if isinstance(option, str):
            if value is None:
                return self.nvim.api.buf_get_option(self.buf.handle, option)
            else:
                self.nvim.api.buf_set_option(self.buf.handle, option, value)
        elif isinstance(option, dict):
            for opt, val in option.items():
                self.nvim.api.buf_set_option(self.buf.handle, opt, val)

    def map(self, modes: Union[str, list[str]], lhs: str, rhs: Union[str, Callable]):
        if isinstance(modes, str):
            modes = [modes]
        for mode in modes:
            self.nvim.key_mapper.buf_set(self.buf.handle, mode, lhs, rhs)

    def autocmd(self, event: Union[str, list[str]], id: str, callback: Callable):
        self.nvim.autocmd_mapper.buf_set(event, id, self.handle, callback)

    def var(self, name: str, value: Any = None):
        if value is None:
            return self.nvim.api.buf_get_var(self.buf.handle, name)
        else:
            self.nvim.api.buf_set_var(self.buf.handle, name, value)

    def lines(
        self,
        replacement: Union[str, list[str], None] = None,
        start: int = 0,
        end: int = -1,
    ) -> list[str]:
        if replacement is not None:
            if isinstance(replacement, str):
                replacement = replacement.split("\n")
            self.nvim.api.buf_set_lines(self.buf.handle, start, end, False, replacement)
        return self.nvim.api.buf_get_lines(self.buf.handle, start, end, False)

    def clear(self):
        self.nvim.api.buf_set_lines(self.buf.handle, 0, -1, True, [])

    def append(self, lines: list[str] | list[Any]):
        self.nvim.api.buf_set_lines(self.buf.handle, -1, -1, True, lines)

    # extmark methods

    def eol(self, line: int, content: str = "", hl_group: str = "Normal"):
        self.nvim.api.buf_set_extmark(
            self.buf.number,
            self.namespace,
            line,  # row
            0,  # col
            {
                "virt_text": [[content, hl_group]],
                "virt_text_pos": "eol",
            },
        )

    # mount methods

    def vsplit(self, opts: dict[str, Any] = {}):
        self.nvim.api.command(f"vsplit | buffer {self.buf.handle}")
        winnr = self.nvim.api.get_current_win()
        for opt, val in opts.items():
            self.nvim.api.win_set_option(winnr, opt, val)
