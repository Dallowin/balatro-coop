-- Keeps both players at the same point of the run:
--  * the shop closes only when BOTH pressed "Next round" (the shop is shared)
--  * a blind picked or skipped by either player is picked/skipped for both;
--    the host decides (the guest only asks), so the two can't pick differently

COOP.FLOW = COOP.FLOW or {}
local F = COOP.FLOW

function F.reset()
	F.leave_ready = {} -- [round] = { me = bool, partner = bool }
	F.pending_choice = nil
	F.chosen = {} -- [round .. on_deck] = true once a choice was applied
	F.leaving = false
	F.badge, F.badge_kind = nil, nil -- the UIBox itself goes away with the run
	F.last_choice, F.last_choice_kind, F.last_choice_at, F.last_choice_sent, F.leave_sent = nil, nil, 0, 0, 0
	F.left_round, F.left_at = nil, 0
end
F.reset()

local function leave_state(round)
	F.leave_ready[round] = F.leave_ready[round] or {}
	return F.leave_ready[round]
end

-- Shop -------------------------------------------------------------------

function F.on_partner_leave_shop(round)
	leave_state(round).partner = true
end

-- A label pinned to the "Next round" button: 'waiting' after we pressed it
-- (the button is disabled), 'partner_ready' when the partner pressed first.
function F.remove_badge()
	if F.badge then
		F.badge:remove()
		F.badge = nil
	end
	F.badge_kind = nil
end

local function show_badge(kind)
	if F.badge_kind == kind then
		return
	end
	F.remove_badge()
	local button = G.shop and G.shop:get_UIE_by_ID('next_round_button')
	if not button then
		return
	end
	local waiting = kind == 'waiting'
	F.badge = UIBox({
		definition = {
			n = G.UIT.ROOT,
			config = { align = 'cm', colour = waiting and G.C.UI.BACKGROUND_INACTIVE or G.C.CLEAR, r = 0.1, padding = 0.05,
				minw = waiting and button.T.w or nil, minh = waiting and button.T.h or nil },
			nodes = {
				{ n = G.UIT.T, config = { text = localize(waiting and 'k_coop_waiting' or 'k_coop_partner_ready'), scale = 0.4,
					colour = waiting and G.C.UI.TEXT_LIGHT or G.C.GREEN, shadow = true } },
			},
		},
		config = waiting and { align = 'cm', offset = { x = 0, y = 0 }, major = button, bond = 'Weak' }
			or { align = 'tm', offset = { x = 0, y = -0.1 }, major = button, bond = 'Weak' },
	})
	F.badge_kind = kind
end

-- Called from Game:update: leave once both are ready.
function F.update_shop()
	if G.STATE ~= G.STATES.SHOP or not G.shop or F.leaving then
		F.remove_badge()
		return
	end
	local s = leave_state(G.GAME.round)
	if s.me and s.partner then
		F.remove_badge()
		F.leaving = true
		F.left_round, F.left_at = G.GAME.round, G.TIMERS.REAL -- keep telling the partner for a while
		F.toggle_shop_ref()
		return
	end
	if s.me then
		local button = G.shop:get_UIE_by_ID('next_round_button')
		if button then
			button.config.button = nil -- already pressed
		end
		show_badge('waiting')
	elseif s.partner then
		show_badge('partner_ready')
	else
		F.remove_badge()
	end
end

-- Blind select ----------------------------------------------------------

local function choice_id(round, on_deck)
	return tostring(round) .. ':' .. tostring(on_deck)
end

local function blind_option(on_deck)
	return G.blind_select_opts and G.blind_select_opts[string.lower(on_deck)]
end

local function apply_choice(choice)
	local opt = blind_option(choice.on_deck)
	if not opt then
		return false
	end
	F.chosen[choice_id(choice.round, choice.on_deck)] = true
	if choice.action == 'skip' then
		F.skip_blind_ref({ UIBox = opt })
	else
		local key = G.GAME.round_resets.blind_choices[choice.on_deck]
		F.select_blind_ref({ UIBox = opt, config = { ref_table = G.P_BLINDS[key] } })
	end
	return true
end

local function is_host()
	local lobby = COOP.get_lobby()
	return lobby and lobby.is_host
end

function F.on_partner_choice(action, round, on_deck)
	F.pending_choice = { action = action, round = round, on_deck = on_deck }
end

-- Host only: the guest asked for a choice. Applied like a partner's choice,
-- then announced to the guest as the decision.
function F.on_partner_request(action, round, on_deck)
	if not is_host() or F.chosen[choice_id(round, on_deck)] then
		return
	end
	F.pending_choice = { action = action, round = round, on_deck = on_deck, request = true }
end

-- Called from Game:update: applies the partner's choice once our blind
-- select screen is up and showing the same blind.
function F.update_blind_select()
	local c = F.pending_choice
	if not c then
		return
	end
	if F.chosen[choice_id(c.round, c.on_deck)] then
		F.pending_choice = nil -- we already made this choice ourselves
		return
	end
	if G.STATE ~= G.STATES.BLIND_SELECT or not G.blind_select or G.CONTROLLER.locked then
		return
	end
	if G.GAME.round ~= c.round or G.GAME.blind_on_deck ~= c.on_deck then
		return
	end
	if apply_choice(c) then
		F.pending_choice = nil
		if c.request then
			F.remember_choice({ action = c.action, round = c.round, on_deck = c.on_deck })
		end
	end
end

-- Messages can get lost (server rate limit, reconnects). The partner ignores
-- duplicates, so the shop-leave and blind-choice messages are simply repeated
-- for a while: a lost one can no longer leave someone stuck.
local RESEND_EVERY, RESEND_FOR = 2, 30

-- kind: 'blind_choice' (a decision) or 'blind_request' (guest asking the host)
function F.remember_choice(choice, kind)
	F.last_choice = choice
	F.last_choice_kind = kind or 'blind_choice'
	F.last_choice_at = G.TIMERS.REAL
	F.last_choice_sent = G.TIMERS.REAL
	COOP.send(F.last_choice_kind, choice)
end

local function resend()
	local now = G.TIMERS.REAL
	local c = F.last_choice
	if c and F.last_choice_kind == 'blind_request' and F.chosen[choice_id(c.round, c.on_deck)] then
		F.last_choice = nil -- the host decided
		c = nil
	end
	-- a request waits for the host as long as it takes (it may still be shopping)
	local fresh = F.last_choice_kind == 'blind_request' or now - F.last_choice_at < RESEND_FOR
	if c and fresh and now - F.last_choice_sent >= RESEND_EVERY then
		F.last_choice_sent = now
		COOP.send(F.last_choice_kind, c)
	end
	if G.STATE == G.STATES.SHOP and G.GAME then
		local s = leave_state(G.GAME.round)
		if s.me and not s.partner and now - (F.leave_sent or 0) >= RESEND_EVERY then
			F.leave_sent = now
			COOP.send('leave_shop', { round = G.GAME.round })
		end
	end
	-- we left: the partner may have missed our last 'leave_shop' and still wait
	if F.left_round and now - (F.left_at or 0) < RESEND_FOR and now - (F.leave_sent or 0) >= RESEND_EVERY then
		F.leave_sent = now
		COOP.send('leave_shop', { round = F.left_round })
	end
end

function F.update()
	F.update_shop()
	F.update_blind_select()
	resend()
	if G.STATE ~= G.STATES.SHOP then
		F.leaving = false
	end
end

function F.install_hooks()
	F.toggle_shop_ref = G.FUNCS.toggle_shop
	G.FUNCS.toggle_shop = function(e)
		if not COOP.is_active() then
			return F.toggle_shop_ref(e)
		end
		local s = leave_state(G.GAME.round)
		if not s.me then
			s.me = true
			COOP.send('leave_shop', { round = G.GAME.round })
		end
		-- F.update_shop shows "waiting" and leaves once the partner is ready too
	end

	F.select_blind_ref = G.FUNCS.select_blind
	G.FUNCS.select_blind = function(e)
		if COOP.is_active() then
			local on_deck = G.GAME.blind_on_deck
			local id = choice_id(G.GAME.round, on_deck)
			if F.chosen[id] then
				return
			end
			local choice = { action = 'select', round = G.GAME.round, on_deck = on_deck }
			if not is_host() then
				-- the host decides; its 'blind_choice' applies it here
				if not (F.last_choice and F.last_choice_kind == 'blind_request'
					and choice_id(F.last_choice.round, F.last_choice.on_deck) == id) then
					F.remember_choice(choice, 'blind_request')
					COOP.popup(localize('k_coop_waiting'))
				end
				return
			end
			F.chosen[id] = true
			F.remember_choice(choice)
		end
		return F.select_blind_ref(e)
	end

	F.skip_blind_ref = G.FUNCS.skip_blind
	G.FUNCS.skip_blind = function(e)
		if COOP.is_active() then
			local on_deck = G.GAME.blind_on_deck
			local id = choice_id(G.GAME.round, on_deck)
			if F.chosen[id] then
				return
			end
			local choice = { action = 'skip', round = G.GAME.round, on_deck = on_deck }
			if not is_host() then
				-- the host decides; its 'blind_choice' applies it here
				if not (F.last_choice and F.last_choice_kind == 'blind_request'
					and choice_id(F.last_choice.round, F.last_choice.on_deck) == id) then
					F.remember_choice(choice, 'blind_request')
					COOP.popup(localize('k_coop_waiting'))
				end
				return
			end
			F.chosen[id] = true
			F.remember_choice(choice)
		end
		return F.skip_blind_ref(e)
	end
end
