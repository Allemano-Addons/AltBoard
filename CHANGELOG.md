# Changelog

## 0.3.0
- Character management: right-click a name for Move left / Move right / Hide / Delete (with confirm;
  not the logged-in character). Once moved, the order is saved (`AltBoardDB.order`), new characters
  come last. "N hidden" in the title shows hidden characters dimmed so they can be unhidden.

## 0.2.1
- Reputation cells: centered standing with a thin accent progress bar (like the mockup); tooltip
  shows exact reputation, percent and how much is left to the next standing.

## 0.2.0
- Reputation section: every faction any character has seen, grouped under its header, cells show
  standing (in standing color) + percent, tooltip with exact values. Factions hidden under collapsed
  headers are kept and refreshed by ID (the player's headers are never expanded).
- Section headings fold open/closed on click (remembered).

## 0.1.1
- Fix: gold was saved as 0 at logout (GetMoney() returns 0 during PLAYER_LOGOUT on Forever).

## 0.1.0
- The board (`/ab`): characters as columns, sections Overview (level, item level, gold, rested,
  guild, location, last seen), Professions and Currency. Total gold in the title. Hush look;
  uses Hush's accent color when Hush is installed, never requires it.
- Data is saved per character (by GUID) from events only: money, level/XP, gear, zone,
  professions (GetProfessions/GetProfessionInfo) and currencies (C_CurrencyInfo).
- ESC closes the window; drag by the title bar; mouse wheel pages characters when they don't fit.

## 0.0.2
- Probe also records currencies (C_CurrencyInfo or the old API, honor). Build order changed:
  lockouts wait until the beta level cap allows raids; v0.1 = gold, currency and professions.

## 0.0.1
- Step 0: skeleton (events, SavedVariables `AltBoardDB`, `/altboard` and `/ab`) and `/altboard probe`,
  which records what the WoW Forever client returns for lockouts, professions, reputation and
  character info into `AltBoardDB.probe`.
