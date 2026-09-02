-- Recipe hero photos in Supabase Storage (spec §5.2, §7.1, §7.2).
--
-- Until now a photo lived only on the device that took it: the bytes went to
-- the app container and only the file *name* went in the database, so a
-- partner's copy of every recipe had no picture. This is the shared half.

-- ── The bucket ──────────────────────────────────────────────────────────────
--
-- Private, never public. The client ships a publishable key by design (§8.1),
-- so a public bucket would put a household's photos — a handwritten recipe
-- card, someone's kitchen — behind a URL with no auth at all. RLS on
-- storage.objects is the boundary here exactly as it is on every table
-- (§8.2), and the client reads by path with its own JWT, so there is no
-- signed-URL expiry to store or refresh.
--
-- The 4 MiB ceiling matches RecipePhotoStore.maxBytes exactly, and that
-- equality is the point: a photo that saves locally always uploads, so there
-- is no third state where an image lives on one device forever for reasons
-- the user cannot see.
insert into storage.buckets (
  id, name, public, file_size_limit, allowed_mime_types
)
values (
  'recipe-photos',
  'recipe-photos',
  false,
  4194304,
  array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif']
)
on conflict (id) do update
  set public             = excluded.public,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- ── A cast that denies instead of erroring ──────────────────────────────────
--
-- The recipe id below is parsed out of an object path, which is a string the
-- client chooses. `'nonsense'::uuid` raises rather than returning false, and a
-- raise inside a policy is a 500 where a denial was meant. Postgres does not
-- promise to evaluate a guarding `like` before the cast, so the guard has to
-- live inside the cast.
create or replace function public.uuid_or_null(p_text text)
returns uuid
language plpgsql
immutable
set search_path = ''
as $$
begin
  return p_text::uuid;
exception when others then
  return null;
end;
$$;

comment on function public.uuid_or_null(text) is
  'A cast that denies instead of erroring, for policies that parse a '
  'client-supplied string (spec §8.2).';

revoke all on function public.uuid_or_null(text) from public;
grant execute on function public.uuid_or_null(text) to authenticated;

-- ── RLS ─────────────────────────────────────────────────────────────────────
--
-- storage.objects has RLS enabled by the Storage extension rather than by us,
-- so this asserts it instead of setting it. The house rule is that nothing
-- ships without RLS proven on in the same migration that creates it; an
-- assertion satisfies that without an ALTER that can fail on ownership in the
-- hosted project.
do $$
begin
  if not exists (
    select 1
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'storage'
      and c.relname = 'objects'
      and c.relrowsecurity
  ) then
    raise exception 'RLS is not enabled on storage.objects';
  end if;
end;
$$;

-- Objects live at "<recipe_id>/<uuid>.<ext>", so foldername()[1] is the
-- recipe, and the household is derived from that recipe at query time.
--
-- Deliberately NOT "<household_id>/...", which is the obvious design and is
-- wrong here: join_household() rewrites recipes.household_id when someone
-- links up (20260827190500_household_join.sql). A household id baked into a
-- path is a copy of a mutable fact that nothing updates, so after one join
-- every carried-across photo would sit under a household with no members and
-- neither person could read it. A recipe id never moves — recipes are
-- soft-deleted, never removed — and reusing recipe_is_mine() keeps the
-- scoping rule in the one place every recipe child table already reads it.
create policy recipe_photos_select_household
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'recipe-photos'
    and public.recipe_is_mine(
      public.uuid_or_null((storage.foldername(name))[1])
    )
  );

create policy recipe_photos_insert_household
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'recipe-photos'
    and public.recipe_is_mine(
      public.uuid_or_null((storage.foldername(name))[1])
    )
  );

-- No update policy and no delete policy, deliberately — the same call
-- households made in 20260827190000_identity.sql.
--
-- Every upload writes a fresh uuid, so objects are immutable and there is
-- nothing for an update to do. And nothing is deleted from a client: a recipe
-- is soft-deleted and can be restored, a replaced photo may still be
-- downloading on the partner's phone, and an object one device destroys is
-- destroyed for both. Orphans are reaped server-side later, where "is anything
-- still pointing at this" can actually be answered, and with a floor of at
-- least 30 days so the reaper cannot race a photo_url write still sitting in
-- an offline queue.

comment on column public.recipes.photo_url is
  'The object path in the recipe-photos bucket — "<recipe_id>/<uuid>.<ext>" — '
  'not a URL. The bucket is private, so there is no durable URL to store; the '
  'client downloads by path with its own JWT (spec §5.2, §7.1).';
