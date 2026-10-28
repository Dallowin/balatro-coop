# Changelog

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
