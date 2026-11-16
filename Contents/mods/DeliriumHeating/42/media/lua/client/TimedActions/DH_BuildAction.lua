-- Delirium Heating - a player building or taking apart a piece of the
-- heating. A client-side timer; perform() sends the command to the server,
-- which checks the tool, the item and the distance itself.

if isServer() then return end

require "TimedActions/ISBaseTimedAction"
require "DH_Shared"

DH_BuildAction = ISBaseTimedAction:derive("DH_BuildAction")

-- The cell worked at: the placed one, or the end of a run the player
-- stands by.
function DH_BuildAction:target()
	return self.spot.x + 0.5, self.spot.y + 0.5
end

function DH_BuildAction:isValid()
	if not DelHeat.hasTool(self.character) then return false end
	local x, y = self:target()
	local dx, dy = x - self.character:getX(), y - self.character:getY()
	return dx * dx + dy * dy <= (DelHeat.BUILD_REACH + 1) * (DelHeat.BUILD_REACH + 1)
end

function DH_BuildAction:waitToStart()
	self.character:faceLocation(self:target())
	return self.character:shouldBeTurning()
end

function DH_BuildAction:update()
	self.character:faceLocation(self:target())
	self.character:setMetabolicTarget(Metabolics.HeavyWork)
end

function DH_BuildAction:start()
	self:setActionAnim("BuildLow")
end

function DH_BuildAction:stop()
	ISBaseTimedAction.stop(self)
end

function DH_BuildAction:perform()
	DelHeat.send(self.command, self.args)
	-- needed to remove from queue / start next.
	ISBaseTimedAction.perform(self)
end

function DH_BuildAction:getDuration()
	if self.character:isTimedActionInstant() then return 1 end
	return self.time
end

function DH_BuildAction:new(character, command, args, time, spot)
	local o = ISBaseTimedAction.new(self, character)
	o.command = command
	o.args = args
	o.spot = spot
	o.time = math.max(1, math.floor(tonumber(time) or 200))
	o.maxTime = o:getDuration()
	return o
end
