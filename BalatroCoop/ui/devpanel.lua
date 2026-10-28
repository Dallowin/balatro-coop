-- Dev panel (F8, dev mode or the solo test): give yourself or the bot any
-- co-op card, put co-op enhancements / seals / editions on cards, fire the
-- partner's events at yourself, a few cheats. Nothing here exists in a normal
-- game with a friend.

COOP.DEVPANEL = COOP.DEVPANEL or {}
local DP = COOP.DEVPANEL

local KEY = 'f8'

local PAIRS = { 'j_coop_yin', 'j_coop_yang', 'j_coop_sun', 'j_coop_moon', 'j_coop_sword', 'j_coop_shield' }
local JOKERS = { 'j_coop_relay', 'j_coop_kindred', 'j_coop_pot', 'j_coop_assist' }
local TEAM = { 'j_coop_pass', 'j_coop_bridge', 'j_coop_echo', 'j_coop_double', 'j_coop_chain', 'j_coop_contrast',
	'j_coop_shared_hand', 'j_coop_support', 'j_coop_second_wind' }
local CONS = { 'c_coop_bond', 'c_coop_offering', 'c_coop_fortress', 'c_coop_twins', 'c_coop_forge', 'c_coop_swap' }
local ENH = { 'm_coop_bulwark', 'm_coop_mirror', 'm_coop_beacon', 'm_coop_twin', 'm_coop_torch' }
local SEALS = { 'coop_bond', 'coop_sacrifice' }
local EDITIONS = { 'e_coop_union', 'e_coop_ether' }
local PACKS = { 'p_coop_pack_normal', 'p_coop_pack_mega' }

function DP.allowed()
	return (COOP.DEV.on() or COOP.TEST) and COOP.is_active() and G.STAGE == G.STAGES.RUN
end

local function name_of(key)
	local c = G.P_CENTERS[key]
	if not c then
		return key
	end
	local set = c.set == 'Enhanced' and 'Enhanced' or c.set == 'Edition' and 'Edition' or c.set
	local ok, n = pcall(localize, { type = 'name_text', set = set, key = key })
	return ok and n and n ~= 'ERROR' and n or key
end

local function seal_name(key)
	local ok, n = pcall(localize, { type = 'name_text', set = 'Other', key = key:lower() .. '_seal' })
	return ok and n and n ~= 'ERROR' and n or key
end

-- Actions ------------------------------------------------------------------------

local function give(key)
	local c = G.P_CENTERS[key]
	if not c then
		return
	end
	if c.set == 'Booster' then
		if SMODS.add_booster_to_shop and G.shop_booster then
			SMODS.add_booster_to_shop(key)
		else
			COOP.popup('Только в лавке', G.C.RED)
		end
		return
	end
	if c.set == 'Enhanced' then
		SMODS.add_card({ set = 'Enhanced', enhancement = key, area = G.hand })
		return
	end
	SMODS.add_card({ key = key })
end

-- the bot's window does the same on its side
function DP.on_dev(p)
	if not (COOP.DEV.on() or COOP.TEST) then
		return
	end
	if p.a == 'give' then
		give(p.k)
		COOP.popup('Дев: ' .. name_of(p.k), G.C.PURPLE)
	end
end

local function give_partner(key)
	COOP.send('dev', { a = 'give', k = key })
	COOP.popup('Напарнику: ' .. name_of(key), G.C.PURPLE)
end

-- highlighted hand cards, else a fresh card in hand
local function targets()
	local t = {}
	for _, c in ipairs(G.hand and G.hand.highlighted or {}) do
		t[#t + 1] = c
	end
	return t
end

local function enhance(key)
	local t = targets()
	if #t == 0 then
		give(key)
		return
	end
	for _, c in ipairs(t) do
		c:set_ability(G.P_CENTERS[key], nil, true)
		c:juice_up(0.3, 0.3)
	end
end

local function seal(key)
	local t = targets()
	if #t == 0 then
		SMODS.add_card({ set = 'Base', area = G.hand, seal = key })
		return
	end
	for _, c in ipairs(t) do
		c:set_seal(key, nil, true)
	end
end

local function edition(key)
	local t = targets()
	for _, c in ipairs(G.jokers and G.jokers.highlighted or {}) do
		t[#t + 1] = c
	end
	if #t == 0 then
		SMODS.add_card({ set = 'Base', area = G.hand, edition = key })
		return
	end
	for _, c in ipairs(t) do
		c:set_edition(key, true)
	end
end

local EVENTS = {
	{ 'Связь: добор', function() COOP.CARDS.on_bond_draw(1) end },
	{ 'Жертва: +сброс', function() COOP.CARDS.on_sacrifice(1) end },
	{ 'Отражение: +50', function() COOP.CARDS.on_mirror_chips(50) end },
	{ 'Факел: +рука', function() COOP.CARDS.on_torch(1) end },
	{ 'Фраза колеса', function() COOP.SOCIAL.on_wheel(math.random(0, 7)) end },
}

-- every co-op effect one after another (ui/fx.lua)
local function showcase()
	local F = COOP.FX
	-- a stand-in copy of a card, so the showcase never changes the run
	local function stand_in(card)
		local c = copy_card(card)
		c.states.drag.can, c.states.click.can = false, false
		c.T.y = c.T.y - 0.4
		return c
	end
	local steps = {
		-- the turn comes over
		function() F.your_turn() end,
		-- a joker and a hand card send their ghosts to the partner
		function()
			local j = G.jokers and G.jokers.cards[1]
			if j then
				F.comet(j, F.partner_jokers, { G.C.BLUE, G.C.WHITE })
			end
		end,
		function()
			local c = G.hand and G.hand.cards[1]
			if c then
				F.comet(c, F.partner_hand, { G.C.BLUE, G.C.WHITE })
			end
		end,
		-- the partner's hand flies into our score: small, then big
		function() F.score_in((G.GAME.blind and G.GAME.blind.chips or 300) * 0.2) end,
		function() F.score_in((G.GAME.blind and G.GAME.blind.chips or 300) * 0.8) end,
		-- Torch burning out (on a stand-in)
		function()
			local c = G.hand and G.hand.cards[#G.hand.cards]
			if c then
				local s = stand_in(c)
				F.burn(s)
				s:start_dissolve()
			end
		end,
		-- Swap (on a stand-in): spectral dissolve, glitch, materialize
		function()
			local j = G.jokers and G.jokers.cards[#G.jokers.cards]
			if j then
				local s = stand_in(j)
				F.swap_out(s)
				s:start_dissolve()
			end
		end,
		function() F.team_win(1.2) end,
		function() F.team_win(3) end,
	}
	for i, fn in ipairs(steps) do
		G.E_MANAGER:add_event(Event({
			trigger = 'after', delay = (i == 1) and 0.3 or 1.8, blockable = false, timer = 'REAL',
			func = function()
				pcall(fn)
				return true
			end,
		}))
	end
end
DP.showcase = showcase

local CHEATS = {
	{ 'Показать эффекты', showcase },
	{ '+$25', function() ease_dollars(25) end },
	{ '+1 рука', function() ease_hands_played(1) end },
	{ '+1 сброс', function() ease_discard(1) end },
	{ 'Добрать 3', function() G.FUNCS.draw_from_deck_to_hand(3) end },
	{ 'Автопилот', function() COOP.BOT.toggle() end },
}

-- UI -----------------------------------------------------------------------------

local function text(s, scale, colour)
	return { n = G.UIT.T, config = { text = s, scale = scale or 0.32, colour = colour or G.C.WHITE, shadow = true } }
end

local fn_count = 0
local function btn(label, colour, fn, keep_open)
	fn_count = fn_count + 1
	local id = 'coop_dev_' .. fn_count
	G.FUNCS[id] = function()
		local ok, err = pcall(fn)
		if not ok then
			sendWarnMessage('dev panel: ' .. tostring(err), COOP.id)
		end
		play_sound('button', 1, 0.3)
		if not keep_open then
			G.FUNCS.exit_overlay_menu()
		end
	end
	return UIBox_button({ button = id, label = { label }, minw = 1.75, minh = 0.42, scale = 0.27, colour = colour, col = true })
end

local function section(title, items, per_row)
	local rows = { { n = G.UIT.R, config = { align = 'cl', padding = 0.03 }, nodes = { text(title, 0.34, G.C.GOLD) } } }
	local cur
	for i, it in ipairs(items) do
		if (i - 1) % (per_row or 6) == 0 then
			cur = { n = G.UIT.R, config = { align = 'cl', padding = 0.02 }, nodes = {} }
			rows[#rows + 1] = cur
		end
		cur.nodes[#cur.nodes + 1] = it
	end
	return { n = G.UIT.R, config = { align = 'cl', padding = 0.04 }, nodes = { { n = G.UIT.C, config = { align = 'cl' }, nodes = rows } } }
end

local function cards_section(title, keys, colour, partner)
	local items = {}
	for _, k in ipairs(keys) do
		items[#items + 1] = btn(name_of(k), colour, function()
			give(k)
		end)
		if partner then
			items[#items + 1] = btn('-> боту', G.C.PURPLE, function()
				give_partner(k)
			end)
		end
	end
	return section(title, items, partner and 6 or 6)
end

function DP.definition()
	local enh, seals, eds, events, cheats = {}, {}, {}, {}, {}
	for _, k in ipairs(ENH) do
		enh[#enh + 1] = btn(name_of(k), G.C.SECONDARY_SET.Enhanced, function()
			enhance(k)
		end)
	end
	for _, k in ipairs(SEALS) do
		seals[#seals + 1] = btn(seal_name(k), G.C.SECONDARY_SET.Spectral, function()
			seal(k)
		end)
	end
	for _, k in ipairs(EDITIONS) do
		eds[#eds + 1] = btn(name_of(k), G.C.DARK_EDITION, function()
			edition(k)
		end)
	end
	for _, e in ipairs(EVENTS) do
		events[#events + 1] = btn(e[1], G.C.BLUE, e[2])
	end
	for _, e in ipairs(CHEATS) do
		cheats[#cheats + 1] = btn(e[1], G.C.GREEN, e[2], true)
	end
	for _, k in ipairs(PACKS) do
		cheats[#cheats + 1] = btn(name_of(k), G.C.BOOSTER, function()
			give(k)
		end)
	end
	local partner = COOP.DEV.on()
	return create_UIBox_generic_options({
		back_func = 'exit_overlay_menu',
		minw = 12,
		contents = {
			{ n = G.UIT.R, config = { align = 'cm', padding = 0.05 }, nodes = { text('ДЕВ-ПАНЕЛЬ  (F8 — открыть, F7 — автопилот, F9 — эффекты)', 0.45, G.C.GOLD) } },
			{ n = G.UIT.R, config = { align = 'cm' }, nodes = { text('Улучшения/печати/издания ставятся на выбранные карты (или создают новую в руке)', 0.28, G.C.UI.TEXT_INACTIVE) } },
			cards_section('Парные джокеры', PAIRS, G.C.RED, partner),
			cards_section('Кооп-джокеры', JOKERS, G.C.RED),
			cards_section('Командные джокеры', TEAM, G.C.SECONDARY_SET.Planet),
			cards_section('Таро и спектральные', CONS, G.C.SECONDARY_SET.Tarot),
			section('Улучшения', enh),
			section('Печати и издания', (function()
				local t = {}
				for _, x in ipairs(seals) do t[#t + 1] = x end
				for _, x in ipairs(eds) do t[#t + 1] = x end
				return t
			end)()),
			section('События от напарника (на тебя)', events),
			section('Читы и паки (паки — в лавку)', cheats),
		},
	})
end

function DP.open()
	if not DP.allowed() or G.OVERLAY_MENU then
		return
	end
	G.FUNCS.overlay_menu({ definition = DP.definition() })
end

function DP.install()
	local key_press_ref = Controller.key_press_update
	function Controller:key_press_update(key, dt)
		if key == KEY and DP.allowed() then
			DP.open()
		end
		if key == 'f9' and DP.allowed() then
			DP.showcase() -- every co-op effect, one after another
		end
		return key_press_ref(self, key, dt)
	end
end
