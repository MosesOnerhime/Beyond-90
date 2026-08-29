--!strict
--[[
	Football positions.

	One definition per position, shared by every system that needs to know what a
	footballer is for: formation anchors, set-piece placement, AI behaviour
	weighting, the human skill profile, and the selection UI.

	Anchors are NORMALIZED (-1 .. 1 along each pitch axis), never metres or
	studs. GameplayFootball stores `GetFormationEntry().position` the same way and
	multiplies by the pitch half-extents at the point of use, which is what lets
	one formation description work for any pitch size and be remapped into a
	corner-kick or free-kick box without being re-authored.
	See docs/research/gameplay-football/match-rules-and-positions.md.

	Longitudinal: -1 = own goal line, +1 = opponent goal line.
	Lateral:      -1 = one touchline, +1 = the other.
]]
local PositionConfig = {
	SlotAttributeName = "Beyond90PositionSlot",
	CategoryAttributeName = "Beyond90PositionCategory",

	Categories = {
		Goalkeeper = "Goalkeeper",
		Defence = "Defence",
		Midfield = "Midfield",
		Attack = "Attack",
	},
}

--[[
	Skill profile.

	Position shapes the footballer, it does not play the game (§43): these scale
	execution quality only. No entry here may decide WHERE to run, WHO to pass to
	or WHETHER to shoot -- those stay with the controller, human or AI.

	1.0 is the Beyond 90 baseline; a value below 1 is a genuine weakness.
]]
local function skill(dribbling: number, passing: number, shooting: number, tackling: number, goalkeeping: number)
	return {
		Dribbling = dribbling,
		Passing = passing,
		Shooting = shooting,
		Tackling = tackling,
		Goalkeeping = goalkeeping,
	}
end

--[[
	AI behaviour weighting (§44).

	HoldShape      how strongly the AI returns to its anchor instead of chasing
	PressWillingness  how readily it takes a designated press
	RunWillingness    how far forward it will break when its team has the ball
	MaximumAdvance / MaximumRetreat  normalized bounds on its anchor, so a
	                  defender cannot end up leading the line
]]
local function aiProfile(holdShape: number, press: number, run: number, maxAdvance: number, maxRetreat: number)
	return {
		HoldShape = holdShape,
		PressWillingness = press,
		RunWillingness = run,
		MaximumAdvance = maxAdvance,
		MaximumRetreat = maxRetreat,
	}
end

PositionConfig.Positions = {
	GK = {
		Id = "GK",
		Category = PositionConfig.Categories.Goalkeeper,
		DisplayName = "GOALKEEPER",
		ShortName = "GK",
		Summary = "Protect the goal • distribute play",
		-- Matches GameplayFootball's keeper reset of side * 0.98.
		Anchor = { Longitudinal = -0.94, Lateral = 0 },
		AIRole = "Goalkeeper",
		Skill = skill(0.8, 0.9, 0.7, 0.85, 1),
		AI = aiProfile(1, 0, 0, -0.7, -1),
		Order = 1,
	},

	DEF = {
		Id = "DEF",
		Category = PositionConfig.Categories.Defence,
		DisplayName = "DEFENDER",
		ShortName = "DEF",
		Summary = "Win possession • protect space",
		Anchor = { Longitudinal = -0.52, Lateral = -0.18 },
		AIRole = "Defender",
		Skill = skill(0.92, 0.95, 0.85, 1.1, 0.6),
		AI = aiProfile(0.9, 1, 0.35, 0.15, -0.95),
		Order = 2,
	},

	MID = {
		Id = "MID",
		Category = PositionConfig.Categories.Midfield,
		DisplayName = "MIDFIELDER",
		ShortName = "MID",
		Summary = "Link play • support both phases",
		Anchor = { Longitudinal = -0.02, Lateral = 0.28 },
		AIRole = "Support",
		Skill = skill(1.02, 1.08, 0.95, 0.95, 0.6),
		AI = aiProfile(0.6, 0.8, 0.7, 0.55, -0.7),
		Order = 3,
	},

	FWD = {
		Id = "FWD",
		Category = PositionConfig.Categories.Attack,
		DisplayName = "FORWARD",
		ShortName = "FWD",
		Summary = "Create chances • attack goal",
		Anchor = { Longitudinal = 0.48, Lateral = -0.12 },
		AIRole = "Forward",
		Skill = skill(1.08, 0.95, 1.12, 0.8, 0.6),
		AI = aiProfile(0.4, 0.6, 1, 0.95, -0.3),
		Order = 4,
	},
}

--[[
	Slot lists per match format.

	The goalkeeper is an ADDITIONAL slot, not one of the outfield three -- 3v3
	means three outfield footballers per side. Larger formats are listed so the
	architecture is demonstrably not 3v3-only (§21), but only formats the game
	actually runs are enabled.
]]
PositionConfig.Formations = {
	["3v3"] = { Enabled = true, Outfield = { "DEF", "MID", "FWD" }, Goalkeeper = "GK" },
	["5v5"] = { Enabled = false, Outfield = { "DEF", "DEF", "MID", "FWD" }, Goalkeeper = "GK" },
	["7v7"] = { Enabled = false, Outfield = { "DEF", "DEF", "MID", "MID", "FWD", "FWD" }, Goalkeeper = "GK" },
	["11v11"] = { Enabled = false, Outfield = { "DEF", "DEF", "DEF", "DEF", "MID", "MID", "MID", "FWD", "FWD", "FWD" }, Goalkeeper = "GK" },
}

-- Modes map to a formation. Training uses the 3v3 shape so DEV AI behaves the
-- same way there as in a match.
PositionConfig.ModeFormations = {
	Quick3v3 = "3v3",
	TrainingFree = "3v3",
}

function PositionConfig.Get(slotId: string?)
	return if typeof(slotId) == "string" then PositionConfig.Positions[slotId] else nil
end

function PositionConfig.IsGoalkeeper(slotId: string?): boolean
	local position = PositionConfig.Get(slotId)
	return position ~= nil and position.Category == PositionConfig.Categories.Goalkeeper
end

function PositionConfig.GetFormation(modeId: string?)
	local formationId = modeId and PositionConfig.ModeFormations[modeId] or "3v3"
	return PositionConfig.Formations[formationId], formationId
end

-- Every slot a format fields, goalkeeper last so outfield indices stay stable.
function PositionConfig.GetSlotIds(modeId: string?): { string }
	local formation = PositionConfig.GetFormation(modeId)
	local slots = {}
	if not formation then
		return slots
	end
	for _, slotId in formation.Outfield do
		table.insert(slots, slotId)
	end
	if formation.Goalkeeper then
		table.insert(slots, formation.Goalkeeper)
	end
	return slots
end

-- Selection order for the UI: goalkeeper first, then back to front.
function PositionConfig.GetSelectableSlots(modeId: string?): { string }
	local seen, ordered = {}, {}
	for _, slotId in PositionConfig.GetSlotIds(modeId) do
		if not seen[slotId] then
			seen[slotId] = true
			table.insert(ordered, slotId)
		end
	end
	table.sort(ordered, function(a, b)
		return (PositionConfig.Positions[a].Order or 99) < (PositionConfig.Positions[b].Order or 99)
	end)
	return ordered
end

-- Skill multiplier for one discipline, defaulting to the baseline when a
-- footballer has no position assigned yet.
function PositionConfig.GetSkill(slotId: string?, discipline: string): number
	local position = PositionConfig.Get(slotId)
	if not position then
		return 1
	end
	local value = position.Skill[discipline]
	return if typeof(value) == "number" then value else 1
end

return PositionConfig
