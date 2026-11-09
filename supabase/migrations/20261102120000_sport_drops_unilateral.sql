-- Dégressif (paliers enchaînés dans une même série) et unilatéral (charge par bras, gauche puis droit).
-- Nullable : les lignes existantes valent « série simple, bilatérale » sans réécriture.

alter table public.sport_sets
  add column drops jsonb check (drops is null or jsonb_typeof(drops) = 'array'),
  add column is_unilateral boolean;

alter table public.sport_exercises
  add column is_unilateral boolean;

-- Un téléphone resté sur l'ancienne version envoie ces colonnes à null (jsonb_populate_recordset) :
-- on garde alors la valeur en base au lieu d'effacer les paliers. L'app à jour envoie toujours [] ou false.
create or replace function public.sport_push(changes jsonb)
returns jsonb
language plpgsql
set search_path = ''
as $$
declare
  t text;
  cols text;
  sets text;
begin
  foreach t in array public.sport_tables() loop
    continue when jsonb_array_length(coalesce(changes -> t, '[]')) = 0;
    select string_agg(quote_ident(column_name), ', ' order by ordinal_position),
           string_agg(
             case when column_name in ('drops', 'is_unilateral')
               then format('%1$I = coalesce(excluded.%1$I, %2$I.%1$I)', column_name, t)
               else format('%1$I = excluded.%1$I', column_name)
             end, ', ' order by ordinal_position)
             filter (where column_name <> 'id')
      into cols, sets
      from information_schema.columns
     where table_schema = 'public' and table_name = t and column_name <> 'updated_at';
    execute format(
      'insert into public.%1$I (%2$s) select %2$s from jsonb_populate_recordset(null::public.%1$I, $1) '
      'on conflict (id) do update set %3$s where %1$I.modified_at <= excluded.modified_at',
      t, cols, sets
    ) using changes -> t;
  end loop;
  return jsonb_build_object('server_now', clock_timestamp());
end;
$$;

revoke execute on function public.sport_push(jsonb) from public, anon;
grant execute on function public.sport_push(jsonb) to authenticated;

-- Démonstrations des exos du catalogue (GIF + photos HD), en lecture publique.
-- Remplies une fois par scripts/build_exercise_catalog.py, jamais écrites par l'app.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('sport-media', 'sport-media', true, 5242880, array['image/gif', 'image/jpeg']);
