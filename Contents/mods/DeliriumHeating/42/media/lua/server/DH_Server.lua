-- Delirium Heating - the server side: keeps the network, puts down and
-- removes its objects, pumps the water, burns the fuel, heats the water and
-- tells the clients which radiators are hot.
--
-- State: ModData "DelHeat_State". It is never transmitted whole (a town's
-- pipes are thousands of cells): the clients get the radiator heat levels
-- ("heat") and the devices ("status") by command. It rolls back with the
-- world save, together with the objects and the items, so there is no file
-- of our own.
--   nodes   = { ["x,y,z"] = "p" | "u" | "i" | "r" | "b" | "w" }
--   cells   = { [boiler or intake cell] = its anchor }
--   boilers = { [anchor] = { facing, fuel, water, temp, on, by } }
--   intakes = { [anchor] = { powered, by } }
--   rads    = { [cell] = facing }
--   inlets  = { [cell] = facing }
--   pumps   = { [cell] = true | false }   has power, as last seen
--   pumpFacing = { [cell] = "E" | "S" }   the pipe it stands along
--
-- An admin builds for free and anywhere; a player (sandbox PlayersBuild)
-- needs a pipe wrench and the item, stands next to the place and gets the
-- item back when taking a thing apart. Anything but a radiator also takes
-- the head or staff of a heat supply organization (DelHeat.isService).
--
-- media/lua/server/ is also executed by connected clients, hence the guard
-- (see E:\mods\CLAUDE.md).
if isClient() then return end

require "DH_Shared"

local MODULE = DelHeat.MODULE
local PIPE, PUMP, INLET = DelHeat.PIPE, DelHeat.PUMP, DelHeat.INLET
local RADIATOR, BOILER, INTAKE = DelHeat.RADIATOR, DelHeat.BOILER, DelHeat.INTAKE
local SUPPORT, TAP, COLD = DelHeat.SUPPORT, DelHeat.TAP, DelHeat.COLD
local HOT_WATER, COLD_WATER = DelHeat.HOT_WATER, DelHeat.COLD_WATER

local Commands = {}

-- Worked out from the state, not saved; rebuilt whenever the network or a
-- pump's power changes.
--   feeds[radiator] = { boiler anchor, ... }   load[boiler] = radiators fed
--   supply[boiler] = working intakes that reach it
--   heat[cell], water[cell] = cells the hot / the intake water would still go
--   inlets[heat unit] = { boiler anchor, ... } for those hot water reaches
--   reached[intake] = boilers its water arrives at
local net = { feeds = {}, load = {}, supply = {}, heat = {}, water = {}, inlets = {}, reached = {} }
local dirty = true
-- Radiator levels as last sent to the clients.
local sentLevels = {}

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function log(msg)
	print("DelHeat: " .. msg)
	writeLog("DelHeat", msg)
end

local function state()
	local s = ModData.getOrCreate(DelHeat.STATE_KEY)
	for _, name in ipairs({ "nodes", "cells", "boilers", "intakes", "rads", "inlets", "pumps", "pumpFacing", "taps" }) do
		if type(s[name]) ~= "table" then s[name] = {} end
	end
	return s
end

local function reply(player, command, args)
	sendServerCommand(player, MODULE, command, args or {})
end

-- The client renders the text in its own language.
local function notify(player, key, arg1, arg2)
	reply(player, "notify", { key = key, arg1 = arg1, arg2 = arg2 })
end

local function coords(args, xName, yName)
	local x, y, z = tonumber(args[xName or "x"]), tonumber(args[yName or "y"]), tonumber(args.z)
	if not x or not y or not z then return nil end
	return math.floor(x), math.floor(y), math.floor(z)
end

local function oneOf(list, value)
	for _, v in ipairs(list) do
		if v == value then return v end
	end
	return nil
end

local function round1(value)
	return math.floor((tonumber(value) or 0) * 10 + 0.5) / 10
end

-- Air temperature the water cools down to.
local function ambient()
	local climate = getClimateManager()
	local air = climate and climate:getTemperature() or 10
	return math.max(5, math.min(25, air))
end

local function hasPower(square)
	return square:haveElectricity() or square:hasGridPower()
end

local isWater = DelHeat.isWater

-- Cells of a structure anchored at x, y, z.
local function structCells(x, y, z, size)
	local out = {}
	for dy = 0, size.h - 1 do
		for dx = 0, size.w - 1 do
			table.insert(out, { x = x + dx, y = y + dy, z = z, dx = dx, dy = dy })
		end
	end
	return out
end

-- ---------------------------------------------------------------------------
-- The builder: rights, tool, items
-- ---------------------------------------------------------------------------

-- Of a part by its name in DelHeat.ITEM: "admin", "player", or nil after
-- telling the player why not.
local function builderOf(player, name)
	if DelHeat.isAdmin(player) then return "admin" end
	if not DelHeat.playersBuild() then
		notify(player, "IGUI_DelHeat_NoRights")
		return nil
	end
	if DelHeat.needsService(name) and not DelHeat.isService(player) then
		notify(player, "IGUI_DelHeat_NotService")
		return nil
	end
	if not DelHeat.hasTool(player) then
		notify(player, "IGUI_DelHeat_NeedTool")
		return nil
	end
	return "player"
end

local function near(player, x, y, z, size)
	if math.abs(math.floor(player:getZ()) - z) > 1 then return false end
	return DelHeat.distanceTo(x, y, size or { w = 1, h = 1 }, player:getX(), player:getY()) <= DelHeat.BUILD_REACH
end

-- The square of a cell. One in the air, where nothing ever was, is made for
-- a pipe the way vanilla makes it for a floor built upstairs
-- (ISBuildIsoEntity:create); nil when the place is not loaded.
local function squareAt(x, y, z, make)
	local square = getCell():getGridSquare(x, y, z)
	if not square and make and z > 0 and getWorld():isValidSquare(x, y, z) then
		square = getCell():createNewGridSquare(x, y, z, true)
		if square then square:EnsureSurroundNotNull() end
	end
	return square
end

-- Somebody else's safehouse.
local function foreign(player, square)
	return square ~= nil and SafeHouse.isSafeHouse(square, player:getUsername(), true) ~= nil
end

local function takeItems(player, fullType, count)
	local items = DelHeat.itemsOf(player, fullType)
	local taken = 0
	for i = 0, items:size() - 1 do
		if taken >= count then break end
		local item = items:get(i)
		local container = item:getContainer() or player:getInventory()
		player:removeFromHands(item)
		container:DoRemoveItem(item)
		sendRemoveItemFromContainer(container, item)
		taken = taken + 1
	end
	return taken
end

local function giveItems(player, fullType, count)
	local inventory = player:getInventory()
	for _ = 1, count do
		local item = instanceItem(fullType)
		if item then
			inventory:AddItem(item)
			sendAddItemToContainer(inventory, item)
		end
	end
end

-- ---------------------------------------------------------------------------
-- The network
-- ---------------------------------------------------------------------------

local function pumpWorks(s, key, needsPower)
	return not needsPower or s.pumps[key] == true
end

local function intakeWorks(intake, needsPower)
	return not needsPower or intake.powered == true
end

-- What a side of the cell takes (DelHeat.sideMedium): nil, "h", "c", "*".
local function sideAt(s, key, bit)
	local kind = s.nodes[key]
	if not kind then return nil end
	if kind == BOILER or kind == INTAKE then
		local anchor = s.cells[key]
		if not anchor then return nil end
		local ax, ay = DelHeat.unkey(anchor)
		local x, y = DelHeat.unkey(key)
		local boiler = s.boilers[anchor]
		return DelHeat.sideMedium(kind, boiler and boiler.facing, x - ax, y - ay, bit)
	end
	return DelHeat.sideMedium(kind, s.pumpFacing[key], 0, 0, bit)
end

local function carries(kind)
	return DelHeat.kindMedium(kind) ~= nil
end

-- Water of a medium ("h" from a boiler, "c" from an intake) leaves the start
-- cells with `reach` cells ahead of it and runs through the pipes, pumps and
-- units of its medium; a working pump on the way sends it on for pumpReach
-- more. In the plane it passes only where both sides the cells share let
-- its medium through; up and down, between cells whose medium lets it.
-- Returns best[cell] = the most cells still ahead of the water there, and
-- the structures (by anchor) the water arrives at.
local function flood(s, starts, reach, pumpReach, needsPower, medium)
	local nodes = s.nodes
	local best, touched, queue, head = {}, {}, {}, 1
	for _, cell in ipairs(starts) do
		local key = DelHeat.key(cell.x, cell.y, cell.z)
		best[key] = reach
		queue[#queue + 1] = key
	end
	local function enter(nkey, left)
		local kind = nodes[nkey]
		if carries(kind) then
			local ahead = left - 1
			if kind == PUMP and ahead < pumpReach and pumpWorks(s, nkey, needsPower) then
				ahead = pumpReach
			end
			if (best[nkey] or -1) < ahead then
				best[nkey] = ahead
				queue[#queue + 1] = nkey
			end
		elseif kind == BOILER or kind == INTAKE then
			local anchor = s.cells[nkey]
			if anchor then touched[anchor] = true end
		end
	end
	while head <= #queue do
		local key = queue[head]
		head = head + 1
		local left = best[key]
		if left > 0 then
			local x, y, z = DelHeat.unkey(key)
			for _, dir in ipairs(DelHeat.DIRS) do
				if DelHeat.lets(sideAt(s, key, dir.bit), medium) then
					local nkey = DelHeat.key(x + dir.dx, y + dir.dy, z)
					if DelHeat.lets(sideAt(s, nkey, dir.back), medium) then enter(nkey, left) end
				end
			end
			if DelHeat.lets(DelHeat.kindMedium(nodes[key]), medium) then
				for dz = -1, 1, 2 do
					local nkey = DelHeat.key(x, y, z + dz)
					if DelHeat.lets(DelHeat.kindMedium(nodes[nkey]), medium) then enter(nkey, left) end
				end
			end
		end
	end
	return best, touched
end

local function rebuild(s)
	local needsPower = DelHeat.pumpNeedsPower()
	local pumpReach = DelHeat.pumpReach()
	local radius, floors = DelHeat.inletRadius(), DelHeat.INLET_FLOORS
	local feeds, load, supply, heat, water, inlets, reached = {}, {}, {}, {}, {}, {}, {}

	local rads = {}
	for key, _ in pairs(s.rads) do
		local x, y, z = DelHeat.unkey(key)
		if x then table.insert(rads, { key = key, x = x, y = y, z = z }) end
	end

	-- Hot water: boiler -> pipes -> heat units -> the radiators around them.
	for bkey, boiler in pairs(s.boilers) do
		local bx, by, bz = DelHeat.unkey(bkey)
		local best = flood(s, structCells(bx, by, bz, DelHeat.sizeOf(BOILER, boiler.facing)),
			DelHeat.boilerReach(), pumpReach, needsPower, HOT_WATER)
		local fed, count = {}, 0
		for key, ahead in pairs(best) do
			if (heat[key] or -1) < ahead then heat[key] = ahead end
			if s.nodes[key] == INLET then
				if not inlets[key] then inlets[key] = {} end
				table.insert(inlets[key], bkey)
				local ix, iy, iz = DelHeat.unkey(key)
				for _, rad in ipairs(rads) do
					if not fed[rad.key] and math.abs(rad.x - ix) <= radius and math.abs(rad.y - iy) <= radius
						and math.abs(rad.z - iz) <= floors then
						fed[rad.key] = true
						count = count + 1
						if not feeds[rad.key] then feeds[rad.key] = {} end
						table.insert(feeds[rad.key], bkey)
					end
				end
			end
		end
		load[bkey] = count
	end

	-- Cold water: working intake -> pipes -> the boilers it arrives at.
	for ikey, intake in pairs(s.intakes) do
		if intakeWorks(intake, needsPower) then
			local ix, iy, iz = DelHeat.unkey(ikey)
			local best, touched = flood(s, structCells(ix, iy, iz, DelHeat.sizeOf(INTAKE)),
				DelHeat.intakeReach(), pumpReach, needsPower, COLD_WATER)
			for key, ahead in pairs(best) do
				if (water[key] or -1) < ahead then water[key] = ahead end
			end
			local count = 0
			for anchor, _ in pairs(touched) do
				if s.boilers[anchor] then
					supply[anchor] = (supply[anchor] or 0) + 1
					count = count + 1
				end
			end
			reached[ikey] = count
		end
	end

	net = { feeds = feeds, load = load, supply = supply, heat = heat, water = water, inlets = inlets,
		reached = reached }
	dirty = false
end

local function network(s)
	if dirty then rebuild(s) end
	return net
end

-- Heat level of every radiator a heat unit serves (0 while the water is cold).
local function levels(s)
	local n = network(s)
	local out = {}
	for key, boilers in pairs(n.feeds) do
		local level = 0
		for _, bkey in ipairs(boilers) do
			local boiler = s.boilers[bkey]
			if boiler then level = math.max(level, DelHeat.heatLevel(boiler.temp)) end
		end
		out[key] = level
	end
	return out
end

local function sameLevels(a, b)
	for key, level in pairs(a) do
		if b[key] ~= level then return false end
	end
	for key, _ in pairs(b) do
		if a[key] == nil then return false end
	end
	return true
end

local function statusOf(s)
	local n = network(s)
	local needsPower = DelHeat.pumpNeedsPower()
	local boilers, pumps, intakes = {}, {}, {}
	for key, boiler in pairs(s.boilers) do
		boilers[key] = {
			facing = boiler.facing,
			fuel = round1(boiler.fuel),
			water = math.floor((tonumber(boiler.water) or 0) + 0.5),
			temp = math.floor((tonumber(boiler.temp) or 0) + 0.5),
			on = boiler.on == true,
			load = n.load[key] or 0,
			supply = n.supply[key] or 0,
		}
	end
	for key, _ in pairs(s.pumps) do
		pumps[key] = pumpWorks(s, key, needsPower)
	end
	for key, intake in pairs(s.intakes) do
		intakes[key] = intakeWorks(intake, needsPower)
	end
	local inlets = {}
	for key, _ in pairs(n.inlets) do
		inlets[key] = true
	end
	local taps = {}
	for key, tap in pairs(s.taps) do
		taps[key] = { fed = n.water[key] ~= nil, water = math.floor((tonumber(tap.water) or 0) + 0.5) }
	end
	return { boilers = boilers, pumps = pumps, intakes = intakes, inlets = inlets, taps = taps }
end

-- To everyone; the heat only when it changed (or forced).
local function pushHeat(s, force)
	local now = levels(s)
	if not force and sameLevels(now, sentLevels) then return end
	sentLevels = now
	sendServerCommand(MODULE, "heat", { levels = now })
end

local function pushStatus(s)
	sendServerCommand(MODULE, "status", statusOf(s))
end

-- After any change of the network.
local function changed(s)
	dirty = true
	pushHeat(s, false)
	pushStatus(s)
end

-- ---------------------------------------------------------------------------
-- World objects: the picture of a cell is rebuilt from the state.
-- ---------------------------------------------------------------------------

-- Sprites the cell should show, bottom first.
local function wantedSprites(s, x, y, z)
	local key = DelHeat.key(x, y, z)
	local kind = s.nodes[key]
	if not kind then return {} end
	if kind == BOILER or kind == INTAKE then
		local anchor = s.cells[key]
		if not anchor then return {} end
		local ax, ay = DelHeat.unkey(anchor)
		if kind == INTAKE then return { DelHeat.intakeSprite(x - ax, y - ay) } end
		local boiler = s.boilers[anchor]
		if not boiler then return {} end
		return { DelHeat.boilerSprite(boiler.facing, x - ax, y - ay) }
	end
	if kind == RADIATOR then return { DelHeat.radiatorSprite(s.rads[key]) } end
	if kind == SUPPORT then return { DelHeat.supportSprite() } end
	local list = {}
	local medium = DelHeat.kindMedium(kind)
	-- A pump's sprite carries its own length of pipe; a pipe and a unit show
	-- an arm to every neighbour that joins it from this side.
	if kind ~= PUMP then
		local mask = 0
		for _, dir in ipairs(DelHeat.DIRS) do
			if DelHeat.joins(medium, sideAt(s, DelHeat.key(x + dir.dx, y + dir.dy, z), dir.back)) then
				mask = mask + dir.bit
			end
		end
		if DelHeat.isPipeKind(kind) or mask > 0 then table.insert(list, DelHeat.pipeSprite(mask, medium)) end
	end
	-- The pipe goes on up to the cell above, in the colour of the pipe.
	local above = DelHeat.kindMedium(s.nodes[DelHeat.key(x, y, z + 1)])
	if DelHeat.joins(medium, above) then
		table.insert(list, DelHeat.riserSprite(medium == DelHeat.ANY_WATER and above or medium))
	end
	if kind == PUMP then table.insert(list, DelHeat.pumpSprite(s.pumpFacing[key])) end
	if kind == INLET then table.insert(list, DelHeat.inletSprite(s.inlets[key])) end
	if kind == TAP then table.insert(list, DelHeat.tapSprite(s.taps[key] and s.taps[key].facing)) end
	return list
end

local function ourObjects(square)
	local out = {}
	local objects = square:getObjects()
	for i = 0, objects:size() - 1 do
		local object = objects:get(i)
		local sprite = object:getSprite()
		local name = sprite and sprite:getName()
		if DelHeat.parseSprite(name) then table.insert(out, { object = object, name = name }) end
	end
	return out
end

-- false when the square is not loaded (its picture stays as it was).
local function redraw(s, x, y, z)
	local square = getCell():getGridSquare(x, y, z)
	if not square then return false end
	local wanted = wantedSprites(s, x, y, z)
	local current = ourObjects(square)
	local same = #wanted == #current
	if same then
		for i, name in ipairs(wanted) do
			if current[i].name ~= name then same = false end
		end
	end
	if same then return true end
	for _, entry in ipairs(current) do
		square:transmitRemoveItemFromSquare(entry.object)
	end
	for _, name in ipairs(wanted) do
		local object = IsoObject.new(getCell(), square, name)
		square:AddTileObject(object)
		object:transmitCompleteItemToClients()
	end
	square:RecalcProperties()
	return true
end

-- Redraws the cells, their neighbours and the cell below each (its riser),
-- each once.
local function redrawAround(s, cells)
	local done = {}
	for _, cell in ipairs(cells) do
		local spots = { { 0, 0, 0 }, { 0, -1, 0 }, { 1, 0, 0 }, { 0, 1, 0 }, { -1, 0, 0 }, { 0, 0, -1 } }
		for _, d in ipairs(spots) do
			local x, y, z = cell.x + d[1], cell.y + d[2], cell.z + d[3]
			local key = DelHeat.key(x, y, z)
			if not done[key] then
				done[key] = true
				redraw(s, x, y, z)
			end
		end
	end
end

-- nil when a pipe, a radiator, a heat unit or a support (name) may go on the square,
-- otherwise a translation key. A pipe above the ground wants no floor.
local function blockedThin(s, square, x, y, z, name)
	if not square then return "IGUI_DelHeat_NotLoaded" end
	if s.nodes[DelHeat.key(x, y, z)] then return "IGUI_DelHeat_Occupied" end
	if DelHeat.needsFloor(name, z) and not square:getFloor() then return "IGUI_DelHeat_NoFloor" end
	return nil
end

-- The same for a device that stands in the way.
local function blockedSolid(s, square, x, y, z)
	local why = blockedThin(s, square, x, y, z)
	if why then return why end
	if square:isSolid() or square:isSolidTrans() or square:getVehicleContainer() or isWater(square) then
		return "IGUI_DelHeat_Occupied"
	end
	return nil
end

local path = DelHeat.path

local function waterNear(x, y, z, size)
	local range = DelHeat.WATER_RANGE
	for wy = y - range, y + size.h - 1 + range do
		for wx = x - range, x + size.w - 1 + range do
			if isWater(getCell():getGridSquare(wx, wy, z)) then return true end
		end
	end
	return false
end

-- ---------------------------------------------------------------------------
-- Commands: building
-- ---------------------------------------------------------------------------

-- { x, y, z, kind = "pipe" | "radiator" | "inlet" | "pump" | "boiler" | "intake", facing }
-- For a boiler and an intake the clicked cell is the one next to the
-- anchor's south-east: the middle of a boiler's front, the near corner of
-- an intake.
function Commands.place(player, args)
	local x, y, z = coords(args)
	local name = args.kind
	local itemType = DelHeat.ITEM[name]
	if not x or not itemType then return end
	local who = builderOf(player, name)
	if not who then return end
	local s = state()

	local structure = name == "boiler" or name == "intake"
	local facing, size, cells
	if name == "boiler" then
		facing = oneOf(DelHeat.BOILER_FACINGS, args.facing)
		if not facing then return end
	elseif name == "radiator" or name == "inlet" or name == "tap" then
		facing = oneOf(DelHeat.RADIATOR_FACINGS, args.facing) or "N"
	elseif name == "pump" then
		facing = oneOf(DelHeat.PUMP_FACINGS, args.facing) or "E"
	end
	if structure then
		x, y, size = DelHeat.anchorOf(name, facing, x, y)
		cells = structCells(x, y, z, size)
	else
		cells = { { x = x, y = y, z = z, dx = 0, dy = 0 } }
	end

	for _, cell in ipairs(cells) do
		local square = squareAt(cell.x, cell.y, cell.z, DelHeat.isPipeName(name))
		local why
		if DelHeat.isPipeName(name) or name == "radiator" or name == "inlet" or name == "support" or name == "tap" then
			why = blockedThin(s, square, cell.x, cell.y, cell.z, name)
		else
			why = blockedSolid(s, square, cell.x, cell.y, cell.z)
		end
		-- Walls inside the footprint; those along its north and west edge are fine.
		if not why and ((cell.dx > 0 and square:has(IsoFlagType.collideW))
			or (cell.dy > 0 and square:has(IsoFlagType.collideN))) then
			why = "IGUI_DelHeat_Occupied"
		end
		if not why and who == "player" and foreign(player, square) then why = "IGUI_DelHeat_Safehouse" end
		if why then return notify(player, why) end
	end
	if who == "player" then
		if not near(player, x, y, z, size) then return notify(player, "IGUI_DelHeat_ComeCloser") end
		if name == "intake" and not waterNear(x, y, z, size) then return notify(player, "IGUI_DelHeat_NeedWater") end
		if takeItems(player, itemType, 1) < 1 then return notify(player, "IGUI_DelHeat_NeedItem") end
	end

	local key = DelHeat.key(x, y, z)
	if name == "boiler" then
		s.boilers[key] = { facing = facing, fuel = 0, water = 0, temp = ambient(), on = false, by = player:getUsername() }
	elseif name == "intake" then
		s.intakes[key] = { powered = hasPower(getCell():getGridSquare(x, y, z)), by = player:getUsername() }
	end
	for _, cell in ipairs(cells) do
		local ckey = DelHeat.key(cell.x, cell.y, cell.z)
		if name == "boiler" then
			s.nodes[ckey], s.cells[ckey] = BOILER, key
		elseif name == "intake" then
			s.nodes[ckey], s.cells[ckey] = INTAKE, key
		elseif name == "pump" then
			s.nodes[ckey] = PUMP
			s.pumps[ckey] = hasPower(getCell():getGridSquare(x, y, z))
			s.pumpFacing[ckey] = facing
		elseif name == "inlet" then
			s.nodes[ckey] = INLET
			s.inlets[ckey] = facing
		elseif name == "tap" then
			s.nodes[ckey] = TAP
			s.taps[ckey] = { facing = facing, water = 0, fixtures = 0, fillable = 0, by = player:getUsername() }
		elseif name == "radiator" then
			s.nodes[ckey] = RADIATOR
			s.rads[ckey] = facing
		elseif name == "support" then
			s.nodes[ckey] = SUPPORT
		elseif name == "coldpipe" then
			s.nodes[ckey] = COLD
		else
			s.nodes[ckey] = PIPE
		end
	end
	redrawAround(s, cells)
	changed(s)
	notify(player, "IGUI_DelHeat_Placed")
	log(string.format("Placed: %s (%s) %s at %s", player:getUsername(), who, name, key))
end

-- The run of a line command: who, state, cells; nil after telling why not.
local function lineOf(player, args, name)
	local who = builderOf(player, name)
	if not who then return nil end
	local x1, y1, z = coords(args, "x1", "y1")
	local x2, y2 = coords(args, "x2", "y2")
	if not x1 or not x2 then return nil end
	if math.abs(x2 - x1) + math.abs(y2 - y1) + 1 > DelHeat.MAX_LINE then
		notify(player, "IGUI_DelHeat_LineTooLong", tostring(DelHeat.MAX_LINE))
		return nil
	end
	-- Either end will do: a run out into the air is laid from where it starts.
	if who == "player" and not near(player, x2, y2, z) and not near(player, x1, y1, z) then
		notify(player, "IGUI_DelHeat_ComeCloser")
		return nil
	end
	return who, state(), path(x1, y1, x2, y2, z)
end

-- { x1, y1, x2, y2, z, kind = "pipe" | "coldpipe" }: pipes along x, then
-- along y. Cells that already hold something are passed over; the run stops
-- at the first cell that takes no pipe, or when the player's pipes run out.
function Commands.line(player, args)
	local name = args.kind == "coldpipe" and "coldpipe" or "pipe"
	local kind = name == "coldpipe" and COLD or PIPE
	local who, s, cells = lineOf(player, args, name)
	if not who then return end
	local have = who == "player" and DelHeat.countOf(player, DelHeat.ITEM[name]) or nil
	local laid, stopped = {}, nil
	for _, cell in ipairs(cells) do
		local key = DelHeat.key(cell.x, cell.y, cell.z)
		if not s.nodes[key] then
			local square = squareAt(cell.x, cell.y, cell.z, true)
			local why = blockedThin(s, square, cell.x, cell.y, cell.z, name)
			if not why and who == "player" and foreign(player, square) then why = "IGUI_DelHeat_Safehouse" end
			if not why and have and #laid >= have then why = "IGUI_DelHeat_NeedItem" end
			if why then
				stopped = why
				break
			end
			s.nodes[key] = kind
			table.insert(laid, cell)
		end
	end
	if #laid > 0 then
		if who == "player" then takeItems(player, DelHeat.ITEM[name], #laid) end
		redrawAround(s, laid)
		changed(s)
		log(string.format("Pipes laid: %s (%s) %d to %d,%d,%d", player:getUsername(), who, #laid,
			cells[#cells].x, cells[#cells].y, cells[#cells].z))
	end
	if stopped then
		notify(player, "IGUI_DelHeat_LineStopped", tostring(#laid), stopped)
	else
		notify(player, "IGUI_DelHeat_LineLaid", tostring(#laid))
	end
end

-- { x1, y1, x2, y2, z }: takes the pipes of both kinds off the same run;
-- devices stay.
function Commands.unline(player, args)
	local who, s, cells = lineOf(player, args, "pipe")
	if not who then return end
	local taken, hot, cold = {}, 0, 0
	for _, cell in ipairs(cells) do
		local key = DelHeat.key(cell.x, cell.y, cell.z)
		local kind = s.nodes[key]
		if DelHeat.isPipeKind(kind) then
			-- An unloaded square would keep its sprite: stop there.
			local square = getCell():getGridSquare(cell.x, cell.y, cell.z)
			if not square or (who == "player" and foreign(player, square)) then break end
			s.nodes[key] = nil
			table.insert(taken, cell)
			if kind == COLD then cold = cold + 1 else hot = hot + 1 end
		end
	end
	if #taken > 0 then
		if who == "player" then
			if hot > 0 then giveItems(player, DelHeat.ITEM.pipe, hot) end
			if cold > 0 then giveItems(player, DelHeat.ITEM.coldpipe, cold) end
		end
		redrawAround(s, taken)
		changed(s)
		log(string.format("Pipes removed: %s (%s) %d to %d,%d,%d", player:getUsername(), who, #taken,
			cells[#cells].x, cells[#cells].y, cells[#cells].z))
	end
	notify(player, "IGUI_DelHeat_LineRemoved", tostring(#taken))
end

-- { x, y, z (any cell) }: removes what stands there, a structure whole. A
-- player gets the item back.
function Commands.remove(player, args)
	local x, y, z = coords(args)
	if not x then return end
	local s = state()
	local key = DelHeat.key(x, y, z)
	local square = getCell():getGridSquare(x, y, z)
	local kind = s.nodes[key]
	-- Sprites without a record are the admin's to clear.
	if not kind and not DelHeat.isAdmin(player) then return end
	local who = builderOf(player, DelHeat.NAME[kind or PIPE])
	if not who then return end
	local cells = { { x = x, y = y, z = z } }
	local anchor, size = s.cells[key], nil
	if anchor and s.boilers[anchor] then
		size = DelHeat.sizeOf(BOILER, s.boilers[anchor].facing)
	elseif anchor and s.intakes[anchor] then
		size = DelHeat.sizeOf(INTAKE)
	else
		-- Sprites without a record (the state rolled back without them): the
		-- admin clears them, nothing is given back.
		local node = DelHeat.nodeAt(square)
		if not kind and (not node or who ~= "admin") then return end
		anchor = nil
		if not kind and (node.kind == BOILER or node.kind == INTAKE) then
			anchor, size = node.key, DelHeat.sizeOf(node.kind, node.facing)
		end
	end
	local ax, ay, az = x, y, z
	if anchor then
		ax, ay, az = DelHeat.unkey(anchor)
		cells = structCells(ax, ay, az, size)
	end
	if who == "player" then
		if not near(player, ax, ay, az, size) then return notify(player, "IGUI_DelHeat_ComeCloser") end
		for _, cell in ipairs(cells) do
			if foreign(player, getCell():getGridSquare(cell.x, cell.y, cell.z)) then
				return notify(player, "IGUI_DelHeat_Safehouse")
			end
		end
	end
	if anchor then
		s.boilers[anchor] = nil
		s.intakes[anchor] = nil
	end
	for _, cell in ipairs(cells) do
		local ckey = DelHeat.key(cell.x, cell.y, cell.z)
		s.nodes[ckey] = nil
		s.cells[ckey] = nil
		s.rads[ckey] = nil
		s.inlets[ckey] = nil
		s.taps[ckey] = nil
		s.pumps[ckey] = nil
		s.pumpFacing[ckey] = nil
	end
	local itemType = kind and DelHeat.ITEM[DelHeat.NAME[kind] or ""]
	if who == "player" and itemType then giveItems(player, itemType, 1) end
	redrawAround(s, cells)
	changed(s)
	notify(player, "IGUI_DelHeat_Removed")
	log(string.format("Removed: %s (%s) %s at %s", player:getUsername(), who, tostring(kind), key))
end

-- ---------------------------------------------------------------------------
-- Commands: admin
-- ---------------------------------------------------------------------------

-- { x, y, z (any boiler cell), what = "fuel" | "water" }: to the brim.
function Commands.fill(player, args)
	if not DelHeat.isAdmin(player) then return end
	local x, y, z = coords(args)
	if not x then return end
	local s = state()
	local boiler = s.boilers[s.cells[DelHeat.key(x, y, z)] or ""]
	if not boiler then return end
	if args.what == "water" then
		boiler.water = DelHeat.waterCapacity()
		notify(player, "IGUI_DelHeat_WaterFilled", tostring(boiler.water))
	else
		boiler.fuel = DelHeat.fuelCapacity()
		notify(player, "IGUI_DelHeat_Refuelled", tostring(round1(boiler.fuel)))
	end
	pushStatus(s)
	log(string.format("Filled (%s): %s at %s", tostring(args.what), player:getUsername(), DelHeat.key(x, y, z)))
end

-- ---------------------------------------------------------------------------
-- Commands: anyone
-- ---------------------------------------------------------------------------

-- The hottest water among these boilers, or nil.
local function hottest(s, boilers)
	local temp
	for _, bkey in ipairs(boilers or {}) do
		local boiler = s.boilers[bkey]
		local t = boiler and tonumber(boiler.temp)
		if t and (not temp or t > temp) then temp = t end
	end
	return temp and math.floor(temp + 0.5) or nil
end

-- { x, y, z (any cell of the thing) }: everything its window shows.
--   key (a structure's anchor), kind (nil when the state holds nothing there),
--   heat, water = cells the boiler's / the intake's water would still go from
--   a pipe, a pump or a heat unit (nil when it does not get there), and by kind:
--   boiler:   facing, fuel, water (litres), temp, on, load, supply, by
--   intake:   works, boilers (its water arrives at), by
--   pump:     works
--   inlet:    fed, temp (of the hottest water reaching it), rads (in its radius)
--   radiator: fed (a heat unit with hot water in range), temp, level
function Commands.info(player, args)
	local x, y, z = coords(args)
	if not x then return end
	local s = state()
	local n = network(s)
	local key = DelHeat.key(x, y, z)
	local kind = s.nodes[key]
	local needsPower = DelHeat.pumpNeedsPower()
	local out = { key = key, kind = kind }
	if kind == BOILER or kind == INTAKE then
		local anchor = s.cells[key]
		out.key = anchor or key
		local boiler = kind == BOILER and anchor and s.boilers[anchor]
		local intake = kind == INTAKE and anchor and s.intakes[anchor]
		if boiler then
			out.facing = boiler.facing
			out.fuel = round1(boiler.fuel)
			out.litres = math.floor((tonumber(boiler.water) or 0) + 0.5)
			out.temp = math.floor((tonumber(boiler.temp) or 0) + 0.5)
			out.on = boiler.on == true
			out.load = n.load[anchor] or 0
			out.supply = n.supply[anchor] or 0
			out.by = boiler.by
		elseif intake then
			out.works = intakeWorks(intake, needsPower)
			out.boilers = n.reached[anchor] or 0
			out.by = intake.by
		end
	elseif kind == RADIATOR then
		out.fed = n.feeds[key] ~= nil
		out.temp = hottest(s, n.feeds[key])
		out.level = out.temp and DelHeat.heatLevel(out.temp) or 0
	elseif kind then
		out.heat, out.water = n.heat[key], n.water[key]
		if kind == PUMP then
			out.works = pumpWorks(s, key, needsPower)
		elseif kind == TAP then
			local tap = s.taps[key] or {}
			out.fed = n.water[key] ~= nil
			out.litres = math.floor((tonumber(tap.water) or 0) + 0.5)
			out.capacity = DelHeat.tapCapacity()
			out.fixtures, out.fillable = tap.fixtures or 0, tap.fillable or 0
			out.clean = DelHeat.tapClean()
			out.by = tap.by
		elseif kind == INLET then
			out.fed = n.inlets[key] ~= nil
			out.temp = hottest(s, n.inlets[key])
			local radius, floors, count = DelHeat.inletRadius(), DelHeat.INLET_FLOORS, 0
			for rkey, _ in pairs(s.rads) do
				local rx, ry, rz = DelHeat.unkey(rkey)
				if rx and math.abs(rx - x) <= radius and math.abs(ry - y) <= radius and math.abs(rz - z) <= floors then
					count = count + 1
				end
			end
			out.rads = count
		end
	end
	reply(player, "info", out)
end

-- The boiler under the cell, when the player stands near enough.
local function boilerNear(s, player, args)
	local x, y, z = coords(args)
	if not x then return nil end
	local anchor = s.cells[DelHeat.key(x, y, z)]
	local boiler = anchor and s.boilers[anchor]
	if not boiler then return nil end
	local ax, ay, az = DelHeat.unkey(anchor)
	if math.floor(player:getZ()) ~= az or DelHeat.distanceTo(ax, ay, DelHeat.sizeOf(BOILER, boiler.facing),
		player:getX(), player:getY()) > DelHeat.REACH then
		notify(player, "IGUI_DelHeat_TooFar")
		return nil
	end
	return boiler, anchor
end

-- { x, y, z (any boiler cell) }: fire on / off.
function Commands.toggle(player, args)
	local s = state()
	local boiler, anchor = boilerNear(s, player, args)
	if not boiler then return end
	boiler.on = not boiler.on
	pushStatus(s)
	notify(player, boiler.on and "IGUI_DelHeat_SwitchedOn" or "IGUI_DelHeat_SwitchedOff")
	log(string.format("Boiler %s: %s at %s", boiler.on and "on" or "off", player:getUsername(), anchor))
end

-- { x, y, z (any boiler cell), ids = { item id, ... } }: the items go into
-- the furnace until it is full.
function Commands.load(player, args)
	local s = state()
	local boiler, anchor = boilerNear(s, player, args)
	if not boiler or type(args.ids) ~= "table" then return end
	local capacity = DelHeat.fuelCapacity()
	local fuelTable = DelHeat.fuelTable()
	local inventory = player:getInventory()
	local added = 0
	for _, id in ipairs(args.ids) do
		local room = capacity - (boiler.fuel or 0)
		if room <= 0.01 then break end
		local item = tonumber(id) and inventory:getItemWithIDRecursiv(tonumber(id))
		local value, how = DelHeat.fuelValue(item, fuelTable)
		if value and how == "item" then
			if value <= room + 0.01 then
				local container = item:getContainer() or inventory
				player:removeFromHands(item)
				container:DoRemoveItem(item)
				sendRemoveItemFromContainer(container, item)
				boiler.fuel = boiler.fuel + value
				added = added + value
			end
		elseif value and how == "drain" then
			local take = math.min(value, room)
			local left = item:getCurrentUsesFloat()
			item:setUsedDelta(math.max(0, left - left * take / value))
			item:syncItemFields()
			boiler.fuel = boiler.fuel + take
			added = added + take
		elseif value and how == "fluid" then
			local fluid = item:getFluidContainer()
			local litres = fluid:getAmount()
			local take = math.min(value, room)
			fluid:adjustAmount(math.max(0, litres - litres * take / value))
			item:syncItemFields()
			boiler.fuel = boiler.fuel + take
			added = added + take
		end
	end
	pushStatus(s)
	if added > 0 then
		notify(player, "IGUI_DelHeat_Loaded", tostring(round1(added)), tostring(round1(boiler.fuel)))
		log(string.format("Fuel: %s +%.1f at %s, now %.1f", player:getUsername(), added, anchor, boiler.fuel))
	elseif capacity - (boiler.fuel or 0) <= 0.01 then
		notify(player, "IGUI_DelHeat_Full")
	else
		notify(player, "IGUI_DelHeat_NoRoom")
	end
end

-- The client asks for the picture after it connects.
function Commands.sync(player)
	local s = state()
	reply(player, "heat", { levels = levels(s) })
	reply(player, "status", statusOf(s))
end

-- ---------------------------------------------------------------------------
-- Time
-- ---------------------------------------------------------------------------

local function everyMinute()
	local s = state()
	local n = network(s)
	local base, perRadiator = DelHeat.burnPerHour(), DelHeat.burnPerRadiator()
	local waterBase, waterPerRadiator = DelHeat.waterPerHour(), DelHeat.waterPerRadiator()
	local waterCapacity, intakeRate = DelHeat.waterCapacity(), DelHeat.intakeRate()
	local heatUp, coolDown = DelHeat.heatUpPerMinute(), DelHeat.coolDownPerMinute()
	local air = ambient()
	local any = false
	for key, boiler in pairs(s.boilers) do
		any = true
		local fuel, water = tonumber(boiler.fuel) or 0, tonumber(boiler.water) or 0
		local temp = tonumber(boiler.temp) or air
		local load = n.load[key] or 0
		water = math.min(waterCapacity, water + (n.supply[key] or 0) * intakeRate / 60)
		if boiler.on and fuel > 0 and water > 0 then
			fuel = math.max(0, fuel - (base + perRadiator * load) / 60)
			water = math.max(0, water - (waterBase + waterPerRadiator * load) / 60)
			temp = math.min(DelHeat.WATER_MAX, temp + heatUp)
		elseif temp > air then
			temp = math.max(air, temp - coolDown)
		else
			temp = air
		end
		boiler.fuel, boiler.water, boiler.temp = fuel, water, temp
	end
	if any then pushHeat(s, false) end
end

-- Power is read only where the square is loaded; elsewhere a pump or an
-- intake keeps the state it was last seen in.
-- ---------------------------------------------------------------------------
-- Water units
-- ---------------------------------------------------------------------------

-- A sink, a toilet, a bath, a shower: what vanilla lets a player plumb
-- (ISMoveableSpriteProps), with a tank of its own to fill. One plumbed to a
-- barrel upstairs is left to its barrel.
local function fixtureTank(object)
	local sprite = object:getSprite()
	local props = sprite and sprite:getProperties()
	if not props or not props:has(IsoFlagType.waterPiped) then return nil, false end
	if object:getUsesExternalWaterSource() then return nil, true end
	local tank = object:getFluidContainer()
	if not tank or tank:getCapacity() <= 0 then return nil, true end
	-- Mains water still on: it needs nothing.
	if object:getFluidCapacity() >= 10000 then return nil, true end
	return tank, true
end

-- Every ten game minutes: the tank takes in what the intake's water brings,
-- then tops up the plumbing within the radius. What a fixture really took is
-- measured on its tank, so one the game would not fill costs nothing.
local function serveTap(s, n, key, tap)
	local capacity = DelHeat.tapCapacity()
	local water = math.min(capacity, tonumber(tap.water) or 0)
	if n.water[key] ~= nil then water = math.min(capacity, water + DelHeat.intakeRate() / 6) end
	local x, y, z = DelHeat.unkey(key)
	local radius, floors = DelHeat.tapRadius(), DelHeat.INLET_FLOORS
	local fluid = DelHeat.tapClean() and FluidType.Water or FluidType.TaintedWater
	local fixtures, fillable = 0, 0
	local cell = getCell()
	for fz = z - floors, z + floors do
		for fy = y - radius, y + radius do
			for fx = x - radius, x + radius do
				local square = cell:getGridSquare(fx, fy, fz)
				if square then
					local objects = square:getObjects()
					for i = 0, objects:size() - 1 do
						local object = objects:get(i)
						local tank, fixture = fixtureTank(object)
						if fixture then fixtures = fixtures + 1 end
						if tank then
							fillable = fillable + 1
							local before = tank:getAmount()
							local give = math.min(tank:getCapacity() - before, water)
							if give >= 0.5 then
								object:emptyFluid()
								object:addFluid(fluid, before + give)
								object:transmitModData()
								water = water - math.max(0, tank:getAmount() - before)
							end
						end
					end
				end
			end
		end
	end
	local changed = math.floor(water) ~= math.floor(tonumber(tap.water) or 0)
		or fixtures ~= tap.fixtures or fillable ~= tap.fillable
	tap.water, tap.fixtures, tap.fillable = water, fixtures, fillable
	return changed
end

local function everyTenMinutes()
	local s = state()
	local any = false
	local n = network(s)
	for key, tap in pairs(s.taps) do
		any = true
		local x, y, z = DelHeat.unkey(key)
		-- An unloaded unit waits: there is nobody near to use the water.
		if x and getCell():getGridSquare(x, y, z) then serveTap(s, n, key, tap) end
	end
	for key, was in pairs(s.pumps) do
		any = true
		local x, y, z = DelHeat.unkey(key)
		local square = x and getCell():getGridSquare(x, y, z)
		if square then
			local now = hasPower(square)
			if now ~= was then
				s.pumps[key] = now
				dirty = true
			end
		end
	end
	for key, intake in pairs(s.intakes) do
		any = true
		local x, y, z = DelHeat.unkey(key)
		local square = x and getCell():getGridSquare(x, y, z)
		if square then
			local now = hasPower(square)
			if now ~= intake.powered then
				intake.powered = now
				dirty = true
			end
		end
	end
	for _, _ in pairs(s.boilers) do
		any = true
		break
	end
	if not any then return end
	pushHeat(s, false)
	pushStatus(s)
end

local function onInitGlobalModData()
	state()
	dirty = true
end

Events.OnInitGlobalModData.Add(onInitGlobalModData)
Events.EveryOneMinute.Add(everyMinute)
Events.EveryTenMinutes.Add(everyTenMinutes)

local function onClientCommand(module, command, player, args)
	if module ~= MODULE then return end
	local handler = Commands[command]
	if not handler then return end
	handler(player, args or {})
end
Events.OnClientCommand.Add(onClientCommand)
