local ContentProvider = game:GetService("ContentProvider")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ReactPackages = require(Shared.ReactPackages)
local React = ReactPackages.React
local ReactRoblox = ReactPackages.ReactRoblox
local FootballActionConfig = require(Shared.Config.FootballActionConfig)
local GoalConfig = require(Shared.Config.GoalConfig)
local UIAssetConfig = require(Shared.Config.UIAssetConfig)
local GameplayHUD = require(script.Parent.Screens.GameplayHUD)
local GoalNotification = require(script.Parent.Screens.GoalNotification)
local HomeScreen = require(script.Parent.Screens.HomeScreen)
local LoadingScreen = require(script.Parent.Screens.LoadingScreen)
local TrainingScreen = require(script.Parent.Screens.TrainingScreen)
local TeamSelectionScreen = require(script.Parent.Screens.TeamSelectionScreen)
local SettingsScreen = require(script.Parent.Screens.SettingsScreen)
local PositionSelectionScreen = require(script.Parent.Screens.PositionSelectionScreen)
local ControlSchemeScreen = require(script.Parent.Screens.ControlSchemeScreen)
local PlayScreen = require(script.Parent.Screens.PlayScreen)
local ClubsScreen = require(script.Parent.Screens.ClubsScreen)
local ProfileScreen = require(script.Parent.Screens.ProfileScreen)
local ControlSchemeConfig = require(ReplicatedStorage.Shared.Config.ControlSchemeConfig)
local MenuKit = require(script.Parent.Components.MenuKit)
local ControlSchemeController = require(script.Parent.Parent.Controllers.ControlSchemeController)
local PositionConfig = require(Shared.Config.PositionConfig)
local Theme = require(script.Parent.Theme)
local ReactUI = require(script.Parent.Components.ReactUI)

local CameraController = require(script.Parent.Parent.Camera.CameraController)
local PlayerConfig = require(ReplicatedStorage.Shared.Config.PlayerConfig)

local UIController = {}
local localPlayer = Players.LocalPlayer
local root = nil
local remoteConnection: RBXScriptConnection? = nil
local setScreenState = nil
local setLoadingState = nil
local setToastState = nil
local setGoalState = nil

local function preloadMenuAssets()
	local images = {}
	local function collect(value)
		if type(value) == "table" then
			for key, child in value do
				if key ~= "LocalSources" then collect(child) end
			end
		elseif type(value) == "string" and string.match(value, "^rbxassetid://%d+$") then
			local image = Instance.new("ImageLabel")
			image.Image = value
			table.insert(images, image)
		end
	end
	collect(UIAssetConfig)

	-- Per-asset verdict, so a menu image that never resolves can be named in the
	-- startup log instead of disappearing into one boolean.
	local unresolved = {}
	local ok, failure = pcall(function()
		ContentProvider:PreloadAsync(images, function(contentId, status)
			if status ~= Enum.AssetFetchStatus.Success then
				table.insert(unresolved, string.format("%s=%s", contentId, status.Name))
			end
		end)
	end)
	if not ok then warn("[Beyond90][UI] Menu preload failure: " .. tostring(failure)) end
	if #unresolved > 0 then
		warn("[Beyond90][UI] Menu images unresolved: " .. table.concat(unresolved, " "))
	end
	for _, image in images do image:Destroy() end
	localPlayer:SetAttribute("Beyond90MenuAssetsReady", true)
end

--[[
	Layout readiness.

	A React effect fires when the tree has been committed, not when Roblox has
	measured and drawn it, so Beyond90MenuSurfaceMounted goes true while the menu
	is still resolving its sizes. Revealing on that alone is what makes the menu
	visibly finish assembling in front of the player.

	Waiting for the root frame to report a real AbsoluteSize, and then for a
	presented frame, means the first menu frame the player sees is already laid
	out. Bounded so a layout that never settles cannot hold the reveal forever.
]]
local function awaitMenuLayout(rootFrame: Instance?)
	task.spawn(function()
		local startedAt = os.clock()
		local timeout = 4

		while os.clock() - startedAt < timeout do
			local frame = rootFrame
			if frame and frame:IsA("GuiObject") and frame.AbsoluteSize.X > 0 and frame.AbsoluteSize.Y > 0 then
				break
			end
			task.wait()
		end

		-- One presented frame after layout settles, so the first visible frame is
		-- drawn rather than merely measured.
		RunService.RenderStepped:Wait()

		if os.clock() - startedAt >= timeout then
			warn("[Beyond90][UI] Menu layout did not settle within timeout; revealing anyway")
		end
		localPlayer:SetAttribute("Beyond90MenuLayoutReady", true)
	end)
end

local function App(props)
	local callbacks = props.Callbacks
	local function click()
		if callbacks.PlayClick then callbacks.PlayClick() end
	end
	local screen, setScreen = React.useState("Home")
	local loading, setLoading = React.useState({
		Variant = "Training", Mode = "TRAINING", Detail = "FREE PRACTICE",
		Status = "PREPARING TRAINING", Progress = 0.12,
	})
	local toast, setToast = React.useState(false)
	local goalVisible, setGoalVisible = React.useState(false)
	--[[
		DEFAULT CAMERA (§21, §64). Session-scoped: seeded from CameraController,
		written straight back to it, no persistence layer invented for it.
	]]
	local defaultCamera, setDefaultCamera = React.useState(CameraController.GetDefaultMode())

	--[[
		WHICH BODY THE PLAYER WEARS (§23-§29).

		Seeded from the server's own attribute rather than from a local default,
		so the menu shows what the player will actually spawn as. The server owns
		the value -- the client asks over a remote and the attribute change comes
		back down, which is why the setter does not write the state directly.
	]]
	local identityConfig = PlayerConfig.Appearance.Identity
	local avatarSource, setAvatarSource = React.useState(function()
		local stored = localPlayer:GetAttribute(identityConfig.AttributeName)
		return if typeof(stored) == "string" and identityConfig.Sources[stored]
			then stored
			else identityConfig.Default
	end)
	React.useEffect(function()
		local connection = localPlayer:GetAttributeChangedSignal(identityConfig.AttributeName):Connect(function()
			local stored = localPlayer:GetAttribute(identityConfig.AttributeName)
			if typeof(stored) == "string" and identityConfig.Sources[stored] then
				setAvatarSource(stored)
			end
		end)
		return function()
			connection:Disconnect()
		end
	end, {})

	local selectedTrack, setSelectedTrack = React.useState(callbacks and callbacks.GetMenuTrack and callbacks.GetMenuTrack() or 1)
	local musicEnabled, setMusicEnabled = React.useState(
		if callbacks and callbacks.GetMusicEnabled then callbacks.GetMusicEnabled() else true
	)
	local pendingMode, setPendingMode = React.useState("TrainingFree")
	local pendingTeam, setPendingTeam = React.useState("Home")
	local occupancy, setOccupancy = React.useState({})
	--[[
		Control scheme. Asked once on desktop before the menu is usable, then
		changeable in Settings. Held here so every screen renders the same answer.
	]]
	local controlScheme, setControlSchemeState = React.useState(ControlSchemeController.Get())
	local needsSchemeChoice, setNeedsSchemeChoice = React.useState(ControlSchemeController.ShouldPrompt())
	local function setControlScheme(next: string, explicit: boolean?)
		ControlSchemeController.Set(next, explicit)
		setControlSchemeState(ControlSchemeController.Get())
	end

	setScreenState = setScreen
	setLoadingState = setLoading
	setToastState = setToast
	setGoalState = setGoalVisible

	local rootFrameRef = React.useRef(nil)

	React.useEffect(function()
		localPlayer:SetAttribute("Beyond90MenuSurfaceMounted", true)
		awaitMenuLayout(rootFrameRef.current)
		return function()
			localPlayer:SetAttribute("Beyond90MenuSurfaceMounted", false)
			localPlayer:SetAttribute("Beyond90MenuLayoutReady", false)
		end
	end, {})

	--[[
		THE MENU FAMILY (§12-§17).

		Play, Training, Clubs, Profile and Settings are one family sharing a shell,
		a bottom navigation and a set of account values. Those values are assembled
		ONCE here rather than in each page, so five screens cannot disagree about
		the player's level or currency -- and when a real profile service exists,
		this is the single place it connects.

		The numbers below are presentation constants with no backing system yet
		(§15). They are deliberately declared here, in the open, rather than being
		scattered as literals inside the pages.
	]]
	--[[
		The player's real avatar, fetched once and shared by every page (§15).
		Resolving it per page would run the same web call five times.
	]]
	local portrait, setPortrait = React.useState("")
	React.useEffect(function()
		task.spawn(function()
			local ok, image = pcall(function()
				return Players:GetUserThumbnailAsync(
					localPlayer.UserId,
					Enum.ThumbnailType.HeadShot,
					Enum.ThumbnailSize.Size420x420
				)
			end)
			if ok then
				setPortrait(image)
			end
		end)
	end, {})

	local mobileMenu = MenuKit.IsMobile()
	local menuPrompt = ControlSchemeConfig.MenuPrompts[controlScheme]
		or ControlSchemeConfig.MenuPrompts.Keyboard

	local navigate = function(destination: string)
		click()
		setScreen(destination)
	end

	local pageProps = {
		Mobile = mobileMenu,
		Navigate = navigate,
		MenuPrompt = menuPrompt,
		Portrait = portrait,
		-- No progression system yet; shown identically on every page.
		LevelText = "LEVEL --",
		LevelProgress = 0,
		SoftCurrency = "--",
		HardCurrency = "--",
	}

	local function withPageProps(extra)
		local merged = {}
		for key, value in pageProps do
			merged[key] = value
		end
		if extra then
			for key, value in extra do
				merged[key] = value
			end
		end
		return merged
	end

	local screenElement
	if screen == "Home" then
		screenElement = React.createElement(HomeScreen, {
			OpenModes = function() click(); setScreen("Play") end,
			-- The Training PAGE, which is where free practice is started from.
			OpenTrainingPage = function() click(); setScreen("Training") end,
			--[[
				Kept for compatibility: the older direct-to-team-pick path. Nothing
				calls it now, but removing a prop a screen might still pass would
				only turn a rename into a silent nil call.
			]]
			OpenTraining = function()
				click()
				setPendingMode("TrainingFree")
				setScreen("TeamSelect")
			end,
			OpenClubs = function() click(); setScreen("Clubs") end,
			OpenProfile = function() click(); setScreen("Profile") end,
			OpenSettings = function() click(); setScreen("Settings") end,
			ComingSoon = function()
				click()
				setToast(true)
				task.delay(1.2, function() setToast(false) end)
			end,
		})
	elseif screen == "Modes" or screen == "Play" then
		--[[
			"Modes" is kept as an alias for Play so every existing entry point --
			including the Home screen's own PLAY button -- keeps working without
			being rewritten.
		]]
		screenElement = React.createElement(PlayScreen, withPageProps({
			SelectMode = function(modeId)
				click()
				setPendingMode(modeId or "Quick3v3")
				setScreen("TeamSelect")
			end,
			Unavailable = function()
				click()
				setToast(true)
				task.delay(1.2, function() setToast(false) end)
			end,
		}))
	elseif screen == "Training" then
		screenElement = React.createElement(TrainingScreen, withPageProps({
			-- Unchanged entry path: team selection, then position, then the match.
			OpenTeamSelection = function(modeId)
				click()
				setPendingMode(modeId or "TrainingFree")
				setScreen("TeamSelect")
			end,
			ComingSoon = function()
				click()
				setToast(true)
				task.delay(1.2, function() setToast(false) end)
			end,
		}))
	elseif screen == "Clubs" then
		screenElement = React.createElement(ClubsScreen, withPageProps({}))
	elseif screen == "Profile" then
		screenElement = React.createElement(ProfileScreen, withPageProps({}))
	elseif screen == "TeamSelect" then
		screenElement = React.createElement(TeamSelectionScreen, {
			-- Back goes to whichever page launched the mode.
			GoBack = function()
				click()
				setScreen(if pendingMode == "TrainingFree" then "Training" else "Play")
			end,
			ModeId = pendingMode,
			--[[
				Team, then position, then the match (§39). Occupancy is read at
				this point so the position screen can show which slots other
				humans already hold.
			]]
			Continue = function(teamId)
				click()
				setPendingTeam(teamId)
				setOccupancy(if callbacks.GetPositionOccupancy
					then callbacks.GetPositionOccupancy(teamId, pendingMode)
					else {})
				setScreen("PositionSelect")
			end,
		})
	elseif screen == "PositionSelect" then
		screenElement = React.createElement(PositionSelectionScreen, {
			GoBack = function() click(); setScreen("TeamSelect") end,
			ModeId = pendingMode,
			TeamId = pendingTeam,
			Occupancy = occupancy,
			Continue = function(slotId)
				click()
				if callbacks.SelectPosition then
					callbacks.SelectPosition(pendingTeam, slotId)
				end
				callbacks.EnterMode(pendingMode, pendingTeam)
			end,
		})
	elseif screen == "Settings" then
		screenElement = React.createElement(SettingsScreen, withPageProps({
			GoHome = function() click(); setScreen("Home") end,
			DefaultCamera = defaultCamera,
			SetDefaultCamera = function(mode)
				if CameraController.SetDefaultMode(mode) then
					setDefaultCamera(mode)
				end
			end,
			AvatarSource = avatarSource,
			SetAvatarSource = function(source)
				click()
				local remotes = ReplicatedStorage:FindFirstChild("Remotes")
				local remote = remotes and remotes:FindFirstChild(identityConfig.RemoteName)
				if remote and remote:IsA("RemoteEvent") then
					remote:FireServer(source)
				end
				-- Optimistic, so the chip responds immediately; the server's own
				-- attribute change is what makes it stick.
				setAvatarSource(source)
			end,
			SelectedTrack = selectedTrack,
			SetTrack = function(index)
				click()
				setSelectedTrack(index)
				callbacks.SetMenuTrack(index)
			end,
			MusicEnabled = musicEnabled,
			SetMusicEnabled = function(enabled)
				click()
				setMusicEnabled(enabled)
				if callbacks.SetMusicEnabled then callbacks.SetMusicEnabled(enabled) end
			end,
			ControlScheme = controlScheme,
			SetControlScheme = function(next)
				click()
				setControlScheme(next, true)
			end,
		}))
	elseif screen == "Gameplay" then
		screenElement = React.createElement(GameplayHUD, {
			ResetBall = function() click(); callbacks.ResetBall() end,
			ReturnToMenu = function() click(); callbacks.ReturnToMenu() end,
		})
	else
		screenElement = React.createElement(LoadingScreen, loading)
	end

	return React.createElement("ScreenGui", {
		Name = "Beyond90UI",
		-- HUD geometry explicitly reserves the top-left CoreGui cluster while keeping
		-- menu and gameplay presentation edge-to-edge.
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 200,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, {
		Root = React.createElement("Frame", {
			ref = rootFrameRef,
			Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = if screen == "Gameplay" then 1 else 0, BorderSizePixel = 0,
		}, {
			Screen = screenElement,
			Toast = toast and React.createElement("Frame", {
				AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.055),
				Size = UDim2.fromScale(0.23, 0.082), BackgroundColor3 = Theme.Panel,
				BackgroundTransparency = 0.02, BorderSizePixel = 0, ZIndex = 300,
			}, {
				Corner = ReactUI.Corner(6),
				Stroke = ReactUI.Stroke(Theme.StrokeBright, 1.25, 0.12),
				Accent = React.createElement("Frame", { Size = UDim2.fromScale(0.018, 1), BackgroundColor3 = Theme.AccentCyan, BorderSizePixel = 0, ZIndex = 301 }, {
					Gradient = ReactUI.Gradient(Theme.AccentCyan, Theme.AccentViolet, 90),
				}),
				Title = React.createElement("TextLabel", { Position = UDim2.fromScale(0.08, 0.18), Size = UDim2.fromScale(0.84, 0.28), BackgroundTransparency = 1, Font = Theme.Fonts.Navigation, Text = "COMING SOON", TextColor3 = Theme.Text, TextSize = 16, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 301 }),
				Body = React.createElement("TextLabel", { Position = UDim2.fromScale(0.08, 0.5), Size = UDim2.fromScale(0.84, 0.22), BackgroundTransparency = 1, Font = Theme.Fonts.Caption, Text = "This area is not available in the current milestone.", TextColor3 = Theme.MutedText, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 301 }),
			}) or nil,
			Goal = React.createElement(GoalNotification, { Visible = goalVisible }),
			--[[
				The control-scheme prompt sits above every menu screen, and only
				while the player has not answered it. It is not shown during
				gameplay: interrupting a live match to ask this would be worse
				than any default.
			]]
			ControlSchemePrompt = (needsSchemeChoice and screen ~= "Gameplay")
				and React.createElement(ControlSchemeScreen, {
					Selected = controlScheme,
					Select = function(next)
						click()
						setControlScheme(next, false)
					end,
					Confirm = function()
						click()
						setControlScheme(controlScheme, true)
						setNeedsSchemeChoice(false)
					end,
				}) or nil,
		}),
	})
end

function UIController.Initialize(callbacks)
	if root then return end
	localPlayer:SetAttribute("Beyond90MenuSurfaceMounted", false)
	localPlayer:SetAttribute("Beyond90MenuLayoutReady", false)
	local playerGui = localPlayer:WaitForChild("PlayerGui")
	root = ReactRoblox.createRoot(playerGui)
	root:render(React.createElement(App, { Callbacks = callbacks }))
	task.spawn(preloadMenuAssets)
	task.spawn(function()
		local remotes = ReplicatedStorage:WaitForChild(FootballActionConfig.RemotesFolderName, 10)
		local goalRemote = remotes and remotes:WaitForChild(GoalConfig.GoalScoredRemoteName, 10)
		if goalRemote and goalRemote:IsA("RemoteEvent") then
			remoteConnection = goalRemote.OnClientEvent:Connect(function()
				if setGoalState then
					setGoalState(true)
					task.delay(1.35, function()
						if setGoalState then setGoalState(false) end
					end)
				end
			end)
		end
	end)
end

--[[
	Show a named menu page directly.

	Used by the menu navigation and by verification tooling. Nothing here decides
	WHICH page is correct -- it only routes -- so it cannot disagree with the
	navigation about where a destination lives.
]]
function UIController.ShowScreen(name: string)
	if setScreenState then
		setScreenState(name)
	end
end

function UIController.ShowHome()
	if setScreenState then setScreenState("Home") end
	GuiService.SelectedObject = nil
end

function UIController.ShowMenuLoading()
	if setLoadingState then
		setLoadingState({
			Variant = "Menu", Mode = "RETURNING TO MENU", Detail = "",
			Status = "CLOSING TRAINING SESSION", Progress = 0.62,
		})
	end
	if setScreenState then setScreenState("Loading") end
end

function UIController.ShowModeLoading(mode: string, detail: string)
	if setLoadingState then
		setLoadingState({
			Variant = "Training", Mode = mode, Detail = detail,
			Status = "PREPARING TRAINING", Progress = 0.12,
		})
	end
	if setScreenState then setScreenState("Loading") end
end

function UIController.UpdateModeLoading(status: string, progress: number)
	if setLoadingState then
		setLoadingState(function(previous)
			local nextState = table.clone(previous)
			nextState.Status = status
			nextState.Progress = progress
			return nextState
		end)
	end
end

function UIController.ShowGameplay()
	UIController.UpdateModeLoading("READY", 1)
	task.wait(0.65)
	if setScreenState then setScreenState("Gameplay") end
	--[[
		Entering gameplay always hands directional input back to the footballer.

		A menu selection left over from the screens we just came through would
		otherwise keep Roblox's GUI navigation active, and WASD would move the
		HUD highlight instead of the player.
	]]
	GuiService.SelectedObject = nil
end

function UIController.Destroy()
	if remoteConnection then remoteConnection:Disconnect() end
	remoteConnection = nil
	if root then root:unmount() end
	root = nil
	setScreenState = nil
	setLoadingState = nil
	setToastState = nil
	setGoalState = nil
	localPlayer:SetAttribute("Beyond90MenuSurfaceMounted", false)
end

return UIController
