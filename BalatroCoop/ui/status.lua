-- Team panel during a run, in the free space on the right between the team
-- joker row and our hand: how much each player has put into the blind (and
-- the cap), the last hands, the resonance, where the partner is (only while elsewhere), and a new chat line for a few
-- seconds. Only non-empty lines are shown, so the panel stays small.

COOP.STATUS = COOP.STATUS or {}
local ST = COOP.STATUS

local CHAT_SHOW_FOR = 8

ST.text = { counted = '', need = '', shares = '', hands = '', resonance = '', activity = '', chat = '' }

local LINES = {
	{ key = 'counted', colour = 'GOLD', scale = 0.28 },
	{ key = 'need', colour = 'RED', scale = 0.25 },
	{ key = 'shares', colour = 'WHITE', scale = 0.25 },
	{ key = 'resonance', colour = 'PLANET', scale = 0.24 },
	{ key = 'activity', colour = 'FILTER', scale = 0.24 },
	{ key = 'chat', colour = 'TEXT_LIGHT', scale = 0.24 },
}

local function colour(name)
	if name == 'PLANET' then
		return G.C.SECONDARY_SET.Planet
	elseif name == 'TEXT_LIGHT' then
		return G.C.UI.TEXT_LIGHT
	end
	return G.C[name]
end

local function create(visible)
	local rows = {}
	for _, l in ipairs(LINES) do
		if visible[l.key] then
			rows[#rows + 1] = { n = G.UIT.R, config = { align = 'cl', padding = 0.015 }, nodes = {
				{ n = G.UIT.T, config = { ref_table = ST.text, ref_value = l.key, scale = l.scale, colour = colour(l.colour), shadow = true } },
			} }
		end
	end
	if visible.unstick then
		rows[#rows + 1] = { n = G.UIT.R, config = { align = 'cm', padding = 0.04 }, nodes = {
			UIBox_button({ button = 'coop_unstick', label = { localize('k_coop_unstick') }, minw = 3, minh = 0.42, scale = 0.32, colour = G.C.RED }),
		} }
	end
	ST.box = UIBox({
		definition = {
			n = G.UIT.ROOT,
			config = { align = 'cm', colour = { 0, 0, 0, 0.6 }, r = 0.1, padding = 0.08 },
			nodes = { { n = G.UIT.C, config = { align = 'cl' }, nodes = rows } },
		},
		-- under the team row, below its "0/3" counter; above the deck if there's no row
		config = G.coop_team and { align = 'bm', offset = { x = 0, y = 0.32 }, major = G.coop_team, bond = 'Weak' }
			or { align = 'tm', offset = { x = 0, y = -0.1 }, major = G.deck, bond = 'Weak' },
	})
end

function ST.remove()
	ST.last_me, ST.last_partner = nil, nil
	ST.shape = nil
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
	local t = ST.text
	local blind = G.GAME.blind.chips or 0
	local in_blind = G.GAME.blind.in_blind
	local cap = COOP.MODES.on('share_cap') and math.floor(COOP.SHARE_CAP * 100) or nil
	if in_blind then
		local me = pct(math.max(COOP.SB.own_score(), 0), blind)
		local partner = pct(COOP.SB.partner_counted_score(), blind)
		-- shares only matter with the cap option
		t.shares = cap and localize({ type = 'variable', key = 'coop_shares_capped', vars = { me, partner, cap } }) or ''
		-- what the blind actually counts, and who still has to add how much
		local counted = math.floor(COOP.SB.counted_score())
		-- without the cap the HUD's round score already says this
		t.counted = cap and localize({ type = 'variable', key = 'coop_counted_line', vars = { number_format(counted), number_format(blind) } }) or ''
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
	t.resonance = COOP.MODES.on('resonance')
			and localize({ type = 'variable', key = 'coop_resonance_line', vars = { COOP.SYN.resonance_mult() } })
		or ''
	-- last hand of each player: the HUD itself resets to 0 x 0 after every hand
	local function last(r, key)
		if not r or not r.hand or r.hand == '' then
			return ''
		end
		return localize({ type = 'variable', key = key, vars = { localize(r.hand, 'poker_hands'), number_format(math.floor(r.score or 0)), number_format(r.mult or 0) } })
	end
	-- both last hands on one line
	local mine, theirs = last(ST.last_me, 'coop_last_me'), last(ST.last_partner, 'coop_last_partner')
	t.hands = (mine ~= '' and theirs ~= '') and (mine .. '   ' .. theirs) or (mine .. theirs)
	-- a new chat line shows for a few seconds
	t.activity = COOP.SOCIAL.activity_line()
	local latest = COOP.CHAT.latest_loud()
	if latest ~= ST.chat_latest then
		ST.chat_latest = latest
		ST.chat_until = latest and G.TIMERS.REAL + CHAT_SHOW_FOR or 0
	end
	t.chat = latest and G.TIMERS.REAL < (ST.chat_until or 0) and COOP.truncate(latest, 36) or ''

	-- rebuild the box when the set of non-empty lines changes
	local visible, shape = {}, ''
	for _, l in ipairs(LINES) do
		if t[l.key] ~= '' then
			visible[l.key] = true
			shape = shape .. l.key .. ','
		end
	end
	if COOP.SB.looks_stuck() then
		visible.unstick = true
		shape = shape .. 'unstick,'
	end
	local empty = shape == ''
	shape = shape .. (G.coop_team and 'row' or '')
	if shape ~= ST.shape then
		if ST.box then
			ST.box:remove()
			ST.box = nil
		end
		ST.shape = shape
		if not empty then
			create(visible) -- an empty panel would show as a stray dark dot
		end
	end
end

G.FUNCS.coop_unstick = function()
	play_sound('button')
	COOP.SB.unstick()
end
