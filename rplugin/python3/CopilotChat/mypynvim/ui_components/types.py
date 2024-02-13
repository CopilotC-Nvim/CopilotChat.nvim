from dataclasses import dataclass
from typing import Dict, Literal, TypedDict, Union

Relative = Literal["editor", "win", "cursor"]
PaddingKeys = Dict[Literal["top", "right", "bottom", "left"], int]


@dataclass
class PopUpConfiguration:
    relative: Relative = "editor"
    anchor: Literal["NW", "NE", "SW", "SE"] = "NW"
    width: Union[int, str] = 40
    height: Union[int, str] = 10
    row: Union[int, str] = 0
    col: Union[int, str] = 0
    zindex: int = 500
    style: Literal["minimal"] = "minimal"
    border: Union[
        list[str],
        Literal["none", "single", "double", "solid", "shadow", "background"],
    ] = "single"
    title: str = ""
    title_pos: Literal["left", "center", "right"] = "center"
    noautocmd: bool = False


class PopUpArgs(TypedDict, total=False):
    relative: Relative
    anchor: Literal["NW", "NE", "SW", "SE"]
    width: Union[int, str]
    height: Union[int, str]
    row: Union[int, str]
    col: Union[int, str]
    zindex: int
    style: Literal["minimal"]
    border: Union[
        list[str],
        Literal["none", "single", "double", "solid", "shadow", "background"],
    ]
    title: str
    title_pos: Literal["left", "center", "right"]
    noautocmd: bool
