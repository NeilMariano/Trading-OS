create table if not exists journal_entries (
  id uuid primary key default gen_random_uuid(),
  trader_id uuid not null references traders(id),
  trade_id uuid references trades(id),
  entry_type journal_entry_type_enum not null,
  content text not null,
  mood int,
  rule_adherence int check (rule_adherence between 1 and 5),
  is_test boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_journal_entries_trader_id
  on journal_entries (trader_id, created_at);

create index if not exists idx_journal_entries_trade_id
  on journal_entries (trade_id);

drop trigger if exists trg_journal_entries_updated_at on journal_entries;
create trigger trg_journal_entries_updated_at
  before update on journal_entries
  for each row execute function set_updated_at();
