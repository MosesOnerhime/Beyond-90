local Theme = require(script.Parent.Parent.Theme)

local UIUtil = {}

function UIUtil.AddCorner(instance: GuiObject, radius: UDim?)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius or Theme.CornerRadius
	corner.Parent = instance
	return corner
end

function UIUtil.AddStroke(instance: GuiObject, color: Color3?, thickness: number?)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or Theme.Stroke
	stroke.Thickness = thickness or 1
	stroke.Transparency = 0.2
	stroke.Parent = instance
	return stroke
end

function UIUtil.AddGradient(instance: GuiObject, first: Color3, second: Color3, rotation: number?)
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(first, second)
	gradient.Rotation = rotation or 0
	gradient.Parent = instance
	return gradient
end

function UIUtil.CreateImage(parent: Instance, name: string, image: string, size: UDim2, position: UDim2)
	local label = Instance.new("ImageLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Image = image
	label.Size = size
	label.Position = position
	label.ScaleType = Enum.ScaleType.Fit
	label.Parent = parent
	return label
end

function UIUtil.CreateText(parent: Instance, name: string, text: string, size: UDim2, position: UDim2, font: Enum.Font, textSize: number)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Size = size
	label.Position = position
	label.Font = font
	label.Text = text
	label.TextSize = textSize
	label.TextColor3 = Theme.Text
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = parent
	return label
end

function UIUtil.CreateButton(parent: Instance, name: string, title: string, subtitle: string)
	local button = Instance.new("TextButton")
	button.Name = name
	button.AutoButtonColor = false
	button.BackgroundColor3 = Theme.Panel
	button.Text = ""
	button.Selectable = true
	button.Parent = parent
	UIUtil.AddCorner(button)
	local stroke = UIUtil.AddStroke(button)
	local titleLabel = UIUtil.CreateText(button, "Title", title, UDim2.new(1, -24, 0, 28), UDim2.fromOffset(16, 12), Enum.Font.GothamBold, 18)
	local subtitleLabel = UIUtil.CreateText(button, "Subtitle", subtitle, UDim2.new(1, -24, 0, 36), UDim2.fromOffset(16, 42), Enum.Font.Gotham, 13)
	subtitleLabel.TextColor3 = Theme.MutedText
	button.MouseEnter:Connect(function()
		button.BackgroundColor3 = Theme.PanelHover
	end)
	button.MouseLeave:Connect(function()
		button.BackgroundColor3 = Theme.Panel
	end)
	button.SelectionGained:Connect(function()
		stroke.Color = Theme.Accent
		stroke.Thickness = 2
		titleLabel.TextColor3 = Theme.Accent
	end)
	button.SelectionLost:Connect(function()
		stroke.Color = Theme.Stroke
		stroke.Thickness = 1
		titleLabel.TextColor3 = Theme.Text
	end)
	return button
end

return UIUtil
