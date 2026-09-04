--!strict
--[[
	SHOT AND PASS POWER, SHOWN OVER THE PLAYER'S HEAD.

	Both actions charge by holding the button, and until now that charge was
	completely invisible: the only way to learn how hard you were about to hit
	the ball was to hit it and watch what happened. A charge the player cannot
	see is not a skill they can develop.

	WHY OVER THE PLAYER AND NOT ON THE HUD.

	Beyond 90 is played from a broadcast camera (AGENTS.md 4), so the eye is on
	the footballer, not on the screen edges. A meter in a corner would ask the
	player to look away from the thing they are aiming. Attached to the player it
	sits inside the same glance as the ball, the defender and the goal.

	It is also DELIBERATELY SPARSE (§40, "Broadcast Camera Readability"): a bar
	and nothing else, only while a charge is live, only for the local player.
	Nothing persists between actions.
]]
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local FootballActionConfig = require(Shared.Config.FootballActionConfig)

local Controllers = script.Parent
local InputController = require(Controllers:WaitForChild("InputController"))

local PowerIndicatorController = {}

local localPlayer = Players.LocalPlayer
local config = FootballActionConfig.PowerIndicator

local initialized = false
local renderConnection: RBXScriptConnection? = nil
local billboard: BillboardGui? = nil
local fillBar: Frame? = nil
local labelText: TextLabel? = nil
local currentAlpha = 0
local visibleAlpha = 0

--[[
	Which charge curve applies to this action.

	Shooting and passing charge on different curves, and showing a shot's curve
	while charging a pass would be a meter that lies. Returns nil for actions
	that do not charge at all, which is how the indicator stays hidden for
	tackles, dives and everything else that shares the input path.
]]
local function resolvePower(actionType: string?, held: number): (number?, Color3?, string?)
	if actionType == "Shoot" then
		--[[
			The shot charges on an explicit curve, and the bar reads that SAME
			curve rather than a linear ramp over the hold time. A meter that
			fills evenly while the power behind it accelerates teaches a timing
			the game does not use.
		]]
		local charge = FootballActionConfig.Shoot.Charge
		local span = math.max(charge.MaximumHoldSeconds - charge.MinimumHoldSeconds, 1e-4)
		local alpha = math.clamp((held - charge.MinimumHoldSeconds) / span, 0, 1) ^ charge.CurveExponent
		local power = charge.MinimumPower + (charge.MaximumPower - charge.MinimumPower) * alpha
		-- As a fraction of full power, so a tap already reads as a real shot
		-- rather than as an empty bar.
		return math.clamp(power / math.max(charge.MaximumPower, 1e-4), 0, 1), config.ShootColor, "POWER"
	end

	if actionType == "GroundPass" or actionType == "LobPass" or actionType == "ThroughPass" then
		--[[
			The pass does NOT use the shot's Charge block -- it scales intensity
			linearly over HoldMaxTime between MinIntensity and MaxIntensity. Two
			different models, so two different readings; reporting the shot curve
			for a pass would be a meter that lies.
		]]
		local pass = FootballActionConfig.Pass
		local alpha = math.clamp(held / math.max(pass.HoldMaxTime, 1e-4), 0, 1)
		local intensity = pass.MinIntensity + (pass.MaxIntensity - pass.MinIntensity) * alpha
		return math.clamp(intensity / math.max(pass.MaxIntensity, 1e-4), 0, 1), config.PassColor, "PASS"
	end

	return nil, nil, nil
end

local function ensureBillboard(character: Model): BillboardGui?
	local head = character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
	if not head or not head:IsA("BasePart") then
		return nil
	end
	if billboard and billboard.Adornee == head then
		return billboard
	end
	if billboard then
		billboard:Destroy()
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = "Beyond90PowerIndicator"
	gui.Adornee = head
	gui.AlwaysOnTop = true
	gui.Size = UDim2.fromOffset(config.Width, config.Height + config.LabelHeight)
	gui.StudsOffsetWorldSpace = Vector3.new(0, config.HeightAboveHead, 0)
	-- MaxDistance keeps it from drawing as a smear when the broadcast camera is
	-- pulled all the way back.
	gui.MaxDistance = config.MaximumDistance
	gui.Parent = localPlayer:WaitForChild("PlayerGui")

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, config.LabelHeight)
	label.Position = UDim2.fromScale(0, 0)
	label.Font = Enum.Font.GothamBold
	label.TextSize = config.LabelTextSize
	label.TextColor3 = config.LabelColor
	label.Text = "POWER"
	label.Parent = gui

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Size = UDim2.new(1, 0, 0, config.Height)
	track.Position = UDim2.new(0, 0, 0, config.LabelHeight)
	track.BackgroundColor3 = config.TrackColor
	track.BackgroundTransparency = config.TrackTransparency
	track.BorderSizePixel = 0
	track.Parent = gui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, config.CornerRadius)
	corner.Parent = track

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = config.ShootColor
	fill.BorderSizePixel = 0
	fill.Parent = track

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, config.CornerRadius)
	fillCorner.Parent = fill

	billboard = gui
	fillBar = fill
	labelText = label
	return gui
end

local function update(deltaTime: number)
	local character = localPlayer.Character
	if not character then
		return
	end

	local actionType, held = InputController.GetChargingAction()
	local power, color, caption = resolvePower(actionType, held)
	local target = power or 0

	currentAlpha = target
	-- Fade rather than pop, and fade OUT faster than in: the release is the
	-- moment the player is watching the ball, not the meter.
	local rate = if target > 0 then config.FadeInRate else config.FadeOutRate
	visibleAlpha += (( if target > 0 then 1 else 0) - visibleAlpha)
		* math.clamp(rate * deltaTime, 0, 1)

	local gui = ensureBillboard(character)
	if not gui or not fillBar or not labelText then
		return
	end

	if visibleAlpha <= 0.01 then
		gui.Enabled = false
		return
	end
	gui.Enabled = true
	gui.Size = UDim2.fromOffset(config.Width, config.Height + config.LabelHeight)
	fillBar.Size = UDim2.fromScale(currentAlpha, 1)
	if color then
		fillBar.BackgroundColor3 = color
		labelText.Text = caption or "POWER"
	end
	labelText.TextTransparency = 1 - visibleAlpha
	fillBar.BackgroundTransparency = 1 - visibleAlpha
	local track = fillBar.Parent
	if track and track:IsA("Frame") then
		track.BackgroundTransparency = 1 - (1 - config.TrackTransparency) * visibleAlpha
	end
end

function PowerIndicatorController.Initialize()
	if initialized or config.Enabled ~= true then
		return
	end
	initialized = true
	renderConnection = RunService.RenderStepped:Connect(update)
end

function PowerIndicatorController.Destroy()
	if not initialized then
		return
	end
	initialized = false
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end
	if billboard then
		billboard:Destroy()
		billboard = nil
	end
	fillBar = nil
	labelText = nil
	currentAlpha = 0
	visibleAlpha = 0
end

return PowerIndicatorController
