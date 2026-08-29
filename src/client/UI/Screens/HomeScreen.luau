local Players = game:GetService("Players")
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local React = require(ReplicatedStorage.Shared.ReactPackages).React
local Assets = require(ReplicatedStorage.Shared.Config.UIAssetConfig)
local ExperienceConfig = require(ReplicatedStorage.Shared.Config.ExperienceConfig)
local PlayerConfig = require(ReplicatedStorage.Shared.Config.PlayerConfig)
local Theme = require(script.Parent.Parent.Theme)
local ReactUI = require(script.Parent.Parent.Components.ReactUI)
local MenuFooter = require(script.Parent.Parent.Components.MenuFooter)
local ControlSchemeConfig = require(ReplicatedStorage.Shared.Config.ControlSchemeConfig)

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

			--[[
				THE MENU FOOTBALLER IS YOU (§18).

				The home screen shows a footballer standing in the tunnel, and it
				was always the same anonymous rig -- which reads as a stock model
				rather than as the player's own footballer, and contradicts the
				Settings screen where they have just chosen to play as their own
				avatar.

				So when they are playing as their Roblox avatar, the menu wears it
				too. Applied as a description onto the existing rig rather than by
				swapping models, so the camera framing, the anchoring, the idle
				animation and the drag-to-rotate all keep working on the rig they
				were written for.

				Best-effort by design: this is a decorative surface. A player whose
				avatar cannot be fetched sees the default footballer, which is
				exactly what they saw before, rather than an empty viewport.
			]]
			local identityConfig = PlayerConfig.Appearance.Identity
			local chosenSource = localPlayer:GetAttribute(identityConfig.AttributeName)
			if typeof(chosenSource) ~= "string" or not identityConfig.Sources[chosenSource] then
				chosenSource = identityConfig.Default
			end
			if humanoid and identityConfig.Enabled == true
				and chosenSource == identityConfig.Sources.RobloxAvatar
			then
				task.spawn(function()
					local okFetch, description = pcall(function()
						return Players:GetHumanoidDescriptionFromUserId(localPlayer.UserId)
					end)
					if disposed or not okFetch or not description then
						if description then description:Destroy() end
						return
					end
					-- Same rule as on the pitch: the face is the player's, the
					-- frame is everyone's, so the menu shows the footballer they
					-- will actually be.
					for _, property in { "HeightScale", "WidthScale", "DepthScale", "HeadScale", "BodyTypeScale", "ProportionScale" } do
						pcall(function()
							(description :: any)[property] = 1
						end)
					end
					pcall(function()
						humanoid:ApplyDescription(description)
					end)
					description:Destroy()
					if disposed or not model.Parent then
						return
					end
					-- Accessories change the bounding box, so re-seat the model on
					-- the floor and re-cache the pivot the drag rotation uses.
					for _, descendant in model:GetDescendants() do
						if descendant:IsA("BasePart") then
							descendant.Anchored = descendant == root
							descendant.CanCollide = false
							descendant.CanTouch = false
							descendant.CanQuery = false
						end
					end
					local reCFrame, reSize = model:GetBoundingBox()
					model:PivotTo(model:GetPivot() + Vector3.new(0, -(reCFrame.Position.Y - reSize.Y / 2), 0))
					basePivotRef.current = model:GetPivot()
				end)
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

				--[[
					Make the footballer finished BEFORE the menu is revealed.

					LoadAnimation returns immediately, but the keyframe data still
					has to arrive; until it does the rig holds its imported T-pose.
					Signalling readiness at Play() therefore revealed the menu while
					the character was still a T-pose blending into its idle -- which
					is exactly the "clipping in" that was visible.

					So: preload the animation asset, wait for the track to report a
					real Length, start it with NO fade so the very first frame is
					already the idle pose, and only then let the reveal proceed.
					Every wait is bounded so a bad asset cannot hang the menu.
				]]
				if loaded and track then
					track.Priority = Enum.AnimationPriority.Idle
					track.Looped = true

					pcall(function()
						ContentProvider:PreloadAsync({ animation })
					end)

					local waitStartedAt = os.clock()
					while track.Length <= 0 and os.clock() - waitStartedAt < 4 and not disposed do
						task.wait()
					end

					if not disposed then
						-- Zero fade: no blend out of the T-pose to be seen.
						track:Play(0, 1, 1)
						-- One presented frame, so the idle pose is actually drawn.
						RunService.RenderStepped:Wait()
					end

					if track.Length <= 0 then
						warn("[Beyond90][UI] Menu footballer idle did not load in time; revealing anyway")
					end
					Players.LocalPlayer:SetAttribute("Beyond90MenuCharacterReady", true)
				end
				animation:Destroy()
			end
			if not humanoid then
				-- No rig to animate; do not hold the reveal open for it.
				Players.LocalPlayer:SetAttribute("Beyond90MenuCharacterReady", true)
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
	-- The prompt set for the player's chosen scheme; mirrored on the player by
	-- ControlSchemeController so no screen needs a controller dependency.
	local menuPrompt = ControlSchemeConfig.MenuPrompts[
		ControlSchemeConfig.Normalize(localPlayer:GetAttribute(ControlSchemeConfig.AttributeName))
	] or ControlSchemeConfig.MenuPrompts.Keyboard
	local portrait, setPortrait = React.useState("")
	local playerBust, setPlayerBust = React.useState("")
	local selectedNavigation, setSelectedNavigation = React.useState(1)
	local rootRef = React.useRef(nil)
	local mobile = UserInputService.TouchEnabled
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

	--[[
		Every destination is now a real page (§12-§16).

		Clubs and Profile used to raise a "coming soon" toast because there was
		nothing to open. They now have designed pages that state honestly what
		they will hold, which is a far better answer to a player clicking them.
	]]
	local nav = {
		-- TRAINING is reached through PLAY now, not from Home (§15). The mode,
		-- its screen and the DEV entry points are all unchanged.
		{ "PLAY", "Jump into matches\nCompete and win", Assets.Navigation.Play, props.OpenModes },
		{ "CLUBS", "Join or create a club\nPlay together", Assets.Navigation.Clubs, props.OpenClubs },
		{ "PROFILE", "View stats and progression\nCustomize your identity", Assets.Navigation.Profile, props.OpenProfile },
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
		--[[
			ScaleType.Crop fills the frame and discards whatever does not fit,
			which is what clipped the wordmark on desktop: the frame is far wider
			than the source is, so Crop scaled to the width and cut the top and
			bottom away.

			Fit never crops. The source is mostly empty space around the mark, so
			the visible region is selected explicitly first -- the same rectangle
			the startup sequence uses -- and Fit then letterboxes only in the
			rare aspect ratios where the frame is narrower than the mark.
		]]
		Logo = React.createElement("ImageLabel", {
			Position = UDim2.fromScale(if mobile then 0.025 else 0.045, if mobile then 0.035 else 0.055),
			Size = UDim2.fromScale(if mobile then 0.34 else 0.38, if mobile then 0.17 else 0.2),
			BackgroundTransparency = 1, Image = Assets.Logo,
			ImageRectOffset = Vector2.new(20, 175),
			ImageRectSize = Vector2.new(1000, 300),
			ScaleType = Enum.ScaleType.Fit, ZIndex = 3,
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
			--[[
				Per ref/mockup 1.png the label is a caption attached to the card:
				it sits fully above the artwork, left edge aligned just inside the
				card's own left edge, with a small consistent gap.

				It previously spanned 0 -> 0.052 while the card began at 0.045, so
				the two overlapped and the label read as printed on the card's top
				edge rather than labelling it.
			]]
			Title = text({ Position = UDim2.fromScale(0.055, 0), Size = UDim2.fromScale(0.9, 0.042), Font = Enum.Font.GothamBold, Text = "FEATURED PLAYER", TextColor3 = Theme.AccentCyan, TextSize = if mobile then 9 else 12 }),
			Card = React.createElement("ImageLabel", { Position = UDim2.fromScale(0.01, 0.062), Size = UDim2.fromScale(0.98, 0.84), BackgroundTransparency = 1, Image = Assets.FeaturedPlayerFrame, ScaleType = Enum.ScaleType.Stretch, ClipsDescendants = true }, {
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
			Footer = React.createElement(MenuFooter.Root, {
				Mobile = mobile,
				DesktopTop = 0.9,
				DesktopHeight = 0.1,
				DesktopFadeHeight = 0.18,
				FadeZIndex = 2,
				--[[
					Below Navigation (ZIndex 5).

					ZIndexBehavior is Sibling, so ordering is decided between
					these two frames by their own ZIndex -- the footer's internal
					layering does not matter here. Defaulting the footer root to
					6 put its darkening wash in front of the navigation buttons
					and dimmed them. The wash belongs behind the nav.
				]]
				RootZIndex = 3,
				Content = React.createElement("Frame", {
					Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
				}, {
			--[[
				The select prompt follows the player's chosen control scheme
				(section 40). Showing the controller "A" glyph to somebody playing
				on a keyboard told them to press a button they do not have; a
				keyboard player gets a click prompt instead.
			]]
			--[[
				CONTROL HINTS (§9).

				Icon and label are laid out as one unit by MenuFooter.Prompt, so
				they cannot drift apart across viewports -- which is exactly what
				the previous hand-positioned version did, each piece placed at its
				own scale coordinate.

				The artwork follows the player's chosen control scheme (section
				40): a keyboard player is shown a mouse click and the ESC key, a
				controller player is shown the controller glyphs.
			]]
			SelectPrompt = React.createElement(MenuFooter.Prompt, {
				Mobile = mobile,
				Position = UDim2.fromScale(if mobile then 0.025 else 0.035, if mobile then 0.18 else 0.16),
				Image = if menuPrompt.SelectImageKey then Assets.Menu[menuPrompt.SelectImageKey] else "",
				Fallback = menuPrompt.Select,
				Label = "SELECT",
			}),
			OpenMenuPrompt = React.createElement(MenuFooter.Prompt, {
				Mobile = mobile,
				Position = UDim2.fromScale(if mobile then 0.115 else 0.135, if mobile then 0.18 else 0.16),
				Image = if menuPrompt.BackImageKey then Assets.Menu[menuPrompt.BackImageKey] else "",
				Fallback = menuPrompt.Back,
				Label = "OPEN MENU",
			}),
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
