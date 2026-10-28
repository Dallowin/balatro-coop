-- Lobby options. The host picks them in the lobby; they travel as lobby
-- metadata ('coop_<key>' = value) and are frozen into COOP.MODES.current when
-- the run starts, so both players play by the same rules.

COOP.MODES = COOP.MODES or {}
local MO = COOP.MODES

-- key, values (first = default). Labels: localization 'coop_opt_<key>' and
-- 'coop_val_<key>_<value>'.
MO.OPTIONS = {
	{ key = 'run', values = { 'normal', 'daily' } },
	{ key = 'challenge', values = { 'none', 'sprint', 'tight', 'broke', 'specialists', 'bighands' } },
	{ key = 'deck', values = { 'shared', 'separate' } },
	{ key = 'turns', values = { 'alternate', 'together' } },
	{ key = 'resonance', values = { 'off', 'on' } },
	{ key = 'share_cap', values = { 'off', 'on' } },
	{ key = 'difficulty', values = { 'normal', 'easy', 'hard', 'insane' } },
	{ key = 'bosses', values = { 'normal', 'evil' } },
	{ key = 'back', values = { 'b_red', 'b_blue', 'b_yellow', 'b_green', 'b_black', 'b_magic', 'b_nebula', 'b_ghost', 'b_abandoned', 'b_checkered', 'b_zodiac', 'b_painted', 'b_anaglyph', 'b_plasma', 'b_erratic', 'b_coop_siamese', 'b_coop_redblack' } },
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

-- The daily run fixes every rule but the run kind itself.
function MO.daily()
	return MO.raw_lobby_value('run') == 'daily'
end

function MO.locked(key)
	return key ~= 'run' and MO.daily()
end

-- the date the host picked the daily run for (so both use the same day)
function MO.daily_date()
	local lobby = COOP.get_lobby()
	local meta = lobby and lobby:get_metadata() or {}
	return meta.coop_daily_date or COOP.CHALLENGE.today()
end

function MO.lobby_value(key)
	if MO.locked(key) then
		return COOP.CHALLENGE.daily_rules(MO.daily_date())[key]
	end
	return MO.raw_lobby_value(key)
end

-- Current value of an option in the lobby (before the run).
function MO.raw_lobby_value(key)
	local lobby = COOP.get_lobby()
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
	local lobby = COOP.get_lobby()
	if lobby and lobby.is_host then
		local meta = { ['coop_' .. key] = value }
		if key == 'run' and value == 'daily' then
			meta.coop_daily_date = COOP.CHALLENGE.today() -- the host's day, for both
		end
		lobby:set_metadata(meta)
	end
end

function MO.freeze()
	MO.current = {}
	for _, o in ipairs(MO.OPTIONS) do
		MO.current[o.key] = MO.lobby_value(o.key)
	end
	-- team decks are one deck each: no shared 104-card deck with them
	if MO.current.back == 'b_coop_siamese' or MO.current.back == 'b_coop_redblack' then
		MO.current.deck = 'separate'
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
	elseif feature == 'resonance' then
		return MO.get('resonance') == 'on'
	elseif feature == 'share_cap' then
		return MO.get('share_cap') == 'on'
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
