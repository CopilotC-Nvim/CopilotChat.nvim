from mypynvim.core.nvim import MyNvim
from mypynvim.core.buffer import MyBuffer
from mypynvim.ui_components.popup import PopUp
from mypynvim.ui_components.layout import Layout, Box
from handlers.chat_handler import ChatHandler
from . import prompts

SYSTEM_PROMPT = """
You're a 10x senior developer that is an expert in programming.
Your job is to change the user's code according to their needs.
Your job is only to change / edit the code.
Your code output should keep the same level of indentation as the user's code.
You MUST add whitespace in the beginning of each line as needed to match the user's code.
"""


class InPlaceChatHandler:
    """This class handles in-place chat functionality."""

    original_code: str = ""
    filetype: str = ""
    diff_mode: bool = False
    range: list[int] = [0, -1]
    model: str = "gpt-4"

    def __init__(self, nvim: MyNvim):
        """Initialize the InPlaceChatHandler with the given nvim instance."""
        self.nvim: MyNvim = nvim

        self.original_popup = PopUp(nvim, title="Original")
        self.copilot_popup = PopUp(
            nvim,
            title=f"Copilot ({self.model})",
            opts={"wrap": True, "linebreak": True},
        )
        self.prompt_popup = PopUp(
            nvim, title="Prompt", enter=True, padding={"left": 1, "right": 1}
        )
        self.popups = [self.original_popup, self.copilot_popup, self.prompt_popup]

        self.layout = Layout(
            nvim,
            Box(
                [
                    Box(
                        [Box([self.original_popup]), Box([self.copilot_popup])],
                        size=["50%", "50%"],
                        direction="row",
                    ),
                    Box(
                        [self.prompt_popup],
                    ),
                ],
                size=["80%", "20%"],
                direction="col",
            ),
            width="75%",
            height="50%",
            relative="editor",
            row="50%",
            col="50%",
        )

        self.chat_handler = ChatHandler(nvim, self.copilot_popup.buffer)

        self._set_keymaps()

    def mount(
        self, original_code: str, filetype: str, range: list[int], user_buffer: MyBuffer
    ):
        """Mount the chat handler with the given parameters."""
        self.original_code = original_code
        self.filetype = filetype
        self.range = [range[0] - 1, range[1]]
        self.user_buffer = user_buffer

        self.original_popup.buffer.lines(original_code)
        self.original_popup.buffer.options["filetype"] = filetype

        self.copilot_popup.buffer.options["filetype"] = "markdown"

        self.layout.mount()

    def _replace_original_code(self):
        """Replace the original code with the new code."""
        new_lines = self.copilot_popup.buffer.lines()
        if new_lines[0].startswith("```"):
            new_lines = new_lines[1:-1]
        self.user_buffer.lines(new_lines, self.range[0], self.range[1])
        self.layout.unmount()
        self.nvim.command("norm! ^")

    def _diff(self):
        """Show the difference between the original code and the new code."""
        if not self.diff_mode:
            self.original_popup.window.command("diffthis")
            self.copilot_popup.window.command("diffthis")
            self.diff_mode = True
        else:
            self.original_popup.window.command("diffoff")
            self.diff_mode = False

    def _chat(self):
        """Start a chat session."""
        self.copilot_popup.buffer.lines("")
        self.copilot_popup.window.command("norm! gg")
        prompt_lines = self.prompt_popup.buffer.lines()
        prompt = "\n".join(prompt_lines)
        self.chat_handler.chat(
            prompt,
            self.filetype,
            self.original_code,
            self.copilot_popup.window.handle,
            system_prompt=SYSTEM_PROMPT,
            disable_start_separator=True,
            disable_end_separator=True,
            model=self.model,
        )

    def _set_prompt(self, prompt: str):
        self.prompt_popup.buffer.lines(prompt)

    def _toggle_model(self):
        if self.model == "gpt-4":
            self.model = "gpt-3.5-turbo"
        else:
            self.model = "gpt-4"
        self.copilot_popup.original_config.title = f"Copilot ({self.model})"
        self.copilot_popup.config.title = f"Copilot ({self.model})"
        self.copilot_popup.unmount()
        self.copilot_popup.mount(controlled=True)

    def _set_keymaps(self):
        """Set the keymaps for the chat handler."""
        self.prompt_popup.map("n", "<CR>", lambda: self._chat())
        self.prompt_popup.map("n", "<C-CR>", lambda: self._replace_original_code())
        self.prompt_popup.map("n", "<C-d>", lambda: self._diff())
        self.prompt_popup.map("n", "<C-g>", lambda cb=self._toggle_model: cb())

        self.prompt_popup.map(
            "n", "'", lambda: self._set_prompt(prompts.PROMPT_SIMPLE_DOCSTRING)
        )
        self.prompt_popup.map(
            "n", "s", lambda: self._set_prompt(prompts.PROMPT_SEPARATE)
        )

        self.prompt_popup.map(
            "i", "<C-s>", lambda: (self.nvim.feed("<Esc>"), self._chat())
        )

        for i, popup in enumerate(self.popups):
            popup.buffer.map("n", "q", lambda: self.layout.unmount())
            popup.buffer.map(
                "n",
                "<Tab>",
                lambda i=i: self.popups[(i + 1) % len(self.popups)].focus(),
            )
