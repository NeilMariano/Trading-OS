-- Populated/maintained by fn_close_trade (see 0012_fn_close_trade.sql), which
-- recomputes a trader/date row from scratch on every close (idempotent).
-- No is_test column here -- see modules/trading/docs/schema.md for the
-- caveat this implies and how the seed sandbox avoids mixing test/real data.
create table if not exists daily_stats (
  trader_id uuid not null references traders(id),
  date date not null,
  trades_count int not null default 0,
  wins int not null default 0,
  losses int not null default 0,
  scratches int not null default 0,
  total_r numeric(6,2) not null default 0,
  max_drawdown_r numeric(6,2) not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (trader_id, date)
);

drop trigger if exists trg_daily_stats_updated_at on daily_stats;
create trigger trg_daily_stats_updated_at
  before update on daily_stats
  for each row execute function set_updated_at();
