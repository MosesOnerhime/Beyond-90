local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Assets = require(ReplicatedStorage.Shared.Config.UIAssetConfig)
local Theme = require(script.Parent.Parent.Theme)
local UIUtil = require(script.Parent.Parent.Components.UIUtil)

local TrainingScreen = {}

local function modeCard(parent, title, subtitle, icon, enabled)
	local button = UIUtil.CreateButton(parent, title:gsub(" ", ""), title, subtitle)
	button.AutoButtonColor = false
	button.BackgroundTransparency = 0.08
	button.Selectable = enabled
	local image = UIUtil.CreateImage(button, "ModeIcon", icon, UDim2.fromOffset(72, 72), UDim2.fromOffset(20, 18))
	image.ImageColor3 = if enabled then Color3.new(1, 1, 1) else Theme.FaintText
	button.Title.Position = UDim2.fromOffset(108, 22)
	button.Title.Size = UDim2.new(1, -124, 0, 28)
	button.Subtitle.Position = UDim2.fromOffset(108, 53)
	button.Subtitle.Size = UDim2.new(1, -124, 0, 34)
	if not enabled then
		button.Title.TextColor3 = Theme.FaintText
		button.Subtitle.Text = "COMING SOON"
	end
	return button
end

function TrainingScreen.Create(parent: Instance, callbacks)
	local frame = Instance.new("Frame")
	frame.Name = "ModeSelect"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Theme.Background
	frame.Visible = false
	frame.Parent = parent
	local background = UIUtil.CreateImage(frame, "Stadium", Assets.MenuStadium, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0))
	background.ScaleType = Enum.ScaleType.Crop
	background.ImageTransparency = 0.55
	local shade = Instance.new("Frame")
	shade.Size = UDim2.fromScale(1, 1)
	shade.BackgroundColor3 = Theme.Background
	shade.BackgroundTransparency = 0.18
	shade.BorderSizePixel = 0
	shade.Parent = frame
	UIUtil.AddGradient(shade, Color3.fromRGB(2, 6, 20), Color3.fromRGB(17, 9, 43), 15)
	UIUtil.CreateImage(frame, "Logo", Assets.Logo, UDim2.fromOffset(180, 120), UDim2.fromOffset(38, 6))
	UIUtil.CreateText(frame, "Title", "CHOOSE YOUR MODE", UDim2.fromOffset(600, 55), UDim2.fromOffset(62, 112), Theme.Fonts.Display, 34)
	local subtitle = UIUtil.CreateText(frame, "Subtitle", "PLAY BEYOND 90 YOUR WAY", UDim2.fromOffset(500, 26), UDim2.fromOffset(65, 162), Theme.Fonts.Caption, 11)
	subtitle.TextColor3 = Theme.AccentCyan

	local list = Instance.new("Frame")
	list.Size = UDim2.fromOffset(540, 480)
	list.Position = UDim2.fromOffset(62, 206)
	list.BackgroundTransparency = 1
	list.Parent = frame
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 12)
	layout.Parent = list
	local free = modeCard(list, "TRAINING", "FREE PRACTICE", Assets.Navigation.Training, true)
	free.Size = UDim2.new(1, 0, 0, 108)
	free.LayoutOrder = 1
	local quick = modeCard(list, "QUICK 3V3", "FAST COMPETITIVE FOOTBALL", Assets.Navigation.Play, false)
	quick.Size = free.Size
	quick.LayoutOrder = 2
	local tournament = modeCard(list, "5V5 TOURNAMENT", "BUILD A WINNING RUN", Assets.Highlights.Trophy, false)
	tournament.Size = free.Size
	tournament.LayoutOrder = 3
	local clubs = modeCard(list, "11V11 CLUBS", "ONE PLAYER. ONE POSITION.", Assets.Navigation.Clubs, false)
	clubs.Size = free.Size
	clubs.LayoutOrder = 4

	local details = Instance.new("Frame")
	details.Name = "TrainingDetails"
	details.Size = UDim2.fromOffset(560, 430)
	details.Position = UDim2.new(1, -632, 0, 190)
	details.BackgroundColor3 = Theme.Panel
	details.BackgroundTransparency = 0.14
	details.BorderSizePixel = 0
	details.Parent = frame
	UIUtil.AddCorner(details)
	UIUtil.AddStroke(details, Theme.StrokeBright, 1.5)
	local detailsIcon = UIUtil.CreateImage(details, "Icon", Assets.Navigation.Training, UDim2.fromOffset(96, 96), UDim2.fromOffset(32, 32))
	UIUtil.CreateText(details, "Mode", "TRAINING", UDim2.fromOffset(350, 38), UDim2.fromOffset(148, 36), Theme.Fonts.Display, 27)
	local freeLabel = UIUtil.CreateText(details, "Detail", "FREE PRACTICE", UDim2.fromOffset(350, 25), UDim2.fromOffset(151, 76), Theme.Fonts.Navigation, 12)
	freeLabel.TextColor3 = Theme.AccentCyan
	local description = UIUtil.CreateText(details, "Description", "A free football sandbox for movement, dribbling, passing and shooting. Reset the ball at any time and switch between every available camera.", UDim2.new(1, -64, 0, 92), UDim2.fromOffset(32, 156), Theme.Fonts.Body, 15)
	description.TextWrapped = true
	description.TextYAlignment = Enum.TextYAlignment.Top
	description.TextColor3 = Theme.MutedText
	local availability = UIUtil.CreateText(details, "Availability", "AVAILABLE NOW", UDim2.fromOffset(180, 22), UDim2.fromOffset(32, 276), Theme.Fonts.Navigation, 11)
	availability.TextColor3 = Theme.Good
	local start = Instance.new("TextButton")
	start.Name = "StartTraining"
	start.Size = UDim2.new(1, -64, 0, 58)
	start.Position = UDim2.new(0, 32, 1, -88)
	start.BackgroundColor3 = Theme.Accent
	start.Text = "START TRAINING"
	start.TextColor3 = Theme.Background
	start.Font = Theme.Fonts.Navigation
	start.TextSize = 15
	start.Selectable = true
	start.Parent = details
	UIUtil.AddCorner(start)
	UIUtil.AddGradient(start, Theme.AccentCyan, Theme.AccentViolet)
	start.Activated:Connect(callbacks.EnterTraining)
	free.Activated:Connect(function() end)
	quick.Activated:Connect(callbacks.ShowComingSoon)
	tournament.Activated:Connect(callbacks.ShowComingSoon)
	clubs.Activated:Connect(callbacks.ShowComingSoon)

	local back = Instance.new("TextButton")
	back.Name = "Back"
	back.Size = UDim2.fromOffset(150, 40)
	back.Position = UDim2.new(0, 62, 1, -62)
	back.BackgroundColor3 = Theme.Panel
	back.Text = "BACK"
	back.TextColor3 = Theme.Text
	back.Font = Theme.Fonts.Navigation
	back.TextSize = 12
	back.Parent = frame
	UIUtil.AddCorner(back)
	UIUtil.AddStroke(back)
	back.Activated:Connect(callbacks.OpenHome)
	return { Frame = frame, DefaultSelection = free }
end

return TrainingScreen
