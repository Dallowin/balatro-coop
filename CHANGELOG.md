# Changelog

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
