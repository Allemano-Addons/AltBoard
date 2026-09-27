# Changelog

## 0.7.1
- Fix: "attempt to perform arithmetic on ... a secret number value" when stats changed in
  combat. WoW Forever hides some values (attack power...) from addons during combat; stats are
  now read when combat ends, and any secret value is skipped instead of causing an error.

## 0.7.0
- Bags and bank are saved per character (counts per item; random-suffix items kept apart).
  The bank is read whenever it is open; an unreadable or just-closed bank never overwrites.
- Search items (magnifier in the board title, launcher menu, `/ab find <name>`): every
  character's bags, bank and equipped items, total + who has it; hover = item tooltip with
  the per-character split, shift-click links it.
- Character sheet tabs Gear / Bags / Bank (grid, best quality first, mouse wheel scrolls).
- Overview row "Bag space" (free slots).

## 0.6.0
- Character sheet: left-click a name on the board. Equipped items (icon, quality color, item
  level; hover = the real item tooltip, shift-click links it) and stats (attributes, melee &
  ranged, spell, resistances). Opens next to the board, follows its scale and opacity.
- Gear (links + name/quality/ilvl/icon) and stats are saved per character on equipment and
  stat events. Druids keep their caster-form stats while shapeshifted.

## 0.5.0
- Hide rows: right-click a row (name or any cell) > Hide row; right-click a reputation group
  heading > Hide all in <group>. Section headings show "N hidden"; right-click a heading to show
  hidden rows one by one or all. Saved per section (`settings.hiddenRows`), for all characters.
- Group headings with no visible rows are left out.

## 0.4.1
- Fix: the settings window never opened (color swatches got only one of three color values, the
  build failed silently and left an invisible window). A failed build now cleans up.
- Errors are recorded (last 10, in AltBoardDB.errors), announced once per session in chat and
  listed by `/ab errors` (WoW Forever does not show Lua errors). Clicks run protected.
- `Tests/smoke_test.lua`: loads the addon against a fake WoW API and clicks through board and
  settings (`lua Tests/smoke_test.lua`).

## 0.4.0
- Settings window (gear button in the title bar, `/ab settings`): font (game fonts + fonts other
  addons share via LibSharedMedia), text size, accent (follow Hush / class / custom presets),
  background opacity, window scale, column width, which sections show, whether hidden characters
  count in the gold total, launcher on/off + lock, reset window positions. All apply at once.
- Launcher button (own, movable, Hush style): left-click opens the board, right-click menu.

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
