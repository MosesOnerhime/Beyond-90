--!strict
--[[
	Control scheme.

	Beyond 90 supports keyboard/mouse, gamepad and touch from one shared input
	abstraction (§35). What this adds is the PRESENTATION half: which prompt a
	player is shown for an action.

	Auto-detection alone is not good enough on desktop. A player with a controller
	plugged in but playing on the keyboard was shown controller glyphs, and a
	keyboard player who nudged a stick had the whole HUD change under them. So the
	scheme is an explicit, remembered choice (§40), asked once and changeable in
	Settings at any time.

	`Touch` is not offered as a choice; a touch device simply is touch.
]]
local ControlSchemeConfig = {}

ControlSchemeConfig.Schemes = {
	Keyboard = "Keyboard",
	Gamepad = "Gamepad",
	Touch = "Touch",
}

-- Mirrored onto the LocalPlayer so any UI can read the choice without a
-- dependency on the controller that owns it.
ControlSchemeConfig.AttributeName = "Beyond90ControlScheme"
-- Set once the player has actually answered the prompt, so it is asked once.
ControlSchemeConfig.ChosenAttributeName = "Beyond90ControlSchemeChosen"

ControlSchemeConfig.Prompt = {
	Enabled = true,
	Title = "CHOOSE YOUR CONTROLS",
	Body = "You can change this at any time in Settings.",
}

ControlSchemeConfig.Display = {
	Keyboard = { Name = "KEYBOARD & MOUSE", Summary = "WASD to move, keys for football actions." },
	Gamepad = { Name = "GAMEPAD", Summary = "Left stick to move, face buttons for football actions." },
	Touch = { Name = "TOUCH", Summary = "On-screen stick and contextual action buttons." },
}

--[[
	The single control table the whole game reads.

	One row per action, carrying both presentations. The HUD, the menu footer and
	the controls panel all render from this, so a binding can never be described
	two different ways in two different places.

	`Keyboard` is resolved from PlayerConfig.Input at runtime by GetKeyboardLabel
	where a KeyCode field name is given, so the displayed key always matches the
	actual binding.
]]
ControlSchemeConfig.Actions = {
	{ Id = "Move", Group = "Movement", Label = "MOVE", KeyboardText = "W A S D", Gamepad = "L-STICK" },
	{ Id = "Sprint", Group = "Movement", Label = "SPRINT", KeyboardText = "SHIFT", Gamepad = "RT", Glyph = "RT" },
	{ Id = "Jump", Group = "Movement", Label = "JUMP", KeyboardKey = "JumpKey", Gamepad = "A" },
	{ Id = "Pass", Group = "Attacking", Label = "PASS", KeyboardKey = "PassKey", Gamepad = "X", Glyph = "X" },
	{ Id = "LobPass", Group = "Attacking", Label = "LOB PASS", KeyboardText = "DOUBLE TAP PASS", Gamepad = "X  X" },
	{ Id = "ThroughPass", Group = "Attacking", Label = "THROUGH BALL", KeyboardKey = "ThroughPassKey", Gamepad = "Y", Glyph = "Y" },
	{ Id = "KnockOn", Group = "Attacking", Label = "KNOCK ON", KeyboardKey = "KnockOnKey", Gamepad = "RB", Glyph = "RB" },
	{ Id = "Shoot", Group = "Attacking", Label = "SHOOT  (HOLD FOR POWER)", KeyboardKey = "ShootKey", Gamepad = "B", Glyph = "B" },
	{ Id = "FakeShot", Group = "Attacking", Label = "FAKE SHOT", KeyboardText = "DOUBLE TAP SHOOT", Gamepad = "B  B" },
	{ Id = "Tackle", Group = "Defending", Label = "PRESS / TACKLE", KeyboardKey = "TackleKey", Gamepad = "LB" },
	{ Id = "CameraToggle", Group = "Camera", Label = "SWITCH CAMERA", KeyboardKey = "CameraToggleKey", Gamepad = "D-PAD UP" },
	{ Id = "CameraLock", Group = "Camera", Label = "MOUSE LOCK  (PRO CAMERA)", KeyboardKey = "CameraLockKey", Gamepad = "--" },
}

-- Shown in the compact always-visible HUD strip. Deliberately short: the full
-- list lives behind the expandable panel.
ControlSchemeConfig.PrimaryActionIds = { "Sprint", "Pass", "Shoot", "Tackle" }

ControlSchemeConfig.Groups = { "Movement", "Attacking", "Defending", "Camera" }

--[[
	THE GOALKEEPER'S CONTROLS ARE THE SAME KEYS, MEANING DIFFERENT THINGS.

	A keeper presses the key an outfielder presses to tackle, and dives; the key
	they press to pass, and throws the ball out. That reroute lives in
	GoalkeeperController -- nothing new is bound, so gamepad and touch need no
	extra buttons and no extra configuration.

	But a HUD that still reads "PRESS / TACKLE" while the button dives is worse
	than no HUD, because it is confidently wrong. So the same rows are RELABELLED
	rather than replaced: the binding, the glyph and the keyboard resolution all
	stay exactly as they are, and only the words change.

	Actions that are meaningless in goal -- through balls, knock-ons, fake shots
	-- are dropped instead of being relabelled into something invented.
]]
ControlSchemeConfig.GoalkeeperOverrides = {
	Tackle = { Label = "DIVE  (AIM WITH MOVE)", Group = "Goalkeeping" },
	Pass = { Label = "THROW / ROLL OUT", Group = "Goalkeeping" },
	Shoot = { Label = "KICK LONG", Group = "Goalkeeping" },
}

-- Rows an outfielder has that a goalkeeper does not.
ControlSchemeConfig.GoalkeeperHiddenActionIds = {
	LobPass = true,
	ThroughPass = true,
	KnockOn = true,
	FakeShot = true,
}

ControlSchemeConfig.GoalkeeperPrimaryActionIds = { "Sprint", "Tackle", "Pass" }
ControlSchemeConfig.GoalkeeperGroups = { "Movement", "Goalkeeping", "Camera" }

-- Menu navigation prompts, per scheme.
--[[
	Footer control hints, per scheme (§9).

	`SelectImage` / `BackImage` name the artwork; `Select` / `Back` are the text
	fallbacks used when that artwork is unavailable, which is what keeps a
	newly-uploaded, not-yet-confirmed asset from producing an empty footer (§57).

	Keyboard now uses the real production icons -- a left mouse click and the ESC
	key -- instead of the controller "A" glyph, which told a keyboard player to
	press a button they do not have.
]]
ControlSchemeConfig.MenuPrompts = {
	Keyboard = {
		Select = "CLICK",
		Back = "ESC",
		SelectGlyph = false,
		SelectImageKey = "LeftMouseClick",
		BackImageKey = "EscKey",
	},
	Gamepad = { Select = "A", Back = "B", SelectGlyph = true, SelectImageKey = "Select", BackImageKey = "OpenMenu" },
	Touch = { Select = "TAP", Back = "BACK", SelectGlyph = false },
}

function ControlSchemeConfig.Normalize(value: any): string
	if value == ControlSchemeConfig.Schemes.Gamepad then
		return ControlSchemeConfig.Schemes.Gamepad
	elseif value == ControlSchemeConfig.Schemes.Touch then
		return ControlSchemeConfig.Schemes.Touch
	end
	return ControlSchemeConfig.Schemes.Keyboard
end

--[[
	The keyboard text for an action, resolved against the live input config so a
	rebinding is reflected everywhere without touching this table.
]]
function ControlSchemeConfig.GetKeyboardLabel(action, inputConfig): string
	if action.KeyboardText then
		return action.KeyboardText
	end
	local keyCode = action.KeyboardKey and inputConfig[action.KeyboardKey]
	if typeof(keyCode) == "EnumItem" then
		return string.upper(keyCode.Name)
	end
	return "--"
end

--[[
	One action row, as the given role sees it.

	Returns the shared row unchanged for an outfielder, and a shallow copy with
	the goalkeeper's wording for a keeper. A copy, so relabelling can never
	mutate the shared table and leak a keeper's wording into an outfielder's HUD.
]]
function ControlSchemeConfig.Localise(action, asGoalkeeper: boolean?)
	if not asGoalkeeper or not action then
		return action
	end
	local override = ControlSchemeConfig.GoalkeeperOverrides[action.Id]
	if not override then
		return action
	end
	local row = table.clone(action)
	row.Label = override.Label
	row.Group = override.Group
	return row
end

function ControlSchemeConfig.GetActionsByGroup(group: string, asGoalkeeper: boolean?)
	local rows = {}
	for _, action in ControlSchemeConfig.Actions do
		if asGoalkeeper then
			if not ControlSchemeConfig.GoalkeeperHiddenActionIds[action.Id] then
				local localised = ControlSchemeConfig.Localise(action, true)
				if localised.Group == group then
					table.insert(rows, localised)
				end
			end
		elseif action.Group == group then
			table.insert(rows, action)
		end
	end
	return rows
end

-- Which group list the controls panel should render for this role.
function ControlSchemeConfig.GetGroups(asGoalkeeper: boolean?)
	return if asGoalkeeper then ControlSchemeConfig.GoalkeeperGroups else ControlSchemeConfig.Groups
end

function ControlSchemeConfig.GetPrimaryActionIds(asGoalkeeper: boolean?)
	return if asGoalkeeper
		then ControlSchemeConfig.GoalkeeperPrimaryActionIds
		else ControlSchemeConfig.PrimaryActionIds
end

function ControlSchemeConfig.GetAction(id: string)
	for _, action in ControlSchemeConfig.Actions do
		if action.Id == id then
			return action
		end
	end
	return nil
end

return ControlSchemeConfig
