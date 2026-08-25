local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local React = require(ReplicatedStorage.Shared.ReactPackages).React
local Assets = require(ReplicatedStorage.Shared.Config.UIAssetConfig)
local BallConfig = require(ReplicatedStorage.Shared.Config.BallConfig)
local FootballTeamConfig = require(ReplicatedStorage.Shared.Config.FootballTeamConfig)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local GameModeConfig = require(ReplicatedStorage.Shared.Config.GameModeConfig)
local PitchCoordinateTransform = require(ReplicatedStorage.Shared.Football.PitchCoordinateTransform)
local Theme = require(script.Parent.Parent.Theme)
local ReactUI = require(script.Parent.Parent.Components.ReactUI)
local InputController = require(script.Parent.Parent.Parent.Controllers.InputController)

local localPlayer = Players.LocalPlayer

local function panel(props, children)
	local merged = {
		BackgroundColor3 = Color3.fromRGB(5, 9, 21),
		BackgroundTransparency = 0.18,
		BorderSizePixel = 0,
	}
	for key, value in props do merged[key] = value end
	children = children or {}
	children.Corner = children.Corner or ReactUI.Corner(8)
	children.Stroke = children.Stroke or ReactUI.Stroke(Theme.AccentViolet, 1.25, 0.24)
	return React.createElement("Frame", merged, children)
end

local function label(props)
	local merged = {
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Body,
		TextColor3 = Theme.Text,
	}
	for key, value in props do merged[key] = value end
	return React.createElement("TextLabel", merged)
end

local function findPitchBounds(): BasePart?
	local container = Workspace:FindFirstChild(GameConfig.WorkspaceContainerName)
	local pitch = container and container:FindFirstChild("Pitch")
	local bounds = pitch and pitch:FindFirstChild("GameplayBounds")
	return if bounds and bounds:IsA("BasePart") then bounds else nil
end

local function findGoalCenter(goalId: string?): Vector3?
	local stadium = Workspace:FindFirstChild("StadiumDevelopment")
	local goalBounds = stadium and stadium:FindFirstChild("GoalBounds")
	local goal = goalBounds and goalBounds:FindFirstChild(tostring(goalId) .. "GoalBounds")
	return if goal and goal:IsA("BasePart") then goal.Position else nil
end

local function Minimap()
	local markers, setMarkers = React.useState({})
	local ballPosition, setBallPosition = React.useState(nil)
	local mobile = UserInputService.TouchEnabled
	React.useEffect(function()
		local trackedPlayers = Players:GetPlayers()
		local elapsed = 0
		local playerAdded = Players.PlayerAdded:Connect(function(player)
			table.insert(trackedPlayers, player)
		end)
		local playerRemoving = Players.PlayerRemoving:Connect(function(player)
			local index = table.find(trackedPlayers, player)
			if index then table.remove(trackedPlayers, index) end
		end)
		local bounds: BasePart? = nil
		local ball: BasePart? = nil
		local transform = nil
		local function project(worldPosition: Vector3): UDim2?
			bounds = bounds or findPitchBounds()
			if not bounds then return nil end
			transform = transform or PitchCoordinateTransform.FromBounds(bounds)
			local teamId = FootballTeamConfig.Normalize(localPlayer:GetAttribute(FootballTeamConfig.AttributeName))
			local mapping = FootballTeamConfig.GetGoalMapping(teamId)
			local defendingGoal = findGoalCenter(mapping and mapping.DefendedGoalId or "Home")
			local attackingGoal = findGoalCenter(mapping and mapping.AttackingGoalId or "Away")
			if not transform or not defendingGoal or not attackingGoal then return nil end
			local coordinate = PitchCoordinateTransform.Project(transform, worldPosition, defendingGoal, attackingGoal)
			return UDim2.fromScale(coordinate.X, coordinate.Y)
		end
		local heartbeat = RunService.Heartbeat:Connect(function(dt)
			elapsed += dt
			if elapsed < 0.1 then return end
			elapsed = 0
			local nextMarkers = {}
			for _, player in trackedPlayers do
				local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
				if root and root:IsA("BasePart") then
					local position = project(root.Position)
					if position then
						local sameTeam = player == localPlayer
							or player:GetAttribute(FootballTeamConfig.AttributeName) == localPlayer:GetAttribute(FootballTeamConfig.AttributeName)
						table.insert(nextMarkers, {
							Key = tostring(player.UserId),
							Position = position,
							Friendly = sameTeam,
							Local = player == localPlayer,
						})
					end
				end
			end
			setMarkers(nextMarkers)
			if not ball or not ball.Parent then
				local container = Workspace:FindFirstChild(GameConfig.WorkspaceContainerName)
				local ballFolder = container and container:FindFirstChild("Ball")
				local found = ballFolder and ballFolder:FindFirstChild(BallConfig.Name)
				ball = if found and found:IsA("BasePart") then found else nil
			end
			setBallPosition(if ball then project(ball.Position) else nil)
		end)
		return function()
			heartbeat:Disconnect()
			playerAdded:Disconnect()
			playerRemoving:Disconnect()
		end
	end, {})

	local pitchChildren = {
		Outline = ReactUI.Stroke(Color3.fromRGB(230, 238, 242), 1.4, 0.15),
		Halfway = React.createElement("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.005, 1), BackgroundColor3 = Color3.fromRGB(224, 235, 238),
			BackgroundTransparency = 0.2, BorderSizePixel = 0,
		}),
		CenterCircle = React.createElement("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.19, 0.42), BackgroundTransparency = 1,
		}, { Corner = ReactUI.Corner(100), Stroke = ReactUI.Stroke(Color3.fromRGB(224, 235, 238), 1.2, 0.25) }),
		LeftBox = React.createElement("Frame", {
			AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5),
			Size = UDim2.fromScale(0.17, 0.62), BackgroundTransparency = 1,
		}, { Stroke = ReactUI.Stroke(Color3.fromRGB(224, 235, 238), 1.1, 0.28) }),
		RightBox = React.createElement("Frame", {
			AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(1, 0.5),
			Size = UDim2.fromScale(0.17, 0.62), BackgroundTransparency = 1,
		}, { Stroke = ReactUI.Stroke(Color3.fromRGB(224, 235, 238), 1.1, 0.28) }),
	}
	for _, marker in markers do
		pitchChildren["Player" .. marker.Key] = React.createElement("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = marker.Position,
			Size = UDim2.fromOffset(marker.Local and 13 or 9, marker.Local and 13 or 9),
			BackgroundTransparency = 1,
			Image = marker.Friendly and Assets.HUD.Minimap.Friendly or Assets.HUD.Minimap.Opponent,
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = marker.Local and 4 or 3,
		})
	end
	if ballPosition then
		pitchChildren.Ball = React.createElement("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = ballPosition,
			Size = UDim2.fromOffset(9, 9), BackgroundTransparency = 1,
			Image = Assets.HUD.Minimap.Ball, ScaleType = Enum.ScaleType.Fit, ZIndex = 5,
		})
	end
	return panel({
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 0.965),
		Size = UDim2.fromScale(if mobile then 0.135 else 0.11, if mobile then 0.205 else 0.145),
		BackgroundColor3 = Color3.fromRGB(3, 10, 18),
		BackgroundTransparency = 0.3,
	}, {
		AspectRatio = React.createElement("UIAspectRatioConstraint", {
			AspectRatio = 1.4,
			DominantAxis = Enum.DominantAxis.Height,
		}),
		Pitch = React.createElement("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.9, 0.84), BackgroundColor3 = Color3.fromRGB(8, 42, 32),
			BackgroundTransparency = 0.28, BorderSizePixel = 0,
		}, {
			Gradient = ReactUI.Gradient(Color3.fromRGB(10, 52, 39), Color3.fromRGB(5, 27, 25), 90),
			PitchContent = React.createElement("Frame", {
				Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
			}, pitchChildren),
		}),
	})
end

local function ControlRow(props)
	return React.createElement("Frame", {
		LayoutOrder = props.Order, Size = UDim2.new(1, 0, 0.18, 0), BackgroundTransparency = 1,
	}, {
		Glyph = props.Gamepad and React.createElement("ImageLabel", {
			Position = UDim2.fromScale(0.04, 0.12), Size = UDim2.fromScale(0.22, 0.76),
			BackgroundTransparency = 1, Image = props.Glyph, ScaleType = Enum.ScaleType.Fit,
		}) or panel({
			Position = UDim2.fromScale(0.06, 0.16), Size = UDim2.fromScale(0.18, 0.68),
			BackgroundColor3 = Color3.fromRGB(12, 18, 33), BackgroundTransparency = 0.05,
		}, {
			Key = label({ Size = UDim2.fromScale(1, 1), Font = Theme.Fonts.Navigation, Text = props.Key, TextColor3 = Theme.AccentCyan, TextScaled = true }),
		}),
		Action = label({
			Position = UDim2.fromScale(0.3, 0.12), Size = UDim2.fromScale(0.66, 0.76),
			Font = Theme.Fonts.Navigation, Text = props.Action, TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
	})
end

local function TouchActionButton(props)
	local pressed, setPressed = React.useState(false)
	local heldRef = React.useRef(false)
	local function setHeld(nextPressed: boolean)
		if heldRef.current == nextPressed then return end
		heldRef.current = nextPressed
		setPressed(nextPressed)
		props.OnChanged(nextPressed)
	end
	React.useEffect(function()
		return function()
			if heldRef.current then
				heldRef.current = false
				props.OnChanged(false)
			end
		end
	end, {})
	return React.createElement("TextButton", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = props.Position, Size = props.Size,
		BackgroundColor3 = if pressed then Color3.fromRGB(33, 99, 157) else Color3.fromRGB(6, 16, 35),
		BackgroundTransparency = if pressed then 0.08 else 0.22, BorderSizePixel = 0,
		AutoButtonColor = false, Font = Theme.Fonts.Navigation, Text = props.Text,
		TextColor3 = Color3.fromRGB(235, 243, 255), TextSize = props.TextSize or 11,
		ZIndex = 32,
		[React.Event.InputBegan] = function(_, input)
			if input.UserInputType == Enum.UserInputType.Touch then setHeld(true) end
		end,
		[React.Event.InputEnded] = function(_, input)
			if input.UserInputType == Enum.UserInputType.Touch then setHeld(false) end
		end,
	}, {
		Corner = ReactUI.Corner(100),
		Stroke = ReactUI.Stroke(if pressed then Theme.AccentCyan else Color3.fromRGB(111, 143, 187), if pressed then 2 else 1, if pressed then 0.12 else 0.42),
	})
end

local function MobileTouchControls()
	local padRef = React.useRef(nil)
	local activeTouchRef = React.useRef(nil)
	local hideVersionRef = React.useRef(0)
	local padTweenRef = React.useRef(nil)
	local knobOffset, setKnobOffset = React.useState(Vector2.zero)
	local function fadePad(visible: boolean)
		local pad = padRef.current
		if not pad then return end
		if padTweenRef.current then padTweenRef.current:Cancel() end
		local animation = TweenService:Create(
			pad,
			TweenInfo.new(if visible then 0.14 else 0.42, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			{ GroupTransparency = if visible then 0 else 1 }
		)
		padTweenRef.current = animation
		animation:Play()
	end
	local function showPad()
		hideVersionRef.current += 1
		fadePad(true)
	end
	local function schedulePadHide()
		hideVersionRef.current += 1
		local version = hideVersionRef.current
		task.delay(2, function()
			if version == hideVersionRef.current and activeTouchRef.current == nil then
				fadePad(false)
			end
		end)
	end
	local function updateTouch(position: Vector3)
		local pad = padRef.current
		if not pad then return end
		local center = pad.AbsolutePosition + pad.AbsoluteSize * 0.5
		local radius = math.max(math.min(pad.AbsoluteSize.X, pad.AbsoluteSize.Y) * 0.37, 1)
		local delta = Vector2.new(position.X, position.Y) - center
		if delta.Magnitude > radius then delta = delta.Unit * radius end
		setKnobOffset(delta)
		InputController.SetTouchMoveVector(Vector2.new(delta.X / radius, -delta.Y / radius))
	end
	React.useEffect(function()
		schedulePadHide()
		local changed = UserInputService.InputChanged:Connect(function(input)
			if input == activeTouchRef.current then updateTouch(input.Position) end
		end)
		local ended = UserInputService.InputEnded:Connect(function(input)
			if input ~= activeTouchRef.current then return end
			activeTouchRef.current = nil
			setKnobOffset(Vector2.zero)
			InputController.SetTouchMoveVector(Vector2.zero)
			schedulePadHide()
		end)
		return function()
			hideVersionRef.current += 1
			if padTweenRef.current then padTweenRef.current:Cancel() end
			changed:Disconnect()
			ended:Disconnect()
			activeTouchRef.current = nil
			InputController.ReleaseTouchInputs()
		end
	end, {})
	return React.createElement("Frame", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 30,
	}, {
		Touchpad = React.createElement("CanvasGroup", {
			ref = padRef, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.13, 0.60),
			Size = UDim2.fromOffset(118, 118), BackgroundColor3 = Color3.fromRGB(4, 13, 29),
			BackgroundTransparency = 0.35, BorderSizePixel = 0, Active = true, GroupTransparency = 0, ZIndex = 31,
			[React.Event.InputBegan] = function(_, input)
				if input.UserInputType ~= Enum.UserInputType.Touch or activeTouchRef.current then return end
				showPad()
				activeTouchRef.current = input
				updateTouch(input.Position)
			end,
		}, {
			Corner = ReactUI.Corner(100),
			Stroke = ReactUI.Stroke(Color3.fromRGB(116, 155, 201), 1.5, 0.42),
			Inner = React.createElement("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.63, 0.63), BackgroundTransparency = 1, ZIndex = 31,
			}, { Corner = ReactUI.Corner(100), Stroke = ReactUI.Stroke(Color3.fromRGB(97, 128, 169), 1, 0.58) }),
			Knob = React.createElement("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, knobOffset.X, 0.5, knobOffset.Y),
				Size = UDim2.fromOffset(48, 48), BackgroundColor3 = Color3.fromRGB(31, 81, 133),
				BackgroundTransparency = 0.08, BorderSizePixel = 0, ZIndex = 32,
			}, { Corner = ReactUI.Corner(100), Stroke = ReactUI.Stroke(Theme.AccentCyan, 1.5, 0.24) }),
		}),
		Shoot = React.createElement(TouchActionButton, { Position = UDim2.fromScale(0.94, 0.73), Size = UDim2.fromOffset(82, 82), Text = "SHOOT", TextSize = 12, OnChanged = function(value) InputController.SetTouchFootballAction("Shoot", value) end }),
		Pass = React.createElement(TouchActionButton, { Position = UDim2.fromScale(0.84, 0.84), Size = UDim2.fromOffset(72, 72), Text = "PASS", OnChanged = function(value) InputController.SetTouchFootballAction("GroundPass", value) end }),
		Through = React.createElement(TouchActionButton, { Position = UDim2.fromScale(0.95, 0.89), Size = UDim2.fromOffset(66, 66), Text = "THRU", OnChanged = function(value) InputController.SetTouchFootballAction("ThroughPass", value) end }),
		KnockOn = React.createElement(TouchActionButton, { Position = UDim2.fromScale(0.76, 0.72), Size = UDim2.fromOffset(62, 62), Text = "PUSH", OnChanged = function(value) InputController.SetTouchFootballAction("KnockOn", value) end }),
		Sprint = React.createElement(TouchActionButton, { Position = UDim2.fromScale(0.7, 0.87), Size = UDim2.fromOffset(78, 58), Text = "SPRINT", OnChanged = InputController.SetTouchSprint }),
	})
end

local function GameplayHUD(props)
	local ping, setPing = React.useState(nil)
	local elapsed, setElapsed = React.useState(0)
	local score, setScore = React.useState({ Home = 0, Away = 0 })
	local gamepad, setGamepad = React.useState(UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled)
	local controlsExpanded, setControlsExpanded = React.useState(true)
	local mobile = UserInputService.TouchEnabled
	React.useEffect(function()
		local startedAt = os.clock()
		local clockElapsed = 0
		local heartbeat = RunService.Heartbeat:Connect(function(dt)
			clockElapsed += dt
			if clockElapsed >= 0.1 then
				clockElapsed = 0
				setElapsed(os.clock() - startedAt)
			end
		end)
		local polling = true
		task.spawn(function()
			local folder = ReplicatedStorage:WaitForChild(GameModeConfig.ReplicatedFolderName, 10)
			local remote = folder and folder:WaitForChild(GameModeConfig.PingRemoteName, 5)
			while polling do
				local measured = nil
				if remote and remote:IsA("RemoteFunction") then
					local started = os.clock()
					local ok = pcall(function() remote:InvokeServer() end)
					if ok then measured = (os.clock() - started) * 1000 end
				end
				if not measured or measured <= 0 then
					pcall(function()
						local item = Stats.Network.ServerStatsItem["Data Ping"]
						measured = tonumber(string.match(item:GetValueString(), "[%d%.]+"))
					end)
				end
				if polling and typeof(measured) == "number" then setPing(math.max(0, measured)) end
				task.wait(1)
			end
		end)
		local inputChanged = UserInputService.LastInputTypeChanged:Connect(function(inputType)
			setGamepad(inputType.Name:find("Gamepad") ~= nil)
		end)
		return function()
			polling = false
			heartbeat:Disconnect()
			inputChanged:Disconnect()
		end
	end, {})
	React.useEffect(function()
		local folder = ReplicatedStorage:WaitForChild(GameModeConfig.ScoreFolderName, 10)
		if not folder then return nil end
		local function updateScore()
			setScore({
				Home = folder:GetAttribute(GameModeConfig.HomeScoreAttributeName) or 0,
				Away = folder:GetAttribute(GameModeConfig.AwayScoreAttributeName) or 0,
			})
		end
		updateScore()
		local homeConnection = folder:GetAttributeChangedSignal(GameModeConfig.HomeScoreAttributeName):Connect(updateScore)
		local awayConnection = folder:GetAttributeChangedSignal(GameModeConfig.AwayScoreAttributeName):Connect(updateScore)
		return function()
			homeConnection:Disconnect()
			awayConnection:Disconnect()
		end
	end, {})
	local minutes = math.floor(elapsed / 60)
	local seconds = math.floor(elapsed) % 60
	local controlData = {
		{ "RT", "SHIFT", "SPRINT" },
		{ "Y", "Q", "THROUGH BALL" },
		{ "X", "E", "PASS / X2 LOB" },
		{ "B", "F", "SHOOT" },
	}
	local controlRows = {
		Layout = React.createElement("UIListLayout", { Padding = UDim.new(0.018, 0), SortOrder = Enum.SortOrder.LayoutOrder }),
		Padding = ReactUI.Padding(4, 4, 4, 4),
	}
	for index, data in controlData do
		controlRows["Control" .. index] = React.createElement(ControlRow, {
			Order = index, Gamepad = gamepad, Glyph = Assets.HUD.Glyphs[data[1]],
			Key = data[2], Action = data[3],
		})
	end
	return React.createElement("Frame", {
		Name = "GameplayHUD", Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, {
		Scoreboard = React.createElement("Frame", {
			Position = UDim2.fromScale(0.115, 0.018), Size = UDim2.fromScale(0.255, 0.068),
			BackgroundTransparency = 1,
		}, {
			BrandClock = panel({ Size = UDim2.fromScale(0.24, 1) }, {
				Logo = React.createElement("ImageLabel", { Position = UDim2.fromScale(0.07, 0.08), Size = UDim2.fromScale(0.86, 0.34), BackgroundTransparency = 1, Image = Assets.HUD.Logo, ScaleType = Enum.ScaleType.Crop }),
				Clock = label({ Position = UDim2.fromScale(0.1, 0.5), Size = UDim2.fromScale(0.8, 0.36), Font = Theme.Fonts.Statistics, Text = string.format("%02d:%02d", minutes, seconds), TextScaled = true }),
			}),
			Score = panel({ Position = UDim2.fromScale(0.255, 0), Size = UDim2.fromScale(0.745, 1) }, {
				HomeBadge = React.createElement("ImageLabel", { Position = UDim2.fromScale(0.05, 0.16), Size = UDim2.fromScale(0.14, 0.68), BackgroundTransparency = 1, Image = Assets.HUD.HomeBadge, ScaleType = Enum.ScaleType.Fit }),
				Home = label({ Position = UDim2.fromScale(0.2, 0.22), Size = UDim2.fromScale(0.18, 0.56), Font = Theme.Fonts.Navigation, Text = "B90", TextScaled = true }),
				HomeScore = label({ Position = UDim2.fromScale(0.4, 0.22), Size = UDim2.fromScale(0.08, 0.56), Font = Theme.Fonts.HUDNumber, Text = tostring(score.Home), TextScaled = true }),
				Divider = label({ Position = UDim2.fromScale(0.49, 0.22), Size = UDim2.fromScale(0.05, 0.56), Font = Theme.Fonts.Display, Text = "-", TextColor3 = Theme.AccentViolet, TextScaled = true }),
				AwayScore = label({ Position = UDim2.fromScale(0.54, 0.22), Size = UDim2.fromScale(0.08, 0.56), Font = Theme.Fonts.HUDNumber, Text = tostring(score.Away), TextScaled = true }),
				Away = label({ Position = UDim2.fromScale(0.63, 0.22), Size = UDim2.fromScale(0.18, 0.56), Font = Theme.Fonts.Navigation, Text = "TRN", TextScaled = true }),
				AwayBadge = React.createElement("ImageLabel", { Position = UDim2.fromScale(0.82, 0.16), Size = UDim2.fromScale(0.14, 0.68), BackgroundTransparency = 1, Image = Assets.HUD.AwayBadge, ScaleType = Enum.ScaleType.Fit }),
			}),
		}),
		Ping = panel({
			AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(0.982, 0.018),
			Size = UDim2.fromScale(0.072, 0.044),
		}, {
			Icon = React.createElement("ImageLabel", { Position = UDim2.fromScale(0.1, 0.18), Size = UDim2.fromScale(0.28, 0.64), BackgroundTransparency = 1, Image = Assets.HUD.Network, ScaleType = Enum.ScaleType.Fit }),
			Value = label({ Position = UDim2.fromScale(0.4, 0.2), Size = UDim2.fromScale(0.5, 0.6), Font = Theme.Fonts.Statistics, Text = if ping then string.format("%.0fms", ping) else "--ms", TextColor3 = if not ping or ping < 90 then Theme.Good elseif ping < 170 then Theme.Warning else Theme.Poor, TextScaled = true }),
		}),
		PlayerPanel = panel({
			AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0.026, 0.935),
			Size = UDim2.fromScale(0.21, 0.1),
		}, {
			Badge = React.createElement("ImageLabel", { Position = UDim2.fromScale(0.035, 0.12), Size = UDim2.fromScale(0.22, 0.76), BackgroundTransparency = 1, Image = Assets.HUD.PlayerBadge, ScaleType = Enum.ScaleType.Fit }),
			Name = label({ Position = UDim2.fromScale(0.28, 0.12), Size = UDim2.fromScale(0.66, 0.3), Font = Theme.Fonts.Navigation, Text = "10  " .. string.upper(localPlayer.DisplayName), TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left }),
			StaminaLabel = label({ Position = UDim2.fromScale(0.28, 0.54), Size = UDim2.fromScale(0.22, 0.18), Font = Theme.Fonts.Caption, Text = "STAMINA", TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left }),
			StaminaTrack = React.createElement("Frame", { Position = UDim2.fromScale(0.51, 0.58), Size = UDim2.fromScale(0.31, 0.09), BackgroundColor3 = Color3.fromRGB(13, 17, 28), BorderSizePixel = 0 }, {
				Fill = React.createElement("Frame", { Size = UDim2.fromScale(0.82, 1), BackgroundColor3 = Theme.Good, BorderSizePixel = 0 }),
			}),
			StaminaValue = label({ Position = UDim2.fromScale(0.84, 0.53), Size = UDim2.fromScale(0.12, 0.2), Font = Theme.Fonts.Statistics, Text = "82%", TextScaled = true }),
		}),
		Radar = React.createElement(Minimap),
		Controls = not mobile and panel({
			AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromScale(0.975, 0.87),
			Size = if controlsExpanded then UDim2.fromScale(0.145, 0.255) else UDim2.fromScale(0.105, 0.047),
			BackgroundTransparency = 0.2,
		}, {
			Header = React.createElement("TextButton", {
				Size = UDim2.fromScale(1, if controlsExpanded then 0.19 else 1),
				BackgroundColor3 = Color3.fromRGB(13, 20, 40), BackgroundTransparency = 0.04,
				BorderSizePixel = 0, AutoButtonColor = false, Font = Theme.Fonts.Navigation,
				Text = if controlsExpanded then "CONTROLS       -" else "CONTROLS       +",
				TextColor3 = Theme.Text, TextSize = 12,
				[React.Event.Activated] = function() setControlsExpanded(not controlsExpanded) end,
			}, { Corner = ReactUI.Corner(6) }),
			Rows = controlsExpanded and React.createElement("Frame", {
				Position = UDim2.fromScale(0.04, 0.22), Size = UDim2.fromScale(0.92, 0.74),
				BackgroundTransparency = 1,
			}, controlRows) or nil,
		}),
		AbilitySlots = not mobile and panel({
			AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromScale(0.975, 0.955),
			Size = UDim2.fromScale(0.1, 0.055), BackgroundTransparency = 0.27,
		}, {
			Layout = React.createElement("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0.08, 0), SortOrder = Enum.SortOrder.LayoutOrder }),
			Slot1 = React.createElement("ImageLabel", { LayoutOrder = 1, Size = UDim2.fromScale(0.24, 0.72), BackgroundTransparency = 1, Image = Assets.HUD.Locks[1], ScaleType = Enum.ScaleType.Fit }),
			Slot2 = React.createElement("ImageLabel", { LayoutOrder = 2, Size = UDim2.fromScale(0.24, 0.72), BackgroundTransparency = 1, Image = Assets.HUD.Locks[2], ScaleType = Enum.ScaleType.Fit }),
			Slot3 = React.createElement("ImageLabel", { LayoutOrder = 3, Size = UDim2.fromScale(0.24, 0.72), BackgroundTransparency = 1, Image = Assets.HUD.Locks[3], ScaleType = Enum.ScaleType.Fit }),
		}),
		Reset = React.createElement("TextButton", {
			AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(0.885, 0.071),
			Size = UDim2.fromScale(0.078, 0.037), BackgroundColor3 = Color3.fromRGB(10, 17, 35),
			BackgroundTransparency = 0.08, BorderSizePixel = 0, Font = Enum.Font.GothamMedium,
			Text = "RESET BALL", TextColor3 = Color3.fromRGB(220, 227, 242), TextSize = 11,
			[React.Event.Activated] = props.ResetBall,
		}, { Corner = ReactUI.Corner(4), Stroke = ReactUI.Stroke(Color3.fromRGB(74, 88, 122), 1, 0.5) }),
		Return = React.createElement("TextButton", {
			AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(0.982, 0.071),
			Size = UDim2.fromScale(0.09, 0.037), BackgroundColor3 = Color3.fromRGB(10, 17, 35),
			BackgroundTransparency = 0.08, BorderSizePixel = 0, Font = Enum.Font.GothamMedium,
			Text = "RETURN TO MENU", TextColor3 = Color3.fromRGB(220, 227, 242), TextSize = 11,
			[React.Event.Activated] = props.ReturnToMenu,
		}, { Corner = ReactUI.Corner(4), Stroke = ReactUI.Stroke(Color3.fromRGB(74, 88, 122), 1, 0.5) }),
		MobileControls = mobile and React.createElement(MobileTouchControls) or nil,
	})
end

return GameplayHUD
