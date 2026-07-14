# sync/

Local sync script territory. Lives in the repo so both trading machines get updates via `git pull`.

- **Phase 1** delivers `NINJATRADER-NOTES.md` here — the mapped schema of a real `executions.db` copy plus open questions. Nothing else in this folder is built until that exists.
- **Phase 4** delivers the sync script itself: reads `executions.db` read-only (`mode=ro`), aggregates fills into trades, pushes through the app's API (never the DB), with manual (`sync.bat`) and scheduled 6am triggers.
