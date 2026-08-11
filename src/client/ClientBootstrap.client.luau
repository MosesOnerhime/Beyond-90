local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)

local Controllers = script.Parent:WaitForChild("Controllers")
local MovementController = require(Controllers:WaitForChild("MovementController"))

local function log(message: string)
	print(string.format("%s[Client] %s", GameConfig.LogPrefix, message))
end

log("Initializing...")
MovementController.Initialize()
log("Movement initialized")
log("Ready")
