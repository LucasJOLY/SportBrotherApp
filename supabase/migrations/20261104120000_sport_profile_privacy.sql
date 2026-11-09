-- Confidentialité des profils, appliquée par l'app (pas par la base) :
--   owner_device           téléphone propriétaire du profil (identifiant d'installation, gardé dans le trousseau) ;
--   shares_data            les autres téléphones voient séances, stats, pesées et coach (sinon juste le prénom) ;
--   allows_others_logging  les autres téléphones peuvent saisir des séries pour ce profil.
-- Colonnes nulles = comportement d'avant (tout partagé, sans propriétaire).
alter table public.sport_profiles
  add column owner_device text check (owner_device is null or length(owner_device) <= 64),
  add column shares_data boolean,
  add column allows_others_logging boolean;

-- Un téléphone encore sur l'ancienne version envoie ces colonnes à null : on garde la valeur en base.
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
             case when column_name in ('drops', 'is_unilateral', 'owner_device', 'shares_data', 'allows_others_logging')
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
