-- Delirium Heating - the placement cursor: the part is shown on the ground
-- under the mouse before it is put down.
--
-- Lives in server/ only because ISBuildingObject does (as the cursor of
-- Delirium Shops); it is client UI and does nothing on a dedicated server.
-- The cursor only picks the place and the turn - the thing itself is put
-- down by the server ("place", "line", "unline" in DH_Server.lua), which
-- checks everything again.
--
-- Vanilla drives it (DoTileBuilding in ISBuildingObject.lua): the ghost
-- follows the mouse, the rotate key steps nSprite 1..4 (west, north, east,
-- south), a click builds. While the button is held the pressed square stays
-- the target and vanilla reports where the mouse went through rotateMouse():
-- a device turns that way, a pipe becomes a run from the pressed square to
-- the mouse.
--
-- Pipes have nothing to turn, so their rotate key lifts the cursor a level:
-- the pipes go over the cells pointed at, laid from below. Above the ground
-- a pipe needs no floor either way.

if isServer() then return end

require "BuildingObjects/ISBuildingObject"
require "DH_Shared"

DH_Cursor = ISBuildingObject:derive("DH_Cursor")

-- nSprite -> facing.
local FACINGS = {
	radiator = { "W", "N", "E", "S" },
	inlet = { "W", "N", "E", "S" },
	pump = { "E", "S", "E", "S" },
	boiler = { "E", "S", "E", "S" },
}
-- How often the rights and the picture of a run are worked out again, in
-- calls (a few a frame).
local RECHECK = 30

local ghosts = {}
local function ghost(name)
	local sprite = ghosts[name]
	if not sprite then
		sprite = IsoSprite.new()
		sprite:LoadSingleTexture(name)
		ghosts[name] = sprite
	end
	return sprite
end

-- The pipe sprite a cell would get: its neighbours on the ground and in the
-- run being drawn.
local function maskAt(x, y, z, run)
	local mask = 0
	for _, dir in ipairs(DelHeat.DIRS) do
		local nx, ny = x + dir.dx, y + dir.dy
		local joins = run[DelHeat.key(nx, ny, z)] == true
		if not joins then
			-- Only a neighbour that takes a pipe from this side: a pump along
			-- its axis, a boiler or an intake at an outlet.
			local node = DelHeat.nodeAt(getCell():getGridSquare(nx, ny, z))
			joins = DelHeat.hasSide(DelHeat.sidesOfNode(node, nx, ny), dir.back)
		end
		if joins then mask = mask + dir.bit end
	end
	return mask
end

-- true when the cell takes no pipe for want of a floor (the server's
-- blockedThin): it lies on a floor on the ground and below it, higher up it
-- hangs in the air - there the square may well not exist yet.
local function noFloor(square, x, y, z)
	if DelHeat.needsFloor("pipe", z) then return square == nil or square:getFloor() == nil end
	return square == nil and not getWorld():isValidSquare(x, y, z)
end

-- nil when the cell takes the part, otherwise a translation key (the
-- server's blockedThin / blockedSolid, read off the sprites).
local function cellWhy(square, solid, dx, dy)
	if not square then return "IGUI_DelHeat_NotLoaded" end
	if DelHeat.nodeAt(square) then return "IGUI_DelHeat_Occupied" end
	if not square:getFloor() then return "IGUI_DelHeat_NoFloor" end
	if solid and (square:isSolid() or square:isSolidTrans() or square:getVehicleContainer()
		or DelHeat.isWater(square)) then
		return "IGUI_DelHeat_Occupied"
	end
	-- Walls inside the footprint; those along its north and west edge are fine.
	if (dx > 0 and square:has(IsoFlagType.collideW)) or (dy > 0 and square:has(IsoFlagType.collideN)) then
		return "IGUI_DelHeat_Occupied"
	end
	return nil
end

local function waterNear(x, y, z, size)
	local range = DelHeat.WATER_RANGE
	for wy = y - range, y + size.h - 1 + range do
		for wx = x - range, x + size.w - 1 + range do
			if DelHeat.isWater(getCell():getGridSquare(wx, wy, z)) then return true end
		end
	end
	return false
end

function DH_Cursor:facing()
	local list = FACINGS[self.kind]
	return list and list[self.nSprite] or nil
end

function DH_Cursor:spriteAt(facing, dx, dy)
	local kind = self.kind
	if kind == "radiator" then return DelHeat.radiatorSprite(facing) end
	if kind == "inlet" then return DelHeat.inletSprite(facing) end
	if kind == "pump" then return DelHeat.pumpSprite(facing) end
	if kind == "boiler" then return DelHeat.boilerSprite(facing, dx, dy) end
	if kind == "intake" then return DelHeat.intakeSprite(dx, dy) end
	if kind == "support" then return DelHeat.supportSprite() end
	return DelHeat.pipeSprite(0)
end

-- Vanilla asks for the sprite by nSprite; ours depends on the part.
function DH_Cursor:getSprite()
	self.chosenSprite = self:spriteAt(self:facing(), 0, 0)
	return self.chosenSprite
end

-- A pipe cursor has no turn: the key moves it a level up and back.
function DH_Cursor:rotateKey(key)
	if not self.pipes then
		ISBuildingObject.rotateKey(self, key)
		return
	end
	if not getCore():isKey(KeybindId.ROTATE_BUILDING, key) then return end
	self.lift = 1 - self.lift
	self.runKey = nil
	self.character:setHaloNote(getText(self.lift > 0 and "IGUI_DelHeat_CursorLevelUp" or "IGUI_DelHeat_CursorLevelOwn"),
		255, 255, 255, 300)
end

function DH_Cursor:rotateMouse(x, y)
	if self.pipes then
		self.endX, self.endY = x, y
		return
	end
	ISBuildingObject.rotateMouse(self, x, y)
end

-- The player walks up in DelHeat.act(), started from create().
function DH_Cursor:walkTo(x, y, z)
	return true
end

-- Translation key of why this player may not build the part at all; worked
-- out now and then, it scans the inventory.
function DH_Cursor:rights()
	self.rightsAge = (self.rightsAge or RECHECK) + 1
	if self.rightsAge > RECHECK then
		self.rightsAge = 0
		self.admin = DelHeat.isAdmin(self.character)
		self.rightsWhy = DelHeat.whyNotBuild(self.character, self.kind)
	end
	return self.rightsWhy
end

-- The run of a pipe cursor from the square vanilla gives (the pressed one
-- while the button is held) to where the mouse is: cells with what to draw.
function DH_Cursor:run(x, y, z)
	local ex, ey = x, y
	if self.endX and (self.isLeftDown or self.build) then ex, ey = self.endX, self.endY end
	local key = x .. "," .. y .. "," .. ex .. "," .. ey .. "," .. z
	self.runAge = (self.runAge or 0) + 1
	if self.runKey == key and self.runAge <= RECHECK then return self.runCells end
	self.runKey, self.runAge = key, 0
	local cells = DelHeat.path(x, y, ex, ey, z)
	local run = {}
	for _, cell in ipairs(cells) do
		run[DelHeat.key(cell.x, cell.y, cell.z)] = true
	end
	for _, cell in ipairs(cells) do
		local square = getCell():getGridSquare(cell.x, cell.y, cell.z)
		local node = DelHeat.nodeAt(square)
		if self.kind == "unpipe" then
			cell.pipe = node ~= nil and node.kind == DelHeat.PIPE
		else
			-- A cell that holds something is passed over; one on the ground
			-- without a floor stops the run.
			cell.taken = node ~= nil
			cell.bad = not cell.taken and noFloor(square, cell.x, cell.y, cell.z)
			cell.sprite = DelHeat.pipeSprite(maskAt(cell.x, cell.y, cell.z, run))
		end
	end
	self.runCells = cells
	return cells
end

-- nil when the part may go where the cursor is, otherwise the text to tell.
function DH_Cursor:why(square)
	local key = self:rights()
	if key then return getText(key) end
	if not square then return getText("IGUI_DelHeat_NotLoaded") end
	local x, y, z = square:getX(), square:getY(), square:getZ() + self.lift
	if self.pipes then
		local cells = self:run(x, y, z)
		if #cells > DelHeat.MAX_LINE then
			return getText("IGUI_DelHeat_LineTooLong", tostring(DelHeat.MAX_LINE))
		end
		if self.kind == "pipe" and #cells == 1 then
			if cells[1].taken then return getText("IGUI_DelHeat_Occupied") end
			if cells[1].bad then return getText("IGUI_DelHeat_NoFloor") end
		end
		return nil
	end
	local ax, ay, size = DelHeat.anchorOf(self.kind, self:facing(), x, y)
	for dy = 0, size.h - 1 do
		for dx = 0, size.w - 1 do
			key = cellWhy(getCell():getGridSquare(ax + dx, ay + dy, z), self.solid, dx, dy)
			if key then return getText(key) end
		end
	end
	if self.kind == "intake" and not self.admin and not waterNear(ax, ay, z, size) then
		return getText("IGUI_DelHeat_NeedWater")
	end
	return nil
end

function DH_Cursor:isValid(square)
	local why = self:why(square)
	-- A click on a red ghost says why it is red.
	if not self.isLeftDown then
		self.told = nil
	elseif why and self.told ~= why then
		self.told = why
		self.character:setHaloNote(why, 255, 255, 255, 300)
	end
	return why == nil
end

function DH_Cursor:render(x, y, z, square)
	if not self.isLeftDown and not self.build then self.endX, self.endY = nil, nil end
	local ok = self.canBeBuild == true
	if self.pipes then
		for _, cell in ipairs(self:run(x, y, z + self.lift)) do
			-- Lifted: the cell pointed at is marked, the pipe is drawn over it.
			if self.lift > 0 then
				self:getFloorCursorSprite():RenderGhostTileColor(cell.x, cell.y, z, 1, 1, 1, 0.2)
			end
			if self.kind == "unpipe" then
				if cell.pipe then
					self:getFloorCursorSprite():RenderGhostTileColor(cell.x, cell.y, cell.z, 1, 0.3, 0.3, 0.8)
				else
					self:getFloorCursorSprite():RenderGhostTileColor(cell.x, cell.y, cell.z, 1, 1, 1, 0.25)
				end
			elseif not cell.taken then
				if ok and not cell.bad then
					ghost(cell.sprite):RenderGhostTile(cell.x, cell.y, cell.z)
				else
					ghost(cell.sprite):RenderGhostTileRed(cell.x, cell.y, cell.z)
				end
			end
		end
		return
	end
	local facing = self:facing()
	local ax, ay, size = DelHeat.anchorOf(self.kind, facing, x, y)
	-- A support is a thin lattice: its ghost alone hardly shows which cell
	-- it stands on, so the cell is marked on the floor under it.
	if self.kind == "support" then
		if ok then
			self:getFloorCursorSprite():RenderGhostTileColor(x, y, z, 0.4, 1, 0.4, 0.8)
		else
			self:getFloorCursorSprite():RenderGhostTileColor(x, y, z, 1, 0.3, 0.3, 0.8)
		end
	end
	for dy = 0, size.h - 1 do
		for dx = 0, size.w - 1 do
			local sprite = ghost(self:spriteAt(facing, dx, dy))
			if ok then
				sprite:RenderGhostTile(ax + dx, ay + dy, z)
			else
				sprite:RenderGhostTileRed(ax + dx, ay + dy, z)
			end
		end
	end
end

-- Called by vanilla with the target square once the click is let go there.
function DH_Cursor:create(x, y, z, north, sprite)
	local player = self.character
	z = z + self.lift
	local here = { x = x, y = y, z = z }
	if self.pipes then
		local ex, ey = self.endX or x, self.endY or y
		self.endX, self.endY = nil, nil
		self.runKey = nil
		local length = math.abs(ex - x) + math.abs(ey - y) + 1
		if self.kind == "pipe" and length == 1 then
			DelHeat.act(player, { here }, "place", { x = x, y = y, z = z, kind = "pipe" }, DelHeat.TIME.pipe)
			return
		end
		-- The far end first; a run out into the air is laid from its start.
		local ends = { { x = ex, y = ey, z = z }, here }
		local run = { x1 = x, y1 = y, x2 = ex, y2 = ey, z = z }
		if self.kind == "pipe" then
			local count = self.admin and length or math.min(length, DelHeat.countOf(player, DelHeat.ITEM.pipe))
			DelHeat.act(player, ends, "line", run, math.min(1500, 60 + 40 * count))
		else
			DelHeat.act(player, ends, "unline", run, math.min(1500, 60 + 30 * length))
		end
		return
	end
	DelHeat.act(player, { here }, "place", { x = x, y = y, z = z, kind = self.kind, facing = self:facing() },
		DelHeat.TIME[self.kind])
	if not self.keep then getCell():setDrag(nil, self.player) end
end

-- kind: a part of DelHeat.PARTS, or "unpipe" to take pipes off.
function DH_Cursor:new(character, kind)
	local o = {}
	setmetatable(o, self)
	self.__index = self
	o:init()
	o.character = character
	o.player = character:getPlayerNum()
	o.kind = kind
	o.pipes = kind == "pipe" or kind == "unpipe"
	-- Levels above the one pointed at (pipes only, the rotate key).
	o.lift = 0
	o.solid = kind == "pump" or kind == "boiler" or kind == "intake"
	-- Pipes and radiators go down one after another; the cursor stays.
	o.keep = o.pipes or kind == "radiator" or kind == "support"
	o.noNeedHammer = true
	o.skipBuildAction = true
	-- A pump along an east-west pipe; the rest to the north / front to the south.
	o.nSprite = kind == "pump" and 1 or 2
	o.sprite = o:getSprite()
	o.northSprite = o.sprite
	return o
end

function DH_Cursor.start(player, kind)
	getCell():setDrag(DH_Cursor:new(player, kind), player:getPlayerNum())
	local hint = "IGUI_DelHeat_CursorHint"
	if kind == "pipe" then
		hint = "IGUI_DelHeat_CursorHintPipe"
	elseif kind == "unpipe" then
		hint = "IGUI_DelHeat_CursorHintUnpipe"
	elseif kind == "intake" or kind == "support" then
		hint = "IGUI_DelHeat_CursorHintPlain"
	end
	player:setHaloNote(getText(hint), 255, 255, 255, 400)
end
