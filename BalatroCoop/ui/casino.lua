-- Casino: its own scene, entered from the shop (the shop slides away like
-- when a pack is opened, the casino slides in where it was). A hub page leads
-- to two separate games:
--
--   Slots      three reels of real joker cards; three of a kind pays by
--              symbol, any pair pays the bet x1.5 (about 90% back over time)
--   Blackjack  real playing cards from a six-deck shoe, casino rules:
--              dealer stands on soft 17 and peeks for blackjack, blackjack
--              pays 3:2, insurance 2:1, double on the first two cards, one
--              split (split aces take one card each)
--
-- The bet is the player's choice (steppers, up to all of their money). Money
-- is shared (domain/money.lua): bets and wins show in the partner's wallet,
-- and a big win is announced in the chat.

COOP.CASINO = COOP.CASINO or {}
local CS = COOP.CASINO

local CARD_SCALE = 0.85 -- blackjack cards
local REEL_SCALE = 1.25 -- slot jokers
-- the casino fills the board right of the HUD (offset from the room centre)
local SCENE_X = 2.45
local SCENE_W, SCENE_H = 14, 9.8

-- Reel symbols (joker, weight on the reel). Blueprint is wild: it stands in
-- for any joker. The rules are checked top to bottom, the first match pays
-- (bet x pays, rounded down). Tuned by enumerating all 27000 outcomes: the
-- slots pay back about 92%.
local WILD = 'j_blueprint'
local SYMBOLS = {
	{ key = 'j_golden', w = 1 },
	{ key = 'j_blueprint', w = 2 },
	{ key = 'j_gros_michel', w = 3 },
	{ key = 'j_cavendish', w = 3 },
	{ key = 'j_greedy_joker', w = 4 },
	{ key = 'j_lusty_joker', w = 4 },
	{ key = 'j_wrathful_joker', w = 4 },
	{ key = 'j_gluttenous_joker', w = 4 },
	{ key = 'j_joker', w = 5 },
}
local REEL_WEIGHT = 0
for _, sym in ipairs(SYMBOLS) do
	REEL_WEIGHT = REEL_WEIGHT + sym.w
end
local SUITS = { j_greedy_joker = true, j_lusty_joker = true, j_wrathful_joker = true, j_gluttenous_joker = true }
local BANANAS = { j_gros_michel = true, j_cavendish = true }

local function count(r, key)
	local n = 0
	for _, k in ipairs(r) do
		if k == key then
			n = n + 1
		end
	end
	return n
end

-- three of `key`, Blueprints standing in (at least one real one)
local function three_of(key)
	return function(r)
		for _, k in ipairs(r) do
			if k ~= key and k ~= WILD then
				return false
			end
		end
		return count(r, key) >= 1
	end
end

local RULES = {
	{ id = 'three_golden', pays = 100, example = { 'j_golden', 'j_golden', 'j_golden' }, test = function(r) return count(r, 'j_golden') == 3 end },
	{ id = 'golden_wild', pays = 50, example = { 'j_golden', WILD, 'j_golden' }, test = three_of('j_golden') },
	{ id = 'three_wild', pays = 30, example = { WILD, WILD, WILD }, test = function(r) return count(r, WILD) == 3 end },
	{ id = 'three_gros', pays = 12, example = { 'j_gros_michel', 'j_gros_michel', 'j_gros_michel' }, test = three_of('j_gros_michel') },
	{ id = 'three_cav', pays = 12, example = { 'j_cavendish', 'j_cavendish', WILD }, test = three_of('j_cavendish') },
	{ id = 'three_greedy', pays = 8, example = { 'j_greedy_joker', 'j_greedy_joker', 'j_greedy_joker' }, test = three_of('j_greedy_joker') },
	{ id = 'three_lusty', pays = 8, example = { 'j_lusty_joker', 'j_lusty_joker', 'j_lusty_joker' }, test = three_of('j_lusty_joker') },
	{ id = 'three_wrath', pays = 8, example = { 'j_wrathful_joker', WILD, 'j_wrathful_joker' }, test = three_of('j_wrathful_joker') },
	{ id = 'three_glut', pays = 8, example = { 'j_gluttenous_joker', 'j_gluttenous_joker', 'j_gluttenous_joker' }, test = three_of('j_gluttenous_joker') },
	{ id = 'three_joker', pays = 6, example = { 'j_joker', 'j_joker', 'j_joker' }, test = three_of('j_joker') },
	{ id = 'bananas', pays = 5, example = { 'j_gros_michel', 'j_cavendish', 'j_gros_michel' }, test = function(r)
		local any = false
		for _, k in ipairs(r) do
			if not (BANANAS[k] or k == WILD) then
				return false
			end
			any = any or BANANAS[k]
		end
		return any
	end },
	{ id = 'all_suits', pays = 3, example = { 'j_greedy_joker', 'j_lusty_joker', 'j_wrathful_joker' }, test = function(r)
		return SUITS[r[1]] and SUITS[r[2]] and SUITS[r[3]] and r[1] ~= r[2] and r[2] ~= r[3] and r[1] ~= r[3]
	end },
	{ id = 'two_golden', pays = 5, example = { 'j_golden', 'j_joker', 'j_golden' }, test = function(r) return count(r, 'j_golden') >= 2 end },
	{ id = 'pair', pays = 0.5, example = { 'j_joker', 'j_joker', 'j_cavendish' }, test = function(r)
		if count(r, WILD) > 0 then
			return true -- a Blueprint pairs with anything
		end
		return r[1] == r[2] or r[2] == r[3] or r[1] == r[3]
	end },
}

local function match(r)
	for _, rule in ipairs(RULES) do
		if rule.test(r) then
			return rule
		end
	end
end

CS.text = { info = '', bet = '', slots = '', dealer = '', hand1 = '', hand2 = '', bj = '' }
CS.bet = 2

local function dollars()
	return tonumber(G.GAME and G.GAME.dollars) or 0
end

local function name_of(key)
	return localize({ type = 'name_text', set = 'Joker', key = key })
end

local function pay(amount, game)
	if amount <= 0 then
		return
	end
	ease_dollars(amount)
	play_sound('coin3')
	if amount >= CS.bet * 5 then
		play_sound('multhit2')
		pcall(COOP.CHAT.send, localize({ type = 'variable', key = 'coop_casino_big_win', vars = { game, amount } }))
	end
end

-- display-only cards: no clicks, no dragging, no tooltips
local function display_card(front, center, area, scale)
	local x, y = area.T.x + area.T.w / 2, area.T.y
	if front and G.deck then
		x, y = G.deck.T.x, G.deck.T.y -- dealt from our deck
	end
	local card = Card(x, y, G.CARD_W * scale, G.CARD_H * scale, front, center, { bypass_discovery_center = true, bypass_discovery_ui = true })
	card.coop_display = true
	card.states.drag.can = false
	card.states.click.can = false
	card.states.hover.can = false
	area:emplace(card)
	return card
end

local function clear_area(area)
	for i = #(area and area.cards or {}), 1, -1 do
		local c = area.cards[i]
		area:remove_card(c)
		c:remove()
	end
end

-- Scene -------------------------------------------------------------------------

local function T(str, scale, col)
	return { n = G.UIT.T, config = { text = str, scale = scale or 0.4, colour = col or G.C.WHITE, shadow = true } }
end

local function RT(key, scale, col)
	return { n = G.UIT.T, config = { ref_table = CS.text, ref_value = key, scale = scale or 0.4, colour = col or G.C.WHITE, shadow = true } }
end

local function R(nodes, padding, extra)
	local config = { align = 'cm', padding = padding or 0.05 }
	for k, v in pairs(extra or {}) do
		config[k] = v
	end
	return { n = G.UIT.R, config = config, nodes = nodes }
end

local function O(object)
	return { n = G.UIT.O, config = { object = object } }
end

-- gate: G.FUNCS name that greys the button out while ok() is false
local function button(action, label, col, w, gate, scale)
	return UIBox_button({ button = action, func = gate, label = { label }, minw = w or 2.2, minh = 0.65, scale = scale or 0.42, colour = col, col = true })
end

local function make_gate(name, action, col, ok)
	G.FUNCS[name] = function(e)
		if ok() then
			e.config.colour = col
			e.config.button = action
		else
			e.config.colour = G.C.UI.BACKGROUND_INACTIVE
			e.config.button = nil
		end
	end
end

-- Removes the shown page (and the card areas placed in it). The next page's
-- areas are made before it is shown, so this must not touch CS.reels etc.
local function remove_box()
	if CS.box then
		CS.box:remove()
		CS.box = nil
	end
end

local function forget_areas()
	CS.reels, CS.dealer_area, CS.hand_areas = nil, nil, nil
end

local function show(definition, slide_in)
	remove_box()
	CS.box = UIBox({
		definition = { n = G.UIT.ROOT, config = { align = 'cl', colour = G.C.CLEAR }, nodes = {
			{ n = G.UIT.C, config = { align = 'tm', padding = 0.2, r = 0.15, emboss = 0.05, colour = G.C.DYN_UI.BOSS_MAIN, minw = SCENE_W, minh = SCENE_H }, nodes = definition },
		} },
		config = { align = 'cm', offset = { x = SCENE_X, y = slide_in and 20 or 0 }, major = G.ROOM_ATTACH, bond = 'Weak' },
	})
	if slide_in then
		G.E_MANAGER:add_event(Event({
			func = function()
				if CS.box then
					CS.box.alignment.offset.y = 0
				end
				return true
			end,
		}))
	end
end

-- bet picker shared by both games; locked while a game is running
local function bet_row()
	return R({
		T(localize('k_coop_casino_bet') .. ':  ', 0.5),
		button('coop_casino_bet_m10', '-10', G.C.GREY, 1, 'coop_casino_can_bet', 0.48),
		button('coop_casino_bet_m1', '-1', G.C.GREY, 1, 'coop_casino_can_bet', 0.48),
		{ n = G.UIT.C, config = { align = 'cm', minw = 1.8, minh = 0.75, r = 0.1, colour = G.C.BLACK }, nodes = { RT('bet', 0.65, G.C.MONEY) } },
		button('coop_casino_bet_p1', '+1', G.C.GREY, 1, 'coop_casino_can_bet', 0.48),
		button('coop_casino_bet_p10', '+10', G.C.GREY, 1, 'coop_casino_can_bet', 0.48),
		button('coop_casino_bet_max', localize('k_coop_casino_max'), G.C.GREY, 1.4, 'coop_casino_can_bet', 0.48),
	}, 0.08)
end

-- title row: back button on the left (always on screen), money on the right
local function header(title, back)
	return {
		R({
			back,
			{ n = G.UIT.C, config = { align = 'cm', minw = 8.4 }, nodes = { T(title, 1, G.C.GOLD) } },
			{ n = G.UIT.C, config = { align = 'cm', minw = 2.8 }, nodes = { RT('info', 0.5, G.C.MONEY) } },
		}, 0.1),
	}
end

local function back_button()
	return button('coop_casino_hub', localize('k_coop_casino_back'), G.C.ORANGE, 2.6, 'coop_casino_can_back', 0.5)
end

local function append(list, more)
	for _, v in ipairs(more) do
		list[#list + 1] = v
	end
	return list
end

-- Hub ----------------------------------------------------------------------------

local function hub()
	CS.page = 'hub'
	forget_areas()
	-- two big tables to pick from, each showing what it is played with
	CS.hub_cards = {
		CardArea(0, 0, G.CARD_W * 2.6, G.CARD_H * 1.1, { card_limit = 2, type = 'title', card_w = G.CARD_W }),
		CardArea(0, 0, G.CARD_W * 3.4, G.CARD_H * 1.1, { card_limit = 3, type = 'title', card_w = G.CARD_W * 0.95 }),
	}
	local function game_tile(action, label, col, area)
		return { n = G.UIT.C, config = { align = 'cm', padding = 0.2, r = 0.15, colour = { 0, 0, 0, 0.3 }, minw = 5.6, minh = 5.2 }, nodes = {
			R({ O(area) }, 0.1),
			R({ button(action, label, col, 4.6, nil, 0.75) }, 0.1),
		} }
	end
	show(append(header(localize('k_coop_casino'), button('coop_casino_leave', localize('k_coop_casino_back_to_shop'), G.C.ORANGE, 2.6, nil, 0.5)), {
		R({
			game_tile('coop_casino_blackjack', localize('k_coop_casino_blackjack'), G.C.RED, CS.hub_cards[1]),
			{ n = G.UIT.B, config = { w = 0.6, h = 0.1 } },
			game_tile('coop_casino_slots', localize('k_coop_casino_slots'), G.C.PURPLE, CS.hub_cards[2]),
		}, 0.3),
		R({ T(localize('k_coop_casino_hub_hint'), 0.4, G.C.UI.TEXT_LIGHT) }, 0.1),
	}), not CS.box)
end

-- the jokers / consumables / team rows would show through the casino
local function set_rows_visible(visible)
	for _, area in ipairs({ G.jokers, G.consumeables, G.coop_team, G.deck }) do
		if area then
			area.states.visible = visible
		end
	end
end

local function fill_hub()
	local a, b = CS.hub_cards and CS.hub_cards[1], CS.hub_cards and CS.hub_cards[2]
	if not a then
		return
	end
	display_card(G.P_CARDS.S_A, G.P_CENTERS.c_base, a, 1)
	display_card(G.P_CARDS.H_K, G.P_CENTERS.c_base, a, 1)
	for _, key in ipairs({ 'j_golden', 'j_blueprint', 'j_cavendish' }) do
		display_card(nil, G.P_CENTERS[key], b, 0.95)
	end
end

function CS.enter()
	if CS.scene or G.STATE ~= G.STATES.SHOP or not G.shop then
		return
	end
	CS.scene = true
	set_rows_visible(false)
	G.shop.alignment.offset.py = G.shop.alignment.offset.y
	G.shop.alignment.offset.y = G.ROOM.T.y + 29 -- the shop slides away, like for a pack
	play_sound('cardSlide1')
	CS.update_info()
	hub()
	fill_hub()
end

function CS.leave()
	if not CS.scene then
		return
	end
	CS.scene = false
	CS.slots_busy, CS.bj, CS.page = false, nil, nil
	remove_box()
	forget_areas()
	set_rows_visible(true)
	if G.shop then
		G.shop.alignment.offset.y = G.shop.alignment.offset.py or -5.3
	end
	play_sound('cardSlide2')
end

-- Slots ---------------------------------------------------------------------------

local function random_symbol()
	local r = pseudorandom('coop_slots', 1, REEL_WEIGHT)
	for _, sym in ipairs(SYMBOLS) do
		r = r - sym.w
		if r <= 0 then
			return sym
		end
	end
	return SYMBOLS[#SYMBOLS]
end

local function set_reel(k, sym)
	local area = CS.reels and CS.reels[k]
	if not area then
		return
	end
	clear_area(area)
	display_card(nil, G.P_CENTERS[sym.key], area, REEL_SCALE)
end

local function slots_page()
	CS.page = 'slots'
	CS.reels = {}
	local reel_nodes = {}
	for k = 1, 3 do
		CS.reels[k] = CardArea(0, 0, G.CARD_W * REEL_SCALE * 1.1, G.CARD_H * REEL_SCALE * 1.05, { card_limit = 1, type = 'title' })
		reel_nodes[#reel_nodes + 1] = { n = G.UIT.C, config = { align = 'cm', padding = 0.1, r = 0.1, colour = G.C.BLACK }, nodes = { O(CS.reels[k]) } }
		if k < 3 then
			reel_nodes[#reel_nodes + 1] = { n = G.UIT.B, config = { w = 0.15, h = 0.1 } }
		end
	end
	CS.text.slots = localize('k_coop_casino_slots_hint')
	show(append(header(localize('k_coop_casino_slots'), back_button()), {
		R(reel_nodes, 0.15),
		R({ RT('slots', 0.65, G.C.GOLD) }, 0.08),
		bet_row(),
		R({ button('coop_slots_spin', localize('k_coop_casino_spin'), G.C.RED, 4.5, 'coop_slots_can_spin', 0.7) }, 0.1),
		R({ T(localize('k_coop_casino_slots_rule'), 0.38, G.C.UI.TEXT_LIGHT) }, 0.03),
		R({ button('coop_slots_paytable', localize('k_coop_casino_paytable'), G.C.BLUE, 4.5, nil, 0.5) }, 0.05),
	}))
	set_reel(1, SYMBOLS[1])
	set_reel(2, SYMBOLS[2])
	set_reel(3, SYMBOLS[3])
end

-- Payout table window, laid out like the game's Poker Hands list: one row per
-- outcome with example jokers, what it pays and how often it lands. More rows
-- than fit on screen: it scrolls (arrows or the mouse wheel).

local PAY_CARD = 0.3
local ROWS_PER_PAGE = 6

-- chance of each rule being the one that pays, by enumerating every outcome
local chances
local function rule_chances()
	if chances then
		return chances
	end
	chances = { none = 0 }
	for _, a in ipairs(SYMBOLS) do
		for _, b in ipairs(SYMBOLS) do
			for _, c in ipairs(SYMBOLS) do
				local pr = a.w * b.w * c.w / REEL_WEIGHT ^ 3
				local rule = match({ a.key, b.key, c.key })
				local id = rule and rule.id or 'none'
				chances[id] = (chances[id] or 0) + pr
			end
		end
	end
	return chances
end

local function chance_text(p)
	if p >= 0.01 then
		return string.format('%d%%', math.floor(p * 100 + 0.5))
	end
	return localize({ type = 'variable', key = 'coop_casino_one_in', vars = { math.floor(1 / p + 0.5) } })
end

local function pays_text(x)
	return 'x' .. (x == math.floor(x) and tostring(x) or string.format('%.1f', x))
end

local function pill(text, col, w)
	return { n = G.UIT.C, config = { align = 'cm', minw = w, minh = 0.55, r = 0.1, colour = col, padding = 0.03 }, nodes = { T(text, 0.4) } }
end

local function rule_name(id)
	return localize('k_coop_slots_' .. id)
end

-- The window is built once with ROWS_PER_PAGE fixed rows; scrolling only
-- swaps what the rows show (texts through ref tables, the example jokers put
-- straight into place), so nothing pops or slides while you scroll.
CS.pt = {}
for i = 1, ROWS_PER_PAGE do
	CS.pt[i] = { name = '', desc = '', pays = '', chance = '' }
end
CS.pt_pos = { text = '' }

local function ref(t, key, scale, col)
	return { n = G.UIT.T, config = { ref_table = t, ref_value = key, scale = scale, colour = col or G.C.WHITE, shadow = true } }
end

-- small pills, like the ones in Run Info
local function ref_pill(t, key, col, w)
	return { n = G.UIT.C, config = { align = 'cm', minw = w, minh = 0.42, r = 0.1, colour = col, padding = 0.02 }, nodes = { ref(t, key, 0.32) } }
end

local function paytable_row(i)
	local t = CS.pt[i]
	-- 'joker' layout spreads the three side by side ('title' piles them up);
	-- fixed_limit keeps Steamodded's slot bookkeeping off this display area
	-- card_w: the layout spaces cards by this width, a full-size card otherwise
	t.area = CardArea(0, 0, G.CARD_W * PAY_CARD * 3.4, G.CARD_H * PAY_CARD, { card_limit = 3, type = 'joker', fixed_limit = true,
		highlight_limit = 0, no_card_count = true, card_w = G.CARD_W * PAY_CARD })
	return { n = G.UIT.R, config = { align = 'cm', padding = 0.04, r = 0.1, colour = i % 2 == 0 and G.C.L_BLACK or G.C.GREY, minw = 13 }, nodes = {
		{ n = G.UIT.C, config = { align = 'cm', minw = 2.4 }, nodes = { O(t.area) } },
		{ n = G.UIT.C, config = { align = 'cm', minw = 6.6 }, nodes = { -- wide enough for the longest text: no reflow while scrolling
			R({ ref(t, 'name', 0.4) }, 0),
			R({ ref(t, 'desc', 0.26, G.C.UI.TEXT_LIGHT) }, 0),
		} },
		ref_pill(t, 'pays', G.C.MULT, 1.1),
		{ n = G.UIT.C, config = { align = 'cm', minw = 0.35 }, nodes = { T('#', 0.32, G.C.UI.TEXT_LIGHT) } },
		ref_pill(t, 'chance', G.C.BLACK, 1.5),
	} }
end

local function all_rows()
	if CS.pt_list then
		return CS.pt_list
	end
	local list = {}
	local ch = rule_chances()
	for _, rule in ipairs(RULES) do
		list[#list + 1] = { keys = rule.example, id = rule.id, pays = pays_text(rule.pays), chance = chance_text(ch[rule.id] or 0) }
	end
	list[#list + 1] = { keys = { 'j_golden', 'j_joker', 'j_cavendish' }, id = 'none', pays = 'x0', chance = chance_text(ch.none) }
	CS.pt_list = list
	return list
end

local function max_first()
	return math.max(#all_rows() - ROWS_PER_PAGE + 1, 1)
end

-- show rows first .. first + ROWS_PER_PAGE - 1
local function fill_paytable(first)
	local list = all_rows()
	CS.paytable_first = first
	for i = 1, ROWS_PER_PAGE do
		local t, e = CS.pt[i], list[first + i - 1]
		t.name = e and rule_name(e.id) or ''
		t.desc = e and localize('k_coop_slots_' .. e.id .. '_desc') or ''
		t.pays = e and e.pays or ''
		t.chance = e and e.chance or ''
		if t.area then
			clear_area(t.area)
			for _, key in ipairs(e and e.keys or {}) do
				display_card(nil, G.P_CENTERS[key], t.area, PAY_CARD)
			end
			t.area:align_cards()
			for _, c in ipairs(t.area.cards) do
				c.VT.x, c.VT.y = c.T.x, c.T.y -- straight into place
			end
		end
	end
	CS.pt_pos.text = first .. '-' .. math.min(first + ROWS_PER_PAGE - 1, #list) .. ' / ' .. #list
end

local function paytable_open()
	return CS.paytable_box and G.OVERLAY_MENU == CS.paytable_box
end

local function scroll_button(action, label, gate)
	return UIBox_button({ button = action, func = gate, label = { label }, minw = 1.4, minh = 0.5, scale = 0.45, colour = G.C.BLUE, col = true })
end

function CS.open_paytable()
	local rows = {
		R({ T(localize('k_coop_casino_paytable'), 0.6, G.C.GOLD) }, 0.02),
		R({ T(localize('k_coop_casino_paytable_hint'), 0.3, G.C.UI.TEXT_LIGHT) }, 0.02),
		R({ scroll_button('coop_paytable_up', '^', 'coop_paytable_can_up') }, 0.02),
	}
	for i = 1, ROWS_PER_PAGE do
		rows[#rows + 1] = paytable_row(i)
	end
	rows[#rows + 1] = R({
		scroll_button('coop_paytable_down', 'v', 'coop_paytable_can_down'),
		{ n = G.UIT.C, config = { align = 'cm', minw = 1.6 }, nodes = { ref(CS.pt_pos, 'text', 0.32, G.C.UI.TEXT_LIGHT) } },
	}, 0.02)
	fill_paytable(1) -- texts first: the window sizes itself from them
	G.FUNCS.overlay_menu({ definition = create_UIBox_generic_options({ contents = rows }) })
	CS.paytable_box = G.OVERLAY_MENU
	-- the areas have their place now: put the jokers in
	G.E_MANAGER:add_event(Event({
		func = function()
			if paytable_open() then
				fill_paytable(CS.paytable_first or 1)
			end
			return true
		end,
	}))
end

function CS.scroll_paytable(step)
	if not paytable_open() then
		return
	end
	local before = CS.paytable_first or 1
	local target = math.max(1, math.min(before + step, max_first()))
	if target ~= before then
		play_sound('paper1', 1.1, 0.4)
		fill_paytable(target)
	end
end

G.FUNCS.coop_slots_paytable = function()
	if CS.slots_busy then
		return
	end
	CS.open_paytable()
end

G.FUNCS.coop_paytable_up = function()
	CS.scroll_paytable(-1)
end

G.FUNCS.coop_paytable_down = function()
	CS.scroll_paytable(1)
end

make_gate('coop_paytable_can_up', 'coop_paytable_up', G.C.BLUE, function()
	return (CS.paytable_first or 1) > 1
end)
make_gate('coop_paytable_can_down', 'coop_paytable_down', G.C.BLUE, function()
	return (CS.paytable_first or 1) < max_first()
end)

-- mouse wheel scrolls the table, one row per notch
local wheel_ref = love.wheelmoved
function love.wheelmoved(x, y)
	if paytable_open() and y ~= 0 then
		CS.scroll_paytable(y > 0 and -1 or 1)
	end
	if wheel_ref then
		return wheel_ref(x, y)
	end
end

local function slots_payout(r, bet)
	local keys = { r[1].key, r[2].key, r[3].key }
	local rule = match(keys)
	if not rule then
		return 0
	end
	return math.floor(bet * rule.pays), rule
end

G.FUNCS.coop_slots_spin = function()
	if CS.slots_busy or dollars() < CS.bet then
		return
	end
	CS.slots_busy = true
	local bet = CS.bet
	ease_dollars(-bet)
	local result = { random_symbol(), random_symbol(), random_symbol() }
	local reels = CS.reels -- the page may change before the reels stop
	CS.text.slots = ''
	local steps = 16
	for i = 1, steps do
		G.E_MANAGER:add_event(Event({
			trigger = 'after',
			delay = 0.07,
			func = function()
				if not reels or CS.reels ~= reels then
					return true -- left the slots: no animation, the payout still comes
				end
				for k = 1, 3 do
					local stop = steps - 9 + k * 3 -- reels stop left to right
					if i < stop then
						set_reel(k, SYMBOLS[math.random(#SYMBOLS)])
					elseif i == stop then
						set_reel(k, result[k])
						local c = reels[k] and reels[k].cards[1]
						if c then
							c:juice_up(0.4, 0.4)
						end
						play_sound('generic1', 0.9 + k * 0.1)
					end
				end
				play_sound('card1', 0.8 + i * 0.03, 0.3)
				return true
			end,
		}))
	end
	G.E_MANAGER:add_event(Event({
		trigger = 'after',
		delay = 0.3,
		func = function()
			local win, rule = slots_payout(result, bet)
			if CS.reels ~= reels then
				pay(win, localize('k_coop_casino_slots'))
				CS.slots_busy = false
				return true
			end
			if win > 0 then
				CS.text.slots = rule_name(rule.id) .. '!  ' .. localize({ type = 'variable', key = 'coop_casino_win', vars = { win } })
				pay(win, localize('k_coop_casino_slots'))
			else
				CS.text.slots = rule and (rule_name(rule.id) .. ': ' .. localize('k_coop_casino_bet_too_small')) or localize('k_coop_casino_miss')
				play_sound('cancel', 0.8, 0.6)
			end
			CS.slots_busy = false
			return true
		end,
	}))
end

-- Blackjack -----------------------------------------------------------------------

local SUITS = { 'H', 'D', 'C', 'S' }
local RANKS = { '2', '3', '4', '5', '6', '7', '8', '9', 'T', 'J', 'Q', 'K', 'A' }
local DECKS = 6

local function new_shoe()
	local shoe = {}
	for _ = 1, DECKS do
		for _, s in ipairs(SUITS) do
			for _, r in ipairs(RANKS) do
				shoe[#shoe + 1] = s .. '_' .. r
			end
		end
	end
	pseudoshuffle(shoe, pseudoseed('coop_shoe'))
	CS.shoe = shoe
	CS.text.bj = localize('k_coop_casino_shuffle')
end

local function rank_of(key)
	return key and key:sub(3) or ''
end

local function card_value(key)
	local r = rank_of(key)
	if r == 'A' then
		return 11
	elseif r == 'T' or r == 'J' or r == 'Q' or r == 'K' then
		return 10
	end
	return tonumber(r) or 0
end

-- total, soft (an ace still counted as 11)
local function total(keys)
	local sum, aces = 0, 0
	for _, k in ipairs(keys) do
		sum = sum + card_value(k)
		if rank_of(k) == 'A' then
			aces = aces + 1
		end
	end
	while sum > 21 and aces > 0 do
		sum, aces = sum - 10, aces - 1
	end
	return sum, aces > 0
end

local function natural(keys)
	return #keys == 2 and total(keys) == 21
end

local function bj_text()
	local bj = CS.bj
	if not bj then
		CS.text.dealer, CS.text.hand1, CS.text.hand2 = '', '', ''
		return
	end
	if #bj.dealer == 0 then
		CS.text.dealer = localize('k_coop_casino_dealer') -- still dealing
	elseif bj.hole_hidden then
		CS.text.dealer = localize('k_coop_casino_dealer') .. ': ' .. card_value(bj.dealer[1])
	else
		CS.text.dealer = localize('k_coop_casino_dealer') .. ': ' .. total(bj.dealer)
	end
	for i = 1, 2 do
		local h = bj.hands[i]
		if h then
			local mark = (#bj.hands > 1 and bj.current == i and not bj.over) and '> ' or ''
			CS.text['hand' .. i] = mark .. localize('k_coop_casino_you') .. ': ' .. total(h.cards) .. '   $' .. h.bet .. (h.result and ('   ' .. h.result) or '')
		else
			CS.text['hand' .. i] = ''
		end
	end
end

-- deal one card (animated through the event queue)
local function deal_to(area, keys, face_down, after)
	G.E_MANAGER:add_event(Event({
		trigger = 'after',
		delay = 0.35,
		func = function()
			if CS.page ~= 'blackjack' or not area or not CS.bj or (area ~= CS.dealer_area and area ~= (CS.hand_areas or {})[1] and area ~= (CS.hand_areas or {})[2]) then
				return true -- that table is gone
			end
			if #CS.shoe == 0 then
				new_shoe()
			end
			local key = table.remove(CS.shoe)
			keys[#keys + 1] = key
			local card = display_card(G.P_CARDS[key], G.P_CENTERS.c_base, area, CARD_SCALE)
			if face_down then
				card.facing, card.sprite_facing = 'back', 'back'
				CS.bj.hole_card = card
			end
			play_sound('card1', 0.9 + math.random() * 0.2)
			bj_text()
			if after then
				after(key)
			end
			return true
		end,
	}))
end

local function blackjack_page()
	CS.page = 'blackjack'
	local w = G.CARD_W * CARD_SCALE * 5.5
	local h = G.CARD_H * CARD_SCALE * 1.05
	CS.dealer_area = CardArea(0, 0, w, h, { card_limit = 6, type = 'title', card_w = G.CARD_W * CARD_SCALE })
	-- one centred hand; the second hand's area is a sliver until a split
	-- widens it (CS.split_layout), and the cards glide apart
	CS.hand_w = w * 1.1
	CS.split_shown = false
	CS.hand_areas = {
		CardArea(0, 0, CS.hand_w, h, { card_limit = 4, type = 'title', card_w = G.CARD_W * CARD_SCALE }),
		CardArea(0, 0, 0.05, h, { card_limit = 4, type = 'title', card_w = G.CARD_W * CARD_SCALE }),
	}
	if not CS.shoe or #CS.shoe < 52 then
		new_shoe()
	else
		CS.text.bj = localize('k_coop_casino_bj_hint')
	end
	CS.bj = nil
	bj_text()
	show(append(header(localize('k_coop_casino_blackjack'), back_button()), {
		R({ RT('dealer', 0.5, G.C.UI.TEXT_LIGHT) }, 0.03),
		R({ O(CS.dealer_area) }, 0.05, { colour = { 0, 0, 0, 0.25 }, r = 0.1 }),
		R({
			{ n = G.UIT.C, config = { align = 'cm', padding = 0.05 }, nodes = { R({ RT('hand1', 0.45, G.C.CHIPS) }, 0.02), R({ O(CS.hand_areas[1]) }) } },
			{ n = G.UIT.C, config = { align = 'cm', padding = 0.05 }, nodes = { R({ RT('hand2', 0.45, G.C.CHIPS) }, 0.02), R({ O(CS.hand_areas[2]) }) } },
		}, 0.05, { colour = { 0, 0, 0, 0.25 }, r = 0.1 }),
		R({ RT('bj', 0.55, G.C.GOLD) }, 0.05),
		R({
			button('coop_bj_deal', localize('k_coop_casino_deal'), G.C.BLUE, 2.2, 'coop_bj_can_deal', 0.5),
			button('coop_bj_hit', localize('k_coop_casino_hit'), G.C.GREEN, 1.8, 'coop_bj_can_hit', 0.5),
			button('coop_bj_stand', localize('k_coop_casino_stand'), G.C.RED, 1.8, 'coop_bj_can_hit', 0.5),
			button('coop_bj_double', localize('k_coop_casino_double'), G.C.ORANGE, 2, 'coop_bj_can_double', 0.5),
			button('coop_bj_split', localize('k_coop_casino_split'), G.C.PURPLE, 1.8, 'coop_bj_can_split', 0.5),
		}, 0.06),
		R({
			button('coop_bj_insure', localize('k_coop_casino_insurance'), G.C.MONEY, 2.6, 'coop_bj_can_insure', 0.42),
			button('coop_bj_no_insure', localize('k_coop_casino_no_insurance'), G.C.GREY, 2.6, 'coop_bj_can_insure', 0.42),
		}, 0.04),
		bet_row(),
		R({ T(localize('k_coop_casino_bj_rules'), 0.32, G.C.UI.TEXT_LIGHT) }, 0.03),
	}))
end

-- Widen / narrow the two hand areas over a few frames; the box is laid out
-- again each step and the cards follow their areas smoothly.
local function split_layout(split)
	if CS.split_shown == split or not CS.hand_areas then
		return
	end
	CS.split_shown = split
	local areas, full = CS.hand_areas, CS.hand_w
	local from = areas[2].T.w
	local to = split and full * 0.5 or 0.05
	local steps = 8
	for i = 1, steps do
		G.E_MANAGER:add_event(Event({
			trigger = 'after',
			delay = 0.03, -- in sequence: the cards dealt next wait for it
			func = function()
				if CS.hand_areas ~= areas or not CS.box then
					return true
				end
				local w2 = from + (to - from) * i / steps
				areas[2].T.w = w2
				areas[1].T.w = full - w2
				CS.box:recalculate()
				return true
			end,
		}))
	end
end

local function reveal_hole()
	local bj = CS.bj
	if bj.hole_hidden then
		bj.hole_hidden = false
		if bj.hole_card then
			bj.hole_card:flip()
		end
		play_sound('card1')
	end
end

local function finish(text)
	local bj = CS.bj
	bj.over = true
	bj.busy = false
	CS.text.bj = text
	bj_text()
end

-- compare each hand with the dealer and pay
local function settle()
	local bj = CS.bj
	local dealer = total(bj.dealer)
	local paid = 0
	for _, h in ipairs(bj.hands) do
		local me = total(h.cards)
		if me > 21 then
			h.result = localize('k_coop_casino_bj_bust')
		elseif dealer > 21 or me > dealer then
			h.result = localize('k_coop_casino_bj_win')
			paid = paid + h.bet * 2
		elseif me == dealer then
			h.result = localize('k_coop_casino_bj_push')
			paid = paid + h.bet
		else
			h.result = localize('k_coop_casino_bj_lose')
		end
	end
	pay(paid, localize('k_coop_casino_blackjack'))
	if paid == 0 then
		play_sound('cancel', 0.8, 0.6)
	end
	finish(paid > 0 and localize({ type = 'variable', key = 'coop_casino_paid', vars = { paid } }) or localize('k_coop_casino_bj_lose'))
end

local function dealer_plays()
	local bj = CS.bj
	bj.busy = true
	reveal_hole()
	bj_text()
	-- all hands bust: the dealer doesn't draw
	local live = false
	for _, h in ipairs(bj.hands) do
		if total(h.cards) <= 21 then
			live = true
		end
	end
	local function step()
		local sum = total(bj.dealer)
		-- stands on 17, soft 17 included
		if live and sum < 17 then
			deal_to(CS.dealer_area, bj.dealer, false, step)
		else
			G.E_MANAGER:add_event(Event({ trigger = 'after', delay = 0.4, func = function()
				if CS.bj == bj then
					settle()
				end
				return true
			end }))
		end
	end
	step()
end

local function next_hand()
	local bj = CS.bj
	bj.current = bj.current + 1
	local h = bj.hands[bj.current]
	if not h then
		return dealer_plays()
	end
	-- a split hand gets its second card now
	deal_to(CS.hand_areas[bj.current], h.cards, false, function()
		if h.split_aces or total(h.cards) == 21 then
			next_hand() -- split aces take one card; 21 stands
		else
			bj.busy = false
			bj_text()
		end
	end)
end

local function hand_done()
	CS.bj.busy = true
	next_hand()
end

-- after the initial deal: insurance, the dealer's peek, naturals
local function after_peek()
	local bj = CS.bj
	local dealer_bj = natural(bj.dealer)
	local h = bj.hands[1]
	local paid = 0
	if bj.insured then
		if dealer_bj then
			paid = paid + bj.insured * 3 -- 2:1 plus the insurance back
		end
	end
	if dealer_bj then
		reveal_hole()
		if natural(h.cards) then
			h.result = localize('k_coop_casino_bj_push')
			paid = paid + h.bet
		else
			h.result = localize('k_coop_casino_bj_lose')
		end
		pay(paid, localize('k_coop_casino_blackjack'))
		return finish(localize('k_coop_casino_dealer_bj'))
	end
	if natural(h.cards) then
		reveal_hole()
		h.result = localize('k_coop_casino_bj_natural')
		paid = paid + h.bet + math.floor(h.bet * 1.5) -- 3:2
		pay(paid, localize('k_coop_casino_blackjack'))
		return finish(localize('k_coop_casino_bj_natural'))
	end
	if bj.insured then
		CS.text.bj = localize('k_coop_casino_insurance_lost')
	else
		CS.text.bj = ''
	end
	bj.busy = false
	bj.phase = 'play'
	bj_text()
end

G.FUNCS.coop_bj_deal = function()
	if dollars() < CS.bet or (CS.bj and not CS.bj.over) then
		return
	end
	clear_area(CS.dealer_area)
	clear_area(CS.hand_areas[1])
	clear_area(CS.hand_areas[2])
	split_layout(false)
	if #CS.shoe < DECKS * 52 * 0.25 then
		new_shoe() -- the cut card came up
	else
		CS.text.bj = ''
	end
	ease_dollars(-CS.bet)
	local bj = { dealer = {}, hands = { { cards = {}, bet = CS.bet } }, current = 1, busy = true, hole_hidden = true, phase = 'deal' }
	CS.bj = bj
	local hand = bj.hands[1]
	deal_to(CS.hand_areas[1], hand.cards)
	deal_to(CS.dealer_area, bj.dealer)
	deal_to(CS.hand_areas[1], hand.cards)
	deal_to(CS.dealer_area, bj.dealer, true, function()
		if CS.bj ~= bj then
			return
		end
		local up = bj.dealer[1]
		if rank_of(up) == 'A' and not natural(hand.cards) then
			bj.phase = 'insurance' -- offered before the dealer peeks
			bj.busy = false
			CS.text.bj = localize('k_coop_casino_insurance_offer')
		else
			after_peek()
		end
	end)
end

G.FUNCS.coop_bj_insure = function()
	local bj = CS.bj
	if not bj or bj.phase ~= 'insurance' then
		return
	end
	local cost = math.floor(bj.hands[1].bet / 2)
	if cost > 0 and dollars() >= cost then
		ease_dollars(-cost)
		bj.insured = cost
	end
	after_peek()
end

G.FUNCS.coop_bj_no_insure = function()
	local bj = CS.bj
	if bj and bj.phase == 'insurance' then
		after_peek()
	end
end

local function current_hand()
	local bj = CS.bj
	return bj and bj.hands[bj.current]
end

G.FUNCS.coop_bj_hit = function()
	local bj, h = CS.bj, current_hand()
	if not h or bj.busy or bj.phase ~= 'play' then
		return
	end
	bj.busy = true
	deal_to(CS.hand_areas[bj.current], h.cards, false, function()
		local sum = total(h.cards)
		if sum > 21 then
			h.result = localize('k_coop_casino_bj_bust')
			play_sound('cancel', 0.8, 0.5)
			hand_done()
		elseif sum == 21 then
			hand_done()
		else
			bj.busy = false
		end
	end)
end

G.FUNCS.coop_bj_stand = function()
	local bj = CS.bj
	if not current_hand() or bj.busy or bj.phase ~= 'play' then
		return
	end
	hand_done()
end

G.FUNCS.coop_bj_double = function()
	local bj, h = CS.bj, current_hand()
	if not h or bj.busy or bj.phase ~= 'play' or #h.cards ~= 2 or dollars() < h.bet then
		return
	end
	ease_dollars(-h.bet)
	h.bet = h.bet * 2
	bj.busy = true
	deal_to(CS.hand_areas[bj.current], h.cards, false, function()
		if total(h.cards) > 21 then
			h.result = localize('k_coop_casino_bj_bust')
		end
		hand_done() -- one card only
	end)
end

local function can_split()
	local bj, h = CS.bj, current_hand()
	return h and not bj.busy and bj.phase == 'play' and #bj.hands == 1 and #h.cards == 2
		and card_value(h.cards[1]) == card_value(h.cards[2]) and dollars() >= h.bet
end

G.FUNCS.coop_bj_split = function()
	if not can_split() then
		return
	end
	local bj = CS.bj
	local h = bj.hands[1]
	ease_dollars(-h.bet)
	local aces = rank_of(h.cards[1]) == 'A'
	local second = table.remove(h.cards)
	split_layout(true) -- the two hands slide apart
	local moved = CS.hand_areas[1].cards[2]
	if moved then
		CS.hand_areas[1]:remove_card(moved)
		CS.hand_areas[2]:emplace(moved)
	end
	h.split_aces = aces
	bj.hands[2] = { cards = { second }, bet = h.bet, split_aces = aces }
	bj.busy = true
	play_sound('cardSlide1')
	-- the first hand gets its second card; the second hand waits its turn
	deal_to(CS.hand_areas[1], h.cards, false, function()
		if aces or total(h.cards) == 21 then
			hand_done()
		else
			bj.busy = false
			bj_text()
		end
	end)
end

-- Button gates -------------------------------------------------------------------

local function bj_idle()
	return not CS.bj or CS.bj.over
end

make_gate('coop_casino_can_bet', nil, G.C.GREY, function()
	return not CS.slots_busy and bj_idle()
end)
-- make_gate with a nil action would clear the button: bet buttons keep their own
for _, b in ipairs({ 'm10', 'm1', 'p1', 'p10', 'max' }) do
	local action = 'coop_casino_bet_' .. b
	G.FUNCS['coop_casino_can_bet_' .. b] = nil
	G.FUNCS[action] = function()
		if CS.slots_busy or not bj_idle() then
			return
		end
		local d = math.max(math.floor(dollars()), 1)
		local bet = CS.bet
		if b == 'm10' then
			bet = bet - 10
		elseif b == 'm1' then
			bet = bet - 1
		elseif b == 'p1' then
			bet = bet + 1
		elseif b == 'p10' then
			bet = bet + 10
		else
			bet = d
		end
		CS.bet = math.max(1, math.min(bet, d))
		play_sound('chips1', 1, 0.5)
	end
end
G.FUNCS.coop_casino_can_bet = function(e)
	local ok = not CS.slots_busy and bj_idle()
	e.config.colour = ok and G.C.GREY or G.C.UI.BACKGROUND_INACTIVE
	if ok then
		e.config.button = e.config.coop_action or e.config.button
		e.config.coop_action = e.config.button
	else
		e.config.coop_action = e.config.coop_action or e.config.button
		e.config.button = nil
	end
end

make_gate('coop_slots_can_spin', 'coop_slots_spin', G.C.RED, function()
	return not CS.slots_busy and dollars() >= CS.bet
end)
make_gate('coop_casino_can_back', 'coop_casino_hub', G.C.ORANGE, function()
	return not CS.slots_busy and bj_idle()
end)
make_gate('coop_bj_can_deal', 'coop_bj_deal', G.C.BLUE, function()
	return bj_idle() and dollars() >= CS.bet
end)
G.FUNCS.coop_bj_can_hit = function(e)
	local bj = CS.bj
	local ok = bj and not bj.busy and not bj.over and bj.phase == 'play'
	e.config.coop_action = e.config.coop_action or e.config.button
	e.config.button = ok and e.config.coop_action or nil
	e.config.colour = ok and (e.config.coop_action == 'coop_bj_hit' and G.C.GREEN or G.C.RED) or G.C.UI.BACKGROUND_INACTIVE
end
make_gate('coop_bj_can_double', 'coop_bj_double', G.C.ORANGE, function()
	local bj, h = CS.bj, current_hand()
	return h and not bj.busy and not bj.over and bj.phase == 'play' and #h.cards == 2 and dollars() >= h.bet
end)
make_gate('coop_bj_can_split', 'coop_bj_split', G.C.PURPLE, function()
	return can_split() and true or false
end)
G.FUNCS.coop_bj_can_insure = function(e)
	local bj = CS.bj
	local ok = bj and bj.phase == 'insurance' and not bj.over
	e.config.coop_action = e.config.coop_action or e.config.button
	e.config.button = ok and e.config.coop_action or nil
	e.config.colour = ok and (e.config.coop_action == 'coop_bj_insure' and G.C.MONEY or G.C.GREY) or G.C.UI.BACKGROUND_INACTIVE
end

-- Navigation ---------------------------------------------------------------------

G.FUNCS.coop_casino_open = function()
	CS.enter()
end

G.FUNCS.coop_casino_leave = function()
	CS.leave()
end

G.FUNCS.coop_casino_hub = function()
	if CS.slots_busy or not bj_idle() then
		return
	end
	CS.bj = nil
	hub()
	fill_hub()
end

G.FUNCS.coop_casino_slots = function()
	play_sound('button')
	slots_page()
end

G.FUNCS.coop_casino_blackjack = function()
	play_sound('button')
	blackjack_page()
end

-- Per frame ---------------------------------------------------------------------

function CS.update_info()
	CS.text.info = localize({ type = 'variable', key = 'coop_casino_info', vars = { dollars() } })
	CS.text.bet = '$' .. CS.bet
end

-- The "Casino" button lives in the shop itself, a third button under "Next
-- round" and "Reroll" (the two get a little shorter to make room).
local function find_parent(node, pred)
	for i, child in ipairs(node.nodes or {}) do
		if pred(child) then
			return node, i
		end
		local p, j = find_parent(child, pred)
		if p then
			return p, j
		end
	end
end

local function add_casino_button(t)
	local column, i = find_parent(t, function(n)
		return n.config and n.config.button == 'reroll_shop'
	end)
	if not column then
		return
	end
	for _, n in ipairs(column.nodes) do
		if n.config and n.config.minh then
			n.config.minh = math.min(n.config.minh, 1.25)
		end
	end
	table.insert(column.nodes, i + 1, { n = G.UIT.R, config = { align = 'cm', minw = 2.8, minh = 0.95, r = 0.15, colour = G.C.GOLD,
		button = 'coop_casino_open', hover = true, shadow = true }, nodes = {
		{ n = G.UIT.T, config = { text = localize('k_coop_casino'), scale = 0.5, colour = G.C.WHITE, shadow = true } },
	} })
end

local shop_def_ref = G.UIDEF.shop
function G.UIDEF.shop()
	local t = shop_def_ref()
	if COOP.is_active() then
		local ok, err = pcall(add_casino_button, t)
		if not ok then
			sendWarnMessage('casino button: ' .. tostring(err), COOP.id)
		end
	end
	return t
end

-- Game:update (co-op runs only)
function CS.update()
	if not CS.scene then
		return
	end
	if G.STATE ~= G.STATES.SHOP or not G.shop then
		-- the shop is gone (left, or the run ended): drop the scene with it
		CS.scene = false
		CS.slots_busy, CS.bj, CS.page = false, nil, nil
		remove_box()
		forget_areas()
		set_rows_visible(true)
		return
	end
	if CS.bet > math.max(math.floor(dollars()), 1) and not CS.slots_busy and bj_idle() then
		CS.bet = math.max(math.floor(dollars()), 1)
	end
	CS.update_info()
end
