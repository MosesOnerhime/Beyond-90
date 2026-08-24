local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Assets = require(ReplicatedStorage.Shared.Config.UIAssetConfig)
local Theme = require(script.Parent.Parent.Theme)
local UIUtil = require(script.Parent.Parent.Components.UIUtil)

local HomeScreen = {}

local function panel(parent, name, size, position, transparency)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = size
	frame.Position = position
	frame.BackgroundColor3 = Theme.Panel
	frame.BackgroundTransparency = transparency or 0.22
	frame.BorderSizePixel = 0
	frame.Parent = parent
	UIUtil.AddCorner(frame)
	UIUtil.AddStroke(frame, Theme.Stroke, 1)
	return frame
end

local function smallStat(parent, icon, title, value, x)
	local box = panel(parent, title, UDim2.fromOffset(132, 68), UDim2.fromOffset(x, 0), 0.3)
	UIUtil.CreateImage(box, "Icon", icon, UDim2.fromOffset(30, 30), UDim2.fromOffset(10, 18))
	local valueLabel = UIUtil.CreateText(box, "Value", value, UDim2.fromOffset(80, 25), UDim2.fromOffset(47, 11), Theme.Fonts.Statistics, 19)
	valueLabel.TextXAlignment = Enum.TextXAlignment.Left
	local titleLabel = UIUtil.CreateText(box, "Label", title, UDim2.fromOffset(80, 20), UDim2.fromOffset(47, 37), Theme.Fonts.Caption, 10)
	titleLabel.TextColor3 = Theme.MutedText
end

local function navigationButton(parent, name, title, icon, subtitle)
	local button = Instance.new("ImageButton")
	button.Name = name
	button.AutoButtonColor = false
	button.BackgroundColor3 = Theme.Panel
	button.BackgroundTransparency = 0.12
	button.Image = ""
	button.Selectable = true
	button.Parent = parent
	UIUtil.AddCorner(button)
	local stroke = UIUtil.AddStroke(button, Theme.Stroke, 1)
	local iconLabel = UIUtil.CreateImage(button, "Icon", icon, UDim2.fromOffset(48, 48), UDim2.new(0.5, -24, 0, 12))
	local titleLabel = UIUtil.CreateText(button, "Title", title, UDim2.new(1, -16, 0, 24), UDim2.fromOffset(8, 64), Theme.Fonts.Navigation, 15)
	titleLabel.TextXAlignment = Enum.TextXAlignment.Center
	local subtitleLabel = UIUtil.CreateText(button, "Subtitle", subtitle, UDim2.new(1, -12, 0, 16), UDim2.fromOffset(6, 88), Theme.Fonts.Caption, 9)
	subtitleLabel.TextColor3 = Theme.MutedText
	subtitleLabel.TextXAlignment = Enum.TextXAlignment.Center
	local function focus(active)
		TweenService:Create(button, TweenInfo.new(0.12), {
			BackgroundColor3 = if active then Theme.PanelSelected else Theme.Panel,
			BackgroundTransparency = if active then 0 else 0.12,
		}):Play()
		stroke.Color = if active then Theme.StrokeBright else Theme.Stroke
		stroke.Thickness = if active then 2 else 1
		titleLabel.TextColor3 = if active then Theme.AccentCyan else Theme.Text
		iconLabel.ImageColor3 = if active then Color3.new(1, 1, 1) else Color3.fromRGB(195, 207, 232)
	end
	button.MouseEnter:Connect(function() focus(true) end)
	button.MouseLeave:Connect(function() focus(false) end)
	button.SelectionGained:Connect(function() focus(true) end)
	button.SelectionLost:Connect(function() focus(false) end)
	return button
end

function HomeScreen.Create(parent: Instance, callbacks)
	local frame = Instance.new("Frame")
	frame.Name = "Home"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = Theme.Background
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.Parent = parent

	local stadium = UIUtil.CreateImage(frame, "StadiumBackground", Assets.MenuStadium, UDim2.fromScale(1, 1), UDim2.fromScale(0, 0))
	stadium.ScaleType = Enum.ScaleType.Crop
	stadium.ImageTransparency = 0.08
	local veil = Instance.new("Frame")
	veil.Size = UDim2.fromScale(1, 1)
	veil.BackgroundColor3 = Theme.Background
	veil.BackgroundTransparency = 0.48
	veil.BorderSizePixel = 0
	veil.Parent = frame
	UIUtil.AddGradient(veil, Color3.fromRGB(1, 4, 16), Color3.fromRGB(14, 8, 40), 12)

	local logo = UIUtil.CreateImage(frame, "Logo", Assets.Logo, UDim2.fromOffset(220, 146), UDim2.fromOffset(42, 14))
	local localPlayer = Players.LocalPlayer

	local account = panel(frame, "Account", UDim2.fromOffset(390, 66), UDim2.new(1, -425, 0, 24), 0.2)
	local avatar = UIUtil.CreateImage(account, "Avatar", "", UDim2.fromOffset(48, 48), UDim2.new(1, -58, 0, 9))
	UIUtil.AddCorner(avatar, UDim.new(1, 0))
	local name = UIUtil.CreateText(account, "Name", localPlayer.DisplayName, UDim2.fromOffset(130, 22), UDim2.new(1, -202, 0, 10), Theme.Fonts.Navigation, 13)
	name.TextXAlignment = Enum.TextXAlignment.Right
	local level = UIUtil.CreateText(account, "Level", "LEVEL 12", UDim2.fromOffset(130, 18), UDim2.new(1, -202, 0, 34), Theme.Fonts.Caption, 10)
	level.TextColor3 = Theme.MutedText
	level.TextXAlignment = Enum.TextXAlignment.Right
	local currency = UIUtil.CreateImage(account, "B90", Assets.Currency.B90, UDim2.fromOffset(25, 25), UDim2.fromOffset(12, 20))
	UIUtil.CreateText(account, "B90Value", "12,450", UDim2.fromOffset(70, 24), UDim2.fromOffset(40, 20), Theme.Fonts.Statistics, 12)
	UIUtil.CreateImage(account, "Premium", Assets.Currency.Premium, UDim2.fromOffset(25, 25), UDim2.fromOffset(104, 20))
	UIUtil.CreateText(account, "PremiumValue", "350", UDim2.fromOffset(48, 24), UDim2.fromOffset(133, 20), Theme.Fonts.Statistics, 12)
	local portrait: ImageLabel? = nil
	task.spawn(function()
		local ok, image = pcall(Players.GetUserThumbnailAsync, Players, localPlayer.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size180x180)
		if ok and avatar.Parent then
			avatar.Image = image
			if portrait then portrait.Image = image end
		end
	end)

	local season = panel(frame, "Season", UDim2.fromOffset(570, 300), UDim2.fromOffset(54, 152), 0.24)
	local eyebrow = UIUtil.CreateText(season, "Eyebrow", "CURRENT SEASON", UDim2.fromOffset(220, 20), UDim2.fromOffset(22, 18), Theme.Fonts.Caption, 10)
	eyebrow.TextColor3 = Theme.AccentCyan
	UIUtil.CreateText(season, "Title", "SEASON 1  ·  RISING", UDim2.fromOffset(310, 32), UDim2.fromOffset(22, 38), Theme.Fonts.Display, 23)
	local endText = UIUtil.CreateText(season, "Ends", "ENDS IN 28 DAYS", UDim2.fromOffset(180, 20), UDim2.new(1, -202, 0, 25), Theme.Fonts.Caption, 10)
	endText.TextColor3 = Theme.MutedText
	endText.TextXAlignment = Enum.TextXAlignment.Right
	local division = panel(season, "Division", UDim2.new(1, -44, 0, 118), UDim2.fromOffset(22, 82), 0.22)
	UIUtil.CreateImage(division, "Badge", Assets.DivisionBadge, UDim2.fromOffset(82, 82), UDim2.fromOffset(13, 18))
	UIUtil.CreateText(division, "DivisionName", "DIVISION 6", UDim2.fromOffset(230, 24), UDim2.fromOffset(106, 17), Theme.Fonts.Navigation, 16)
	local rating = UIUtil.CreateText(division, "Rating", "1,284 RATING", UDim2.fromOffset(230, 20), UDim2.fromOffset(106, 44), Theme.Fonts.Caption, 11)
	rating.TextColor3 = Theme.MutedText
	local progress = Instance.new("Frame")
	progress.Size = UDim2.fromOffset(260, 5)
	progress.Position = UDim2.fromOffset(106, 72)
	progress.BackgroundColor3 = Color3.fromRGB(54, 65, 99)
	progress.BorderSizePixel = 0
	progress.Parent = division
	local progressFill = Instance.new("Frame")
	progressFill.Size = UDim2.fromScale(0.62, 1)
	progressFill.BackgroundColor3 = Theme.Accent
	progressFill.BorderSizePixel = 0
	progressFill.Parent = progress
	UIUtil.AddGradient(progressFill, Theme.AccentCyan, Theme.AccentViolet)
	local reward = UIUtil.CreateText(division, "Reward", "NEXT REWARD  +750 B90", UDim2.fromOffset(165, 22), UDim2.new(1, -177, 0, 83), Theme.Fonts.Caption, 10)
	reward.TextColor3 = Theme.AccentCyan
	local highlights = Instance.new("Frame")
	highlights.BackgroundTransparency = 1
	highlights.Size = UDim2.new(1, -44, 0, 68)
	highlights.Position = UDim2.fromOffset(22, 216)
	highlights.Parent = season
	smallStat(highlights, Assets.Highlights.Trophy, "MATCHES", "24", 0)
	smallStat(highlights, Assets.Highlights.Goal, "GOALS", "18", 142)
	smallStat(highlights, Assets.Highlights.MOTM, "MOTM", "6", 284)

	local featured = panel(frame, "FeaturedPlayer", UDim2.fromOffset(310, 390), UDim2.new(1, -370, 0, 112), 0.3)
	local featuredTitle = UIUtil.CreateText(featured, "Heading", "FEATURED PLAYER", UDim2.new(1, -24, 0, 25), UDim2.fromOffset(12, 10), Theme.Fonts.Navigation, 12)
	featuredTitle.TextXAlignment = Enum.TextXAlignment.Center
	local card = UIUtil.CreateImage(featured, "CardFrame", Assets.FeaturedPlayerFrame, UDim2.fromOffset(202, 270), UDim2.new(0.5, -101, 0, 40))
	portrait = UIUtil.CreateImage(featured, "Portrait", avatar.Image, UDim2.fromOffset(118, 118), UDim2.new(0.5, -59, 0, 82))
	UIUtil.AddCorner(portrait, UDim.new(1, 0))
	local ratingCard = UIUtil.CreateText(featured, "CardRating", "84", UDim2.fromOffset(52, 35), UDim2.fromOffset(61, 66), Theme.Fonts.Display, 26)
	ratingCard.TextXAlignment = Enum.TextXAlignment.Center
	local position = UIUtil.CreateText(featured, "Position", "CM", UDim2.fromOffset(52, 20), UDim2.fromOffset(61, 98), Theme.Fonts.Navigation, 11)
	position.TextXAlignment = Enum.TextXAlignment.Center
	local cardName = UIUtil.CreateText(featured, "CardName", string.upper(localPlayer.DisplayName), UDim2.fromOffset(180, 24), UDim2.new(0.5, -90, 0, 205), Theme.Fonts.Navigation, 12)
	cardName.TextXAlignment = Enum.TextXAlignment.Center
	local stats = UIUtil.CreateText(featured, "Stats", "82 PAC     80 SHO\n86 PAS     85 DRI\n62 DEF     76 PHY", UDim2.fromOffset(170, 60), UDim2.new(0.5, -85, 0, 235), Theme.Fonts.Statistics, 10)
	stats.TextXAlignment = Enum.TextXAlignment.Center
	stats.TextYAlignment = Enum.TextYAlignment.Top
	local hint = UIUtil.CreateText(featured, "Hint", "DEVELOPMENT CARD · COSMETIC", UDim2.new(1, -20, 0, 18), UDim2.fromOffset(10, 352), Theme.Fonts.Caption, 9)
	hint.TextColor3 = Theme.MutedText
	hint.TextXAlignment = Enum.TextXAlignment.Center

	local nav = Instance.new("Frame")
	nav.Name = "Navigation"
	nav.Size = UDim2.new(1, -108, 0, 112)
	nav.Position = UDim2.new(0, 54, 1, -162)
	nav.BackgroundTransparency = 1
	nav.Parent = frame
	local grid = Instance.new("UIGridLayout")
	grid.CellPadding = UDim2.fromOffset(13, 0)
	grid.CellSize = UDim2.new(0.2, -11, 1, 0)
	grid.FillDirectionMaxCells = 5
	grid.Parent = nav
	local play = navigationButton(nav, "Play", "PLAY", Assets.Navigation.Play, "CHOOSE A MODE")
	local training = navigationButton(nav, "Training", "TRAINING", Assets.Navigation.Training, "FREE PRACTICE")
	local clubs = navigationButton(nav, "Clubs", "CLUBS", Assets.Navigation.Clubs, "COMING SOON")
	local profileButton = navigationButton(nav, "Profile", "PROFILE", Assets.Navigation.Profile, "COMING SOON")
	local settings = navigationButton(nav, "Settings", "SETTINGS", Assets.Navigation.Settings, "COMING SOON")
	play.LayoutOrder = 1
	training.LayoutOrder = 2
	clubs.LayoutOrder = 3
	profileButton.LayoutOrder = 4
	settings.LayoutOrder = 5
	play.Activated:Connect(callbacks.OpenModeSelect)
	training.Activated:Connect(callbacks.OpenModeSelect)
	clubs.Activated:Connect(callbacks.ShowComingSoon)
	profileButton.Activated:Connect(callbacks.ShowComingSoon)
	settings.Activated:Connect(callbacks.ShowComingSoon)

	local footer = panel(frame, "Footer", UDim2.new(1, 0, 0, 34), UDim2.new(0, 0, 1, -34), 0.12)
	UIUtil.CreateText(footer, "Select", "A  SELECT       ☰  OPEN MENU", UDim2.fromOffset(300, 24), UDim2.fromOffset(24, 5), Theme.Fonts.Caption, 10)
	local news = UIUtil.CreateText(footer, "News", "NEWS   TRAINING FREE IS NOW OPEN", UDim2.fromOffset(480, 24), UDim2.new(0.5, -240, 0, 5), Theme.Fonts.Caption, 10)
	news.TextColor3 = Theme.MutedText
	news.TextXAlignment = Enum.TextXAlignment.Center
	UIUtil.CreateImage(footer, "Friends", Assets.Social.Friends, UDim2.fromOffset(20, 20), UDim2.new(1, -130, 0, 7))
	UIUtil.CreateImage(footer, "Chat", Assets.Social.Chat, UDim2.fromOffset(20, 20), UDim2.new(1, -92, 0, 7))
	UIUtil.CreateImage(footer, "Network", Assets.Social.Network, UDim2.fromOffset(20, 20), UDim2.new(1, -54, 0, 7))

	return { Frame = frame, DefaultSelection = play }
end

return HomeScreen
