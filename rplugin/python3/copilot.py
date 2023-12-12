import requests
import dotenv
import os
import uuid
import time
import json

from prompt_toolkit import PromptSession
from prompt_toolkit.history import InMemoryHistory
import utilities
import typings


class Copilot:
    def __init__(self, token):
        self.github_token = token
        self.token: dict[str, any] = None
        self.chat_history: list[typings.Message] = []
        self.vscode_sessionid: str = None
        self.machineid = utilities.random_hex()

        self.session = requests.Session()

    def authenticate(self):
        self.vscode_sessionid = str(uuid.uuid4()) + str(round(time.time() * 1000))
        url = "https://api.github.com/copilot_internal/v2/token"
        headers = {
            "authorization": f"token {self.github_token}",
            "editor-version": "vscode/1.80.1",
            "editor-plugin-version": "copilot-chat/0.4.1",
            "user-agent": "GitHubCopilotChat/0.4.1",
        }

        self.token = self.session.get(url, headers=headers).json()

        # with aiohttp.ClientSession() as session:
        #     with session.get(url, headers=headers) as response:
        #         self.token = response.json()
        #         return self.token

    def ask(self, prompt: str, code: str, language: str = ""):
        url = "https://copilot-proxy.githubusercontent.com/v1/chat/completions"
        headers = {
            "authorization": f"Bearer {self.token['token']}",
            "x-request-id": str(uuid.uuid4()),
            "vscode-sessionid": self.vscode_sessionid,
            "machineid": self.machineid,
            "editor-version": "vscode/1.80.1",
            "editor-plugin-version": "copilot-chat/0.4.1",
            "openai-organization": "github-copilot",
            "openai-intent": "conversation-panel",
            "content-type": "application/json",
            "user-agent": "GitHubCopilotChat/0.4.1",
        }
        self.chat_history.append(typings.Message(prompt, "user"))
        data = utilities.generate_request(self.chat_history, code, language)

        full_response = ""

        # with aiohttp.ClientSession() as session:
        #     with session.post(url, headers=headers, json=data) as response:
        response = self.session.post(url, headers=headers, json=data, stream=True)
        for line in response.iter_lines():
            line = line.decode("utf-8").replace("data: ", "").strip()
            if line.startswith("[DONE]"):
                break
            elif line == "":
                continue
            try:
                line = json.loads(line)
                content = line["choices"][0]["delta"]["content"]
                if content is None:
                    continue
                full_response += content
                yield content
            except json.decoder.JSONDecodeError:
                print("Error:", line)
                continue

        self.chat_history.append(typings.Message(full_response, "system"))


def get_input(session: PromptSession, text: str = ""):
    print(text, end="", flush=True)
    return session.prompt(multiline=True)


def main():
    dotenv.load_dotenv()
    copilot = Copilot(os.getenv("GITHUB_TOKEN"))
    copilot.authenticate()
    session = PromptSession(history=InMemoryHistory())
    while True:
        user_prompt = get_input(session, "\n\nPrompt: \n")
        if user_prompt == "!exit":
            break
        code = get_input(session, "\n\nCode: \n")

        print("\n\nAI Response:")
        for response in copilot.ask(user_prompt, code):
            print(response, end="", flush=True)


if __name__ == "__main__":
    main()
