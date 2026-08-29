local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AnimationConfig = require(Shared.Config.AnimationConfig)
local ExperienceConfig = require(Shared.Config.ExperienceConfig)
local GameConfig = require(Shared.Config.GameConfig)

local Controllers = script.Parent
local AnimationController = require(Controllers.AnimationController)
local AudioController = require(Controllers.AudioController)
local PositionController = require(script.Parent.PositionController)
local BallPresentationController = require(Controllers.BallPresentationController)
local ControlSchemeController = require(Controllers.ControlSchemeController)
local ControlledBallController = require(Controllers.ControlledBallController)
local DefendingController = require(Controllers.DefendingController)
local DevelopmentHUDController = require(Controllers.DevelopmentHUDController)
local FootballActionController = require(Controllers.FootballActionController)
local GameModeController = require(Controllers.GameModeController)
local GoalkeeperController = require(Controllers.GoalkeeperController)
local InputController = require(Controllers.InputController)
local MatchPresentationController = require(Controllers.MatchPresentationController)
local RefereeDecisionController = require(Controllers.RefereeDecisionController)
local MovementController = require(Controllers.MovementController)
local PassTargetPresentationController = require(Controllers.PassTargetPresentationController)
local PassTargetResolver = require(Controllers.PassTargetResolver)
local PlayerIndicatorController = require(Controllers.PlayerIndicatorController)
local ShotTrajectoryController = require(Controllers.ShotTrajectoryController)
local CameraController = require(script.Parent.Parent.Camera.CameraController)
local UIController = require(script.Parent.Parent.UI.UIController)

local ExperienceFlowController = {}
local localPlayer = Players.LocalPlayer
local initialized = false
local gameplayActive = false
local transitionId = 0

local gameplayControllers = {
	InputController,
	MovementController,
	AnimationController,
	ControlledBallController,
	PassTargetResolver,
	PassTargetPresentationController,
	FootballActionController,
	DefendingController,
	-- After DefendingController, because it reroutes the same tackle input when
	-- the local footballer is actually a goalkeeper.
	GoalkeeperController,
	ShotTrajectoryController,
	PlayerIndicatorController,
	BallPresentationController,
	CameraController,
	MatchPresentationController,
	RefereeDecisionController,
	DevelopmentHUDController,
}

local function log(message: string)
	print(string.format("%s[Client][Experience] %s", GameConfig.LogPrefix, message))
end

local function setState(state: string)
	localPlayer:SetAttribute("Beyond90ClientExperienceState", state)
	localPlayer:SetAttribute("Beyond90MenuOpen", state ~= ExperienceConfig.States.Gameplay)
	log("State -> " .. state)
end

local function hideRobloxCoreUI()
	local topbarHidden = pcall(function()
		StarterGui:SetCore("TopbarEnabled", false)
	end)
	localPlayer:SetAttribute("Beyond90TopbarHidden", topbarHidden)
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false)
	end)
	for _, coreGuiType in {
		Enum.CoreGuiType.Chat,
		Enum.CoreGuiType.PlayerList,
		Enum.CoreGuiType.Backpack,
		Enum.CoreGuiType.EmotesMenu,
		Enum.CoreGuiType.Health,
	} do
		pcall(function()
			StarterGui:SetCoreGuiEnabled(coreGuiType, false)
		end)
	end
	pcall(function()
		StarterGui:SetCore("ChatActive", false)
	end)
end

local function collectAnimationAssets(value, animations: { Animation })
	if type(value) == "table" then
		for _, child in value do
			collectAnimationAssets(child, animations)
		end
	elseif type(value) == "string" and string.match(value, "^rbxassetid://%d+$") then
		local animation = Instance.new("Animation")
		animation.AnimationId = value
		table.insert(animations, animation)
	end
end

local function preloadGameplayAssets(onProgress)
	local animations = {}
	collectAnimationAssets(AnimationConfig.Assets, animations)
	local completed = false
	task.spawn(function()
		local loaded = 0
		local ok, failure = pcall(function()
			ContentProvider:PreloadAsync(animations, function()
				loaded += 1
				onProgress(0.3 + 0.55 * loaded / math.max(#animations, 1), "LOADING ANIMATIONS")
			end)
		end)
		if not ok then
			warn(string.format("%s[Client][Experience] Gameplay preload failure: %s", GameConfig.LogPrefix, tostring(failure)))
		end
		completed = true
	end)
	local startedAt = os.clock()
	while not completed and os.clock() - startedAt < ExperienceConfig.PreloadTimeout do
		task.wait()
	end
	for _, animation in animations do
		animation:Destroy()
	end
end

local function initializeGameplay()
	if gameplayActive then
		return
	end
	for _, controller in gameplayControllers do
		controller.Initialize()
	end
	gameplayActive = true
end

local function destroyGameplay()
	if not gameplayActive then
		return
	end
	for index = #gameplayControllers, 1, -1 do
		local controller = gameplayControllers[index]
		if controller.Destroy then
			controller.Destroy()
		end
	end
	gameplayActive = false
end

function ExperienceFlowController.EnterMode(modeId: string, teamId: string)
	if gameplayActive or localPlayer:GetAttribute("Beyond90ClientExperienceState") == ExperienceConfig.States.ModeLoading then
		return
	end
	transitionId += 1
	local currentTransition = transitionId
	setState(ExperienceConfig.States.ModeLoading)
	AudioController.BeginTransition()
	local modeName = if modeId == "Quick3v3" then "QUICK 3V3" else "TRAINING"
	local modeDetail = if modeId == "Quick3v3" then "3V3 AI DEVELOPMENT MATCH" else "FREE PRACTICE"
	UIController.ShowModeLoading(modeName, string.upper(teamId) .. " TEAM - " .. modeDetail)
	local startedAt = os.clock()
	GameModeController.EnterMode(modeId, teamId)
	preloadGameplayAssets(function(progress, status)
		UIController.UpdateModeLoading(status, progress)
	end)
	UIController.UpdateModeLoading("PREPARING FOOTBALLER", 0.9)
	while os.clock() - startedAt < ExperienceConfig.CharacterReadyTimeout do
		if currentTransition ~= transitionId then
			return
		end
		local character = localPlayer.Character
		if character and character:GetAttribute("Beyond90CharacterReady") == true
			and localPlayer:GetAttribute("Beyond90ExperienceState") == "Gameplay"
		then
			break
		end
		task.wait()
	end
	local character = localPlayer.Character
	if not character or character:GetAttribute("Beyond90CharacterReady") ~= true
		or localPlayer:GetAttribute("Beyond90ExperienceState") ~= "Gameplay"
	then
		warn(string.format("%s[Client][Experience] %s initialization timed out", GameConfig.LogPrefix, modeId))
		GameModeController.ExitGameplay()
		setState(ExperienceConfig.States.Menu)
		UIController.ShowHome()
		return
	end
	while os.clock() - startedAt < ExperienceConfig.ModeMinimumDisplayTime do
		task.wait()
	end
	if currentTransition ~= transitionId then
		return
	end
	initializeGameplay()
	local animationReadyStartedAt = os.clock()
	while localPlayer:GetAttribute("Beyond90AnimationTrackLoaded") ~= true and os.clock() - animationReadyStartedAt < 2 do
		task.wait()
	end
	-- Arm the first-session broadcast reveal before Gameplay becomes visible.
	CameraController.PlayJoinIntro()
	setState(ExperienceConfig.States.Gameplay)
	AudioController.EnterGameplay()
	UIController.ShowGameplay()
	-- Everything the player needs is now live. Only at this point may the server
	-- start the match, so AI cannot contest the ball while we were loading.
	MatchPresentationController.SignalReady()
end

function ExperienceFlowController.EnterTraining(teamId: string)
	ExperienceFlowController.EnterMode("TrainingFree", teamId)
end

function ExperienceFlowController.ReturnToMenu()
	transitionId += 1
	local currentTransition = transitionId
	setState(ExperienceConfig.States.MenuLoading)
	AudioController.BeginTransition()
	UIController.ShowMenuLoading()
	local startedAt = os.clock()
	destroyGameplay()
	GameModeController.ExitGameplay()
	while os.clock() - startedAt < ExperienceConfig.CharacterReadyTimeout do
		if currentTransition ~= transitionId then
			return
		end
		if localPlayer:GetAttribute("Beyond90ExperienceState") == "Menu" and localPlayer.Character == nil then
			break
		end
		task.wait()
	end
	while os.clock() - startedAt < ExperienceConfig.ReturnToMenuMinimumDisplayTime do
		task.wait()
	end
	if currentTransition ~= transitionId then
		return
	end
	setState(ExperienceConfig.States.Menu)
	AudioController.EnterMenu()
	UIController.ShowHome()
end

function ExperienceFlowController.Initialize()
	if initialized then
		return
	end
	initialized = true
	hideRobloxCoreUI()
	for attempt = 1, 5 do
		task.delay(attempt * 0.75, hideRobloxCoreUI)
	end
	setState(ExperienceConfig.States.MenuLoading)
	AudioController.Initialize()
	ControlSchemeController.Initialize()
	GameModeController.Initialize()
	UIController.Initialize({
		EnterTraining = ExperienceFlowController.EnterTraining,
		EnterMode = ExperienceFlowController.EnterMode,
		ReturnToMenu = ExperienceFlowController.ReturnToMenu,
		ResetBall = GameModeController.ResetTrainingBall,
		SetMenuTrack = AudioController.SetMenuTrack,
		GetMenuTrack = AudioController.GetMenuTrackIndex,
		SetMusicEnabled = AudioController.SetMusicEnabled,
		GetMusicEnabled = AudioController.IsMusicEnabled,
		SelectPosition = PositionController.SelectPosition,
		GetPositionOccupancy = PositionController.GetOccupancy,
		PlayClick = AudioController.PlayClick,
	})
	local menuMountStartedAt = os.clock()
	while localPlayer:GetAttribute("Beyond90MenuSurfaceMounted") ~= true
		and os.clock() - menuMountStartedAt < ExperienceConfig.PreloadTimeout
	do
		task.wait()
	end
	localPlayer:SetAttribute("Beyond90MenuReady", true)
	local startupWaitStartedAt = os.clock()
	local transitionAtStartupWait = transitionId
	while localPlayer:GetAttribute("Beyond90StartupComplete") ~= true
		and os.clock() - startupWaitStartedAt < ExperienceConfig.PreloadTimeout
	do
		task.wait()
	end

	--[[
		Do not clobber a transition that began while we were waiting.

		This tail used to force the Menu state unconditionally. The startup wait
		can run for many seconds -- longer still when an asset is slow -- and
		anything that started entering a mode during that window was silently
		dragged back to the menu the moment this resumed, after gameplay had
		already been set up.

		In normal play the window is unreachable, because the menu is not visible
		to click until this has finished. It cost a verification run to find, and
		the guard is a transition-id check that costs nothing.
	]]
	if transitionId ~= transitionAtStartupWait then
		return
	end

	setState(ExperienceConfig.States.Menu)
	AudioController.EnterMenu()
	UIController.ShowHome()
end

return ExperienceFlowController
