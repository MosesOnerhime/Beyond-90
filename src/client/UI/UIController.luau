local ContentProvider = game:GetService("ContentProvider")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FootballActionConfig = require(Shared.Config.FootballActionConfig)
local GoalConfig = require(Shared.Config.GoalConfig)
local UIAssetConfig = require(Shared.Config.UIAssetConfig)
local HomeScreen = require(script.Parent.Screens.HomeScreen)
local TrainingScreen = require(script.Parent.Screens.TrainingScreen)
local LoadingScreen = require(script.Parent.Screens.LoadingScreen)
local GameplayHUD = require(script.Parent.Screens.GameplayHUD)
local GoalNotification = require(script.Parent.Screens.GoalNotification)
local Theme = require(script.Parent.Theme)

local UIController = {}
local localPlayer = Players.LocalPlayer
local screenGui: ScreenGui? = nil
local canvas: Frame? = nil
local canvasScale: UIScale? = nil
local homeView
local modeView
local loadingView
local gameplayView
local toast: TextLabel? = nil
local rootBackdrop: Frame? = nil
local scaleConnection: RBXScriptConnection? = nil

local function setSelected(object: GuiObject?)
	if GuiService.AutoSelectGuiEnabled and object and object.Visible then
		GuiService.SelectedObject = object
	end
end

local function updateScale()
	if not canvasScale then return end
	local camera = workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(1600, 900)
	canvasScale.Scale = math.max(0.35, math.min(viewport.X / 1600, viewport.Y / 900))
end

local function setScreen(name: string)
	if not homeView then return end
	homeView.Frame.Visible = name == "Home"
	modeView.Frame.Visible = name == "Modes"
	loadingView.Frame.Visible = name == "Loading"
	gameplayView.Frame.Visible = name == "Gameplay"
	if rootBackdrop then rootBackdrop.Visible = name ~= "Gameplay" end
	if name == "Home" then
		setSelected(homeView.DefaultSelection)
	elseif name == "Modes" then
		setSelected(modeView.DefaultSelection)
	else
		GuiService.SelectedObject = nil
	end
end

local function showComingSoon()
	if not toast then return end
	toast.TextTransparency = 0
	toast.BackgroundTransparency = 0.08
	task.delay(1.2, function()
		if toast then
			TweenService:Create(toast, TweenInfo.new(0.18), { TextTransparency = 1, BackgroundTransparency = 1 }):Play()
		end
	end)
end

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
end

function UIController.Initialize(callbacks)
	if screenGui then return end
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "Beyond90UI"
	screenGui.IgnoreGuiInset = true
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 200
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = playerGui
	rootBackdrop = Instance.new("Frame")
	rootBackdrop.Size = UDim2.fromScale(1, 1)
	rootBackdrop.BackgroundColor3 = Theme.Background
	rootBackdrop.BorderSizePixel = 0
	rootBackdrop.Parent = screenGui
	canvas = Instance.new("Frame")
	canvas.Name = "Canvas"
	canvas.AnchorPoint = Vector2.new(0.5, 0.5)
	canvas.Position = UDim2.fromScale(0.5, 0.5)
	canvas.Size = UDim2.fromOffset(1600, 900)
	canvas.BackgroundTransparency = 1
	canvas.Parent = screenGui
	canvasScale = Instance.new("UIScale")
	canvasScale.Parent = canvas
	updateScale()
	scaleConnection = RunService.RenderStepped:Connect(updateScale)

	local uiCallbacks = {
		OpenHome = function() setScreen("Home") end,
		OpenModeSelect = function() setScreen("Modes") end,
		EnterTraining = callbacks.EnterTraining,
		ReturnToMenu = callbacks.ReturnToMenu,
		ResetBall = callbacks.ResetBall,
		ShowComingSoon = showComingSoon,
	}
	homeView = HomeScreen.Create(canvas, uiCallbacks)
	modeView = TrainingScreen.Create(canvas, uiCallbacks)
	loadingView = LoadingScreen.Create(canvas)
	gameplayView = GameplayHUD.Create(canvas, uiCallbacks)
	local goalView = GoalNotification.Create(canvas)
	toast = Instance.new("TextLabel")
	toast.AnchorPoint = Vector2.new(0.5, 1)
	toast.Position = UDim2.new(0.5, 0, 1, -52)
	toast.Size = UDim2.fromOffset(250, 40)
	toast.BackgroundColor3 = Theme.Panel
	toast.BackgroundTransparency = 1
	toast.Text = "COMING SOON"
	toast.TextColor3 = Theme.AccentCyan
	toast.TextTransparency = 1
	toast.Font = Theme.Fonts.Navigation
	toast.TextSize = 12
	toast.ZIndex = 300
	toast.Parent = canvas
	task.spawn(function()
		local remotes = ReplicatedStorage:WaitForChild(FootballActionConfig.RemotesFolderName, 10)
		local goalRemote = remotes and remotes:WaitForChild(GoalConfig.GoalScoredRemoteName, 10)
		if goalRemote and goalRemote:IsA("RemoteEvent") then
			goalRemote.OnClientEvent:Connect(function(payload) goalView.Play(payload) end)
		end
	end)
	preloadMenuAssets()
end

function UIController.ShowHome()
	setScreen("Home")
end

function UIController.ShowModeLoading(mode: string, detail: string)
	loadingView.SetMode(mode, detail)
	loadingView.SetStatus("PREPARING TRAINING", 0.12)
	setScreen("Loading")
end

function UIController.UpdateModeLoading(status: string, progress: number)
	if loadingView then loadingView.SetStatus(status, progress) end
end

function UIController.ShowGameplay()
	loadingView.SetStatus("READY", 1)
	task.wait(0.12)
	setScreen("Gameplay")
end

return UIController
