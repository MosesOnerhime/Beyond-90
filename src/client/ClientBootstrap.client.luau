local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local ExperienceFlowController = require(script.Parent.Controllers.ExperienceFlowController)
local StartupFallback = require(script.Parent.UI.StartupFallback)

--[[
	THE IDENT'S SURFACE HAS TO BE OWNED BY A CLIENT SCRIPT, NOT BY ReplicatedFirst.

	This is the root cause of the intro problem, and it took a runtime diagnostic
	to see rather than a log:

		Drixil stage  coverSize=1170.40002, 550.400024
		Beyond 90     coverSize=0, 0
		re-attach     "The Parent property of Beyond90StartupLoading is locked,
		               current parent: NULL, new parent PlayerGui"

	Parent NULL, and permanently locked. Nothing in Beyond 90 orphaned it.

	Roblox ADOPTS any ScreenGui a ReplicatedFirst script parents into PlayerGui
	as that client's loading screen, and owns its lifetime from then on: when
	loading completes it un-parents the instance and locks it. A branding
	sequence that runs for seven seconds therefore cannot live there. The first
	stage drew because it happened before that moment, and everything after it
	drew, perfectly and invisibly, into an orphan. Re-parenting cannot recover it
	and neither can releasing the loading-screen slot first -- both were tried,
	and the lock message above is the answer to both.

	So the surface is created HERE, by a StarterPlayerScripts script, which
	Roblox has no special interest in. StartupLoading builds into it instead of
	into a GUI of its own. It is created before anything else in the client boots
	so that it is waiting by the time the ident is ready to draw.
]]
local surface = Instance.new("ScreenGui")
surface.Name = "Beyond90StartupSurface"
surface.IgnoreGuiInset = true
surface.ResetOnSpawn = false
-- Above every other surface in the game, including the menu it hands over to.
surface.DisplayOrder = 2147483647
surface.ZIndexBehavior = Enum.ZIndexBehavior.Global
surface.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

--[[
	ROBLOX'S DEFAULT CAMERA NEVER GETS A FRAME.

	Runtime inspection during a 3v3 entry found the camera sitting at
	`CameraType = Custom` with `Beyond90CameraMode = nil` -- Roblox's own
	third-person follow camera, live, before any Beyond 90 camera had claimed it.
	That is the "I saw my player in third person before the START MATCH button"
	report: the character spawns, Roblox attaches its stock camera to it, and
	Beyond 90's camera only takes over some seconds later when the mode finishes
	assembling.

	Nothing about the fix belongs in the camera modes themselves. The window
	exists BEFORE any of them run, so it has to be closed before any of them run:
	the camera is taken to Scriptable here, at the first instruction of the
	client, and simply holds still until a real camera claims it. A parked camera
	behind a loading screen shows nothing; a stock follow camera behind a loading
	screen shows the pitch the moment that screen is a frame late.

	`CameraSubject` is deliberately left alone. Scriptable ignores it, and
	preserving it means whatever restores Custom later -- the menu, a mode exit --
	finds the camera exactly as Roblox left it.
]]
do
	--[[
		WHEN DOES BEYOND 90 NOT OWN THE CAMERA?

		Two states, and the first version of this guard only knew about one of
		them. `nil` is "no Beyond 90 camera has ever run" -- a fresh client.
		`"Default"` is `restoreDefaultCamera` handing the camera back on the way
		out of a match, which is every session after the first.

		Testing only for `nil` therefore protected the first entry into a mode
		and nothing afterwards, which is exactly the shape of the report: the
		glitch appears only after you have played once, returned to the menu and
		gone back in.
	]]
	local function beyond90OwnsCamera(): boolean
		local mode = Players.LocalPlayer:GetAttribute("Beyond90CameraMode")
		return mode ~= nil and mode ~= "Default"
	end

	local function parkCameraIfUnclaimed()
		local live = Workspace.CurrentCamera
		if live and not beyond90OwnsCamera() then
			live.CameraType = Enum.CameraType.Scriptable
		end
	end

	parkCameraIfUnclaimed()

	--[[
		Roblox re-points the camera at a newly spawned character WITHOUT
		replacing the Camera object, so CurrentCamera never changes on re-entry
		and a guard hung only on that signal never fires a second time. That is
		the other half of the same bug: the stock follow camera latches onto the
		new footballer and shows him standing on the pitch while the mode is
		still assembling -- around ten seconds, on the evidence of the logs,
		between the character spawning and Broadcast1 claiming the camera.

		CharacterAdded is the signal that actually corresponds to "something the
		stock camera would want to follow now exists". There is no state in
		which a character is live and Beyond 90 wants Roblox's camera, so
		parking here is safe: CameraController claims it moments later and sets
		the attribute that makes this a no-op.
	]]
	Players.LocalPlayer.CharacterAdded:Connect(parkCameraIfUnclaimed)
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(parkCameraIfUnclaimed)
end

print(string.format("%s[Client] Initializing menu-first experience...", GameConfig.LogPrefix))
StartupFallback.Run()
ExperienceFlowController.Initialize()
print(string.format("%s[Client] Main menu ready", GameConfig.LogPrefix))
