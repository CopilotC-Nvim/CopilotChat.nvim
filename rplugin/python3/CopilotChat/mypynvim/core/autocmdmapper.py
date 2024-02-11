from __future__ import annotations

from typing import TYPE_CHECKING, Callable, Union

if TYPE_CHECKING:
    from CopilotChat.mypynvim.core.nvim import MyNvim


class AutocmdMapper:
    def __init__(self, nvim: MyNvim):
        self.nvim: MyNvim = nvim
        self._autocmd_callback_library = {}

    def buf_set(
        self,
        events: Union[str, list[str]],
        id: str,
        bufnr: int,
        callback: Callable,
    ):
        if isinstance(events, str):
            events = [events]

        for e in events:
            if not self._autocmd_callback_library.get(e):
                self._autocmd_callback_library[e] = {}

            if not self._autocmd_callback_library[e].get(id):
                self._autocmd_callback_library[e][id] = {}

            self._autocmd_callback_library[e][id][str(bufnr)] = callback

            self.nvim.api.create_autocmd(
                e,
                {
                    "buffer": bufnr,
                    "command": f"{self.nvim._autocmd_command} {e} {id} {bufnr}",
                },
            )

    def execute(self, event: str, id: str, bufnr: int):
        try:
            self._autocmd_callback_library[event][id][bufnr]()
        except KeyError:
            self.nvim.notify(f"KeyError: {event} {id} {bufnr}")
