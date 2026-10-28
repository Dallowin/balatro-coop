-- The partner's side of the board, shown between our jokers and the play area:
-- their hand (left) and jokers (right), with the cards they select raised.
--
-- Each client streams its own side:
--   'state'   snapshot of hand/jokers/stats whenever it changes
--   'play'    the cards just played  -> moved to a partner play area
--   'discard' the cards just discarded -> dissolve
--   'step'    every scoring popup (+Mult, X2, $3...) -> replayed on our copies
--   'joker_state' what each joker has built up (its ability table: X Mult,
--             +Chips, counters, stickers) -> put into our copies, so their
--             descriptions show the partner's real numbers
--
-- Copies are display-only and live in their own CardAreas, never in G.hand
-- or G.jokers, so no joker or game rule ever counts them. Cards are matched
-- by the partner's sort_id, so an unchanged card is never rebuilt.
--
-- Clicking a partner hand card marks it as a tarot target (see domain/tarot.lua).

COOP.PV = COOP.PV or {}
local PV = COOP.PV

local HAND_SCALE = 0.5
local JOKER_SCALE = 0.5
local PLAY_SCALE = 1 -- same size as our own played cards
local SEND_EVERY = 0.15

function PV.reset()
	PV.remove()
	PV.partner = nil -- last snapshot received
	PV.gone = {} -- id -> time it was played/discarded, ignored in snapshots for a moment
	PV.play_pending = false
	PV.last_sent = nil
	PV.last_jokers_sent = nil
	PV.joker_state = {} -- partner joker id -> ability values
	PV.send_timer = 0
end

-- Sending ------------------------------------------------------------------

local function encode(card)
	return table.concat({
		card.sort_id,
		card.config.card_key or '', -- playing card, e.g. 'H_A'; '' for jokers
		card.config.center.key,
		card.edition and card.edition.key or '',
		card.seal or '',
		card.highlighted and '1' or '',
		card.ability and card.ability.coop_uid or '', -- shared deck id (Shared Hand)
	}, '|')
end

function PV.encode_cards(cards)
	local out = {}
	for _, c in ipairs(cards or {}) do
		out[#out + 1] = encode(c)
	end
	return table.concat(out, ';')
end

function PV.update_send(dt)
	PV.send_timer = PV.send_timer + dt
	if PV.send_timer < SEND_EVERY or not G.GAME or not G.jokers or not G.hand then
		return
	end
	PV.send_timer = 0
	local snap = {
		hand = PV.encode_cards(G.hand.cards),
		jokers = PV.encode_cards(G.jokers.cards),
		hands_left = G.GAME.current_round.hands_left or 0,
		discards_left = G.GAME.current_round.discards_left or 0,
	}
	local sig = snap.hand .. '#' .. snap.jokers .. '#' .. snap.hands_left .. '#' .. snap.discards_left
	if sig ~= PV.last_sent then
		PV.last_sent = sig
		COOP.send('state', snap)
	end
	PV.send_joker_state()
end

-- Joker values ---------------------------------------------------------------

-- A JSON-safe copy of an ability table: numbers, strings, booleans and nested
-- tables only, number keys as '@<n>' (JSON objects can't mix key types).
local function plain(v, depth)
	local t = type(v)
	if t == 'number' then
		return (v == v and v ~= math.huge and v ~= -math.huge) and v or nil
	elseif t == 'string' or t == 'boolean' then
		return v
	elseif t == 'table' and depth < 3 then
		local out = {}
		for k, x in pairs(v) do
			local key = type(k) == 'number' and ('@' .. k) or type(k) == 'string' and k or nil
			local px = key and plain(x, depth + 1)
			if px ~= nil then
				out[key] = px
			end
		end
		return out
	end
	return nil
end

local function restore(v)
	if type(v) ~= 'table' then
		return v
	end
	local out = {}
	for k, x in pairs(v) do
		local n = type(k) == 'string' and k:match('^@(%-?%d+)$')
		out[n and tonumber(n) or k] = restore(x)
	end
	return out
end

-- stable text of a value, to notice changes
local function signature(v)
	if type(v) ~= 'table' then
		return tostring(v)
	end
	local keys = {}
	for k in pairs(v) do
		keys[#keys + 1] = k
	end
	table.sort(keys)
	local parts = {}
	for _, k in ipairs(keys) do
		parts[#parts + 1] = k .. '=' .. signature(v[k])
	end
	return '{' .. table.concat(parts, ',') .. '}'
end

function PV.send_joker_state()
	local data, parts = {}, {}
	for _, card in ipairs(G.jokers.cards) do
		local ab = plain(card.ability, 0) or {}
		ab._debuff = card.debuff and true or false
		data[#data + 1] = { id = card.sort_id, ab = ab }
		parts[#parts + 1] = card.sort_id .. signature(ab)
	end
	local sig = table.concat(parts, ';')
	if sig ~= PV.last_jokers_sent then
		PV.last_jokers_sent = sig
		COOP.send('joker_state', { data = data })
	end
end

local function apply_joker_state(card)
	local ab = card and PV.joker_state and PV.joker_state[card.coop_id]
	if not ab then
		return
	end
	for k, v in pairs(ab) do
		if k == '_debuff' then
			card.debuff = v and true or false
		else
			card.ability[k] = restore(v)
		end
	end
end

-- Bridge's hidden copy of a partner joker gets the same values.
function PV.apply_joker_state_to(card, id)
	if card then
		card.coop_id = id
		apply_joker_state(card)
	end
end

function PV.on_partner_joker_state(data)
	PV.joker_state = {}
	for _, e in ipairs(data) do
		if type(e) == 'table' and tonumber(e.id) and type(e.ab) == 'table' then
			PV.joker_state[tonumber(e.id)] = e.ab
		end
	end
	for _, card in pairs(PV.joker_cards or {}) do
		apply_joker_state(card)
	end
end

-- Scoring popups: send each one with the card it belongs to.
local COLOURS = { 'MULT', 'CHIPS', 'MONEY', 'XMULT', 'FILTER', 'GREEN', 'RED', 'BLUE', 'PURPLE', 'GOLD', 'DARK_EDITION', 'ATTENTION', 'SECONDARY_SET' }

local function colour_name(c)
	if not c then
		return ''
	end
	for _, name in ipairs(COLOURS) do
		if G.C[name] == c then
			return name
		end
	end
	return ''
end

function PV.capture_step(card, eval_type, amt, extra)
	if not card or not card.sort_id or type(amt) ~= 'number' and amt ~= nil then
		return
	end
	local where
	if card.area == G.play then
		where = 'play'
	elseif card.area == G.hand then
		where = 'hand'
	elseif card.area == G.jokers then
		where = 'jokers'
	else
		return
	end
	local message = extra and extra.message
	COOP.send('step', {
		id = card.sort_id,
		where = where,
		eval_type = tostring(eval_type),
		amt = amt or 0,
		message = type(message) == 'string' and message or '',
		colour = colour_name(extra and extra.colour),
		flags = (extra and (extra.mult_mod or extra.Xmult_mod) and 'm' or '') .. (extra and (extra.chip_mod or extra.Xchip_mod) and 'c' or '') .. (extra and extra.edition and 'e' or ''),
	})
end

-- Display ------------------------------------------------------------------

local function split(s, sep)
	local out = {}
	if not s or s == '' then
		return out
	end
	for part in string.gmatch(s .. sep, '(.-)' .. sep) do
		out[#out + 1] = part
	end
	return out
end

local function parse(code)
	local f = split(code, '|')
	return {
		id = tonumber(f[1]),
		front = f[2] ~= '' and f[2] or nil,
		center = f[3],
		edition = f[4] ~= '' and f[4] or nil,
		seal = f[5] ~= '' and f[5] or nil,
		highlighted = f[6] == '1',
		uid = f[7] ~= '' and f[7] or nil,
		look = table.concat({ f[2] or '', f[3] or '', f[4] or '', f[5] or '' }, '|'),
	}
end

-- from_deck: start at our deck so the card flies in like a real draw
local function make_card(item, area, scale, from_deck)
	local center = G.P_CENTERS[item.center] or G.P_CENTERS.c_base
	local front = item.front and G.P_CARDS[item.front] or nil
	local x, y = area.T.x + area.T.w / 2, area.T.y
	if from_deck and G.deck then
		x, y = G.deck.T.x, G.deck.T.y
	end
	local card = Card(x, y, G.CARD_W * scale, G.CARD_H * scale, front, center,
		{ bypass_discovery_center = true, bypass_discovery_ui = true })
	if item.edition then
		card:set_edition(item.edition, true, true)
	end
	if item.seal then
		card:set_seal(item.seal, true, true)
	end
	card.coop_display = true
	card.coop_id = item.id
	card.coop_look = item.look
	card.coop_uid = item.uid
	card.states.drag.can = false
	return card
end

local function destroy(card)
	if card.area then
		card.area:remove_card(card)
	end
	card:remove()
end

-- Brings an area in line with a list of parsed items, keeping cards that are
-- unchanged so they don't flicker. Returns id -> card.
local function sync(area, items, scale, on_new, from_deck)
	local by_id = {}
	for _, c in ipairs(area.cards) do
		by_id[c.coop_id] = c
	end
	local keep = {}
	for _, item in ipairs(items) do
		local card = by_id[item.id]
		if card and card.coop_look ~= item.look then
			-- a tarot or joker changed it: rebuild
			destroy(card)
			card = nil
		end
		if not card then
			card = make_card(item, area, scale, from_deck)
			area:emplace(card)
			if on_new then
				on_new(card)
			end
		end
		card.highlighted = item.highlighted
		keep[item.id] = card
	end
	for i = #area.cards, 1, -1 do
		local c = area.cards[i]
		if not keep[c.coop_id] then
			destroy(c)
		end
	end
	-- partner's order
	local ordered = {}
	for _, item in ipairs(items) do
		ordered[#ordered + 1] = keep[item.id]
	end
	area.cards = ordered
	area:set_ranks()
	return keep
end

local function make_target_clickable(card)
	card.click = function(self)
		self.coop_target = not self.coop_target
		play_sound(self.coop_target and 'cardSlide1' or 'cardSlide2')
		self:juice_up(0.3, 0.3)
		if self.area then
			self.area:align_cards()
		end
	end
end

local function create_areas()
	local x, w = G.play.T.x, G.play.T.w
	local y = G.jokers.T.y + G.jokers.T.h + 0.55
	local hand_h = G.CARD_H * HAND_SCALE
	-- the team joker row starts at the consumeables column; stop before it
	local right = (G.consumeables and G.consumeables.T.x or (x + w)) - 0.25
	local hand_w = (right - x) * 0.55 -- the rest goes to their jokers
	local joker_x = x + hand_w + 0.2

	-- the 'hand' layout spreads cards over max(#cards, card_limit) slots: 8 keeps
	-- a short hand bunched in the middle like a real hand
	-- fixed_limit: Steamodded must not run its slot bookkeeping on these copies
	-- (an area made while a tarot is being used never got it set up: crash)
	PV.hand_area = CardArea(x, y, hand_w, hand_h, { card_limit = 8, type = 'hand', highlight_limit = 0, no_card_count = true, fixed_limit = true })
	PV.joker_area = CardArea(joker_x, y + (hand_h - G.CARD_H * JOKER_SCALE) / 2, math.max(right - joker_x, G.CARD_W * JOKER_SCALE), G.CARD_H * JOKER_SCALE,
		-- a real joker row: cards side by side (overlapping only past 5), hover shows the description
		{ card_limit = 5, type = 'joker', highlight_limit = 0, no_card_count = true, fixed_limit = true })
	PV.play_area = CardArea(G.play.T.x, G.play.T.y, G.play.T.w, G.CARD_H * PLAY_SCALE,
		{ card_limit = 5, type = 'play', highlight_limit = 0, fixed_limit = true }) -- 5 slots like G.play: 10 squeezed the cards together

	-- tarot targets sit a bit higher than the partner's own selection
	local align_ref = PV.hand_area.align_cards
	PV.hand_area.align_cards = function(self)
		if not self.cards then
			return -- already removed
		end
		align_ref(self)
		for _, c in ipairs(self.cards or {}) do
			if c.coop_target then
				c.T.y = c.T.y - 0.35
			end
		end
	end

	PV.label = UIBox({
		definition = {
			n = G.UIT.ROOT,
			config = { align = 'cm', colour = { 0, 0, 0, 0.35 }, r = 0.1, padding = 0.06 },
			nodes = {
				{ n = G.UIT.T, config = { ref_table = PV, ref_value = 'label_text', scale = 0.3, colour = G.C.WHITE, shadow = true } },
			},
		},
		-- in the gap above the partner's hand: below it the played cards and
		-- their scoring would run over the text
		config = { align = 'tm', offset = { x = 0, y = -0.12 }, major = PV.hand_area, bond = 'Weak' },
	})
	PV.label_text = ''
end

function PV.remove()
	-- UI anchored to the partner's hand goes first: it would keep moving the
	-- removed area for a frame (crash in CardArea:align_cards)
	if COOP.TEAM and COOP.TEAM.remove_take_button then
		COOP.TEAM.remove_take_button()
	end
	if PV.label then
		PV.label:remove()
		PV.label = nil
	end
	for _, k in ipairs({ 'hand_area', 'joker_area', 'play_area' }) do
		local area = PV[k]
		if area then
			for i = #(area.cards or {}), 1, -1 do
				area.cards[i]:remove()
			end
			area:remove()
			PV[k] = nil
		end
	end
	PV.hand_cards, PV.joker_cards = {}, {}
end
PV.hand_cards, PV.joker_cards, PV.gone = {}, {}, {}

local function visible_state()
	local s = G.STATE
	-- PLAY_TAROT: keep the panel while a tarot is used, instead of rebuilding it
	return s == G.STATES.SELECTING_HAND or s == G.STATES.HAND_PLAYED or s == G.STATES.DRAW_TO_HAND or s == G.STATES.PLAY_TAROT
end

function PV.targets()
	local out = {}
	if PV.hand_area then
		for _, c in ipairs(PV.hand_area.cards) do
			if c.coop_target then
				out[#out + 1] = c
			end
		end
	end
	return out
end

function PV.clear_targets()
	for _, c in ipairs(PV.targets()) do
		c.coop_target = nil
	end
	if PV.hand_area then
		PV.hand_area:align_cards()
	end
end

function PV.update_display()
	-- The Fog boss: the partner's board stays hidden this blind
	local fog = COOP.boss_is and COOP.boss_is('bl_coop_fog')
	if fog or G.STAGE ~= G.STAGES.RUN or not G.play or not G.jokers or not visible_state() then
		if PV.hand_area then
			PV.remove()
		end
		return
	end
	if not PV.hand_area then
		create_areas()
		PV.shown = nil
	end
	-- G.play rides up and down with our hand (it rises while we pick cards):
	-- keep the partner's played cards exactly where ours would be
	PV.play_area.T.x, PV.play_area.T.y, PV.play_area.T.w = G.play.T.x, G.play.T.y, G.play.T.w
	local p = PV.partner
	if not p then
		PV.label_text = localize('k_coop_waiting')
		return
	end

	local turn = COOP.SB.my_turn()
	local turn_text = turn == false and p.hands_left > 0 and ('  ' .. localize('k_coop_their_move')) or ''
	PV.label_text = localize({ type = 'variable', key = 'coop_partner_label', vars = { p.hands_left, p.discards_left } }) .. turn_text

	local sig = p.hand .. '#' .. p.jokers
	if sig ~= PV.shown then
		PV.shown = sig
		local hand_items, joker_items = {}, {}
		for _, code in ipairs(split(p.hand, ';')) do
			local item = parse(code)
			if not (PV.gone[item.id] and G.TIMERS.REAL - PV.gone[item.id] < 2.5) then
				hand_items[#hand_items + 1] = item
			end
		end
		for _, code in ipairs(split(p.jokers, ';')) do
			joker_items[#joker_items + 1] = parse(code)
		end
		PV.hand_cards = sync(PV.hand_area, hand_items, HAND_SCALE, make_target_clickable, true)
		-- a click only marks it for Swap: a real highlight would offer to sell the copy
		PV.joker_cards = sync(PV.joker_area, joker_items, JOKER_SCALE, function(card)
			card.click = function(self)
				COOP.CARDS.pick_partner_joker(self) -- the target of Swap
			end
			apply_joker_state(card)
		end)
	end
end

-- Partner actions ------------------------------------------------------------

function PV.on_partner_state(snap)
	PV.partner = snap
end

-- Their played cards fly from their hand into our play area, full size,
-- exactly where our own played cards go.
function PV.on_partner_play(cards)
	if not PV.play_area then
		return
	end
	-- the partner is "playing" from now until their cards leave the board
	PV.play_pending = true
	PV.play_started = G.TIMERS.REAL
	for i = #PV.play_area.cards, 1, -1 do
		destroy(PV.play_area.cards[i])
	end
	for i, code in ipairs(split(cards, ';')) do
		local item = parse(code)
		item.highlighted = false
		local old = PV.hand_cards[item.id]
		local x, y = G.deck and G.deck.T.x or 0, G.deck and G.deck.T.y or 0
		if old then
			x, y = old.T.x, old.T.y
			destroy(old)
			PV.hand_cards[item.id] = nil
			PV.gone[item.id] = G.TIMERS.REAL
		end
		-- The copy exists right away (scoring popups and the scoring raise look
		-- it up as soon as their messages arrive), but it waits where it came
		-- from: disable_align keeps the area from moving it. Then the cards fly
		-- in one at a time, like a real play; the replayed scoring is queued
		-- after these events, so it starts once the last card has landed.
		local card = make_card(item, PV.play_area, PLAY_SCALE)
		card.T.x, card.T.y = x, y
		card.VT.x, card.VT.y = x, y
		card.disable_align = true
		PV.play_area:emplace(card)
		G.E_MANAGER:add_event(Event({
			trigger = 'after',
			delay = 0.15,
			func = function()
				card.disable_align = nil
				play_sound('card1', 0.85 + 0.05 * i)
				return true
			end,
		}))
	end
end

function PV.on_partner_discard(ids)
	for _, id in ipairs(split(ids, ';')) do
		local card = PV.hand_cards[tonumber(id)]
		if card then
			PV.hand_cards[tonumber(id)] = nil
			PV.gone[tonumber(id)] = G.TIMERS.REAL
			card:start_dissolve({ G.C.RED }, true)
		end
	end
	play_sound('cardSlide2')
end

-- Their scoring cards rise, like ours do while scoring.
function PV.on_partner_scoring(ids)
	if not PV.play_area then
		return
	end
	local set = {}
	for id in string.gmatch(ids or '', '[^;]+') do
		set[tonumber(id)] = true
	end
	for _, c in ipairs(PV.play_area.cards) do
		if set[c.coop_id] then
			c.highlighted = true
			c:juice_up(0.2, 0.2)
		end
	end
	play_sound('highlight1', 1, 0.3)
end

-- Hand fully scored on their side: after the replay, their cards slide off to
-- the discard pile like ours do.
function PV.on_partner_scored()
	if not PV.play_area then
		PV.play_pending = false
		return
	end
	G.E_MANAGER:add_event(Event({
		trigger = 'after',
		delay = 0.3,
		func = function()
			if PV.play_area and G.discard then
				for i = #PV.play_area.cards, 1, -1 do
					local c = PV.play_area.cards[i]
					PV.play_area:remove_card(c)
					c.T.x, c.T.y = G.discard.T.x, G.discard.T.y
					G.E_MANAGER:add_event(Event({
						trigger = 'after',
						delay = 0.6,
						blocking = false,
						func = function()
							c:remove()
							return true
						end,
					}))
				end
				play_sound('cardSlide2')
			end
			PV.play_pending = false -- their turn is over on our board
			return true
		end,
	}))
end

-- Hand name / chips / mult -----------------------------------------------------
--
-- update_hand_text drives the HUD's hand name, level, chips and mult while a
-- hand is picked and scored. Every call is streamed and replayed through the
-- real update_hand_text on the other side, so the partner's hand counts up in
-- our own HUD, with the same sounds, pulses and timing.

local NIL = '~' -- 'not given'. A control character got stripped on the way: never use one

local function pack(v)
	if v == nil then
		return NIL
	end
	return tostring(v)
end

-- numeric: chips and mult are always numbers; anything else means 'not given'
local function unpack_value(s, numeric)
	if s == NIL or s == nil then
		return nil
	end
	if numeric then
		return tonumber(s)
	end
	return tonumber(s) or s
end

PV.replaying = false

-- Live HUD -----------------------------------------------------------------------
--
-- While we score a hand, what our HUD shows (hand, level, chips, mult) is sent
-- several times a second, as it changes. The partner puts it straight into
-- their HUD with a non-blockable update, so it never waits behind other
-- animations: they watch our chips x mult count up as it happens.

local LIVE_EVERY = 0.05

function PV.stream_live(dt)
	PV.live_timer = (PV.live_timer or 0) + dt
	if PV.live_timer < LIVE_EVERY then
		return
	end
	PV.live_timer = 0
	if G.STATE ~= G.STATES.HAND_PLAYED or not G.GAME.current_round then
		if PV.live_last then
			-- our hand is over: clear it from the partner's HUD too
			COOP.send('live', { name = '', level = 0, chips = 0, mult = 0, total = 0 })
		end
		PV.live_last = nil
		return
	end
	local h = G.GAME.current_round.current_hand
	local played = G.GAME.last_hand_played and G.GAME.hands[G.GAME.last_hand_played]
	local live = {
		name = tostring(h.handname or ''),
		-- 0 once the HUD cleared it (the total shows): as the HUD shows it
		level = played and (h.hand_level or '') ~= '' and tonumber(played.level) or 0,
		chips = tonumber(h.chips) or 0,
		mult = tonumber(h.mult) or 0,
		-- the hand's total, shown in place of the hand name once it's counted
		total = tonumber(h.chip_total) or 0,
	}
	local sig = live.name .. '|' .. live.level .. '|' .. live.chips .. '|' .. live.mult .. '|' .. live.total
	if sig ~= PV.live_last then
		PV.live_last = sig
		COOP.send('live', live)
		PV.ht_sent = (PV.ht_sent or 0) + 1
	end
end

function PV.on_partner_live(p)
	PV.ht_recv = (PV.ht_recv or 0) + 1
	if COOP.boss_is and COOP.boss_is('bl_coop_fog') then
		return -- hidden by The Fog
	end
	if p.name == '' and p.chips == 0 and p.mult == 0 and p.total == 0 then
		-- their hand is over: clear it, unless we are scoring or picking cards ourselves
		if G.STATE ~= G.STATES.HAND_PLAYED and #(G.hand and G.hand.highlighted or {}) == 0 then
			pcall(update_hand_text, { immediate = true, delay = 0, nopulse = true },
				{ handname = '', level = '', chips = 0, mult = 0, chip_total = 0 })
		end
		return
	end
	if p.total == 0 and (G.GAME.current_round.current_hand.chip_total or 0) ~= 0 then
		-- the total counted down to nothing: back to the hand name, like theirs
		G.GAME.current_round.current_hand.chip_total = 0
	end
	PV.replaying = true
	-- mirror exactly, blanks included: once the total shows, the game clears
	-- the hand name and level (kept, they ran into the total)
	local ok, err = pcall(update_hand_text, { immediate = true, delay = 0 }, {
		handname = p.name,
		level = p.level > 0 and p.level or '',
		chips = p.chips,
		mult = p.mult,
		chip_total = p.total > 0 and p.total or nil,
	})
	PV.replaying = false
	if not ok then
		sendWarnMessage('live hud failed: ' .. tostring(err), COOP.id)
	end
end

function PV.capture_hand_text(config, vals)
	-- superseded by the live HUD stream (PV.stream_live); kept for counting only
	if true then
		return
	end
	-- only our real scoring: previews while we pick cards would overwrite the
	-- partner's own HUD while they are choosing theirs
	if PV.replaying or not COOP.is_active() or not vals or G.STATE ~= G.STATES.HAND_PLAYED then
		return
	end
	if vals.handname == nil and vals.chips == nil and vals.mult == nil and vals.level == nil then
		return
	end
	config = config or {}
	COOP.send('hand_text', {
		name = pack(vals.handname),
		level = pack(vals.level),
		chips = pack(vals.chips),
		mult = pack(vals.mult),
		delay = config.delay or 0.8,
		immediate = config.immediate and true or false,
		nopulse = config.nopulse and true or false,
		sound = config.sound or '',
	})
	PV.ht_sent = (PV.ht_sent or 0) + 1
end

function PV.on_partner_hand_text(p)
	PV.ht_recv = (PV.ht_recv or 0) + 1
	local vals = {
		handname = unpack_value(p.name),
		level = unpack_value(p.level),
		chips = unpack_value(p.chips, true),
		mult = unpack_value(p.mult, true),
	}
	if type(vals.handname) == 'number' then
		vals.handname = tostring(vals.handname)
	end
	-- their end-of-hand reset to 0 x 0 would wipe what we are previewing:
	-- keep their last result on screen instead
	if vals.handname == '' and vals.chips == 0 and vals.mult == 0 then
		return
	end
	local config = {
		delay = p.delay,
		immediate = p.immediate or nil,
		nopulse = p.nopulse or nil,
		sound = p.sound ~= '' and p.sound or nil,
	}
	PV.replaying = true
	local ok, err = pcall(update_hand_text, config, vals)
	PV.replaying = false
	if not ok then
		sendWarnMessage('hand text replay failed: ' .. tostring(err), COOP.id)
	end
end

local function find_display(where, id)
	if where == 'play' and PV.play_area then
		for _, c in ipairs(PV.play_area.cards) do
			if c.coop_id == id then
				return c
			end
		end
	elseif where == 'hand' then
		return PV.hand_cards[id]
	elseif where == 'jokers' then
		return PV.joker_cards[id]
	end
end

function PV.on_partner_step(p)
	local card = find_display(p.where, p.id)
	if not card then
		return
	end
	local extra = nil
	if p.eval_type == 'extra' or p.eval_type == 'jokers' then
		extra = {
			message = p.message ~= '' and p.message or nil,
			colour = p.colour ~= '' and G.C[p.colour] or nil,
			mult_mod = p.flags:find('m') and true or nil,
			chip_mod = p.flags:find('c') and true or nil,
			edition = p.flags:find('e') and true or nil,
		}
		if not extra.message then
			return
		end
	elseif p.colour ~= '' then
		extra = { colour = G.C[p.colour] }
	end
	-- card_eval_status_text places the text by the card's area (above played
	-- and held cards, below jokers). Our copies live in our own areas, so
	-- briefly present them as being in the matching real area.
	local real_area = card.area
	card.area = (p.where == 'play' and G.play) or (p.where == 'hand' and G.hand) or (p.where == 'jokers' and G.jokers) or real_area
	local ok, err = pcall(card_eval_status_text, card, p.eval_type, p.amt, nil, nil, extra)
	card.area = real_area
	if not ok then
		sendWarnMessage('partner step replay failed: ' .. tostring(err), COOP.id)
	end
end

function PV.update(dt)
	PV.update_send(dt)
	PV.stream_live(dt)
	PV.update_display()
end

-- Unstick: forget a partner hand that never finished on our board.
function PV.clear_stuck_play()
	PV.play_pending = false
	if PV.play_area then
		for i = #PV.play_area.cards, 1, -1 do
			destroy(PV.play_area.cards[i])
		end
	end
end

-- True while the partner's played hand is on our board. Gives up after 15s
-- (a lost score report must not leave their cards there, blocking our turn).
function PV.partner_playing()
	local on_board = PV.play_area and PV.play_area.cards and #PV.play_area.cards > 0
	if not PV.play_pending and not on_board then
		return false
	end
	if G.TIMERS.REAL - (PV.play_started or 0) > 30 then
		PV.play_pending = false
		if on_board then
			for i = #PV.play_area.cards, 1, -1 do
				destroy(PV.play_area.cards[i])
			end
		end
		return false
	end
	return true
end

function PV.install_hooks()
	-- Safety net: a CardArea that was removed (cards = nil) but is still
	-- referenced by some UI for one more frame must not crash when moved.
	local align_cards_ref = CardArea.align_cards
	function CardArea:align_cards()
		if not self.cards then
			return
		end
		return align_cards_ref(self)
	end

	-- While we pick cards our hand is raised over the play area; when we play,
	-- the game lowers it. Do the same while the partner's hand is on the board.
	local move_ref = CardArea.move
	function CardArea:move(dt)
		if self == G.hand and COOP.is_active() and PV.partner_playing() then
			local desired_y = G.TILE_H - G.hand.T.h
			G.hand.T.y = 15 * G.real_dt * desired_y + (1 - 15 * G.real_dt) * G.hand.T.y
			if math.abs(desired_y - G.hand.T.y) < 0.01 then
				G.hand.T.y = desired_y
			end
			Moveable.move(self, dt)
			self:align_cards()
			return
		end
		return move_ref(self, dt)
	end

	local status_ref = card_eval_status_text
	function card_eval_status_text(card, eval_type, amt, percent, dir, extra)
		if COOP.is_active() and card and not card.coop_display then
			pcall(PV.capture_step, card, eval_type, amt, extra)
		end
		return status_ref(card, eval_type, amt, percent, dir, extra)
	end

	local play_ref = G.FUNCS.play_cards_from_highlighted
	G.FUNCS.play_cards_from_highlighted = function(e)
		if COOP.is_active() and G.hand and #G.hand.highlighted > 0 then
			local cards = {}
			for _, c in ipairs(G.hand.highlighted) do
				cards[#cards + 1] = c
			end
			table.sort(cards, function(a, b)
				return a.T.x < b.T.x
			end)
			COOP.send('play', { cards = PV.encode_cards(cards) })
		end
		return play_ref(e)
	end

	local discard_ref = G.FUNCS.discard_cards_from_highlighted
	G.FUNCS.discard_cards_from_highlighted = function(e, hook)
		if COOP.is_active() and not hook and G.hand and #G.hand.highlighted > 0 then
			local ids = {}
			for _, c in ipairs(G.hand.highlighted) do
				ids[#ids + 1] = c.sort_id
			end
			COOP.send('discard', { ids = table.concat(ids, ';') })
		end
		return discard_ref(e, hook)
	end
end
