import os
import requests
import uuid
import time
import json

from . import utilities
from . import typings

LOGIN_HEADERS = {
    "accept": "application/json",
    "content-type": "application/json",
    "editor-version": "Neovim/0.9.2",
    "editor-plugin-version": "copilot.lua/1.11.4",
    "user-agent": "GithubCopilot/1.133.0",
}


class Copilot:
    def __init__(self):
        token = os.getenv("COPILOT_TOKEN")
        if token is None:
            token = utilities.get_cached_token()
        self.github_token = token

        self.token: dict[str, any] = None
        self.chat_history: list[typings.Message] = []
        self.vscode_sessionid: str = None
        self.machineid = utilities.random_hex()

        self.session = requests.Session()
        self.authenticate()

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

    def function_calling_test(
        self,
    ):
        url = "https://api.githubcopilot.com/chat/completions"

        data = {
            "model": "gpt-4",
            "messages": [
                {
                    "role": "system",
                    "content": "Perform function requests for the user",
                },
                {
                    "role": "user",
                    "content": "What's the current time?",
                },
            ],
            "functions": [
                {
                    "name": "get_current_time",
                    "description": "Returns the current time",
                    "parameters": [],
                }
            ],
        }

        response = self.session.post(
            url, headers=self._headers(), json=data, stream=True
        )

        with open("response.json", "w") as f:
            f.write(response.text)

    def ask(
        self,
        system_prompt: str,
        prompt: str,
        code: str,
        language: str = "",
        model: str = "gpt-4",
    ):
        url = "https://api.githubcopilot.com/chat/completions"
        self.chat_history.append(typings.Message(prompt, "user"))
        data = utilities.generate_request(
            self.chat_history, code, language, system_prompt=system_prompt, model=model
        )

        full_response = ""

        response = self.session.post(
            url, headers=self._headers(), json=data, stream=True
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
