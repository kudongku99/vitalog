create function public.mcp_list_metrics()
returns jsonb
language sql stable security invoker
set search_path = public
as $$
  select jsonb_build_object(
    'daily_stats', coalesce((
      select jsonb_agg(jsonb_build_object(
        'type', type, 'days', days, 'first_day', first_day, 'last_day', last_day
      ) order by type)
      from (
        select type, count(*) as days, min(day) as first_day, max(day) as last_day
        from daily_stats group by type
      ) d
    ), '[]'::jsonb),
    'category_samples', coalesce((
      select jsonb_agg(jsonb_build_object(
        'type', type, 'count', n, 'first_at', first_at, 'last_at', last_at
      ) order by type)
      from (
        select type, count(*) as n, min(start_at) as first_at, max(start_at) as last_at
        from category_samples group by type
      ) c
    ), '[]'::jsonb),
    'other_samples', coalesce((
      select jsonb_agg(jsonb_build_object(
        'type', type, 'count', n, 'first_at', first_at, 'last_at', last_at
      ) order by type)
      from (
        select type, count(*) as n, min(start_at) as first_at, max(start_at) as last_at
        from other_samples group by type
      ) o
    ), '[]'::jsonb),
    'workouts', (
      select jsonb_build_object('count', count(*), 'first_at', min(start_at), 'last_at', max(start_at))
      from workouts
    ),
    'activity_summaries', (
      select jsonb_build_object('days', count(*), 'first_day', min(day), 'last_day', max(day))
      from activity_summaries
    )
  );
$$;

create function public.mcp_daily_summary(p_from date, p_to date)
returns jsonb
language sql stable security invoker
set search_path = public
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'day', day,
    'steps', steps,
    'active_energy_kcal', active_energy_kcal,
    'exercise_min', exercise_min
  ) order by day), '[]'::jsonb)
  from (
    select day,
      round(sum(sum) filter (where type = 'step_count')::numeric, 0) as steps,
      round(sum(sum) filter (where type = 'active_energy_burned')::numeric, 0) as active_energy_kcal,
      round(sum(sum) filter (where type = 'apple_exercise_time')::numeric, 0) as exercise_min
    from daily_stats
    where day between p_from and p_to
      and type in ('step_count', 'active_energy_burned', 'apple_exercise_time')
    group by day
    order by day
    limit 400
  ) s;
$$;

create function public.mcp_sleep_summary(p_from date, p_to date, p_tz text default 'Asia/Seoul')
returns jsonb
language sql stable security invoker
set search_path = public
as $$
  with seg as (
    select
      (((start_at - interval '18 hours') at time zone p_tz)::date + 1) as night,
      value, start_at, end_at,
      extract(epoch from (end_at - start_at)) / 60.0 as minutes
    from category_samples
    where type = 'sleep_analysis'
      and start_at >= (p_from::timestamp - interval '1 day') at time zone p_tz
      and start_at < (p_to::timestamp + interval '2 days') at time zone p_tz
  ),
  nights as (
    select
      night,
      round((sum(minutes) filter (where value like 'asleep%'))::numeric, 0) as asleep_min,
      round((sum(minutes) filter (where value = 'asleep_core'))::numeric, 0) as core_min,
      round((sum(minutes) filter (where value = 'asleep_deep'))::numeric, 0) as deep_min,
      round((sum(minutes) filter (where value = 'asleep_rem'))::numeric, 0) as rem_min,
      round((sum(minutes) filter (where value = 'awake'))::numeric, 0) as awake_min,
      round((sum(minutes) filter (where value = 'in_bed'))::numeric, 0) as in_bed_min,
      to_char(min(start_at) at time zone p_tz, 'YYYY-MM-DD"T"HH24:MI') as bedtime,
      to_char(max(end_at) at time zone p_tz, 'YYYY-MM-DD"T"HH24:MI') as wake_time
    from seg
    where night between p_from and p_to
    group by night
    having coalesce(sum(minutes) filter (where value like 'asleep%'), 0) > 0
  )
  select jsonb_build_object(
    'nights', coalesce((select jsonb_agg(to_jsonb(n) order by night) from nights n), '[]'::jsonb),
    'average', (
      select jsonb_build_object(
        'nights', count(*),
        'asleep_min', round(avg(asleep_min), 0),
        'deep_min', round(avg(deep_min), 0),
        'rem_min', round(avg(rem_min), 0)
      ) from nights
    )
  );
$$;

create function public.mcp_workouts(p_from date, p_to date, p_limit integer default 50, p_tz text default 'Asia/Seoul')
returns jsonb
language sql stable security invoker
set search_path = public
as $$
  with w as (
    select *, (start_at at time zone p_tz)::date as local_day
    from workouts
    where start_at >= p_from::timestamp at time zone p_tz
      and start_at < (p_to::timestamp + interval '1 day') at time zone p_tz
  )
  select jsonb_build_object(
    'total_count', (select count(*) from w),
    'by_type', coalesce((
      select jsonb_agg(jsonb_build_object(
        'activity_type', activity_type,
        'count', n,
        'total_min', total_min,
        'total_kcal', total_kcal,
        'total_km', total_km
      ) order by n desc)
      from (
        select activity_type, count(*) as n,
          round((sum(duration_s) / 60.0)::numeric, 0) as total_min,
          round(sum(total_energy_kcal)::numeric, 0) as total_kcal,
          round((sum(total_distance_m) / 1000.0)::numeric, 1) as total_km
        from w group by activity_type
      ) t
    ), '[]'::jsonb),
    'workouts', coalesce((
      select jsonb_agg(jsonb_build_object(
        'day', local_day,
        'start', to_char(start_at at time zone p_tz, 'YYYY-MM-DD"T"HH24:MI'),
        'activity_type', activity_type,
        'duration_min', round((duration_s / 60.0)::numeric, 1),
        'energy_kcal', round(total_energy_kcal::numeric, 0),
        'distance_km', round((total_distance_m / 1000.0)::numeric, 2)
      ) order by start_at desc)
      from (select * from w order by start_at desc limit least(greatest(p_limit, 1), 200)) l
    ), '[]'::jsonb)
  );
$$;

create function public.mcp_metric_trend(p_type text, p_from date, p_to date, p_bucket text default 'week')
returns jsonb
language plpgsql stable security invoker
set search_path = public
as $$
declare
  result jsonb;
begin
  if p_bucket not in ('day', 'week', 'month') then
    raise exception 'bucket은 day, week, month 중 하나여야 합니다';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'period_start', period_start,
    'days', days,
    'avg', round(avg_value::numeric, 2),
    'min', round(min_value::numeric, 2),
    'max', round(max_value::numeric, 2),
    'total', round(total::numeric, 1)
  ) order by period_start), '[]'::jsonb)
  into result
  from (
    select
      date_trunc(p_bucket, day)::date as period_start,
      count(*) as days,
      avg(coalesce(sum, avg)) as avg_value,
      min(coalesce(min, sum, avg)) as min_value,
      max(coalesce(max, sum, avg)) as max_value,
      sum(sum) as total
    from daily_stats
    where type = p_type and day between p_from and p_to
    group by 1
    order by 1
    limit 400
  ) t;

  return result;
end;
$$;

create function public.mcp_run_sql(p_query text, p_max_rows integer default 200)
returns jsonb
language plpgsql stable security invoker
set search_path = public
as $$
declare
  q text := regexp_replace(btrim(p_query), ';\s*$', '');
  max_rows integer := least(greatest(p_max_rows, 1), 1000);
  rows_json jsonb;
  row_count integer;
begin
  if q !~* '^(select|with)\y' then
    raise exception 'SELECT 또는 WITH로 시작하는 조회문만 허용됩니다';
  end if;
  if position(';' in q) > 0 then
    raise exception '문장은 하나만 허용됩니다';
  end if;

  execute format(
    'select coalesce(jsonb_agg(t), ''[]''::jsonb) from (select * from (%s%s) q limit %s) t',
    q, E'\n', max_rows + 1
  ) into rows_json;

  row_count := jsonb_array_length(rows_json);
  if row_count > max_rows then
    return jsonb_build_object(
      'rows', (select jsonb_agg(e) from jsonb_array_elements(rows_json) with ordinality as x(e, i) where i <= max_rows),
      'truncated', true
    );
  end if;
  return jsonb_build_object('rows', rows_json, 'truncated', false);
end;
$$;

revoke execute on function
  public.mcp_list_metrics(),
  public.mcp_daily_summary(date, date),
  public.mcp_sleep_summary(date, date, text),
  public.mcp_workouts(date, date, integer, text),
  public.mcp_metric_trend(text, date, date, text),
  public.mcp_run_sql(text, integer)
from public, anon;

grant execute on function
  public.mcp_list_metrics(),
  public.mcp_daily_summary(date, date),
  public.mcp_sleep_summary(date, date, text),
  public.mcp_workouts(date, date, integer, text),
  public.mcp_metric_trend(text, date, date, text),
  public.mcp_run_sql(text, integer)
to authenticated;
