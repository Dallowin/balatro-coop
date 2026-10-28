-- History of co-op runs, kept on this computer (Balatro's save folder,
-- coop_history.json): date, result, how far you got, best hand, partner,
-- run kind and challenge. The co-op menu shows it, and the result of a run
-- (the daily run first of all) can be copied to share it.

COOP.HISTORY = COOP.HISTORY or {}
local H = COOP.HISTORY

local FILE = 'coop_history.json'
local KEEP = 50
local json_ok, json = pcall(require, 'json')

function H.load()
	if H.list then
		return H.list
	end
	H.list = {}
	if json_ok and love.filesystem.getInfo(FILE) then
		local ok, data = pcall(love.filesystem.read, FILE)
		local ok2, t = false, nil
		if ok and data then
			ok2, t = pcall(json.decode, data)
		end
		if ok2 and type(t) == 'table' then
			H.list = t
		end
	end
	return H.list
end

local function save()
	if json_ok then
		local ok, data = pcall(json.encode, H.list)
		if ok then
			pcall(love.filesystem.write, FILE, data)
		end
	end
end

local function partner_name()
	local lobby = COOP.get_lobby()
	for _, p in ipairs(lobby and lobby:get_players() or {}) do
		if p.id ~= lobby.player_id then
			return tostring(p.displayName or '?')
		end
	end
	return COOP.TEST and 'test' or '?'
end

local function best_hand()
	local rs = G.GAME.round_scores
	return math.floor(tonumber(rs and rs.hand and rs.hand.amt) or 0)
end

-- won: true for a win; a loss after a win (endless) only moves the numbers
function H.record(won)
	local list = H.load()
	local e = H.current
	if not e then
		e = {
			date = os.date('!%Y-%m-%d'),
			time = os.date('%H:%M'),
			run = COOP.MODES.get('run'),
			challenge = COOP.MODES.get('challenge'),
			back = COOP.MODES.get('back'),
			partner = partner_name(),
			seed = G.GAME.pseudorandom and G.GAME.pseudorandom.seed or '',
		}
		table.insert(list, 1, e)
		while #list > KEEP do
			table.remove(list)
		end
		H.current = e
	end
	e.won = e.won or won or false
	e.ante = G.GAME.round_resets and G.GAME.round_resets.ante or 0
	e.round = G.GAME.round or 0
	e.best = math.max(e.best or 0, best_hand())
	save()
end

-- best daily result of a day (furthest ante, then best hand)
function H.best_daily(date)
	local best
	for _, e in ipairs(H.load()) do
		if e.run == 'daily' and e.date == date then
			if not best or (e.ante or 0) > (best.ante or 0) or ((e.ante or 0) == (best.ante or 0) and (e.best or 0) > (best.best or 0)) then
				best = e
			end
		end
	end
	return best
end

function H.challenge_name(id)
	return localize('coop_val_challenge_' .. tostring(id or 'none'))
end

function H.share_text(e)
	if not e then
		return ''
	end
	return localize({ type = 'variable', key = 'coop_history_share', vars = {
		e.run == 'daily' and (localize('k_coop_daily') .. ' ' .. tostring(e.date)) or tostring(e.date),
		H.challenge_name(e.challenge),
		localize(e.won and 'k_coop_history_won' or 'k_coop_history_lost'),
		e.ante or 0, e.round or 0, number_format(e.best or 0), e.partner or '?',
	} })
end

function H.install_hooks()
	local start_run_ref = Game.start_run
	function Game:start_run(args)
		start_run_ref(self, args)
		if COOP.in_run and not (args and args.savetext) then
			H.current = nil -- a fresh co-op run: a new history entry when it ends
		end
	end

	local win_game_ref = win_game
	function win_game(...)
		if COOP.is_active() then
			pcall(H.record, true)
		end
		return win_game_ref(...)
	end
end

-- Game:update (co-op runs only): a lost run is written once
function H.update()
	if G.STATE == G.STATES.GAME_OVER then
		if not H.lost_written then
			H.lost_written = true
			pcall(H.record, false)
		end
	else
		H.lost_written = false
	end
end
