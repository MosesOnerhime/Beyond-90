local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Shared.ReactPackages).React
local Theme = require(script.Parent.Parent.Theme)
local ReactUI = require(script.Parent.Parent.Components.ReactUI)

local function GoalNotification(props)
	if not props.Visible then return nil end
	return React.createElement("Frame", {
		Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 100,
	}, {
		Panel = React.createElement("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.37),
			Size = UDim2.fromScale(0.28, 0.13), BackgroundColor3 = Theme.Panel,
			BackgroundTransparency = 0.08, BorderSizePixel = 0, ZIndex = 101,
		}, {
			Corner = ReactUI.Corner(8), Stroke = ReactUI.Stroke(Theme.AccentCyan, 2, 0.05),
			Gradient = ReactUI.Gradient(Color3.fromRGB(17, 17, 55), Color3.fromRGB(7, 31, 63)),
			Title = React.createElement("TextLabel", {
				Position = UDim2.fromScale(0.08, 0.12), Size = UDim2.fromScale(0.84, 0.5),
				BackgroundTransparency = 1, Font = Theme.Fonts.Display, Text = "GOAL",
				TextColor3 = Theme.Text, TextScaled = true, ZIndex = 102,
			}),
			Caption = React.createElement("TextLabel", {
				Position = UDim2.fromScale(0.12, 0.66), Size = UDim2.fromScale(0.76, 0.17),
				BackgroundTransparency = 1, Font = Theme.Fonts.Navigation,
				Text = "BEYOND 90 TRAINING", TextColor3 = Theme.AccentCyan, TextScaled = true, ZIndex = 102,
			}),
		}),
	})
end

return GoalNotification
