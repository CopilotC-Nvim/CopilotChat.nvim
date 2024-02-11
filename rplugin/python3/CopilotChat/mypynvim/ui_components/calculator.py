from __future__ import annotations

from dataclasses import dataclass
from typing import TYPE_CHECKING, Literal, Union

from CopilotChat.mypynvim.core.nvim import MyNvim

if TYPE_CHECKING:
    from CopilotChat.mypynvim.ui_components.popup import PopUpConfiguration


@dataclass
class Calculator:
    nvim: "MyNvim"

    def absolute(self, config: PopUpConfiguration) -> PopUpConfiguration:
        return self._convert_relative_values_to_absolute(config)

    def center(self, config: PopUpConfiguration) -> PopUpConfiguration:
        config = self._convert_relative_values_to_absolute(config)
        config = self._center_configuration_row_col(config)
        return config

    def _center_configuration_row_col(self, config: PopUpConfiguration):
        """Centers the row and col properties based on width and height."""
        if config.relative in ["editor", "win"]:
            config.row = int(config.row) - int(config.height) // 2 - 1
            config.col = int(config.col) - int(config.width) // 2 - 1
        return config

    def _convert_relative_values_to_absolute(self, config: PopUpConfiguration):
        """Converts relative values to absolute values."""
        for property in ["width", "height", "row", "col"]:
            current_value = getattr(config, property)
            absolute_value = self._percentage_to_absolute(
                current_value, config.relative, property
            )
            setattr(config, property, absolute_value)
        return config

    def _percentage_to_absolute(
        self,
        value: Union[int, str],
        relative: Literal["editor", "win", "cursor"],
        property: str,
    ) -> int:
        """
        Converts percentage string values to absolute int values.
        If the value is already an int, it is returned as is.
        """

        if isinstance(value, int):
            return value

        max = self._get_max_value_for_property(relative, property)
        return int(int(value.rstrip("%")) / 100.0 * max)

    def _get_max_value_for_property(
        self, relative: Literal["editor", "win", "cursor"], property: str
    ) -> int:
        """Based on relative configuration, returns the max value for a given property."""

        def get_editor_dimensions():
            source = self.nvim.options
            width, height = source["columns"], source["lines"]
            return {"row": height, "col": width, "width": width, "height": height}

        def get_window_dimensions():
            source = self.nvim.current.window
            width, height = source.width, source.height
            return {"row": height, "col": width, "width": width, "height": height}

        max_values = {
            "editor": get_editor_dimensions(),
            "win": get_window_dimensions(),
            "cursor": get_window_dimensions(),
        }
        return max_values[relative][property]
