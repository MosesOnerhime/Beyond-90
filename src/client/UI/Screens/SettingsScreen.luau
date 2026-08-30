--!strict
--[[
	SETTINGS (§16), following assets/UI_assets/mockup_settings.png.

	The mockup's structure is reproduced: a category list down the left, and a
	grid of setting panels filling the rest of the page, each with a title, a
	caption and a column of labelled rows.

	EVERY WORKING SETTING IS PRESERVED (§16).

	The three that genuinely do something today are all still here and all still
	wired to the same callbacks:

		Control scheme  -> props.SetControlScheme (keyboard / gamepad, §10)
		Menu music      -> props.SetMusicEnabled
		Menu track      -> props.SetTrack

	No functionality was removed to make the page match the mockup. The mockup
	shows many more settings than Beyond 90 has -- graphics presets, volume
	sliders, camera height, match difficulty, accessibility options. Those are
	drawn in their proper places and marked unavailable rather than being given
	controls that move but change nothing, which would be worse than not showing
	them at all.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Shared.ReactPackages).React
local AudioConfig = require(ReplicatedStorage.Shared.Config.AudioConfig)
local Theme = require(script.Parent.Parent.Theme)
local ReactUI = require(script.Parent.Parent.Components.ReactUI)
local MenuKit = require(script.Parent.Parent.Components.MenuKit)
local CameraConfig = require(ReplicatedStorage.Shared.Config.CameraConfig)
local PlayerConfig = require(ReplicatedStorage.Shared.Config.PlayerConfig)
local ControlSchemeScreen = require(script.Parent.ControlSchemeScreen)
local ControlSchemeConfig = require(ReplicatedStorage.Shared.Config.ControlSchemeConfig)

--[[
	A setting row: a label on the left and a control on the right.

	`Enabled` is what separates a real setting from a placeholder. A disabled row
	is dimmed and its control is inert and labelled, so a player is never invited
	to change something that does nothing.
]]
local function SettingRow(props)
	local mobile = props.Mobile == true
	local enabled = props.Enabled == true
	return React.createElement("Frame", {
		LayoutOrder = props.Order,
		Size = UDim2.new(1, 0, 0, if mobile then 22 else 30),
		BackgroundTransparency = 1,
		ZIndex = 5,
	}, {
		Label = MenuKit.Text({
			Position = UDim2.fromScale(0, 0),
			Size = UDim2.fromScale(0.55, 1),
			Font = Theme.Fonts.Body,
			Text = props.Label,
			TextColor3 = if enabled then Theme.Text else Theme.FaintText,
			TextSize = MenuKit.Size(mobile, 12),
			ZIndex = 6,
		}),
		Control = props.Control or MenuKit.Text({
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.fromScale(0.44, 1),
			Font = Theme.Fonts.Statistics,
			Text = props.Value or "NOT AVAILABLE",
			TextColor3 = if enabled then Theme.AccentCyan else Theme.FaintText,
			TextSize = MenuKit.Size(mobile, 11),
			TextXAlignment = Enum.TextXAlignment.Right,
			ZIndex = 6,
		}),
	})
end

-- A two-state control that genuinely toggles something.
local function Toggle(props)
	local mobile = props.Mobile == true
	local on = props.On == true
	return React.createElement("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.fromScale(1, 0.5),
		Size = UDim2.fromScale(0.38, 0.78),
		BackgroundColor3 = if on then Theme.AccentDark else MenuKit.PanelColor,
		BackgroundTransparency = 0.08,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Font = Theme.Fonts.Statistics,
		Text = if on then "ON" else "OFF",
		TextColor3 = if on then Theme.Text else Theme.MutedText,
		TextSize = MenuKit.Size(mobile, 11),
		ZIndex = 6,
		[React.Event.Activated] = props.Activate,
	}, {
		Corner = ReactUI.Corner(5),
		Stroke = ReactUI.Stroke(if on then Theme.StrokeBright else MenuKit.PanelStroke, 1.2, 0.3),
	})
end

local function CategoryButton(props)
	local mobile = props.Mobile == true
	local selected = props.Selected == true
	return React.createElement("TextButton", {
		LayoutOrder = props.Order,
		Size = UDim2.new(1, 0, 0, if mobile then 26 else 40),
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
		Title = MenuKit.Text({
			Position = UDim2.fromScale(0.08, if mobile then 0 else 0.12),
			Size = UDim2.fromScale(0.88, if mobile then 1 else 0.45),
			Font = Theme.Fonts.Navigation,
			Text = props.Title,
			TextColor3 = if selected then Theme.Text else Theme.MutedText,
			TextSize = MenuKit.Size(mobile, 14),
			ZIndex = 6,
		}),
		Caption = (not mobile) and MenuKit.Text({
			Position = UDim2.fromScale(0.08, 0.55),
			Size = UDim2.fromScale(0.88, 0.35),
			Font = Theme.Fonts.Caption,
			Text = props.Caption,
			TextColor3 = Theme.FaintText,
			TextSize = 10,
			ZIndex = 6,
		}) or nil,
	})
end

return function(props)
	local mobile = props.Mobile == true
	local musicOn = props.MusicEnabled ~= false
	local musicVolume = math.clamp(
		if typeof(props.MusicVolume) == "number" then props.MusicVolume else AudioConfig.Music.DefaultVolume,
		AudioConfig.Music.Minimum,
		AudioConfig.Music.Maximum
	)

	local categories = {
		{ Title = "CONTROLS", Caption = "Input and key bindings" },
		{ Title = "AUDIO", Caption = "Sound and volume" },
		{ Title = "CAMERA", Caption = "Camera and view settings" },
		{ Title = "GAMEPLAY", Caption = "Match and game options" },
		{ Title = "FOOTBALLER", Caption = "Who you play as" },
	}
	local selectedCategory, setSelectedCategory = React.useState(1)

	--[[
		ONE CATEGORY AT A TIME.

		Every panel used to be on screen simultaneously, tiled into quadrants,
		while the category list on the left only highlighted itself -- so
		choosing CONTROLS did nothing except move a highlight, and each panel was
		stuck at roughly a third of the page whether it needed that much room or
		not. That is what made the page feel cluttered.

		Now the list selects, and the right-hand side is a single region that the
		chosen category fills. Every panel shares this geometry and only the
		selected one is visible, so a category with a lot to show (CONTROLS) gets
		the whole area instead of a quarter of it.
	]]
	--[[
		The camera choices, rendered as a row of selectable chips. Uses the
		shared surface/stroke treatment rather than a new control type, per the
		design rules' "reuse before create".
	]]
	local cameraChoiceChildren = {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, if mobile then 5 else 8),
		}),
	}
	for index, entry in CameraConfig.SelectableModes do
		local selected = props.DefaultCamera == entry.Id
		cameraChoiceChildren[entry.Id] = React.createElement("TextButton", {
			LayoutOrder = index,
			Size = UDim2.fromScale(0.32, 1),
			BackgroundColor3 = if selected then Theme.PanelSelected else MenuKit.PanelColor,
			BackgroundTransparency = if selected then 0.05 else 0.3,
			BorderSizePixel = 0,
			AutoButtonColor = true,
			Font = Theme.Fonts.Navigation,
			Text = entry.Label,
			TextColor3 = if selected then Theme.AccentCyan else Theme.Text,
			TextSize = MenuKit.Size(mobile, 12),
			ZIndex = 6,
			[React.Event.Activated] = function()
				if props.SetDefaultCamera then
					props.SetDefaultCamera(entry.Id)
				end
			end,
		}, {
			Corner = ReactUI.Corner(6),
			Stroke = ReactUI.Stroke(
				if selected then Theme.StrokeBright else MenuKit.PanelStroke,
				if selected then 1.4 else 1,
				if selected then 0.15 else 0.45
			),
		})
	end

	--[[
		YOUR FOOTBALLER (§23-§29).

		Same chip treatment as the camera row above, because it is the same kind
		of choice: a small set of named options, one selected. Reuse before
		create.

		The caption matters as much as the control here. Players will reasonably
		expect their avatar to arrive at its own size, and it does not -- every
		footballer is scaled to the same frame so that nobody buys a longer
		stride in the avatar shop. Saying so plainly is better than letting them
		wonder why they look shorter than they expect.
	]]
	local avatarChoiceChildren = {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			SortOrder = Enum.SortOrder.LayoutOrder,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, if mobile then 5 else 8),
		}),
	}
	local avatarOptions = {
		{ Id = PlayerConfig.Appearance.Identity.Sources.RobloxAvatar, Label = "MY ROBLOX AVATAR" },
		{ Id = PlayerConfig.Appearance.Identity.Sources.Beyond90Avatar, Label = "BEYOND 90 KIT" },
	}
	for index, entry in avatarOptions do
		local selected = props.AvatarSource == entry.Id
		avatarChoiceChildren[entry.Id] = React.createElement("TextButton", {
			LayoutOrder = index,
			Size = UDim2.fromScale(0.48, 1),
			BackgroundColor3 = if selected then Theme.PanelSelected else MenuKit.PanelColor,
			BackgroundTransparency = if selected then 0.05 else 0.3,
			BorderSizePixel = 0,
			AutoButtonColor = true,
			Font = Theme.Fonts.Navigation,
			Text = entry.Label,
			TextColor3 = if selected then Theme.AccentCyan else Theme.Text,
			TextSize = MenuKit.Size(mobile, 12),
			ZIndex = 6,
			[React.Event.Activated] = function()
				if props.SetAvatarSource then
					props.SetAvatarSource(entry.Id)
				end
			end,
		}, {
			Corner = ReactUI.Corner(6),
			Stroke = ReactUI.Stroke(
				if selected then Theme.StrokeBright else MenuKit.PanelStroke,
				if selected then 1.4 else 1,
				if selected then 0.15 else 0.45
			),
		})
	end

	local panelPosition = UDim2.fromScale(if mobile then 0.25 else 0.23, if mobile then 0.3 else 0.3)
	local panelSize = UDim2.fromScale(if mobile then 0.72 else 0.73, if mobile then 0.52 else 0.5)

	local categoryChildren = {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, if mobile then 4 else 7),
		}),
	}
	for index, entry in categories do
		categoryChildren[entry.Title] = React.createElement(CategoryButton, {
			Order = index,
			Mobile = mobile,
			Title = entry.Title,
			Caption = entry.Caption,
			Selected = selectedCategory == index,
			Activate = function()
				setSelectedCategory(index)
			end,
		})
	end

	--[[
		Menu track list. A real, working setting -- the same one that existed
		before -- restyled to match the mockup's row treatment.
	]]
	local trackRows = {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, if mobile then 3 else 5),
		}),
	}
	for index, track in AudioConfig.MenuTracks do
		local selected = props.SelectedTrack == index
		trackRows["Track" .. index] = React.createElement("TextButton", {
			LayoutOrder = index,
			Size = UDim2.new(1, 0, 0, if mobile then 20 else 27),
			BackgroundColor3 = if selected then Theme.PanelSelected else MenuKit.PanelColor,
			BackgroundTransparency = if selected then 0.05 else 0.3,
			BorderSizePixel = 0,
			AutoButtonColor = true,
			Font = Theme.Fonts.Navigation,
			Text = track.Name,
			TextColor3 = if selected then Theme.AccentCyan else Theme.Text,
			TextSize = MenuKit.Size(mobile, 12),
			ZIndex = 5,
			[React.Event.Activated] = function()
				if props.SetTrack then
					props.SetTrack(index)
				end
			end,
		}, {
			Corner = ReactUI.Corner(5),
			Stroke = ReactUI.Stroke(
				if selected then Theme.StrokeBright else MenuKit.PanelStroke,
				if selected then 1.4 else 1,
				if selected then 0.15 else 0.45
			),
		})
	end

	return React.createElement(MenuKit.Shell, {
		Name = "Settings",
		Mobile = mobile,
		Current = "Settings",
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
				Title = "SETTINGS",
				Caption = "Customize your experience.",
				TitleSize = 32,
				Position = UDim2.fromScale(if mobile then 0.03 else 0.04, if mobile then 0.19 else 0.2),
				Size = UDim2.fromScale(0.28, if mobile then 0.14 else 0.12),
			}),

			-- Aligned with the content region so the list and the panel share a
			-- top edge instead of floating at different heights.
			Categories = React.createElement("Frame", {
				Position = UDim2.fromScale(if mobile then 0.03 else 0.04, if mobile then 0.3 else 0.3),
				Size = UDim2.fromScale(if mobile then 0.19 else 0.16, if mobile then 0.52 else 0.5),
				BackgroundTransparency = 1,
				ZIndex = 4,
			}, categoryChildren),

			--[[
				CONTROLS -- a real setting.

				The same two scheme cards as the first-run prompt, so the choice
				looks identical wherever it is made, and it can be changed at any
				time. Touch has no choice to offer, so the panel explains the touch
				controls instead of showing an inert picker.
			]]
			ControlsPanel = MenuKit.Panel({
				Position = panelPosition,
				Size = panelSize,
				Visible = selectedCategory == 1,
				Transparency = 0.14,
				ZIndex = 4,
			}, {
				Heading = React.createElement(MenuKit.PanelHeading, {
					Mobile = mobile,
					Title = "CONTROLS",
					Caption = "Choose your control scheme.",
					Position = UDim2.fromScale(0.05, 0.05),
					Size = UDim2.fromScale(0.9, 0.2),
					ZIndex = 5,
				}),
				Picker = (not mobile and props.SetControlScheme) and React.createElement(ControlSchemeScreen, {
					Embedded = true,
					Position = UDim2.fromScale(0.05, 0.28),
					Size = UDim2.fromScale(0.9, 0.66),
					ZIndex = 5,
					Selected = props.ControlScheme,
					Select = props.SetControlScheme,
				}) or nil,
				TouchNote = mobile and MenuKit.Text({
					Position = UDim2.fromScale(0.05, 0.3),
					Size = UDim2.fromScale(0.9, 0.6),
					Font = Theme.Fonts.Caption,
					Text = ControlSchemeConfig.Display.Touch.Summary,
					TextColor3 = Theme.MutedText,
					TextSize = MenuKit.Size(mobile, 11),
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					ZIndex = 5,
				}) or nil,
			}),

			--[[
				AUDIO -- menu music and track selection are real; the per-channel
				volume sliders in the mockup have no mixer behind them yet.
			]]
			AudioPanel = MenuKit.Panel({
				Position = panelPosition,
				Size = panelSize,
				Visible = selectedCategory == 2,
				Transparency = 0.14,
				ZIndex = 4,
			}, {
				Heading = React.createElement(MenuKit.PanelHeading, {
					Mobile = mobile,
					Title = "AUDIO",
					Caption = "Menu music and volume levels.",
					Position = UDim2.fromScale(0.05, 0.05),
					Size = UDim2.fromScale(0.9, 0.2),
					ZIndex = 5,
				}),
				MusicRow = React.createElement("Frame", {
					Position = UDim2.fromScale(0.05, 0.29),
					Size = UDim2.fromScale(0.9, 0.13),
					BackgroundTransparency = 1,
					ZIndex = 5,
				}, {
					Label = MenuKit.Text({
						Size = UDim2.fromScale(0.55, 1),
						Text = "Menu Music",
						TextSize = MenuKit.Size(mobile, 12),
						ZIndex = 6,
					}),
					Control = React.createElement(Toggle, {
						Mobile = mobile,
						On = musicOn,
						Activate = function()
							if props.SetMusicEnabled then
								props.SetMusicEnabled(not musicOn)
							end
						end,
					}),
				}),
				--[[
					MUSIC VOLUME.

					The panel heading has promised "volume levels" all along while
					offering only an on/off switch, so a player who found the music
					too loud had exactly one option: silence. The percentage is
					shown beside the label because a bare track gives no way to
					tell 30% from 35% at a glance, and this is a value people set
					once and want to be able to return to.

					Dimmed and non-interactive when the music is off, rather than
					hidden -- a control that vanishes is harder to find again than
					one that is visibly unavailable.
				]]
				VolumeRow = React.createElement("Frame", {
					Position = UDim2.fromScale(0.05, 0.44),
					Size = UDim2.fromScale(0.9, 0.13),
					BackgroundTransparency = 1,
					ZIndex = 5,
				}, {
					Label = MenuKit.Text({
						Size = UDim2.fromScale(0.55, 0.5),
						Text = string.format("Music Volume    %d%%", math.floor(musicVolume * 100 + 0.5)),
						TextColor3 = if musicOn then Theme.Text else Theme.MutedText,
						TextSize = MenuKit.Size(mobile, 12),
						ZIndex = 6,
					}),
					Slider = React.createElement(MenuKit.Slider, {
						Mobile = mobile,
						AnchorPoint = Vector2.new(1, 0.5),
						Position = UDim2.fromScale(1, 0.5),
						Size = UDim2.fromScale(0.42, 1),
						Value = musicVolume,
						Step = AudioConfig.Music.Step,
						ZIndex = 6,
						OnChanged = if musicOn and props.SetMusicVolume
							then props.SetMusicVolume
							else nil,
					}),
				}),
				TrackCaption = MenuKit.Text({
					Position = UDim2.fromScale(0.05, 0.585),
					Size = UDim2.fromScale(0.9, 0.09),
					Font = Theme.Fonts.Caption,
					Text = "MENU TRACK",
					TextColor3 = Theme.AccentCyan,
					TextSize = MenuKit.Size(mobile, 10),
					ZIndex = 5,
				}),
				Tracks = React.createElement("Frame", {
					Position = UDim2.fromScale(0.05, 0.675),
					Size = UDim2.fromScale(0.9, 0.29),
					BackgroundTransparency = 1,
					ZIndex = 5,
				}, trackRows),
			}),

			--[[
				CAMERA and GAMEPLAY. Nothing here is adjustable yet: camera
				presets are chosen by game mode and the match rules are fixed, so
				every row states its current value and is marked unavailable
				rather than being given a control that does nothing.
			]]
			CameraPanel = MenuKit.Panel({
				Position = panelPosition,
				Size = panelSize,
				Visible = selectedCategory == 3,
				Transparency = 0.14,
				ZIndex = 4,
			}, {
				Heading = React.createElement(MenuKit.PanelHeading, {
					Mobile = mobile,
					Title = "CAMERA",
					Caption = "Camera and view settings.",
					Position = UDim2.fromScale(0.05, 0.08),
					Size = UDim2.fromScale(0.9, 0.28),
					ZIndex = 5,
				}),
				--[[
					DEFAULT CAMERA -- a real, working setting (§21).

					The three production gameplay cameras. The choice decides which
					one a match opens in; the player can still cycle during play.
				]]
				DefaultCameraLabel = MenuKit.Text({
					Position = UDim2.fromScale(0.05, 0.3),
					Size = UDim2.fromScale(0.9, 0.07),
					Font = Theme.Fonts.Caption,
					Text = "DEFAULT CAMERA",
					TextColor3 = Theme.MutedText,
					TextSize = MenuKit.Size(mobile, 11),
					TextXAlignment = Enum.TextXAlignment.Left,
					ZIndex = 5,
				}),
				DefaultCamera = React.createElement("Frame", {
					Position = UDim2.fromScale(0.05, 0.38),
					Size = UDim2.fromScale(0.9, 0.12),
					BackgroundTransparency = 1,
					ZIndex = 5,
				}, cameraChoiceChildren),

				Rows = React.createElement("Frame", {
					Position = UDim2.fromScale(0.05, 0.56),
					Size = UDim2.fromScale(0.9, 0.38),
					BackgroundTransparency = 1,
					ZIndex = 5,
				}, {
					Layout = React.createElement("UIListLayout", {
						FillDirection = Enum.FillDirection.Vertical,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 2),
					}),
					Row2 = React.createElement(SettingRow, {
						Order = 2, Mobile = mobile, Label = "Camera Height",
						Value = "MODE DEFAULT", Enabled = false,
					}),
					Row3 = React.createElement(SettingRow, {
						Order = 3, Mobile = mobile, Label = "Camera Zoom",
						Value = "MODE DEFAULT", Enabled = false,
					}),
				}),
			}),

			GameplayPanel = MenuKit.Panel({
				Position = panelPosition,
				Size = panelSize,
				Visible = selectedCategory == 4,
				Transparency = 0.14,
				ZIndex = 4,
			}, {
				Heading = React.createElement(MenuKit.PanelHeading, {
					Mobile = mobile,
					Title = "GAMEPLAY",
					Caption = "Match and game options.",
					Position = UDim2.fromScale(0.05, 0.08),
					Size = UDim2.fromScale(0.9, 0.28),
					ZIndex = 5,
				}),
				Rows = React.createElement("Frame", {
					Position = UDim2.fromScale(0.05, 0.42),
					Size = UDim2.fromScale(0.9, 0.52),
					BackgroundTransparency = 1,
					ZIndex = 5,
				}, {
					Layout = React.createElement("UIListLayout", {
						FillDirection = Enum.FillDirection.Vertical,
						SortOrder = Enum.SortOrder.LayoutOrder,
						Padding = UDim.new(0, 2),
					}),
					Row1 = React.createElement(SettingRow, {
						Order = 1, Mobile = mobile, Label = "Half Length",
						Value = "MATCH DEFAULT", Enabled = false,
					}),
					Row2 = React.createElement(SettingRow, {
						Order = 2, Mobile = mobile, Label = "Offside",
						Value = "ON", Enabled = false,
					}),
					Row3 = React.createElement(SettingRow, {
						Order = 3, Mobile = mobile, Label = "Injuries",
						Value = "ON", Enabled = false,
					}),
				}),
			}),

			--[[
				INTERFACE was in the category list with nothing behind it, so
				selecting it showed an empty page. It says so plainly rather than
				displaying invented HUD toggles that do not exist yet.
			]]
			InterfacePanel = MenuKit.Panel({
				Position = panelPosition,
				Size = panelSize,
				Visible = selectedCategory == 5,
				Transparency = 0.14,
				ZIndex = 4,
			}, {
				Heading = React.createElement(MenuKit.PanelHeading, {
					Mobile = mobile,
					Title = "FOOTBALLER",
					Caption = "How you look on the pitch and in the menus.",
					Position = UDim2.fromScale(0.05, 0.06),
					Size = UDim2.fromScale(0.9, 0.14),
					ZIndex = 5,
				}),
				AvatarLabel = MenuKit.Text({
					Position = UDim2.fromScale(0.05, 0.26),
					Size = UDim2.fromScale(0.9, 0.07),
					Font = Theme.Fonts.Caption,
					Text = "PLAY AS",
					TextColor3 = Theme.MutedText,
					TextSize = MenuKit.Size(mobile, 11),
					TextXAlignment = Enum.TextXAlignment.Left,
					ZIndex = 5,
				}),
				AvatarChoices = React.createElement("Frame", {
					Position = UDim2.fromScale(0.05, 0.34),
					Size = UDim2.fromScale(0.9, 0.12),
					BackgroundTransparency = 1,
					ZIndex = 5,
				}, avatarChoiceChildren),
				AvatarCaption = MenuKit.Text({
					Position = UDim2.fromScale(0.05, 0.48),
					Size = UDim2.fromScale(0.9, 0.16),
					Font = Theme.Fonts.Caption,
					--[[
						The wording now says what the setting actually does.

						It read as an interface preference -- something about menus
						-- when it is the single choice of who you are on the
						pitch. It governs the footballer you play matches as, the
						one shown in the main menu, and every appearance of you in
						the game. Saying so is the difference between a player
						finding this setting and never looking for it.
					]]
					Text = "This is the footballer you play as everywhere -- in matches, in training and in the menu. Every footballer is built to the same height, so nobody gains reach or stride from their avatar. Takes effect from your next match.",
					TextColor3 = Theme.MutedText,
					TextSize = MenuKit.Size(mobile, 11),
					TextWrapped = true,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextYAlignment = Enum.TextYAlignment.Top,
					ZIndex = 5,
				}),
				Note = MenuKit.Text({
					Position = UDim2.fromScale(0.05, 0.68),
					Size = UDim2.fromScale(0.9, 0.2),
					Font = Theme.Fonts.Caption,
					Text = "HUD layout options arrive with the match HUD pass.",
					TextColor3 = Theme.MutedText,
					TextSize = MenuKit.Size(mobile, 12),
					TextWrapped = true,
					TextYAlignment = Enum.TextYAlignment.Top,
					ZIndex = 5,
				}),
			}),
		},
	})
end
