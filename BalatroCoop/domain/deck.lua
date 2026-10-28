-- One shared deck for both players.
--
-- Both clients hold every card of the shared deck (COOP.DECK_COPIES standard
-- decks). Each card has a shared id (ability.coop_uid). A card the partner
-- holds sits in our hidden "away" area, so it can't be drawn twice:
--   * the host draws from the top of the deck, the guest from the bottom,
--     so simultaneous draws never pick the same card
--   * drawing a card announces it ('card_take'); the partner moves their copy away
--   * any change to a card we hold (tarot, seal, edition, Hiker bonus...) is
--     sent ('card_update') and applied to the partner's copy
--   * destroyed and newly added cards are mirrored ('card_remove' / 'card_add')
--   * shuffles first bring every away card back, then shuffle in uid order with
--     the same seed on both sides; the host also sends its deck order so the
--     guest can correct any drift ('deck_order')

COOP.DECK = COOP.DECK or {}
local DK = COOP.DECK

COOP.DECK_COPIES = 2 -- 2 x 52 = 104 shared cards
local POLL_EVERY = 0.2
local ORDER_EVERY = 0.5

local function is_host()
	local lobby = MPAPI.get_current_lobby()
	return lobby and lobby.is_host
end

function DK.reset()
	DK.by_uid = {} -- uid -> card
	DK.look = {} -- uid -> last look we know both sides agree on
	DK.held = {} -- uid -> true while we hold the card (hand/play/discard)
	DK.next_uid = 0
	DK.poll_timer = 0
	DK.order_timer = 0
	DK.dealt = false
	DK.last_order = nil
	if DK.away then
		DK.away:remove()
	end
	DK.away = nil
end
DK.reset()

-- Card state ----------------------------------------------------------------

function DK.look_of(card)
	return table.concat({
		card.config.card_key or '',
		card.config.center.key,
		card.edition and card.edition.key or '',
		card.seal or '',
		tostring(card.ability.perma_bonus or 0),
	}, '|')
end

local function split(s, sep)
	local out = {}
	for part in string.gmatch(s .. sep, '(.-)' .. sep) do
		out[#out + 1] = part
	end
	return out
end

local function apply_look(card, look)
	local f = split(look, '|')
	local front, center, edition, seal, bonus = f[1], f[2], f[3], f[4], tonumber(f[5]) or 0
	if front ~= '' and card.config.card_key ~= front and G.P_CARDS[front] then
		card:set_base(G.P_CARDS[front])
	end
	if card.config.center.key ~= center and G.P_CENTERS[center] then
		card:set_ability(G.P_CENTERS[center])
	end
	local cur_edition = card.edition and card.edition.key or ''
	if cur_edition ~= edition then
		card:set_edition(edition ~= '' and edition or nil, true, true)
	end
	if (card.seal or '') ~= seal then
		card:set_seal(seal ~= '' and seal or nil, true, true)
	end
	card.ability.perma_bonus = bonus
end

local function register(card, uid)
	card.ability.coop_uid = uid
	DK.by_uid[uid] = card
	DK.look[uid] = DK.look_of(card)
end

local function new_uid()
	DK.next_uid = DK.next_uid + 1
	return (is_host() and 'h' or 'g') .. DK.next_uid
end

local function create_card(uid, look, area)
	local f = split(look, '|')
	local card = create_playing_card({ front = G.P_CARDS[f[1]], center = G.P_CENTERS[f[2]] or G.P_CENTERS.c_base }, area, true, true)
	apply_look(card, look)
	register(card, uid)
	return card
end

local function move(card, to)
	if card.area == to then
		return
	end
	if card.area then
		card.area:remove_card(card)
	end
	to:emplace(card)
end

-- Deal ------------------------------------------------------------------------

local function ensure_away()
	if not DK.away then
		DK.away = CardArea(-30, -30, G.CARD_W, G.CARD_H, { card_limit = 999, type = 'discard' })
	end
	return DK.away
end

-- Deterministic: every card gets a key from the run seed, the shuffle seed and
-- its uid, so two cards end up in the same relative order on both sides even
-- if one side holds a card the other doesn't have in its deck.
local function shuffle_deck(seed)
	local cards = G.deck.cards
	local salt = tostring(G.GAME.pseudorandom.seed) .. (seed or 'shuffle') .. tostring(G.GAME.round)
	local key = {}
	for _, c in ipairs(cards) do
		local uid = c.ability.coop_uid or ''
		key[c] = { pseudohash(salt .. uid), uid }
	end
	table.sort(cards, function(a, b)
		local ka, kb = key[a], key[b]
		if ka[1] ~= kb[1] then
			return ka[1] < kb[1]
		end
		return ka[2] < kb[2]
	end)
	G.deck:set_ranks()
	DK.last_order = nil -- host re-sends its order
end

function DK.deal()
	DK.reset()
	ensure_away()
	local protos = {}
	for _, card in ipairs(G.playing_cards) do
		protos[#protos + 1] = DK.look_of(card)
	end
	table.sort(protos)
	for i = #G.playing_cards, 1, -1 do
		G.playing_cards[i]:remove()
	end
	local n = 0
	for _ = 1, COOP.DECK_COPIES do
		for _, look in ipairs(protos) do
			n = n + 1
			create_card(string.format('c%03d', n), look, G.deck)
		end
	end
	G.GAME.starting_deck_size = #G.playing_cards
	shuffle_deck('coop_deal')
	DK.dealt = true
	G.deck:hard_set_T()
end

-- Polling our own side --------------------------------------------------------

local function location(card)
	if card.area == G.deck then
		return 'deck'
	elseif DK.away and card.area == DK.away then
		return 'away'
	end
	return 'mine'
end

function DK.poll()
	local present = {}
	for _, card in ipairs(G.playing_cards) do
		local uid = card.ability.coop_uid
		if not uid or DK.by_uid[uid] ~= card then
			-- a brand-new card (DNA, Cryptid, Certificate, Marble...)
			uid = new_uid()
			register(card, uid)
			local where = location(card)
			COOP.send('card_add', { uid = uid, look = DK.look[uid], to_deck = where == 'deck' })
			if where == 'mine' then
				DK.held[uid] = true
			end
		end
		present[uid] = true

		local where = location(card)
		if where ~= 'away' then
			local look = DK.look_of(card)
			if look ~= DK.look[uid] then
				DK.look[uid] = look
				COOP.send('card_update', { uid = uid, look = look })
			end
			if where == 'mine' and not DK.held[uid] then
				DK.held[uid] = true
				COOP.send('card_take', { uid = uid })
			elseif where == 'deck' then
				DK.held[uid] = nil
			end
		end
	end
	for uid in pairs(DK.by_uid) do
		if not present[uid] then
			DK.by_uid[uid], DK.look[uid], DK.held[uid] = nil, nil, nil
			COOP.send('card_remove', { uid = uid })
		end
	end
end

function DK.send_order()
	DK.poll() -- announce our takes before the order that no longer lists them
	local uids = {}
	for i, c in ipairs(G.deck.cards) do
		uids[i] = c.ability.coop_uid or ''
	end
	local order = table.concat(uids, ';')
	if order ~= DK.last_order then
		DK.last_order = order
		COOP.send('deck_order', { uids = order })
	end
end

function DK.update(dt)
	if not DK.dealt or not G.deck or not G.playing_cards then
		return
	end
	ensure_away()
	DK.poll_timer = DK.poll_timer + dt
	if DK.poll_timer >= POLL_EVERY then
		DK.poll_timer = 0
		DK.poll()
	end
	if is_host() then
		DK.order_timer = DK.order_timer + dt
		if DK.order_timer >= ORDER_EVERY then
			DK.order_timer = 0
			DK.send_order()
		end
	end
end

-- Partner -> us -----------------------------------------------------------------

function DK.on_take(uid)
	local card = DK.by_uid[uid]
	if card and card.area == G.deck then
		move(card, ensure_away())
	end
end

function DK.on_update(uid, look)
	local card = DK.by_uid[uid]
	if card then
		DK.look[uid] = look
		apply_look(card, look)
	end
end

function DK.on_add(uid, look, to_deck)
	if DK.by_uid[uid] then
		return
	end
	create_card(uid, look, to_deck and G.deck or ensure_away())
end

function DK.on_remove(uid)
	local card = DK.by_uid[uid]
	if not card then
		return
	end
	DK.by_uid[uid], DK.look[uid], DK.held[uid] = nil, nil, nil
	if card.area then
		card.area:remove_card(card)
	end
	card:remove()
end

-- Host's deck order: put our deck cards in the same order.
function DK.on_order(uids)
	local in_deck = {}
	for _, c in ipairs(G.deck.cards) do
		in_deck[c] = true
	end
	local ordered, used = {}, {}
	for _, uid in ipairs(split(uids, ';')) do
		local c = DK.by_uid[uid]
		if c and in_deck[c] and not used[c] then
			ordered[#ordered + 1] = c
			used[c] = true
		end
	end
	-- cards the host doesn't list (it may be holding them) go on top: the
	-- guest draws from the bottom, so it won't draw them before they settle
	for _, c in ipairs(G.deck.cards) do
		if not used[c] then
			ordered[#ordered + 1] = c
		end
	end
	G.deck.cards = ordered
	G.deck:set_ranks()
end

-- The Pass team joker: hand a card to the partner.
function DK.pass_card(card)
	local uid = card.ability.coop_uid
	if not uid then
		return
	end
	DK.held[uid] = nil
	move(card, ensure_away())
	COOP.send('pass', { uid = uid })
end

function DK.on_pass(uid)
	local card = DK.by_uid[uid]
	if not card then
		return
	end
	DK.held[uid] = true -- partner already knows it's ours
	if card.area then
		card.area:remove_card(card)
	end
	card.T.x, card.T.y = G.deck.T.x, G.deck.T.y
	G.hand:emplace(card)
	card:juice_up(0.4, 0.4)
	play_sound('card1')
	COOP.popup(localize('k_coop_passed_to_you'), G.C.GREEN)
end

-- The Shared Hand team joker: take a card out of the partner's hand.
-- Our copy of it sits in the away area; it moves into our hand right away and
-- the partner drops theirs. If they played it meanwhile, they refuse and we
-- put it back.
function DK.take_from_partner(uid)
	local card = DK.by_uid[uid]
	if not card or card.area ~= DK.away then
		return false
	end
	DK.away:remove_card(card)
	card.T.x, card.T.y = COOP.PV.hand_area and COOP.PV.hand_area.T.x or G.deck.T.x, COOP.PV.hand_area and COOP.PV.hand_area.T.y or G.deck.T.y
	G.hand:emplace(card)
	DK.held[uid] = true -- the partner knows; no 'card_take'
	card:juice_up(0.4, 0.4)
	play_sound('card1')
	COOP.send('take_card', { uid = uid })
	return true
end

function DK.on_partner_took(uid)
	local card = DK.by_uid[uid]
	if not card or card.area ~= G.hand then
		COOP.send('take_reject', { uid = uid })
		return
	end
	if card.highlighted then
		G.hand:remove_from_highlighted(card, true)
	end
	DK.held[uid] = nil
	move(card, ensure_away())
	COOP.popup(localize('k_coop_partner_took'), G.C.SECONDARY_SET.Planet)
end

function DK.on_take_rejected(uid)
	local card = DK.by_uid[uid]
	if card and card.area == G.hand then
		if card.highlighted then
			G.hand:remove_from_highlighted(card, true)
		end
		DK.held[uid] = nil
		move(card, ensure_away())
	end
	COOP.TEAM.take_used_round = nil -- didn't happen, may try again
end

-- Hooks -------------------------------------------------------------------------

function DK.install_hooks()
	local start_run_ref = Game.start_run
	function Game:start_run(args)
		start_run_ref(self, args)
		if COOP.in_run and MPAPI.is_active(COOP.id) and not (args and args.savetext) and COOP.MODES.on('shared_deck') then
			DK.deal()
		end
	end

	-- The guest draws from the bottom of the shared deck. The normal draw picks
	-- its cards from the top up front and then draws those exact cards, so
	-- flip the deck while the guest's draw is picking.
	local draw_ref = G.FUNCS.draw_from_deck_to_hand
	G.FUNCS.draw_from_deck_to_hand = function(e)
		if not COOP.is_active() or is_host() or not G.deck or not DK.dealt then
			return draw_ref(e)
		end
		local function flip()
			local c = G.deck.cards
			for i = 1, math.floor(#c / 2) do
				c[i], c[#c - i + 1] = c[#c - i + 1], c[i]
			end
		end
		flip()
		local ok, res = pcall(draw_ref, e)
		flip()
		if not ok then
			error(res)
		end
		return res
	end

	-- draws that ask the deck for "the next card" (packs, some jokers)
	local remove_card_ref = CardArea.remove_card
	function CardArea:remove_card(card, discarded_only)
		if not card and self == G.deck and not discarded_only and COOP.is_active() and DK.dealt and not is_host() and self.cards[1] then
			card = self.cards[1]
		end
		return remove_card_ref(self, card, discarded_only)
	end

	local shuffle_ref = CardArea.shuffle
	function CardArea:shuffle(seed)
		if self ~= G.deck or not COOP.is_active() then
			return shuffle_ref(self, seed)
		end
		if not DK.dealt then
			-- separate decks: same seed, same cards -> the guest shuffles with
			-- its own seed, or both would draw the very same hands
			return shuffle_ref(self, is_host() and seed or ((seed or 'shuffle') .. '_guest'))
		end
		-- whatever the partner held is back in the shared deck now, except the
		-- cards already in their new hand (they may have drawn before we shuffle)
		if DK.away then
			local in_partner_hand = {}
			local p = COOP.PV.partner
			for entry in string.gmatch((p and p.hand or '') .. ';', '([^;]*);') do
				local uid = entry:match('^[^|]*|[^|]*|[^|]*|[^|]*|[^|]*|[^|]*|([^|]*)')
				if uid and uid ~= '' then
					in_partner_hand[uid] = true
				end
			end
			for i = #DK.away.cards, 1, -1 do
				local c = DK.away.cards[i]
				if not in_partner_hand[c.ability.coop_uid or ''] then
					DK.away:remove_card(c)
					G.deck:emplace(c)
				end
			end
		end
		DK.held = {}
		shuffle_deck(seed)
	end
end
