--!strict
--[[
	The referee's decisions, on screen.

	MatchRulesService announces every decision it makes; this renders that
	announcement as a broadcast-style card so a player always knows WHY play
	stopped. Before this, a throw-in and a free kick looked identical from the
	pitch: the ball moved and everybody repositioned.

	Purely a presentation listener. It never sends anything back, so nothing here
	can influence a decision (section 17).
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FootballTeamConfig = require(Shared.Config.FootballTeamConfig)
local GameConfig = require(Shared.Config.GameConfig)
local MatchRulesConfig = require(Shared.Config.MatchRulesConfig)
local RefereeConfig = require(Shared.Config.RefereeConfig)

local RefereeDecisionController = {}

local TONE_COLORS = {
	Neutral = Color3.fromRGB(118, 191, 255),
	Good = Color3.fromRGB(74, 224, 144),
	Warning = Color3.fromRGB(255, 190, 74),
	Bad = Color3.fromRGB(255, 91, 110),
}

local localPlayer = Players.LocalPlayer
local initialized = false
local gui: ScreenGui? = nil
local cardFrame: Frame? = nil
local titleLabel: TextLabel? = nil
local detailLabel: TextLabel? = nil
local accentBar: Frame? = nil
local connection: RBXScriptConnection? = nil
local showToken = 0

local function log(message: string)
	if MatchRulesConfig.Debug.Enabled then
		print(string.format("%s[Client][Referee] %s", GameConfig.LogPrefix, message))
	end
end

local function buildGui()
	if gui and gui.Parent then
		return
	end
	local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end

	local screen = Instance.new("ScreenGui")
	screen.Name = "Beyond90RefereeDecision"
	screen.IgnoreGuiInset = true
	screen.ResetOnSpawn = false
	-- Above the HUD, below the match-start presentation.
	screen.DisplayOrder = 250
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.Parent = playerGui

	--[[
		Built once and kept hidden. A decision card that had to be constructed on
		the frame the whistle blows would cost exactly the frames that matter.
	]]
	local card = Instance.new("Frame")
	card.Name = "DecisionCard"
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Position = UDim2.fromScale(0.5, 0.16)
	card.Size = UDim2.fromOffset(320, 62)
	card.BackgroundColor3 = Color3.fromRGB(5, 9, 21)
	card.BackgroundTransparency = 1
	card.BorderSizePixel = 0
	card.Visible = false
	card.Parent = screen

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = card

	local stroke = Instance.new("UIStroke")
	stroke.Name = "Edge"
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = Color3.fromRGB(118, 191, 255)
	stroke.Thickness = 1.25
	stroke.Transparency = 1
	stroke.Parent = card

	local accent = Instance.new("Frame")
	accent.Name = "Accent"
	accent.Size = UDim2.new(0, 3, 1, 0)
	accent.BackgroundColor3 = Color3.fromRGB(118, 191, 255)
	accent.BackgroundTransparency = 1
	accent.BorderSizePixel = 0
	accent.ZIndex = 2
	accent.Parent = card

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.AnchorPoint = Vector2.new(0, 0)
	title.Position = UDim2.new(0, 16, 0, 10)
	title.Size = UDim2.new(1, -28, 0, 24)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.Text = ""
	title.TextColor3 = Color3.fromRGB(246, 248, 255)
	title.TextSize = 20
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextTransparency = 1
	title.ZIndex = 2
	title.Parent = card

	local detail = Instance.new("TextLabel")
	detail.Name = "Detail"
	detail.AnchorPoint = Vector2.new(0, 0)
	detail.Position = UDim2.new(0, 16, 0, 35)
	detail.Size = UDim2.new(1, -28, 0, 16)
	detail.BackgroundTransparency = 1
	detail.Font = Enum.Font.GothamMedium
	detail.Text = ""
	detail.TextColor3 = Color3.fromRGB(156, 169, 201)
	detail.TextSize = 12
	detail.TextXAlignment = Enum.TextXAlignment.Left
	detail.TextTransparency = 1
	detail.ZIndex = 2
	detail.Parent = card

	gui = screen
	cardFrame = card
	titleLabel = title
	detailLabel = detail
	accentBar = accent
end

--[[
	Who the decision went to, from the local player's point of view.

	"FREE KICK -- YOUR BALL" is instantly readable in a way that "FREE KICK --
	HOME" is not, so the team is described relative to the viewer.
]]
local function describeTeam(teamId: string?): string?
	if typeof(teamId) ~= "string" then
		return nil
	end
	local localTeam = FootballTeamConfig.Normalize(
		localPlayer:GetAttribute(FootballTeamConfig.AttributeName)
	)
	if localTeam == teamId then
		return "YOUR BALL"
	end
	return "OPPONENT BALL"
end

local function describe(payload): (string, string, Color3)
	local kind = tostring(payload.Kind)
	local announcement = RefereeConfig.GetAnnouncement(kind)
	local title = if announcement then announcement.Title else string.upper(kind)
	local tone = if announcement then announcement.Tone else "Neutral"
	local color = TONE_COLORS[tone] or TONE_COLORS.Neutral

	local parts = {}
	local possession = describeTeam(payload.TeamId)

	--[[
		A goal is the one decision where possession is the WRONG framing: the team
		named scored, they did not win a restart.
	]]
	if kind == "Goal" then
		local localTeam = FootballTeamConfig.Normalize(
			localPlayer:GetAttribute(FootballTeamConfig.AttributeName)
		)
		possession = if localTeam == payload.TeamId then "YOUR TEAM SCORES" else "OPPONENT SCORES"
	elseif kind == "HalfTime" or kind == "FullTime" then
		possession = nil
	end

	if possession then
		table.insert(parts, possession)
	end

	--[[
		Detail is a reason, not a debug field. Internal reasons such as
		"match-start" or a raw scorer id are of no use to a player, so only the
		ones that describe the decision are shown.
	]]
	local detail = payload.Detail
	if kind == "Foul" and detail == "SeriousFoul" then
		table.insert(parts, "SERIOUS FOUL PLAY")
	elseif kind == "Kickoff" and detail == "after-goal" then
		table.insert(parts, "RESTART")
	elseif kind == "Kickoff" and detail == "second-half" then
		table.insert(parts, "SECOND HALF")
	elseif kind == "FreeKick" and detail == "injury" then
		table.insert(parts, "AFTER TREATMENT")
	end

	return title, table.concat(parts, "  -  "), color
end

local function present(payload)
	buildGui()
	local card, title, detail, accent = cardFrame, titleLabel, detailLabel, accentBar
	if not card or not title or not detail or not accent then
		return
	end
	local stroke = card:FindFirstChild("Edge") :: UIStroke?

	local titleText, detailText, color = describe(payload)
	title.Text = titleText
	title.TextColor3 = color
	detail.Text = detailText
	detail.Visible = detailText ~= ""
	accent.BackgroundColor3 = color
	if stroke then
		stroke.Color = color
	end

	showToken += 1
	local token = showToken

	card.Visible = true
	card.BackgroundTransparency = 1
	title.TextTransparency = 1
	detail.TextTransparency = 1
	accent.BackgroundTransparency = 1
	if stroke then
		stroke.Transparency = 1
	end

	local fade = RefereeConfig.Notification.FadeSeconds
	local inInfo = TweenInfo.new(fade, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(card, inInfo, { BackgroundTransparency = 0.08 }):Play()
	TweenService:Create(title, inInfo, { TextTransparency = 0 }):Play()
	TweenService:Create(detail, inInfo, { TextTransparency = 0.15 }):Play()
	TweenService:Create(accent, inInfo, { BackgroundTransparency = 0 }):Play()
	if stroke then
		TweenService:Create(stroke, inInfo, { Transparency = 0.25 }):Play()
	end

	task.delay(fade + RefereeConfig.Notification.HoldSeconds, function()
		-- A newer decision has taken over the card; it owns the fade now.
		if token ~= showToken or not card.Parent then
			return
		end
		local outInfo = TweenInfo.new(fade, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		TweenService:Create(card, outInfo, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(title, outInfo, { TextTransparency = 1 }):Play()
		TweenService:Create(detail, outInfo, { TextTransparency = 1 }):Play()
		TweenService:Create(accent, outInfo, { BackgroundTransparency = 1 }):Play()
		if stroke then
			TweenService:Create(stroke, outInfo, { Transparency = 1 }):Play()
		end
		task.delay(fade, function()
			if token == showToken and card.Parent then
				card.Visible = false
			end
		end)
	end)

	log(string.format("decision %s %s", titleText, detailText))
end

function RefereeDecisionController.Initialize()
	if initialized then
		return
	end
	initialized = true
	buildGui()

	task.spawn(function()
		local folder = ReplicatedStorage:FindFirstChild(MatchRulesConfig.FolderName)
			or ReplicatedStorage:WaitForChild(MatchRulesConfig.FolderName, 15)
		if not folder or not initialized then
			return
		end
		local remote = folder:FindFirstChild(MatchRulesConfig.AnnouncementRemoteName)
			or folder:WaitForChild(MatchRulesConfig.AnnouncementRemoteName, 10)
		if remote and remote:IsA("RemoteEvent") and initialized then
			connection = remote.OnClientEvent:Connect(function(payload)
				if typeof(payload) == "table" and typeof(payload.Kind) == "string" then
					present(payload)
				end
			end)
		end
	end)
end

function RefereeDecisionController.Destroy()
	if not initialized then
		return
	end
	initialized = false
	if connection then
		connection:Disconnect()
		connection = nil
	end
	if gui then
		gui:Destroy()
	end
	gui = nil
	cardFrame = nil
	titleLabel = nil
	detailLabel = nil
	accentBar = nil
end

return RefereeDecisionController
