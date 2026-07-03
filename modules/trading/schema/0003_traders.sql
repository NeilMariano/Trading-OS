create table if not exists traders (
  id uuid primary key default gen_random_uuid(),
  discord_user_id text not null unique,
  display_name text not null,
  timezone text not null,
  platform text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists trg_traders_updated_at on traders;
create trigger trg_traders_updated_at
  before update on traders
  for each row execute function set_updated_at();
