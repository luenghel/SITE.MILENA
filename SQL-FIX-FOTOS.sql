-- ═══════════════════════════════════════════════════════════════════
-- ARREGLAR LA SUBIDA DE FOTOS
-- Crea el bucket "imagenes" si falta y simplifica los permisos
-- ═══════════════════════════════════════════════════════════════════

-- ─── 1. Crear el bucket si no existe (público) ─────────────────────
insert into storage.buckets (id, name, public)
values ('imagenes', 'imagenes', true)
on conflict (id) do update set public = true;

-- ─── 2. Borrar las políticas viejas que se pisaban entre sí ────────
drop policy if exists "Imagenes son publicas" on storage.objects;
drop policy if exists "Admin puede subir imagenes" on storage.objects;
drop policy if exists "Admin puede actualizar imagenes" on storage.objects;
drop policy if exists "Admin puede borrar imagenes" on storage.objects;
drop policy if exists "Logueados suben imagenes de posts" on storage.objects;

-- ─── 3. Políticas nuevas, simples y que funcionan ──────────────────

-- Cualquiera puede VER las imágenes (necesario para que se muestren)
create policy "Ver imagenes"
  on storage.objects for select
  using (bucket_id = 'imagenes');

-- Cualquier persona logueada puede SUBIR
create policy "Logueados suben imagenes"
  on storage.objects for insert
  to authenticated
  with check (bucket_id = 'imagenes');

-- Cada uno puede ACTUALIZAR lo que subió; el equipo, cualquier cosa
create policy "Actualizar imagenes propias"
  on storage.objects for update
  to authenticated
  using (bucket_id = 'imagenes' and (owner = auth.uid() or public.es_equipo()));

-- Cada uno puede BORRAR lo que subió; el equipo, cualquier cosa
create policy "Borrar imagenes propias"
  on storage.objects for delete
  to authenticated
  using (bucket_id = 'imagenes' and (owner = auth.uid() or public.es_equipo()));

-- ─── VERIFICACIÓN ──────────────────────────────────────────────────
select id, name, public from storage.buckets where id = 'imagenes';
