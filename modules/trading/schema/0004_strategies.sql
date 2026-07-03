-- No trader_id: strategies are a shared team-wide catalog, not per-trader data.
-- See modules/trading/docs/schema.md for the trader_id convention and its exceptions.
create table if not exists strategies (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  rules jsonb not null default '{}'::jsonb,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists trg_strategies_updated_at on strategies;
create trigger trg_strategies_updated_at
  before update on strategies
  for each row execute function set_updated_at();
