--[[
	RealTime
	The game's sky follows the real sky over the Duck Pond: dawn when it's
	dawn in Blacksburg, dusk at dusk, night at night.

	Roblox's sun always rises at ClockTime 6 and sets at 18, whatever the
	season, so this works out today's real sunrise and sunset at the pond
	(NOAA's solar equations) and maps the real day onto Roblox's: sunrise ->
	6, sunset -> 18, and the night between them onto 18 -> 30. So the light
	matches the real park's, even in June when its days are long.

	The map is oriented to match: north is -Z, east +X, so Roblox's sun rises
	over the campus to the east and sets behind the golf course to the west.
]]

local Lighting = game:GetService("Lighting")

local LAT, LON = 37.2261, -80.4286 -- the Duck Pond
local UPDATE = 5 -- seconds

Lighting.GeographicLatitude = LAT

-- Today's sunrise and sunset, in minutes after midnight UTC.
local function sunTimes(now)
	local date = os.date("!*t", now)
	local gamma = 2 * math.pi / 365 * (date.yday - 1 + (date.hour - 12) / 24)
	local eqtime = 229.18 * (0.000075 + 0.001868 * math.cos(gamma) - 0.032077 * math.sin(gamma)
		- 0.014615 * math.cos(2 * gamma) - 0.040849 * math.sin(2 * gamma))
	local decl = 0.006918 - 0.399912 * math.cos(gamma) + 0.070257 * math.sin(gamma)
		- 0.006758 * math.cos(2 * gamma) + 0.000907 * math.sin(2 * gamma)
		- 0.002697 * math.cos(3 * gamma) + 0.00148 * math.sin(3 * gamma)
	local lat = math.rad(LAT)
	local cosHa = math.cos(math.rad(90.833)) / (math.cos(lat) * math.cos(decl)) - math.tan(lat) * math.tan(decl)
	local ha = math.deg(math.acos(math.clamp(cosHa, -1, 1)))
	local sunrise = 720 - 4 * (LON + ha) - eqtime
	local sunset = 720 - 4 * (LON - ha) - eqtime
	return sunrise % 1440, sunset % 1440
end

local function clockTime(now)
	local date = os.date("!*t", now)
	local minute = date.hour * 60 + date.min + date.sec / 60
	local sunrise, sunset = sunTimes(now)
	local day = (sunset - sunrise) % 1440
	local sinceRise = (minute - sunrise) % 1440
	if sinceRise <= day then
		return 6 + 12 * sinceRise / day
	end
	local night = 1440 - day
	return (18 + 12 * (sinceRise - day) / night) % 24
end

while true do
	Lighting.ClockTime = clockTime(os.time())
	task.wait(UPDATE)
end
