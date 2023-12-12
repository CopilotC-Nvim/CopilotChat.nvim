import prompts
import typings
import random


def random_hex(length: int = 65):
    return "".join([random.choice("0123456789abcdef") for _ in range(length)])


def generate_request(
    chat_history: list[typings.Message], code_excerpt: str, language: str = ""
):
    messages = [
        {
            "content": prompts.COPILOT_INSTRUCTIONS,
            "role": "system",
        }
    ]
    for message in chat_history:
        messages.append(
            {
                "content": message.content,
                "role": message.role,
            }
        )
    if code_excerpt != "":
        messages.insert(
            -1,
            {
                "content": f"\nActive selection:\n```{language}\n{code_excerpt}\n```",
                "role": "system",
            },
        )
    return {
        "intent": True,
        "model": "copilot-chat",
        "n": 1,
        "stream": True,
        "temperature": 0.1,
        "top_p": 1,
        "messages": messages,
    }


if __name__ == "__main__":
    import json

    print(
        json.dumps(
            generate_request(
                [
                    typings.Message("Hello, Copilot!", "user"),
                    typings.Message("Hello, World!", "system"),
                    typings.Message("How are you?", "user"),
                    typings.Message("I am fine, thanks.", "system"),
                    typings.Message("What does this code do?", "user"),
                ],
                "print('Hello, World!')",
                "python",
            ),
            indent=2,
        )
    )
