local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local React = require(ReplicatedStorage.Shared.ReactPackages).React
local Assets = require(ReplicatedStorage.Shared.Config.UIAssetConfig)
local Theme = require(script.Parent.Parent.Theme)
local ReactUI = require(script.Parent.Parent.Components.ReactUI)

local function LoadingScreen(props)
	local progress = math.clamp(props.Progress or 0, 0, 1)
	local returning = props.Variant == "Menu"
	local fillRef = React.useRef(nil)
	React.useEffect(function()
		local fill = fillRef.current
		if not fill then return nil end
		local target = math.max(progress, 0.02)
		local current = fill.Size.X.Scale
		local duration = 0.55 + math.abs(target - current) * 0.9
		local animation = TweenService:Create(
			fill,
			TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			{ Size = UDim2.fromScale(target, 1) }
		)
		animation:Play()
		return function() animation:Cancel() end
	end, { progress })
	return React.createElement("Frame", {
		Name = "ModeLoading",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Background,
		BorderSizePixel = 0,
	}, {
		Background = React.createElement("ImageLabel", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			Image = Assets.MenuStadium,
			ImageTransparency = 0.28,
			ScaleType = Enum.ScaleType.Crop,
		}, {
			Shade = React.createElement("UIGradient", {
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.fromRGB(3, 5, 18)),
					ColorSequenceKeypoint.new(0.55, Color3.fromRGB(9, 19, 52)),
					ColorSequenceKeypoint.new(1, Color3.fromRGB(4, 7, 20)),
				}),
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.08),
					NumberSequenceKeypoint.new(0.5, 0.28),
					NumberSequenceKeypoint.new(1, 0.05),
				}),
				Rotation = 18,
			}),
		}),
		Vignette = React.createElement("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Theme.Background,
			BackgroundTransparency = 0.42,
			BorderSizePixel = 0,
		}),
		Logo = React.createElement("ImageLabel", {
			Position = UDim2.fromScale(0.06, 0.075),
			Size = UDim2.fromScale(0.31, 0.15),
			BackgroundTransparency = 1,
			Image = Assets.Logo,
			ScaleType = Enum.ScaleType.Crop,
		}),
		Center = React.createElement("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0.07, 0.62),
			Size = UDim2.fromScale(0.48, 0.31),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, {
			Accent = React.createElement("Frame", {
				Position = UDim2.fromScale(0, 0.04), Size = UDim2.fromScale(0.008, 0.54),
				BackgroundColor3 = Theme.AccentCyan, BorderSizePixel = 0,
			}, { Gradient = ReactUI.Gradient(Theme.AccentCyan, Theme.AccentViolet, 90) }),
			Eyebrow = React.createElement("TextLabel", {
				Position = UDim2.fromScale(0.045, 0.05),
				Size = UDim2.fromScale(0.9, 0.1),
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Navigation,
				Text = returning and "BEYOND 90" or "SELECTED MODE",
				TextColor3 = Theme.AccentCyan,
				TextSize = Theme.TextSizes.Navigation,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			Title = React.createElement("TextLabel", {
				Position = UDim2.fromScale(0.045, 0.18),
				Size = UDim2.fromScale(0.95, 0.22),
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Display,
				Text = returning and "RETURNING TO MENU" or (props.Mode or "TRAINING"),
				TextColor3 = Theme.Text,
				TextSize = 42,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			Detail = React.createElement("TextLabel", {
				Position = UDim2.fromScale(0.045, 0.43),
				Size = UDim2.fromScale(0.9, 0.1),
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Body,
				Text = returning and "Closing the Training session..." or (props.Detail or "FREE PRACTICE"),
				TextColor3 = Theme.MutedText,
				TextSize = Theme.TextSizes.Subheading,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			Track = React.createElement("Frame", {
				Position = UDim2.fromScale(0.045, 0.68),
				Size = UDim2.fromScale(0.76, 0.02),
				BackgroundColor3 = Color3.fromRGB(44, 52, 82),
				BorderSizePixel = 0,
			}, {
				Corner = ReactUI.Corner(8),
				Fill = React.createElement("Frame", {
					ref = fillRef,
					Size = UDim2.fromScale(0.02, 1),
					BackgroundColor3 = Theme.Accent,
					BorderSizePixel = 0,
				}, {
					Corner = ReactUI.Corner(8),
					Gradient = ReactUI.Gradient(Theme.AccentViolet, Theme.AccentCyan),
				}),
			}),
			Status = React.createElement("TextLabel", {
				Position = UDim2.fromScale(0.045, 0.75),
				Size = UDim2.fromScale(0.76, 0.09),
				BackgroundTransparency = 1,
				Font = Theme.Fonts.Caption,
				Text = props.Status or "PREPARING TRAINING",
				TextColor3 = Theme.MutedText,
				TextSize = Theme.TextSizes.Caption,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
		}),
	})
end

return LoadingScreen
