-- Delirium Heating - client: the heat sources at the hot radiators, the
-- server's replies and the context menu (boiler: fire, fuel; admin: put
-- down, lay pipes, remove).

if isServer() then return end

require "ISUI/ISToolTip"
require "DH_Shared"
require "TimedActions/DH_LoadFuelAction"

local MODULE = DelHeat.MODULE
local PIPE, RADIATOR, PUMP, BOILER = DelHeat.PIPE, DelHeat.RADIATOR, DelHeat.PUMP, DelHeat.BOILER

function DelHeat.send(command, args)
	local player = getPlayer()
	if not player then return end
	sendClientCommand(player, MODULE, command, args or {})
end

-- ---------------------------------------------------------------------------
-- What the server told us. A connect-time request can be lost (see
-- E:\mods\CLAUDE.md), so it is asked again until an answer arrives.
-- ---------------------------------------------------------------------------

-- levels = { ["x,y,z"] = 0..LEVELS } for every radiator the water reaches;
-- status = { boilers = { [anchor] = { facing, fuel, temp, on, load } },
--            pumps = { [cell] = works } }
local levels = {}
local status = { boilers = {}, pumps = {} }
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
end

Events.OnGameStart.Add(request)
Events.OnCreatePlayer.Add(function() request() end)
Events.EveryOneMinute.Add(everyMinute)

-- ---------------------------------------------------------------------------
-- Server replies
-- ---------------------------------------------------------------------------

local Replies = {}

function Replies.notify(args)
	local player = getPlayer()
	if not player or type(args.key) ~= "string" then return end
	local arg1, arg2 = args.arg1, args.arg2
	-- An argument may itself be a translation key (why a pipe run stopped).
	if type(arg2) == "string" and string.sub(arg2, 1, 5) == "IGUI_" then arg2 = getText(arg2) end
	local text
	if arg2 ~= nil then
		text = getText(args.key, tostring(arg1), tostring(arg2))
	elseif arg1 ~= nil then
		text = getText(args.key, tostring(arg1))
	else
		text = getText(args.key)
	end
	player:setHaloNote(text, 255, 255, 255, 300)
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

function Replies.status(args)
	status = {
		boilers = type(args.boilers) == "table" and args.boilers or {},
		pumps = type(args.pumps) == "table" and args.pumps or {},
	}
end

local function onServerCommand(module, command, args)
	if module ~= MODULE then return end
	local handler = Replies[command]
	if handler then handler(args or {}) end
end
Events.OnServerCommand.Add(onServerCommand)

-- ---------------------------------------------------------------------------
-- Tooltips
-- ---------------------------------------------------------------------------

local RED = " <RGB:1,0.4,0.4> "
local GREEN = " <RGB:0.5,1,0.5> "

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
	local fuel = tonumber(record.fuel) or 0
	local burning = record.on and fuel > 0
	if burning then
		table.insert(lines, GREEN .. getText("IGUI_DelHeat_Burning"))
	elseif record.on then
		table.insert(lines, RED .. getText("IGUI_DelHeat_OutOfFuel"))
	else
		table.insert(lines, getText("IGUI_DelHeat_Off"))
	end
	table.insert(lines, " <RGB:1,1,1> " .. getText("IGUI_DelHeat_Water", tostring(record.temp or 0)))
	table.insert(lines, getText("IGUI_DelHeat_Fuel", number1(fuel), tostring(DelHeat.fuelCapacity())))
	local load = tonumber(record.load) or 0
	table.insert(lines, getText("IGUI_DelHeat_Radiators", tostring(load)))
	local perHour = DelHeat.burnPerHour() + DelHeat.burnPerRadiator() * load
	if perHour > 0 then
		table.insert(lines, getText("IGUI_DelHeat_BurnRate", number1(perHour), number1(fuel / perHour)))
	end
	return lines
end

local function radiatorLines(key)
	local level = levels[key]
	if level == nil then return { RED .. getText("IGUI_DelHeat_RadiatorDry") } end
	if level <= 0 then return { getText("IGUI_DelHeat_RadiatorCold") } end
	local percent = math.floor(level * 100 / DelHeat.LEVELS + 0.5)
	return { GREEN .. getText("IGUI_DelHeat_RadiatorHot", tostring(percent)) }
end

local function pumpLines(key)
	if status.pumps[key] == nil then return { getText("IGUI_DelHeat_NoData") } end
	if status.pumps[key] then return { GREEN .. getText("IGUI_DelHeat_PumpWorks") } end
	return { RED .. getText("IGUI_DelHeat_PumpNoPower") }
end

-- ---------------------------------------------------------------------------
-- Fuel in the player's inventory, bags included.
-- ---------------------------------------------------------------------------

-- { { name, ids = {...}, units }, ... } by item type, and all ids.
local function fuelGroups(player)
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

local function loadFuel(player, node, square, ids)
	if luautils.walkAdj(player, square, true) then
		ISTimedActionQueue.add(DH_LoadFuelAction:new(player, node, ids))
	end
end

-- ---------------------------------------------------------------------------
-- Context menu
-- ---------------------------------------------------------------------------

-- The admin's first click of a pipe run.
local lineStart = nil

local function boilerMenu(context, player, node, square)
	local record = status.boilers[node.key]
	local parent = context:addOption(getText("IGUI_DelHeat_Boiler"))
	parent.toolTip = tooltip(boilerLines(record))
	local sub = ISContextMenu:getNew(context)
	context:addSubMenu(parent, sub)
	local args = { x = node.x, y = node.y, z = node.z }

	local on = record and record.on
	local switch = sub:addOption(getText(on and "IGUI_DelHeat_SwitchOff" or "IGUI_DelHeat_SwitchOn"), MODULE,
		function() DelHeat.send("toggle", args) end)
	switch.toolTip = tooltip(boilerLines(record))

	local groups, all = fuelGroups(player)
	local fuelOption = sub:addOption(getText("IGUI_DelHeat_LoadFuel"))
	if #groups == 0 then
		fuelOption.notAvailable = true
		fuelOption.toolTip = tooltip({ getText("IGUI_DelHeat_NoFuelItems") })
		return
	end
	local fuelMenu = ISContextMenu:getNew(sub)
	sub:addSubMenu(fuelOption, fuelMenu)
	if #groups > 1 then
		fuelMenu:addOption(getText("IGUI_DelHeat_LoadAll"), player, loadFuel, node, square, all)
	end
	for _, group in ipairs(groups) do
		local name = getText("IGUI_DelHeat_LoadGroup", group.name, tostring(#group.ids), number1(group.units))
		fuelMenu:addOption(name, player, loadFuel, node, square, group.ids)
	end
end

local function adminMenu(context, square, node)
	local parent = context:addOption(getText("IGUI_DelHeat_Admin"))
	local sub = ISContextMenu:getNew(context)
	context:addSubMenu(parent, sub)
	local x, y, z = square:getX(), square:getY(), square:getZ()
	local args = { x = x, y = y, z = z }

	if not node then
		sub:addOption(getText("IGUI_DelHeat_PlacePipe"), MODULE, function()
			DelHeat.send("place", { x = x, y = y, z = z, kind = "pipe" })
		end)
	end
	sub:addOption(getText("IGUI_DelHeat_LineStart"), MODULE, function()
		lineStart = { x = x, y = y, z = z }
		getPlayer():setHaloNote(getText("IGUI_DelHeat_LineStartSet"), 255, 255, 255, 300)
	end)
	if lineStart and lineStart.z == z then
		local run = { x1 = lineStart.x, y1 = lineStart.y, x2 = x, y2 = y, z = z }
		local length = math.abs(x - lineStart.x) + math.abs(y - lineStart.y) + 1
		local lay = sub:addOption(getText("IGUI_DelHeat_LineEnd", tostring(length)), MODULE, function()
			DelHeat.send("line", run)
			-- The next run starts where this one ended.
			lineStart = { x = x, y = y, z = z }
		end)
		local take = sub:addOption(getText("IGUI_DelHeat_LineRemove", tostring(length)), MODULE, function()
			DelHeat.send("unline", run)
			lineStart = nil
		end)
		if length > DelHeat.MAX_LINE then
			lay.notAvailable = true
			take.notAvailable = true
		end
	end

	if not node then
		local radiator = sub:addOption(getText("IGUI_DelHeat_PlaceRadiator"))
		local radiatorMenu = ISContextMenu:getNew(sub)
		sub:addSubMenu(radiator, radiatorMenu)
		for _, facing in ipairs(DelHeat.RADIATOR_FACINGS) do
			radiatorMenu:addOption(getText("IGUI_DelHeat_Wall_" .. facing), MODULE, function()
				DelHeat.send("place", { x = x, y = y, z = z, kind = "radiator", facing = facing })
			end)
		end
		sub:addOption(getText("IGUI_DelHeat_PlacePump"), MODULE, function()
			DelHeat.send("place", { x = x, y = y, z = z, kind = "pump" })
		end)
		local boiler = sub:addOption(getText("IGUI_DelHeat_PlaceBoiler"))
		local boilerMenu2 = ISContextMenu:getNew(sub)
		sub:addSubMenu(boiler, boilerMenu2)
		for _, facing in ipairs(DelHeat.BOILER_FACINGS) do
			boilerMenu2:addOption(getText("IGUI_DelHeat_Front_" .. facing), MODULE, function()
				DelHeat.send("place", { x = x, y = y, z = z, kind = "boiler", facing = facing })
			end)
		end
		return
	end

	sub:addOption(getText("IGUI_DelHeat_Probe"), MODULE, function() DelHeat.send("probe", args) end)
	if node.kind == BOILER then
		sub:addOption(getText("IGUI_DelHeat_Refuel"), MODULE, function() DelHeat.send("refuel", args) end)
	end
	sub:addOption(getText("IGUI_DelHeat_Remove"), MODULE, function() DelHeat.send("remove", args) end)
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

	if node and node.kind == BOILER then
		boilerMenu(context, player, node, square)
	elseif node and node.kind == RADIATOR then
		local option = context:addOption(getText("IGUI_DelHeat_Radiator"))
		option.toolTip = tooltip(radiatorLines(node.key))
	elseif node and node.kind == PUMP then
		local option = context:addOption(getText("IGUI_DelHeat_Pump"))
		option.toolTip = tooltip(pumpLines(node.key))
	end

	if DelHeat.isAdmin(player) then adminMenu(context, square, node) end
end
Events.OnFillWorldObjectContextMenu.Add(onFill)
