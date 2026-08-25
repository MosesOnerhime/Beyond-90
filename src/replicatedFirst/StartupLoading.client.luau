local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

ReplicatedFirst:RemoveDefaultLoadingScreen()

local player = Players.LocalPlayer
player:SetAttribute("Beyond90StartupSequenceActive", true)
player:SetAttribute("Beyond90StartupReadyForMenu", false)
player:SetAttribute("Beyond90StartupComplete", false)
player:SetAttribute("Beyond90MenuSurfaceMounted", false)
player:SetAttribute("Beyond90MenuReady", false)

local playerGui = player:WaitForChild("PlayerGui")
local gui = Instance.new("ScreenGui")
gui.Name = "Beyond90StartupLoading"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 2147483647
gui.ZIndexBehavior = Enum.ZIndexBehavior.Global
gui.Parent = playerGui

local background = Instance.new("Frame")
background.Size = UDim2.fromScale(1, 1)
background.BackgroundColor3 = Color3.fromRGB(2, 3, 8)
background.BorderSizePixel = 0
background.Parent = gui

local backgroundGradient = Instance.new("UIGradient")
backgroundGradient.Color = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(2, 3, 8)),
	ColorSequenceKeypoint.new(0.55, Color3.fromRGB(5, 8, 18)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(9, 5, 19)),
})
backgroundGradient.Rotation = 18
backgroundGradient.Parent = background

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ExperienceConfig = require(Shared.Config.ExperienceConfig)
local AudioConfig = require(Shared.Config.AudioConfig)
local UIAssetConfig = require(Shared.Config.UIAssetConfig)

local brand = Instance.new("TextLabel")
brand.AnchorPoint = Vector2.new(0.5, 0.5)
brand.Position = UDim2.fromScale(0.5, 0.47)
brand.Size = UDim2.new(0.86, 0, 0, 58)
brand.BackgroundTransparency = 1
brand.Font = Enum.Font.GothamBold
brand.Text = "DRIXIL INTERACTIVE"
brand.TextColor3 = Color3.fromRGB(244, 247, 255)
brand.TextSize = 42
brand.TextTransparency = 1
brand.Parent = background

local brandScale = Instance.new("UIScale")
brandScale.Scale = 0.84
brandScale.Parent = brand

local brandConstraint = Instance.new("UITextSizeConstraint")
brandConstraint.MinTextSize = 25
brandConstraint.MaxTextSize = 42
brandConstraint.Parent = brand

local presents = Instance.new("TextLabel")
presents.AnchorPoint = Vector2.new(0.5, 0)
presents.Position = UDim2.fromScale(0.5, 0.525)
presents.Size = UDim2.new(0.7, 0, 0, 25)
presents.BackgroundTransparency = 1
presents.Font = Enum.Font.GothamMedium
presents.Text = "PRESENTS"
presents.TextColor3 = Color3.fromRGB(151, 162, 188)
presents.TextSize = 14
presents.TextTransparency = 1
presents.Parent = background

local accent = Instance.new("Frame")
accent.AnchorPoint = Vector2.new(0.5, 0)
accent.Position = UDim2.fromScale(0.5, 0.575)
accent.Size = UDim2.fromOffset(0, 2)
accent.BackgroundColor3 = Color3.fromRGB(39, 203, 255)
accent.BackgroundTransparency = 1
accent.BorderSizePixel = 0
accent.Parent = background

local accentGradient = Instance.new("UIGradient")
accentGradient.Color = ColorSequence.new(Color3.fromRGB(39, 203, 255), Color3.fromRGB(135, 78, 255))
accentGradient.Parent = accent

local logo = Instance.new("CanvasGroup")
logo.AnchorPoint = Vector2.new(0.5, 0.5)
logo.Position = UDim2.fromScale(0.5, 0.48)
logo.Size = UDim2.new(0.46, 0, 0.3, 0)
logo.BackgroundTransparency = 1
logo.GroupTransparency = 1
logo.ClipsDescendants = true
logo.Visible = false
logo.Parent = background

-- Roblox serves this 1536x1024 source at 1024x683. Split the logo into two
-- source rectangles so the embedded subtitle is omitted without masking glow.
local logoBeyond = Instance.new("ImageLabel")
logoBeyond.Position = UDim2.fromScale(0.01, 0.31)
logoBeyond.Size = UDim2.fromScale(0.72, 0.38)
logoBeyond.BackgroundTransparency = 1
logoBeyond.Image = UIAssetConfig.Logo
logoBeyond.ImageRectOffset = Vector2.new(20, 270)
logoBeyond.ImageRectSize = Vector2.new(700, 120)
logoBeyond.ScaleType = Enum.ScaleType.Fit
logoBeyond.Parent = logo

local logoNinety = Instance.new("ImageLabel")
logoNinety.Position = UDim2.fromScale(0.69, 0.04)
logoNinety.Size = UDim2.fromScale(0.31, 0.92)
logoNinety.BackgroundTransparency = 1
logoNinety.Image = UIAssetConfig.Logo
logoNinety.ImageRectOffset = Vector2.new(720, 175)
logoNinety.ImageRectSize = Vector2.new(300, 300)
logoNinety.ScaleType = Enum.ScaleType.Fit
logoNinety.Parent = logo

local logoScale = Instance.new("UIScale")
logoScale.Scale = 0.9
logoScale.Parent = logo

local function tween(instance: Instance, duration: number, properties, style: Enum.EasingStyle?)
	local animation = TweenService:Create(
		instance,
		TweenInfo.new(duration, style or Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		properties
	)
	animation:Play()
	return animation
end

local function preloadWithTimeout(instances: { Instance }, timeout: number): (boolean, any)
	local completed = false
	local succeeded = false
	local failure = nil
	task.spawn(function()
		succeeded, failure = pcall(function()
			ContentProvider:PreloadAsync(instances)
		end)
		completed = true
	end)
	local startedAt = os.clock()
	while not completed and os.clock() - startedAt < timeout do
		task.wait()
	end
	return completed and succeeded, if completed then failure else "timed out"
end

local function preloadMenuAssets()
	local assets = {}
	local function collectImages(value)
		if type(value) == "table" then
			for key, child in value do
				if key ~= "LocalSources" then
					collectImages(child)
				end
			end
		elseif type(value) == "string" and string.match(value, "^rbxassetid://%d+$") then
			local image = Instance.new("ImageLabel")
			image.Image = value
			table.insert(assets, image)
		end
	end
	collectImages(UIAssetConfig)
	local ok, failure = pcall(function()
		ContentProvider:PreloadAsync(assets)
	end)
	if not ok then
		warn("[Beyond90][Client][Startup] Menu asset preload failure: " .. tostring(failure))
	end
	for _, asset in assets do
		asset:Destroy()
	end
	player:SetAttribute("Beyond90MenuAssetsReady", true)
end

local sting = nil
local startupAssetId = AudioConfig.NormalizeAssetId(AudioConfig.Startup.AssetId)
if startupAssetId ~= "" then
	sting = Instance.new("Sound")
	sting.Name = "Beyond90StartupSting"
	sting.SoundId = startupAssetId
	sting.Volume = AudioConfig.Startup.Volume
	sting.Parent = SoundService
end

-- The sting is the timing-critical asset. Do not let an unrelated menu image
-- delay the branded sequence after the audio itself is ready.
local startupAssets = { logoBeyond, logoNinety }
if sting then
	table.insert(startupAssets, sting)
end
local startupLoaded = false
local startupFailure = nil
startupLoaded, startupFailure = preloadWithTimeout(startupAssets, ExperienceConfig.PreloadTimeout)
if sting then
	local soundWaitStartedAt = os.clock()
	while not sting.IsLoaded and os.clock() - soundWaitStartedAt < ExperienceConfig.PreloadTimeout do
		task.wait()
	end
	startupLoaded = startupLoaded and sting.IsLoaded
end
if not startupLoaded then
	warn("[Beyond90][Client][Startup] Startup sting preload failure: " .. tostring(startupFailure))
end
print(string.format(
	"[Beyond90][Client][Startup] Media ready=%s stingLoaded=%s",
	tostring(startupLoaded),
	tostring(sting ~= nil and sting.IsLoaded)
))
print("[Beyond90][Client][Startup] Drixil Interactive Presents")
tween(brand, 1.35, { TextTransparency = 0 })
tween(brandScale, 4.8, { Scale = 1 }, Enum.EasingStyle.Sine)
tween(presents, 1.25, { TextTransparency = 0.08 })
tween(accent, 1.4, { Size = UDim2.fromOffset(132, 2), BackgroundTransparency = 0.05 })
task.wait(4.65)
tween(brand, 0.9, { TextTransparency = 1 }, Enum.EasingStyle.Quad)
tween(presents, 0.8, { TextTransparency = 1 }, Enum.EasingStyle.Quad)
tween(accent, 0.8, { Size = UDim2.fromOffset(0, 2), BackgroundTransparency = 1 }, Enum.EasingStyle.Quad)
task.wait(1.05)
brand.Visible = false
presents.Visible = false
accent.Visible = false
task.wait(0.3)

if sting then
	sting.TimePosition = 0
	sting:Play()
end
print(string.format(
	"[Beyond90][Client][Startup] Beyond 90 sting=%s playing=%s volume=%.2f",
	if sting then sting.SoundId else "unavailable",
	tostring(sting ~= nil and sting.Playing),
	if sting then sting.Volume else 0
))
logo.Visible = true
tween(logo, 1.35, { GroupTransparency = 0 }, Enum.EasingStyle.Sine)
tween(logoScale, 2.8, { Scale = 1 }, Enum.EasingStyle.Sine)
task.wait(3.75)
tween(logo, 0.95, { GroupTransparency = 1 }, Enum.EasingStyle.Sine)
task.wait(1.05)

-- The opaque startup layer remains alive while the real Home screen mounts.
-- This prevents the Training loader or the 3D world from appearing between UIs.
preloadMenuAssets()
player:SetAttribute("Beyond90StartupReadyForMenu", true)
print("[Beyond90][Client][Startup] Waiting for mounted Home menu")
local menuWaitStartedAt = os.clock()
while player:GetAttribute("Beyond90MenuSurfaceMounted") ~= true
	and os.clock() - menuWaitStartedAt < ExperienceConfig.PreloadTimeout
do
	task.wait()
end
if player:GetAttribute("Beyond90MenuSurfaceMounted") ~= true then
	warn("[Beyond90][Client][Startup] Home menu mount timed out; revealing current client surface")
end

RunService.RenderStepped:Wait()
RunService.RenderStepped:Wait()
tween(background, ExperienceConfig.StartupHandoffDuration, { BackgroundTransparency = 1 }, Enum.EasingStyle.Sine)
task.wait(ExperienceConfig.StartupHandoffDuration + 0.05)
gui:Destroy()
if sting then
	sting:Destroy()
end
player:SetAttribute("Beyond90StartupComplete", true)
player:SetAttribute("Beyond90StartupSequenceActive", false)
print("[Beyond90][Client][Startup] Home menu handoff complete")
