-- Delirium Heating - client: the heat sources at the hot radiators, the
-- server's replies and the context menu (boiler: fire, fuel; building and
-- taking apart with the items; admin: the same for free).

if isServer() then return end

require "ISUI/ISToolTip"
require "DH_Shared"
require "TimedActions/DH_LoadFuelAction"
require "TimedActions/DH_BuildAction"

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

-- { any, heat, water }: how much further the boiler's and the intake's
-- water would go from the probed cell.
function Replies.probe(args)
	if not args.any then return halo(getText("IGUI_DelHeat_ProbeNothing")) end
	local heat = args.heat and getText("IGUI_DelHeat_ProbeHeatYes", tostring(args.heat))
		or getText("IGUI_DelHeat_ProbeHeatNo")
	local water = args.water and getText("IGUI_DelHeat_ProbeWaterYes", tostring(args.water))
		or getText("IGUI_DelHeat_ProbeWaterNo")
	halo(heat .. " | " .. water)
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
	status = {}
	for _, name in ipairs({ "boilers", "pumps", "intakes", "inlets" }) do
		status[name] = type(args[name]) == "table" and args[name] or {}
	end
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
	if (tonumber(record.supply) or 0) > 0 then
		table.insert(lines, GREEN .. getText("IGUI_DelHeat_SupplyYes") .. WHITE)
	else
		table.insert(lines, RED .. getText("IGUI_DelHeat_SupplyNo") .. WHITE)
	end
	local load = tonumber(record.load) or 0
	table.insert(lines, getText("IGUI_DelHeat_Radiators", tostring(load)))
	local perHour = DelHeat.burnPerHour() + DelHeat.burnPerRadiator() * load
	if perHour > 0 then
		table.insert(lines, getText("IGUI_DelHeat_BurnRate", number1(perHour), number1(fuel / perHour)))
	end
	return lines
end

-- What the tooltip of a thing says; nil for a plain pipe.
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
		local radius = getText("IGUI_DelHeat_InletRadius", tostring(DelHeat.inletRadius()))
		if status.inlets[node.key] then return { GREEN .. getText("IGUI_DelHeat_InletFed"), WHITE .. radius } end
		return { RED .. getText("IGUI_DelHeat_InletDry"), WHITE .. radius }
	end
	return nil
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
-- Building. An admin's command goes straight to the server; a player walks
-- up and works for a while first (the server checks the tool, the item and
-- the distance again).
-- ---------------------------------------------------------------------------

local TIME = { pipe = 80, radiator = 200, inlet = 250, pump = 300, intake = 500, boiler = 800 }

local function act(player, square, command, args, time)
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

-- The first click of a pipe run.
local lineStart = nil

-- Lazily made submenu: a thing with nothing to offer stays a plain line.
local function submenuOf(context, parent)
	local sub
	return function()
		if not sub then
			sub = ISContextMenu:getNew(context)
			context:addSubMenu(parent, sub)
		end
		return sub
	end
end

local function disable(option, key, arg)
	option.notAvailable = true
	option.toolTip = tooltip({ arg and getText(key, tostring(arg)) or getText(key) })
end

-- Run of pipes: start here / lay to here / take off to here.
local function lineOptions(sub, player, square, admin, hasTool, pipes)
	local x, y, z = square:getX(), square:getY(), square:getZ()
	sub:addOption(getText("IGUI_DelHeat_LineStart"), MODULE, function()
		lineStart = { x = x, y = y, z = z }
		player:setHaloNote(getText("IGUI_DelHeat_LineStartSet"), 255, 255, 255, 300)
	end)
	if not lineStart or lineStart.z ~= z then return end
	local run = { x1 = lineStart.x, y1 = lineStart.y, x2 = x, y2 = y, z = z }
	local length = math.abs(x - lineStart.x) + math.abs(y - lineStart.y) + 1
	local lay = sub:addOption(getText("IGUI_DelHeat_LineEnd", tostring(length)), MODULE, function()
		act(player, square, "line", run, math.min(1500, 60 + 40 * (admin and length or math.min(length, pipes))))
		-- The next run starts where this one ended.
		lineStart = { x = x, y = y, z = z }
	end)
	local take = sub:addOption(getText("IGUI_DelHeat_LineRemove", tostring(length)), MODULE, function()
		act(player, square, "unline", run, math.min(1500, 60 + 30 * length))
		lineStart = nil
	end)
	if length > DelHeat.MAX_LINE then
		disable(lay, "IGUI_DelHeat_LineTooLong", DelHeat.MAX_LINE)
		disable(take, "IGUI_DelHeat_LineTooLong", DelHeat.MAX_LINE)
	elseif not admin and not hasTool then
		disable(lay, "IGUI_DelHeat_NeedTool")
		disable(take, "IGUI_DelHeat_NeedTool")
	elseif not admin and pipes <= 0 then
		disable(lay, "IGUI_DelHeat_NeedItem")
	end
end

-- Right click on one of our things.
local function nodeMenu(context, player, node, square, admin, canBuild, hasTool, service)
	local name = DelHeat.NAME[node.kind]
	local parent = context:addOption(getText("IGUI_DelHeat_Kind_" .. name))
	local lines = infoLines(node)
	if lines then parent.toolTip = tooltip(lines) end
	local sub = submenuOf(context, parent)
	local args = { x = square:getX(), y = square:getY(), z = square:getZ() }

	if node.kind == BOILER then
		local record = status.boilers[node.key]
		local on = record and record.on
		sub():addOption(getText(on and "IGUI_DelHeat_SwitchOff" or "IGUI_DelHeat_SwitchOn"), MODULE,
			function() DelHeat.send("toggle", args) end)
		local groups, all = fuelGroups(player)
		local fuelOption = sub():addOption(getText("IGUI_DelHeat_LoadFuel"))
		if #groups == 0 then
			disable(fuelOption, "IGUI_DelHeat_NoFuelItems")
		else
			local fuelMenu = ISContextMenu:getNew(sub())
			sub():addSubMenu(fuelOption, fuelMenu)
			if #groups > 1 then
				fuelMenu:addOption(getText("IGUI_DelHeat_LoadAll"), player, loadFuel, node, square, all)
			end
			for _, group in ipairs(groups) do
				local text = getText("IGUI_DelHeat_LoadGroup", group.name, tostring(#group.ids), number1(group.units))
				fuelMenu:addOption(text, player, loadFuel, node, square, group.ids)
			end
		end
		if admin then
			sub():addOption(getText("IGUI_DelHeat_FillFuel"), MODULE, function()
				DelHeat.send("fill", { x = args.x, y = args.y, z = args.z, what = "fuel" })
			end)
			sub():addOption(getText("IGUI_DelHeat_FillWater"), MODULE, function()
				DelHeat.send("fill", { x = args.x, y = args.y, z = args.z, what = "water" })
			end)
		end
	end

	if node.kind ~= RADIATOR then
		sub():addOption(getText("IGUI_DelHeat_Probe"), MODULE, function() DelHeat.send("probe", args) end)
	end
	if not canBuild then return end
	if service and (node.kind == PIPE or node.kind == PUMP or node.kind == INLET) then
		lineOptions(sub(), player, square, admin, hasTool, DelHeat.countOf(player, DelHeat.ITEM.pipe))
	end
	local remove = sub():addOption(getText(admin and "IGUI_DelHeat_Remove" or "IGUI_DelHeat_Dismantle"), MODULE,
		function() act(player, square, "remove", args, TIME[name] or 200) end)
	if not service and DelHeat.needsService(name) then
		disable(remove, "IGUI_DelHeat_NotService")
	elseif not admin and not hasTool then
		disable(remove, "IGUI_DelHeat_NeedTool")
	end
end

-- Right click on bare ground with something to build. A part the player
-- carries but may not build is greyed out with the reason.
local function buildMenu(context, player, square, admin, hasTool, service)
	local have = {}
	local any = admin
	for name, itemType in pairs(DelHeat.ITEM) do
		have[name] = DelHeat.countOf(player, itemType)
		if have[name] > 0 then any = true end
	end
	if not any then return end
	local parent = context:addOption(getText("IGUI_DelHeat_Build"))
	local sub = ISContextMenu:getNew(context)
	context:addSubMenu(parent, sub)
	local x, y, z = square:getX(), square:getY(), square:getZ()

	local function place(menu, textKey, name, facing)
		if not admin and have[name] <= 0 then return end
		local option = menu:addOption(getText(textKey), MODULE, function()
			act(player, square, "place", { x = x, y = y, z = z, kind = name, facing = facing }, TIME[name])
		end)
		if not service and DelHeat.needsService(name) then
			disable(option, "IGUI_DelHeat_NotService")
		elseif not admin and not hasTool then
			disable(option, "IGUI_DelHeat_NeedTool")
		end
	end

	local function placeFacing(textKey, name, facings, prefix)
		if not admin and have[name] <= 0 then return end
		local option = sub:addOption(getText(textKey))
		local menu = ISContextMenu:getNew(sub)
		sub:addSubMenu(option, menu)
		for _, facing in ipairs(facings) do
			place(menu, prefix .. facing, name, facing)
		end
	end

	place(sub, "IGUI_DelHeat_PlacePipe", "pipe")
	if admin or (service and have.pipe > 0) then lineOptions(sub, player, square, admin, hasTool, have.pipe) end
	placeFacing("IGUI_DelHeat_PlaceRadiator", "radiator", DelHeat.RADIATOR_FACINGS, "IGUI_DelHeat_Wall_")
	placeFacing("IGUI_DelHeat_PlaceInlet", "inlet", DelHeat.RADIATOR_FACINGS, "IGUI_DelHeat_Wall_")
	place(sub, "IGUI_DelHeat_PlacePump", "pump")
	place(sub, "IGUI_DelHeat_PlaceIntake", "intake")
	placeFacing("IGUI_DelHeat_PlaceBoiler", "boiler", DelHeat.BOILER_FACINGS, "IGUI_DelHeat_Front_")
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

	local admin = DelHeat.isAdmin(player)
	local canBuild = admin or DelHeat.playersBuild()
	local hasTool = admin or DelHeat.hasTool(player)
	-- May build the network, not only radiators.
	local service = admin or DelHeat.isService(player)
	if node then
		nodeMenu(context, player, node, square, admin, canBuild, hasTool, service)
	elseif canBuild then
		buildMenu(context, player, square, admin, hasTool, service)
	end
end
Events.OnFillWorldObjectContextMenu.Add(onFill)
