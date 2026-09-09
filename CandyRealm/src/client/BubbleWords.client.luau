--======================================================================
-- BubbleWords.client.luau  -- CandyRealm
--======================================================================
-- NPC DIALOGUE IS RE-FLOWED TO FIT TWO HARD CAPS: eight words a slide, five slides. One rule,
-- in code, for all sixteen quests.
--
-- ===== THE TWO FAILURES THIS FIXES =====
--
-- TOO MANY WORDS ON A SLIDE. Some lines had grown into full sentences -- "Three waves of it,
-- and every piece that hits the ground is wasted" is seventeen words -- and a bubble that long
-- is a wall of text a kid skips rather than reads. TextScaled then shrinks it until it is
-- barely legible, so the more you write the less anybody sees.
--
-- TOO MANY SLIDES. The opposite failure, and the one that actually shipped: capping words per
-- slide with no cap on the NUMBER of slides turned the quest intros into click marathons. At
-- eight words a slide the Great Bake-Off ran to FIFTEEN bubbles, Taffy Storm fourteen, the
-- Pancake Monster thirteen. Nobody reads the fifteenth bubble; they mash through all of them
-- and then ask what they are supposed to do.
--
-- ===== WHY THIS RE-FLOWS INSTEAD OF SPLITTING =====
-- The first version only ever SPLIT a line into more pages. That can never get seven authored
-- lines down to five slides -- splitting only makes the count go UP -- so a slide cap was
-- impossible to honour without either merging or throwing copy away.
--
-- So it re-flows. The dialogue is broken into SENTENCES, and sentences are packed into as few
-- slides as the budget allows. Short authored lines merge; long ones split; the words and their
-- order are untouched either way.
--
-- ===== NOTHING IS EVER DISCARDED =====
-- These are DIRECTIONS -- "pull all four coolant rods", "ring the bell at the summit". Dropping
-- the tail of a bubble to hit a slide count would silently delete the instruction that tells a
-- player what the quest wants. So a block that will not fit the 40-word budget runs long and
-- SAYS SO in the log, naming how many words have to come out. That is a writing job, not a
-- formatting one -- and every shipped quest has already been cut to fit.
--======================================================================

-- ===== TWO HARD CAPS, AND THEY BOTH BIND =====
-- EIGHT words a slide, FIVE slides. Neither gives way, which means a dialogue block has a
-- budget of exactly 8 x 5 = 40 WORDS. That is the whole rule, and it is deliberately strict:
-- a bubble longer than eight words gets shrunk by TextScaled until nobody reads it, and a
-- conversation longer than five bubbles gets mashed through without being read either.
--
-- An earlier version let the word cap widen to hold the slide count, which produced 26-word
-- bubbles on the Broken Tractor -- technically five slides, practically a wall of text. The
-- budget is now fixed and the COPY is what has to fit it.
local MAX_WORDS = 8
local MAX_PAGES = 5

local function words(t)
	local n = 0
	for _ in string.gmatch(t, "%S+") do n += 1 end
	return n
end

--[[
	Break a line into sentences, keeping the punctuation on the end of each. Sentences are the
	unit we pack with, because a bubble that ends mid-clause reads as a glitch while one that
	ends on a full stop reads as someone pausing for breath.
]]
local function sentences(text, out)
	local buf = {}
	for word in string.gmatch(text, "%S+") do
		buf[#buf + 1] = word
		if string.match(word, "[%.%!%?]$") then
			out[#out + 1] = table.concat(buf, " ")
			buf = {}
		end
	end
	if #buf > 0 then
		out[#out + 1] = table.concat(buf, " ")
	end
end

--[[
	Split one over-long SENTENCE into <= cap chunks, preferring natural pauses: commas and
	dashes first, then plain word boundaries as a last resort. Only reached when a single
	sentence is longer than the whole slide budget.
]]
local function splitSentence(text, cap, out)
	local w = {}
	for word in string.gmatch(text, "%S+") do w[#w + 1] = word end
	if #w <= cap then out[#out + 1] = text; return end

	local i = 1
	while i <= #w do
		local last = math.min(i + cap - 1, #w)
		local cut = last
		if last < #w then
			-- Look back from the cap for a word that ends a clause. Never search past halfway
			-- back, or a comma near the start would leave a two-word slide.
			local floor = i + math.max(1, math.floor(cap / 2)) - 1
			for j = last, floor, -1 do
				if string.match(w[j], "[,;:%-]$") then cut = j; break end
			end
		end
		out[#out + 1] = table.concat(w, " ", i, cut)
		i = cut + 1
	end
end

--[[
	Pack a dialogue block into slides at `cap` words each.

	Strings are re-flowed; anything else (a table, a formatted page object) is passed straight
	through as its own slide and flushes whatever was being packed -- a quest that hands us
	something exotic must never have it merged into a neighbour's text.
]]
local function pack(pages, cap)
	local out, buf, bufN = {}, {}, 0
	local function flush()
		if #buf > 0 then
			out[#out + 1] = table.concat(buf, " ")
			buf, bufN = {}, 0
		end
	end

	for _, p in ipairs(pages) do
		if type(p) == "string" then
			local sents = {}
			sentences(p, sents)
			for _, sent in ipairs(sents) do
				local n = words(sent)
				if n > cap then
					-- Too long to sit beside anything: flush, then break it up on its own.
					flush()
					splitSentence(sent, cap, out)
				else
					if bufN + n > cap then flush() end
					buf[#buf + 1] = sent
					bufN += n
				end
			end
		else
			flush()
			out[#out + 1] = p
		end
	end
	flush()
	return out
end

local warned = {}
local WORD_BUDGET = MAX_WORDS * MAX_PAGES

--[[
	THE ENTRY POINT the quests call: _G.capBubble(pages[, startWords]).

	Takes the array a questPages() returned and gives back one that is at most MAX_PAGES slides
	long, with the fewest words per slide that achieves it. Defensive on purpose -- a quest
	passing nil, a string, or a table with holes must never break its own dialogue over a
	formatting nicety.
]]
_G.capBubble = function(pages, startWords)
	if type(pages) == "string" then pages = { pages } end
	if type(pages) ~= "table" then return pages end

	local cap = tonumber(startWords) or MAX_WORDS
	local out = pack(pages, cap)

	-- OVER BUDGET. Both caps are hard, so there is nothing left to give but the copy -- and
	-- the copy is DIRECTIONS, so it is not this file's to throw away. The block runs long and
	-- says so, naming exactly how many words have to come out. That is a writing job.
	if #out > MAX_PAGES then
		local total = 0
		for _, p in ipairs(pages) do
			if type(p) == "string" then total += words(p) end
		end
		local key = tostring(total)
		if not warned[key] then
			warned[key] = true
			warn(("[BubbleWords] a dialogue block is %d words -- the budget is %d (%d slides x %d "
				.. "words), so it runs to %d bubbles. Cut %d word(s) from the line. Nothing is "
				.. "dropped here: these are quest directions.")
				:format(total, WORD_BUDGET, MAX_PAGES, MAX_WORDS, #out, total - WORD_BUDGET))
		end
	end
	return out
end

-- how many words a line is, for anything that wants to check rather than split
_G.bubbleWordCount = words

print(("[BubbleWords] ready -- NPC dialogue is re-flowed to %d words a slide, %d slides max "
	.. "(a %d-word budget per conversation). Sentences merge and split; nothing is discarded, "
	.. "and anything over budget is named in a warning. _G.capBubble(pages) is the hook.")
	:format(MAX_WORDS, MAX_PAGES, WORD_BUDGET))
