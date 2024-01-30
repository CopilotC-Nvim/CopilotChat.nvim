from handlers.chat_handler import ChatHandler
from mypynvim.core.buffer import MyBuffer
from mypynvim.core.nvim import MyNvim
from mypynvim.ui_components.layout import Box, Layout
from mypynvim.ui_components.popup import PopUp

from . import prompts

SYSTEM_PROMPT = """
You're a 10x senior developer that is an expert in programming.
Your job is to change the user's code according to their needs.
Your job is only to change / edit the code.
Your code output should keep the same level of indentation as the user's code.
You MUST add whitespace in the beginning of each line as needed to match the user's code.
"""


# This is not working yet! It's a work in progress.
# TODO: clear chat history
# TODO: change the layout, e.g: move to right side of the screen
class InPlaceChatHandler:
    """This class handles in-place chat functionality."""

    def __init__(self, nvim: MyNvim):
        """Initialize the InPlaceChatHandler with the given nvim instance."""
        self.nvim: MyNvim = nvim
        self.diff_mode: bool = False
        self.model: str = "gpt-4"

        # Initialize popups
        self.original_popup = PopUp(nvim, title="Original")
        self.copilot_popup = PopUp(
            nvim,
            title=f"Copilot ({self.model})",
            opts={"wrap": True, "linebreak": True},
        )
        self.prompt_popup = PopUp(
            nvim, title="Prompt", enter=True, padding={"left": 1, "right": 1}
        )
        self.help_popup = PopUp(nvim, title="Help")

        self.popups = [
            self.original_popup,
            self.copilot_popup,
            self.prompt_popup,
        ]

        # Initialize layout base on help text option
        self.help_popup_visible = self.nvim.eval("g:copilot_chat_show_help") == "yes"
        if self.help_popup_visible:
            self.layout = self._create_layout()
            self.popups.append(self.help_popup)
        else:
            self.layout = self._create_layout_without_help()

        # Initialize chat handler
        self.chat_handler = ChatHandler(nvim, self.copilot_popup.buffer)

        # Set keymaps and help content

        self._set_keymaps()
        self._set_help_content()

    def _create_layout(self):
        """Create the layout for the chat handler."""
        return Layout(
            self.nvim,
            Box(
                [
                    Box(
                        [
                            Box([self.original_popup]),
                            Box([self.copilot_popup]),
                        ],
                        size=["50%", "50%"],
                        direction="row",
                    ),
                    Box(
                        [Box([self.prompt_popup]), Box([self.help_popup])],
                        size=["50%", "50%"],
                        direction="row",
                    ),
                ],
                size=["80%", "20%"],
                direction="col",
            ),
            width="80%",
            height="60%",
            relative="editor",
            row="50%",
            col="50%",
        )

    def _create_layout_without_help(self):
        """Create the layout with help for the chat handler."""
        return Layout(
            self.nvim,
            Box(
                [
                    Box(
                        [
                            Box([self.original_popup]),
                            Box([self.copilot_popup]),
                        ],
                        size=["50%", "50%"],
                        direction="row",
                    ),
                    Box(
                        [Box([self.prompt_popup]), Box([])],
                        size=["100%", "0%"],
                        direction="row",
                    ),
                ],
                size=["80%", "20%"],
                direction="col",
            ),
            width="80%",
            height="60%",
            relative="editor",
            row="50%",
            col="50%",
        )

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
            popup.buffer.map("n", "<C-h>", lambda: self._toggle_help())
            popup.buffer.map(
                "n",
                "<Tab>",
                lambda i=i: self.popups[(i + 1) % len(self.popups)].focus(),
            )

    def _set_help_content(self):
        """Set the content for the help popup."""
        help_content = [
            "<CR>: Start a chat session",
            "<C-CR>: Replace the original code with the new code",
            "<C-d>: Show the difference between the original code and the new code",
            "<C-g>: Toggle the model",
            "': Set the prompt to PROMPT_SIMPLE_DOCSTRING",
            "s: Set the prompt to PROMPT_SEPARATE",
            "<C-s>: Start a chat session in insert mode",
            "<C-h>: Toggle the help popup",
            "q: Close the layout",
            "<Tab>: Switch focus between popups",
        ]
        self.help_popup.buffer.lines(help_content)

    def _toggle_help(self):
        """Toggle the visibility of the help popup."""
        self.layout.unmount()
        if self.help_popup_visible:
            self.popups = [
                self.original_popup,
                self.copilot_popup,
                self.prompt_popup,
            ]
            self.layout = self._create_layout_without_help()
        else:
            self.popups = [
                self.original_popup,
                self.copilot_popup,
                self.prompt_popup,
                self.help_popup,
            ]
            self.layout = self._create_layout()

        self.help_popup_visible = not self.help_popup_visible
        self._set_keymaps()
        self.layout.mount()
