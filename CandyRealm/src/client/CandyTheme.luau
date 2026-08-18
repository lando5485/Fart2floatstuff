--!strict
--[[
	CandyTheme.luau  (StarterPlayerScripts.CandyTheme)

	The Space Realm color palette. The HUD LAYOUT mirrors Fart to Float exactly;
	only the PALETTE differs — dark/space-blue backgrounds, neon glow accents,
	planet-tinted highlights. Keeping the palette in one module makes a future
	re-skin a one-file change.
]]

local CandyTheme = {}

-- Core palette ---------------------------------------------------------------
CandyTheme.Background = Color3.fromRGB(10, 14, 32)     -- deep space navy
CandyTheme.Panel = Color3.fromRGB(58, 26, 54)          -- panel fill (deep raspberry)
CandyTheme.PanelStroke = Color3.fromRGB(255, 138, 196) -- glowing candy-pink edge
CandyTheme.TextPrimary = Color3.fromRGB(255, 248, 242) -- warm cream
CandyTheme.TextMuted = Color3.fromRGB(226, 178, 206)   -- soft sugar pink

-- Neon accents ---------------------------------------------------------------
-- DEFAULT ACCENT. The field name is inherited from the Space Realm original so NotifyCenter.luau is a
-- byte-identical port apart from the module name -- read it as "the accent colour", not "cyan".
CandyTheme.NeonCyan = Color3.fromRGB(255, 122, 190)    -- candy pink: banner glow / meter fill
CandyTheme.NeonMagenta = Color3.fromRGB(255, 86, 220)
CandyTheme.CoinGold = Color3.fromRGB(255, 214, 92)     -- coin counter

-- Transparency used for the soft "glow" stroke layer.
CandyTheme.GlowTransparency = 0.35

-- Per-planet accent tint, used to color the planet label + meter glow so the
-- HUD subtly recolors as the player travels Mercury -> Neptune.
CandyTheme.PlanetTint = {
	Mercury = Color3.fromRGB(170, 170, 170),
	Venus = Color3.fromRGB(232, 178, 96),
	Earth = Color3.fromRGB(80, 160, 255),
	Mars = Color3.fromRGB(226, 102, 70),
	Jupiter = Color3.fromRGB(214, 168, 122),
	Saturn = Color3.fromRGB(236, 214, 150),
	Uranus = Color3.fromRGB(150, 224, 224),
	Neptune = Color3.fromRGB(86, 120, 240),
}

--[[ Tint for a planet name, falling back to neon cyan for anything unknown. ]]
function CandyTheme.tintFor(planetName: string): Color3
	return CandyTheme.PlanetTint[planetName] or CandyTheme.NeonCyan
end

-- Glossy-panel restyle palette (TAP TO FART button + Astro Stomach bar) -------
CandyTheme.StarfieldFill = Color3.fromRGB(44, 18, 42)    -- deep cocoa-plum: the fill the sprinkles sit on
CandyTheme.BorderBlueLight = Color3.fromRGB(130, 205, 255)
CandyTheme.BorderBlueDeep = Color3.fromRGB(40, 92, 214)
CandyTheme.GlowBlue = Color3.fromRGB(70, 150, 255)       -- soft outer glow behind the panels
CandyTheme.CounterBlue = Color3.fromRGB(91, 200, 255)    -- the "current" number in the X / Y counter
CandyTheme.CounterGray = Color3.fromRGB(174, 184, 204)   -- the "/ max" part of the counter

-- Unified Astro Stomach panel (the one bottom-centre HUD card: progress bar + shop CTA) ------
-- Deliberately flatter and softer than the old glossy pills: smooth gradients, one thick cyan edge, no starfield.
CandyTheme.PanelTop = Color3.fromRGB(88, 40, 82)         -- panel body gradient, top
CandyTheme.PanelBottom = Color3.fromRGB(46, 20, 44)      -- panel body gradient, bottom
CandyTheme.PanelRecess = Color3.fromRGB(9, 12, 32)       -- recessed wells (the progress track)
CandyTheme.EdgeCyan = Color3.fromRGB(88, 226, 255)       -- the thick, soft cyan outline + its outer bloom
CandyTheme.CtaPurple = Color3.fromRGB(150, 108, 255)     -- shop CTA gradient, left/top
CandyTheme.CtaBlue = Color3.fromRGB(74, 130, 255)        -- shop CTA gradient, right/bottom

--[[ A smooth two-stop gradient on a panel. The frame's BackgroundColor3 should be white so the gradient reads
     true. `rotation` defaults to 90 (vertical, top → bottom). Returns the gradient. ]]
function CandyTheme.addVerticalGradient(frame: Instance, top: Color3, bottom: Color3, rotation: number?)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(top, bottom)
	g.Rotation = rotation or 90
	g.Parent = frame
	return g
end

--[[ An INNER shadow: a rounded overlay that darkens the top edge (and, faintly, the bottom) so the panel reads as
     recessed//inset rather than flat. Sits at ZIndex 0 — above the fill, below the content. `corner` accepts a
     UDim (e.g. UDim.new(1, 0) for a capsule) or a plain pixel radius. `strength` is the top darkness (0..1). ]]
function CandyTheme.addInnerShadow(frame: Instance, corner: any, strength: number?)
	local s = strength or 0.68
	local sh = Instance.new("Frame")
	sh.Name = "InnerShadow"
	sh.BackgroundColor3 = Color3.fromRGB(0, 2, 12)
	sh.BorderSizePixel = 0
	sh.Size = UDim2.fromScale(1, 1)
	sh.ZIndex = 0
	local c = Instance.new("UICorner")
	if typeof(corner) == "UDim" then
		c.CornerRadius = corner -- capsule wells pass UDim.new(1, 0)
	else
		c.CornerRadius = UDim.new(0, corner or 12)
	end
	c.Parent = sh
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, s),
		NumberSequenceKeypoint.new(0.28, 1),
		NumberSequenceKeypoint.new(0.82, 1),
		NumberSequenceKeypoint.new(1, math.clamp(s + 0.18, 0, 1)),
	})
	g.Parent = sh
	sh.Parent = frame
	return sh
end

--[[ The panel's signature edge: a THICK, SOFT cyan outline. Unlike addBlueBorder (which runs all the way down to a
     deep navy) every stop stays in the cyan family, so it reads as one soft colour rather than a two-tone rim. ]]
function CandyTheme.addCyanEdge(frame: Instance, thickness: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = thickness or 3
	stroke.Color = Color3.fromRGB(255, 255, 255) -- the gradient supplies the actual colour
	stroke.Transparency = 0.06
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(168, 244, 255)),
		ColorSequenceKeypoint.new(0.5, CandyTheme.EdgeCyan),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(56, 176, 236)),
	})
	g.Rotation = 90
	g.Parent = stroke
	stroke.Parent = frame
	return stroke
end

-- Procedural restyle helpers (asset-free; no external rbxassetid images) ------
-- All build the "glossy space" look from gradients/strokes/frames only, so they stay phone-performant: a fixed
-- handful of static instances per panel and no per-frame work.

--[[ Scatter small static "stars" inside a panel. Deterministic via `seed`; sets ClipsDescendants so the dots
     stay inside the rounded shape. ]]
function CandyTheme.addStarfield(frame: Instance, count: number?, seed: number?)
	(frame :: any).ClipsDescendants = true
	local rng = Random.new(seed or 1)
	for i = 1, (count or 16) do
		local s = rng:NextInteger(1, 2)
		local dot = Instance.new("Frame")
		dot.Name = "Star"
		dot.BorderSizePixel = 0
		dot.BackgroundColor3 = (i % 5 == 0) and CandyTheme.NeonCyan or Color3.fromRGB(222, 232, 255)
		dot.BackgroundTransparency = 0.45 + rng:NextNumber() * 0.35
		dot.Size = UDim2.fromOffset(s, s)
		dot.Position = UDim2.fromScale(rng:NextNumber(), rng:NextNumber())
		dot.ZIndex = 0 -- behind the content, above the panel fill
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = dot
		dot.Parent = frame
	end
end

--[[ A bright blue GRADIENT border (UIStroke + UIGradient). Returns the stroke so callers can pulse it. ]]
function CandyTheme.addBlueBorder(frame: Instance, thickness: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = thickness or 2.5
	stroke.Color = Color3.fromRGB(255, 255, 255) -- the gradient supplies the actual colour
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border -- border the RECTANGLE (works on TextButtons too, not their text)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, CandyTheme.BorderBlueLight),
		ColorSequenceKeypoint.new(0.5, CandyTheme.NeonCyan),
		ColorSequenceKeypoint.new(1, CandyTheme.BorderBlueDeep),
	})
	g.Rotation = 90
	g.Parent = stroke
	stroke.Parent = frame
	return stroke
end

--[[ A bright NEON gradient border in an arbitrary THEME colour (lighter top → colour → deeper bottom). Borders
     the rectangle (ApplyStrokeMode.Border) so it works on TextButtons too. Returns the stroke. ]]
function CandyTheme.addNeonBorder(frame: Instance, color: Color3, thickness: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = thickness or 2.5
	stroke.Color = Color3.fromRGB(255, 255, 255) -- the gradient supplies the actual colour
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, color:Lerp(Color3.new(1, 1, 1), 0.55)),
		ColorSequenceKeypoint.new(0.5, color),
		ColorSequenceKeypoint.new(1, color:Lerp(Color3.new(0, 0, 0), 0.4)),
	})
	g.Rotation = 90
	g.Parent = stroke
	stroke.Parent = frame
	return stroke
end

--[[ A subtle top-lit gloss sheen: a faint white highlight over the top, fading down. Sits at ZIndex 0 (above
     the fill/stars, below the content). `cornerRadius` should match the panel's. ]]
--[[ A polished, VIVID neon-blue edge (bright cyan → cyan → vivid blue; no pale/gray light end), the matched border
     for the HUD's glossy top panels (planet pill, coin pill, settings gear, STATS). White base so the gradient
     supplies the colour; Border mode so it borders the rounded rectangle (works on TextButtons too). ]]
function CandyTheme.addNeonEdge(frame: Instance, thickness: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = thickness or 2.5
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(120, 235, 255)),
		ColorSequenceKeypoint.new(0.5, CandyTheme.NeonCyan),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(56, 120, 255)),
	})
	g.Rotation = 90
	g.Parent = stroke
	stroke.Parent = frame
	return stroke
end

function CandyTheme.addGloss(frame: Instance, cornerRadius: number?)
	local hi = Instance.new("Frame")
	hi.Name = "Gloss"
	hi.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	hi.BorderSizePixel = 0
	hi.Position = UDim2.fromScale(0, 0)
	hi.Size = UDim2.new(1, 0, 0.52, 0)
	hi.ZIndex = 0
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, cornerRadius or 12); c.Parent = hi
	local g = Instance.new("UIGradient")
	g.Rotation = 90
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.8),
		NumberSequenceKeypoint.new(1, 1),
	})
	g.Parent = hi
	hi.Parent = frame
	return hi
end

--[[ Glossy 3D text: a vertical sheen gradient (lighter top → cooler/deeper bottom) on the text. Pair with a
     dark UIStroke (outline) and a shadow clone for the mockup's chunky 3D look. Returns the gradient. ]]
function CandyTheme.addTextGloss(textObj: Instance)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(226, 240, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(160, 196, 250)),
	})
	g.Rotation = 90
	g.Parent = textObj
	return g
end

--[[ Depth behind a panel: a soft blue OUTER GLOW halo + a stronger DROP SHADOW, both as siblings rendered
     behind the panel (so the panel reads as a beveled, floating 3D card). Works for any AnchorPoint — the
     layers are centred on the panel and the shadow is nudged down. The host ScreenGui should use
     ZIndexBehavior.Sibling so the negative-offset ZIndex keeps these behind the panel. Returns (glow, shadow). ]]
function CandyTheme.addPanelDepth(panel: GuiObject, opts: { glowColor: Color3?, corner: number?, glowSpread: number?, shadowSpread: number?, shadowDrop: number? }?)
	opts = opts or {}
	local glowColor = opts.glowColor or CandyTheme.GlowBlue
	local cornerRadius = (opts.corner or 16) + 4
	local glowSpread = opts.glowSpread or 7
	local shadowSpread = opts.shadowSpread or 5
	local shadowDrop = opts.shadowDrop or 5
	local parent = panel.Parent
	local a, pos, size, baseZ = panel.AnchorPoint, panel.Position, panel.Size, panel.ZIndex

	local function makeLayer(name: string, spread: number, dropY: number, color: Color3, transparency: number, z: number): Frame
		local f = Instance.new("Frame")
		f.Name = name
		f.AnchorPoint = a
		-- Centre the larger layer on the panel regardless of AnchorPoint, then bias the shadow down.
		f.Position = UDim2.new(
			pos.X.Scale, pos.X.Offset + spread * (2 * a.X - 1),
			pos.Y.Scale, pos.Y.Offset + spread * (2 * a.Y - 1) + dropY)
		f.Size = UDim2.new(size.X.Scale, size.X.Offset + spread * 2, size.Y.Scale, size.Y.Offset + spread * 2)
		f.BackgroundColor3 = color
		f.BackgroundTransparency = transparency
		f.BorderSizePixel = 0
		f.ZIndex = z
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, cornerRadius); c.Parent = f
		f.Parent = parent
		return f
	end

	local shadow = makeLayer(panel.Name .. "Shadow", shadowSpread, shadowDrop, Color3.fromRGB(0, 0, 0), 0.45, baseZ - 2)
	local glow = makeLayer(panel.Name .. "Glow", glowSpread, 0, glowColor, 0.68, baseZ - 1)
	return glow, shadow
end

return CandyTheme
