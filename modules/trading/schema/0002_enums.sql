-- All enum types used across the trading module tables.
-- Wrapped in DO blocks since Postgres has no `CREATE TYPE IF NOT EXISTS`.

do $$ begin
  create type instrument_enum as enum ('NQ', 'ES', 'YM', 'RTY');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type direction_enum as enum ('long', 'short');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type trade_status_enum as enum ('open', 'closed', 'scratched');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type session_enum as enum ('asia', 'london', 'ny_am', 'ny_pm');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type trade_event_type_enum as enum ('partial', 'stop_moved', 'added', 'note');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type journal_entry_type_enum as enum ('pre_session', 'post_session', 'trade_review', 'general');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type report_type_enum as enum ('daily', 'weekly', 'monthly', 'edge');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type report_scope_enum as enum ('trader', 'team');
exception when duplicate_object then null;
end $$;
