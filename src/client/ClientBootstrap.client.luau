local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local ExperienceFlowController = require(script.Parent.Controllers.ExperienceFlowController)

print(string.format("%s[Client] Initializing menu-first experience...", GameConfig.LogPrefix))
ExperienceFlowController.Initialize()
print(string.format("%s[Client] Main menu ready", GameConfig.LogPrefix))
