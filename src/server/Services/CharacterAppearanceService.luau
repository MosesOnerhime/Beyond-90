local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

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

local function scaleCharacterToCanonicalHeight(character: Model): number?
	if not appearanceConfig.ScaleToCanonicalHeight then
		return measureBodyHeight(character)
	end

	local measuredHeight = measureBodyHeight(character)

	if not measuredHeight or measuredHeight <= 0 then
		return nil
	end

	local targetHeight = appearanceConfig.TargetHeightStuds or WorldScaleConfig.CanonicalPlayerHeightStuds
	local scaleFactor = targetHeight / measuredHeight
	local ok, err = pcall(function()
		character:ScaleTo(character:GetScale() * scaleFactor)
	end)

	if not ok then
		warnLog(string.format("Could not scale character to canonical height: %s", tostring(err)))
		return measuredHeight
	end

	RunService.Heartbeat:Wait()
	return measureBodyHeight(character) or targetHeight
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

function CharacterAppearanceService.StandardizeCharacter(player: Player, character: Model, humanoid: Humanoid): boolean
	if not appearanceConfig.StandardizeEnabled then
		return false
	end

	if humanoid.RigType ~= Enum.HumanoidRigType.R15 then
		warn(string.format(
			"%s[Character] ERROR expected R15 but received %s for %s",
			GameConfig.LogPrefix,
			humanoid.RigType.Name,
			player.Name
		))
		character:SetAttribute("Beyond90StandardR15", false)
		return false
	end

	local okDescription, description = pcall(function()
		return humanoid:GetAppliedDescription()
	end)

	if not okDescription or not description then
		warnLog(string.format("Could not read applied HumanoidDescription for %s", player.Name))
		return false
	end

	normalizeDescription(description)

	local okApply, err = pcall(function()
		humanoid:ApplyDescription(description)
	end)

	description:Destroy()

	if not okApply then
		warnLog(string.format("Could not apply standardized HumanoidDescription for %s: %s", player.Name, tostring(err)))
		return false
	end

	RunService.Heartbeat:Wait()
	local measuredHeight = scaleCharacterToCanonicalHeight(character)
	local hasR15Structure, structureReport = getR15StructureReport(character)
	local targetHeight = appearanceConfig.TargetHeightStuds or WorldScaleConfig.CanonicalPlayerHeightStuds

	character:SetAttribute("Beyond90StandardR15", true)
	character:SetAttribute("Beyond90CanonicalHeightStuds", WorldScaleConfig.CanonicalPlayerHeightStuds)
	character:SetAttribute("Beyond90TargetHeightStuds", targetHeight)
	character:SetAttribute("Beyond90MeasuredBodyHeightStuds", measuredHeight or -1)
	character:SetAttribute("Beyond90BodyRadius", profileConfig.CanonicalBodyRadius)
	character:SetAttribute("Beyond90FootContactHeight", profileConfig.CanonicalFootContactHeight)
	character:SetAttribute("Beyond90FootForwardOffset", profileConfig.CanonicalFootForwardOffset)
	character:SetAttribute("Beyond90R15StructureValid", hasR15Structure)
	character:SetAttribute("Beyond90R15StructureReport", structureReport)
	characterLog(string.format(
		"RigType=R15 height=%.2f targetHeight=%.2f structure=%s appearance=standard-r15-blocky",
		measuredHeight or -1,
		targetHeight,
		if hasR15Structure then "ok" else "missing " .. structureReport
	))

	return true
end

return CharacterAppearanceService
