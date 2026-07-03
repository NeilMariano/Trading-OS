-- Sandbox dataset: 2 fake traders, 3 fake strategies, ~60 NQ/ES trades over
-- the trailing 6 weeks, matching journal entries, and daily_stats populated
-- via fn_close_trade. Everything here is is_test = true.
--
-- Run this AFTER modules/trading/schema/000*.sql have been applied.
-- Idempotent: if test_trader_1 already exists, the whole block is a no-op.
-- To reseed, delete is_test = true rows first (see modules/trading/docs/schema.md).

do $$
declare
  v_already_seeded boolean;
begin
  select exists(select 1 from traders where discord_user_id = 'test_trader_1')
    into v_already_seeded;

  if v_already_seeded then
    raise notice 'Seed data already present (test_trader_1 found) -- skipping.';
    return;
  end if;

  -- 1. Traders -------------------------------------------------------------
  insert into traders (discord_user_id, display_name, timezone, platform, active)
  values
    ('test_trader_1', 'Test Trader Alpha', 'America/New_York', 'Tradovate', true),
    ('test_trader_2', 'Test Trader Bravo', 'America/Chicago', 'NinjaTrader', true);

  -- 2. Strategies ------------------------------------------------------------
  insert into strategies (name, description, rules, active)
  values
    ('ORB Breakout', 'Trade breakouts of the opening range high/low with volume confirmation.', '{}'::jsonb, true),
    ('VWAP Reversion', 'Fade extended moves back toward VWAP on momentum divergence.', '{}'::jsonb, true),
    ('Trend Continuation', 'Enter pullbacks in the direction of the prevailing trend.', '{}'::jsonb, true);

  -- 3. Staging table for the randomized trade set ---------------------------
  -- Materialized once so the same random draws are used both when the
  -- trades are inserted and later when they're closed via fn_close_trade.
  drop table if exists tmp_seed;

  create temporary table tmp_seed as
  with trader_ids as (
    select array_agg(id order by discord_user_id) as ids
    from traders
    where discord_user_id in ('test_trader_1', 'test_trader_2')
  ),
  strategy_ids as (
    select array_agg(id order by name) as ids
    from strategies
    where name in ('ORB Breakout', 'Trend Continuation', 'VWAP Reversion')
  ),
  rolls as (
    select
      s.seq,
      ti.ids as trader_ids,
      si.ids as strategy_ids,
      random() as trader_roll,
      random() as strategy_roll,
      random() as strategy_null_roll,
      random() as instrument_roll,
      random() as direction_roll,
      random() as session_roll,
      random() as date_roll,
      random() as tod_roll,
      random() as entry_price_roll,
      random() as risk_roll,
      random() as reward_roll,
      random() as contracts_roll,
      random() as outcome_roll,
      random() as outcome_variance_roll,
      random() as duration_roll,
      random() as source_roll,
      random() as reason_roll,
      random() as tags_roll,
      random() as mood_roll,
      random() as adherence_roll,
      random() as review_present_roll
    from generate_series(1, 60) as s(seq)
    cross join trader_ids ti
    cross join strategy_ids si
  ),
  picked as (
    select
      r.*,
      r.trader_ids[1 + floor(r.trader_roll * 2)::int] as trader_id,
      case when r.strategy_null_roll < 0.85
        then r.strategy_ids[1 + floor(r.strategy_roll * 3)::int]
        else null
      end as strategy_id,
      case when r.instrument_roll < 0.52 then 'NQ'::instrument_enum else 'ES'::instrument_enum end as instrument,
      case when r.direction_roll < 0.55 then 'long'::direction_enum else 'short'::direction_enum end as direction,
      case
        when r.session_roll < 0.35 then 'ny_am'::session_enum
        when r.session_roll < 0.65 then 'ny_pm'::session_enum
        when r.session_roll < 0.85 then 'london'::session_enum
        else 'asia'::session_enum
      end as session,
      -- Spread across the trailing 42 days, nudged onto a weekday.
      (current_date - floor(r.date_roll * 42)::int) as raw_date
    from rolls r
  ),
  dated as (
    select
      p.*,
      case extract(dow from p.raw_date)::int
        when 0 then p.raw_date - 2  -- Sunday -> Friday
        when 6 then p.raw_date - 1  -- Saturday -> Friday
        else p.raw_date
      end as trade_date
    from picked p
  ),
  timed as (
    select
      d.*,
      -- Approximate, non-DST-adjusted UTC session windows -- fine for
      -- synthetic sandbox data, not meant to model real session times.
      (
        d.trade_date::timestamptz
        + case d.session
            when 'asia' then interval '0 hour'
            when 'london' then interval '7 hour'
            when 'ny_am' then interval '13 hour 30 minute'
            when 'ny_pm' then interval '17 hour'
          end
        + case d.session
            when 'asia' then d.tod_roll * interval '3 hour'
            when 'london' then d.tod_roll * interval '2 hour'
            when 'ny_am' then d.tod_roll * interval '2 hour'
            when 'ny_pm' then d.tod_roll * interval '2 hour 30 minute'
          end
      ) as entry_time
    from dated d
  ),
  priced as (
    select
      t.*,
      case t.instrument
        when 'NQ' then round((21000 + (t.entry_price_roll - 0.5) * 400)::numeric / 0.25) * 0.25
        else round((6050 + (t.entry_price_roll - 0.5) * 100)::numeric / 0.25) * 0.25
      end as entry_price,
      case t.instrument
        when 'NQ' then round((15 + t.risk_roll * 30)::numeric / 0.25) * 0.25
        else round((3 + t.risk_roll * 7)::numeric / 0.25) * 0.25
      end as risk_points,
      (1.2 + t.reward_roll * 1.8) as reward_multiple,
      (1 + floor(t.contracts_roll * 3)::int) as contracts
    from timed t
  ),
  leveled as (
    select
      p.*,
      case when p.direction = 'long' then p.entry_price - p.risk_points else p.entry_price + p.risk_points end as stop_price,
      case when p.direction = 'long' then p.entry_price + p.risk_points * p.reward_multiple
           else p.entry_price - p.risk_points * p.reward_multiple end as target_price,
      row_number() over (order by p.trade_date desc, p.seq desc) as recency_rank,
      case
        when p.outcome_roll < 0.48 then 'win'
        when p.outcome_roll < 0.90 then 'loss'
        else 'small'
      end as outcome_bucket
    from priced p
  ),
  final as (
    select
      l.*,
      (l.recency_rank > 4) as should_close,
      case l.outcome_bucket
        when 'win' then l.entry_price + (l.target_price - l.entry_price) * (0.6 + l.outcome_variance_roll * 0.5)
        when 'loss' then l.entry_price + (l.stop_price - l.entry_price) * (0.7 + l.outcome_variance_roll * 0.5)
        else l.entry_price + l.risk_points * (l.outcome_variance_roll - 0.5) * 0.3
      end as raw_exit_price,
      l.entry_time + interval '5 minute' + l.duration_roll * interval '3 hour 55 minute' as exit_time,
      (array['openclaw', 'openclaw', 'openclaw', 'manual', 'manual', 'shorthand'])[1 + floor(l.source_roll * 6)::int] as source,
      (array[
        'ORB breakout above opening range high, volume confirmation',
        'VWAP rejection with momentum divergence',
        'Trend pullback to 20 EMA, continuation entry',
        'Liquidity sweep reversal at prior session high/low',
        'Range breakout on increasing delta'
      ])[1 + floor(l.reason_roll * 5)::int] as entry_reason,
      case l.outcome_bucket
        when 'win' then (array['hit target', 'trailed stop, closed remainder near target', 'scaled out into strength near target'])[1 + floor(l.outcome_variance_roll * 3)::int]
        when 'loss' then (array['hit stop', 'stopped out on retest of level', 'cut early, still near initial stop'])[1 + floor(l.outcome_variance_roll * 3)::int]
        else (array['scratched - no follow through', 'closed flat into session end', 'manual exit - thesis invalidated'])[1 + floor(l.outcome_variance_roll * 3)::int]
      end as exit_reason,
      case
        when l.tags_roll < 0.3 then array['orb']
        when l.tags_roll < 0.5 then array['reversion']
        when l.tags_roll < 0.65 then array['trend']
        else null
      end as tags,
      'seed-' || lpad(l.seq::text, 3, '0') as external_ref
    from leveled l
  )
  select
    seq,
    trader_id,
    strategy_id,
    instrument,
    direction,
    session,
    entry_time,
    entry_price,
    stop_price,
    target_price,
    contracts,
    entry_reason,
    tags,
    source,
    external_ref,
    should_close,
    round(raw_exit_price::numeric, 2) as exit_price,
    exit_time,
    exit_reason,
    outcome_bucket,
    mood_roll,
    adherence_roll,
    review_present_roll
  from final;

  -- 4. Insert the trades (all open initially; closed ones get closed below) --
  insert into trades (
    trader_id, strategy_id, instrument, direction, entry_price, stop_price,
    target_price, contracts, session, entry_time, entry_reason, tags,
    source, external_ref, is_test
  )
  select
    trader_id, strategy_id, instrument, direction, entry_price, stop_price,
    target_price, contracts, session, entry_time, entry_reason, tags,
    source, external_ref, true
  from tmp_seed;

  -- 5. Close the trades that aren't meant to stay open, via fn_close_trade --
  --    (this also populates daily_stats).
  perform fn_close_trade(t.id, ts.exit_price, ts.exit_time, ts.exit_reason)
  from trades t
  join tmp_seed ts on ts.external_ref = t.external_ref
  where ts.should_close and t.is_test = true;

  -- 6. Journal entries: trade reviews for most closed trades, with rule
  --    adherence loosely correlated to outcome (winners skew higher).
  insert into journal_entries (trader_id, trade_id, entry_type, content, mood, rule_adherence, is_test)
  select
    ts.trader_id,
    t.id,
    'trade_review',
    case ts.outcome_bucket
      when 'win' then 'Followed the plan on the ' || ts.instrument || ' ' || ts.direction || ' -- patient entry, let it work to target.'
      when 'loss' then 'Took the ' || ts.instrument || ' ' || ts.direction || ' per plan, got stopped -- no real mistake, just didn''t work.'
      else 'Cut the ' || ts.instrument || ' ' || ts.direction || ' early, hesitated on the exit -- need to trust the plan more.'
    end,
    case
      when ts.outcome_bucket = 'win' then 3 + round(ts.mood_roll * 2)::int
      when ts.outcome_bucket = 'loss' then 1 + round(ts.mood_roll * 3)::int
      else 2 + round(ts.mood_roll * 2)::int
    end,
    case
      when ts.outcome_bucket = 'win' then 3 + round(ts.adherence_roll * 2)::int
      when ts.outcome_bucket = 'loss' then 1 + round(ts.adherence_roll * 3)::int
      else 2 + round(ts.adherence_roll * 2)::int
    end,
    true
  from tmp_seed ts
  join trades t on t.external_ref = ts.external_ref
  where ts.should_close and ts.review_present_roll < 0.8;

  -- 7. A handful of standalone journal entries not tied to any trade.
  --    (random() calls stay in the top-level SELECT list, not a nested
  --    uncorrelated subquery, so they evaluate fresh per row.)
  insert into journal_entries (trader_id, entry_type, content, mood, is_test)
  with journal_trader_ids as (
    select array_agg(id order by discord_user_id) as ids from traders
    where discord_user_id in ('test_trader_1', 'test_trader_2')
  )
  select
    ti.ids[1 + floor(random() * 2)::int],
    (array['pre_session', 'post_session', 'general'])[1 + floor(random() * 3)::int]::journal_entry_type_enum,
    (array[
      'Plan for today: only take A+ setups in NY session, max 2 trades.',
      'Choppy day overall -- glad I sat out the afternoon chop.',
      'Reviewing last week: best trades came from patience at the open, worst from FOMO entries mid-range.',
      'Feeling sharp today, well rested, good headspace for the open.',
      'Need to stop moving stops early on winners -- cost me R twice this week.',
      'Solid week overall, sticking to the process even through the losing streak.'
    ])[1 + floor(random() * 6)::int],
    1 + floor(random() * 5)::int,
    true
  from generate_series(1, 6) as g(seq)
  cross join journal_trader_ids ti;

  drop table if exists tmp_seed;

  raise notice 'Seed complete: 2 traders, 3 strategies, 60 trades, journal entries, daily_stats.';
end $$;
