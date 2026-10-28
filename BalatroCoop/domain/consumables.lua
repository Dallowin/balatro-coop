-- Shared consumables: tarots, planets and spectrals are one pool for the team.
-- Whatever lands in one player's consumable slots (bought, from a pack kept
-- for later, made by a joker) shows up in the partner's slots too, and once
-- one of you uses, sells or loses it, it is gone for both. Each card gets a
-- shared id (ability.coop_cid); our slots are checked a few times a second.
-- The effect of a used card stays with whoever used it (a planet levels your
-- hand; a tarot can still target the partner's cards, see domain/tarot.lua).

COOP.CONS = COOP.CONS or {}
local CS = COOP.CONS

local POLL_EVERY = 0.25

function CS.reset()
	CS.known = {} -- cid -> true for every shared card in our slots
	CS.next_id = 0
	CS.timer = 0
end
CS.reset()

local function is_host()
	local lobby = COOP.get_lobby()
	return not lobby or lobby.is_host
end

local function new_cid()
	CS.next_id = CS.next_id + 1
	return (is_host() and 'h' or 'g') .. CS.next_id
end

local function find(cid)
	for _, c in ipairs(G.consumeables and G.consumeables.cards or {}) do
		if c.ability and c.ability.coop_cid == cid then
			return c
		end
	end
end

-- Game:update (co-op runs only)
function CS.update(dt)
	if not G.consumeables then
		return
	end
	CS.timer = CS.timer + (dt or 0)
	if CS.timer < POLL_EVERY then
		return
	end
	CS.timer = 0
	local present = {}
	for _, c in ipairs(G.consumeables.cards) do
		local center = c.config and c.config.center
		if center and not c.removed and not c.coop_removing then
			local cid = c.ability.coop_cid
			if not cid then
				-- new on our side: tell the partner
				cid = new_cid()
				c.ability.coop_cid = cid
				COOP.send('cons_add', { cid = cid, key = center.key, edition = c.edition and c.edition.key or '' })
			end
			present[cid] = true
		end
	end
	for cid in pairs(CS.known) do
		if not present[cid] then
			COOP.send('cons_remove', { cid = cid })
		end
	end
	CS.known = present
end

function CS.on_add(cid, key, edition)
	if CS.known[cid] or find(cid) or not G.P_CENTERS[key] or not G.consumeables then
		return
	end
	local ok, err = pcall(function()
		local card = SMODS.create_card({ key = key, area = G.consumeables, no_edition = true, skip_materialize = true })
		card.ability.coop_cid = cid
		if edition ~= '' then
			card:set_edition(edition, true, true)
		end
		card:add_to_deck()
		G.consumeables:emplace(card)
		card:start_materialize()
		CS.known[cid] = true
	end)
	if not ok then
		sendWarnMessage('shared consumable failed: ' .. tostring(err), COOP.id)
	end
end

function CS.on_remove(cid)
	CS.known[cid] = nil
	local card = find(cid)
	if card then
		card.coop_removing = true -- still in the slots while it dissolves: not "new"
		card:start_dissolve(nil, true)
	end
end
