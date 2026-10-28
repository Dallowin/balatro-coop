-- New co-op cards, all only in co-op runs, art in assets/*/coop_*.png:
--
--   Pair jokers   three pairs (Yin/Yang, Sun/Moon, Sword/Shield): each half
--                 is weak alone and strong while the PARTNER holds the other
--                 half (both halves with one player do nothing extra). Once a
--                 half is owned, its other half shows up in the next shop.
--   Swap          spectral: swaps one of your jokers with one of the
--                 partner's (the one you clicked in their panel, else their
--                 rightmost)
--   Seals         Bond: played -> the partner draws a card;
--                 Sacrifice: discarded -> the partner gets +1 discard
--   Enhancements  Bulwark: while it's held in your hand, the partner's
--                 hands get X1.2 Mult (each); Mirror, Beacon, Twin, Torch below
--   The Forge     tarot: one card becomes a random co-op enhancement
--   Tarots        The Bond, The Offering, The Fortress put those on cards
--                 (yours or, as usual, the partner's); The Twins makes the
--                 other half of a pair joker the partner holds
--   Co-op Pack    booster with all of the above (normal 1 of 3, mega 2 of 5)
--   Editions      Union (both players' colours; +Mult for you and the
--                 partner) and Ether (see-through ghost; XMult), with their
--                 own shaders in assets/shaders

COOP.CARDS = COOP.CARDS or {}
local CC = COOP.CARDS

SMODS.Atlas({ key = 'pairs', path = 'coop_pairs.png', px = 71, py = 95 })
SMODS.Atlas({ key = 'coop_tarots', path = 'coop_tarots.png', px = 71, py = 95 })
SMODS.Atlas({ key = 'coop_boosters', path = 'coop_boosters.png', px = 71, py = 95 })
SMODS.Atlas({ key = 'coop_enhancers', path = 'coop_enhancers.png', px = 71, py = 95 })

local function coop_pool()
	return COOP.is_active()
end

-- an effect (ui/fx.lua) queued with the scoring, so it plays in step with it
local function fx(fn)
	G.E_MANAGER:add_event(Event({
		func = function()
			pcall(fn, COOP.FX)
			return true
		end,
	}))
end
CC.fx = fx

local BULWARK_X = 1.2

-- What the partner has, from their last snapshot (ui/partner_view.lua):
-- cards are 'sort_id|card_key|center|edition|seal|...' joined by ';'.
local function partner_codes(field)
	local p = COOP.PV and COOP.PV.partner
	local out = {}
	for code in tostring(p and p[field] or ''):gmatch('[^;]+') do
		local parts = {}
		for part in (code .. '|'):gmatch('([^|]*)|') do
			parts[#parts + 1] = part
		end
		out[#out + 1] = parts
	end
	return out
end

function COOP.partner_jokers()
	local keys = {}
	for _, p in ipairs(partner_codes('jokers')) do
		keys[#keys + 1] = p[3]
	end
	return keys
end

function COOP.partner_has_joker(key)
	for _, k in ipairs(COOP.partner_jokers()) do
		if k == key then
			return true
		end
	end
	return false
end

local function i_have_joker(key)
	return G.jokers and next(SMODS.find_card(key, true)) ~= nil
end

-- Pair jokers ------------------------------------------------------------------------

CC.PAIRS = { yin = 'yang', yang = 'yin', sun = 'moon', moon = 'sun', sword = 'shield', shield = 'sword' }
local PAIR_POS = { yin = 0, yang = 1, sun = 2, moon = 3, sword = 4, shield = 5 }

local function other_half(card)
	local short = card.config.center.key:gsub('^j_coop_', '')
	return 'j_coop_' .. (CC.PAIRS[short] or '')
end

-- the pair works while the other half is the partner's
function CC.paired(card)
	return COOP.is_active() and COOP.partner_has_joker(other_half(card))
end

local function pair_vars(card, ...)
	local vars = { ... }
	vars[#vars + 1] = localize({ type = 'name_text', set = 'Joker', key = other_half(card) })
	vars[#vars + 1] = localize(CC.paired(card) and 'k_coop_pair_on' or 'k_coop_pair_off')
	return vars
end

local function pair_joker(key, def)
	def.key = key
	def.atlas = 'pairs'
	def.pos = { x = PAIR_POS[key], y = 0 }
	def.in_pool = coop_pool
	def.blueprint_compat = def.blueprint_compat ~= false
	SMODS.Joker(def)
end

-- Yin / Yang: +4 Mult; paired X2 Mult too.
for _, key in ipairs({ 'yin', 'yang' }) do
	pair_joker(key, {
		rarity = 1,
		cost = 5,
		config = { extra = { mult = 4, xmult = 2 } },
		loc_vars = function(self, info_queue, card)
			return { vars = pair_vars(card, card.ability.extra.mult, card.ability.extra.xmult) }
		end,
		calculate = function(self, card, context)
			if context.joker_main then
				if CC.paired(card) then
					fx(function(F)
						local half = function()
							return F.partner_card('j_coop_' .. CC.PAIRS[key])
						end
						F.beam(card, half, key == 'yin' and G.C.WHITE or F.PARTNER, 0.5)
						F.comet(half, card, { G.C.WHITE, G.C.BLACK, F.PARTNER }, { arc = 1.2, sound = 'multhit1', pitch = 1.2 })
					end)
					return { mult = card.ability.extra.mult, xmult = card.ability.extra.xmult }
				end
				return { mult = card.ability.extra.mult }
			end
		end,
	})
end

-- Sun: +15 Chips per scored Heart / Diamond; Moon: per Spade / Club. Paired:
-- every scored card counts.
local SUITS = { sun = { 'Hearts', 'Diamonds' }, moon = { 'Spades', 'Clubs' } }
for _, key in ipairs({ 'sun', 'moon' }) do
	pair_joker(key, {
		rarity = 1,
		cost = 5,
		config = { extra = { chips = 15 } },
		loc_vars = function(self, info_queue, card)
			return { vars = pair_vars(card, card.ability.extra.chips) }
		end,
		calculate = function(self, card, context)
			if context.individual and context.cardarea == G.play then
				local c = context.other_card
				if CC.paired(card) or c:is_suit(SUITS[key][1]) or c:is_suit(SUITS[key][2]) then
					return { chips = card.ability.extra.chips }
				end
			end
		end,
	})
end

-- Sword: X1.5 Mult; paired X2.5.
pair_joker('sword', {
	rarity = 2,
	cost = 6,
	config = { extra = { xmult = 1.5, paired_xmult = 2.5 } },
	loc_vars = function(self, info_queue, card)
		return { vars = pair_vars(card, card.ability.extra.xmult, card.ability.extra.paired_xmult) }
	end,
	calculate = function(self, card, context)
		if context.joker_main then
			if CC.paired(card) then
				fx(function(F)
					local shield = F.partner_card('j_coop_shield')
					F.beam(shield, card, G.C.WHITE, 0.45, { jitter = 0.15 })
					F.comet(shield, card, { G.C.WHITE, G.C.GREY, F.PARTNER }, { sound = 'slice1', pitch = 1.1, arc = -0.6, time = 0.35 })
				end)
			end
			return { xmult = CC.paired(card) and card.ability.extra.paired_xmult or card.ability.extra.xmult }
		end
	end,
})

-- Shield: +1 discard each blind; paired +1 hand too.
pair_joker('shield', {
	rarity = 2,
	cost = 6,
	blueprint_compat = false,
	config = { extra = { discards = 1, hands = 1 } },
	loc_vars = function(self, info_queue, card)
		return { vars = pair_vars(card, card.ability.extra.discards, card.ability.extra.hands) }
	end,
	calculate = function(self, card, context)
		if context.setting_blind and not context.blueprint then
			ease_discard(card.ability.extra.discards)
			if CC.paired(card) then
				ease_hands_played(card.ability.extra.hands)
				fx(function(F)
					F.comet(F.partner_jokers(), card, { G.C.BLUE, F.PARTNER, G.C.WHITE })
				end)
			end
			return { message = localize('k_coop_shield_up'), colour = G.C.BLUE }
		end
	end,
})

-- the other half of a pair one of us holds and nobody has yet
function CC.wanted_half()
	if not COOP.is_active() then
		return nil
	end
	local theirs = COOP.partner_jokers()
	local function owned(key)
		if i_have_joker(key) then
			return true
		end
		for _, k in ipairs(theirs) do
			if k == key then
				return true
			end
		end
		return false
	end
	for half, other in pairs(CC.PAIRS) do
		local a, b = 'j_coop_' .. half, 'j_coop_' .. other
		if owned(a) and not owned(b) then
			for _, c in ipairs(G.shop_jokers and G.shop_jokers.cards or {}) do
				if c.config.center.key == b then
					return nil -- already on sale
				end
			end
			return b
		end
	end
end

-- The shop (generated by the host, see domain/shop.lua): once per round,
-- the first joker slot becomes the missing half.
local create_card_for_shop_ref = create_card_for_shop
function create_card_for_shop(area)
	local card = create_card_for_shop_ref(area)
	local ok, err = pcall(function()
		local lobby = COOP.get_lobby()
		if not (COOP.is_active() and lobby and lobby.is_host and area == G.shop_jokers and card and card.ability.set == 'Joker') then
			return
		end
		if G.GAME.coop_pair_round == G.GAME.round then
			return
		end
		local want = CC.wanted_half()
		if want and G.P_CENTERS[want] then
			G.GAME.coop_pair_round = G.GAME.round
			card:set_ability(G.P_CENTERS[want], true)
			card:set_cost()
		end
	end)
	if not ok then
		sendWarnMessage('pair in shop failed: ' .. tostring(err), COOP.id)
	end
	return card
end

-- Swap -------------------------------------------------------------------------------

-- the partner joker clicked in their panel (index), for Swap
CC.swap_pick = nil

function CC.pick_partner_joker(card)
	local area = COOP.PV.joker_area
	if not area then
		return
	end
	for i, c in ipairs(area.cards) do
		if c == card then
			CC.swap_pick = CC.swap_pick ~= i and i or nil
		end
		c.highlighted = false
	end
	if CC.swap_pick and area.cards[CC.swap_pick] then
		area.cards[CC.swap_pick].highlighted = true
		area.cards[CC.swap_pick]:juice_up(0.3, 0.3)
	end
	play_sound('cardSlide1')
end

local function swappable(card)
	return card and not (card.ability and card.ability.eternal)
end

SMODS.Consumable({
	key = 'swap',
	set = 'Spectral',
	atlas = 'coop_tarots',
	pos = { x = 4, y = 0 },
	cost = 4,
	in_pool = coop_pool,
	loc_vars = function(self, info_queue, card)
		return { vars = {} }
	end,
	can_use = function(self, card)
		return COOP.is_active() and G.jokers and #G.jokers.highlighted == 1 and swappable(G.jokers.highlighted[1])
			and #COOP.partner_jokers() > 0
	end,
	use = function(self, card, area)
		local mine = G.jokers.highlighted[1]
		local n = #COOP.partner_jokers()
		local idx = CC.swap_pick and CC.swap_pick <= n and CC.swap_pick or n
		CC.swap_pick = nil
		COOP.send('swap', { key = mine.config.center.key, edition = mine.edition and mine.edition.key or '', idx = idx })
		fx(function(F)
			F.comet(mine, F.partner_jokers, { G.C.SECONDARY_SET.Spectral, G.C.WHITE }, { time = 0.8 })
		end)
		G.E_MANAGER:add_event(Event({
			func = function()
				COOP.FX.swap_out(mine)
				COOP.FX.swap_out(mine)
		mine:start_dissolve({ G.C.SECONDARY_SET.Spectral }, nil, 1.2)
				return true
			end,
		}))
	end,
})

local function add_joker(key, edition)
	if not G.P_CENTERS[key] then
		return
	end
	local card = SMODS.add_card({ key = key, area = G.jokers, edition = edition ~= '' and edition or nil })
	if card then
		card:juice_up(0.4, 0.4)
		pcall(function()
			COOP.FX.swap_in(card)
		end)
	end
end

-- partner used Swap: give them the joker at idx, take theirs
function CC.on_swap(key, edition, idx)
	if not G.jokers then
		return
	end
	local mine = G.jokers.cards[idx] or G.jokers.cards[#G.jokers.cards]
	if mine and swappable(mine) then
		COOP.send('swap_back', { key = mine.config.center.key, edition = mine.edition and mine.edition.key or '' })
		mine:start_dissolve({ G.C.SECONDARY_SET.Spectral }, nil, 1.2)
	else
		COOP.send('swap_back', { key = key, edition = edition }) -- nothing to give: theirs comes back
		return
	end
	add_joker(key, edition)
	COOP.popup(localize('k_coop_swapped'), G.C.SECONDARY_SET.Spectral)
end

function CC.on_swap_back(key, edition)
	add_joker(key, edition)
	COOP.popup(localize('k_coop_swapped'), G.C.SECONDARY_SET.Spectral)
end

-- Seals and Bulwark ------------------------------------------------------------------

CC.pending_draws = 0

SMODS.Seal({
	key = 'bond',
	atlas = 'coop_enhancers',
	pos = { x = 1, y = 0 },
	badge_colour = HEX('2FB8A8'),
	in_pool = coop_pool,
	calculate = function(self, card, context)
		if context.main_scoring and context.cardarea == G.play and COOP.is_active() then
			COOP.send('bond_draw', { n = 1 })
			fx(function(F)
				F.beam(card, F.partner_hand, F.TEAL, 0.4, { sound = false })
				F.comet(card, F.partner_hand, { F.TEAL, G.C.WHITE })
			end)
			return { message = localize('k_coop_bond_msg'), colour = HEX('2FB8A8') }
		end
	end,
})

SMODS.Seal({
	key = 'sacrifice',
	atlas = 'coop_enhancers',
	pos = { x = 2, y = 0 },
	badge_colour = HEX('9AA0A6'),
	in_pool = coop_pool,
	calculate = function(self, card, context)
		if context.discard and (not context.other_card or context.other_card == card) and COOP.is_active() then
			-- the discard may reach the seal twice (the game's own call and
			-- Steamodded's); count it once
			if card.coop_sacrificed and G.TIMERS.REAL - card.coop_sacrificed < 1 then
				return
			end
			card.coop_sacrificed = G.TIMERS.REAL
			COOP.send('sacrifice', { n = 1 })
			pcall(function()
				COOP.FX.comet(card, COOP.FX.partner_hand, { G.C.RED, G.C.GREY }, { sound = 'cancel', pitch = 1.2 })
			end)
			return { message = localize('k_coop_sacrifice_msg'), colour = G.C.UI.TEXT_INACTIVE }
		end
	end,
})

SMODS.Enhancement({
	key = 'bulwark',
	atlas = 'coop_enhancers',
	pos = { x = 0, y = 0 },
	config = { extra = { xmult = BULWARK_X } },
	in_pool = coop_pool,
	loc_vars = function(self, info_queue, card)
		return { vars = { BULWARK_X } }
	end,
})

-- the partner played a Bond card: draw one (now if we're picking cards, else
-- at our next chance in this blind)
function CC.on_bond_draw(n)
	CC.pending_draws = CC.pending_draws + (n or 1)
end

function CC.on_sacrifice(n)
	if G.GAME and G.GAME.blind and G.GAME.blind.in_blind then
		ease_discard(n or 1)
		COOP.popup(localize('k_coop_sacrifice_got'), G.C.RED)
		pcall(function()
			COOP.FX.comet(COOP.FX.partner_hand(), G.deck, { G.C.RED, G.C.GREY })
		end)
	end
end

-- Game:update
function CC.update()
	if CC.pending_draws <= 0 then
		return
	end
	local in_blind = G.GAME and G.GAME.blind and G.GAME.blind.in_blind
	if not in_blind then
		CC.pending_draws = 0
		return
	end
	if G.STATE ~= G.STATES.SELECTING_HAND or G.CONTROLLER.locked or #G.deck.cards == 0 then
		return
	end
	local n = math.min(CC.pending_draws, #G.deck.cards)
	CC.pending_draws = 0
	-- straight from the deck, over the hand limit: the game's own draw only
	-- fills the hand up to its size, and by then it is usually full
	for _ = 1, n do
		draw_card(G.deck, G.hand, 90, 'up', true)
	end
	COOP.popup(localize('k_coop_bond_got'), HEX('2FB8A8'))
	pcall(function()
		COOP.FX.comet(COOP.FX.partner_hand(), G.hand, { COOP.FX.TEAL, G.C.WHITE })
	end)
end

-- Bulwark cards in the partner's hand back up every hand we play.
function CC.bulwark_xmult()
	local n = 0
	for _, p in ipairs(partner_codes('hand')) do
		if p[3] == 'm_coop_bulwark' then
			n = n + 1
		end
	end
	return n > 0 and BULWARK_X ^ n or nil
end


-- More co-op enhancements (atlas coop_enhancers, cells 3..6):
--   Mirror  scored -> the partner's next hand gets +Chips equal to its chips
--   Beacon  scored -> +4 Mult, +4 more for each Beacon in the partner's hand
--   Twin    scored -> X1.5 Mult if the partner's last hand had its rank
--   Torch   scored -> X2 Mult; 1 in 4 burns out, and then the partner gets
--           +1 hand this blind
local BEACON_MULT = 4
local TWIN_X = 1.5
local TORCH_X, TORCH_ODDS = 2, 4

CC.pending_chips = 0

local function partner_hand_count(center_key)
	local n = 0
	for _, p in ipairs(partner_codes('hand')) do
		if p[3] == center_key then
			n = n + 1
		end
	end
	return n
end

local function scored(card, context)
	return context.main_scoring and context.cardarea == G.play and COOP.is_active()
end

SMODS.Enhancement({
	key = 'mirror',
	atlas = 'coop_enhancers',
	pos = { x = 3, y = 0 },
	in_pool = coop_pool,
	calculate = function(self, card, context)
		if scored(card, context) then
			local n = card:get_chip_bonus()
			if n > 0 then
				COOP.send('mirror_chips', { n = n })
				fx(function(F)
					F.comet(card, F.partner_hand, { G.C.CHIPS, G.C.WHITE })
				end)
				return { message = localize('k_coop_mirror_msg'), colour = G.C.CHIPS }
			end
		end
	end,
})

SMODS.Enhancement({
	key = 'beacon',
	atlas = 'coop_enhancers',
	pos = { x = 4, y = 0 },
	in_pool = coop_pool,
	loc_vars = function(self, info_queue, card)
		local n = COOP.is_active() and partner_hand_count('m_coop_beacon') or 0
		return { vars = { BEACON_MULT, BEACON_MULT * (n + 1) } }
	end,
	calculate = function(self, card, context)
		if scored(card, context) then
			local n = partner_hand_count('m_coop_beacon')
			if n > 0 then
				fx(function(F)
					F.comet(F.partner_hand(), card, F.GOLD, { sound = 'gold_seal', pitch = 1.2 })
				end)
			end
			return { mult = BEACON_MULT * (1 + n) }
		end
	end,
})

SMODS.Enhancement({
	key = 'twin',
	atlas = 'coop_enhancers',
	pos = { x = 5, y = 0 },
	in_pool = coop_pool,
	loc_vars = function(self, info_queue, card)
		return { vars = { TWIN_X } }
	end,
	calculate = function(self, card, context)
		if scored(card, context) then
			local pp = COOP.SYN and COOP.SYN.partner_play
			if pp and pp.ranks and pp.ranks[card.base.value] then
				fx(function(F)
					F.comet(F.partner_hand(), card, { F.PARTNER, G.C.WHITE }, { arc = 1 })
				end)
				return { xmult = TWIN_X }
			end
		end
	end,
})

SMODS.Enhancement({
	key = 'torch',
	atlas = 'coop_enhancers',
	pos = { x = 6, y = 0 },
	in_pool = coop_pool,
	config = { extra = { odds = TORCH_ODDS } },
	loc_vars = function(self, info_queue, card)
		return { vars = { TORCH_X, G.GAME and G.GAME.probabilities.normal or 1, TORCH_ODDS } }
	end,
	calculate = function(self, card, context)
		if scored(card, context) then
			return { xmult = TORCH_X }
		end
		if context.destroy_card == card and context.cardarea == G.play and COOP.is_active()
			and pseudorandom('coop_torch') < (G.GAME.probabilities.normal or 1) / TORCH_ODDS then
			COOP.send('torch', { n = 1 })
			COOP.FX.burn(card) -- dissolves in fire
			return { remove = true }
		end
	end,
})

function CC.on_mirror_chips(n)
	CC.pending_chips = CC.pending_chips + math.max(0, n or 0)
	pcall(function()
		COOP.FX.comet(COOP.FX.partner_hand(), G.deck, { G.C.CHIPS, G.C.WHITE })
	end)
end

function CC.on_torch(n)
	if G.GAME and G.GAME.blind and G.GAME.blind.in_blind then
		ease_hands_played(n or 1)
		COOP.popup(localize('k_coop_torch_got'), G.C.ORANGE)
		pcall(function()
			COOP.FX.comet(COOP.FX.partner_hand(), G.deck, COOP.FX.FIRE, { time = 0.7 })
		end)
	end
end

-- Tarots -----------------------------------------------------------------------------

local function on_selected(card, max, apply)
	local targets = {}
	for i = 1, math.min(#G.hand.highlighted, max) do
		targets[#targets + 1] = G.hand.highlighted[i]
	end
	for _, c in ipairs(targets) do
		G.E_MANAGER:add_event(Event({
			trigger = 'after',
			delay = 0.15,
			func = function()
				c:flip()
				play_sound('card1', 1.1)
				return true
			end,
		}))
	end
	for _, c in ipairs(targets) do
		G.E_MANAGER:add_event(Event({
			trigger = 'after',
			delay = 0.1,
			func = function()
				apply(c)
				return true
			end,
		}))
	end
	for _, c in ipairs(targets) do
		G.E_MANAGER:add_event(Event({
			trigger = 'after',
			delay = 0.15,
			func = function()
				c:flip()
				play_sound('tarot2', 1, 0.6)
				c:juice_up(0.3, 0.3)
				return true
			end,
		}))
	end
	G.E_MANAGER:add_event(Event({
		trigger = 'after',
		delay = 0.2,
		func = function()
			G.hand:unhighlight_all()
			return true
		end,
	}))
end

local function card_tarot(key, pos, max, apply, info)
	SMODS.Consumable({
		key = key,
		set = 'Tarot',
		atlas = 'coop_tarots',
		pos = { x = pos, y = 0 },
		cost = 3,
		config = { max_highlighted = max },
		in_pool = coop_pool,
		loc_vars = function(self, info_queue, card)
			if info then
				info_queue[#info_queue + 1] = info()
			end
			return { vars = { card.ability.max_highlighted } }
		end,
		use = function(self, card, area)
			on_selected(card, card.ability.max_highlighted, apply)
		end,
	})
end

card_tarot('bond', 0, 2, function(c)
	c:set_seal('coop_bond', nil, true)
end, function()
	return G.P_SEALS.coop_bond
end)

card_tarot('offering', 1, 2, function(c)
	c:set_seal('coop_sacrifice', nil, true)
end, function()
	return G.P_SEALS.coop_sacrifice
end)

-- The Forge: one card becomes a random co-op enhancement
local FORGE = { 'm_coop_bulwark', 'm_coop_mirror', 'm_coop_beacon', 'm_coop_twin', 'm_coop_torch' }
card_tarot('forge', 5, 1, function(c)
	c:set_ability(G.P_CENTERS[pseudorandom_element(FORGE, pseudoseed('coop_forge'))], nil, true)
end)

card_tarot('fortress', 2, 2, function(c)
	c:set_ability(G.P_CENTERS.m_coop_bulwark, nil, true)
end, function()
	return G.P_CENTERS.m_coop_bulwark
end)

-- The Twins: the other half of a pair joker the partner holds
local function twins_target()
	for _, k in ipairs(COOP.partner_jokers()) do
		local short = k:gsub('^j_coop_', '')
		local other = CC.PAIRS[short] and ('j_coop_' .. CC.PAIRS[short])
		if other and not i_have_joker(other) then
			return other
		end
	end
end

SMODS.Consumable({
	key = 'twins',
	set = 'Tarot',
	atlas = 'coop_tarots',
	pos = { x = 3, y = 0 },
	cost = 3,
	in_pool = coop_pool,
	loc_vars = function(self, info_queue, card)
		local t = COOP.is_active() and twins_target()
		return { vars = { t and localize({ type = 'name_text', set = 'Joker', key = t }) or localize('k_coop_no_pair') } }
	end,
	can_use = function(self, card)
		return COOP.is_active() and twins_target() ~= nil and G.jokers and #G.jokers.cards < G.jokers.config.card_limit
	end,
	use = function(self, card, area)
		local key = twins_target()
		G.E_MANAGER:add_event(Event({
			trigger = 'after',
			delay = 0.4,
			func = function()
				add_joker(key, '')
				play_sound('timpani')
				return true
			end,
		}))
	end,
})

-- Co-op Pack -------------------------------------------------------------------------

local TAROTS = { 'c_coop_bond', 'c_coop_offering', 'c_coop_fortress', 'c_coop_twins', 'c_coop_forge' }
local JOKERS = { 'j_coop_yin', 'j_coop_yang', 'j_coop_sun', 'j_coop_moon', 'j_coop_sword', 'j_coop_shield' }

local function pack_card(i)
	local roll = pseudorandom('coop_pack')
	if roll < 0.45 then
		return { key = pseudorandom_element(TAROTS, pseudoseed('coop_pack_t')), area = G.pack_cards, skip_materialize = true }
	elseif roll < 0.55 then
		return { key = 'c_coop_swap', area = G.pack_cards, skip_materialize = true }
	end
	return { key = pseudorandom_element(JOKERS, pseudoseed('coop_pack_j')), area = G.pack_cards, skip_materialize = true }
end

local function pack(key, pos, extra, choose, cost, weight)
	SMODS.Booster({
		key = key,
		kind = 'Coop',
		atlas = 'coop_boosters',
		pos = { x = pos, y = 0 },
		config = { extra = extra, choose = choose },
		cost = cost,
		weight = weight,
		draw_hand = true,
		group_key = 'k_coop_pack',
		in_pool = coop_pool,
		loc_vars = function(self, info_queue, card)
			return { vars = { card.ability.choose, card.ability.extra } }
		end,
		create_card = function(self, card, i)
			return pack_card(i)
		end,
		ease_background_colour = function(self)
			ease_colour(G.C.DYN_UI.MAIN, HEX('2FB8A8'))
			ease_background_colour({ new_colour = HEX('2FB8A8'), special_colour = G.C.PURPLE, contrast = 2 })
		end,
	})
end

pack('pack_normal', 0, 3, 1, 6, 0.8)
pack('pack_mega', 1, 5, 2, 9, 0.25)

-- Mod-wide scoring: Bulwark from the partner's hand -------------------------------

COOP.calculate = function(self, context)
	if context.joker_main and COOP.is_active() then
		-- Union jokers of the partner, Bulwark cards in the partner's hand,
		-- Mirror chips the partner sent
		local m = CC.union_mult and CC.union_mult() or 0
		local x = CC.bulwark_xmult()
		local c = CC.pending_chips
		CC.pending_chips = 0
		if m > 0 or x or c > 0 then
			fx(function(F)
				local cols = x and { G.C.GREY, G.C.WHITE } or c > 0 and { G.C.CHIPS, G.C.WHITE } or { F.PARTNER, G.C.MULT }
				F.comet(F.partner_hand(), G.play, cols)
			end)
			return { chips = c > 0 and c or nil, mult = m > 0 and m or nil, xmult = x,
				message = localize(x and 'k_coop_bulwark_msg' or c > 0 and 'k_coop_mirror_msg' or 'k_coop_union_msg') }
		end
	end
end

-- Editions ---------------------------------------------------------------------------
--
--   Union   shimmers in both players' colours; +8 Mult for you AND for every
--           hand your partner plays
--   Ether   a see-through ghost of a card; X1.3 Mult

local UNION_MULT = 8

SMODS.Shader({ key = 'kinship', path = 'kinship.fs' }) -- 'union' is a reserved word in GLSL
SMODS.Shader({ key = 'ether', path = 'ether.fs' })

local function coop_weight(self)
	return COOP.is_active() and self.weight or 0
end

SMODS.Edition({
	key = 'union',
	shader = 'kinship',
	config = { mult = UNION_MULT },
	in_shop = true,
	weight = 4,
	extra_cost = 4,
	get_weight = coop_weight,
	sound = { sound = 'holo1', per = 1.3, vol = 0.5 },
	loc_vars = function(self, info_queue, card)
		return { vars = { UNION_MULT } }
	end,
	calculate = function(self, card, context)
		if context.pre_joker or (context.main_scoring and context.cardarea == G.play) then
			fx(function(F)
				F.burst(card, { G.C.RED, G.C.BLUE, G.C.WHITE }, { size = 0.9, speed = 3 })
				F.beam(card, F.partner_hand, G.C.RED, 0.35, { jitter = 0.2, sound = false })
			end)
			return { mult = UNION_MULT }
		end
	end,
})

SMODS.Edition({
	key = 'ether',
	shader = 'ether',
	config = { x_mult = 1.3 },
	in_shop = true,
	weight = 3,
	extra_cost = 5,
	get_weight = coop_weight,
	sound = { sound = 'negative', per = 1.6, vol = 0.4 },
	loc_vars = function(self, info_queue, card)
		return { vars = { 1.3 } }
	end,
	calculate = function(self, card, context)
		if context.post_joker or (context.main_scoring and context.cardarea == G.play) then
			fx(function(F)
				F.burst(card, { { 0.75, 0.85, 1, 0.6 }, G.C.WHITE }, { size = 1, speed = 1.5, lifespan = 0.9 })
			end)
			return { xmult = 1.3 }
		end
	end,
})

-- Union cards the partner holds also boost our hands: their jokers count
-- always, their playing cards only when they are played (that's theirs).
function CC.union_mult()
	local n = 0
	for _, p in ipairs(partner_codes('jokers')) do
		if p[4] == 'e_coop_union' then
			n = n + 1
		end
	end
	return n * UNION_MULT
end
