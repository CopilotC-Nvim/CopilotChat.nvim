from __future__ import annotations

from copy import deepcopy
from dataclasses import dataclass
from typing import TYPE_CHECKING, Any, Callable, Dict, Optional, Union, Unpack

if TYPE_CHECKING:
    from mypynvim.core.nvim import MyNvim

    from .layout import Layout


from mypynvim.core.buffer import MyBuffer
from mypynvim.core.window import MyWindow

from .calculator import Calculator
from .types import PaddingKeys, PopUpArgs, PopUpConfiguration, Relative


@dataclass
class Padding:
    top: int = 0
    right: int = 0
    bottom: int = 0
    left: int = 0


class PopUp:
    def __init__(
        self,
        nvim: MyNvim,
        preset: Optional[PopUpConfiguration] = None,
        padding: PaddingKeys = {},
        enter: bool = False,
        opts={},
        **kwargs: Unpack[PopUpArgs],
    ):
        self.nvim: MyNvim = nvim
        self.calculator: Calculator = Calculator(self.nvim)
        self.enter: bool = enter
        self.opts: Dict[str, Any] = opts

        # preset configuration
        if preset is None:
            preset = PopUpConfiguration()
        for key, value in kwargs.items():
            setattr(preset, key, value)
        self.original_config: PopUpConfiguration = preset

        # main window
        self.buffer: MyBuffer = MyBuffer.new(self.nvim)
        self._set_default_keymaps()
        self._set_default_autocmds()

        # padding window
        self.pd: Padding = Padding(**padding)
        self.pd_buffer: MyBuffer = MyBuffer.new(self.nvim)

    def mount(self, controlled: bool = False):
        """
        Mounts the PopUp.

        Resets the configuration to its original values when PopUp was instantiated.
        Then computes the absolute values for the configuration.
        Then mutate main window configuration & mounts the padding window if any padding is set.
        Then mounts the main window.
        """

        # reset config to original
        self.config: PopUpConfiguration = deepcopy(self.original_config)
        self.pd_config: PopUpConfiguration = PopUpConfiguration()

        if controlled:
            self._set_controlled_configurations()
        else:
            self._set_uncontrolled_configurations()

        # mount padding window if any padding is set
        if self._has_padding():
            pd_window = self.nvim.api.open_win(
                self.pd_buffer, False, self.pd_config.__dict__
            )
            self.pd_window = MyWindow(self.nvim, pd_window)
        # mount main window
        window = self.nvim.api.open_win(self.buffer, self.enter, self.config.__dict__)
        self.window = MyWindow(self.nvim, window)

        self._set_main_window_options()

    def unmount(self):
        """Unmounts the PopUp."""
        self.nvim.api.win_close(self.window, True)
        if self._has_padding():
            self.nvim.api.win_close(self.pd_window, True)

    def map(self, mode: str, key: str, rhs: Union[str, Callable]):
        """Maps a key to a function in the main window."""
        self.buffer.map(mode, key, rhs)

    def focus(self):
        """Make the popup active."""
        self.nvim.current.window = self.window

    def set_layout(self, layout: Layout):
        self.layout = layout

    def define_controlled_configurations(
        self, width: int, height: int, row: int, col: int, relative: Relative = "editor"
    ):
        self.controlled_config = deepcopy(self.original_config)
        self.controlled_config.width = width
        self.controlled_config.height = height
        self.controlled_config.row = row
        self.controlled_config.col = col
        self.controlled_config.relative = relative

    def _set_main_window_options(self):
        for key, value in self.opts.items():
            self.window.options[key] = value

    def _set_controlled_configurations(self):
        """Mutates the configuration of controlled PopUp."""
        self.config = self.controlled_config
        if self._has_padding():
            self._mutate_configurations_for_padding()

    def _set_uncontrolled_configurations(self):
        """Mutates the configuration of uncontrolled PopUp."""
        self.config = self.calculator.center(self.config)
        if self._has_padding():
            self._mutate_configurations_for_padding()

    def _has_padding(self) -> bool:
        return any([self.pd.top, self.pd.right, self.pd.bottom, self.pd.left])

    def _mutate_configurations_for_padding(self):
        """
        Mutates the configuration to account for padding.

        This is done by making the padding window takes place of the original window.
        (Effectively replacing the original window with the padding window)
        Then the original window is resized (shrinked) to fit within the padding window.
        """

        # set window config for padding window
        vars(self.pd_config).update(vars(self.config))

        # shrink content window
        self.config.title = ""
        self.config.width = int(self.config.width) - int(self.pd.left) - self.pd.right
        self.config.height = int(self.config.height) - int(self.pd.top) - self.pd.bottom
        self.config.row = int(self.config.row) + self.pd.top + 1
        self.config.col = int(self.config.col) + self.pd.left + 1
        self.config.border = "none"

    def _set_default_keymaps(self):
        self.buffer.map("n", "q", lambda: self.unmount())

    def _set_default_autocmds(self):
        self.buffer.autocmd(
            "BufEnter",
            "update_last_popup_for_Layout",
            lambda: self.layout.set_last_popup(self),
        )
