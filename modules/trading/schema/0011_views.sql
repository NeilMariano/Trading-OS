-- Every view here filters is_test = false: these are the "real" analytics
-- surfaces. Sandbox/dev querying should hit the tables directly with an
-- explicit is_test = true filter instead of these views.

create or replace view v_win_rate_by_session as
select
  session,
  count(*) filter (where status = 'closed') as closed_trades,
  count(*) filter (where status = 'closed' and realized_r > 0) as wins,
  round(
    count(*) filter (where status = 'closed' and realized_r > 0)::numeric
      / nullif(count(*) filter (where status = 'closed'), 0),
    4
  ) as win_rate
from trades
where is_test = false
group by session;

create or replace view v_expectancy_by_strategy as
select
  s.id as strategy_id,
  s.name as strategy_name,
  count(t.id) filter (where t.status = 'closed') as closed_trades,
  round(avg(t.realized_r) filter (where t.status = 'closed'), 4) as expectancy_r,
  round(sum(t.realized_r) filter (where t.status = 'closed'), 2) as total_r
from strategies s
left join trades t on t.strategy_id = s.id and t.is_test = false
group by s.id, s.name;

-- 10 buckets spanning -5R to +5R; realized_r outside that range collapses
-- into the first/last bucket (width_bucket's edge behavior).
create or replace view v_r_distribution as
select
  width_bucket(realized_r, -5, 5, 10) as bucket,
  min(realized_r) as bucket_min_r,
  max(realized_r) as bucket_max_r,
  count(*) as trade_count
from trades
where is_test = false and status = 'closed' and realized_r is not null
group by bucket
order by bucket;

create or replace view v_trader_leaderboard as
select
  tr.id as trader_id,
  tr.display_name,
  count(t.id) filter (where t.status = 'closed') as closed_trades,
  round(sum(t.realized_r) filter (where t.status = 'closed'), 2) as total_r,
  round(avg(t.realized_r) filter (where t.status = 'closed'), 4) as expectancy_r,
  round(
    count(*) filter (where t.status = 'closed' and t.realized_r > 0)::numeric
      / nullif(count(*) filter (where t.status = 'closed'), 0),
    4
  ) as win_rate
from traders tr
left join trades t on t.trader_id = tr.id and t.is_test = false
group by tr.id, tr.display_name
order by total_r desc nulls last;
