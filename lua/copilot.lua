UUID = require("uuid")
JSON = require("json")
REQUESTS = require("requests")
-- A class to represent a Copilot object
local Copilot = {}
Copilot.__index = Copilot

-- A constructor function to create a new Copilot object
function Copilot:new(token)
	local self = setmetatable({}, Copilot)
	if token == nil then
		token = utilities.get_cached_token()
	end
	self.github_token = token
	self.token = {}
	self.chat_history = {}
	self.vscode_sessionid = nil
	self.machineid = utilities.random_hex()
	return self
end

-- A method to request authentication from GitHub
function Copilot:request_auth()
	local url = "https://github.com/login/device/code"
	local response = REQUESTS.post(
		url,
		{
			headers = LOGIN_HEADERS,
			data = JSON.dumps({
				client_id = "Iv1.b507a08c87ecfe98",
				scope = "read:user"
			})
		}
	):json()
	return response
end

-- A method to poll authentication status from GitHub
function Copilot:poll_auth(device_code)
	local url = "https://github.com/login/oauth/access_token"
	local response = REQUESTS.post(
		url,
		{
			headers = LOGIN_HEADERS,
			data = JSON.dumps({
				client_id = "Iv1.b507a08c87ecfe98",
				device_code = device_code,
				grant_type = "urn:ietf:params:oauth:grant-type:device_code"
			})
		}
	):json()
	if response["access_token"] then
		local access_token, token_type = response["access_token"], response["token_type"]
		url = "https://api.github.com/user"
		local headers = {
			authorization = token_type .. " " .. access_token,
			user_agent = "GithubCopilot/1.133.0",
			accept = "application/json"
		}
		response = REQUESTS.get(url, { headers = headers }):json()
		utilities.cache_token(response["login"], access_token)
		self.github_token = access_token
		return true
	end
	return false
end

-- A method to authenticate with GitHub Copilot
function Copilot:authenticate()
	if self.github_token == nil then
		error("No token found")
	end
	self.vscode_sessionid = tostring(UUID.new()) .. tostring(math.floor(os.time() * 1000))
	local url = "https://api.github.com/copilot_internal/v2/token"
	local headers = {
		authorization = "token " .. self.github_token,
		editor_version = "vscode/1.80.1",
		editor_plugin_version = "copilot-chat/0.4.1",
		user_agent = "GitHubCopilotChat/0.4.1"
	}
	self.token = REQUESTS.get(url, { headers = headers }):json()
end

-- A method to ask a question to GitHub Copilot
function Copilot:ask(prompt, code, language)
	if language == nil then
		language = ""
	end
	local url = "https://copilot-proxy.githubusercontent.com/v1/chat/completions"
	local headers = {
		authorization = "Bearer " .. self.token["token"],
		x_request_id = tostring(UUID.new()),
		vscode_sessionid = self.vscode_sessionid,
		machineid = self.machineid,
		editor_version = "vscode/1.80.1",
		editor_plugin_version = "copilot-chat/0.4.1",
		openai_organization = "github-copilot",
		openai_intent = "conversation-panel",
		content_type = "application/json",
		user_agent = "GitHubCopilotChat/0.4.1"
	}
	table.insert(self.chat_history, typings.Message(prompt, "user"))
	local data = utilities.generate_request(self.chat_history, code, language)
	local full_response = ""
	local response = REQUESTS.post(url, { headers = headers, json = data, stream = true })
	for line in response:iter_lines() do
		line = line:decode("utf-8"):gsub("data: ", ""):strip()
		if line:startswith("[DONE]") then
			break
		elseif line == "" then
			goto continue
		end
		local ok, line = pcall(JSON.loads, line)
		if not ok then
			print("Error:", line)
			goto continue
		end
		local content = line["choices"][1]["delta"]["content"]
		if content == nil then
			goto continue
		end
		full_response = full_response .. content
		coroutine.yield(content)
		::continue::
	end
	table.insert(self.chat_history, typings.Message(full_response, "system"))
end
