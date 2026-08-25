local ContentProvider = game:GetService("ContentProvider")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ReactPackages = require(Shared.ReactPackages)
local React = ReactPackages.React
local ReactRoblox = ReactPackages.ReactRoblox
local FootballActionConfig = require(Shared.Config.FootballActionConfig)
local GoalConfig = require(Shared.Config.GoalConfig)
local UIAssetConfig = require(Shared.Config.UIAssetConfig)
local GameplayHUD = require(script.Parent.Screens.GameplayHUD)
local GoalNotification = require(script.Parent.Screens.GoalNotification)
local HomeScreen = require(script.Parent.Screens.HomeScreen)
local LoadingScreen = require(script.Parent.Screens.LoadingScreen)
local TrainingScreen = require(script.Parent.Screens.TrainingScreen)
local TeamSelectionScreen = require(script.Parent.Screens.TeamSelectionScreen)
local SettingsScreen = require(script.Parent.Screens.SettingsScreen)
local Theme = require(script.Parent.Theme)
local ReactUI = require(script.Parent.Components.ReactUI)

local UIController = {}
local localPlayer = Players.LocalPlayer
local root = nil
local remoteConnection: RBXScriptConnection? = nil
local setScreenState = nil
local setLoadingState = nil
local setToastState = nil
local setGoalState = nil

local function preloadMenuAssets()
	local images = {}
	local function collect(value)
		if type(value) == "table" then
			for key, child in value do
				if key ~= "LocalSources" then collect(child) end
			end
		elseif type(value) == "string" and string.match(value, "^rbxassetid://%d+$") then
			local image = Instance.new("ImageLabel")
			image.Image = value
			table.insert(images, image)
		end
	end
	collect(UIAssetConfig)
	local ok, failure = pcall(function() ContentProvider:PreloadAsync(images) end)
	if not ok then warn("[Beyond90][UI] Menu preload failure: " .. tostring(failure)) end
	for _, image in images do image:Destroy() end
	localPlayer:SetAttribute("Beyond90MenuAssetsReady", true)
end

local function App(props)
	local callbacks = props.Callbacks
	local function click()
		if callbacks.PlayClick then callbacks.PlayClick() end
	end
	local screen, setScreen = React.useState("Home")
	local loading, setLoading = React.useState({
		Variant = "Training", Mode = "TRAINING", Detail = "FREE PRACTICE",
		Status = "PREPARING TRAINING", Progress = 0.12,
	})
	local toast, setToast = React.useState(false)
	local goalVisible, setGoalVisible = React.useState(false)
	local selectedTrack, setSelectedTrack = React.useState(callbacks and callbacks.GetMenuTrack and callbacks.GetMenuTrack() or 1)

	setScreenState = setScreen
	setLoadingState = setLoading
	setToastState = setToast
	setGoalState = setGoalVisible

	React.useEffect(function()
		localPlayer:SetAttribute("Beyond90MenuSurfaceMounted", true)
		return function()
			localPlayer:SetAttribute("Beyond90MenuSurfaceMounted", false)
		end
	end, {})

	local screenElement
	if screen == "Home" then
		screenElement = React.createElement(HomeScreen, {
			OpenModes = function() click(); setScreen("Modes") end,
			OpenSettings = function() click(); setScreen("Settings") end,
			ComingSoon = function()
				click()
				setToast(true)
				task.delay(1.2, function() setToast(false) end)
			end,
		})
	elseif screen == "Modes" then
		screenElement = React.createElement(TrainingScreen, {
			GoHome = function() click(); setScreen("Home") end,
			OpenTeamSelection = function() click(); setScreen("TeamSelect") end,
			ComingSoon = function()
				click()
				setToast(true)
				task.delay(1.2, function() setToast(false) end)
			end,
		})
	elseif screen == "TeamSelect" then
		screenElement = React.createElement(TeamSelectionScreen, {
			GoBack = function() click(); setScreen("Modes") end,
			Continue = function(teamId) click(); callbacks.EnterTraining(teamId) end,
		})
	elseif screen == "Settings" then
		screenElement = React.createElement(SettingsScreen, {
			GoHome = function() click(); setScreen("Home") end,
			SelectedTrack = selectedTrack,
			SetTrack = function(index)
				click()
				setSelectedTrack(index)
				callbacks.SetMenuTrack(index)
			end,
		})
	elseif screen == "Gameplay" then
		screenElement = React.createElement(GameplayHUD, {
			ResetBall = function() click(); callbacks.ResetBall() end,
			ReturnToMenu = function() click(); callbacks.ReturnToMenu() end,
		})
	else
		screenElement = React.createElement(LoadingScreen, loading)
	end

	return React.createElement("ScreenGui", {
		Name = "Beyond90UI",
		-- HUD geometry explicitly reserves the top-left CoreGui cluster while keeping
		-- menu and gameplay presentation edge-to-edge.
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 200,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, {
		Root = React.createElement("Frame", {
			Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = if screen == "Gameplay" then 1 else 0, BorderSizePixel = 0,
		}, {
			Screen = screenElement,
			Toast = toast and React.createElement("Frame", {
				AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.055),
				Size = UDim2.fromScale(0.23, 0.082), BackgroundColor3 = Theme.Panel,
				BackgroundTransparency = 0.02, BorderSizePixel = 0, ZIndex = 300,
			}, {
				Corner = ReactUI.Corner(6),
				Stroke = ReactUI.Stroke(Theme.StrokeBright, 1.25, 0.12),
				Accent = React.createElement("Frame", { Size = UDim2.fromScale(0.018, 1), BackgroundColor3 = Theme.AccentCyan, BorderSizePixel = 0, ZIndex = 301 }, {
					Gradient = ReactUI.Gradient(Theme.AccentCyan, Theme.AccentViolet, 90),
				}),
				Title = React.createElement("TextLabel", { Position = UDim2.fromScale(0.08, 0.18), Size = UDim2.fromScale(0.84, 0.28), BackgroundTransparency = 1, Font = Theme.Fonts.Navigation, Text = "COMING SOON", TextColor3 = Theme.Text, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 301 }),
				Body = React.createElement("TextLabel", { Position = UDim2.fromScale(0.08, 0.5), Size = UDim2.fromScale(0.84, 0.22), BackgroundTransparency = 1, Font = Theme.Fonts.Caption, Text = "This area is not available in the current milestone.", TextColor3 = Theme.MutedText, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 301 }),
			}) or nil,
			Goal = React.createElement(GoalNotification, { Visible = goalVisible }),
		}),
	})
end

function UIController.Initialize(callbacks)
	if root then return end
	localPlayer:SetAttribute("Beyond90MenuSurfaceMounted", false)
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	root = ReactRoblox.createRoot(playerGui)
	root:render(React.createElement(App, { Callbacks = callbacks }))
	task.spawn(preloadMenuAssets)
	task.spawn(function()
		local remotes = ReplicatedStorage:WaitForChild(FootballActionConfig.RemotesFolderName, 10)
		local goalRemote = remotes and remotes:WaitForChild(GoalConfig.GoalScoredRemoteName, 10)
		if goalRemote and goalRemote:IsA("RemoteEvent") then
			remoteConnection = goalRemote.OnClientEvent:Connect(function()
				if setGoalState then
					setGoalState(true)
					task.delay(1.35, function()
						if setGoalState then setGoalState(false) end
					end)
				end
			end)
		end
	end)
end

function UIController.ShowHome()
	if setScreenState then setScreenState("Home") end
	GuiService.SelectedObject = nil
end

function UIController.ShowMenuLoading()
	if setLoadingState then
		setLoadingState({
			Variant = "Menu", Mode = "RETURNING TO MENU", Detail = "",
			Status = "CLOSING TRAINING SESSION", Progress = 0.62,
		})
	end
	if setScreenState then setScreenState("Loading") end
end

function UIController.ShowModeLoading(mode: string, detail: string)
	if setLoadingState then
		setLoadingState({
			Variant = "Training", Mode = mode, Detail = detail,
			Status = "PREPARING TRAINING", Progress = 0.12,
		})
	end
	if setScreenState then setScreenState("Loading") end
end

function UIController.UpdateModeLoading(status: string, progress: number)
	if setLoadingState then
		setLoadingState(function(previous)
			local nextState = table.clone(previous)
			nextState.Status = status
			nextState.Progress = progress
			return nextState
		end)
	end
end

function UIController.ShowGameplay()
	UIController.UpdateModeLoading("READY", 1)
	task.wait(0.65)
	if setScreenState then setScreenState("Gameplay") end
end

function UIController.Destroy()
	if remoteConnection then remoteConnection:Disconnect() end
	remoteConnection = nil
	if root then root:unmount() end
	root = nil
	setScreenState = nil
	setLoadingState = nil
	setToastState = nil
	setGoalState = nil
	localPlayer:SetAttribute("Beyond90MenuSurfaceMounted", false)
end

return UIController
