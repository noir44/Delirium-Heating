-- Delirium Heating - client: the heat sources at the hot radiators, the
-- server's replies and the context menus. A thing of the heating opens its
-- window (ISUI/DH_Window.lua); a part is put down with the placement cursor
-- (server/DH_Cursor.lua), started from the part in the inventory or from
-- "Heating" on the ground.

if isServer() then return end

require "ISUI/ISToolTip"
require "DH_Shared"
require "TimedActions/DH_LoadFuelAction"
require "TimedActions/DH_BuildAction"
require "ISUI/DH_Window"

local MODULE = DelHeat.MODULE
local PIPE, PUMP, INLET = DelHeat.PIPE, DelHeat.PUMP, DelHeat.INLET
local RADIATOR, BOILER, INTAKE = DelHeat.RADIATOR, DelHeat.BOILER, DelHeat.INTAKE

function DelHeat.send(command, args)
	local player = getPlayer()
	if not player then return end
	sendClientCommand(player, MODULE, command, args or {})
end

-- ---------------------------------------------------------------------------
-- What the server told us. A connect-time request can be lost (see
-- E:\mods\CLAUDE.md), so it is asked again until an answer arrives.
-- ---------------------------------------------------------------------------

-- levels = { ["x,y,z"] = 0..LEVELS } for every radiator a heat unit serves;
-- status = { boilers = { [anchor] = { facing, fuel, water, temp, on, load, supply } },
--            pumps = { [cell] = works }, intakes = { [anchor] = works },
--            inlets = { [cell] = true } }
local levels = {}
local status = { boilers = {}, pumps = {}, intakes = {}, inlets = {} }
local received = false

local function request()
	if received then return end
	DelHeat.send("sync")
end

-- ---------------------------------------------------------------------------
-- Heat: one IsoHeatSource per hot radiator, as a vanilla fireplace has.
-- The cell throws away the sources outside the loaded area on its own
-- (IsoCell.updateHeatSources), so they are put back every game minute.
-- ---------------------------------------------------------------------------

local sources = {}

local function dropSource(key)
	local source = sources[key]
	if not source then return end
	getCell():removeHeatSource(source)
	sources[key] = nil
end

local function refreshHeat()
	local cell = getCell()
	if not cell then return end
	local full, radius = DelHeat.radiatorTemp(), DelHeat.radiatorRadius()
	for key, _ in pairs(sources) do
		if (levels[key] or 0) <= 0 then dropSource(key) end
	end
	for key, level in pairs(levels) do
		if level > 0 then
			local temp = math.floor(full * level / DelHeat.LEVELS + 0.5)
			local source = sources[key]
			if not source then
				local x, y, z = DelHeat.unkey(key)
				if x then
					source = IsoHeatSource.new(x, y, z, radius, temp)
					sources[key] = source
				end
			end
			if source then
				source:setTemperature(temp)
				source:setRadius(radius)
				-- Adding twice only logs an error; take it out first.
				cell:removeHeatSource(source)
				if source:isInBounds() then cell:addHeatSource(source) end
			end
		end
	end
end

local function everyMinute()
	request()
	refreshHeat()
	DH_Window.ask()
end

Events.OnGameStart.Add(request)
Events.OnCreatePlayer.Add(function() request() end)
Events.EveryOneMinute.Add(everyMinute)

-- ---------------------------------------------------------------------------
-- Server replies
-- ---------------------------------------------------------------------------

local Replies = {}

local function halo(text)
	local player = getPlayer()
	if player then player:setHaloNote(text, 255, 255, 255, 300) end
end

function Replies.notify(args)
	if type(args.key) ~= "string" then return end
	local arg1, arg2 = args.arg1, args.arg2
	-- An argument may itself be a translation key (why a pipe run stopped).
	if type(arg2) == "string" and string.sub(arg2, 1, 5) == "IGUI_" then arg2 = getText(arg2) end
	if arg2 ~= nil then
		halo(getText(args.key, tostring(arg1), tostring(arg2)))
	elseif arg1 ~= nil then
		halo(getText(args.key, tostring(arg1)))
	else
		halo(getText(args.key))
	end
end

function Replies.heat(args)
	if type(args.levels) ~= "table" then return end
	levels = {}
	for key, level in pairs(args.levels) do
		levels[key] = tonumber(level) or 0
	end
	received = true
	refreshHeat()
end

-- Sent after every change of the network or of a boiler: the open window
-- asks for its thing again.
function Replies.status(args)
	status = {}
	for _, name in ipairs({ "boilers", "pumps", "intakes", "inlets" }) do
		status[name] = type(args[name]) == "table" and args[name] or {}
	end
	DH_Window.ask()
end

function Replies.info(args)
	DH_Window.onInfo(args)
end

local function onServerCommand(module, command, args)
	if module ~= MODULE then return end
	local handler = Replies[command]
	if handler then handler(args or {}) end
end
Events.OnServerCommand.Add(onServerCommand)

-- ---------------------------------------------------------------------------
-- Tooltips of the context menu: the short state of a thing.
-- ---------------------------------------------------------------------------

local RED = " <RGB:1,0.4,0.4> "
local GREEN = " <RGB:0.5,1,0.5> "
local WHITE = " <RGB:1,1,1> "

local function tooltip(lines)
	local tip = ISToolTip:new()
	tip:initialise()
	tip:setVisible(false)
	tip.description = table.concat(lines, " <LINE> ")
	return tip
end

local function number1(value)
	return tostring(math.floor((tonumber(value) or 0) * 10 + 0.5) / 10)
end

local function boilerLines(record)
	if not record then return { getText("IGUI_DelHeat_NoData") } end
	local lines = {}
	local fuel, water = tonumber(record.fuel) or 0, tonumber(record.water) or 0
	if not record.on then
		table.insert(lines, getText("IGUI_DelHeat_Off"))
	elseif water <= 0 then
		table.insert(lines, RED .. getText("IGUI_DelHeat_OutOfWater"))
	elseif fuel <= 0 then
		table.insert(lines, RED .. getText("IGUI_DelHeat_OutOfFuel"))
	else
		table.insert(lines, GREEN .. getText("IGUI_DelHeat_Burning"))
	end
	table.insert(lines, WHITE .. getText("IGUI_DelHeat_Temp", tostring(record.temp or 0)))
	table.insert(lines, getText("IGUI_DelHeat_Fuel", number1(fuel), tostring(DelHeat.fuelCapacity())))
	table.insert(lines, getText("IGUI_DelHeat_Water", tostring(water), tostring(DelHeat.waterCapacity())))
	return lines
end

-- nil for a plain pipe.
local function infoLines(node)
	if node.kind == BOILER then return boilerLines(status.boilers[node.key]) end
	if node.kind == RADIATOR then
		local level = levels[node.key]
		if level == nil then return { RED .. getText("IGUI_DelHeat_RadiatorDry") } end
		if level <= 0 then return { getText("IGUI_DelHeat_RadiatorCold") } end
		return { GREEN .. getText("IGUI_DelHeat_RadiatorHot", tostring(math.floor(level * 100 / DelHeat.LEVELS + 0.5))) }
	end
	if node.kind == PUMP then
		if status.pumps[node.key] then return { GREEN .. getText("IGUI_DelHeat_Works") } end
		return { RED .. getText("IGUI_DelHeat_PumpNoPower") }
	end
	if node.kind == INTAKE then
		if status.intakes[node.key] then return { GREEN .. getText("IGUI_DelHeat_Works") } end
		return { RED .. getText("IGUI_DelHeat_IntakeNoPower") }
	end
	if node.kind == INLET then
		if status.inlets[node.key] then return { GREEN .. getText("IGUI_DelHeat_InletFed") } end
		return { RED .. getText("IGUI_DelHeat_InletDry") }
	end
	return nil
end

-- ---------------------------------------------------------------------------
-- Fuel in the player's inventory, bags included.
-- ---------------------------------------------------------------------------

-- { { name, ids = {...}, units }, ... } by item type, and all ids.
function DelHeat.fuelGroups(player)
	local fuelTable = DelHeat.fuelTable()
	local items = player:getInventory():getAllEvalRecurse(function(item)
		return DelHeat.fuelValue(item, fuelTable) ~= nil
	end)
	local groups, byType, all = {}, {}, {}
	for i = 0, items:size() - 1 do
		local item = items:get(i)
		local units = DelHeat.fuelValue(item, fuelTable)
		local fullType = item:getFullType()
		local group = byType[fullType]
		if not group then
			group = { name = item:getDisplayName(), ids = {}, units = 0 }
			byType[fullType] = group
			table.insert(groups, group)
		end
		table.insert(group.ids, item:getID())
		table.insert(all, item:getID())
		group.units = group.units + units
	end
	return groups, all
end

-- Walks up to the boiler and throws the items in.
function DelHeat.loadFuel(player, node, square, ids)
	if luautils.walkAdj(player, square, true) then
		ISTimedActionQueue.add(DH_LoadFuelAction:new(player, node, ids))
	end
end

-- ---------------------------------------------------------------------------
-- Building. An admin's command goes straight to the server; a player walks
-- up and works for a while first (the server checks the rights, the tool,
-- the item and the distance again).
-- ---------------------------------------------------------------------------

DelHeat.TIME = { pipe = 80, radiator = 200, inlet = 250, pump = 300, intake = 500, boiler = 800 }
-- The parts in the order the menu shows them.
DelHeat.PARTS = { "pipe", "radiator", "inlet", "pump", "intake", "boiler" }

function DelHeat.act(player, square, command, args, time)
	if DelHeat.isAdmin(player) then
		DelHeat.send(command, args)
		return
	end
	-- A pipe in the air has no floor to walk up to: it is worked on from
	-- below, from where the player stands.
	if square:getZ() ~= math.floor(player:getZ()) or not square:getFloor() then
		local dx, dy = square:getX() + 0.5 - player:getX(), square:getY() + 0.5 - player:getY()
		if dx * dx + dy * dy > DelHeat.BUILD_REACH * DelHeat.BUILD_REACH then
			player:setHaloNote(getText("IGUI_DelHeat_ComeCloser"), 255, 255, 255, 300)
			return
		end
		ISTimedActionQueue.add(DH_BuildAction:new(player, command, args, time))
	elseif luautils.walkAdj(player, square, true) then
		ISTimedActionQueue.add(DH_BuildAction:new(player, command, args, time))
	end
end

-- nil when this player may take the part apart, otherwise a translation
-- key. The server asks the same.
function DelHeat.whyNotDismantle(player, name)
	if DelHeat.isAdmin(player) then return nil end
	if not DelHeat.playersBuild() then return "IGUI_DelHeat_NoRights" end
	if DelHeat.needsService(name) and not DelHeat.isService(player) then return "IGUI_DelHeat_NotService" end
	if not DelHeat.hasTool(player) then return "IGUI_DelHeat_NeedTool" end
	return nil
end

-- The same for building it; "unpipe" is taking pipes off with the cursor.
function DelHeat.whyNotBuild(player, name)
	if name == "unpipe" then return DelHeat.whyNotDismantle(player, "pipe") end
	local why = DelHeat.whyNotDismantle(player, name)
	if why then return why end
	if not DelHeat.isAdmin(player) and DelHeat.countOf(player, DelHeat.ITEM[name]) <= 0 then
		return "IGUI_DelHeat_NeedItem"
	end
	return nil
end

local function startCursor(player, name)
	DH_Cursor.start(player, name)
end

local function disable(option, key)
	option.notAvailable = true
	option.toolTip = tooltip({ getText(key) })
end

-- "Heating" on the ground: the parts the player carries (an admin: all of
-- them), each starting the placement cursor.
local function buildMenu(context, player, admin)
	local names = {}
	for _, name in ipairs(DelHeat.PARTS) do
		if admin or DelHeat.countOf(player, DelHeat.ITEM[name]) > 0 then table.insert(names, name) end
	end
	local unpipe = admin or (DelHeat.isService(player) and DelHeat.hasTool(player))
	if #names == 0 and not unpipe then return end
	local parent = context:addOption(getText("IGUI_DelHeat_Build"))
	local sub = ISContextMenu:getNew(context)
	context:addSubMenu(parent, sub)
	for _, name in ipairs(names) do
		local option = sub:addOption(getText("IGUI_DelHeat_Kind_" .. name), player, startCursor, name)
		local why = DelHeat.whyNotBuild(player, name)
		if why then disable(option, why) end
	end
	if unpipe then sub:addOption(getText("IGUI_DelHeat_RemovePipes"), player, startCursor, "unpipe") end
end

local function onFill(playerNum, context, worldobjects, test)
	if test then return end
	local player = getSpecificPlayer(playerNum)
	if not player or not worldobjects then return end
	-- The clicked squares: a device wins over a bare pipe.
	local square, node
	for _, object in ipairs(worldobjects) do
		local sq = object:getSquare()
		local found = DelHeat.nodeAt(sq)
		if sq and not square then square = sq end
		if found and (not node or (node.kind == PIPE and found.kind ~= PIPE)) then
			square, node = sq, found
		end
	end
	if not square then return end

	if node then
		local option = context:addOption(getText("IGUI_DelHeat_Kind_" .. DelHeat.NAME[node.kind]), player,
			DH_Window.open, node, square)
		local lines = infoLines(node)
		if lines then option.toolTip = tooltip(lines) end
	end
	local admin = DelHeat.isAdmin(player)
	if admin or DelHeat.playersBuild() then buildMenu(context, player, admin) end
end
Events.OnFillWorldObjectContextMenu.Add(onFill)

-- "Place" on a part in the inventory.
local function onFillInventory(playerNum, context, items)
	local player = getSpecificPlayer(playerNum)
	items = ISInventoryPane.getActualItems(items)
	if not player or not items or #items < 1 then return end
	local item = items[1]
	local container = item:getContainer()
	if not container or not container:isInCharacterInventory(player) then return end
	local fullType = item:getFullType()
	for _, name in ipairs(DelHeat.PARTS) do
		if DelHeat.ITEM[name] == fullType then
			local option = context:addOption(getText("IGUI_DelHeat_PlaceItem"), player, startCursor, name)
			local why = DelHeat.whyNotBuild(player, name)
			if why then disable(option, why) end
			return
		end
	end
end
Events.OnFillInventoryObjectContextMenu.Add(onFillInventory)
