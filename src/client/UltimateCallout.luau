-- A caster callout for an ultimate: a short, readable marker on the caster that says "this one is
-- casting" from the match camera. A Highlight outline in the ultimate's theme color over the whole
-- figure (drawn on top of everything, so it reads through other units), fading in fast, held, then
-- fading out; and a quick small flat ring flashing on the ground under them (VfxRecipe.meshRing,
-- within the cast's ring budget). Times run on the effects' clock (slow motion slows them).
-- Presentation only.
--
-- Use (from an ultimate module): UltimateCallout.mark(run.view, color, seconds)
--   seconds: how long the outline is held at full strength (the windup and the strikes)
--   opts.ring = false: no ground ring; opts.fill: the outline's fill transparency (default 0.85)

local RunService = game:GetService("RunService")

local ImpactEffects = require(script.Parent.ImpactEffects)
local VfxRecipe = require(script.Parent.VfxRecipe)

local UltimateCallout = {}

local FADE_IN = 0.08
local FADE_OUT = 0.3
local RING = 0.6 -- the ground ring's start diameter, a share of the figure's height (it grows 3x)

export type Options = { ring: boolean?, fill: number? }

function UltimateCallout.mark(view: any, color: Color3, seconds: number, opts: Options?)
	local part = view and view.part
	if not part or not part.Parent then
		return
	end
	local o = opts or {}
	-- The outline: over the hitbox and everything under it (the whole figure; the hitbox itself is
	-- invisible and draws nothing).
	local highlight = Instance.new("Highlight")
	highlight.Name = "UltimateCallout"
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.FillColor = color
	highlight.OutlineColor = color
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 1
	highlight.Adornee = part
	highlight.Parent = part
	local fill = o.fill or 0.85
	local startsAt = ImpactEffects.now()
	local connection: RBXScriptConnection? = nil
	connection = RunService.RenderStepped:Connect(function()
		local t = ImpactEffects.now() - startsAt
		local strength
		if t < 0 or t > FADE_IN + seconds + FADE_OUT or not highlight.Parent then
			strength = 0
		elseif t < FADE_IN then
			strength = t / FADE_IN
		elseif t < FADE_IN + seconds then
			strength = 1
		else
			strength = 1 - (t - FADE_IN - seconds) / FADE_OUT
		end
		-- Done, or the clock was reset under it (a preview ended): gone.
		if strength <= 0 and (t < 0 or t > FADE_IN) then
			if connection then
				connection:Disconnect()
			end
			highlight:Destroy()
			return
		end
		highlight.OutlineTransparency = 1 - strength
		highlight.FillTransparency = 1 - (1 - fill) * strength
	end)
	if o.ring ~= false then
		local ground = part.Position - Vector3.new(0, part.Size.Y / 2, 0)
		VfxRecipe.meshRing(ground, part.Size.Y * RING, color, 0.3)
	end
end

return UltimateCallout
