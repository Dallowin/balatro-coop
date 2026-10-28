-- Lobby options. The host picks them in the lobby; they travel as lobby
-- metadata ('coop_<key>' = value) and are frozen into COOP.MODES.current when
-- the run starts, so both players play by the same rules.

COOP.MODES = COOP.MODES or {}
local MO = COOP.MODES

-- key, values (first = default). Labels: localization 'coop_opt_<key>' and
-- 'coop_val_<key>_<value>'.
MO.OPTIONS = {
	{ key = 'deck', values = { 'shared', 'separate' } },
	{ key = 'turns', values = { 'alternate', 'together' } },
	{ key = 'synergy', values = { 'full', 'no_cap', 'off' } },
	{ key = 'difficulty', values = { 'normal', 'easy', 'hard', 'insane' } },
	{ key = 'bosses', values = { 'normal', 'evil' } },
	{ key = 'back', values = { 'b_red', 'b_blue', 'b_yellow', 'b_green', 'b_black', 'b_magic', 'b_nebula', 'b_ghost', 'b_abandoned', 'b_checkered', 'b_zodiac', 'b_painted', 'b_anaglyph', 'b_plasma', 'b_erratic' } },
	{ key = 'stake', values = { '1', '2', '3', '4', '5', '6', '7', '8' } },
}

MO.BLIND_MULT = { easy = 1.5, normal = 1.75, hard = 2.25, insane = 3 }

function MO.option(key)
	for _, o in ipairs(MO.OPTIONS) do
		if o.key == key then
			return o
		end
	end
end

-- Current value of an option in the lobby (before the run).
function MO.lobby_value(key)
	local lobby = MPAPI.get_current_lobby()
	local meta = lobby and lobby:get_metadata() or {}
	local v = meta['coop_' .. key]
	local o = MO.option(key)
	if v and o then
		for _, allowed in ipairs(o.values) do
			if allowed == v then
				return v
			end
		end
	end
	return o and o.values[1]
end

function MO.set_lobby_value(key, value)
	local lobby = MPAPI.get_current_lobby()
	if lobby and lobby.is_host then
		lobby:set_metadata({ ['coop_' .. key] = value })
	end
end

function MO.freeze()
	MO.current = {}
	for _, o in ipairs(MO.OPTIONS) do
		MO.current[o.key] = MO.lobby_value(o.key)
	end
	COOP.BLIND_MULT = MO.BLIND_MULT[MO.current.difficulty] or 1.75
end

function MO.get(key)
	local cur = MO.current or {}
	return cur[key] or MO.option(key).values[1]
end

-- Feature switches used around the mod.
function MO.on(feature)
	if feature == 'shared_deck' then
		return MO.get('deck') == 'shared'
	elseif feature == 'alternate_turns' then
		return MO.get('turns') == 'alternate'
	elseif feature == 'relay' or feature == 'resonance' then
		return MO.get('synergy') ~= 'off'
	elseif feature == 'share_cap' then
		return MO.get('synergy') == 'full'
	elseif feature == 'evil_bosses' then
		return MO.get('bosses') == 'evil'
	end
	return false
end

function MO.label(key)
	return localize('coop_opt_' .. key)
end

function MO.value_label(key, value)
	if key == 'back' then
		return localize({ type = 'name_text', set = 'Back', key = value })
	elseif key == 'stake' then
		local stake = G.P_CENTER_POOLS.Stake[tonumber(value)]
		return stake and localize({ type = 'name_text', set = 'Stake', key = stake.key }) or value
	end
	return localize('coop_val_' .. key .. '_' .. value)
end
