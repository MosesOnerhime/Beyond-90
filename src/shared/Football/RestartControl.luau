--!strict
--[[
	Who is holding a set piece, read from the football.

	RESTART CONTROL IS POSSESSION, BUT NOT DRIBBLING (§31, §32).

	Beyond 90 has two distinct ways a footballer can "have" the ball:

		ControlledBall   open play. Dribbling, touches, carrying, everything.
		RestartControl   a set piece. The ball is on its spot and the taker owns
		                 it, but it cannot be carried anywhere.

	Milestone 6.4 made restarts legal by removing possession from the taker
	entirely, which fixed dribbling a kick-off away but left the taker having to
	walk to the ball and reacquire it before the whistle meant anything. This
	module is the middle ground: the taker genuinely holds the restart from the
	moment it is set up, and the systems that grant *dribbling* simply never
	consult it.

	The server publishes these on the ball in `RestartService`; this is the
	shared reader so client and server cannot drift on what the attributes mean.
]]
local MatchRulesConfig = require(script.Parent.Parent.Config.MatchRulesConfig)

local RestartControl = {}

-- The footballer id holding the current restart, if any.
function RestartControl.GetTakerId(ball: BasePart?): number?
	if not ball then
		return nil
	end
	local id = ball:GetAttribute(MatchRulesConfig.RestartControl.ControlAttributeName)
	return if typeof(id) == "number" and id ~= 0 then id else nil
end

-- Is the restart actually live, rather than merely being set up? Before this is
-- true the ball is placed but nobody may play it yet.
function RestartControl.IsAwaitingAction(ball: BasePart?): boolean
	return ball ~= nil
		and ball:GetAttribute(MatchRulesConfig.RestartControl.AwaitingAttributeName) == true
end

function RestartControl.GetKind(ball: BasePart?): string?
	if not ball then
		return nil
	end
	local kind = ball:GetAttribute("MatchRestartKind")
	return if typeof(kind) == "string" and kind ~= "" then kind else nil
end

--[[
	Does this footballer hold a restart that is ready to be played?

	This is the question an ACTION system should ask -- "may I pass/shoot/throw
	right now" -- and the question a DRIBBLING system must never ask.
]]
function RestartControl.IsHeldBy(ball: BasePart?, footballerId: number?): boolean
	if footballerId == nil then
		return false
	end
	return RestartControl.GetTakerId(ball) == footballerId
		and RestartControl.IsAwaitingAction(ball)
end

-- Is `actionType` legal for the restart currently in progress? Mirrors the
-- server's own allow-list so the client does not offer an action that would
-- only be rejected.
function RestartControl.IsActionLegal(ball: BasePart?, actionType: string?): boolean
	local kind = RestartControl.GetKind(ball)
	if not kind or not actionType then
		return false
	end
	local allowed = MatchRulesConfig.RestartControl.Actions[kind]
	return allowed ~= nil and allowed[actionType] == true
end

return RestartControl
