-- Co-op boss blinds: they only appear in co-op runs and hit the teamwork,
-- not just the cards. Both players run the same seed, so both always face the
-- same boss. Requirement multipliers are tuned so each is about as hard as an
-- ordinary boss (the co-op difficulty multiplier comes on top, as usual).
--
--   The Envy     cards of the ranks your partner just played are debuffed
--   The Shackle  play exactly as many cards as your partner's last hand
--   The Tyrant   only the weaker player's score counts (doubled)
--   The Fog      you can't see your partner's board this blind

local function coop_boss(def)
	def.atlas = 'blind_chips'
	def.prefix_config = { atlas = false } -- vanilla boss chips
	def.boss = def.boss or { min = 1, max = 10 }
	def.in_pool = function()
		return COOP.is_active()
	end
	SMODS.Blind(def)
end

local function partner_play_this_blind()
	local pp = COOP.SYN.partner_play
	return pp and pp.round == COOP.SB.round() and pp or nil
end

coop_boss({
	key = 'envy',
	pos = { x = 0, y = 17 },
	boss_colour = HEX('3fae5a'),
	mult = 2,
	dollars = 5,
	recalc_debuff = function(self, card, from_blind)
		local pp = partner_play_this_blind()
		return pp and card.base and card.base.value and pp.ranks[card.base.value] or false
	end,
})

coop_boss({
	key = 'shackle',
	pos = { x = 0, y = 8 },
	boss_colour = HEX('6b6b7a'),
	mult = 1.75, -- a whole hand type can be ruled out: a little lower requirement
	dollars = 5,
	debuff_hand = function(self, cards, hand, handname, check)
		local pp = partner_play_this_blind()
		return pp ~= nil and #cards ~= pp.count
	end,
	loc_vars = function(self)
		local pp = partner_play_this_blind()
		return { vars = { pp and pp.count or '?' } }
	end,
	collection_loc_vars = function(self)
		return { vars = { '?' } }
	end,
})

coop_boss({
	key = 'tyrant',
	pos = { x = 0, y = 16 },
	boss_colour = HEX('9c3b3b'),
	mult = 1.5, -- only twice the weaker score counts: the requirement is lower
	dollars = 6,
	boss = { min = 2, max = 10 },
})

coop_boss({
	key = 'fog',
	pos = { x = 0, y = 6 },
	boss_colour = HEX('7d8fa0'),
	mult = 2,
	dollars = 5,
})

function COOP.boss_is(key)
	local blind = G.GAME and G.GAME.blind
	return blind and blind.in_blind and not blind.disabled and blind.config and blind.config.blind
		and blind.config.blind.key == key or false
end

-- The Envy: a new partner hand changes what is debuffed
function COOP.refresh_envy()
	if not COOP.boss_is('bl_coop_envy') then
		return
	end
	for _, card in ipairs(G.playing_cards or {}) do
		if SMODS.recalc_debuff then
			SMODS.recalc_debuff(card)
		end
	end
end
