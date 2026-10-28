-- Our own lobby: who is in it, who hosts, ready state and the options
-- (metadata). It lives on this machine only; the Steam lobby
-- (net/steam_lobby.lua) keeps the two sides in step with its own messages,
-- the solo test uses one with just us in it.
--
-- One lobby at a time: COOP.get_lobby() is nil outside a lobby. It stays
-- through the run and back to the menu until someone leaves.

COOP.LOBBY = COOP.LOBBY or {}
local LB = COOP.LOBBY

LB.current = nil

local Lobby = {}
Lobby.__index = Lobby

function COOP.get_lobby()
	return LB.current
end

-- opts: { host = bool, name = our name, view = false for no lobby page }
function LB.create(opts)
	opts = opts or {}
	if LB.current then
		LB.current:leave()
	end
	local l = setmetatable({
		is_host = opts.host ~= false,
		player_id = 'me',
		_players = {},
		_metadata = {},
		_handlers = {},
	}, Lobby)
	l.host_id = l.player_id
	l._players.me = { id = 'me', displayName = opts.name or localize('k_coop_you') }
	LB.current = l
	if opts.view ~= false then
		COOP.PAGES.show('lobby')
	end
	return l
end

function Lobby:get_players()
	local out = {}
	for _, p in pairs(self._players) do
		out[#out + 1] = p
	end
	return out
end

function Lobby:get_metadata()
	return self._metadata
end

function Lobby:set_metadata(t)
	for k, v in pairs(t) do
		self._metadata[k] = v
	end
	self:_fire('metadata_changed')
end

function Lobby:on(event, fn)
	self._handlers[event] = self._handlers[event] or {}
	table.insert(self._handlers[event], fn)
end

function Lobby:_fire(event, ...)
	for _, fn in ipairs(self._handlers[event] or {}) do
		local ok, err = pcall(fn, ...)
		if not ok then
			sendWarnMessage('lobby ' .. event .. ' failed: ' .. tostring(err), COOP.id)
		end
	end
end

-- back to the co-op menu (the page only changes in the menus, not in a run)
function Lobby:leave()
	if self._left then
		return
	end
	self._left = true
	if LB.current == self then
		LB.current = nil
	end
	self:_fire('disconnected')
	COOP.partner_version = nil
	if G.STAGE == G.STAGES.MAIN_MENU and COOP.PAGES.current == 'lobby' then
		COOP.PAGES.show('menu')
	end
end
