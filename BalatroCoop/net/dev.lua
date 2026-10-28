-- Dev mode: two Balatro windows on one PC playing a real co-op run together,
-- no Steam friend needed. Started by dev/start_dev.bat:
--
--   Balatro.exe --coop-dev host    the window you play (left half)
--   Balatro.exe --coop-dev guest   the bot's window (right half, autopilot on)
--
-- Steam P2P (net/steam.lua) is swapped for UDP on 127.0.0.1, so the lobby,
-- the run and every message go through exactly the same code as with a
-- friend. The guest window never saves anything (it shares your profile) and
-- never talks to Steam.

COOP.DEV = COOP.DEV or {}
local DEV = COOP.DEV
local SN = COOP.STEAMNET

local PORTS = { host = 47811, guest = 47812 }
local IDS = { host = '1', guest = '2' }
local NAMES = { host = 'Ты (дев)', guest = 'Бот' }

local function launch_role()
	for i, a in ipairs(arg or {}) do
		if a == '--coop-dev' then
			local r = arg[i + 1]
			if r == 'host' or r == 'guest' then
				return r
			end
		end
	end
	local env = os.getenv('COOP_DEV')
	if env == 'host' or env == 'guest' then
		return env
	end
end

DEV.role = launch_role()

function DEV.on()
	return DEV.role ~= nil
end

if not DEV.role then
	return
end

-- '--coop-lang en-us': the dev windows play in that language (for recording
-- the site's clips), and your saved language is never touched.
local function launch_lang()
	for i, a in ipairs(arg or {}) do
		if a == '--coop-lang' then
			return arg[i + 1]
		end
	end
end

DEV.lang = launch_lang()
if DEV.lang and G.SETTINGS then
	local own, own_real = G.SETTINGS.language, G.SETTINGS.real_language
	G.SETTINGS.language, G.SETTINGS.real_language = DEV.lang, nil -- Steamodded also loads real_language's texts
	G:set_language()
	-- saving writes the settings: with the player's own language
	for _, fn in ipairs({ 'save_settings', 'save_progress' }) do
		local ref = Game[fn]
		G[fn] = function(self, ...)
			G.SETTINGS.language, G.SETTINGS.real_language = own, own_real
			local ok, err = pcall(ref, self, ...)
			G.SETTINGS.language, G.SETTINGS.real_language = DEV.lang, nil
			if not ok then
				error(err, 0)
			end
		end
	end
	NAMES.host, NAMES.guest = 'Player', 'Partner'
end

local other = DEV.role == 'host' and 'guest' or 'host'
local socket_ok, socket = pcall(require, 'socket')
local json_ok, json = pcall(require, 'json')
local udp

local function open()
	if udp ~= nil then
		return udp ~= false
	end
	udp = false
	if not (socket_ok and json_ok) then
		sendWarnMessage('dev: luasocket/json missing', COOP.id)
		return false
	end
	local s = socket.udp()
	local ok, err = s:setsockname('127.0.0.1', PORTS[DEV.role])
	if not ok then
		sendWarnMessage('dev: port ' .. PORTS[DEV.role] .. ' busy: ' .. tostring(err), COOP.id)
		return false
	end
	s:settimeout(0)
	udp = s
	return true
end

-- the fake Steam: same functions, local transport
SN.available = function()
	return open()
end
SN.my_id = function()
	return IDS[DEV.role]
end
SN.my_name = function()
	return NAMES[DEV.role]
end
SN.friends_in_game = function()
	return { { id = IDS[other], name = NAMES[other] } }
end
SN.send = function(id, tbl)
	if not open() or id ~= IDS[other] then
		return false
	end
	local ok, data = pcall(json.encode, tbl)
	if not ok then
		return false
	end
	return udp:sendto(data, '127.0.0.1', PORTS[other]) ~= nil
end
SN.receive = function()
	local out = {}
	if not open() then
		return out
	end
	for _ = 1, 200 do
		local data = udp:receivefrom()
		if not data then
			break
		end
		local ok, msg = pcall(json.decode, data)
		if ok and type(msg) == 'table' then
			out[#out + 1] = { from = IDS[other], msg = msg }
		end
	end
	return out
end
SN.accept = function()
	return true
end
SN.close = function() end
SN.invite_dialog = function() end
SN.set_connect = function() end
SN.friend_connect = function()
	return nil
end
SN.on_join_requested = function() end
-- the guest knocks on the host from the start, like after a Steam invite
SN.launch_line = function()
	return DEV.role == 'guest' and ('+coop_join ' .. IDS.host) or ''
end

-- The guest shares your profile but must never write it.
local function silence_saving()
	if DEV.role ~= 'guest' or DEV.silenced or not G.SAVE_MANAGER then
		return
	end
	DEV.silenced = true
	G.SAVE_MANAGER.channel = { push = function() end }
	G.STEAM = nil -- no stats or achievements from the bot
	local save_settings_ref = G.save_settings
	G.save_settings = function() end
	DEV.save_settings_ref = save_settings_ref
end

-- Each window takes half of the screen.
local function place_window()
	if DEV.placed or not love.window then
		return
	end
	DEV.placed = true
	pcall(function()
		local dw, dh = love.window.getDesktopDimensions(1)
		local w, h = math.floor(dw / 2), math.floor(dh * 0.9)
		local x, y, borderless = DEV.role == 'host' and 0 or w, 30, false
		if DEV.lang and dw >= 2400 then
			-- recording the site's clips: the host is a borderless 1920x1080
			-- in the top left corner, the bot gets the strip to its right
			if DEV.role == 'host' then
				w, h, x, y, borderless = 1920, 1080, 0, 0, true
			else
				w, h, x, y = dw - 1920, math.floor(dh * 0.6), 1920, 30
			end
		end
		G.SETTINGS.WINDOW.screenmode = 'Windowed'
		love.window.updateMode(w, h, { fullscreen = false, resizable = not borderless, borderless = borderless, display = 1 })
		love.window.setPosition(x, y, 1)
		love.window.setTitle('Balatro Co-op dev: ' .. NAMES[DEV.role])
		love.resize(w, h)
	end)
end

-- The host opens a lobby by itself; the guest gets ready by itself; the run
-- starts as soon as both are there (options can still be changed first:
-- the start waits START_DELAY seconds after the guest is ready).
local START_DELAY = 4

local function auto_lobby()
	local t = G.TIMERS.REAL
	if G.STAGE ~= G.STAGES.MAIN_MENU or t < 2 then
		return
	end
	local l = COOP.get_lobby()
	if DEV.role == 'host' then
		if not l and not DEV.opened then
			DEV.opened = true
			COOP.SL.host_open()
		elseif l and COOP.SL.connected() and DEV.autostart then
			local guest_ready = false
			for _, p in ipairs(l:get_players()) do
				if p.id ~= l.player_id and p.ready then
					guest_ready = true
				end
			end
			if guest_ready and COOP.partner_version == tostring(COOP.version) then
				DEV.ready_at = DEV.ready_at or t
				if t - DEV.ready_at > START_DELAY then
					DEV.ready_at = nil
					COOP.SL.start()
				end
			else
				DEV.ready_at = nil
			end
		end
	elseif l and COOP.SL.connected() then
		local me = l._players[l.player_id]
		if me and not me.ready and (not DEV.ready_try or t - DEV.ready_try > 3) then
			DEV.ready_try = t
			COOP.SL.toggle_ready()
		end
	end
end

-- after a run (game over, back to menu) the next one starts again by itself;
-- not while recording (the 'start' command starts it)
DEV.autostart = not DEV.lang

-- Each dev run starts with co-op cards in play, so their effects show up
-- without hunting for them: one half of Yin/Yang each, and a few cards with
-- co-op seals and enhancements in hand.
local function showcase_run()
	if G.STAGE ~= G.STAGES.RUN or G.STATE ~= G.STATES.SELECTING_HAND or not COOP.is_active() then
		return
	end
	if DEV.showcased == G.GAME.pseudorandom.seed then
		return
	end
	DEV.showcased = G.GAME.pseudorandom.seed
	SMODS.add_card({ key = DEV.role == 'host' and 'j_coop_yin' or 'j_coop_yang' })
	SMODS.add_card({ set = 'Base', area = G.hand, seal = 'coop_bond' })
	SMODS.add_card({ set = 'Enhanced', enhancement = 'm_coop_torch', area = G.hand })
	SMODS.add_card({ set = 'Enhanced', enhancement = DEV.role == 'host' and 'm_coop_mirror' or 'm_coop_beacon', area = G.hand })
	SMODS.add_card({ set = 'Base', area = G.hand, edition = 'e_coop_union' })
end

-- Commands from a file in Balatro's save folder, for driving a window
-- without its keyboard (staging the site's clips): coop_dev_cmd_host.txt /
-- coop_dev_cmd_guest.txt, one per line: fx, bot, pause, play, give <key>,
-- enhance <key>, seal <key>, money <n>, casino, wheel <0-7>, ping <level>,
-- score <share>, win <margin>, ghost <joker>, burn.
local CMD_FILE = 'coop_dev_cmd_' .. DEV.role .. '.txt'
DEV.cmd_at = 0

local function commands()
	if G.TIMERS.REAL < DEV.cmd_at then
		return
	end
	DEV.cmd_at = G.TIMERS.REAL + 1
	if not love.filesystem.getInfo(CMD_FILE) then
		return
	end
	local text = love.filesystem.read(CMD_FILE) or ''
	love.filesystem.remove(CMD_FILE)
	-- one command per line: 'name argument'
	for line in text:gmatch('[^' .. string.char(13, 10) .. ']+') do
		local cmd, a = line:match('^%s*(%S+)%s*(%S*)')
		sendInfoMessage('dev command: ' .. tostring(cmd) .. ' ' .. tostring(a), COOP.id)
		local ok, err = pcall(function()
			local F = COOP.FX
			if cmd == 'fx' then
				DEV.fx_pending = true -- shown at the next hand to pick (see below)
			elseif cmd == 'bot' then
				COOP.BOT.toggle()
			elseif cmd == 'pause' or cmd == 'play' then
				COOP.BOT.on = cmd == 'play'
			elseif cmd == 'stopat' then
				DEV.stop_at = a -- 'shop' or 'hand': the autopilot plays on, then pauses there
				COOP.BOT.on = true
			elseif cmd == 'start' then
				COOP.SL.start()
			elseif cmd == 'lategame' then
				-- a late-game board for the clips: strong jokers with
				-- editions, levelled hands, money, ante 6
				local set = DEV.role == 'host'
					and { { 'j_duo', 'e_polychrome' }, { 'j_trio', 'e_holo' }, { 'j_family', 'e_negative' }, { 'j_blueprint', 'e_negative' }, { 'j_cavendish', 'e_foil' } }
					or { { 'j_tribe', 'e_polychrome' }, { 'j_order', 'e_holo' }, { 'j_card_sharp', 'e_negative' }, { 'j_brainstorm', 'e_negative' }, { 'j_duo', 'e_foil' } }
				for _, j in ipairs(set) do
					SMODS.add_card({ key = j[1], edition = j[2] })
				end
				for name in pairs(G.GAME.hands) do
					level_up_hand(nil, name, true, 6)
				end
				ease_dollars(80)
				ease_ante(5)
				G.GAME.round_resets.blind_ante = G.GAME.round_resets.ante
			elseif cmd == 'give' then
				SMODS.add_card({ key = a })
			elseif cmd == 'enhance' then
				SMODS.add_card({ set = 'Enhanced', enhancement = a, area = G.hand })
			elseif cmd == 'seal' then
				SMODS.add_card({ set = 'Base', area = G.hand, seal = a })
			elseif cmd == 'money' then
				ease_dollars(tonumber(a) or 20)
			elseif cmd == 'casino' then
				G.FUNCS.coop_casino_open()
			elseif cmd == 'wheel' then
				local i = tonumber(a) or 0
				COOP.send('wheel', { i = i })
				COOP.SOCIAL.on_wheel_self(i)
			elseif cmd == 'ping' then
				local c = G.shop_jokers and G.shop_jokers.cards[1]
				if c then
					COOP.SOCIAL.ping_card(c, tonumber(a) or 4)
				end
			elseif cmd == 'score' then
				F.score_in((G.GAME.blind and G.GAME.blind.chips or 300) * (tonumber(a) or 0.6))
			elseif cmd == 'win' then
				F.team_win(tonumber(a) or 3)
			elseif cmd == 'ghost' then
				local j = G.jokers and G.jokers.cards[tonumber(a) or 1]
				if j then
					F.comet(j, F.partner_jokers, { G.C.BLUE, G.C.WHITE })
				end
			elseif cmd == 'burn' then
				local c = G.hand and G.hand.cards[#G.hand.cards]
				if c then
					F.burn(c)
					G.hand:remove_card(c)
					c:start_dissolve()
				end
			end
		end)
		if not ok then
			sendWarnMessage('dev command ' .. tostring(cmd) .. ': ' .. tostring(err), COOP.id)
		end
	end
end

-- the showcase waits for a hand to pick, with the partner's side on the
-- board; the autopilot pauses for it
local function pending_showcase()
	if not DEV.fx_pending or G.STATE ~= G.STATES.SELECTING_HAND or not (COOP.PV and COOP.PV.hand_area) then
		return
	end
	DEV.fx_pending = false
	local was_on = COOP.BOT.on
	COOP.BOT.on = false
	COOP.DEVPANEL.showcase()
	G.E_MANAGER:add_event(Event({
		trigger = 'after', delay = 18, blockable = false, blocking = false, timer = 'REAL',
		func = function()
			COOP.BOT.on = was_on
			return true
		end,
	}))
end

-- 'stopat': pause the autopilot once the game gets there
local function stop_at()
	local s = DEV.stop_at
	if not s then
		return
	end
	local there = (s == 'shop' and G.STATE == G.STATES.SHOP and G.shop_jokers and #G.shop_jokers.cards > 0)
		or (s == 'hand' and G.STATE == G.STATES.SELECTING_HAND and COOP.SB.my_turn() == true and COOP.PV and COOP.PV.hand_area)
	if there then
		DEV.stop_at = nil
		COOP.BOT.on = false
		COOP.BOT.pending = nil
		if G.hand then
			G.hand:unhighlight_all()
		end
	end
end

function DEV.update()
	pcall(commands)
	pcall(stop_at)
	pcall(pending_showcase)
	silence_saving()
	place_window()
	auto_lobby()
	local ok, err = pcall(showcase_run)
	if not ok and not DEV.showcase_err then
		DEV.showcase_err = true
		sendWarnMessage("dev showcase: " .. tostring(err), COOP.id)
	end
end
