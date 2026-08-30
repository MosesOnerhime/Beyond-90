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

--[[
	THE PRESENTATION IS BUILT DETACHED, AND ATTACHED ONLY WHEN IT CAN BE SEEN.

	This is the root cause of "the intro never plays". It took a screen capture
	to find, because every log said it was working.

	A ScreenGui parented from ReplicatedFirst does not survive as a drawable
	surface. Traced at the moment the Drixil stage began:

		guiEnabled=true cover=true coverAlpha=0.00 coverSize=0, 0

	Zero pixels wide -- enabled, visible, opaque black, and attached to nothing
	that is rendered. Every stage then ran perfectly on a canvas with no
	dimensions, at a healthy 60 FPS, which is exactly why the screen showed the
	sky straight through where the cover should have been while the log looked
	clean.

	Three repair attempts failed and each was informative:

	  * re-parenting gives "The Parent property of Beyond90StartupLoading is
	    locked, current parent: NULL" -- confirming the orphaning outright;
	  * moving the children fails for the same reason, since ReplicatedFirst
	    instances are parent-locked wholesale;
	  * attaching to a freshly found PlayerGui measures correctly at first and
	    then returns to 0 x 0 a moment later.

	Meanwhile a ScreenGui created once the client is up measures correctly every
	time. So the fix is to stop attaching early at all: the whole presentation is
	assembled with no parent -- which is legal, keeps every instance unlocked,
	and costs nothing -- and is attached to a live PlayerGui only once the client
	is genuinely rendering.

	Nothing is uncovered in the meantime, because Roblox's own default loading
	screen is deliberately left up until our cover is proven to have pixels.
]]
local playerGui = player:WaitForChild("PlayerGui")

--[[
	The ident is built into a CLIENT-OWNED ScreenGui, created by ClientBootstrap.

	See the long note there for why: a ScreenGui parented into PlayerGui by a
	ReplicatedFirst script is adopted by Roblox as the loading screen and is
	un-parented and permanently locked the moment loading completes, which is
	several seconds before a branding sequence has finished. Everything drawn
	after that point went into an orphan -- visible in the trace as coverSize
	going from 1170x550 to 0x0 between the two stages.

	Detached until it is attached below, so nothing is ever parented into a
	PlayerGui that might be discarded.
]]
local gui: ScreenGui = Instance.new("ScreenGui")
gui.Name = "Beyond90StartupLoading"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 2147483647
gui.ZIndexBehavior = Enum.ZIndexBehavior.Global

local background = Instance.new("Frame")
background.Size = UDim2.fromScale(1, 1)
background.BackgroundColor3 = Color3.fromRGB(2, 3, 8)
background.BorderSizePixel = 0
background.Parent = gui

--[[
	Attach the finished surface to whichever PlayerGui is live, and report
	whether it actually gained pixels.
]]
local lastAttachDiagnostic = "not attempted"

local function attachSurface(): boolean
	local livePlayerGui = player:FindFirstChildOfClass("PlayerGui")
	if not livePlayerGui then
		lastAttachDiagnostic = "no live PlayerGui"
		return false
	end

	--[[
		ATTACH INTO THE CLIENT-OWNED SURFACE.

		`Beyond90StartupSurface` is created by ClientBootstrap, which Roblox does
		not treat specially, so a GUI inside it survives the end of loading. Our
		own ScreenGui is parented into it rather than into PlayerGui directly --
		which is the parenting Roblox adopts and then destroys.

		Falls back to PlayerGui if the surface is somehow unavailable. That path
		is the old behaviour and will still lose the ident at the end of loading,
		but a first stage that draws beats a sequence that never appears at all.
	]]
	local host: Instance = livePlayerGui
	local clientSurface = livePlayerGui:FindFirstChild("Beyond90StartupSurface")
	if clientSurface and clientSurface:IsA("ScreenGui") then
		host = clientSurface
	end

	if gui.Parent == host then
		--[[
			Already attached to the PlayerGui that is live, and still without
			pixels. Re-setting the same parent achieves nothing, so say so
			plainly rather than reporting a failed attach that never happened.
		]]
		RunService.Heartbeat:Wait()
		if background.AbsoluteSize.X > 1 and background.AbsoluteSize.Y > 1 then
			lastAttachDiagnostic = "already attached, has pixels"
			return true
		end
		lastAttachDiagnostic = string.format(
			"attached to %s but measuring %s (viewport %s)",
			host.Name,
			tostring(background.AbsoluteSize),
			if Workspace.CurrentCamera then tostring(Workspace.CurrentCamera.ViewportSize) else "no camera"
		)
		return false
	end
	local ok, failure = pcall(function()
		gui.Parent = host
	end)
	if not ok then
		lastAttachDiagnostic = "parent rejected: " .. tostring(failure)
		return false
	end
	RunService.Heartbeat:Wait()
	if background.AbsoluteSize.X > 1 and background.AbsoluteSize.Y > 1 then
		lastAttachDiagnostic = "re-attached, has pixels"
		return true
	end
	lastAttachDiagnostic = string.format("re-attached but measuring %s", tostring(background.AbsoluteSize))
	return false
end

--[[
	Parenting the cover is not the same as the cover having been drawn. Removing
	Roblox's loading screen in the same frame hands the display over to a surface
	that has not been presented yet, and the compositor shows the world behind it
	for a frame or two -- the sky flash before the Drixil stage.

	So wait until the cover has actually been presented. This must be bounded:
	inside ReplicatedFirst, before the client has loaded, RenderStepped may not
	fire at all, and an unconditional wait here hangs the entire startup.
]]
--[[
	KEEP THE SURFACE ALIVE FOR THE WHOLE SEQUENCE, NOT JUST ITS FIRST FRAME.

	Attaching once and assuming it holds is not enough, and the self-trace caught
	exactly why. On a cold start the two stages reported:

		Drixil    coverSize=1170.40002, 550.400024
		Beyond90  coverSize=0, 0

	Same ScreenGui, same Enabled flag, same everything -- and no pixels by the
	second stage. The PlayerGui that was live when the ident began had been
	discarded and replaced underneath it, which is the same failure the original
	attach was written to survive; it simply happens LATER as well as earlier,
	once the client finishes loading.

	So the surface is re-verified, and re-attached to whatever PlayerGui is live
	now, before each stage draws. Cheap -- one AbsoluteSize read in the common
	case -- and it converts a silently invisible ident into one that repairs
	itself.

	Returns whether the surface has pixels afterwards, so a caller can log the
	truth rather than assume it.
]]
local function ensureSurface(): boolean
	if background.AbsoluteSize.X > 1 and background.AbsoluteSize.Y > 1 then
		return true
	end
	for _ = 1, 10 do
		if attachSurface() then
			return true
		end
		task.wait(0.05)
	end
	player:SetAttribute("Beyond90StartupSurfaceDiagnostic", lastAttachDiagnostic)
	return false
end

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

--[[
	ROBLOX'S LOADING SCREEN STAYS UP UNTIL OUR COVER IS REAL.

	Removing it here is what uncovered the world -- the sky flash. Our surface is
	not even attached yet at this point, so removing Roblox's cover now would
	leave nothing in front of the camera at all. It is removed further down, the
	moment our own cover is attached AND measured.
]]
local coverPresented = false

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

--[[
	The card's resting position, and the small offset it settles up from.

	Held as values rather than as a UIScale on purpose -- see
	ExperienceConfig.Intro.DrixilSettleOffset for why scaling this particular
	content is expensive and moving it is free.

	Both rows share one offset and one duration so the wordmark and PRESENTS
	arrive as a single card rather than as two independently animated lines.
]]
local drixilSettleOffset = math.max(
	math.floor(ExperienceConfig.Intro.DrixilSettleOffset * brandScaleFactor),
	1
)
local brandRestPosition = brandRow.Position
local presentsRestPosition = presentsRow.Position
brandRow.Position = brandRestPosition + UDim2.fromOffset(0, drixilSettleOffset)
presentsRow.Position = presentsRestPosition + UDim2.fromOffset(0, drixilSettleOffset)

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

	Its IMAGES are fetched here, because that is pure network work with nothing
	on screen to show for it and the loading window is free time.

	Its REVEAL is not released here, and that distinction is the bug that was
	visible as a flash of menu immediately before the ident.

	`Beyond90StartupReadyForMenu` does not merely permit the menu to build -- the
	menu builds on mount regardless. What it actually does is start HomeScreen's
	2.25-second reveal tween. Setting it at this point was safe only while the
	cover was attached from the first instant; now that the cover cannot hold
	pixels until the client viewport exists, there is a real window here in which
	Roblox has dropped its own loading screen, our cover is not up yet, and the
	menu is already fading in. The player sees the menu, and then the intro
	covers it back up.

	So the release moves to the far side of the attach, below. The menu still
	spends the entire branding sequence getting ready; it simply cannot begin
	showing itself until there is something in front of it.
]]
task.spawn(preloadMenuAssets)

--[[
	THE IDENT DOES NOT BEGIN UNTIL THE SCREEN IS GENUINELY BEING PRESENTED.

	This gate has now been wrong twice, in two different ways, and the second way
	is only visible from an actual screen capture rather than from a log.

	Attempt one waited for two RenderStepped frames with a 0.5s budget.
	RenderStepped does not fire at all in ReplicatedFirst before the client has
	loaded, so the budget expired having seen zero frames and the ident played
	against a frozen display.

	Attempt two waited for six frames. It reported "render ready in 5.19s, 6
	frames" and looked fixed. Capturing the Studio window during startup shows
	what that number actually meant: six frames in 5.19 seconds is 1.2 FPS. The
	session was stepping, but the viewport was not being presented -- Studio was
	still showing the Edit view, and swapped to the play viewport about seven
	seconds in, by which point the ident had been and gone.

	A COUNT of frames cannot tell those apart. A RATE can: a viewport nobody is
	looking at ticks over at a frame or two per second, and one that is genuinely
	on screen runs at tens. So this waits for a sustained real frame rate, which
	is the closest honest proxy available for "a person can see this now", and it
	is satisfied almost immediately in a real client.

	Note what is deliberately NOT here any more: the menu-mounted condition. The
	startup contract is supposed to be that the ident begins as soon as the
	startup UI can render, with the menu building behind it -- gating the ident on
	the menu inverted that, and stacking readiness conditions onto a brittle intro
	is what made it fragile in the first place.
]]
local function waitForLivePresentation(timeout: number): (boolean, number, number)
	local startedAt = os.clock()
	local healAttempts = 0
	local lastHealAt = 0
	local frames = 0
	local windowStartedAt = os.clock()
	local windowFrames = 0
	local bestRate = 0
	local connection = RunService.RenderStepped:Connect(function()
		frames += 1
		windowFrames += 1
	end)
	while os.clock() - startedAt < timeout do
		--[[
			THE DECISIVE CONDITION: DOES THE COVER HAVE A SIZE?

			This is what was actually wrong, and no amount of frame counting would
			have found it. Tracing the rendered objects at the moment the Drixil
			stage began reported:

				guiEnabled=true cover=true coverAlpha=0.00 coverSize=0, 0

			The cover was enabled, opaque and visible -- and zero pixels wide. A
			ScreenGui's children measure against the viewport, and inside
			ReplicatedFirst the PlayerGui exists before the client's viewport does,
			so `Size = fromScale(1, 1)` resolves to nothing. Every stage then ran
			perfectly, on a canvas with no dimensions, drawing nothing at all --
			which is exactly why the logs looked healthy while the screen showed the
			sky straight through where the black cover was supposed to be.

			A non-zero AbsoluteSize is direct evidence that this GUI occupies real
			pixels. Nothing is allowed to start before it does.
		]]
		--[[
			The surface is still detached at this point, so there is nothing to
			measure yet. What is being waited for is the CLIENT being live enough
			that attaching will work -- a real viewport, the DataModel loaded, and
			a genuine frame rate. The attach and its proof happen immediately
			after this loop.
		]]
		local camera = Workspace.CurrentCamera
		local laidOut = camera ~= nil and camera.ViewportSize.Y > 1

		--[[
			And a live frame RATE, not a frame count.

			The previous attempt waited for six frames and reported "6 frames in
			5.19s" as success. That is 1.2 FPS -- the signature of a viewport that is
			stepping but not being presented to anyone, which is precisely what
			Studio does while it is still showing the Edit view. A rate tells the two
			apart; a count cannot.
		]]
		local elapsed = os.clock() - windowStartedAt
		if elapsed >= 0.4 then
			local rate = windowFrames / elapsed
			bestRate = math.max(bestRate, rate)
			if laidOut and rate >= 12 and game:IsLoaded() then
				break
			end
			windowStartedAt = os.clock()
			windowFrames = 0
		end
		task.wait()
	end
	connection:Disconnect()
	return bestRate >= 12, bestRate, os.clock() - startedAt
end

local presenting, presentedRate, presentationWait = waitForLivePresentation(12)

--[[
	ATTACH, and only now stop relying on Roblox's loading screen.

	Retried briefly: the first PlayerGui offered during startup is sometimes the
	one that gets discarded, and attaching to that is what produced a cover with
	no pixels. A surface that measures is the only accepted proof.
]]
--[[
	RELEASE THE LOADING-SCREEN SLOT *BEFORE* ATTACHING. THIS ORDER IS THE FIX.

	The ident was playing its first stage correctly and then going blank, and the
	self-trace and the attach diagnostic together said exactly why:

		Drixil    coverSize=1170.40002, 550.400024
		Beyond90  coverSize=0, 0
		attach    "The Parent property of Beyond90StartupLoading is locked,
		           current parent: NULL, new parent PlayerGui"

	Parent NULL, and locked. Nothing in this script orphaned it -- ROBLOX did.

	A ScreenGui parented into PlayerGui from ReplicatedFirst while Roblox is
	still managing a loading screen is ADOPTED as that loading screen. Roblox
	then owns its lifetime: when loading completes it un-parents it and locks the
	instance, permanently, so it can never be re-attached. The first stage drew
	because it ran before that moment; everything after it drew into an orphan.

	`RemoveDefaultLoadingScreen` is what hands that slot back. Called FIRST,
	Roblox has no loading screen to manage, and the GUI attached immediately
	afterwards is an ordinary ScreenGui with an ordinary lifetime -- ours, for
	as long as the sequence needs it.

	Nothing is exposed by the reordering. This point is already past
	`game:IsLoaded()` and a sustained real frame rate, the menu's own root frame
	is mounted and opaque behind us, and the attach happens in the same frame,
	so there is no window in which the pitch is visible.
]]
ReplicatedFirst:RemoveDefaultLoadingScreen()

--[[
	Wait, briefly, for the client-owned surface. ClientBootstrap creates it as
	its very first act, so by this point -- past game:IsLoaded() and a sustained
	frame rate -- it is normally already there. Bounded, because the fallback of
	attaching straight to PlayerGui is still better than not drawing at all.
]]
do
	local waitStartedAt = os.clock()
	while os.clock() - waitStartedAt < 3 do
		local livePlayerGui = player:FindFirstChildOfClass("PlayerGui")
		if livePlayerGui and livePlayerGui:FindFirstChild("Beyond90StartupSurface") then
			break
		end
		task.wait(0.05)
	end
end

local attached = false
for _ = 1, 20 do
	if attachSurface() then
		attached = true
		break
	end
	task.wait(0.1)
end
coverPresented = attached
if attached then
	presentCoverFrames(2, 0.75)
else
	warn(string.format(
		"[Beyond90][Client][Startup] Startup surface never gained pixels (%s)",
		lastAttachDiagnostic
	))
end

--[[
	THE MENU MAY BUILD -- BUT NOT DURING A MOVING FRAME.

	Releasing this is what lets the rest of the client start: StartupFallback is
	blocked on it, and the moment it clears, ClientBootstrap runs
	ExperienceFlowController.Initialize(), which mounts the entire React menu
	tree (Home, its ViewportFrame and the character rig inside it) and builds
	the audio bank. React's first mount is synchronous, so that is ONE very long
	frame -- measured at 151ms, roughly nine frames' worth.

	Released here, that frame landed precisely on the Drixil letter reveal,
	because this line sits immediately before the stage that types the wordmark
	on. A 151ms freeze in the middle of a 3.2-second type-on is exactly what
	"the intro stutters" describes, and no amount of making the ANIMATION
	cheaper can hide a stall that belongs to the whole client.

	So the release moves to the one place in the sequence where a long frame
	costs nothing: the static hold after every letter has arrived. Nothing is
	moving then, and there is still roughly five seconds of ident left for the
	menu to finish building behind -- it currently resolves with time to spare
	("Menu readiness resolved in 0.00s").

	The failure branch keeps the old behaviour. If the cover never gained
	pixels there is no animation to protect, and the player must still reach a
	usable menu.
]]
local menuBuildDeferred = coverPresented and presenting
if not menuBuildDeferred then
	player:SetAttribute("Beyond90StartupReadyForMenu", true)
end
if not presenting then
	warn(string.format(
		"[Beyond90][Client][Startup] Client never reached a live display (cover %s, best %.1f FPS in %.2fs); the ident may not be visible",
		tostring(background.AbsoluteSize),
		presentedRate,
		presentationWait
	))
end

--[[
	SELF-TRACE.

	A log line saying a stage ran is not evidence that anything was on screen --
	that is precisely the trap the last two attempts fell into. So each stage
	records what was actually TRUE OF THE RENDERED OBJECTS at the moment it ran,
	and leaves it on the player where it can be read after the fact.
]]
local function traceStage(stage: string, extra: string?)
	local letter = brandLetters[1]
	player:SetAttribute("Beyond90StartupTrace_" .. stage, string.format(
		"guiEnabled=%s cover=%s coverAlpha=%.2f coverSize=%s brandRow=%s letterAlpha=%.2f logoVisible=%s logoAlpha=%.2f %s",
		tostring(gui.Enabled),
		tostring(background.Visible),
		background.BackgroundTransparency,
		tostring(background.AbsoluteSize),
		tostring(brandRow.Visible),
		if letter then letter.TextTransparency else -1,
		tostring(logo.Visible),
		logo.GroupTransparency,
		extra or ""
	))
end

print(string.format(
	"[Beyond90][Client][Startup] Drixil Interactive Presents (surface %s live in %.2fs at %.1f FPS)",
	tostring(background.AbsoluteSize),
	presentationWait,
	presentedRate
))
--[[
	Re-verified here rather than trusted: the attach happened before the client
	had finished loading, and the PlayerGui it attached to may not be the one
	that is live now.
]]
if not ensureSurface() then
	warn("[Beyond90][Client][Startup] Drixil stage has no drawable surface")
end
traceStage("Drixil")
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

--[[
	MEASURE THE STAGE, so "it stutters" becomes a number.

	The stage already reported the frame rate it STARTED at, which is what made
	the last diagnosis a guess: an average says nothing about a hitch, and a
	single long frame in the middle of a two-second reveal is exactly what a
	viewer calls stutter. So track the worst frame the stage actually served.

	One Heartbeat connection holding three numbers -- cheap enough that it
	cannot become part of the problem it exists to measure.
]]
local drixilRevealDoneAt = drixilStartedAt
	+ #brandLetters * intro.DrixilLetterStagger
	+ intro.DrixilRevealDuration

local drixilFrames, drixilWorstMoving, drixilWorstStill = 0, 0, 0
local drixilFrameConnection = RunService.Heartbeat:Connect(function(deltaTime: number)
	drixilFrames += 1
	--[[
		Split at the end of the reveal, because the two windows have completely
		different tolerances and one number cannot describe both. A long frame
		while the letters are arriving is the stutter being reported; the same
		frame during the static hold is invisible and is exactly where the
		client's own startup work has been moved to.
	]]
	if os.clock() < drixilRevealDoneAt then
		if deltaTime > drixilWorstMoving then
			drixilWorstMoving = deltaTime
		end
	elseif deltaTime > drixilWorstStill then
		drixilWorstStill = deltaTime
	end
end)

--[[
	The card settles into place as the letters arrive, then stops moving.

	It finishes with the last letter rather than running through the hold. A
	still card is the point of the hold -- and the less time any motion spends
	over the heaviest part of startup, the less there is to drop a frame in.

	Quint/Out, so almost all of the travel happens immediately and the last
	pixel is a long way from the first: that is what reads as settling rather
	than sliding.
]]
local drixilSettleDuration = #brandLetters * intro.DrixilLetterStagger
	+ intro.DrixilRevealDuration
tween(brandRow, drixilSettleDuration, { Position = brandRestPosition })
tween(presentsRow, drixilSettleDuration, { Position = presentsRestPosition })

revealLetters(brandLetters, intro.DrixilRevealDuration, 0, intro.DrixilLetterStagger)
-- PRESENTS settles under the wordmark once the mark itself has arrived.
task.delay(#brandLetters * intro.DrixilLetterStagger + 0.12, function()
	revealLetters(presentsLetters, intro.DrixilRevealDuration * 0.8, 0.12, intro.DrixilLetterStagger * 0.6)
end)

--[[
	Every letter has landed and the card has stopped moving. This is the quiet
	window -- see the release note above for why the rest of the client is
	deliberately started HERE rather than before the reveal.
]]
if menuBuildDeferred then
	waitUntil(drixilRevealDoneAt)
	player:SetAttribute("Beyond90StartupReadyForMenu", true)
end

local drixilHoldUntil = drixilRevealDoneAt + intro.DrixilHold
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
drixilFrameConnection:Disconnect()
local drixilElapsed = os.clock() - drixilStartedAt
print(string.format(
	"[Beyond90][Client][Startup] Drixil stage complete in %.2fs (%d frames, %.1f FPS mean, worst frame: reveal %.0fms / hold %.0fms, menuBuildDeferred=%s)",
	drixilElapsed,
	drixilFrames,
	if drixilElapsed > 0 then drixilFrames / drixilElapsed else 0,
	drixilWorstMoving * 1000,
	drixilWorstStill * 1000,
	tostring(menuBuildDeferred)
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
-- The stage that was measuring 0x0. See ensureSurface.
local beyondSurfaceOk = ensureSurface()
if not beyondSurfaceOk then
	warn("[Beyond90][Client][Startup] Beyond 90 stage has no drawable surface")
end
print(string.format(
	"[Beyond90][Client][Startup] Beyond 90 stage imageReady=%s surface=%s",
	tostring(logoImageReady),
	tostring(background.AbsoluteSize)
))
traceStage("Beyond90", string.format("imageReady=%s", tostring(logoImageReady)))

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

--[[
	A beat of black before anything else happens.

	The ident is finished; the menu has not started arriving. Without this the
	two overlap and the fade-out reads as having been cut off by the handoff.
]]
task.wait(intro.PostBeyondHold)

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
-- A cover that has lost its surface cannot fade off it, and the handoff would
-- read as the menu appearing abruptly out of nothing.
ensureSurface()
tween(background, ExperienceConfig.StartupHandoffDuration, { BackgroundTransparency = 1 }, Enum.EasingStyle.Sine)
task.wait(ExperienceConfig.StartupHandoffDuration + 0.05)
gui:Destroy()
if sting then
	sting:Destroy()
end
player:SetAttribute("Beyond90StartupComplete", true)
player:SetAttribute("Beyond90StartupSequenceActive", false)
print("[Beyond90][Client][Startup] Home menu handoff complete")
