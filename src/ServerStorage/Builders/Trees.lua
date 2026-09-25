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

local function trunk(model, base, height, width, colour, lean)
	local cf = CFrame.new(base) * lean * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.rad(90))
	part(model, Enum.PartType.Cylinder, Vector3.new(height, width, width), cf, colour, Enum.Material.Wood, true)
	return (CFrame.new(base) * lean * CFrame.new(0, height, 0)).Position
end

local function pick(list, rng)
	return list[rng:NextInteger(1, #list)]
end

-- A broadleaf: a trunk to about half its height, and a crown of overlapping
-- balls, the biggest in the middle.
local function broadleaf(model, base, h, r, rng)
	local lean = CFrame.Angles(math.rad(rng:NextNumber(-3, 3)), 0, math.rad(rng:NextNumber(-3, 3)))
	local top = trunk(model, base, h * 0.55, math.max(1, h * 0.045), BARK, lean)
	local centre = top + Vector3.new(0, h * 0.12, 0)
	local leaves = pick(LEAVES.broadleaf, rng)
	part(model, Enum.PartType.Ball, Vector3.one * r * 1.5, CFrame.new(centre), leaves, Enum.Material.Grass)
	for _ = 1, 5 do
		local a = rng:NextNumber(0, math.pi * 2)
		local off = Vector3.new(math.cos(a) * r * 0.55, rng:NextNumber(-0.15, 0.35) * h, math.sin(a) * r * 0.55)
		local size = r * rng:NextNumber(0.9, 1.2)
		part(model, Enum.PartType.Ball, Vector3.one * size, CFrame.new(centre + off), leaves:Lerp(Color3.new(0, 0, 0),
			rng:NextNumber(0, 0.12)), Enum.Material.Grass)
	end
end

-- A weeping willow: a short leaning trunk, a rounded crown, and curtains of
-- fronds hanging nearly to the ground (the photos: they trail in the water).
local function willow(model, base, h, r, rng)
	local lean = CFrame.Angles(math.rad(rng:NextNumber(-8, 8)), 0, math.rad(rng:NextNumber(-8, 8)))
	local top = trunk(model, base, h * 0.5, math.max(1.2, h * 0.06), WILLOW_BARK, lean)
	local leaves = pick(LEAVES.willow, rng)
	local crown = top + Vector3.new(0, h * 0.15, 0)
	part(model, Enum.PartType.Ball, Vector3.new(r * 2, h * 0.45, r * 2), CFrame.new(crown), leaves, Enum.Material.Grass)
	-- Two rings of thin strands, staggered in length, so it reads as a
	-- weeping curtain rather than a wall.
	for ring, reach in ipairs({ 0.95, 0.7 }) do
		local strands = math.clamp(math.floor(r * reach * math.pi * 2 / 1.8), 8, 48)
		for k = 1, strands do
			local a = (k + ring * 0.5) / strands * math.pi * 2 + rng:NextNumber(-0.08, 0.08)
			local out = r * reach * rng:NextNumber(0.9, 1.05)
			local hang = h * rng:NextNumber(0.35, 0.72)
			local topY = crown.Y + h * 0.04
			local p = Vector3.new(crown.X + math.cos(a) * out, topY - hang / 2, crown.Z + math.sin(a) * out)
			local width = rng:NextNumber(0.9, 1.6)
			part(model, Enum.PartType.Block, Vector3.new(width, hang, width * 0.6),
				CFrame.new(p) * CFrame.Angles(0, -a, 0) * CFrame.Angles(0, 0, math.rad(rng:NextNumber(-4, 4))),
				leaves:Lerp(Color3.fromRGB(176, 196, 96), rng:NextNumber(0, 0.3)), Enum.Material.Grass)
		end
	end
end

-- A conifer: a trunk the whole way up, in tiers of foliage narrowing to the top.
local function conifer(model, base, h, r, rng)
	trunk(model, base, h * 0.95, math.max(0.9, h * 0.035), BARK, CFrame.new())
	local leaves = pick(LEAVES.conifer, rng)
	local tiers = 5
	for k = 0, tiers - 1 do
		local t = k / tiers
		local y = h * (0.25 + 0.7 * t)
		local width = r * 2 * (1 - t * 0.8)
		local depth = h * 0.22
		part(model, Enum.PartType.Cylinder, Vector3.new(depth, width, width),
			CFrame.new(base + Vector3.new(0, y, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi), math.rad(90)), leaves,
			Enum.Material.Grass)
	end
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
			-- Sunk a little, so the trunk meets the ground wherever the
			-- terrain's surface lands.
			build(model, Vector3.new(x, y - 1.5, z), h, r, Random.new(math.floor(x * 31 + z * 17)))
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
