# Changelog

## 1.0.0

First release for WoW Forever (interface 16001).

- Chat filters: short one-line messages for loot, money, experience, reputation,
  quests, achievements, auctions, trade skills, channel names and player status.
  Patterns are built from the game's own strings, so they work in every client language.
- Chat window: transparent, messages slide in and fade out, tabs and edit box
  appear when needed. Movable and resizable, with detached windows.
- Loot list: a floating, background-less list of what you loot, with the item icon,
  quality colour, stack count, how many you now carry, and a green arrow when the
  item level beats what you wear. Hover a line for the item tooltip, click the list
  to keep it on screen.
- Demo mode: `/lpd` shows sample chat lines and a filled loot list until typed again.
- Built for the Forever client rules: no Blizzard function is replaced, typed
  commands stay secure, and protected ("secret") chat during boss encounters is
  shown untouched.
