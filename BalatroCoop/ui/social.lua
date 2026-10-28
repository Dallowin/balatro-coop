-- Talking without typing, and without filling the screen:
--
--   Chat wheel  hold Y: the wheel opens around the mouse; move onto (or
--               towards) a phrase, let go. The partner
--               sees it in a bubble over their view of you for a few seconds
--               (and in their own language: only the phrase number travels).
--   Pings       middle mouse button (or G) over a card: the same card lights
--               up on the partner's screen with "Look!". Again on the same
--               card within a few seconds: "Take it!", then "Don't".
--               In the shop a selected card also has an "Offer" button
--               next to "Buy": the same, as "how about this?".
--               Shop cards, team jokers, consumables, your jokers and hand
--               (the partner sees them in their partner view) and theirs.
--   Activity    "Partner: in the casino" in the team panel, only while you
--               two are in different places (shop, casino, pack, blind...).
--
-- Bubbles go away by themselves; nothing stays on screen.

COOP.SOCIAL = COOP.SOCIAL or {}
local SO = COOP.SOCIAL

local WHEEL_KEY = 'y'
local PING_KEY = 'g'
local BUBBLE_FOR = 3
local PING_AGAIN = 4 -- seconds: pinging the same card again raises the level
local LIMIT_N, LIMIT_T = 6, 5 -- at most this many wheel phrases / pings per this many seconds

-- sector (0 = right, clockwise, as the screen's y goes down) -> phrase
-- layout of the wheel on screen, 3x3 with the middle empty
local GRID = { { 5, 6, 7 }, { 4, nil, 0 }, { 3, 2, 1 } }
local PING_COLOURS = { 'BLUE', 'GREEN', 'RED', 'ORANGE' }
local OFFER_FOR = 6

SO.bubbles = {}
SO.sent = {}
SO.partner_activity = nil
SO.my_activity = nil

local function now()
	return G.TIMERS and G.TIMERS.REAL or 0
end

local function in_run()
	return COOP.is_active() and G.STAGE == G.STAGES.RUN
end

-- flood guard for both the wheel and pings
local function allowed()
	local t, kept = now(), {}
	for _, at in ipairs(SO.sent) do
		if t - at < LIMIT_T then
			kept[#kept + 1] = at
		end
	end
	SO.sent = kept
	if #kept >= LIMIT_N then
		return false
	end
	kept[#kept + 1] = t
	return true
end

-- Bubbles ------------------------------------------------------------------------

local function bubble(major, text, colour, align, offset, scale)
	if not major then
		return
	end
	local box = UIBox({
		definition = { n = G.UIT.ROOT, config = { align = 'cm', colour = colour, r = 0.1, padding = 0.07, emboss = 0.05 }, nodes = {
			{ n = G.UIT.O, config = { object = DynaText({ string = { text }, colours = { G.C.WHITE }, scale = scale or 0.4,
				shadow = true, pop_in = 0, pop_in_rate = 8, silent = true }) } },
		} },
		config = { align = align or 'tm', offset = offset or { x = 0, y = -0.1 }, major = major, bond = 'Weak', instance_type = 'POPUP' },
	})
	local b = { box = box, until_t = now() + BUBBLE_FOR }
	SO.bubbles[#SO.bubbles + 1] = b
	return b
end

local function clear_bubbles()
	for _, b in ipairs(SO.bubbles) do
		pcall(function()
			b.box:remove()
		end)
	end
	SO.bubbles = {}
end

-- where the partner is shown on our screen (their hand, else their jokers)
local function partner_anchor()
	local PV = COOP.PV
	return (PV.hand_area and PV.hand_area.states and PV.hand_area.states.visible ~= false and PV.hand_area)
		or PV.joker_area or G.jokers
end

-- Chat wheel ---------------------------------------------------------------------

local function phrase(sector)
	return localize('coop_w_' .. sector)
end

local function wheel_definition()
	SO.cell_colours = {}
	local rows = {}
	for _, line in ipairs(GRID) do
		local cells = {}
		for c = 1, 3 do
			local s = line[c]
			if s then
				local col = copy_table(G.C.BLACK)
				SO.cell_colours[s] = col
				cells[#cells + 1] = { n = G.UIT.C, config = { id = 'coop_w_' .. s, align = 'cm', minw = 2.4, minh = 0.7, r = 0.1, padding = 0.06, colour = col, emboss = 0.05 }, nodes = {
					{ n = G.UIT.T, config = { text = phrase(s), scale = 0.38, colour = G.C.WHITE, shadow = true } },
				} }
			else
				cells[#cells + 1] = { n = G.UIT.C, config = { id = 'coop_w_mid', align = 'cm', minw = 2.4, minh = 0.7 }, nodes = {
					{ n = G.UIT.T, config = { text = WHEEL_KEY:upper(), scale = 0.5, colour = G.C.UI.TEXT_INACTIVE, shadow = true } },
				} }
			end
		end
		rows[#rows + 1] = { n = G.UIT.R, config = { align = 'cm', padding = 0.05 }, nodes = cells }
	end
	return { n = G.UIT.ROOT, config = { align = 'cm', colour = { 0, 0, 0, 0.55 }, r = 0.2, padding = 0.12 }, nodes = rows }
end

-- Like Dota: the wheel opens centred on the mouse, so every phrase is one
-- short move away.
function SO.wheel_open()
	if SO.wheel or not in_run() or G.OVERLAY_MENU then
		return
	end
	SO.wheel_pick = nil
	local box = UIBox({ definition = wheel_definition(),
		config = { align = 'tli', offset = { x = 0, y = 0 }, major = G.ROOM_ATTACH, bond = 'Weak', instance_type = 'POPUP' } })
	-- the cursor is in screen tiles, the UI in room tiles
	local cx, cy = G.CURSOR.T.x - G.ROOM.T.x, G.CURSOR.T.y - G.ROOM.T.y
	local w, h = box.T.w, box.T.h
	box.alignment.offset.x = math.max(0, math.min(G.ROOM.T.w - w, cx - w / 2))
	box.alignment.offset.y = math.max(0, math.min(G.ROOM.T.h - h, cy - h / 2))
	box:align_to_major()
	box:hard_set_VT()
	SO.wheel = box
	play_sound('paper1', 1.2, 0.4)
end

-- the phrase under the mouse; outside the wheel, the one in the mouse's
-- direction from its middle; over the middle, none
local function wheel_pick()
	local box = SO.wheel
	if box:get_UIE_by_ID('coop_w_mid'):collides_with_point(G.CURSOR.T) then
		return nil
	end
	for s = 0, 7 do
		local cell = box:get_UIE_by_ID('coop_w_' .. s)
		if cell and cell:collides_with_point(G.CURSOR.T) then
			return s
		end
	end
	local mx = box.T.x + box.T.w / 2 + G.ROOM.T.x
	local my = box.T.y + box.T.h / 2 + G.ROOM.T.y
	local dx, dy = G.CURSOR.T.x - mx, G.CURSOR.T.y - my
	if dx * dx + dy * dy < 0.25 then
		return nil
	end
	return math.floor((math.atan2(dy, dx) + math.pi / 8) / (math.pi / 4)) % 8
end

local function wheel_track()
	if not SO.wheel then
		return
	end
	local ok, pick = pcall(wheel_pick)
	if not ok then
		pick = nil
	end
	if pick ~= SO.wheel_pick then
		SO.wheel_pick = pick
		for s, col in pairs(SO.cell_colours or {}) do
			local target = s == pick and G.C.BLUE or G.C.BLACK
			for i = 1, 4 do
				col[i] = target[i]
			end
		end
		if pick then
			play_sound('cardSlide2', 1.4, 0.3)
		end
	end
end

local function show_phrase(major, who, sector, colour)
	local text = phrase(sector)
	bubble(major, who .. ': ' .. text, colour)
	COOP.CHAT.add(who, text, true)
end

function SO.wheel_close()
	if not SO.wheel then
		return
	end
	wheel_track()
	SO.wheel:remove()
	SO.wheel = nil
	local pick = SO.wheel_pick
	if not pick or not in_run() or not allowed() then
		return
	end
	COOP.send('wheel', { i = pick })
	show_phrase(G.hand, localize('k_coop_you'), pick, G.C.UI.BACKGROUND_INACTIVE)
	play_sound('paper1', 1.1, 0.5)
end

function SO.on_wheel(i)
	if not in_run() or not localize('coop_w_' .. i) then
		return
	end
	show_phrase(partner_anchor(), localize('k_coop_partner'), math.floor(i) % 8, G.C.BLUE)
	play_sound('highlight1', 1.3, 0.6)
end

-- Pings --------------------------------------------------------------------------

local SHOP_AREAS = { 'shop_jokers', 'shop_vouchers', 'shop_booster' }

local function index_in(area, card)
	for i, c in ipairs(area and area.cards or {}) do
		if c == card then
			return i
		end
	end
end

-- what the partner calls this card: kind + id
local function target_of(card)
	local a = card and card.area
	if not a then
		return nil
	end
	for _, name in ipairs(SHOP_AREAS) do
		if a == G[name] and card.coop_sid then
			return 'shop', tostring(card.coop_sid)
		end
	end
	if a == G.consumeables and card.ability and card.ability.coop_cid then
		return 'cons', tostring(card.ability.coop_cid)
	end
	local kinds = {
		{ G.jokers, 'myj' }, { G.hand, 'myh' }, { G.coop_team, 'team' },
		{ COOP.PV.joker_area, 'pj' }, { COOP.PV.hand_area, 'ph' },
	}
	for _, k in ipairs(kinds) do
		if k[1] and a == k[1] then
			local i = index_in(a, card)
			return i and k[2], i and tostring(i)
		end
	end
end

-- the card the partner meant, on our screen
local function card_of(kind, id)
	if kind == 'shop' then
		for _, name in ipairs(SHOP_AREAS) do
			for _, c in ipairs(G[name] and G[name].cards or {}) do
				if tostring(c.coop_sid) == id then
					return c
				end
			end
		end
	elseif kind == 'cons' then
		for _, c in ipairs(G.consumeables and G.consumeables.cards or {}) do
			if c.ability and tostring(c.ability.coop_cid) == id then
				return c
			end
		end
	else
		-- their jokers / hand are our partner view, ours are theirs
		local areas = { myj = COOP.PV.joker_area, myh = COOP.PV.hand_area, team = G.coop_team, pj = G.jokers, ph = G.hand }
		local area = areas[kind]
		return area and area.cards and area.cards[tonumber(id) or 0]
	end
end

local function ping_text(who, level)
	return who .. ': ' .. localize('coop_ping_' .. level)
end

-- level: 1 look, 2 take it, 3 don't (cycled by pinging again), 4 the shop's "Offer"
function SO.ping_card(h, level)
	if not in_run() or not (h and h.is and h:is(Card)) then
		return
	end
	local kind, id = target_of(h)
	if not kind or not allowed() then
		return
	end
	local last = SO.last_ping
	if not level then
		level = 1
		if last and last.kind == kind and last.id == id and last.level <= 3 and now() - last.at < PING_AGAIN then
			level = last.level % 3 + 1
		end
	end
	SO.last_ping = { kind = kind, id = id, level = level, at = now() }
	COOP.send('ping', { k = kind, id = id, lvl = level })
	h:juice_up(0.2, 0.2)
	bubble(h, ping_text(localize('k_coop_you'), level), G.C.UI.BACKGROUND_INACTIVE, 'tm', { x = 0, y = -0.05 }, 0.32)
	play_sound('card1', 1.3, 0.5)
end

function SO.ping_hovered()
	local h = G.CONTROLLER and G.CONTROLLER.hovering and G.CONTROLLER.hovering.target
	SO.ping_card(h)
end

function SO.on_ping(kind, id, level)
	if not in_run() then
		return
	end
	level = math.max(1, math.min(4, math.floor(level or 1)))
	local card = card_of(kind, id)
	if not card then
		return
	end
	card:juice_up(0.4, 0.4)
	local b = bubble(card, ping_text(localize('k_coop_partner'), level), G.C[PING_COLOURS[level]], 'tm', { x = 0, y = -0.05 }, 0.36)
	if b and level == 4 then
		b.until_t = now() + OFFER_FOR -- an offer stays a bit longer
	end
	play_sound(level == 4 and 'timpani' or 'highlight2', 1.2, 0.6)
end

-- Activity -----------------------------------------------------------------------

local PACK_STATES = { 'TAROT_PACK', 'PLANET_PACK', 'SPECTRAL_PACK', 'STANDARD_PACK', 'BUFFOON_PACK', 'SMODS_BOOSTER_OPENED' }

local function activity()
	local S = G.STATES
	if COOP.CASINO and COOP.CASINO.scene then
		return 'casino'
	end
	for _, name in ipairs(PACK_STATES) do
		if S[name] and G.STATE == S[name] then
			return 'pack'
		end
	end
	if G.STATE == S.SHOP then
		return 'shop'
	elseif G.STATE == S.BLIND_SELECT then
		return 'blind_select'
	elseif G.STATE == S.ROUND_EVAL then
		return 'cashout'
	elseif G.STATE == S.SELECTING_HAND or G.STATE == S.HAND_PLAYED or G.STATE == S.DRAW_TO_HAND then
		return 'blind'
	end
	return nil -- in between: keep the last one
end

function SO.on_activity(s)
	SO.partner_activity = s
end

-- the team panel's line: only while we're in different places
function SO.activity_line()
	local theirs = SO.partner_activity
	if not theirs or theirs == SO.my_activity then
		return ''
	end
	local text = localize('coop_act_' .. theirs)
	if not text or text == 'ERROR' then
		return ''
	end
	return localize('k_coop_partner') .. ': ' .. text
end

-- Game:update -----------------------------------------------------------------------

function SO.update()
	wheel_track()
	local t = now()
	local kept = {}
	for _, b in ipairs(SO.bubbles) do
		if t >= b.until_t then
			pcall(function()
				b.box:remove()
			end)
		else
			kept[#kept + 1] = b
		end
	end
	SO.bubbles = kept
	local a = activity()
	if a and a ~= SO.my_activity then
		SO.my_activity = a
		COOP.send('activity', { s = a })
	end
end

function SO.reset()
	if SO.wheel then
		SO.wheel:remove()
		SO.wheel = nil
	end
	clear_bubbles()
	SO.partner_activity, SO.my_activity, SO.last_ping = nil, nil, nil
end

-- Input -----------------------------------------------------------------------------

local function typing()
	return G.CONTROLLER and G.CONTROLLER.text_input_hook
end

local key_press_ref = Controller.key_press_update
function Controller:key_press_update(key, dt)
	if not typing() and in_run() then
		if key == WHEEL_KEY then
			SO.wheel_open()
		elseif key == PING_KEY then
			SO.ping_hovered()
		end
	end
	return key_press_ref(self, key, dt)
end

local key_release_ref = Controller.key_release_update
function Controller:key_release_update(key, dt)
	if key == WHEEL_KEY then
		SO.wheel_close()
	end
	return key_release_ref(self, key, dt)
end

local mousepressed_ref = love.mousepressed
function love.mousepressed(x, y, button, touch)
	if button == 3 then
		pcall(SO.ping_hovered)
	end
	return mousepressed_ref(x, y, button, touch)
end

-- "Offer" button in the shop ------------------------------------------------------

G.FUNCS.coop_offer = function(e)
	SO.ping_card(e.config.ref_table, 4)
end

local function offer_button(card)
	return UIBox({
		definition = { n = G.UIT.ROOT, config = { colour = G.C.CLEAR }, nodes = {
			{ n = G.UIT.C, config = { ref_table = card, align = 'cm', padding = 0.1, r = 0.08, minw = 1.1, minh = 0.6,
				hover = true, shadow = true, colour = G.C.BLUE, one_press = false, button = 'coop_offer' }, nodes = {
				{ n = G.UIT.T, config = { text = localize('k_coop_offer'), colour = G.C.WHITE, scale = 0.35, shadow = true } },
			} },
		} },
		config = { align = 'cl', offset = { x = 0.3, y = 0 }, major = card, bond = 'Weak', parent = card },
	})
end

-- the game adds the shop buttons in an event; ours goes in right after
local create_shop_card_ui_ref = create_shop_card_ui
function create_shop_card_ui(card, type, area)
	local res = create_shop_card_ui_ref(card, type, area)
	G.E_MANAGER:add_event(Event({
		trigger = 'after',
		delay = 0.45,
		blocking = false,
		func = function()
			if COOP.is_active() and card and not card.removed and not card.children.coop_offer then
				card.children.coop_offer = offer_button(card)
				card.children.coop_offer.states.visible = false
			end
			return true
		end,
	}))
	return res
end

-- shown with "Buy", while the card is selected and still in the shop
local card_update_ref = Card.update
function Card:update(dt)
	card_update_ref(self, dt)
	local b = self.children.coop_offer
	if b then
		local a = self.area
		local in_shop = a and (a == G.shop_jokers or a == G.shop_vouchers or a == G.shop_booster)
		if not in_shop then
			b:remove()
			self.children.coop_offer = nil
		else
			b.states.visible = self.highlighted and true or false
		end
	end
end
