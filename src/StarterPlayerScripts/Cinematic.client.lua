--[[
	Cinematic
	A slow film of the Duck Pond: fade in on a shot, hold it a few seconds as
	the camera moves, fade out, and on to the next -- never the same shot
	twice running. The studded button in the top right starts and stops it.

	The places come from ReplicatedStorage.Shots (tools/make_shots.py): the
	pond, its islands, the weir, Solitude, the paths along the water and the
	benches. Each shot is a function of t, 0 to 1, giving the camera's
	CFrame (and, for one, its field of view).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local StudUI = require(script.Parent:WaitForChild("StudUI"))
local P = require(ReplicatedStorage:WaitForChild("Shots"))

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local HOLD = 7 -- seconds a shot plays
local FADE = 1.1
local FOV = 60

local rng = Random.new()
local W = P.water

-- Helpers ----------------------------------------------------------------------

local function pick(list)
	return list[rng:NextInteger(1, #list)]
end

local function ease(t)
	return t * t * (3 - 2 * t)
end

-- A point a distance along a polyline, and the way it's heading there.
local function along(line, distance)
	local walked = 0
	for i = 1, #line - 1 do
		local leg = (line[i + 1] - line[i]).Magnitude
		if walked + leg >= distance or i == #line - 1 then
			local f = math.clamp((distance - walked) / math.max(leg, 0.01), 0, 1)
			return line[i]:Lerp(line[i + 1], f), (line[i + 1] - line[i]).Unit
		end
		walked += leg
	end
	return line[#line], Vector3.new(0, 0, 1)
end

local function length(line)
	local total = 0
	for i = 1, #line - 1 do
		total += (line[i + 1] - line[i]).Magnitude
	end
	return total
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

local function duck()
	local pond = workspace:FindFirstChild("DuckPond")
	local ducks = pond and pond:FindFirstChild("Ducks")
	if not ducks then
		return nil
	end
	local birds = {}
	for _, m in ipairs(ducks:GetChildren()) do
		if m:IsA("Model") and m.PrimaryPart then
			table.insert(birds, m)
		end
	end
	return if #birds > 0 then pick(birds) else nil
end

-- The shots ----------------------------------------------------------------------
-- Each: name, and make() -> { focus = Vector3, at = function(t) -> CFrame, fov? }

local SHOTS = {}

-- Walking a path by the water, eye height, looking ahead.
table.insert(SHOTS, { name = "Along the path", make = function()
	local line = pick(P.paths)
	local total = length(line)
	local start = rng:NextNumber(0, math.max(0, total - 90))
	local function eye(d)
		local p = along(line, math.min(d, total))
		return p + Vector3.new(0, 5.5, 0)
	end
	return {
		focus = eye(start),
		at = function(t)
			local d = start + 70 * t
			return CFrame.lookAt(eye(d), eye(d + 25) - Vector3.new(0, 1.5, 0))
		end,
	}
end })

-- Straight down over the pond, turning slowly, easing in or out.
table.insert(SHOTS, { name = "Bird's eye", make = function()
	local inward = rng:NextNumber() < 0.5
	local spin = rng:NextNumber(0, math.pi * 2)
	return {
		focus = P.pond,
		at = function(t)
			local k = ease(t)
			local h = if inward then 330 - 130 * k else 200 + 130 * k
			local angle = spin + 0.35 * t
			return CFrame.new(P.pond + Vector3.new(0, h, 0)) * CFrame.Angles(-math.pi / 2, 0, 0)
				* CFrame.Angles(0, 0, angle)
		end,
	}
end })

-- Round an island, low over the water.
table.insert(SHOTS, { name = "Round the island", make = function()
	local island = pick(P.islands)
	local r = island.radius + 55
	local a0 = rng:NextNumber(0, math.pi * 2)
	local dir = if rng:NextNumber() < 0.5 then 1 else -1
	return {
		focus = island.centre,
		at = function(t)
			local a = a0 + dir * 0.9 * t
			local eye = island.centre + Vector3.new(math.cos(a) * r, 18, math.sin(a) * r)
			return CFrame.lookAt(eye, island.centre + Vector3.new(0, 10, 0))
		end,
	}
end })

-- A duck's-eye glide across the water toward an island.
table.insert(SHOTS, { name = "Duck's eye", make = function()
	local island = pick(P.islands)
	local a = rng:NextNumber(0, math.pi * 2)
	local from = island.centre + Vector3.new(math.cos(a), 0, math.sin(a)) * (island.radius + 110)
	local to = island.centre + Vector3.new(math.cos(a), 0, math.sin(a)) * (island.radius + 45)
	return {
		focus = to,
		at = function(t)
			local p = from:Lerp(to, ease(t))
			local eye = Vector3.new(p.X, W + 1.3 + math.sin(t * 9) * 0.08, p.Z)
			return CFrame.lookAt(eye, island.centre + Vector3.new(0, 6, 0))
		end,
	}
end })

-- From a bench, craning up to show the pond.
table.insert(SHOTS, { name = "Crane up", make = function()
	local bench = pick(P.benches)
	local toPond = flat(P.pond - bench).Unit
	local low = bench - toPond * 9 + Vector3.new(0, 3, 0)
	local high = bench - toPond * 30 + Vector3.new(0, 55, 0)
	return {
		focus = bench,
		at = function(t)
			local k = ease(t)
			local eye = low:Lerp(high, k)
			local look = (bench + Vector3.new(0, 2, 0)):Lerp(P.pond, k)
			return CFrame.lookAt(eye, look)
		end,
	}
end })

-- Pushing in on the weir, low and slow.
table.insert(SHOTS, { name = "The weir", make = function()
	local side = rng:NextNumber(-0.6, 0.6)
	local fromDir = (flat(P.pond - P.weir).Unit + Vector3.new(side, 0, side)).Unit
	return {
		focus = P.weir,
		at = function(t)
			local d = 90 - 50 * ease(t)
			local eye = P.weir + fromDir * d + Vector3.new(0, 8, 0)
			return CFrame.lookAt(eye, P.weir + Vector3.new(0, 1, 0))
		end,
	}
end })

-- Sliding past Solitude.
table.insert(SHOTS, { name = "Solitude", make = function()
	local a = rng:NextNumber(0, math.pi * 2)
	local out = Vector3.new(math.cos(a), 0, math.sin(a))
	local across = Vector3.new(-out.Z, 0, out.X)
	return {
		focus = P.solitude,
		at = function(t)
			local eye = P.solitude + out * 95 + across * (t - 0.5) * 90 + Vector3.new(0, 16, 0)
			return CFrame.lookAt(eye, P.solitude + Vector3.new(0, 14, 0))
		end,
	}
end })

-- Following a duck, just behind and above.
table.insert(SHOTS, { name = "Follow a duck", make = function()
	local bird = duck()
	if not bird then
		return nil
	end
	local smooth = nil
	return {
		focus = bird:GetPivot().Position,
		at = function()
			if not bird.Parent then
				return nil
			end
			local cf = bird:GetPivot()
			local eye = cf.Position - flat(cf.LookVector).Unit * 9 + Vector3.new(0, 3.5, 0)
			smooth = if smooth then smooth:Lerp(eye, 0.05) else eye
			return CFrame.lookAt(smooth, cf.Position + flat(cf.LookVector).Unit * 6)
		end,
	}
end })

-- Looking down at the water's surface, tilting up to the far shore.
table.insert(SHOTS, { name = "Reflections", make = function()
	local island = pick(P.islands)
	local a = rng:NextNumber(0, math.pi * 2)
	local eye = island.centre + Vector3.new(math.cos(a), 0, math.sin(a)) * (island.radius + 70)
	eye = Vector3.new(eye.X, W + 4, eye.Z)
	local toward = flat(island.centre - eye).Unit
	return {
		focus = island.centre,
		at = function(t)
			local pitch = -1.1 + 1.05 * ease(t)
			local look = toward * math.cos(pitch) + Vector3.new(0, math.sin(pitch), 0)
			return CFrame.lookAt(eye, eye + look)
		end,
	}
end })

-- Drifting sideways over the treetops at the pond's edge.
table.insert(SHOTS, { name = "Over the trees", make = function()
	local a = rng:NextNumber(0, math.pi * 2)
	local out = Vector3.new(math.cos(a), 0, math.sin(a))
	local across = Vector3.new(-out.Z, 0, out.X)
	local base = P.pond + out * 330 + Vector3.new(0, 85, 0)
	return {
		focus = P.pond + out * 200,
		at = function(t)
			local eye = base + across * (t - 0.5) * 160
			return CFrame.lookAt(eye, P.pond + across * (t - 0.5) * 60)
		end,
	}
end })

-- The vertigo shot: pulling back while zooming in, so an island stays the
-- same size as the shore behind it swells.
table.insert(SHOTS, { name = "Dolly zoom", make = function()
	local island = pick(P.islands)
	local a = rng:NextNumber(0, math.pi * 2)
	local dir = Vector3.new(math.cos(a), 0, math.sin(a))
	local target = island.centre + Vector3.new(0, 8, 0)
	local width = island.radius * 2.2
	return {
		focus = island.centre,
		at = function(t)
			local k = ease(t)
			local d = 90 + 170 * k
			local fov = math.deg(2 * math.atan(width / 2 / d))
			local eye = target + dir * d + Vector3.new(0, 10, 0)
			return CFrame.lookAt(eye, target), math.clamp(fov, 12, 75)
		end,
	}
end })

-- The film ------------------------------------------------------------------------

local gui = Instance.new("ScreenGui")
gui.Name = "Cinematic"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 50
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling -- a button's studs and label draw over it
gui.Parent = player:WaitForChild("PlayerGui")

local black = Instance.new("Frame")
black.Name = "Fade"
black.BackgroundColor3 = Color3.new(0, 0, 0)
black.BackgroundTransparency = 1
black.Size = UDim2.fromScale(1, 1)
black.Active = false
black.Parent = gui

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.new(0, 28, 1, -64)
title.Size = UDim2.fromOffset(500, 40)
title.Font = Enum.Font.GothamMedium
title.TextSize = 22
title.TextColor3 = Color3.new(1, 1, 1)
title.TextTransparency = 1
title.TextStrokeTransparency = 1
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = gui

local button = StudUI.button(gui, "CINEMATIC", Color3.fromRGB(58, 110, 170))
button.AnchorPoint = Vector2.new(1, 0)
button.Position = UDim2.new(1, -20, 0, 70)
button.Size = UDim2.fromOffset(170, 48)
button.ZIndex = 5

local playing = false
local run = 0

local function fadeTo(value, time)
	local tween = TweenService:Create(black, TweenInfo.new(time or FADE), { BackgroundTransparency = value })
	tween:Play()
	TweenService:Create(title, TweenInfo.new(time or FADE),
		{ TextTransparency = if value < 0.5 then 1 else 0.15, TextStrokeTransparency = if value < 0.5 then 1 else 0.6 }):Play()
	tween.Completed:Wait()
end

local function stop()
	playing = false
	run += 1
	RunService:UnbindFromRenderStep("Cinematic")
	camera.CameraType = Enum.CameraType.Custom
	camera.FieldOfView = FOV
	black.BackgroundTransparency = 1
	title.TextTransparency = 1
	title.TextStrokeTransparency = 1
	button.Text = "CINEMATIC"
end

local function play()
	playing = true
	run += 1
	local mine = run
	button.Text = "STOP"
	local last = nil
	task.spawn(function()
		fadeTo(0, 0.6)
		while playing and run == mine do
			-- A new shot, not the last one.
			local shot, spec
			for _ = 1, 10 do
				shot = pick(SHOTS)
				if shot ~= last then
					spec = shot.make()
					if spec then
						break
					end
				end
			end
			if not spec then
				break
			end
			last = shot
			-- Load the scenery round it while the screen is black.
			pcall(function()
				player:RequestStreamAroundAsync(spec.focus, 3)
			end)
			if not playing or run ~= mine then
				break
			end
			camera.CameraType = Enum.CameraType.Scriptable
			title.Text = shot.name
			local started = os.clock()
			RunService:BindToRenderStep("Cinematic", Enum.RenderPriority.Camera.Value + 1, function()
				local t = math.clamp((os.clock() - started) / (HOLD + FADE * 2), 0, 1)
				local cf, fov = spec.at(t)
				if cf then
					camera.CFrame = cf
					camera.FieldOfView = fov or FOV
				end
			end)
			fadeTo(1)
			task.wait(HOLD)
			if not playing or run ~= mine then
				break
			end
			fadeTo(0)
			RunService:UnbindFromRenderStep("Cinematic")
		end
	end)
end

button.Activated:Connect(function()
	if playing then
		stop()
	else
		play()
	end
end)
