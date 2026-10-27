create table public.sources (
  id integer generated always as identity primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  bundle_id text not null default '',
  name text not null default '',
  product_type text not null default '',
  device_model text not null default '',
  unique (user_id, bundle_id, name, product_type, device_model),
  unique (user_id, id)
);

create table public.quantity_samples (
  uuid uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  type text not null,
  value double precision not null,
  start_at timestamptz not null,
  end_at timestamptz not null,
  source_id integer,
  metadata jsonb,
  foreign key (user_id, source_id) references public.sources (user_id, id),
  check (end_at >= start_at)
);

create table public.category_samples (
  uuid uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  type text not null,
  value text not null,
  start_at timestamptz not null,
  end_at timestamptz not null,
  source_id integer,
  metadata jsonb,
  foreign key (user_id, source_id) references public.sources (user_id, id),
  check (end_at >= start_at)
);

create table public.other_samples (
  uuid uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  type text not null,
  start_at timestamptz not null,
  end_at timestamptz not null,
  source_id integer,
  payload jsonb not null,
  metadata jsonb,
  foreign key (user_id, source_id) references public.sources (user_id, id),
  check (end_at >= start_at)
);

create table public.workouts (
  uuid uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  activity_type text not null,
  start_at timestamptz not null,
  end_at timestamptz not null,
  duration_s double precision not null,
  total_energy_kcal double precision,
  total_distance_m double precision,
  source_id integer,
  statistics jsonb,
  activities jsonb,
  events jsonb,
  metadata jsonb,
  foreign key (user_id, source_id) references public.sources (user_id, id),
  check (end_at >= start_at)
);

create table public.workout_routes (
  uuid uuid primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  workout_uuid uuid references public.workouts (uuid) on delete cascade,
  start_at timestamptz not null,
  end_at timestamptz not null,
  source_id integer,
  point_times double precision[] not null,
  latitudes double precision[] not null,
  longitudes double precision[] not null,
  altitudes double precision[],
  foreign key (user_id, source_id) references public.sources (user_id, id),
  check (end_at >= start_at),
  check (cardinality(point_times) = cardinality(latitudes) and cardinality(point_times) = cardinality(longitudes))
);

create table public.activity_summaries (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  day date not null,
  active_energy_kcal double precision,
  active_energy_goal_kcal double precision,
  move_time_min double precision,
  move_time_goal_min double precision,
  exercise_time_min double precision,
  exercise_time_goal_min double precision,
  stand_hours double precision,
  stand_hours_goal double precision,
  updated_at timestamptz not null default now(),
  primary key (user_id, day)
);

create table public.daily_stats (
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  day date not null,
  type text not null,
  sum double precision,
  avg double precision,
  min double precision,
  max double precision,
  updated_at timestamptz not null default now(),
  primary key (user_id, type, day)
);

create table public.characteristics (
  user_id uuid primary key default auth.uid() references auth.users (id) on delete cascade,
  biological_sex text,
  blood_type text,
  date_of_birth date,
  fitzpatrick_skin_type text,
  wheelchair_use text,
  activity_move_mode text,
  updated_at timestamptz not null default now()
);

create table public.sync_log (
  id bigint generated always as identity primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  run_at timestamptz not null default now(),
  mode text not null check (mode in ('backfill', 'observer', 'background_task', 'manual')),
  type text,
  inserted integer not null default 0,
  deleted integer not null default 0,
  error text
);

create index quantity_samples_user_type_start_idx on public.quantity_samples (user_id, type, start_at);
create index category_samples_user_type_start_idx on public.category_samples (user_id, type, start_at);
create index other_samples_user_type_start_idx on public.other_samples (user_id, type, start_at);
create index workouts_user_start_idx on public.workouts (user_id, start_at);
create index workout_routes_workout_idx on public.workout_routes (workout_uuid);
create index sync_log_user_run_at_idx on public.sync_log (user_id, run_at desc);

alter table public.sources enable row level security;
alter table public.quantity_samples enable row level security;
alter table public.category_samples enable row level security;
alter table public.other_samples enable row level security;
alter table public.workouts enable row level security;
alter table public.workout_routes enable row level security;
alter table public.activity_summaries enable row level security;
alter table public.daily_stats enable row level security;
alter table public.characteristics enable row level security;
alter table public.sync_log enable row level security;

grant select, insert, update, delete on
  public.sources,
  public.quantity_samples,
  public.category_samples,
  public.other_samples,
  public.workouts,
  public.workout_routes,
  public.activity_summaries,
  public.daily_stats,
  public.characteristics
to authenticated;

grant select, insert on public.sync_log to authenticated;

create policy "sources_own" on public.sources
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy "quantity_samples_own" on public.quantity_samples
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy "category_samples_own" on public.category_samples
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy "other_samples_own" on public.other_samples
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy "workouts_own" on public.workouts
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy "workout_routes_own" on public.workout_routes
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy "activity_summaries_own" on public.activity_summaries
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy "daily_stats_own" on public.daily_stats
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy "characteristics_own" on public.characteristics
  for all to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy "sync_log_select_own" on public.sync_log
  for select to authenticated
  using (user_id = (select auth.uid()));

create policy "sync_log_insert_own" on public.sync_log
  for insert to authenticated
  with check (user_id = (select auth.uid()));
