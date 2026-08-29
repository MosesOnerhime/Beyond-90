--[[
	Position selection.

	Deliberately fast (§41): four cards, a pitch preview showing where the
	position actually plays, and Continue. This is not an Ultimate Team lineup
	screen and must not become one.

	Occupancy is replicated from PositionService, so a slot another human has
	already reserved is shown as taken rather than silently rejected on Continue.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local React = require(ReplicatedStorage.Shared.ReactPackages).React
local Assets = require(ReplicatedStorage.Shared.Config.UIAssetConfig)
local PositionConfig = require(ReplicatedStorage.Shared.Config.PositionConfig)
local Theme = require(script.Parent.Parent.Theme)
local ReactUI = require(script.Parent.Parent.Components.ReactUI)
local MenuFooter = require(script.Parent.Parent.Components.MenuFooter)
local BackButton = require(script.Parent.Parent.Components.BackButton)

local localPlayer = Players.LocalPlayer

--[[
	A drawn pitch showing where a position actually plays.

	Two things are shown, and both come from the SAME PositionConfig values the
	server uses for formation shape and set pieces, so this preview cannot drift
	away from where the footballer really stands:

	  - the operating BAND, from the position's MaximumRetreat to its
	    MaximumAdvance, which is the part a player actually wants to know;
	  - the anchor itself, which is where they start.

	Drawn rather than an uploaded image: it costs no Roblox asset and therefore no
	moderation risk (section 57), it restyles with the theme, and a new position
	needs no new artwork.

	Own goal is at the BOTTOM and the attacking goal at the top, which is the
	orientation every football graphic uses for "your half".
]]
local PITCH_LINE = Color3.fromRGB(196, 224, 214)

local function pitchLine(props)
	local merged = {
		BackgroundColor3 = PITCH_LINE,
		BackgroundTransparency = props.Transparency or 0.55,
		BorderSizePixel = 0,
		ZIndex = props.ZIndex or 5,
		AnchorPoint = props.AnchorPoint,
		Position = props.Position,
		Size = props.Size,
	}
	return React.createElement("Frame", merged, props.Children)
end

-- Normalized longitudinal (-1 own goal .. +1 attacking goal) -> preview Y.
local function longitudinalToY(value: number): number
	return 1 - (math.clamp(value, -1, 1) * 0.5 + 0.5)
end

--[[
	POSITION PREVIEW (§11).

	The supplied pitch artwork is used when available. The procedurally drawn
	pitch below existed only because those images did not exist yet -- it is kept
	as the fallback, not as the primary, so a moderation problem degrades the
	preview instead of leaving an empty card (§57).

	Server-side position reservation, AI slot filling, position profiles and
	validation are all untouched: this is presentation only.
]]
local function PitchPreview(props)
	local anchor = props.Anchor
	local profile = props.Profile

	local image = Assets.GetPitchPositionImage(props.SlotId)
	if image ~= "" then
		return React.createElement("ImageLabel", {
			AnchorPoint = props.AnchorPoint,
			Position = props.Position,
			Size = props.Size,
			BackgroundTransparency = 1,
			Image = image,
			-- The artwork is a tall pitch on transparency; Fit letterboxes rather
			-- than cutting the goalmouths off.
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = 3,
		})
	end
	local markerY = longitudinalToY(anchor.Longitudinal)
	local markerX = anchor.Lateral * 0.5 + 0.5

	local children = {
		Corner = ReactUI.Corner(5),
		Stroke = ReactUI.Stroke(PITCH_LINE, 1.1, 0.4),
		Turf = React.createElement("Frame", {
			Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = Color3.fromRGB(10, 46, 36),
			BackgroundTransparency = 0.15,
			BorderSizePixel = 0,
			ZIndex = 3,
		}, {
			Corner = ReactUI.Corner(5),
			-- Mown stripes: the cheapest thing that makes a rectangle read as turf.
			Gradient = React.createElement("UIGradient", {
				Rotation = 90,
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0),
					NumberSequenceKeypoint.new(0.24, 0.12),
					NumberSequenceKeypoint.new(0.25, 0),
					NumberSequenceKeypoint.new(0.49, 0.12),
					NumberSequenceKeypoint.new(0.5, 0),
					NumberSequenceKeypoint.new(0.74, 0.12),
					NumberSequenceKeypoint.new(0.75, 0),
					NumberSequenceKeypoint.new(1, 0.12),
				}),
			}),
		}),
		Halfway = pitchLine({
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, 0, 0, 1),
		}),
		CenterCircle = React.createElement("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.3, 0.17),
			BackgroundTransparency = 1,
			ZIndex = 5,
		}, { Corner = ReactUI.Corner(100), Stroke = ReactUI.Stroke(PITCH_LINE, 1, 0.55) }),
		-- Own penalty area (bottom) and the attacking one (top).
		OwnBox = React.createElement("Frame", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 1),
			Size = UDim2.fromScale(0.54, 0.16),
			BackgroundTransparency = 1,
			ZIndex = 5,
		}, { Stroke = ReactUI.Stroke(PITCH_LINE, 1, 0.5) }),
		OwnSixYard = React.createElement("Frame", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 1),
			Size = UDim2.fromScale(0.26, 0.07),
			BackgroundTransparency = 1,
			ZIndex = 5,
		}, { Stroke = ReactUI.Stroke(PITCH_LINE, 1, 0.62) }),
		FarBox = React.createElement("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0),
			Size = UDim2.fromScale(0.54, 0.16),
			BackgroundTransparency = 1,
			ZIndex = 5,
		}, { Stroke = ReactUI.Stroke(PITCH_LINE, 1, 0.5) }),
		FarSixYard = React.createElement("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0),
			Size = UDim2.fromScale(0.26, 0.07),
			BackgroundTransparency = 1,
			ZIndex = 5,
		}, { Stroke = ReactUI.Stroke(PITCH_LINE, 1, 0.62) }),
	}

	--[[
		The operating band. This is the honest answer to "where does this position
		play?" -- a single dot suggests a footballer stands still, which is exactly
		what a position is not.
	]]
	if profile then
		local topY = longitudinalToY(profile.MaximumAdvance)
		local bottomY = longitudinalToY(profile.MaximumRetreat)
		children.Zone = React.createElement("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, topY),
			Size = UDim2.fromScale(0.94, math.max(bottomY - topY, 0.02)),
			BackgroundColor3 = props.Accent,
			BackgroundTransparency = 0.76,
			BorderSizePixel = 0,
			ZIndex = 4,
		}, {
			Corner = ReactUI.Corner(3),
			Gradient = React.createElement("UIGradient", {
				Rotation = 90,
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0.5),
					NumberSequenceKeypoint.new(0.5, 0),
					NumberSequenceKeypoint.new(1, 0.5),
				}),
			}),
		})
	end

	children.Marker = React.createElement("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(markerX, markerY),
		Size = UDim2.fromOffset(10, 10),
		BackgroundColor3 = props.Accent,
		BorderSizePixel = 0,
		ZIndex = 7,
	}, {
		Corner = ReactUI.Corner(40),
		Stroke = ReactUI.Stroke(Color3.fromRGB(8, 16, 24), 1.4, 0.2),
	})

	return React.createElement("Frame", {
		AnchorPoint = props.AnchorPoint,
		Position = props.Position,
		Size = props.Size,
		BackgroundColor3 = Color3.fromRGB(6, 26, 21),
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
		ClipsDescendants = true,
		ZIndex = 3,
	}, children)
end

local function PositionCard(props)
	local focused, setFocused = React.useState(false)
	local taken = props.Taken and not props.Selected
	local active = props.Selected or (focused and not taken)
	local accent = if props.Selected then Theme.AccentCyan else Theme.MutedText

	return React.createElement("TextButton", {
		LayoutOrder = props.Order,
		Size = UDim2.fromScale(if props.Mobile then 0.23 else 0.22, 1),
		BackgroundColor3 = if active then Theme.PanelHover else Theme.Panel,
		BackgroundTransparency = if taken then 0.45 elseif active then 0.06 else 0.16,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Selectable = not taken,
		Active = not taken,
		Text = "",
		ZIndex = 3,
		[React.Event.Activated] = function()
			if not taken then
				props.Select()
			end
		end,
		[React.Event.MouseEnter] = function() setFocused(true) end,
		[React.Event.MouseLeave] = function() setFocused(false) end,
		[React.Event.SelectionGained] = function() setFocused(true) end,
		[React.Event.SelectionLost] = function() setFocused(false) end,
	}, {
		Corner = ReactUI.Corner(6),
		Stroke = ReactUI.Stroke(
			if props.Selected then Theme.StrokeBright else Theme.Stroke,
			if props.Selected then 1.5 else 1,
			if props.Selected then 0.14 else 0.4
		),
		Accent = props.Selected and React.createElement("Frame", {
			Size = UDim2.new(1, 0, 0, 2),
			BackgroundColor3 = Theme.AccentCyan,
			BorderSizePixel = 0,
			ZIndex = 5,
		}, { Gradient = ReactUI.Gradient(Theme.AccentCyan, Theme.AccentViolet, 0) }) or nil,

		Short = React.createElement("TextLabel", {
			Position = UDim2.fromScale(0.08, 0.07),
			Size = UDim2.fromScale(0.84, 0.16),
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Display,
			Text = props.ShortName,
			TextColor3 = if props.Selected then Theme.AccentCyan else Theme.Text,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 4,
		}),
		Name = React.createElement("TextLabel", {
			Position = UDim2.fromScale(0.08, 0.25),
			Size = UDim2.fromScale(0.84, 0.09),
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Navigation,
			Text = props.DisplayName,
			TextColor3 = Theme.Text,
			TextSize = if props.Mobile then 10 else 13,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = 4,
		}),
		Summary = React.createElement("TextLabel", {
			Position = UDim2.fromScale(0.08, 0.36),
			Size = UDim2.fromScale(0.84, 0.16),
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Caption,
			Text = props.Summary,
			TextColor3 = Theme.MutedText,
			TextSize = if props.Mobile then 8 else 11,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = true,
			ZIndex = 4,
		}),

		Preview = React.createElement(PitchPreview, {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.66, 0.42),
			Anchor = props.Anchor,
			Profile = props.Profile,
			-- Selects the artwork; GK / DEF / MID / FWD each have their own.
			SlotId = props.SlotId,
			Accent = accent,
		}),

		Status = React.createElement("TextLabel", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 0.96),
			Size = UDim2.fromScale(0.9, 0.08),
			BackgroundTransparency = 1,
			Font = Theme.Fonts.Caption,
			Text = props.StatusText,
			TextColor3 = if taken then Theme.Warning else Theme.MutedText,
			TextSize = if props.Mobile then 8 else 10,
			ZIndex = 4,
		}),
	})
end

return function(props)
	local mobile = UserInputService.TouchEnabled
	local slots = PositionConfig.GetSelectableSlots(props.ModeId)
	local occupancy = props.Occupancy or {}

	--[[
		Default to the first slot no other human holds, so a player who just
		presses Continue still gets something sensible rather than nothing.
	]]
	local function firstFree(): string
		for _, slotId in slots do
			local row = occupancy[slotId]
			if not row or not row.Taken then
				return slotId
			end
		end
		return slots[1] or "MID"
	end

	local selected, setSelected = React.useState(firstFree)

	local cards = {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0.02, 0),
			SortOrder = Enum.SortOrder.LayoutOrder,
		}),
	}

	for index, slotId in slots do
		local position = PositionConfig.Get(slotId)
		if position then
			local row = occupancy[slotId]
			local taken = row ~= nil and row.Taken == true
			local statusText = if taken
				then string.upper(tostring(row.OccupiedBy or "TAKEN"))
				else "AI WILL FILL"
			if selected == slotId then
				statusText = "YOUR POSITION"
			end

			cards[slotId] = React.createElement(PositionCard, {
				Order = index,
				Mobile = mobile,
				-- Chooses the position artwork (§11); GK / DEF / MID / FWD.
				SlotId = slotId,
				ShortName = position.ShortName,
				DisplayName = position.DisplayName,
				Summary = position.Summary,
				Anchor = position.Anchor,
				Profile = position.AI,
				Selected = selected == slotId,
				Taken = taken,
				StatusText = statusText,
				Select = function() setSelected(slotId) end,
			})
		end
	end

	local teamLabel = string.upper(tostring(props.TeamId or "HOME"))

	return React.createElement("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Theme.Background,
		BorderSizePixel = 0,
	}, {
		Background = React.createElement("ImageLabel", {
			Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
			Image = Assets.MenuStadium, ImageTransparency = 0.28, ScaleType = Enum.ScaleType.Crop,
		}),
		Shade = React.createElement("Frame", {
			Size = UDim2.fromScale(1, 1), BackgroundColor3 = Theme.Background,
			BackgroundTransparency = 0.45, BorderSizePixel = 0,
		}),
		Title = React.createElement("TextLabel", {
			Position = UDim2.fromScale(0.22, if mobile then 0.07 else 0.12),
			Size = UDim2.fromScale(0.56, if mobile then 0.11 else 0.085),
			BackgroundTransparency = 1, Font = Theme.Fonts.Display,
			Text = "SELECT POSITION", TextColor3 = Theme.Text, TextScaled = true, ZIndex = 2,
		}),
		Subtitle = React.createElement("TextLabel", {
			Position = UDim2.fromScale(0.2, if mobile then 0.185 else 0.215),
			Size = UDim2.fromScale(0.6, if mobile then 0.05 else 0.038),
			BackgroundTransparency = 1, Font = Theme.Fonts.Body,
			Text = teamLabel .. " TEAM  •  AI FILLS EVERY POSITION YOU DO NOT TAKE",
			TextColor3 = Theme.MutedText, TextScaled = true, ZIndex = 2,
		}),
		Cards = React.createElement("Frame", {
			Position = UDim2.fromScale(0.05, if mobile then 0.26 else 0.29),
			Size = UDim2.fromScale(0.9, if mobile then 0.46 else 0.44),
			BackgroundTransparency = 1, ZIndex = 2,
		}, cards),
		Continue = React.createElement("TextButton", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, if mobile then 0.85 else 0.865),
			Size = UDim2.fromScale(if mobile then 0.3 else 0.22, if mobile then 0.09 else 0.07),
			BackgroundColor3 = Theme.AccentDark, BorderSizePixel = 0,
			Font = Theme.Fonts.Navigation, Text = "CONTINUE", TextColor3 = Theme.Text,
			TextSize = if mobile then 14 else 17, ZIndex = 2,
			[React.Event.Activated] = function() props.Continue(selected) end,
		}, {
			Corner = ReactUI.Corner(5), Stroke = ReactUI.Stroke(Theme.AccentCyan, 1.25, 0.18),
		}),
		Footer = React.createElement(MenuFooter.Root, {
			Mobile = mobile,
			Content = React.createElement("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, {
				Back = React.createElement(BackButton.Root, { Mobile = mobile, ZIndex = 7, OnActivated = props.GoBack }),
			}),
		}),
	})
end
