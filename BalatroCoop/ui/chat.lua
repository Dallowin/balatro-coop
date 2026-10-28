-- A small chat of our own (MPAPI's chat needs server-side permissions most
-- accounts don't have). Messages ride the normal co-op batches; they are
-- shown straight away, in the lobby as well as in a run.

COOP.CHAT = COOP.CHAT or {}
local CH = COOP.CHAT

CH.MAX = 30
CH.log = CH.log or {}
CH.input = { text = '' }

local function my_name()
	local s = MPAPI.connection_state or {}
	local name = s.display_name or s.steam_name
	if not name or name == '' then
		name = localize('k_coop_you')
	end
	return name
end

function CH.add(name, text)
	CH.log[#CH.log + 1] = { name = name, text = text, at = G.TIMERS.REAL }
	while #CH.log > CH.MAX do
		table.remove(CH.log, 1)
	end
	play_sound('paper1', 1.1, 0.5)
	if G.STAGE ~= G.STAGES.RUN then
		MPAPI.refresh_current_view() -- lobby page shows the chat
	end
end

-- last n lines, newest last
function CH.lines(n)
	local out = {}
	for i = math.max(1, #CH.log - n + 1), #CH.log do
		local m = CH.log[i]
		out[#out + 1] = m.name .. ': ' .. m.text
	end
	return out
end

function CH.send(text)
	text = (text or ''):match('^%s*(.-)%s*$') or ''
	if #text == 0 then
		return
	end
	text = text:sub(1, 120)
	COOP.send('chat', { name = my_name(), text = text })
	CH.add(my_name(), text)
end

G.FUNCS.coop_chat_send = function()
	CH.send(CH.input.text)
	CH.input.text = ''
	if G.OVERLAY_MENU then
		G.FUNCS.exit_overlay_menu()
	end
end

-- Quick phrases: the game's text box only types Latin letters (it reads
-- physical keys), so the common co-op calls are one click, in any language.
CH.QUICK = {
	'need_hearts', 'need_spades', 'need_diamonds', 'need_clubs',
	'need_face', 'need_ace', 'play_flush', 'play_pairs',
	'take_joker', 'my_joker', 'wait', 'go',
	'thanks', 'gg',
}

for i, key in ipairs(CH.QUICK) do
	G.FUNCS['coop_quick_' .. i] = function()
		CH.send(localize('coop_q_' .. key))
		if G.OVERLAY_MENU then
			G.FUNCS.exit_overlay_menu()
		end
	end
end

-- Grid of quick-phrase buttons, 4 per row.
function CH.quick_rows(scale)
	scale = scale or 0.35
	local rows, row = {}, nil
	for i, key in ipairs(CH.QUICK) do
		if (i - 1) % 4 == 0 then
			row = { n = G.UIT.R, config = { align = 'cm', padding = 0.04 }, nodes = {} }
			rows[#rows + 1] = row
		end
		row.nodes[#row.nodes + 1] = UIBox_button({ button = 'coop_quick_' .. i, label = { localize('coop_q_' .. key) },
			minw = 2.4, minh = 0.5, scale = scale, colour = G.C.SECONDARY_SET.Planet })
	end
	return rows
end

-- Opens the chat: quick phrases plus a free-text box.
G.FUNCS.coop_chat_open = function()
	CH.input.text = ''
	local contents = {
		{ n = G.UIT.R, config = { align = 'cm', padding = 0.1 }, nodes = {
			{ n = G.UIT.T, config = { text = localize('k_coop_chat'), scale = 0.5, colour = G.C.WHITE } },
		} },
	}
	for _, r in ipairs(CH.quick_rows()) do
		contents[#contents + 1] = r
	end
	contents[#contents + 1] = { n = G.UIT.R, config = { align = 'cm', padding = 0.1 }, nodes = {
		create_text_input({ ref_table = CH.input, ref_value = 'text', prompt_text = localize('k_coop_chat_prompt'),
			max_length = 60, w = 7, h = 0.6, extended_corpus = true }),
	} }
	contents[#contents + 1] = { n = G.UIT.R, config = { align = 'cm', padding = 0.1 }, nodes = {
		UIBox_button({ button = 'coop_chat_send', label = { localize('k_coop_chat_send') }, minw = 2.5, minh = 0.6, colour = G.C.GREEN }),
	} }
	G.FUNCS.overlay_menu({ definition = create_UIBox_generic_options({ snap_back = true, contents = contents }) })
end
