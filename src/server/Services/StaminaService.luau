--!strict
--[[
	Authoritative stamina (§44-§48).

	One loop, every footballer, human and AI alike. Everything it needs is
	server-visible -- measured root speed, the current match phase, whether a
	press is running -- so a client cannot claim to be fresh after sprinting for
	a minute (§47).

	The client still gets a responsive number: the authoritative value is
	published on the character and the client interpolates toward it, rather than
	simulating its own stamina and being corrected. Stamina changes slowly enough
	that this reads as instant while remaining server-owned.

	Deliberately cheap (§102): one bounded tick, no searches, no allocation per
	footballer per frame.
]]
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BallControlMath = require(Shared.Football.BallControlMath)
local GameConfig = require(Shared.Config.GameConfig)
local MatchRulesConfig = require(Shared.Config.MatchRulesConfig)
local StaminaConfig = require(Shared.Config.StaminaConfig)

local FootballerRegistryService = require(script.Parent.FootballerRegistryService)

local StaminaService = {}

local initialized = false
local accumulator = 0
local logAccumulator = 0
-- Footballer id -> stamina. Keyed by id rather than by actor so a respawned
-- character keeps its stamina.
local staminaById: { [number]: number } = {}
-- Ids currently doing high-intensity defensive work; set by DefendingService and
-- AIService, cleared every tick so it can never latch on.
local pressingIds: { [number]: boolean } = {}
local chasingIds: { [number]: boolean } = {}

local function log(message: string)
	if StaminaConfig.Debug.Enabled then
		print(string.format("%s[Stamina] %s", GameConfig.LogPrefix, message))
	end
end

function StaminaService.Get(footballerId: number): number
	return staminaById[footballerId] or StaminaConfig.StartingValue
end

function StaminaService.GetSprintCeiling(footballerId: number): number
	return StaminaConfig.GetSprintCeiling(StaminaService.Get(footballerId))
end

--[[
	Enough left to start a sprint?

	`urgent` spends the reserve: an AI must never look slow because it was saving
	energy during a loose-ball race or a recovery run (§48, §51).
]]
function StaminaService.CanSprint(footballerId: number, urgent: boolean?): boolean
	if StaminaConfig.Enabled ~= true then
		return true
	end
	local reserve = if urgent then StaminaConfig.AI.UrgentReserve else StaminaConfig.AI.ReserveForSprint
	return StaminaService.Get(footballerId) > reserve
end

-- Marked each tick by whoever is running the behaviour; never latches.
function StaminaService.MarkPressing(footballerId: number)
	pressingIds[footballerId] = true
end

function StaminaService.MarkChasing(footballerId: number)
	chasingIds[footballerId] = true
end

function StaminaService.Reset(footballerId: number?)
	if footballerId then
		staminaById[footballerId] = StaminaConfig.StartingValue
		return
	end
	table.clear(staminaById)
end

-- Half time is a real rest, not a full reset: a tired side stays tired (§45).
function StaminaService.ApplyHalfTimeRecovery()
	local fraction = StaminaConfig.Recovery.HalfTimeRecoveryFraction
	for id, value in staminaById do
		local deficit = StaminaConfig.Maximum - value
		staminaById[id] = math.min(StaminaConfig.Maximum, value + deficit * fraction)
	end
	log("Half-time recovery applied")
end

local function publish(actor, value: number)
	if not actor.Character or not actor.Character.Parent then
		return
	end
	actor.Character:SetAttribute(StaminaConfig.Attributes.Value, value)
	actor.Character:SetAttribute(
		StaminaConfig.Attributes.SprintCeiling,
		StaminaConfig.GetSprintCeiling(value)
	)
end

--[[
	One footballer, one tick.

	`phase` is the match phase; during any stoppage everyone recovers, which is
	what makes a restart a genuine breather rather than dead time.
]]
local function step(actor, deltaTime: number, phase: string)
	local id = actor.Id
	if typeof(id) ~= "number" then
		return
	end
	local current = staminaById[id]
	if current == nil then
		current = StaminaConfig.StartingValue
	end

	local rootPart = actor.RootPart
	if not rootPart or not rootPart.Parent then
		staminaById[id] = current
		return
	end

	local speed = BallControlMath.GetHorizontal(rootPart.AssemblyLinearVelocity).Magnitude
	local drain = StaminaConfig.Drain
	local recovery = StaminaConfig.Recovery

	local delta = 0
	local stopped = phase ~= MatchRulesConfig.Phases.Playing

	if stopped then
		-- Play is not live: everyone gets their breath back.
		delta = recovery.StoppagePerSecond
	elseif speed >= StaminaConfig.SprintSpeedThreshold then
		--[[
			Cost scales with how far above the sprint threshold the footballer
			actually is, so easing off genuinely helps rather than being a binary
			on/off.
		]]
		local sprintRange = math.max(
			StaminaConfig.GetSprintCeiling(current) - StaminaConfig.SprintSpeedThreshold,
			1e-3
		)
		local intensity = math.clamp((speed - StaminaConfig.SprintSpeedThreshold) / sprintRange, 0, 1)
		delta = -drain.SprintPerSecond * (drain.PartialSprintScale + (1 - drain.PartialSprintScale) * intensity)
	elseif speed <= StaminaConfig.RestSpeedThreshold then
		delta = recovery.IdlePerSecond
	else
		delta = recovery.JoggingPerSecond
	end

	-- High-intensity defensive work costs even below sprint speed.
	if not stopped then
		if pressingIds[id] then
			delta -= drain.PressPerSecond
		end
		if chasingIds[id] then
			delta -= drain.ChasePerSecond
		end
	end

	staminaById[id] = math.clamp(current + delta * deltaTime, 0, StaminaConfig.Maximum)
	publish(actor, staminaById[id])
end

function StaminaService.Update(deltaTime: number, phase: string)
	if StaminaConfig.Enabled ~= true then
		return
	end
	accumulator += deltaTime
	if accumulator < StaminaConfig.UpdateInterval then
		return
	end
	local tickDelta = accumulator
	accumulator = 0

	for _, actor in FootballerRegistryService.GetAll() do
		step(actor, tickDelta, phase)
	end

	-- Intensity marks are per-tick only, so nothing can stay "pressing" forever.
	table.clear(pressingIds)
	table.clear(chasingIds)

	if StaminaConfig.Debug.Enabled then
		logAccumulator += tickDelta
		if logAccumulator >= StaminaConfig.Debug.LogInterval then
			logAccumulator = 0
			local parts = {}
			for _, actor in FootballerRegistryService.GetAll() do
				table.insert(parts, string.format("%s=%.0f", actor.DisplayName, StaminaService.Get(actor.Id)))
			end
			log(table.concat(parts, " "))
		end
	end
end

function StaminaService.Initialize()
	if initialized then
		return
	end
	initialized = true
	table.clear(staminaById)
end

return StaminaService
