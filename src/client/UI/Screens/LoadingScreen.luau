local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Assets = require(ReplicatedStorage.Shared.Config.UIAssetConfig)
local Theme = require(script.Parent.Parent.Theme)
local UIUtil = require(script.Parent.Parent.Components.UIUtil)

local LoadingScreen = {}

function LoadingScreen.Create(parent: Instance)
	local frame = Instance.new("Frame")
	frame.Name = "ModeLoading"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Theme.Background
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.ZIndex = 100
	frame.Parent = parent

	local stadium = UIUtil.CreateImage(frame, "Stadium", Assets.MenuStadium, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0))
	stadium.ScaleType = Enum.ScaleType.Crop
	stadium.ImageTransparency = 0.32
	stadium.ZIndex = 100
	local shade = Instance.new("Frame")
	shade.Size = UDim2.fromScale(1, 1)
	shade.BackgroundColor3 = Theme.Background
	shade.BackgroundTransparency = 0.25
	shade.BorderSizePixel = 0
	shade.ZIndex = 101
	shade.Parent = frame
	UIUtil.AddGradient(shade, Color3.fromRGB(2, 5, 18), Color3.fromRGB(20, 9, 48), 15)

	local logo = UIUtil.CreateImage(frame, "Logo", Assets.Logo, UDim2.fromOffset(230, 150), UDim2.new(0.5, -115, 0.14, 0))
	logo.ZIndex = 102
	local title = UIUtil.CreateText(frame, "Title", "TRAINING", UDim2.fromOffset(700, 54), UDim2.new(0.5, -350, 0.48, 0), Theme.Fonts.Display, 38)
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.ZIndex = 102
	local subtitle = UIUtil.CreateText(frame, "Subtitle", "FREE PRACTICE", UDim2.fromOffset(700, 32), UDim2.new(0.5, -350, 0.545, 0), Theme.Fonts.Navigation, 15)
	subtitle.TextColor3 = Theme.AccentCyan
	subtitle.TextXAlignment = Enum.TextXAlignment.Center
	subtitle.ZIndex = 102
	local status = UIUtil.CreateText(frame, "Status", "PREPARING TRAINING", UDim2.fromOffset(500, 28), UDim2.new(0.5, -250, 0.65, 0), Theme.Fonts.Caption, 12)
	status.TextColor3 = Theme.MutedText
	status.TextXAlignment = Enum.TextXAlignment.Center
	status.ZIndex = 102
	local track = Instance.new("Frame")
	track.Size = UDim2.fromOffset(430, 4)
	track.Position = UDim2.new(0.5, -215, 0.71, 0)
	track.BackgroundColor3 = Color3.fromRGB(46, 57, 88)
	track.BorderSizePixel = 0
	track.ZIndex = 102
	track.Parent = frame
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0.08, 1)
	fill.BackgroundColor3 = Theme.Accent
	fill.BorderSizePixel = 0
	fill.ZIndex = 103
	fill.Parent = track
	UIUtil.AddGradient(fill, Theme.AccentCyan, Theme.AccentViolet)
	local tip = UIUtil.CreateText(frame, "Tip", "Pass early. Move before the ball arrives.", UDim2.fromOffset(600, 28), UDim2.new(0.5, -300, 0.79, 0), Theme.Fonts.Body, 13)
	tip.TextColor3 = Theme.MutedText
	tip.TextXAlignment = Enum.TextXAlignment.Center
	tip.ZIndex = 102

	return {
		Frame = frame,
		SetMode = function(mode: string, detail: string)
			title.Text = string.upper(mode)
			subtitle.Text = string.upper(detail)
		end,
		SetStatus = function(text: string, progress: number)
			status.Text = string.upper(text)
			fill.Size = UDim2.fromScale(math.clamp(progress, 0.08, 1), 1)
		end,
	}
end

return LoadingScreen
