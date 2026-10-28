-- Pre-lobby page (Create / Join / Rules) and the lobby page: code, players
-- with ready state, game options (host edits, guest sees), ready / start,
-- rules, chat.

local code_ref = { text = '' }

local PANEL = { 0, 0, 0, 0.55 }

-- col = true: buttons in one row sit side by side instead of stacking
local function button(id, label, colour, w, scale)
	return UIBox_button({ button = id, label = { label }, minw = w or 2.6, minh = 0.65, scale = scale or 0.45, colour = colour, col = true })
end

local function disabled_button(label, w)
	return UIBox_button({ button = 'coop_noop', label = { label }, minw = w or 2.6, minh = 0.65, scale = 0.42, colour = G.C.UI.BACKGROUND_INACTIVE, col = true })
end
G.FUNCS.coop_noop = function() end

local function row(nodes, align, padding)
	return { n = G.UIT.R, config = { align = align or 'cm', padding = padding or 0.06 }, nodes = nodes }
end

local function col(nodes, config)
	config = config or {}
	config.align = config.align or 'tm'
	return { n = G.UIT.C, config = config, nodes = nodes }
end

local function text(str, scale, colour)
	return { n = G.UIT.T, config = { text = str, scale = scale or 0.4, colour = colour or G.C.WHITE, shadow = true } }
end

local function root(nodes)
	return {
		n = G.UIT.ROOT,
		config = { align = 'cm', colour = G.C.CLEAR },
		nodes = { col(nodes, { align = 'cm', colour = PANEL, r = 0.15, padding = 0.18 }) },
	}
end

-- Lobby events ---------------------------------------------------------------

function COOP.hook_lobby(lobby)
	for _, ev in ipairs({ 'player_joined', 'player_left', 'metadata_changed', 'host_changed', 'player_ready_changed' }) do
		lobby:on(ev, function()
			MPAPI.refresh_current_view()
		end)
	end
	COOP.partner_version = nil
	lobby:on('player_joined', function()
		COOP.send_hello()
	end)
	lobby:on('player_left', function()
		COOP.partner_version = nil
	end)
	lobby:on('connected', function()
		COOP.send_hello()
		if lobby.is_host and lobby.code then
			love.system.setClipboardText(lobby.code)
		end
	end)
	lobby:on('game_started', function(started)
		local gm = MPAPI.GameModes[COOP.GAMEMODE]
		local instance = gm:new_instance()
		lobby:set_gamemode_instance(instance)
		instance:start_run(started.seed, lobby)
	end)
end

-- Buttons ----------------------------------------------------------------------

G.FUNCS.coop_create = function()
	local lobby = MPAPI.create_lobby(COOP.id, { max_players = 2 })
	if lobby then
		COOP.hook_lobby(lobby)
	end
end

-- Solo test: a local lobby (no server) and a mirror "partner" that replays
-- our own moves (see COOP.flush / COOP.release_test_mirror in core.lua).
G.FUNCS.coop_solo_test = function()
	local lobby = MPAPI.create_local_lobby(COOP.id, { max_players = 1 })
	if not lobby then
		return
	end
	lobby.suppress_lobby_view = true
	COOP.TEST = true
	COOP.test_pending = {}
	lobby:on('connected', function()
		COOP.request_run(tostring(math.random(10000000, 99999999)), lobby)
	end)
end

G.FUNCS.coop_join = function()
	code_ref.text = ''
	G.FUNCS.overlay_menu({
		definition = create_UIBox_generic_options({
			snap_back = true,
			contents = {
				row({ text(localize('k_coop_enter_code'), 0.5) }),
				row({
					create_text_input({ ref_table = code_ref, ref_value = 'text', prompt_text = localize('k_lobby_code_cap'),
						max_length = 6, all_caps = true, w = 4, h = 0.6 }),
				}),
				row({ button('coop_join_confirm', localize('k_coop_join'), G.C.GREEN) }),
			},
		}),
	})
end

G.FUNCS.coop_join_confirm = function()
	-- read the closure's ref table: the UIE lookup is nil inside generic_options
	local code = (code_ref.text or ''):match('^%s*(.-)%s*$') or ''
	if #code == 0 then
		return
	end
	G.FUNCS.exit_overlay_menu()
	local lobby = MPAPI.join_lobby(COOP.id, code)
	if lobby then
		COOP.hook_lobby(lobby)
	end
end

G.FUNCS.coop_copy_code = function()
	local lobby = MPAPI.get_current_lobby()
	if lobby and lobby.code then
		love.system.setClipboardText(lobby.code)
		play_sound('card1')
	end
end

local function me(lobby)
	for _, p in ipairs(lobby:get_players()) do
		if p.id == lobby.player_id then
			return p
		end
	end
end

G.FUNCS.coop_ready = function()
	local lobby = MPAPI.get_current_lobby()
	if lobby and lobby.coop_steam then
		COOP.SL.toggle_ready()
	elseif lobby then
		local p = me(lobby)
		lobby:set_ready(not (p and p.ready))
	end
end

local function guest_ready(lobby)
	local players = lobby:get_players()
	if #players < 2 then
		return false
	end
	for _, p in ipairs(players) do
		if p.id ~= lobby.host_id and not p.ready then
			return false
		end
	end
	return true
end

G.FUNCS.coop_start = function()
	local lobby = MPAPI.get_current_lobby()
	if not (lobby and lobby.is_host) then
		return
	end
	if lobby.coop_steam then
		COOP.SL.start()
		return
	end
	if not MPAPI.has_server_referee(lobby) then
		-- local test lobby: no server to pick a seed, start straight away
		COOP.request_run(tostring(math.random(10000000, 99999999)), lobby)
		return
	end
	lobby:set_metadata({ gamemode = COOP.GAMEMODE })
	lobby:start_game({ stake = tonumber(COOP.MODES.lobby_value('stake')) or 1, options = { gamemode = COOP.GAMEMODE }, min_players = 2 },
		function(err)
			if err then
				sendWarnMessage('start_game failed: ' .. tostring(err.message), COOP.id)
			end
		end)
end

G.FUNCS.coop_leave = function()
	local lobby = MPAPI.get_current_lobby()
	if lobby and lobby.coop_steam then
		COOP.SL.leave()
	elseif lobby then
		lobby:leave()
	end
end

-- Option cycles: host only.
for _, o in ipairs(COOP.MODES.OPTIONS) do
	G.FUNCS['coop_opt_' .. o.key] = function(args)
		local value = o.values[args.to_key]
		if value then
			COOP.MODES.set_lobby_value(o.key, value)
		end
	end
end

-- Rules overlay ------------------------------------------------------------------

G.FUNCS.coop_rules = function()
	local contents = { row({ text(localize('k_coop_rules'), 0.6) }) }
	local i = 1
	while true do
		local key = 'k_coop_rule_' .. i
		local line = G.localization.misc.dictionary[key]
		if not line then
			break
		end
		-- lines starting with '# ' are section headers
		local header = line:sub(1, 2) == '# '
		contents[#contents + 1] = row({ text(header and line:sub(3) or line, header and 0.4 or 0.32, header and G.C.FILTER or G.C.WHITE) }, 'cl', 0.02)
		i = i + 1
	end
	contents[#contents + 1] = row({ text(localize('k_coop_current_modes'), 0.4, G.C.FILTER) }, 'cl')
	for _, o in ipairs(COOP.MODES.OPTIONS) do
		local value = G.STAGE == G.STAGES.RUN and COOP.MODES.get(o.key) or COOP.MODES.lobby_value(o.key)
		contents[#contents + 1] = row({ text(COOP.MODES.label(o.key) .. ': ' .. COOP.MODES.value_label(o.key, value), 0.32) }, 'cl', 0.01)
	end
	G.FUNCS.overlay_menu({ definition = create_UIBox_generic_options({ snap_back = true, contents = contents }) })
end

-- Pages ----------------------------------------------------------------------------

local function players_column(lobby)
	local nodes = { row({ text(localize('k_coop_players'), 0.45, G.C.FILTER) }) }
	local players = lobby:get_players()
	table.sort(players, function(a, b)
		return (a.id == lobby.host_id and 0 or 1) < (b.id == lobby.host_id and 0 or 1)
	end)
	for _, p in ipairs(players) do
		local name = MPAPI.truncate(p.displayName or '?', 16)
		local status, colour
		if COOP.SL.is_partner_player(p) and COOP.SL.lost() then
			status, colour = localize('k_coop_steam_no_link'), G.C.RED
		elseif p.id == lobby.host_id then
			status, colour = localize('k_coop_host'), G.C.FILTER
		elseif p.ready then
			status, colour = localize('k_coop_is_ready'), G.C.GREEN
		else
			status, colour = localize('k_coop_not_ready'), G.C.RED
		end
		local you = p.id == lobby.player_id and (' (' .. localize('k_coop_you') .. ')') or ''
		nodes[#nodes + 1] = row({
			col({ text(name .. you, 0.38) }, { align = 'cl', minw = 2.8 }),
			col({ text(status, 0.34, colour) }, { align = 'cr', minw = 1.6 }),
		}, 'cm', 0.04)
	end
	if #players < 2 and lobby.coop_steam and COOP.SL.partner then
		nodes[#nodes + 1] = row({ text(localize('k_coop_steam_waiting'), 0.32, G.C.UI.TEXT_INACTIVE) })
		nodes[#nodes + 1] = row({ text(MPAPI.truncate(COOP.SL.partner.name, 20), 0.34, G.C.FILTER) })
	elseif #players < 2 then
		nodes[#nodes + 1] = row({ text(localize('k_coop_waiting_player'), 0.32, G.C.UI.TEXT_INACTIVE) })
	elseif not COOP.partner_version then
		nodes[#nodes + 1] = row({ text(localize('k_coop_version_unknown'), 0.3, G.C.UI.TEXT_INACTIVE) })
	elseif not COOP.versions_match() then
		nodes[#nodes + 1] = row({ text(localize('k_coop_version_differs') .. ': ' .. tostring(COOP.version)
			.. ' / ' .. MPAPI.truncate(COOP.partner_version, 12), 0.3, G.C.RED) })
	end
	return col(nodes, { align = 'tm', minw = 4.6, padding = 0.08, colour = { 0, 0, 0, 0.25 }, r = 0.1 })
end

local function options_column(lobby)
	local nodes = { row({ text(localize('k_coop_modes'), 0.45, G.C.FILTER) }) }
	for _, o in ipairs(COOP.MODES.OPTIONS) do
		local current = COOP.MODES.lobby_value(o.key)
		if lobby.is_host then
			local labels, idx = {}, 1
			for i, v in ipairs(o.values) do
				labels[i] = COOP.MODES.value_label(o.key, v)
				if v == current then
					idx = i
				end
			end
			nodes[#nodes + 1] = row({
				col({ text(COOP.MODES.label(o.key), 0.32) }, { align = 'cl', minw = 2.2 }),
				col({ create_option_cycle({ options = labels, current_option = idx, opt_callback = 'coop_opt_' .. o.key,
					w = 3.6, scale = 0.7, no_pips = true, colour = G.C.RED }) }, { align = 'cm' }),
			}, 'cm', 0.02)
		else
			nodes[#nodes + 1] = row({
				col({ text(COOP.MODES.label(o.key), 0.32) }, { align = 'cl', minw = 2.2 }),
				col({ text(COOP.MODES.value_label(o.key, current), 0.34, G.C.FILTER) }, { align = 'cl', minw = 3.6 }),
			}, 'cm', 0.05)
		end
	end
	return col(nodes, { align = 'tm', minw = 6.2, padding = 0.08, colour = { 0, 0, 0, 0.25 }, r = 0.1 })
end

local function chat_rows()
	local nodes = {}
	local lines = COOP.CHAT.lines(4)
	if #lines == 0 then
		nodes[#nodes + 1] = row({ text(localize('k_coop_chat_empty'), 0.3, G.C.UI.TEXT_INACTIVE) }, 'cl', 0.01)
	end
	for _, l in ipairs(lines) do
		nodes[#nodes + 1] = row({ text(MPAPI.truncate(l, 70), 0.3, G.C.UI.TEXT_LIGHT) }, 'cl', 0.01)
	end
	return col(nodes, { align = 'tl', minw = 11, minh = 1.3, padding = 0.08, colour = { 0, 0, 0, 0.25 }, r = 0.1 })
end

function COOP.register_pages()
	MPAPI.Page({
		key = 'coop_main_menu',
		category = 'mod_menu',
		build = function(self)
			MPAPI.set_logo_offset(-10, true) -- the logo would sit on top of the panel
			return root({
				row({ text(localize('k_coop_title'), 0.8, G.C.FILTER) }),
				row({ text(localize('k_coop_tagline'), 0.35) }),
				row({ button('coop_steam', localize('k_coop_steam'), G.C.GREEN, 5.4) }),
				row({ text(localize('k_coop_steam_menu_hint'), 0.28, G.C.UI.TEXT_LIGHT) }),
				row({ button('coop_create', localize('k_coop_create'), G.C.BLUE), button('coop_join', localize('k_coop_join'), G.C.BLUE) }),
				row({ button('coop_solo_test', localize('k_coop_solo_test'), G.C.SECONDARY_SET.Planet), button('coop_rules', localize('k_coop_rules'), G.C.ORANGE) }),
				row({ text(localize('k_coop_solo_test_hint'), 0.28, G.C.UI.TEXT_LIGHT) }),
			})
		end,
	})

	MPAPI.Page({
		key = 'coop_lobby',
		category = 'lobby_menu',
		build = function(self)
			local lobby = MPAPI.get_current_lobby()
			if not lobby then
				return {}
			end
			MPAPI.set_logo_offset(-10, true) -- the logo would sit on top of the panel

			local actions = {}
			if lobby.is_host then
				if guest_ready(lobby) and COOP.versions_match() then
					actions[#actions + 1] = button('coop_start', localize('k_coop_start'), G.C.BLUE)
				elseif guest_ready(lobby) then
					actions[#actions + 1] = disabled_button(localize('k_coop_version_wait'), 3.4)
				else
					actions[#actions + 1] = disabled_button(localize(#lobby:get_players() < 2 and 'k_coop_waiting_player' or 'k_coop_waiting_ready'), 3.4)
				end
			else
				local p = me(lobby)
				if p and p.ready then
					actions[#actions + 1] = button('coop_ready', localize('k_coop_unready'), G.C.RED)
				else
					actions[#actions + 1] = button('coop_ready', localize('k_coop_ready'), G.C.GREEN)
				end
			end
			if lobby.coop_steam and lobby.is_host and not COOP.SL.connected() then
				actions[#actions + 1] = button('coop_steam_overlay', localize('k_coop_steam_invite_any'), G.C.GREEN, 3.4)
			end
			actions[#actions + 1] = button('coop_rules', localize('k_coop_rules'), G.C.ORANGE, 2)
			actions[#actions + 1] = button('coop_chat_open', localize('k_coop_chat'), G.C.SECONDARY_SET.Planet, 2)
			actions[#actions + 1] = button('coop_leave', localize('k_coop_leave'), G.C.RED, 2)

			return root({
				row({ text(localize('k_coop_lobby_title'), 0.7, G.C.FILTER) }),
				lobby.coop_steam and row({ text(localize('k_coop_steam_lobby'), 0.45, G.C.GOLD) }) or row({
					text(localize('k_lobby_code_cap') .. ': ', 0.45),
					text(tostring(lobby.code or '...'), 0.55, G.C.GOLD),
					{ n = G.UIT.B, config = { w = 0.2, h = 0.1 } },
					button('coop_copy_code', localize('k_coop_copy'), G.C.GREY, 1.8, 0.35),
				}),
				row({ players_column(lobby), { n = G.UIT.B, config = { w = 0.2, h = 0.1 } }, options_column(lobby) }, 'tm'),
				row({ chat_rows() }),
				row(actions),
			})
		end,
	})
end
