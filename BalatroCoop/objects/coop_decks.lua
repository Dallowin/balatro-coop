-- Team starting decks, picked in the lobby like any deck. Both play with a
-- deck each (the shared 104-card deck is turned off for them).
--
--   Siamese      both players get the very same draws, in the same order
--   Red & Black  the host plays only Hearts and Diamonds, the guest only
--                Spades and Clubs (26 cards each, +1 hand to make up for it)

local function coop_deck(def)
	def.atlas = 'centers'
	def.prefix_config = { atlas = false } -- vanilla deck backs
	def.unlocked = true
	def.discovered = true
	SMODS.Back(def)
end

coop_deck({
	key = 'siamese',
	pos = { x = 2, y = 4 },
	-- the shuffle is made identical in domain/deck.lua (COOP.siamese())
})

coop_deck({
	key = 'redblack',
	pos = { x = 1, y = 3 },
	config = { hands = 1 },
	apply = function(self, back)
		local lobby = COOP.get_lobby()
		local host = not lobby or lobby.is_host
		local keep = host and { Hearts = true, Diamonds = true } or { Spades = true, Clubs = true }
		G.E_MANAGER:add_event(Event({
			func = function()
				for i = #G.playing_cards, 1, -1 do
					local card = G.playing_cards[i]
					if card.base and not keep[card.base.suit] then
						card:remove()
					end
				end
				G.GAME.starting_deck_size = #G.playing_cards
				return true
			end,
		}))
	end,
})

function COOP.team_deck()
	local back = G.GAME and G.GAME.selected_back and G.GAME.selected_back.effect and G.GAME.selected_back.effect.center
	return back and (back.key == 'b_coop_siamese' or back.key == 'b_coop_redblack') and back.key or nil
end

function COOP.siamese()
	return COOP.team_deck() == 'b_coop_siamese'
end
