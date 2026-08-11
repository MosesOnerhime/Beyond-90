local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)

local function log(message: string)
	print(string.format("%s[Client] %s", GameConfig.LogPrefix, message))
end

log("Initializing...")
log("Ready")
