local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local React = require(ReplicatedStorage.Shared.ReactPackages).React
local Assets = require(ReplicatedStorage.Shared.Config.UIAssetConfig)
local ExperienceConfig = require(ReplicatedStorage.Shared.Config.ExperienceConfig)
local Theme = require(script.Parent.Parent.Theme)
local ReactUI = require(script.Parent.Parent.Components.ReactUI)

local localPlayer = Players.LocalPlayer

local function glassFrame(props, children)
	local merged = {
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = props.Transparency or 0.2,
		BorderSizePixel = 0,
	}
	for key, value in props do
		if key ~= "Transparency" then
			merged[key] = value
		end
	end
	children = children or {}
	children.Corner = children.Corner or ReactUI.Corner(7)
	children.Stroke = children.Stroke or ReactUI.Stroke(Theme.Stroke, 1, 0.18)
	return React.createElement("Frame", merged, children)
end

local function panel(props, children)
	local merged = {
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
	}
	for key, value in props do
		merged[key] = value
	end
	children = children or {}
	children.Corner = children.Corner or ReactUI.Corner(6)
	children.Stroke = children.Stroke or ReactUI.Stroke(Theme.Stroke, 1, 0.22)
	return React.createElement("Frame", merged, children)
end

local function text(props)
	local merged = {
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Body,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
	}
	for key, value in props do merged[key] = value end
	return React.createElement("TextLabel", merged)
end

local function AnimatedMenuPlayer()
	local viewportRef = React.useRef(nil)
	local modelRef = React.useRef(nil)
	local basePivotRef = React.useRef(nil)
	local dragRef = React.useRef({ Active = false, X = 0, Yaw = 0 })
	React.useEffect(function()
		local disposed = false
		local viewport = viewportRef.current
		if not viewport then return nil end
		task.spawn(function()
			-- Workspace is streaming-enabled. The server clones the exact Workspace
			-- menu_character into ReplicatedStorage so every client receives the full rig.
			local sourceRig = ReplicatedStorage:WaitForChild("Beyond90MenuCharacter", 5)
			if not sourceRig then
				local workspaceRig = Workspace:FindFirstChild("menu_character")
				sourceRig = if workspaceRig and workspaceRig:FindFirstChildWhichIsA("BasePart", true) then workspaceRig else nil
			end
			local ok, model = pcall(function()
				return sourceRig and sourceRig:IsA("Model") and sourceRig:Clone() or nil
			end)
			if disposed or not ok or not model then
				if model then model:Destroy() end
				return
			end
			model.Name = "MenuFootballer"
			local world = Instance.new("WorldModel")
			world.Name = "MenuWorld"
			world.Parent = viewport
			model.Parent = world
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			local root = model:FindFirstChild("HumanoidRootPart")
			for _, descendant in model:GetDescendants() do
				if descendant:IsA("BasePart") then
					descendant.Anchored = descendant == root
					descendant.CanCollide = false
					descendant.CanTouch = false
					descendant.CanQuery = false
				elseif descendant:IsA("BaseScript") then
					descendant:Destroy()
				end
			end
			if humanoid then
				humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
			end
			model:PivotTo(CFrame.Angles(0, math.rad(135), 0))
			local boundingCFrame, boundingSize = model:GetBoundingBox()
			model:PivotTo(model:GetPivot() + Vector3.new(0, -(boundingCFrame.Position.Y - boundingSize.Y / 2), 0))
			modelRef.current = model
			basePivotRef.current = model:GetPivot()
			local camera = Instance.new("Camera")
			camera.FieldOfView = 21
			camera.CFrame = CFrame.lookAt(Vector3.new(-0.8, 4.35, 20.5), Vector3.new(0, 4.15, 0))
			camera.Parent = viewport
			viewport.CurrentCamera = camera
			if humanoid then
				local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
				animator.Parent = humanoid
				local animation = Instance.new("Animation")
				animation.AnimationId = "rbxassetid://71821812678071"
				local loaded, track = pcall(function() return animator:LoadAnimation(animation) end)
				animation:Destroy()
				if loaded and track then
					track.Priority = Enum.AnimationPriority.Idle
					track.Looped = true
					track:Play(0.18, 1, 1)
				end
			end
		end)
		return function()
			disposed = true
			modelRef.current = nil
			basePivotRef.current = nil
			if viewport then viewport:ClearAllChildren() end
		end
	end, {})
	return React.createElement("ViewportFrame", {
		ref = viewportRef,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.61, 0.79),
		Size = UDim2.fromScale(0.37, 0.8),
		BackgroundTransparency = 1,
		Ambient = Color3.fromRGB(135, 151, 190),
		LightColor = Color3.fromRGB(195, 220, 255),
		LightDirection = Vector3.new(-1, -0.8, -0.35),
		Active = true,
		ZIndex = 2,
		[React.Event.InputBegan] = function(_, input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dragRef.current.Active = true
				dragRef.current.X = input.Position.X
			end
		end,
		[React.Event.InputChanged] = function(_, input)
			if not dragRef.current.Active then return end
			if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then return end
			local delta = input.Position.X - dragRef.current.X
			dragRef.current.X = input.Position.X
			dragRef.current.Yaw += delta * 0.008
			local model = modelRef.current
			local basePivot = basePivotRef.current
			if model and basePivot then
				model:PivotTo(basePivot * CFrame.Angles(0, dragRef.current.Yaw, 0))
			end
		end,
		[React.Event.InputEnded] = function(_, input)
			if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
				dragRef.current.Active = false
			end
		end,
	})
end

local function NavigationCard(props)
	local focused, setFocused = React.useState(false)
	local buttonRef = React.useRef(nil)
	local selectionRef = React.useRef(nil)
	React.useEffect(function()
		if buttonRef.current and selectionRef.current then
			buttonRef.current.SelectionImageObject = selectionRef.current
		end
		return nil
	end, {})
	return React.createElement("TextButton", {
		ref = buttonRef,
		LayoutOrder = props.Order,
		Size = UDim2.new(0.19, 0, 1, 0),
		BackgroundColor3 = if focused or props.Selected then Theme.PanelSelected else Theme.Panel,
		BackgroundTransparency = if focused or props.Selected then 0.02 else 0.08,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Selectable = true,
		Text = "",
		[React.Event.Activated] = props.OnActivated,
		[React.Event.MouseEnter] = function()
			setFocused(true)
			if props.OnFocused then props.OnFocused() end
		end,
		[React.Event.MouseLeave] = function() setFocused(false) end,
		[React.Event.SelectionGained] = function()
			setFocused(true)
			if props.OnFocused then props.OnFocused() end
		end,
		[React.Event.SelectionLost] = function() setFocused(false) end,
	}, {
		Glow = props.Selected and React.createElement("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, 12, 1, 12), BackgroundTransparency = 1, ZIndex = 0,
		}, {
			Corner = ReactUI.Corner(7),
			Stroke = ReactUI.Stroke(Theme.AccentCyan, 4, 0.18),
		}) or nil,
		SelectionImage = React.createElement("ImageLabel", {
			ref = selectionRef, Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
			ImageTransparency = 1,
		}),
		Corner = ReactUI.Corner(5),
		Stroke = ReactUI.Stroke(if props.Selected then Color3.fromRGB(194, 221, 255) else Theme.Stroke,
			if props.Selected then 2 else 1, if props.Selected then 0.04 else 0.26),
		Icon = React.createElement("ImageLabel", {
			Position = UDim2.fromScale(0.05, 0.16),
			Size = UDim2.fromScale(0.26, 0.68),
			BackgroundTransparency = 1,
			Image = props.Icon,
			ScaleType = Enum.ScaleType.Fit,
		}),
		Title = text({
			Position = UDim2.fromScale(0.34, 0.23), Size = UDim2.fromScale(0.61, 0.22),
			Font = Theme.Fonts.Navigation, Text = props.Title, TextSize = if UserInputService.TouchEnabled then 13 else 16,
		}),
		Subtitle = text({
			Position = UDim2.fromScale(0.34, 0.49), Size = UDim2.fromScale(0.61, 0.3),
			Font = Enum.Font.Gotham, Text = props.Subtitle, TextColor3 = Theme.MutedText,
			TextWrapped = true, TextSize = if UserInputService.TouchEnabled then 9 else 11,
		}),
	})
end

local function Highlight(props)
	return glassFrame({
		LayoutOrder = props.Order,
		Size = UDim2.new(0.32, 0, 1, 0),
		BackgroundTransparency = 0.38,
	}, {
		Icon = React.createElement("ImageLabel", {
			Position = UDim2.fromScale(0.08, 0.18), Size = UDim2.fromScale(0.22, 0.64),
			BackgroundTransparency = 1, Image = props.Icon, ScaleType = Enum.ScaleType.Fit,
		}),
		Value = text({
			Position = UDim2.fromScale(0.36, 0.16), Size = UDim2.fromScale(0.58, 0.38),
			Font = Theme.Fonts.Display, Text = props.Value, TextScaled = true,
		}),
		Caption = text({
			Position = UDim2.fromScale(0.36, 0.57), Size = UDim2.fromScale(0.58, 0.22),
			Font = Theme.Fonts.Caption, Text = props.Caption, TextColor3 = Theme.MutedText, TextScaled = true,
		}),
	})
end

local function PlayerStat(props)
	return React.createElement("Frame", {
		Position = props.Position, Size = UDim2.fromScale(0.26, 0.43),
		BackgroundTransparency = 1,
	}, {
		Label = text({
			Position = UDim2.fromScale(0, 0), Size = UDim2.fromScale(1, 0.4),
			Font = Enum.Font.GothamMedium, Text = props.Label, TextColor3 = Color3.fromRGB(201, 210, 230),
			TextSize = if props.Mobile then 6 else 9, TextXAlignment = Enum.TextXAlignment.Center,
		}),
		Value = text({
			Position = UDim2.fromScale(0, 0.41), Size = UDim2.fromScale(1, 0.51),
			Font = Enum.Font.GothamBold, Text = props.Value, TextColor3 = Theme.Text,
			TextSize = if props.Mobile then 10 else 14, TextXAlignment = Enum.TextXAlignment.Center,
		}),
	})
end

local function HomeScreen(props)
	local portrait, setPortrait = React.useState("")
	local playerBust, setPlayerBust = React.useState("")
	local selectedNavigation, setSelectedNavigation = React.useState(1)
	local rootRef = React.useRef(nil)
	local mobile = UserInputService.TouchEnabled
	local topLeftInset = GuiService:GetGuiInset()
	local footerInset = if mobile then topLeftInset.Y else 0
	React.useEffect(function()
		task.spawn(function()
			local headOk, headImage = pcall(function()
				return Players:GetUserThumbnailAsync(localPlayer.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size420x420)
			end)
			if headOk then setPortrait(headImage) end
			local bustOk, bustImage = pcall(function()
				return Players:GetUserThumbnailAsync(localPlayer.UserId, Enum.ThumbnailType.AvatarBust, Enum.ThumbnailSize.Size420x420)
			end)
			if bustOk then setPlayerBust(bustImage) end
		end)
	end, {})
	React.useEffect(function()
		local rootGroup = rootRef.current
		if not rootGroup then return nil end
		local cancelled = false
		task.spawn(function()
			if localPlayer:GetAttribute("Beyond90StartupComplete") == true then
				rootGroup.GroupTransparency = 0
				return
			end
			while not cancelled and localPlayer:GetAttribute("Beyond90StartupReadyForMenu") ~= true do
				task.wait()
			end
			if cancelled or not rootGroup.Parent then return end
			TweenService:Create(
				rootGroup,
				TweenInfo.new(ExperienceConfig.MenuRevealDuration, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
				{ GroupTransparency = 0 }
			):Play()
		end)
		return function() cancelled = true end
	end, {})

	local nav = {
		{ "PLAY", "Jump into matches\nCompete and win", Assets.Navigation.Play, props.OpenModes },
		{ "TRAINING", "Improve your skills\nMaster the pitch", Assets.Navigation.Training, props.OpenModes },
		{ "CLUBS", "Join or create a club\nComing soon", Assets.Navigation.Clubs, props.ComingSoon },
		{ "PROFILE", "View stats and progression\nComing soon", Assets.Navigation.Profile, props.ComingSoon },
		{ "SETTINGS", "Game settings\nand preferences", Assets.Navigation.Settings, props.OpenSettings },
	}
	local navChildren = {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0.012, 0),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}
	for index, data in nav do
		navChildren[data[1]] = React.createElement(NavigationCard, {
			Order = index, Title = data[1], Subtitle = data[2], Icon = data[3],
			OnActivated = data[4], Selected = index == selectedNavigation,
			OnFocused = function() setSelectedNavigation(index) end,
		})
	end

	return React.createElement("CanvasGroup", {
		ref = rootRef,
		Name = "Home",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Background,
		BorderSizePixel = 0,
		GroupTransparency = if localPlayer:GetAttribute("Beyond90StartupComplete") == true then 0 else 1,
	}, {
		Background = React.createElement("ImageLabel", {
			Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
			Image = Assets.MenuStadium, ScaleType = Enum.ScaleType.Crop,
		}),
		Shade = React.createElement("Frame", {
			Size = UDim2.fromScale(1, 1), BackgroundColor3 = Theme.Background,
			BackgroundTransparency = 0.52, BorderSizePixel = 0, ZIndex = 1,
		}, {
			Gradient = React.createElement("UIGradient", {
				Color = ColorSequence.new(Color3.fromRGB(4, 8, 25), Color3.fromRGB(3, 8, 20)),
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.05),
					NumberSequenceKeypoint.new(0.55, 0.58),
					NumberSequenceKeypoint.new(1, 0.12),
				}),
				Rotation = 0,
			}),
		}),
		MenuPlayer = React.createElement(AnimatedMenuPlayer),
		PlayerLegFade = React.createElement("Frame", {
			Position = UDim2.fromScale(0.425, 0.54), Size = UDim2.fromScale(0.37, 0.28),
			BackgroundColor3 = Color3.fromRGB(3, 9, 24), BorderSizePixel = 0, ZIndex = 3,
		}, {
			Gradient = React.createElement("UIGradient", {
				Rotation = 90,
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(0.36, 0.96),
					NumberSequenceKeypoint.new(0.72, 0.42),
					NumberSequenceKeypoint.new(1, 0.02),
				}),
			}),
		}),
		Logo = React.createElement("ImageLabel", {
			Position = UDim2.fromScale(if mobile then 0.025 else 0.045, if mobile then 0.035 else 0.055),
			Size = UDim2.fromScale(if mobile then 0.34 else 0.38, if mobile then 0.17 else 0.2),
			BackgroundTransparency = 1, Image = Assets.Logo, ScaleType = Enum.ScaleType.Crop, ZIndex = 3,
		}),
		Account = glassFrame({
			Position = UDim2.fromScale(if mobile then 0.77 else 0.81, 0.018),
			Size = UDim2.fromScale(if mobile then 0.21 else 0.17, if mobile then 0.085 else 0.072), ZIndex = 4,
			BackgroundTransparency = 0.08,
		}, {
			Avatar = React.createElement("ImageLabel", {
				Position = UDim2.fromScale(0.03, 0.08), Size = UDim2.fromScale(0.2, 0.84),
				BackgroundTransparency = 1, Image = portrait, ScaleType = Enum.ScaleType.Crop,
			}, { Corner = ReactUI.Corner(40), Stroke = ReactUI.Stroke(Theme.AccentViolet, 1.5) }),
			Name = text({ Position = UDim2.fromScale(0.27, 0.12), Size = UDim2.fromScale(0.68, 0.3), Font = Theme.Fonts.Navigation, Text = localPlayer.DisplayName, TextScaled = true }),
			Level = text({ Position = UDim2.fromScale(0.27, 0.45), Size = UDim2.fromScale(0.68, 0.2), Text = "LEVEL 23", TextColor3 = Theme.MutedText, TextScaled = true }),
			XP = React.createElement("Frame", { Position = UDim2.fromScale(0.27, 0.75), Size = UDim2.fromScale(0.64, 0.07), BackgroundColor3 = Theme.Stroke, BorderSizePixel = 0 }, {
				Glow = React.createElement("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.fromScale(0.46, 2.8), BackgroundColor3 = Theme.AccentCyan, BackgroundTransparency = 0.72, BorderSizePixel = 0 }, {
					Corner = ReactUI.Corner(20),
				}),
				Fill = React.createElement("Frame", { Size = UDim2.fromScale(0.46, 1), BackgroundColor3 = Theme.AccentCyan, BorderSizePixel = 0 }, {
					Corner = ReactUI.Corner(20),
					Gradient = React.createElement("UIGradient", {
						Color = ColorSequence.new(Color3.fromRGB(66, 220, 255), Color3.fromRGB(103, 128, 255)),
						Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.78, 0), NumberSequenceKeypoint.new(1, 1) }),
					}),
				}),
				Corner = ReactUI.Corner(20),
			}),
		}),
		Currency = glassFrame({
			Position = UDim2.fromScale(if mobile then 0.585 else 0.655, 0.018),
			Size = UDim2.fromScale(if mobile then 0.17 else 0.14, if mobile then 0.06 else 0.052), ZIndex = 4,
			BackgroundTransparency = 0.08,
		}, {
			B90 = React.createElement("ImageLabel", { Position = UDim2.fromScale(0.05, 0.18), Size = UDim2.fromScale(0.16, 0.64), BackgroundTransparency = 1, Image = Assets.Currency.B90, ScaleType = Enum.ScaleType.Fit }),
			B90Text = text({ Position = UDim2.fromScale(0.22, 0.18), Size = UDim2.fromScale(0.28, 0.64), Font = Theme.Fonts.Statistics, Text = "12,450", TextScaled = true }),
			Premium = React.createElement("ImageLabel", { Position = UDim2.fromScale(0.57, 0.18), Size = UDim2.fromScale(0.14, 0.64), BackgroundTransparency = 1, Image = Assets.Currency.Premium, ScaleType = Enum.ScaleType.Fit }),
			PremiumText = text({ Position = UDim2.fromScale(0.72, 0.18), Size = UDim2.fromScale(0.23, 0.64), Font = Theme.Fonts.Statistics, Text = "275", TextScaled = true }),
		}),
		Season = React.createElement("Frame", {
			Position = UDim2.fromScale(if mobile then 0.035 else 0.058, if mobile then 0.235 else 0.285),
			Size = UDim2.fromScale(if mobile then 0.39 else 0.355, if mobile then 0.43 else 0.4),
			BackgroundTransparency = 1, ZIndex = 4,
		}, {
			Eyebrow = text({ Size = UDim2.fromScale(1, 0.09), Font = Enum.Font.GothamMedium, Text = "CURRENT SEASON", TextColor3 = Theme.AccentCyan, TextSize = if mobile then 10 else 15 }),
			Title = text({ Position = UDim2.fromScale(0, 0.11), Size = UDim2.fromScale(1, 0.13), Font = Enum.Font.GothamBlack, Text = "SEASON 1 - RISING", TextSize = if mobile then 17 else 27 }),
			TimeIcon = Assets.Menu.Time ~= "" and React.createElement("ImageLabel", {
				Position = UDim2.fromScale(0, 0.245), Size = UDim2.fromScale(0.035, 0.07),
				BackgroundTransparency = 1, Image = Assets.Menu.Time, ScaleType = Enum.ScaleType.Fit,
			}) or nil,
			Ends = text({ Position = UDim2.fromScale(0.04, 0.245), Size = UDim2.fromScale(0.6, 0.07), Font = Theme.Fonts.Caption, Text = "ENDS IN 28 DAYS", TextColor3 = Theme.MutedText, TextSize = if mobile then 9 else 13 }),
			Panel = glassFrame({ Position = UDim2.fromScale(0, 0.34), Size = UDim2.fromScale(1, 0.66), Transparency = 0.24 }, {
				Badge = React.createElement("ImageLabel", { Position = UDim2.fromScale(0.025, 0.025), Size = UDim2.fromScale(0.245, 0.53), BackgroundTransparency = 1, Image = Assets.DivisionBadge, ImageColor3 = Color3.fromRGB(205, 218, 238), ScaleType = Enum.ScaleType.Fit }, {
					TopShade = React.createElement("Frame", { Position = UDim2.fromScale(0.08, 0.02), Size = UDim2.fromScale(0.84, 0.28), BackgroundColor3 = Color3.fromRGB(4, 9, 26), BackgroundTransparency = 0.62, BorderSizePixel = 0 }),
				}),
			DivisionCaption = text({ Position = UDim2.fromScale(0.285, 0.075), Size = UDim2.fromScale(0.3, 0.08), Text = "DIVISION", TextColor3 = Theme.MutedText, TextSize = if mobile then 8 else 11 }),
			Division = text({ Position = UDim2.fromScale(0.285, 0.16), Size = UDim2.fromScale(0.35, 0.1), Font = Theme.Fonts.Navigation, Text = "DIAMOND II", TextSize = if mobile then 12 else 16 }),
			RatingCaption = text({ Position = UDim2.fromScale(0.285, if mobile then 0.275 else 0.29), Size = UDim2.fromScale(0.25, 0.07), Text = "RATING", TextColor3 = Theme.MutedText, TextSize = if mobile then 8 else 11 }),
			RatingNetwork = React.createElement("ImageLabel", { Position = UDim2.fromScale(0.285, 0.365), Size = UDim2.fromScale(0.045, 0.075), BackgroundTransparency = 1, Image = Assets.Social.Network, ScaleType = Enum.ScaleType.Fit }),
			Rating = text({ Position = UDim2.fromScale(0.34, 0.355), Size = UDim2.fromScale(0.25, 0.1), Font = Theme.Fonts.Statistics, Text = "1,286", TextSize = if mobile then 12 else 17 }),
			Reward = text({ Position = UDim2.fromScale(0.665, 0.065), Size = UDim2.fromScale(0.19, 0.17), Font = Theme.Fonts.Caption, Text = "NEXT REWARD\nDIAMOND I", TextColor3 = Theme.AccentCyan, TextWrapped = true, TextSize = if mobile then 8 else 11 }),
				Diamond = React.createElement("ImageLabel", { Position = UDim2.fromScale(0.84, 0.08), Size = UDim2.fromScale(0.12, 0.23), BackgroundTransparency = 1, Image = Assets.Currency.Premium, ScaleType = Enum.ScaleType.Fit }),
				Progress = React.createElement("Frame", { Position = UDim2.fromScale(0.285, 0.47), Size = UDim2.fromScale(0.54, 0.025), BackgroundColor3 = Theme.Stroke, BorderSizePixel = 0 }, {
					Fill = React.createElement("Frame", { Size = UDim2.fromScale(0.91, 1), BackgroundColor3 = Theme.Accent, BorderSizePixel = 0 }, { Gradient = ReactUI.Gradient(Theme.AccentViolet, Theme.AccentCyan) }),
				}),
			ProgressCount = text({ Position = UDim2.fromScale(0.84, 0.42), Size = UDim2.fromScale(0.14, 0.1), Font = Theme.Fonts.Caption, Text = "1,286 / 1,400", TextColor3 = Theme.Text, TextSize = if mobile then 7 else 10, TextXAlignment = Enum.TextXAlignment.Right }),
				HighlightsTitle = text({ Position = UDim2.fromScale(0.025, 0.56), Size = UDim2.fromScale(0.5, 0.07), Font = Theme.Fonts.Navigation, Text = "SEASON HIGHLIGHTS", TextColor3 = Theme.Accent, TextScaled = true }),
				Highlights = React.createElement("Frame", { Position = UDim2.fromScale(0.02, 0.66), Size = UDim2.fromScale(0.96, 0.27), BackgroundTransparency = 1 }, {
					Layout = React.createElement("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0.02, 0), SortOrder = Enum.SortOrder.LayoutOrder }),
					Matches = React.createElement(Highlight, { Order = 1, Icon = Assets.Highlights.Trophy, Value = "24", Caption = "MATCHES PLAYED" }),
					Goals = React.createElement(Highlight, { Order = 2, Icon = Assets.Highlights.Goal, Value = "38", Caption = "GOALS SCORED" }),
					MOTM = React.createElement(Highlight, { Order = 3, Icon = Assets.Highlights.MOTM, Value = "11", Caption = "MOTM AWARDS" }),
				}),
			}),
		}),
		Featured = React.createElement("Frame", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(if mobile then 0.975 else 0.97, if mobile then 0.115 else 0.085),
			Size = UDim2.fromScale(if mobile then 0.22 else 0.215, if mobile then 0.61 else 0.69),
			BackgroundTransparency = 1, ZIndex = 4,
		}, {
			Aspect = React.createElement("UIAspectRatioConstraint", { AspectRatio = 0.59, DominantAxis = Enum.DominantAxis.Height }),
			Title = text({ Position = UDim2.fromScale(0.1, 0), Size = UDim2.fromScale(0.8, 0.052), Font = Enum.Font.GothamMedium, Text = "FEATURED PLAYER", TextColor3 = Theme.AccentCyan, TextSize = if mobile then 9 else 12 }),
			Card = React.createElement("ImageLabel", { Position = UDim2.fromScale(0.01, 0.045), Size = UDim2.fromScale(0.98, 0.84), BackgroundTransparency = 1, Image = Assets.FeaturedPlayerFrame, ScaleType = Enum.ScaleType.Stretch, ClipsDescendants = true }, {
				Portrait = React.createElement("ImageLabel", { Position = UDim2.fromScale(0.18, 0.08), Size = UDim2.fromScale(0.72, 0.54), BackgroundTransparency = 1, Image = if playerBust ~= "" then playerBust else portrait, ScaleType = Enum.ScaleType.Fit, Rotation = 5 }, {
					Fade = React.createElement("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.65, 0.04), NumberSequenceKeypoint.new(1, 1) }) }),
				}),
				Rating = text({ Position = UDim2.fromScale(0.13, 0.13), Size = UDim2.fromScale(0.17, 0.075), Font = Enum.Font.GothamBlack, Text = "92", TextSize = if mobile then 17 else 23, TextXAlignment = Enum.TextXAlignment.Center }),
				Position = text({ Position = UDim2.fromScale(0.13, 0.205), Size = UDim2.fromScale(0.17, 0.05), Font = Enum.Font.GothamBold, Text = "LW", TextSize = if mobile then 9 else 12, TextXAlignment = Enum.TextXAlignment.Center }),
				NameRow = React.createElement("Frame", { Position = UDim2.fromScale(0.11, 0.65), Size = UDim2.fromScale(0.78, 0.065), BackgroundTransparency = 1 }, {
					Country = React.createElement("ImageLabel", { Position = UDim2.fromScale(0.03, 0.12), Size = UDim2.fromScale(0.14, 0.76), BackgroundTransparency = 1, Image = Assets.Menu.NigeriaFlag, ScaleType = Enum.ScaleType.Fit }),
					Name = text({ Size = UDim2.fromScale(1, 1), Font = Enum.Font.GothamBold, Text = string.upper(localPlayer.DisplayName), TextXAlignment = Enum.TextXAlignment.Center, TextSize = if mobile then 8 else 11, TextTruncate = Enum.TextTruncate.AtEnd }),
				}),
				Stats = React.createElement("Frame", { Position = UDim2.fromScale(0.16, 0.725), Size = UDim2.fromScale(0.68, 0.16), BackgroundTransparency = 1 }, {
					PAC = React.createElement(PlayerStat, { Position = UDim2.fromScale(0, 0), Value = "94", Label = "PAC", Mobile = mobile }),
					SHO = React.createElement(PlayerStat, { Position = UDim2.fromScale(0.37, 0), Value = "91", Label = "SHO", Mobile = mobile }),
					PAS = React.createElement(PlayerStat, { Position = UDim2.fromScale(0.74, 0), Value = "87", Label = "PAS", Mobile = mobile }),
					DRI = React.createElement(PlayerStat, { Position = UDim2.fromScale(0, 0.52), Value = "93", Label = "DRI", Mobile = mobile }),
					DEF = React.createElement(PlayerStat, { Position = UDim2.fromScale(0.37, 0.52), Value = "42", Label = "DEF", Mobile = mobile }),
					PHY = React.createElement(PlayerStat, { Position = UDim2.fromScale(0.74, 0.52), Value = "81", Label = "PHY", Mobile = mobile }),
				}),
			}),
		}),
		Navigation = React.createElement("Frame", {
			AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, if mobile then 0.86 else 0.875),
			Size = UDim2.fromScale(if mobile then 0.95 else 0.9, if mobile then 0.15 else 0.135), BackgroundTransparency = 1, ZIndex = 5,
		}, navChildren),
		FooterFade = React.createElement("Frame", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 0, if mobile then 1 else 0.9, footerInset),
			Size = UDim2.new(1, 0, if mobile then 0.3 else 0.18, footerInset),
			BackgroundColor3 = Color3.fromRGB(1, 5, 17), BorderSizePixel = 0, ZIndex = 2,
		}, {
			Gradient = React.createElement("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.42, 0.76), NumberSequenceKeypoint.new(0.72, 0.3), NumberSequenceKeypoint.new(1, 0.04) }) }),
		}),
		Footer = React.createElement("Frame", {
			AnchorPoint = if mobile then Vector2.new(0, 1) else Vector2.zero,
			Position = UDim2.new(0, 0, if mobile then 1 else 0.9, footerInset),
			Size = UDim2.new(1, 0, if mobile then 0.14 else 0.1, footerInset),
			BackgroundColor3 = Color3.fromRGB(1, 5, 17), BackgroundTransparency = 0.02,
			BorderSizePixel = 0, ZIndex = 6,
		}, {
			Content = React.createElement("Frame", {
				Size = UDim2.new(1, 0, 1, -footerInset), BackgroundTransparency = 1,
			}, {
			SelectGlyph = React.createElement("ImageLabel", { Position = UDim2.fromScale(if mobile then 0.025 else 0.035, if mobile then 0.24 else 0.2), Size = UDim2.fromOffset(if mobile then 22 else 28, if mobile then 22 else 28), BackgroundTransparency = 1, Image = Assets.Menu.Select, ScaleType = Enum.ScaleType.Fit }),
			Select = not mobile and text({ Position = UDim2.fromScale(0.06, 0.22), Size = UDim2.fromScale(0.06, 0.5), Font = Enum.Font.GothamMedium, Text = "SELECT", TextColor3 = Theme.MutedText, TextSize = 11 }) or nil,
			OpenMenuIcon = Assets.Menu.OpenMenu ~= "" and React.createElement("ImageLabel", { Position = UDim2.fromScale(if mobile then 0.075 else 0.118, if mobile then 0.27 else 0.27), Size = UDim2.fromOffset(20, 20), BackgroundTransparency = 1, Image = Assets.Menu.OpenMenu, ScaleType = Enum.ScaleType.Fit }) or panel({ Position = UDim2.fromScale(if mobile then 0.075 else 0.118, 0.27), Size = UDim2.fromOffset(20, 20), BackgroundTransparency = 0.2 }, {
				Mark = text({ Size = UDim2.fromScale(1, 1), Font = Theme.Fonts.Caption, Text = "=", TextColor3 = Theme.Text, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Center }),
			}),
			OpenMenu = not mobile and text({ Position = UDim2.fromScale(0.138, 0.22), Size = UDim2.fromScale(0.09, 0.5), Font = Enum.Font.GothamMedium, Text = "OPEN MENU", TextColor3 = Theme.MutedText, TextSize = 11 }) or nil,
			NewsTag = text({ Position = UDim2.fromScale(if mobile then 0.125 else 0.295, 0.22), Size = UDim2.fromScale(if mobile then 0.065 else 0.06, 0.5), Font = Theme.Fonts.Navigation, Text = "NEWS", TextColor3 = Theme.Accent, TextSize = if mobile then 9 else 12 }),
			News = text({ Position = UDim2.fromScale(if mobile then 0.19 else 0.34, if mobile then 0.08 else 0.22), Size = UDim2.fromScale(if mobile then 0.53 else 0.43, if mobile then 0.84 else 0.5), Font = Enum.Font.Gotham, Text = "Welcome to Beyond 90! Season 1 is live now. Compete, climb the ranks, and become a legend.", TextColor3 = Color3.fromRGB(205, 214, 234), TextSize = if mobile then 8 else 11, TextWrapped = mobile }),
			Friends = panel({ Position = UDim2.fromScale(if mobile then 0.755 else 0.825, 0.16), Size = UDim2.fromScale(if mobile then 0.07 else 0.055, 0.64), BackgroundColor3 = Color3.fromRGB(2, 8, 26), BackgroundTransparency = 0.02 }, {
				Icon = React.createElement("ImageLabel", { Position = UDim2.fromScale(0.08, 0.13), Size = UDim2.fromScale(0.58, 0.74), BackgroundTransparency = 1, Image = Assets.Social.Friends, ScaleType = Enum.ScaleType.Fit }),
				Count = text({ Position = UDim2.fromScale(0.64, 0.2), Size = UDim2.fromScale(0.25, 0.6), Text = "3", TextSize = 11, TextXAlignment = Enum.TextXAlignment.Center }),
			}),
			Chat = panel({ Position = UDim2.fromScale(if mobile then 0.84 else 0.885, 0.16), Size = UDim2.fromScale(if mobile then 0.065 else 0.047, 0.64), BackgroundColor3 = Color3.fromRGB(2, 8, 26), BackgroundTransparency = 0.02 }, {
				Icon = React.createElement("ImageLabel", { Position = UDim2.fromScale(0.13, 0.13), Size = UDim2.fromScale(0.74, 0.74), BackgroundTransparency = 1, Image = Assets.Social.Chat, ScaleType = Enum.ScaleType.Fit }),
			}),
			Network = panel({ Position = UDim2.fromScale(if mobile then 0.92 else 0.937, 0.16), Size = UDim2.fromScale(if mobile then 0.065 else 0.047, 0.64), BackgroundColor3 = Color3.fromRGB(2, 8, 26), BackgroundTransparency = 0.02 }, {
				Icon = React.createElement("ImageLabel", { Position = UDim2.fromScale(0.13, 0.13), Size = UDim2.fromScale(0.74, 0.74), BackgroundTransparency = 1, Image = Assets.Social.Network, ScaleType = Enum.ScaleType.Fit }),
			}),
			}),
		}),
	})
end

return HomeScreen
