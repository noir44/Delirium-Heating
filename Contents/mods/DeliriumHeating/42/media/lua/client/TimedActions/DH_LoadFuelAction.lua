-- Delirium Heating - throwing fuel into the boiler's furnace. A client-side
-- timer; perform() sends the item ids to the server, which finds the items
-- itself, takes them and counts the fuel.

if isServer() then return end

require "TimedActions/ISBaseTimedAction"
require "DH_Shared"

DH_LoadFuelAction = ISBaseTimedAction:derive("DH_LoadFuelAction")

function DH_LoadFuelAction:centre()
	local size = DelHeat.BOILER_SIZE[self.node.facing] or DelHeat.BOILER_SIZE.S
	return self.node.x + size.w / 2, self.node.y + size.h / 2
end

function DH_LoadFuelAction:isValid()
	local distance = DelHeat.boilerDistance(self.node.x, self.node.y, self.node.facing,
		self.character:getX(), self.character:getY())
	return distance <= DelHeat.REACH
end

function DH_LoadFuelAction:waitToStart()
	self.character:faceLocation(self:centre())
	return self.character:shouldBeTurning()
end

function DH_LoadFuelAction:update()
	self.character:faceLocation(self:centre())
	self.character:setMetabolicTarget(Metabolics.HeavyDomestic)
end

function DH_LoadFuelAction:start()
	self:setActionAnim("Loot")
	self.character:SetVariable("LootPosition", "Mid")
end

function DH_LoadFuelAction:stop()
	ISBaseTimedAction.stop(self)
end

function DH_LoadFuelAction:perform()
	DelHeat.send("load", { x = self.node.x, y = self.node.y, z = self.node.z, ids = self.ids })
	-- needed to remove from queue / start next.
	ISBaseTimedAction.perform(self)
end

function DH_LoadFuelAction:getDuration()
	if self.character:isTimedActionInstant() then return 1 end
	return math.min(400, 60 + #self.ids * 20)
end

function DH_LoadFuelAction:new(character, node, ids)
	local o = ISBaseTimedAction.new(self, character)
	o.node = node
	o.ids = ids
	o.maxTime = o:getDuration()
	return o
end
