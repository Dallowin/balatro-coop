-- Team panel during a run, above the deck on the right: how much each player
-- has put into the blind (and the cap), the Mult relay waiting for you, the
-- resonance level, the last chat lines, and buttons for chat and the rules.

COOP.STATUS = COOP.STATUS or {}
local ST = COOP.STATUS

ST.text = { counted = '', need = '', shares = '', last_me = '', last_partner = '', synergy = '', chat1 = '', chat2 = '' }

local function line(key, colour, scale)
	return { n = G.UIT.R, config = { align = 'cl', padding = 0.035 }, nodes = {
		{ n = G.UIT.T, config = { ref_table = ST.text, ref_value = key, scale = scale or 0.3, colour = colour or G.C.WHITE, shadow = true } },
	} }
end

-- one block of the panel: a slightly darker rounded box with inner padding
local function block(rows)
	return { n = G.UIT.R, config = { align = 'cm', padding = 0.05 }, nodes = {
		{ n = G.UIT.C, config = { align = 'cl', colour = { 0, 0, 0, 0.25 }, r = 0.08, padding = 0.1, minw = 3.9 }, nodes = rows },
	} }
end

local function create()
	ST.box = UIBox({
		definition = {
			n = G.UIT.ROOT,
			config = { align = 'cm', colour = { 0, 0, 0, 0.35 }, r = 0.12, padding = 0.12, minw = 4.2 },
			nodes = {
				block({
					line('counted', G.C.GOLD, 0.32),
					line('need', G.C.RED, 0.29),
					line('shares', G.C.WHITE, 0.29),
				}),
				block({
					line('last_me', G.C.CHIPS, 0.28),
					line('last_partner', G.C.CHIPS, 0.28),
					line('synergy', G.C.SECONDARY_SET.Planet, 0.28),
				}),
				block({
					line('chat1', G.C.UI.TEXT_LIGHT, 0.26),
					line('chat2', G.C.UI.TEXT_LIGHT, 0.26),
				}),
				{ n = G.UIT.R, config = { align = 'cm', padding = 0.08 }, nodes = {
					UIBox_button({ button = 'coop_chat_open', label = { localize('k_coop_chat') }, minw = 1.7, minh = 0.45, scale = 0.32, colour = G.C.SECONDARY_SET.Planet }),
					{ n = G.UIT.B, config = { w = 0.15, h = 0.1 } },
					UIBox_button({ button = 'coop_rules', label = { localize('k_coop_rules') }, minw = 1.7, minh = 0.45, scale = 0.32, colour = G.C.ORANGE }),
				} },
			},
		},
		config = { align = 'tm', offset = { x = 0, y = -0.15 }, major = G.deck, bond = 'Weak' },
	})
end

function ST.remove()
	ST.last_me, ST.last_partner = nil, nil
	if ST.box then
		ST.box:remove()
		ST.box = nil
	end
end

local function pct(score, blind)
	if not blind or blind <= 0 then
		return 0
	end
	return math.floor(score / blind * 100 + 0.5)
end

function ST.update()
	if G.STAGE ~= G.STAGES.RUN or not G.deck or not G.GAME or not G.GAME.blind then
		ST.remove()
		return
	end
	if not ST.box then
		create()
	end
	local t = ST.text
	local blind = G.GAME.blind.chips or 0
	local in_blind = G.GAME.blind.in_blind
	local cap = COOP.MODES.on('share_cap') and math.floor(COOP.SHARE_CAP * 100) or nil
	if in_blind then
		local me = pct(math.max(COOP.SB.own_score(), 0), blind)
		local partner = pct(COOP.SB.partner_counted_score(), blind)
		t.shares = localize({ type = 'variable', key = cap and 'coop_shares_capped' or 'coop_shares', vars = { me, partner, cap } })
		-- what the blind actually counts, and who still has to add how much
		local counted = math.floor(COOP.SB.counted_score())
		t.counted = localize({ type = 'variable', key = 'coop_counted_line', vars = { number_format(counted), number_format(blind) } })
		t.need = ''
		if counted < blind and cap then
			local cap_pts = blind * COOP.SHARE_CAP
			local own = math.max(COOP.SB.own_score(), 0)
			local theirs = COOP.SB.partner_counted_score()
			local missing = math.ceil(blind - counted)
			if theirs >= cap_pts and own < cap_pts then
				t.need = localize({ type = 'variable', key = 'coop_need_me', vars = { number_format(missing) } })
			elseif own >= cap_pts and theirs < cap_pts then
				t.need = localize({ type = 'variable', key = 'coop_need_partner', vars = { number_format(missing) } })
			end
		end
	else
		t.counted, t.need = '', ''
		t.shares = cap and localize({ type = 'variable', key = 'coop_cap_rule', vars = { cap } }) or ''
	end
	t.synergy = COOP.MODES.on('relay')
			and localize({ type = 'variable', key = 'coop_synergy_line', vars = { COOP.SYN.relay or 0, COOP.SYN.resonance_mult() } })
		or ''
	-- last hand of each player: the HUD itself resets to 0 x 0 after every hand
	local function last(r, key)
		if not r or not r.hand or r.hand == '' then
			return ''
		end
		return localize({ type = 'variable', key = key, vars = { localize(r.hand, 'poker_hands'), number_format(math.floor(r.score or 0)), number_format(r.mult or 0) } })
	end
	t.last_me = last(ST.last_me, 'coop_last_me')
	t.last_partner = last(ST.last_partner, 'coop_last_partner')
	local lines = COOP.CHAT.lines(2)
	local function fit(s)
		return s and MPAPI.truncate(s, 36) or ''
	end
	t.chat1, t.chat2 = fit(lines[#lines - 1]), fit(lines[#lines])
end
