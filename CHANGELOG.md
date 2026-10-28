# Changelog

## 0.12.0

### Changed
- **No MultiplayerAPI any more**: the mod needs only Lovely and Steamodded. The co-op panel sits in the top left corner of the main menu; play goes through Steam. Lobbies by code through the Multiplayer server are gone.

### New
- **Pair jokers**: Yin & Yang, Sun & Moon, Sword & Shield. Each half is weak alone and strong while your partner holds the other half. Own a half and the other one comes to the next shop.
- **Co-op cards**: Tarots The Bond, The Offering, The Fortress and The Twins; the Swap spectral (trade a joker with your partner); Bond and Sacrifice seals; Bulwark cards (held in hand, they boost every partner hand X1.2). All from the new **Co-op Pack** and **Mega Co-op Pack** in the shop.
- **Chat wheel**: hold Y, the wheel opens around the mouse, move onto a phrase and let go. Your partner sees it in a bubble, in their own language.
- **Pings**: middle mouse button (or G) over a card lights it up for your partner: "look!", again "take it!", again "don't". Shop cards have an **Offer** button next to Buy.
- **Where's your partner**: the team panel says "Partner: in the casino" (shop, pack...) while you two are in different places.
- **Shared consumables**: tarots, planets and spectrals are one pool for the team, with 4 slots. Whatever one player gets, both have; used or sold by one, it's gone for both.
- **What's new** window: opens once after an update, and from a button in the co-op menu.
- **New co-op menu** with the Balatro Co-op logo; the lobby options sit in two columns and the rules come in pages.
- **Daily run** (lobby option "Run"): one seed and one fixed set of rules per day for every pair, with a challenge of the day.
- **Challenges** (lobby option "Challenge"): Sprint (2 hands, 2 discards), Tight (3 joker slots), Broke (no money, no interest), Specialists (the host plays, the guest discards), Big hands (+2 hand size). Each one scales the blind requirement so it stays fair.
- **Co-op bosses**: The Envy (the ranks your partner just played are debuffed), The Shackle (play as many cards as your partner did), The Tyrant (only the weaker score counts, doubled), The Fog (your partner's board is hidden).
- **Team decks**: Siamese (both get the same draws) and Red & Black (the host plays red suits, the guest black ones, +1 hand).
- **Lobby previews**: the chosen deck shows its card and description, the challenge what it changes and how the blind requirement is adjusted.
- **Run history** in the co-op menu, with a button to copy your result (today's best daily run first).

## 0.11.0

### New
- **Casino**: a "Casino" button in the shop opens a scene of its own (the shop slides away, like for a pack). Real, shared money, a bet you choose.
  - **Slots** with joker reels: 9 jokers, 14 combos, Blueprint is wild, a x100 jackpot for three Golden Jokers. A scrollable payout table shows every combo with its odds (about 92% paid back).
  - **Blackjack** with real cards and casino rules: 6-deck shoe, dealer stands on 17 and peeks, blackjack 3:2, insurance 2:1, double, one split (the hands slide apart).
- **Invite via Steam**: Steam's invite window, so you can invite any friend, even one who isn't playing. Accepting the invite starts Balatro and joins your lobby. "Join game" from the friends list works too.
- **Live partner scoring**: their chips x mult and the hand total count up in your HUD as it happens; their points land in the round score as soon as their hand ends.
- **Partner's jokers show their real values** (X Mult, +Chips, counters, stickers). Bridge copies those values too.
- New art for all 9 team jokers.
- **Unstick turn**: if both players sit with nobody's turn, the turn fixes itself after a few seconds, and an "Unstick turn" button shows up if anything still hangs.

### Changed
- Synergy removed: the built-in Mult relay did the same as the Echo team joker. Echo now passes 35% instead of 20%.
- Resonance reworked: no more matching ranks (it forced the same build). The more evenly you both score in a blind, the bigger an XMult, up to X1.5. Resonance and the 70% share cap are separate lobby options, both off by default.
- Leaner team panel: only what the HUD doesn't show already.
- Co-op menu: the Balatro logo no longer covers the panel; buttons sit side by side.

### Fixed
- Crash (`extra_slots_used`) when the partner's cards appeared while a tarot was being used.
- A joker made free by a skip tag was free for one player only.
- A bought joker could stay in the shop as an unbuyable ghost.
- The partner's last hand stayed in your HUD after their turn.

## 0.10.0

- **Play via Steam**: invite a Steam friend who is running Balatro, no lobby code or server needed. Steam handles the connection (NAT punching, relays), with no message rate limit.
- Connection status in the lobby and in the run ("Lost connection to partner…").

## 0.9.0

- The host decides blind selection: the guest only asks, so the two can no longer pick differently.
- Shared deck: cards already in the partner's new hand are not shuffled back; deck order is the same on both sides.
- Lobby version check: the host can't start with a different (or unknown) mod version.
- "New Run" from the game over screen starts an ordinary solo run instead of a broken co-op one.
- Mr. Bones in the partner's jokers now saves the team.
- Fixes: Bridge recursion crash, shop crash after the shop closed, players stuck after leaving the shop, a round ending twice, the partner's final score shown as 0, the partner's cards flying in all at once, the partner's boss disable/score changes not shared.

## 0.8.x

- Solo test mode with a mirror partner, strictly turn-based.
- Lobby UI: ready, options, rules, quick-phrase chat.
- Team jokers, synergy (relay, 70% cap, resonance), shared vouchers, tarots on the partner's cards.
