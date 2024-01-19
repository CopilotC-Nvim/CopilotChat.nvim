from dataclasses import dataclass


@dataclass
class Message:
    content: str
    role: str


@dataclass
class FileExtract:
    filepath: str
    code: str
