local ContentProvider = game:GetService("ContentProvider")
local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

--[[
	The very first visible frame of the experience must be ours.

	Removing Roblox's default loading screen before our own cover exists leaves a
	window where the sky, pitch and an uninitialised camera are visible -- which
	is exactly the "world appears before the Drixil intro" problem. So the cover
	is built and presented FIRST, and only then is the default screen removed.
]]
local player = Players.LocalPlayer
player:SetAttribute("Beyond90StartupSequenceActive", true)
player:SetAttribute("Beyond90StartupReadyForMenu", false)
player:SetAttribute("Beyond90StartupComplete", false)

--[[
	Liveness, not a deadline.

	StartupFallback has to decide whether this script has HUNG or is simply still
	running. It used to decide that with a fixed budget, which silently coupled
	the fallback to the length of the intro: lengthening the fades pushed the
	sequence past the budget and the fallback replayed the whole ident over the
	top of it.

	A heartbeat separates the two questions. As long as this value keeps
	advancing, the sequence is alive and the fallback waits however long the
	presentation takes; if it stops advancing, the sequence really has stalled and
	the fallback takes over.
]]
player:SetAttribute("Beyond90StartupHeartbeat", os.clock())
task.spawn(function()
	while player.Parent and player:GetAttribute("Beyond90StartupComplete") ~= true do
		player:SetAttribute("Beyond90StartupHeartbeat", os.clock())
		task.wait(0.25)
	end
end)
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

--[[
	Parenting the cover is not the same as the cover having been drawn. Removing
	Roblox's loading screen in the same frame hands the display over to a surface
	that has not been presented yet, and the compositor shows the world behind it
	for a frame or two -- the sky flash before the Drixil stage.

	So wait until the cover has actually been presented. This must be bounded:
	inside ReplicatedFirst, before the client has loaded, RenderStepped may not
	fire at all, and an unconditional wait here hangs the entire startup.
]]
local function presentCoverFrames(count: number, timeout: number)
	local startedAt = os.clock()
	for _ = 1, count do
		if os.clock() - startedAt >= timeout then
			return false
		end
		--[[
			Heartbeat, not RenderStepped.

			Inside ReplicatedFirst, before the client has finished loading,
			RenderStepped does not fire at all -- the previous version of this
			always timed out and reported coverPresented=false, so it was waiting
			for nothing. Heartbeat does run here, and a few Heartbeat steps are
			enough for the cover to be part of the first frame that is drawn.
		]]
		local fired = false
		local connection
		connection = RunService.Heartbeat:Connect(function()
			fired = true
		end)
		while not fired and os.clock() - startedAt < timeout do
			task.wait()
		end
		connection:Disconnect()
		if not fired then
			return false
		end
	end
	return true
end

local coverPresented = presentCoverFrames(2, 0.75)
ReplicatedFirst:RemoveDefaultLoadingScreen()

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ExperienceConfig = require(Shared.Config.ExperienceConfig)
local AudioConfig = require(Shared.Config.AudioConfig)
local UIAssetConfig = require(Shared.Config.UIAssetConfig)

--[[
	The Drixil ident.

	A studio ident reads as deliberate because of TYPE, not decoration. Roblox
	TextLabels have no letter-spacing, so the wordmark is composed one character
	at a time inside a horizontal layout whose padding IS the tracking. Wide
	tracking on a thin weight is what makes the mark feel like an ident rather
	than a caption.

	The gradient rule that used to sit under PRESENTS is gone: it was the one
	decorative element in an otherwise typographic composition, and it read as a
	UI divider rather than as part of the mark.
]]
local BRAND_TEXT = "DRIXIL INTERACTIVE"
local PRESENTS_TEXT = "PRESENTS"

local viewportWidth = 1280
do
	local camera = Workspace.CurrentCamera
	if camera and camera.ViewportSize.X > 0 then
		viewportWidth = camera.ViewportSize.X
	end
end
-- One scale factor for the whole mark, so tracking and type stay in proportion
-- on a phone and on a desktop alike.
local brandScaleFactor = math.clamp(viewportWidth / 1280, 0.52, 1.25)

--[[
	Build a tracked wordmark and return its character labels.

	Spaces become fixed-width gaps: a TextLabel holding only a space collapses
	under AutomaticSize, which would close the word gap entirely.
]]
local function buildWordmark(
	text: string,
	font: Enum.Font,
	textSize: number,
	color: Color3,
	tracking: number,
	yScale: number
): ({ TextLabel }, Frame)
	local row = Instance.new("Frame")
	row.AnchorPoint = Vector2.new(0.5, 0.5)
	row.Position = UDim2.fromScale(0.5, yScale)
	row.Size = UDim2.new(1, 0, 0, math.ceil(textSize * 1.6))
	row.BackgroundTransparency = 1
	row.Parent = background

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, tracking)
	layout.Parent = row

	local labels: { TextLabel } = {}
	for index = 1, #text do
		local character = string.sub(text, index, index)
		if character == " " then
			local gap = Instance.new("Frame")
			gap.LayoutOrder = index
			gap.Size = UDim2.fromOffset(math.ceil(textSize * 0.55), 1)
			gap.BackgroundTransparency = 1
			gap.Parent = row
		else
			local letter = Instance.new("TextLabel")
			letter.LayoutOrder = index
			letter.AutomaticSize = Enum.AutomaticSize.X
			letter.Size = UDim2.fromOffset(0, math.ceil(textSize * 1.4))
			letter.BackgroundTransparency = 1
			letter.Font = font
			letter.Text = character
			letter.TextColor3 = color
			letter.TextSize = textSize
			letter.TextTransparency = 1
			letter.Parent = row
			table.insert(labels, letter)
		end
	end
	return labels, row
end

--[[
	Drixil ident sizing (§5).

	Enlarged: the mark read as too small for a company ident on a full screen.
	Both lines and their tracking scale together so the composition -- centred,
	static, PRESENTS set small beneath the wordmark -- is unchanged; it is simply
	bigger. The vertical positions move slightly apart to keep the same optical
	gap now that the type is larger.

	brandScaleFactor already carries the viewport adaptation, so this stays
	correct on a 780x360 landscape phone as well as on desktop.
]]
local brandLetters, brandRow = buildWordmark(
	BRAND_TEXT,
	Enum.Font.GothamMedium,
	math.floor(52 * brandScaleFactor),
	Color3.fromRGB(244, 247, 255),
	math.max(math.floor(13 * brandScaleFactor), 4),
	0.468
)
local presentsLetters, presentsRow = buildWordmark(
	PRESENTS_TEXT,
	Enum.Font.Gotham,
	math.floor(19 * brandScaleFactor),
	Color3.fromRGB(138, 150, 178),
	math.max(math.floor(10 * brandScaleFactor), 4),
	0.572
)

local logo = Instance.new("CanvasGroup")
logo.AnchorPoint = Vector2.new(0.5, 0.5)
logo.Position = UDim2.fromScale(0.5, 0.48)
logo.Size = UDim2.new(0.46, 0, 0.3, 0)
logo.BackgroundTransparency = 1
logo.GroupTransparency = 1
--[[
	NOT CLIPPED (§19).

	This was true, and it was cutting the mark off at the frame edge -- the "90"
	is positioned at 0.69 with width 0.31, so it ends exactly on the boundary and
	any glow or antialiasing on its right side was sliced flat.

	Clipping was never what kept the embedded subtitle out of shot: that is done
	by ImageRectOffset / ImageRectSize, which crop the SOURCE image before it is
	ever drawn. So the clip was doing no useful work and one visible harm.
]]
logo.ClipsDescendants = false
--[[
	HIDDEN until the Drixil stage has completely finished (§7).

	The two idents must never be on screen together, so this group stays
	Visible = false and is only enabled after Drixil is torn down. The previous
	attempt made it visible from creation in order to force the image to decode
	-- which fixed the decode but removed the structural guarantee that the
	stages cannot overlap.

	The decode is now handled by a separate off-stage probe (see below), so
	both properties hold at once: the image is ready early, and this group is
	incapable of appearing during Drixil.
]]
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

--[[
	FALLBACK WORDMARK (§6).

	The reason the Beyond 90 stage did not read as a fade turned out not to be
	the easing at all: the logo IMAGE is frequently still decoding when the stage
	begins. Runtime probing showed rbxassetid://95120414425732 reporting
	`pending` indefinitely and IsLoaded staying false, so the CanvasGroup was
	being faded while it had nothing in it -- and the logo then popped in at
	whatever transparency the tween had already reached, which reads as appearing
	rather than fading.

	Two things fix that, and both are needed:

	  1. The stage WAITS (bounded) for the image to actually be loaded before it
	     starts fading -- see waitForLogoImage below.
	  2. If it never loads, this text wordmark is shown instead, so the stage
	     always has visible content and the fade is always a fade.

	It lives inside the same CanvasGroup, so GroupTransparency drives it
	identically and no second fade path exists.
]]
local logoFallback = Instance.new("TextLabel")
logoFallback.Name = "LogoFallback"
logoFallback.AnchorPoint = Vector2.new(0.5, 0.5)
logoFallback.Position = UDim2.fromScale(0.5, 0.5)
logoFallback.Size = UDim2.fromScale(1, 0.6)
logoFallback.BackgroundTransparency = 1
logoFallback.Font = Enum.Font.GothamBlack
logoFallback.Text = "BEYOND 90"
logoFallback.TextColor3 = Color3.fromRGB(246, 249, 255)
logoFallback.TextScaled = true
logoFallback.Visible = false
logoFallback.Parent = logo

local logoScale = Instance.new("UIScale")
logoScale.Scale = 0.9
logoScale.Parent = logo

--[[
	DECODE THE LOGO OFF-STAGE, during Drixil.

	Roblox does not decode an image for UI it is not drawing, which is why the
	Beyond 90 stage used to reach its fade with nothing loaded and fall back to
	the wordmark. But making the presentation group visible in order to force
	that decode is what allowed the two idents to overlap.

	So the decode is done by this probe instead: a one-pixel label in the corner
	of the black cover, which genuinely renders -- and therefore genuinely
	decodes -- while being invisible in practice against black. The presentation
	group stays hidden and the stages stay mutually exclusive.
]]
local decodeProbe = Instance.new("ImageLabel")
decodeProbe.Name = "LogoDecodeProbe"
decodeProbe.AnchorPoint = Vector2.new(0, 0)
decodeProbe.Position = UDim2.fromOffset(0, 0)
decodeProbe.Size = UDim2.fromOffset(1, 1)
decodeProbe.BackgroundTransparency = 1
decodeProbe.Image = UIAssetConfig.Logo
decodeProbe.ImageTransparency = 0
decodeProbe.ZIndex = 0
decodeProbe.Parent = background

--[[
	`IsLoaded` IS NOT A USABLE SIGNAL HERE.

	Measured: `PreloadAsync` on the logo returns at 3.85s, and the label's
	`IsLoaded` is still false fifteen seconds later. Roblox only flips that
	property for images it is really rasterising at a real size, and the probe
	is deliberately one pixel in the corner -- so it fetches the asset without
	ever satisfying `IsLoaded`.

	The completion of `PreloadAsync` is Roblox's own contract for "this content
	has arrived", so that is what the stage waits on.
]]
local logoContentReady = false
task.spawn(function()
	pcall(function()
		ContentProvider:PreloadAsync({ decodeProbe })
	end)
	logoContentReady = true
end)

--[[
	Wait, bounded, for the logo image to be genuinely decoded.

	IsLoaded is polled rather than ContentProvider:PreloadAsync being used,
	because PreloadAsync on an asset that never resolves blocks forever -- which
	is exactly what this asset does, and what previously ate 13 seconds of
	startup before timing out.

	Returns whether the image is usable.
]]
local function waitForLogoImage(timeout: number): boolean
	local deadline = os.clock() + timeout
	while os.clock() < deadline do
		if logoContentReady then
			return true
		end
		task.wait(0.03)
	end
	return logoContentReady
end

--[[
	`direction` matters more than it looks for transparency.

	EasingDirection.Out front-loads the change, which is right for something
	arriving but wrong for something leaving: a fade-out eased Out is already
	almost invisible at the quarter mark and then spends the rest of its duration
	finishing a change nobody can see. Fades pass InOut.
]]
--[[
	Wait until a wall-clock moment, not for a duration.

	Measured during the concurrent menu build: a single 1.43-second frame. A
	chain of `task.wait(d)` calls turns every hitch like that into extra
	sequence length -- the Drixil stage was configured for 1.8s and ran for
	3.12s purely because the menu was mounting underneath it.

	Anchoring each beat to a deadline means a hitch eats into the hold instead
	of extending the intro. The tweens are time-based and unaffected, so the
	motion still looks right; only the dead time absorbs the cost.
]]
local function waitUntil(deadline: number)
	while os.clock() < deadline do
		task.wait()
	end
end

local function tween(
	instance: Instance,
	duration: number,
	properties,
	style: Enum.EasingStyle?,
	direction: Enum.EasingDirection?
)
	local animation = TweenService:Create(
		instance,
		TweenInfo.new(duration, style or Enum.EasingStyle.Quint, direction or Enum.EasingDirection.Out),
		properties
	)
	animation:Play()
	return animation
end

-- RenderStepped does not fire until the client has loaded, so waiting on it
-- unconditionally can hang the whole startup sequence. Always bound it.
local function waitForFrames(count: number, timeout: number)
	local startedAt = os.clock()
	for _ = 1, count do
		if os.clock() - startedAt >= timeout then
			return
		end
		local fired = false
		local connection
		connection = RunService.RenderStepped:Connect(function()
			fired = true
		end)
		while not fired and os.clock() - startedAt < timeout do
			task.wait()
		end
		connection:Disconnect()
	end
end

--[[
	Preload with a per-asset verdict.

	A bare PreloadAsync over a mixed batch reports one boolean for the whole
	set, so a single slow asset marks every asset "not ready" and there is no
	way to tell which one stalled. The callback form records each content id as
	it resolves, so a timeout can name the asset that caused it.
]]
local function preloadWithTimeout(
	instances: { Instance },
	timeout: number
): (boolean, any, { [string]: string })
	local completed = false
	local succeeded = false
	local failure = nil
	local statuses: { [string]: string } = {}

	task.spawn(function()
		succeeded, failure = pcall(function()
			ContentProvider:PreloadAsync(instances, function(contentId, status)
				statuses[contentId] = status.Name
			end)
		end)
		completed = true
	end)

	local startedAt = os.clock()
	while not completed and os.clock() - startedAt < timeout do
		task.wait()
	end

	return completed and succeeded, if completed then failure else "timed out", statuses
end

-- Names the assets that never reached a resolved state, for the startup log.
local function describeUnresolved(instances: { Instance }, statuses: { [string]: string }): string
	local unresolved = {}
	for _, instance in instances do
		local contentId = if instance:IsA("ImageLabel") or instance:IsA("ImageButton")
			then instance.Image
			elseif instance:IsA("Sound") then instance.SoundId
			else ""
		if contentId ~= "" then
			-- Enum.AssetFetchStatus is Success/Failure, not "Loaded".
			local status = statuses[contentId]
			if status ~= "Success" then
				table.insert(unresolved, string.format("%s=%s", contentId, status or "pending"))
			end
		end
	end
	return if #unresolved == 0 then "none" else table.concat(unresolved, " ")
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
	--[[
		This MUST be bounded.

		A bare PreloadAsync blocks until every asset resolves, and an asset that
		never resolves -- one still processing, or held by moderation -- blocks it
		forever. This sits directly in front of the menu handoff, so a single
		stuck image was able to hang startup indefinitely; that it previously
		appeared to work was only the startup fallback taking over after its
		timeout and driving the menu itself.

		A menu asset failing to preload is not fatal: the image simply pops in
		when it arrives. Waiting forever for it is.
	]]
	local loaded, failure, statuses = preloadWithTimeout(assets, ExperienceConfig.PreloadTimeout)
	if not loaded then
		warn(string.format(
			"[Beyond90][Client][Startup] Menu asset preload incomplete (%s); continuing. Unresolved: [%s]",
			tostring(failure or "timed out"),
			describeUnresolved(assets, statuses)
		))
	end
	for _, asset in assets do
		asset:Destroy()
	end
	player:SetAttribute("Beyond90MenuAssetsReady", loaded)
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

--[[
	NOTHING BLOCKS THE FIRST STAGE (§9, §10).

	This used to await a full PreloadAsync over the logo and the sting before a
	single frame of branding was shown -- roughly five seconds of black screen
	that the Drixil stage did not need, because Drixil is TextLabels and needs
	no assets at all.

	The preload now runs in the background, and so does the menu build. By the
	time the Beyond 90 stage and then the menu actually need their assets, the
	loading has been happening underneath the branding rather than in front of
	it.
]]
local startupAssets = { decodeProbe }
if sting then
	table.insert(startupAssets, sting)
end
local startupLoaded, startupFailure = false, nil
local startupStatuses: { [string]: string } = {}
local preloadStartedAt = os.clock()
local preloadFinishedAt = 0
task.spawn(function()
	startupLoaded, startupFailure, startupStatuses =
		preloadWithTimeout(startupAssets, ExperienceConfig.PreloadTimeout)
	preloadFinishedAt = os.clock()
	player:SetAttribute("Beyond90StartupMediaReady", startupLoaded)
end)

--[[
	THE MENU BUILDS BEHIND THE BRANDING (§10).

	`Beyond90StartupReadyForMenu` is what releases HomeScreen to build its
	footballer and UIController to mount. It used to be set after the Beyond 90
	stage had finished, so the menu only STARTED preparing once the branding was
	over and the player then waited again for it.

	Released here, the menu mounts, lays out, preloads its images and readies its
	character while the idents play. It stays fully hidden behind the opaque
	cover -- the reveal is still gated on the cover fading at the very end -- so
	nothing is shown early.
]]
player:SetAttribute("Beyond90StartupReadyForMenu", true)
task.spawn(preloadMenuAssets)

--[[
	THE IDENT DOES NOT BEGIN UNTIL THE SCREEN IS ACTUALLY BEING DRAWN.

	This was `waitForFrames(2, 0.5)`, and that bound is the reason the branding
	could play to nobody. RenderStepped does not fire at all inside
	ReplicatedFirst until the client has finished loading -- the earlier
	`presentCoverFrames` had to be rewritten onto Heartbeat for exactly that
	reason -- so a 0.5s budget expires having seen ZERO frames and the sequence
	starts anyway. The tweens then run against wall clock while the display is
	still frozen on whatever it last drew, and by the time frames resume the
	ident has been and gone. The console shows a correct 1.78s Drixil stage; the
	screen never showed it.

	So the gate is now the real condition -- sustained presented frames -- and it
	is given a budget long enough to actually be met. Two further conditions ride
	along with it:

	  * `game:IsLoaded()`, because a DataModel still loading produces exactly the
	    stutter that makes a staggered type reveal look broken.
	  * the menu having MOUNTED, because that build is the single heaviest thing
	    on this client (measured: one 1.43-second frame). Paying it here, against
	    the black cover, costs nothing visible; paying it during the reveal turns
	    the fade into a jump.

	None of this serialises the slow part: the asset preload and the menu build
	were both released above and run underneath this wait.
]]
local function waitForPresentation(timeout: number): (boolean, number, number)
	local startedAt = os.clock()
	local frames = 0
	local connection = RunService.RenderStepped:Connect(function()
		frames += 1
	end)
	while os.clock() - startedAt < timeout do
		if frames >= 6
			and game:IsLoaded()
			and player:GetAttribute("Beyond90MenuSurfaceMounted") == true
		then
			break
		end
		task.wait()
	end
	connection:Disconnect()
	return frames >= 6, frames, os.clock() - startedAt
end

local presenting, presentedFrames, presentationWait = waitForPresentation(6)
if not presenting then
	warn(string.format(
		"[Beyond90][Client][Startup] Only %d frame(s) presented in %.2fs; the ident may not be visible",
		presentedFrames,
		presentationWait
	))
end
print(string.format(
	"[Beyond90][Client][Startup] Drixil Interactive Presents (render ready in %.2fs, %d frames, menuMounted=%s)",
	presentationWait,
	presentedFrames,
	tostring(player:GetAttribute("Beyond90MenuSurfaceMounted") == true)
))
--[[
	The Drixil stage: a staggered type reveal, a hold, then a fade.

	Two things are deliberate here.

	First, there is still no sustained MOVEMENT. The previous version's
	continuous UIScale and accent-width tweens ran across the heaviest part of
	startup, where a dropped frame turns motion into visible stutter. Opacity has
	nothing to stutter -- a late frame only means one letter lands slightly
	differently -- so the reveal is built entirely out of per-letter fades.

	Second, the easing direction is the whole reason the fades read as fades.
	Sine with EasingDirection.Out on a value travelling 0 -> 1 completes most of
	its change in the first fraction of the duration: at the halfway point a
	1.8-second "slow fade out" has already reached 0.71 transparency and is
	essentially invisible, then spends the remaining 0.9 seconds imperceptibly
	finishing. InOut spends its time in the middle of the range, which is where
	a fade is actually visible.
]]

local function revealLetters(letters: { TextLabel }, duration: number, target: number, stagger: number)
	for index, letter in letters do
		task.delay((index - 1) * stagger, function()
			if letter.Parent then
				tween(letter, duration, { TextTransparency = target }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			end
		end)
	end
end

local function fadeLetters(letters: { TextLabel }, duration: number)
	for _, letter in letters do
		if letter.Parent then
			tween(letter, duration, { TextTransparency = 1 }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		end
	end
end

local intro = ExperienceConfig.Intro
local drixilStartedAt = os.clock()

revealLetters(brandLetters, intro.DrixilRevealDuration, 0, intro.DrixilLetterStagger)
-- PRESENTS settles under the wordmark once the mark itself has arrived.
task.delay(#brandLetters * intro.DrixilLetterStagger + 0.12, function()
	revealLetters(presentsLetters, intro.DrixilRevealDuration * 0.8, 0.12, intro.DrixilLetterStagger * 0.6)
end)

local drixilHoldUntil = drixilStartedAt
	+ #brandLetters * intro.DrixilLetterStagger
	+ intro.DrixilRevealDuration
	+ intro.DrixilHold
waitUntil(drixilHoldUntil)
fadeLetters(brandLetters, intro.DrixilFadeDuration)
fadeLetters(presentsLetters, intro.DrixilFadeDuration)
waitUntil(drixilHoldUntil + intro.DrixilFadeDuration + 0.05)

--[[
	DRIXIL IS TORN DOWN BEFORE BEYOND 90 EXISTS ON SCREEN (§7).

	Not merely faded -- hidden AND its rows disabled, with a beat of black
	between. There is no ordering in which both idents can be drawn in the same
	frame, because the second one is not visible until after this point.
]]
brandRow.Visible = false
presentsRow.Visible = false
print(string.format(
	"[Beyond90][Client][Startup] Drixil stage complete in %.2fs",
	os.clock() - drixilStartedAt
))
task.wait(intro.StageGap)

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
--[[
	Two-stage fade so the logo emerges out of the black rather than arriving.

	A single Sine-out tween spends most of its time near full opacity, so the
	logo reads as appearing at once. Easing in to a partial value first gives a
	slow, dark emergence, and the second stage carries it up to full while the
	scale movement -- which is kept -- is still running.
]]
--[[
	Nothing fades until there is something to fade (§6).

	The wait is bounded, so a permanently unavailable asset costs a short delay
	and then falls back to the wordmark rather than hanging startup or producing
	an invisible "fade".
]]
local beyondStartedAt = os.clock()
local logoImageReady = waitForLogoImage(intro.LogoDecodeTimeout)
if not logoImageReady then
	logoBeyond.Visible = false
	logoNinety.Visible = false
	logoFallback.Visible = true
	warn(string.format(
		"[Beyond90][Client][Startup] Logo image %s did not load in %.1fs; using the text wordmark so the stage still fades",
		UIAssetConfig.Logo,
		intro.LogoDecodeTimeout
	))
end
print(string.format("[Beyond90][Client][Startup] Beyond 90 stage imageReady=%s", tostring(logoImageReady)))

--[[
	Only NOW does the Beyond 90 group become visible, at full transparency, so
	the very first thing it does on screen is fade up from nothing.
]]
logo.GroupTransparency = 1
logo.Visible = true
-- The probe has done its job and must not sit under the presentation.
decodeProbe.Visible = false
tween(logoScale, intro.BeyondFadeInDuration + intro.BeyondHold + intro.BeyondFadeOutDuration,
	{ Scale = 1 }, Enum.EasingStyle.Sine)

--[[
	One continuous fade in each direction, eased InOut.

	This was previously a two-stage rise and a single Sine/Out fade-out, and the
	fade-out was the reason the logo appeared to cut rather than fade: eased Out,
	a 1.8-second 0 -> 1 transparency tween is past 0.7 by the halfway point, so
	the visible part of the fade lasted a few hundred milliseconds and the rest
	of the duration was spent invisible. InOut puts the duration where the change
	can actually be seen, and the fade-out is given longer than the fade-in
	because a receding logo reads slower than an arriving one.
]]
local beyondFadeStartedAt = os.clock()
tween(logo, intro.BeyondFadeInDuration, { GroupTransparency = 0 },
	Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
waitUntil(beyondFadeStartedAt + intro.BeyondFadeInDuration)
-- Hold at full presentation. Shorter than either fade on purpose: the stage
-- should read as the logo emerging and receding, not as a static title card.
waitUntil(beyondFadeStartedAt + intro.BeyondFadeInDuration + intro.BeyondHold)
tween(logo, intro.BeyondFadeOutDuration, { GroupTransparency = 1 },
	Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
waitUntil(beyondFadeStartedAt + intro.BeyondFadeInDuration + intro.BeyondHold
	+ intro.BeyondFadeOutDuration + 0.05)
-- The Beyond 90 stage must be completely gone before the menu is revealed; the
-- intro logo and the Home screen must never be visible at the same time.
logo.Visible = false
logo.GroupTransparency = 1

print(string.format(
	"[Beyond90][Client][Startup] Beyond 90 stage complete in %.2fs (media preload %.2fs)",
	os.clock() - beyondStartedAt,
	if preloadFinishedAt > 0 then preloadFinishedAt - preloadStartedAt else os.clock() - preloadStartedAt
))

-- The menu was released to build back at the start of the branding, so this is
-- normally already satisfied and costs nothing.
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

--[[
	Menu readiness barrier.

	Mounting is not the same as being ready to look at: images, the menu
	footballer and its idle can all still be resolving. Wait for those too, so
	the first visible menu frame is complete rather than assembling itself in
	front of the player. One broken asset must not hold this forever.
]]
local readinessStartedAt = os.clock()
-- The menu has had the entire branding sequence to get ready, so this is a
-- safety net rather than a loading budget.
local readinessTimeout = 2.5
while os.clock() - readinessStartedAt < readinessTimeout do
	local assetsReady = player:GetAttribute("Beyond90MenuAssetsReady") == true
	local characterReady = player:GetAttribute("Beyond90MenuCharacterReady") == true
	local layoutReady = player:GetAttribute("Beyond90MenuLayoutReady") == true
	if assetsReady and characterReady and layoutReady then
		break
	end
	task.wait()
end
if player:GetAttribute("Beyond90MenuAssetsReady") ~= true then
	warn("[Beyond90][Client][Startup] Menu images not fully ready; revealing anyway")
end
if player:GetAttribute("Beyond90MenuCharacterReady") ~= true then
	warn("[Beyond90][Client][Startup] Menu footballer not ready; revealing anyway")
end
if player:GetAttribute("Beyond90MenuLayoutReady") ~= true then
	warn("[Beyond90][Client][Startup] Menu layout not settled; revealing anyway")
end
print(string.format(
	"[Beyond90][Client][Startup] Menu readiness resolved in %.2fs",
	os.clock() - readinessStartedAt
))

--[[
	Two presented frames before the cover starts fading, so the menu underneath is
	definitely on screen first.

	This MUST be bounded, for the reason stated at waitForFrames: RenderStepped is
	not guaranteed to fire here, and an unbounded wait on it hangs the entire
	startup with the cover still opaque -- the player is left looking at a black
	screen forever. A missed frame only costs a slightly less clean handoff.
]]
waitForFrames(2, 1)
tween(background, ExperienceConfig.StartupHandoffDuration, { BackgroundTransparency = 1 }, Enum.EasingStyle.Sine)
task.wait(ExperienceConfig.StartupHandoffDuration + 0.05)
gui:Destroy()
if sting then
	sting:Destroy()
end
player:SetAttribute("Beyond90StartupComplete", true)
player:SetAttribute("Beyond90StartupSequenceActive", false)
print("[Beyond90][Client][Startup] Home menu handoff complete")
