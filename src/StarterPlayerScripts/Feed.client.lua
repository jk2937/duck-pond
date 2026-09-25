--[[
	Feed
	Toss bread to the ducks: F on a keyboard, ButtonX on a gamepad, or the
	on-screen button on a phone. The server drops the crumbs and the birds
	race for them (Ducks.server.lua).
]]

local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local toss = ReplicatedStorage:WaitForChild("TossBread")

local function feed(_, state)
	if state == Enum.UserInputState.Begin then
		toss:FireServer()
	end
	return Enum.ContextActionResult.Sink
end

ContextActionService:BindAction("TossBread", feed, true, Enum.KeyCode.F, Enum.KeyCode.ButtonX)
ContextActionService:SetTitle("TossBread", "Bread")
ContextActionService:SetPosition("TossBread", UDim2.new(1, -150, 1, -140))
