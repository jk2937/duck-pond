--[[
	Paths builder
	The bridges and steps, from TerrainData.Features (tools/make_terrain.py,
	out of OpenStreetMap). The paths themselves are terrain, painted by the
	Terrain builder; these are the parts that aren't ground.

		require(game.ServerStorage.Builders.Paths).build()

	What they look like, from reference photos (data/photos, Wikimedia
	Commons) where there are any, and guesses where not:
	  footbridges   rustic: a dark timber deck, log posts and rails, braces
	                (the winter bridge photo)
	  weir          a stepped concrete cascade, the water in tiers (the dam
	                photo)
	  road bridges  Duck Pond Drive: an asphalt deck between Hokie Stone
	                parapets -- a guess
	  steps         concrete, or timber-edged grass where OSM says grass
]]

local ServerStorage = game:GetService("ServerStorage")

local Paths = {}

local HOKIE_STONE = Color3.fromRGB(150, 142, 130)
local CONCRETE = Color3.fromRGB(176, 172, 164)
local ASPHALT = Color3.fromRGB(62, 62, 66)
local RAIL = Color3.fromRGB(38, 40, 44)
local TIMBER = Color3.fromRGB(110, 84, 58)
local GRASS = Color3.fromRGB(96, 140, 64)
local OLD_TIMBER = Color3.fromRGB(66, 56, 44) -- weathered, nearly black when wet

local function part(parent, name, size, cframe, colour, material, props)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = colour
	p.Material = material or Enum.Material.Concrete
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props or {}) do
		p[k] = v
	end
	p.Parent = parent
	return p
end

-- A way's points as a path: total length, and the point and height at any
-- distance along it, the height running straight from one end to the other.
local function along(points, fromHeight, toHeight)
	local legs, total = {}, 0
	for i = 1, #points - 1 do
		local a = Vector3.new(points[i][1], 0, points[i][2])
		local b = Vector3.new(points[i + 1][1], 0, points[i + 1][2])
		table.insert(legs, { a = a, b = b, from = total, length = (b - a).Magnitude })
		total += (b - a).Magnitude
	end
	return total, function(distance)
		local leg = legs[#legs]
		for _, l in ipairs(legs) do
			if distance <= l.from + l.length then
				leg = l
				break
			end
		end
		local t = math.clamp((distance - leg.from) / math.max(leg.length, 0.01), 0, 1)
		local flat = leg.a:Lerp(leg.b, t)
		local y = fromHeight + (toHeight - fromHeight) * math.clamp(distance / math.max(total, 0.01), 0, 1)
		return Vector3.new(flat.X, y, flat.Z), (leg.b - leg.a).Unit
	end
end

-- A slab from p to q (world points on its top surface's centre line).
local function slab(parent, name, p, q, width, thickness, colour, material)
	local length = (q - p).Magnitude
	local cf = CFrame.lookAt((p + q) / 2, q) * CFrame.new(0, -thickness / 2, 0)
	return part(parent, name, Vector3.new(width, thickness, length), cf, colour, material)
end

-- The terrain's real surface under a point (the rendered surface sits a
-- little off the planned heights), water ignored.
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Include
groundParams.IgnoreWater = true

local function groundY(p)
	groundParams.FilterDescendantsInstances = { workspace.Terrain }
	local hit = workspace:Raycast(Vector3.new(p.X, 400, p.Z), Vector3.new(0, -800, 0), groundParams)
	return if hit then hit.Position.Y else -math.huge
end

local function bridge(parent, spec)
	local model = Instance.new("Model")
	model.Name = if spec.name ~= "" then spec.name .. " Bridge" else "Footbridge"
	model.Parent = parent
	local road = spec.kind == "road"
	-- A little past each end, so the deck meets the ground.
	-- Its ends sit on the ground as it really is (a little past each end,
	-- where the path meets it), and the deck runs straight between them.
	local over = 3
	local first, last = spec.points[1], spec.points[#spec.points]
	local total0, at0 = along(spec.points, 0, 0)
	local _, dirA = at0(0)
	local _, dirB = at0(total0)
	local endA = Vector3.new(first[1], 0, first[2]) - dirA * over
	local endB = Vector3.new(last[1], 0, last[2]) + dirB * over
	local total, at = along(spec.points, math.max(spec.ends[1], groundY(endA) + 0.2),
		math.max(spec.ends[2], groundY(endB) + 0.2))
	local steps = math.max(2, math.ceil((total + over * 2) / 6))
	local deckColour = if road then ASPHALT else OLD_TIMBER
	local deckMaterial = if road then Enum.Material.Asphalt else Enum.Material.WoodPlanks
	local previous = nil
	for i = 0, steps do
		local d = -over + (total + over * 2) * i / steps
		local p, dir = at(math.clamp(d, 0, total))
		p += dir * (d - math.clamp(d, 0, total))
		-- Never below the ground: a deck meets the path, not a step up.
		p = Vector3.new(p.X, math.max(p.Y, groundY(p) + 0.2), p.Z)
		-- A footbridge arches a little in the middle.
		if not road then
			p += Vector3.new(0, math.sin(math.clamp(d / total, 0, 1) * math.pi) * 1.5, 0)
		end
		if previous then
			slab(model, "Deck", previous.p, p, spec.width, if road then 2.5 else 1.2, deckColour, deckMaterial)
			local side = previous.dir:Cross(Vector3.yAxis).Unit
			for _, s in ipairs({ -1, 1 }) do
				local off = side * s * (spec.width / 2 + (if road then 0.8 else 0.2))
				if road then
					-- Hokie Stone parapets, waist high: top 3.2 studs over the deck.
					local lift = Vector3.new(0, 3.2, 0)
					slab(model, "Parapet", previous.p + off + lift, p + off + lift, 1.6, 4.8, HOKIE_STONE,
						Enum.Material.Slate)
				else
					-- A log post, a log top rail and a lower rail to the next
					-- one, and a brace from the post's foot outward.
					local foot = previous.p + off
					part(model, "Post", Vector3.new(0.9, 3.6, 0.9), CFrame.new(foot + Vector3.new(0, 1.8, 0)),
						OLD_TIMBER, Enum.Material.Wood)
					slab(model, "Rail", foot + Vector3.new(0, 3.7, 0), p + off + Vector3.new(0, 3.7, 0), 0.8, 0.7,
						OLD_TIMBER, Enum.Material.Wood)
					slab(model, "LowRail", foot + Vector3.new(0, 1.9, 0), p + off + Vector3.new(0, 1.9, 0), 0.6, 0.5,
						OLD_TIMBER, Enum.Material.Wood)
					local out = side * s * 1.6
					slab(model, "Brace", foot + Vector3.new(0, 2.6, 0), foot + out + Vector3.new(0, -0.6, 0), 0.5, 0.5,
						OLD_TIMBER, Enum.Material.Wood)
				end
			end
		end
		previous = { p = p, dir = dir }
	end
	return model
end

local function stairs(parent, spec)
	local model = Instance.new("Model")
	model.Name = "Steps"
	model.Parent = parent
	local low, high = math.min(spec.ends[1], spec.ends[2]), math.max(spec.ends[1], spec.ends[2])
	local rise = high - low
	-- As many steps as OSM counts, or ~17 cm (0.6 studs) each.
	local count = if spec.count > 0 then spec.count else math.max(2, math.round(rise / 0.6))
	local points = spec.points
	if spec.ends[1] > spec.ends[2] then
		-- Always climb from the first point.
		local reversed = {}
		for i = #points, 1, -1 do
			table.insert(reversed, points[i])
		end
		points = reversed
	end
	local total, at = along(points, low, high)
	local grass = spec.surface == "grass"
	local width = if grass then 5 else 6.5
	for i = 1, count do
		local d0, d1 = total * (i - 1) / count, total * i / count
		local p0, dir = at(d0)
		local p1 = at(d1)
		local top = low + rise * i / count
		local mid = (p0 + p1) / 2
		local depth = math.max((p1 - p0).Magnitude, 0.8)
		local height = top - low + 2
		local cf = CFrame.lookAt(Vector3.new(mid.X, top - height / 2, mid.Z),
			Vector3.new(mid.X, top - height / 2, mid.Z) + dir)
		if grass then
			part(model, "Tread", Vector3.new(width, height, depth), cf, GRASS, Enum.Material.Grass)
			part(model, "Riser", Vector3.new(width, 0.5, 0.4), cf * CFrame.new(0, height / 2 - 0.2, -depth / 2),
				TIMBER, Enum.Material.Wood)
		else
			part(model, "Tread", Vector3.new(width, height, depth), cf, CONCRETE, Enum.Material.Concrete)
		end
	end
	if spec.handrail then
		local _, dir = at(0)
		local off = dir:Cross(Vector3.yAxis).Unit * (width / 2 - 0.3)
		local a, b = at(0), at(total)
		for _, s in ipairs({ -1, 1 }) do
			local o = off * s + Vector3.new(0, 3.2, 0)
			slab(model, "Handrail", a + o, b + o, 0.25, 0.25, RAIL, Enum.Material.Metal)
			for _, p in ipairs({ a, b }) do
				part(model, "Post", Vector3.new(0.25, 3.2, 0.25), CFrame.new(p + off * s + Vector3.new(0, 1.6, 0)), RAIL,
					Enum.Material.Metal)
			end
		end
	end
	return model
end

-- The weir: steps of concrete from the upper pond's level down to the
-- lower's, each a block along the weir's line, set back downstream in turn,
-- with walls at either end.
local function weir(parent, spec)
	local model = Instance.new("Model")
	model.Name = "Weir"
	model.Parent = parent
	local down = Vector3.new(spec.downstream[1], 0, spec.downstream[2])
	local a = Vector3.new(spec.points[1][1], 0, spec.points[1][2])
	local b = Vector3.new(spec.points[#spec.points][1], 0, spec.points[#spec.points][2])
	local length = (b - a).Magnitude
	local centre = (a + b) / 2
	local facing = CFrame.lookAt(centre, centre + down) -- -Z downstream, X along the weir
	local steps, depth = 4, 3.2
	local drop = (spec.upper - spec.lower + 1) / steps
	local bottom = spec.lower - 5
	for k = 0, steps - 1 do
		local top = spec.upper - 0.3 - drop * k
		local height = top - bottom
		local cf = facing * CFrame.new(0, 0, -(k + 0.5) * depth)
		cf = CFrame.new(cf.Position.X, bottom + height / 2, cf.Position.Z) * facing.Rotation
		part(model, "Step", Vector3.new(length, height, depth), cf, CONCRETE, Enum.Material.Concrete)
		-- A sheet of water over the step's lip.
		part(model, "Spill", Vector3.new(length - 1, 0.25, depth), cf * CFrame.new(0, height / 2 + 0.12, 0),
			Color3.fromRGB(150, 180, 170), Enum.Material.Glass,
			{ Transparency = 0.45, CanCollide = false, CanQuery = false })
	end
	-- Walls at the ends, a slab walk along their tops.
	for _, s in ipairs({ -1, 1 }) do
		local run = steps * depth + 2
		local cf = facing * CFrame.new(s * (length / 2 + 1), 0, -run / 2 + 1)
		local height = spec.upper + 1 - bottom
		part(model, "Wall", Vector3.new(2, height, run),
			CFrame.new(cf.Position.X, bottom + height / 2, cf.Position.Z) * facing.Rotation, CONCRETE,
			Enum.Material.Concrete)
	end
	return model
end

-- Paths and roads: a ribbon of thin slabs along each OSM line, at its real
-- width, following the ground point by point, with a round pad at every
-- joint so bends have no gaps. (Terrain's 4-stud voxels can't draw a
-- clean path edge; these can.)
local SURFACES = {
	asphalt = { Color3.fromRGB(70, 70, 74), Enum.Material.Asphalt },
	concrete = { Color3.fromRGB(184, 180, 170), Enum.Material.Concrete },
	brick = { Color3.fromRGB(150, 84, 64), Enum.Material.Brick },
	gravel = { Color3.fromRGB(160, 150, 132), Enum.Material.Pebble },
	dirt = { Color3.fromRGB(132, 108, 80), Enum.Material.Ground },
}
local STEP = 2 -- studs between ground samples
local LIFT = 0.12 -- how far the surface sits above the ground
local THICK = 0.3 -- thin: where two paths cross at slightly different heights, only a sliver of edge shows
local SMOOTH = 0.15 -- studs of ground unevenness a merged piece may bridge

-- The ground either side of a point, across a path of this width.
local function sides(p, dir, width)
	local across = Vector3.new(-dir.Z, 0, dir.X) * (width / 2)
	return groundY(p - across), groundY(p), groundY(p + across)
end

-- A piece from node a to node b. Each node has its own height and sideways
-- tilt, set from the ground across the path there (see way), and a piece is
-- the plane through its two nodes -- so neighbours meet exactly, with no
-- step between them, and each edge follows the ground.
local function piece(parent, a, b, width, colour, material)
	local flat = Vector3.new(b.p.X - a.p.X, 0, b.p.Z - a.p.Z)
	local length = flat.Magnitude
	if length < 0.05 then
		return
	end
	local dir = flat.Unit
	local right = Vector3.new(-dir.Z, 0, dir.X)
	local ca = Vector3.new(a.p.X, a.y, a.p.Z)
	local cb = Vector3.new(b.p.X, b.y, b.p.Z)
	local forward = (cb - ca).Unit
	local side = (right + Vector3.new(0, (a.bank + b.bank) / 2, 0)).Unit
	local up = side:Cross(forward).Unit
	if up.Y < 0 then
		up = -up
	end
	side = forward:Cross(up).Unit
	local cf = CFrame.fromMatrix((ca + cb) / 2 - up * THICK / 2, side, up, -forward)
	part(parent, "Path", Vector3.new(width, THICK, length + 0.3), cf, colour, material, { CanCollide = false })
end

local function way(parent, spec)
	local look = SURFACES[spec.surface] or SURFACES.concrete
	local colour, material = look[1], look[2]
	-- Resample the line every STEP studs, each point with its ground heights
	-- left, centre and right.
	local flatPts = {}
	for i = 1, #spec.points - 1 do
		local a = Vector3.new(spec.points[i][1], 0, spec.points[i][2])
		local b = Vector3.new(spec.points[i + 1][1], 0, spec.points[i + 1][2])
		local n = math.max(1, math.ceil((b - a).Magnitude / STEP))
		for k = 0, n - 1 do
			table.insert(flatPts, a:Lerp(b, k / n))
		end
	end
	local last = spec.points[#spec.points]
	table.insert(flatPts, Vector3.new(last[1], 0, last[2]))
	local pts = {}
	for i, p in ipairs(flatPts) do
		local nxt = flatPts[math.min(i + 1, #flatPts)]
		local prv = flatPts[math.max(i - 1, 1)]
		local dir = (nxt - prv).Magnitude > 0.01 and (nxt - prv).Unit or Vector3.new(0, 0, 1)
		local l, c, r = sides(p, dir, spec.width)
		if c == -math.huge then
			c = 0
		end
		l = if l == -math.huge or l - c > 3 then c else l
		r = if r == -math.huge or r - c > 3 then c else r
		-- The node: tilted like the ground across the path, and high enough
		-- that neither edge nor the middle is under it.
		local bank = (r - l) / spec.width
		-- High enough over five points across the path, the tilted plane's
		-- height at each offset compared with the ground there (a crowned or
		-- dished path would otherwise sink in the middle or at the quarters).
		local across = Vector3.new(-dir.Z, 0, dir.X)
		local y = -math.huge
		for _, f in ipairs({ -0.5, -0.25, 0, 0.25, 0.5 }) do
			local g = groundY(p + across * f * spec.width)
			if g == -math.huge or g - c > 3 then
				g = c
			end
			y = math.max(y, g - bank * f * spec.width)
		end
		y += LIFT
		table.insert(pts, { p = p, l = l, c = c, r = r, y = y, bank = bank })
	end
	-- Merge runs where the ground is even, left, centre and right alike.
	local kept = { pts[1] }
	local i = 1
	while i < #pts do
		local j = i + 1
		while j + 1 <= #pts do
			local a, b = pts[i], pts[j + 1]
			local span = (b.p - a.p).Magnitude
			local ok = true
			for k = i + 1, j do
				local t = (pts[k].p - a.p).Magnitude / math.max(span, 0.01)
				local onLine = a.p:Lerp(b.p, t)
				if (onLine - pts[k].p).Magnitude > 0.3
					or math.abs(a.c + (b.c - a.c) * t - pts[k].c) > SMOOTH
					or math.abs(a.l + (b.l - a.l) * t - pts[k].l) > SMOOTH
					or math.abs(a.r + (b.r - a.r) * t - pts[k].r) > SMOOTH then
					ok = false
					break
				end
			end
			if not ok then
				break
			end
			j += 1
		end
		table.insert(kept, pts[j])
		i = j
	end
	for k = 1, #kept - 1 do
		piece(parent, kept[k], kept[k + 1], spec.width, colour, material)
	end
	-- Round pads at the original bends, their tops just under the path's own
	-- surface there, so they fill the gap at the bend without standing proud.
	for k = 2, #spec.points - 1 do
		local p = Vector3.new(spec.points[k][1], 0, spec.points[k][2])
		local best, bd = nil, math.huge
		for _, node in ipairs(pts) do
			local d = (node.p - p).Magnitude
			if d < bd then
				best, bd = node, d
			end
		end
		if best then
			-- Tilted like the path there, so neither side stands proud.
			local prev = Vector3.new(spec.points[k - 1][1], 0, spec.points[k - 1][2])
			local nxt = Vector3.new(spec.points[k + 1][1], 0, spec.points[k + 1][2])
			local dir = (nxt - prev).Magnitude > 0.01 and (nxt - prev).Unit or Vector3.new(0, 0, 1)
			local tilt = CFrame.lookAt(Vector3.zero, dir) * CFrame.Angles(0, 0, math.atan(best.bank))
			local top = best.y - 0.03
			part(parent, "Joint", Vector3.new(THICK, spec.width, spec.width),
				CFrame.new(p.X, top, p.Z) * tilt * CFrame.new(0, -THICK / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
				colour, material, { Shape = Enum.PartType.Cylinder, CanCollide = false })
		end
	end
end

function Paths.build()
	-- A fresh copy each run: require caches, and the data changes between runs.
	local features = require(ServerStorage:WaitForChild("TerrainData"):WaitForChild("Features"):Clone())
	local root = workspace:FindFirstChild("DuckPond") or Instance.new("Folder")
	root.Name = "DuckPond"
	root.Parent = workspace
	for _, name in ipairs({ "Bridges", "Steps", "Ways" }) do
		local old = root:FindFirstChild(name)
		if old then
			old:Destroy()
		end
	end
	local bridges = Instance.new("Folder")
	bridges.Name = "Bridges"
	bridges.Parent = root
	local steps = Instance.new("Folder")
	steps.Name = "Steps"
	steps.Parent = root
	for _, spec in ipairs(features.bridges) do
		bridge(bridges, spec)
	end
	for _, spec in ipairs(features.steps) do
		stairs(steps, spec)
	end
	local ways = Instance.new("Folder")
	ways.Name = "Ways"
	ways.Parent = root
	for i, spec in ipairs(features.ways or {}) do
		way(ways, spec)
		if i % 20 == 0 then
			task.wait()
		end
	end
	for _, spec in ipairs(features.weirs or {}) do
		weir(bridges, spec)
	end
	return string.format("%d bridges, %d flights of steps, %d paths (%d pieces)", #features.bridges,
		#features.steps, #(features.ways or {}), #ways:GetChildren())
end

return Paths
