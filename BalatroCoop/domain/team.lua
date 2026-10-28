-- Team jokers: 3 shared slots on the right, next to the partner panel.
--
-- Team jokers (rarity "Team") are rare and expensive. Whoever buys one, it
-- lands in the team row of BOTH players and works in every hand either of
-- them plays. Selling it removes it for both. Each client keeps its own copy,
-- so per-hand counters (Echo) are tracked per player.

COOP.TEAM = COOP.TEAM or {}
COOP.ECHO_SHARE = 0.35 -- Echo: this much of the partner's last hand Mult
local TM = COOP.TEAM

TM.SLOTS = 3
local SCALE = 0.7

function TM.reset()
	G.coop_team = nil -- the area itself is cleaned up with the run
	TM.present = {} -- uid -> card, as of last frame
	TM.removing = {} -- uids removed because the partner sold them
	TM.next_uid = 0
	TM.echo_bonus = 0
	TM.my_mult = 0
	TM.pass_used_at = nil
	TM.bridge_card = nil
	TM.chain = 1
	TM.partner_last_score = nil
	TM.take_used_round = nil
	TM.remove_pass_button()
	TM.remove_take_button()
end

function TM.is_team(card)
	return card and card.config and card.config.center and card.config.center.coop_team
end

function TM.has(key)
	if not G.coop_team then
		return false
	end
	for _, c in ipairs(G.coop_team.cards) do
		if c.config.center.key == key and not c.debuff then
			return true
		end
	end
	return false
end

local function is_host()
	local lobby = MPAPI.get_current_lobby()
	return lobby and lobby.is_host
end

local function ensure_area()
	if G.coop_team or not G.consumeables or not G.jokers then
		return G.coop_team
	end
	local x = G.consumeables.T.x
	local y = G.jokers.T.y + G.jokers.T.h + 0.45
	local w = math.max(G.TILE_W - x - 0.3, G.CARD_W * SCALE * 2)
	G.coop_team = CardArea(x, y, w, G.CARD_H * SCALE, { card_limit = TM.SLOTS, type = 'joker', highlight_limit = 1 })
	-- Steamodded fills these on its first update unless a tarot is being used
	-- right then; it then reads them anyway (crash). Start them off ourselves.
	local limits = G.coop_team.config.card_limits
	if limits then
		limits.extra_slots = limits.extra_slots or 0
		limits.extra_slots_used = limits.extra_slots_used or 0
	end
	return G.coop_team
end

-- Polling ---------------------------------------------------------------------

function TM.update()
	local area = ensure_area()
	if not area then
		return
	end

	-- a team joker bought from the shop or a pack lands in G.jokers: move it
	for i = #G.jokers.cards, 1, -1 do
		local c = G.jokers.cards[i]
		if TM.is_team(c) and not c.coop_team_uid then
			TM.next_uid = TM.next_uid + 1
			c.coop_team_uid = (is_host() and 'h' or 'g') .. TM.next_uid
			G.jokers:remove_card(c)
			area:emplace(c)
			COOP.send('team_add', { uid = c.coop_team_uid, key = c.config.center.key, edition = c.edition and c.edition.key or '' })
		end
	end

	-- sold or destroyed here -> remove for the partner too
	local now = {}
	for _, c in ipairs(area.cards) do
		if c.coop_team_uid then
			now[c.coop_team_uid] = c
		end
	end
	for uid in pairs(TM.present) do
		if not now[uid] and not TM.removing[uid] then
			COOP.send('team_remove', { uid = uid })
		end
	end
	TM.removing = {}
	TM.present = now

	TM.update_pass_button()
	TM.update_take_button()
end

function TM.on_add(uid, key, edition)
	local area = ensure_area()
	if not area or not G.P_CENTERS[key] then
		return
	end
	for _, c in ipairs(area.cards) do
		if c.coop_team_uid == uid then
			return
		end
	end
	local card = SMODS.create_card({ set = 'Joker', key = key, area = area, no_edition = true })
	if edition ~= '' then
		card:set_edition(edition, true, true)
	end
	card.coop_team_uid = uid
	card:add_to_deck()
	area:emplace(card)
	card:juice_up(0.5, 0.5)
	COOP.popup(localize('k_coop_team_joker'), G.C.SECONDARY_SET.Spectral)
end

function TM.on_remove(uid)
	if not G.coop_team then
		return
	end
	for _, c in ipairs(G.coop_team.cards) do
		if c.coop_team_uid == uid then
			TM.removing[uid] = true
			c:start_dissolve()
		end
	end
end

-- Chain: decided by whoever just played, then sent so both sides match.
function TM.after_my_hand(score)
	if not TM.has('j_coop_chain') or not TM.partner_last_score then
		return
	end
	if score > TM.partner_last_score then
		TM.chain = (TM.chain or 1) + 0.25
	else
		TM.chain = 1
	end
	COOP.send('chain', { value = TM.chain })
end

function TM.on_chain(value)
	TM.chain = value
end

-- Echo: the partner's final Mult feeds our next hand.
function TM.on_partner_mult(mult)
	if TM.has('j_coop_echo') and type(mult) == 'number' and mult > 0 then
		TM.echo_bonus = math.floor(mult * COOP.ECHO_SHARE)
	end
end

-- Pass button ----------------------------------------------------------------

function TM.remove_pass_button()
	if TM.pass_button then
		TM.pass_button:remove()
		TM.pass_button = nil
	end
end

local function pass_available()
	return COOP.is_active()
		and TM.has('j_coop_pass')
		and G.STATE == G.STATES.SELECTING_HAND
		and G.hand
		and #G.hand.highlighted == 1
		and TM.pass_used_at ~= G.GAME.current_round.hands_played .. ':' .. G.GAME.round
		and not G.CONTROLLER.locked
end

function TM.update_pass_button()
	if not pass_available() then
		TM.remove_pass_button()
		return
	end
	if TM.pass_button then
		return
	end
	TM.pass_button = UIBox({
		definition = {
			n = G.UIT.ROOT,
			config = { align = 'cm', colour = G.C.CLEAR },
			nodes = {
				UIBox_button({ button = 'coop_pass_card', label = { localize('k_coop_pass') }, minw = 2.2, minh = 0.6, scale = 0.45, colour = G.C.GREEN }),
			},
		},
		config = { align = 'tr', offset = { x = 0, y = -0.9 }, major = G.hand, bond = 'Weak' },
	})
end

G.FUNCS.coop_pass_card = function()
	if not pass_available() then
		return
	end
	local card = G.hand.highlighted[1]
	TM.pass_used_at = G.GAME.current_round.hands_played .. ':' .. G.GAME.round
	G.hand:remove_from_highlighted(card, true)
	COOP.DECK.pass_card(card)
	play_sound('card1')
	TM.remove_pass_button()
end

-- Shared Hand button: under the partner's hand, once one of their cards is
-- selected (click it, as for tarot targets).

function TM.remove_take_button()
	if TM.take_button then
		TM.take_button:remove()
		TM.take_button = nil
	end
end

local function take_target()
	local targets = COOP.PV.targets()
	if #targets == 1 and targets[1].coop_uid then
		return targets[1]
	end
end

local function take_available()
	return COOP.is_active()
		and TM.has('j_coop_shared_hand')
		and G.STATE == G.STATES.SELECTING_HAND
		and TM.take_used_round ~= G.GAME.round
		and COOP.PV.hand_area
		and take_target()
		and not G.CONTROLLER.locked
end

function TM.update_take_button()
	if not take_available() then
		TM.remove_take_button()
		return
	end
	if TM.take_button then
		return
	end
	TM.take_button = UIBox({
		definition = {
			n = G.UIT.ROOT,
			config = { align = 'cm', colour = G.C.CLEAR },
			nodes = {
				UIBox_button({ button = 'coop_take_card', label = { localize('k_coop_take_card') }, minw = 2.2, minh = 0.55, scale = 0.42, colour = G.C.SECONDARY_SET.Spectral }),
			},
		},
		config = { align = 'bm', offset = { x = 0, y = 0.5 }, major = COOP.PV.hand_area, bond = 'Weak' },
	})
end

G.FUNCS.coop_take_card = function()
	local target = take_available() and take_target()
	if not target then
		return
	end
	if COOP.DECK.take_from_partner(target.coop_uid) then
		TM.take_used_round = G.GAME.round
		COOP.PV.clear_targets()
		TM.remove_take_button()
	end
end

-- Hooks ----------------------------------------------------------------------

function TM.install_hooks()
	-- team jokers are scored like our own jokers
	local get_areas_ref = SMODS.get_card_areas
	function SMODS.get_card_areas(_type, _context)
		local t = get_areas_ref(_type, _context)
		if _type == 'jokers' and G.coop_team and COOP.is_active() then
			t[#t + 1] = G.coop_team
		end
		return t
	end

	-- Bridge and passive jokers: Shortcut, Four Fingers, Smeared Joker,
	-- Pareidolia, Splash... never "trigger", the game just asks whether you
	-- own them. Answer yes when Bridge is copying one.
	local function bridged(match)
		if not COOP.is_active() or not TM.has('j_coop_bridge') then
			return nil
		end
		local target = TM.bridge_target()
		if target and match(target) then
			return target
		end
	end

	local find_joker_ref = find_joker
	function find_joker(name, non_debuff)
		local found = find_joker_ref(name, non_debuff)
		local target = bridged(function(c)
			return c.ability.name == name
		end)
		if target then
			found[#found + 1] = target
		end
		return found
	end

	local find_card_ref = SMODS.find_card
	function SMODS.find_card(key, count_debuffed)
		local found = find_card_ref(key, count_debuffed)
		local target = bridged(function(c)
			return c.config.center.key == key
		end)
		if target then
			found[#found + 1] = target
		end
		return found
	end

	-- buying a team joker needs a free team slot, not a joker slot
	local buy_space_ref = G.FUNCS.check_for_buy_space
	G.FUNCS.check_for_buy_space = function(card)
		if COOP.is_active() and TM.is_team(card) then
			local area = ensure_area()
			if area and #area.cards >= TM.SLOTS then
				alert_no_space(card, area)
				return false
			end
			return true
		end
		return buy_space_ref(card)
	end

	-- remember our final Mult for Echo (sent with the score report). Scoring
	-- ends by resetting the HUD to mult = 0, so ignore zeros: the last
	-- non-zero value is the hand's final Mult.
	local hand_text_ref = update_hand_text
	function update_hand_text(config, vals)
		if COOP.is_active() and not COOP.PV.replaying and vals and type(vals.mult) == 'number' and vals.mult ~= 0
			and G.STATE == G.STATES.HAND_PLAYED then
			TM.my_mult = vals.mult
		end
		COOP.PV.capture_hand_text(config, vals)
		return hand_text_ref(config, vals)
	end
end

TM.reset()
