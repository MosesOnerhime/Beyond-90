local Players = game:GetService("Players")
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterPlayer = game:GetService("StarterPlayer")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local React = require(ReplicatedStorage.Shared.ReactPackages).React
local Assets = require(ReplicatedStorage.Shared.Config.UIAssetConfig)
local ExperienceConfig = require(ReplicatedStorage.Shared.Config.ExperienceConfig)
local PlayerConfig = require(ReplicatedStorage.Shared.Config.PlayerConfig)
local Theme = require(script.Parent.Parent.Theme)
local ReactUI = require(script.Parent.Parent.Components.ReactUI)
local MenuFooter = require(script.Parent.Parent.Components.MenuFooter)
local MenuKit = require(script.Parent.Parent.Components.MenuKit)
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
	-- Through MenuKit so scaled labels pick up the readability floor; see
	-- MenuKit.Text. The defaults above still win, they are merged first.
	return MenuKit.Text(merged)
end

local function AnimatedMenuPlayer()
	local viewportRef = React.useRef(nil)
	local modelRef = React.useRef(nil)
	local basePivotRef = React.useRef(nil)
	local dragRef = React.useRef({ Active = false, X = 0, Yaw = 0 })
	--[[
		THE VIEWPORT SHOWS NOTHING UNTIL THE FOOTBALLER IS FINISHED.

		The rig was being presented the moment it was cloned, and the player's
		own avatar was applied afterwards from a detached `task.spawn`. So the
		menu showed the stock footballer first and swapped it for the player a
		moment later -- the "old character shows before my avatar" pop.

		A half-built character is not worth showing. The viewport stays hidden
		until the description has been applied and the idle is holding, and the
		first frame anyone sees is the finished footballer.
	]]
	local rigReady, setRigReady = React.useState(false)
	React.useEffect(function()
		local disposed = false
		local viewport = viewportRef.current
		if not viewport then return nil end
		--[[
			The avatar fetch starts HERE, before the rig is even cloned, so the
			web request overlaps the clone and the strip rather than following
			them. Awaited further down, once there is a humanoid to apply it to.
		]]
		local identityConfigEarly = PlayerConfig.Appearance.Identity
		local chosenSourceEarly = localPlayer:GetAttribute(identityConfigEarly.AttributeName)
		if typeof(chosenSourceEarly) ~= "string" or not identityConfigEarly.Sources[chosenSourceEarly] then
			chosenSourceEarly = identityConfigEarly.Default
		end
		local wantsAvatar = identityConfigEarly.Enabled == true
			and chosenSourceEarly == identityConfigEarly.Sources.RobloxAvatar
		local avatarDescription: HumanoidDescription? = nil
		local avatarFetchDone = not wantsAvatar
		if wantsAvatar then
			task.spawn(function()
				local okFetch, description = pcall(function()
					return Players:GetHumanoidDescriptionFromUserId(localPlayer.UserId)
				end)
				avatarDescription = if okFetch then description else nil
				avatarFetchDone = true
			end)
		end
		task.spawn(function()
			--[[
				THE MENU FOOTBALLER IS THE ONE YOU ACTUALLY PLAY AS.

				The rig came from `menu_character`, a separate model that is not
				the body any footballer on the pitch has -- measured, it is 5.92
				studs against StarterCharacter's own build. That was survivable
				only while every player wore their Roblox avatar in the menu,
				because the description replaced almost all of it anyway.

				It stopped being survivable when the Beyond 90 kit became the
				default footballer: a player who has not changed anything now sees
				an anonymous rig in the menu and a different body on the pitch.
				The menu is where a player meets their footballer, so it has to be
				the same footballer.

				StarterPlayer.StarterCharacter is that body, it replicates to
				clients, and it is the exact model the AI and the player are both
				built from. The old sources are kept as fallbacks so a place
				without a StarterCharacter still shows somebody.
			]]
			--[[
				A ROBLOX AVATAR IS BUILT FROM ITS DESCRIPTION, NOT PAINTED ONTO
				THE KIT.

				Applying a HumanoidDescription over a cloned StarterCharacter does
				NOT give you that avatar. ApplyDescription swaps only what the
				description explicitly overrides and leaves every other part in
				place, so the kit's own limbs survive underneath. Measured on the
				live menu rig, wearing a Roblox avatar:

					UpperTorso   = 542765884    the player's      (replaced)
					LeftUpperLeg = 2337186877   the Beyond 90 kit (survived)
					Head         = 2337186646   the Beyond 90 kit (survived)

				-- the player's torso and clothes on the kit's legs and head. Not
				a footballer and not an avatar; a hybrid of the two, and it looked
				exactly as bad as that sounds.

				CreateHumanoidModelFromDescription builds the whole rig from the
				description in one step, which is the only way to get the avatar
				the player actually has. The kit clone stays as the source for
				everybody NOT wearing their own avatar, where it is correct.
			]]
			if wantsAvatar then
				local waitStartedAt = os.clock()
				while not avatarFetchDone and os.clock() - waitStartedAt < 4 and not disposed do
					task.wait()
				end
			end
			local builtFromAvatar = nil
			if wantsAvatar and avatarDescription and not disposed then
				local okBuild, built = pcall(function()
					return Players:CreateHumanoidModelFromDescription(
						avatarDescription :: HumanoidDescription,
						Enum.HumanoidRigType.R15
					)
				end)
				if okBuild and built then
					builtFromAvatar = built
				else
					warn("[Beyond90][UI] Could not build the menu avatar; showing the Beyond 90 kit")
				end
			end

			-- The kit now lives in ReplicatedStorage (see
			-- PlayerService.CloneFootballerTemplate for why it left
			-- StarterCharacter); StarterCharacter stays as a fallback.
			local sourceRig = builtFromAvatar
				or ReplicatedStorage:FindFirstChild("Beyond90Kit")
				or StarterPlayer:FindFirstChild("StarterCharacter")
			if not (sourceRig and sourceRig:IsA("Model") and sourceRig:FindFirstChildOfClass("Humanoid")) then
				sourceRig = ReplicatedStorage:WaitForChild("Beyond90MenuCharacter", 5)
			end
			if not sourceRig then
				local workspaceRig = Workspace:FindFirstChild("menu_character")
				sourceRig = if workspaceRig and workspaceRig:FindFirstChildWhichIsA("BasePart", true) then workspaceRig else nil
			end
			-- A rig built from the description is already ours and single-use, so
			-- it is adopted directly; a shared source (the kit) must be cloned.
			local ok, model = pcall(function()
				if builtFromAvatar and sourceRig == builtFromAvatar then
					return builtFromAvatar
				end
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
			--[[
				THE MENU FOOTBALLER IS YOU -- BEFORE IT IS EVER SEEN.

				This used to run detached, so the stock rig was already on screen
				when the player's avatar landed on top of it. It is now awaited in
				line: the fetch was started before the clone, so by this point it
				has usually already returned and the wait costs nothing.

				The wait is bounded. A slow or failing avatar service costs a short
				delay and then shows the default footballer -- exactly what was
				shown before this feature existed -- rather than holding the menu.
			]]
			if wantsAvatar and humanoid then
				local fetchWaitStartedAt = os.clock()
				while not avatarFetchDone and os.clock() - fetchWaitStartedAt < 4 and not disposed do
					task.wait()
				end
				if not avatarFetchDone then
					warn(
						"[Beyond90][UI] Menu avatar slow; showing the default footballer "
							.. "and wearing the avatar when it lands"
					)
				end
			end
			--[[
				Wearing the player's own avatar onto the mounted rig.

				Pulled out of the mount path because a LATE-ARRIVING fetch has to
				do exactly the same thing -- see the watcher below.
			]]
			--[[
				Set once the camera exists; the watcher below may fire before or
				after that, so it is checked rather than assumed.
			]]
			local reframeAfterLateAvatar: (() -> ())? = nil

			local function wearDescription(description: HumanoidDescription)
				if not humanoid or disposed or not model.Parent then
					return
				end
				-- Same rule as on the pitch: the face is the player's, the frame
				-- is everyone's, so the menu shows the footballer they will be.
				for _, property in { "HeightScale", "WidthScale", "DepthScale", "HeadScale", "BodyTypeScale", "ProportionScale" } do
					pcall(function()
						(description :: any)[property] = 1
					end)
				end
				pcall(function()
					humanoid:ApplyDescription(description)
				end)
				-- Accessories change the bounding box, so the parts added by the
				-- description need the same treatment the cloned ones got.
				for _, descendant in model:GetDescendants() do
					if descendant:IsA("BasePart") then
						descendant.Anchored = descendant == root
						descendant.CanCollide = false
						descendant.CanTouch = false
						descendant.CanQuery = false
					end
				end
			end

			local description = avatarDescription
			if builtFromAvatar then
				-- Already built from this description; re-applying it here is what
				-- used to layer the avatar over the kit.
				description = nil
			end
			if description then
				wearDescription(description)
				description:Destroy()
			end
			avatarDescription = nil

			--[[
				A LATE AVATAR STILL GETS WORN.

				The waits above are bounded so a slow fetch cannot hold the menu.
				They used to be bounded AND FINAL: past the deadline the player was
				shown the stock kit for the rest of the session, even though their
				avatar landed a moment later. That is what the player saw --

					22:02:07.473  Menu asset preload incomplete (timed out) ... 17 pending
					22:02:07.473  Menu avatar fetch timed out; showing the default footballer

				-- both timing out on the same tick, because the avatar fetch is
				queued behind the menu's own asset preload. The deadline was not
				really the bug; giving up permanently was.

				So the deadline now only decides WHAT IS SHOWN FIRST. If the fetch
				lands afterwards the rig puts the avatar on then, which is a brief
				change on a decorative surface rather than a wrong one for the
				whole session. Bounded by disposal and by the rig still being
				mounted, so nothing is left running behind a closed menu.
			]]
			if wantsAvatar and not avatarFetchDone then
				task.spawn(function()
					while not avatarFetchDone and not disposed and model.Parent do
						task.wait()
					end
					local late = avatarDescription
					avatarDescription = nil
					if not late then
						return
					end
					if disposed or not model.Parent then
						late:Destroy()
						return
					end
					wearDescription(late)
					late:Destroy()
					-- The avatar just changed the rig's height; stand it back on
					-- the floor and re-frame the shot around what is now there.
					if reframeAfterLateAvatar and not disposed and model.Parent then
						reframeAfterLateAvatar()
					end
				end)
			end

			--[[
				Stand the rig on the floor and report the height it turned out to
				be. Separated from the mount path because WEARING AN AVATAR CHANGES
				THE BOUNDING BOX -- a hat or a hairstyle makes the rig taller -- so
				a late-arriving avatar has to redo both the ground pivot and the
				framing that was measured from it, or it floats and gets cropped.
			]]
			local function standOnFloor(): number
				model:PivotTo(CFrame.Angles(0, math.rad(135), 0))
				local groundCFrame, groundSize = model:GetBoundingBox()
				model:PivotTo(
					model:GetPivot() + Vector3.new(0, -(groundCFrame.Position.Y - groundSize.Y / 2), 0)
				)
				basePivotRef.current = model:GetPivot()
				return math.max(groundSize.Y, 0.01)
			end

			local boundingSizeY = standOnFloor()
			modelRef.current = model
			--[[
				FRAME THE FOOTBALLER THAT IS ACTUALLY THERE.

				These numbers were literals tuned against the old 5.92-stud
				menu_character: eye height 4.35, look-at 4.15, distance 20.5. Point
				them at a taller rig and the head leaves the frame.

				They are the same shot expressed as ratios of the rig's own
				measured height, so a 5.92 rig is framed exactly as before and any
				other rig -- the kit, a tall Roblox avatar, whatever a later
				milestone puts here -- is framed the same way rather than cropped.
			]]
			local camera = Instance.new("Camera")
			camera.FieldOfView = 21
			local function frameRig(rigHeight: number)
				camera.CFrame = CFrame.lookAt(
					Vector3.new(-0.135 * rigHeight, 0.735 * rigHeight, 3.463 * rigHeight),
					Vector3.new(0, 0.701 * rigHeight, 0)
				)
			end
			frameRig(boundingSizeY)
			camera.Parent = viewport
			viewport.CurrentCamera = camera
			-- Handed to the late-avatar watcher so it can re-stand and re-frame.
			reframeAfterLateAvatar = function()
				frameRig(standOnFloor())
			end
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
					if not disposed then setRigReady(true) end
				end
				animation:Destroy()
			end
			if not humanoid then
				-- No rig to animate; do not hold the reveal open for it.
				Players.LocalPlayer:SetAttribute("Beyond90MenuCharacterReady", true)
				if not disposed then setRigReady(true) end
			end
			--[[
				Belt and braces: nothing above is allowed to leave the viewport
				permanently blank. If the animation branch fell through -- a rig
				with a humanoid but no loadable idle -- the footballer is still
				finished and should still be shown.
			]]
			if not disposed then
				setRigReady(true)
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
		-- Hidden until the footballer is the player's own and holding its idle.
		Visible = rigReady,
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
	local compact = MenuKit.Compact()
	--[[
		HOVER AND FOCUS ARE TRACKED SEPARATELY.

		They used to share one `focused` flag set by MouseEnter and
		SelectionGained alike, so a controller could not tell which card it was on
		beyond the same background change a mouse produces -- the distinction
		docs/ui/UI_AGENT_DECISION_RULES.md section 7 asks for. `active` keeps the
		shared background treatment; only `focused` draws the ring.
	]]
	local hovered, setHovered = React.useState(false)
	local focused, setFocused = React.useState(false)
	local active = hovered or focused
	local buttonRef = React.useRef(nil)
	local selectionRef = React.useRef(nil)
	React.useEffect(function()
		if buttonRef.current and selectionRef.current then
			buttonRef.current.SelectionImageObject = selectionRef.current
		end
		-- Publish upward so the row can wire an explicit focus order; see the
		-- effect in the Home screen below.
		if props.Register then
			props.Register(props.Order, buttonRef.current)
		end
		return nil
	end, {})
	return React.createElement("TextButton", {
		ref = buttonRef,
		LayoutOrder = props.Order,
		Size = UDim2.new(0.19, 0, 1, 0),
		BackgroundColor3 = if active or props.Selected then Theme.PanelSelected else Theme.Panel,
		BackgroundTransparency = if active or props.Selected then 0.02 else 0.08,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Selectable = true,
		Text = "",
		[React.Event.Activated] = props.OnActivated,
		[React.Event.MouseEnter] = function()
			setHovered(true)
			if props.OnFocused then props.OnFocused() end
		end,
		[React.Event.MouseLeave] = function() setHovered(false) end,
		[React.Event.SelectionGained] = function()
			setFocused(true)
			if props.OnFocused then props.OnFocused() end
		end,
		[React.Event.SelectionLost] = function() setFocused(false) end,
	}, {
		--[[
			SELECTION IS AN EDGE MARKER, NOT A RING.

			This used to draw up to three outlines at once: a cyan halo on the
			selected card, a brightened stroke on it, and a second ring on the
			gamepad-focused one. Rejected by the player -- "I do not like the blue
			selector round boxes" -- and AGENTS.md section 40 names the same thing
			in its list of defaults to avoid: glowing borders on every card.

			What replaces it is what sports broadcast and EA FC's own menus use: a
			solid accent bar down the LEADING EDGE of the active card, with the
			card surface lifting slightly. It reads instantly at TV distance,
			survives a bright stadium background, costs one thin rectangle, and
			leaves the card's own rectangle clean -- which is the "strong
			rectangular navigation cards" the approved mockup is built on.

			Selected and focused are still distinguishable: the bar is accent blue
			for the screen you are on, and white for the one the controller is
			sitting on, which is the same white the selected label uses.
		]]
		EdgeMarker = (props.Selected or focused) and React.createElement("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 0, 0.5, 0),
			Size = UDim2.new(0, 4, 0.72, 0),
			BackgroundColor3 = if focused then Theme.SelectedText else Theme.Accent,
			BackgroundTransparency = 0,
			BorderSizePixel = 0,
			ZIndex = 50,
		}, {
			Corner = ReactUI.Corner(2),
		}) or nil,
		--[[
			A SelectionImageObject IS STILL AN ORDINARY CHILD.

			Assigning one does not hide it: Roblox draws it over the selected
			control AND leaves it rendering where it sits in the hierarchy. A
			visible Frame here therefore put a permanent ring on all four cards at
			once, which is what it did until this comment was written.

			So this stays deliberately blank. Its only job is to replace Roblox's
			default blue selection box with nothing; the edge marker above is the
			actual indicator.
		]]
		SelectionImage = React.createElement("ImageLabel", {
			ref = selectionRef,
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ImageTransparency = 1,
		}),
		Corner = ReactUI.Corner(5),
		-- One quiet stroke in every state. The edge marker carries the selection.
		Stroke = ReactUI.Stroke(Theme.Stroke, 1, if active or props.Selected then 0.12 else 0.3),
		Icon = React.createElement("ImageLabel", {
			Position = UDim2.fromScale(0.05, 0.16),
			Size = UDim2.fromScale(0.26, 0.68),
			BackgroundTransparency = 1,
			Image = props.Icon,
			ScaleType = Enum.ScaleType.Fit,
		}),
		--[[
			THE SUBTITLE IS DROPPED IN PHONE LANDSCAPE.

			The navigation row is 15% of screen height, so on a 780x360 phone a
			card is 54px tall and the subtitle's share of that is 16px. Its text
			wraps to two or three lines and needs 31-41px, so it overflowed the
			card no matter what size the type was -- measured at 11px:

				"Jump into matche..."  needs 82x31  box 85x16

			docs/ui/UI_RESPONSIVE_INPUT.md section 2 ranks preserving the primary
			action and readable text above keeping secondary content, and section
			3 explicitly allows the composition to change on a phone. The title
			IS the action; the subtitle explains it. So the subtitle goes and the
			title takes the whole card, centred, at a size that fits.

			Nothing is lost that the player needs: "PLAY", "CLUBS", "PROFILE" and
			"SETTINGS" are self-describing, which is why they are the labels.
		]]
		Title = text({
			Position = UDim2.fromScale(0.34, if compact then 0.2 else 0.23),
			Size = UDim2.fromScale(0.61, if compact then 0.6 else 0.22),
			Font = Theme.Fonts.Navigation, Text = props.Title,
			TextSize = MenuKit.Size(compact, 16),
			TextYAlignment = if compact then Enum.TextYAlignment.Center else Enum.TextYAlignment.Top,
		}),
		Subtitle = not compact and text({
			Position = UDim2.fromScale(0.34, 0.49), Size = UDim2.fromScale(0.61, 0.3),
			Font = Enum.Font.Gotham, Text = props.Subtitle, TextColor3 = Theme.MutedText,
			TextWrapped = true, TextSize = MenuKit.Size(compact, 11),
		}) or nil,
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
			TextSize = MenuKit.Size(props.Mobile, 11), TextXAlignment = Enum.TextXAlignment.Center,
		}),
		Value = text({
			Position = UDim2.fromScale(0, 0.41), Size = UDim2.fromScale(1, 0.51),
			Font = Enum.Font.GothamBold, Text = props.Value, TextColor3 = Theme.Text,
			TextSize = MenuKit.Size(props.Mobile, 14), TextXAlignment = Enum.TextXAlignment.Center,
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
	-- Buttons of the navigation row, published by each card so the row can be
	-- given an explicit gamepad focus order (see the effect below).
	local navButtonsRef = React.useRef({})
	-- Phone landscape, decided by the viewport rather than by whether the device
	-- happens to have a touchscreen; see MenuKit.Compact.
	local mobile = MenuKit.Compact()
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
			Register = function(order, button)
				navButtonsRef.current[order] = button
			end,
		})
	end

	--[[
		AN EXPLICIT FOCUS ORDER ALONG THE NAVIGATION ROW.

		docs/ui/UI_RESPONSIVE_INPUT.md section 7 asks for a deterministic focus
		order and warns against relying on Roblox's automatic geometric
		selection. Measured, nothing in the menu set any NextSelection link at
		all -- 0 of 7 selectable buttons -- so every gamepad move was a guess
		made from screen positions.

		The row is wired left-to-right and wraps at both ends, so holding a
		direction cycles rather than dead-ending on the last card. Wired from
		refs rather than by layout order alone, so it stays correct if a card is
		hidden or reordered.
	]]
	React.useEffect(function()
		local buttons = navButtonsRef.current
		local count = #nav
		for index = 1, count do
			local button = buttons[index]
			if button then
				button.NextSelectionLeft = buttons[if index > 1 then index - 1 else count]
				button.NextSelectionRight = buttons[if index < count then index + 1 else 1]
			end
		end
		return nil
	end, {})

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
			Eyebrow = text({ Size = UDim2.fromScale(1, 0.09), Font = Enum.Font.GothamMedium, Text = "CURRENT SEASON", TextColor3 = Theme.AccentCyan, TextSize = MenuKit.Size(mobile, 15) }),
			Title = text({ Position = UDim2.fromScale(0, 0.11), Size = UDim2.fromScale(1, 0.13), Font = Enum.Font.GothamBlack, Text = "SEASON 1 - RISING", TextSize = MenuKit.Size(mobile, 27) }),
			TimeIcon = Assets.Menu.Time ~= "" and React.createElement("ImageLabel", {
				Position = UDim2.fromScale(0, 0.245), Size = UDim2.fromScale(0.035, 0.07),
				BackgroundTransparency = 1, Image = Assets.Menu.Time, ScaleType = Enum.ScaleType.Fit,
			}) or nil,
			Ends = text({ Position = UDim2.fromScale(0.04, 0.245), Size = UDim2.fromScale(0.6, 0.07), Font = Theme.Fonts.Caption, Text = "ENDS IN 28 DAYS", TextColor3 = Theme.MutedText, TextSize = MenuKit.Size(mobile, 13) }),
			Panel = glassFrame({ Position = UDim2.fromScale(0, 0.34), Size = UDim2.fromScale(1, 0.66), Transparency = 0.24 }, {
				Badge = React.createElement("ImageLabel", { Position = UDim2.fromScale(0.025, 0.025), Size = UDim2.fromScale(0.245, 0.53), BackgroundTransparency = 1, Image = Assets.DivisionBadge, ImageColor3 = Color3.fromRGB(205, 218, 238), ScaleType = Enum.ScaleType.Fit }, {
					TopShade = React.createElement("Frame", { Position = UDim2.fromScale(0.08, 0.02), Size = UDim2.fromScale(0.84, 0.28), BackgroundColor3 = Color3.fromRGB(4, 9, 26), BackgroundTransparency = 0.62, BorderSizePixel = 0 }),
				}),
			DivisionCaption = text({ Position = UDim2.fromScale(0.285, 0.075), Size = UDim2.fromScale(0.3, 0.08), Text = "DIVISION", TextColor3 = Theme.MutedText, TextSize = MenuKit.Size(mobile, 11) }),
			Division = text({ Position = UDim2.fromScale(0.285, 0.16), Size = UDim2.fromScale(0.35, 0.1), Font = Theme.Fonts.Navigation, Text = "DIAMOND II", TextSize = MenuKit.Size(mobile, 16) }),
			RatingCaption = text({ Position = UDim2.fromScale(0.285, if mobile then 0.275 else 0.29), Size = UDim2.fromScale(0.25, 0.07), Text = "RATING", TextColor3 = Theme.MutedText, TextSize = MenuKit.Size(mobile, 11) }),
			RatingNetwork = React.createElement("ImageLabel", { Position = UDim2.fromScale(0.285, 0.365), Size = UDim2.fromScale(0.045, 0.075), BackgroundTransparency = 1, Image = Assets.Social.Network, ScaleType = Enum.ScaleType.Fit }),
			Rating = text({ Position = UDim2.fromScale(0.34, 0.355), Size = UDim2.fromScale(0.25, 0.1), Font = Theme.Fonts.Statistics, Text = "1,286", TextSize = MenuKit.Size(mobile, 17) }),
			Reward = text({ Position = UDim2.fromScale(0.665, 0.065), Size = UDim2.fromScale(0.19, 0.17), Font = Theme.Fonts.Caption, Text = "NEXT REWARD\nDIAMOND I", TextColor3 = Theme.AccentCyan, TextWrapped = true, TextSize = MenuKit.Size(mobile, 11) }),
				Diamond = React.createElement("ImageLabel", { Position = UDim2.fromScale(0.84, 0.08), Size = UDim2.fromScale(0.12, 0.23), BackgroundTransparency = 1, Image = Assets.Currency.Premium, ScaleType = Enum.ScaleType.Fit }),
				Progress = React.createElement("Frame", { Position = UDim2.fromScale(0.285, 0.47), Size = UDim2.fromScale(0.54, 0.025), BackgroundColor3 = Theme.Stroke, BorderSizePixel = 0 }, {
					Fill = React.createElement("Frame", { Size = UDim2.fromScale(0.91, 1), BackgroundColor3 = Theme.Accent, BorderSizePixel = 0 }, { Gradient = ReactUI.Gradient(Theme.AccentViolet, Theme.AccentCyan) }),
				}),
			-- Right-aligned, so a box narrower than the string overflows LEFT across
			-- the progress bar rather than truncating. At 780x360 "1,286 / 1,400"
			-- needs 54px of glyphs in a 42px box, so the box widens on compact;
			-- the right edge stays at 0.98 either way, so nothing moves.
			ProgressCount = text({ Position = UDim2.fromScale(if mobile then 0.68 else 0.84, 0.42),
				Size = UDim2.fromScale(if mobile then 0.3 else 0.14, 0.1), Font = Theme.Fonts.Caption, Text = "1,286 / 1,400", TextColor3 = Theme.Text, TextSize = MenuKit.Size(mobile, 10), TextXAlignment = Enum.TextXAlignment.Right }),
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
			Title = text({ Position = UDim2.fromScale(0.055, 0), Size = UDim2.fromScale(0.9, 0.042), Font = Enum.Font.GothamBold, Text = "FEATURED PLAYER", TextColor3 = Theme.AccentCyan, TextSize = MenuKit.Size(mobile, 12) }),
			Card = React.createElement("ImageLabel", { Position = UDim2.fromScale(0.01, 0.062), Size = UDim2.fromScale(0.98, 0.84), BackgroundTransparency = 1, Image = Assets.FeaturedPlayerFrame, ScaleType = Enum.ScaleType.Stretch, ClipsDescendants = true }, {
				Portrait = React.createElement("ImageLabel", { Position = UDim2.fromScale(0.18, 0.08), Size = UDim2.fromScale(0.72, 0.54), BackgroundTransparency = 1, Image = if playerBust ~= "" then playerBust else portrait, ScaleType = Enum.ScaleType.Fit, Rotation = 5 }, {
					Fade = React.createElement("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.65, 0.04), NumberSequenceKeypoint.new(1, 1) }) }),
				}),
				Rating = text({ Position = UDim2.fromScale(0.13, 0.13), Size = UDim2.fromScale(0.17, 0.075), Font = Enum.Font.GothamBlack, Text = "92", TextSize = MenuKit.Size(mobile, 23), TextXAlignment = Enum.TextXAlignment.Center }),
				Position = text({ Position = UDim2.fromScale(0.13, 0.205), Size = UDim2.fromScale(0.17, 0.05), Font = Enum.Font.GothamBold, Text = "LW", TextSize = MenuKit.Size(mobile, 12), TextXAlignment = Enum.TextXAlignment.Center }),
				NameRow = React.createElement("Frame", { Position = UDim2.fromScale(0.11, 0.65), Size = UDim2.fromScale(0.78, 0.065), BackgroundTransparency = 1 }, {
					Country = React.createElement("ImageLabel", { Position = UDim2.fromScale(0.03, 0.12), Size = UDim2.fromScale(0.14, 0.76), BackgroundTransparency = 1, Image = Assets.Menu.NigeriaFlag, ScaleType = Enum.ScaleType.Fit }),
					Name = text({ Size = UDim2.fromScale(1, 1), Font = Enum.Font.GothamBold, Text = string.upper(localPlayer.DisplayName), TextXAlignment = Enum.TextXAlignment.Center, TextSize = MenuKit.Size(mobile, 11), TextTruncate = Enum.TextTruncate.AtEnd }),
				}),
				--[[
					THE SIX-STAT GRID IS DROPPED IN PHONE LANDSCAPE.

					The grid is 68% x 16% of a card that is itself a fifth of the
					screen, which on a 780x360 phone is 85x29px holding six stats
					in two rows -- about 28x14px each. It only ever "fit" because
					the labels were 6px, which is unreadable and is the "tiny stat
					labels" docs/ui/UI_ACCESSIBILITY_LOCALIZATION.md section 1
					names directly.

					Six attribute numbers are tertiary decoration on the home
					screen; section 2's adaptation priority removes that before it
					compromises readable text. The card keeps what identifies the
					player -- portrait, rating, position, name -- which is the part
					that carries meaning at a glance.
				]]
				Stats = not mobile and React.createElement("Frame", { Position = UDim2.fromScale(0.16, 0.725), Size = UDim2.fromScale(0.68, 0.16), BackgroundTransparency = 1 }, {
					PAC = React.createElement(PlayerStat, { Position = UDim2.fromScale(0, 0), Value = "94", Label = "PAC", Mobile = mobile }),
					SHO = React.createElement(PlayerStat, { Position = UDim2.fromScale(0.37, 0), Value = "91", Label = "SHO", Mobile = mobile }),
					PAS = React.createElement(PlayerStat, { Position = UDim2.fromScale(0.74, 0), Value = "87", Label = "PAS", Mobile = mobile }),
					DRI = React.createElement(PlayerStat, { Position = UDim2.fromScale(0, 0.52), Value = "93", Label = "DRI", Mobile = mobile }),
					DEF = React.createElement(PlayerStat, { Position = UDim2.fromScale(0.37, 0.52), Value = "42", Label = "DEF", Mobile = mobile }),
					PHY = React.createElement(PlayerStat, { Position = UDim2.fromScale(0.74, 0.52), Value = "81", Label = "PHY", Mobile = mobile }),
				}) or nil,
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
			NewsTag = text({ Position = UDim2.fromScale(if mobile then 0.125 else 0.295, 0.22), Size = UDim2.fromScale(if mobile then 0.065 else 0.06, 0.5), Font = Theme.Fonts.Navigation, Text = "NEWS", TextColor3 = Theme.Accent, TextSize = MenuKit.Size(mobile, 12) }),
			News = text({ Position = UDim2.fromScale(if mobile then 0.19 else 0.34, if mobile then 0.08 else 0.22), Size = UDim2.fromScale(if mobile then 0.53 else 0.43, if mobile then 0.84 else 0.5), Font = Enum.Font.Gotham, Text = "Welcome to Beyond 90! Season 1 is live now. Compete, climb the ranks, and become a legend.", TextColor3 = Color3.fromRGB(205, 214, 234), TextSize = MenuKit.Size(mobile, 11), TextWrapped = mobile }),
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
