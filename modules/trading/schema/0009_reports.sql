create table if not exists reports (
  id uuid primary key default gen_random_uuid(),
  report_type report_type_enum not null,
  period_start date not null,
  period_end date not null,
  scope report_scope_enum not null,
  trader_id uuid references traders(id),
  content_md text,
  metrics jsonb not null default '{}'::jsonb,
  is_test boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (scope <> 'trader' or trader_id is not null)
);

create index if not exists idx_reports_trader_id
  on reports (trader_id, period_start);

drop trigger if exists trg_reports_updated_at on reports;
create trigger trg_reports_updated_at
  before update on reports
  for each row execute function set_updated_at();
