-- One wallet for the team. Every change of our money (ease_dollars) is sent
-- to the partner, who applies the same change to their copy. Both start the
-- run with the same money, so the two copies stay equal.
--
-- Cash-out: the blind reward and interest are team income, paid once (by the
-- host's cash-out). Leftover hands and joker payouts stay per player.

COOP.MONEY = COOP.MONEY or {}
local M = COOP.MONEY

local applying_remote = false

function M.on_partner_change(amount)
	applying_remote = true
	local ok, err = pcall(ease_dollars, amount)
	applying_remote = false
	if not ok then
		sendWarnMessage('shared money failed: ' .. tostring(err), COOP.id)
	end
end

local function is_host()
	local lobby = COOP.get_lobby()
	return lobby and lobby.is_host
end

function M.install_hooks()
	-- guest's cash-out: no blind reward, no interest (the host's covers both)
	local evaluate_round_ref = G.FUNCS.evaluate_round
	G.FUNCS.evaluate_round = function(...)
		if not COOP.is_active() or is_host() then
			return evaluate_round_ref(...)
		end
		local blind_dollars = G.GAME.blind.dollars
		local no_interest = G.GAME.modifiers.no_interest
		G.GAME.blind.dollars = 0
		G.GAME.modifiers.no_interest = true
		local ok, err = pcall(evaluate_round_ref, ...)
		G.GAME.blind.dollars = blind_dollars
		G.GAME.modifiers.no_interest = no_interest
		if not ok then
			error(err)
		end
	end

	local ease_dollars_ref = ease_dollars
	function ease_dollars(mod, instant)
		if COOP.is_active() and not applying_remote and type(mod) == 'number' and mod ~= 0 then
			COOP.send('money', { amount = mod })
		end
		return ease_dollars_ref(mod, instant)
	end
end
