-- Team jokers: rare, expensive, and they sit in the shared team row
-- (domain/team.lua), working for both players. Art reuses vanilla sprites.

SMODS.Rarity({
	key = 'team',
	default_weight = 0.05,
	badge_colour = HEX('C552E0'),
	pools = { Joker = true },
	get_weight = function(self, weight, object_type)
		return COOP.is_active() and weight or 0
	end,
})

local function team_joker(def)
	def.atlas = 'Joker'
	def.prefix_config = { atlas = false } -- vanilla joker sheet
	def.rarity = 'coop_team'
	def.coop_team = true
	local needs_shared = def.needs_shared_deck
	def.in_pool = function()
		return COOP.is_active() and (not needs_shared or COOP.MODES.on('shared_deck'))
	end
	SMODS.Joker(def)
end

-- Pass: once per turn, hand one card from your hand to your partner.
team_joker({
	key = 'pass',
	needs_shared_deck = true,
	pos = { x = 4, y = 5 },
	cost = 10,
	blueprint_compat = false,
})

-- Bridge: copies the ability of the partner's rightmost joker.
team_joker({
	key = 'bridge',
	pos = { x = 0, y = 3 },
	cost = 15,
	blueprint_compat = false,
	loc_vars = function(self, info_queue, card)
		local target = COOP.TEAM.bridge_target()
		local name = target and localize({ type = 'name_text', set = 'Joker', key = target.config.center.key }) or '-'
		return { vars = { name } }
	end,
	calculate = function(self, card, context)
		local target = COOP.TEAM.bridge_target()
		if context.joker_main then
			COOP.debug('bridge: target=%s', target and target.config.center.key or 'none')
		end
		if target then
			return SMODS.blueprint_effect(card, target, context)
		end
	end,
})

-- Echo: your hand gets +Mult equal to 20% of the partner's last hand's Mult.
team_joker({
	key = 'echo',
	pos = { x = 8, y = 9 },
	cost = 12,
	blueprint_compat = true,
	loc_vars = function(self, info_queue, card)
		return { vars = { 20, COOP.TEAM.echo_bonus or 0 } }
	end,
	calculate = function(self, card, context)
		if context.joker_main then
			COOP.debug('echo: bonus=%s', tostring(COOP.TEAM.echo_bonus))
		end
		if context.joker_main and (COOP.TEAM.echo_bonus or 0) > 0 then
			return { mult = COOP.TEAM.echo_bonus }
		end
		if context.after and not context.blueprint then
			COOP.TEAM.echo_bonus = 0
		end
	end,
})

-- Double Strike: X3 Mult if you play the same poker hand your partner just played.
team_joker({
	key = 'double',
	pos = { x = 2, y = 11 },
	cost = 14,
	blueprint_compat = true,
	config = { extra = { xmult = 3 } },
	loc_vars = function(self, info_queue, card)
		local last = COOP.SB and COOP.SB.partner_hand_this_blind()
		return { vars = { card.ability.extra.xmult, last and localize(last, 'poker_hands') or '-' } }
	end,
	calculate = function(self, card, context)
		local last = COOP.SB.partner_hand_this_blind()
		if context.joker_main then
			COOP.debug('double strike: partner=%s mine=%s', tostring(last), tostring(context.scoring_name))
		end
		if context.joker_main and last and context.scoring_name == last then
			return { xmult = card.ability.extra.xmult }
		end
	end,
})

-- Chain: a hand that beats the partner's previous hand adds X0.25 Mult for
-- both of you; a weaker hand resets it to X1. Updated in COOP.TEAM.after_my_hand.
team_joker({
	key = 'chain',
	pos = { x = 9, y = 5 },
	cost = 13,
	blueprint_compat = true,
	loc_vars = function(self, info_queue, card)
		return { vars = { 0.25, COOP.TEAM.chain or 1 } }
	end,
	calculate = function(self, card, context)
		if context.joker_main and (COOP.TEAM.chain or 1) > 1 then
			return { xmult = COOP.TEAM.chain }
		end
	end,
})

-- Contrast: X2.5 Mult if you play a different poker hand than the partner's
-- last one this blind.
team_joker({
	key = 'contrast',
	pos = { x = 3, y = 6 },
	cost = 12,
	blueprint_compat = true,
	config = { extra = { xmult = 2.5 } },
	loc_vars = function(self, info_queue, card)
		local last = COOP.SB and COOP.SB.partner_hand_this_blind()
		return { vars = { card.ability.extra.xmult, last and localize(last, 'poker_hands') or '-' } }
	end,
	calculate = function(self, card, context)
		local last = COOP.SB.partner_hand_this_blind()
		if context.joker_main and last and context.scoring_name ~= last then
			return { xmult = card.ability.extra.xmult }
		end
	end,
})

-- Shared Hand: once per blind, take a card from the partner's hand into yours
-- (button under their hand, domain/team.lua).
team_joker({
	key = 'shared_hand',
	needs_shared_deck = true,
	pos = { x = 6, y = 2 },
	cost = 13,
	blueprint_compat = false,
})

-- Support: your last hand of the blind gets +Chips equal to 25% of what the
-- partner scored this blind.
team_joker({
	key = 'support',
	pos = { x = 7, y = 4 },
	cost = 12,
	blueprint_compat = true,
	config = { extra = { percent = 25 } },
	loc_vars = function(self, info_queue, card)
		return { vars = { card.ability.extra.percent, math.floor(COOP.SB.partner_round_total() * card.ability.extra.percent / 100) } }
	end,
	calculate = function(self, card, context)
		if context.joker_main and G.GAME.current_round.hands_left == 0 then
			local chips = math.floor(COOP.SB.partner_round_total() * card.ability.extra.percent / 100)
			if chips > 0 then
				return { chips = chips }
			end
		end
	end,
})

-- Second Wind: a lost blind with at least 75% of the score still counts as
-- beaten, once. Both players hold it, so both are saved and both lose it.
team_joker({
	key = 'second_wind',
	pos = { x = 8, y = 6 },
	cost = 15,
	blueprint_compat = false,
	config = { extra = { percent = 75 } },
	loc_vars = function(self, info_queue, card)
		return { vars = { card.ability.extra.percent } }
	end,
	calculate = function(self, card, context)
		if context.end_of_round and context.game_over and context.main_eval and not context.blueprint
			and G.GAME.chips >= G.GAME.blind.chips * card.ability.extra.percent / 100 then
			G.E_MANAGER:add_event(Event({
				func = function()
					card:start_dissolve()
					return true
				end,
			}))
			return { message = localize('k_saved_ex'), saved = 'k_coop_second_wind_saved', colour = G.C.RED }
		end
	end,
})

-- Bridge copies a hidden instance of the partner's rightmost joker, rebuilt
-- whenever that joker changes.
function COOP.TEAM.bridge_target()
	local p = COOP.PV.partner
	if not p or not p.jokers or p.jokers == '' then
		return nil
	end
	local last = p.jokers:match('([^;]+)$')
	local key = last and last:match('^[^|]*|[^|]*|([^|]*)')
	if not key or not G.P_CENTERS[key] or key == 'j_coop_bridge' then
		return nil
	end
	local TM = COOP.TEAM
	if TM.bridge_building then
		return nil -- creating/removing the copy asks find_card, which asks us: don't recurse
	end
	if not TM.bridge_card or TM.bridge_card.config.center.key ~= key then
		TM.bridge_building = true
		local ok, err = pcall(function()
			if TM.bridge_card then
				TM.bridge_card:remove()
				TM.bridge_card = nil
			end
			TM.bridge_card = Card(-30, -30, G.CARD_W, G.CARD_H, nil, G.P_CENTERS[key], { bypass_discovery_center = true, bypass_discovery_ui = true })
			TM.bridge_card.coop_display = true
		end)
		TM.bridge_building = false
		if not ok then
			sendWarnMessage('bridge copy failed: ' .. tostring(err), COOP.id)
			return nil
		end
	end
	return TM.bridge_card
end
