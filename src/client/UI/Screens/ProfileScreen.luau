--!strict
--[[
	PROFILE (§15), following assets/UI_assets/mockup_profile.png.

	The mockup's structure is reproduced: an identity card on the left with the
	player's avatar and level, a PLAYER STATS grid in the middle, PROGRESSION on
	the right, and an identity / achievements / football-info row beneath.

	REAL DATA VERSUS PLACEHOLDER (§15).

	What Beyond 90 genuinely knows about a player right now is: their Roblox
	display name, their user id, their avatar, their selected team and their
	chosen position. Those are shown, and they are real.

	Everything the mockup shows beyond that -- matches played, goals, assists,
	win rate, clean sheets, MOTM awards, level, season pass tier, achievements --
	requires the persistence layer from milestone 6.7, which does not exist. Those
	are rendered as an explicit placeholder state rather than as invented numbers:
	§15 says not to fake statistics, and a fabricated "38 goals scored" would be
	indistinguishable from a real value that happened to be wrong.

	The stat tiles are therefore laid out exactly as the mockup has them and show
	a dash, with one line explaining why. When PlayerDataService exists, only the
	values change.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Shared.ReactPackages).React
local Theme = require(script.Parent.Parent.Theme)
local ReactUI = require(script.Parent.Parent.Components.ReactUI)
local MenuKit = require(script.Parent.Parent.Components.MenuKit)
local PositionConfig = require(ReplicatedStorage.Shared.Config.PositionConfig)
local FootballTeamConfig = require(ReplicatedStorage.Shared.Config.FootballTeamConfig)

local localPlayer = Players.LocalPlayer

-- One row of the IDENTITY panel: a label and its value.
local function IdentityRow(props)
	local mobile = props.Mobile == true
	return React.createElement("Frame", {
		LayoutOrder = props.Order,
		Size = UDim2.new(1, 0, 0, if mobile then 20 else 28),
		BackgroundColor3 = Color3.fromRGB(14, 21, 46),
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		ZIndex = 5,
	}, {
		Corner = ReactUI.Corner(5),
		Label = MenuKit.Text({
			Position = UDim2.fromScale(0.05, 0),
			Size = UDim2.fromScale(0.5, 1),
			Font = Theme.Fonts.Caption,
			Text = props.Label,
			TextColor3 = Theme.MutedText,
			TextSize = MenuKit.Size(mobile, 11),
			ZIndex = 6,
		}),
		Value = MenuKit.Text({
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(0.95, 0),
			Size = UDim2.fromScale(0.45, 1),
			Font = Theme.Fonts.Statistics,
			Text = props.Value,
			TextColor3 = if props.Known then Theme.Text else Theme.FaintText,
			TextSize = MenuKit.Size(mobile, 11),
			TextXAlignment = Enum.TextXAlignment.Right,
			TextTruncate = Enum.TextTruncate.AtEnd,
			ZIndex = 6,
		}),
	})
end

local function ProfileScreen(props)
	local mobile = props.Mobile == true
	local portrait = props.Portrait or ""

	--[[
		Real, currently-known identity. Team and position are only set once the
		player has been through the pre-match flow, so both fall back to a plain
		"not selected" rather than to a guess.
	]]
	local teamId = FootballTeamConfig.Normalize(localPlayer:GetAttribute(FootballTeamConfig.AttributeName))
	local slotId = localPlayer:GetAttribute(PositionConfig.SlotAttributeName)
	local positionEntry = if typeof(slotId) == "string" then PositionConfig.Get(slotId) else nil

	--[[
		The stat grid. Every value is a dash: these need match persistence, which
		does not exist yet (§15). The GRID is the deliverable; the numbers arrive
		with milestone 6.7.
	]]
	local statNames = {
		"MATCHES PLAYED", "GOALS SCORED", "ASSISTS",
		"GOALS PER MATCH", "WIN RATE", "CLEAN SHEETS",
		"SHOTS TAKEN", "TACKLES", "MOTM AWARDS",
	}
	local statChildren = {
		Layout = React.createElement("UIGridLayout", {
			CellSize = UDim2.fromScale(0.315, 0.29),
			CellPadding = UDim2.fromScale(0.025, 0.06),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}
	for index, caption in statNames do
		statChildren["Stat" .. index] = React.createElement(MenuKit.StatTile, {
			Order = index,
			Mobile = mobile,
			Value = "--",
			Caption = caption,
			ValueSize = 22,
			Size = UDim2.fromScale(1, 1),
			ZIndex = 5,
		})
	end

	local identityRows = {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, if mobile then 3 else 5),
		}),
		Row1 = React.createElement(IdentityRow, {
			Order = 1, Mobile = mobile, Label = "DISPLAY NAME",
			Value = localPlayer.DisplayName, Known = true,
		}),
		Row2 = React.createElement(IdentityRow, {
			Order = 2, Mobile = mobile, Label = "USERNAME",
			Value = "@" .. localPlayer.Name, Known = true,
		}),
		Row3 = React.createElement(IdentityRow, {
			Order = 3, Mobile = mobile, Label = "CURRENT TEAM",
			Value = if teamId then string.upper(teamId) else "NOT SELECTED", Known = teamId ~= nil,
		}),
		Row4 = React.createElement(IdentityRow, {
			Order = 4, Mobile = mobile, Label = "POSITION",
			Value = if positionEntry then string.upper(positionEntry.DisplayName) else "NOT SELECTED",
			Known = positionEntry ~= nil,
		}),
		Row5 = React.createElement(IdentityRow, {
			Order = 5, Mobile = mobile, Label = "CLUB",
			Value = "NO CLUB", Known = false,
		}),
	}

	return React.createElement(MenuKit.Shell, {
		Name = "Profile",
		Mobile = mobile,
		Current = "Profile",
		Navigate = props.Navigate,
		MenuPrompt = props.MenuPrompt,
		Portrait = portrait,
		LevelText = props.LevelText,
		LevelProgress = props.LevelProgress,
		SoftCurrency = props.SoftCurrency,
		HardCurrency = props.HardCurrency,
		Content = {
			Title = React.createElement(MenuKit.PageTitle, {
				Mobile = mobile,
				Title = "PROFILE",
				Caption = "View your stats, progression and identity.",
				Position = UDim2.fromScale(if mobile then 0.03 else 0.04, if mobile then 0.19 else 0.2),
				Size = UDim2.fromScale(0.3, if mobile then 0.14 else 0.12),
			}),

			--[[
				The identity card. Avatar and name are real; the level bar shows
				the same placeholder the account strip does, so the two can never
				disagree about a number neither of them has.
			]]
			Card = MenuKit.Panel({
				Position = UDim2.fromScale(if mobile then 0.03 else 0.04, if mobile then 0.35 else 0.35),
				Size = UDim2.fromScale(if mobile then 0.28 else 0.26, if mobile then 0.42 else 0.42),
				Transparency = 0.12,
				ZIndex = 4,
			}, {
				--[[
					A STATIC PORTRAIT (§17).

					A live rig playing an idle was added here previously. It has
					been removed: Profile is a page you read, and a looping
					character animation in the corner of it competes with the
					information the page exists to show. It also cost a rig clone,
					an animation fetch and a ViewportFrame render on a screen that
					needs none of them.
				]]
				Avatar = React.createElement("ImageLabel", {
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.fromScale(0.5, 0.05),
					Size = UDim2.fromScale(0.42, 0.36),
					BackgroundColor3 = Color3.fromRGB(10, 16, 38),
					BackgroundTransparency = 0.4,
					BorderSizePixel = 0,
					Image = portrait,
					ScaleType = Enum.ScaleType.Fit,
					ZIndex = 5,
				}, {
					Corner = ReactUI.Corner(100),
					Stroke = ReactUI.Stroke(Theme.AccentViolet, 2, 0.15),
				}),
				Name = MenuKit.Text({
					Position = UDim2.fromScale(0.06, 0.44),
					Size = UDim2.fromScale(0.88, 0.1),
					Font = Enum.Font.GothamBold,
					Text = localPlayer.DisplayName,
					TextSize = MenuKit.Size(mobile, 19),
					TextXAlignment = Enum.TextXAlignment.Center,
					TextTruncate = Enum.TextTruncate.AtEnd,
					ZIndex = 5,
				}),
				Handle = MenuKit.Text({
					Position = UDim2.fromScale(0.06, 0.545),
					Size = UDim2.fromScale(0.88, 0.07),
					Font = Theme.Fonts.Caption,
					Text = "@" .. localPlayer.Name,
					TextColor3 = Theme.MutedText,
					TextSize = MenuKit.Size(mobile, 11),
					TextXAlignment = Enum.TextXAlignment.Center,
					ZIndex = 5,
				}),
				ProgressCaption = MenuKit.Text({
					Position = UDim2.fromScale(0.08, 0.66),
					Size = UDim2.fromScale(0.84, 0.07),
					Font = Theme.Fonts.Caption,
					Text = "LEVEL PROGRESS",
					TextColor3 = Theme.MutedText,
					TextSize = MenuKit.Size(mobile, 10),
					ZIndex = 5,
				}),
				Progress = MenuKit.ProgressBar({
					Position = UDim2.fromScale(0.08, 0.75),
					Size = UDim2.fromScale(0.84, 0.035),
					Fill = props.LevelProgress or 0,
					ZIndex = 5,
				}),
				Note = MenuKit.Text({
					AnchorPoint = Vector2.new(0.5, 1),
					Position = UDim2.fromScale(0.5, 0.95),
					Size = UDim2.fromScale(0.86, 0.14),
					Font = Theme.Fonts.Caption,
					Text = "Career progression is not saved yet.",
					TextColor3 = Theme.FaintText,
					TextSize = MenuKit.Size(mobile, 10),
					TextXAlignment = Enum.TextXAlignment.Center,
					TextWrapped = true,
					ZIndex = 5,
				}),
			}),

			StatsPanel = MenuKit.Panel({
				Position = UDim2.fromScale(if mobile then 0.33 else 0.32, if mobile then 0.19 else 0.2),
				Size = UDim2.fromScale(if mobile then 0.32 else 0.32, if mobile then 0.58 else 0.57),
				Transparency = 0.14,
				ZIndex = 4,
			}, {
				Heading = React.createElement(MenuKit.PanelHeading, {
					Mobile = mobile,
					Title = "PLAYER STATS",
					Caption = "Recorded once match persistence is implemented.",
					Position = UDim2.fromScale(0.05, 0.04),
					Size = UDim2.fromScale(0.9, 0.14),
					ZIndex = 5,
				}),
				Grid = React.createElement("Frame", {
					Position = UDim2.fromScale(0.05, 0.2),
					Size = UDim2.fromScale(0.9, 0.75),
					BackgroundTransparency = 1,
					ZIndex = 5,
				}, statChildren),
			}),

			IdentityPanel = MenuKit.Panel({
				Position = UDim2.fromScale(if mobile then 0.67 else 0.66, if mobile then 0.19 else 0.2),
				Size = UDim2.fromScale(if mobile then 0.3 else 0.3, if mobile then 0.34 else 0.33),
				Transparency = 0.14,
				ZIndex = 4,
			}, {
				Heading = React.createElement(MenuKit.PanelHeading, {
					Mobile = mobile,
					Title = "IDENTITY",
					Caption = "What Beyond 90 currently knows about you.",
					Position = UDim2.fromScale(0.05, 0.05),
					Size = UDim2.fromScale(0.9, 0.22),
					ZIndex = 5,
				}),
				Rows = React.createElement("Frame", {
					Position = UDim2.fromScale(0.05, 0.3),
					Size = UDim2.fromScale(0.9, 0.64),
					BackgroundTransparency = 1,
					ZIndex = 5,
				}, identityRows),
			}),

			ProgressionPanel = MenuKit.Panel({
				Position = UDim2.fromScale(if mobile then 0.67 else 0.66, if mobile then 0.55 else 0.55),
				Size = UDim2.fromScale(if mobile then 0.3 else 0.3, if mobile then 0.22 else 0.22),
				Transparency = 0.14,
				ZIndex = 4,
			}, {
				Heading = React.createElement(MenuKit.PanelHeading, {
					Mobile = mobile,
					Title = "PROGRESSION",
					Position = UDim2.fromScale(0.05, 0.08),
					Size = UDim2.fromScale(0.9, 0.28),
					ZIndex = 5,
				}),
				Body = MenuKit.Text({
					Position = UDim2.fromScale(0.05, 0.42),
					Size = UDim2.fromScale(0.9, 0.36),
					Font = Theme.Fonts.Caption,
					Text = "XP, seasons, achievements and rewards arrive with the progression milestone.",
					TextColor3 = Theme.MutedText,
					TextSize = MenuKit.Size(mobile, 11),
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					ZIndex = 5,
				}),
				Status = MenuKit.Text({
					AnchorPoint = Vector2.new(0, 1),
					Position = UDim2.fromScale(0.05, 0.92),
					Size = UDim2.fromScale(0.9, 0.14),
					Font = Theme.Fonts.Statistics,
					Text = "NOT AVAILABLE YET",
					TextColor3 = Theme.FaintText,
					TextSize = MenuKit.Size(mobile, 10),
					ZIndex = 5,
				}),
			}),
		},
	})
end

return ProfileScreen
