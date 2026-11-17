-- Delirium Heating - the window of a thing of the heating.
--
-- One window, opened from the context menu of the thing; what it shows
-- depends on the kind. A boiler house: the state of the furnace, bars for
-- fuel, water and water temperature, the fire button, the fuel the player
-- carries with a button per kind. The rest: whether it works and what it
-- does. Everything comes from the server ("info" in DH_Server.lua), asked
-- for when the window opens, every game minute and after every change the
-- server announces. Rights shown here are only a convenience: the server
-- checks every command.

if isServer() then return end

require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "DH_Shared"

DH_Window = ISCollapsableWindow:derive("DH_Window")
DH_Window.instance = nil

local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local PAD = 10
local BUTTON_HGT = FONT_HGT_SMALL + 6
local ROW = FONT_HGT_SMALL + 4
local BAR_HGT = FONT_HGT_SMALL + 6
local WIDTH = 400
local FUEL_ROWS = 8
local REFRESH_TICKS = 60
-- The window closes when the player walks this far away.
local CLOSE_DISTANCE = 25

local WHITE = { 1, 1, 1 }
local GREY = { 0.65, 0.65, 0.65 }
local GREEN = { 0.5, 1, 0.5 }
local RED = { 1, 0.4, 0.4 }
local FUEL_COLOUR = { 0.8, 0.45, 0.1 }
local WATER_COLOUR = { 0.15, 0.4, 0.8 }
local TEMP_COLOUR = { 0.75, 0.2, 0.15 }

local function number1(value)
	return tostring(math.floor((tonumber(value) or 0) * 10 + 0.5) / 10)
end

-- node: what DelHeat.nodeAt() read off the clicked square.
function DH_Window.open(player, node, square)
	if DH_Window.instance then DH_Window.instance:close() end
	local x = (getCore():getScreenWidth() - WIDTH) / 2
	local y = getCore():getScreenHeight() / 2 - 200
	local ui = DH_Window:new(x, y, WIDTH, 120, player, node, square)
	ui:initialise()
	ui:instantiate()
	ui.pinButton:setVisible(false)
	ui.collapseButton:setVisible(false)
	ui:addToUIManager()
	DH_Window.instance = ui
	DH_Window.ask()
	return ui
end

-- Asks the server about the thing of the open window.
function DH_Window.ask()
	local ui = DH_Window.instance
	if not ui then return end
	DelHeat.send("info", { x = ui.node.x, y = ui.node.y, z = ui.node.z })
end

function DH_Window.onInfo(args)
	local ui = DH_Window.instance
	if not ui or args.key ~= ui.node.key then return end
	ui.data = args
	ui:refresh()
end

function DH_Window:addButton(title, onclick)
	local width = getTextManager():MeasureStringX(UIFont.Small, title) + 20
	local button = ISButton:new(0, 0, width, BUTTON_HGT, title, self, onclick)
	button:initialise()
	button:instantiate()
	button.borderColor = { r = 0.7, g = 0.7, b = 0.7, a = 0.5 }
	self:addChild(button)
	return button
end

function DH_Window:createChildren()
	ISCollapsableWindow.createChildren(self)
	self.toggleBtn = self:addButton(getText("IGUI_DelHeat_SwitchOn"), DH_Window.onToggle)
	self.fillFuelBtn = self:addButton(getText("IGUI_DelHeat_FillFuel"), DH_Window.onFill)
	self.fillFuelBtn.what = "fuel"
	self.fillWaterBtn = self:addButton(getText("IGUI_DelHeat_FillWater"), DH_Window.onFill)
	self.fillWaterBtn.what = "water"
	self.loadAllBtn = self:addButton(getText("IGUI_DelHeat_LoadAllBtn"), DH_Window.onLoadAll)
	self.fuelBtns = {}
	for i = 1, FUEL_ROWS do
		local button = self:addButton(getText("IGUI_DelHeat_LoadBtn"), DH_Window.onLoadRow)
		button.index = i
		self.fuelBtns[i] = button
	end
	self.removeBtn = self:addButton(getText("IGUI_DelHeat_Dismantle"), DH_Window.onRemove)
	self:refresh()
end

local function place(button, x, y, visible)
	button:setX(x)
	button:setY(y)
	button:setVisible(visible)
end

-- A greyed out button says why in its tooltip.
local function enable(button, why)
	button:setEnable(why == nil)
	button:setTooltip(why)
end

local function retitle(button, title)
	button:setTitle(title)
	button:setWidth(getTextManager():MeasureStringX(UIFont.Small, title) + 20)
end

-- Words of a text in lines no wider than the window.
local function wrap(text, maxWidth)
	local manager = getTextManager()
	if manager:MeasureStringX(UIFont.Small, text) <= maxWidth then return { text } end
	local out, line = {}, ""
	for word in string.gmatch(text, "%S+") do
		local longer = line == "" and word or (line .. " " .. word)
		if line ~= "" and manager:MeasureStringX(UIFont.Small, longer) > maxWidth then
			table.insert(out, line)
			line = word
		else
			line = longer
		end
	end
	if line ~= "" then table.insert(out, line) end
	return out
end

-- Returns the y under the text.
function DH_Window:addLine(y, text, colour)
	for _, part in ipairs(wrap(text, self.width - PAD * 2)) do
		table.insert(self.lines, { y = y, text = part, colour = colour or WHITE })
		y = y + ROW
	end
	return y
end

-- marks: fractions of the bar to draw a tick at.
function DH_Window:addBar(y, text, fraction, colour, marks)
	fraction = math.max(0, math.min(1, tonumber(fraction) or 0))
	table.insert(self.bars, { y = y, text = text, fraction = fraction, colour = colour, marks = marks })
	return y + BAR_HGT + 4
end

-- How far the boiler's and the intake's water would still go from here.
function DH_Window:reachLines(d, y)
	if d.heat then
		y = self:addLine(y, getText("IGUI_DelHeat_ProbeHeatYes", tostring(d.heat)), GREEN)
	else
		y = self:addLine(y, getText("IGUI_DelHeat_ProbeHeatNo"), GREY)
	end
	if d.water then
		y = self:addLine(y, getText("IGUI_DelHeat_ProbeWaterYes", tostring(d.water)), GREEN)
	else
		y = self:addLine(y, getText("IGUI_DelHeat_ProbeWaterNo"), GREY)
	end
	return y
end

function DH_Window:boiler(d, y)
	local right = self.width - PAD
	local admin = DelHeat.isAdmin(self.player)
	local fuel, litres, temp = tonumber(d.fuel) or 0, tonumber(d.litres) or 0, tonumber(d.temp) or 0
	local fuelCapacity, waterCapacity = DelHeat.fuelCapacity(), DelHeat.waterCapacity()
	local load = tonumber(d.load) or 0

	if not d.on then
		y = self:addLine(y, getText("IGUI_DelHeat_Off"))
	elseif litres <= 0 then
		y = self:addLine(y, getText("IGUI_DelHeat_OutOfWater"), RED)
	elseif fuel <= 0 then
		y = self:addLine(y, getText("IGUI_DelHeat_OutOfFuel"), RED)
	else
		y = self:addLine(y, getText("IGUI_DelHeat_Burning"), GREEN)
	end
	y = y + 2
	y = self:addBar(y, getText("IGUI_DelHeat_Fuel", number1(fuel), tostring(fuelCapacity)), fuel / fuelCapacity,
		FUEL_COLOUR)
	y = self:addBar(y, getText("IGUI_DelHeat_Water", tostring(litres), tostring(waterCapacity)),
		litres / waterCapacity, WATER_COLOUR)
	y = self:addBar(y, getText("IGUI_DelHeat_Temp", tostring(temp)), temp / DelHeat.WATER_MAX, TEMP_COLOUR,
		{ DelHeat.WATER_WARM / DelHeat.WATER_MAX, DelHeat.WATER_HOT / DelHeat.WATER_MAX })
	y = self:addLine(y, getText("IGUI_DelHeat_WarmHint", tostring(DelHeat.WATER_WARM), tostring(DelHeat.WATER_HOT)),
		GREY)

	if (tonumber(d.supply) or 0) > 0 then
		y = self:addLine(y, getText("IGUI_DelHeat_SupplyYes"), GREEN)
	else
		y = self:addLine(y, getText("IGUI_DelHeat_SupplyNo"), RED)
	end
	y = self:addLine(y, getText("IGUI_DelHeat_Radiators", tostring(load)))
	local perHour = DelHeat.burnPerHour() + DelHeat.burnPerRadiator() * load
	if perHour > 0 then
		y = self:addLine(y, getText("IGUI_DelHeat_BurnRate", number1(perHour), number1(fuel / perHour)))
	end
	local waterPerHour = DelHeat.waterPerHour() + DelHeat.waterPerRadiator() * load
	y = self:addLine(y, getText("IGUI_DelHeat_WaterRate", number1(waterPerHour)))
	y = self:addLine(y, getText("IGUI_DelHeat_BoilerReachLine", tostring(DelHeat.boilerReach())), GREY)
	if d.by then y = self:addLine(y, getText("IGUI_DelHeat_BuiltBy", tostring(d.by)), GREY) end

	y = y + 4
	retitle(self.toggleBtn, getText(d.on and "IGUI_DelHeat_SwitchOff" or "IGUI_DelHeat_SwitchOn"))
	place(self.toggleBtn, PAD, y, true)
	place(self.fillWaterBtn, right - self.fillWaterBtn.width, y, admin)
	place(self.fillFuelBtn, right - self.fillWaterBtn.width - PAD - self.fillFuelBtn.width, y, admin)
	y = y + BUTTON_HGT + PAD
	self.separatorY = y - PAD / 2

	-- The fuel on the player, a row and a button per kind.
	self.fuel, self.fuelAll = DelHeat.fuelGroups(self.player)
	local full = fuelCapacity - fuel <= 0.01
	local why = full and getText("IGUI_DelHeat_Full") or nil
	if #self.fuel == 0 then
		y = self:addLine(y, getText("IGUI_DelHeat_NoFuelItems"), GREY)
		return y
	end
	y = self:addLine(y, getText("IGUI_DelHeat_FuelOnYou"))
	for i = 1, math.min(FUEL_ROWS, #self.fuel) do
		local group = self.fuel[i]
		local button = self.fuelBtns[i]
		table.insert(self.lines, { y = y + (BUTTON_HGT - FONT_HGT_SMALL) / 2, colour = WHITE,
			text = getText("IGUI_DelHeat_LoadGroup", group.name, tostring(#group.ids), number1(group.units)) })
		place(button, right - button.width, y, true)
		enable(button, why)
		y = y + BUTTON_HGT + 4
	end
	if #self.fuel > FUEL_ROWS then
		y = self:addLine(y, getText("IGUI_DelHeat_MoreFuel", tostring(#self.fuel - FUEL_ROWS)), GREY)
	end
	if #self.fuel > 1 then
		place(self.loadAllBtn, right - self.loadAllBtn.width, y, true)
		enable(self.loadAllBtn, why)
		y = y + BUTTON_HGT + 4
	end
	return y
end

function DH_Window:intake(d, y)
	if d.works then
		y = self:addLine(y, getText("IGUI_DelHeat_Works"), GREEN)
	else
		y = self:addLine(y, getText("IGUI_DelHeat_IntakeNoPower"), RED)
	end
	local boilers = tonumber(d.boilers) or 0
	y = self:addLine(y, getText("IGUI_DelHeat_IntakeBoilers", tostring(boilers)), boilers > 0 and GREEN or RED)
	y = self:addLine(y, getText("IGUI_DelHeat_IntakeOutput", tostring(DelHeat.intakeRate())))
	y = self:addLine(y, getText("IGUI_DelHeat_IntakeReachLine", tostring(DelHeat.intakeReach())), GREY)
	if d.by then y = self:addLine(y, getText("IGUI_DelHeat_BuiltBy", tostring(d.by)), GREY) end
	return y
end

function DH_Window:pump(d, y)
	if d.works then
		y = self:addLine(y, getText("IGUI_DelHeat_Works"), GREEN)
	else
		y = self:addLine(y, getText("IGUI_DelHeat_PumpNoPower"), RED)
	end
	y = self:addLine(y, getText("IGUI_DelHeat_PumpPush", tostring(DelHeat.pumpReach())), GREY)
	return self:reachLines(d, y)
end

function DH_Window:inlet(d, y)
	if d.fed then
		y = self:addLine(y, getText("IGUI_DelHeat_InletFed"), GREEN)
		y = self:addBar(y, getText("IGUI_DelHeat_Temp", tostring(d.temp or 0)), (tonumber(d.temp) or 0) / DelHeat.WATER_MAX,
			TEMP_COLOUR, { DelHeat.WATER_WARM / DelHeat.WATER_MAX, DelHeat.WATER_HOT / DelHeat.WATER_MAX })
	else
		y = self:addLine(y, getText("IGUI_DelHeat_InletDry"), RED)
	end
	y = self:addLine(y, getText("IGUI_DelHeat_InletRadius", tostring(DelHeat.inletRadius())))
	y = self:addLine(y, getText("IGUI_DelHeat_InletRads", tostring(d.rads or 0)))
	return self:reachLines(d, y)
end

function DH_Window:tap(d, y)
	if d.fed then
		y = self:addLine(y, getText("IGUI_DelHeat_TapFed"), GREEN)
	else
		y = self:addLine(y, getText("IGUI_DelHeat_TapDry"), RED)
	end
	local capacity = tonumber(d.capacity) or 1
	y = self:addBar(y, getText("IGUI_DelHeat_TapTank", tostring(d.litres or 0), tostring(math.floor(capacity))),
		(tonumber(d.litres) or 0) / capacity, WATER_COLOUR)
	y = self:addLine(y, getText(d.clean and "IGUI_DelHeat_TapClean" or "IGUI_DelHeat_TapTainted"), d.clean and WHITE or RED)
	y = self:addLine(y, getText("IGUI_DelHeat_TapRadius", tostring(DelHeat.tapRadius())))
	y = self:addLine(y, getText("IGUI_DelHeat_TapFixtures", tostring(d.fixtures or 0), tostring(d.fillable or 0)))
	y = self:addLine(y, getText("IGUI_DelHeat_TapRate", tostring(math.floor(DelHeat.intakeRate()))), GREY)
	if d.by then y = self:addLine(y, getText("IGUI_DelHeat_BuiltBy", tostring(d.by)), GREY) end
	return self:reachLines(d, y)
end

function DH_Window:radiator(d, y)
	local level = tonumber(d.level) or 0
	if not d.fed then
		y = self:addLine(y, getText("IGUI_DelHeat_RadiatorDry"), RED)
	elseif level <= 0 then
		y = self:addLine(y, getText("IGUI_DelHeat_RadiatorCold"))
	else
		y = self:addLine(y, getText("IGUI_DelHeat_RadiatorWarm"), GREEN)
	end
	local percent = math.floor(level * 100 / DelHeat.LEVELS + 0.5)
	y = self:addBar(y, getText("IGUI_DelHeat_RadiatorHot", tostring(percent)), level / DelHeat.LEVELS, TEMP_COLOUR)
	if d.fed then y = self:addLine(y, getText("IGUI_DelHeat_Temp", tostring(d.temp or 0))) end
	if level > 0 then
		local air = math.floor(DelHeat.radiatorTemp() * level / DelHeat.LEVELS + 0.5)
		y = self:addLine(y, getText("IGUI_DelHeat_RadiatorAir", tostring(air)))
	end
	y = self:addLine(y, getText("IGUI_DelHeat_RadiatorReach", tostring(DelHeat.radiatorRadius())), GREY)
	y = self:addLine(y, getText("IGUI_DelHeat_WarmHint", tostring(DelHeat.WATER_WARM), tostring(DelHeat.WATER_HOT)),
		GREY)
	return y
end

-- Builds the lines and the bars and places the buttons for what the server
-- told last; the height follows what is shown.
function DH_Window:refresh()
	local d = self.data
	local kind = self.node.kind
	local name = DelHeat.NAME[kind]
	local y = self:titleBarHeight() + PAD
	self.lines, self.bars = {}, {}
	self.separatorY = nil
	place(self.toggleBtn, 0, 0, false)
	place(self.fillFuelBtn, 0, 0, false)
	place(self.fillWaterBtn, 0, 0, false)
	place(self.loadAllBtn, 0, 0, false)
	for _, button in ipairs(self.fuelBtns) do
		place(button, 0, 0, false)
	end

	if not d then
		y = self:addLine(y, getText("IGUI_DelHeat_NoData"), GREY)
	elseif d.kind ~= kind then
		-- Sprites the state knows nothing of, or the thing is gone.
		y = self:addLine(y, getText("IGUI_DelHeat_NoRecord"), RED)
	elseif kind == DelHeat.BOILER then
		y = self:boiler(d, y)
	elseif kind == DelHeat.INTAKE then
		y = self:intake(d, y)
	elseif kind == DelHeat.PUMP then
		y = self:pump(d, y)
	elseif kind == DelHeat.INLET then
		y = self:inlet(d, y)
	elseif kind == DelHeat.RADIATOR then
		y = self:radiator(d, y)
	elseif kind == DelHeat.TAP then
		y = self:tap(d, y)
	elseif kind == DelHeat.SUPPORT then
		y = self:addLine(y, getText("IGUI_DelHeat_SupportInfo"), GREY)
	else
		y = self:reachLines(d, y)
	end

	local admin = DelHeat.isAdmin(self.player)
	if admin or DelHeat.playersBuild() then
		y = y + 4
		retitle(self.removeBtn, getText(admin and "IGUI_DelHeat_Remove" or "IGUI_DelHeat_Dismantle"))
		place(self.removeBtn, self.width - PAD - self.removeBtn.width, y, true)
		local why = DelHeat.whyNotDismantle(self.player, name)
		enable(self.removeBtn, why and getText(why) or nil)
		y = y + BUTTON_HGT
	else
		place(self.removeBtn, 0, 0, false)
	end
	self:setHeight(y + PAD)
end

function DH_Window:update()
	ISCollapsableWindow.update(self)
	self.tick = self.tick + 1
	if self.tick < REFRESH_TICKS then return end
	self.tick = 0
	local dx, dy = self.node.x - self.player:getX(), self.node.y - self.player:getY()
	if dx * dx + dy * dy > CLOSE_DISTANCE * CLOSE_DISTANCE then
		self:close()
		return
	end
	-- The fuel in the inventory and the rights change without the server.
	self:refresh()
end

function DH_Window:render()
	ISCollapsableWindow.render(self)
	local width = self.width - PAD * 2
	for _, bar in ipairs(self.bars or {}) do
		local c = bar.colour
		self:drawRect(PAD, bar.y, width, BAR_HGT, 0.8, 0.1, 0.1, 0.1)
		self:drawRect(PAD + 1, bar.y + 1, (width - 2) * bar.fraction, BAR_HGT - 2, 0.9, c[1], c[2], c[3])
		for _, mark in ipairs(bar.marks or {}) do
			self:drawRect(PAD + width * mark, bar.y, 1, BAR_HGT, 0.7, 1, 1, 1)
		end
		self:drawRectBorder(PAD, bar.y, width, BAR_HGT, 0.8, 0.5, 0.5, 0.5)
		self:drawTextCentre(bar.text, self.width / 2, bar.y + (BAR_HGT - FONT_HGT_SMALL) / 2, 1, 1, 1, 1, UIFont.Small)
	end
	for _, line in ipairs(self.lines or {}) do
		local c = line.colour
		self:drawText(line.text, PAD, line.y, c[1], c[2], c[3], 1, UIFont.Small)
	end
	if self.separatorY then
		self:drawRect(PAD, self.separatorY, width, 1, 0.5, 0.6, 0.6, 0.6)
	end
end

-- ---------------------------------------------------------------------------
-- Buttons
-- ---------------------------------------------------------------------------

function DH_Window:coords()
	return { x = self.square:getX(), y = self.square:getY(), z = self.square:getZ() }
end

function DH_Window:onToggle()
	DelHeat.send("toggle", self:coords())
end

function DH_Window:onFill(button)
	local args = self:coords()
	args.what = button.what
	DelHeat.send("fill", args)
end

function DH_Window:onLoadRow(button)
	local group = self.fuel and self.fuel[button.index]
	if group then DelHeat.loadFuel(self.player, self.node, self.square, group.ids) end
end

function DH_Window:onLoadAll()
	if self.fuelAll and #self.fuelAll > 0 then
		DelHeat.loadFuel(self.player, self.node, self.square, self.fuelAll)
	end
end

function DH_Window:onRemove()
	local name = DelHeat.NAME[self.node.kind]
	local at = self:coords()
	DelHeat.act(self.player, { { x = at.x, y = at.y, z = at.z } }, "remove", at, DelHeat.TIME[name] or 200)
	self:close()
end

function DH_Window:close()
	ISCollapsableWindow.close(self)
	self:removeFromUIManager()
	if DH_Window.instance == self then DH_Window.instance = nil end
end

function DH_Window:new(x, y, width, height, player, node, square)
	local o = ISCollapsableWindow:new(x, y, width, height)
	setmetatable(o, self)
	self.__index = self
	o.player = player
	o.node = node
	o.square = square
	o.title = getText("IGUI_DelHeat_Kind_" .. DelHeat.NAME[node.kind])
	o.resizable = false
	o.tick = 0
	o.lines = {}
	o.bars = {}
	return o
end
