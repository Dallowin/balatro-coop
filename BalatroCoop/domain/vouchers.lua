-- Shared vouchers: a voucher redeemed by either player is redeemed for both
-- (shop size, discounts, extra hands/discards, Telescope...). Since one
-- purchase now upgrades two players, vouchers cost COOP.VOUCHER_PRICE_MULT more.

COOP.VOUCHERS = COOP.VOUCHERS or {}
local V = COOP.VOUCHERS

COOP.VOUCHER_PRICE_MULT = 1.3

function V.on_partner_redeem(key)
	local center = G.P_CENTERS[key]
	if not center or G.GAME.used_vouchers[key] then
		return
	end
	G.GAME.used_vouchers[key] = true
	if G.GAME.current_round.voucher and G.GAME.current_round.voucher.spawn then
		G.GAME.current_round.voucher.spawn[key] = false
	end
	Card.apply_to_run(nil, center)
	COOP.popup(localize({ type = 'variable', key = 'coop_partner_voucher', vars = { localize({ type = 'name_text', set = 'Voucher', key = key }) } }), G.C.SECONDARY_SET.Voucher)
	play_sound('coin1')
end

function V.install_hooks()
	local redeem_ref = Card.redeem
	function Card:redeem()
		if COOP.is_active() and self.ability.set == 'Voucher' then
			COOP.send('voucher', { key = self.config.center_key })
		end
		return redeem_ref(self)
	end

	local set_cost_ref = Card.set_cost
	function Card:set_cost()
		set_cost_ref(self)
		if COOP.is_active() and self.ability and self.ability.set == 'Voucher' and self.cost > 0 then
			self.cost = math.floor(self.cost * COOP.VOUCHER_PRICE_MULT + 0.5)
		end
	end
end
