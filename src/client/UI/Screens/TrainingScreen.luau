local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local React = require(ReplicatedStorage.Shared.ReactPackages).React
local Assets = require(ReplicatedStorage.Shared.Config.UIAssetConfig)
local Theme = require(script.Parent.Parent.Theme)
local ReactUI = require(script.Parent.Parent.Components.ReactUI)

local function ModeCard(props)
	return React.createElement("TextButton", {
		LayoutOrder = props.Order,
		Size = UDim2.new(0.235, 0, 1, 0),
		BackgroundColor3 = Theme.Panel,
		BackgroundTransparency = props.Enabled and 0.1 or 0.3,
		BorderSizePixel = 0,
		AutoButtonColor = props.Enabled,
		Selectable = true,
		Text = "",
		ZIndex = 2,
		[React.Event.Activated] = props.Enabled and props.OnActivated or props.ComingSoon,
	}, {
		Corner = ReactUI.Corner(6),
		Stroke = ReactUI.Stroke(props.Enabled and Theme.StrokeBright or Theme.Stroke, props.Enabled and 1.5 or 1, props.Enabled and 0.16 or 0.45),
		Icon = React.createElement("ImageLabel", {
			Position = UDim2.fromScale(0.18, 0.09), Size = UDim2.fromScale(0.64, 0.38),
			BackgroundTransparency = 1, Image = props.Icon, ImageTransparency = props.Enabled and 0 or 0.45,
			ScaleType = Enum.ScaleType.Fit,
		}),
		Title = React.createElement("TextLabel", {
			Position = UDim2.fromScale(0.08, 0.53), Size = UDim2.fromScale(0.84, 0.11),
			BackgroundTransparency = 1, Font = Theme.Fonts.Navigation, Text = props.Title,
			TextColor3 = props.Enabled and Theme.Text or Theme.FaintText, TextSize = if props.Mobile then 12 else 18,
		}),
		Detail = React.createElement("TextLabel", {
			Position = UDim2.fromScale(0.1, 0.67), Size = UDim2.fromScale(0.8, 0.16),
			BackgroundTransparency = 1, Font = Theme.Fonts.Caption, Text = props.Detail,
			TextColor3 = Theme.MutedText, TextWrapped = true, TextSize = if props.Mobile then 8 else 12,
		}),
		Status = React.createElement("TextLabel", {
			Position = UDim2.fromScale(0.2, 0.87), Size = UDim2.fromScale(0.6, 0.07),
			BackgroundTransparency = 1, Font = Theme.Fonts.Navigation,
			Text = props.Enabled and "AVAILABLE" or "COMING SOON",
			TextColor3 = props.Enabled and Theme.AccentCyan or Theme.FaintText, TextSize = if props.Mobile then 8 else 11,
		}),
	})
end

local function TrainingScreen(props)
	local selected, setSelected = React.useState(false)
	local mobile = UserInputService.TouchEnabled
	local topLeftInset = GuiService:GetGuiInset()
	local footerInset = if mobile then topLeftInset.Y else 0
	local cards = {
		{ "TRAINING", "Free Practice", Assets.Navigation.Training, true },
		{ "QUICK 3V3", "Fast competitive football", Assets.Navigation.Play, false },
		{ "5V5 TOURNAMENT", "Structured team competition", Assets.Navigation.Clubs, false },
		{ "11V11 CLUBS", "Full-pitch club football", Assets.Navigation.Clubs, false },
	}
	local children = {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0.02, 0),
			HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}
	for index, card in cards do
		children["Mode" .. index] = React.createElement(ModeCard, {
			Order = index, Title = card[1], Detail = card[2], Icon = card[3], Enabled = card[4],
			Mobile = mobile,
			OnActivated = function() setSelected(true) end, ComingSoon = props.ComingSoon,
		})
	end
	return React.createElement("Frame", {
		Name = "ModeSelect", Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Background, BorderSizePixel = 0,
	}, {
		Background = React.createElement("ImageLabel", {
			Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
			Image = Assets.MenuStadium, ImageTransparency = 0.32, ScaleType = Enum.ScaleType.Crop,
		}),
		Shade = React.createElement("Frame", {
			Size = UDim2.fromScale(1, 1), BackgroundColor3 = Theme.Background,
			BackgroundTransparency = 0.58, BorderSizePixel = 0, ZIndex = 1,
		}),
		Logo = React.createElement("ImageLabel", {
			Position = UDim2.fromScale(0.035, if mobile then 0.01 else 0.025), Size = UDim2.fromScale(if mobile then 0.25 else 0.29, if mobile then 0.12 else 0.145),
			BackgroundTransparency = 1, Image = Assets.Logo, ScaleType = Enum.ScaleType.Fit, ZIndex = 2,
		}),
		Title = React.createElement("TextLabel", {
			Position = UDim2.fromScale(0.08, if mobile then 0.16 else 0.235), Size = UDim2.fromScale(0.84, if mobile then 0.1 else 0.085),
			BackgroundTransparency = 1, Font = Theme.Fonts.Display, Text = "CHOOSE YOUR MODE",
			TextColor3 = Theme.Text, TextScaled = true, ZIndex = 2,
		}),
		Subtitle = React.createElement("TextLabel", {
			Position = UDim2.fromScale(0.18, if mobile then 0.26 else 0.325), Size = UDim2.fromScale(0.64, if mobile then 0.055 else 0.04),
			BackgroundTransparency = 1, Font = Theme.Fonts.Body,
			Text = "Select how you want to experience Beyond 90", TextColor3 = Theme.MutedText, TextScaled = true, ZIndex = 2,
		}),
		Cards = React.createElement("Frame", {
			Position = UDim2.fromScale(0.035, if mobile then 0.34 else 0.41), Size = UDim2.fromScale(0.93, if mobile then 0.36 else 0.35),
			BackgroundTransparency = 1, ZIndex = 2,
		}, children),
		Details = selected and React.createElement("Frame", {
			AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, if mobile then 0.86 else 0.865),
			Size = UDim2.fromScale(if mobile then 0.72 else 0.58, if mobile then 0.14 else 0.13), BackgroundColor3 = Theme.Panel,
			BackgroundTransparency = 0.08, BorderSizePixel = 0, ZIndex = 2,
		}, {
			Corner = ReactUI.Corner(8), Stroke = ReactUI.Stroke(Theme.AccentViolet, 1.5, 0.15),
			Title = React.createElement("TextLabel", {
				Position = UDim2.fromScale(0.04, 0.16), Size = UDim2.fromScale(0.55, 0.28),
				BackgroundTransparency = 1, Font = Theme.Fonts.Navigation, Text = "TRAINING - FREE PRACTICE",
				TextColor3 = Theme.Text, TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left,
			}),
			Detail = React.createElement("TextLabel", {
				Position = UDim2.fromScale(0.04, 0.52), Size = UDim2.fromScale(0.55, 0.2),
				BackgroundTransparency = 1, Font = Theme.Fonts.Caption,
				Text = "Open sandbox for movement, passing and shooting.", TextColor3 = Theme.MutedText,
				TextScaled = true, TextXAlignment = Enum.TextXAlignment.Left,
			}),
			Start = React.createElement("TextButton", {
				AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.fromScale(0.95, 0.5),
				Size = UDim2.fromScale(0.28, 0.54), BackgroundColor3 = Theme.Accent,
				BorderSizePixel = 0, Font = Theme.Fonts.Navigation, Text = "START TRAINING",
				TextColor3 = Theme.Text, TextSize = if mobile then 12 else 16, [React.Event.Activated] = props.OpenTeamSelection,
			}, {
				Corner = ReactUI.Corner(5), Stroke = ReactUI.Stroke(Theme.AccentCyan, 1.25, 0.18),
			}),
		}) or nil,
		FooterFade = React.createElement("Frame", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new(0, 0, if mobile then 1 else 0.87, footerInset),
			Size = UDim2.new(1, 0, if mobile then 0.3 else 0.22, footerInset),
			BackgroundColor3 = Color3.fromRGB(1, 5, 17), BorderSizePixel = 0, ZIndex = 1,
		}, {
			Gradient = React.createElement("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.42, 0.76), NumberSequenceKeypoint.new(0.72, 0.3), NumberSequenceKeypoint.new(1, 0.04) }) }),
		}),
		Footer = React.createElement("Frame", {
			AnchorPoint = if mobile then Vector2.new(0, 1) else Vector2.zero,
			Position = UDim2.new(0, 0, if mobile then 1 else 0.87, footerInset),
			Size = UDim2.new(1, 0, if mobile then 0.14 else 0.13, footerInset),
			BackgroundColor3 = Color3.fromRGB(1, 5, 17), BackgroundTransparency = 0.02,
			BorderSizePixel = 0, ZIndex = 6,
		}, {
			Content = React.createElement("Frame", { Size = UDim2.new(1, 0, 1, -footerInset), BackgroundTransparency = 1 }, {
				Back = React.createElement("TextButton", {
					Position = UDim2.fromScale(0.035, if mobile then 0.13 else 0.18), Size = UDim2.fromScale(if mobile then 0.2 else 0.1, if mobile then 0.7 else 0.58),
					BackgroundTransparency = 1, Font = Theme.Fonts.Navigation, Text = "<  BACK",
					TextColor3 = Theme.MutedText, TextSize = if mobile then 12 else 13, ZIndex = 7,
					[React.Event.Activated] = props.GoHome,
				}),
			}),
		}),
	})
end

return TrainingScreen
