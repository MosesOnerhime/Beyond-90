local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

ReplicatedFirst:RemoveDefaultLoadingScreen()

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local gui = Instance.new("ScreenGui")
gui.Name = "Beyond90StartupLoading"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 1000
gui.Parent = playerGui

local background = Instance.new("Frame")
background.Size = UDim2.fromScale(1, 1)
background.BackgroundColor3 = Color3.fromRGB(3, 5, 15)
background.BorderSizePixel = 0
background.Parent = gui

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ExperienceConfig = require(Shared.Config.ExperienceConfig)
local UIAssetConfig = require(Shared.Config.UIAssetConfig)

local stadium = Instance.new("ImageLabel")
stadium.Size = UDim2.fromScale(1, 1)
stadium.BackgroundTransparency = 1
stadium.Image = UIAssetConfig.MenuStadium
stadium.ImageTransparency = 0.42
stadium.ScaleType = Enum.ScaleType.Crop
stadium.Parent = background

local shade = Instance.new("UIGradient")
shade.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(2, 4, 14)),
	ColorSequenceKeypoint.new(0.55, Color3.fromRGB(7, 13, 36)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(20, 8, 46)),
})
shade.Transparency = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.05),
	NumberSequenceKeypoint.new(0.55, 0.3),
	NumberSequenceKeypoint.new(1, 0.12),
})
shade.Parent = stadium

local logo = Instance.new("ImageLabel")
logo.AnchorPoint = Vector2.new(0.5, 0.5)
logo.Position = UDim2.fromScale(0.5, 0.43)
logo.Size = UDim2.fromOffset(390, 260)
logo.BackgroundTransparency = 1
logo.Image = UIAssetConfig.Logo
logo.ScaleType = Enum.ScaleType.Fit
logo.Parent = background

local status = Instance.new("TextLabel")
status.AnchorPoint = Vector2.new(0.5, 0)
status.Position = UDim2.fromScale(0.5, 0.66)
status.Size = UDim2.fromOffset(420, 28)
status.BackgroundTransparency = 1
status.Font = Enum.Font.GothamMedium
status.Text = "STARTING BEYOND 90"
status.TextColor3 = Color3.fromRGB(225, 232, 250)
status.TextSize = 14
status.Parent = background

local track = Instance.new("Frame")
track.AnchorPoint = Vector2.new(0.5, 0)
track.Position = UDim2.fromScale(0.5, 0.71)
track.Size = UDim2.fromOffset(360, 3)
track.BackgroundColor3 = Color3.fromRGB(49, 58, 88)
track.BorderSizePixel = 0
track.Parent = background

local fill = Instance.new("Frame")
fill.Size = UDim2.fromScale(0.12, 1)
fill.BackgroundColor3 = Color3.fromRGB(47, 180, 255)
fill.BorderSizePixel = 0
fill.Parent = track
local fillGradient = Instance.new("UIGradient")
fillGradient.Color = ColorSequence.new(Color3.fromRGB(31, 195, 255), Color3.fromRGB(139, 76, 255))
fillGradient.Parent = fill

local startedAt = os.clock()
task.spawn(function()
	pcall(function()
		ContentProvider:PreloadAsync({ stadium, logo })
	end)
	status.Text = "LOADING INTERFACE"
	TweenService:Create(fill, TweenInfo.new(1.4, Enum.EasingStyle.Quad), { Size = UDim2.fromScale(0.88, 1) }):Play()
end)

while not player:GetAttribute("Beyond90MenuReady") or os.clock() - startedAt < ExperienceConfig.StartupMinimumDisplayTime do
	if os.clock() - startedAt >= ExperienceConfig.PreloadTimeout
		and os.clock() - startedAt >= ExperienceConfig.StartupMinimumDisplayTime
	then
		break
	end
	task.wait()
end

status.Text = "WELCOME TO BEYOND 90"
TweenService:Create(fill, TweenInfo.new(0.2), { Size = UDim2.fromScale(1, 1) }):Play()
task.wait(0.15)
local fade = TweenService:Create(background, TweenInfo.new(0.35, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 })
for _, descendant in background:GetDescendants() do
	if descendant:IsA("ImageLabel") then
		TweenService:Create(descendant, TweenInfo.new(0.35), { ImageTransparency = 1 }):Play()
	elseif descendant:IsA("TextLabel") then
		TweenService:Create(descendant, TweenInfo.new(0.35), { TextTransparency = 1 }):Play()
	elseif descendant:IsA("Frame") then
		TweenService:Create(descendant, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
	end
end
fade:Play()
fade.Completed:Wait()
gui:Destroy()
