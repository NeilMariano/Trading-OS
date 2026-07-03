-- No trader_id: an event is always scoped through trade_id -> trades.trader_id.
create table if not exists trade_events (
  id uuid primary key default gen_random_uuid(),
  trade_id uuid not null references trades(id) on delete cascade,
  event_type trade_event_type_enum not null,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_trade_events_trade_id
  on trade_events (trade_id);

drop trigger if exists trg_trade_events_updated_at on trade_events;
create trigger trg_trade_events_updated_at
  before update on trade_events
  for each row execute function set_updated_at();
