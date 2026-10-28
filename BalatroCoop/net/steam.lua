-- Steam P2P transport: messages go straight to the partner through Steam
-- (ISteamNetworkingMessages: NAT punching, Valve's relays when that fails),
-- no server in between. The game's luasteam has no networking, so the flat
-- Steam API is called with LuaJIT FFI from the steam_api library the game
-- already loaded.
--
-- Steam ids travel as decimal strings ('7656119...').

COOP.STEAMNET = COOP.STEAMNET or {}
local SN = COOP.STEAMNET

local APP_ID = 2379780 -- Balatro
local CHANNEL = 7
local SEND_FLAGS = 8 + 32 -- reliable, restart a broken session
local FRIEND_FLAG_IMMEDIATE = 4
local MAX_RECEIVE = 64

local ffi_ok, ffi = pcall(require, 'ffi')
local json_ok, json = pcall(require, 'json')

local lib, msgs_iface, friends_iface, my_id64
local resolved = false

local DECLS = {
	'typedef struct { uint64_t game_id; uint32_t game_ip; uint16_t game_port; uint16_t query_port; uint64_t lobby; } coop_FriendGameInfo;',
	'typedef struct { void* data; int size; uint32_t conn; uint8_t peer[136]; } coop_NetMessage;',
	'void* SteamAPI_SteamNetworkingMessages_SteamAPI_v002();',
	'void* SteamAPI_SteamNetworkingUtils_SteamAPI_v004();',
	'void SteamAPI_ISteamNetworkingUtils_InitRelayNetworkAccess(void* self);',
	'void* SteamAPI_SteamFriends_v017();',
	'void* SteamAPI_SteamUser_v022();',
	'uint64_t SteamAPI_ISteamUser_GetSteamID(void* self);',
	'const char* SteamAPI_ISteamFriends_GetPersonaName(void* self);',
	'int SteamAPI_ISteamFriends_GetFriendCount(void* self, int flags);',
	'uint64_t SteamAPI_ISteamFriends_GetFriendByIndex(void* self, int index, int flags);',
	'const char* SteamAPI_ISteamFriends_GetFriendPersonaName(void* self, uint64_t id);',
	'bool SteamAPI_ISteamFriends_GetFriendGamePlayed(void* self, uint64_t id, coop_FriendGameInfo* info);',
	'void SteamAPI_SteamNetworkingIdentity_SetSteamID64(void* self, uint64_t id);',
	'uint64_t SteamAPI_SteamNetworkingIdentity_GetSteamID64(void* self);',
	'int SteamAPI_ISteamNetworkingMessages_SendMessageToUser(void* self, const void* identity, const char* data, uint32_t size, int flags, int channel);',
	'int SteamAPI_ISteamNetworkingMessages_ReceiveMessagesOnChannel(void* self, int channel, coop_NetMessage** out, int max);',
	'bool SteamAPI_ISteamNetworkingMessages_AcceptSessionWithUser(void* self, const void* identity);',
	'bool SteamAPI_ISteamNetworkingMessages_CloseSessionWithUser(void* self, const void* identity);',
	'void SteamAPI_SteamNetworkingMessage_t_Release(coop_NetMessage* msg);',
}

local LIB_NAMES = { 'steam_api64', 'steam_api', 'libsteam_api' }

local function id_string(id64)
	return (tostring(id64):gsub('ULL$', ''))
end

local function id64_of(s)
	local v = ffi.new('uint64_t', 0)
	for d in tostring(s):gmatch('%d') do
		v = v * 10 + tonumber(d)
	end
	return v
end

local function resolve()
	if resolved then
		return lib ~= nil
	end
	if not G.STEAM then
		return false -- Steam not (yet) initialised: try again later
	end
	resolved = true
	if not ffi_ok or not json_ok then
		return false
	end
	for _, decl in ipairs(DECLS) do
		pcall(ffi.cdef, decl) -- already declared (another mod, a reload) is fine
	end
	for _, name in ipairs(LIB_NAMES) do
		local ok, l = pcall(ffi.load, name)
		if ok and l then
			lib = l
			break
		end
	end
	if not lib then
		sendWarnMessage('steam: steam_api library not found', COOP.id)
		return false
	end
	local ok, err = pcall(function()
		msgs_iface = lib.SteamAPI_SteamNetworkingMessages_SteamAPI_v002()
		friends_iface = lib.SteamAPI_SteamFriends_v017()
		my_id64 = lib.SteamAPI_ISteamUser_GetSteamID(lib.SteamAPI_SteamUser_v022())
		local utils = lib.SteamAPI_SteamNetworkingUtils_SteamAPI_v004()
		if utils ~= nil then
			lib.SteamAPI_ISteamNetworkingUtils_InitRelayNetworkAccess(utils) -- warm up the relays
		end
	end)
	if not ok or msgs_iface == nil or friends_iface == nil or my_id64 == nil or my_id64 == 0 then
		sendWarnMessage('steam: networking unavailable: ' .. tostring(err), COOP.id)
		lib = nil
		return false
	end
	return true
end

function SN.available()
	return resolve()
end

function SN.my_id()
	return resolve() and id_string(my_id64) or nil
end

function SN.my_name()
	if not resolve() then
		return nil
	end
	local ok, name = pcall(function()
		return ffi.string(lib.SteamAPI_ISteamFriends_GetPersonaName(friends_iface))
	end)
	return ok and name ~= '' and name or nil
end

-- Friends who are running Balatro right now: { { id =, name = }, ... }
function SN.friends_in_game()
	local out = {}
	if not resolve() then
		return out
	end
	local info = ffi.new('coop_FriendGameInfo')
	local n = lib.SteamAPI_ISteamFriends_GetFriendCount(friends_iface, FRIEND_FLAG_IMMEDIATE)
	for i = 0, n - 1 do
		local id = lib.SteamAPI_ISteamFriends_GetFriendByIndex(friends_iface, i, FRIEND_FLAG_IMMEDIATE)
		if lib.SteamAPI_ISteamFriends_GetFriendGamePlayed(friends_iface, id, info)
			and tonumber(info.game_id % 16777216) == APP_ID then
			out[#out + 1] = {
				id = id_string(id),
				name = ffi.string(lib.SteamAPI_ISteamFriends_GetFriendPersonaName(friends_iface, id)),
			}
		end
	end
	table.sort(out, function(a, b)
		return a.name:lower() < b.name:lower()
	end)
	return out
end

local identities = {}
local function identity(id)
	if not identities[id] then
		local buf = ffi.new('uint64_t[20]') -- SteamNetworkingIdentity is 136 bytes
		lib.SteamAPI_SteamNetworkingIdentity_SetSteamID64(buf, id64_of(id))
		identities[id] = buf
	end
	return identities[id]
end

-- Sends a table (JSON) to a player. Returns true when Steam took it.
function SN.send(id, tbl)
	if not resolve() or not id then
		return false
	end
	local ok, data = pcall(json.encode, tbl)
	if not ok then
		sendWarnMessage('steam: encode failed: ' .. tostring(data), COOP.id)
		return false
	end
	local result = lib.SteamAPI_ISteamNetworkingMessages_SendMessageToUser(msgs_iface, identity(id), data, #data, SEND_FLAGS, CHANNEL)
	if result ~= 1 then
		COOP.debug('steam: send to %s failed: result %d', id, tonumber(result))
		return false
	end
	return true
end

-- Messages that arrived since the last call: { { from = id, msg = table }, ... }
local out_buf
function SN.receive()
	local out = {}
	if not resolve() then
		return out
	end
	out_buf = out_buf or ffi.new('coop_NetMessage*[?]', MAX_RECEIVE)
	local n = lib.SteamAPI_ISteamNetworkingMessages_ReceiveMessagesOnChannel(msgs_iface, CHANNEL, out_buf, MAX_RECEIVE)
	for i = 0, n - 1 do
		local m = out_buf[i]
		local data = ffi.string(m.data, m.size)
		local from = id_string(lib.SteamAPI_SteamNetworkingIdentity_GetSteamID64(m.peer))
		lib.SteamAPI_SteamNetworkingMessage_t_Release(m)
		local ok, msg = pcall(json.decode, data)
		if ok and type(msg) == 'table' then
			out[#out + 1] = { from = from, msg = msg }
		end
	end
	return out
end

-- Someone who messages us first has to be accepted before their messages
-- come through. True if there was a pending session with that player.
function SN.accept(id)
	return resolve() and lib.SteamAPI_ISteamNetworkingMessages_AcceptSessionWithUser(msgs_iface, identity(id)) or false
end

function SN.close(id)
	if resolve() and id then
		lib.SteamAPI_ISteamNetworkingMessages_CloseSessionWithUser(msgs_iface, identity(id))
	end
end
