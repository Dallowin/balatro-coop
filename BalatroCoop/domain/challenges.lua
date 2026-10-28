-- Co-op challenges (lobby option "Challenge") and the daily run.
--
-- A challenge changes the starting rules once the run has started; its blind
-- factor scales every blind's requirement so the challenge stays fair: what
-- it takes away is given back as a lower requirement, what it gives is paid
-- for with a higher one.
--
-- The daily run: one seed per UTC day for every pair, with fixed rules and
-- a challenge of the day, so results can be compared.

COOP.CHALLENGE = COOP.CHALLENGE or {}
local CH = COOP.CHALLENGE

local function is_host()
	local lobby = COOP.get_lobby()
	return not lobby or lobby.is_host
end

-- id -> { blind = requirement factor, apply = function() at run start }
CH.LIST = {
	none = { blind = 1 },
	sprint = { -- 2 hands and 2 discards each
		blind = 0.6,
		apply = function()
			G.GAME.round_resets.hands = 2
			G.GAME.round_resets.discards = 2
		end,
	},
	tight = { -- 3 joker slots each
		blind = 0.8,
		apply = function()
			G.jokers.config.card_limit = 3
		end,
	},
	broke = { -- no starting money, no interest
		blind = 0.85,
		apply = function()
			G.GAME.dollars = 0
			G.GAME.modifiers.no_interest = true
		end,
	},
	specialists = { -- the host plays, the guest discards
		blind = 1,
		apply = function()
			if is_host() then
				G.GAME.round_resets.hands = 6
				G.GAME.round_resets.discards = 0
			else
				G.GAME.round_resets.hands = 2
				G.GAME.round_resets.discards = 6
			end
		end,
	},
	bighands = { -- hand size +2
		blind = 1.6,
		apply = function()
			G.hand:change_size(2)
		end,
	},
}
CH.ORDER = { 'none', 'sprint', 'tight', 'broke', 'specialists', 'bighands' }

function CH.current()
	return CH.LIST[COOP.MODES.get('challenge')] or CH.LIST.none
end

function CH.blind_factor()
	return CH.current().blind or 1
end

-- Game:start_run (fresh co-op run): set the challenge's starting rules.
function CH.apply()
	-- co-op: consumables are a shared pool (domain/consumables.lua), 4 slots
	if G.consumeables then
		G.consumeables.config.card_limit = math.max(G.consumeables.config.card_limit, 4)
	end
	local c = CH.current()
	if c.apply then
		local ok, err = pcall(c.apply)
		if not ok then
			sendWarnMessage('challenge apply failed: ' .. tostring(err), COOP.id)
		end
	end
	-- the hands / discards of the first round come from round_resets
	G.GAME.current_round.hands_left = G.GAME.round_resets.hands
	G.GAME.current_round.discards_left = G.GAME.round_resets.discards
end

-- Daily run --------------------------------------------------------------------

function CH.today()
	return os.date('!%Y-%m-%d')
end

function CH.daily_seed(date)
	return 'D' .. tostring(date or CH.today()):gsub('-', '')
end

-- the challenge of the day rotates through the list (never 'none')
function CH.daily_challenge(date)
	local digits = tostring(date or CH.today()):gsub('-', '')
	local n = tonumber(digits) or 0
	local pool = { 'sprint', 'tight', 'broke', 'specialists', 'bighands' }
	return pool[n % #pool + 1]
end

-- fixed rules of the daily run (the challenge depends on the day)
function CH.daily_rules(date)
	return {
		deck = 'shared',
		turns = 'alternate',
		resonance = 'off',
		share_cap = 'off',
		difficulty = 'normal',
		bosses = 'normal',
		back = 'b_red',
		stake = '1',
		challenge = CH.daily_challenge(date),
	}
end

function CH.install_hooks()
	local start_run_ref = Game.start_run
	function Game:start_run(args)
		start_run_ref(self, args)
		if COOP.in_run and COOP.get_lobby() and not (args and args.savetext) then
			CH.apply()
		end
	end
end
