local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Shared.ReactPackages).React

local ReactUI = {}

function ReactUI.Corner(radius: number?)
	return React.createElement("UICorner", {
		CornerRadius = UDim.new(0, radius or 6),
	})
end

function ReactUI.Stroke(color: Color3, thickness: number?, transparency: number?)
	return React.createElement("UIStroke", {
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

return ReactUI
