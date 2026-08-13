local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)

local Controllers = script.Parent:WaitForChild("Controllers")
local BallPresentationController = require(Controllers:WaitForChild("BallPresentationController"))
local MovementController = require(Controllers:WaitForChild("MovementController"))
local ControlledBallController = require(Controllers:WaitForChild("ControlledBallController"))

local function log(message: string)
	print(string.format("%s[Client] %s", GameConfig.LogPrefix, message))
end

log("Initializing...")
MovementController.Initialize()
log("Movement initialized")
ControlledBallController.Initialize()
log("Controlled ball initialized")
BallPresentationController.Initialize()
log("Ball presentation initialized")
log("Ready")
