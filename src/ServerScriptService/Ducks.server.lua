--[[
	Ducks
	The Duck Pond's birds, as the photos show them: mallards (drakes and
	hens), Muscovy ducks (white and black, red faces) and Chinese geese
	(white or brown, orange bills with a knob).

	They paddle about the ponds, now and then tip up to feed, and swim over
	to anyone standing at the water's edge, hoping for bread. Some geese
	graze the banks instead, waddling. Where the water is comes from
	TerrainData.Water (tools/make_terrain.py), the same grid the terrain was
	built from.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local data = ServerStorage:WaitForChild("TerrainData")
local meta = require(data:WaitForChild("Meta"))
local waterData = data:WaitForChild("Water").Value

local POPULATION = {
	{ species = "mallardDrake", count = 14 },
	{ species = "mallardHen", count = 12 },
	{ species = "muscovy", count = 6 },
	{ species = "goose", count = 8 },
}
local SOUNDS = {
	duck = "rbxassetid://9068554227", -- "Quack Effect - Duck Sound", Creator Store
	goose = "rbxassetid://4139639790", -- "goose_honk_b_01", Creator Store
}
local SWIM_SPEED = 3.2 -- studs/s
local WALK_SPEED = 2.2
local TURN = 2.2 -- radians/s
local CURIOUS = 45 -- studs: a player this close at the water gets visitors

-- Flocking, after Duck Duck Drift's (itself after the old xfishtank
-- screensaver): each bird on the water steers by its neighbours within
-- NEIGHBOR_RADIUS only -- keep apart (strong, or they jam into a pile),
-- match their heading, drift toward their middle -- plus its own pull
-- toward wherever it's going and a slow wander. Only neighbours, so the
-- birds form loose, shifting little rafts rather than one blob. Same
-- species hang together more than mixed ones.
local BOID = {
	NEIGHBOR_RADIUS = 18,
	SEPARATION_RADIUS = 3.5,
	SEPARATION_K = 25,
	ALIGN_K = 0.8,
	COHESION_K = 0.12,
	OTHER_SPECIES = 0.3, -- how much a different species counts, for align and cohesion
	SEEK_K = 1.2, -- the pull toward its goal
	WANDER_K = 0.8,
	MAX_ACCEL = 8, -- studs/s^2
}
local rng = Random.new()
local FEED = { CRUMBS = 5, RANGE = 160, LIFETIME = 45, COOLDOWN = 1.2, RUSH = 1.8 }

-- Water ------------------------------------------------------------------------

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local value = {}
for i = 1, #B64 do
	value[string.byte(B64, i)] = i - 1
end

-- The water surface at a point (studs), or nil on land.
local function waterAt(x, z)
	local i = math.floor((x - meta.x0) / meta.cell)
	local j = math.floor((z - meta.z0) / meta.cell)
	if i < 0 or j < 0 or i >= meta.nx or j >= meta.nz then
		return nil
	end
	local index = j * meta.nx + i + 1
	local a, b = string.byte(waterData, index * 2 - 1, index * 2)
	local q = value[a] * 64 + value[b]
	return if q == 0 then nil else (q - 1) / 4
end

-- Open water: water here and all round, so a duck isn't hard up on a bank.
local function openWater(x, z, margin)
	local level = waterAt(x, z)
	if not level then
		return nil
	end
	for _, d in ipairs({ { margin, 0 }, { -margin, 0 }, { 0, margin }, { 0, -margin } }) do
		local l = waterAt(x + d[1], z + d[2])
		if not l or math.abs(l - level) > 0.5 then
			return nil
		end
	end
	return level
end

-- Every open-water cell, to spawn and pick destinations from.
local pondCells = {}
for j = 0, meta.nz - 1, 2 do
	for i = 0, meta.nx - 1, 2 do
		local x, z = meta.x0 + (i + 0.5) * meta.cell, meta.z0 + (j + 0.5) * meta.cell
		local level = openWater(x, z, 6)
		if level then
			table.insert(pondCells, Vector3.new(x, level, z))
		end
	end
end

-- A straight swim from a to b stays on the same water.
local function clearSwim(a, b, level)
	for k = 1, 10 do
		local p = a:Lerp(b, k / 10)
		local l = waterAt(p.X, p.Z)
		if not l or math.abs(l - level) > 0.5 then
			return false
		end
	end
	return true
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Include
groundParams.IgnoreWater = true
local function groundY(x, z)
	groundParams.FilterDescendantsInstances = { workspace.Terrain }
	local hit = workspace:Raycast(Vector3.new(x, 400, z), Vector3.new(0, -800, 0), groundParams)
	return if hit then hit.Position.Y else nil
end

-- Models -----------------------------------------------------------------------

local function piece(model, root, size, offset, colour, shape)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = true
	p.Size = size
	p.Color = colour
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape == "ball" then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	elseif shape == "wedge" then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Wedge
		mesh.Parent = p
	end
	p.CFrame = root.CFrame * offset
	p.Parent = model
	-- Welded to the root, so moving the root moves the bird.
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = p
	weld.Parent = p
	return p
end

-- A bird faces -Z; its root sits at the waterline.
local SPECIES = {
	mallardDrake = {
		call = "duck", scale = 1,
		body = Color3.fromRGB(176, 174, 166), chest = Color3.fromRGB(110, 66, 44), head = Color3.fromRGB(28, 92, 56),
		bill = Color3.fromRGB(214, 190, 70), tail = Color3.fromRGB(30, 30, 32), ring = true,
	},
	mallardHen = {
		call = "duck", scale = 0.95,
		body = Color3.fromRGB(142, 108, 74), chest = Color3.fromRGB(150, 116, 80), head = Color3.fromRGB(126, 98, 70),
		bill = Color3.fromRGB(206, 120, 50), tail = Color3.fromRGB(120, 92, 64),
	},
	muscovy = {
		call = "duck", scale = 1.25,
		body = Color3.fromRGB(240, 240, 236), chest = Color3.fromRGB(240, 240, 236), head = Color3.fromRGB(236, 236, 232),
		bill = Color3.fromRGB(226, 160, 160), tail = Color3.fromRGB(30, 30, 32), patch = Color3.fromRGB(26, 28, 30),
		face = Color3.fromRGB(200, 40, 40),
	},
	goose = {
		call = "goose", scale = 1.5, neck = true, knob = true,
		body = Color3.fromRGB(242, 242, 238), chest = Color3.fromRGB(242, 242, 238), head = Color3.fromRGB(242, 242, 238),
		bill = Color3.fromRGB(236, 132, 40), tail = Color3.fromRGB(230, 230, 226),
	},
}

local folder = Instance.new("Folder")
folder.Name = "Ducks"
folder.Parent = workspace:FindFirstChild("DuckPond") or workspace

local function makeBird(kind, at)
	local s = SPECIES[kind]
	local k = s.scale
	local model = Instance.new("Model")
	model.Name = kind
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.Transparency = 1
	root.Size = Vector3.new(0.2, 0.2, 0.2)
	root.CFrame = at
	root.Parent = model
	model.PrimaryPart = root

	-- A brown Chinese goose now and then, as in the photo.
	local body = s.body
	if kind == "goose" and rng:NextNumber() < 0.35 then
		body = Color3.fromRGB(150, 128, 104)
	end
	piece(model, root, Vector3.new(1.1, 0.8, 2.2) * k, CFrame.new(0, 0.15 * k, 0), body, "ball")
	piece(model, root, Vector3.new(1.0, 0.75, 0.9) * k, CFrame.new(0, 0.25 * k, -0.7 * k), s.chest, "ball")
	piece(model, root, Vector3.new(0.5, 0.35, 0.6) * k, CFrame.new(0, 0.45 * k, 1.05 * k) * CFrame.Angles(math.rad(25), 0, 0),
		s.tail, "ball")
	if s.patch then
		piece(model, root, Vector3.new(1.0, 0.5, 1.2) * k, CFrame.new(0, 0.45 * k, 0.2 * k), s.patch, "ball")
	end
	local headAt
	if s.neck then
		-- A goose's long neck, up and a little forward.
		piece(model, root, Vector3.new(0.4, 1.6, 0.45) * k, CFrame.new(0, 1.05 * k, -1.0 * k) * CFrame.Angles(math.rad(-12), 0, 0),
			body, "ball")
		headAt = CFrame.new(0, 1.85 * k, -1.2 * k)
	else
		headAt = CFrame.new(0, 0.95 * k, -0.95 * k)
	end
	piece(model, root, Vector3.new(0.55, 0.6, 0.7) * k, headAt, if kind == "goose" then body else s.head, "ball")
	piece(model, root, Vector3.new(0.3, 0.15, 0.5) * k, headAt * CFrame.new(0, -0.08 * k, -0.5 * k), s.bill)
	if s.knob then
		piece(model, root, Vector3.new(0.26, 0.26, 0.26) * k, headAt * CFrame.new(0, 0.1 * k, -0.3 * k), s.bill, "ball")
	end
	if s.ring then
		piece(model, root, Vector3.new(0.5, 0.08, 0.5) * k, headAt * CFrame.new(0, -0.35 * k, 0.1 * k), Color3.new(1, 1, 1), "ball")
	end
	if s.face then
		for _, x in ipairs({ -0.22, 0.22 }) do
			piece(model, root, Vector3.new(0.12, 0.3, 0.35) * k, headAt * CFrame.new(x * k, 0.02, -0.15 * k), s.face)
		end
	end
	for _, x in ipairs({ -0.2, 0.2 }) do
		piece(model, root, Vector3.new(0.09, 0.09, 0.09) * k, headAt * CFrame.new(x * k, 0.1 * k, -0.2 * k),
			Color3.new(0, 0, 0), "ball")
		-- Orange legs: under water they don't show; on land they do.
		piece(model, root, Vector3.new(0.12, 0.6, 0.12) * k, CFrame.new(x * k, -0.35 * k, 0.1 * k),
			Color3.fromRGB(230, 130, 40))
	end

	local sound = Instance.new("Sound")
	sound.SoundId = SOUNDS[s.call]
	sound.Volume = 0.5
	sound.RollOffMaxDistance = 120
	sound.RollOffMinDistance = 8
	sound.Parent = root

	model.Parent = folder
	return model
end

-- Behaviour ---------------------------------------------------------------------

local birds = {}

-- A raft of birds shares one destination (bird.flock.target), so they
-- travel together; the boid rules keep them spaced and moving as one.
local function newTarget(bird)
	local here = if bird.flock then bird.flock.centre or bird.position else bird.position
	for _ = 1, 20 do
		local c = pondCells[rng:NextInteger(1, #pondCells)]
		if (c - here).Magnitude < 70 and math.abs(c.Y - bird.level) < 0.5
			and clearSwim(here, Vector3.new(c.X, here.Y, c.Z), bird.level) then
			return Vector3.new(c.X, here.Y, c.Z)
		end
	end
	return here
end

local FLOCK_SIZE = { 3, 7 }
for _, group in ipairs(POPULATION) do
	local flock, left = nil, 0
	for _ = 1, group.count do
		-- Start a new raft every few birds, the rest spawning near its first.
		if left <= 0 then
			local home = pondCells[rng:NextInteger(1, #pondCells)]
			flock = { home = home, centre = home }
			left = rng:NextInteger(FLOCK_SIZE[1], FLOCK_SIZE[2])
		end
		left -= 1
		local c = flock.home
		for _ = 1, 20 do
			local near = flock.home + Vector3.new(rng:NextNumber(-10, 10), 0, rng:NextNumber(-10, 10))
			local level = waterAt(near.X, near.Z)
			if level and math.abs(level - flock.home.Y) < 0.5 then
				c = Vector3.new(near.X, level, near.Z)
				break
			end
		end
		local heading = rng:NextNumber(0, math.pi * 2)
		local bird = {
			kind = group.species,
			level = c.Y,
			position = Vector3.new(c.X, c.Y, c.Z),
			heading = heading,
			mode = "swim",
			vel = Vector3.zero,
			flock = flock,
			until_ = 0,
			nextCall = os.clock() + rng:NextNumber(5, 60),
			phase = rng:NextNumber(0, 10),
		}
		-- About half the geese graze the banks.
		if group.species == "goose" and rng:NextNumber() < 0.5 then
			bird.mode = "graze"
		end
		bird.model = makeBird(group.species, CFrame.new(bird.position))
		if not flock.target then
			flock.target = newTarget(bird)
		end
		table.insert(birds, bird)
	end
end

-- Bread ------------------------------------------------------------------------
-- A player tosses bread (F, or the button; see Feed.client.lua); crumbs land
-- on the water a little ahead of them and every bird in range races for one.

local crumbs = {} -- { part, level, born }
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local toss = Instance.new("RemoteEvent")
toss.Name = "TossBread"
toss.Parent = ReplicatedStorage
local lastToss = {}

toss.OnServerEvent:Connect(function(player)
	local now = os.clock()
	if now - (lastToss[player] or 0) < FEED.COOLDOWN then
		return
	end
	lastToss[player] = now
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local ahead = (root.CFrame.LookVector * Vector3.new(1, 0, 1)).Unit
	-- Aim for the water: the first open water ahead, within a good throw.
	local reach = 10
	for d = 6, 30, 2 do
		local p = root.Position + ahead * d
		if waterAt(p.X, p.Z) and waterAt(p.X + ahead.X * 2, p.Z + ahead.Z * 2) then
			reach = d + 3
			break
		end
	end
	for _ = 1, FEED.CRUMBS do
		local landing = root.Position + ahead * (reach + rng:NextNumber(-1.5, 2.5))
			+ Vector3.new(rng:NextNumber(-2, 2), 0, rng:NextNumber(-2, 2))
		local level = waterAt(landing.X, landing.Z)
		local y = level or groundY(landing.X, landing.Z) or root.Position.Y
		local p = Instance.new("Part")
		p.Name = "Crumb"
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.Size = Vector3.new(0.35, 0.18, 0.3)
		p.Color = Color3.fromRGB(214, 180, 124)
		p.Material = Enum.Material.SmoothPlastic
		p.CFrame = CFrame.new(landing.X, y + 0.05, landing.Z) * CFrame.Angles(0, rng:NextNumber(0, 6), 0)
		p.Parent = folder
		table.insert(crumbs, { part = p, level = level, born = now })
	end
end)

-- The nearest crumb on this bird's water, if there is one in range.
local function nearestCrumb(bird)
	local best, bestD = nil, FEED.RANGE
	for _, c in ipairs(crumbs) do
		if c.level and math.abs(c.level - bird.level) < 0.5 then
			local d = (Vector3.new(c.part.Position.X, bird.position.Y, c.part.Position.Z) - bird.position).Magnitude
			if d < bestD then
				best, bestD = c, d
			end
		end
	end
	return best
end

-- The nearest player standing at the water, near enough to be interesting.
local function curiousAbout(bird)
	local best, bestD = nil, CURIOUS
	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root then
			local d = (Vector3.new(root.Position.X, bird.position.Y, root.Position.Z) - bird.position).Magnitude
			if d < bestD then
				best, bestD = root.Position, d
			end
		end
	end
	return best
end

-- A spot on the bank near the water, for a grazing goose.
local function bankSpot(near)
	for _ = 1, 30 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(6, 18)
		local x, z = near.X + math.cos(a) * r, near.Z + math.sin(a) * r
		if not waterAt(x, z) then
			local y = groundY(x, z)
			if y and math.abs(y - near.Y) < 6 then
				return Vector3.new(x, y, z)
			end
		end
	end
	return nil
end

local function turnToward(bird, goal, dt)
	local d = goal - bird.position
	if Vector3.new(d.X, 0, d.Z).Magnitude < 0.5 then
		return false
	end
	local want = math.atan2(-d.X, -d.Z)
	local diff = (want - bird.heading + math.pi) % (math.pi * 2) - math.pi
	bird.heading += math.clamp(diff, -TURN * dt, TURN * dt)
	return math.abs(diff) < 0.6
end

local t = 0
RunService.Heartbeat:Connect(function(dt)
	t += dt
	local now = os.clock()
	-- Each raft's middle, for its arrival check.
	local sums = {}
	for _, bird in ipairs(birds) do
		local f = bird.flock
		sums[f] = sums[f] or { Vector3.zero, 0 }
		sums[f][1] += bird.position
		sums[f][2] += 1
	end
	for f, sum in pairs(sums) do
		f.centre = sum[1] / sum[2]
	end
	-- Old crumbs sink.
	for i = #crumbs, 1, -1 do
		if now - crumbs[i].born > FEED.LIFETIME then
			crumbs[i].part:Destroy()
			table.remove(crumbs, i)
		end
	end
	for _, bird in ipairs(birds) do
		local pose = CFrame.new()
		if bird.mode == "graze" then
			-- On the bank: walk to a spot, peck a while, walk on.
			if not bird.spot then
				bird.spot = bankSpot(Vector3.new(bird.position.X, bird.level, bird.position.Z))
				if not bird.spot then
					bird.mode = "swim"
				end
			end
			if bird.spot then
				if turnToward(bird, bird.spot, dt) then
					local d = bird.spot - bird.position
					local flat = Vector3.new(d.X, 0, d.Z)
					if flat.Magnitude > 0.6 then
						local step = flat.Unit * math.min(WALK_SPEED * dt, flat.Magnitude)
						local y = groundY(bird.position.X + step.X, bird.position.Z + step.Z) or bird.position.Y
						if waterAt(bird.position.X + step.X, bird.position.Z + step.Z) then
							bird.spot = nil
						else
							bird.position = Vector3.new(bird.position.X + step.X, y + 0.6 * SPECIES[bird.kind].scale,
								bird.position.Z + step.Z)
						end
						pose = CFrame.Angles(0, 0, math.sin(t * 9 + bird.phase) * 0.12) -- the waddle
					elseif now > bird.until_ then
						if bird.until_ > 0 then
							bird.spot = nil
							bird.until_ = 0
						else
							bird.until_ = now + rng:NextNumber(4, 12)
						end
					else
						pose = CFrame.Angles(math.rad(-35 + math.sin(t * 3 + bird.phase) * 15), 0, 0) -- pecking
					end
				end
			end
		else
			-- On the water: bread first, then a person at the edge, then
			-- wherever it was going.
			local crumb = nearestCrumb(bird)
			local person = if crumb then nil else curiousAbout(bird)
			local goal = bird.flock.target
			local speed = SWIM_SPEED
			if crumb then
				goal = Vector3.new(crumb.part.Position.X, bird.position.Y, crumb.part.Position.Z)
				speed = SWIM_SPEED * FEED.RUSH
				if bird.mode == "tip" then
					bird.mode = "swim"
				end
				if (goal - bird.position).Magnitude < 1.4 then
					crumb.part:Destroy()
					table.remove(crumbs, table.find(crumbs, crumb))
				end
			end
			if person then
				local toBird = bird.position - Vector3.new(person.X, bird.position.Y, person.Z)
				local stop = Vector3.new(person.X, bird.position.Y, person.Z) + toBird.Unit * 5
				local level = waterAt(stop.X, stop.Z)
				if level and math.abs(level - bird.level) < 0.5 then
					goal = stop
				end
			end
			local d = goal - bird.position
			-- The raft has arrived when its middle reaches the spot: a new one
			-- for all of them, and now and then a bird tips up to feed.
			local fd = bird.flock.target - bird.flock.centre
			if not person and not crumb and Vector3.new(fd.X, 0, fd.Z).Magnitude < 8 then
				bird.flock.target = newTarget(bird)
			end
			if Vector3.new(d.X, 0, d.Z).Magnitude < 10 and bird.mode == "swim" and not crumb
				and rng:NextNumber() < 0.15 * dt then
				bird.mode = "tip"
				bird.until_ = now + rng:NextNumber(2, 4)
			end
			if bird.mode == "swim" then
				-- The boid rules: seek the goal, keep apart, align, cohere,
				-- wander -- summed, capped, and applied to the velocity.
				local flatD = Vector3.new(d.X, 0, d.Z)
				local want = if flatD.Magnitude > 0.5 then flatD.Unit * speed else Vector3.zero
				local accel = (want - bird.vel) * BOID.SEEK_K
				local sep, avgVel, avgPos, weight = Vector3.zero, Vector3.zero, Vector3.zero, 0
				for _, other in ipairs(birds) do
					if other ~= bird and other.mode ~= "graze" and math.abs(other.level - bird.level) < 0.5 then
						local off = bird.position - other.position
						local dist = Vector3.new(off.X, 0, off.Z).Magnitude
						if dist < BOID.NEIGHBOR_RADIUS then
							if dist < BOID.SEPARATION_RADIUS and dist > 0.01 then
								sep += Vector3.new(off.X, 0, off.Z).Unit * (BOID.SEPARATION_RADIUS - dist) / BOID.SEPARATION_RADIUS
							end
							local w = if other.kind == bird.kind then 1 else BOID.OTHER_SPECIES
							avgVel += other.vel * w
							avgPos += other.position * w
							weight += w
						end
					end
				end
				accel += sep * BOID.SEPARATION_K
				if weight > 0 and not crumb then
					avgVel /= weight
					avgPos /= weight
					accel += (avgVel - bird.vel) * BOID.ALIGN_K
					accel += Vector3.new(avgPos.X - bird.position.X, 0, avgPos.Z - bird.position.Z) * BOID.COHESION_K
				end
				local w = math.noise(bird.phase, t * 0.15) * math.pi * 2
				accel += Vector3.new(math.cos(w), 0, math.sin(w)) * BOID.WANDER_K
				if accel.Magnitude > BOID.MAX_ACCEL then
					accel = accel.Unit * BOID.MAX_ACCEL
				end
				bird.vel += accel * dt
				if bird.vel.Magnitude > speed then
					bird.vel = bird.vel.Unit * speed
				end
				local next = bird.position + bird.vel * dt
				local level = waterAt(next.X, next.Z)
				if level and math.abs(level - bird.level) < 0.5 then
					bird.position = next
				else
					-- The bank: turn back.
					bird.vel = -bird.vel * 0.3
				end
				-- Face where it's swimming.
				if bird.vel.Magnitude > 0.3 then
					local wantHeading = math.atan2(-bird.vel.X, -bird.vel.Z)
					local diff = (wantHeading - bird.heading + math.pi) % (math.pi * 2) - math.pi
					bird.heading += math.clamp(diff, -TURN * dt, TURN * dt)
				end
			else
				bird.vel *= math.max(0, 1 - 3 * dt)
			end
			if bird.mode == "tip" then
				-- Bottoms up: feeding off the bottom.
				pose = CFrame.new(0, -0.3, 0) * CFrame.Angles(math.rad(-75), 0, 0)
				if now > bird.until_ then
					bird.mode = "swim"
				end
			end
			local bob = math.sin(t * 1.7 + bird.phase) * 0.06
			bird.position = Vector3.new(bird.position.X, bird.level + bob, bird.position.Z)
		end
		bird.model:PivotTo(CFrame.new(bird.position) * CFrame.Angles(0, bird.heading, 0) * pose)

		if now > bird.nextCall then
			bird.nextCall = now + rng:NextNumber(15, 70)
			local sound = bird.model.Root:FindFirstChildOfClass("Sound")
			if sound then
				sound.PlaybackSpeed = rng:NextNumber(0.9, 1.1)
				sound:Play()
			end
		end
	end
end)
