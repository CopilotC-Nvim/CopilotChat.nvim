import CopilotChat.prompts as system_prompts
from CopilotChat.handlers.chat_handler import ChatHandler
from CopilotChat.mypynvim.core.buffer import MyBuffer
from CopilotChat.mypynvim.core.nvim import MyNvim
from CopilotChat.mypynvim.ui_components.layout import Box, Layout
from CopilotChat.mypynvim.ui_components.popup import PopUp

# Define constants for the models
MODEL_GPT4 = "gpt-4"
MODEL_GPT35_TURBO = "gpt-3.5-turbo"


# TODO: change the layout, e.g: move to right side of the screen
class InPlaceChatHandler:
    """This class handles in-place chat functionality."""

    def __init__(self, nvim: MyNvim):
        """Initialize the InPlaceChatHandler with the given nvim instance."""
        self.nvim: MyNvim = nvim
        self.diff_mode: bool = False
        self.model: str = MODEL_GPT4
        self.system_prompt: str = "SENIOR_DEVELOPER_PROMPT"
        self.language = self.nvim.eval("g:copilot_chat_language")

        # Add user prompts collection
        self.user_prompts = self.nvim.eval("g:copilot_chat_user_prompts")
        self.current_user_prompt = 0

        # Initialize popups
        self.original_popup = PopUp(nvim, title="Original")
        self.copilot_popup = PopUp(
            nvim,
            title=f"Copilot ({self.model}, {self.system_prompt})",
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
            system_prompt=system_prompts.__dict__[self.system_prompt],
            disable_start_separator=True,
            disable_end_separator=True,
            model=self.model,
        )

    def _set_prompt(self, prompt: str):
        self.prompt_popup.buffer.lines(prompt)

    def _set_next_user_prompt(self):
        self.current_user_prompt = (self.current_user_prompt + 1) % len(
            self.user_prompts
        )
        prompt = list(self.user_prompts.keys())[self.current_user_prompt]
        self.prompt_popup.buffer.lines(self.user_prompts[prompt])

    def _set_previous_user_prompt(self):
        self.current_user_prompt = (self.current_user_prompt - 1) % len(
            self.user_prompts
        )
        prompt = list(self.user_prompts.keys())[self.current_user_prompt]
        self.prompt_popup.buffer.lines(self.user_prompts[prompt])

    def _toggle_model(self):
        if self.model == MODEL_GPT4:
            self.model = MODEL_GPT35_TURBO
        else:
            self.model = MODEL_GPT4
        self.copilot_popup.original_config.title = (
            f"Copilot ({self.model}, {self.system_prompt})"
        )
        self.copilot_popup.config.title = (
            f"Copilot ({self.model}, {self.system_prompt})"
        )
        self.copilot_popup.unmount()
        self.copilot_popup.mount(controlled=True)

    def _toggle_system_model(self):
        # Create a list of all system prompts and add the current system prompt
        system_prompts = [
            "SENIOR_DEVELOPER_PROMPT",
            "COPILOT_EXPLAIN",
            "COPILOT_TESTS",
            "COPILOT_FIX",
            "COPILOT_WORKSPACE",
            "TEST_SHORTCUT",
            "EXPLAIN_SHORTCUT",
            "FIX_SHORTCUT",
        ]

        # Get the index of the current system prompt
        current_system_prompt_index = system_prompts.index(self.system_prompt)

        # Set the next system prompt
        self.system_prompt = system_prompts[
            (current_system_prompt_index + 1) % len(system_prompts)
        ]

        self.copilot_popup.original_config.title = (
            f"Copilot ({self.model}, {self.system_prompt})"
        )
        self.copilot_popup.config.title = (
            f"Copilot ({self.model}, {self.system_prompt})"
        )
        self.copilot_popup.unmount()
        self.copilot_popup.mount(controlled=True)

    # TODO: Add custom keymaps for in-place chat as suggestion here https://discord.com/channels/1200633211236122665/1200633212041449606/1208065809285382164
    def _set_keymaps(self):
        """Set the keymaps for the chat handler."""
        self.prompt_popup.map("n", "<CR>", lambda: self._chat())
        self.prompt_popup.map("n", "<C-CR>", lambda: self._replace_original_code())
        self.prompt_popup.map("n", "<C-d>", lambda: self._diff())
        self.prompt_popup.map("n", "<C-g>", lambda cb=self._toggle_model: cb())
        self.prompt_popup.map("n", "<C-m>", lambda cb=self._toggle_system_model: cb())

        self.prompt_popup.map(
            "n", "'", lambda: self._set_prompt(system_prompts.PROMPT_SIMPLE_DOCSTRING)
        )
        self.prompt_popup.map(
            "n", "s", lambda: self._set_prompt(system_prompts.PROMPT_SEPARATE)
        )

        self.prompt_popup.map(
            "i", "<C-s>", lambda: (self.nvim.feed("<Esc>"), self._chat())
        )

        self.prompt_popup.map(
            "n",
            "<C-n>",
            lambda: self._set_next_user_prompt(),
        )

        self.prompt_popup.map(
            "n",
            "<C-p>",
            lambda: self._set_previous_user_prompt(),
        )

        for i, popup in enumerate(self.popups):
            popup.buffer.map("n", "q", lambda: self.layout.unmount())
            popup.buffer.map("n", "<C-l>", lambda: self._clear_chat_history())
            popup.buffer.map("n", "?", lambda: self._toggle_help())
            popup.buffer.map(
                "n",
                "<Tab>",
                lambda i=i: self.popups[(i + 1) % len(self.popups)].focus(),
            )

    def _clear_chat_history(self):
        """Clear the chat history in the copilot popup."""
        self.copilot_popup.buffer.lines([])

    def _set_help_content(self):
        """Set the content for the help popup."""
        help_content = [
            "Navigation:",
            "  <Tab>: Switch focus between popups",
            "  q: Close layout",
            "  ?: Toggle help content",
            "",
            "Chat in Normal Mode:",
            "  <CR>: Submit prompt to Copilot",
            "  <C-CR>: Replace old code with new",
            "  <C-d>: Show code differences",
            "  <C-l>: Clear chat history",
            "",
            "Chat in Insert Mode:",
            "  <C-s>: Start chat and submit prompt to Copilot",
            "",
            "Prompt Binding:",
            "  ': Set prompt to SIMPLE_DOCSTRING",
            "  s: Set prompt to SEPARATE",
            "  <C-p>: Get the previous user prompt",
            "  <C-n>: Set prompt to next item in user prompts",
            "",
            "Model:",
            "  <C-g>: Toggle AI model",
            "  <C-m>: Set system prompt to next item in system prompts",
            "",
            "User prompts:",
        ]

        for prompt in self.user_prompts:
            help_content.append(f"  {prompt}: {self.user_prompts[prompt]}")

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
