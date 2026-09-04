--!strict
--[[
	PLAY (§12), following assets/UI_assets/mockup_play.png.

	The mockup's structure is reproduced: a page title on the left, a row of
	large match cards under a "CHOOSE YOUR MATCH" heading, a strip of featured
	modes beneath, and a right-hand column carrying season standing, daily
	challenges and friends.

	WHAT IS REAL AND WHAT IS NOT (§12).

	Beyond 90 currently supports exactly two playable entries: Quick 3v3 and
	Training. Those are the cards that work. Everything else in the mockup --
	ranked, casual, tournaments, club matches, event modes -- has no backend, so
	it is presented HONESTLY as unavailable rather than being wired to a button
	that pretends to queue. The season standing and daily challenges are shown as
	locked placeholders for the same reason: inventing a rank or a challenge
	progress number would be fabricating player data.

	The rule applied throughout: reproduce the LAYOUT faithfully, never invent
	the FUNCTIONALITY behind it.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Shared.ReactPackages).React
local Assets = require(ReplicatedStorage.Shared.Config.UIAssetConfig)
local Theme = require(script.Parent.Parent.Theme)
local ReactUI = require(script.Parent.Parent.Components.ReactUI)
local MenuKit = require(script.Parent.Parent.Components.MenuKit)

local localPlayer = Players.LocalPlayer

--[[
	A match card.

	`Available` decides everything about how it reads: an available card is
	bright, bordered in the accent and clickable; an unavailable one is dimmed
	and says so plainly. There is deliberately no third state -- a card either
	starts a match that exists, or admits that it does not.
]]
local function MatchCard(props)
	local mobile = props.Mobile == true
	local available = props.Available == true

	return React.createElement("TextButton", {
		LayoutOrder = props.Order,
		Size = UDim2.fromScale(0.245, 1),
		BackgroundColor3 = if props.Featured then Theme.PanelSelected else MenuKit.PanelColor,
		BackgroundTransparency = if available then 0.1 else 0.32,
		BorderSizePixel = 0,
		AutoButtonColor = available,
		Text = "",
		ZIndex = 4,
		[React.Event.Activated] = function()
			if available and props.Activate then
				props.Activate()
			elseif not available and props.Unavailable then
				props.Unavailable()
			end
		end,
	}, {
		Corner = ReactUI.Corner(9),
		Stroke = ReactUI.Stroke(
			if props.Featured then Theme.StrokeBright else MenuKit.PanelStroke,
			if props.Featured then 1.8 else 1,
			if available then 0.12 else 0.5
		),
		Title = MenuKit.Text({
			Position = UDim2.fromScale(0.08, 0.06),
			Size = UDim2.fromScale(0.86, 0.13),
			Font = Enum.Font.GothamBold,
			Text = props.Title,
			TextColor3 = if available then Theme.Text else Theme.FaintText,
			TextSize = MenuKit.Size(mobile, 21),
			FitTo = MenuKit.Size(mobile, 21),
			ZIndex = 5,
		}),
		Detail = MenuKit.Text({
			Position = UDim2.fromScale(0.08, 0.21),
			Size = UDim2.fromScale(0.84, 0.22),
			Font = Theme.Fonts.Caption,
			Text = props.Detail,
			TextColor3 = Theme.MutedText,
			TextSize = MenuKit.Size(mobile, 12),
			TextWrapped = true,
			ZIndex = 5,
		}),
		Art = React.createElement("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.58),
			Size = UDim2.fromScale(0.5, 0.34),
			BackgroundTransparency = 1,
			Image = props.Icon,
			ImageTransparency = if available then 0 else 0.55,
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = 5,
		}),
		--[[
			The footer strip carries the format on the left and the status on the
			right, matching the "5v5 | Players Online 1,742" bar in the mockup --
			except that here the right-hand slot tells the truth about whether the
			mode exists.
		]]
		Footer = MenuKit.Panel({
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 0.94),
			Size = UDim2.fromScale(0.86, 0.14),
			Transparency = 0.22,
			Radius = 6,
			ZIndex = 5,
		}, {
			Format = MenuKit.Text({
				Position = UDim2.fromScale(0.06, 0),
				Size = UDim2.fromScale(0.4, 1),
				Font = Theme.Fonts.Heading,
				Text = props.Format,
				TextColor3 = if available then Theme.Text else Theme.FaintText,
				TextSize = MenuKit.Size(mobile, 15),
				FitTo = MenuKit.Size(mobile, 15),
				ZIndex = 6,
			}),
			Status = MenuKit.Text({
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.fromScale(0.94, 0),
				Size = UDim2.fromScale(0.54, 1),
				Font = Theme.Fonts.Caption,
				Text = if available then "AVAILABLE" else "COMING LATER",
				TextColor3 = if available then Theme.AccentCyan else Theme.FaintText,
				TextSize = MenuKit.Size(mobile, 10),
				FitTo = MenuKit.Size(mobile, 10),
				TextXAlignment = Enum.TextXAlignment.Right,
				ZIndex = 6,
			}),
		}),
	})
end

-- A small featured-mode tile from the strip beneath the match cards.
local function FeaturedTile(props)
	local mobile = props.Mobile == true
	return MenuKit.Panel({
		LayoutOrder = props.Order,
		Size = UDim2.fromScale(0.245, 1),
		Transparency = 0.28,
		ZIndex = 4,
	}, {
		Badge = MenuKit.Panel({
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(0.95, 0.1),
			Size = UDim2.fromScale(0.26, 0.2),
			Transparency = 0.1,
			Radius = 4,
			ZIndex = 5,
		}, {
			Label = MenuKit.Text({
				Size = UDim2.fromScale(1, 1),
				Font = Theme.Fonts.Statistics,
				Text = props.Format,
				TextColor3 = Theme.MutedText,
				TextSize = MenuKit.Size(mobile, 10),
				FitTo = MenuKit.Size(mobile, 10),
				TextXAlignment = Enum.TextXAlignment.Center,
				ZIndex = 6,
			}),
		}),
		Title = MenuKit.Text({
			Position = UDim2.fromScale(0.07, 0.42),
			Size = UDim2.fromScale(0.86, 0.24),
			Font = Enum.Font.GothamBold,
			Text = props.Title,
			TextColor3 = Theme.FaintText,
			TextSize = MenuKit.Size(mobile, 14),
			ZIndex = 5,
		}),
		Detail = MenuKit.Text({
			Position = UDim2.fromScale(0.07, 0.66),
			Size = UDim2.fromScale(0.86, 0.28),
			Font = Theme.Fonts.Caption,
			Text = props.Detail,
			TextColor3 = Theme.FaintText,
			TextSize = MenuKit.Size(mobile, 10),
			TextWrapped = true,
			ZIndex = 5,
		}),
	})
end

--[[
	A right-column panel with nothing behind it yet.

	Used for the season standing, the daily challenges and the friends list.
	Rather than showing invented numbers, each says what it will be and that it
	is not available -- which is the honest version of the mockup (§12).
]]
local function PlaceholderPanel(props)
	local mobile = props.Mobile == true
	return MenuKit.Panel({
		Position = props.Position,
		Size = props.Size,
		Transparency = 0.16,
		ZIndex = 4,
	}, {
		Heading = React.createElement(MenuKit.PanelHeading, {
			Mobile = mobile,
			Title = props.Title,
			Position = UDim2.fromScale(0.06, 0.1),
			Size = UDim2.fromScale(0.88, 0.26),
			TitleSize = 15,
			ZIndex = 5,
		}),
		Body = MenuKit.Text({
			Position = UDim2.fromScale(0.06, 0.42),
			Size = UDim2.fromScale(0.88, 0.36),
			Font = Theme.Fonts.Caption,
			Text = props.Body,
			TextColor3 = Theme.MutedText,
			TextSize = MenuKit.Size(mobile, 11),
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			ZIndex = 5,
		}),
		Status = MenuKit.Text({
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0.06, 0.9),
			Size = UDim2.fromScale(0.88, 0.16),
			Font = Theme.Fonts.Statistics,
			Text = "NOT AVAILABLE YET",
			TextColor3 = Theme.FaintText,
			TextSize = MenuKit.Size(mobile, 10),
			ZIndex = 5,
		}),
	})
end

local function PlayScreen(props)
	local mobile = props.Mobile == true

	--[[
		The real modes come first, and only the real ones are clickable.
		`Quick3v3` and `TrainingFree` are the two mode ids GameModeService
		actually accepts.
	]]
	--[[
		TRAINING FIRST.

		It is the mode that is finished, the one a new player should meet first,
		and the one an existing player returns to most while the match modes are
		still being built. Ordering a list by how impressive a mode sounds rather
		than by how often it is wanted is a menu serving itself.

		It also carries the FEATURED treatment for the same reason -- the largest
		card on the page should be the thing the page most wants you to do.
	]]
	local matches = {
		{
			Title = "TRAINING",
			Detail = "Free practice on the pitch. Drills, shooting and control.",
			Format = "SOLO",
			Icon = Assets.Navigation.Training,
			Available = true,
			Featured = true,
			ModeId = "TrainingFree",
		},
		{
			Title = "QUICK 3V3",
			Detail = "Human-first match with AI filling any empty slots.",
			Format = "3v3",
			Icon = Assets.Navigation.Play,
			Available = true,
			ModeId = "Quick3v3",
		},
		{
			Title = "RANKED MATCH",
			Detail = "Compete in ranked matches to climb the leaderboard.",
			Format = "5v5",
			Icon = Assets.DivisionBadge,
			Available = false,
		},
		{
			Title = "CASUAL PLAY",
			Detail = "Unranked matches. No pressure, just football.",
			Format = "5v5",
			Icon = Assets.Highlights.Goal,
			Available = false,
		},
	}

	local cards = {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Left,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0.013, 0),
		}),
	}
	for index, entry in matches do
		cards["Match" .. index] = React.createElement(MatchCard, {
			Order = index,
			Mobile = mobile,
			Title = entry.Title,
			Detail = entry.Detail,
			Format = entry.Format,
			Icon = entry.Icon,
			Available = entry.Available,
			Featured = entry.Featured,
			Activate = function()
				if props.SelectMode then
					props.SelectMode(entry.ModeId)
				end
			end,
			Unavailable = props.Unavailable,
		})
	end

	local featured = {
		{ Title = "VOLTA RUSH", Detail = "Fast-paced street football.", Format = "3v3" },
		{ Title = "CLUB MATCHES", Detail = "Team up with your club.", Format = "11v11" },
		{ Title = "TOURNAMENTS", Detail = "Compete for big rewards.", Format = "5v5" },
		{ Title = "EVENT MODES", Detail = "Rotating modes with unique rules.", Format = "LIMITED" },
	}
	local featuredChildren = {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Left,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0.013, 0),
		}),
	}
	for index, entry in featured do
		featuredChildren["Featured" .. index] = React.createElement(FeaturedTile, {
			Order = index,
			Mobile = mobile,
			Title = entry.Title,
			Detail = entry.Detail,
			Format = entry.Format,
		})
	end

	return React.createElement(MenuKit.Shell, {
		Name = "Play",
		Mobile = mobile,
		Current = "Play",
		Navigate = props.Navigate,
		MenuPrompt = props.MenuPrompt,
		Portrait = props.Portrait,
		LevelText = props.LevelText,
		LevelProgress = props.LevelProgress,
		SoftCurrency = props.SoftCurrency,
		HardCurrency = props.HardCurrency,
		Content = {
			Title = React.createElement(MenuKit.PageTitle, {
				Mobile = mobile,
				Title = "PLAY",
				Caption = "Jump into matches, compete, and climb the ranks.",
				Position = UDim2.fromScale(if mobile then 0.03 else 0.045, if mobile then 0.19 else 0.2),
				Size = UDim2.fromScale(0.35, if mobile then 0.16 else 0.14),
			}),

			ChooseHeading = MenuKit.Text({
				Position = UDim2.fromScale(if mobile then 0.03 else 0.045, if mobile then 0.35 else 0.35),
				Size = UDim2.fromScale(0.4, 0.05),
				Font = Enum.Font.GothamBold,
				Text = "CHOOSE YOUR MATCH",
				TextColor3 = Theme.AccentCyan,
				TextSize = MenuKit.Size(mobile, 15),
				ZIndex = 4,
			}),

			Matches = React.createElement("Frame", {
				Position = UDim2.fromScale(if mobile then 0.03 else 0.045, if mobile then 0.41 else 0.41),
				Size = UDim2.fromScale(if mobile then 0.64 else 0.615, if mobile then 0.28 else 0.31),
				BackgroundTransparency = 1,
				ZIndex = 4,
			}, cards),

			FeaturedHeading = MenuKit.Text({
				Position = UDim2.fromScale(if mobile then 0.03 else 0.045, if mobile then 0.7 else 0.735),
				Size = UDim2.fromScale(0.4, 0.04),
				Font = Enum.Font.GothamBold,
				Text = "FEATURED MODES",
				TextColor3 = Theme.AccentCyan,
				TextSize = MenuKit.Size(mobile, 13),
				ZIndex = 4,
			}),

			Featured = React.createElement("Frame", {
				Position = UDim2.fromScale(if mobile then 0.03 else 0.045, if mobile then 0.745 else 0.775),
				Size = UDim2.fromScale(if mobile then 0.64 else 0.615, if mobile then 0.1 else 0.09),
				BackgroundTransparency = 1,
				ZIndex = 4,
			}, featuredChildren),

			--[[
				Right column. Every panel here corresponds to a system Beyond 90
				has not built yet, so each says so rather than showing a fabricated
				rank or challenge count (§12).
			]]
			Season = React.createElement(PlaceholderPanel, {
				Mobile = mobile,
				Title = "SEASON",
				Body = "Ranked seasons, divisions and rewards arrive with the competitive milestone.",
				Position = UDim2.fromScale(if mobile then 0.69 else 0.675, if mobile then 0.19 else 0.2),
				Size = UDim2.fromScale(if mobile then 0.28 else 0.28, if mobile then 0.19 else 0.19),
			}),
			Challenges = React.createElement(PlaceholderPanel, {
				Mobile = mobile,
				Title = "DAILY CHALLENGES",
				Body = "Objectives and XP rewards arrive with the progression milestone.",
				Position = UDim2.fromScale(if mobile then 0.69 else 0.675, if mobile then 0.4 else 0.41),
				Size = UDim2.fromScale(if mobile then 0.28 else 0.28, if mobile then 0.22 else 0.23),
			}),
			Friends = React.createElement(PlaceholderPanel, {
				Mobile = mobile,
				Title = "PLAY WITH FRIENDS",
				Body = "Parties and invites arrive with the matchmaking milestone.",
				Position = UDim2.fromScale(if mobile then 0.69 else 0.675, if mobile then 0.64 else 0.66),
				Size = UDim2.fromScale(if mobile then 0.28 else 0.28, if mobile then 0.19 else 0.2),
			}),
		},
	})
end

return PlayScreen
