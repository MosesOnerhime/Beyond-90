local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local React = require(ReplicatedStorage.Shared.ReactPackages).React
local Assets = require(ReplicatedStorage.Shared.Config.UIAssetConfig)
local AIConfig = require(ReplicatedStorage.Shared.Config.AIConfig)
local BallConfig = require(ReplicatedStorage.Shared.Config.BallConfig)
local FootballTeamConfig = require(ReplicatedStorage.Shared.Config.FootballTeamConfig)
local GameConfig = require(ReplicatedStorage.Shared.Config.GameConfig)
local GameModeConfig = require(ReplicatedStorage.Shared.Config.GameModeConfig)
local PlayerConfig = require(ReplicatedStorage.Shared.Config.PlayerConfig)
local PitchCoordinateTransform = require(ReplicatedStorage.Shared.Football.PitchCoordinateTransform)
local Theme = require(script.Parent.Parent.Theme)
local MatchRulesConfig = require(ReplicatedStorage.Shared.Config.MatchRulesConfig)
local ControlSchemeConfig = require(ReplicatedStorage.Shared.Config.ControlSchemeConfig)
local GoalkeeperConfig = require(ReplicatedStorage.Shared.Config.GoalkeeperConfig)
local StaminaConfig = require(ReplicatedStorage.Shared.Config.StaminaConfig)
local CameraConfig = require(ReplicatedStorage.Shared.Config.CameraConfig)
local ReactUI = require(script.Parent.Parent.Components.ReactUI)
local MenuKit = require(script.Parent.Parent.Components.MenuKit)
local InputController = require(script.Parent.Parent.Parent.Controllers.InputController)

local localPlayer = Players.LocalPlayer

-- Survives HUD remounts so the controls panel does not reopen itself after the
-- player has closed it. Starts collapsed for every new client session.
local sessionControlsExpanded = false
-- Which tab the full controls reference was left on, likewise per session.
local sessionControlsTab = nil

--[[
	An authored desktop type size, adapted for this display.

	The HUD's fixed sizes ran from 9px to 14px and never changed -- measured, a
	1920x1080 monitor and a 780x360 phone rendered the identical 9px control
	prompts, because a raw TextSize is a device pixel count and nothing was
	scaling it. Theme.Size grows it on large displays and floors it at the
	readability minimum on small ones; see Theme for the derivation.
]]
local function hudSize(desktop: number): number
	return Theme.Size(Theme.Compact(), desktop)
end

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
	--[[
		Through MenuKit so a TextScaled label picks up the readability floor.

		Most of the HUD's own text is TextScaled inside a proportional box, which
		has no lower bound at all -- measured on a 780x360 phone the match clock
		came out about 8px and the stamina caption about 6px. The scorebug's
		clock and score are the first two things
		docs/ui/UI_COMPONENTS_AND_PATTERNS.md section 7 says the scorebug MUST
		prioritise, so they are the last text that should vanish on a small
		screen.
	]]
	return MenuKit.Text(merged)
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
	-- Which horizontal end of the map the local team attacks: -1 left, +1 right.
	local attackingEnd, setAttackingEnd = React.useState(0)
	local mobile = UserInputService.TouchEnabled
	-- Layout density is a question about the screen, not the input; see the note
	-- on the same pair in the HUD component below.
	local compact = Theme.Compact()
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
		--[[
			The minimap is drawn in the BROADCAST CAMERA's frame, identical for both
			teams, because the camera itself never swaps touchlines. It previously
			rotated the whole map 180 degrees for the Away team, which left the map
			disagreeing with the screen in both axes at once.

			Which end a team attacks is shown by labelling the ends instead --
			see AttackingEnd below.
		]]
		local function project(worldPosition: Vector3): UDim2?
			bounds = bounds or findPitchBounds()
			if not bounds then return nil end
			transform = transform or PitchCoordinateTransform.FromBounds(bounds)
			if not transform then return nil end
			local coordinate = PitchCoordinateTransform.Project(
				transform,
				worldPosition,
				CameraConfig.Broadcast.BroadcastSide
			)
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
			local container = Workspace:FindFirstChild(GameConfig.WorkspaceContainerName)
			local footballers = container and container:FindFirstChild(AIConfig.FootballerFolderName)
			if footballers then
				for _, character in footballers:GetChildren() do
					local root = character:IsA("Model") and character:FindFirstChild("HumanoidRootPart")
					local id = character:GetAttribute(AIConfig.Attributes.Id)
					if root and root:IsA("BasePart") and typeof(id) == "number" then
						local position = project(root.Position)
						if position then
							table.insert(nextMarkers, {
								Key = "AI" .. tostring(id),
								Position = position,
								Friendly = character:GetAttribute(FootballTeamConfig.AttributeName)
									== localPlayer:GetAttribute(FootballTeamConfig.AttributeName),
								Local = false,
							})
						end
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

			--[[
				Attacking direction is LABELLED rather than baked into the
				projection, so the map can stay aligned with the screen.
			]]
			if transform then
				local teamId = FootballTeamConfig.Normalize(
					localPlayer:GetAttribute(FootballTeamConfig.AttributeName)
				)
				local mapping = FootballTeamConfig.GetGoalMapping(teamId)
				local defendingGoal = findGoalCenter(mapping and mapping.DefendedGoalId or "Home")
				local attackingGoal = findGoalCenter(mapping and mapping.AttackingGoalId or "Away")
				if defendingGoal and attackingGoal then
					setAttackingEnd(PitchCoordinateTransform.GetAttackingEndSign(
						transform, defendingGoal, attackingGoal, CameraConfig.Broadcast.BroadcastSide
					))
				end
			end
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
	if attackingEnd ~= 0 then
		local attackX = if attackingEnd > 0 then 1 else 0
		pitchChildren.AttackingEnd = React.createElement("Frame", {
			AnchorPoint = Vector2.new(attackX, 0.5),
			Position = UDim2.fromScale(attackX, 0.5),
			Size = UDim2.fromScale(0.035, 1),
			BackgroundColor3 = Theme.AccentCyan,
			BackgroundTransparency = 0.55,
			BorderSizePixel = 0,
			ZIndex = 2,
		})
		pitchChildren.DefendingEnd = React.createElement("Frame", {
			AnchorPoint = Vector2.new(1 - attackX, 0.5),
			Position = UDim2.fromScale(1 - attackX, 0.5),
			Size = UDim2.fromScale(0.035, 1),
			BackgroundColor3 = Theme.Poor,
			BackgroundTransparency = 0.62,
			BorderSizePixel = 0,
			ZIndex = 2,
		})
	end
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
		-- Mobile sits closer to the bottom edge and is slightly smaller, so the
		-- lower HUD row reads as one band without crowding the touch controls.
		-- Desktop framing is unchanged.
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, if compact then 0.995 else 0.965),
		Size = UDim2.fromScale(if compact then 0.142 else 0.125, if compact then 0.205 else 0.16),
		BackgroundColor3 = Color3.fromRGB(3, 10, 18),
		BackgroundTransparency = 0.3,
	}, {
		AspectRatio = React.createElement("UIAspectRatioConstraint", {
			AspectRatio = 1.5,
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

-- Control hint row, matched to ref/mockup 4.png: a fixed-size rounded glyph badge
-- with a coloured stroke, then a left-aligned uppercase label at a fixed text
-- size. Fixed offsets keep the text inside its container instead of scaling it
-- until it overflows.
--[[
	CONTROL REFERENCE TYPOGRAPHY (§21).

	Rows were too tall and their glyphs too large for the amount of text beside
	them, so long actions such as "THROUGH PASS" truncated while the row itself
	wasted vertical space. Tightening the row and the glyph and dropping the
	label a point leaves the action names room to fit at their natural size.
]]
local CONTROL_ROW_HEIGHT = 22
local CONTROL_GLYPH_SIZE = 22

-- Small uppercase divider between the CONTROLLER and KEYBOARD groups.
local function ControlSectionRow(props)
	return React.createElement("Frame", {
		LayoutOrder = props.Order,
		Size = UDim2.new(1, 0, 0, 16),
		BackgroundTransparency = 1,
	}, {
		Title = React.createElement("TextLabel", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 0, 1, -2),
			Size = UDim2.new(1, 0, 0, 11),
			BackgroundTransparency = 1,
			Font = Theme.Fonts.HUDLabel,
			Text = props.Title,
			TextColor3 = Theme.FaintText,
			TextSize = hudSize(9),
			TextXAlignment = Enum.TextXAlignment.Left,
		}),
	})
end

-- Scheme tab for the expanded controls reference.
local function ControlsTab(props)
	local selected = props.Selected
	return React.createElement("TextButton", {
		LayoutOrder = props.Order,
		Size = UDim2.fromOffset(104, 24),
		BackgroundColor3 = if selected then Theme.PanelSelected else Color3.fromRGB(11, 17, 34),
		BackgroundTransparency = if selected then 0.04 else 0.34,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Font = Theme.Fonts.HUDLabel,
		Text = props.Label,
		TextColor3 = if selected then Theme.SelectedText else Theme.MutedText,
		TextSize = hudSize(10),
		ZIndex = 42,
		[React.Event.Activated] = props.Select,
	}, {
		Corner = ReactUI.Corner(5),
		Stroke = ReactUI.Stroke(
			if selected then Theme.StrokeBright else Theme.Stroke,
			1,
			if selected then 0.2 else 0.55
		),
	})
end

local function ControlRow(props)
	local accent = props.Accent or Theme.AccentCyan
	--[[
		A KEY CHIP IS AS WIDE AS ITS KEY.

		The chip was a fixed 22px square, which suits "V" or "E" and cannot hold
		"SHIFT" -- measured, that needed 25px of glyphs in the 22px chip and
		spilled over the edge. A UITextSizeConstraint sat here to catch exactly
		this, but a constraint only takes effect when TextScaled is set, and it
		was not, so it had never done anything.

		Both halves are fixed: the chip grows for longer keys the way a real key
		pill does, and TextScaled plus the constraint keeps the text inside it
		without dropping below the readability floor. The action label starts
		after whatever width the chip ends up with, so rows still line up.
	]]
	local keyText = tostring(props.Key or "")
	local chipWidth = math.max(CONTROL_GLYPH_SIZE, 10 + #keyText * 7)
	return React.createElement("Frame", {
		LayoutOrder = props.Order,
		Size = UDim2.new(1, 0, 0, CONTROL_ROW_HEIGHT),
		BackgroundTransparency = 1,
	}, {
		Glyph = props.Gamepad and React.createElement("ImageLabel", {
			AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0),
			Size = UDim2.fromOffset(CONTROL_GLYPH_SIZE, CONTROL_GLYPH_SIZE),
			BackgroundTransparency = 1, Image = props.Glyph, ScaleType = Enum.ScaleType.Fit,
		}) or React.createElement("Frame", {
			AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0),
			Size = UDim2.fromOffset(chipWidth, CONTROL_GLYPH_SIZE),
			BackgroundColor3 = Color3.fromRGB(11, 17, 34),
			BackgroundTransparency = 0.1, BorderSizePixel = 0,
		}, {
			Corner = ReactUI.Corner(7),
			Stroke = ReactUI.Stroke(accent, 1.25, 0.32),
			Key = React.createElement("TextLabel", {
				Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
				Font = Theme.Fonts.Navigation, Text = keyText, TextColor3 = accent,
				TextXAlignment = Enum.TextXAlignment.Center,
				TextYAlignment = Enum.TextYAlignment.Center,
				-- TextScaled is what makes the constraint below apply at all.
				TextScaled = true,
			}, {
				Padding = ReactUI.Padding(2, 2, 4, 4),
				-- Was MinTextSize = 7, below the readability floor the rest of the
				-- UI now holds; Max comes off the same scale so it stays above Min.
				Constraint = React.createElement("UITextSizeConstraint", {
					MaxTextSize = math.max(hudSize(10), Theme.MinimumCompactTextSize),
					MinTextSize = Theme.MinimumCompactTextSize,
				}),
			}),
		}),
		Action = React.createElement("TextLabel", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, chipWidth + 8, 0.5, 0),
			Size = UDim2.new(1, -(chipWidth + 8), 0, 14),
			BackgroundTransparency = 1,
			Font = Theme.Fonts.HUDLabel, Text = props.Action,
			TextColor3 = Theme.Text, TextSize = hudSize(11),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Center,
			TextTruncate = Enum.TextTruncate.AtEnd,
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
		TextColor3 = Color3.fromRGB(235, 243, 255),
		-- Callers pass an already-scaled size; this is the scaled default.
		TextSize = props.TextSize or hudSize(11),
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

-- eFootball-style contextual slot: the same physical button attacks when the
-- footballer has the ball and challenges for it when they do not.
local function useHasPossession(): boolean
	local hasBall, setHasBall = React.useState(false)
	React.useEffect(function()
		local elapsed = 0
		local connection = RunService.Heartbeat:Connect(function(dt)
			elapsed += dt
			if elapsed < 0.15 then return end
			elapsed = 0
			local container = Workspace:FindFirstChild(GameConfig.WorkspaceContainerName)
			local ballFolder = container and container:FindFirstChild("Ball")
			local ball = ballFolder and ballFolder:FindFirstChild(BallConfig.Name)
			local owned = ball ~= nil
				and ball:GetAttribute("State") == "Controlled"
				and ball:GetAttribute("ControllerFootballerId") == localPlayer.UserId
			setHasBall(owned)
		end)
		return function() connection:Disconnect() end
	end, {})
	return hasBall
end

--[[
	Is the local footballer a goalkeeper? (touch layout)

	Same question the desktop HUD asks, asked separately here because the touch
	cluster is built in its own component. A keeper's thumbs must not be offered
	THROUGH, PUSH or a shoot button that does nothing in goal, and the two
	buttons that DO work must say what they now do.
]]
local function useIsGoalkeeper(): boolean
	local isKeeper, setIsKeeper = React.useState(false)
	React.useEffect(function()
		local connections = {}
		local function bind(character: Model?)
			for _, connection in connections do
				connection:Disconnect()
			end
			table.clear(connections)
			if not character then
				setIsKeeper(false)
				return
			end
			local function refresh()
				setIsKeeper(
					character:GetAttribute(GoalkeeperConfig.RoleAttributeName) == GoalkeeperConfig.Role
				)
			end
			table.insert(
				connections,
				character:GetAttributeChangedSignal(GoalkeeperConfig.RoleAttributeName):Connect(refresh)
			)
			refresh()
		end
		bind(localPlayer.Character)
		local added = localPlayer.CharacterAdded:Connect(bind)
		return function()
			added:Disconnect()
			for _, connection in connections do
				connection:Disconnect()
			end
		end
	end, {})
	return isKeeper
end

--[[
	The live viewport, in pixels.

	Needed because the touch cluster has to FIT, and "fits" is a question about
	pixels rather than about scale. A phone in landscape can be as short as 360
	pixels, and a control cluster sized for a tablet simply runs off the bottom
	of one.
]]
local function useViewportSize(): Vector2
	local camera = Workspace.CurrentCamera
	local size, setSize = React.useState(if camera then camera.ViewportSize else Vector2.new(1280, 720))
	React.useEffect(function()
		local current = Workspace.CurrentCamera
		if not current then
			return nil
		end
		setSize(current.ViewportSize)
		local connection = current:GetPropertyChangedSignal("ViewportSize"):Connect(function()
			setSize(current.ViewportSize)
		end)
		return function()
			connection:Disconnect()
		end
	end, {})
	return size
end

local function MobileTouchControls()
	local touchpadDiameter = 118
	local knobDiameter = 46
	local inputRadius = touchpadDiameter * 0.5
	local knobTravelRadius = touchpadDiameter * 0.74
	local joystickExtent = knobTravelRadius + knobDiameter * 0.5
	local rootRef = React.useRef(nil)
	local padRef = React.useRef(nil)
	local knobRef = React.useRef(nil)
	local padCenterRef = React.useRef(nil)
	local activeTouchRef = React.useRef(nil)
	local hideVersionRef = React.useRef(0)
	local padTweenRef = React.useRef(nil)
	local knobTweenRef = React.useRef(nil)
	local hasPossession = useHasPossession()
	local isGoalkeeper = useIsGoalkeeper()
	--[[
		Shrink the cluster on a short screen rather than letting it run off the
		bottom. 420 is the height at which the full-size cluster (234px plus its
		margin) still leaves room for the scorebug above it; below that it scales
		down proportionally, floored so touch targets stay legal.
	]]
	local viewportSize = useViewportSize()
	local clusterScale = math.clamp(viewportSize.Y / 420, 0.78, 1)
	local padPosition, setPadPosition = React.useState(UDim2.fromScale(0.13, 0.6))
	local knobOffset, setKnobOffset = React.useState(Vector2.zero)
	local function fadePad(visible: boolean)
		local pad = padRef.current
		local knob = knobRef.current
		local info = TweenInfo.new(if visible then 0.14 else 0.42, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)
		if pad then
			if padTweenRef.current then padTweenRef.current:Cancel() end
			-- GroupTransparency alone leaves the base fill and stroke faintly
			-- visible, so fade the surface itself to fully invisible too.
			local animation = TweenService:Create(pad, info, {
				GroupTransparency = if visible then 0 else 1,
				BackgroundTransparency = if visible then 0.35 else 1,
			})
			padTweenRef.current = animation
			animation:Play()
			local padStroke = pad:FindFirstChildOfClass("UIStroke")
			if padStroke then
				TweenService:Create(padStroke, info, { Transparency = if visible then 0.42 else 1 }):Play()
			end
			local inner = pad:FindFirstChild("Inner")
			local innerStroke = inner and inner:FindFirstChildOfClass("UIStroke")
			if innerStroke then
				TweenService:Create(innerStroke, info, { Transparency = if visible then 0.58 else 1 }):Play()
			end
		end
		-- The knob lives outside the pad's CanvasGroup, so it needs its own fade
		-- to stay visually part of the same control.
		if knob then
			if knobTweenRef.current then knobTweenRef.current:Cancel() end
			local knobStroke = knob:FindFirstChildOfClass("UIStroke")
			local animation = TweenService:Create(knob, info, {
				BackgroundTransparency = if visible then 0.08 else 1,
			})
			knobTweenRef.current = animation
			animation:Play()
			if knobStroke then
				TweenService:Create(knobStroke, info, { Transparency = if visible then 0.24 else 1 }):Play()
			end
		end
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
		local center = padCenterRef.current or (pad.AbsolutePosition + pad.AbsoluteSize * 0.5)
		local rawDelta = Vector2.new(position.X, position.Y) - center
		local visualDelta = rawDelta
		if visualDelta.Magnitude > knobTravelRadius then
			visualDelta = visualDelta.Unit * knobTravelRadius
		end
		local inputDelta = rawDelta
		if inputDelta.Magnitude > inputRadius then
			inputDelta = inputDelta.Unit * inputRadius
		end
		setKnobOffset(visualDelta)
		InputController.SetTouchMoveVector(Vector2.new(inputDelta.X / inputRadius, -inputDelta.Y / inputRadius))
	end
	local function beginTouch(input)
		if input.UserInputType ~= Enum.UserInputType.Touch or activeTouchRef.current then return end
		local root = rootRef.current
		if not root then return end
		local localTouch = Vector2.new(input.Position.X, input.Position.Y) - root.AbsolutePosition
		local center = Vector2.new(
			math.clamp(localTouch.X, joystickExtent, math.max(joystickExtent, root.AbsoluteSize.X * 0.5 - joystickExtent)),
			math.clamp(localTouch.Y, joystickExtent, math.max(joystickExtent, root.AbsoluteSize.Y - joystickExtent))
		)
		padCenterRef.current = root.AbsolutePosition + center
		setPadPosition(UDim2.fromOffset(center.X, center.Y))
		setKnobOffset(Vector2.zero)
		InputController.SetTouchMoveVector(Vector2.zero)
		showPad()
		activeTouchRef.current = input
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
			if knobTweenRef.current then knobTweenRef.current:Cancel() end
			changed:Disconnect()
			ended:Disconnect()
			activeTouchRef.current = nil
			padCenterRef.current = nil
			InputController.ReleaseTouchInputs()
		end
	end, {})
	return React.createElement("Frame", {
		ref = rootRef, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 30,
	}, {
		LeftTouchCapture = React.createElement("Frame", {
			Size = UDim2.fromScale(0.5, 1), BackgroundTransparency = 1,
			BorderSizePixel = 0, Active = true, ZIndex = 30,
			[React.Event.InputBegan] = function(_, input)
				beginTouch(input)
			end,
		}),
		-- A CanvasGroup composites its descendants into its own buffer, so a knob
		-- parented inside the pad was drawn within the pad's surface and vanished
		-- as it travelled past the edge. The knob is therefore a sibling that
		-- tracks the pad's position and renders above it.
		Touchpad = React.createElement("CanvasGroup", {
			ref = padRef, AnchorPoint = Vector2.new(0.5, 0.5), Position = padPosition,
			Size = UDim2.fromOffset(touchpadDiameter, touchpadDiameter), BackgroundColor3 = Color3.fromRGB(4, 13, 29),
			BackgroundTransparency = 0.35, BorderSizePixel = 0, Active = true,
			ClipsDescendants = false, GroupTransparency = 0, ZIndex = 31,
			[React.Event.InputBegan] = function(_, input)
				beginTouch(input)
			end,
		}, {
			Corner = ReactUI.Corner(100),
			Stroke = ReactUI.Stroke(Color3.fromRGB(116, 155, 201), 1.5, 0.42),
			Inner = React.createElement("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(0.63, 0.63), BackgroundTransparency = 1, ZIndex = 31,
			}, { Corner = ReactUI.Corner(100), Stroke = ReactUI.Stroke(Color3.fromRGB(97, 128, 169), 1, 0.58) }),
		}),
		Knob = React.createElement("Frame", {
			ref = knobRef,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(
				padPosition.X.Scale, padPosition.X.Offset + knobOffset.X,
				padPosition.Y.Scale, padPosition.Y.Offset + knobOffset.Y
			),
			Size = UDim2.fromOffset(knobDiameter, knobDiameter), BackgroundColor3 = Color3.fromRGB(31, 81, 133),
			BackgroundTransparency = 0.08, BorderSizePixel = 0, ZIndex = 34,
		}, {
			Corner = ReactUI.Corner(100),
			Stroke = ReactUI.Stroke(Theme.AccentCyan, 1.5, 0.24),
		}),
		--[[
			THE ACTION CLUSTER HAS TO FIT ON THE SCREEN.

			It did not. The frame was 230 x 220, but its children are laid out by
			offset inside it and the furthest ones reach 256 x 234 -- DASH ends at
			x = 256 and THROW/PASS at y = 234. Anchored to the bottom-right corner,
			that overflow has nowhere to go but off the edge of the display. Worked
			through at 780 x 360, the numbers are:

				DASH        x 712..794   (screen is 780) -- 14px off the right
				DIVE/SHOOT  x 712..788                   --  8px off the right
				THROW/PASS  y 298..370   (screen is 360) -- 10px off the bottom

			and it is not a small-screen bug: the overflow is measured from the
			anchored corner, so those buttons hang off the edge on every touch
			device. Three of the five football controls were partly unreachable.

			Two changes. The frame is now sized to what it actually contains, so
			nothing is outside it. And on a short viewport the whole cluster is
			scaled down rather than clipped -- shrinking toward its own anchored
			corner, so it stays where the thumb expects it. The floor of 0.78
			keeps every button above the 44-pixel touch-target minimum: the
			smallest button is 58, and 58 x 0.78 = 45.

			`ButtonScale` is deliberately not applied to the movement stick. That
			is on the other thumb, has the whole left half of the screen, and does
			not overflow.
		]]
		ActionCluster = React.createElement("Frame", {
			AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -12, 1, -8),
			Size = UDim2.fromOffset(256, 234), BackgroundTransparency = 1, ZIndex = 31,
		}, {
			Scale = React.createElement("UIScale", { Scale = clusterScale }),
			--[[
				A GOALKEEPER GETS A SMALLER CLUSTER.

				Through balls, knock-ons and an outfield shot are all meaningless
				in goal, and leaving dead buttons under a thumb is worse on touch
				than anywhere else -- there is no key label to contradict, just a
				button that does nothing. So the keeper layout drops them and keeps
				the two that matter, in the same physical places their outfield
				equivalents occupy, so muscle memory survives switching position.

				DIVE is the big one, because it is the only input whose TIMING is
				being tested.
			]]
			Through = (not isGoalkeeper) and React.createElement(TouchActionButton, { Position = UDim2.fromOffset(72, 76), Size = UDim2.fromOffset(66, 66), Text = "THROUGH", TextSize = hudSize(9), OnChanged = function(value) InputController.SetTouchFootballAction("ThroughPass", value) end }) or nil,
			-- Contextual: in goal this is the DIVE; outfield it is SHOOT with the
			-- ball and PRESS without it.
			Shoot = React.createElement(TouchActionButton, {
				Position = UDim2.fromOffset(174, 50), Size = UDim2.fromOffset(76, 76),
				Text = if isGoalkeeper then "DIVE" elseif hasPossession then "SHOOT" else "PRESS",
				TextSize = hudSize(12),
				OnChanged = function(value)
					InputController.SetTouchFootballAction(
						if isGoalkeeper or not hasPossession then "Tackle" else "Shoot",
						value
					)
				end,
			}),
			Pass = React.createElement(TouchActionButton, {
				Position = UDim2.fromOffset(72, 162), Size = UDim2.fromOffset(72, 72),
				Text = if isGoalkeeper then "THROW" else "PASS",
				TextSize = if isGoalkeeper then 10 else nil,
				OnChanged = function(value) InputController.SetTouchFootballAction("GroundPass", value) end,
			}),
			Sprint = React.createElement(TouchActionButton, { Position = UDim2.fromOffset(174, 148), Size = UDim2.fromOffset(82, 72), Text = "DASH", OnChanged = InputController.SetTouchSprint }),
			KnockOn = (not isGoalkeeper) and React.createElement(TouchActionButton, { Position = UDim2.fromOffset(8, 126), Size = UDim2.fromOffset(58, 58), Text = "PUSH", TextSize = hudSize(9), OnChanged = function(value) InputController.SetTouchFootballAction("KnockOn", value) end }) or nil,
		}),
	})
end

local function GameplayHUD(props)
	local ping, setPing = React.useState(nil)
	local elapsed, setElapsed = React.useState(0)
	local score, setScore = React.useState({ Home = 0, Away = 0 })
	-- Bumped when the stored control scheme changes, purely to re-render.
	local _schemeVersion, setSchemeVersion = React.useState(0)
	--[[
		Which presentation the always-visible strip uses. This is the player's
		explicit choice (section 40), not a guess from what hardware is plugged in --
		a keyboard player with a controller connected was previously shown
		controller glyphs for the whole match.
	]]
	local gamepad = ControlSchemeConfig.Normalize(
		localPlayer:GetAttribute(ControlSchemeConfig.AttributeName)
	) == ControlSchemeConfig.Schemes.Gamepad
	--[[
		Collapsed on entry, and the player's choice survives for the session.

		Keeping this in React state alone means every remount of the HUD --
		returning from the menu, re-entering a mode -- silently reopens the panel
		after the player closed it.
	]]
	local controlsExpanded, setControlsExpandedState = React.useState(sessionControlsExpanded)
	--[[
		What the surface currently DRAWS, as opposed to where it is heading. The
		two are separated so the expanded list is not rendered inside the small
		collapsed rectangle while the retract animation is still running.
	]]
	local controlsRendered, setControlsRendered = React.useState(sessionControlsExpanded)
	local function setControlsExpanded(value: boolean)
		sessionControlsExpanded = value
		setControlsExpandedState(value)
	end
	--[[
		The reference defaults to the player's own scheme but is not locked to it:
		both tabs stay available, because looking up the other one is exactly what
		a reference is for.
	]]
	--[[
		IS THE LOCAL FOOTBALLER A GOALKEEPER?

		Tracked reactively, because the answer changes when the player picks a
		different position and re-enters, and a HUD that keeps describing the
		outfield controls after that is confidently wrong -- worse than showing
		nothing. Read from the character attribute the server writes when it
		registers the keeper, so the HUD and the actual input reroute can never
		disagree about which of the two the player is.
	]]
	local isGoalkeeper, setIsGoalkeeper = React.useState(false)
	React.useEffect(function()
		local connections = {}
		local function bind(character: Model?)
			for _, connection in connections do
				connection:Disconnect()
			end
			table.clear(connections)
			if not character then
				setIsGoalkeeper(false)
				return
			end
			local function refresh()
				setIsGoalkeeper(
					character:GetAttribute(GoalkeeperConfig.RoleAttributeName) == GoalkeeperConfig.Role
				)
			end
			table.insert(
				connections,
				character:GetAttributeChangedSignal(GoalkeeperConfig.RoleAttributeName):Connect(refresh)
			)
			refresh()
		end
		bind(localPlayer.Character)
		local added = localPlayer.CharacterAdded:Connect(bind)
		return function()
			added:Disconnect()
			for _, connection in connections do
				connection:Disconnect()
			end
		end
	end, {})

	local defaultTab = ControlSchemeConfig.Normalize(
		localPlayer:GetAttribute(ControlSchemeConfig.AttributeName)
	)
	if defaultTab == ControlSchemeConfig.Schemes.Touch then
		defaultTab = ControlSchemeConfig.Schemes.Keyboard
	end
	local controlsTab, setControlsTabState = React.useState(sessionControlsTab or defaultTab)
	local function setControlsTab(value: string)
		sessionControlsTab = value
		setControlsTabState(value)
	end
	local mobile = UserInputService.TouchEnabled
	--[[
		TWO DIFFERENT QUESTIONS, TWO DIFFERENT FLAGS.

		`mobile` gates touch-only UI -- the sticks, the action pads, and hiding
		the keyboard reference panels. That genuinely is a question about the
		INPUT: a touchscreen laptop wants on-screen controls whatever size its
		screen is, and a small desktop window does not want them at all.

		`compact` drives layout density and type size. That is a question about
		the SCREEN, and it is the one the menus already answer through
		Theme.Compact. Using TouchEnabled for it meant the HUD laid itself out
		identically at 1920x1080 and at 780x360 -- measured, the same 23 labels at
		the same sizes -- so it never actually adapted to a phone at all.
	]]
	local compact = Theme.Compact()
	local topLeftInset = GuiService:GetGuiInset()
	local topInset = math.max(topLeftInset.Y, 0)
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
		--[[
			The control presentation follows the player's SETTING, not the last
			device they happened to touch. Re-rendering the whole control surface
			because somebody brushed a stick was the reason a keyboard player kept
			seeing controller glyphs, so this now only asks for a re-render when
			the stored scheme actually changes.
		]]
		local schemeChanged = localPlayer:GetAttributeChangedSignal(
			ControlSchemeConfig.AttributeName
		):Connect(function()
			setSchemeVersion(function(value) return value + 1 end)
		end)
		return function()
			polling = false
			heartbeat:Disconnect()
			schemeChanged:Disconnect()
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
	--[[
		The clock is server-authoritative (§48): it only advances while the ball
		is live, so it stops for restarts, celebrations and half time. The local
		`elapsed` counter is only a fallback for modes with no match running.
	]]
	--[[
		STAMINA (§49).

		The authoritative value, published by StaminaService on the character.
		Subscribed to rather than polled: the server updates it on a bounded tick,
		so an attribute-changed signal already fires exactly as often as the value
		changes and a per-frame read would only re-render for nothing.

		Interpolation is deliberately NOT added on top. The published value
		already moves smoothly because the model itself changes gradually, and
		smoothing a truthful number is how a bar ends up disagreeing with the
		speed the player is actually running at.
	]]
	local stamina, setStamina = React.useState(StaminaConfig.Maximum)
	React.useEffect(function()
		local connections = {}
		local characterConnection

		local function watch(character: Model?)
			for _, connection in connections do
				connection:Disconnect()
			end
			table.clear(connections)
			if not character then
				return
			end
			local function refresh()
				local value = character:GetAttribute(StaminaConfig.Attributes.Value)
				setStamina(if typeof(value) == "number" then value else StaminaConfig.Maximum)
			end
			refresh()
			table.insert(
				connections,
				character:GetAttributeChangedSignal(StaminaConfig.Attributes.Value):Connect(refresh)
			)
		end

		watch(localPlayer.Character)
		characterConnection = localPlayer.CharacterAdded:Connect(watch)

		return function()
			if characterConnection then
				characterConnection:Disconnect()
			end
			for _, connection in connections do
				connection:Disconnect()
			end
		end
	end, {})

	local staminaAlpha = math.clamp(stamina / StaminaConfig.Maximum, 0, 1)
	local staminaColor = if staminaAlpha > 0.55
		then Theme.Good
		elseif staminaAlpha > 0.25 then Theme.Warning
		else Theme.Poor

	local matchClock, setMatchClock = React.useState(nil :: number?)
	local matchPhase, setMatchPhase = React.useState(nil :: string?)
	React.useEffect(function()
		local rules = ReplicatedStorage:FindFirstChild(MatchRulesConfig.FolderName)
		if not rules then
			return nil
		end
		local function refresh()
			setMatchClock(rules:GetAttribute(MatchRulesConfig.ClockAttributeName))
			setMatchPhase(rules:GetAttribute(MatchRulesConfig.StateAttributeName))
		end
		refresh()
		local clockConnection = rules:GetAttributeChangedSignal(MatchRulesConfig.ClockAttributeName):Connect(refresh)
		local phaseConnection = rules:GetAttributeChangedSignal(MatchRulesConfig.StateAttributeName):Connect(refresh)
		return function()
			clockConnection:Disconnect()
			phaseConnection:Disconnect()
		end
	end, {})

	local matchRestart, setMatchRestart = React.useState(nil :: string?)
	local matchRestartTeam, setMatchRestartTeam = React.useState(nil :: string?)
	React.useEffect(function()
		local rules = ReplicatedStorage:FindFirstChild(MatchRulesConfig.FolderName)
		if not rules then
			return nil
		end
		local function refresh()
			setMatchRestart(rules:GetAttribute(MatchRulesConfig.RestartAttributeName))
			setMatchRestartTeam(rules:GetAttribute(MatchRulesConfig.RestartTeamAttributeName))
		end
		refresh()
		local a = rules:GetAttributeChangedSignal(MatchRulesConfig.RestartAttributeName):Connect(refresh)
		local b = rules:GetAttributeChangedSignal(MatchRulesConfig.RestartTeamAttributeName):Connect(refresh)
		return function() a:Disconnect() b:Disconnect() end
	end, {})

	--[[
		One line telling the player why the ball is not moving. Only shown during
		an actual stoppage, so it never sits on screen during normal play.
	]]
	local Phases = MatchRulesConfig.Phases
	local bannerText = nil
	if matchPhase == Phases.HalfTime then
		bannerText = "HALF TIME"
	elseif matchPhase == Phases.FullTime then
		bannerText = "FULL TIME"
	elseif matchPhase == Phases.GoalCelebration then
		bannerText = "GOAL"
	elseif matchPhase == Phases.InjuryStoppage then
		bannerText = "INJURY"
	elseif MatchRulesConfig.IsRestartPhase(matchPhase) or matchPhase == Phases.Stoppage then
		if typeof(matchRestart) == "string" and matchRestart ~= MatchRulesConfig.Restarts.None then
			-- "CornerKick" -> "CORNER KICK"
			local spaced = string.gsub(matchRestart, "(%l)(%u)", "%1 %2")
			bannerText = string.upper(spaced)
			if typeof(matchRestartTeam) == "string" then
				bannerText ..= "  •  " .. string.upper(matchRestartTeam)
			end
		end
	end

	local displaySeconds = if typeof(matchClock) == "number" then matchClock else elapsed
	local minutes = math.floor(displaySeconds / 60)
	local seconds = math.floor(displaySeconds) % 60
	--[[
		Controls presentation.

		Every row is rendered from ControlSchemeConfig, which carries BOTH the
		keyboard and gamepad presentation of each action. The panel therefore cannot
		describe a binding differently from the menu, and the keyboard text is
		resolved against the live PlayerConfig.Input so a rebinding shows up here
		without touching the HUD.
	]]
	local inputConfig = PlayerConfig.Input
	local function promptFor(action, forGamepad: boolean): (string, string?)
		if forGamepad then
			return action.Gamepad or "--", action.Glyph
		end
		return ControlSchemeConfig.GetKeyboardLabel(action, inputConfig), nil
	end

	-- Accent per group, so the four families are separable at a glance.
	local groupAccent = {
		Movement = Theme.AccentViolet,
		Attacking = Theme.AccentCyan,
		Defending = Theme.Good,
		-- A keeper's actions are neither attacking nor defending rows; they are
		-- their own family and read as one.
		Goalkeeping = Theme.Warning,
		Camera = Theme.Warning,
	}

	--[[
		The compact strip: only the handful of actions a player actually needs in
		front of them, in their own scheme.
	]]
	local primaryRows = {
		Layout = React.createElement("UIListLayout", {
			Padding = UDim.new(0, 3),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Left,
		}),
		Padding = ReactUI.Padding(2, 2, 2, 2),
	}
	for index, actionId in ControlSchemeConfig.GetPrimaryActionIds(isGoalkeeper) do
		local action = ControlSchemeConfig.Localise(ControlSchemeConfig.GetAction(actionId), isGoalkeeper)
		if action then
			local key, glyph = promptFor(action, gamepad)
			primaryRows["Primary" .. index] = React.createElement(ControlRow, {
				Order = index,
				Gamepad = gamepad and glyph ~= nil,
				Glyph = glyph and Assets.HUD.Glyphs[glyph] or nil,
				Key = key,
				Action = action.Label,
				Accent = groupAccent[action.Group] or Theme.AccentCyan,
			})
		end
	end

	--[[
		The full reference, grouped, for whichever tab is selected. Both tabs are
		always available regardless of the player's own scheme: looking up the other
		one is exactly why a reference exists.
	]]
	local fullRows = {
		Layout = React.createElement("UIListLayout", {
			Padding = UDim.new(0, 3),
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Left,
		}),
		Padding = ReactUI.Padding(4, 4, 2, 6),
	}
	local tabIsGamepad = controlsTab == ControlSchemeConfig.Schemes.Gamepad
	local order = 0
	for _, group in ControlSchemeConfig.GetGroups(isGoalkeeper) do
		order += 1
		fullRows["Header" .. group] = React.createElement(ControlSectionRow, {
			Order = order, Title = string.upper(group),
		})
		for _, action in ControlSchemeConfig.GetActionsByGroup(group, isGoalkeeper) do
			local key, glyph = promptFor(action, tabIsGamepad)
			order += 1
			fullRows[group .. action.Id] = React.createElement(ControlRow, {
				Order = order,
				Gamepad = tabIsGamepad and glyph ~= nil,
				Glyph = glyph and Assets.HUD.Glyphs[glyph] or nil,
				Key = key,
				Action = action.Label,
				Accent = groupAccent[group] or Theme.AccentCyan,
			})
		end
	end

	--[[
		TWO SEPARATE SURFACES (§19, §20).

		These used to be ONE frame that travelled from the middle right to the
		centre of the screen and back. That conflated two different things: a
		permanent glanceable reminder of the handful of keys you use constantly,
		and a detailed reference you open, read and close.

		They are now genuinely separate elements:

			COMPACT   middle-right, always present, four primary actions
			POPUP     bottom-right, opens on demand, every binding, tabbed

		The popup opens at the bottom right rather than the centre because the
		centre of the screen is the pitch -- covering it to read a key list means
		you cannot see the thing the keys act on. Bottom-right also matches
		ref/mockup 4.png, where the control list sits in that corner.

		The popup animates by growing from the compact strip's edge, so opening
		still reads as one continuous motion even though nothing moves.
	]]
	local POPUP_ANCHOR = Vector2.new(1, 1)
	--[[
		The popup is PINNED to the bottom-right corner and only its height
		animates, so it grows out of that corner instead of travelling there.

		Both halves of this were wrong before. It opened to half the viewport
		height, which on any ordinary window put its top edge above the middle of
		the screen -- so it swallowed the compact strip whole and the two read as
		one panel that had merely got bigger. And its closed position sat at 0.6,
		so it slid up from mid-screen rather than emerging from the corner.

		Capped at 0.34 of the height it clears the compact strip on a 720p window
		with room to spare, which is what makes them legible as two separate
		things: a small persistent reminder at middle right, a full reference at
		bottom right.
	]]
	local POPUP_OPEN_POSITION = UDim2.fromScale(0.982, 0.965)
	local POPUP_CLOSED_POSITION = POPUP_OPEN_POSITION
	local POPUP_OPEN_SIZE = UDim2.fromScale(0.29, 0.34)
	local POPUP_CLOSED_SIZE = UDim2.fromScale(0.29, 0)

	local popupRef = React.useRef(nil)
	React.useEffect(function()
		local surface = popupRef.current
		if not surface then
			return nil
		end
		local tween = TweenService:Create(
			surface,
			TweenInfo.new(0.26, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{
				Position = if controlsExpanded then POPUP_OPEN_POSITION else POPUP_CLOSED_POSITION,
				Size = if controlsExpanded then POPUP_OPEN_SIZE else POPUP_CLOSED_SIZE,
			}
		)
		tween:Play()
		--[[
			Contents appear immediately on open and are torn down only after the
			close animation finishes, so the list is never drawn inside a
			collapsing sliver.
		]]
		local swap
		if controlsExpanded then
			setControlsRendered(true)
		else
			swap = task.delay(0.2, function()
				setControlsRendered(false)
			end)
		end
		return function()
			tween:Cancel()
			if swap then
				task.cancel(swap)
			end
		end
	end, { controlsExpanded })

	return React.createElement("Frame", {
		Name = "GameplayHUD", Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, {
		--[[
			Top centre, deliberately high.

			Reserving the full GUI inset pushed the scoreboard a whole topbar
			height down the screen. The inset exists for the CoreGui cluster,
			which sits in the top corners -- the centre strip is free -- so only a
			fraction of it is reserved here. Mobile keeps a larger share because
			that is where notches and dynamic islands actually intrude.
		]]
		Scoreboard = React.createElement("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, math.max(2, topInset * (if compact then 0.35 else 0.18)) + 2),
			--[[
				TALLER ON A PHONE, NOT JUST WIDER.

				docs/ui/UI_COMPONENTS_AND_PATTERNS.md section 7 puts score and
				match time at the top of what the scorebug MUST prioritise, and at
				7.5% of a 360px screen the whole bug was 27px -- which left the
				clock a 9px-tall box. The text floor then held the clock at 11px
				and it simply overflowed the box it was given.

				Flooring the type without giving it somewhere to sit only moves
				the problem, so the bug itself grows on compact. 13% of height is
				still a sparse HUD, and it buys the clock ~17px and the score ~26.
			]]
			Size = UDim2.fromScale(if compact then 0.36 else 0.255, if compact then 0.13 else 0.068),
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
		MatchBanner = bannerText and panel({
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, math.max(2, topInset * (if compact then 0.35 else 0.18)) + (if compact then 44 else 56)),
			Size = UDim2.fromScale(if compact then 0.34 else 0.2, if compact then 0.05 else 0.042),
			BackgroundTransparency = 0.12,
		}, {
			Accent = React.createElement("Frame", {
				Size = UDim2.fromScale(1, 0.08), BackgroundColor3 = Theme.AccentCyan,
				BorderSizePixel = 0, ZIndex = 3,
			}, { Gradient = ReactUI.Gradient(Theme.AccentCyan, Theme.AccentViolet, 0) }),
			Text = label({
				Position = UDim2.fromScale(0.04, 0.18), Size = UDim2.fromScale(0.92, 0.64),
				Font = Theme.Fonts.Navigation, Text = bannerText, TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Center,
			}),
		}) or nil,
		Ping = panel({
			AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(0.982, 0.018),
			-- 4.4% of a 360px screen is 15px, which leaves the readout a 9px box
			-- and pushes 11px text out of it. Taller on compact so the number
			-- sits inside the chip it is drawn in.
			Size = UDim2.fromScale(if compact then 0.1 else 0.072, if compact then 0.075 else 0.044),
		}, {
			Icon = React.createElement("ImageLabel", { Position = UDim2.fromScale(0.1, 0.18), Size = UDim2.fromScale(0.28, 0.64), BackgroundTransparency = 1, Image = Assets.HUD.Network, ScaleType = Enum.ScaleType.Fit }),
			Value = label({ Position = UDim2.fromScale(0.4, 0.2), Size = UDim2.fromScale(0.5, 0.6), Font = Theme.Fonts.Statistics, Text = if ping then string.format("%.0fms", ping) else "--ms", TextColor3 = if not ping or ping < 90 then Theme.Good elseif ping < 170 then Theme.Warning else Theme.Poor, TextScaled = true }),
		}),
		PlayerPanel = panel({
			-- Mobile drops to the bottom band alongside the minimap; desktop keeps
			-- its existing placement.
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0.026, if compact then 0.992 else 0.935),
			-- A little taller on compact so the name and bar clear the floor; the
			-- two secondary stamina readouts drop instead of squeezing further.
			Size = UDim2.fromScale(if compact then 0.28 else 0.21, if compact then 0.15 else 0.1),
		}, {
			Badge = React.createElement("ImageLabel", { Position = UDim2.fromScale(0.035, 0.12), Size = UDim2.fromScale(0.22, 0.76), BackgroundTransparency = 1, Image = Assets.HUD.PlayerBadge, ScaleType = Enum.ScaleType.Fit }),
			Name = label({ Position = UDim2.fromScale(0.28, 0.12), Size = UDim2.fromScale(0.66, 0.3), Font = Theme.Fonts.Navigation, Text = "10  " .. string.upper(localPlayer.DisplayName), TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left }),
			--[[
				STAMINA (§49).

				The real, server-authoritative value. This bar previously showed a
				hardcoded 82% -- a decoration that happened to look like data,
				which is worse than showing nothing because it cannot be told
				apart from a working readout.

				The colour carries the same information as the length so the state
				is readable at a glance without measuring the bar: green while
				fresh, amber once fatigue starts biting, red near empty. The
				thresholds are the stamina model's own, not invented here.
			]]
			--[[
				The caption and the percentage are the first things to go on a
				phone. The BAR carries the reading -- length and colour both -- so
				the word "STAMINA" beside it and the exact number are duplicates,
				and docs/ui/UI_RESPONSIVE_INPUT.md section 2 drops secondary
				content before it lets primary text shrink. Measured, the caption
				had a 7px-tall box at 780x360, which nothing legible fits.
			]]
			StaminaLabel = (not compact) and label({ Position = UDim2.fromScale(0.28, 0.54), Size = UDim2.fromScale(0.22, 0.18), Font = Theme.Fonts.Caption, Text = "STAMINA", TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left }) or nil,
			StaminaTrack = React.createElement("Frame", {
				Position = UDim2.fromScale(if compact then 0.28 else 0.51, if compact then 0.6 else 0.58),
				Size = UDim2.fromScale(if compact then 0.66 else 0.31, if compact then 0.14 else 0.09),
				BackgroundColor3 = Color3.fromRGB(13, 17, 28), BorderSizePixel = 0,
			}, {
				Fill = React.createElement("Frame", {
					Size = UDim2.fromScale(math.clamp(stamina / StaminaConfig.Maximum, 0, 1), 1),
					BackgroundColor3 = staminaColor,
					BorderSizePixel = 0,
					Visible = stamina > 0.5,
				}),
			}),
			StaminaValue = (not compact) and label({
				Position = UDim2.fromScale(0.84, 0.53), Size = UDim2.fromScale(0.12, 0.2),
				Font = Theme.Fonts.Statistics,
				Text = string.format("%d%%", math.floor(stamina + 0.5)),
				TextColor3 = staminaColor,
				TextScaled = true,
			}) or nil,
		}),
		Radar = React.createElement(Minimap),
		--[[
			Controls.

			Collapsed, this is a compact strip at the middle right showing only the
			handful of actions worth having permanently in view. Expanded, the same
			surface grows to the middle of the screen and becomes the full
			reference, with a tab per scheme.

			It is ONE frame that moves and resizes rather than two that swap, so the
			open and the close both read as a single smooth motion.
		]]
		--[[
			COMPACT CONTROLS (§19).

			Stays at the middle right. Smaller, quieter and tighter than before:
			a thin surface with a hairline stroke and four rows, sized in offset
			pixels rather than screen fractions so it stays the same physical size
			whatever the viewport is -- a reference you glance at should not grow
			with the window.

			Clicking it opens the detailed popup, which is a separate element.
		]]
		--[[
			MAIN CONTROLS -- a reference panel, not a toggle (§65, §66).

			This used to be the collapsed half of the All Controls panel: clicking
			it opened the other one, so the two were a single expanding element
			wearing two names. They are now genuinely independent -- this shows
			the handful of controls a player needs mid-match and does nothing
			else, and All Controls owns its own expansion at the bottom right.
		]]
		ControlsCompact = not mobile and React.createElement("Frame", {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.fromScale(0.985, 0.5),
			Size = UDim2.fromOffset(166, 124),
			BackgroundColor3 = Color3.fromRGB(5, 9, 21),
			BackgroundTransparency = 0.22,
			BorderSizePixel = 0,
			ZIndex = 40,
		}, {
			Corner = ReactUI.Corner(8),
			Stroke = ReactUI.Stroke(Theme.AccentViolet, 1, 0.5),
			Header = React.createElement("Frame", {
				Position = UDim2.new(0, 10, 0, 7),
				Size = UDim2.new(1, -20, 0, 13),
				BackgroundTransparency = 1,
				ZIndex = 41,
			}, {
				Title = React.createElement("TextLabel", {
					Size = UDim2.new(1, -14, 1, 0),
					BackgroundTransparency = 1,
					Font = Theme.Fonts.HUDLabel,
					Text = "MAIN CONTROLS",
					TextColor3 = Theme.MutedText,
					-- Authored at 9, which is below the readability floor on any
					-- display where TextScale is not already lifting it.
					TextSize = hudSize(11),
					TextXAlignment = Enum.TextXAlignment.Left,
					ZIndex = 42,
				}),

			}),
			Primary = React.createElement("Frame", {
				Position = UDim2.new(0, 10, 0, 24),
				Size = UDim2.new(1, -20, 1, -32),
				BackgroundTransparency = 1,
				ZIndex = 41,
			}, primaryRows),
		}) or nil,

		--[[
			DETAILED CONTROLS POPUP (§20, §21).

			A separate element at the bottom right. Fixed pixel width so the rows
			cannot be squeezed until the labels overflow -- which is what happened
			when the panel was sized as a fraction of the viewport and every row
			had to fit whatever width that produced.

			ClipsDescendants is what makes the grow/shrink read as a reveal rather
			than as the contents being crushed.
		]]
		--[[
			ALL CONTROLS -- its own handle, at the bottom right (§66).

			Collapsing the panel used to leave nothing on screen that could
			reopen it, because the only opener was the Main Controls strip in the
			middle of the screen. This tab is the panel's own control: it sits
			where the panel grows from, so expanding and collapsing happen in one
			place and the two panels never depend on each other.
		]]
		ControlsTab = (not mobile and not controlsExpanded) and React.createElement("TextButton", {
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.fromScale(0.982, 0.965),
			Size = UDim2.fromOffset(150, 30),
			BackgroundColor3 = Color3.fromRGB(5, 9, 21),
			BackgroundTransparency = 0.05,
			BorderSizePixel = 0,
			AutoButtonColor = true,
			Text = "",
			ZIndex = 44,
			[React.Event.Activated] = function()
				setControlsExpanded(true)
			end,
		}, {
			Corner = ReactUI.Corner(9),
			Stroke = ReactUI.Stroke(Theme.AccentViolet, 1.2, 0.35),
			Title = React.createElement("TextLabel", {
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.new(0, 12, 0.5, 0),
				Size = UDim2.new(1, -40, 0, 14),
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Navigation,
				Text = "ALL CONTROLS",
				TextColor3 = Theme.Text,
				TextSize = hudSize(12),
				TextXAlignment = Enum.TextXAlignment.Left,
				ZIndex = 45,
			}),
			Chevron = React.createElement("TextLabel", {
				AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -12, 0.5, 0),
				Size = UDim2.fromOffset(14, 14),
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Navigation,
				Text = "+",
				TextColor3 = Theme.MutedText,
				TextSize = hudSize(14),
				ZIndex = 45,
			}),
		}) or nil,

		ControlsPopup = not mobile and React.createElement("Frame", {
			ref = popupRef,
			AnchorPoint = POPUP_ANCHOR,
			Position = if controlsExpanded then POPUP_OPEN_POSITION else POPUP_CLOSED_POSITION,
			Size = if controlsExpanded then POPUP_OPEN_SIZE else POPUP_CLOSED_SIZE,
			BackgroundColor3 = Color3.fromRGB(5, 9, 21),
			BackgroundTransparency = 0.05,
			BorderSizePixel = 0,
			ClipsDescendants = true,
			Visible = controlsExpanded or controlsRendered,
			ZIndex = 44,
		}, {
			Corner = ReactUI.Corner(9),
			Stroke = ReactUI.Stroke(Theme.AccentViolet, 1.2, 0.2),
			-- Keeps the reference readable on both a small window and a 4K one.
			SizeLimit = React.createElement("UISizeConstraint", {
				MinSize = Vector2.new(268, 0),
				-- Height capped so the panel cannot climb into the compact
				-- strip's band on a tall window.
				MaxSize = Vector2.new(330, 360),
			}),

			Header = React.createElement("TextButton", {
				Size = UDim2.new(1, 0, 0, 30),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				AutoButtonColor = false,
				Text = "",
				ZIndex = 45,
				[React.Event.Activated] = function()
					setControlsExpanded(false)
				end,
			}, {
				Title = React.createElement("TextLabel", {
					AnchorPoint = Vector2.new(0, 0.5),
					Position = UDim2.new(0, 12, 0.5, 0),
					Size = UDim2.new(1, -44, 0, 14),
					BackgroundTransparency = 1,
					Font = Theme.Fonts.Navigation,
					Text = "ALL CONTROLS",
					TextColor3 = Theme.Text,
					TextSize = hudSize(12),
					TextXAlignment = Enum.TextXAlignment.Left,
					ZIndex = 46,
				}),
				Close = React.createElement("TextLabel", {
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.new(1, -12, 0.5, 0),
					Size = UDim2.fromOffset(14, 14),
					BackgroundTransparency = 1,
					Font = Theme.Fonts.Navigation,
					Text = "\u{2212}",
					TextColor3 = Theme.MutedText,
					TextSize = hudSize(13),
					ZIndex = 46,
				}),
			}),

			--[[
				Scheme tabs. Both are always offered regardless of the player's own
				scheme: looking up the other one is exactly why a reference exists.
			]]
			Tabs = controlsRendered and React.createElement("Frame", {
				Position = UDim2.new(0, 12, 0, 32),
				Size = UDim2.new(1, -24, 0, 24),
				BackgroundTransparency = 1,
				ZIndex = 45,
			}, {
				Layout = React.createElement("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					Padding = UDim.new(0, 6),
					SortOrder = Enum.SortOrder.LayoutOrder,
				}),
				Keyboard = React.createElement(ControlsTab, {
					Order = 1,
					Label = "KEYBOARD",
					Selected = controlsTab == ControlSchemeConfig.Schemes.Keyboard,
					Select = function()
						setControlsTab(ControlSchemeConfig.Schemes.Keyboard)
					end,
				}),
				Gamepad = React.createElement(ControlsTab, {
					Order = 2,
					Label = "GAMEPAD",
					Selected = controlsTab == ControlSchemeConfig.Schemes.Gamepad,
					Select = function()
						setControlsTab(ControlSchemeConfig.Schemes.Gamepad)
					end,
				}),
			}) or nil,

			Full = controlsRendered and React.createElement("ScrollingFrame", {
				Position = UDim2.new(0, 10, 0, 62),
				Size = UDim2.new(1, -20, 1, -72),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ScrollBarThickness = 3,
				ScrollBarImageColor3 = Theme.AccentViolet,
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				CanvasSize = UDim2.new(),
				ZIndex = 45,
			}, fullRows) or nil,
		}) or nil,

		Return = not mobile and React.createElement("TextButton", {
			AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(0.982, 0.071),
			Size = UDim2.fromScale(0.09, 0.037), BackgroundColor3 = Color3.fromRGB(10, 17, 35),
			BackgroundTransparency = 0.08, BorderSizePixel = 0, Font = Enum.Font.GothamMedium,
			Text = "RETURN TO MENU", TextColor3 = Color3.fromRGB(220, 227, 242), TextSize = hudSize(11),
			[React.Event.Activated] = props.ReturnToMenu,
		}, { Corner = ReactUI.Corner(4), Stroke = ReactUI.Stroke(Color3.fromRGB(74, 88, 122), 1, 0.5) }),
		--[[
			Mobile utilities ride just under the scoreboard rather than 60px down
			the screen. The offset is derived from the same reduced inset the
			scoreboard uses, so the two move together instead of drifting apart.
		]]
		MobileUtilities = mobile and React.createElement("Frame", {
			AnchorPoint = Vector2.new(1, 0),
			-- Sits clear below the scoreboard band rather than level with it.
			Position = UDim2.new(1, -12, 0, math.max(2, topInset * 0.35) + 44),
			Size = UDim2.fromOffset(214, 32), BackgroundTransparency = 1,
		}, {
			Return = React.createElement("TextButton", {
				AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromOffset(108, 32),
				BackgroundColor3 = Color3.fromRGB(7, 17, 35), BackgroundTransparency = 0.12,
				BorderSizePixel = 0, AutoButtonColor = false, Font = Theme.Fonts.Navigation,
				Text = "RETURN TO MENU", TextColor3 = Color3.fromRGB(226, 235, 249), TextSize = hudSize(9),
				[React.Event.Activated] = props.ReturnToMenu,
			}, { Corner = ReactUI.Corner(5), Stroke = ReactUI.Stroke(Color3.fromRGB(83, 113, 153), 1, 0.38) }),
		}),
		MobileControls = mobile and React.createElement(MobileTouchControls) or nil,
	})
end

return GameplayHUD
