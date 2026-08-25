local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local AudioConfig = require(ReplicatedStorage.Shared.Config.AudioConfig)
local ExperienceConfig = require(ReplicatedStorage.Shared.Config.ExperienceConfig)
local UIAssetConfig = require(ReplicatedStorage.Shared.Config.UIAssetConfig)

local StartupFallback = {}

local function tween(instance: Instance, duration: number, properties, style: Enum.EasingStyle?)
	local animation = TweenService:Create(
		instance,
		TweenInfo.new(duration, style or Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		properties
	)
	animation:Play()
	return animation
end

function StartupFallback.Run()
	local player = Players.LocalPlayer
	if player:GetAttribute("Beyond90StartupComplete") == true then
		return
	end
	if player:GetAttribute("Beyond90StartupSequenceActive") == true then
		local waitStartedAt = os.clock()
		while player:GetAttribute("Beyond90StartupReadyForMenu") ~= true
			and player:GetAttribute("Beyond90StartupComplete") ~= true
			and os.clock() - waitStartedAt < ExperienceConfig.PreloadTimeout + 30
		do
			task.wait()
		end
		if player:GetAttribute("Beyond90StartupReadyForMenu") == true
			or player:GetAttribute("Beyond90StartupComplete") == true
		then
			return
		end
		warn("[Beyond90][Client][Startup] ReplicatedFirst sequence timed out; using fallback")
	end

	player:SetAttribute("Beyond90StartupSequenceActive", true)
	player:SetAttribute("Beyond90StartupReadyForMenu", false)
	player:SetAttribute("Beyond90StartupComplete", false)

	local gui = Instance.new("ScreenGui")
	gui.Name = "Beyond90StartupFallback"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 2147483647
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Global
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")

	local background = Instance.new("Frame")
	background.Size = UDim2.fromScale(1, 1)
	background.BackgroundColor3 = Color3.fromRGB(2, 3, 8)
	background.BorderSizePixel = 0
	background.Parent = gui

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

	local logo = Instance.new("CanvasGroup")
	logo.AnchorPoint = Vector2.new(0.5, 0.5)
	logo.Position = UDim2.fromScale(0.5, 0.48)
	logo.Size = UDim2.new(0.46, 0, 0.3, 0)
	logo.BackgroundTransparency = 1
	logo.GroupTransparency = 1
	logo.ClipsDescendants = true
	logo.Visible = false
	logo.Parent = background
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

	local soundId = AudioConfig.NormalizeAssetId(AudioConfig.Startup.AssetId)
	local sting = nil
	if soundId ~= "" then
		sting = Instance.new("Sound")
		sting.Name = "Beyond90StartupFallbackSting"
		sting.SoundId = soundId
		sting.Volume = AudioConfig.Startup.Volume
		sting.Parent = SoundService
	end

	local startupAssets = { logoBeyond, logoNinety }
	if sting then
		table.insert(startupAssets, sting)
	end
	local preloadComplete = false
	local preloadOk = false
	local preloadFailure = nil
	if #startupAssets == 0 then
		preloadOk = true
		preloadComplete = true
	else
		task.spawn(function()
			preloadOk, preloadFailure = pcall(function()
				ContentProvider:PreloadAsync(startupAssets)
			end)
			preloadComplete = true
		end)
	end
	local preloadStartedAt = os.clock()
	while not preloadComplete and os.clock() - preloadStartedAt < ExperienceConfig.PreloadTimeout do
		task.wait()
	end
	if not preloadComplete or not preloadOk then
		warn("[Beyond90][Client][Startup] Fallback media preload failure: " .. tostring(preloadFailure or "timed out"))
	end
	print("[Beyond90][Client][Startup] Drixil Interactive Presents (fallback)")
	tween(brand, 1.35, { TextTransparency = 0 })
	tween(brandScale, 4.8, { Scale = 1 }, Enum.EasingStyle.Sine)
	tween(presents, 1.25, { TextTransparency = 0.08 })
	task.wait(4.65)
	tween(brand, 0.9, { TextTransparency = 1 }, Enum.EasingStyle.Quad)
	tween(presents, 0.8, { TextTransparency = 1 }, Enum.EasingStyle.Quad)
	task.wait(1.05)
	brand.Visible = false
	presents.Visible = false
	task.wait(0.3)

	if sting then
		sting.TimePosition = 0
		sting:Play()
	end
	print(string.format(
		"[Beyond90][Client][Startup] Beyond 90 fallback sting=%s playing=%s",
		if sting then sting.SoundId else "unavailable",
		tostring(sting ~= nil and sting.Playing)
	))
	logo.Visible = true
	tween(logo, 1.35, { GroupTransparency = 0 }, Enum.EasingStyle.Sine)
	tween(logoScale, 2.8, { Scale = 1 }, Enum.EasingStyle.Sine)
	task.wait(3.75)
	tween(logo, 0.95, { GroupTransparency = 1 }, Enum.EasingStyle.Sine)
	task.wait(1.05)

	player:SetAttribute("Beyond90StartupReadyForMenu", true)
	task.spawn(function()
		local menuWaitStartedAt = os.clock()
		while player:GetAttribute("Beyond90MenuSurfaceMounted") ~= true
			and os.clock() - menuWaitStartedAt < ExperienceConfig.PreloadTimeout
		do
			task.wait()
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
	end)
end

return StartupFallback
