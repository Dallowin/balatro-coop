-- Optional co-op rules, each its own lobby option, both off by default.
-- (Passing Mult to the partner is the Echo team joker's job.)
--
-- Resonance ("Резонанс"): the more evenly the two of you have scored in this
--   blind, the bigger an XMult on every hand: up to X(1 + RESONANCE_MAX) when
--   both brought the same. It doesn't care what you play, so the builds can
--   be as different as you like; it only rewards both pulling their weight.
--
-- Contribution cap ("Доля", its own lobby option, off by default): one
--   player's score counts for at most COOP.SHARE_CAP of the blind.

COOP.SYN = COOP.SYN or {}
local SY = COOP.SYN

COOP.SHARE_CAP = 0.7
COOP.RESONANCE_MAX = 0.5

function SY.reset()
	SY.this_hand = nil -- resonance X decided for the hand being scored
end
SY.reset()

-- Resonance X from both players' scores in this blind so far: 1 + MAX times
-- how even they are (smaller / bigger), in steps of 0.05. X1 until both scored.
function SY.resonance_mult()
	if not (COOP.SB and G.GAME and G.GAME.blind and G.GAME.blind.in_blind) then
		return 1
	end
	local mine = math.max(COOP.SB.own_score(), 0)
	local theirs = math.max(COOP.SB.partner_round_total(), 0)
	if mine <= 0 or theirs <= 0 then
		return 1
	end
	local balance = math.min(mine, theirs) / math.max(mine, theirs)
	return 1 + math.floor(balance * COOP.RESONANCE_MAX * 20 + 0.5) / 20
end

-- Partner -> us -----------------------------------------------------------------

-- The partner's last played hand (for co-op bosses): round, card count, ranks.
function SY.on_partner_play(cards_code)
	local pp = { round = COOP.SB.round(), count = 0, ranks = {} }
	for code in string.gmatch(cards_code or '', '[^;]+') do
		pp.count = pp.count + 1
		local front = code:match('^[^|]*|([^|]*)')
		local card = front and G.P_CARDS[front]
		if card and card.value then
			pp.ranks[card.value] = true
		end
	end
	SY.partner_play = pp
	if COOP.refresh_envy then
		COOP.refresh_envy()
	end
end

function SY.on_resonance(level) end -- older versions sent their rank resonance

-- Scoring (called by SMODS through COOP.calculate) ------------------------------

function SY.calculate(context)
	if context.initial_scoring_step then
		-- decide resonance once for this hand, from the scores before it
		SY.this_hand = SY.resonance_mult()
	end
	if context.main_scoring and SY.this_hand and SY.this_hand > 1 then
		local x = SY.this_hand
		SY.this_hand = nil -- once per hand
		return {
			xmult = x,
			message = localize({ type = 'variable', key = 'coop_resonance_msg', vars = { x } }),
			colour = G.C.PURPLE,
		}
	end
	if context.after then
		SY.this_hand = nil
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
