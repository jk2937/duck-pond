--[[
	Trees builder
	The Duck Pond's real trees, found in USGS lidar by tools/make_trees.py:
	each where it stands, as tall as it is, its crown as wide, and of the kind
	it looks like -- broadleaf, weeping willow (the banks), or conifer.

		require(game.ServerStorage.Builders.Trees).build()

	Each tree is a handful of parts, shaped by kind, sized by the data and
	varied by a seed from its position, so a rebuild makes the same trees.
	Leaves don't collide; trunks do.
]]

local ServerStorage = game:GetService("ServerStorage")

local Trees = {}

local BARK = Color3.fromRGB(88, 72, 58)
local WILLOW_BARK = Color3.fromRGB(104, 94, 78)
local LEAVES = {
	broadleaf = { Color3.fromRGB(72, 112, 46), Color3.fromRGB(88, 126, 52), Color3.fromRGB(62, 98, 44) },
	willow = { Color3.fromRGB(128, 156, 70), Color3.fromRGB(140, 166, 80) },
	conifer = { Color3.fromRGB(46, 76, 44), Color3.fromRGB(52, 84, 50) },
}

local function part(parent, shape, size, cframe, colour, material, collide)
	local p = Instance.new("Part")
	p.Shape = shape
	p.Size = size
	p.CFrame = cframe
	p.Color = colour
	p.Material = material
	p.Anchored = true
	p.CanCollide = collide or false
	p.CanQuery = collide or false
	p.CanTouch = false
	p.CastShadow = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- A squashed ball: Roblox's Ball parts are always round, so an ellipsoid is
-- a block with a sphere mesh stretched to fill it.
local function ellipsoid(model, size, cframe, colour)
	local p = part(model, Enum.PartType.Block, size, cframe, colour, Enum.Material.Grass)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

local function trunk(model, base, height, width, colour, lean)
	local cf = CFrame.new(base) * lean * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.rad(90))
	part(model, Enum.PartType.Cylinder, Vector3.new(height, width, width), cf, colour, Enum.Material.Wood, true)
	return (CFrame.new(base) * lean * CFrame.new(0, height, 0)).Position
end

local function pick(list, rng)
	return list[rng:NextInteger(1, #list)]
end

-- Leaves never reach the ground: every tree keeps a bit of bare trunk under
-- its crown, at least 0.7 m, and more on a tall tree. `base` is sunk 1.5
-- studs, so this is measured from there.
local SINK = 1.5
local function clearance(h)
	return SINK + math.max(2.5, h * 0.15)
end

-- A ball of leaves, raised if it would hang below the clearance.
local function leafBall(model, base, h, centre, size, colour)
	local lowest = base.Y + clearance(h) + size.Y / 2
	local y = math.max(centre.Y, lowest)
	part(model, Enum.PartType.Ball, size, CFrame.new(centre.X, y, centre.Z), colour, Enum.Material.Grass)
end

-- A broadleaf: a trunk to about half its height, and a crown of overlapping
-- balls, the biggest in the middle.
local function broadleaf(model, base, h, r, rng)
	local lean = CFrame.Angles(math.rad(rng:NextNumber(-3, 3)), 0, math.rad(rng:NextNumber(-3, 3)))
	local top = trunk(model, base, h * 0.55, math.max(1, h * 0.045), BARK, lean)
	local centre = top + Vector3.new(0, h * 0.12, 0)
	local leaves = pick(LEAVES.broadleaf, rng)
	leafBall(model, base, h, centre, Vector3.one * r * 1.5, leaves)
	for _ = 1, 5 do
		local a = rng:NextNumber(0, math.pi * 2)
		local off = Vector3.new(math.cos(a) * r * 0.55, rng:NextNumber(-0.15, 0.35) * h, math.sin(a) * r * 0.55)
		local size = r * rng:NextNumber(0.9, 1.2)
		leafBall(model, base, h, centre + off, Vector3.one * size, leaves:Lerp(Color3.new(0, 0, 0),
			rng:NextNumber(0, 0.12)))
	end
end

-- A limb: a tapering cylinder from a to b.
local function limb(model, a, b, width, colour)
	local length = (b - a).Magnitude
	part(model, Enum.PartType.Cylinder, Vector3.new(length, width, width),
		CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.rad(90), 0), colour, Enum.Material.Wood, true)
end

-- A weeping willow, as they grow by the water in the photos: a short, thick,
-- leaning trunk splitting into a few big limbs that arch up and out; a crown
-- that droops -- high in the middle, lower at the edges, like an umbrella --
-- and long curtains of strands falling out of it, longest at the edges and
-- ragged at the bottom, with a gap under them for the trunk.
local function willow(model, base, h, r, rng)
	local leaves = pick(LEAVES.willow, rng)
	local pale = Color3.fromRGB(184, 200, 104)
	local lean = CFrame.Angles(math.rad(rng:NextNumber(-10, 10)), 0, math.rad(rng:NextNumber(-10, 10)))
	local trunkWidth = math.max(1.4, h * 0.075)
	local fork = trunk(model, base, h * 0.32, trunkWidth, WILLOW_BARK, lean)
	local crownTop = base.Y + h
	-- The crown's underside at a distance out from the middle: a dome.
	local function under(out)
		return crownTop - h * 0.18 - h * 0.28 * (out / r) ^ 2
	end

	-- The limbs.
	local limbs = rng:NextInteger(3, 5)
	local spin = rng:NextNumber(0, math.pi * 2)
	for k = 1, limbs do
		local a = spin + k / limbs * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
		local reach = r * rng:NextNumber(0.35, 0.55)
		local tip = Vector3.new(fork.X + math.cos(a) * reach, under(reach) + h * 0.04, fork.Z + math.sin(a) * reach)
		limb(model, fork, tip, trunkWidth * 0.55, WILLOW_BARK)
	end

	-- The crown: a flattened dome in the middle, and a ring of lower, flatter
	-- mounds round the edge, so the whole crown droops.
	ellipsoid(model, Vector3.new(r * 1.6, h * 0.22, r * 1.6), CFrame.new(fork.X, crownTop - h * 0.12, fork.Z), leaves)
	local ring = math.clamp(math.floor(r / 3), 5, 9)
	for k = 1, ring do
		local a = spin + (k + 0.5) / ring * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		for step, out in ipairs({ r * 0.5, r * 0.82 }) do
			local c = Vector3.new(fork.X + math.cos(a) * out, under(out) + h * 0.08, fork.Z + math.sin(a) * out)
			local wide = r * rng:NextNumber(0.9, 1.1) * (1.1 - step * 0.1)
			local size = Vector3.new(wide, h * 0.2, wide * 0.85)
			ellipsoid(model, size, CFrame.new(c) * CFrame.Angles(0, -a, 0), leaves:Lerp(pale, rng:NextNumber(0.15, 0.45)))
		end
	end

	-- The curtains: strands falling from inside the crown, spread over it,
	-- longer the further out. Each is a wider upper piece and a narrower,
	-- paler lower one, so they taper; none reach the clearance.
	local floor = base.Y + clearance(h)
	local strands = math.clamp(math.floor(r * r * 0.5), 40, 160)
	for _ = 1, strands do
		local a = rng:NextNumber(0, math.pi * 2)
		local out = r * math.sqrt(rng:NextNumber(0.3, 1.05))
		local x, z = fork.X + math.cos(a) * out, fork.Z + math.sin(a) * out
		local top = under(out) + h * 0.14 -- starts high in the foliage, so the curtain hides the crown's edge
		local length = h * rng:NextNumber(0.2, 0.42) * (0.5 + out / r)
		local bottom = math.max(floor, top - length)
		local span = top - bottom
		if span > 1.5 then
			local colour = leaves:Lerp(pale, rng:NextNumber(0.1, 0.5))
			local width = rng:NextNumber(0.8, 1.4)
			local turn = CFrame.Angles(0, -a + rng:NextNumber(-0.4, 0.4), math.rad(rng:NextNumber(-3, 3)))
			local split = top - span * 0.45
			part(model, Enum.PartType.Block, Vector3.new(width, top - split, width * 0.45),
				CFrame.new(x, (top + split) / 2, z) * turn, colour, Enum.Material.Grass)
			part(model, Enum.PartType.Block, Vector3.new(width * 0.65, split - bottom, width * 0.35),
				CFrame.new(x, (split + bottom) / 2, z) * turn, colour:Lerp(pale, 0.3), Enum.Material.Grass)
		end
	end
end

-- A conifer: a trunk the whole way up, in tiers of foliage narrowing to the
-- top, the lowest tier clear of the ground.
local function conifer(model, base, h, r, rng)
	trunk(model, base, h * 0.95, math.max(0.9, h * 0.035), BARK, CFrame.new())
	local leaves = pick(LEAVES.conifer, rng)
	local tiers = 5
	local depth = h * 0.22
	local lift = math.max(0, clearance(h) + depth / 2 - h * 0.25)
	for k = 0, tiers - 1 do
		local t = k / tiers
		local y = h * (0.25 + 0.7 * t) + lift * (1 - t)
		local width = r * 2 * (1 - t * 0.8)
		part(model, Enum.PartType.Cylinder, Vector3.new(depth, width, width),
			CFrame.new(base + Vector3.new(0, y, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi), math.rad(90)), leaves,
			Enum.Material.Grass)
	end
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Include
groundParams.IgnoreWater = true

-- The terrain's surface under a point, or the fallback.
local function groundY(x, z, fallback)
	groundParams.FilterDescendantsInstances = { workspace.Terrain }
	local hit = workspace:Raycast(Vector3.new(x, 400, z), Vector3.new(0, -800, 0), groundParams)
	return if hit then hit.Position.Y else fallback
end

local BUILD = { broadleaf = broadleaf, willow = willow, conifer = conifer }

function Trees.build()
	local data = ServerStorage:WaitForChild("TerrainData"):WaitForChild("Trees").Value
	local root = workspace:FindFirstChild("DuckPond") or Instance.new("Folder")
	root.Name = "DuckPond"
	root.Parent = workspace
	local old = root:FindFirstChild("Trees")
	if old then
		old:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "Trees"
	folder.Parent = root
	local counts = {}
	local n = 0
	for line in string.gmatch(data, "[^\n]+") do
		local x, z, y, h, r, kind = string.match(line, "(%S+) (%S+) (%S+) (%S+) (%S+) (%S+)")
		x, z, y, h, r = tonumber(x), tonumber(z), tonumber(y), tonumber(h), tonumber(r)
		local build = BUILD[kind]
		if build then
			local model = Instance.new("Model")
			model.Name = kind
			-- On the terrain as it's drawn (it lands a little off the data),
			-- sunk a little so the trunk always meets it.
			build(model, Vector3.new(x, groundY(x, z, y) - SINK, z), h, r, Random.new(math.floor(x * 31 + z * 17)))
			model.Parent = folder
			counts[kind] = (counts[kind] or 0) + 1
			n += 1
			if n % 100 == 0 then
				task.wait()
			end
		end
	end
	return string.format("%d trees: %d broadleaf, %d willow, %d conifer", n, counts.broadleaf or 0,
		counts.willow or 0, counts.conifer or 0)
end

return Trees
