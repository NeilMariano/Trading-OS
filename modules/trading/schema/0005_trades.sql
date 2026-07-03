create table if not exists trades (
  id uuid primary key default gen_random_uuid(),
  trader_id uuid not null references traders(id),
  strategy_id uuid references strategies(id),
  instrument instrument_enum not null,
  direction direction_enum not null,
  status trade_status_enum not null default 'open',
  entry_price numeric(12,2) not null,
  stop_price numeric(12,2) not null,
  target_price numeric(12,2) not null,
  exit_price numeric(12,2),
  contracts int not null check (contracts > 0),
  -- Planned position size relative to the trader's standard 1R unit
  -- (1.00 = full size). Not used in the realized_r calc -- see schema.md.
  risk_r numeric(6,2) not null default 1.00,
  realized_r numeric(6,2),
  session session_enum not null,
  entry_time timestamptz not null,
  exit_time timestamptz,
  entry_reason text,
  exit_reason text,
  screenshot_url text,
  tags text[],
  source text not null check (source ~ '^(openclaw|shorthand|manual|import_.+)$'),
  external_ref text,
  is_test boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Dedupe convention for importers: a given source's external_ref must be
-- unique so re-running an import is idempotent. NULL external_ref (manual /
-- openclaw / shorthand entries with no upstream id) is unrestricted.
create unique index if not exists ux_trades_source_external_ref
  on trades (source, external_ref)
  where external_ref is not null;

create index if not exists idx_trades_trader_id_entry_time
  on trades (trader_id, entry_time);

create index if not exists idx_trades_strategy_id
  on trades (strategy_id);

drop trigger if exists trg_trades_updated_at on trades;
create trigger trg_trades_updated_at
  before update on trades
  for each row execute function set_updated_at();
