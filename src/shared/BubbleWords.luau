--======================================================================
-- BubbleWords.luau  (ModuleScript -- ReplicatedStorage.Shared.BubbleWords)
--======================================================================
-- EIGHT WORDS A SLIDE, EVERYWHERE, WITHOUT REWRITING EVERY NPC.
--
-- Every NPC in this place hands its dialogue over as an array of strings, one per speech bubble.
-- Several of those had grown into full sentences -- "Earn coins by flying high -- save up for a
-- BIGGER STOMACH to fly even higher!" is sixteen words -- and a bubble that long is a wall of
-- text a kid skips rather than reads. Long lines also get shrunk by TextScaled until they are
-- barely legible, so the more you write the less anybody actually sees.
--
-- ===== WHY THIS IS A SPLITTER AND NOT A REWRITE =====
-- The obvious fix is to shorten every line by hand. That is a dozen files of prose to rewrite, it
-- loses whatever the writer meant, and the very next line anybody adds is long again. Instead the
-- RULE lives in code: any page over the cap is split at a natural break into as many pages as it
-- needs. Nothing is lost -- you read the same words, a slide at a time -- and lines written next
-- year obey it for free.
--
-- ===== WHERE IT BREAKS =====
-- Sentence enders first (. ! ?), then commas and dashes, then plain word boundaries as a last
-- resort. Splitting "Three waves of it, and every piece" mid-clause reads as a glitch; splitting
-- it at the comma reads as someone pausing for breath.
--
-- This is the FOOD realm's copy of CandyRealm's BubbleWords.client.luau, which does the same job
-- through _G.capBubble. It is a MODULE rather than a global because the NPCs here talk from the
-- SERVER (IslandNPCs, FarmerNPC), and a client global is not reachable from there.
--
--   local Bubble = require(game:GetService("ReplicatedStorage").Shared.BubbleWords)
--   pages = Bubble.cap(pages)
--======================================================================

local BubbleWords = {}

BubbleWords.MAX_WORDS = 8

function BubbleWords.words(t)
	local n = 0
	for _ in string.gmatch(tostring(t), "%S+") do n += 1 end
	return n
end

-- split one over-long line into <= cap chunks, preferring natural pauses
local function splitOne(text, out, cap)
	local w = {}
	for word in string.gmatch(text, "%S+") do w[#w + 1] = word end
	if #w <= cap then out[#out + 1] = text; return end

	local i = 1
	while i <= #w do
		local last = math.min(i + cap - 1, #w)
		local cut = last
		if last < #w then
			-- Look back from the cap for a word that ENDS a clause, so the break lands on a pause the
			-- reader would have made anyway. Never search past halfway back, or a comma near the start
			-- would leave a two-word slide.
			local floor = i + math.max(1, math.floor(cap / 2)) - 1
			for j = last, floor, -1 do
				if string.match(w[j], "[%.%!%?]$") then cut = j; break end
			end
			if cut == last then
				for j = last, floor, -1 do
					if string.match(w[j], "[,;:%-]$") then cut = j; break end
				end
			end
		end
		out[#out + 1] = table.concat(w, " ", i, cut)
		i = cut + 1
	end
end

-- THE ENTRY POINT. Takes a pages array and gives back one where nothing is over the cap.
-- Defensive on purpose: an NPC passing nil, a bare string, or a table with non-strings in it must
-- never lose its dialogue over a formatting nicety.
function BubbleWords.cap(pages, maxWords)
	local cap = tonumber(maxWords) or BubbleWords.MAX_WORDS
	if type(pages) == "string" then pages = { pages } end
	if type(pages) ~= "table" then return pages end
	local out = {}
	for _, p in ipairs(pages) do
		if type(p) == "string" then
			splitOne(p, out, cap)
		else
			out[#out + 1] = p            -- not a string: pass it through untouched
		end
	end
	return out
end

return BubbleWords
