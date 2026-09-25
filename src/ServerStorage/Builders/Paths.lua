--[[
	Paths builder
	The bridges and steps, from TerrainData.Features (tools/make_terrain.py,
	out of OpenStreetMap). The paths themselves are terrain, painted by the
	Terrain builder; these are the parts that aren't ground.

		require(game.ServerStorage.Builders.Paths).build()

	What they look like is a guess for now, to be put right on visits:
	  road bridges  Duck Pond Drive: an asphalt deck between Hokie Stone
	                parapets (Virginia Tech's grey limestone)
	  footbridges   concrete decks, a gentle arch, dark metal railings
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
	local deckColour = if road then ASPHALT else CONCRETE
	local deckMaterial = if road then Enum.Material.Asphalt else Enum.Material.Concrete
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
					-- A post, and the top rail to the next one.
					local foot = previous.p + off
					part(model, "Post", Vector3.new(0.3, 3.4, 0.3), CFrame.new(foot + Vector3.new(0, 1.7, 0)), RAIL,
						Enum.Material.Metal)
					slab(model, "Rail", foot + Vector3.new(0, 3.4, 0), p + off + Vector3.new(0, 3.4, 0), 0.3, 0.3,
						RAIL, Enum.Material.Metal)
					slab(model, "MidRail", foot + Vector3.new(0, 1.8, 0), p + off + Vector3.new(0, 1.8, 0), 0.15, 0.15,
						RAIL, Enum.Material.Metal)
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

function Paths.build()
	local features = require(ServerStorage:WaitForChild("TerrainData"):WaitForChild("Features"))
	local root = workspace:FindFirstChild("DuckPond") or Instance.new("Folder")
	root.Name = "DuckPond"
	root.Parent = workspace
	for _, name in ipairs({ "Bridges", "Steps" }) do
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
	return string.format("%d bridges, %d flights of steps", #features.bridges, #features.steps)
end

return Paths
