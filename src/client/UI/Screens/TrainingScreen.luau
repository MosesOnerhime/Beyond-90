--!strict
--[[
	TRAINING (§13), following assets/UI_assets/mockup_training.png.

	The mockup's structure is reproduced: a "LEVEL UP. EVERY DAY." title block
	over a large featured-drill card on the left, a TRAINING MODULES grid on the
	right, and a row of supporting panels beneath it.

	FUNCTION IS PRESERVED (§13).

	The one thing on this page that actually works is entering training, and it
	still works exactly as before: START DRILL calls the same OpenTeamSelection
	callback with the same `TrainingFree` mode id, so team selection, position
	selection and the AI/goalkeeper spawn support behind them are untouched.
	The DEV tooling available once inside gameplay is likewise unaffected --
	nothing on this screen touches it.

	The training MODULES (attacking / ball control / defending / physical) and
	their progress bars have no backing system: there are no drills, no XP and
	no per-skill progress yet. They are drawn as the mockup has them but marked
	unavailable, rather than showing invented "65% complete" figures.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Shared.ReactPackages).React
local Assets = require(ReplicatedStorage.Shared.Config.UIAssetConfig)
local Theme = require(script.Parent.Parent.Theme)
local ReactUI = require(script.Parent.Parent.Components.ReactUI)
local MenuKit = require(script.Parent.Parent.Components.MenuKit)

--[[
	A training module tile.

	`Available` is false for all four today. When drills exist, each becomes a
	real entry point and the progress bar reports real completion.
]]
local function ModuleTile(props)
	local mobile = props.Mobile == true
	return MenuKit.Panel({
		LayoutOrder = props.Order,
		Size = UDim2.fromScale(0.235, 1),
		Transparency = 0.22,
		ZIndex = 5,
	}, {
		Icon = React.createElement("ImageLabel", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0.1),
			Size = UDim2.fromScale(0.32, 0.26),
			BackgroundTransparency = 1,
			Image = props.Icon,
			ImageTransparency = 0.35,
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = 6,
		}),
		Title = MenuKit.Text({
			Position = UDim2.fromScale(0.06, 0.42),
			Size = UDim2.fromScale(0.88, 0.16),
			Font = Enum.Font.GothamBold,
			Text = props.Title,
			TextColor3 = Theme.MutedText,
			TextSize = MenuKit.Size(mobile, 14),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 6,
		}),
		Detail = MenuKit.Text({
			Position = UDim2.fromScale(0.08, 0.58),
			Size = UDim2.fromScale(0.84, 0.22),
			Font = Theme.Fonts.Caption,
			Text = props.Detail,
			TextColor3 = Theme.FaintText,
			TextSize = MenuKit.Size(mobile, 10),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextWrapped = true,
			ZIndex = 6,
		}),
		Status = MenuKit.Text({
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 0.94),
			Size = UDim2.fromScale(0.88, 0.13),
			Font = Theme.Fonts.Statistics,
			Text = "COMING LATER",
			TextColor3 = Theme.FaintText,
			TextSize = MenuKit.Size(mobile, 9),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = 6,
		}),
	})
end

local function TrainingScreen(props)
	local mobile = props.Mobile == true

	local modules = {
		{ Title = "ATTACKING", Detail = "Shooting, finishing, off the ball", Icon = Assets.Highlights.Goal },
		{ Title = "BALL CONTROL", Detail = "Dribbling, first touch, agility", Icon = Assets.Navigation.Play },
		{ Title = "DEFENDING", Detail = "Tackling, positioning, interceptions", Icon = Assets.Navigation.Clubs },
		{ Title = "PHYSICAL", Detail = "Speed, stamina, strength", Icon = Assets.Highlights.MOTM },
	}
	local moduleChildren = {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0.015, 0),
		}),
	}
	for index, entry in modules do
		moduleChildren["Module" .. index] = React.createElement(ModuleTile, {
			Order = index,
			Mobile = mobile,
			Title = entry.Title,
			Detail = entry.Detail,
			Icon = entry.Icon,
		})
	end

	return React.createElement(MenuKit.Shell, {
		Name = "Training",
		Mobile = mobile,
		Current = "Training",
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
				Eyebrow = "TRAINING",
				Title = "LEVEL UP. EVERY DAY.",
				Caption = "Sharpen your skills and master the pitch.",
				TitleSize = 32,
				Position = UDim2.fromScale(if mobile then 0.03 else 0.04, if mobile then 0.18 else 0.19),
				Size = UDim2.fromScale(0.4, if mobile then 0.2 else 0.19),
			}),

			--[[
				FEATURED DRILL -- the one working entry point on this page.

				Free practice is a real mode. START DRILL routes through the exact
				same callback the old screen used, so team selection, position
				selection and everything downstream of them is unchanged.
			]]
			Featured = MenuKit.Panel({
				Position = UDim2.fromScale(if mobile then 0.03 else 0.04, if mobile then 0.4 else 0.41),
				Size = UDim2.fromScale(if mobile then 0.4 else 0.36, if mobile then 0.35 else 0.35),
				Transparency = 0.1,
				StrokeColor = Theme.StrokeBright,
				StrokeTransparency = 0.25,
				ZIndex = 4,
			}, {
				Eyebrow = MenuKit.Text({
					Position = UDim2.fromScale(0.05, 0.07),
					Size = UDim2.fromScale(0.9, 0.1),
					Font = Enum.Font.GothamBold,
					Text = "FEATURED DRILL",
					TextColor3 = Theme.AccentCyan,
					TextSize = MenuKit.Size(mobile, 12),
					ZIndex = 5,
				}),
				Title = MenuKit.Text({
					Position = UDim2.fromScale(0.05, 0.18),
					Size = UDim2.fromScale(0.9, 0.16),
					Font = Enum.Font.GothamBlack,
					Text = "FREE PRACTICE",
					TextSize = MenuKit.Size(mobile, 26),
					ZIndex = 5,
				}),
				Detail = MenuKit.Text({
					Position = UDim2.fromScale(0.05, 0.36),
					Size = UDim2.fromScale(0.88, 0.24),
					Font = Theme.Fonts.Body,
					Text = "The full pitch, the football and no clock. Work on close control, passing, shooting and first touch at your own pace.",
					TextColor3 = Theme.MutedText,
					TextSize = MenuKit.Size(mobile, 12),
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					ZIndex = 5,
				}),
				Start = React.createElement("TextButton", {
					AnchorPoint = Vector2.new(0, 1),
					Position = UDim2.fromScale(0.05, 0.9),
					Size = UDim2.fromScale(0.5, 0.2),
					BackgroundColor3 = Theme.AccentDark,
					BackgroundTransparency = 0.05,
					BorderSizePixel = 0,
					AutoButtonColor = true,
					Font = Enum.Font.GothamBold,
					Text = "START PRACTICE",
					TextColor3 = Theme.Text,
					TextSize = MenuKit.Size(mobile, 14),
					ZIndex = 5,
					[React.Event.Activated] = function()
						if props.OpenTeamSelection then
							props.OpenTeamSelection("TrainingFree")
						end
					end,
				}, {
					-- Proportional height, so no floor of its own; this is the ~48px
					-- touch target from docs/ui/UI_AGENT_DECISION_RULES.md section 8.
					MinimumHeight = ReactUI.MinimumSize(nil, Theme.MinimumTouchTarget),
					Corner = ReactUI.Corner(7),
					Stroke = ReactUI.Stroke(Theme.StrokeBright, 1.5, 0.15),
					Gradient = ReactUI.Gradient(Theme.AccentDark, Theme.AccentViolet, 20),
				}),
			}),

			--[[
				QUICK 3V3 also lives here, because it is the other mode a player can
				genuinely enter and hiding it behind PLAY only would make Training a
				dead end on a page whose own modules do not work yet.
			]]
			QuickMatch = MenuKit.Panel({
				Position = UDim2.fromScale(if mobile then 0.03 else 0.04, if mobile then 0.765 else 0.775),
				Size = UDim2.fromScale(if mobile then 0.4 else 0.36, if mobile then 0.09 else 0.085),
				Transparency = 0.2,
				ZIndex = 4,
			}, {
				Title = MenuKit.Text({
					Position = UDim2.fromScale(0.05, 0.12),
					Size = UDim2.fromScale(0.5, 0.45),
					Font = Enum.Font.GothamBold,
					Text = "QUICK 3V3",
					TextSize = MenuKit.Size(mobile, 15),
					ZIndex = 5,
				}),
				Detail = MenuKit.Text({
					Position = UDim2.fromScale(0.05, 0.55),
					Size = UDim2.fromScale(0.55, 0.36),
					Font = Theme.Fonts.Caption,
					Text = "Human-first match with AI fill",
					TextColor3 = Theme.MutedText,
					TextSize = MenuKit.Size(mobile, 10),
					ZIndex = 5,
				}),
				Play = React.createElement("TextButton", {
					AnchorPoint = Vector2.new(1, 0.5),
					Position = UDim2.fromScale(0.95, 0.5),
					Size = UDim2.fromScale(0.3, 0.6),
					BackgroundColor3 = MenuKit.PanelColor,
					BackgroundTransparency = 0.05,
					BorderSizePixel = 0,
					AutoButtonColor = true,
					Font = Theme.Fonts.Navigation,
					Text = "PLAY",
					TextColor3 = Theme.Text,
					TextSize = MenuKit.Size(mobile, 12),
					ZIndex = 5,
					[React.Event.Activated] = function()
						if props.OpenTeamSelection then
							props.OpenTeamSelection("Quick3v3")
						end
					end,
				}, {
					-- Proportional height, so no floor of its own; this is the ~48px
					-- touch target from docs/ui/UI_AGENT_DECISION_RULES.md section 8.
					MinimumHeight = ReactUI.MinimumSize(nil, Theme.MinimumTouchTarget),
					Corner = ReactUI.Corner(6),
					Stroke = ReactUI.Stroke(Theme.StrokeBright, 1.3, 0.2),
				}),
			}),

			ModulesPanel = MenuKit.Panel({
				Position = UDim2.fromScale(if mobile then 0.45 else 0.42, if mobile then 0.29 else 0.3),
				Size = UDim2.fromScale(if mobile then 0.52 else 0.54, if mobile then 0.33 else 0.34),
				Transparency = 0.16,
				ZIndex = 4,
			}, {
				Heading = React.createElement(MenuKit.PanelHeading, {
					Mobile = mobile,
					Title = "TRAINING MODULES",
					Caption = "Structured drills and per-skill progression, in a later milestone.",
					Position = UDim2.fromScale(0.03, 0.05),
					Size = UDim2.fromScale(0.94, 0.2),
					TitleSize = 15,
					ZIndex = 5,
				}),
				Grid = React.createElement("Frame", {
					Position = UDim2.fromScale(0.03, 0.28),
					Size = UDim2.fromScale(0.94, 0.66),
					BackgroundTransparency = 1,
					ZIndex = 5,
				}, moduleChildren),
			}),

			ProgressPanel = MenuKit.Panel({
				Position = UDim2.fromScale(if mobile then 0.45 else 0.42, if mobile then 0.645 else 0.66),
				Size = UDim2.fromScale(if mobile then 0.52 else 0.54, if mobile then 0.21 else 0.2),
				Transparency = 0.18,
				ZIndex = 4,
			}, {
				Heading = React.createElement(MenuKit.PanelHeading, {
					Mobile = mobile,
					Title = "TRAINING PROGRESSION",
					Position = UDim2.fromScale(0.03, 0.1),
					Size = UDim2.fromScale(0.94, 0.3),
					TitleSize = 14,
					ZIndex = 5,
				}),
				Body = MenuKit.Text({
					Position = UDim2.fromScale(0.03, 0.44),
					Size = UDim2.fromScale(0.94, 0.36),
					Font = Theme.Fonts.Caption,
					Text = "Training level, daily sessions and skill history need saved player data, which arrives with the persistence milestone. Free practice works now.",
					TextColor3 = Theme.MutedText,
					TextSize = MenuKit.Size(mobile, 11),
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					ZIndex = 5,
				}),
			}),
		},
	})
end

return TrainingScreen
