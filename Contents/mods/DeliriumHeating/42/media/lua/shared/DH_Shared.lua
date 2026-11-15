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
-- Tiles: tileset delheat_01,
--   0..15   pipe by neighbour mask (N = 1, E = 2, S = 4, W = 8),
--   16      pump, 17 heat unit,
--   18..21  radiator at the north, west, south, east edge of its cell,
--   22..27  boiler with its front to the south, 3 wide x 2 deep (dy * 3 + dx),
--   28..33  boiler with its front to the east, 2 wide x 3 deep (dy * 2 + dx),
--   34..37  water intake, 2 x 2 (dy * 2 + dx);
-- (dx, dy) counted from the structure's north-west cell, its anchor.

DelHeat = DelHeat or {}
DelHeat.MODULE = "DelHeat"
DelHeat.STATE_KEY = "DelHeat_State"
DelHeat.TILESET = "delheat_01_"

DelHeat.PIPE, DelHeat.PUMP, DelHeat.INLET = "p", "u", "i"
DelHeat.RADIATOR, DelHeat.BOILER, DelHeat.INTAKE = "r", "b", "w"

-- Kind -> the name the commands, the items and the translations use.
DelHeat.NAME = { p = "pipe", u = "pump", i = "inlet", r = "radiator", b = "boiler", w = "intake" }
-- What a player builds each of, and gets back when it is taken apart.
DelHeat.ITEM = {
	pipe = "DelHeat.Pipe", pump = "DelHeat.Pump", inlet = "DelHeat.Inlet",
	radiator = "DelHeat.Radiator", boiler = "DelHeat.Boiler", intake = "DelHeat.Intake",
}
-- The tool a player needs on them to build or take apart.
DelHeat.TOOL = "Base.PipeWrench"

DelHeat.SPRITE_PUMP = 16
DelHeat.SPRITE_INLET = 17
DelHeat.SPRITE_RADIATOR = { N = 18, W = 19, S = 20, E = 21 }
DelHeat.SPRITE_BOILER = { S = 22, E = 28 }
DelHeat.SPRITE_INTAKE = 34
DelHeat.RADIATOR_FACINGS = { "N", "W", "S", "E" }
DelHeat.BOILER_FACINGS = { "S", "E" }
DelHeat.BOILER_SIZE = { S = { w = 3, h = 2 }, E = { w = 2, h = 3 } }
DelHeat.INTAKE_SIZE = { w = 2, h = 2 }

-- Neighbours in the plane, with their bit in a pipe's sprite mask.
DelHeat.DIRS = {
	{ dx = 0, dy = -1, bit = 1 },
	{ dx = 1, dy = 0, bit = 2 },
	{ dx = 0, dy = 1, bit = 4 },
	{ dx = -1, dy = 0, bit = 8 },
}

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

function DelHeat.pumpSprite()
	return DelHeat.TILESET .. tostring(DelHeat.SPRITE_PUMP)
end

function DelHeat.inletSprite()
	return DelHeat.TILESET .. tostring(DelHeat.SPRITE_INLET)
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
	if index <= 15 then return { kind = DelHeat.PIPE, pipe = true } end
	if index == DelHeat.SPRITE_PUMP then return { kind = DelHeat.PUMP } end
	if index == DelHeat.SPRITE_INLET then return { kind = DelHeat.INLET } end
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
-- Admin rights: same test as Delirium Shops, kept here so the mod stands
-- alone.
-- ---------------------------------------------------------------------------

function DelHeat.isAdmin(player)
	if not player then return false end
	if player.getAccessLevel and player:getAccessLevel() == "admin" then return true end
	local role = player.getRole and player:getRole()
	if role and role.hasCapability and Capability and Capability.CanSetupNonPVPZone then
		if role:hasCapability(Capability.CanSetupNonPVPZone) then return true end
	end
	if role and role.hasAdminPower and role:hasAdminPower() then return true end
	return false
end
