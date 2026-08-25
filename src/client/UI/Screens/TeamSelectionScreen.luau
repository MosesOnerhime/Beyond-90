local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local React = require(ReplicatedStorage.Shared.ReactPackages).React
local Assets = require(ReplicatedStorage.Shared.Config.UIAssetConfig)
local Theme = require(script.Parent.Parent.Theme)
local ReactUI = require(script.Parent.Parent.Components.ReactUI)

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
		Name = React.createElement("TextLabel", { Position = UDim2.fromScale(0.12, 0.66), Size = UDim2.fromScale(0.76, 0.13), BackgroundTransparency = 1, Font = Theme.Fonts.Heading, Text = props.Name, TextColor3 = Theme.Text, TextSize = if props.Mobile then 16 else 23, ZIndex = 4 }),
		Direction = React.createElement("TextLabel", { Position = UDim2.fromScale(0.12, 0.82), Size = UDim2.fromScale(0.76, 0.07), BackgroundTransparency = 1, Font = Theme.Fonts.Caption, Text = props.Detail, TextColor3 = Theme.MutedText, TextSize = if props.Mobile then 9 else 12, ZIndex = 4 }),
	})
end

return function(props)
	local selected, setSelected = React.useState("Home")
	local mobile = UserInputService.TouchEnabled
	local topLeftInset = GuiService:GetGuiInset()
	local footerInset = if mobile then topLeftInset.Y else 0
	return React.createElement("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Theme.Background, BorderSizePixel = 0 }, {
		Background = React.createElement("ImageLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = Assets.MenuStadium, ImageTransparency = 0.28, ScaleType = Enum.ScaleType.Crop }),
		Shade = React.createElement("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Theme.Background, BackgroundTransparency = 0.45, BorderSizePixel = 0 }),
		Title = React.createElement("TextLabel", { Position = UDim2.fromScale(0.22, if mobile then 0.08 else 0.14), Size = UDim2.fromScale(0.56, if mobile then 0.12 else 0.09), BackgroundTransparency = 1, Font = Theme.Fonts.Display, Text = "SELECT TEAM", TextColor3 = Theme.Text, TextScaled = true, ZIndex = 2 }),
		Subtitle = React.createElement("TextLabel", { Position = UDim2.fromScale(0.2, if mobile then 0.2 else 0.235), Size = UDim2.fromScale(0.6, if mobile then 0.055 else 0.04), BackgroundTransparency = 1, Font = Theme.Fonts.Body, Text = "Choose your side before entering Free Practice", TextColor3 = Theme.MutedText, TextScaled = true, ZIndex = 2 }),
		Cards = React.createElement("Frame", { Position = UDim2.fromScale(if mobile then 0.12 else 0.18, if mobile then 0.27 else 0.31), Size = UDim2.fromScale(if mobile then 0.76 else 0.64, if mobile then 0.48 else 0.45), BackgroundTransparency = 1, ZIndex = 2 }, {
			Layout = React.createElement("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0.08, 0), SortOrder = Enum.SortOrder.LayoutOrder }),
			Home = React.createElement(TeamCard, { Order = 1, Name = "HOME", Detail = "ATTACKS AWAY GOAL", Badge = Assets.HUD.HomeBadge, Mobile = mobile, Selected = selected == "Home", Select = function() setSelected("Home") end }),
			Away = React.createElement(TeamCard, { Order = 2, Name = "AWAY", Detail = "ATTACKS HOME GOAL", Badge = Assets.HUD.AwayBadge, Mobile = mobile, Selected = selected == "Away", Select = function() setSelected("Away") end }),
		}),
		Continue = React.createElement("TextButton", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, if mobile then 0.84 else 0.855), Size = UDim2.fromScale(if mobile then 0.3 else 0.22, if mobile then 0.09 else 0.07), BackgroundColor3 = Theme.AccentDark, BorderSizePixel = 0, Font = Theme.Fonts.Navigation, Text = "CONTINUE", TextColor3 = Theme.Text, TextSize = if mobile then 14 else 17, ZIndex = 2, [React.Event.Activated] = function() props.Continue(selected) end }, {
			Corner = ReactUI.Corner(5), Stroke = ReactUI.Stroke(Theme.AccentCyan, 1.25, 0.18),
		}),
		FooterFade = React.createElement("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, if mobile then 1 else 0.87, footerInset), Size = UDim2.new(1, 0, if mobile then 0.3 else 0.22, footerInset), BackgroundColor3 = Color3.fromRGB(1, 5, 17), BorderSizePixel = 0, ZIndex = 1 }, {
			Gradient = React.createElement("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.42, 0.76), NumberSequenceKeypoint.new(0.72, 0.3), NumberSequenceKeypoint.new(1, 0.04) }) }),
		}),
		Footer = React.createElement("Frame", { AnchorPoint = if mobile then Vector2.new(0, 1) else Vector2.zero, Position = UDim2.new(0, 0, if mobile then 1 else 0.87, footerInset), Size = UDim2.new(1, 0, if mobile then 0.14 else 0.13, footerInset), BackgroundColor3 = Color3.fromRGB(1, 5, 17), BackgroundTransparency = 0.02, BorderSizePixel = 0, ZIndex = 6 }, {
			Content = React.createElement("Frame", { Size = UDim2.new(1, 0, 1, -footerInset), BackgroundTransparency = 1 }, {
				Back = React.createElement("TextButton", { Position = UDim2.fromScale(0.035, if mobile then 0.13 else 0.18), Size = UDim2.fromScale(if mobile then 0.2 else 0.1, if mobile then 0.7 else 0.58), BackgroundTransparency = 1, Font = Theme.Fonts.Navigation, Text = "<  BACK", TextColor3 = Theme.MutedText, TextSize = if mobile then 12 else 13, ZIndex = 7, [React.Event.Activated] = props.GoBack }),
			}),
		}),
	})
end
