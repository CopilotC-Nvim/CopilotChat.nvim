import json

from mypynvim.core.nvim import MyNvim
from mypynvim.ui_components.layout import Layout, Box
from mypynvim.ui_components.popup import PopUp
from mypynvim.ui_components.types import PaddingKeys


class PriorityMatrix:
    def __init__(self, nvim: MyNvim):
        self.nvim = nvim

        padding: PaddingKeys = {"left": 1, "right": 1, "top": 1}
        self.do_popup = PopUp(
            nvim,
            title="Important and Urgent (Do)",
            enter=True,
            padding=padding,
            opts={"wrap": True},
        )
        self.schedule_popup = PopUp(
            nvim,
            title="Important but Not Urgent (Schedule)",
            padding=padding,
            opts={"wrap": True},
        )
        self.delegate_popup = PopUp(
            nvim,
            title="Not Important but Urgent (Delegate)",
            padding=padding,
            opts={"wrap": True},
        )
        self.eliminate_popup = PopUp(
            nvim,
            title="Not Important and Not Urgent (Eliminate)",
            padding=padding,
            opts={"wrap": True},
        )
        self.popups = [
            self.do_popup,
            self.schedule_popup,
            self.delegate_popup,
            self.eliminate_popup,
        ]

        self.layout = Layout(
            nvim,
            Box(
                [
                    Box(
                        [Box([self.do_popup]), Box([self.schedule_popup])],
                        size=["50%", "50%"],
                        direction="row",
                    ),
                    Box(
                        [Box([self.delegate_popup]), Box([self.eliminate_popup])],
                        size=["50%", "50%"],
                        direction="row",
                    ),
                ],
                size=["50%", "50%"],
                direction="col",
            ),
            width="50%",
            height="50%",
            relative="editor",
            row="50%",
            col="50%",
        )

        self.layout.post_first_mount_callback = self._load_priority_matrix

        self._add_popup_keymaps()
        self._add_popup_autocmds()

    def _load_priority_matrix(self):
        try:
            with open("priority_matrix.json", "r") as f:
                contents = json.load(f)

            for popup, content in zip(self.popups, contents):
                popup.buffer.lines(content)

        except Exception as err:
            self.nvim.notify(f"Error loading priority matrix: {err}")

    def _save_priority_matrix(self):
        contents = []
        for popup in self.popups:
            lines = popup.buffer.lines()
            contents.append("\n".join(lines))

        with open("priority_matrix.json", "w") as f:
            json.dump(contents, f)

    def _add_popup_autocmds(self):
        self.do_popup.buffer.autocmd(
            ["WinClosed"],
            "save_priority_matrix",
            lambda: self._save_priority_matrix(),
        )

    def _add_popup_keymaps(self):
        self.do_popup.map("n", "<C-h>", "<Nop>")
        self.do_popup.map("n", "<C-j>", lambda: self.delegate_popup.focus())
        self.do_popup.map("n", "<C-k>", "<Nop>")
        self.do_popup.map("n", "<C-l>", lambda: self.schedule_popup.focus())

        self.schedule_popup.map("n", "<C-h>", lambda: self.do_popup.focus())
        self.schedule_popup.map("n", "<C-j>", lambda: self.eliminate_popup.focus())
        self.schedule_popup.map("n", "<C-k>", "<Nop>")
        self.schedule_popup.map("n", "<C-l>", "<Nop>")

        self.delegate_popup.map("n", "<C-h>", "<Nop>")
        self.delegate_popup.map("n", "<C-j>", "<Nop>")
        self.delegate_popup.map("n", "<C-k>", lambda: self.do_popup.focus())
        self.delegate_popup.map("n", "<C-l>", lambda: self.eliminate_popup.focus())

        self.eliminate_popup.map("n", "<C-h>", lambda: self.delegate_popup.focus())
        self.eliminate_popup.map("n", "<C-j>", "<Nop>")
        self.eliminate_popup.map("n", "<C-k>", lambda: self.schedule_popup.focus())
        self.eliminate_popup.map("n", "<C-l>", "<Nop>")

        for i, popup in enumerate(self.popups):
            popup.buffer.map("n", "q", lambda: self.layout.unmount())
            popup.buffer.map(
                "n",
                "<Tab>",
                lambda i=i: self.popups[(i + 1) % len(self.popups)].focus(),
            )
            popup.buffer.map(
                ["n", "x", "i"],
                "<C-s>",
                lambda: (
                    self.nvim.feed("<Esc>"),
                    self._save_priority_matrix(),
                    # self.nvim.notify("Saved Priority Matrix!"),
                ),
            )
