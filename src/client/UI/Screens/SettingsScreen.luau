local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local React = require(ReplicatedStorage.Shared.ReactPackages).React
local AudioConfig = require(ReplicatedStorage.Shared.Config.AudioConfig)
local Assets = require(ReplicatedStorage.Shared.Config.UIAssetConfig)
local Theme = require(script.Parent.Parent.Theme)
local ReactUI = require(script.Parent.Parent.Components.ReactUI)

return function(props)
	local mobile = UserInputService.TouchEnabled
	local topLeftInset = GuiService:GetGuiInset()
	local footerInset = if mobile then topLeftInset.Y else 0
	local rows = { Layout = React.createElement("UIListLayout", { Padding = UDim.new(0.035, 0), SortOrder = Enum.SortOrder.LayoutOrder }) }
	for index, track in AudioConfig.MenuTracks do
		local selected = props.SelectedTrack == index
		rows["Track" .. index] = React.createElement("TextButton", {
			LayoutOrder = index, Size = UDim2.fromScale(1, 0.22), BackgroundColor3 = selected and Theme.PanelSelected or Theme.Panel,
			BackgroundTransparency = selected and 0.03 or 0.18, BorderSizePixel = 0, AutoButtonColor = false,
			Font = Theme.Fonts.Navigation, Text = track.Name, TextColor3 = selected and Theme.AccentCyan or Theme.Text,
			TextSize = Theme.TextSizes.Subheading, ZIndex = 3, [React.Event.Activated] = function() props.SetTrack(index) end,
		}, { Corner = ReactUI.Corner(5), Stroke = ReactUI.Stroke(selected and Theme.StrokeBright or Theme.Stroke, selected and 1.5 or 1, selected and 0.15 or 0.35) })
	end
	return React.createElement("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Theme.Background, BorderSizePixel = 0 }, {
		Background = React.createElement("ImageLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = Assets.MenuStadium, ImageTransparency = 0.18, ScaleType = Enum.ScaleType.Crop }),
		Shade = React.createElement("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Theme.Background, BackgroundTransparency = 0.3, BorderSizePixel = 0, ZIndex = 1 }),
		Title = React.createElement("TextLabel", { Position = UDim2.fromScale(0.1, if mobile then 0.1 else 0.16), Size = UDim2.fromScale(0.8, if mobile then 0.11 else 0.09), BackgroundTransparency = 1, Font = Theme.Fonts.Display, Text = "SETTINGS", TextColor3 = Theme.Text, TextSize = if mobile then 28 else Theme.TextSizes.Display, ZIndex = 2 }),
		Caption = React.createElement("TextLabel", { Position = UDim2.fromScale(if mobile then 0.24 else 0.32, if mobile then 0.24 else 0.29), Size = UDim2.fromScale(if mobile then 0.52 else 0.36, 0.05), BackgroundTransparency = 1, Font = Theme.Fonts.Subheading, Text = "MENU MUSIC", TextColor3 = Theme.AccentCyan, TextSize = if mobile then 14 else Theme.TextSizes.Subheading, ZIndex = 2 }),
		Tracks = React.createElement("Frame", { Position = UDim2.fromScale(if mobile then 0.24 else 0.32, if mobile then 0.32 else 0.37), Size = UDim2.fromScale(if mobile then 0.52 else 0.36, if mobile then 0.43 else 0.38), BackgroundTransparency = 1, ZIndex = 2 }, rows),
		FooterFade = React.createElement("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, if mobile then 1 else 0.87, footerInset), Size = UDim2.new(1, 0, if mobile then 0.3 else 0.22, footerInset), BackgroundColor3 = Color3.fromRGB(1, 5, 17), BorderSizePixel = 0, ZIndex = 1 }, {
			Gradient = React.createElement("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.42, 0.76), NumberSequenceKeypoint.new(0.72, 0.3), NumberSequenceKeypoint.new(1, 0.04) }) }),
		}),
		Footer = React.createElement("Frame", { AnchorPoint = if mobile then Vector2.new(0, 1) else Vector2.zero, Position = UDim2.new(0, 0, if mobile then 1 else 0.87, footerInset), Size = UDim2.new(1, 0, if mobile then 0.14 else 0.13, footerInset), BackgroundColor3 = Color3.fromRGB(1, 5, 17), BackgroundTransparency = 0.02, BorderSizePixel = 0, ZIndex = 6 }, {
			Content = React.createElement("Frame", { Size = UDim2.new(1, 0, 1, -footerInset), BackgroundTransparency = 1 }, {
				Back = React.createElement("TextButton", { Position = UDim2.fromScale(0.035, if mobile then 0.13 else 0.18), Size = UDim2.fromScale(if mobile then 0.2 else 0.1, if mobile then 0.7 else 0.58), BackgroundTransparency = 1, Font = Theme.Fonts.Navigation, Text = "<  BACK", TextColor3 = Theme.MutedText, TextSize = if mobile then 12 else 13, ZIndex = 7, [React.Event.Activated] = props.GoHome }),
			}),
		}),
	})
end
