local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Parent.Theme)

local GoalNotification = {}

function GoalNotification.Create(parent: Instance)
	local frame = Instance.new("Frame")
	frame.Name = "GoalNotification"
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundTransparency = 1
	frame.Visible = false
	frame.ZIndex = 40
	frame.Parent = parent

	local text = Instance.new("TextLabel")
	text.Name = "GoalText"
	text.AnchorPoint = Vector2.new(0.5, 0.5)
	text.Position = UDim2.fromScale(0.5, 0.38)
	text.Size = UDim2.fromOffset(520, 112)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBlack
	text.Text = "GOAL"
	text.TextColor3 = Theme.Text
	text.TextSize = 82
	text.TextTransparency = 1
	text.ZIndex = 41
	text.Parent = frame
	local scale = Instance.new("UIScale")
	scale.Scale = 0.72
	scale.Parent = text

	local accent = Instance.new("Frame")
	accent.Name = "Accent"
	accent.AnchorPoint = Vector2.new(0.5, 0.5)
	accent.Position = UDim2.fromScale(0.5, 0.445)
	accent.Size = UDim2.fromOffset(0, 5)
	accent.BackgroundColor3 = Theme.Accent
	accent.BorderSizePixel = 0
	accent.ZIndex = 41
	accent.Parent = frame

	local sequence = 0
	return {
		Frame = frame,
		Play = function(payload)
			sequence += 1
			local currentSequence = sequence
			frame.Visible = true
			text.TextTransparency = 1
			text.Position = UDim2.fromScale(0.5, 0.4)
			scale.Scale = 0.72
			accent.BackgroundTransparency = 0
			accent.Size = UDim2.fromOffset(0, 5)

			TweenService:Create(text, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				TextTransparency = 0,
				Position = UDim2.fromScale(0.5, 0.38),
			}):Play()
			TweenService:Create(scale, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Scale = 1,
			}):Play()
			TweenService:Create(accent, TweenInfo.new(0.24, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
				Size = UDim2.fromOffset(300, 5),
			}):Play()

			task.delay(1, function()
				if sequence ~= currentSequence or not frame.Parent then
					return
				end
				TweenService:Create(text, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					TextTransparency = 1,
					Position = UDim2.fromScale(0.5, 0.35),
				}):Play()
				local accentFade = TweenService:Create(accent, TweenInfo.new(0.24), {
					BackgroundTransparency = 1,
					Size = UDim2.fromOffset(360, 5),
				})
				accentFade:Play()
				accentFade.Completed:Wait()
				if sequence == currentSequence then
					frame.Visible = false
				end
			end)
		end,
	}
end

return GoalNotification
