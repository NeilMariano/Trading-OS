-- Closes a trade, computes realized_r, and recomputes that trader's
-- daily_stats row for the exit date from scratch (not incrementally), so
-- re-closing/correcting a trade stays idempotent. See schema.md for the
-- realized_r formula and max_drawdown_r sign convention.
create or replace function fn_close_trade(
  p_trade_id uuid,
  p_exit_price numeric,
  p_exit_time timestamptz,
  p_exit_reason text
)
returns trades
language plpgsql
as $$
declare
  v_trade trades;
  v_realized_r numeric(6,2);
  v_date date;
  v_trades_count int;
  v_wins int;
  v_losses int;
  v_scratches int;
  v_total_r numeric(6,2);
  v_max_drawdown_r numeric(6,2);
begin
  select * into v_trade from trades where id = p_trade_id for update;
  if not found then
    raise exception 'trade % not found', p_trade_id;
  end if;

  v_realized_r := round(
    case v_trade.direction
      when 'long' then (p_exit_price - v_trade.entry_price) / nullif(v_trade.entry_price - v_trade.stop_price, 0)
      when 'short' then (v_trade.entry_price - p_exit_price) / nullif(v_trade.stop_price - v_trade.entry_price, 0)
    end,
    2
  );

  update trades
  set exit_price = p_exit_price,
      exit_time = p_exit_time,
      exit_reason = p_exit_reason,
      realized_r = v_realized_r,
      status = 'closed'
  where id = p_trade_id
  returning * into v_trade;

  v_date := (p_exit_time at time zone 'utc')::date;

  select
    count(*),
    count(*) filter (where status = 'closed' and realized_r > 0),
    count(*) filter (where status = 'closed' and realized_r < 0),
    count(*) filter (where status = 'scratched'),
    coalesce(sum(realized_r), 0)
  into v_trades_count, v_wins, v_losses, v_scratches, v_total_r
  from trades
  where trader_id = v_trade.trader_id
    and (exit_time at time zone 'utc')::date = v_date
    and status in ('closed', 'scratched');

  -- Peak-to-trough drawdown across the day's trades in exit_time order.
  -- dd is <= 0 per row; the most negative dd is the day's max drawdown.
  with day_trades as (
    select realized_r, exit_time
    from trades
    where trader_id = v_trade.trader_id
      and (exit_time at time zone 'utc')::date = v_date
      and status in ('closed', 'scratched')
  ),
  running as (
    select
      exit_time,
      sum(coalesce(realized_r, 0)) over (order by exit_time rows between unbounded preceding and current row) as cum_r
    from day_trades
  ),
  drawdown as (
    select
      cum_r - max(cum_r) over (order by exit_time rows between unbounded preceding and current row) as dd
    from running
  )
  select coalesce(min(dd), 0) into v_max_drawdown_r from drawdown;

  insert into daily_stats (trader_id, date, trades_count, wins, losses, scratches, total_r, max_drawdown_r)
  values (v_trade.trader_id, v_date, v_trades_count, v_wins, v_losses, v_scratches, v_total_r, v_max_drawdown_r)
  on conflict (trader_id, date) do update set
    trades_count = excluded.trades_count,
    wins = excluded.wins,
    losses = excluded.losses,
    scratches = excluded.scratches,
    total_r = excluded.total_r,
    max_drawdown_r = excluded.max_drawdown_r;

  return v_trade;
end;
$$;
