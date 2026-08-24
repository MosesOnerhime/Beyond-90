local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Assets = require(ReplicatedStorage.Shared.Config.UIAssetConfig)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local Theme = require(script.Parent.Parent.Theme)
local UIUtil = require(script.Parent.Parent.Components.UIUtil)

local GameplayHUD = {}

local function glass(parent, name, size, position)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = size
	frame.Position = position
	frame.BackgroundColor3 = Theme.Panel
	frame.BackgroundTransparency = 0.13
	frame.BorderSizePixel = 0
	frame.Parent = parent
	UIUtil.AddCorner(frame)
	UIUtil.AddStroke(frame, Theme.Stroke, 1)
	return frame
end

local function findPitchBounds(): BasePart?
	for _, descendant in Workspace:GetDescendants() do
		if descendant:IsA("BasePart") and descendant:GetAttribute("Beyond90GameplayBounds") == true then
			return descendant
		end
	end
	return nil
end

function GameplayHUD.Create(parent: Instance, callbacks)
	local frame = Instance.new("Frame")
	frame.Name = "GameplayHUD"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundTransparency = 1
	frame.Visible = false
	frame.Parent = parent

	local match = glass(frame, "MatchHeader", UDim2.fromOffset(410, 58), UDim2.fromOffset(20, 18))
	UIUtil.CreateImage(match, "Logo", Assets.Logo, UDim2.fromOffset(82, 55), UDim2.fromOffset(4, 1))
	local mode = UIUtil.CreateText(match, "Mode", "TRAINING", UDim2.fromOffset(145, 22), UDim2.fromOffset(94, 8), Theme.Fonts.Navigation, 13)
	mode.TextColor3 = Theme.AccentCyan
	local detail = UIUtil.CreateText(match, "Detail", "FREE PRACTICE", UDim2.fromOffset(145, 18), UDim2.fromOffset(94, 31), Theme.Fonts.Caption, 9)
	detail.TextColor3 = Theme.MutedText
	local clock = UIUtil.CreateText(match, "Clock", "00:00", UDim2.fromOffset(100, 34), UDim2.new(1, -114, 0, 12), Theme.Fonts.Statistics, 20)
	clock.TextXAlignment = Enum.TextXAlignment.Right

	local pingPanel = glass(frame, "Ping", UDim2.fromOffset(112, 38), UDim2.new(1, -132, 0, 20))
	UIUtil.CreateImage(pingPanel, "Icon", Assets.Social.Network, UDim2.fromOffset(21, 21), UDim2.fromOffset(11, 8))
	local ping = UIUtil.CreateText(pingPanel, "Value", "-- ms", UDim2.fromOffset(65, 24), UDim2.fromOffset(38, 7), Theme.Fonts.Statistics, 12)
	ping.TextXAlignment = Enum.TextXAlignment.Right

	local playerPanel = glass(frame, "PlayerPanel", UDim2.fromOffset(330, 78), UDim2.new(0, 22, 1, -102))
	local badge = UIUtil.CreateImage(playerPanel, "Badge", Assets.ClubBadgeSheet, UDim2.fromOffset(56, 56), UDim2.fromOffset(10, 11))
	badge.ImageRectOffset = Vector2.new(0, 0)
	badge.ImageRectSize = Vector2.new(418, 418)
	UIUtil.CreateText(playerPanel, "Number", "10", UDim2.fromOffset(44, 38), UDim2.fromOffset(72, 10), Theme.Fonts.Display, 26)
	local playerName = UIUtil.CreateText(playerPanel, "Name", string.upper(Players.LocalPlayer.DisplayName), UDim2.fromOffset(185, 24), UDim2.fromOffset(112, 10), Theme.Fonts.Navigation, 13)
	local staminaText = UIUtil.CreateText(playerPanel, "StaminaLabel", "STAMINA", UDim2.fromOffset(80, 16), UDim2.fromOffset(74, 48), Theme.Fonts.Caption, 9)
	staminaText.TextColor3 = Theme.MutedText
	local staminaTrack = Instance.new("Frame")
	staminaTrack.Size = UDim2.fromOffset(172, 5)
	staminaTrack.Position = UDim2.fromOffset(128, 54)
	staminaTrack.BackgroundColor3 = Color3.fromRGB(47, 58, 85)
	staminaTrack.BorderSizePixel = 0
	staminaTrack.Parent = playerPanel
	local stamina = Instance.new("Frame")
	stamina.Size = UDim2.fromScale(1, 1)
	stamina.BackgroundColor3 = Theme.AccentCyan
	stamina.BorderSizePixel = 0
	stamina.Parent = staminaTrack
	local staminaValue = UIUtil.CreateText(playerPanel, "Stamina", "100%", UDim2.fromOffset(55, 18), UDim2.new(1, -66, 0, 59), Theme.Fonts.Statistics, 9)
	staminaValue.TextXAlignment = Enum.TextXAlignment.Right

	local radar = glass(frame, "Minimap", UDim2.fromOffset(310, 136), UDim2.new(0.5, -155, 1, -155))
	local pitch = Instance.new("Frame")
	pitch.Name = "Pitch"
	pitch.Size = UDim2.new(1, -22, 1, -18)
	pitch.Position = UDim2.fromOffset(11, 9)
	pitch.BackgroundColor3 = Color3.fromRGB(12, 37, 50)
	pitch.BackgroundTransparency = 0.26
	pitch.BorderSizePixel = 0
	pitch.ClipsDescendants = true
	pitch.Parent = radar
	UIUtil.AddStroke(pitch, Color3.fromRGB(150, 188, 208), 1)
	local halfway = Instance.new("Frame")
	halfway.Size = UDim2.new(0, 1, 1, 0)
	halfway.Position = UDim2.fromScale(0.5, 0)
	halfway.BackgroundColor3 = Color3.fromRGB(125, 157, 178)
	halfway.BackgroundTransparency = 0.4
	halfway.BorderSizePixel = 0
	halfway.Parent = pitch
	local markers: { [Player]: Frame } = {}
	local ballMarker = Instance.new("Frame")
	ballMarker.Name = "Ball"
	ballMarker.AnchorPoint = Vector2.new(0.5, 0.5)
	ballMarker.Size = UDim2.fromOffset(6, 6)
	ballMarker.BackgroundColor3 = Color3.new(1, 1, 1)
	ballMarker.BorderSizePixel = 0
	ballMarker.Parent = pitch
	UIUtil.AddCorner(ballMarker, UDim.new(1, 0))

	local legend = glass(frame, "Controls", UDim2.fromOffset(220, 196), UDim2.new(1, -242, 1, -222))
	UIUtil.CreateText(legend, "Title", "CONTROLS", UDim2.new(1, -24, 0, 22), UDim2.fromOffset(12, 10), Theme.Fonts.Navigation, 11)
	local controls = UIUtil.CreateText(legend, "List", "RT   SPRINT\nY     THROUGH BALL\nX     PASS\nX ×2  LOB PASS\nB     SHOOT\nA     JUMP", UDim2.new(1, -28, 0, 145), UDim2.fromOffset(14, 39), Theme.Fonts.Caption, 11)
	controls.TextColor3 = Theme.MutedText
	controls.TextYAlignment = Enum.TextYAlignment.Top
	controls.LineHeight = 1.55

	local reset = Instance.new("TextButton")
	reset.Name = "ResetBall"
	reset.Size = UDim2.fromOffset(142, 38)
	reset.Position = UDim2.new(1, -164, 0, 68)
	reset.BackgroundColor3 = Theme.Panel
	reset.Text = "RESET BALL"
	reset.TextColor3 = Theme.Text
	reset.Font = Theme.Fonts.Navigation
	reset.TextSize = 11
	reset.Parent = frame
	UIUtil.AddCorner(reset)
	UIUtil.AddStroke(reset)
	reset.Activated:Connect(callbacks.ResetBall)
	local menu = reset:Clone()
	menu.Name = "ExitTraining"
	menu.Position = UDim2.new(1, -164, 0, 112)
	menu.Text = "RETURN TO MENU"
	menu.Parent = frame
	menu.Activated:Connect(callbacks.ReturnToMenu)

	local startedAt = os.clock()
	local accumulator = 0
	local pingAccumulator = 0
	local bounds: BasePart? = nil
	local function mapPosition(worldPosition: Vector3): UDim2?
		bounds = bounds or findPitchBounds()
		if not bounds then return nil end
		local center = bounds:GetAttribute("PitchCenter")
		local lengthAxis = bounds:GetAttribute("PitchLengthAxis")
		local widthAxis = bounds:GetAttribute("PitchWidthAxis")
		local length = bounds:GetAttribute("PitchLength")
		local width = bounds:GetAttribute("PitchWidth")
		if typeof(center) ~= "Vector3" or typeof(lengthAxis) ~= "Vector3" or typeof(widthAxis) ~= "Vector3"
			or typeof(length) ~= "number" or typeof(width) ~= "number" then return nil end
		local offset = worldPosition - center
		return UDim2.fromScale(math.clamp(0.5 + offset:Dot(lengthAxis) / length, 0, 1), math.clamp(0.5 + offset:Dot(widthAxis) / width, 0, 1))
	end
	local connection = RunService.Heartbeat:Connect(function(deltaTime)
		if not frame.Visible then return end
		clock.Text = string.format("%02d:%02d", math.floor((os.clock() - startedAt) / 60), math.floor(os.clock() - startedAt) % 60)
		accumulator += deltaTime
		pingAccumulator += deltaTime
		if pingAccumulator >= 1 then
			pingAccumulator = 0
			local value
			pcall(function() value = Stats.Network.ServerStatsItem["Data Ping"]:GetValue() end)
			if typeof(value) == "number" then
				ping.Text = string.format("%.0f ms", value)
				ping.TextColor3 = if value < 90 then Theme.Good elseif value < 170 then Theme.Warning else Theme.Poor
			end
		end
		if accumulator < 0.1 then return end
		accumulator = 0
		for _, player in Players:GetPlayers() do
			local marker = markers[player]
			if not marker then
				marker = Instance.new("Frame")
				marker.AnchorPoint = Vector2.new(0.5, 0.5)
				marker.Size = UDim2.fromOffset(if player == Players.LocalPlayer then 8 else 6, if player == Players.LocalPlayer then 8 else 6)
				marker.BackgroundColor3 = if player == Players.LocalPlayer then Theme.AccentCyan else Theme.AccentViolet
				marker.BorderSizePixel = 0
				marker.Parent = pitch
				UIUtil.AddCorner(marker, UDim.new(1, 0))
				markers[player] = marker
			end
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			local position = root and root:IsA("BasePart") and mapPosition(root.Position)
			marker.Visible = position ~= nil
			if position then marker.Position = position end
		end
		local rootFolder = Workspace:FindFirstChild(GameConfig.WorkspaceContainerName)
		local ball = rootFolder and rootFolder:FindFirstChild("Football", true)
		local ballPosition = ball and ball:IsA("BasePart") and mapPosition(ball.Position)
		ballMarker.Visible = ballPosition ~= nil
		if ballPosition then ballMarker.Position = ballPosition end
	end)
	UserInputService.LastInputTypeChanged:Connect(function(inputType)
		local keyboard = inputType == Enum.UserInputType.Keyboard or inputType == Enum.UserInputType.MouseMovement
		controls.Text = if keyboard
			then "SHIFT  SPRINT\nQ      THROUGH BALL\nE      PASS\nE ×2   LOB PASS\nF      SHOOT\nSPACE  JUMP"
			else "RT   SPRINT\nY     THROUGH BALL\nX     PASS\nX ×2  LOB PASS\nB     SHOOT\nA     JUMP"
	end)

	return { Frame = frame, Destroy = function() connection:Disconnect() end }
end

return GameplayHUD
