--[[
	One Back-button treatment for every menu screen.

	Each screen previously drew its own bare transparent TextButton reading
	"<  BACK", which gave no affordance that it could be pressed and looked
	unfinished next to the rest of the menu. This is a compact pill in the
	existing navy/cyan/violet language: a dark glass fill, a cyan-violet chevron
	block, and a hover state so it reads as interactive.

	Screens pass only position, size and the callback, so the treatment stays
	identical everywhere it appears.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Shared.ReactPackages).React
local Theme = require(script.Parent.Parent.Theme)
local ReactUI = require(script.Parent.ReactUI)

local BackButton = {}

function BackButton.Root(props)
	local mobile = props.Mobile == true
	local hovered, setHovered = React.useState(false)

	local zIndex = props.ZIndex or 7
	local height = props.Size or UDim2.fromScale(if mobile then 0.2 else 0.1, if mobile then 0.7 else 0.58)

	return React.createElement("TextButton", {
		Position = props.Position or UDim2.fromScale(0.035, if mobile then 0.13 else 0.18),
		Size = height,
		AnchorPoint = props.AnchorPoint,
		BackgroundColor3 = if hovered then Theme.PanelHover else Theme.Panel,
		BackgroundTransparency = if hovered then 0.08 else 0.22,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		ZIndex = zIndex,
		[React.Event.Activated] = props.OnActivated,
		[React.Event.MouseEnter] = function() setHovered(true) end,
		[React.Event.MouseLeave] = function() setHovered(false) end,
	}, {
		Corner = ReactUI.Corner(6),
		Stroke = ReactUI.Stroke(
			if hovered then Theme.AccentCyan else Theme.StrokeBright,
			1.25,
			if hovered then 0.15 else 0.55
		),

		-- Accent edge, matching the vertical accent bar used on menu panels.
		Accent = React.createElement("Frame", {
			Position = UDim2.fromScale(0, 0.22),
			Size = UDim2.new(0, 2, 0.56, 0),
			BackgroundColor3 = Theme.AccentCyan,
			BorderSizePixel = 0,
			ZIndex = zIndex + 1,
		}, {
			Gradient = ReactUI.Gradient(Theme.AccentCyan, Theme.AccentViolet, 90),
		}),

		Chevron = React.createElement("TextLabel", {
			Position = UDim2.fromScale(0.1, 0.5),
			AnchorPoint = Vector2.new(0, 0.5),
			Size = UDim2.fromScale(0.22, 0.62),
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Display,
			Text = "\u{2039}",
			TextColor3 = if hovered then Theme.AccentCyan else Theme.Text,
			TextSize = if mobile then 18 else 20,
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = zIndex + 1,
		}),

		Label = React.createElement("TextLabel", {
			Position = UDim2.fromScale(0.34, 0.5),
			AnchorPoint = Vector2.new(0, 0.5),
			Size = UDim2.fromScale(0.6, 0.6),
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Navigation,
			Text = props.Text or "BACK",
			TextColor3 = Theme.Text,
			TextSize = if mobile then 12 else 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = zIndex + 1,
		}),
	})
end

return BackButton
