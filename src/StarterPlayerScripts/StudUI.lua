--[[
	StudUI
	The house style from Be a Crash Test Dummy (HudGrid, Studs): a solid
	panel with the Roblox stud texture tiled over it, a gloss lighter toward
	the bottom, a thick near-black outline and a soft inner rim.

		StudUI.button(parent, text, colour) -> TextButton
]]

local StudUI = {}

StudUI.STUD_TEXTURE = "rbxassetid://83612320669030" -- 4 x 4 studs, highlights and shading on transparency
local STUD_PX = 22
local OUTLINE = Color3.fromRGB(12, 14, 20)

function StudUI.button(parent, text, colour)
	local b = Instance.new("TextButton")
	b.AutoButtonColor = true
	b.BackgroundColor3 = colour
	b.Font = Enum.Font.FredokaOne
	b.TextColor3 = Color3.new(1, 1, 1)
	b.TextStrokeTransparency = 0.5
	b.TextSize = 22
	b.Text = text
	b.Parent = parent
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 12)
	local outline = Instance.new("UIStroke")
	outline.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	outline.Color = OUTLINE
	outline.Thickness = 3
	outline.Parent = b

	-- The studs: whole ones, under the text.
	local studs = Instance.new("ImageLabel")
	studs.Name = "Studs"
	studs.BackgroundTransparency = 1
	studs.Image = StudUI.STUD_TEXTURE
	studs.ImageTransparency = 0.6
	studs.ScaleType = Enum.ScaleType.Tile
	studs.TileSize = UDim2.fromOffset(STUD_PX * 4, STUD_PX * 4)
	studs.Size = UDim2.fromScale(1, 1)
	studs.ZIndex = b.ZIndex
	studs.Parent = b
	Instance.new("UICorner", studs).CornerRadius = UDim.new(0, 12)

	-- The gloss, lighter toward the bottom, and the inner rim.
	local gloss = Instance.new("Frame")
	gloss.Name = "Gloss"
	gloss.BackgroundColor3 = Color3.new(1, 1, 1)
	gloss.BackgroundTransparency = 0.82
	gloss.Size = UDim2.fromScale(1, 1)
	gloss.ZIndex = b.ZIndex
	gloss.Parent = b
	Instance.new("UICorner", gloss).CornerRadius = UDim.new(0, 12)
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Transparency = NumberSequence.new(1, 0.2)
	g.Parent = gloss
	local rim = Instance.new("UIStroke")
	rim.Color = Color3.new(1, 1, 1)
	rim.Transparency = 0.55
	rim.Thickness = 2
	rim.Parent = gloss

	-- The label above the studs and gloss.
	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = b.Font
	label.TextColor3 = b.TextColor3
	label.TextStrokeTransparency = b.TextStrokeTransparency
	label.TextSize = b.TextSize
	label.Text = text
	label.ZIndex = b.ZIndex + 1
	label.Parent = b
	b.TextTransparency = 1
	b:GetPropertyChangedSignal("Text"):Connect(function()
		label.Text = b.Text
	end)
	return b
end

return StudUI
