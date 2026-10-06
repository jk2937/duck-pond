--[[
	Trees builder
	The Duck Pond's real trees (tools/make_trees.py): found in USGS lidar,
	named and measured by Virginia Tech's campus tree inventory where it
	covers. Each stands where it is, as tall as it is, its crown as wide, in
	the shape of its kind -- broadleaf, weeping willow, conifer, deciduous
	conifer (bald cypress, dawn redwood), or small ornamental (cherry,
	crabapple, dogwood) -- with its species' bark and leaf colours.

		require(game.ServerStorage.Builders.Trees).build()

	Each tree is a handful of parts, shaped by kind, sized by the data and
	varied by a seed from its position, so a rebuild makes the same trees.
	Leaves don't collide; trunks do.
]]

local ServerStorage = game:GetService("ServerStorage")

local Trees = {}

-- Realistic models, where they exist (see TreeModels).
-- (A fresh copy, like every builder's data: require caches, and the models
-- may have been imported since the last run.)
local TreeModels = require(ServerStorage:WaitForChild("Builders"):WaitForChild("TreeModels"):Clone())

local BARK = Color3.fromRGB(88, 72, 58)
local WILLOW_BARK = Color3.fromRGB(104, 94, 78)
local LEAVES = {
	broadleaf = { Color3.fromRGB(72, 112, 46), Color3.fromRGB(88, 126, 52), Color3.fromRGB(62, 98, 44) },
	willow = { Color3.fromRGB(128, 156, 70), Color3.fromRGB(140, 166, 80) },
	conifer = { Color3.fromRGB(46, 76, 44), Color3.fromRGB(52, 84, 50) },
	cypress = { Color3.fromRGB(104, 142, 74), Color3.fromRGB(116, 150, 80) },
	ornamental = { Color3.fromRGB(84, 122, 56), Color3.fromRGB(96, 130, 60) },
}

-- Species touches, by a word in the inventory's common name: bark, leaves.
local SPECIES = {
	sycamore = { bark = Color3.fromRGB(196, 190, 170) }, -- pale, mottled
	birch = { bark = Color3.fromRGB(184, 150, 128) }, -- river birch: peeling, pinkish
	beech = { bark = Color3.fromRGB(150, 150, 146) },
	ash = { leaves = Color3.fromRGB(80, 118, 50) },
	maple = { leaves = Color3.fromRGB(70, 110, 44) },
	oak = { leaves = Color3.fromRGB(64, 100, 44) },
	walnut = { leaves = Color3.fromRGB(96, 128, 56) },
	locust = { leaves = Color3.fromRGB(104, 134, 58) },
	hemlock = { leaves = Color3.fromRGB(40, 70, 44) },
	pine = { leaves = Color3.fromRGB(52, 84, 48) },
	spruce = { leaves = Color3.fromRGB(44, 72, 56) },
	cherry = { bark = Color3.fromRGB(110, 62, 54), leaves = Color3.fromRGB(90, 118, 54) },
	plum = { leaves = Color3.fromRGB(92, 44, 56) }, -- purple-leaf plums
	dogwood = { leaves = Color3.fromRGB(82, 116, 58) },
}
local current = {} -- this tree's species touches, set per tree in build()

local function leafFor(kind, rng)
	local list = LEAVES[kind] or LEAVES.broadleaf
	return current.leaves or list[rng:NextInteger(1, #list)]
end

local function barkFor(default)
	return current.bark or default
end

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
	local top = trunk(model, base, h * 0.55, math.max(1, h * 0.045), barkFor(BARK), lean)
	local centre = top + Vector3.new(0, h * 0.12, 0)
	local leaves = leafFor("broadleaf", rng)
	leafBall(model, base, h, centre, Vector3.one * r * 1.5, leaves)
	for _ = 1, 5 do
		local a = rng:NextNumber(0, math.pi * 2)
		-- Spread up and down with the tree's height -- but no further than
		-- the crown's width can fill, or a tall, narrow-crowned tree comes
		-- apart into separate balls. (Most trees are well inside this.)
		local spread = math.min(h, r * 4)
		local off = Vector3.new(math.cos(a) * r * 0.55, rng:NextNumber(-0.15, 0.35) * spread, math.sin(a) * r * 0.55)
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
	local leaves = leafFor("willow", rng)
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

	-- The crown: an off-centre dome, and clumps of every size scattered
	-- over it at random -- not in rings, which read as a starfish from above
	-- -- lower toward the edge, so the whole crown droops, and lopsided,
	-- as a real willow is.
	local lopsided = Vector3.new(rng:NextNumber(-0.2, 0.2) * r, 0, rng:NextNumber(-0.2, 0.2) * r)
	ellipsoid(model, Vector3.new(r * rng:NextNumber(1.3, 1.7), h * 0.22, r * rng:NextNumber(1.3, 1.7)),
		CFrame.new(fork.X + lopsided.X, crownTop - h * 0.12, fork.Z + lopsided.Z) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0),
		leaves)
	local clumps = math.clamp(math.floor(r * 0.9), 8, 22)
	for _ = 1, clumps do
		local a = rng:NextNumber(0, math.pi * 2)
		local out = r * math.sqrt(rng:NextNumber(0.1, 0.95))
		local c = Vector3.new(fork.X + lopsided.X + math.cos(a) * out, under(out) + h * rng:NextNumber(0.02, 0.12),
			fork.Z + lopsided.Z + math.sin(a) * out)
		local wide = r * rng:NextNumber(0.45, 1.0)
		local size = Vector3.new(wide, h * rng:NextNumber(0.13, 0.22), wide * rng:NextNumber(0.6, 1))
		ellipsoid(model, size, CFrame.new(c) * CFrame.Angles(math.rad(rng:NextNumber(-10, 10)), rng:NextNumber(0, math.pi * 2), 0),
			leaves:Lerp(pale, rng:NextNumber(0.1, 0.45)))
	end

	-- The curtains: strands falling from inside the crown, spread over it,
	-- longer the further out. Each is a wider upper piece and a narrower,
	-- paler lower one, so they taper; none reach the clearance.
	local floor = base.Y + clearance(h)
	local strands = math.clamp(math.floor(r * r * 0.5), 40, 160)
	for _ = 1, strands do
		local a = rng:NextNumber(0, math.pi * 2)
		local out = r * math.sqrt(rng:NextNumber(0.3, 1.05))
		local x, z = fork.X + lopsided.X + math.cos(a) * out, fork.Z + lopsided.Z + math.sin(a) * out
		local top = under(out) + h * 0.14 -- starts high in the foliage, so the curtain hides the crown's edge
		local length = h * rng:NextNumber(0.12, 0.45) * (0.5 + out / r) -- ragged: some short, some long
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

-- A conifer -- hemlock, pine, spruce: a trunk to just under the top, and a
-- cone of flattened layers narrowing to a point, the lowest clear of the
-- ground. Each layer is nudged a little sideways -- left, right, forward or
-- back -- so the stack isn't perfectly straight; heights and turns stay even.
local function conifer(model, base, h, r, rng)
	local leaves = leafFor("conifer", rng)
	local floor = base.Y + clearance(h)
	local layers = 7
	local topY = 0
	for k = 0, layers - 1 do
		local t = k / layers
		local width = r * 2.1 * (1 - t * 0.88)
		local depth = h * 0.2
		local y = math.max(floor - base.Y + depth / 2, h * (0.18 + 0.78 * t))
		local nudge = Vector3.new(rng:NextNumber(-0.04, 0.04) * width, 0, rng:NextNumber(-0.04, 0.04) * width)
		ellipsoid(model, Vector3.new(width, depth, width), CFrame.new(base + nudge + Vector3.new(0, y, 0)),
			leaves:Lerp(Color3.new(0, 0, 0), rng:NextNumber(0, 0.1)))
		topY = math.max(topY, y + depth / 2)
	end
	-- The trunk stops inside the top layer, never poking out of it.
	trunk(model, base, math.max(2, topY - h * 0.1), math.max(0.9, h * 0.035), barkFor(BARK), CFrame.new())
end

-- A deciduous conifer -- bald cypress, dawn redwood, larch: a straight
-- trunk, a narrow cone of soft, light, feathery green (the tree over the
-- creek in the photos).
local function cypress(model, base, h, r, rng)
	local leaves = leafFor("cypress", rng)
	local floor = base.Y + clearance(h)
	local tiers = 6
	local topY = 0
	for k = 0, tiers - 1 do
		local t = k / tiers
		local y = math.max(floor - base.Y + h * 0.08, h * (0.2 + 0.75 * t))
		local width = r * 1.7 * (1 - t * 0.85)
		local nudge = Vector3.new(rng:NextNumber(-0.04, 0.04) * width, 0, rng:NextNumber(-0.04, 0.04) * width)
		ellipsoid(model, Vector3.new(width, h * 0.2, width), CFrame.new(base + nudge + Vector3.new(0, y, 0)),
			leaves:Lerp(Color3.fromRGB(150, 176, 100), rng:NextNumber(0, 0.2)))
		topY = math.max(topY, y + h * 0.1)
	end
	-- The trunk stops inside the top tier, never poking out of it.
	trunk(model, base, math.max(2, topY - h * 0.1), math.max(1, h * 0.05), Color3.fromRGB(128, 84, 60), CFrame.new())
end

-- A small ornamental -- cherry, crabapple, dogwood, serviceberry: a short
-- trunk and a low, wide, rounded crown.
local function ornamental(model, base, h, r, rng)
	local lean = CFrame.Angles(math.rad(rng:NextNumber(-4, 4)), 0, math.rad(rng:NextNumber(-4, 4)))
	local top = trunk(model, base, h * 0.4, math.max(0.7, h * 0.05), barkFor(BARK), lean)
	local leaves = leafFor("ornamental", rng)
	local crown = Vector3.new(r * 2, math.max(h * 0.55, 3), r * 2)
	local centre = top + Vector3.new(0, crown.Y * 0.35, 0)
	local lowest = base.Y + clearance(h) + crown.Y / 2
	ellipsoid(model, crown, CFrame.new(centre.X, math.max(centre.Y, lowest), centre.Z), leaves)
	for _ = 1, 3 do
		local a = rng:NextNumber(0, math.pi * 2)
		local c = Vector3.new(centre.X + math.cos(a) * r * 0.5, math.max(centre.Y, lowest) + rng:NextNumber(0, crown.Y * 0.25),
			centre.Z + math.sin(a) * r * 0.5)
		ellipsoid(model, crown * rng:NextNumber(0.55, 0.75), CFrame.new(c), leaves:Lerp(Color3.new(0, 0, 0), rng:NextNumber(0, 0.1)))
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

local BUILD = { broadleaf = broadleaf, willow = willow, conifer = conifer, cypress = cypress, ornamental = ornamental }

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
		local x, z, y, h, r, kind, species = string.match(line, "(%S+) (%S+) (%S+) (%S+) (%S+) (%S+) ?(%S*)")
		x, z, y, h, r = tonumber(x), tonumber(z), tonumber(y), tonumber(h), tonumber(r)
		local build = BUILD[kind]
		if build then
			species = if species and species ~= "" and species ~= "-" then species else nil
			current = {}
			if species then
				for word, touch in pairs(SPECIES) do
					if string.find(species, word) then
						current = touch
						break
					end
				end
			end
			-- A realistic model for this very tree, if it has one (and the models
			-- and their textures are in the place): that, not the block tree.
			local entry = TreeModels.lookup(x, z, species)
			if entry then
				TreeModels.place(folder, entry, x, groundY(x, z, y), z)
				counts.model = (counts.model or 0) + 1
				n += 1
				continue
			end
			local model = Instance.new("Model")
			model.Name = if species then string.gsub(species, "_", " ") else kind
			model:SetAttribute("Kind", kind)
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
	local parts = {}
	for kind, count in pairs(counts) do
		table.insert(parts, count .. " " .. kind)
	end
	table.sort(parts)
	return string.format("%d trees: %s", n, table.concat(parts, ", "))
end

return Trees
