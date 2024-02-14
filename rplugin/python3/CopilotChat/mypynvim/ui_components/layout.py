from dataclasses import dataclass
from typing import Callable, Literal, Optional, Union, cast

from CopilotChat.mypynvim.core.nvim import MyNvim
from CopilotChat.mypynvim.ui_components.calculator import Calculator
from CopilotChat.mypynvim.ui_components.popup import PopUp
from CopilotChat.mypynvim.ui_components.types import PopUpConfiguration, Relative


class Box:
    width: int = 0
    height: int = 0
    row: int = 0
    col: int = 0
    relative: Relative = "editor"

    def __init__(
        self,
        items: Union[list["Box"], list[PopUp]],
        size: list[str] = ["100%"],
        direction: Literal["row", "col"] = "row",
        gap: int = 0,
    ):
        """Initialize a Box with items, size, direction and gap."""
        self.size = size
        self.direction = direction
        self.items = items
        self.gap = gap

    def set_base_dimensions(
        self, width: int, height: int, row: int, col: int, relative: Relative
    ):
        """Set the base dimensions of the Box."""
        self.width = width
        self.height = height
        self.row = row
        self.col = col
        self.relative = relative

        self.last_child_row = row
        self.last_child_col = col

    def mount(self):
        """Mount the Box."""
        if self._has_box_items():
            for child in self.items:
                cast(Box, child).mount()
        elif self._has_popup_items():
            for child in self.items:
                cast(PopUp, child).mount(controlled=True)

    def unmount(self):
        """Unmount the Box."""
        for child in self.items:
            child.unmount()

    def process(self):
        """Process the Box."""
        for child in self.items:
            child.set_layout(self.layout)

        self._process_size()
        if self._has_box_items():
            self._process_box_items()
        if self._has_popup_items():
            self._process_popup_items()

    def set_layout(self, layout: "Layout"):
        self.layout = layout

    def _process_size(self):
        """Compute the Box size to integers."""
        for index, size in enumerate(self.size):
            if isinstance(size, str):
                self.size[index] = size.rstrip("%")

    def _process_box_items(self):
        """Process the Box items."""
        if self.direction == "row":
            self._process_row_box_items()
        elif self.direction == "col":
            self._process_col_box_items()

        for child in self.items:
            cast(Box, child).process()

    def _process_row_box_items(self):
        """Process the row box items."""
        for index, child in enumerate(self.items):
            offset = 0 if index == len(self.items) else self.gap + 2
            child_width = int(self.width / 100 * int(self.size[index])) - offset
            child_col = self.last_child_col + (offset * index)
            self.last_child_col = child_col + child_width - (offset * index)
            cast(Box, child).set_base_dimensions(
                width=child_width,
                height=self.height,
                row=self.row,
                col=child_col,
                relative=self.relative,
            )

    def _process_col_box_items(self):
        """Process the column box items."""
        for index, child in enumerate(self.items):
            offset = 0 if index == len(self.items) else self.gap + 2
            child_height = int(self.height / 100 * int(self.size[index])) - offset + 1
            child_row = self.last_child_row + (offset * index)
            self.last_child_row = child_row + child_height - (offset * index)
            cast(Box, child).set_base_dimensions(
                width=self.width,
                height=child_height,
                row=child_row,
                col=self.col,
                relative=self.relative,
            )

    def _process_popup_items(self):
        """Process the PopUp items."""
        for child in self.items:
            cast(PopUp, child).define_controlled_configurations(
                width=self.width,
                height=self.height,
                row=self.row,
                col=self.col,
                relative=self.relative,
            )

    def _has_box_items(self) -> bool:
        """Check if the Box has Box items."""
        return isinstance(self.items, list) and all(
            isinstance(item, Box) for item in self.items
        )

    def _has_popup_items(self) -> bool:
        """Check if the Box has PopUp items."""
        return isinstance(self.items, list) and all(
            isinstance(item, PopUp) for item in self.items
        )


@dataclass
class Layout:
    nvim: MyNvim
    box: Box
    width: Union[int, str]
    height: Union[int, str]
    row: Union[int, str]
    col: Union[int, str]
    relative: Relative = "editor"

    last_popup: Optional[PopUp] = None

    mounting: bool = False
    unmounting: bool = False

    has_been_mounted: bool = False
    post_first_mount_callback: Optional[Callable] = None

    def _prepare_for_mount(self):
        self._configure_popup()
        self._calculate_absolute_config()
        self._set_box_base_dimensions()
        self.box.set_layout(self)
        self.box.process()

    def _configure_popup(self):
        self.config = PopUpConfiguration(
            width=self.width,
            height=self.height,
            row=self.row,
            col=self.col,
            relative=self.relative,
        )

    def _calculate_absolute_config(self):
        self.absolute_config = Calculator(self.nvim).center(self.config)

    def _set_box_base_dimensions(self):
        self.box.set_base_dimensions(
            width=int(self.absolute_config.width),
            height=int(self.absolute_config.height),
            row=int(self.absolute_config.row),
            col=int(self.absolute_config.col),
            relative=self.relative,
        )

    def mount(self):
        """Mount the Layout. Focus the last popup if any."""
        self.mounting = True
        self._prepare_for_mount()
        self.box.mount()
        self.mounting = False

        if not self.has_been_mounted:
            self.has_been_mounted = True
            if self.post_first_mount_callback:
                self.post_first_mount_callback()

        if self.last_popup:
            self.last_popup.focus()

    def unmount(self):
        """Unmount the Layout."""
        self.unmounting = True
        self.box.unmount()
        self.unmounting = False

    def set_last_popup(self, popup: PopUp):
        if not self.mounting and not self.unmounting:
            self.last_popup = popup
