# Limpid

**A clean, transparent chat for World of Warcraft: Forever.**

Limpid does three things:

1. **Tidies chat messages.** Loot, money, experience, reputation, quests and more are
   rewritten as short one-line messages: `+ Linen Cloth x3`, `+ 41 Reputation: Ironforge`,
   `+ 2375 XP`.
2. **Replaces the chat window** with a background-less one: messages slide in, fade out
   when idle and come back when you move the mouse over them.
3. **Adds a floating loot list**, separate from the chat, showing what you just picked up.

Type `/limpid` in game to open the options.

## Features

### Message filters

Each one can be turned on or off:

- Loot, currency and received items, with roll results
- Money gains and losses with coin icons
- Experience, reputation and honor
- Quest accept / progress / completion, with rewards on a single line
- Achievements, auctions, trade skills
- Channel names shortened (`[G]`, `[P]`, `1.`), player names without brackets
- Friend and guild online / offline messages
- Optional: channel join / leave, boss emotes, pet and system messages
- Keyword highlighting for your own name, click-to-invite, copy chat (`/copychat`)

The filters are built from the game's own text, so they work in every client language.

### Chat window

- No background: only the text, with an outline so it stays readable
- Messages slide in and fade out; tabs and the edit box appear when needed
- Movable and resizable (`/limpid lock`), with detached windows from a tab's right-click menu
- Fonts, sizes, fade times and tab style are configurable, with profiles

### Loot list

- A floating list of your own loot: icon, name in quality colour, stack count and how
  many you now carry
- A green arrow when the item's level is higher than what you wear in that slot and you
  can equip it
- Looted coins summed on one line
- Hover a line for the item tooltip; click the list to keep it on screen, click anywhere
  else to let it fade
- `/limpid loot` unlocks it for moving; right-click the frame for text size and scale

## Commands

| Command | Action |
| --- | --- |
| `/limpid` or `/lim` | Open the options |
| `/limpid lock` | Unlock / lock the chat window |
| `/limpid loot` | Unlock / lock the loot list (right-click it for text size and scale) |
| `/limpid demo` or `/lpd` | Demo mode: sample lines and a filled loot list, type again to turn off |
| `/limpid copy` or `/copychat` | Open the copy window |
| `/limpid help` | List the commands in chat |

## Installation

Install from CurseForge, or copy the `Limpid` folder into
`World of Warcraft/_forever_/Interface/AddOns/`.

Limpid replaces the chat window. Turn off the chat module of any other interface addon
(ElvUI, EllesmereUI...) and do not run it next to another chat-replacement addon.

## Good to know

- During boss encounters the game protects chat text. Limpid shows those messages as
  they are, without filtering them.
- Some settings need a reload. Limpid never reloads by itself: it asks you to type `/reload`.
- The upgrade arrow compares item levels, not individual stats.

## Credits

Limpid is a port and extension of **CleanerChat** by migwynkriid, which combined
**ChatCleaner** by Lars Norberg (Goldpaw) and **Glass** by Mitchel Cabuloy (mixxorz).
All credit for the original work belongs to them. See [CREDITS.md](CREDITS.md).

## License

MIT, see [LICENSE](LICENSE). Third-party notices are in `LICENSE-ChatCleaner.txt`,
`LICENSE-Glass.txt` and [CREDITS.md](CREDITS.md).
