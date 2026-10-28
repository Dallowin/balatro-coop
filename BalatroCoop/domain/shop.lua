-- One shop for two players.
--
-- The host's shop is the real one. Every shop card gets a sync id (sid), and
-- the host broadcasts the list of what is on sale whenever it changes. The
-- guest's shop mirrors that list: its own generated cards are thrown away and
-- the host's cards are recreated by key.
--
-- Whatever leaves a player's shop (bought, redeemed, pack opened) is reported
-- as 'taken' so it disappears for the other player too. Money stays separate:
-- the buyer pays. A reroll by the guest is paid by the guest and performed on
-- the host's shop. Rerolls only happen while both are in the shop, because
-- the shop only closes when both pressed "Next round".

COOP.SHOP = COOP.SHOP or {}
local S = COOP.SHOP

local AREAS = { 'shop_jokers', 'shop_vouchers', 'shop_booster' }
local each_shop_card -- defined below, used by the purchase checks above it

function S.reset()
	S.next_sid = 0
	S.last_sent = nil
	S.listing = nil -- latest listing from the host (guest only)
	S.present = {} -- sids present in our shop last frame
	S.removing = {} -- sids we removed ourselves (not a purchase)
	S.taken = {} -- sids we took; never re-add them even if a stale listing has them
	S.pending_reroll = false
	S.claimed = {} -- host: sid -> 'host' | 'guest', who got it
	S.waiting = {} -- guest: sid -> the purchase waiting for the host's answer
	S.approved = {} -- guest: sid -> true while replaying an approved purchase
	S.buying = {} -- guest: sids bought; never pulled out of the shop by the sync
end
S.reset()

-- Purchases --------------------------------------------------------------------
--
-- Both players buy from their own copy of the same shop, so two quick clicks
-- could both get the same card. The host settles it: a guest purchase first
-- asks the host ('claim'), the host reserves the card and answers
-- ('claim_result'); only then does the guest's purchase go through. The host
-- checks the same reservations for its own purchases.

local function shop_card(card)
	return card and card.coop_sid and card.area
		and (card.area == G.shop_jokers or card.area == G.shop_vouchers or card.area == G.shop_booster)
end

-- Returns true when the purchase may go ahead right now.
local function may_buy(card, replay)
	if not COOP.is_active() or not shop_card(card) then
		return true
	end
	local sid = card.coop_sid
	local lobby = MPAPI.get_current_lobby()
	if lobby and lobby.is_host then
		if S.claimed[sid] == 'guest' then
			COOP.popup(localize('k_coop_already_bought'), G.C.RED)
			return false
		end
		S.claimed[sid] = 'host'
		return true
	end
	if S.approved[sid] then
		return true
	end
	if not S.waiting[sid] then
		S.waiting[sid] = { replay = replay, card = card }
		COOP.send('claim', { sid = sid })
		card:juice_up(0.2, 0.2)
	end
	return false
end

-- host
function S.on_claim(sid)
	local present = false
	each_shop_card(function(card)
		if card.coop_sid == sid then
			present = true
		end
	end)
	local ok = present and S.claimed[sid] == nil
	if ok then
		S.claimed[sid] = 'guest'
		S.host_on_taken(sid)
	end
	COOP.send('claim_result', { sid = sid, ok = ok })
end

-- guest
function S.on_claim_result(sid, ok)
	local pending = S.waiting[sid]
	S.waiting[sid] = nil
	if not pending then
		return
	end
	local replay = pending.replay
	-- the answer can come after we already left the shop: buying then would
	-- touch a card that is gone (crash in buy_from_shop)
	if ok and not (G.STATE == G.STATES.SHOP and shop_card(pending.card)) then
		return
	end
	if ok then
		S.approved[sid] = true
		S.buying[sid] = true -- keep the card in place until the purchase is done
		local done, err = pcall(replay)
		S.approved[sid] = nil
		if not done then
			sendWarnMessage('approved purchase failed: ' .. tostring(err), COOP.id)
		end
	else
		COOP.popup(localize('k_coop_already_bought'), G.C.RED)
		each_shop_card(function(card)
			if card.coop_sid == sid then
				S.removing[sid] = true
				card:start_dissolve()
			end
		end)
	end
end

local function is_host()
	local lobby = MPAPI.get_current_lobby()
	return lobby and lobby.is_host
end

-- The shop UI stays alive while a pack bought there is being opened.
local function shop_exists()
	return G.shop and G.shop_jokers and G.shop_vouchers and G.shop_booster
end

local function shop_ready()
	return G.STATE == G.STATES.SHOP and shop_exists()
end

each_shop_card = function(fn)
	for _, name in ipairs(AREAS) do
		local area = G[name]
		if area then
			for i = #area.cards, 1, -1 do
				fn(area.cards[i], name)
			end
		end
	end
end

local function remove_card(card)
	if card.area then
		card.area:remove_card(card)
	end
	card:remove()
end

-- Host --------------------------------------------------------------------

local function describe(card, area_name)
	local center = card.config.center
	return {
		sid = card.coop_sid,
		area = area_name,
		key = center.key,
		set = center.set,
		edition = card.edition and card.edition.key or '',
		booster_pos = card.ability.booster_pos or 0,
	}
end

function S.host_update()
	local items, parts = {}, {}
	each_shop_card(function(card, area_name)
		if not card.coop_sid then
			S.next_sid = S.next_sid + 1
			card.coop_sid = S.next_sid
		end
		local d = describe(card, area_name)
		items[#items + 1] = d
		parts[#parts + 1] = d.sid .. d.key .. d.edition
	end)
	table.sort(parts)
	local signature = table.concat(parts, ',') .. '|' .. tostring(G.GAME.current_round.reroll_cost)
	if signature ~= S.last_sent then
		S.last_sent = signature
		COOP.send('shop', { round = G.GAME.round, reroll_cost = G.GAME.current_round.reroll_cost, items = items })
	end
end

-- The guest bought / opened something: take it out of the real shop too.
function S.host_on_taken(sid)
	each_shop_card(function(card)
		if card.coop_sid == sid then
			if card.ability.booster_pos and G.GAME.current_round.used_packs then
				G.GAME.current_round.used_packs[card.ability.booster_pos] = 'USED'
			end
			if card.shop_voucher and G.GAME.current_round.voucher and G.GAME.current_round.voucher.spawn then
				G.GAME.current_round.voucher.spawn[card.config.center.key] = false
			end
			card:start_dissolve()
		end
	end)
end

-- Same as G.FUNCS.reroll_shop, minus the payment (the guest already paid).
function S.host_reroll()
	G.E_MANAGER:add_event(Event({
		trigger = 'immediate',
		func = function()
			G.GAME.round_scores.times_rerolled.amt = G.GAME.round_scores.times_rerolled.amt + 1
			calculate_reroll_cost(false)
			for i = #G.shop_jokers.cards, 1, -1 do
				local c = G.shop_jokers:remove_card(G.shop_jokers.cards[i])
				c:remove()
			end
			play_sound('coin2')
			play_sound('other1')
			for _ = 1, G.GAME.shop.joker_max - #G.shop_jokers.cards do
				local card = create_card_for_shop(G.shop_jokers)
				G.shop_jokers:emplace(card)
				card:juice_up()
			end
			return true
		end,
	}))
end

-- Guest -------------------------------------------------------------------

local function create_mirror(item)
	local area = G[item.area]
	local center = G.P_CENTERS[item.key]
	if not area or not center then
		return
	end
	local card
	if item.area == 'shop_booster' then
		card = Card(area.T.x + area.T.w / 2, area.T.y, G.CARD_W * 1.27, G.CARD_H * 1.27, G.P_CARDS.empty, center,
			{ bypass_discovery_center = true, bypass_discovery_ui = true })
		create_shop_card_ui(card, 'Booster', area)
		card.ability.booster_pos = item.booster_pos
	elseif item.area == 'shop_vouchers' then
		card = Card(area.T.x + area.T.w / 2, area.T.y, G.CARD_W, G.CARD_H, G.P_CARDS.empty, center,
			{ bypass_discovery_center = true, bypass_discovery_ui = true })
		card.shop_voucher = true
		create_shop_card_ui(card, 'Voucher', area)
	else
		card = SMODS.create_card({ set = item.set, key = item.key, area = area, no_edition = true, skip_materialize = true })
		if item.edition ~= '' then
			card:set_edition(item.edition, true, true)
		end
		create_shop_card_ui(card, item.set, area)
		card:set_cost()
	end
	card.coop_sid = item.sid
	card:start_materialize()
	area:emplace(card)
	if item.area == 'shop_vouchers' then
		area.config.card_limit = math.max(area.config.card_limit, #area.cards)
	end
end

function S.guest_update()
	local listing = S.listing
	local wanted = {}
	if listing and listing.round == G.GAME.round then
		for _, item in ipairs(listing.items) do
			-- playing cards for sale (Magic Trick) can't be rebuilt from a key
			if not S.taken[item.sid] and item.set ~= 'Default' and item.set ~= 'Enhanced' then
				wanted[item.sid] = item
			end
		end
		G.GAME.current_round.reroll_cost = listing.reroll_cost
	end

	-- detect what the player took since last frame
	local now = {}
	each_shop_card(function(card)
		if card.coop_sid then
			now[card.coop_sid] = true
		end
	end)
	for sid in pairs(S.present) do
		if not now[sid] and not S.removing[sid] then
			S.taken[sid] = true
			COOP.send('taken', { sid = sid })
		end
	end
	S.removing = {}

	if not shop_ready() or G.CONTROLLER.locked then
		S.present = now
		return
	end

	-- drop our own generated cards and whatever the host no longer sells
	each_shop_card(function(card)
		-- a card we are buying (approved, purchase still animating) or waiting for
		-- the host on must stay put: the game reads its area a moment later
		local ours = card.coop_sid and (S.taken[card.coop_sid] or S.waiting[card.coop_sid] or S.buying[card.coop_sid])
		if not ours and (not card.coop_sid or (listing and not wanted[card.coop_sid])) then
			if card.coop_sid then
				S.removing[card.coop_sid] = true
				now[card.coop_sid] = nil
			end
			remove_card(card)
		end
	end)
	-- add what the host sells and we don't show yet
	for sid, item in pairs(wanted) do
		if not now[sid] then
			create_mirror(item)
			now[sid] = true
		end
	end
	S.present = now
end

function S.on_listing(round, reroll_cost, items)
	S.listing = { round = round, reroll_cost = reroll_cost, items = items }
end

-- Per frame ---------------------------------------------------------------

function S.update()
	if not shop_exists() then
		S.present = {}
		S.last_sent = nil
		return
	end
	if is_host() then
		if S.pending_reroll and shop_ready() and not G.CONTROLLER.locked then
			S.pending_reroll = false
			S.host_reroll()
		end
		S.host_update()
	else
		S.guest_update()
	end
end

function S.install_hooks()
	-- jokers / consumables / playing cards: "Buy" and "Buy and use"
	local buy_ref = G.FUNCS.buy_from_shop
	G.FUNCS.buy_from_shop = function(e)
		local card = e and e.config and e.config.ref_table
		-- no room: refuse before reserving, or the card would vanish for both
		if COOP.is_active() and shop_card(card) and e.config.id ~= 'buy_and_use' and not G.FUNCS.check_for_buy_space(card) then
			e.disable_button = nil
			return false
		end
		if not may_buy(card, function()
			return buy_ref(e)
		end) then
			return false
		end
		return buy_ref(e)
	end

	-- vouchers ("Redeem") and packs ("Open") go through use_card in the shop
	local use_ref = G.FUNCS.use_card
	G.FUNCS.use_card = function(e, mute, nosave)
		local card = e and e.config and e.config.ref_table
		if not may_buy(card, function()
			return use_ref(e, mute, nosave)
		end) then
			return
		end
		return use_ref(e, mute, nosave)
	end

	local reroll_ref = G.FUNCS.reroll_shop
	G.FUNCS.reroll_shop = function(e)
		if not COOP.is_active() or is_host() then
			return reroll_ref(e)
		end
		-- guest: pay here, let the host reroll the shared shop
		stop_use()
		local cost = G.GAME.current_round.reroll_cost
		if cost > 0 then
			ease_dollars(-cost)
		end
		G.GAME.current_round.free_rerolls = math.max(G.GAME.current_round.free_rerolls - 1, 0)
		COOP.send('reroll', { round = G.GAME.round })
	end
end
