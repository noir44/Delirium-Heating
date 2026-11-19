-- Delirium Heating - vanilla's sledgehammer destroys any object that is not
-- on its short list of exceptions (ISDestroyCursor:canDestroy), a pipe or a
-- boiler included, and the network would not know. Only an admin removes
-- them, from the context menu.
--
-- Client UI, but it lives in server/ next to ISDestroyCursor: on connecting
-- client/ is loaded before server/, and from client/ the require below
-- failed ("attempted index: canDestroy of non-table").

if isServer() then return end

require "BuildingObjects/ISDestroyCursor"
require "DH_Shared"

local canDestroy = ISDestroyCursor.canDestroy

function ISDestroyCursor:canDestroy(object)
	local sprite = object and object.getSprite and object:getSprite()
	if sprite and DelHeat.parseSprite(sprite:getName()) then return false end
	return canDestroy(self, object)
end
