local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AIConfig = require(Shared.Config.AIConfig)
local BallControlMath = require(Shared.Football.BallControlMath)
local FootballTeamConfig = require(Shared.Config.FootballTeamConfig)
local GameConfig = require(Shared.Config.GameConfig)
local PositionConfig = require(Shared.Config.PositionConfig)

local FootballerRegistryService = {}

local aiActorsById = {}
local footballerFolder: Folder? = nil

local function getRoot(character: Model?): BasePart?
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function getHumanoid(character: Model?): Humanoid?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return if humanoid and humanoid.Health > 0 then humanoid else nil
end

function FootballerRegistryService.Initialize(): Folder
	if footballerFolder and footballerFolder.Parent then
		return footballerFolder
	end
	local root = Workspace:FindFirstChild(GameConfig.WorkspaceContainerName)
	if not root then
		root = Instance.new("Folder")
		root.Name = GameConfig.WorkspaceContainerName
		root.Parent = Workspace
	end
	local existing = root:FindFirstChild(AIConfig.FootballerFolderName)
	if existing then
		assert(existing:IsA("Folder"), existing:GetFullName() .. " must be a Folder")
		footballerFolder = existing
	else
		footballerFolder = Instance.new("Folder")
		footballerFolder.Name = AIConfig.FootballerFolderName
		footballerFolder.Parent = root
	end
	return footballerFolder
end

function FootballerRegistryService.GetFolder(): Folder
	return FootballerRegistryService.Initialize()
end

function FootballerRegistryService.GetHumanActor(player: Player)
	local character = player.Character
	local humanoid = getHumanoid(character)
	local root = getRoot(character)
	if not character or not humanoid or not root then
		return nil
	end
	return {
		Id = player.UserId,
		Kind = "Human",
		TeamId = FootballTeamConfig.Normalize(player:GetAttribute(FootballTeamConfig.AttributeName)),
		Character = character,
		Humanoid = humanoid,
		RootPart = root,
		DisplayName = player.DisplayName,
		Player = player,
		IsAI = false,
		Role = player:GetAttribute(AIConfig.Attributes.Role),
		-- The position slot the server reserved for this player, so rules and
		-- set-piece placement can treat humans and AI identically.
		PositionSlotId = player:GetAttribute(PositionConfig.SlotAttributeName),
	}
end

function FootballerRegistryService.RegisterAI(actor)
	assert(typeof(actor) == "table" and typeof(actor.Id) == "number", "AI actor requires a numeric Id")
	assert(actor.Character and actor.Character:IsA("Model"), "AI actor requires a Character")
	aiActorsById[actor.Id] = actor
	actor.Character:SetAttribute(AIConfig.Attributes.Id, actor.Id)
	actor.Character:SetAttribute(AIConfig.Attributes.Kind, "AI")
	actor.Character:SetAttribute(AIConfig.Attributes.Role, actor.Role)
	actor.Character:SetAttribute(FootballTeamConfig.AttributeName, actor.TeamId)
	actor.Character:SetAttribute(PositionConfig.SlotAttributeName, actor.PositionSlotId)
	actor.Character.Parent = FootballerRegistryService.GetFolder()
	return actor
end

function FootballerRegistryService.UnregisterAI(actorOrId, destroyCharacter: boolean?)
	local id = if typeof(actorOrId) == "number" then actorOrId else actorOrId and actorOrId.Id
	local actor = id and aiActorsById[id] or nil
	if not actor then
		return
	end
	aiActorsById[id] = nil
	if destroyCharacter ~= false and actor.Character and actor.Character.Parent then
		actor.Character:Destroy()
	end
end

function FootballerRegistryService.ClearAI()
	local actors = {}
	for _, actor in aiActorsById do
		table.insert(actors, actor)
	end
	for _, actor in actors do
		FootballerRegistryService.UnregisterAI(actor, true)
	end
end

function FootballerRegistryService.GetActorById(id: number)
	local aiActor = aiActorsById[id]
	if aiActor then
		return aiActor
	end
	for _, player in Players:GetPlayers() do
		if player.UserId == id then
			return FootballerRegistryService.GetHumanActor(player)
		end
	end
	return nil
end

function FootballerRegistryService.GetAll(modeId: string?)
	local actors = {}
	for _, player in Players:GetPlayers() do
		if not modeId or player:GetAttribute("Beyond90SelectedGameMode") == modeId then
			local actor = FootballerRegistryService.GetHumanActor(player)
			if actor then
				table.insert(actors, actor)
			end
		end
	end
	for _, actor in aiActorsById do
		if actor.Character and actor.Character.Parent and actor.Humanoid.Health > 0 then
			table.insert(actors, actor)
		end
	end
	return actors
end

function FootballerRegistryService.GetTeam(teamId: string, modeId: string?)
	local actors = {}
	for _, actor in FootballerRegistryService.GetAll(modeId) do
		if actor.TeamId == teamId then
			table.insert(actors, actor)
		end
	end
	return actors
end

function FootballerRegistryService.CreateCandidate(actor)
	if not actor or not actor.RootPart or not actor.RootPart.Parent then
		return nil
	end
	return {
		Kind = actor.Kind,
		Name = actor.DisplayName,
		UserId = actor.Id,
		FootballerId = actor.Id,
		Instance = if actor.IsAI then actor.Character else actor.Player,
		Position = actor.RootPart.Position,
		Velocity = actor.RootPart.AssemblyLinearVelocity,
		FacingDirection = BallControlMath.GetHorizontal(actor.RootPart.CFrame.LookVector),
		TeamId = actor.TeamId,
	}
end

return FootballerRegistryService
