local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Shared.ReactPackages).React
local Assets = require(ReplicatedStorage.Shared.Config.UIAssetConfig)
local Theme = require(script.Parent.Parent.Theme)
local ReactUI = require(script.Parent.Parent.Components.ReactUI)
local MenuKit = require(script.Parent.Parent.Components.MenuKit)
local MenuFooter = require(script.Parent.Parent.Components.MenuFooter)
local BackButton = require(script.Parent.Parent.Components.BackButton)

local function TeamCard(props)
	local focused, setFocused = React.useState(false)
	local active = props.Selected or focused
	return React.createElement("TextButton", {
		LayoutOrder = props.Order,
		Size = UDim2.fromScale(0.38, 0.58), BackgroundColor3 = active and Theme.PanelHover or Theme.Panel,
		BackgroundTransparency = active and 0.08 or 0.16, BorderSizePixel = 0, AutoButtonColor = false,
		Selectable = true, Text = "", ZIndex = 3, [React.Event.Activated] = props.Select,
		[React.Event.MouseEnter] = function() setFocused(true) end,
		[React.Event.MouseLeave] = function() setFocused(false) end,
		[React.Event.SelectionGained] = function() setFocused(true) end,
		[React.Event.SelectionLost] = function() setFocused(false) end,
	}, {
		Corner = ReactUI.Corner(6),
		Stroke = ReactUI.Stroke(props.Selected and Theme.StrokeBright or Theme.Stroke, props.Selected and 1.5 or 1, props.Selected and 0.14 or 0.35),
		Badge = React.createElement("ImageLabel", { Position = UDim2.fromScale(0.28, 0.08), Size = UDim2.fromScale(0.44, 0.52), BackgroundTransparency = 1, Image = props.Badge, ScaleType = Enum.ScaleType.Fit, ZIndex = 4 }),
		Name = React.createElement("TextLabel", { Position = UDim2.fromScale(0.12, 0.66), Size = UDim2.fromScale(0.76, 0.13), BackgroundTransparency = 1, Font = Theme.Fonts.Heading, Text = props.Name, TextColor3 = Theme.Text, TextSize = MenuKit.Size(props.Mobile, 23), ZIndex = 4 }),
		Direction = React.createElement("TextLabel", { Position = UDim2.fromScale(0.12, 0.82), Size = UDim2.fromScale(0.76, 0.07), BackgroundTransparency = 1, Font = Theme.Fonts.Caption, Text = props.Detail, TextColor3 = Theme.MutedText, TextSize = MenuKit.Size(props.Mobile, 12), ZIndex = 4 }),
	})
end

return function(props)
	local selected, setSelected = React.useState("Home")
	-- Phone landscape, decided by the viewport rather than by whether the device
	-- happens to have a touchscreen; see MenuKit.Compact.
	local mobile = MenuKit.Compact()
	return React.createElement("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Theme.Background, BorderSizePixel = 0 }, {
		Background = React.createElement("ImageLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = Assets.MenuStadium, ImageTransparency = 0.28, ScaleType = Enum.ScaleType.Crop }),
		Shade = React.createElement("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Theme.Background, BackgroundTransparency = 0.45, BorderSizePixel = 0 }),
		Title = React.createElement("TextLabel", { Position = UDim2.fromScale(0.22, if mobile then 0.08 else 0.14), Size = UDim2.fromScale(0.56, if mobile then 0.12 else 0.09), BackgroundTransparency = 1, Font = Theme.Fonts.Display, Text = "SELECT TEAM", TextColor3 = Theme.Text, TextScaled = true, ZIndex = 2 }),
		Subtitle = React.createElement("TextLabel", { Position = UDim2.fromScale(0.2, if mobile then 0.2 else 0.235), Size = UDim2.fromScale(0.6, if mobile then 0.055 else 0.04), BackgroundTransparency = 1, Font = Theme.Fonts.Body, Text = if props.ModeId == "Quick3v3" then "Choose your side for the 3v3 match" else "Choose your side before entering Free Practice", TextColor3 = Theme.MutedText, TextScaled = true, ZIndex = 2 }),
		Cards = React.createElement("Frame", { Position = UDim2.fromScale(if mobile then 0.12 else 0.18, if mobile then 0.27 else 0.31), Size = UDim2.fromScale(if mobile then 0.76 else 0.64, if mobile then 0.48 else 0.45), BackgroundTransparency = 1, ZIndex = 2 }, {
			Layout = React.createElement("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0.08, 0), SortOrder = Enum.SortOrder.LayoutOrder }),
			Home = React.createElement(TeamCard, { Order = 1, Name = "HOME", Detail = "ATTACKS AWAY GOAL", Badge = Assets.HUD.HomeBadge, Mobile = mobile, Selected = selected == "Home", Select = function() setSelected("Home") end }),
			Away = React.createElement(TeamCard, { Order = 2, Name = "AWAY", Detail = "ATTACKS HOME GOAL", Badge = Assets.HUD.AwayBadge, Mobile = mobile, Selected = selected == "Away", Select = function() setSelected("Away") end }),
		}),
		Continue = React.createElement("TextButton", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, if mobile then 0.84 else 0.855), Size = UDim2.fromScale(if mobile then 0.3 else 0.22, if mobile then 0.09 else 0.07), BackgroundColor3 = Theme.AccentDark, BorderSizePixel = 0, Font = Theme.Fonts.Navigation, Text = "CONTINUE", TextColor3 = Theme.Text, TextSize = MenuKit.Size(mobile, 17), ZIndex = 2, [React.Event.Activated] = function() props.Continue(selected) end }, {
			Corner = ReactUI.Corner(5), Stroke = ReactUI.Stroke(Theme.AccentCyan, 1.25, 0.18),
		}),
		Footer = React.createElement(MenuFooter.Root, {
			Mobile = mobile,
			Content = React.createElement("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, {
				Back = React.createElement(BackButton.Root, { Mobile = mobile, ZIndex = 7, OnActivated = props.GoBack }),
			}),
		}),
	})
end
