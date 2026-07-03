# Trading module schema

Source of truth: `modules/trading/schema/0001..0012_*.sql`, numbered migrations applied in order. Sandbox data: `scripts/seed-fake-data.sql`.

## Tables

### `traders`
One row per person trading. `discord_user_id` is the natural key used to look a trader up from a Discord interaction.

### `strategies`
A shared, team-wide catalog of named strategies (`rules` is a free-form jsonb blob for whatever criteria a strategy wants to track). **No `trader_id`** — see "trader_id convention" below.

### `trades`
The core table. One row per trade, `trader_id` required, `strategy_id` optional (a trade doesn't have to be tagged to a formal strategy). Status starts `open` and transitions to `closed` via `fn_close_trade` (or manually to `scratched` — see "status" below).

### `trade_events`
Sub-events on a trade (partial exits, stop moves, adds, notes) as a jsonb `payload`. **No `trader_id`** — always reached via `trade_id → trades.trader_id`.

### `journal_entries`
Freeform journaling, optionally linked to a specific trade (`trade_id` nullable) for trade reviews, or standalone for pre/post-session notes and general entries.

### `daily_stats`
One row per `(trader_id, date)`, maintained by `fn_close_trade`. **Not manually written to** — always derived.

### `reports`
Generated report artifacts (daily/weekly/monthly/edge), either scoped to one trader or the whole team (`scope`). `content_md` holds the rendered report, `metrics` holds the structured numbers behind it.

### `prompts`
Global runtime prompt config, keyed by unique `name`, versioned. Workflows fetch these by name at runtime rather than hardcoding prompt text into nodes (per the root `CLAUDE.md` rule). **No `trader_id`** — these are global.

## `trader_id` convention

Root `CLAUDE.md` states "trader_id on every table" as a general rule. Three tables intentionally don't have it:

- **`strategies`** — a shared catalog, not per-trader data.
- **`trade_events`** — always scoped through `trade_id`, which already carries `trader_id` on the parent `trades` row.
- **`prompts`** — global runtime config, not trader-specific.

This is a deliberate reading of the rule (it applies to trader-scoped *data*, not shared/global catalogs), not an oversight.

## `realized_r` calculation

`fn_close_trade(trade_id, exit_price, exit_time, exit_reason)` computes `realized_r` purely from `entry_price`, `stop_price`, `exit_price`, and `direction` — it does not use `risk_r`:

```
long:  realized_r = (exit_price - entry_price) / (entry_price - stop_price)
short: realized_r = (entry_price - exit_price) / (stop_price - entry_price)
```

Both forms divide the realized price move by the *initial risk distance* (entry-to-stop, always a positive number given correct stop placement), so a profitable trade yields positive R and a loss yields negative R regardless of direction. Result is rounded to `numeric(6,2)`.

### `risk_r` vs `realized_r`

- `risk_r` (default `1.00`) is the trade's **planned position size**, expressed as a multiple of the trader's standard 1R unit — e.g. `0.5` for a half-size trade taken with reduced conviction. It is set at entry and is informational; it does not feed into the `realized_r` formula.
- `realized_r` is the **outcome**, computed only at close.

## `status` and `daily_stats`

`fn_close_trade` always transitions a trade to `status = 'closed'`. It does not produce `status = 'scratched'` rows — a scratch (an early, discretionary exit with no real signal) is modeled as a `closed` trade with a small `realized_r` near zero, distinguished by `exit_reason` text (e.g. "scratched - no follow through"), not a separate status. If you do want a trade marked `scratched`, set it directly with `UPDATE trades` and re-derive that day's `daily_stats` row using the same aggregation `fn_close_trade` uses (see the function body) — `fn_close_trade` itself will not touch a trade already marked `scratched` correctly since it unconditionally sets `status = 'closed'`.

`daily_stats` has no `is_test` column (per the literal table spec). `fn_close_trade` aggregates *all* trades for a `(trader_id, date)` regardless of `is_test`. This is safe as long as test and real trades never share a `trader_id` — which is why the seed script uses dedicated fake traders (`test_trader_1`, `test_trader_2`) rather than flagging real traders' rows as test. Don't reuse a real trader's `id` for test trades.

`fn_close_trade` **recomputes the full `daily_stats` row from scratch** on every call (not an incremental increment), so closing or re-closing/correcting a trade is idempotent — safe to call again if a trade's exit needs correcting.

### `max_drawdown_r`

The worst peak-to-trough dip in cumulative R across a trader's trades on a given day, in `exit_time` order. Always `<= 0`. A value of `-3.50` means that at some point during the day, cumulative R had fallen 3.50R below the highest cumulative R reached earlier that same day. `0` means the day never dipped below its running peak (monotonically flat or improving).

## `source` / `external_ref` dedupe convention

`trades.source` is free text constrained to `openclaw | shorthand | manual | import_*` (the `import_.+` pattern lets future importers use a specific tag per upstream system, e.g. `import_tradovate`, `import_ninjatrader`, without a schema change).

For dedupe, there's a partial unique index:

```sql
create unique index ux_trades_source_external_ref
  on trades (source, external_ref)
  where external_ref is not null;
```

**Convention for future importers:** always set `external_ref` to a stable identifier from the upstream system (e.g. the broker's fill/execution id). Insert with `ON CONFLICT (source, external_ref) WHERE external_ref IS NOT NULL DO NOTHING` (or `DO UPDATE` if you want re-imports to refresh the row). This makes re-running an import script safe — it won't create duplicate trades. Manual/OpenClaw/shorthand entries typically have no natural upstream id and can leave `external_ref` `NULL`, which is unrestricted (multiple `NULL`s don't collide).

## Views

All views filter `is_test = false` — they're the "real" analytics surfaces. For sandbox querying, hit the tables directly with an explicit `is_test = true` filter.

- **`v_win_rate_by_session`** — closed trade count, win count, and win rate per `session`.
- **`v_expectancy_by_strategy`** — closed trade count, average R (expectancy), and total R per strategy.
- **`v_r_distribution`** — a 10-bucket histogram of `realized_r` spanning -5R to +5R (`width_bucket`).
- **`v_trader_leaderboard`** — per-trader closed trade count, total R, expectancy, and win rate, ordered by total R descending.

## Seed data (`scripts/seed-fake-data.sql`)

Idempotent: it no-ops if `test_trader_1` already exists (delete `is_test = true` rows to reseed). Produces:

- 2 fake traders (`test_trader_1`, `test_trader_2`), 3 fake strategies.
- 60 NQ/ES trades spread over the trailing 6 weeks, weekday-nudged, mixed sessions (weighted toward `ny_am`/`ny_pm`), mixed direction, realistic tick-rounded prices. Outcome mix is roughly 48% win / 42% loss / 10% small-near-breakeven, so `realized_r` comes out with a sane distribution. The 4 most recent trades are left `open`.
- Trades are closed via `fn_close_trade` itself (not a separate hand-rolled formula), so the seed script also exercises the function and populates `daily_stats` as a side effect.
- Trade-review `journal_entries` for ~80% of closed trades, with `mood` and `rule_adherence` loosely correlated to the trade's outcome (winners skew higher adherence). Plus a handful of standalone pre/post-session and general entries.
- All rows (`trades`, `journal_entries`) flagged `is_test = true`.

This is the dataset every workflow/experiment should run against before touching real data.
