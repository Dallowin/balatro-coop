-- The co-op menu page (Steam / solo test / rules...) and the lobby page:
-- players with ready state, game options (host edits, guest sees), ready /
-- start, rules, chat. Shown by ui/pages.lua.

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

-- Buttons ----------------------------------------------------------------------

-- Solo test: a lobby with just us and a mirror "partner" that replays our
-- own moves (see COOP.flush / COOP.release_test_mirror in core.lua).
G.FUNCS.coop_solo_test = function()
	COOP.LOBBY.create({ host = true, view = false })
	COOP.TEST = true
	COOP.test_pending = {}
	COOP.request_run(tostring(math.random(10000000, 99999999)), COOP.get_lobby())
end

local function me(lobby)
	for _, p in ipairs(lobby:get_players()) do
		if p.id == lobby.player_id then
			return p
		end
	end
end

G.FUNCS.coop_ready = function()
	COOP.SL.toggle_ready()
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
	COOP.SL.start()
end

G.FUNCS.coop_leave = function()
	COOP.SL.leave()
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

-- Rules come in sections (lines starting with '# ' in the localization); one
-- section per page plus a page with the current options, so it always fits.
local function rule_sections()
	local sections, current = {}, nil
	local i = 1
	while true do
		local line = G.localization.misc.dictionary['k_coop_rule_' .. i]
		if not line then
			break
		end
		if line:sub(1, 2) == '# ' or not current then
			current = { title = line:sub(1, 2) == '# ' and line:sub(3) or localize('k_coop_rules'), lines = {} }
			sections[#sections + 1] = current
		end
		if line:sub(1, 2) ~= '# ' then
			current.lines[#current.lines + 1] = line
		end
		i = i + 1
	end
	local modes = { title = localize('k_coop_current_modes'), lines = {} }
	for _, o in ipairs(COOP.MODES.OPTIONS) do
		local value = G.STAGE == G.STAGES.RUN and COOP.MODES.get(o.key) or COOP.MODES.lobby_value(o.key)
		modes.lines[#modes.lines + 1] = COOP.MODES.label(o.key) .. ': ' .. COOP.MODES.value_label(o.key, value)
	end
	sections[#sections + 1] = modes
	return sections
end

local function show_rules(page)
	local sections = rule_sections()
	page = math.max(1, math.min(page or 1, #sections))
	local titles = {}
	for i, sec in ipairs(sections) do
		titles[i] = sec.title
	end
	local contents = {
		row({ text(localize('k_coop_rules'), 0.6, G.C.GOLD) }),
		row({ create_option_cycle({ options = titles, current_option = page, opt_callback = 'coop_rules_page',
			w = 6, scale = 0.8, colour = G.C.RED }) }),
	}
	for _, line in ipairs(sections[page].lines) do
		for j, part in ipairs(COOP.wrap(line, 70)) do
			contents[#contents + 1] = row({ text((j > 1 and '  ' or '') .. part, 0.32) }, 'cl', j > 1 and 0 or 0.03)
		end
	end
	G.FUNCS.overlay_menu({ definition = create_UIBox_generic_options({ snap_back = true, contents = contents }) })
end

G.FUNCS.coop_rules = function()
	show_rules(1)
end

G.FUNCS.coop_rules_page = function(args)
	show_rules(args.to_key)
end

-- Pages ----------------------------------------------------------------------------

-- What the chosen options mean, under the players: the deck (its card and
-- its own description, as on the run setup screen), the challenge and the
-- daily run.
local function deck_preview()
	local key = COOP.MODES.lobby_value('back')
	local center = G.P_CENTERS[key]
	if not center then
		return nil
	end
	local atlas = G.ASSET_ATLAS[center.atlas or 'centers'] or G.ASSET_ATLAS.centers
	local sprite = Sprite(0, 0, G.CARD_W * 0.42, G.CARD_H * 0.42, atlas, center.pos)
	return row({
		{ n = G.UIT.C, config = { align = 'cm', padding = 0.05, r = 0.08, colour = G.C.BLACK, button = 'coop_deck_view', hover = true, shadow = true,
			tooltip = { text = { localize('k_coop_deck_view_hint') } } }, nodes = {
			{ n = G.UIT.O, config = { object = sprite } },
		} },
		col({ text(COOP.MODES.value_label('back', key), 0.32, G.C.FILTER) }, { align = 'cl', padding = 0.05 }),
	}, 'cm', 0.02)
end

-- Deck viewer, the same as the game's Collection > Decks: a stack of cards
-- with the deck's back, its name and description, < > to browse. For the
-- host browsing also picks the deck for the run; the guest only looks.
local DECK_VIEW_CARDS = 12

local function deck_values()
	return COOP.MODES.option('back').values
end

G.FUNCS.coop_deck_view = function()
	local values = deck_values()
	local current = COOP.MODES.lobby_value('back')
	local idx, names = 1, {}
	for i, v in ipairs(values) do
		names[i] = COOP.MODES.value_label('back', v)
		if v == current then
			idx = i
		end
	end
	G.GAME.viewed_back = Back(G.P_CENTERS[values[idx]] or G.P_CENTERS.b_red)
	local area = CardArea(G.ROOM.T.x + 0.2 * G.ROOM.T.w / 2, G.ROOM.T.h, 1.2 * G.CARD_W, 1.2 * G.CARD_H,
		{ card_limit = DECK_VIEW_CARDS, type = 'deck', highlight_limit = 0 })
	for i = 1, DECK_VIEW_CARDS do
		local card = Card(G.ROOM.T.x + 0.2 * G.ROOM.T.w / 2, G.ROOM.T.h, G.CARD_W * 1.2, G.CARD_H * 1.2,
			pseudorandom_element(G.P_CARDS), G.P_CENTERS.c_base, { playing_card = i, viewed_back = true })
		card.sprite_facing = 'back'
		card.facing = 'back'
		area:emplace(card)
	end
	COOP.deck_view_area = area
	local lobby = COOP.get_lobby()
	local can_pick = lobby and lobby.is_host and not COOP.MODES.locked('back')
	G.FUNCS.overlay_menu({ definition = create_UIBox_generic_options({ contents = {
		create_option_cycle({ options = names, opt_callback = 'coop_deck_view_change', current_option = idx, colour = G.C.RED, w = 4.5,
			focus_args = { snap_to = true }, mid = { n = G.UIT.R, config = { align = 'cm', minw = 2.5, padding = 0.1, r = 0.1, colour = G.C.BLACK, emboss = 0.05 }, nodes = {
				{ n = G.UIT.R, config = { align = 'cm', padding = 0.2, colour = G.C.BLACK, r = 0.2 }, nodes = {
					{ n = G.UIT.C, config = { align = 'cm', padding = 0 }, nodes = { { n = G.UIT.O, config = { object = area } } } },
					{ n = G.UIT.C, config = { align = 'tm', minw = 3.7, minh = 2.1, r = 0.1, colour = G.C.L_BLACK, padding = 0.1 }, nodes = {
						{ n = G.UIT.R, config = { align = 'cm', emboss = 0.1, r = 0.1, minw = 4, maxw = 4, minh = 0.6 }, nodes = {
							{ n = G.UIT.O, config = { id = nil, func = 'RUN_SETUP_check_back_name', object = Moveable() } },
						} },
						{ n = G.UIT.R, config = { align = 'cm', colour = G.C.WHITE, emboss = 0.1, minh = 2.2, r = 0.1 }, nodes = {
							{ n = G.UIT.O, config = { id = G.GAME.viewed_back.name, func = 'RUN_SETUP_check_back',
								object = UIBox({ definition = G.GAME.viewed_back:generate_UI(), config = { offset = { x = 0, y = 0 } } }) } },
						} },
					} },
				} },
			} } }),
		row({ text(localize(can_pick and 'k_coop_deck_view_pick' or 'k_coop_deck_view_look'), 0.32, G.C.UI.TEXT_LIGHT) }, 'cm', 0.05),
	} }) })
end

G.FUNCS.coop_deck_view_change = function(args)
	local key = deck_values()[args.to_key]
	local center = key and G.P_CENTERS[key]
	if not center then
		return
	end
	G.GAME.viewed_back:change_to(center)
	for _, c in ipairs(COOP.deck_view_area and COOP.deck_view_area.cards or {}) do
		c.children.back = false
		c:set_ability(c.config.center, true)
	end
	local lobby = COOP.get_lobby()
	if lobby and lobby.is_host and not COOP.MODES.locked('back') then
		COOP.MODES.set_lobby_value('back', key) -- the host picks the run's deck here
	end
end

local function rules_preview()
	local nodes = {}
	if COOP.MODES.daily() then
		nodes[#nodes + 1] = row({ text(localize('k_coop_daily_explain'), 0.28, G.C.GOLD) }, 'cm', 0.01)
	end
	local ch = COOP.MODES.lobby_value('challenge')
	if ch and ch ~= 'none' then
		nodes[#nodes + 1] = row({ text(localize('coop_val_challenge_' .. ch), 0.3, G.C.FILTER) }, 'cm', 0.01)
		nodes[#nodes + 1] = row({ text(localize({ type = 'variable', key = 'coop_challenge_blind',
			vars = { COOP.CHALLENGE.LIST[ch] and COOP.CHALLENGE.LIST[ch].blind or 1 } }), 0.26, G.C.UI.TEXT_LIGHT) }, 'cm', 0.01)
	end
	return nodes
end

local function players_column(lobby)
	local nodes = { row({ text(localize('k_coop_players'), 0.45, G.C.FILTER) }) }
	local players = lobby:get_players()
	table.sort(players, function(a, b)
		return (a.id == lobby.host_id and 0 or 1) < (b.id == lobby.host_id and 0 or 1)
	end)
	for _, p in ipairs(players) do
		local name = COOP.truncate(p.displayName or '?', 16)
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
	if #players < 2 and COOP.SL.partner then
		nodes[#nodes + 1] = row({ text(localize('k_coop_steam_waiting'), 0.32, G.C.UI.TEXT_INACTIVE) })
		nodes[#nodes + 1] = row({ text(COOP.truncate(COOP.SL.partner.name, 20), 0.34, G.C.FILTER) })
	elseif #players < 2 then
		nodes[#nodes + 1] = row({ text(localize('k_coop_waiting_player'), 0.32, G.C.UI.TEXT_INACTIVE) })
	elseif not COOP.partner_version then
		nodes[#nodes + 1] = row({ text(localize('k_coop_version_unknown'), 0.3, G.C.UI.TEXT_INACTIVE) })
	elseif not COOP.versions_match() then
		nodes[#nodes + 1] = row({ text(localize('k_coop_version_differs') .. ': ' .. tostring(COOP.version)
			.. ' / ' .. COOP.truncate(COOP.partner_version, 12), 0.3, G.C.RED) })
	end
	-- the chosen deck and challenge, so both see what they are in for
	local ok, dp = pcall(deck_preview)
	if ok and dp then
		nodes[#nodes + 1] = row({ text(localize('k_coop_preview'), 0.36, G.C.FILTER) }, 'cm', 0.06)
		nodes[#nodes + 1] = dp
	end
	local ok2, rp = pcall(rules_preview)
	for _, n in ipairs(ok2 and rp or {}) do
		nodes[#nodes + 1] = n
	end
	return col(nodes, { align = 'tm', minw = 4.6, padding = 0.08, colour = { 0, 0, 0, 0.25 }, r = 0.1 })
end

-- what an option means, shown on hover (localization coop_tip_<key>, lines split by |)
local function option_tip(o)
	local raw = G.localization.misc.dictionary['coop_tip_' .. o.key]
	if not raw then
		return nil
	end
	local lines = {}
	for line in string.gmatch(raw, '[^|]+') do
		lines[#lines + 1] = line
	end
	return { title = COOP.MODES.label(o.key), text = lines }
end

local function option_cell(lobby, o)
	local current = COOP.MODES.lobby_value(o.key)
	if lobby.is_host and not COOP.MODES.locked(o.key) then
		local labels, idx = {}, 1
		for i, v in ipairs(o.values) do
			labels[i] = COOP.MODES.value_label(o.key, v)
			if v == current then
				idx = i
			end
		end
		return col({
			row({ text(COOP.MODES.label(o.key), 0.28, G.C.UI.TEXT_LIGHT) }, 'cm', 0),
			row({ create_option_cycle({ options = labels, current_option = idx, opt_callback = 'coop_opt_' .. o.key,
				w = 3.3, scale = 0.6, no_pips = true, colour = G.C.RED }) }, 'cm', 0),
		}, { align = 'cm', minw = 4.4, padding = 0.02, tooltip = option_tip(o) })
	end
	-- the guest's view, and the daily run's fixed rules (in gold)
	return col({
		row({ text(COOP.MODES.label(o.key), 0.28, G.C.UI.TEXT_LIGHT) }, 'cm', 0),
		row({ text(COOP.MODES.value_label(o.key, current), 0.32, COOP.MODES.locked(o.key) and G.C.GOLD or G.C.FILTER) }, 'cm', 0.04),
	}, { align = 'cm', minw = 4.4, minh = 0.85, padding = 0.02, tooltip = option_tip(o) })
end

local function options_column(lobby)
	local nodes = { row({ text(localize('k_coop_modes'), 0.42, G.C.FILTER) }, 'cm', 0.02) }
	local opts = COOP.MODES.OPTIONS
	for i = 1, #opts, 2 do
		local cells = { option_cell(lobby, opts[i]) }
		if opts[i + 1] then
			cells[2] = option_cell(lobby, opts[i + 1])
		end
		nodes[#nodes + 1] = row(cells, 'cm', 0.01)
	end
	return col(nodes, { align = 'tm', padding = 0.06, colour = { 0, 0, 0, 0.25 }, r = 0.1 })
end

local function chat_rows()
	local nodes = {}
	local lines = COOP.CHAT.lines(3)
	if #lines == 0 then
		return nil -- nothing said yet: no empty block taking up room
	end
	for _, l in ipairs(lines) do
		nodes[#nodes + 1] = row({ text(COOP.truncate(l, 70), 0.3, G.C.UI.TEXT_LIGHT) }, 'cl', 0.01)
	end
	return col(nodes, { align = 'tl', minw = 11, padding = 0.06, colour = { 0, 0, 0, 0.25 }, r = 0.1 })
end

function COOP.register_pages()
	COOP.PAGES.register('menu', function()
			COOP.maybe_show_whats_new()
			local buttons = col({
				row({ button('coop_steam', localize('k_coop_steam'), G.C.GREEN, 5.4, 0.55) }),
				row({ text(localize('k_coop_steam_menu_hint'), 0.28, G.C.UI.TEXT_LIGHT) }, 'cm', 0.02),
				row({ button('coop_solo_test', localize('k_coop_solo_test'), G.C.SECONDARY_SET.Planet), button('coop_rules', localize('k_coop_rules'), G.C.ORANGE) }),
				row({ button('coop_history', localize('k_coop_history'), G.C.GOLD), button('coop_whats_new', localize('k_coop_whats_new'), G.C.PURPLE) }),
				row({ text(localize('k_coop_solo_test_hint'), 0.26, G.C.UI.TEXT_LIGHT) }, 'cm', 0.02),
			}, { align = 'cm', padding = 0.05 })
			-- the logo sits above the panel, big like the game's own title
			local logo = COOP.menu_sprite('coop_logo', 10, 10 * 262 / 480)
			local panel = col({
				row({ text(localize('k_coop_tagline'), 0.36) }, 'cm', 0.02),
				row({ buttons }, 'cm', 0.06),
			}, { align = 'cm', colour = PANEL, r = 0.15, padding = 0.18 })
			return {
				n = G.UIT.ROOT,
				config = { align = 'cm', colour = G.C.CLEAR },
				nodes = {
					logo and row({ logo }, 'cm', 0) or row({ text(localize('k_coop_title'), 0.9, G.C.FILTER) }),
					row({ panel }, 'cm', 0.05),
				},
			}
	end)

	COOP.PAGES.register('lobby', function()
			local lobby = COOP.get_lobby()

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
			if lobby.is_host and not COOP.SL.connected() then
				actions[#actions + 1] = button('coop_steam_overlay', localize('k_coop_steam_invite_any'), G.C.GREEN, 3.4)
			end
			actions[#actions + 1] = button('coop_rules', localize('k_coop_rules'), G.C.ORANGE, 2)
			actions[#actions + 1] = button('coop_chat_open', localize('k_coop_chat'), G.C.SECONDARY_SET.Planet, 2)
			actions[#actions + 1] = button('coop_leave', localize('k_coop_leave'), G.C.RED, 2)

			local chat = chat_rows()
			return root({
				row({ text(localize('k_coop_lobby_title'), 0.6, G.C.FILTER) }, 'cm', 0.02),
				row({ text(localize('k_coop_steam_lobby'), 0.45, G.C.GOLD) }),
				row({ players_column(lobby), { n = G.UIT.B, config = { w = 0.2, h = 0.1 } }, options_column(lobby) }, 'tm'),
				chat and row({ chat }) or row({}, 'cm', 0),
				row(actions),
			})
	end)
end

-- Menu art ---------------------------------------------------------------------

-- one-frame sprite from objects/art.lua, nil if the atlas is missing
function COOP.menu_sprite(atlas_key, w, h)
	local atlas = G.ASSET_ATLAS[atlas_key]
	if not atlas then
		return nil
	end
	local ok, sprite = pcall(Sprite, 0, 0, w, h, atlas, { x = 0, y = 0 })
	return ok and { n = G.UIT.O, config = { object = sprite } } or nil
end

-- What's new ----------------------------------------------------------------------
--
-- Opens by itself the first time the co-op menu is shown after an update
-- (the last version seen is kept in coop_seen_version.txt), and from its button.

local SEEN_FILE = 'coop_seen_version.txt'

-- What's new comes in pages of a few items, each wrapped to fit the window
local NEW_PER_PAGE = 4

local function show_whats_new(page)
	local items = {}
	while G.localization.misc.dictionary['k_coop_new_' .. (#items + 1)] do
		items[#items + 1] = G.localization.misc.dictionary['k_coop_new_' .. (#items + 1)]
	end
	local pages = math.max(1, math.ceil(#items / NEW_PER_PAGE))
	page = math.max(1, math.min(page or 1, pages))
	local contents = { row({ text(localize('k_coop_whats_new_title') .. ' ' .. tostring(COOP.version), 0.6, G.C.GOLD) }) }
	if pages > 1 then
		local labels = {}
		for i = 1, pages do
			labels[i] = i .. ' / ' .. pages
		end
		contents[#contents + 1] = row({ create_option_cycle({ options = labels, current_option = page, opt_callback = 'coop_whats_new_page',
			w = 3, scale = 0.7, colour = G.C.PURPLE, no_pips = true }) })
	end
	for i = (page - 1) * NEW_PER_PAGE + 1, math.min(#items, page * NEW_PER_PAGE) do
		local lines = COOP.wrap(items[i], 62)
		local nodes = {}
		for j, line in ipairs(lines) do
			nodes[#nodes + 1] = row({ text((j == 1 and '- ' or '  ') .. line, 0.34) }, 'cl', 0.01)
		end
		contents[#contents + 1] = row({ col(nodes, { align = 'cl', padding = 0.05, minw = 11 }) }, 'cl', 0)
	end
	contents[#contents + 1] = row({ text(localize('k_coop_whats_new_more'), 0.28, G.C.UI.TEXT_LIGHT) }, 'cm', 0.08)
	G.FUNCS.overlay_menu({ definition = create_UIBox_generic_options({ contents = contents }) })
end

G.FUNCS.coop_whats_new = function()
	show_whats_new(1)
	pcall(love.filesystem.write, SEEN_FILE, tostring(COOP.version))
end

G.FUNCS.coop_whats_new_page = function(args)
	show_whats_new(args.to_key)
end

function COOP.maybe_show_whats_new()
	if COOP.whats_new_checked then
		return
	end
	COOP.whats_new_checked = true
	local ok, seen = pcall(love.filesystem.read, SEEN_FILE)
	if ok and seen == tostring(COOP.version) then
		return
	end
	-- after the page is up (a page build can't open an overlay itself)
	G.E_MANAGER:add_event(Event({
		trigger = 'after',
		delay = 0.4,
		func = function()
			if not G.OVERLAY_MENU then
				G.FUNCS.coop_whats_new()
			end
			return true
		end,
	}))
end

-- History ----------------------------------------------------------------------

local function history_row(e)
	local H = COOP.HISTORY
	local mode = (e.run == 'daily' and localize('k_coop_daily') or localize('k_coop_history_normal'))
		.. ((e.challenge and e.challenge ~= 'none') and (' / ' .. H.challenge_name(e.challenge)) or '')
	return row({
		col({ text(tostring(e.date or ''), 0.3, G.C.UI.TEXT_LIGHT) }, { align = 'cl', minw = 2 }),
		col({ text(localize(e.won and 'k_coop_history_won' or 'k_coop_history_lost'), 0.32, e.won and G.C.GREEN or G.C.RED) }, { align = 'cl', minw = 1.6 }),
		col({ text(localize('k_ante') .. ' ' .. tostring(e.ante or 0), 0.32) }, { align = 'cl', minw = 1.4 }),
		col({ text(number_format(e.best or 0), 0.32, G.C.CHIPS) }, { align = 'cr', minw = 1.8 }),
		col({ text('  ' .. mode, 0.28, G.C.UI.TEXT_LIGHT) }, { align = 'cl', minw = 3.6 }),
		col({ text(COOP.truncate(tostring(e.partner or '?'), 14), 0.28, G.C.FILTER) }, { align = 'cl', minw = 2 }),
	}, 'cm', 0.02)
end

G.FUNCS.coop_history = function()
	local H = COOP.HISTORY
	local list = H.load()
	local today = COOP.CHALLENGE.today()
	local best = H.best_daily(today)
	local contents = {
		row({ text(localize('k_coop_history'), 0.6, G.C.GOLD) }),
		row({ text(localize('k_coop_daily_today') .. ': ' .. H.challenge_name(COOP.CHALLENGE.daily_challenge(today)), 0.36, G.C.FILTER) }),
		row({ text(best and H.share_text(best) or localize('k_coop_daily_none'), 0.3, best and G.C.WHITE or G.C.UI.TEXT_INACTIVE) }),
	}
	if #list == 0 then
		contents[#contents + 1] = row({ text(localize('k_coop_history_empty'), 0.34, G.C.UI.TEXT_INACTIVE) }, 'cm', 0.2)
	end
	for i = 1, math.min(#list, 10) do
		contents[#contents + 1] = history_row(list[i])
	end
	if list[1] then
		contents[#contents + 1] = row({ button('coop_history_copy', localize('k_coop_history_copy'), G.C.BLUE, 4.2) }, 'cm', 0.1)
	end
	G.FUNCS.overlay_menu({ definition = create_UIBox_generic_options({ contents = contents }) })
end

-- copies today's best daily result, or else the last run
G.FUNCS.coop_history_copy = function()
	local H = COOP.HISTORY
	local e = H.best_daily(COOP.CHALLENGE.today()) or H.load()[1]
	if e then
		love.system.setClipboardText(H.share_text(e))
		play_sound('card1')
	end
end
