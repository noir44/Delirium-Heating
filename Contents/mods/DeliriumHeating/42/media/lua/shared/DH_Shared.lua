-- Delirium Heating - definitions shared by client and server.
--
-- District heating. A water intake (2x2 cells, by a river or a lake) pumps
-- water into the pipes; a boiler house (2x3) takes it, burns fuel and heats
-- it; pipes laid on the ground carry it, pump stations push it further; at
-- a house the pipe ends in a heat unit, and the radiators within its radius
-- warm the rooms the way a vanilla fireplace does (IsoHeatSource, made by
-- each client for the radiators near it).
--
-- The network lives in the server's ModData as cells, "x,y,z" -> kind:
--   "p" pipe, "u" pump, "i" heat unit, "b" boiler cell, "w" intake cell,
--   "r" radiator (takes its cell but joins no pipe).
-- The world objects are only its picture. A pump and a heat unit stand on a
-- pipe of their own: their cell shows a pipe sprite (by its neighbours) and
-- the device sprite on top of it.
--
-- Pipes in the air: above the ground a pipe needs no floor. It is laid
-- from a floor of its level out into the air, or from the level below (the
-- cursor lifted a level). A pipe joins the pipe right above or below it, and
-- the lower one shows a riser.
--
-- Tiles: tileset delheat_01,
--   0..15   pipe by neighbour mask (N = 1, E = 2, S = 4, W = 8),
--   16, 42  pump along an east-west pipe, along a north-south one,
--   17, 38..40  heat unit at the north, west, south, east edge of its cell,
--   18..21  radiator at the same four edges,
--   22..27  boiler with its front to the south, 3 wide x 2 deep (dy * 3 + dx),
--   28..33  boiler with its front to the east, 2 wide x 3 deep (dy * 2 + dx),
--   34..37  water intake, 2 x 2 (dy * 2 + dx),
--   41      riser: the pipe going up to the cell above,
--   43      pipe support: a steel lattice post one level high, only for the look,
--   44..47  water unit at the north, west, south, east edge of its cell;
-- (dx, dy) counted from the structure's north-west cell, its anchor.
--
-- Where things join. A pipe and a heat unit take a pipe on all four sides.
-- A pump takes one only along its axis: its sprite carries its own length of
-- pipe, there is no pipe sprite under it. A boiler and an intake take pipes
-- only at their outlets (PORTS below, where the sprite shows a pipe end). A
-- pipe lying next to any other cell of them does not join, neither on the
-- picture nor for the water.
--
-- Who builds: an admin anything; any player the radiators; the head and
-- staff of an organization with the heat supply activity (Delirium Economy)
-- the rest - pipes, heat units, pumps, intakes, boiler houses.

require "DE_Shared"

DelHeat = DelHeat or {}
DelHeat.MODULE = "DelHeat"
DelHeat.STATE_KEY = "DelHeat_State"
DelHeat.TILESET = "delheat_01_"

DelHeat.PIPE, DelHeat.PUMP, DelHeat.INLET = "p", "u", "i"
DelHeat.RADIATOR, DelHeat.BOILER, DelHeat.INTAKE = "r", "b", "w"
DelHeat.SUPPORT = "s"
-- Water unit: the heat unit's twin for the intake's cold water. It keeps a
-- tank filled from the pipe and tops up the sinks, toilets and baths around.
DelHeat.TAP = "t"

-- Kind -> the name the commands, the items and the translations use.
DelHeat.NAME = { p = "pipe", u = "pump", i = "inlet", r = "radiator", b = "boiler", w = "intake", s = "support", t = "tap" }
-- What a player builds each of, and gets back when it is taken apart.
DelHeat.ITEM = {
	pipe = "DelHeat.Pipe", pump = "DelHeat.Pump", inlet = "DelHeat.Inlet",
	radiator = "DelHeat.Radiator", boiler = "DelHeat.Boiler", intake = "DelHeat.Intake",
	support = "DelHeat.Support", tap = "DelHeat.WaterUnit",
}
-- The tool a player needs on them to build or take apart.
DelHeat.TOOL = "Base.PipeWrench"

-- The organization activity (Delirium Economy) the admin ticks for a heat
-- supply company: only its head and staff build and take apart the network.
DelHeat.ACTIVITY = "heating"
if DelEcon.addActivity then DelEcon.addActivity(DelHeat.ACTIVITY, "IGUI_DelHeat_Activity") end

-- By the pipe a pump stands along: "E" east-west, "S" north-south.
DelHeat.SPRITE_PUMP = { E = 16, S = 42 }
DelHeat.PUMP_FACINGS = { "E", "S" }
DelHeat.SPRITE_INLET = { N = 17, W = 38, S = 39, E = 40 }
DelHeat.SPRITE_RISER = 41
DelHeat.SPRITE_RADIATOR = { N = 18, W = 19, S = 20, E = 21 }
DelHeat.SPRITE_BOILER = { S = 22, E = 28 }
DelHeat.SPRITE_INTAKE = 34
DelHeat.SPRITE_SUPPORT = 43
DelHeat.SPRITE_TAP = { N = 44, W = 45, S = 46, E = 47 }
-- The four edges of a cell a radiator or a heat unit stands at.
DelHeat.RADIATOR_FACINGS = { "N", "W", "S", "E" }
DelHeat.BOILER_FACINGS = { "S", "E" }
DelHeat.BOILER_SIZE = { S = { w = 3, h = 2 }, E = { w = 2, h = 3 } }
DelHeat.INTAKE_SIZE = { w = 2, h = 2 }

-- Neighbours in the plane, with their bit in a pipe's sprite mask and the
-- bit of the side that faces back.
DelHeat.DIRS = {
	{ dx = 0, dy = -1, bit = 1, back = 4 },
	{ dx = 1, dy = 0, bit = 2, back = 8 },
	{ dx = 0, dy = 1, bit = 4, back = 1 },
	{ dx = -1, dy = 0, bit = 8, back = 2 },
}

-- The sides (a mask of the same bits) a thing takes a pipe on.
DelHeat.ALL_SIDES = 15
DelHeat.PUMP_SIDES = { E = 2 + 8, S = 1 + 4 }
-- Outlets of the structures by cell ("dx,dy" from the anchor): the boiler's
-- two at its tank, the intake's discharge out of the south face of its pad.
DelHeat.BOILER_PORTS = { S = { ["2,1"] = 2 + 4 }, E = { ["1,0"] = 1 + 2 } }
DelHeat.INTAKE_PORTS = { ["1,1"] = 4 }

-- Kahlua has no bit operators.
function DelHeat.hasSide(mask, bit)
	return math.floor((mask or 0) / bit) % 2 == 1
end

-- kind, and for a pump or a boiler its facing, for a boiler or an intake the
-- cell (dx, dy from the anchor).
function DelHeat.sidesOf(kind, facing, dx, dy)
	if kind == DelHeat.PIPE or kind == DelHeat.INLET or kind == DelHeat.TAP then return DelHeat.ALL_SIDES end
	if kind == DelHeat.PUMP then return DelHeat.PUMP_SIDES[facing] or DelHeat.PUMP_SIDES.E end
	if kind == DelHeat.BOILER then
		local ports = DelHeat.BOILER_PORTS[facing] or DelHeat.BOILER_PORTS.S
		return ports[tostring(dx) .. "," .. tostring(dy)] or 0
	end
	if kind == DelHeat.INTAKE then return DelHeat.INTAKE_PORTS[tostring(dx) .. "," .. tostring(dy)] or 0 end
	return 0
end

-- The same for what nodeAt() read off the square at (x, y).
function DelHeat.sidesOfNode(node, x, y)
	if not node then return 0 end
	return DelHeat.sidesOf(node.kind, node.facing, x - node.x, y - node.y)
end

-- Water temperature, Celsius: radiators start to warm at WARM and give
-- their full heat at HOT; the boiler stops at MAX.
DelHeat.WATER_WARM = 30
DelHeat.WATER_HOT = 80
DelHeat.WATER_MAX = 90
-- Radiator heat is sent to the clients as a level 0..LEVELS.
DelHeat.LEVELS = 10
-- The longest pipe run laid or removed by one command.
DelHeat.MAX_LINE = 200
-- How far from a boiler a player may stand to work it, and from a cell to
-- build on it or take it apart.
DelHeat.REACH = 2.5
DelHeat.BUILD_REACH = 4
-- A heat unit serves the radiators this many floors above and below it.
DelHeat.INLET_FLOORS = 3
-- An intake wants water within this many cells of its footprint.
DelHeat.WATER_RANGE = 3

DelHeat.DEFAULT_FUEL = "Base.Log:6; Base.Firewood:2; Base.Plank:2; Base.LargeBranch:1.5; Base.TreeBranch2:1; "
	.. "Base.UnusableWood:1; Base.Charcoal:3; Base.CharcoalCrafted:3; Base.Coke:4; Base.PropaneTank:80"

-- ---------------------------------------------------------------------------
-- Sandbox: read at the point of use, never at file scope (see E:\mods\CLAUDE.md).
-- ---------------------------------------------------------------------------

local function sandbox()
	return SandboxVars and SandboxVars.DelHeat or {}
end

local function number(value, default, min)
	return math.max(min, tonumber(value) or default)
end

function DelHeat.playersBuild() return sandbox().PlayersBuild ~= false end
function DelHeat.fuelCapacity() return number(sandbox().FuelCapacity, 500, 1) end
-- Fuel units an idle boiler burns in a game hour: one unit is one such hour.
function DelHeat.burnPerHour() return number(sandbox().BurnPerHour, 1, 0) end
-- Extra units per game hour for every radiator the boiler feeds.
function DelHeat.burnPerRadiator() return number(sandbox().BurnPerRadiator, 0.05, 0) end
function DelHeat.heatUpPerMinute() return number(sandbox().HeatUpPerMinute, 1, 0.01) end
function DelHeat.coolDownPerMinute() return number(sandbox().CoolDownPerMinute, 0.25, 0.01) end
-- Water: litres in a boiler's tank, lost per game hour while it burns, and
-- pumped in per game hour by every working intake that reaches the boiler.
function DelHeat.waterCapacity() return number(sandbox().WaterCapacity, 1000, 1) end
function DelHeat.waterPerHour() return number(sandbox().WaterPerHour, 10, 0) end
function DelHeat.waterPerRadiator() return number(sandbox().WaterPerRadiator, 0.5, 0) end
function DelHeat.intakeRate() return number(sandbox().IntakeRate, 200, 0) end
-- Cells of pipe the water travels from an intake, from a boiler, and from a
-- working pump.
function DelHeat.intakeReach() return math.floor(number(sandbox().IntakeReach, 60, 1)) end
function DelHeat.boilerReach() return math.floor(number(sandbox().BoilerReach, 40, 1)) end
function DelHeat.pumpReach() return math.floor(number(sandbox().PumpReach, 80, 1)) end
function DelHeat.pumpNeedsPower() return sandbox().PumpNeedsPower ~= false end
-- Cells around a heat unit in which radiators work.
function DelHeat.inletRadius() return math.floor(number(sandbox().InletRadius, 10, 1)) end
-- Water unit: the plumbing it serves (same floors as a heat unit), its tank,
-- and whether it gives clean water or the river's as it is.
function DelHeat.tapRadius() return math.floor(number(sandbox().TapRadius, 10, 1)) end
function DelHeat.tapCapacity() return number(sandbox().TapCapacity, 200, 1) end
function DelHeat.tapClean() return sandbox().TapClean ~= false end
-- A vanilla fireplace is a heat source of 35 degrees.
function DelHeat.radiatorTemp() return math.floor(number(sandbox().RadiatorTemp, 35, 1)) end
function DelHeat.radiatorRadius() return math.floor(number(sandbox().RadiatorRadius, 6, 1)) end
function DelHeat.petrolPerLitre() return number(sandbox().PetrolPerLitre, 2, 0) end

-- "Base.Log:6; Base.Plank:2" -> { ["Base.Log"] = 6, ... }. A table without
-- a single good entry falls back to the default one.
local function parseFuel(text)
	local out, any = {}, false
	for entry in string.gmatch(tostring(text or ""), "[^;]+") do
		local fullType, units = string.match(entry, "^%s*([%w_]+%.[%w_]+)%s*:%s*([%d%.]+)%s*$")
		units = tonumber(units)
		if fullType and units and units > 0 then
			out[fullType] = units
			any = true
		end
	end
	return out, any
end

function DelHeat.fuelTable()
	local list, any = parseFuel(sandbox().FuelTable)
	if not any then list = parseFuel(DelHeat.DEFAULT_FUEL) end
	return list
end

-- ---------------------------------------------------------------------------
-- Fuel
-- ---------------------------------------------------------------------------

-- What the item is worth in the boiler: units, how it is taken
-- ("item" - the whole item goes, "drain" - a drainable is emptied,
-- "fluid" - petrol is poured out of its container). nil when it is no fuel.
function DelHeat.fuelValue(item, fuelTable)
	if not item then return nil end
	local units = (fuelTable or DelHeat.fuelTable())[item:getFullType()]
	if units then
		if item:IsDrainable() then
			local left = item:getCurrentUsesFloat()
			if left <= 0 then return nil end
			return units * left, "drain"
		end
		return units, "item"
	end
	local fluid = item:getFluidContainer()
	if fluid and fluid:contains(Fluid.Petrol) and fluid:getAmount() >= 0.099 then
		local perLitre = DelHeat.petrolPerLitre()
		if perLitre <= 0 then return nil end
		return fluid:getAmount() * perLitre, "fluid"
	end
	return nil
end

-- ---------------------------------------------------------------------------
-- Items of the builder
-- ---------------------------------------------------------------------------

-- Items of this full type on the player, bags included (a Java list).
function DelHeat.itemsOf(player, fullType)
	return player:getInventory():getAllEvalRecurse(function(item)
		return item:getFullType() == fullType
	end)
end

function DelHeat.countOf(player, fullType)
	return DelHeat.itemsOf(player, fullType):size()
end

function DelHeat.hasTool(player)
	return DelHeat.countOf(player, DelHeat.TOOL) > 0
end

-- ---------------------------------------------------------------------------
-- Geometry
-- ---------------------------------------------------------------------------

function DelHeat.key(x, y, z)
	return tostring(math.floor(x)) .. "," .. tostring(math.floor(y)) .. "," .. tostring(math.floor(z))
end

-- "x,y,z" -> x, y, z.
function DelHeat.unkey(key)
	local x, y, z = string.match(tostring(key), "^(-?%d+),(-?%d+),(-?%d+)$")
	return tonumber(x), tonumber(y), tonumber(z)
end

-- Footprint of a boiler (by its facing) or an intake.
function DelHeat.sizeOf(kind, facing)
	if kind == DelHeat.INTAKE then return DelHeat.INTAKE_SIZE end
	return DelHeat.BOILER_SIZE[facing] or DelHeat.BOILER_SIZE.S
end

function DelHeat.pipeSprite(mask)
	return DelHeat.TILESET .. tostring(mask)
end

function DelHeat.pumpSprite(facing)
	return DelHeat.TILESET .. tostring(DelHeat.SPRITE_PUMP[facing] or DelHeat.SPRITE_PUMP.E)
end

function DelHeat.inletSprite(facing)
	return DelHeat.TILESET .. tostring(DelHeat.SPRITE_INLET[facing] or DelHeat.SPRITE_INLET.N)
end

function DelHeat.tapSprite(facing)
	return DelHeat.TILESET .. tostring(DelHeat.SPRITE_TAP[facing] or DelHeat.SPRITE_TAP.N)
end

function DelHeat.supportSprite()
	return DelHeat.TILESET .. tostring(DelHeat.SPRITE_SUPPORT)
end

function DelHeat.riserSprite()
	return DelHeat.TILESET .. tostring(DelHeat.SPRITE_RISER)
end

function DelHeat.radiatorSprite(facing)
	return DelHeat.TILESET .. tostring(DelHeat.SPRITE_RADIATOR[facing] or DelHeat.SPRITE_RADIATOR.N)
end

function DelHeat.boilerSprite(facing, dx, dy)
	local size = DelHeat.sizeOf(DelHeat.BOILER, facing)
	return DelHeat.TILESET .. tostring((DelHeat.SPRITE_BOILER[facing] or DelHeat.SPRITE_BOILER.S) + dy * size.w + dx)
end

function DelHeat.intakeSprite(dx, dy)
	return DelHeat.TILESET .. tostring(DelHeat.SPRITE_INTAKE + dy * DelHeat.INTAKE_SIZE.w + dx)
end

-- Sprite name -> { kind, facing, dx, dy, pipe = true for the pipe sprites };
-- nil when it is not ours.
function DelHeat.parseSprite(name)
	if not name or string.sub(name, 1, #DelHeat.TILESET) ~= DelHeat.TILESET then return nil end
	local index = tonumber(string.sub(name, #DelHeat.TILESET + 1))
	if not index or index < 0 then return nil end
	if index <= 15 or index == DelHeat.SPRITE_RISER then return { kind = DelHeat.PIPE, pipe = true } end
	if index == DelHeat.SPRITE_SUPPORT then return { kind = DelHeat.SUPPORT } end
	for facing, sprite in pairs(DelHeat.SPRITE_PUMP) do
		if index == sprite then return { kind = DelHeat.PUMP, facing = facing } end
	end
	for facing, sprite in pairs(DelHeat.SPRITE_INLET) do
		if index == sprite then return { kind = DelHeat.INLET, facing = facing } end
	end
	for facing, sprite in pairs(DelHeat.SPRITE_TAP) do
		if index == sprite then return { kind = DelHeat.TAP, facing = facing } end
	end
	for facing, sprite in pairs(DelHeat.SPRITE_RADIATOR) do
		if index == sprite then return { kind = DelHeat.RADIATOR, facing = facing } end
	end
	for facing, first in pairs(DelHeat.SPRITE_BOILER) do
		local size = DelHeat.BOILER_SIZE[facing]
		if index >= first and index < first + size.w * size.h then
			local cell = index - first
			return { kind = DelHeat.BOILER, facing = facing, dx = cell % size.w, dy = math.floor(cell / size.w) }
		end
	end
	local size = DelHeat.INTAKE_SIZE
	if index >= DelHeat.SPRITE_INTAKE and index < DelHeat.SPRITE_INTAKE + size.w * size.h then
		local cell = index - DelHeat.SPRITE_INTAKE
		return { kind = DelHeat.INTAKE, dx = cell % size.w, dy = math.floor(cell / size.w) }
	end
	return nil
end

-- What stands on this square, read off its sprites:
-- { kind, facing, x, y, z (a structure's anchor, otherwise the square), key }.
-- A device wins over the pipe under it.
function DelHeat.nodeAt(square)
	if not square then return nil end
	local objects = square:getObjects()
	local found
	for i = 0, objects:size() - 1 do
		local sprite = objects:get(i):getSprite()
		local info = DelHeat.parseSprite(sprite and sprite:getName())
		if info and (not found or found.pipe) then found = info end
	end
	if not found then return nil end
	local x, y, z = square:getX(), square:getY(), square:getZ()
	if found.dx then x, y = x - found.dx, y - found.dy end
	return { kind = found.kind, facing = found.facing, x = x, y = y, z = z, key = DelHeat.key(x, y, z) }
end

-- Where a part clicked at (x, y) goes: its north-west cell and its size.
-- A boiler and an intake are clicked on the cell next to the anchor's
-- south-east: the middle of a boiler's front, the near corner of an intake.
function DelHeat.anchorOf(name, facing, x, y)
	if name == "boiler" then return x - 1, y - 1, DelHeat.sizeOf(DelHeat.BOILER, facing) end
	if name == "intake" then return x - 1, y - 1, DelHeat.INTAKE_SIZE end
	return x, y, { w = 1, h = 1 }
end

-- Cells from (x1, y1) to (x2, y2): along x first, then along y.
function DelHeat.path(x1, y1, x2, y2, z)
	local out = {}
	local x, y = x1, y1
	table.insert(out, { x = x, y = y, z = z })
	while x ~= x2 do
		x = x + (x2 > x and 1 or -1)
		table.insert(out, { x = x, y = y, z = z })
	end
	while y ~= y2 do
		y = y + (y2 > y and 1 or -1)
		table.insert(out, { x = x, y = y, z = z })
	end
	return out
end

-- A pipe lies on a floor on the ground and below it; higher up it hangs in
-- the air. Everything else stands on a floor.
function DelHeat.needsFloor(name, z)
	return name ~= "pipe" or z <= 0
end

function DelHeat.isWater(square)
	local floor = square and square:getFloor()
	local sprite = floor and floor:getSprite()
	local props = sprite and sprite:getProperties()
	return props ~= nil and props:has(IsoFlagType.water)
end

-- Distance from a point to a footprint at (x, y), 0 inside it.
function DelHeat.distanceTo(x, y, size, px, py)
	local dx = math.max(math.max(x - px, px - (x + size.w)), 0)
	local dy = math.max(math.max(y - py, py - (y + size.h)), 0)
	return math.sqrt(dx * dx + dy * dy)
end

-- Water temperature -> radiator heat level 0..LEVELS.
function DelHeat.heatLevel(temp)
	local f = ((tonumber(temp) or 0) - DelHeat.WATER_WARM) / (DelHeat.WATER_HOT - DelHeat.WATER_WARM)
	f = math.max(0, math.min(1, f))
	return math.floor(f * DelHeat.LEVELS + 0.5)
end

-- ---------------------------------------------------------------------------
-- Rights
-- ---------------------------------------------------------------------------

function DelHeat.isAdmin(player)
	return DelShops.hasAdminRights(player)
end

-- Parts by their name in DelHeat.ITEM: a radiator is anybody's to put in
-- their rooms, the rest is the network and takes a heat supply company.
function DelHeat.needsService(name)
	return name ~= "radiator"
end

-- Head or staff of an organization with the heat supply activity. Admin
-- rights are asked separately. The state is the server's own on the server
-- and Economy's read-only copy on a client.
function DelHeat.isService(player)
	if not player then return false end
	-- A Delirium Economy without activities: no filter.
	if not DelEcon.hasActivity then return true end
	local state = DelEcon.getState()
	for _, id in ipairs(DelEcon.hallIds(state)) do
		local hall = state.halls[id]
		if DelEcon.hasActivity(hall, DelHeat.ACTIVITY)
			and (DelEcon.isMayorOf(hall, player) or DelEcon.isStaffOf(hall, player)) then
			return true
		end
	end
	return false
end
