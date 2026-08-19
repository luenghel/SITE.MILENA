-- ═══════════════════════════════════════════════════════════════════
-- REPARAR LA SUBIDA DE IMÁGENES
-- Junta todas las reglas de Storage en una sola configuración limpia.
-- Es seguro correrlo aunque ya hayas corrido los otros SQL.
-- ═══════════════════════════════════════════════════════════════════

-- ─── 1. El depósito de imágenes, público ───────────────────────────
insert into storage.buckets (id, name, public)
values ('imagenes', 'imagenes', true)
on conflict (id) do update set public = true;

-- ─── 2. Borrar TODAS las reglas anteriores ─────────────────────────
-- (con el tiempo se fueron acumulando y se pisaban entre sí)
drop policy if exists "Imagenes son publicas" on storage.objects;
drop policy if exists "Ver imagenes" on storage.objects;
drop policy if exists "Admin puede subir imagenes" on storage.objects;
drop policy if exists "Admin puede actualizar imagenes" on storage.objects;
drop policy if exists "Admin puede borrar imagenes" on storage.objects;
drop policy if exists "Logueados suben imagenes" on storage.objects;
drop policy if exists "Logueados suben imagenes de posts" on storage.objects;
drop policy if exists "Actualizar imagenes propias" on storage.objects;
drop policy if exists "Borrar imagenes propias" on storage.objects;

-- ─── 3. Reglas nuevas, simples y claras ────────────────────────────

-- Cualquiera puede VER las imágenes (si no, no se muestran en el sitio)
create policy "Ver imagenes"
  on storage.objects for select
  using (bucket_id = 'imagenes');

-- Cualquier persona con sesión puede SUBIR, a cualquier carpeta
create policy "Subir imagenes"
  on storage.objects for insert
  to authenticated
  with check (bucket_id = 'imagenes');

-- Cada uno puede REEMPLAZAR lo suyo; el equipo, cualquier cosa
create policy "Actualizar imagenes"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'imagenes'
    and (owner = auth.uid() or public.es_equipo())
  );

-- Cada uno puede BORRAR lo suyo; el equipo, cualquier cosa
create policy "Borrar imagenes"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'imagenes'
    and (owner = auth.uid() or public.es_equipo())
  );

-- ─── 4. Columnas de los banners (por si faltaran) ──────────────────
alter table public.carruseles add column if not exists imagen_movil text;
alter table public.carruseles add column if not exists texto_boton text;
alter table public.carruseles add column if not exists mostrar_boton boolean default true;
update public.carruseles set mostrar_boton = true where mostrar_boton is null;

-- ─── 5. Que el equipo pueda borrar banners ─────────────────────────
drop policy if exists "Admin gestiona carruseles - delete" on public.carruseles;
create policy "Admin gestiona carruseles - delete"
  on public.carruseles for delete
  using (public.es_equipo());

drop policy if exists "Admin gestiona carruseles - update" on public.carruseles;
create policy "Admin gestiona carruseles - update"
  on public.carruseles for update
  using (public.es_equipo());

drop policy if exists "Admin gestiona carruseles - insert" on public.carruseles;
create policy "Admin gestiona carruseles - insert"
  on public.carruseles for insert
  with check (public.es_equipo());

-- ═══════════════════════════════════════════════════════════════════
-- VERIFICACIÓN — mirá los resultados
-- ═══════════════════════════════════════════════════════════════════

-- ¿Existe el depósito y es público?
select id, public as es_publico from storage.buckets where id = 'imagenes';

-- ¿Están las columnas de los banners?
select column_name from information_schema.columns
where table_schema = 'public' and table_name = 'carruseles'
  and column_name in ('imagen_movil','texto_boton','mostrar_boton','link');

-- ¿Cuántas reglas de Storage quedaron? (tienen que ser 4)
select policyname from pg_policies
where schemaname = 'storage' and tablename = 'objects'
order by policyname;
