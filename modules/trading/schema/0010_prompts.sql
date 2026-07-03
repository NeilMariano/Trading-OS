-- No trader_id: prompts are global runtime config, fetched by name from
-- workflows (see modules/trading/prompts/*.md for the authored source and
-- root CLAUDE.md's rule that prompts are never hardcoded into nodes).
create table if not exists prompts (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  content_md text not null,
  version int not null default 1,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists trg_prompts_updated_at on prompts;
create trigger trg_prompts_updated_at
  before update on prompts
  for each row execute function set_updated_at();
