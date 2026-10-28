-- Our pages in the main menu: the co-op menu ('menu') and the lobby
-- ('lobby') take the place of the game's main menu buttons; 'vanilla' brings
-- the game's own menu back. The co-op panel in the top left corner opens
-- 'menu' and goes back.
--
-- A page change waits for Game:update: it is often asked for from inside an
-- event or a network callback, where tearing UI down is unsafe.

COOP.PAGES = COOP.PAGES or {}
local PG = COOP.PAGES

PG.builders = PG.builders or {} -- key -> function returning a UIT root
PG.current = nil
PG.pending = nil

local original_set_main_menu_UI = set_main_menu_UI

function PG.register(key, build)
	PG.builders[key] = build
end

function PG.show(key)
	PG.pending = key
end

-- rebuild the page on screen (the lobby changed, a message came in...)
function COOP.refresh_view()
	if PG.current and G.STAGE == G.STAGES.MAIN_MENU then
		PG.pending = PG.pending or PG.current
	end
end

-- the game's title and the splash logo move away while our page is up: our
-- page has its own logo
local function logo_offset(y)
	for _, key in ipairs({ 'title_top', 'SPLASH_LOGO' }) do
		local o = G[key]
		if o and o.T then
			o.coop_base_y = o.coop_base_y or o.T.y
			o.T.y = o.coop_base_y + y
			o.VT.y = o.T.y
		end
	end
end

local function remove_menu_ui()
	if G.MAIN_MENU_UI then
		G.MAIN_MENU_UI:remove()
		G.MAIN_MENU_UI = nil
	end
	if G.PROFILE_BUTTON then
		G.PROFILE_BUTTON:remove()
		G.PROFILE_BUTTON = nil
	end
end

local function render(key)
	if G.STAGE ~= G.STAGES.MAIN_MENU then
		return
	end
	if key == 'lobby' and not COOP.get_lobby() then
		key = 'menu'
	end
	remove_menu_ui()
	if key == 'vanilla' or not PG.builders[key] then
		PG.current = nil
		logo_offset(0)
		original_set_main_menu_UI()
		PG.attach_corner()
		return
	end
	logo_offset(-10)
	G.MAIN_MENU_UI = UIBox({
		definition = PG.builders[key](),
		config = { align = 'bmi', offset = { x = 0, y = 10 }, major = G.ROOM_ATTACH, bond = 'Weak' },
	})
	G.MAIN_MENU_UI.alignment.offset.y = 0
	G.MAIN_MENU_UI:align_to_major()
	PG.current = key
	PG.attach_corner()
end

-- Game:update
function PG.update()
	local key = PG.pending
	if not key then
		return
	end
	PG.pending = nil
	local ok, err = pcall(render, key)
	if not ok then
		sendWarnMessage('page ' .. tostring(key) .. ' failed: ' .. tostring(err), COOP.id)
	end
end

-- Back in the main menu (start-up, or after a run): the game builds its own
-- menu; while we are still in a lobby, the lobby page replaces it.
function set_main_menu_UI(...)
	PG.current = nil
	local res = original_set_main_menu_UI(...)
	G.COOP_CORNER = nil -- a new menu: the old panel went with the old stage
	PG.attach_corner()
	if COOP.get_lobby() and not COOP.TEST then
		PG.show('lobby')
	end
	return res
end

-- The co-op corner panel, top left (where MultiplayerAPI's panel used to be):
-- in the game's menu it opens ours, on our pages it goes back.
local CORNER_W = 2.2

local function corner_button(label, fn, colour)
	return { n = G.UIT.R, config = { align = 'cm', padding = 0.03 }, nodes = {
		{ n = G.UIT.C, config = { align = 'cm', padding = 0.08, minw = CORNER_W, maxw = CORNER_W, minh = 0.7, r = 0.1,
			hover = true, shadow = true, colour = colour, button = fn }, nodes = {
			{ n = G.UIT.T, config = { text = label, scale = 0.45, colour = G.C.UI.TEXT_LIGHT, shadow = true } },
		} },
	} }
end

local function corner_definition()
	local nodes = { { n = G.UIT.R, config = { align = 'cm' }, nodes = {
		{ n = G.UIT.T, config = { text = localize('k_coop_menu_button'), scale = 0.4, colour = G.C.UI.TEXT_LIGHT, shadow = true } },
	} } }
	if PG.current then
		nodes[#nodes + 1] = corner_button(localize('b_back'), 'coop_back_to_game_menu', G.C.ORANGE)
	else
		nodes[#nodes + 1] = corner_button(localize(COOP.get_lobby() and 'k_coop_lobby_title' or 'k_coop_play_together'), 'coop_open_menu', G.C.GREEN)
	end
	return { n = G.UIT.ROOT, config = { align = 'cm', colour = G.C.CLEAR }, nodes = {
		{ n = G.UIT.R, config = { align = 'cm', padding = 0.1, r = 0.1, emboss = 0.1, colour = G.C.BLUE, minw = CORNER_W + 0.1 }, nodes = nodes },
	} }
end

-- slides in from the left the first time, like the game's own buttons
function PG.attach_corner()
	local fresh = not G.COOP_CORNER
	if G.COOP_CORNER then
		G.COOP_CORNER:remove()
	end
	G.COOP_CORNER = UIBox({ definition = corner_definition(),
		config = { align = 'tli', offset = { x = fresh and -10 or 0, y = 0 }, major = G.ROOM_ATTACH, bond = 'Weak' } })
	G.COOP_CORNER.alignment.offset.x = 0
	G.COOP_CORNER:align_to_major()
end

G.FUNCS.coop_open_menu = function()
	PG.show(COOP.get_lobby() and 'lobby' or 'menu')
end

G.FUNCS.coop_back_to_game_menu = function()
	PG.show('vanilla')
end
