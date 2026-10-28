-- Co-op jokers. They only show up in co-op runs and react to what the
-- partner does. Art reuses vanilla sprites for now.

local function coop_pool()
	return COOP.is_active()
end

-- Relay: +4 Mult for each hand the partner played this blind.
SMODS.Joker({
	key = 'relay',
	atlas = 'Joker',
	prefix_config = { atlas = false }, -- vanilla joker sheet, not coop_Joker
	pos = { x = 0, y = 15 },
	rarity = 1,
	cost = 5,
	blueprint_compat = true,
	config = { extra = { mult = 4 } },
	in_pool = coop_pool,
	loc_vars = function(self, info_queue, card)
		local played = COOP.SB and COOP.SB.partner_hands_played() or 0
		return { vars = { card.ability.extra.mult, card.ability.extra.mult * played } }
	end,
	calculate = function(self, card, context)
		if context.joker_main then
			local played = COOP.SB.partner_hands_played()
			if played > 0 then
				return { mult = card.ability.extra.mult * played }
			end
		end
	end,
})

-- Kindred Spirits: X2 Mult if you play the same poker hand the partner played last.
SMODS.Joker({
	key = 'kindred',
	atlas = 'Joker',
	prefix_config = { atlas = false }, -- vanilla joker sheet, not coop_Joker
	pos = { x = 5, y = 4 },
	rarity = 2,
	cost = 7,
	blueprint_compat = true,
	config = { extra = { xmult = 2 } },
	in_pool = coop_pool,
	loc_vars = function(self, info_queue, card)
		local last = COOP.SB and COOP.SB.partner_last_hand
		return { vars = { card.ability.extra.xmult, last and localize(last, 'poker_hands') or '-' } }
	end,
	calculate = function(self, card, context)
		if context.joker_main and COOP.SB.partner_last_hand and context.scoring_name == COOP.SB.partner_last_hand then
			return { xmult = card.ability.extra.xmult }
		end
	end,
})

-- Shared Pot: end of round, $2 into the shared wallet for each hand the
-- partner played this blind.
SMODS.Joker({
	key = 'pot',
	atlas = 'Joker',
	prefix_config = { atlas = false }, -- vanilla joker sheet, not coop_Joker
	pos = { x = 3, y = 13 },
	rarity = 1,
	cost = 5,
	blueprint_compat = false,
	config = { extra = { dollars = 2 } },
	in_pool = coop_pool,
	loc_vars = function(self, info_queue, card)
		local played = COOP.SB and COOP.SB.partner_hands_played() or 0
		return { vars = { card.ability.extra.dollars, card.ability.extra.dollars * played } }
	end,
	calc_dollar_bonus = function(self, card)
		local bonus = card.ability.extra.dollars * COOP.SB.partner_hands_played()
		if bonus > 0 then
			return bonus
		end
	end,
})

-- Assist: when the partner scores, gain +Chips equal to 10% of their score,
-- used up by your next hand.
SMODS.Joker({
	key = 'assist',
	atlas = 'Joker',
	prefix_config = { atlas = false }, -- vanilla joker sheet, not coop_Joker
	pos = { x = 0, y = 11 },
	rarity = 2,
	cost = 6,
	blueprint_compat = true,
	config = { extra = { percent = 10, chips = 0 } },
	in_pool = coop_pool,
	loc_vars = function(self, info_queue, card)
		return { vars = { card.ability.extra.percent, card.ability.extra.chips } }
	end,
	calculate = function(self, card, context)
		if context.joker_main and card.ability.extra.chips > 0 then
			return { chips = card.ability.extra.chips }
		end
		if context.after and not context.blueprint then
			card.ability.extra.chips = 0
		end
	end,
})

-- Called when the partner's score lands on our counter.
function COOP.on_partner_scored(amount)
	if not G.jokers then
		return
	end
	for _, card in ipairs(G.jokers.cards) do
		if card.config.center.key == 'j_coop_assist' then
			local gain = math.floor(amount * card.ability.extra.percent / 100)
			card.ability.extra.chips = card.ability.extra.chips + gain
			card_eval_status_text(card, 'extra', nil, nil, nil, { message = '+' .. number_format(gain), colour = G.C.CHIPS })
		end
	end
end
