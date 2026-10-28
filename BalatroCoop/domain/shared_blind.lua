-- Shared blind, played in turns.
--
-- Both players run the same seed, so they face the same blinds and bosses.
-- Each has their own deck, hand, jokers and hands/discards, but the blind is
-- beaten by the TEAM: G.GAME.chips shows own score + partner score, and the
-- requirement is multiplied by COOP.BLIND_MULT.
--
-- Players alternate: one hand per turn (discards only on your own turn).
-- Whose turn it is follows from how many hands each has played this blind,
-- so it needs no extra messages:
--   * the starter is the host on odd rounds and the guest on even rounds
--   * if one player is out of hands, the other keeps playing
--   * team total >= requirement -> both win the blind
--   * both out of hands and short -> both lose the run
--
-- A blind is identified by G.GAME.round: blind choices are shared, so both
-- players always have the same round number.
--
-- Deadlock guard: the heartbeat also says whose turn each side thinks it is.
-- If both sides sit idle, each believing it's the other's turn, for a few
-- seconds, the player whose turn it is by the counts takes it (SB.force); if
-- that doesn't settle it, the host does. "Unstick" in the team panel does the
-- same by hand and also clears a partner hand stuck on our board.

COOP.SB = COOP.SB or {}
local SB = COOP.SB

COOP.BLIND_MULT = 1.75

function SB.reset()
	-- reports[round] = { total, hands_left, played, ready, last_hand }
	SB.reports = {}
	SB.applied = 0
	SB.applied_round = nil
	SB.sent_ready = nil
	SB.last_turn_mine = nil
	SB.partner_last_hand = nil
	SB.own_round, SB.own_before = nil, 0
	SB.ease_pending = 0 -- partner points queued but not yet in G.GAME.chips
	SB.partner_blind = {} -- round -> partner's blind state (disabled, chips)
	SB.ended_round = nil -- vanilla end_round already ran for this round
	SB.end_deferred = false
	SB.force = nil -- { round, played }: our turn, whatever else says, until we play
	SB.stuck_since = nil -- both idle and nobody's turn since then
	SB.state_stuck_since = nil -- our own game sitting in DRAW_TO_HAND with nothing queued
end
SB.reset()

local function in_blind()
	return G.GAME and G.GAME.blind and G.GAME.blind.in_blind
end

function SB.round()
	return G.GAME and G.GAME.round or 0
end

local function report(round)
	round = round or SB.round()
	SB.reports[round] = SB.reports[round] or { total = 0, hands_left = 1, played = 0 }
	return SB.reports[round]
end

function SB.partner_ready()
	local r = SB.reports[SB.round()]
	return r ~= nil and r.ready
end

function SB.partner_hands_left()
	return report().hands_left
end

function SB.partner_hands_played()
	return report().played
end

local function my_hands_left()
	return G.GAME.current_round.hands_left
end

function SB.partner_done()
	return SB.partner_ready() and SB.partner_hands_left() < 1
end

function SB.i_start()
	if COOP.TEST then
		return true -- the mirror only repeats us: we always open, it follows
	end
	local lobby = COOP.get_lobby()
	local host = lobby and lobby.is_host
	if SB.round() % 2 == 1 then
		return host
	end
	return not host
end

-- true / false, or nil while waiting for the partner to enter the blind
function SB.my_turn()
	if not in_blind() or not SB.partner_ready() then
		return nil
	end
	local mine, theirs = my_hands_left(), SB.partner_hands_left()
	if mine < 1 then
		return false
	end
	local f = SB.force
	if f and f.round == SB.round() and f.played == G.GAME.current_round.hands_played then
		return true
	end
	if COOP.PV.partner_playing() then
		return false -- their hand is still being shown and scored on our board
	end
	if theirs < 1 or not COOP.MODES.on('alternate_turns') then
		return true -- partner is done, or both play at will
	end
	local my_played, their_played = G.GAME.current_round.hands_played, SB.partner_hands_played()
	if SB.i_start() then
		return my_played <= their_played
	end
	return my_played < their_played
end

-- Whose turn it is by the hand counts alone (ignores replays on the board).
local function my_turn_by_counts()
	if my_hands_left() < 1 then
		return false
	end
	if SB.partner_hands_left() < 1 or not COOP.MODES.on('alternate_turns') then
		return true
	end
	local my_played, their_played = G.GAME.current_round.hands_played, SB.partner_hands_played()
	if SB.i_start() then
		return my_played <= their_played
	end
	return my_played < their_played
end

local function is_host()
	local lobby = COOP.get_lobby()
	return lobby and lobby.is_host
end

-- Take the turn now; clears whatever partner hand is still shown on our board.
function SB.take_turn(why)
	COOP.debug('turn: taking it (%s); my played=%s their played=%s', tostring(why),
		tostring(G.GAME.current_round.hands_played), tostring(SB.partner_hands_played()))
	SB.force = { round = SB.round(), played = G.GAME.current_round.hands_played }
	SB.stuck_since = nil
	COOP.PV.clear_stuck_play()
end

-- "Unstick" button: take the turn and tell the partner to let go of theirs.
function SB.unstick()
	if G.STATE == G.STATES.DRAW_TO_HAND and #(G.E_MANAGER.queues.base or {}) == 0 then
		-- our own game stopped between hands: pick up from selecting cards
		G.STATE = G.STATES.SELECTING_HAND
		G.STATE_COMPLETE = false
	end
	SB.state_stuck_since = nil
	if my_hands_left() > 0 then
		SB.take_turn('button')
	end
	COOP.send('unstick', { round = SB.round() })
end

function SB.on_partner_unstick(round)
	if round == SB.round() then
		COOP.debug('turn: partner pressed unstick')
		SB.force = nil
		SB.stuck_since = nil
		COOP.PV.clear_stuck_play()
	end
end

-- True when the game seems stuck long enough to offer the button.
function SB.looks_stuck()
	local now = G.TIMERS.REAL
	return (SB.stuck_since and now - SB.stuck_since > 4) or (SB.state_stuck_since and now - SB.state_stuck_since > 5) or false
end

function SB.own_score()
	if SB.applied_round ~= SB.round() then
		return G.GAME.chips or 0
	end
	return (G.GAME.chips or 0) - SB.applied
end

-- What the blind counts: own + partner, each capped (see domain/synergy.lua).
function SB.partner_counted_score()
	return SB.applied_round == SB.round() and SB.applied or 0
end

function SB.counted_score()
	if COOP.boss_is and COOP.boss_is('bl_coop_tyrant') then
		-- The Tyrant: only the weaker score counts, twice
		return 2 * math.min(math.max(SB.own_score(), 0), SB.partner_counted_score())
	end
	if not COOP.MODES.on('share_cap') then
		return G.GAME.chips
	end
	return COOP.SYN.counted(math.max(SB.own_score(), 0), SB.partner_counted_score())
end

-- once per blind: the team's win effect (ui/fx.lua)
function SB.celebrate()
	local round = SB.round()
	if SB.celebrated == round then
		return
	end
	SB.celebrated = round
	local margin = G.GAME.blind.chips > 0 and SB.counted_score() / G.GAME.blind.chips or 1
	pcall(COOP.FX.team_win, margin)
end

function SB.team_beat_blind()
	return SB.counted_score() - G.GAME.blind.chips >= 0
end

-- Adds whatever the partner scored since last time onto our chips counter.
function SB.apply_partner_score()
	local round = SB.round()
	if SB.applied_round ~= round then
		SB.applied_round = round
		SB.applied = 0
	end
	local r = SB.reports[round]
	if not r then
		return
	end
	local diff = r.total - SB.applied
	if diff ~= 0 then
		SB.applied = r.total
		-- Queued behind the partner's replayed scoring, then counted up into
		-- the round score the same way our own hands are. Until it has landed
		-- in G.GAME.chips the blind must not be decided (SB.ease_pending).
		SB.ease_pending = (SB.ease_pending or 0) + 1
		G.E_MANAGER:add_event(Event({
			blockable = false, -- don't wait behind the replayed popups
			func = function()
				-- front-inserted, so they run right after this one, in reverse
				-- order of insertion: the ease first, then the flag is cleared
				G.E_MANAGER:add_event(Event({
					func = function()
						SB.ease_pending = math.max((SB.ease_pending or 1) - 1, 0)
						return true
					end,
				}), nil, true)
				G.E_MANAGER:add_event(Event({
					trigger = 'ease',
					ref_table = G.GAME,
					ref_value = 'chips',
					ease_to = G.GAME.chips + diff, -- chips as they are now, at this point of the queue
					delay = 0.35,
					func = function(t)
						return math.floor(t)
					end,
				}), nil, true)
				if diff > 0 then
					pcall(COOP.FX.score_in, diff) -- flies in while it counts up
					-- the amount itself flies in as a label (ui/fx.lua): no pop-up on top
					COOP.on_partner_scored(diff)
				end
				return true
			end,
		}))
	end
end

-- Network ---------------------------------------------------------------

-- Heartbeat: the partner's full state in this blind, sent every second while
-- they sit in it. Counts are absolute, so a lost message (server rate limit,
-- reconnect) is repaired by the next heartbeat instead of locking the turns.
function SB.on_partner_ready(round, hands_left, played, total, turn)
	local r = report(round)
	r.ready = true
	r.turn = turn -- 1: they think it's theirs, 0: not, -1: they're waiting
	r.beat_at = G.TIMERS.REAL
	r.hands_left = hands_left
	r.played = math.max(r.played, played or 0)
	r.total = math.max(r.total, total or 0)
end

-- The partner's hand total shows on their HUD (streamed live, see
-- ui/partner_view.lua) a good while before their report arrives: count it
-- into the round score right then. The report only corrects the difference.
function SB.prelanding(hand_total)
	if not in_blind() or not hand_total or hand_total <= 0 then
		return
	end
	local round = SB.round()
	if SB.applied_round ~= round then
		SB.applied_round = round
		SB.applied = 0
	end
	local r = report(round)
	r.total = math.max(r.total, (SB.applied or 0) + math.floor(hand_total))
end

function SB.on_partner_report(round, total, hands_left, hand, played)
	COOP.debug('partner report: round=%s total=%s hand=%s played=%s (my round=%s); live score msgs received=%s', tostring(round), tostring(total), tostring(hand), tostring(played), tostring(SB.round()), tostring(COOP.PV.ht_recv or 0))
	COOP.PV.ht_recv = 0
	local r = report(round)
	if hand and hand ~= '' then
		-- score of that single hand, for Chain
		COOP.TEAM.partner_last_score = total - (r.total or 0)
	end
	r.ready = true
	r.total = math.max(r.total, total)
	r.hands_left = hands_left
	r.played = math.max(r.played + (played and 0 or 1), played or 0)
	r.last_hand = hand
	if hand and hand ~= '' then
		SB.partner_last_hand = hand
	end
end

function SB.send_report(hand)
	COOP.send('score', {
		round = SB.round(),
		total = math.floor(SB.own_score()),
		hands_left = my_hands_left(),
		hand = hand or '',
		mult = COOP.TEAM.my_mult or 0,
		played = G.GAME.current_round.hands_played or 0,
	})
	COOP.TEAM.my_mult = 0
end

-- Everything the partner scored in the current blind so far.
function SB.partner_round_total()
	local r = SB.reports and SB.reports[SB.round()]
	return r and r.total or 0
end

-- The poker hand the partner played last in the current blind, if any.
function SB.partner_hand_this_blind()
	local r = SB.reports[SB.round()]
	if r and r.last_hand and r.last_hand ~= '' then
		return r.last_hand
	end
end

-- Blind state ---------------------------------------------------------------
--
-- Each player has their own copy of the blind. A boss disabled on one side
-- (Chicot, Luchador...) or a requirement changed by an effect must change on
-- the other side too, or the two would chase different targets and end the
-- blind at different times. Both sides converge: disabled wins, lower
-- requirement wins.

local function blind_signature()
	return tostring(G.GAME.blind.disabled and true or false) .. ':' .. tostring(G.GAME.blind.chips)
end

-- Sent when it changes and repeated every 2s: the partner may not be in the
-- blind yet when it changes (Chicot disables the boss the moment it starts).
function SB.sync_blind()
	local sig = SB.round() .. '|' .. blind_signature()
	local now = G.TIMERS.REAL
	if sig ~= SB.last_blind_sig or now - (SB.blind_sent_at or 0) >= 2 then
		SB.last_blind_sig = sig
		SB.blind_sent_at = now
		COOP.send('blind_state', { round = SB.round(), disabled = G.GAME.blind.disabled and true or false, chips = G.GAME.blind.chips or 0 })
	end
end

-- Kept per round and applied once we are in that blind ourselves.
function SB.on_partner_blind(round, disabled, chips)
	SB.partner_blind = SB.partner_blind or {}
	local prev = SB.partner_blind[round] or {}
	SB.partner_blind[round] = {
		disabled = prev.disabled or disabled,
		chips = (prev.chips and chips and chips > 0) and math.min(prev.chips, chips) or (chips and chips > 0 and chips) or prev.chips,
	}
end

function SB.apply_partner_blind()
	local pb = SB.partner_blind and SB.partner_blind[SB.round()]
	if not pb or not in_blind() then
		return
	end
	local blind = G.GAME.blind
	if pb.disabled and not blind.disabled then
		blind:disable()
		COOP.popup(localize('k_coop_boss_disabled'), G.C.GREEN)
	end
	if pb.chips and pb.chips < blind.chips then
		blind.chips = pb.chips
		blind.chip_text = number_format(pb.chips)
	end
end

-- Per frame ---------------------------------------------------------------

local function end_blind()
	G.STATE = G.STATES.NEW_ROUND
	G.STATE_COMPLETE = false
end

function SB.update()
	if not in_blind() then
		return
	end
	SB.apply_partner_blind()
	SB.sync_blind()
	local now = G.TIMERS.REAL
	-- our own game parked between hands with nothing left to run
	if G.STATE == G.STATES.DRAW_TO_HAND and #(G.E_MANAGER.queues.base or {}) == 0 then
		SB.state_stuck_since = SB.state_stuck_since or now
	else
		SB.state_stuck_since = nil
	end
	if G.STATE ~= G.STATES.SELECTING_HAND or G.CONTROLLER.locked then
		SB.stuck_since = nil
		return
	end

	local round = SB.round()
	local turn = SB.my_turn()
	if SB.sent_ready ~= round or now - (SB.last_heartbeat or 0) >= 1 then
		SB.sent_ready = round
		SB.last_heartbeat = now
		COOP.send('ready_blind', {
			round = round,
			hands_left = my_hands_left(),
			played = G.GAME.current_round.hands_played or 0,
			total = math.floor(SB.own_score()),
			turn = turn == true and 1 or turn == false and 0 or -1,
		})
	end

	-- deadlock: both idle in this blind, neither thinks it's their turn
	local r = SB.reports[round]
	local partner_idle_not_turn = r and r.ready and r.turn ~= nil and r.turn ~= 1 and now - (r.beat_at or 0) < 3
	if turn ~= true and my_hands_left() > 0 and partner_idle_not_turn and SB.partner_hands_left() > 0 then
		SB.stuck_since = SB.stuck_since or now
		local stuck_for = now - SB.stuck_since
		if stuck_for > 6 and my_turn_by_counts() then
			SB.take_turn('deadlock, mine by counts')
		elseif stuck_for > 12 and is_host() then
			SB.take_turn('deadlock, host decides')
		end
	else
		SB.stuck_since = nil
	end

	-- Only touch G.GAME.chips while nothing is scoring: a hand's score is an
	-- 'ease' event that would overwrite a change made in the middle of it.
	SB.apply_partner_score()
	if (SB.ease_pending or 0) > 0 then
		return -- partner's points are still being counted in: decide afterwards
	end

	if SB.team_beat_blind() then
		SB.celebrate()
		return end_blind()
	end
	if my_hands_left() < 1 and SB.partner_done() then
		return end_blind() -- nobody has hands left: the run is lost
	end

	local mine = SB.my_turn()
	if mine ~= SB.last_turn_mine then
		SB.last_turn_mine = mine
		-- queued: "your turn" only after the partner's hand finished replaying
		if mine == true then
			COOP.popup(localize('k_coop_your_turn'), G.C.GREEN, true)
			G.E_MANAGER:add_event(Event({
				func = function()
					play_sound('timpani')
					pcall(COOP.FX.your_turn)
					return true
				end,
			}))
		elseif mine == false and my_hands_left() > 0 then
			COOP.popup(localize('k_coop_partner_turn'), G.C.SECONDARY_SET.Planet, true)
		elseif mine == nil then
			COOP.popup(localize('k_coop_waiting'), G.C.SECONDARY_SET.Planet, true)
		end
	end
end

-- Replacement for the event body inside Game:update_hand_played.
local function debug_team_row()
	local keys = {}
	for _, c in ipairs(G.coop_team and G.coop_team.cards or {}) do
		keys[#keys + 1] = c.config.center.key .. (c.debuff and '(debuffed)' or '')
	end
	local scored = false
	for _, area in ipairs(SMODS.get_card_areas('jokers')) do
		if area == G.coop_team then
			scored = true
		end
	end
	COOP.debug('hand %s played; team row=[%s] in scoring areas=%s; partner last=%s; my mult=%s; live score msgs sent=%s',
		tostring(G.GAME.last_hand_played), table.concat(keys, ','), tostring(scored),
		tostring(SB.partner_hand_this_blind()), tostring(COOP.TEAM.my_mult), tostring(COOP.PV.ht_sent or 0))
	COOP.PV.ht_sent = 0
end

function SB.after_hand_scored()
	pcall(debug_team_row)
	-- this hand's own score, for Chain
	local own = math.floor(SB.own_score())
	if SB.own_round ~= SB.round() then
		SB.own_round, SB.own_before = SB.round(), 0
	end
	pcall(COOP.TEAM.after_my_hand, own - SB.own_before)
	COOP.STATUS.last_me = { hand = G.GAME.last_hand_played, score = own - SB.own_before, mult = COOP.TEAM.my_mult or 0 }
	SB.own_before = own
	SB.send_report(G.GAME.last_hand_played)
	SB.apply_partner_score() -- scoring has finished, safe to add what arrived meanwhile

	if SB.team_beat_blind() then
		SB.celebrate()
		G.STATE = G.STATES.NEW_ROUND
	elseif my_hands_left() < 1 and SB.partner_done() then
		G.STATE = G.STATES.NEW_ROUND -- nobody has hands left: run is lost
	else
		-- even with 0 hands left: draw back up and watch the partner play
		G.STATE = G.STATES.DRAW_TO_HAND
	end
	G.STATE_COMPLETE = false
	return true
end

local function disable(e)
	e.config.colour = G.C.UI.BACKGROUND_INACTIVE
	e.config.button = nil
end

function SB.install_hooks()
	local update_hand_played_ref = Game.update_hand_played
	function Game:update_hand_played(dt)
		if not COOP.is_active() then
			return update_hand_played_ref(self, dt)
		end
		if self.buttons then
			self.buttons:remove()
			self.buttons = nil
		end
		if self.shop then
			self.shop:remove()
			self.shop = nil
		end
		if not G.STATE_COMPLETE then
			G.STATE_COMPLETE = true
			G.E_MANAGER:add_event(Event({
				trigger = 'immediate',
				func = SB.after_hand_scored,
			}))
		end
	end

	local can_play_ref = G.FUNCS.can_play
	G.FUNCS.can_play = function(e)
		can_play_ref(e)
		if COOP.is_active() and SB.my_turn() ~= true then
			disable(e)
		end
	end

	local can_discard_ref = G.FUNCS.can_discard
	G.FUNCS.can_discard = function(e)
		can_discard_ref(e)
		if COOP.is_active() and SB.my_turn() ~= true then
			disable(e)
		end
	end

	-- Vanilla ends the round as soon as hand and deck are both empty, which
	-- would lose the run while the partner can still score. In co-op an empty
	-- deck just means "out of hands": we wait and the partner plays on. The
	-- blind only really ends once the team won or nobody has hands left.
	local end_round_ref = end_round
	function end_round(...)
		if COOP.is_active() then
			-- Once per round. Out of cards, vanilla calls end_round every frame,
			-- and our own NEW_ROUND would call it once more: a second run would
			-- advance the ante twice and pay the cash-out twice.
			if SB.ended_round == SB.round() then
				return
			end
			-- The partner's last points are still easing into G.GAME.chips:
			-- decide once they are in (queued behind that ease).
			if in_blind() and (SB.ease_pending or 0) > 0 then
				if not SB.end_deferred then -- one deferred call, not one per frame
					SB.end_deferred = true
					local args = { ... }
					G.E_MANAGER:add_event(Event({
						func = function()
							SB.end_deferred = false
							end_round(unpack(args))
							return true
						end,
					}))
				end
				return
			end
		end
		if COOP.is_active() and in_blind() and not SB.team_beat_blind() and not SB.partner_done() then
			if my_hands_left() > 0 then
				G.GAME.current_round.hands_left = 0
				SB.send_report('')
				COOP.popup(localize('k_coop_out_of_cards'), G.C.RED)
			end
			return
		end
		-- vanilla decides win/loss from G.GAME.chips; with the share cap the
		-- raw sum can be over the blind while the counted score isn't
		if COOP.is_active() and in_blind() and not SB.team_beat_blind() then
			G.GAME.chips = math.floor(SB.counted_score())
		end
		if COOP.is_active() then
			SB.ended_round = SB.round()
		end
		return end_round_ref(...)
	end

	-- bigger blinds: two players score them
	local set_blind_ref = Blind.set_blind
	function Blind:set_blind(blind, reset, silent)
		set_blind_ref(self, blind, reset, silent)
		if COOP.is_active() and blind and not reset and self.chips and self.chips > 0 then
			local mult = COOP.BLIND_MULT * COOP.CHALLENGE.blind_factor()
			if self.boss and COOP.MODES.on('evil_bosses') then
				-- "evil bosses" mode: harder bosses, double reward
				mult = mult * 1.5
				self.dollars = (self.dollars or 0) * 2
			end
			self.chips = math.floor(self.chips * mult)
			self.chip_text = number_format(self.chips)
		end
	end
end
