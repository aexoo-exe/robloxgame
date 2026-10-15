-- Player toggles for combat presentation, read live from attributes on the local player so a
-- settings menu (or the Studio command bar) can flip them:
--   ReducedEffects       true: ultimates skip their extra layers and screen dimming
--   ReducedCameraMotion  true: no camera pushes from ultimates (shake stays capped by tier)
-- Presentation only.

local Players = game:GetService("Players")

local EffectSettings = {}

local function flag(name: string): boolean
	local player = Players.LocalPlayer
	return player ~= nil and player:GetAttribute(name) == true
end

function EffectSettings.reducedEffects(): boolean
	return flag("ReducedEffects")
end

function EffectSettings.reducedCameraMotion(): boolean
	return flag("ReducedCameraMotion")
end

return EffectSettings
