-- Delirium Heating - the server side: keeps the network, puts down and
-- removes its objects, burns the fuel, heats the water and tells the clients
-- which radiators are hot.
--
-- State: ModData "DelHeat_State". It is never transmitted whole (a town's
-- pipes are thousands of cells): the clients get the radiator heat levels
-- ("heat") and the boilers and pumps ("status") by command. It rolls back
-- with the world save, together with the objects and the fuel items, so
-- there is no file of our own.
--   nodes   = { ["x,y,z"] = "p" | "r" | "u" | "b" }
--   cells   = { [boiler cell] = boiler anchor }
--   boilers = { [anchor] = { facing, fuel, temp, on, by } }
--   rads    = { [cell] = facing }
--   pumps   = { [cell] = true | false }   has power, as last seen
--
-- media/lua/server/ is also executed by connected clients, hence the guard
-- (see E:\mods\CLAUDE.md).
if isClient() then return end

require "DH_Shared"

local MODULE = DelHeat.MODULE
local PIPE, RADIATOR, PUMP, BOILER = DelHeat.PIPE, DelHeat.RADIATOR, DelHeat.PUMP, DelHeat.BOILER

local Commands = {}

-- Worked out from the state, not saved: which boilers feed a radiator, how
-- many radiators a boiler feeds, how much further the water would go from a
-- cell. Rebuilt whenever the network or a pump's power changes.
local net = { feeds = {}, load = {}, reach = {} }
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
	if type(s.nodes) ~= "table" then s.nodes = {} end
	if type(s.cells) ~= "table" then s.cells = {} end
	if type(s.boilers) ~= "table" then s.boilers = {} end
	if type(s.rads) ~= "table" then s.rads = {} end
	if type(s.pumps) ~= "table" then s.pumps = {} end
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

-- ---------------------------------------------------------------------------
-- The network
-- ---------------------------------------------------------------------------

local function pumpWorks(s, key, needsPower)
	return not needsPower or s.pumps[key] == true
end

-- From every boiler the water travels boilerReach cells; a working pump on
-- the way sends it on for pumpReach more. best[cell] is the most cells still
-- ahead of the water there.
local function rebuild(s)
	local needsPower = DelHeat.pumpNeedsPower()
	local boilerReach, pumpReach = DelHeat.boilerReach(), DelHeat.pumpReach()
	local feeds, load, reach = {}, {}, {}
	local nodes = s.nodes
	for bkey, boiler in pairs(s.boilers) do
		local best, queue, head = {}, {}, 1
		local bx, by, bz = DelHeat.unkey(bkey)
		local size = DelHeat.BOILER_SIZE[boiler.facing] or DelHeat.BOILER_SIZE.S
		for dy = 0, size.h - 1 do
			for dx = 0, size.w - 1 do
				local key = DelHeat.key(bx + dx, by + dy, bz)
				best[key] = boilerReach
				queue[#queue + 1] = key
			end
		end
		while head <= #queue do
			local key = queue[head]
			head = head + 1
			local left = best[key]
			if left > 0 then
				local x, y, z = DelHeat.unkey(key)
				local around = {
					DelHeat.key(x, y - 1, z), DelHeat.key(x + 1, y, z), DelHeat.key(x, y + 1, z),
					DelHeat.key(x - 1, y, z), DelHeat.key(x, y, z + 1), DelHeat.key(x, y, z - 1),
				}
				for _, nkey in ipairs(around) do
					local kind = nodes[nkey]
					if kind and kind ~= BOILER then
						local ahead = left - 1
						if kind == PUMP and ahead < pumpReach and pumpWorks(s, nkey, needsPower) then
							ahead = pumpReach
						end
						if (best[nkey] or -1) < ahead then
							best[nkey] = ahead
							queue[#queue + 1] = nkey
						end
					end
				end
			end
		end
		local count = 0
		for key, ahead in pairs(best) do
			if (reach[key] or -1) < ahead then reach[key] = ahead end
			if nodes[key] == RADIATOR then
				count = count + 1
				if not feeds[key] then feeds[key] = {} end
				table.insert(feeds[key], bkey)
			end
		end
		load[bkey] = count
	end
	net = { feeds = feeds, load = load, reach = reach }
	dirty = false
end

local function network(s)
	if dirty then rebuild(s) end
	return net
end

-- Heat level of every radiator the water reaches (0 while the water is cold).
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
	local boilers, pumps = {}, {}
	for key, boiler in pairs(s.boilers) do
		boilers[key] = {
			facing = boiler.facing,
			fuel = round1(boiler.fuel),
			temp = math.floor((boiler.temp or 0) + 0.5),
			on = boiler.on == true,
			load = n.load[key] or 0,
		}
	end
	for key, _ in pairs(s.pumps) do
		pumps[key] = pumpWorks(s, key, needsPower)
	end
	return { boilers = boilers, pumps = pumps }
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
	if kind == BOILER then
		local anchor = s.cells[key]
		local boiler = anchor and s.boilers[anchor]
		if not boiler then return {} end
		local ax, ay = DelHeat.unkey(anchor)
		return { DelHeat.boilerSprite(boiler.facing, x - ax, y - ay) }
	end
	local mask = 0
	for _, dir in ipairs(DelHeat.DIRS) do
		if s.nodes[DelHeat.key(x + dir.dx, y + dir.dy, z)] then mask = mask + dir.bit end
	end
	local list = {}
	if kind == PIPE or mask > 0 then table.insert(list, DelHeat.pipeSprite(mask)) end
	if kind == RADIATOR then table.insert(list, DelHeat.radiatorSprite(s.rads[key])) end
	if kind == PUMP then table.insert(list, DelHeat.pumpSprite()) end
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

-- Redraws the cells and their neighbours, each once.
local function redrawAround(s, cells)
	local done = {}
	for _, cell in ipairs(cells) do
		local spots = { { 0, 0 }, { 0, -1 }, { 1, 0 }, { 0, 1 }, { -1, 0 } }
		for _, d in ipairs(spots) do
			local x, y = cell.x + d[1], cell.y + d[2]
			local key = DelHeat.key(x, y, cell.z)
			if not done[key] then
				done[key] = true
				redraw(s, x, y, cell.z)
			end
		end
	end
end

-- nil when a pipe or a radiator may go on the square, otherwise a
-- translation key.
local function blockedThin(s, square, x, y, z)
	if not square then return "IGUI_DelHeat_NotLoaded" end
	if s.nodes[DelHeat.key(x, y, z)] then return "IGUI_DelHeat_Occupied" end
	if not square:getFloor() then return "IGUI_DelHeat_NoFloor" end
	return nil
end

-- The same for a pump or a boiler cell: they stand in the way.
local function blockedSolid(s, square, x, y, z)
	local why = blockedThin(s, square, x, y, z)
	if why then return why end
	if square:isSolid() or square:isSolidTrans() or square:getVehicleContainer() then
		return "IGUI_DelHeat_Occupied"
	end
	return nil
end

-- Cells from (x1, y1) to (x2, y2): along x first, then along y.
local function path(x1, y1, x2, y2, z)
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

local function boilerCells(x, y, z, facing)
	local size = DelHeat.BOILER_SIZE[facing]
	local out = {}
	for dy = 0, size.h - 1 do
		for dx = 0, size.w - 1 do
			table.insert(out, { x = x + dx, y = y + dy, z = z, dx = dx, dy = dy })
		end
	end
	return out
end

-- ---------------------------------------------------------------------------
-- Commands: admin
-- ---------------------------------------------------------------------------

-- { x, y, z, kind = "pipe" | "radiator" | "pump" | "boiler", facing }
function Commands.place(player, args)
	if not DelHeat.isAdmin(player) then return end
	local x, y, z = coords(args)
	if not x then return end
	local s = state()
	local kind = args.kind
	if kind == "boiler" then
		local facing = oneOf(DelHeat.BOILER_FACINGS, args.facing)
		if not facing then return end
		-- The clicked cell is the middle of the front.
		local ax, ay = x - 1, y - 1
		local cells = boilerCells(ax, ay, z, facing)
		for _, cell in ipairs(cells) do
			local square = getCell():getGridSquare(cell.x, cell.y, cell.z)
			local why = blockedSolid(s, square, cell.x, cell.y, cell.z)
			-- Walls inside the footprint; those along its north and west edge are fine.
			if not why and ((cell.dx > 0 and square:has(IsoFlagType.collideW))
				or (cell.dy > 0 and square:has(IsoFlagType.collideN))) then
				why = "IGUI_DelHeat_Occupied"
			end
			if why then return notify(player, why) end
		end
		local anchor = DelHeat.key(ax, ay, z)
		s.boilers[anchor] = { facing = facing, fuel = 0, temp = ambient(), on = false, by = player:getUsername() }
		for _, cell in ipairs(cells) do
			local key = DelHeat.key(cell.x, cell.y, cell.z)
			s.nodes[key] = BOILER
			s.cells[key] = anchor
		end
		redrawAround(s, cells)
		changed(s)
		notify(player, "IGUI_DelHeat_Placed")
		log(string.format("Boiler placed: %s %s at %s", player:getUsername(), facing, anchor))
		return
	end

	local square = getCell():getGridSquare(x, y, z)
	local key = DelHeat.key(x, y, z)
	local why
	if kind == "pump" then
		why = blockedSolid(s, square, x, y, z)
	elseif kind == "pipe" or kind == "radiator" then
		why = blockedThin(s, square, x, y, z)
	else
		return
	end
	if why then return notify(player, why) end
	if kind == "pump" then
		s.nodes[key] = PUMP
		s.pumps[key] = hasPower(square)
	elseif kind == "radiator" then
		s.nodes[key] = RADIATOR
		s.rads[key] = oneOf(DelHeat.RADIATOR_FACINGS, args.facing) or "N"
	else
		s.nodes[key] = PIPE
	end
	redrawAround(s, { { x = x, y = y, z = z } })
	changed(s)
	notify(player, "IGUI_DelHeat_Placed")
	log(string.format("Placed: %s %s at %s", player:getUsername(), kind, key))
end

-- { x1, y1, x2, y2, z }: pipes along x, then along y. Cells that already
-- hold something are passed over; the run stops at the first cell that
-- takes no pipe.
function Commands.line(player, args)
	if not DelHeat.isAdmin(player) then return end
	local x1, y1, z = coords(args, "x1", "y1")
	local x2, y2 = coords(args, "x2", "y2")
	if not x1 or not x2 then return end
	if math.abs(x2 - x1) + math.abs(y2 - y1) + 1 > DelHeat.MAX_LINE then
		return notify(player, "IGUI_DelHeat_LineTooLong", tostring(DelHeat.MAX_LINE))
	end
	local s = state()
	local laid, stopped = {}, nil
	for _, cell in ipairs(path(x1, y1, x2, y2, z)) do
		local key = DelHeat.key(cell.x, cell.y, cell.z)
		if not s.nodes[key] then
			local why = blockedThin(s, getCell():getGridSquare(cell.x, cell.y, cell.z), cell.x, cell.y, cell.z)
			if why then
				stopped = why
				break
			end
			s.nodes[key] = PIPE
			table.insert(laid, cell)
		end
	end
	if #laid > 0 then
		redrawAround(s, laid)
		changed(s)
		log(string.format("Pipes laid: %s %d from %d,%d to %d,%d,%d", player:getUsername(), #laid, x1, y1, x2, y2, z))
	end
	if stopped then
		notify(player, "IGUI_DelHeat_LineStopped", tostring(#laid), stopped)
	else
		notify(player, "IGUI_DelHeat_LineLaid", tostring(#laid))
	end
end

-- { x1, y1, x2, y2, z }: takes the pipes off the same run; devices stay.
function Commands.unline(player, args)
	if not DelHeat.isAdmin(player) then return end
	local x1, y1, z = coords(args, "x1", "y1")
	local x2, y2 = coords(args, "x2", "y2")
	if not x1 or not x2 then return end
	if math.abs(x2 - x1) + math.abs(y2 - y1) + 1 > DelHeat.MAX_LINE then
		return notify(player, "IGUI_DelHeat_LineTooLong", tostring(DelHeat.MAX_LINE))
	end
	local s = state()
	local taken = {}
	for _, cell in ipairs(path(x1, y1, x2, y2, z)) do
		local key = DelHeat.key(cell.x, cell.y, cell.z)
		if s.nodes[key] == PIPE then
			-- An unloaded square would keep its sprite: stop there.
			if not getCell():getGridSquare(cell.x, cell.y, cell.z) then break end
			s.nodes[key] = nil
			table.insert(taken, cell)
		end
	end
	if #taken > 0 then
		redrawAround(s, taken)
		changed(s)
		log(string.format("Pipes removed: %s %d from %d,%d to %d,%d,%d", player:getUsername(), #taken, x1, y1, x2, y2, z))
	end
	notify(player, "IGUI_DelHeat_LineRemoved", tostring(#taken))
end

-- { x, y, z (any cell) }: removes what stands there, a boiler whole.
function Commands.remove(player, args)
	if not DelHeat.isAdmin(player) then return end
	local x, y, z = coords(args)
	if not x then return end
	local s = state()
	local key = DelHeat.key(x, y, z)
	local square = getCell():getGridSquare(x, y, z)
	local cells = { { x = x, y = y, z = z } }
	local anchor, facing = s.cells[key], nil
	if anchor and s.boilers[anchor] then
		facing = s.boilers[anchor].facing
	else
		-- Sprites without a record (the state rolled back without them).
		local node = DelHeat.nodeAt(square)
		if node and node.kind == BOILER then anchor, facing = node.key, node.facing end
	end
	if anchor and facing then
		local ax, ay, az = DelHeat.unkey(anchor)
		cells = boilerCells(ax, ay, az, facing)
		s.boilers[anchor] = nil
	end
	for _, cell in ipairs(cells) do
		local ckey = DelHeat.key(cell.x, cell.y, cell.z)
		s.nodes[ckey] = nil
		s.cells[ckey] = nil
		s.rads[ckey] = nil
		s.pumps[ckey] = nil
	end
	redrawAround(s, cells)
	changed(s)
	notify(player, "IGUI_DelHeat_Removed")
	log(string.format("Removed: %s at %s", player:getUsername(), key))
end

-- { x, y, z (any boiler cell) }: fuel to the brim.
function Commands.refuel(player, args)
	if not DelHeat.isAdmin(player) then return end
	local x, y, z = coords(args)
	if not x then return end
	local s = state()
	local boiler = s.boilers[s.cells[DelHeat.key(x, y, z)] or ""]
	if not boiler then return end
	boiler.fuel = DelHeat.fuelCapacity()
	pushStatus(s)
	notify(player, "IGUI_DelHeat_Refuelled", tostring(round1(boiler.fuel)))
	log(string.format("Refuelled: %s at %s", player:getUsername(), DelHeat.key(x, y, z)))
end

-- { x, y, z }: does the water get here.
function Commands.probe(player, args)
	if not DelHeat.isAdmin(player) then return end
	local x, y, z = coords(args)
	if not x then return end
	local s = state()
	local key = DelHeat.key(x, y, z)
	if not s.nodes[key] then return notify(player, "IGUI_DelHeat_ProbeNothing") end
	local ahead = network(s).reach[key]
	if ahead then
		notify(player, "IGUI_DelHeat_ProbeYes", tostring(ahead))
	else
		notify(player, "IGUI_DelHeat_ProbeNo")
	end
end

-- ---------------------------------------------------------------------------
-- Commands: anyone
-- ---------------------------------------------------------------------------

-- The boiler under the cell, when the player stands near enough.
local function boilerNear(s, player, args)
	local x, y, z = coords(args)
	if not x then return nil end
	local anchor = s.cells[DelHeat.key(x, y, z)]
	local boiler = anchor and s.boilers[anchor]
	if not boiler then return nil end
	local ax, ay, az = DelHeat.unkey(anchor)
	if math.floor(player:getZ()) ~= az
		or DelHeat.boilerDistance(ax, ay, boiler.facing, player:getX(), player:getY()) > DelHeat.REACH then
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
	local heatUp, coolDown = DelHeat.heatUpPerMinute(), DelHeat.coolDownPerMinute()
	local air = ambient()
	local any = false
	for key, boiler in pairs(s.boilers) do
		any = true
		local fuel, temp = tonumber(boiler.fuel) or 0, tonumber(boiler.temp) or air
		if boiler.on and fuel > 0 then
			fuel = math.max(0, fuel - (base + perRadiator * (n.load[key] or 0)) / 60)
			temp = math.min(DelHeat.WATER_MAX, temp + heatUp)
		elseif temp > air then
			temp = math.max(air, temp - coolDown)
		else
			temp = air
		end
		boiler.fuel, boiler.temp = fuel, temp
	end
	if any then pushHeat(s, false) end
end

-- Pump power is read only where the square is loaded; elsewhere a pump
-- keeps the state it was last seen in.
local function everyTenMinutes()
	local s = state()
	local any = false
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
