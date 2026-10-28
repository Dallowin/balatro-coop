COOP = SMODS.current_mod

COOP.GAMEMODE = 'coop_shared_blind'

-- Cut a string to max characters (not bytes: cutting bytes splits Cyrillic
-- letters in a Steam name and crashes the UI with "Invalid UTF-8").
COOP.truncate = function(s, max)
	if not s then
		return s
	end
	local chars = {}
	for ch in s:gmatch('[%z\1-\127\194-\244][\128-\191]*') do
		chars[#chars + 1] = ch
	end
	if #chars <= max then
		return s
	end
	return table.concat(chars, '', 1, max - 3) .. '...'
end

local function load(file)
	local chunk, err = SMODS.load_file(file, COOP.id)
	if not chunk then
		sendWarnMessage('Failed to load ' .. file .. ': ' .. tostring(err), COOP.id)
		return
	end
	local ok, res = pcall(chunk)
	if not ok then
		sendWarnMessage('Failed to run ' .. file .. ': ' .. tostring(res), COOP.id)
	end
end

load('domain/modes.lua')
load('domain/synergy.lua')
load('domain/challenges.lua')
load('domain/history.lua')
load('domain/consumables.lua')
load('domain/shared_blind.lua')
load('domain/deck.lua')
load('domain/flow.lua')
load('domain/shop.lua')
load('domain/money.lua')
load('domain/tarot.lua')
load('domain/team.lua')
load('domain/vouchers.lua')
load('net/lobby.lua')
load('net/steam.lua')
load('net/steam_lobby.lua')
load('ui/pages.lua')
load('ui/partner_view.lua')
load('ui/chat.lua')
load('ui/social.lua')
load('ui/casino.lua')
load('ui/status.lua')
load('ui/menus.lua')
-- SMODS objects must be registered while mods load
load('objects/jokers.lua')
load('objects/team_jokers.lua')
load('objects/coop_bosses.lua')
load('objects/coop_decks.lua')
load('objects/coop_cards.lua')
load('objects/art.lua')

-- Diagnostics in the Lovely log (Mods/lovely/log), tagged "Coop".
function COOP.debug(fmt, ...)
	local ok, msg = pcall(string.format, fmt, ...)
	sendWarnMessage(ok and msg or tostring(fmt), 'Coop')
end

function COOP.is_active()
	return COOP.in_run and G.STAGE == G.STAGES.RUN and COOP.get_lobby() ~= nil
end

-- Our own co-op messages ("Your turn!", "Partner +N"...) show above the deck,
-- clear of the play area where hands are played and replayed.
-- queued = true: wait until the events already queued (e.g. the partner's
-- replayed scoring) have played out.
-- SMODS scores every mod that has a calculate function (as an "individual"
-- target, like the deck or a stake): that is how Relay and Resonance join
-- every hand without being jokers.
function COOP.calculate(self, context)
	if COOP.is_active() and context.initial_scoring_step and context.scoring_hand then
		-- which of the played cards score: they rise on the partner's screen
		local ids = {}
		for _, c in ipairs(context.scoring_hand) do
			ids[#ids + 1] = c.sort_id
		end
		COOP.send('scoring', { ids = table.concat(ids, ';') })
	end
	-- Mr. Bones saves the team: the partner's own copy saves them, this saves
	-- us (same rule: at least 25% of the blind; the counted score is shared)
	if COOP.is_active() and context.end_of_round and context.game_over and context.main_eval then
		local p = COOP.PV.partner
		local partner_bones = p and p.jokers and p.jokers:find('|j_mr_bones|', 1, true)
		if partner_bones and not next(SMODS.find_card('j_mr_bones'))
			and G.GAME.blind.chips > 0 and G.GAME.chips / G.GAME.blind.chips >= 0.25 then
			return { message = localize('k_saved_ex'), saved = 'ph_mr_bones', colour = G.C.RED }
		end
	end
	if COOP.is_active() and COOP.MODES.on('resonance') then
		return COOP.SYN.calculate(context)
	end
end

function COOP.popup(text, colour, queued)
	local function show()
		if G.deck then
			attention_text({
				text = text,
				scale = 0.5,
				hold = 2,
				major = G.deck,
				backdrop_colour = colour or G.C.BLUE,
				align = 'tm',
				offset = { x = 0, y = -0.6 },
				silent = true,
			})
		end
		return true
	end
	if queued then
		G.E_MANAGER:add_event(Event({ func = show }))
	else
		show()
	end
end

-- Network ---------------------------------------------------------------
--
-- Every message is queued and handled from Game:update, never inside the
-- network callback: several handlers start game events or change G.STATE.

COOP.inbox = {}

local STR, NUM, TBL = 'string', 'number', 'table'
local MESSAGES = {
	score = { round = NUM, total = NUM, hands_left = NUM, hand = STR, mult = NUM, played = NUM },
	hand_text = { name = STR, level = STR, chips = STR, mult = STR, delay = NUM, immediate = 'boolean', nopulse = 'boolean', sound = STR },
	card_take = { uid = STR },
	card_update = { uid = STR, look = STR },
	card_add = { uid = STR, look = STR, to_deck = 'boolean' },
	card_remove = { uid = STR },
	deck_order = { uids = STR },
	pass = { uid = STR },
	team_add = { uid = STR, key = STR, edition = STR },
	team_remove = { uid = STR },
	voucher = { key = STR },
	chain = { value = NUM },
	resonance = { level = NUM },
	blind_state = { round = NUM, disabled = 'boolean', chips = NUM },
	claim = { sid = NUM },
	scoring = { ids = STR },
	claim_result = { sid = NUM, ok = 'boolean' },
	chat = { name = STR, text = STR },
	take_card = { uid = STR },
	take_reject = { uid = STR },
	ready_blind = { round = NUM, hands_left = NUM, played = NUM, total = NUM, turn = NUM },
	unstick = { round = NUM },
	cons_add = { cid = STR, key = STR, edition = STR },
	cons_remove = { cid = STR },
	state = { hand = STR, jokers = STR, hands_left = NUM, discards_left = NUM },
	play = { cards = STR },
	discard = { ids = STR },
	step = { id = NUM, where = STR, eval_type = STR, amt = NUM, message = STR, colour = STR, flags = STR },
	shop = { round = NUM, reroll_cost = NUM, items = TBL },
	taken = { sid = NUM },
	reroll = { round = NUM },
	leave_shop = { round = NUM },
	blind_choice = { action = STR, round = NUM, on_deck = STR },
	blind_request = { action = STR, round = NUM, on_deck = STR },
	hello = { version = STR },
	live = { name = STR, level = NUM, chips = NUM, mult = NUM, total = NUM },
	joker_state = { data = TBL },
	meta = { data = TBL },
	ready = { ready = 'boolean' },
	start = { seed = STR },
	money = { amount = NUM },
	use_on_partner = { key = STR, ids = STR },
	wheel = { i = NUM },
	ping = { k = STR, id = STR, lvl = NUM },
	activity = { s = STR },
	swap = { key = STR, edition = STR, idx = NUM },
	swap_back = { key = STR, edition = STR },
	bond_draw = { n = NUM },
	sacrifice = { n = NUM },
}

local HANDLERS = {
	swap = function(p)
		COOP.CARDS.on_swap(p.key, p.edition, p.idx)
	end,
	swap_back = function(p)
		COOP.CARDS.on_swap_back(p.key, p.edition)
	end,
	bond_draw = function(p)
		COOP.CARDS.on_bond_draw(p.n)
	end,
	sacrifice = function(p)
		COOP.CARDS.on_sacrifice(p.n)
	end,
	-- also in IMMEDIATE below; here for the solo test's mirror, which goes through the inbox
	wheel = function(p)
		COOP.SOCIAL.on_wheel(p.i)
	end,
	ping = function(p)
		COOP.SOCIAL.on_ping(p.k, p.id, p.lvl)
	end,
	activity = function(p)
		COOP.SOCIAL.on_activity(p.s)
	end,
	score = function(p)
		COOP.SB.on_partner_report(p.round, p.total, p.hands_left, p.hand, p.played)
		COOP.TEAM.on_partner_mult(p.mult)
		if p.hand ~= '' then
			COOP.STATUS.last_partner = { hand = p.hand, score = COOP.TEAM.partner_last_score or 0, mult = p.mult }
		end
		COOP.PV.on_partner_scored()
	end,
	hand_text = function(p)
		COOP.PV.on_partner_hand_text(p)
	end,
	card_take = function(p)
		COOP.DECK.on_take(p.uid)
	end,
	card_update = function(p)
		COOP.DECK.on_update(p.uid, p.look)
	end,
	card_add = function(p)
		COOP.DECK.on_add(p.uid, p.look, p.to_deck)
	end,
	card_remove = function(p)
		COOP.DECK.on_remove(p.uid)
	end,
	deck_order = function(p)
		local lobby = COOP.get_lobby()
		if lobby and not lobby.is_host then
			COOP.DECK.on_order(p.uids)
		end
	end,
	pass = function(p)
		COOP.DECK.on_pass(p.uid)
	end,
	team_add = function(p)
		COOP.TEAM.on_add(p.uid, p.key, p.edition)
	end,
	team_remove = function(p)
		COOP.TEAM.on_remove(p.uid)
	end,
	voucher = function(p)
		COOP.VOUCHERS.on_partner_redeem(p.key)
	end,
	chain = function(p)
		COOP.TEAM.on_chain(p.value)
	end,
	resonance = function(p)
		COOP.SYN.on_resonance(p.level)
	end,
	blind_state = function(p)
		COOP.SB.on_partner_blind(p.round, p.disabled, p.chips)
	end,
	claim = function(p)
		local lobby = COOP.get_lobby()
		if lobby and lobby.is_host then
			COOP.SHOP.on_claim(p.sid)
		end
	end,
	claim_result = function(p)
		COOP.SHOP.on_claim_result(p.sid, p.ok)
	end,
	scoring = function(p)
		COOP.PV.on_partner_scoring(p.ids)
	end,
	take_card = function(p)
		COOP.DECK.on_partner_took(p.uid)
	end,
	take_reject = function(p)
		COOP.DECK.on_take_rejected(p.uid)
	end,
	play = function(p)
		COOP.PV.on_partner_play(p.cards)
		COOP.SYN.on_partner_play(p.cards)
	end,
	discard = function(p)
		COOP.PV.on_partner_discard(p.ids)
	end,
	step = function(p)
		COOP.PV.on_partner_step(p)
	end,
	money = function(p)
		COOP.MONEY.on_partner_change(p.amount)
	end,
	use_on_partner = function(p)
		COOP.TAROT.on_partner_use(p.key, p.ids)
	end,
	ready_blind = function(p)
		COOP.SB.on_partner_ready(p.round, p.hands_left, p.played, p.total, p.turn)
	end,
	unstick = function(p)
		COOP.SB.on_partner_unstick(p.round)
	end,
	cons_add = function(p)
		COOP.CONS.on_add(p.cid, p.key, p.edition)
	end,
	cons_remove = function(p)
		COOP.CONS.on_remove(p.cid)
	end,
	state = function(p)
		COOP.PV.on_partner_state(p)
	end,
	shop = function(p)
		COOP.SHOP.on_listing(p.round, p.reroll_cost, p.items)
	end,
	taken = function(p)
		local lobby = COOP.get_lobby()
		if lobby and lobby.is_host then
			COOP.SHOP.host_on_taken(p.sid)
		end
	end,
	reroll = function(p)
		local lobby = COOP.get_lobby()
		if lobby and lobby.is_host and p.round == G.GAME.round then
			COOP.SHOP.pending_reroll = true
		end
	end,
	leave_shop = function(p)
		COOP.FLOW.on_partner_leave_shop(p.round)
	end,
	blind_choice = function(p)
		COOP.FLOW.on_partner_choice(p.action, p.round, p.on_deck)
	end,
	live = function(p)
		COOP.PV.on_partner_live(p)
	end,
	joker_state = function(p)
		COOP.PV.on_partner_joker_state(p.data)
	end,
	blind_request = function(p)
		COOP.FLOW.on_partner_request(p.action, p.round, p.on_deck)
	end,
}

-- Outgoing messages are batched: a single scored hand alone makes dozens of
-- messages (every popup and every chips/mult update). So COOP.send only
-- queues; the queue goes out as one Steam packet at most every FLUSH_EVERY
-- seconds.

local FLUSH_EVERY = 0.1

COOP.outbox = {}
local flush_timer = 0

local function valid(name, params)
	local schema = MESSAGES[name]
	if not schema or type(params) ~= 'table' then
		return false
	end
	for key, t in pairs(schema) do
		if type(params[key]) ~= t then
			return false
		end
	end
	return true
end

function COOP.send(name, params)
	if not valid(name, params) then
		sendWarnMessage('dropping invalid message ' .. tostring(name), COOP.id)
		return
	end
	COOP.outbox[#COOP.outbox + 1] = { n = name, p = params }
end

-- Solo test ("mirror"): no server, no partner. Everything we would send comes
-- back to us as the partner's messages, held until our own hand has finished
-- scoring so the "partner" replay doesn't overlap ours. Money and chat are not
-- mirrored (they would double).
local MIRROR_SKIP = { money = true, chat = true, hello = true, meta = true, ready = true, start = true }
COOP.test_pending = {}

function COOP.release_test_mirror()
	if not COOP.TEST or #COOP.test_pending == 0 then
		return
	end
	-- In a blind, the mirror "partner" only moves once our turn is completely
	-- over: hand scored, new cards drawn, back to picking cards.
	local in_blind = G.GAME and G.GAME.blind and G.GAME.blind.in_blind
	if in_blind and (G.STATE ~= G.STATES.SELECTING_HAND or (G.play and #G.play.cards > 0)) then
		return
	end
	if G.CONTROLLER.locked then
		return
	end
	for _, msg in ipairs(COOP.test_pending) do
		COOP.inbox[#COOP.inbox + 1] = msg
	end
	COOP.test_pending = {}
end

function COOP.flush(dt)
	if COOP.TEST then
		for _, msg in ipairs(COOP.outbox) do
			if not MIRROR_SKIP[msg.n] then
				COOP.test_pending[#COOP.test_pending + 1] = { name = msg.n, params = msg.p }
			end
		end
		COOP.outbox = {}
		return
	end
	flush_timer = flush_timer + (dt or 0)
	if #COOP.outbox == 0 or flush_timer < FLUSH_EVERY then
		return
	end
	flush_timer = 0
	COOP.SL.flush(COOP.outbox) -- Steam P2P: the whole queue is one packet
	COOP.outbox = {}
end

-- Lobby-level messages work outside a run too, so they skip the inbox.
local IMMEDIATE = {
	chat = function(p)
		COOP.CHAT.add(p.name, p.text)
	end,
	hello = function(p)
		COOP.on_hello(p.version)
	end,
	meta = function(p)
		COOP.SL.on_meta(p.data)
	end,
	ready = function(p)
		COOP.SL.on_ready(p.ready)
	end,
	start = function(p)
		COOP.SL.on_start(p.seed)
	end,
	wheel = function(p)
		COOP.SOCIAL.on_wheel(p.i)
	end,
	ping = function(p)
		COOP.SOCIAL.on_ping(p.k, p.id, p.lvl)
	end,
	activity = function(p)
		COOP.SOCIAL.on_activity(p.s)
	end,
}

-- A batch from the partner over Steam (net/steam_lobby.lua).
function COOP.receive_msgs(msgs)
	for _, msg in ipairs(msgs) do
		if type(msg) == 'table' and IMMEDIATE[msg.n] and valid(msg.n, msg.p) then
			local ok, err = pcall(IMMEDIATE[msg.n], msg.p)
			if not ok then
				sendWarnMessage('handler ' .. msg.n .. ' failed: ' .. tostring(err), COOP.id)
			end
		elseif type(msg) == 'table' and HANDLERS[msg.n] and valid(msg.n, msg.p) then
			COOP.inbox[#COOP.inbox + 1] = { name = msg.n, params = msg.p }
		end
	end
end

local function drain_inbox()
	if not COOP.is_active() then
		return
	end
	local inbox = COOP.inbox
	COOP.inbox = {}
	for _, msg in ipairs(inbox) do
		local ok, err = pcall(HANDLERS[msg.name], msg.params)
		if not ok then
			sendWarnMessage('handler ' .. msg.name .. ' failed: ' .. tostring(err), COOP.id)
		end
	end
end

-- Version check -----------------------------------------------------------

-- Both players must run the same version: the messages and rules change
-- between versions. Each side announces its version on joining; the host
-- can't start until the partner's version is known and equal.
function COOP.send_hello()
	COOP.send('hello', { version = tostring(COOP.version) })
end

function COOP.on_hello(version)
	if COOP.partner_version == version then
		return
	end
	local first = COOP.partner_version == nil
	COOP.partner_version = version
	if first then
		COOP.send_hello() -- so a newcomer learns ours too
	end
	COOP.refresh_view()
end

function COOP.versions_match()
	return COOP.partner_version == tostring(COOP.version)
end

-- Run start ---------------------------------------------------------------

-- G.FUNCS.start_run clears the event queue, so it must not run from inside an
-- Event or a network callback. Store the request and start it from Game:update.
function COOP.request_run(seed, lobby)
	COOP.pending_run = { seed = seed, lobby = lobby }
end

local function start_pending_run()
	local p = COOP.pending_run
	if not p then
		return
	end
	COOP.pending_run = nil
	if p.lobby ~= COOP.get_lobby() then
		return
	end
	if G.STAGE == G.STAGES.RUN then
		G:delete_run()
	end
	COOP.SB.reset()
	COOP.FLOW.reset()
	COOP.SHOP.reset()
	COOP.PV.reset()
	COOP.TAROT.queue = {}
	COOP.DECK.reset()
	COOP.SYN.reset()
	COOP.TEAM.reset()
	COOP.CONS.reset()
	COOP.SOCIAL.reset()
	-- keep COOP.inbox: the partner's run may already be sending
	COOP.in_run = true
	COOP.result_sent = false
	COOP.MODES.freeze()
	if COOP.MODES.get('run') == 'daily' then
		p.seed = COOP.CHALLENGE.daily_seed(COOP.MODES.daily_date()) -- same seed for every pair today
	end
	G.GAME.viewed_back = Back(G.P_CENTERS[COOP.MODES.get('back')] or G.P_CENTERS.b_red)
	COOP.starting = true
	local ok, err = pcall(G.FUNCS.start_run, nil, { stake = tonumber(COOP.MODES.get('stake')) or 1, seed = p.seed })
	COOP.starting = false
	if not ok then
		error(err, 0)
	end
end

-- "New Run" from the game over screen or the options menu starts an ordinary
-- solo run: it must not keep acting as the co-op run (sending moves, waiting
-- for the partner).
local start_run_ref = G.FUNCS.start_run
G.FUNCS.start_run = function(...)
	if COOP.in_run and not COOP.starting then
		COOP.in_run = false
		if COOP.TEST then
			COOP.TEST = false
			COOP.test_pending = {}
			local lobby = COOP.get_lobby()
			if lobby then
				lobby:leave()
			end
		end
		COOP.PV.remove()
		COOP.STATUS.remove()
		COOP.TEAM.reset()
		COOP.inbox = {}
	end
	return start_run_ref(...)
end

local go_to_menu_ref = G.FUNCS.go_to_menu
G.FUNCS.go_to_menu = function(...)
	COOP.pending_run = nil
	COOP.in_run = false
	if COOP.TEST then
		-- the solo test's local lobby only lives for that one run
		COOP.TEST = false
		COOP.test_pending = {}
		local lobby = COOP.get_lobby()
		if lobby then
			lobby:leave()
		end
	end
	COOP.inbox = {}
	COOP.outbox = {}
	COOP.PV.remove()
	COOP.STATUS.remove()
	COOP.TEAM.reset()
	COOP.SOCIAL.reset()
	return go_to_menu_ref(...)
end

local function step(name, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		sendWarnMessage(name .. ' failed: ' .. tostring(err), COOP.id)
	end
end

-- the game's own functions exist once the mods have loaded
local function install()
	COOP.register_pages()
	COOP.SB.install_hooks()
	COOP.DECK.install_hooks()
	COOP.FLOW.install_hooks()
	COOP.SHOP.install_hooks()
	COOP.MONEY.install_hooks()
	COOP.TAROT.install_hooks()
	COOP.PV.install_hooks()
	COOP.TEAM.install_hooks()
	COOP.VOUCHERS.install_hooks()
	COOP.CHALLENGE.install_hooks()
	COOP.HISTORY.install_hooks()

	local game_update_ref = Game.update
	function Game:update(dt)
		game_update_ref(self, dt)
		step('start run', start_pending_run)
		step('pages', COOP.PAGES.update)
		step('steam', COOP.SL.update)
		step('send', COOP.flush, dt)
		if not COOP.is_active() then
			return
		end
		step('solo test mirror', COOP.release_test_mirror)
		step('inbox', drain_inbox)
		step('shared blind', COOP.SB.update)
		step('flow', COOP.FLOW.update)
		step('shop', COOP.SHOP.update)
		step('partner view', COOP.PV.update, dt)
		step('partner tarot', COOP.TAROT.update)
		step('casino', COOP.CASINO.update)
		step('history', COOP.HISTORY.update)
		step('shared consumables', COOP.CONS.update, dt)
		step('shared deck', COOP.DECK.update, dt)
		step('team jokers', COOP.TEAM.update)
		step('social', COOP.SOCIAL.update)
		step('co-op cards', COOP.CARDS.update)
		step('team panel', COOP.STATUS.update)
	end
end
install()
