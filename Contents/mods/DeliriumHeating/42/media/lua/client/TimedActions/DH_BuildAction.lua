-- Delirium Heating - a player building or taking apart a piece of the
-- heating. A client-side timer; perform() sends the command to the server,
-- which checks the tool, the item and the distance itself.

if isServer() then return end

require "TimedActions/ISBaseTimedAction"
require "DH_Shared"

DH_BuildAction = ISBaseTimedAction:derive("DH_BuildAction")

-- The cell worked on: the end of a run or the placed cell.
function DH_BuildAction:target()
	local x = self.args.x2 or self.args.x
	local y = self.args.y2 or self.args.y
	return x + 0.5, y + 0.5
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

function DH_BuildAction:new(character, command, args, time)
	local o = ISBaseTimedAction.new(self, character)
	o.command = command
	o.args = args
	o.time = math.max(1, math.floor(tonumber(time) or 200))
	o.maxTime = o:getDuration()
	return o
end
