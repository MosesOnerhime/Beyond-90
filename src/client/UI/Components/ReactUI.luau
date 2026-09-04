local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Shared.ReactPackages).React
local Theme = require(script.Parent.Parent.Theme)

local ReactUI = {}

function ReactUI.Corner(radius: number?)
	return React.createElement("UICorner", {
		CornerRadius = UDim.new(0, radius or 6),
	})
end

--[[
	A border, and only a border.

	`ApplyStrokeMode` defaults to `Contextual`, and Contextual on a TextLabel or
	TextButton strokes the GLYPHS rather than the frame. Every text-bearing
	control in the menus gets one of these, so the default was outlining all of
	their text -- which is what made the settings track list read as a different,
	wider, thinner typeface than the rest of the menu, and what put the hard blue
	halo around the selected track's letters (the selected row strokes in
	`Theme.StrokeBright`, so its glyph outline was bright blue).

	`Border` is identical to Contextual on a Frame, so pinning it here fixes the
	text controls without changing a single panel.
]]
function ReactUI.Stroke(color: Color3, thickness: number?, transparency: number?)
	return React.createElement("UIStroke", {
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Color = color,
		Thickness = thickness or 1,
		Transparency = transparency or 0,
	})
end

function ReactUI.Gradient(first: Color3, second: Color3, rotation: number?)
	return React.createElement("UIGradient", {
		Color = ColorSequence.new(first, second),
		Rotation = rotation or 0,
	})
end

function ReactUI.Padding(left: number, right: number?, top: number?, bottom: number?)
	return React.createElement("UIPadding", {
		PaddingLeft = UDim.new(0, left),
		PaddingRight = UDim.new(0, right or left),
		PaddingTop = UDim.new(0, top or left),
		PaddingBottom = UDim.new(0, bottom or top or left),
	})
end

--[[
	A floor under a proportionally-sized control.

	Beyond 90 sizes almost everything with UDim2.fromScale so the layout grows
	with the screen. That is the right default and it has one blind spot: a scale
	has no minimum, so a control that is comfortable at 1080p can fall below a
	usable touch target on a short viewport without anything looking wrong in the
	code. Applying this keeps the proportional size wherever there is room and
	stops it collapsing where there is not.

	Defaults to Theme.MinimumTouchTarget on both axes.
]]
function ReactUI.MinimumSize(width: number?, height: number?)
	return React.createElement("UISizeConstraint", {
		MinSize = Vector2.new(
			width or Theme.MinimumTouchTarget,
			height or width or Theme.MinimumTouchTarget
		),
	})
end

return ReactUI
