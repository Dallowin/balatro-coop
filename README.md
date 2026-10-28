# Balatro Co-op

[▶ Watch the teaser on YouTube](https://www.youtube.com/watch?v=5GjqEjpJz3o)

**Two players, one run, one shared score against every blind.**

A co-op mode for [Balatro](https://store.steampowered.com/app/2379780/Balatro/): you and a friend play the same seed, take turns playing hands, and your chips add up against a single, tougher blind. You win together and you lose together.

🌐 **Website:** https://dallowin.github.io/balatro-coop/ · 🇷🇺 [Читать по-русски](README_RU.md)

> **Status:** early, playable, actively developed. Expect bugs. Please [report them](https://github.com/Dallowin/balatro-coop/issues).

## Features

- **Shared blind**: hands are played in turns (or simultaneously), scores add up, the requirement is scaled for two.
- **Play via Steam**: invite any Steam friend, even one who isn't playing: they get the invite in Steam chat and Balatro starts right into your lobby. No lobby code, no server.
- **Casino in the shop**: slots with joker reels (Blueprint is wild, x100 jackpot) and blackjack with real cards and casino rules, for your shared money.
- **Shared shop, money and vouchers**: you shop together and leave together; vouchers are shared (and 30% more expensive).
- **Shared deck** (option): 104 cards for the two of you; card changes (tarots, seals, editions) are seen by both.
- **See your partner**: their hand and jokers above yours (with their jokers' real values), and their chips x mult counting up live in your HUD.
- **Tarots on your partner's cards**.
- **Team jokers**: 3 shared slots and 9 rare team jokers with their own art (Pass, Bridge, Echo, Double Strike, Chain, Contrast, Shared Hand, Support, Second Wind).
- **Optional rules**: resonance (the more evenly you both score in a blind, the bigger an XMult, up to X1.5, whatever your builds) and a 70% per-player share cap. Both off by default.
- **Shared consumables**: tarots, planets and spectrals are one pool for both, with 4 slots.
- **Pair jokers and co-op cards**: Yin & Yang, Sun & Moon, Sword & Shield (strong only when split between you), new Tarots, the Swap spectral, Bond and Sacrifice seals, five co-op enhancements (Bulwark, Mirror, Beacon, Twin, Torch), Union and Ether editions with their own shaders, all from the Co-op Pack.
- **Talk without typing**: a Dota-style chat wheel (hold Y), card pings (middle mouse / G) and an Offer button in the shop.
- **Daily run, challenges, co-op bosses and team decks**: one seed a day for every pair, five challenges, four bosses that hit teamwork, two decks made for two.
- **Run history** with a copyable result to share.
- **Lobby options**: shared or separate deck, alternating or simultaneous turns, resonance, share cap, difficulty, evil bosses, deck and stake.
- **Solo test mode**: a mirror partner that replays your own moves, to try things out alone.
- English and Russian.

## Requirements

Balatro on PC with these mods:

| Mod | Where to get it |
| --- | --- |
| [Lovely Injector](https://github.com/ethangreen-dev/lovely-injector) | [Releases](https://github.com/ethangreen-dev/lovely-injector/releases) |
| [Steamodded](https://github.com/Steamodded/smods) (1.0.0 beta or newer) | [Releases](https://github.com/Steamodded/smods/releases) |

MultiplayerAPI is no longer needed. Remove the **Multiplayer** mod (e.g. `multiplayer-0.5.5`) if you have it.

**Both players need the same version of Balatro Co-op.** The lobby checks it and won't start otherwise.

## Installation

1. Install **Lovely**: put `version.dll` (or `winmm.dll`, depending on the release) next to `Balatro.exe`.
   (Steam → right-click Balatro → Manage → Browse local files.)
2. Open the mods folder: `%AppData%\Balatro\Mods` (create `Mods` if it doesn't exist).
3. Put **Steamodded** there.
4. Download `BalatroCoop-x.y.z.zip` from the [latest release](https://github.com/Dallowin/balatro-coop/releases/latest) and extract it into `Mods`, so you get `Mods\BalatroCoop\BalatroCoop.json`.
5. Start Balatro from Steam.

## How to play

**Via Steam (easiest)**: both of you must be Steam friends with Balatro running.

1. Open the Co-op menu → **Play via Steam** → **Invite** next to your friend.
2. Your friend sees "… invites you to co-op" and clicks **Accept**.
3. Your friend clicks **Ready**, you click **Start**.

**With a lobby code**: **Create lobby** (the code is copied to your clipboard), your friend uses **Join with code**.

The in-game **Rules** button explains everything; the host chooses the options in the lobby.

## Reporting bugs

Open an [issue](https://github.com/Dallowin/balatro-coop/issues) with what happened and, if possible, the log from `%AppData%\Balatro\Mods\lovely\log` (lines with `Coop` or `BalatroCoop`).

## Credits

- [Lovely Injector](https://github.com/ethangreen-dev/lovely-injector) and [Steamodded](https://github.com/Steamodded/smods): Balatro Co-op is built on them.
- Balatro by LocalThunk / Playstack. This is an unofficial fan mod.

## License

[GPL-3.0](LICENSE).
