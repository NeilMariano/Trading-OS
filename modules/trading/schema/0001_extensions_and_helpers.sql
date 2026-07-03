-- Extensions and shared helpers used by every table below.

create extension if not exists pgcrypto;

-- Generic updated_at trigger, attached per-table in later migrations.
create or replace function set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;
