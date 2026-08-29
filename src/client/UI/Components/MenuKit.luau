--!strict
--[[
	The shared vocabulary of the Beyond 90 menu family (§12-§17).

	Every one of the five redesigned pages -- Play, Training, Clubs, Profile,
	Settings -- is built out of the pieces in here rather than each screen
	inventing its own panels and spacing. That is what makes them read as one
	product: the mockups share a single design language, and reproducing that
	language once is the only way five separately-authored screens stay
	consistent as they change.

	RESPONSIVENESS (§17). Mobile is the desktop design RESCALED, never a
	different layout. Every component takes `Mobile` and adjusts type size,
	padding and density from it; the composition -- where things are, what is
	next to what -- is identical. A 780x360 landscape phone gets the same page,
	smaller.

	Nothing here talks to a service or holds state. Screens own their data; this
	owns how it looks.
]]
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Shared.ReactPackages).React
local Assets = require(ReplicatedStorage.Shared.Config.UIAssetConfig)
local Theme = require(script.Parent.Parent.Theme)
local ReactUI = require(script.Parent.ReactUI)
local MenuFooter = require(script.Parent.MenuFooter)

local localPlayer = Players.LocalPlayer

local MenuKit = {}

MenuKit.PanelColor = Color3.fromRGB(10, 16, 38)
MenuKit.PanelStroke = Color3.fromRGB(38, 56, 104)

--[[
	Scale a desktop size for the current viewport.

	One helper rather than `if mobile then a else b` scattered through every
	label, so the whole family shrinks by the same ratio and the hierarchy
	between heading, body and caption survives the change of screen.
]]
function MenuKit.Size(mobile: boolean, desktop: number): number
	return if mobile then math.max(math.floor(desktop * 0.66), 7) else desktop
end

--[[
	A dark translucent card. The base surface of every panel in the mockups.

	Its OWN props are listed explicitly and stripped before the rest are forwarded
	to the Frame. React applies every remaining key directly as an Instance
	property, so leaking one of these through does not degrade -- it throws
	"Radius is not a valid member of Frame" and takes the whole tree down with it.
]]
local PANEL_OWN_PROPS = {
	Transparency = true,
	Color = true,
	Radius = true,
	StrokeColor = true,
	StrokeTransparency = true,
}

function MenuKit.Panel(props, children)
	local merged = {
		BackgroundColor3 = props.Color or MenuKit.PanelColor,
		BackgroundTransparency = props.Transparency or 0.14,
		BorderSizePixel = 0,
	}
	for key, value in props do
		if not PANEL_OWN_PROPS[key] then
			merged[key] = value
		end
	end
	children = children or {}
	children.Corner = children.Corner or ReactUI.Corner(props.Radius or 8)
	children.Stroke = children.Stroke
		or ReactUI.Stroke(props.StrokeColor or MenuKit.PanelStroke, 1, props.StrokeTransparency or 0.35)
	return React.createElement("Frame", merged, children)
end

function MenuKit.Text(props)
	local merged = {
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Body,
		TextColor3 = Theme.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
	}
	for key, value in props do
		merged[key] = value
	end
	return React.createElement("TextLabel", merged)
end

--[[
	A panel heading: a title with an optional caption beneath it, matching the
	"GRAPHICS QUALITY / Adjust overall graphic quality" pattern the mockups use
	at the top of every panel.
]]
function MenuKit.PanelHeading(props)
	local mobile = props.Mobile == true
	return React.createElement("Frame", {
		Position = props.Position or UDim2.fromScale(0.04, 0.05),
		Size = props.Size or UDim2.fromScale(0.92, 0.2),
		BackgroundTransparency = 1,
		ZIndex = props.ZIndex or 3,
	}, {
		Title = MenuKit.Text({
			Size = UDim2.fromScale(1, if props.Caption then 0.55 else 1),
			Font = Theme.Fonts.Heading,
			Text = props.Title,
			TextSize = MenuKit.Size(mobile, props.TitleSize or 17),
			ZIndex = props.ZIndex or 3,
		}),
		Caption = props.Caption and MenuKit.Text({
			Position = UDim2.fromScale(0, 0.56),
			Size = UDim2.fromScale(1, 0.44),
			Font = Theme.Fonts.Caption,
			Text = props.Caption,
			TextColor3 = Theme.MutedText,
			TextSize = MenuKit.Size(mobile, 11),
			ZIndex = props.ZIndex or 3,
		}) or nil,
	})
end

--[[
	A filled progress bar with a gradient, used for XP, division progress and
	training module completion. Fill is 0-1 and is clamped, so a caller that
	reports 1400/1400 cannot overflow the track.
]]
function MenuKit.ProgressBar(props)
	local fill = math.clamp(props.Fill or 0, 0, 1)
	return React.createElement("Frame", {
		AnchorPoint = props.AnchorPoint,
		Position = props.Position,
		Size = props.Size,
		BackgroundColor3 = Color3.fromRGB(24, 33, 62),
		BorderSizePixel = 0,
		ZIndex = props.ZIndex or 3,
	}, {
		Corner = ReactUI.Corner(20),
		Fill = React.createElement("Frame", {
			Size = UDim2.fromScale(fill, 1),
			BackgroundColor3 = props.Color or Theme.Accent,
			BorderSizePixel = 0,
			ZIndex = (props.ZIndex or 3) + 1,
			-- A zero-width frame still renders its corner as a dot; hide it.
			Visible = fill > 0.001,
		}, {
			Corner = ReactUI.Corner(20),
			Gradient = ReactUI.Gradient(
				props.GradientStart or Theme.AccentCyan,
				props.GradientEnd or Theme.AccentViolet
			),
		}),
	})
end

--[[
	A statistic tile: a large number over a small caption.

	The repeating unit of the Profile mockup's PLAYER STATS grid, and used for
	the Clubs activity strip too.
]]
function MenuKit.StatTile(props)
	local mobile = props.Mobile == true
	return MenuKit.Panel({
		LayoutOrder = props.Order,
		Size = props.Size or UDim2.fromScale(0.32, 1),
		Transparency = 0.2,
		Radius = 6,
		ZIndex = props.ZIndex or 3,
	}, {
		Value = MenuKit.Text({
			Position = UDim2.fromScale(0, 0.16),
			Size = UDim2.fromScale(1, 0.42),
			Font = Enum.Font.GothamBold,
			Text = props.Value,
			TextSize = MenuKit.Size(mobile, props.ValueSize or 24),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = (props.ZIndex or 3) + 1,
		}),
		Caption = MenuKit.Text({
			Position = UDim2.fromScale(0, 0.6),
			Size = UDim2.fromScale(1, 0.26),
			Font = Theme.Fonts.Caption,
			Text = props.Caption,
			TextColor3 = Theme.MutedText,
			TextSize = MenuKit.Size(mobile, 10),
			TextXAlignment = Enum.TextXAlignment.Center,
			ZIndex = (props.ZIndex or 3) + 1,
		}),
	})
end

--[[
	The page title block at the top left of every mockup: a big word, a line of
	explanation, sometimes an eyebrow above it.
]]
function MenuKit.PageTitle(props)
	local mobile = props.Mobile == true
	return React.createElement("Frame", {
		Position = props.Position or UDim2.fromScale(if mobile then 0.03 else 0.045, if mobile then 0.2 else 0.235),
		Size = props.Size or UDim2.fromScale(0.4, 0.16),
		BackgroundTransparency = 1,
		ZIndex = props.ZIndex or 4,
	}, {
		Eyebrow = props.Eyebrow and MenuKit.Text({
			Size = UDim2.fromScale(1, 0.2),
			Font = Enum.Font.GothamBold,
			Text = props.Eyebrow,
			TextColor3 = Theme.AccentCyan,
			TextSize = MenuKit.Size(mobile, 13),
			ZIndex = props.ZIndex or 4,
		}) or nil,
		Title = MenuKit.Text({
			Position = UDim2.fromScale(0, if props.Eyebrow then 0.2 else 0),
			Size = UDim2.fromScale(1, 0.5),
			Font = Enum.Font.GothamBlack,
			Text = props.Title,
			TextSize = MenuKit.Size(mobile, props.TitleSize or 40),
			ZIndex = props.ZIndex or 4,
		}),
		Caption = props.Caption and MenuKit.Text({
			Position = UDim2.fromScale(0, if props.Eyebrow then 0.72 else 0.54),
			Size = UDim2.fromScale(1.4, 0.26),
			Font = Theme.Fonts.Body,
			Text = props.Caption,
			TextColor3 = Theme.MutedText,
			TextSize = MenuKit.Size(mobile, 13),
			TextWrapped = true,
			ZIndex = props.ZIndex or 4,
		}) or nil,
	})
end

--[[
	The account chip and currency strip that sit at the top right of every
	mockup.

	The player's real name and avatar are used. Everything else -- level, XP,
	currency -- is presentation with NO backing system yet (§15): it is rendered
	from the constants passed in rather than invented here, so when a real
	profile service exists there is exactly one place to connect it.
]]
function MenuKit.AccountStrip(props)
	local mobile = props.Mobile == true
	local portrait = props.Portrait or ""
	return React.createElement("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex = props.ZIndex or 6,
	}, {
		Currency = MenuKit.Panel({
			Position = UDim2.fromScale(if mobile then 0.575 else 0.655, 0.018),
			Size = UDim2.fromScale(if mobile then 0.18 else 0.14, if mobile then 0.075 else 0.055),
			Transparency = 0.08,
			ZIndex = props.ZIndex or 6,
		}, {
			B90Icon = React.createElement("ImageLabel", {
				Position = UDim2.fromScale(0.05, 0.18), Size = UDim2.fromScale(0.16, 0.64),
				BackgroundTransparency = 1, Image = Assets.Currency.B90, ScaleType = Enum.ScaleType.Fit,
				ZIndex = (props.ZIndex or 6) + 1,
			}),
			B90 = MenuKit.Text({
				Position = UDim2.fromScale(0.23, 0.18), Size = UDim2.fromScale(0.28, 0.64),
				Font = Theme.Fonts.Statistics, Text = props.SoftCurrency or "0", TextScaled = true,
				ZIndex = (props.ZIndex or 6) + 1,
			}),
			PremiumIcon = React.createElement("ImageLabel", {
				Position = UDim2.fromScale(0.57, 0.18), Size = UDim2.fromScale(0.14, 0.64),
				BackgroundTransparency = 1, Image = Assets.Currency.Premium, ScaleType = Enum.ScaleType.Fit,
				ZIndex = (props.ZIndex or 6) + 1,
			}),
			Premium = MenuKit.Text({
				Position = UDim2.fromScale(0.73, 0.18), Size = UDim2.fromScale(0.23, 0.64),
				Font = Theme.Fonts.Statistics, Text = props.HardCurrency or "0", TextScaled = true,
				ZIndex = (props.ZIndex or 6) + 1,
			}),
		}),
		Account = MenuKit.Panel({
			Position = UDim2.fromScale(if mobile then 0.77 else 0.81, 0.018),
			Size = UDim2.fromScale(if mobile then 0.21 else 0.17, if mobile then 0.09 else 0.075),
			Transparency = 0.08,
			ZIndex = props.ZIndex or 6,
		}, {
			Avatar = React.createElement("ImageLabel", {
				Position = UDim2.fromScale(0.03, 0.08), Size = UDim2.fromScale(0.2, 0.84),
				BackgroundTransparency = 1, Image = portrait, ScaleType = Enum.ScaleType.Crop,
				ZIndex = (props.ZIndex or 6) + 1,
			}, { Corner = ReactUI.Corner(40), Stroke = ReactUI.Stroke(Theme.AccentViolet, 1.5) }),
			Name = MenuKit.Text({
				Position = UDim2.fromScale(0.27, 0.12), Size = UDim2.fromScale(0.68, 0.3),
				Font = Theme.Fonts.Navigation, Text = localPlayer.DisplayName, TextScaled = true,
				ZIndex = (props.ZIndex or 6) + 1,
			}),
			Level = MenuKit.Text({
				Position = UDim2.fromScale(0.27, 0.45), Size = UDim2.fromScale(0.68, 0.2),
				Text = props.LevelText or "LEVEL 1", TextColor3 = Theme.MutedText, TextScaled = true,
				ZIndex = (props.ZIndex or 6) + 1,
			}),
			XP = MenuKit.ProgressBar({
				Position = UDim2.fromScale(0.27, 0.76), Size = UDim2.fromScale(0.64, 0.07),
				Fill = props.LevelProgress or 0, ZIndex = (props.ZIndex or 6) + 1,
			}),
		}),
	})
end

--[[
	The persistent bottom navigation from the Training / Clubs / Profile /
	Settings mockups: five destinations, the current one highlighted.
]]
function MenuKit.BottomNav(props)
	local mobile = props.Mobile == true
	local entries = {
		{ Id = "Play", Title = "PLAY", Detail = "Jump into matches\nCompete and win", Icon = Assets.Navigation.Play },
		{ Id = "Training", Title = "TRAINING", Detail = "Improve your skills\nMaster the pitch", Icon = Assets.Navigation.Training },
		{ Id = "Clubs", Title = "CLUBS", Detail = "Join or create a club\nPlay together", Icon = Assets.Navigation.Clubs },
		{ Id = "Profile", Title = "PROFILE", Detail = "View stats and progression\nCustomize your identity", Icon = Assets.Navigation.Profile },
		{ Id = "Settings", Title = "SETTINGS", Detail = "Game settings\nand preferences", Icon = Assets.Navigation.Settings },
	}

	local children = {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0.012, 0),
		}),
	}

	for index, entry in entries do
		local selected = props.Current == entry.Id
		children[entry.Id] = React.createElement("TextButton", {
			LayoutOrder = index,
			Size = UDim2.fromScale(0.19, 1),
			BackgroundColor3 = if selected then Theme.PanelSelected else MenuKit.PanelColor,
			BackgroundTransparency = if selected then 0.05 else 0.2,
			BorderSizePixel = 0,
			AutoButtonColor = true,
			Text = "",
			ZIndex = props.ZIndex or 6,
			[React.Event.Activated] = function()
				if props.Navigate then
					props.Navigate(entry.Id)
				end
			end,
		}, {
			Corner = ReactUI.Corner(8),
			Stroke = ReactUI.Stroke(
				if selected then Theme.StrokeBright else MenuKit.PanelStroke,
				if selected then 1.6 else 1,
				if selected then 0.1 else 0.4
			),
			Icon = React.createElement("ImageLabel", {
				AnchorPoint = Vector2.new(0, 0.5),
				Position = UDim2.fromScale(0.06, 0.5),
				Size = UDim2.fromScale(0.2, 0.56),
				BackgroundTransparency = 1,
				Image = entry.Icon,
				ImageTransparency = if selected then 0 else 0.25,
				ScaleType = Enum.ScaleType.Fit,
				ZIndex = (props.ZIndex or 6) + 1,
			}),
			Title = MenuKit.Text({
				Position = UDim2.fromScale(0.31, if mobile then 0.16 else 0.2),
				Size = UDim2.fromScale(0.65, 0.28),
				Font = Theme.Fonts.Heading,
				Text = entry.Title,
				TextColor3 = if selected then Theme.Text else Color3.fromRGB(214, 224, 244),
				TextSize = MenuKit.Size(mobile, 17),
				ZIndex = (props.ZIndex or 6) + 1,
			}),
			--[[
				The two-line description is dropped on mobile. At 780x360 a nav
				tile is barely 140px wide, and forcing the caption in makes both
				it and the title unreadable; the icon and title alone still
				identify the destination.
			]]
			Detail = (not mobile) and MenuKit.Text({
				Position = UDim2.fromScale(0.31, 0.48),
				Size = UDim2.fromScale(0.66, 0.4),
				Font = Theme.Fonts.Caption,
				Text = entry.Detail,
				TextColor3 = Theme.MutedText,
				TextSize = 11,
				ZIndex = (props.ZIndex or 6) + 1,
			}) or nil,
		})
	end

	return React.createElement("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.fromScale(0.5, if mobile then 0.985 else 0.975),
		Size = UDim2.fromScale(if mobile then 0.98 else 0.94, if mobile then 0.15 else 0.115),
		BackgroundTransparency = 1,
		ZIndex = props.ZIndex or 6,
	}, children)
end

--[[
	The page shell.

	Stadium background, darkening wash, wordmark, account strip, bottom
	navigation and control-hint footer -- everything the five mockups share --
	so a page only has to describe its own content.

	`Content` is the page body. `Current` names the highlighted nav entry.
]]
--[[
	BACK, not a navigation bar.

	The five-way navigation belongs to the main menu, and only there. Repeating
	it on every sub-page meant Settings offered a button back to Settings, and it
	took the entire bottom band of the screen on pages whose content was already
	squeezed into the middle.

	A single Back button replaces it. It sits where the navigation used to start,
	so the eye already knows to look there, and it frees roughly a fifth of the
	page height for the content itself.
]]
function MenuKit.BackButton(props)
	local mobile = props.Mobile == true

	return React.createElement("TextButton", {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(if mobile then 0.03 else 0.04, if mobile then 0.955 else 0.965),
		Size = UDim2.fromScale(if mobile then 0.2 else 0.115, if mobile then 0.075 else 0.062),
		BackgroundColor3 = MenuKit.PanelColor,
		BackgroundTransparency = 0.12,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Text = "",
		ZIndex = props.ZIndex or 6,
		[React.Event.Activated] = function()
			if props.Activate then
				props.Activate()
			end
		end,
	}, {
		Corner = ReactUI.Corner(8),
		Stroke = ReactUI.Stroke(MenuKit.PanelStroke, 1, 0.35),
		Arrow = MenuKit.Text({
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0.1, 0.5),
			Size = UDim2.fromScale(0.2, 0.6),
			Font = Theme.Fonts.Navigation,
			Text = "\u{2190}",
			TextColor3 = Theme.AccentCyan,
			TextSize = MenuKit.Size(mobile, 18),
			ZIndex = (props.ZIndex or 6) + 1,
		}),
		Label = MenuKit.Text({
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.fromScale(0.34, 0.5),
			Size = UDim2.fromScale(0.6, 0.6),
			Font = Theme.Fonts.Heading,
			Text = "BACK",
			TextColor3 = Theme.Text,
			TextSize = MenuKit.Size(mobile, 15),
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = (props.ZIndex or 6) + 1,
		}),
	})
end

function MenuKit.Shell(props)
	local mobile = props.Mobile == true
	local menuPrompt = props.MenuPrompt or {}
	-- Shell pages always carry a Back button, so they never show the
	-- conflicting Select/Open Menu footer hints (§14).
	props = table.clone(props)
	props.HideFooterHints = true

	return React.createElement("Frame", {
		Name = props.Name or "MenuPage",
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
		}),
		--[[
			The wash is what makes text legible over a photographic stadium and is
			the single strongest reason the mockups read as one product. Darkest in
			the middle band, where the content panels sit.
		]]
		Shade = React.createElement("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Theme.Background,
			BackgroundTransparency = 0.42,
			BorderSizePixel = 0,
			ZIndex = 1,
		}, {
			Gradient = React.createElement("UIGradient", {
				Color = ColorSequence.new(Color3.fromRGB(4, 8, 25), Color3.fromRGB(3, 7, 19)),
				Rotation = 90,
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.28),
					NumberSequenceKeypoint.new(0.5, 0.1),
					NumberSequenceKeypoint.new(1, 0),
				}),
			}),
		}),
		Logo = React.createElement("ImageLabel", {
			Position = UDim2.fromScale(if mobile then 0.025 else 0.04, if mobile then 0.03 else 0.045),
			Size = UDim2.fromScale(if mobile then 0.3 else 0.3, if mobile then 0.15 else 0.17),
			BackgroundTransparency = 1,
			Image = Assets.Logo,
			-- The source has the subtitle baked in below the mark; this rectangle
			-- is the mark itself.
			ImageRectOffset = Vector2.new(20, 175),
			ImageRectSize = Vector2.new(1000, 300),
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = 4,
		}),
		Account = React.createElement(MenuKit.AccountStrip, {
			Mobile = mobile,
			Portrait = props.Portrait,
			LevelText = props.LevelText,
			LevelProgress = props.LevelProgress,
			SoftCurrency = props.SoftCurrency,
			HardCurrency = props.HardCurrency,
			ZIndex = 6,
		}),
		Content = React.createElement("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			ZIndex = 3,
		}, props.Content),
		Back = React.createElement(MenuKit.BackButton, {
			Mobile = mobile,
			ZIndex = 6,
			Activate = function()
				if props.OnBack then
					props.OnBack()
				elseif props.Navigate then
					props.Navigate("Home")
				end
			end,
		}),
		Footer = React.createElement(MenuFooter.Root, {
			Mobile = mobile,
			DesktopTop = 0.88,
			DesktopHeight = 0.12,
			DesktopFadeHeight = 0.2,
			RootZIndex = 2,
			FadeZIndex = 2,
			Content = React.createElement("Frame", {
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
			}, {
				--[[
					The same control hints the Home screen uses, following the
					player's chosen scheme (§9). Placed at the very bottom edge,
					below the navigation, exactly as the mockups have them.
				]]
				--[[
					A screen with a Back button does not also get Select and Open
					Menu hints (§14).

					All three previously shared the bottom band, so submenus showed
					a Back button and two footer prompts stacked into the same
					strip. The Back button IS the return control on these screens,
					so the hints are removed rather than nudged aside.
				]]
				SelectPrompt = (not props.HideFooterHints) and React.createElement(MenuFooter.Prompt, {
					Mobile = mobile,
					Position = UDim2.fromScale(if mobile then 0.02 else 0.03, 0.02),
					Image = if menuPrompt.SelectImageKey then Assets.Menu[menuPrompt.SelectImageKey] else "",
					Fallback = menuPrompt.Select,
					Label = "SELECT",
					ZIndex = 5,
				}) or nil,
				BackPrompt = (not props.HideFooterHints) and React.createElement(MenuFooter.Prompt, {
					Mobile = mobile,
					Position = UDim2.fromScale(if mobile then 0.11 else 0.13, 0.02),
					Image = if menuPrompt.BackImageKey then Assets.Menu[menuPrompt.BackImageKey] else "",
					Fallback = menuPrompt.Back,
					Label = "BACK",
					ZIndex = 5,
				}) or nil,
			}),
		}),
	})
end

--[[
	Where a page's content band sits.

	Below the wordmark and account strip, above the bottom navigation. Returned
	as a helper so the five pages cannot drift apart vertically.
]]
function MenuKit.ContentBand(mobile: boolean): (UDim2, UDim2)
	if mobile then
		return UDim2.fromScale(0.5, 0.46), UDim2.fromScale(0.95, 0.52)
	end
	return UDim2.fromScale(0.5, 0.47), UDim2.fromScale(0.93, 0.5)
end

function MenuKit.IsMobile(): boolean
	local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize
	if viewport and viewport.X < 900 then
		return true
	end
	local _, inset = GuiService:GetGuiInset()
	return inset.Y > 0 and viewport ~= nil and viewport.X < 1100
end

return MenuKit
