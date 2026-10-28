-- Synchronisation : une requête pour tout recevoir, une requête pour tout envoyer, un canal temps réel.

-- Ordre de dépendance des clés étrangères (envoi parent avant enfant).
create function public.sport_tables() returns text[]
language sql
immutable
set search_path = ''
as $$
  select array[
    'sport_profiles', 'sport_body_weights', 'sport_exercises', 'sport_templates', 'sport_template_items',
    'sport_sessions', 'sport_entries', 'sport_sets', 'sport_feedback', 'sport_coach_reviews'
  ];
$$;

-- Toutes les lignes modifiées après `since` (curseur serveur), toutes tables confondues.
create function public.sport_pull(since timestamptz default '-infinity')
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  t text;
  rows jsonb;
  result jsonb := jsonb_build_object('server_now', clock_timestamp());
begin
  foreach t in array public.sport_tables() loop
    execute format(
      'select coalesce(jsonb_agg(to_jsonb(r) - ''updated_at''), ''[]'') from public.%I r where r.updated_at > $1',
      t
    ) into rows using since;
    result := result || jsonb_build_object(t, rows);
  end loop;
  return result;
end;
$$;

-- Upsert en lot dans une transaction. Une ligne n'écrase la version serveur que si elle est plus récente
-- (modified_at), pour qu'un téléphone resté hors ligne ne remplace pas une saisie plus fraîche.
create function public.sport_push(changes jsonb)
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
           string_agg(format('%1$I = excluded.%1$I', column_name), ', ' order by ordinal_position)
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

revoke execute on function public.sport_pull(timestamptz) from public, anon;
revoke execute on function public.sport_push(jsonb) from public, anon;
grant execute on function public.sport_pull(timestamptz) to authenticated;
grant execute on function public.sport_push(jsonb) to authenticated;

-- Temps réel : chaque écriture est diffusée sur le canal privé `sport`.
create function public.sport_broadcast() returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform realtime.broadcast_changes('sport', tg_op, tg_op, tg_table_name, tg_table_schema, new, old);
  return null;
end;
$$;

revoke execute on function public.sport_broadcast() from public, anon, authenticated;

do $$
declare
  t text;
begin
  foreach t in array public.sport_tables() loop
    execute format(
      'create trigger broadcast after insert or update or delete on public.%I for each row execute function public.sport_broadcast()',
      t
    );
  end loop;
end;
$$;

create policy "membres reçoivent le canal sport"
  on realtime.messages for select to authenticated
  using ((select realtime.topic()) = 'sport');

-- Photos des machines.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('sport-photos', 'sport-photos', false, 2097152, array['image/jpeg']);

create policy "membres lisent les photos" on storage.objects for select to authenticated
  using (bucket_id = 'sport-photos');
create policy "membres ajoutent des photos" on storage.objects for insert to authenticated
  with check (bucket_id = 'sport-photos');
create policy "membres remplacent les photos" on storage.objects for update to authenticated
  using (bucket_id = 'sport-photos');
create policy "membres suppriment les photos" on storage.objects for delete to authenticated
  using (bucket_id = 'sport-photos');
