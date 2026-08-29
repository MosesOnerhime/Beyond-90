--!strict
--[[
	CLUBS (§14), following assets/UI_assets/mockup_clubs.png.

	The mockup's structure is reproduced: page title on the left over a vertical
	section list, a club identity card across the top, member / match /
	announcement columns beneath, and an activity strip along the bottom.

	NO CLUBS BACKEND EXISTS, AND NONE IS INVENTED HERE (§14).

	Beyond 90 has no club records, no membership, no club matches and no club
	ranking -- Clubs is milestone 6.8. Showing "BEYOND FC, 24/30 members, 87
	wins" would be fabricated networked data presented as real, which §14
	explicitly forbids and which would be indistinguishable from a bug once a
	real backend arrives and disagrees with it.

	So the page is built as the mockup's LAYOUT holding an honest empty state:
	every panel names what it will contain and says it is not available. The
	structure is real, the design is real, and the moment a ClubService exists
	the panels have somewhere to put its data.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Shared.ReactPackages).React
local Assets = require(ReplicatedStorage.Shared.Config.UIAssetConfig)
local Theme = require(script.Parent.Parent.Theme)
local ReactUI = require(script.Parent.Parent.Components.ReactUI)
local MenuKit = require(script.Parent.Parent.Components.MenuKit)

--[[
	The left-hand section list from the mockup (OVERVIEW / MEMBERS / MATCHES /
	RANKINGS / CLUB SHOP / SETTINGS).

	Selectable so the page reads correctly, but every section shows the same
	honest empty state -- there is nothing behind any of them yet.
]]
local function SectionButton(props)
	local mobile = props.Mobile == true
	local selected = props.Selected == true
	return React.createElement("TextButton", {
		LayoutOrder = props.Order,
		Size = UDim2.new(1, 0, 0, if mobile then 26 else 38),
		BackgroundColor3 = if selected then Theme.PanelSelected else MenuKit.PanelColor,
		BackgroundTransparency = if selected then 0.05 else 0.28,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Text = "",
		ZIndex = 5,
		[React.Event.Activated] = props.Activate,
	}, {
		Corner = ReactUI.Corner(6),
		Stroke = ReactUI.Stroke(
			if selected then Theme.StrokeBright else MenuKit.PanelStroke,
			if selected then 1.5 else 1,
			if selected then 0.12 else 0.45
		),
		Label = MenuKit.Text({
			Position = UDim2.fromScale(0.1, 0),
			Size = UDim2.fromScale(0.85, 1),
			Font = Theme.Fonts.Navigation,
			Text = props.Title,
			TextColor3 = if selected then Theme.Text else Theme.MutedText,
			TextSize = MenuKit.Size(mobile, 14),
			ZIndex = 6,
		}),
	})
end

--[[
	A panel that describes what it will hold, and says plainly that it does not
	hold it yet. The unit the whole page is made of.
]]
local function EmptyPanel(props)
	local mobile = props.Mobile == true
	return MenuKit.Panel({
		Position = props.Position,
		Size = props.Size,
		Visible = props.Visible ~= false,
		Transparency = 0.16,
		ZIndex = 4,
	}, {
		Title = MenuKit.Text({
			Position = UDim2.fromScale(0.06, 0.08),
			Size = UDim2.fromScale(0.88, 0.18),
			Font = Enum.Font.GothamBold,
			Text = props.Title,
			TextSize = MenuKit.Size(mobile, 15),
			ZIndex = 5,
		}),
		Body = MenuKit.Text({
			Position = UDim2.fromScale(0.06, 0.3),
			Size = UDim2.fromScale(0.88, 0.42),
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
			Position = UDim2.fromScale(0.06, 0.92),
			Size = UDim2.fromScale(0.88, 0.14),
			Font = Theme.Fonts.Statistics,
			Text = "NOT AVAILABLE YET",
			TextColor3 = Theme.FaintText,
			TextSize = MenuKit.Size(mobile, 10),
			ZIndex = 5,
		}),
	})
end

local function ClubsScreen(props)
	local mobile = props.Mobile == true
	local sections = { "OVERVIEW", "MEMBERS", "MATCHES", "RANKINGS", "CLUB SHOP", "SETTINGS" }
	local selectedSection, setSelectedSection = React.useState(1)

	--[[
		THE SECTION LIST NOW SELECTS SOMETHING.

		All five content panels were drawn at once in a tiled grid, so picking
		MEMBERS moved a highlight and changed nothing on the right -- and the
		page showed five competing placeholder cards when it had one thing to
		say. Each section now owns the whole right-hand region and only the
		chosen one is drawn.
	]]
	local panelPosition = UDim2.fromScale(if mobile then 0.25 else 0.23, if mobile then 0.3 else 0.3)
	local panelSize = UDim2.fromScale(if mobile then 0.72 else 0.73, if mobile then 0.52 else 0.5)

	-- OVERVIEW is the one section with two things to say, so it splits the
	-- region: who the club is on top, what it has been saying underneath.
	local overviewTopSize = UDim2.fromScale(if mobile then 0.72 else 0.73, if mobile then 0.3 else 0.28)
	local overviewBottomPosition = UDim2.fromScale(if mobile then 0.25 else 0.23, if mobile then 0.63 else 0.6)
	local overviewBottomSize = UDim2.fromScale(if mobile then 0.72 else 0.73, if mobile then 0.19 else 0.2)

	local sectionChildren = {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, if mobile then 4 else 7),
		}),
	}
	for index, title in sections do
		sectionChildren[title] = React.createElement(SectionButton, {
			Order = index,
			Mobile = mobile,
			Title = title,
			Selected = selectedSection == index,
			Activate = function()
				setSelectedSection(index)
			end,
		})
	end

	return React.createElement(MenuKit.Shell, {
		Name = "Clubs",
		Mobile = mobile,
		Current = "Clubs",
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
				Title = "CLUBS",
				Caption = "Play together. Win together.",
				Position = UDim2.fromScale(if mobile then 0.03 else 0.04, if mobile then 0.19 else 0.21),
				Size = UDim2.fromScale(0.28, if mobile then 0.15 else 0.13),
			}),

			Sections = React.createElement("Frame", {
				Position = UDim2.fromScale(if mobile then 0.03 else 0.04, if mobile then 0.3 else 0.3),
				Size = UDim2.fromScale(if mobile then 0.19 else 0.16, if mobile then 0.52 else 0.5),
				BackgroundTransparency = 1,
				ZIndex = 4,
			}, sectionChildren),

			--[[
				The club identity card. In the mockup this carries the badge, name,
				tag, founding date, member count and club level. With no club to
				describe, it invites the player to create one instead -- which is
				what this page will actually do first when Clubs ships.
			]]
			Identity = MenuKit.Panel({
				Position = panelPosition,
				Size = overviewTopSize,
				Visible = selectedSection == 1,
				Transparency = 0.12,
				ZIndex = 4,
			}, {
				Badge = React.createElement("ImageLabel", {
					Position = UDim2.fromScale(0.04, 0.06),
					Size = UDim2.fromScale(0.15, 0.34),
					BackgroundTransparency = 1,
					Image = Assets.ClubBadgeSheet,
					ImageTransparency = 0.45,
					ScaleType = Enum.ScaleType.Fit,
					ZIndex = 5,
				}),
				Heading = MenuKit.Text({
					Position = UDim2.fromScale(0.22, 0.08),
					Size = UDim2.fromScale(0.7, 0.12),
					Font = Enum.Font.GothamBold,
					Text = "NO CLUB YET",
					TextSize = MenuKit.Size(mobile, 22),
					ZIndex = 5,
				}),
				Body = MenuKit.Text({
					Position = UDim2.fromScale(0.22, 0.22),
					Size = UDim2.fromScale(0.73, 0.18),
					Font = Theme.Fonts.Caption,
					Text = "Create a club, invite friends, compete in tournaments and climb the rankings together.",
					TextColor3 = Theme.MutedText,
					TextSize = MenuKit.Size(mobile, 11),
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					ZIndex = 5,
				}),
				Status = MenuKit.Text({
					Position = UDim2.fromScale(0.22, 0.42),
					Size = UDim2.fromScale(0.7, 0.08),
					Font = Theme.Fonts.Statistics,
					Text = "CLUBS ARRIVE IN A LATER MILESTONE",
					TextColor3 = Theme.FaintText,
					TextSize = MenuKit.Size(mobile, 10),
					ZIndex = 5,
				}),
			}),

			Ranking = React.createElement(EmptyPanel, {
				Mobile = mobile,
				Title = "CLUB RANKING",
				Body = "Division, rating and promotion progress for your club.",
				Position = panelPosition,
				Size = panelSize,
				Visible = selectedSection == 4,
			}),

			Members = React.createElement(EmptyPanel, {
				Mobile = mobile,
				Title = "MEMBERS",
				Body = "Your club roster, with roles, levels and who is online.",
				Position = panelPosition,
				Size = panelSize,
				Visible = selectedSection == 2,
			}),
			Matches = React.createElement(EmptyPanel, {
				Mobile = mobile,
				Title = "CLUB MATCHES",
				Body = "Recent results, upcoming fixtures and tournament entries.",
				Position = panelPosition,
				Size = panelSize,
				Visible = selectedSection == 3,
			}),
			Shop = React.createElement(EmptyPanel, {
				Mobile = mobile,
				Title = "CLUB SHOP",
				Body = "Club-only kits, badges and cosmetics bought with club funds.",
				Position = panelPosition,
				Size = panelSize,
				Visible = selectedSection == 5,
			}),
			ClubSettings = React.createElement(EmptyPanel, {
				Mobile = mobile,
				Title = "CLUB SETTINGS",
				Body = "Roles, permissions, join requirements and club identity.",
				Position = panelPosition,
				Size = panelSize,
				Visible = selectedSection == 6,
			}),
			-- OVERVIEW is the one section with two things to say, so it keeps
			-- both: who the club is on top, what it has been saying underneath.
			Announcements = React.createElement(EmptyPanel, {
				Mobile = mobile,
				Title = "ANNOUNCEMENTS",
				Body = "Posts from your club's leaders and captains.",
				Position = overviewBottomPosition,
				Size = overviewBottomSize,
				Visible = selectedSection == 1,
			}),
		},
	})
end

return ClubsScreen
