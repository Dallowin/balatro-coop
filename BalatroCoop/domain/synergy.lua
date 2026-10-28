-- Core co-op synergy, no jokers needed. It exists so that one strong player
-- can't carry the run alone, and so that the two builds feed each other.
--
-- Relay ("Передача"): COOP.RELAY_SHARE of your hand's final Mult becomes +Mult
--   at the very start of the partner's next hand (so their jokers multiply
--   it too). A mult build powers up a chips build, and the other way round.
--
-- Contribution cap ("Доля"): one player's score counts for at most
--   COOP.SHARE_CAP of the blind. The other must bring the rest.
--
-- Resonance ("Резонанс"): a hand that scores a card of the same rank as one
--   the partner just played raises a shared resonance level: X1.25, X1.5...
--   A hand without a shared rank breaks it.

COOP.SYN = COOP.SYN or {}
local SY = COOP.SYN

COOP.RELAY_SHARE = 0.35
COOP.SHARE_CAP = 0.7
COOP.RESONANCE_STEP = 0.25

function SY.reset()
	SY.relay = 0 -- +Mult waiting for our next hand
	SY.resonance = 0 -- shared level; X(1 + level * step)
	SY.partner_ranks = {} -- ranks in the partner's last played hand
	SY.this_hand = nil -- resonance decided for the hand being scored
end
SY.reset()

local function rank_of(card_key)
	return card_key and card_key:match('_(.+)$')
end

function SY.resonance_mult(level)
	return 1 + (level or SY.resonance) * COOP.RESONANCE_STEP
end

-- Partner -> us -----------------------------------------------------------------

function SY.on_partner_play(cards_code)
	SY.partner_ranks = {}
	for code in string.gmatch(cards_code or '', '[^;]+') do
		local front = code:match('^[^|]*|([^|]*)')
		local r = rank_of(front)
		if r then
			SY.partner_ranks[r] = true
		end
	end
end

function SY.on_partner_mult(mult)
	if type(mult) == 'number' and mult > 0 then
		SY.relay = math.floor(mult * COOP.RELAY_SHARE)
	end
end

function SY.on_resonance(level)
	SY.resonance = level
end

-- Scoring (called by SMODS through COOP.calculate) ------------------------------

local function shares_rank(scoring_hand)
	for _, c in ipairs(scoring_hand or {}) do
		local r = rank_of(c.config and c.config.card_key)
		if r and SY.partner_ranks[r] then
			return true
		end
	end
	return false
end

function SY.calculate(context)
	if context.initial_scoring_step then
		-- decide resonance once for this hand
		if next(SY.partner_ranks) then
			SY.this_hand = shares_rank(context.scoring_hand) and SY.resonance + 1 or 0
		else
			SY.this_hand = SY.resonance -- partner hasn't played yet: keep it
		end
		if SY.relay > 0 then
			return {
				mult = SY.relay,
				message = localize({ type = 'variable', key = 'coop_relay_msg', vars = { SY.relay } }),
				colour = G.C.MULT,
			}
		end
	end
	if context.main_scoring and SY.this_hand and SY.this_hand > 0 then
		local x = SY.resonance_mult(SY.this_hand)
		return {
			xmult = x,
			message = localize({ type = 'variable', key = 'coop_resonance_msg', vars = { x } }),
			colour = G.C.PURPLE,
		}
	end
	if context.after then
		SY.relay = 0
		if SY.this_hand then
			SY.resonance = SY.this_hand
			SY.this_hand = nil
			COOP.send('resonance', { level = SY.resonance })
		end
	end
end

-- Contribution cap ---------------------------------------------------------------

function SY.cap()
	return (G.GAME and G.GAME.blind and G.GAME.blind.chips or 0) * COOP.SHARE_CAP
end

-- Team score as the blind counts it: each player at most SHARE_CAP of it.
function SY.counted(own, partner)
	local cap = SY.cap()
	return math.min(own, cap) + math.min(partner, cap)
end
