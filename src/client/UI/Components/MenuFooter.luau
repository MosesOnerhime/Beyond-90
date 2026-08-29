local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Shared.ReactPackages).React
local Assets = require(ReplicatedStorage.Shared.Config.UIAssetConfig)
local Theme = require(script.Parent.Parent.Theme)
local ReactUI = require(script.Parent.ReactUI)

local MenuFooter = {}

--[[
	ONE CONTROL HINT (§9).

	An icon and its action label as a single laid-out unit, so the image and the
	word can never drift apart the way the hand-positioned versions did -- they
	were placed at independent scale coordinates and stopped lining up as soon as
	the viewport changed shape.

	The icon is optional: when `Image` is empty or fails to resolve, a text chip
	is rendered instead. That fallback is what makes it safe to reference a newly
	uploaded asset whose moderation state is not yet confirmed (§57) -- the hint
	degrades to readable text rather than to an empty box.

	props:
		Image      asset id, may be ""
		Fallback   short text for the chip when there is no image ("CLICK", "ESC")
		Label      the action, e.g. "SELECT"
		Position   UDim2
		Mobile     boolean
		Order      LayoutOrder
]]
function MenuFooter.Prompt(props)
	local mobile = props.Mobile == true
	local hasImage = typeof(props.Image) == "string" and props.Image ~= ""
	local iconSize = if mobile then 20 else 26

	return React.createElement("Frame", {
		Position = props.Position,
		Size = props.Size or UDim2.fromOffset(if mobile then 96 else 132, if mobile then 24 else 30),
		BackgroundTransparency = 1,
		LayoutOrder = props.Order,
		ZIndex = props.ZIndex or 4,
	}, {
		Layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, if mobile then 5 else 7),
		}),
		Icon = hasImage and React.createElement("ImageLabel", {
			LayoutOrder = 1,
			Size = UDim2.fromOffset(iconSize, iconSize),
			BackgroundTransparency = 1,
			Image = props.Image,
			ScaleType = Enum.ScaleType.Fit,
			ZIndex = props.ZIndex or 4,
		}) or React.createElement("TextLabel", {
			LayoutOrder = 1,
			Size = UDim2.fromOffset(if mobile then 32 else 40, if mobile then 18 else 21),
			BackgroundColor3 = Theme.Panel,
			BackgroundTransparency = 0.18,
			BorderSizePixel = 0,
			Font = Theme.Fonts.Statistics,
			Text = props.Fallback or "",
			TextColor3 = Theme.Text,
			TextSize = if mobile then 9 else 10,
			ZIndex = props.ZIndex or 4,
		}, {
			Corner = ReactUI.Corner(4),
			Stroke = ReactUI.Stroke(Theme.StrokeBright, 1, 0.55),
		}),
		--[[
			The label is hidden on mobile: a touch player is not pressing either of
			these, and the words only crowd an already tight footer.
		]]
		Label = (not mobile) and React.createElement("TextLabel", {
			LayoutOrder = 2,
			AutomaticSize = Enum.AutomaticSize.X,
			Size = UDim2.fromOffset(0, 18),
			BackgroundTransparency = 1,
			Font = Enum.Font.GothamMedium,
			Text = props.Label or "",
			TextColor3 = Theme.MutedText,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Left,
			ZIndex = props.ZIndex or 4,
		}) or nil,
	})
end

local FOOTER_COLOR = Color3.fromRGB(1, 5, 17)

function MenuFooter.Root(props)
	local mobile = props.Mobile == true
	local _, bottomRightInset = GuiService:GetGuiInset()
	local bottomInset = if mobile then math.max(bottomRightInset.Y, 0) else 0
	--[[
		Defaults ARE the tuned Home-screen treatment.

		These used to be untuned placeholders (a 0.87 top and a 0.46 wash), and
		only the Home screen overrode them -- so every other menu, including the
		mode picker, drew a completely different and much heavier footer. Making
		the good values the defaults gives the whole menu family one footer.
	]]
	local desktopTop = props.DesktopTop or 0.9
	local desktopHeight = props.DesktopHeight or 0.1
	local mobileHeight = props.MobileHeight or 0.14
	local footerPosition = if mobile then UDim2.fromScale(0, 1) else UDim2.fromScale(0, desktopTop)
	local footerSize = if mobile
		then UDim2.new(1, 0, mobileHeight, bottomInset)
		else UDim2.fromScale(1, desktopHeight)

	-- ref/mockup 1.png has no footer panel at all: the navigation sits directly
	-- on the stadium background, with the scene simply darkening toward the
	-- bottom edge. A single tall gradient wash reproduces that, so there is no
	-- rectangle edge and therefore no seam to hide.
	--[[
		Mobile is the desktop treatment rescaled, not a separate design.

		The mobile wash used to be an independent constant, which drifted to
		roughly three times the desktop value and turned the same composition
		into a completely different-looking screen. Deriving it from the desktop
		height keeps one visual identity: mobile gets modestly more coverage
		because its footer band is taller relative to the screen, and the bottom
		safe inset is added on top so the wash always reaches the physical edge.
	]]
	local desktopFade = props.DesktopFadeHeight or 0.18
	local washHeight = if mobile
		then (props.MobileFadeHeight or math.min(desktopFade * 1.35, 0.5))
		else desktopFade

	return React.createElement("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = props.RootZIndex or props.ZIndex or 6,
	}, {
		Wash = React.createElement("Frame", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 1),
			Size = UDim2.new(1, 0, washHeight, bottomInset),
			BackgroundColor3 = FOOTER_COLOR,
			BorderSizePixel = 0,
			ZIndex = props.FadeZIndex or 1,
		}, {
			Gradient = React.createElement("UIGradient", {
				Rotation = 90,
				-- Eased ramp from fully clear to fully opaque. Nothing along it
				-- steps, so no horizontal edge can appear anywhere.
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1),
					NumberSequenceKeypoint.new(0.14, 0.97),
					NumberSequenceKeypoint.new(0.28, 0.9),
					NumberSequenceKeypoint.new(0.42, 0.78),
					NumberSequenceKeypoint.new(0.56, 0.6),
					NumberSequenceKeypoint.new(0.7, 0.38),
					NumberSequenceKeypoint.new(0.82, 0.19),
					NumberSequenceKeypoint.new(0.92, 0.06),
					NumberSequenceKeypoint.new(1, 0),
				}),
			}),
		}),
		-- Content only. No fill of its own, so the navigation reads as sitting on
		-- the scene rather than inside an attached panel.
		Footer = React.createElement("Frame", {
			AnchorPoint = if mobile then Vector2.new(0, 1) else Vector2.zero,
			Position = footerPosition,
			Size = footerSize,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = props.ZIndex or 6,
		}, {
			Content = React.createElement("Frame", {
				Size = UDim2.new(1, 0, 1, -bottomInset),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
			}, {
				Body = props.Content,
			}),
		}),
	})
end

return MenuFooter
