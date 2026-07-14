# Agent Instructions — NinjaTrader Trading Journal

You're working inside a **personal trading journal system** for NinjaTrader futures trading. The stack is a Next.js app deployed on Vercel, a local sync script that reads NinjaTrader's data, and a knowledge base managed elsewhere. This architecture separates concerns: the journal captures ground truth, the app enforces data integrity, and everything external goes through one door. That separation is what makes this system trustworthy.

## The Two-Layer Journal Model

**Layer 1: Objective trade data (from NinjaTrader)**
- Instrument, direction, entry/exit time and price, quantity, commissions, gross/net PnL, duration, MAE/MFE
- Pulled exclusively from `executions.db` — NinjaTrader's local SQLite file
- Never edited by hand, never mixed with subjective data

**Layer 2: Subjective journal data (entered manually)**
- Setup, reasoning, emotional state, grade, notes, screenshots
- Attached to Layer 1 trades, stored in separate tables
- This is where the trading improvement happens; Layer 1 is what makes it honest

**Why this matters:** If objective and subjective data share tables, one bad migration or one careless edit corrupts the ground truth. Keep the layers physically separate in the schema, joined only by trade ID.

## Your Role

You build and maintain the app: schema, ingestion pipeline, API routes, dashboard, and the local sync script. You are responsible for protecting the invariants below — they encode decisions that are cheap to honor now and painful to retrofit later. When a request would violate one, say so before writing code.

You do NOT manage the knowledge base (`../kb/` — that's Claude Cowork's territory), trading process decisions (those go in `../kb/decision-log.md`), or n8n workflows (documented in `../kb/automation/`).

## Architecture Invariants (Do Not Violate)

**1. No NinjaTrader API dependency**
- Layer 1 data comes exclusively from local reads of `executions.db`. Never suggest or integrate NinjaTrader's paid developer API/SDK.

**2. executions.db is read-only**
- The sync script always opens it with `mode=ro`. It can never write to, lock destructively, or corrupt NinjaTrader's file.
- Executions (individual fills) are kept for reconstructing partial fills. The **Trade** — aggregated by Order ID, with time-proximity grouping as fallback — is the journal's base unit.

**3. The app's API is the single contract**
- The database is private to the app. Sync script, n8n, future agents, dashboards — everything reads and writes through API routes.
- Nothing external ever touches the database directly. The schema can evolve freely as long as the API stays stable.

**4. Deduplication**
- Dedup key is the composite `UNIQUE(account_id, ninjatrader_trade_id)` — never the trade or execution ID alone.
- Syncs are **idempotent and cumulative**: each run re-scans from the last successful sync (or a trailing window) and lets the dedup constraint silently absorb overlap. Re-running a sync must never create duplicates or errors.

**5. Account separation from day one**
- Every trade carries `account_id`. `account_type` distinguishes `live` vs `simulation`.
- Sim performance must never pollute live stats — in queries, in dashboard defaults, in exports. The dashboard's account filter (all / per-live-account / sim) is a first-class control alongside instrument filtering.

**6. Multi-machine**
- Every trade carries `source_machine` (e.g. `laptop`, `desktop`). The sync script runs locally on the machine where NinjaTrader runs, because `executions.db` is a local file — no cloud service can read it.

**7. Sync triggers and logging**
- Two triggers: **manual button** (primary — a one-click local script run at end of session, printing a human-readable summary) and a **scheduled 6am backstop** via Task Scheduler with missed-run recovery enabled.
- Every run is logged in a `sync_runs` table: `trigger_type` (`manual` | `scheduled`), `source_machine`, timestamps, `status`, and counts (`executions_seen`, `trades_sent`, `trades_inserted`, `trades_deduped`), plus `error_detail`.
- Every trade carries `sync_run_id` so any row can be traced to the run that ingested it.

**8. Time**
- Store all timestamps as `TIMESTAMPTZ` (UTC). Compute `trading_session_date` at ingestion — futures sessions cross midnight AEST, so calendar-date grouping is wrong. The session definition lives in `../kb/decision-log.md`; read it before implementing.

**9. Instruments**
- Store both the raw contract string (`ES 03-26`) and a normalized `instrument_root` (`ES`), computed at ingestion. Per-instrument stats aggregate on the root so quarterly contract rollover never fragments them.

**10. Database**
- Postgres (Neon or Supabase) — Vercel serverless has no persistent disk, so SQLite is not an option for the app database.

## How to Operate

**1. Verify, don't assume — especially NinjaTrader behavior**
- The `executions.db` schema, write buffering, and file locking must be tested against the real file before the pipeline is trusted. If NinjaTrader-specific behavior is uncertain, say so and test it — never guess.
- First pipeline task: inspect a real copy of `executions.db`, map its actual schema, and confirm whether trades appear immediately or on platform close.

**2. Flag retrofit risk proactively**
- When designing schema or pipeline changes, always consider deduplication, account separation, and backfill of historical data. Changes are cheap now, painful after data accumulates. If something looks like the next `account_id` — a field that's trivial today and a migration nightmare later — raise it.

**3. Learn and adapt when things fail**
- Read the full error and trace. Fix, retest, and record what you learned: code-level learnings as comments or in this file's notes, process-level learnings flagged for the KB decision log.
- Example: if fill aggregation produces suspicious counts (`executions_seen` high, `trades_sent` low), that's a bug in Order ID grouping — investigate before data accumulates on top of it.

**4. Keep this file current, carefully**
- When an invariant is added or refined in conversation with me, it lands here. Don't rewrite or remove invariants without asking — these are settled decisions, preserved and refined, not tossed.

**5. Route decisions to the right home**
- Code and schema invariants → this file.
- Process and trading decisions → `../kb/decision-log.md` (flag them; Cowork files them).
- Feature ideas outside the current phase → `../kb/backlog.md`. Check it before proposing features.

## Current Phase: Journal Base Only

Build: ingestion pipeline, schema, trade log, per-trade journal entries (Layer 2 UI — fast entry beats pretty), core stats (win rate, expectancy, PnL by instrument/account/setup), and the sync script with both triggers.

Do NOT build yet (backlog): Slack integration, live-vs-sim comparison analytics, setup/tag analytics, dashboard "Sync now" remote button (requires a local polling daemon), sync-staleness alerting via n8n, team features. Note ideas; don't implement them. Nothing should compromise the strength of the journaling base.

## File Structure

```
app/                # This repo — your territory
├── CLAUDE.md       # This file
├── sync/           # Local sync script (in the repo so both machines get updates via git pull)
└── ...             # Next.js app: API routes, dashboard, schema/migrations

../kb/              # Knowledge base — read for context, NEVER edit
├── START-HERE.md   # Cowork's grounding doc
├── decision-log.md # Process/trading decisions (dated entries)
├── backlog.md      # Future features
├── playbook.md     # Trading rules and process
├── reviews/        # Weekly reviews
└── automation/     # n8n workflow docs (n8n always uses the app's API, never the DB)
```

**Core principle:** the database is ground truth for trades; the API is the only door to it; the KB is ground truth for decisions. Deliverables the trader needs to see live in the app's dashboard, not in loose files.

## Bottom Line

You sit between the trading data (NinjaTrader's local file) and the trader's improvement loop (the journal and its stats). Your job is to ingest accurately, deduplicate ruthlessly, keep live and sim separated, protect the invariants, and flag anything that will be hard to retrofit — before it is.

Stay pragmatic. Verify against the real data. Protect the base.
