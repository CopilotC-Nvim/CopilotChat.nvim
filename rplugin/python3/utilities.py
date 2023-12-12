import prompts
import typings
import random
import os
import json


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


def cache_token(user: str, token: str):
    # ~/.config/github-copilot/hosts.json
    home = os.path.expanduser("~")
    config_dir = os.path.join(home, ".config", "github-copilot")
    if not os.path.exists(config_dir):
        os.makedirs(config_dir)
    with open(os.path.join(config_dir, "hosts.json"), "w") as f:
        f.write(json.dumps({
            "github.com": {
                "user": user,
                "oauth_token": token,
            }
        }))


def get_cached_token():
    home = os.path.expanduser("~")
    config_dir = os.path.join(home, ".config", "github-copilot")
    hosts_file = os.path.join(config_dir, "hosts.json")
    if not os.path.exists(hosts_file):
        return None
    with open(hosts_file, "r") as f:
        hosts = json.loads(f.read())
        if "github.com" in hosts:
            return hosts["github.com"]["oauth_token"]
        else:
            return None


if __name__ == "__main__":

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
