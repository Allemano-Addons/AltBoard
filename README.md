# AltBoard

An overview of all your characters on WoW Forever: gold, professions, currencies and
reputation, with characters as columns. Standalone (uses Hush's accent color if Hush is
installed, but never needs it).

## Install
Unzip so the folder is `Interface\AddOns\AltBoard` (the folder must be called AltBoard),
then restart the game. Log in once on each character so AltBoard can read it.

## Use
- `/ab` (or `/altboard`) or the small launcher button opens the board.
- Right-click a character name: move left/right, hide, delete.
- Right-click a row: hide it. Right-click a section heading: show hidden rows.
- Left-click a section heading: fold it.
- Left-click a character name: its gear, stats, bags and bank (hover an item for the tooltip, shift-click to link).
  The bank is remembered from the last time you opened it on that character.
- Magnifier button or `/ab find <name>`: search all characters' bags, bank and equipped items.
- Gear button or `/ab settings`: font, text size, accent color, opacity, scale, column width,
  sections, launcher.
- Something not working? `/ab errors` lists recent errors (WoW Forever hides Lua errors).
