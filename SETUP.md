# Trading Journal — Initial Setup Plan

This document is the build order for setting up the trading journal project. Work through it top to bottom. `CLAUDE.md` (in this repo's root) holds the architecture invariants — read it first; it governs every decision below. If anything here conflicts with CLAUDE.md, CLAUDE.md wins and the conflict should be flagged.

## Context in one paragraph

Personal trading journal for NinjaTrader futures trading. Two-layer model: Layer 1 is objective trade data read from NinjaTrader's local `executions.db` (SQLite) by a sync script; Layer 2 is manual journal entries. The app is Next.js on Vercel with a Postgres database (Neon or Supabase). The app's API is the single door to the database — the sync script, and later n8n and agents, all go through it. Multi-account (live vs sim strictly separated) and multi-machine (laptop + desktop) from day one.

## Phase 0 — Workspace skeleton

Target structure (the parent folder already exists or should be created):

```
trading-journal/
├── app/          ← this repo, git-initialized
│   ├── CLAUDE.md
│   ├── SETUP.md  ← this file
│   └── sync/
└── kb/           ← knowledge base, NOT your territory (Claude Cowork manages it)
```

Tasks:
1. Confirm `app/` is git-initialized with a sensible `.gitignore` (Node, `.env`, `*.db` copies).
2. Scaffold a Next.js (App Router, TypeScript) project in `app/` around the existing CLAUDE.md and this file — don't overwrite either.
3. Add `.env.example` documenting required variables (`DATABASE_URL`, plus sync-script config: machine name, API base URL, API key/secret for the sync endpoint).

## Phase 1 — Verify NinjaTrader reality (before any pipeline code)

CLAUDE.md's rule: verify, don't assume. The entire schema design depends on what `executions.db` actually contains.

1. Ask for a copy of the real `executions.db` (a copy, not the live file).
2. Open it read-only and map the actual schema: tables, columns, types, how executions relate to orders and trades, where account identifiers live, how instruments are named, what timestamps look like (timezone? epoch? local?).
3. Write findings into `sync/NINJATRADER-NOTES.md`: the mapped schema plus open questions.
4. Flag for manual testing by the trader: does NinjaTrader flush trades to the file immediately or on platform close? Does it lock the file while running? (This decides whether the 6am scheduled sync can read mid-session — the read must see committed trades, and the `mode=ro` connection protects the file either way.)

Do not proceed to Phase 2 until the real schema is mapped.

## Phase 2 — App database schema

Postgres, managed via migrations (Drizzle or Prisma — pick one and stay with it). Core tables, honoring every invariant in CLAUDE.md:

- **accounts** — `id`, `ninjatrader_account_name`, `account_type` (`live` | `simulation`), `display_name`, `created_at`.
- **sync_runs** — `id`, `source_machine`, `trigger_type` (`manual` | `scheduled`), `started_at`, `completed_at`, `status` (`success` | `partial` | `failed`), `executions_seen`, `trades_sent`, `trades_inserted`, `trades_deduped`, `error_detail`.
- **trades** (Layer 1) — `id`, `account_id` FK, `ninjatrader_trade_id`, `sync_run_id` FK, `source_machine`, `instrument_raw` (`ES 03-26`), `instrument_root` (`ES`), `direction`, `quantity`, `entry_time` / `exit_time` (TIMESTAMPTZ, UTC), `entry_price` / `exit_price`, `commission`, `gross_pnl` / `net_pnl`, `duration_seconds`, `mae` / `mfe`, `trading_session_date`, `created_at`. Constraint: `UNIQUE(account_id, ninjatrader_trade_id)`.
- **executions** — raw fills for reconstruction: `id`, `trade_id` FK (nullable until grouped), `account_id`, `ninjatrader_execution_id`, `order_id`, `time`, `price`, `quantity`, `sync_run_id`. Unique on `(account_id, ninjatrader_execution_id)`.
- **journal_entries** (Layer 2) — `id`, `trade_id` FK (unique — one entry per trade), `setup`, `reasoning`, `emotional_state`, `grade`, `notes`, `created_at`, `updated_at`. Physically separate from trades; joined only by ID.
- **screenshots** — `id`, `journal_entry_id` FK, storage URL/path, `created_at`.

Adjust field details to what Phase 1 actually found — but the invariant fields (account_id, dedup key, sync_run_id, source_machine, instrument_root, trading_session_date, TIMESTAMPTZ) are non-negotiable.

`trading_session_date` is computed at ingestion; its definition (when the trading day ends, given Globex hours vs AEST) lives in `../kb/decision-log.md`. If it isn't defined there yet, ask rather than inventing one.

## Phase 3 — API routes (the single contract)

- `POST /api/sync/runs` — open a sync run, returns `sync_run_id`.
- `POST /api/sync/trades` — batch upsert of aggregated trades + executions for a run; relies on dedup constraints; returns inserted/deduped counts.
- `PATCH /api/sync/runs/:id` — close the run with status and counts.
- `GET /api/trades` — filterable by account, account_type, instrument_root, date range.
- `GET /api/trades/:id` — trade + journal entry + executions.
- `PUT /api/journal/:tradeId` — create/update the Layer 2 entry.
- `GET /api/stats` — core stats respecting the same filters.
- `GET /api/sync/status` — last successful sync per machine (powers dashboard staleness display).

Auth: a simple bearer token from `.env` is fine for a personal system, but it must exist — these routes will be reachable from the public internet on Vercel.

## Phase 4 — Sync script (`sync/`)

Runs locally on each trading machine. Node or Python — pick whichever makes single-file distribution and Task Scheduler invocation simplest (recommend Node/TypeScript so it shares types with the app).

Behavior:
1. Open `executions.db` **read-only** (`mode=ro`).
2. Read executions since the last successful sync for this machine (query the API's `/api/sync/status`), with a trailing overlap window — dedup absorbs the overlap.
3. Aggregate fills into trades by Order ID; time-proximity grouping as fallback. Compute `instrument_root` and `trading_session_date` here.
4. Push through the API (never the DB), logging the run via the sync-run endpoints.
5. Print a human-readable summary: `Read 34 executions → 12 trades → 9 new, 3 already synced. Done.`
6. Exit nonzero on failure so Task Scheduler records it.

Also deliver:
- A one-click manual trigger per platform (`sync.bat` / desktop shortcut) that runs the script and keeps the window open to show the summary.
- Setup notes for the 6am scheduled task: Windows Task Scheduler, with **"Run task as soon as possible after a scheduled start is missed"** enabled.
- A `--backfill` mode that scans the entire `executions.db` history — this is how historical trades get loaded on day one, and idempotency means it can be re-run safely.

## Phase 5 — Dashboard (minimum viable journal)

1. **Trade log** — table of trades, filterable by account (all / per-live-account / sim — first-class control), instrument_root, and date range. Sim and live never mixed in a default view.
2. **Trade detail / journal entry** — Layer 1 data displayed read-only; Layer 2 form optimized for speed (target: journaling a trade in under 60 seconds). Screenshot upload.
3. **Core stats** — win rate, expectancy, net PnL, by instrument and account, respecting filters.
4. **Sync status strip** — "Last sync: laptop 2h ago · desktop 3d ago", prominent, so a forgotten sync is visible.

Fast and honest beats pretty. No feature creep — the backlog lives in `../kb/backlog.md`.

## Phase 6 — Verify end-to-end

1. Run `--backfill` against the real `executions.db` copy; confirm counts reconcile against NinjaTrader's own trade history view.
2. Run the sync twice in a row; second run must report all-deduped, zero inserted.
3. Take one sim trade, sync, journal it, confirm it appears under sim filters only.
4. Confirm a trade spanning midnight AEST lands on the correct `trading_session_date`.

## Explicitly out of scope (backlog — do not build)

Slack integration · live-vs-sim comparison analytics · setup/tag analytics · dashboard "Sync now" remote button (needs a local polling daemon) · n8n sync-staleness alerts · team features · any NinjaTrader API/SDK usage · real-time/streaming data.

## Definition of done for this setup

- Schema migrated, API deployed to Vercel, sync script running on at least one machine with both triggers configured.
- Historical backfill completed and reconciled.
- One real trade journaled end-to-end through the UI.
- `sync/NINJATRADER-NOTES.md` documents verified NinjaTrader behavior.
- Any process decisions surfaced during the build flagged for `../kb/decision-log.md`.
