# Changelog

## 0.0.2
- Probe also records currencies (C_CurrencyInfo or the old API, honor). Build order changed:
  lockouts wait until the beta level cap allows raids; v0.1 = gold, currency and professions.

## 0.0.1
- Step 0: skeleton (events, SavedVariables `AltBoardDB`, `/altboard` and `/ab`) and `/altboard probe`,
  which records what the WoW Forever client returns for lockouts, professions, reputation and
  character info into `AltBoardDB.probe`.
