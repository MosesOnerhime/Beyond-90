local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local MatchConfig = require(Shared.Config.MatchConfig)
local AudioController = require(script.Parent.AudioController)

--[[
	Owns the client half of the match-start handshake.

	Signals readiness once every gameplay controller has initialized, then
	renders the START MATCH card and plays the whistle exactly once when the
	server transitions into Starting.
]]
local MatchPresentationController = {}

local localPlayer = Players.LocalPlayer
local initialized = false
local gui: ScreenGui? = nil
local card: Frame? = nil
local startButton: TextButton? = nil
local startRemote: RemoteEvent? = nil
local stateConnection: RBXScriptConnection? = nil
local folder: Folder? = nil
local lastAnnouncedState = ""

local function log(message: string)
	print(string.format("%s[Client][Match] %s", GameConfig.LogPrefix, message))
end

--[[
	Only a gamepad should ever take GUI selection; a keyboard or touch player
	navigating the HUD with WASD is never what was wanted.
]]
local function isGamepadActive(): boolean
	if not UserInputService.GamepadEnabled then
		return false
	end
	local lastInput = UserInputService:GetLastInputType()
	return lastInput == Enum.UserInputType.Gamepad1
		or lastInput == Enum.UserInputType.Gamepad2
		or lastInput == Enum.UserInputType.Gamepad3
		or lastInput == Enum.UserInputType.Gamepad4
end

-- Hand directional input back to gameplay, but never steal a selection that
-- something else has since made.
local function releaseGuiSelection(button: Instance?)
	pcall(function()
		if button == nil or GuiService.SelectedObject == button then
			GuiService.SelectedObject = nil
		end
	end)
end

local function buildGui()
	if gui then
		return
	end
	local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end

	local screen = Instance.new("ScreenGui")
	screen.Name = "Beyond90MatchPresentation"
	screen.IgnoreGuiInset = true
	screen.ResetOnSpawn = false
	screen.DisplayOrder = 260
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.Enabled = true
	screen.Parent = playerGui

	-- Pre-built and kept transparent. Constructing this during the transition
	-- would cost frames at exactly the moment the card needs to be smooth.
	local root = Instance.new("Frame")
	root.Name = "StartCard"
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.4)
	root.Size = UDim2.fromOffset(320, 64)
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Visible = false
	root.Parent = screen

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.fromScale(1, 1)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.Text = MatchConfig.Presentation.Title
	title.TextColor3 = Color3.fromRGB(246, 248, 255)
	title.TextSize = 34
	title.TextTransparency = 1
	title.Parent = root

	local accent = Instance.new("Frame")
	accent.Name = "Accent"
	accent.AnchorPoint = Vector2.new(0.5, 0)
	accent.Position = UDim2.fromScale(0.5, 1)
	accent.Size = UDim2.fromOffset(0, 2)
	accent.BackgroundColor3 = Color3.fromRGB(44, 226, 255)
	accent.BackgroundTransparency = 1
	accent.BorderSizePixel = 0
	accent.Parent = root

	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(Color3.fromRGB(44, 226, 255), Color3.fromRGB(130, 76, 255))
	gradient.Parent = accent

	-- Kick-off button. Built up front and simply shown/hidden, so pressing it
	-- costs no construction on the frame the whistle plays.
	local button = Instance.new("TextButton")
	button.Name = "StartMatchButton"
	button.AnchorPoint = Vector2.new(0.5, 0.5)
	button.Position = UDim2.fromScale(0.5, 0.62)
	button.Size = UDim2.fromOffset(264, 56)
	button.BackgroundColor3 = Color3.fromRGB(13, 20, 44)
	button.BackgroundTransparency = 0.06
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Font = Enum.Font.GothamBold
	button.Text = MatchConfig.Presentation.ButtonLabel
	button.TextColor3 = Color3.fromRGB(246, 248, 255)
	button.TextSize = 19
	button.Visible = false
	button.Selectable = true
	button.ZIndex = 4
	button.Parent = screen

	local buttonCorner = Instance.new("UICorner")
	buttonCorner.CornerRadius = UDim.new(0, 8)
	buttonCorner.Parent = button

	local buttonStroke = Instance.new("UIStroke")
	buttonStroke.Color = Color3.fromRGB(118, 191, 255)
	buttonStroke.Thickness = 1.4
	buttonStroke.Transparency = 0.18
	buttonStroke.Parent = button

	local hint = Instance.new("TextLabel")
	hint.Name = "Hint"
	hint.AnchorPoint = Vector2.new(0.5, 0)
	hint.Position = UDim2.new(0.5, 0, 1, 8)
	hint.Size = UDim2.fromOffset(264, 14)
	hint.BackgroundTransparency = 1
	hint.Font = Enum.Font.GothamMedium
	hint.Text = MatchConfig.Presentation.Hint
	hint.TextColor3 = Color3.fromRGB(156, 169, 201)
	hint.TextSize = 11
	hint.ZIndex = 4
	hint.Parent = button

	button.Activated:Connect(function()
		if not startRemote then
			return
		end
		-- Fire once, then disarm; the server also rejects a second request.
		button.Visible = false
		releaseGuiSelection(button)
		startRemote:FireServer()
		log("Kick-off requested")
	end)

	gui = screen
	card = root
	startButton = button
end

local function setButtonState(visible: boolean, waiting: boolean)
	buildGui()
	local button = startButton
	if not button then
		return
	end
	button.Text = if waiting
		then MatchConfig.Presentation.WaitingLabel
		else MatchConfig.Presentation.ButtonLabel
	button.AutoButtonColor = not waiting
	button.Active = not waiting
	button.BackgroundTransparency = if waiting then 0.4 else 0.06
	button.Visible = visible
	local hint = button:FindFirstChild("Hint")
	if hint and hint:IsA("TextLabel") then
		hint.Visible = not waiting
	end
	--[[
		GUI selection is a GAMEPAD affordance, and it is exclusive: while
		GuiService.SelectedObject is set, Roblox routes directional input to
		navigating between Selectable GuiObjects instead of to the game. Every
		menu and HUD button in Beyond 90 is Selectable, so leaving this pointing
		at the kick-off button meant WASD moved the HUD highlight around rather
		than the footballer -- for the rest of the match, because it was never
		cleared when the button was hidden.

		So it is only offered to a gamepad, and it is always given back.
	]]
	if visible and not waiting and isGamepadActive() then
		pcall(function()
			GuiService.SelectedObject = button
		end)
	else
		releaseGuiSelection(button)
	end
end

local function playStartPresentation()
	buildGui()
	local root = card
	if not root then
		return
	end
	local title = root:FindFirstChild("Title") :: TextLabel?
	local accent = root:FindFirstChild("Accent") :: Frame?
	if not title or not accent then
		return
	end

	local presentation = MatchConfig.Presentation
	root.Visible = true
	title.TextTransparency = 1
	accent.BackgroundTransparency = 1
	accent.Size = UDim2.fromOffset(0, 2)

	AudioController.PlayMatchStartWhistle()

	local inInfo = TweenInfo.new(presentation.FadeInSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(title, inInfo, { TextTransparency = 0 }):Play()
	TweenService:Create(accent, inInfo, {
		BackgroundTransparency = 0.1,
		Size = UDim2.fromOffset(180, 2),
	}):Play()

	task.delay(presentation.FadeInSeconds + presentation.HoldSeconds, function()
		if not root.Parent then
			return
		end
		local outInfo = TweenInfo.new(presentation.FadeOutSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(title, outInfo, { TextTransparency = 1 }):Play()
		TweenService:Create(accent, outInfo, { BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 2) }):Play()
		task.delay(presentation.FadeOutSeconds, function()
			if root.Parent then
				root.Visible = false
			end
		end)
	end)
end

local function onStateChanged()
	if not folder then
		return
	end
	local state = folder:GetAttribute(MatchConfig.StateAttributeName)
	localPlayer:SetAttribute("Beyond90MatchState", state)

	if state ~= MatchConfig.States.Starting then
		lastAnnouncedState = state or ""
	end

	if state == MatchConfig.States.WaitingForPlayers then
		setButtonState(true, true)
		return
	end
	if state == MatchConfig.States.ReadyToStart then
		setButtonState(true, false)
		return
	end
	setButtonState(false, false)

	if state ~= MatchConfig.States.Starting then
		return
	end
	-- One whistle per entry into Starting. StartedAt is still 0 at this point,
	-- so the guard keys off the state transition itself.
	if lastAnnouncedState == MatchConfig.States.Starting then
		return
	end
	lastAnnouncedState = MatchConfig.States.Starting
	log("Match starting")
	playStartPresentation()
end

-- Called by ExperienceFlowController once every gameplay controller has
-- initialized and the HUD is mounted.
function MatchPresentationController.SignalReady()
	local matchFolder = ReplicatedStorage:FindFirstChild(MatchConfig.FolderName)
	local remote = matchFolder and matchFolder:FindFirstChild(MatchConfig.ReadyRemoteName)
	if remote and remote:IsA("RemoteEvent") then
		remote:FireServer()
		log("Client ready signalled")
	end
end

function MatchPresentationController.Initialize()
	if initialized then
		return
	end
	initialized = true
	lastAnnouncedState = ""
	buildGui()

	folder = ReplicatedStorage:FindFirstChild(MatchConfig.FolderName) :: Folder?
	if not folder then
		folder = ReplicatedStorage:WaitForChild(MatchConfig.FolderName, 10) :: Folder?
	end
	if folder then
		local remote = folder:FindFirstChild(MatchConfig.StartRequestRemoteName)
			or folder:WaitForChild(MatchConfig.StartRequestRemoteName, 5)
		if remote and remote:IsA("RemoteEvent") then
			startRemote = remote
		end
		stateConnection = folder:GetAttributeChangedSignal(MatchConfig.StateAttributeName):Connect(onStateChanged)
		onStateChanged()
	end
end

function MatchPresentationController.Destroy()
	if not initialized then
		return
	end
	initialized = false
	if stateConnection then
		stateConnection:Disconnect()
		stateConnection = nil
	end
	if gui then
		gui:Destroy()
		gui = nil
		card = nil
		startButton = nil
	end
	startRemote = nil
	folder = nil
	lastAnnouncedState = ""
	localPlayer:SetAttribute("Beyond90MatchState", nil)
end

return MatchPresentationController
