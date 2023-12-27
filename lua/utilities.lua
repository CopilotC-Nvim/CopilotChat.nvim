PROMPTS = require("prompts")
-- A function to generate a random hexadecimal string of a given length
-- Default length is 65
function random_hex(length)
	length = length or 65                        -- Use 65 if length is not provided
	local hex = ""                               -- Initialize an empty string
	local choices = "0123456789abcdef"           -- The possible characters
	for _ = 1, length do                         -- Loop for the given length
		local index = math.random(#choices)        -- Pick a random index
		hex = hex .. choices:sub(index, index)     -- Append the character at that index
	end
	return hex                                   -- Return the hexadecimal string
end

-- A function to generate a request for the copilot-chat model
-- Takes a chat history, a code excerpt, and an optional language
function generate_request(chat_history, code_excerpt, language)
	language = language or ""                         -- Use an empty string if language is not provided
	local messages = {                                -- Initialize a table of messages
		{
			content = PROMPTS.COPILOT_INSTRUCTIONS,       -- The instructions for the user
			role = "system"                               -- The role of the system
		}
	}
	for _, message in ipairs(chat_history) do   -- Loop through the chat history
		table.insert(messages, {                  -- Append each message to the table
			content = message.content,              -- The content of the message
			role = message.role                     -- The role of the sender
		})
	end
	if code_excerpt ~= "" then                                                                     -- If there is a code excerpt
		table.insert(messages, #messages, {                                                          -- Insert it before the last message
			content = "\nActive selection:\n```" .. language .. "\n" .. code_excerpt .. "\n```",       -- The formatted code excerpt
			role = "system"                                                                            -- The role of the system
		})
	end
	return {   -- Return a table with the request parameters
		intent = true,
		model = "copilot-chat",
		n = 1,
		stream = true,
		temperature = 0.1,
		top_p = 1,
		messages = messages
	}
end

-- A function to cache a token for a user
-- Writes to ~/.config/github-copilot/hosts.json
function cache_token(user, token)
	local home = os.getenv("HOME")                         -- Get the home directory
	local config_dir = home .. "/.config/github-copilot"   -- The config directory
	local lfs = require("lfs")                             -- Require the Lua file system module
	if not lfs.attributes(config_dir) then                 -- If the config directory does not exist
		lfs.mkdir(config_dir)                                -- Create it
	end
	local hosts_file = config_dir .. "/hosts.json"         -- The hosts file
	local json = require("json")                           -- Require the json module
	local hosts = {                                        -- Create a table with the host information
		["github.com"] = {
			user = user,
			oauth_token = token
		}
	}
	local f = io.open(hosts_file, "w")   -- Open the file for writing
	if not f then                         -- If the file could not be opened
		return                             -- Return
	end
	f:write(json.encode(hosts))          -- Write the json-encoded table
	f:close()                            -- Close the file
end

-- A function to get the cached token
-- Reads from ~/.config/github-copilot/hosts.json
function get_cached_token()
	local home = os.getenv("HOME")                         -- Get the home directory
	local config_dir = home .. "/.config/github-copilot"   -- The config directory
	local hosts_file = config_dir .. "/hosts.json"         -- The hosts file
	local lfs = require("lfs")                             -- Require the Lua file system module
	if not lfs.attributes(hosts_file) then                 -- If the hosts file does not exist
		return nil                                           -- Return nil
	end
	local f = io.open(hosts_file, "r")                     -- Open the file for reading
	if not f then                                           -- If the file could not be opened
		return nil                                           -- Return nil
	end
	local json = require("json")                           -- Require the json module
	local hosts = json.decode(f:read("*a"))                -- Decode the json string
	f:close()                                              -- Close the file
	if hosts["github.com"] then                            -- If there is a host for github.com
		return hosts["github.com"].oauth_token               -- Return the token
	else
		return nil                                           -- Return nil
	end
end


