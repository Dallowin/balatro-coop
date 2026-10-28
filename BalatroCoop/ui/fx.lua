-- Co-op visual effects in Balatro's look:
--
--   ghosts          a see-through copy of our card glides to the partner
--                   and dissolves there: what a co-op card sends them
--   comets          a spinning pixel with a square tail: what arrives from
--                   the partner's side
--   score label     the partner's hand flies into our round score (+1,232)
--   paired shimmer  a pair joker whose other half the partner holds is drawn
--                   with the Union edition shader, like a living edition
--   dissolves       Torch burns away in fire colours, Swap dissolves and
--                   materializes in spectral colours (the game's dissolve
--                   shader), with the CRT glitch the game uses
--   background      the team win swirls the background in chips blue and
--                   mult red, one colour for each player
--
-- No score flames: they are the game's own "you beat the blind" signal.
-- Everything is cosmetic and local; nothing here is sent or counted.

COOP.FX = COOP.FX or {}
local FX = COOP.FX

FX.TEAL = HEX('2FB8A8')
FX.PARTNER = HEX('5DA9FF')
FX.FIRE = { HEX('FF9A3C'), HEX('FE5F55'), HEX('FDA200') }
FX.GOLD = { G.C.GOLD, HEX('FFE5A3') }
FX.SPECTRAL = { G.C.SECONDARY_SET.Spectral, G.C.WHITE }

local function now()
	return G.TIMERS.REAL
end

local function resolve(m)
	if type(m) == 'function' then
		m = m()
	end
	return m and m.T and m or nil
end

local function colour_list(c)
	if type(c) == 'table' and type(c[1]) == 'table' then
		return c
	end
	return { c or G.C.WHITE, G.C.WHITE }
end

-- Paired shimmer ---------------------------------------------------------------------

local function install_shimmer()
	SMODS.DrawStep({
		key = 'coop_paired',
		order = 21, -- right after editions
		func = function(card, layer)
			if not (card.ability and card.ability.set == 'Joker' and card.area == G.jokers) then
				return
			end
			local short = card.config.center.key:match('^j_coop_(.+)$')
			if not (short and COOP.CARDS and COOP.CARDS.PAIRS[short] and COOP.CARDS.paired(card)) then
				return
			end
			local union = G.P_CENTERS.e_coop_union
			if union and union.shader and not card.edition then
				card.children.center:draw_shader(union.shader, nil, card.ARGS.send_to_shader)
			end
		end,
		conditions = { vortex = false, facing = 'front' },
	})
end

-- Dissolves ---------------------------------------------------------------------------

-- a card flagged coop_dissolve = { colours } dissolves in those colours
local function install_dissolves()
	local ref = Card.start_dissolve
	function Card:start_dissolve(colours, silent, time_fac, no_juice)
		if self.coop_dissolve then
			colours = self.coop_dissolve
			time_fac = (time_fac or 1) * 1.6
			self.coop_dissolve = nil
		end
		return ref(self, colours, silent, time_fac, no_juice)
	end
end

-- the CRT shader's own glitch (Steamodded sends it as 0): a short burst
function FX.glitch(time, amount)
	FX.glitch_until = now() + (time or 0.35)
	FX.glitch_amount = amount or 0.4
end

local function install_glitch()
	local crt = SMODS.ScreenShaders and SMODS.ScreenShaders.CRT
	if not (crt and crt.send_vars) then
		return
	end
	local ref = crt.send_vars
	crt.send_vars = function(self)
		local vars = ref(self)
		local left = (FX.glitch_until or 0) - now()
		if left > 0 and type(vars) == 'table' then
			vars.glitch_intensity = (FX.glitch_amount or 0.4) * math.min(1, left * 6)
		end
		return vars
	end
end

-- Background -----------------------------------------------------------------------

function FX.swirl(a, b, hold)
	pcall(function()
		ease_background_colour({ new_colour = a, special_colour = b, contrast = 3 })
		FX.swirl_until = now() + (hold or 1.6)
	end)
end

-- Small touches: juice and square sparks ----------------------------------------------

function FX.burst(target, colours, opts)
	pcall(function()
		local m = resolve(target)
		if not m then
			return
		end
		opts = opts or {}
		local w, h = m.T.w * (opts.size or 0.6), m.T.h * (opts.size or 0.6)
		local p = Particles(m.T.x + (m.T.w - w) / 2, m.T.y + (m.T.h - h) / 2, w, h, {
			timer = 0.008, scale = opts.scale or 0.3, speed = opts.speed or 3,
			lifespan = opts.lifespan or 0.5, colours = colour_list(colours), fill = true,
		})
		p.created_on_pause = true
		G.E_MANAGER:add_event(Event({
			trigger = 'after', delay = opts.time or 0.15, blockable = false, blocking = false, timer = 'REAL',
			func = function()
				p:fade(0.3)
				return true
			end,
		}))
		G.E_MANAGER:add_event(Event({
			trigger = 'after', delay = (opts.time or 0.15) + (opts.lifespan or 0.5) + 0.5, blockable = false, blocking = false, timer = 'REAL',
			func = function()
				p:remove()
				return true
			end,
		}))
	end)
end

local function touch(target, colours, power)
	local m = resolve(target)
	if not m then
		return
	end
	if m.juice_up then
		m:juice_up(power or 0.3, (power or 0.3) * 0.6)
	end
	FX.burst(m, colours, { size = 0.5 })
end

-- Layer above the cards ------------------------------------------------------------
--
-- An attention_text entry in G.I.UIBOX: the game draws those last, after
-- every card. Items: 'comet'.

FX.items = {}

local DRAW = {}

local function centre(m)
	m = resolve(m)
	if not (m and m.VT and m.VT.w) then
		return nil
	end
	return m.VT.x + m.VT.w / 2, m.VT.y + m.VT.h / 2, m
end

local function smooth(k)
	k = math.max(0, math.min(1, k))
	return k * k * (3 - 2 * k)
end

local function mix(a, b, k)
	return { a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k, a[3] + (b[3] - a[3]) * k, 1 }
end

-- The arc every co-op effect travels on, from a to b, bowing towards the top
-- of the screen. Returns a point and the arc's normal.
local function arc(ax, ay, bx, by, f, t)
	local dx, dy = bx - ax, by - ay
	local len = math.sqrt(dx * dx + dy * dy) + 1e-6
	local nx, ny = -dy / len, dx / len
	if ny > 0 then
		nx, ny = -nx, -ny
	end
	local bulge = math.min(1.4, len * 0.2)
	local off = 4 * f * (1 - f) * bulge + math.sin(f * math.pi * 3 - (t or 0) * 6) * 0.06 * math.sin(math.pi * f)
	return ax + dx * f + nx * off, ay + dy * f + ny * off, nx, ny
end

local function add(item)
	item.born = now()
	FX.items[#FX.items + 1] = item
	return item
end

local layer = { attention_text = true, states = { visible = true } }

function layer:translate_container()
	Node.translate_container(self)
end

function layer:draw()
	if #FX.items == 0 then
		return
	end
	love.graphics.push()
	love.graphics.scale(G.TILESCALE * G.TILESIZE)
	for _, it in ipairs(FX.items) do
		if not it.dead then
			local ok, err = pcall(DRAW[it.kind], it, now() - it.born)
			if not ok then
				it.dead = true
				love.graphics.setShader()
				sendWarnMessage('fx ' .. it.kind .. ': ' .. tostring(err), COOP.id)
			end
		end
	end
	love.graphics.setShader()
	love.graphics.setColor(1, 1, 1, 1)
	love.graphics.pop()
end

local function ensure_layer()
	layer.container = G.ROOM
	for _, v in ipairs(G.I.UIBOX) do
		if v == layer then
			return
		end
	end
	table.insert(G.I.UIBOX, layer)
end

-- Ghost: the card's projection -------------------------------------------------------
--
-- What one of our cards sends to the partner is shown the way the game
-- shows cards: a see-through copy of it (the Ether edition shader) lifts off
-- the card, glides over to the receiver and dissolves there in chips blue.
-- The copy is in no card area, so nothing ever counts it.

local GHOST_COLOURS = { G.C.BLUE, G.C.WHITE }

function FX.ghost(card, to, opts)
	opts = opts or {}
	local tx, ty = centre(to)
	if not (card and card.is and card:is(Card) and tx) then
		return false
	end
	local ok, err = pcall(function()
		local g = copy_card(card, nil, opts.scale or 0.75)
		g.states.drag.can, g.states.click.can, g.states.hover.can = false, false, false
		g:set_edition('e_coop_ether', true, true)
		-- starts on the card, the movement smoothing glides it to the receiver
		g.VT.x, g.VT.y = card.VT.x, card.VT.y
		g.T.x, g.T.y = tx - g.T.w / 2, ty - g.T.h / 2 - 0.2
		g:juice_up(0.3, 0.3)
		G.E_MANAGER:add_event(Event({
			trigger = 'after', delay = opts.hold or 0.55, blockable = false, blocking = false, timer = 'REAL',
			func = function()
				local landing = resolve(to)
				if landing and landing.juice_up then
					landing:juice_up(0.35, 0.25)
				end
				play_sound(opts.sound or 'tarot1', opts.pitch or 1.4, 0.5)
				if opts.on_land then
					pcall(opts.on_land)
				end
				g:start_dissolve(GHOST_COLOURS, true, 0.8)
				return true
			end,
		}))
	end)
	if ok then
		play_sound('cardSlide2', 1.2, 0.5)
	else
		sendWarnMessage('fx ghost: ' .. tostring(err), COOP.id)
	end
	return ok
end

-- (no drawn link between the cards: Balatro never draws lines)
function FX.link() end

-- Comet: a spinning pixel with a square tail, flying along the arc -------------------

local SHADOW = { 0, 0, 0, 0.3 }
local PX = 0.075

local function pixel(x, y, s, c, a, r)
	love.graphics.push()
	love.graphics.translate(x, y)
	love.graphics.rotate(r or 0)
	love.graphics.setColor(SHADOW[1], SHADOW[2], SHADOW[3], SHADOW[4] * (a or 1))
	love.graphics.rectangle('fill', -s / 2 + 0.03, -s / 2 + 0.04, s, s)
	love.graphics.setColor(c[1], c[2], c[3], (c[4] or 1) * (a or 1))
	love.graphics.rectangle('fill', -s / 2, -s / 2, s, s)
	love.graphics.pop()
end

function DRAW.comet(it, t)
	t = t - it.delay
	if t < 0 then
		return
	end
	local ax, ay = centre(it.a)
	local bx, by, landing = centre(it.b)
	ax, ay = ax or it.ax, ay or it.ay
	bx, by = bx or it.bx, by or it.by
	if not (ax and bx) then
		it.dead = true
		return
	end
	it.ax, it.ay, it.bx, it.by = ax, ay, bx, by
	local k = math.min(1, t / it.time)
	local x, y = arc(ax, ay, bx, by, smooth(k), now())
	if not it.landed then
		it.tail[#it.tail + 1] = { x, y }
		if #it.tail > 14 then
			table.remove(it.tail, 1)
		end
	end
	if k >= 1 and not it.landed then
		it.landed = now()
		if landing then
			FX.burst(landing, it.colours, { size = 0.45, speed = it.big and 6 or 4 })
			if landing.juice_up then
				landing:juice_up(it.big and 0.6 or 0.35, it.big and 0.4 or 0.2)
			end
		end
		if it.on_land then
			pcall(it.on_land)
		end
		if it.sound ~= false then
			play_sound(it.sound or 'generic1', it.pitch or 1.3, it.big and 0.7 or 0.5)
		end
	end
	local fade = it.landed and math.max(0, 1 - (now() - it.landed) / 0.25) or 1
	if fade <= 0 then
		it.dead = true
		return
	end
	local size = it.big and 1.5 or 1
	local n = #it.tail
	for i, p in ipairs(it.tail) do
		local f = i / n
		pixel(p[1], p[2], PX * (0.6 + 1.2 * f) * size, it.colours[(i % #it.colours) + 1], f * fade, t * 3 + i)
	end
	if not it.landed then
		pixel(x, y, PX * 2.6 * size, it.colours[1], 1, t * 8)
		pixel(x, y, PX * 1.2 * size, G.C.WHITE, 1, -t * 8)
	end
end

function FX.comet(from, to, colours, opts)
	opts = opts or {}
	if not (centre(from) and centre(to)) then
		return
	end
	local cols = colour_list(colours)
	if FX.ghost(resolve(from), to, { sound = opts.sound, pitch = opts.pitch, on_land = opts.on_land }) then
		return
	end
	touch(from, cols, 0.2)
	add({
		kind = 'comet', a = from, b = to, tail = {}, colours = cols, delay = opts.delay or 0.15,
		time = opts.time or 0.55, big = opts.big, sound = opts.sound, pitch = opts.pitch, on_land = opts.on_land,
	})
	play_sound('cardSlide1', 1.2 + math.random() * 0.2, 0.5)
end

function FX.beam(a, b, colour, time, opts)
	FX.comet(a, b, colour, opts)
end
FX.thread = FX.beam

function FX.ring(target, colour)
	touch(target, colour, 0.4)
end

function FX.flash()
	FX.shake(1)
end

function FX.shake(n)
	if G.ROOM then
		G.ROOM.jiggle = (G.ROOM.jiggle or 0) + (n or 2)
	end
end

-- Token: a small label box flying along the arc ------------------------------------------

function FX.token(text, colour, from, to, opts)
	local ok, err = pcall(function()
		opts = opts or {}
		local fx, fy = centre(from)
		local tx, ty = centre(to)
		if not (fx and tx) then
			return
		end
		local box = UIBox({
			definition = {
				n = G.UIT.ROOT,
				config = { align = 'cm', colour = G.C.CLEAR },
				nodes = {
					{ n = G.UIT.C, config = { align = 'cm', colour = colour, r = 0.1, padding = 0.08, emboss = 0.05, shadow = true }, nodes = {
						{ n = G.UIT.O, config = { object = DynaText({ string = { text }, colours = { G.C.WHITE }, shadow = true, bump = true, scale = opts.scale or 0.5, pop_in = 0, silent = true }) } },
					} },
				},
			},
			config = { align = 'tli', offset = { x = fx, y = fy }, major = G.ROOM_ATTACH, bond = 'Weak', instance_type = 'POPUP' },
		})
		local trail = Particles(0, 0, 0, 0, { timer = 0.02, scale = 0.25, speed = 1.2, lifespan = 0.5, attach = box, colours = { colour, G.C.WHITE } })
		trail.created_on_pause = true
		local start, flight = now(), opts.time or 0.6
		G.E_MANAGER:add_event(Event({
			blockable = false, blocking = false, timer = 'REAL',
			func = function()
				local k = math.min(1, (now() - start) / flight)
				local nx, ny = centre(to)
				nx, ny = nx or tx, ny or ty
				local x, y = arc(fx, fy, nx, ny, smooth(k), 0)
				box.alignment.offset.x = x - box.T.w / 2
				box.alignment.offset.y = y - box.T.h / 2
				box.T.r = 0.15 * math.sin(k * math.pi * 2)
				if k < 1 then
					return false
				end
				local landing = type(to) == 'function' and to() or to
				if landing then
					FX.burst(landing, { colour, G.C.WHITE }, { size = 0.6, speed = 5 })
					if landing.juice_up then
						landing:juice_up(0.6, 0.4)
					end
				end
				play_sound(opts.sound or 'chips2', opts.pitch or 1, 0.7)
				if opts.on_land then
					pcall(opts.on_land)
				end
				trail:remove()
				box:remove()
				return true
			end,
		}))
		play_sound('cardSlide1', 1.1, 0.6)
	end)
	if not ok then
		sendWarnMessage('fx token: ' .. tostring(err), COOP.id)
	end
end

-- Targets ----------------------------------------------------------------------------

function FX.partner_hand()
	local PV = COOP.PV
	return PV and (PV.hand_area or PV.joker_area)
end

function FX.partner_jokers()
	local PV = COOP.PV
	return PV and (PV.joker_area or PV.hand_area)
end

function FX.partner_card(key)
	local area = COOP.PV and COOP.PV.joker_area
	for _, c in ipairs(area and area.cards or {}) do
		if c.config.center.key == key then
			return c
		end
	end
	return FX.partner_jokers()
end

function FX.score_counter()
	return (G.HUD and G.HUD:get_UIE_by_ID('chip_UI_count')) or G.deck
end

-- Co-op moments ----------------------------------------------------------------------

-- the partner's hand flies from their side into our round score as a label
-- (no flames: in Balatro they mean the score beat the blind)
function FX.score_in(amount)
	local from = COOP.PV and COOP.PV.play_area and #COOP.PV.play_area.cards > 0 and COOP.PV.play_area or FX.partner_hand()
	local blind = G.GAME.blind and G.GAME.blind.chips or 0
	local big = blind > 0 and amount >= blind * 0.5
	FX.token('+' .. number_format(amount), G.C.CHIPS, from, FX.score_counter, {
		time = 0.6, scale = big and 0.65 or 0.5,
		on_land = function()
			if big then
				FX.shake(2)
			end
		end,
	})
end

-- the turn comes over: our cards stir
function FX.your_turn()
	G.E_MANAGER:add_event(Event({
		trigger = 'after', delay = 0.3, blockable = false, blocking = false, timer = 'REAL',
		func = function()
			for i, c in ipairs(G.hand and G.hand.cards or {}) do
				c:juice_up(0.12, 0.08)
			end
			return true
		end,
	}))
end

-- The team beat the blind. margin = team score / blind target.
function FX.team_win(margin)
	pcall(function()
		local big = (margin or 1) >= 2
		FX.swirl(G.C.BLUE, G.C.RED, big and 2.4 or 1.6)
		FX.glitch(big and 0.35 or 0.2, big and 0.5 or 0.3)
		-- both sides send a gold comet into the blind
		local blind_ui = G.HUD_blind or G.deck
		FX.comet(FX.partner_hand, blind_ui, FX.GOLD, { big = true, time = 0.6, sound = 'multhit1' })
		FX.comet(G.hand, blind_ui, { G.C.GOLD, G.C.RED }, { big = true, time = 0.6, delay = 0.25, sound = false })
		if G.GAME.blind and G.GAME.blind.juice_up then
			G.GAME.blind:juice_up(0.6, 0.4)
		end
		attention_text({
			text = localize(big and 'k_coop_fx_team_big' or 'k_coop_fx_team'),
			scale = big and 1.1 or 0.85,
			hold = 1.4,
			major = G.play,
			backdrop_colour = big and G.C.GOLD or G.C.BLUE,
			align = 'cm',
			offset = { x = 0, y = -1.6 },
			silent = true,
		})
		play_sound(big and 'multhit2' or 'multhit1', 1, 0.7)
		FX.shake(big and 4 or 2)
	end)
end

-- Card moments ----------------------------------------------------------------------

-- Torch burns out: the card dissolves in fire
function FX.burn(card)
	card.coop_dissolve = FX.FIRE
	FX.burst(card, FX.FIRE, { size = 0.9, speed = 6, scale = 0.4, lifespan = 0.8, time = 0.4 })
	FX.shake(2)
	play_sound('magic_crumple', 1.2, 0.6)
end

-- Swap: ours dissolves away, theirs materializes, the screen glitches
function FX.swap_out(card)
	card.coop_dissolve = FX.SPECTRAL
	FX.glitch(0.35)
end

function FX.swap_in(card)
	pcall(function()
		card:start_materialize(FX.SPECTRAL)
	end)
	FX.glitch(0.25)
end

-- Paired jokers pulse together with their other half now and then: a
-- heartbeat shared across both boards.
local HEARTBEAT_EVERY = 4
FX.beat_at = 0
function FX.heartbeat()
	if not (G.jokers and COOP.CARDS and COOP.CARDS.paired) or now() < FX.beat_at then
		return
	end
	FX.beat_at = now() + HEARTBEAT_EVERY
	for _, c in ipairs(G.jokers.cards) do
		local short = c.config.center.key:gsub('^j_coop_', '')
		local other = COOP.CARDS.PAIRS[short]
		if other and COOP.CARDS.paired(c) then
			c:juice_up(0.12, 0.06)
			local half = FX.partner_card('j_coop_' .. other)
			if half and half.juice_up then
				half:juice_up(0.12, 0.06)
			end
		end
	end
end

function FX.update()
	ensure_layer()
	for i = #FX.items, 1, -1 do
		if FX.items[i].dead then
			table.remove(FX.items, i)
		end
	end
	if G.STAGE ~= G.STAGES.RUN then
		FX.items = {}
	elseif COOP.is_active() then
		FX.heartbeat()
	end
	if FX.swirl_until and now() > FX.swirl_until then
		FX.swirl_until = nil
		pcall(ease_background_colour_blind, G.STATE)
	end
end

function FX.install()
	install_dissolves()
	install_glitch()
end

install_shimmer() -- draw steps register while the mod loads
