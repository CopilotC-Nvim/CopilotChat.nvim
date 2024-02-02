import json
import os
import time
import uuid
from typing import Dict, List

import dotenv
import prompts
import requests
import typings
import utilities
from prompt_toolkit import PromptSession
from prompt_toolkit.history import InMemoryHistory

LOGIN_HEADERS = {
    "accept": "application/json",
    "content-type": "application/json",
    "editor-version": "Neovim/0.9.2",
    "editor-plugin-version": "copilot.lua/1.11.4",
    "user-agent": "GithubCopilot/1.133.0",
}


class Copilot:
    def __init__(self, token: str = None):
        if token is None:
            token = utilities.get_cached_token()
        self.github_token = token
        self.token: Dict[str, any] = None
        self.chat_history: List[typings.Message] = []
        self.vscode_sessionid: str = None
        self.machineid = utilities.random_hex()

        self.session = requests.Session()

    def request_auth(self):
        url = "https://github.com/login/device/code"

        response = self.session.post(
            url,
            headers=LOGIN_HEADERS,
            data=json.dumps(
                {"client_id": "Iv1.b507a08c87ecfe98", "scope": "read:user"}
            ),
        ).json()
        return response

    def poll_auth(self, device_code: str) -> bool:
        url = "https://github.com/login/oauth/access_token"

        response = self.session.post(
            url,
            headers=LOGIN_HEADERS,
            data=json.dumps(
                {
                    "client_id": "Iv1.b507a08c87ecfe98",
                    "device_code": device_code,
                    "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
                }
            ),
        ).json()
        if "access_token" in response:
            access_token, token_type = response["access_token"], response["token_type"]
            url = "https://api.github.com/user"
            headers = {
                "authorization": f"{token_type} {access_token}",
                "user-agent": "GithubCopilot/1.133.0",
                "accept": "application/json",
            }
            response = self.session.get(url, headers=headers).json()
            utilities.cache_token(response["login"], access_token)
            self.github_token = access_token
            return True
        return False

    def authenticate(self):
        if self.github_token is None:
            raise Exception("No token found")
        self.vscode_sessionid = str(uuid.uuid4()) + str(round(time.time() * 1000))
        url = "https://api.github.com/copilot_internal/v2/token"
        headers = {
            "authorization": f"token {self.github_token}",
            "editor-version": "vscode/1.85.1",
            "editor-plugin-version": "copilot-chat/0.12.2023120701",
            "user-agent": "GitHubCopilotChat/0.12.2023120701",
        }

        self.token = self.session.get(url, headers=headers).json()

    def ask(
        self,
        system_prompt: str,
        prompt: str,
        code: str,
        language: str = "",
        model: str = "gpt-4",
    ):
        if not self.token:
            self.authenticate()
        # If expired, reauthenticate
        if self.token.get("expires_at") <= round(time.time()):
            self.authenticate()

        if not system_prompt:
            system_prompt = prompts.COPILOT_INSTRUCTIONS
        url = "https://api.githubcopilot.com/chat/completions"
        self.chat_history.append(typings.Message(prompt, "user"))
        data = utilities.generate_request(
            self.chat_history, code, language, system_prompt=system_prompt, model=model
        )

        full_response = ""

        response = self.session.post(
            url, headers=self._headers(), json=data, stream=True
        )
        if response.status_code != 200:
            error_messages = {
                401: "Unauthorized. Make sure you have access to Copilot Chat.",
                500: "Internal server error. Please try again later.",
                400: "The developer of this plugin has made a mistake. Please report this issue.",
                419: "You have been rate limited. Please try again later.",
            }
            raise Exception(
                error_messages.get(
                    response.status_code, f"Unknown error: {response.status_code}"
                )
            )
        for line in response.iter_lines():
            line = line.decode("utf-8").replace("data: ", "").strip()
            if line.startswith("[DONE]"):
                break
            elif line == "":
                continue
            try:
                line = json.loads(line)
                if "choices" not in line:
                    print("Error:", line)
                    raise Exception(f"No choices on {line}")
                if len(line["choices"]) == 0:
                    continue
                content = line["choices"][0]["delta"]["content"]
                if content is None:
                    continue
                full_response += content
                yield content
            except json.decoder.JSONDecodeError:
                print("Error:", line)
                continue

        self.chat_history.append(typings.Message(full_response, "system"))

    def _get_embeddings(self, inputs: list[typings.FileExtract]):
        embeddings = []
        url = "https://api.githubcopilot.com/embeddings"
        # If we have more than 18 files, we need to split them into multiple requests
        for i in range(0, len(inputs), 18):
            if i + 18 > len(inputs):
                data = utilities.generate_embedding_request(inputs[i:])
            else:
                data = utilities.generate_embedding_request(inputs[i : i + 18])
            response = self.session.post(url, headers=self._headers(), json=data).json()
            if "data" not in response:
                raise Exception(f"Error fetching embeddings: {response}")
            for embedding in response["data"]:
                embeddings.append(embedding["embedding"])
        return embeddings

    def _headers(self):
        return {
            "authorization": f"Bearer {self.token['token']}",
            "x-request-id": str(uuid.uuid4()),
            "vscode-sessionid": self.vscode_sessionid,
            "machineid": self.machineid,
            "editor-version": "vscode/1.85.1",
            "editor-plugin-version": "copilot-chat/0.12.2023120701",
            "openai-organization": "github-copilot",
            "openai-intent": "conversation-panel",
            "content-type": "application/json",
            "user-agent": "GitHubCopilotChat/0.12.2023120701",
        }


def get_input(session: PromptSession, text: str = ""):
    print(text, end="", flush=True)
    return session.prompt(multiline=True)


def main():
    dotenv.load_dotenv()
    token = os.getenv("COPILOT_TOKEN")
    copilot = Copilot(token)
    if copilot.github_token is None:
        req = copilot.request_auth()
        print("Please visit", req["verification_uri"], "and enter", req["user_code"])
        while not copilot.poll_auth(req["device_code"]):
            time.sleep(req["interval"])
        print("Successfully authenticated")
    copilot.authenticate()
    session = PromptSession(history=InMemoryHistory())
    while True:
        user_prompt = get_input(session, "\n\nPrompt: \n")
        if user_prompt == "!exit":
            break
        code = get_input(session, "\n\nCode: \n")

        print("\n\nAI Response:")
        for response in copilot.ask(None, user_prompt, code):
            print(response, end="", flush=True)


if __name__ == "__main__":
    main()
