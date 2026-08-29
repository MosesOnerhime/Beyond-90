# Restart Control — how a set piece is taken

Milestone 6.4 (§27–§35). This describes how Beyond 90 actually works, not what a
reference does. For the source research this builds on, see
`docs/research/gameplay-football/match-rules-and-positions.md` — no new
GameplayFootball source inspection was required for this change; the set-piece
box remapping, taker selection and restart lifecycle documented there were
already implemented and are unchanged.

## The problem

Runtime evidence from the 6.3 playtest:

```
RestartReady
    -> AI reaches the stationary kick-off ball
    -> Reception type = LooseBall / TakeInStride
    -> Control acquired
    -> Phase -> Playing
    -> AI dribbles away with the football
```

A kick-off was being completed by ordinary possession acquisition. The cause was
in two places at once:

1. `BallControlService.isRestartBlocked` blocked every footballer **except the
   designated taker** from acquiring the ball — so the taker could acquire it
   normally.
2. `MatchRulesService.NotifyTouch` treated **any** contact from the authorized
   taker as "the restart has been taken", and control acquisition reports a
   touch.

Together those meant "walk onto the ball and dribble" was a legal way to take
every set piece in the game.

Adding a velocity restriction, a possession timeout or a taker speed cap would
each have suppressed the symptom while leaving "a restart is completed by
touching the ball" as the underlying rule. The rule is what was wrong.

## The model

A stationary restart is **not** foot-dribble possession. It is its own state.

```
RestartSetup      everyone placed, ball on the spot
      |
RestartControl    taker designated, ball HELD, nobody may acquire it
      |
      |  a LEGAL RELEASE ACTION is played
      v
Playing           ball is live, ordinary rules resume
```

### Nobody acquires possession during a restart

`BallControlService.isRestartBlocked` now returns true for **everyone**,
including the taker, whenever a restart is pending or the match has not started.
This is the load-bearing change: with no possession path open, "dribble the
kick-off away" is not merely discouraged, it is unrepresentable.

### The ball is held, and so is the taker

`RestartService.UpdateControl` runs every frame while a restart is pending:

- the football is pinned to its spot and its velocity zeroed, so nothing —
  a footballer walking through it, a stray impulse, a servo — can move it;
- the taker is clamped to a bounded radius around the spot
  (`MatchRulesConfig.RestartControl.Movement`, 4.5–7 studs by restart type).

The taker is pulled back to the **edge** of the allowed region rather than to
the spot, so the clamp only removes the part of their movement that broke the
rule instead of fighting their input every frame. They can still turn, aim and
take a short run-up.

### Only a legal action completes it

`MatchRulesService.NotifyTouch` no longer completes a restart at all. A restart
is completed exclusively by `MatchRulesService.NotifyRestartAction(actor,
actionType)`, which requires:

- a restart is pending and has reached RestartReady;
- the actor is the designated taker;
- `actionType` is in that restart's allow-list.

The allow-lists (`MatchRulesConfig.RestartControl.Actions`) are the rules:

| Restart | Legal actions |
| --- | --- |
| Kick-off | GroundPass, ThroughPass, LobPass |
| Goal kick | GroundPass, ThroughPass, LobPass |
| Corner | GroundPass, ThroughPass, LobPass, Shoot |
| Free kick | GroundPass, ThroughPass, LobPass, Shoot |
| Penalty | Shoot |
| Throw-in | ThrowIn |

Control acquisition appears in none of them, which is exactly why it can no
longer take a restart.

### The ball leaves through a dedicated path

`BallControlService.ReleaseForRestart` is the only way a held restart ball can be
played. It does not go through the possession release path — there is no
possession to release — and it briefly suppresses the taker's own reacquisition
so a taker cannot pass to themselves.

## Humans and AI use the same rules

`FootballActionService` skips the possession requirement for a restart take and
gains the action rule in exchange; `FootballActionService.ExecuteAIRestart` puts
an AI taker through the identical release and the identical
`NotifyRestartAction` check. An AI kick-off is a pass, an AI penalty is a shot,
an AI throw-in is a throw — and each completes only because the rules accepted
the action. There is no bot-only restart path.

The AI's *choice* — which team-mate, ground or lofted — remains the AI's, which
is the §2 split between deciding and executing.

## Throw-ins

A throw-in was previously a foot pass from ground level. It is now its own
action (`ThrowInPlanner`):

- the ball is placed at the thrower's hands (`ReleaseHeight`, 4.6 studs above the
  root) at the moment of release, then launched — never welded;
- flight is a genuine ballistic arc, slower and higher than a driven pass;
- **hold duration chooses the distance**, and the player's own target selection
  chooses the receiver. Hold only picks a receiver when the player has not.

The Pass input is mapped to ThrowIn **on the server**, so a client cannot decide
for itself that a kick is a throw.

With no legal receiver the ball is thrown a short distance *infield* rather than
straight back over the same touchline, which would otherwise restart the loop
forever.

## Pre-match

`MatchRulesConfig.Phases.PreMatch` holds a fully assembled, motionless field
until the user presses START MATCH. `MatchAssemblyService` builds it in
dependency order (pitch → footballers → goalkeepers → officials → kick-off
arrangement) with bounded waits, and the client does not reveal the pitch until
`Beyond90FieldReady` is set.

Movement is denied in two places, deliberately:

- the client refuses input while the published phase is PreMatch (responsive);
- `RestartService.HoldAssembly` holds every footballer at the position field
  assembly placed it at (authoritative).

The second is what makes it a real restriction rather than a loading screen.

## Penalty geometry

The penalty spot comes from the stadium, not from a metre constant:

- `Workspace.StadiumDevelopment.PenaltyPoint` is authoritative when present. One
  marker is enough — its distance in from the nearer goal line is measured as a
  ratio and mirrored for the opposite end, because a pitch has two symmetrical
  spots and a second marker is only a chance to disagree with the first.
- With no marker, the ratio in `MatchRulesConfig.Pitch` is used. Those ratios
  were re-measured from the painted markings in
  `Workspace.StadiumDevelopment.stadium` (penalty area 60 studs deep and 137
  wide, spot 40 studs out on a 343 x 241 pitch) rather than converted from
  GameplayFootball's 110 x 72 m pitch, which did not match Beyond 90's own lines.
