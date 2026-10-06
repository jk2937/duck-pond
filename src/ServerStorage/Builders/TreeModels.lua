--[[
	TreeModels
	Realistic tree models (made from real scans, see assets/trees/) standing
	in for the block-built trees. Used by the Trees builder: where a model
	exists for a tree it places that, and builds the block tree otherwise.

	What it needs, once, in the place (it isn't in the repo -- meshes live in
	the place file):
	  ServerStorage.TreeModels   a Folder of the imported models, each named by
	                             its file: sugar_maple_1, sugar_maple_1_hero ...
	                             (Studio's 3D Importer, from the .fbx files;
	                             three MeshParts each: Trunk, Branches, Leaves)
	  TEXTURES below             the uploaded texture ids

	A model for a particular tree goes where that tree stands (TerrainData/
	TreeModels, made by tools/make_tree_models.py from the models' CSV).
	Trees near a path or bench use the hero model, the rest the standard one
	(Roblox's automatic level of detail then thins both with distance).
]]

local ServerStorage = game:GetService("ServerStorage")

local TreeModels = {}

-- Uploaded textures (rbxassetid://...), by species set. Fill in after upload.
local TEXTURES = {
	sugar_maple = {
		barkColor = "",
		barkNormal = "",
		leavesColor = "", -- RGBA: the cut-out is in its alpha
	},
}
-- Tints the leaves a little (the sheet is slightly desaturated for this).
local LEAF_TINT = Color3.fromRGB(190, 215, 160)

local MATCH = 14 -- studs: how near a model's mapped spot a tree must stand to be that tree
local HERO_NEAR = 45 -- studs from a path or bench for the hero tier

local models, entries, pathGrid = nil, nil, nil

local function load()
	if entries then
		return
	end
	entries = {}
	local data = ServerStorage:FindFirstChild("TerrainData")
	local list = data and data:FindFirstChild("TreeModels")
	if list then
		entries = require(list:Clone())
	end
	models = ServerStorage:FindFirstChild("TreeModels")
	-- A grid of path points and benches, to tell which trees are near where
	-- people walk.
	pathGrid = {}
	local function add(x, z)
		local key = math.floor(x / 40) .. "," .. math.floor(z / 40)
		pathGrid[key] = pathGrid[key] or {}
		table.insert(pathGrid[key], Vector2.new(x, z))
	end
	if data and data:FindFirstChild("Features") then
		for _, way in ipairs(require(data.Features:Clone()).ways or {}) do
			for _, p in ipairs(way.points) do
				add(p[1], p[2])
			end
		end
	end
end

local function nearWalking(x, z)
	local cx, cz = math.floor(x / 40), math.floor(z / 40)
	for dx = -2, 2 do
		for dz = -2, 2 do
			for _, p in ipairs(pathGrid[(cx + dx) .. "," .. (cz + dz)] or {}) do
				if (p.X - x) ^ 2 + (p.Y - z) ^ 2 < HERO_NEAR * HERO_NEAR then
					return true
				end
			end
		end
	end
	return false
end

-- Is there a model, and its textures, for the tree at (x, z) of this
-- species (the inventory's name, such as "sugar_maple")? Returns the entry.
function TreeModels.lookup(x, z, species)
	load()
	if not models or not species then
		return nil
	end
	for _, e in ipairs(entries) do
		if species == e.species and (e.x - x) ^ 2 + (e.z - z) ^ 2 < MATCH * MATCH then
			local tex = TEXTURES[e.species]
			if tex and tex.barkColor ~= "" and tex.leavesColor ~= "" and models:FindFirstChild(e.file) then
				return e
			end
		end
	end
	return nil
end

local function dress(part, tex)
	local name = string.lower(part.Name)
	local look = Instance.new("SurfaceAppearance")
	if string.find(name, "leaf") or string.find(name, "leaves") then
		look.ColorMap = tex.leavesColor
		look.AlphaMode = Enum.AlphaMode.Transparency
		look.Color = LEAF_TINT
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
	else
		look.ColorMap = tex.barkColor
		if tex.barkNormal ~= "" then
			look.NormalMap = tex.barkNormal
		end
		-- Only the trunk is solid: you walk into it, not through a branch.
		local solid = string.find(name, "trunk") ~= nil
		part.CanCollide = solid
		part.CanQuery = solid
		part.CanTouch = false
	end
	look.Parent = part
	part.Anchored = true
	part.CastShadow = true
	part.RenderFidelity = Enum.RenderFidelity.Automatic
end

-- Stand the model for `entry` on the ground at (x, y, z). Returns the Model.
function TreeModels.place(parent, entry, x, y, z)
	load()
	local tier = if nearWalking(x, z) and models:FindFirstChild(entry.file .. "_hero") then "_hero" else ""
	local source = models:FindFirstChild(entry.file .. tier)
	local model = source:Clone()
	model.Name = entry.id
	model:SetAttribute("Kind", "model")
	model:SetAttribute("Tier", if tier == "" then "standard" else "hero")
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("MeshPart") then
			for _, old in ipairs(d:GetChildren()) do
				if old:IsA("SurfaceAppearance") then
					old:Destroy()
				end
			end
			dress(d, TEXTURES[entry.species])
		elseif d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	-- Stand it by the trunk's foot, not the model's pivot (which the importer
	-- may put at the middle of the bounding box): the bottom centre of the
	-- Trunk part, sunk a touch so it meets the terrain wherever it lands.
	local trunk
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and string.find(string.lower(d.Name), "trunk") then
			trunk = d
		end
	end
	local base = if trunk then Vector3.new(trunk.Position.X, trunk.Position.Y - trunk.Size.Y / 2, trunk.Position.Z)
		else model:GetPivot().Position
	model:PivotTo(model:GetPivot() + (Vector3.new(x, y - 0.4, z) - base))
	model.Parent = parent
	return model
end

return TreeModels
