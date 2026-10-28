-- Tarots / spectrals on the partner's cards.
--
-- Click cards in the partner's hand (top panel) to mark them as targets, with
-- nothing selected in your own hand. A card-targeting consumable (Strength,
-- Death, The Magician, Talisman...) then becomes usable: instead of acting on
-- your hand it is sent to the partner, whose game runs the real effect on
-- their own cards, as if they had used it themselves.

COOP.TAROT = COOP.TAROT or {}
local T = COOP.TAROT

T.queue = {}

local function targets_card(card)
	local c = card.ability and card.ability.consumeable
	return c and c.max_highlighted ~= nil
end

local function partner_mode(card)
	return COOP.is_active() and targets_card(card) and G.hand and #G.hand.highlighted == 0 and #COOP.PV.targets() > 0
end

-- Partner -> us ------------------------------------------------------------

function T.on_partner_use(key, ids)
	T.queue[#T.queue + 1] = { key = key, ids = ids }
end

local function run(job)
	local wanted = {}
	for id in string.gmatch(job.ids, '[^;]+') do
		wanted[tonumber(id)] = true
	end
	local cards = {}
	for _, c in ipairs(G.hand.cards) do
		if wanted[c.sort_id] then
			cards[#cards + 1] = c
		end
	end
	local center = G.P_CENTERS[job.key]
	if #cards == 0 or not center then
		return -- cards were played or discarded meanwhile
	end

	G.hand:unhighlight_all()
	for _, c in ipairs(cards) do
		G.hand:add_to_highlighted(c, true)
	end
	COOP.popup(localize({ type = 'variable', key = 'coop_partner_used', vars = { localize({ type = 'name_text', set = center.set, key = center.key }) } }), G.C.SECONDARY_SET.Tarot)

	-- a temporary copy of their consumable runs the real effect here
	local tmp = Card(G.consumeables.T.x, G.consumeables.T.y, G.CARD_W, G.CARD_H, nil, center,
		{ bypass_discovery_center = true, bypass_discovery_ui = true })
	tmp.coop_remote = true
	tmp:use_consumeable(G.consumeables)
	G.E_MANAGER:add_event(Event({
		func = function()
			tmp:remove()
			G.hand:unhighlight_all()
			return true
		end,
	}))
end

-- Runs queued effects once our hand is idle, so they never collide with our
-- own scoring or drawing.
function T.update()
	if #T.queue == 0 then
		return
	end
	if G.STATE ~= G.STATES.SELECTING_HAND or G.CONTROLLER.locked or (G.play and #G.play.cards > 0) then
		return
	end
	local job = table.remove(T.queue, 1)
	local ok, err = pcall(run, job)
	if not ok then
		sendWarnMessage('partner tarot failed: ' .. tostring(err), COOP.id)
	end
end

-- Us -> partner ------------------------------------------------------------

function T.install_hooks()
	local can_use_ref = Card.can_use_consumeable
	function Card:can_use_consumeable(any_state, skip_check)
		if not partner_mode(self) then
			return can_use_ref(self, any_state, skip_check)
		end
		-- check the partner's targets against the card's own rules
		local real = G.hand.highlighted
		G.hand.highlighted = COOP.PV.targets()
		local ok, res = pcall(can_use_ref, self, any_state, skip_check)
		G.hand.highlighted = real
		return ok and res
	end

	local use_ref = Card.use_consumeable
	function Card:use_consumeable(area, copier)
		if self.coop_remote or not partner_mode(self) then
			return use_ref(self, area, copier)
		end
		local ids = {}
		for _, c in ipairs(COOP.PV.targets()) do
			ids[#ids + 1] = c.coop_id
			c:juice_up(0.5, 0.5)
		end
		COOP.send('use_on_partner', { key = self.config.center.key, ids = table.concat(ids, ';') })
		COOP.PV.clear_targets()
		play_sound('tarot1')
	end
end
