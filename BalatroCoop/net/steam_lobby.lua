-- A lobby over Steam P2P (net/steam.lua), no server:
--   * the host picks a friend who is running Balatro and invites them
--     ('invite', repeated until answered); the friend gets a pop-up list with
--     the invite and accepts ('join')
--   * both sides then run an MPAPI local lobby, so the rest of the mod sees an
--     ordinary lobby; the game's messages travel as 'batch' packets
--   * what a server lobby would do is done with our own messages: options
--     ('meta'), ready ('ready'), start with a seed ('start'); 'ping' keeps an
--     eye on the connection and 'bye' says we left
--
-- Packets: { t = 'invite' | 'join' | 'batch' | 'ping' | 'bye', ... }

COOP.SL = COOP.SL or {}
local SL = COOP.SL
local SN = COOP.STEAMNET

local SCAN_EVERY = 1
local INVITE_EVERY = 2
local PING_EVERY = 2
local INVITE_TTL = 8 -- an invite not repeated for this long is gone
local LOST_AFTER = 12

SL.partner = nil -- { id, name, joined }
SL.invites = {} -- id -> { name, version, at }
SL.friends = {}
SL.scan_at, SL.invite_at, SL.ping_at, SL.last_heard = 0, 0, 0, 0
SL.lost_warned = false

local function now()
	return G.TIMERS and G.TIMERS.REAL or 0
end

local function lobby()
	local l = MPAPI.get_current_lobby()
	return l and l.coop_steam and l or nil
end

function SL.active()
	return lobby() ~= nil
end

function SL.connected()
	return SL.active() and SL.partner and SL.partner.joined or false
end

function SL.lost()
	return SL.connected() and now() - SL.last_heard > LOST_AFTER
end

local function player_id(id)
	return 'steam:' .. id
end

function SL.is_partner_player(p)
	return SL.partner and p.id == player_id(SL.partner.id)
end

local function hello_packet(t)
	return { t = t, name = SN.my_name() or '?', version = tostring(COOP.version) }
end

local function add_partner_player(l)
	l._players[player_id(SL.partner.id)] = { id = player_id(SL.partner.id), displayName = SL.partner.name, is_away = false }
end

-- Shared setup of the local lobby on both sides.
local function make_lobby(host)
	local current = MPAPI.get_current_lobby()
	if current then
		SL.replacing = true
		current:leave()
		SL.replacing = false
	end
	local l = MPAPI.create_local_lobby(COOP.id, { max_players = 2 })
	if not l then
		return nil
	end
	l.coop_steam = true
	l.is_host = host
	l.host_id = host and l.player_id or player_id(SL.partner.id)
	local me = l._players[l.player_id]
	if me then
		me.displayName = SN.my_name() or me.displayName
	end
	COOP.partner_version = nil
	SL.last_heard = now()
	SL.lost_warned = false
	l:on('metadata_changed', function()
		if l.is_host then
			SL.send_meta()
		end
		MPAPI.refresh_current_view()
	end)
	l.coop_partner = SL.partner
	l:on('disconnected', function()
		local p = l.coop_partner
		if not p then
			return
		end
		-- switching to a new lobby with the same partner: no goodbye
		if not (SL.replacing and SL.partner and SL.partner.id == p.id) then
			SN.send(p.id, { t = 'bye' })
		end
		if SL.partner == p and not SL.replacing then
			SL.partner = nil
		end
	end)
	return l
end

function SL.send_meta()
	local l = lobby()
	if l and l.is_host and SL.connected() then
		local copy = {}
		for k, v in pairs(l:get_metadata()) do
			copy[k] = v
		end
		COOP.send('meta', { data = copy })
	end
end

-- Host: invite a friend.
function SL.host(id, name)
	SL.partner = { id = id, name = name or '?', joined = false }
	if not make_lobby(true) then
		SL.partner = nil
		return
	end
	SL.invite_at = 0 -- send now
end

-- Guest: accept a friend's invite.
function SL.accept(id)
	local inv = SL.invites[id]
	SL.partner = { id = id, name = inv and inv.name or '?', joined = true }
	SL.invites[id] = nil
	local l = make_lobby(false)
	if not l then
		SL.partner = nil
		return
	end
	add_partner_player(l)
	SN.accept(id)
	SN.send(id, hello_packet('join'))
	COOP.send_hello()
	MPAPI.refresh_current_view()
end

function SL.leave()
	local l = lobby()
	if l then
		l:leave() -- 'disconnected' says bye
	end
end

-- Packets ---------------------------------------------------------------------

local function on_invite(from, m)
	local fresh = not SL.invites[from]
	SL.invites[from] = { name = tostring(m.name or '?'), version = tostring(m.version or '?'), at = now() }
	if fresh then
		play_sound('timpani')
		-- show it unless the player is busy with something else
		if G.STAGE == G.STAGES.MAIN_MENU and not G.OVERLAY_MENU and not MPAPI.get_current_lobby() then
			SL.open_menu()
		end
	end
end

local function on_join(m)
	local l = lobby()
	if not l or not l.is_host or SL.partner.joined then
		return
	end
	SL.partner.joined = true
	SL.partner.name = tostring(m.name or SL.partner.name)
	add_partner_player(l)
	COOP.send_hello()
	SL.send_meta()
	play_sound('highlight2')
	MPAPI.refresh_current_view()
end

local function on_bye()
	local l = lobby()
	if not l then
		return
	end
	if COOP.is_active() then
		COOP.popup(localize('k_coop_steam_left'), G.C.RED)
		SL.partner.joined = false
		return
	end
	if l.is_host then
		-- keep the lobby, wait for them to come back (the invite is resent)
		l._players[player_id(SL.partner.id)] = nil
		SL.partner.joined = false
		COOP.partner_version = nil
		MPAPI.refresh_current_view()
	else
		l.coop_partner = nil -- don't say bye back
		SL.partner = nil
		l:leave()
	end
end

local function handle(from, m)
	local p = SL.partner
	if p and from == p.id then
		SL.last_heard = now()
		if m.t == 'batch' and type(m.msgs) == 'table' then
			COOP.receive_msgs(m.msgs)
		elseif m.t == 'join' then
			on_join(m)
		elseif m.t == 'bye' then
			on_bye()
		elseif m.t == 'invite' then
			local l = lobby()
			if l and not l.is_host then
				SN.send(from, hello_packet('join')) -- our 'join' got lost
			elseif l and not p.joined and (SN.my_id() or '') > from then
				SL.invites[from] = { name = tostring(m.name or p.name), version = tostring(m.version or '?'), at = now() }
				SL.accept(from) -- we invited each other: the bigger id becomes the guest
			end
		end
	elseif m.t == 'invite' then
		on_invite(from, m)
	end
end

-- Game:update, in the menus and in a run.
function SL.update()
	if not SN.available() then
		return
	end
	if G.STEAM and G.STEAM.runCallbacks then
		pcall(G.STEAM.runCallbacks)
	end
	local t = now()
	-- friends running Balatro: let their invites through
	if t - SL.scan_at >= SCAN_EVERY and G.STAGE ~= G.STAGES.RUN then
		SL.scan_at = t
		SL.friends = SN.friends_in_game()
		for _, f in ipairs(SL.friends) do
			SN.accept(f.id)
		end
		for id, inv in pairs(SL.invites) do
			if t - inv.at > INVITE_TTL then
				SL.invites[id] = nil
			end
		end
		SL.refresh_menu()
	end
	for _, pk in ipairs(SN.receive()) do
		local ok, err = pcall(handle, pk.from, pk.msg)
		if not ok then
			sendWarnMessage('steam packet failed: ' .. tostring(err), COOP.id)
		end
	end
	local l = lobby()
	if not l or not SL.partner then
		return
	end
	if l.is_host and not SL.partner.joined and t - SL.invite_at >= INVITE_EVERY then
		SL.invite_at = t
		SN.send(SL.partner.id, hello_packet('invite'))
	end
	if SL.partner.joined and t - SL.ping_at >= PING_EVERY then
		SL.ping_at = t
		SN.send(SL.partner.id, { t = 'ping' })
	end
	-- connection state changes show in the lobby page / as a pop-up in a run
	local lost = SL.lost()
	if lost ~= SL.lost_warned then
		SL.lost_warned = lost
		if COOP.is_active() then
			COOP.popup(localize(lost and 'k_coop_steam_lost' or 'k_coop_steam_back'), lost and G.C.RED or G.C.GREEN)
		else
			MPAPI.refresh_current_view()
		end
	end
end

-- COOP.flush in a Steam lobby: everything queued goes out as one packet.
function SL.flush(outbox)
	if SL.connected() then
		SN.send(SL.partner.id, { t = 'batch', msgs = outbox })
	end
end

-- Lobby messages (handled straight away, see COOP.receive_msgs) -----------------

function SL.on_meta(data)
	local l = lobby()
	if l and not l.is_host then
		for k, v in pairs(data) do
			l._metadata[k] = v
		end
		MPAPI.refresh_current_view()
	end
end

function SL.on_ready(ready)
	local l = lobby()
	if l and SL.partner then
		local p = l._players[player_id(SL.partner.id)]
		if p then
			p.ready = ready
		end
		MPAPI.refresh_current_view()
	end
end

function SL.toggle_ready()
	local l = lobby()
	local me = l and l._players[l.player_id]
	if me then
		me.ready = not me.ready
		COOP.send('ready', { ready = me.ready })
		MPAPI.refresh_current_view()
	end
end

local function clear_ready(l)
	for _, p in pairs(l._players) do
		p.ready = false
	end
end

function SL.start()
	local l = lobby()
	if not (l and l.is_host and SL.connected()) then
		return
	end
	local seed = tostring(math.random(10000000, 99999999))
	clear_ready(l)
	COOP.send('start', { seed = seed })
	COOP.request_run(seed, l)
end

function SL.on_start(seed)
	local l = lobby()
	if l and not l.is_host then
		clear_ready(l)
		COOP.request_run(seed, l)
	end
end

-- Friends menu -------------------------------------------------------------------

local function text(str, scale, colour)
	return { n = G.UIT.T, config = { text = str, scale = scale or 0.4, colour = colour or G.C.WHITE, shadow = true } }
end

local function row(nodes, align, padding)
	return { n = G.UIT.R, config = { align = align or 'cm', padding = padding or 0.05 }, nodes = nodes }
end

local function id_button(fn, label, colour, id)
	return { n = G.UIT.C, config = { align = 'cm', minw = 1.9, minh = 0.5, r = 0.1, padding = 0.05, colour = colour,
		button = fn, ref_table = { id = id }, hover = true, shadow = true }, nodes = { text(label, 0.36) } }
end

local function menu_signature()
	local parts = {}
	for _, f in ipairs(SL.friends) do
		parts[#parts + 1] = f.id
	end
	parts[#parts + 1] = '#'
	for id in pairs(SL.invites) do
		parts[#parts + 1] = id
	end
	table.sort(parts)
	return table.concat(parts, ',')
end

local function menu_definition()
	local nodes = { row({ text(localize('k_coop_steam_title'), 0.6, G.C.FILTER) }) }
	if not SN.available() then
		nodes[#nodes + 1] = row({ text(localize('k_coop_steam_unavailable'), 0.36, G.C.RED) })
		return nodes
	end
	for id, inv in pairs(SL.invites) do
		local same = inv.version == tostring(COOP.version)
		nodes[#nodes + 1] = row({
			{ n = G.UIT.C, config = { align = 'cl', minw = 5.4 }, nodes = {
				text(MPAPI.truncate(inv.name, 18) .. ' ' .. localize('k_coop_steam_invites_you'), 0.36, G.C.GREEN),
				same and text('', 0.3) or text('  (' .. MPAPI.truncate(inv.version, 10) .. ')', 0.3, G.C.RED),
			} },
			id_button('coop_steam_accept', localize('k_coop_steam_accept'), G.C.GREEN, id),
		}, 'cm', 0.06)
	end
	nodes[#nodes + 1] = row({ text(localize('k_coop_steam_friends'), 0.42, G.C.FILTER) })
	if #SL.friends == 0 then
		nodes[#nodes + 1] = row({ text(localize('k_coop_steam_no_friends'), 0.32, G.C.UI.TEXT_INACTIVE) })
	end
	for i, f in ipairs(SL.friends) do
		if i > 8 then
			break
		end
		nodes[#nodes + 1] = row({
			{ n = G.UIT.C, config = { align = 'cl', minw = 5.4 }, nodes = { text(MPAPI.truncate(f.name, 22), 0.36) } },
			id_button('coop_steam_invite', localize('k_coop_steam_invite'), G.C.BLUE, f.id),
		}, 'cm', 0.04)
	end
	nodes[#nodes + 1] = row({ text(localize('k_coop_steam_hint'), 0.28, G.C.UI.TEXT_LIGHT) })
	return nodes
end

function SL.open_menu()
	if SN.available() then
		SL.friends = SN.friends_in_game()
	end
	G.FUNCS.overlay_menu({ definition = create_UIBox_generic_options({ contents = menu_definition() }) })
	SL.menu_box = G.OVERLAY_MENU
	SL.menu_sig = menu_signature()
end

-- Rebuild the open menu when friends come and go or an invite arrives.
function SL.refresh_menu()
	if not SL.menu_box or G.OVERLAY_MENU ~= SL.menu_box then
		SL.menu_box = nil
		return
	end
	if menu_signature() ~= SL.menu_sig then
		SL.open_menu()
	end
end

G.FUNCS.coop_steam = function()
	SL.open_menu()
end

G.FUNCS.coop_steam_invite = function(e)
	local id = e.config.ref_table.id
	local name
	for _, f in ipairs(SL.friends) do
		if f.id == id then
			name = f.name
		end
	end
	SL.menu_box = nil
	G.FUNCS.exit_overlay_menu()
	SL.host(id, name)
end

G.FUNCS.coop_steam_accept = function(e)
	local id = e.config.ref_table.id
	SL.menu_box = nil
	G.FUNCS.exit_overlay_menu()
	SL.accept(id)
end
