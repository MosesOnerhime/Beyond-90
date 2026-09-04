--[[
	One-time control-scheme prompt.

	Shown over the menu the first time a desktop player arrives. Two cards, no
	navigation away from it -- picking one is the only exit, because every prompt
	the rest of the UI draws depends on the answer.

	Also reused inside Settings (Embedded = true), where it drops the backdrop and
	the heading and simply presents the two cards.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local React = require(ReplicatedStorage.Shared.ReactPackages).React
local ControlSchemeConfig = require(ReplicatedStorage.Shared.Config.ControlSchemeConfig)
local Assets = require(ReplicatedStorage.Shared.Config.UIAssetConfig)
local Theme = require(script.Parent.Parent.Theme)
local ReactUI = require(script.Parent.Parent.Components.ReactUI)
local MenuKit = require(script.Parent.Parent.Components.MenuKit)

local Schemes = ControlSchemeConfig.Schemes

--[[
	How each scheme is represented (§10).

	The supplied production artwork is used when it is available -- a photograph
	of the actual device is instantly recognisable in a way a drawn abstraction is
	not, which is the whole point of the selector.

	The drawn version below is KEPT as the fallback rather than deleted. A newly
	uploaded asset's moderation state is not confirmed yet (§57), and an empty
	frame where the device should be would make the screen unusable; the drawing
	costs nothing and always renders.
]]
local function SchemeArt(props)
	local accent = props.Accent

	local image = if props.Scheme == Schemes.Gamepad
		then Assets.ControlScheme.Gamepad
		else Assets.ControlScheme.Keyboard
	if typeof(image) == "string" and image ~= "" then
		return React.createElement("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, props.Top),
			Size = UDim2.fromScale(0.78, 0.3),
			BackgroundTransparency = 1,
			Image = image,
			-- Fit, never Crop: these are device photographs on transparency and
			-- cropping one cuts the device in half.
			ScaleType = Enum.ScaleType.Fit,
			ImageColor3 = Color3.new(1, 1, 1),
		})
	end

	if props.Scheme == Schemes.Gamepad then
		return React.createElement("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, props.Top),
			Size = UDim2.fromScale(0.52, 0.2),
			BackgroundColor3 = Theme.Panel,
			BackgroundTransparency = 0.25,
			BorderSizePixel = 0,
		}, {
			Corner = ReactUI.Corner(14),
			Stroke = ReactUI.Stroke(accent, 1.2, 0.4),
			-- Left stick.
			Stick = React.createElement("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = UDim2.fromScale(0.26, 0.46),
				Size = UDim2.fromScale(0.17, 0.34),
				BackgroundColor3 = accent,
				BackgroundTransparency = 0.15,
				BorderSizePixel = 0,
			}, { Corner = ReactUI.Corner(100) }),
			-- Face buttons, in the familiar diamond.
			North = React.createElement("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.74, 0.28),
				Size = UDim2.fromScale(0.09, 0.18), BackgroundColor3 = Theme.Warning,
				BorderSizePixel = 0,
			}, { Corner = ReactUI.Corner(100) }),
			South = React.createElement("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.74, 0.66),
				Size = UDim2.fromScale(0.09, 0.18), BackgroundColor3 = Theme.Good,
				BorderSizePixel = 0,
			}, { Corner = ReactUI.Corner(100) }),
			West = React.createElement("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.65, 0.47),
				Size = UDim2.fromScale(0.09, 0.18), BackgroundColor3 = Theme.AccentCyan,
				BorderSizePixel = 0,
			}, { Corner = ReactUI.Corner(100) }),
			East = React.createElement("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.83, 0.47),
				Size = UDim2.fromScale(0.09, 0.18), BackgroundColor3 = Theme.Poor,
				BorderSizePixel = 0,
			}, { Corner = ReactUI.Corner(100) }),
		})
	end

	-- Keyboard: the WASD cluster, which is the thing actually being chosen.
	local keys = {}
	local layout = {
		{ Key = "W", X = 0.5, Y = 0.26 },
		{ Key = "A", X = 0.28, Y = 0.7 },
		{ Key = "S", X = 0.5, Y = 0.7 },
		{ Key = "D", X = 0.72, Y = 0.7 },
	}
	for index, entry in layout do
		keys["Key" .. index] = React.createElement("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(entry.X, entry.Y),
			Size = UDim2.fromScale(0.19, 0.38),
			BackgroundColor3 = Theme.Panel,
			BackgroundTransparency = 0.1,
			BorderSizePixel = 0,
			Font = Theme.Fonts.Statistics,
			Text = entry.Key,
			TextColor3 = accent,
			TextScaled = true,
		}, {
			Corner = ReactUI.Corner(5),
			Stroke = ReactUI.Stroke(accent, 1, 0.45),
			Padding = ReactUI.Padding(4, 4, 4, 4),
			Fit = React.createElement("UITextSizeConstraint", { MinTextSize = Theme.MinimumCompactTextSize }),
		})
	end
	return React.createElement("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromScale(0.5, props.Top),
		Size = UDim2.fromScale(0.52, 0.2),
		BackgroundTransparency = 1,
	}, keys)
end

local function SchemeCard(props)
	--[[
		Hover and focus are separate states.

		They shared one flag set by MouseEnter and SelectionGained alike, so a
		controller could not tell which card it was on -- the distinction
		docs/ui/UI_AGENT_DECISION_RULES.md section 7 asks for. `active` keeps the
		shared background treatment; only `focused` draws the ring.
	]]
	local hovered, setHovered = React.useState(false)
	local focused, setFocused = React.useState(false)
	local active = props.Selected or hovered or focused
	local accent = if props.Selected then Theme.AccentCyan else Theme.MutedText
	local buttonRef = React.useRef(nil)
	local focusRef = React.useRef(nil)

	-- The blank SelectionImageObject only suppresses Roblox's default blue
	-- selection box; the ring below is the real indicator. See the note on it.
	React.useEffect(function()
		if buttonRef.current and focusRef.current then
			buttonRef.current.SelectionImageObject = focusRef.current
		end
		return nil
	end, {})

	return React.createElement("TextButton", {
		ref = buttonRef,
		LayoutOrder = props.Order,
		Size = UDim2.fromScale(if props.Mobile then 0.46 else 0.42, 1),
		BackgroundColor3 = if active then Theme.PanelHover else Theme.Panel,
		BackgroundTransparency = if active then 0.05 else 0.18,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Selectable = true,
		Text = "",
		ZIndex = 3,
		[React.Event.Activated] = props.Select,
		[React.Event.MouseEnter] = function() setHovered(true) end,
		[React.Event.MouseLeave] = function() setHovered(false) end,
		[React.Event.SelectionGained] = function() setFocused(true) end,
		[React.Event.SelectionLost] = function() setFocused(false) end,
	}, {
		--[[
			A SelectionImageObject IS STILL AN ORDINARY CHILD.

			Assigning one does not hide it: Roblox draws it over the selected
			control AND leaves it rendering where it sits in the hierarchy. A
			visible Frame here therefore put a permanent ring on both cards and on
			Confirm at once. So this stays blank -- its only job is to replace the
			default blue selection box with nothing.
		]]
		Focus = React.createElement("ImageLabel", {
			ref = focusRef,
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ImageTransparency = 1,
		}),
		-- The actual ring, drawn only while this card holds gamepad focus.
		-- Leading-edge marker, not a ring. See HomeScreen for the reasoning; the
		-- two screens must agree or selection means different things in each.
		EdgeMarker = focused and React.createElement("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 0, 0.5, 0),
			Size = UDim2.new(0, 4, 0.72, 0),
			BackgroundColor3 = Theme.SelectedText,
			BorderSizePixel = 0,
			ZIndex = 50,
		}, {
			Corner = ReactUI.Corner(2),
		}) or nil,
		Corner = ReactUI.Corner(8),
		Stroke = ReactUI.Stroke(
			if props.Selected then Theme.StrokeBright else Theme.Stroke,
			if props.Selected then 1.6 else 1,
			if props.Selected then 0.12 else 0.4
		),
		Accent = props.Selected and React.createElement("Frame", {
			Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = Theme.AccentCyan,
			BorderSizePixel = 0, ZIndex = 5,
		}, { Gradient = ReactUI.Gradient(Theme.AccentCyan, Theme.AccentViolet, 0) }) or nil,

		Art = React.createElement(SchemeArt, { Scheme = props.Scheme, Accent = accent, Top = 0.16 }),

		Name = React.createElement("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0.46),
			Size = UDim2.fromScale(0.88, 0.13),
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Display,
			Text = props.Name,
			TextColor3 = if props.Selected then Theme.SelectedText else Theme.Text,
			TextScaled = true,
			ZIndex = 4,
		}, {
			Fit = React.createElement("UITextSizeConstraint", { MinTextSize = Theme.MinimumCompactTextSize }),
		}),
		Summary = React.createElement("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0.63),
			Size = UDim2.fromScale(0.84, 0.2),
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Caption,
			Text = props.Summary,
			TextColor3 = Theme.MutedText,
			TextSize = MenuKit.Size(props.Mobile, 12),
			TextWrapped = true,
			ZIndex = 4,
		}),
		Status = props.Selected and React.createElement("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 0.95),
			Size = UDim2.fromScale(0.8, 0.09),
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Caption,
			Text = "SELECTED",
			TextColor3 = Theme.AccentCyan,
			TextSize = MenuKit.Size(props.Mobile, 11),
			ZIndex = 4,
		}) or nil,
	})
end

--[[
	props:
		Selected   current scheme
		Select     fn(scheme)
		Confirm    fn() -- omitted when Embedded
		Embedded   render inside Settings rather than as a modal
]]
return function(props)
	-- Phone landscape, decided by the viewport rather than by whether the device
	-- happens to have a touchscreen; see MenuKit.Compact.
	local mobile = MenuKit.Compact()
	local modalRef = React.useRef(nil)
	local confirmRef = React.useRef(nil)
	local confirmFocusRef = React.useRef(nil)
	local confirmFocused, setConfirmFocused = React.useState(false)
	local selected = props.Selected or Schemes.Keyboard

	local cards = {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0.04, 0),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}
	for index, scheme in { Schemes.Keyboard, Schemes.Gamepad } do
		local display = ControlSchemeConfig.Display[scheme]
		cards[scheme] = React.createElement(SchemeCard, {
			Order = index,
			Mobile = mobile,
			Scheme = scheme,
			Name = display.Name,
			Summary = display.Summary,
			Selected = selected == scheme,
			Select = function() props.Select(scheme) end,
		})
	end

	if props.Embedded then
		return React.createElement("Frame", {
			Size = props.Size or UDim2.fromScale(1, 1),
			Position = props.Position,
			BackgroundTransparency = 1,
			ZIndex = props.ZIndex or 2,
		}, cards)
	end

	--[[
		Focus starts on the confirm action -- FOR A GAMEPAD PLAYER ONLY.

		A gamepad player used to meet this prompt with nothing focused at all, so
		there was no visible focus and no obvious first move.

		It is conditional because taking selection is not free: a non-nil
		SelectedObject routes WASD and the arrow keys into menu navigation, which
		is exactly why UIController clears it when gameplay starts. Grabbing it
		for a mouse player would hijack their keyboard to move a highlight they
		cannot even see -- Roblox only draws the selection visual for gamepad.

		PreferredInput is the signal docs/ui/UI_RESPONSIVE_INPUT.md section 9
		names for this.
	]]
	React.useEffect(function()
		if confirmRef.current and confirmFocusRef.current then
			confirmRef.current.SelectionImageObject = confirmFocusRef.current
		end
		local previous = GuiService.SelectedObject
		local usingGamepad = UserInputService.PreferredInput == Enum.PreferredInput.Gamepad
		if usingGamepad and confirmRef.current then
			GuiService.SelectedObject = confirmRef.current
		end
		return function()
			if GuiService.SelectedObject and modalRef.current
				and GuiService.SelectedObject:IsDescendantOf(modalRef.current)
			then
				GuiService.SelectedObject = if previous and previous.Parent then previous else nil
			end
		end
	end, {})

	return React.createElement("Frame", {
		ref = modalRef,
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Background,
		BorderSizePixel = 0,
		ZIndex = 400,
		--[[
			A MODAL MUST CONTAIN THE CONTROLLER.

			docs/ui/UI_RESPONSIVE_INPUT.md section 7: when a modal opens, focus
			moves inside it and background controls are not reachable. Measured
			with this prompt open, they were: all four Home navigation buttons
			behind it were still selectable, so a gamepad could walk out of the
			modal and activate PLAY underneath it.

			SelectionGroup is Roblox's own answer -- gamepad selection cannot
			leave a group's descendants -- so it holds no matter what is rendered
			behind, without every other screen having to know a modal exists.
		]]
		SelectionGroup = true,
	}, {
		Background = React.createElement("ImageLabel", {
			Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
			Image = Assets.MenuStadium, ImageTransparency = 0.4,
			ScaleType = Enum.ScaleType.Crop, ZIndex = 400,
		}),
		Shade = React.createElement("Frame", {
			Size = UDim2.fromScale(1, 1), BackgroundColor3 = Theme.Background,
			BackgroundTransparency = 0.12, BorderSizePixel = 0, ZIndex = 401,
		}),
		Title = React.createElement("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, if mobile then 0.13 else 0.17),
			Size = UDim2.fromScale(0.7, if mobile then 0.1 else 0.085),
			BackgroundTransparency = 1, Font = Theme.Fonts.Display,
			Text = ControlSchemeConfig.Prompt.Title, TextColor3 = Theme.Text,
			TextScaled = true, ZIndex = 402,
		}, {
			Fit = React.createElement("UITextSizeConstraint", { MinTextSize = Theme.MinimumCompactTextSize }),
		}),
		Subtitle = React.createElement("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, if mobile then 0.25 else 0.27),
			Size = UDim2.fromScale(0.6, if mobile then 0.05 else 0.04),
			BackgroundTransparency = 1, Font = Theme.Fonts.Body,
			Text = ControlSchemeConfig.Prompt.Body, TextColor3 = Theme.MutedText,
			TextScaled = true, ZIndex = 402,
		}, {
			Fit = React.createElement("UITextSizeConstraint", { MinTextSize = Theme.MinimumCompactTextSize }),
		}),
		Cards = React.createElement("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, if mobile then 0.33 else 0.35),
			Size = UDim2.fromScale(0.82, if mobile then 0.42 else 0.4),
			BackgroundTransparency = 1, ZIndex = 402,
		}, cards),
		Confirm = React.createElement("TextButton", {
			ref = confirmRef,
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, if mobile then 0.9 else 0.88),
			Size = UDim2.fromScale(if mobile then 0.34 else 0.2, if mobile then 0.09 else 0.07),
			BackgroundColor3 = Theme.AccentDark, BorderSizePixel = 0, AutoButtonColor = false,
			Font = Theme.Fonts.Navigation, Text = "CONFIRM", TextColor3 = Theme.Text,
			TextSize = MenuKit.Size(mobile, 17), ZIndex = 403, Selectable = true,
			[React.Event.Activated] = props.Confirm,
			[React.Event.SelectionGained] = function() setConfirmFocused(true) end,
			[React.Event.SelectionLost] = function() setConfirmFocused(false) end,
		}, {
			-- A proportional height has no floor; this is the touch-target one.
			MinimumHeight = ReactUI.MinimumSize(nil, Theme.MinimumTouchTarget),
			Corner = ReactUI.Corner(5),
			Stroke = ReactUI.Stroke(Theme.AccentCyan, 1.25, 0.18),
			-- Blank: suppresses Roblox's default selection box only. Assigning a
			-- visible Frame here does not hide it -- it renders as an ordinary
			-- child as well -- which is what ringed every control at once.
			Focus = React.createElement("ImageLabel", {
				ref = confirmFocusRef,
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				ImageTransparency = 1,
			}),
			-- The real indicator, drawn only while Confirm holds gamepad focus.
			--[[
				A primary button gets an underline rather than a leading bar: its
				label is centred, so a left-edge marker would read as decoration
				rather than as "this is where the controller is".
			]]
			FocusUnderline = confirmFocused and React.createElement("Frame", {
				AnchorPoint = Vector2.new(0.5, 1),
				Position = UDim2.new(0.5, 0, 1, -3),
				Size = UDim2.new(0.55, 0, 0, 3),
				BackgroundColor3 = Theme.SelectedText,
				BorderSizePixel = 0,
				ZIndex = 50,
			}, {
				Corner = ReactUI.Corner(2),
			}) or nil,
		}),
	})
end
