local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local PlayerConfig = require(Shared.Config.PlayerConfig)
local WorldScaleConfig = require(Shared.Config.WorldScaleConfig)

local CharacterAppearanceService = {}

local appearanceConfig = PlayerConfig.Appearance
local profileConfig = PlayerConfig.GameplayProfile

local accessoryPropertiesToClear = {
	"BackAccessory",
	"FrontAccessory",
	"HatAccessory",
	"NeckAccessory",
	"ShouldersAccessory",
	"WaistAccessory",
	"JacketAccessory",
	"SweaterAccessory",
	"ShortsAccessory",
	"DressSkirtAccessory",
	"PantsAccessory",
	"ShirtAccessory",
	"TShirtAccessory",
	"LeftShoeAccessory",
	"RightShoeAccessory",
}

local animationPropertiesToClear = {
	"ClimbAnimation",
	"FallAnimation",
	"IdleAnimation",
	"JumpAnimation",
	"MoodAnimation",
	"RunAnimation",
	"SwimAnimation",
	"WalkAnimation",
}

local bodyPartPropertiesToClear = {
	"Torso",
	"LeftArm",
	"RightArm",
	"LeftLeg",
	"RightLeg",
}

local requiredR15Parts = {
	"UpperTorso",
	"LowerTorso",
	"LeftUpperArm",
	"LeftLowerArm",
	"LeftHand",
	"RightUpperLeg",
	"RightLowerLeg",
	"RightFoot",
}

local function warnLog(message: string)
	warn(string.format("%s[Server][Appearance] %s", GameConfig.LogPrefix, message))
end

local function characterLog(message: string)
	print(string.format("%s[Character] %s", GameConfig.LogPrefix, message))
end

local function setDescriptionProperty(description: HumanoidDescription, property: string, value: any)
	pcall(function()
		description[property] = value
	end)
end

local function isInAccessory(instance: Instance): boolean
	local current = instance.Parent

	while current do
		if current:IsA("Accessory") then
			return true
		end

		current = current.Parent
	end

	return false
end

local function measureBodyHeight(character: Model): number?
	local minY = math.huge
	local maxY = -math.huge
	local foundPart = false

	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart")
			and descendant.Name ~= "HumanoidRootPart"
			and not isInAccessory(descendant)
		then
			foundPart = true
			local halfHeight = descendant.Size.Y / 2
			minY = math.min(minY, descendant.Position.Y - halfHeight)
			maxY = math.max(maxY, descendant.Position.Y + halfHeight)
		end
	end

	if not foundPart then
		return nil
	end

	return maxY - minY
end

local function scaleCharacterToHeight(character: Model, targetHeight: number, label: string): (number?, number?)
	local measuredHeight = measureBodyHeight(character)

	if not measuredHeight or measuredHeight <= 0 then
		return nil, nil
	end

	character:SetAttribute("Beyond90SourceBodyHeightStuds", measuredHeight)
	local scaleFactor = targetHeight / measuredHeight

	if math.abs(scaleFactor - 1) <= 0.005 then
		return measuredHeight, 1
	end

	local ok, err = pcall(function()
		character:ScaleTo(character:GetScale() * scaleFactor)
	end)

	if not ok then
		warnLog(string.format("Could not scale character for %s: %s", label, tostring(err)))
		return measuredHeight, nil
	end

	RunService.Heartbeat:Wait()
	return measureBodyHeight(character) or targetHeight, scaleFactor
end

local function scaleCharacterForCurrentSource(character: Model): (number?, number?, boolean)
	if appearanceConfig.DevelopmentFootballerScaleEnabled then
		local targetHeight = appearanceConfig.DevelopmentFootballerTargetHeightStuds
			or appearanceConfig.IntendedHeightStuds
			or WorldScaleConfig.CanonicalPlayerHeightStuds
		local measuredHeight, scaleFactor = scaleCharacterToHeight(character, targetHeight, "development footballer")

		if scaleFactor then
			character:SetAttribute("Beyond90DevelopmentFootballerScaleFactor", scaleFactor)
		end

		return measuredHeight, scaleFactor, true
	end

	if appearanceConfig.ScaleToCanonicalHeight then
		local targetHeight = appearanceConfig.TargetHeightStuds
			or appearanceConfig.IntendedHeightStuds
			or WorldScaleConfig.CanonicalPlayerHeightStuds
		local measuredHeight, scaleFactor = scaleCharacterToHeight(character, targetHeight, "canonical height")
		return measuredHeight, scaleFactor, false
	end

	return measureBodyHeight(character), 1, false
end

local function getR15StructureReport(character: Model): (boolean, string)
	local missing = {}

	for _, partName in requiredR15Parts do
		local part = character:FindFirstChild(partName)

		if not part or not part:IsA("BasePart") then
			table.insert(missing, partName)
		end
	end

	if #missing > 0 then
		return false, table.concat(missing, ", ")
	end

	return true, "ok"
end

local function normalizeDescription(description: HumanoidDescription)
	setDescriptionProperty(description, "HeightScale", appearanceConfig.HeightScale)
	setDescriptionProperty(description, "WidthScale", appearanceConfig.WidthScale)
	setDescriptionProperty(description, "DepthScale", appearanceConfig.DepthScale)
	setDescriptionProperty(description, "HeadScale", appearanceConfig.HeadScale)
	setDescriptionProperty(description, "BodyTypeScale", appearanceConfig.BodyTypeScale)
	setDescriptionProperty(description, "ProportionScale", appearanceConfig.ProportionScale)

	for _, property in accessoryPropertiesToClear do
		setDescriptionProperty(description, property, "")
	end

	if appearanceConfig.RemoveAnimationPacks then
		for _, property in animationPropertiesToClear do
			setDescriptionProperty(description, property, 0)
		end
	end

	if appearanceConfig.RemoveBodyPackageParts then
		for _, property in bodyPartPropertiesToClear do
			setDescriptionProperty(description, property, 0)
		end
	end
end

--[[
	THE FRAME EVERY FOOTBALLER SHARES.

	PlayerConfig.Appearance promises that "a player whose own avatar is unusually
	tall, short, wide or narrow still plays as the same physical footballer as
	everyone else", because control distance, tackle reach, shot contact radius,
	interception reach and body exclusion are all measured in studs from the root
	part. That promise was only half kept, and only for humans.

	Measured, same place, same session:

		human     height 7.50  hipHeight 4.064  BodyHeightScale 1.000
		AI / ref  height 8.27  hipHeight 3.223  BodyHeightScale nil

	Identical model scale, completely different builds -- and the missing
	BodyHeightScale is the tell. A HumanoidDescription had never been applied to
	an NPC at all. Humans go through `ApplyDescription`, which REBUILDS the rig
	from R15 body parts; NPCs were clones of StarterCharacter that kept whatever
	limbs that model happened to have. Two different bodies playing the same
	sport, with the AI three quarters of a stud taller and its hips eight tenths
	of a stud lower.

	What this pins is the six SCALE factors -- the player's own body proportions,
	which are the thing that would otherwise hand a taller or wider avatar a
	longer stride and more reach.

	WHAT IT DELIBERATELY DOES NOT TOUCH IS THE BODY PACKAGE.

	An earlier version cleared the package parts too, on the reasoning that limb
	meshes are the frame and clearing them drops everyone onto one skeleton. That
	reasoning is sound in general and completely wrong here, because in this place
	the body package IS THE BEYOND 90 KIT. StarterPlayer.StarterCharacter has no
	Shirt and no Pants -- every limb is a MeshPart from one package:

		Head          2337186646
		UpperTorso    2337186836
		LeftUpperArm  2337186767   ... and so on for all fifteen

	So clearing the package did not neutralise a competitive advantage, it
	undressed the footballer: ApplyDescription swapped the kit for default R15
	limbs, and choosing "Beyond 90 kit" gave you anything but.

	Parity is kept by the height pass instead (see PlayerConfig.Appearance
	ScaleToCanonicalHeight), which measures the assembled body and scales every
	footballer to one number whatever their limbs are made of. And by default it
	does not arise at all: the kit is now the default footballer, so a human and
	an AI are literally the same StarterCharacter. Only a player who opts into
	their own Roblox avatar has different limbs, and they are height-normalised
	to match.

	Also not touched: shirt, pants, skin colour, face, hair and accessories.
]]
local function standardiseFrame(description: HumanoidDescription)
	for _, property in { "HeightScale", "WidthScale", "DepthScale", "HeadScale", "BodyTypeScale", "ProportionScale" } do
		setDescriptionProperty(description, property, 1)
	end
end

--[[
	Which body should this footballer wear?

	A player's own choice when they have made one, the configured default
	otherwise. AI footballers and officials are never given a Roblox avatar --
	they have no account to take one from -- so they always wear the uniform
	body.
]]
local function getIdentitySource(player: Player?): string
	local identity = appearanceConfig.Identity
	if not identity or identity.Enabled ~= true or not player then
		return "Beyond90Avatar"
	end
	local chosen = player:GetAttribute(identity.AttributeName)
	if typeof(chosen) == "string" and identity.Sources[chosen] then
		return chosen
	end
	return identity.Default
end

--[[
	Put the player's own Roblox avatar on this rig.

	Applied as a HumanoidDescription onto the existing character rather than by
	spawning a different model, so every downstream system -- the animation
	tracks, the collider policy, the grounding calibration, the ball-control
	geometry -- keeps working on exactly the rig it already knew about. Only the
	appearance changes.

	Bounded and fail-safe: the fetch is a web call, and a player whose avatar
	cannot be read spawns in the uniform body instead of not spawning at all.

	Returns whether the avatar was actually applied.
]]
local function applyRobloxAvatar(player: Player, character: Model, humanoid: Humanoid): boolean
	local identity = appearanceConfig.Identity
	local okFetch, description = pcall(function()
		return Players:GetHumanoidDescriptionFromUserId(player.UserId)
	end)
	if not okFetch or not description then
		warnLog(string.format(
			"Could not read the Roblox avatar for %s; using the Beyond 90 body",
			player.Name
		))
		return false
	end

	--[[
		SIZE IS NOT INHERITED.

		The description carries the player's own body scales, and applying them
		would hand a taller avatar a longer stride and a wider reach. Neutralising
		them here is cheaper and more reliable than scaling it back out
		afterwards, and it means the height pass below starts from a known frame
		every time.

		Their body package IS kept -- that is their avatar, and this branch only
		runs because they asked to wear it.
	]]
	standardiseFrame(description)

	--[[
		A NOTE ON WHAT THIS DOES NOT FIX.

		This place has a StarterPlayer.StarterCharacter, so Roblox spawns every
		player as the Beyond 90 kit and the player's own avatar is applied over
		the top. ApplyDescription only replaces part of it -- measured on a live
		character wearing their own avatar:

			UpperTorso    = 542765884    the player's      (replaced)
			LeftUpperLeg  = 2337186877   the Beyond 90 kit (survived)
			RightUpperArm = 2337186817   the Beyond 90 kit (survived)
			Head          = 2337186646   the Beyond 90 kit (survived)

		so a player wearing their own avatar gets their torso and clothes on the
		kit's arms, legs and head.

		DO NOT try to finish the job by copying meshes across with
		MeshPart:ApplyMesh. That was tried and it is worse: an R15 rig hangs its
		joints off Attachments that ship inside each body part, ApplyMesh replaces
		the geometry and leaves those attachments where they were, and the result
		is a mangled body -- measured, 30 attachment mismatches, the head 1.86
		studs off centre and the RIGHT arm rendered on the LEFT side of the torso.

		The real fix is that players should not be built from StarterCharacter at
		all; the kit belongs somewhere the AI can clone it from, leaving Roblox to
		spawn a player as their own avatar the way it does by default. That is a
		change to how the place is authored rather than to this file, so it is
		deliberately not attempted here.
	]]
	local okApply, err = pcall(function()
		humanoid:ApplyDescription(description)
	end)
	description:Destroy()
	if not okApply then
		warnLog(string.format("Could not apply the Roblox avatar for %s: %s", player.Name, tostring(err)))
		return false
	end
	RunService.Heartbeat:Wait()
	return true
end

--[[
	Rebuild an NPC on the shared frame.

	Fail-safe in the same shape as `applyRobloxAvatar`: an official or an AI
	footballer whose description cannot be read or applied keeps the body it
	already had rather than failing to spawn. It will be the wrong size, which is
	a visible bug rather than a broken match.
]]
local function applyStandardFrameToNPC(label: string, character: Model, humanoid: Humanoid): boolean
	local okRead, description = pcall(function()
		return humanoid:GetAppliedDescription()
	end)
	if not okRead or not description then
		warnLog(string.format("Could not read the description for %s; body left unstandardised", label))
		return false
	end

	standardiseFrame(description)

	--[[
		ApplyDescription NEEDS THE MODEL IN THE DATAMODEL.

		AIService and RefereeService both clone their footballer, standardise it,
		and parent it afterwards -- so the first attempt at this failed on every
		single NPC with:

			Humanoid::ApplyDescription() DataModel was not available

		silently, because the call is pcall-wrapped to be fail-safe. The heights
		still converged, but only because the scale pass was doing all the work;
		the frame itself was never standardised at all. A fix that reports success
		while doing nothing is worse than no fix.

		It has to be WORKSPACE, not ServerStorage. ServerStorage also satisfies
		"in the DataModel" and the call reports success there, but it does not
		rebuild the rig -- measured, same match, same NPCs:

			parked in ServerStorage   hip 3.780   modelScale 1.194
			parked in Workspace       hip 4.041   modelScale 1.311
			the human being matched    hip 4.041   modelScale 1.311

		Only the Workspace round trip actually produces the human's frame, which
		is the entire point of doing this. The model is about to be parented
		there regardless, this runs during mode assembly behind the loading
		screen, and the original parent is restored so the caller's own parenting
		is untouched.
	]]
	local originalParent = character.Parent
	local parked = false
	if not character:IsDescendantOf(game) then
		character.Parent = Workspace
		parked = true
	end

	local okApply, err = pcall(function()
		humanoid:ApplyDescription(description)
	end)
	description:Destroy()

	if okApply then
		RunService.Heartbeat:Wait()
	end
	if parked then
		character.Parent = originalParent
	end

	if not okApply then
		warnLog(string.format("Could not standardise the frame for %s: %s", label, tostring(err)))
		return false
	end
	return true
end

local function standardizeCharacter(label: string, character: Model, humanoid: Humanoid, player: Player?): boolean
	if not appearanceConfig.StandardizeEnabled then
		return false
	end

	if humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		warn(string.format(
			"%s[Character] ERROR expected R15 but received %s for %s",
			GameConfig.LogPrefix,
			humanoid.RigType.Name,
			label
		))
		character:SetAttribute("Beyond90StandardR15", false)
		return false
	end

	--[[
		IDENTITY FIRST, then scale.

		Order matters: applying a description resizes limbs, so the canonical
		height pass has to run afterwards or the footballer ends up whatever
		height the avatar happened to be.
	]]
	local identitySource = getIdentitySource(player)
	local wearingRobloxAvatar = false
	if identitySource == "RobloxAvatar" and player then
		wearingRobloxAvatar = applyRobloxAvatar(player, character, humanoid)
	else
		--[[
			EVERY OTHER FOOTBALLER GETS A DESCRIPTION TOO.

			This branch was `elseif not player` -- NPCs only -- which was correct
			only while every human wore their Roblox avatar. The Beyond 90 kit is
			now the default, so the common case is a HUMAN who takes neither
			path, and they would have been the one footballer on the pitch whose
			frame was never standardised.

			The rule is simply: if the rig was not rebuilt by applying a Roblox
			avatar, rebuild it here. Human or NPC does not enter into it -- a
			frame is a frame.

			This is the whole of the 7.50-versus-8.27 mismatch. A footballer's
			build comes from ApplyDescription rebuilding the rig; skip it and the
			body is simply whatever StarterCharacter was authored as. Humans were
			rebuilt, AI and officials were not, so the two were never the same
			shape -- and every stud-measured gameplay rule (control distance,
			tackle reach, shot contact, interception reach) was being applied to
			two different bodies.

			Its own applied description is the input, so the kit, colours and
			anything worn survive; only the frame is normalised.
		]]
		applyStandardFrameToNPC(label, character, humanoid)
	end
	character:SetAttribute(
		"Beyond90AvatarSource",
		if wearingRobloxAvatar then "RobloxAvatar" else "Beyond90Avatar"
	)

	if appearanceConfig.ApplyDescriptionStandardization then
		local okDescription, description = pcall(function()
			return humanoid:GetAppliedDescription()
		end)

		if not okDescription or not description then
			warnLog(string.format("Could not read applied HumanoidDescription for %s", label))
			return false
		end

		normalizeDescription(description)

		local okApply, err = pcall(function()
			humanoid:ApplyDescription(description)
		end)

		description:Destroy()

		if not okApply then
			warnLog(string.format("Could not apply standardized HumanoidDescription for %s: %s", label, tostring(err)))
			return false
		end

		RunService.Heartbeat:Wait()
	end

	local measuredHeight, scaleFactor, developmentFootballer = scaleCharacterForCurrentSource(character)
	local hasR15Structure, structureReport = getR15StructureReport(character)
	local intendedHeight = if developmentFootballer
		then appearanceConfig.DevelopmentFootballerTargetHeightStuds
		else (appearanceConfig.IntendedHeightStuds or WorldScaleConfig.CanonicalPlayerHeightStuds)

	character:SetAttribute("Beyond90StandardR15", true)
	character:SetAttribute("Beyond90CanonicalHeightStuds", WorldScaleConfig.CanonicalPlayerHeightStuds)
	character:SetAttribute("Beyond90IntendedHeightStuds", intendedHeight)
	character:SetAttribute("Beyond90MeasuredBodyHeightStuds", measuredHeight or -1)
	character:SetAttribute("Beyond90DevelopmentFootballer", developmentFootballer)
	character:SetAttribute("Beyond90BodyRadius", profileConfig.CanonicalBodyRadius)
	character:SetAttribute("Beyond90FootContactHeight", profileConfig.CanonicalFootContactHeight)
	character:SetAttribute("Beyond90FootForwardOffset", profileConfig.CanonicalFootForwardOffset)
	character:SetAttribute("Beyond90R15StructureValid", hasR15Structure)
	character:SetAttribute("Beyond90R15StructureReport", structureReport)
	character:SetAttribute("Beyond90AvatarSettingsSourceOfTruth", not developmentFootballer and not appearanceConfig.ScaleToCanonicalHeight)
	characterLog(string.format(
		"RigType=R15 height=%.2f targetHeight=%.2f scaleFactor=%.3f developmentFootballer=%s structure=%s appearance=%s",
		measuredHeight or -1,
		intendedHeight,
		scaleFactor or -1,
		tostring(developmentFootballer),
		if hasR15Structure then "ok" else "missing " .. structureReport,
		if wearingRobloxAvatar
			then "roblox-avatar-scaled"
			elseif developmentFootballer
			then "beyond90-body-scaled"
			elseif appearanceConfig.ApplyDescriptionStandardization
			then "runtime-standardized"
			elseif not player
			then "npc-standard-frame"
			else "avatar-settings-source"
	))

	return true
end

function CharacterAppearanceService.StandardizeCharacter(player: Player, character: Model, humanoid: Humanoid): boolean
	-- The player is passed through so their own avatar can be applied; an NPC
	-- has no account to take one from and keeps the uniform body.
	return standardizeCharacter(player.Name, character, humanoid, player)
end

function CharacterAppearanceService.StandardizeNPC(label: string, character: Model, humanoid: Humanoid): boolean
	return standardizeCharacter(label, character, humanoid)
end

return CharacterAppearanceService
