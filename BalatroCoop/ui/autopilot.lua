-- Autopilot (dev mode): the window plays by itself, through the same
-- buttons a person would press, so every co-op rule (turns, shared shop,
-- host picks the blind...) applies to it. On by default in both dev windows,
-- F7 toggles it.
--
-- Plays the best-scoring hand it can find, discards weak hands, uses
-- consumables, buys co-op cards first (offering them to the partner), opens
-- packs, cashes out, leaves the shop. Now and then it says something on the
-- chat wheel and pings a card.

COOP.BOT = COOP.BOT or {}
local BOT = COOP.BOT

local TOGGLE_KEY = 'f7'
local STEP_EVERY = 0.7 -- seconds between actions: slow enough to watch
local CHATTY_EVERY = 25

BOT.on = false
BOT.next_at = 0
BOT.chat_at = 0

-- UI buttons --------------------------------------------------------------------

local function find_button(node, name)
	if not node then
		return nil
	end
	if node.config and node.config.button == name and node.states and node.states.visible and not node.disable_button then
		return node
	end
	for _, child in pairs(node.children or {}) do
		local found = type(child) == 'table' and find_button(child, name)
		if found then
			return found
		end
	end
end

-- press the visible, enabled button that calls G.FUNCS[name]
local function press(name)
	for _, box in ipairs(G.I.UIBOX or {}) do
		local b = find_button(box.UIRoot, name)
		if b then
			b:click()
			return true
		end
	end
	return false
end

-- Hands ------------------------------------------------------------------------

local function estimate(cards)
	local text, _, _, scoring = G.FUNCS.get_poker_hand_info(cards)
	local hand = G.GAME.hands[text]
	if not hand then
		return 0, scoring
	end
	local chips = hand.chips
	for _, c in ipairs(scoring) do
		if not c.debuff then
			chips = chips + c:get_chip_bonus()
		end
	end
	return chips * hand.mult, scoring, text
end

-- best subset of up to 5 cards (at most 8 in hand: 218 subsets)
local function best_hand(cards)
	local best, best_set, best_text = -1, nil, nil
	local n = #cards
	local pick = {}
	local function walk(start)
		if #pick > 0 then
			local score, _, text = estimate(pick)
			if score > best then
				best, best_set, best_text = score, { unpack(pick) }, text
			end
		end
		if #pick == 5 then
			return
		end
		for i = start, n do
			pick[#pick + 1] = cards[i]
			walk(i + 1)
			pick[#pick] = nil
		end
	end
	walk(1)
	return best_set or {}, best, best_text
end

local function highlight(cards)
	G.hand:unhighlight_all()
	for _, c in ipairs(cards) do
		G.hand:add_to_highlighted(c, true)
	end
end

local WEAK = { ['High Card'] = true, Pair = true }

local function play_turn()
	local hand_cards = {}
	for _, c in ipairs(G.hand.cards) do
		hand_cards[#hand_cards + 1] = c
	end
	if #hand_cards > 8 then
		table.sort(hand_cards, function(a, b)
			return a:get_chip_bonus() > b:get_chip_bonus()
		end)
		for i = #hand_cards, 9, -1 do
			hand_cards[i] = nil
		end
	end
	local set, _, text = best_hand(hand_cards)
	if #set == 0 then
		return false
	end
	-- weak hand and discards left: throw away what doesn't score
	if WEAK[text] and G.GAME.current_round.discards_left > 0 and G.GAME.current_round.hands_left > 1 then
		local keep = {}
		for _, c in ipairs(set) do
			keep[c] = true
		end
		local junk = {}
		for _, c in ipairs(G.hand.cards) do
			if not keep[c] and #junk < 5 then
				junk[#junk + 1] = c
			end
		end
		if #junk > 0 then
			highlight(junk)
			BOT.pending = 'discard_cards_from_highlighted'
			return true
		end
	end
	highlight(set)
	BOT.pending = 'play_cards_from_highlighted'
	return true
end

-- Consumables: planets straight away, tarots on the first cards in hand.
local function use_consumable(area)
	for _, card in ipairs(area and area.cards or {}) do
		local max = card.ability.consumeable and (card.ability.max_highlighted or card.ability.consumeable.max_highlighted)
		if max and G.hand and #G.hand.cards > 0 then
			local targets = {}
			for i = 1, math.min(max, #G.hand.cards) do
				targets[#targets + 1] = G.hand.cards[i]
			end
			highlight(targets)
		end
		if card.ability.consumeable and card:can_use_consumeable() then
			G.FUNCS.use_card({ config = { ref_table = card } })
			return true
		end
		if max and G.hand then
			G.hand:unhighlight_all()
		end
	end
	return false
end

-- Shop -------------------------------------------------------------------------

local function is_coop(card)
	return card.config.center.key:find('_coop_') ~= nil
end

local function affordable(card)
	return card.cost <= G.GAME.dollars - G.GAME.bankrupt_at
end

local function buy_something()
	local candidates = {}
	for _, area in ipairs({ G.shop_jokers, G.shop_booster, G.shop_vouchers }) do
		for _, c in ipairs(area and area.cards or {}) do
			if affordable(c) and not BOT.tried[c] then
				candidates[#candidates + 1] = c
			end
		end
	end
	table.sort(candidates, function(a, b)
		if is_coop(a) ~= is_coop(b) then
			return is_coop(a)
		end
		return a.cost < b.cost
	end)
	local card = candidates[1]
	if not card then
		return false
	end
	BOT.tried[card] = true
	if is_coop(card) and COOP.SOCIAL and COOP.SOCIAL.ping_card then
		pcall(COOP.SOCIAL.ping_card, card, 4) -- "offer" ping for the partner
	end
	if card.area == G.shop_jokers then
		if card.ability.set == 'Joker' or card.ability.consumeable then
			if G.FUNCS.check_for_buy_space(card) then
				G.FUNCS.buy_from_shop({ config = { ref_table = card } })
			end
		else
			G.FUNCS.buy_from_shop({ config = { ref_table = card } })
		end
	else
		G.FUNCS.use_card({ config = { ref_table = card } }) -- open pack / redeem voucher
	end
	return true
end

local PACK_STATES = {}

local function in_pack()
	return G.pack_cards and G.pack_cards.cards and #G.pack_cards.cards > 0 and PACK_STATES[G.STATE]
end

local function pick_from_pack()
	for _, card in ipairs(G.pack_cards.cards) do
		if card.ability.set == 'Joker' then
			if G.jokers and #G.jokers.cards < G.jokers.config.card_limit then
				G.FUNCS.use_card({ config = { ref_table = card } })
				return true
			end
		elseif card.ability.consumeable then
			local max = card.ability.max_highlighted or card.ability.consumeable.max_highlighted
			if max and G.hand and #G.hand.cards > 0 then
				local t = {}
				for i = 1, math.min(max, #G.hand.cards) do
					t[#t + 1] = G.hand.cards[i]
				end
				highlight(t)
			end
			if card:can_use_consumeable() then
				G.FUNCS.use_card({ config = { ref_table = card } })
				return true
			end
			if G.hand then
				G.hand:unhighlight_all()
			end
		else
			G.FUNCS.use_card({ config = { ref_table = card } }) -- playing card
			return true
		end
	end
	return press('skip_booster')
end

-- Chatter ------------------------------------------------------------------------

local function chatter()
	if G.TIMERS.REAL < BOT.chat_at then
		return
	end
	BOT.chat_at = G.TIMERS.REAL + CHATTY_EVERY * (0.6 + math.random() * 0.8)
	local i = math.random(0, 7)
	COOP.send('wheel', { i = i })
	if COOP.SOCIAL.on_wheel_self then
		pcall(COOP.SOCIAL.on_wheel_self, i)
	end
end

-- One action per step ---------------------------------------------------------------

local function act()
	local S = G.STATES
	if G.STATE ~= S.SELECTING_HAND then
		BOT.pending = nil
	end
	if G.STATE == S.BLIND_SELECT then
		-- only the blind on deck: the others' buttons are live for a moment too
		local opt = G.blind_select_opts and G.blind_select_opts[string.lower(G.GAME.blind_on_deck or '')]
		local b = opt and opt:get_UIE_by_ID('select_blind_button')
		if b and b.config.button == 'select_blind' and not b.disable_button then
			b:click()
			return true
		end
		return false
	elseif G.STATE == S.SELECTING_HAND then
		if COOP.SB.my_turn() ~= true then
			return false
		end
		-- cards were picked last step: the button is enabled by now
		if BOT.pending then
			local name = BOT.pending
			BOT.pending = nil
			if press(name) then
				return true
			end
			G.hand:unhighlight_all()
			return false
		end
		if use_consumable(G.consumeables) then
			return true
		end
		return play_turn()
	elseif G.STATE == S.ROUND_EVAL then
		return press('cash_out')
	elseif G.STATE == S.SHOP then
		if BOT.shop_round ~= G.GAME.round then
			BOT.shop_round, BOT.tried, BOT.buys = G.GAME.round, {}, 0
			-- the guest shops a bit later, so two bots don't spend the shared
			-- wallet at the same moment
			BOT.money_seen, BOT.money_at = nil, G.TIMERS.REAL + (COOP.DEV.role == 'guest' and 3 or 0)
		end
		-- wait until the wallet has stopped moving (the partner's buys arrive)
		if G.GAME.dollars ~= BOT.money_seen then
			BOT.money_seen, BOT.money_at = G.GAME.dollars, math.max(BOT.money_at or 0, G.TIMERS.REAL + 1.5)
			return false
		end
		if G.TIMERS.REAL < (BOT.money_at or 0) then
			return false
		end
		if BOT.buys < 4 and buy_something() then
			BOT.buys = BOT.buys + 1
			return true
		end
		if use_consumable(G.consumeables) then
			return true
		end
		return press('toggle_shop')
	elseif in_pack() then
		return pick_from_pack()
	end
	return false
end

function BOT.update()
	if not BOT.on or not COOP.is_active() or G.STAGE ~= G.STAGES.RUN then
		return
	end
	if G.CONTROLLER.locked or G.OVERLAY_MENU or (G.GAME and G.GAME.STOP_USE and G.GAME.STOP_USE > 0) then
		return
	end
	local t = G.TIMERS.REAL
	if t < BOT.next_at then
		return
	end
	BOT.next_at = t + STEP_EVERY
	BOT.tried = BOT.tried or {}
	local ok, err = pcall(act)
	if not ok then
		sendWarnMessage('autopilot: ' .. tostring(err), COOP.id)
		BOT.next_at = t + 3
	end
	pcall(chatter)
end

function BOT.toggle()
	BOT.on = not BOT.on
	COOP.popup(BOT.on and 'Автопилот: ВКЛ' or 'Автопилот: ВЫКЛ', BOT.on and G.C.GREEN or G.C.RED)
end

function BOT.install()
	local S = G.STATES
	for _, s in ipairs({ S.TAROT_PACK, S.PLANET_PACK, S.SPECTRAL_PACK, S.STANDARD_PACK, S.BUFFOON_PACK, S.SMODS_BOOSTER_OPENED }) do
		if s then
			PACK_STATES[s] = true
		end
	end
	BOT.on = COOP.DEV.on() -- both dev windows play; F7 to take over
	local key_press_ref = Controller.key_press_update
	function Controller:key_press_update(key, dt)
		if key == TOGGLE_KEY and COOP.DEV.on() then
			BOT.toggle()
		end
		return key_press_ref(self, key, dt)
	end
end
