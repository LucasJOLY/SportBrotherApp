-- Section Sport de SportBrother : un seul jeu de données partagé par tous les téléphones.
-- Chaque ligne porte :
--   modified_at : horloge du téléphone qui a écrit (arbitrage last-write-wins, saisie hors ligne)
--   updated_at  : horloge serveur, posée par trigger (curseur de synchronisation)
--   deleted_at  : suppression douce, pour que les suppressions se propagent

create function public.sport_touch() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := clock_timestamp();
  return new;
end;
$$;

create table public.sport_profiles (
  id uuid primary key,
  name text not null check (length(name) between 1 and 40),
  color_index smallint not null default 0,
  sort_order smallint not null default 0,
  modified_at timestamptz not null,
  updated_at timestamptz not null default clock_timestamp(),
  deleted_at timestamptz
);

-- 4 profils actifs au maximum.
create function public.sport_profiles_limit() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.deleted_at is null
     and (select count(*) from public.sport_profiles p where p.deleted_at is null and p.id <> new.id) >= 4 then
    raise exception 'Quatre profils au maximum' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

create table public.sport_body_weights (
  id uuid primary key,
  profile_id uuid not null references public.sport_profiles (id),
  measured_on date not null,
  kg numeric(5, 2) not null check (kg > 0),
  modified_at timestamptz not null,
  updated_at timestamptz not null default clock_timestamp(),
  deleted_at timestamptz
);

-- id = identifiant du catalogue embarqué (exo du catalogue réglé ou mis en favori) ou uuid (exo perso).
create table public.sport_exercises (
  id text primary key,
  name text,
  muscle_group text check (muscle_group in ('dos', 'biceps', 'triceps', 'epaules', 'pecs', 'jambes', 'abdos')),
  photo_path text,
  is_favorite boolean not null default false,
  rest_seconds smallint,
  rep_range_high smallint,
  is_bodyweight boolean,
  is_hidden boolean not null default false,
  modified_at timestamptz not null,
  updated_at timestamptz not null default clock_timestamp(),
  deleted_at timestamptz
);

create table public.sport_templates (
  id uuid primary key,
  name text not null,
  sort_order smallint not null default 0,
  modified_at timestamptz not null,
  updated_at timestamptz not null default clock_timestamp(),
  deleted_at timestamptz
);

create table public.sport_template_items (
  id uuid primary key,
  template_id uuid not null references public.sport_templates (id),
  exercise_ref text not null,
  sort_order smallint not null default 0,
  set_count smallint not null default 3,
  modified_at timestamptz not null,
  updated_at timestamptz not null default clock_timestamp(),
  deleted_at timestamptz
);

create table public.sport_sessions (
  id uuid primary key,
  performed_on date not null,
  started_at timestamptz not null,
  ended_at timestamptz,
  profile_ids uuid[] not null default '{}',
  template_id uuid references public.sport_templates (id),
  modified_at timestamptz not null,
  updated_at timestamptz not null default clock_timestamp(),
  deleted_at timestamptz
);

create table public.sport_entries (
  id uuid primary key,
  session_id uuid not null references public.sport_sessions (id),
  exercise_ref text not null,
  sort_order smallint not null default 0,
  modified_at timestamptz not null,
  updated_at timestamptz not null default clock_timestamp(),
  deleted_at timestamptz
);

create table public.sport_sets (
  id uuid primary key,
  entry_id uuid not null references public.sport_entries (id),
  profile_id uuid not null references public.sport_profiles (id),
  set_index smallint not null,
  weight_kg numeric(6, 2) not null default 0 check (weight_kg >= 0),
  reps smallint not null default 0 check (reps >= 0),
  done_at timestamptz,
  modified_at timestamptz not null,
  updated_at timestamptz not null default clock_timestamp(),
  deleted_at timestamptz
);

create table public.sport_feedback (
  id uuid primary key,
  entry_id uuid not null references public.sport_entries (id),
  profile_id uuid not null references public.sport_profiles (id),
  effort text check (effort in ('facile', 'bien', 'dur')),
  note text,
  modified_at timestamptz not null,
  updated_at timestamptz not null default clock_timestamp(),
  deleted_at timestamptz
);

create table public.sport_coach_reviews (
  id uuid primary key,
  profile_id uuid not null references public.sport_profiles (id),
  month date not null,
  payload jsonb not null,
  modified_at timestamptz not null,
  updated_at timestamptz not null default clock_timestamp(),
  deleted_at timestamptz
);

-- Index : clés étrangères + curseur de synchronisation.
create index on public.sport_body_weights (profile_id);
create index on public.sport_template_items (template_id);
create index on public.sport_sessions (template_id);
create index on public.sport_entries (session_id);
create index on public.sport_sets (entry_id);
create index on public.sport_sets (profile_id);
create index on public.sport_feedback (entry_id);
create index on public.sport_feedback (profile_id);
create index on public.sport_coach_reviews (profile_id);

do $$
declare
  t text;
begin
  foreach t in array array[
    'sport_profiles', 'sport_body_weights', 'sport_exercises', 'sport_templates', 'sport_template_items',
    'sport_sessions', 'sport_entries', 'sport_sets', 'sport_feedback', 'sport_coach_reviews'
  ] loop
    execute format('create index on public.%I (updated_at)', t);
    execute format('create trigger touch before insert or update on public.%I for each row execute function public.sport_touch()', t);
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon', t);
    execute format(
      'create policy "membres" on public.%I for all to authenticated using ((select auth.role()) = ''authenticated'') with check ((select auth.role()) = ''authenticated'')',
      t
    );
  end loop;
end;
$$;

create trigger profiles_limit before insert or update on public.sport_profiles
  for each row execute function public.sport_profiles_limit();
