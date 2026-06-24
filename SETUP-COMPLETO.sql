-- ═══════════════════════════════════════════════════════════════════
-- SQL COMPLETO - SITIO MILENA - CMM
-- Ejecutar todo de una vez en Supabase SQL Editor
-- ═══════════════════════════════════════════════════════════════════

-- 1. COLUMNAS NUEVAS EN CURSOS
alter table public.cursos add column if not exists slogan text;
alter table public.cursos add column if not exists foto_portada text;
alter table public.cursos add column if not exists galeria_urls text[];

-- 2. TABLA NEWSLETTER
create table if not exists public.newsletter_suscriptores (
  id uuid primary key default gen_random_uuid(),
  email text unique not null,
  suscrito_en timestamptz default now(),
  activo bool default true
);
alter table public.newsletter_suscriptores enable row level security;
drop policy if exists "Todos pueden suscribirse" on public.newsletter_suscriptores;
create policy "Todos pueden suscribirse"
  on public.newsletter_suscriptores for insert with check (true);
drop policy if exists "Admin ve suscriptores" on public.newsletter_suscriptores;
create policy "Admin ve suscriptores"
  on public.newsletter_suscriptores for select using (
    exists (select 1 from public.perfiles where id = auth.uid() and rol in ('admin', 'fundadora'))
  );

-- 3. TABLA CARRUSELES
create table if not exists public.carruseles (
  id uuid primary key default gen_random_uuid(),
  tipo text not null check (tipo in ('home_principal', 'home_vertical')),
  imagen_url text not null,
  titulo text,
  descripcion text,
  link text,
  orden int default 0,
  activo bool default true,
  creado_en timestamptz default now()
);
alter table public.carruseles enable row level security;
drop policy if exists "Carruseles activos visibles" on public.carruseles;
create policy "Carruseles activos visibles"
  on public.carruseles for select using (activo = true);
drop policy if exists "Admin gestiona carruseles - insert" on public.carruseles;
create policy "Admin gestiona carruseles - insert"
  on public.carruseles for insert with check (
    exists (select 1 from public.perfiles where id = auth.uid() and rol in ('admin', 'fundadora'))
  );
drop policy if exists "Admin gestiona carruseles - update" on public.carruseles;
create policy "Admin gestiona carruseles - update"
  on public.carruseles for update using (
    exists (select 1 from public.perfiles where id = auth.uid() and rol in ('admin', 'fundadora'))
  );
drop policy if exists "Admin gestiona carruseles - delete" on public.carruseles;
create policy "Admin gestiona carruseles - delete"
  on public.carruseles for delete using (
    exists (select 1 from public.perfiles where id = auth.uid() and rol in ('admin', 'fundadora'))
  );

-- 4. TABLA ARTÍCULOS DEL BLOG
create table if not exists public.articulos (
  id uuid primary key default gen_random_uuid(),
  slug text unique not null,
  titulo text not null,
  resumen text,
  contenido text,
  imagen_portada text,
  categoria text,
  tiempo_lectura int default 5,
  autor text default 'Milena Machado',
  publicado bool default false,
  destacado bool default false,
  publicado_en timestamptz,
  creado_en timestamptz default now(),
  actualizado_en timestamptz default now()
);
alter table public.articulos enable row level security;
drop policy if exists "Articulos publicados visibles" on public.articulos;
create policy "Articulos publicados visibles"
  on public.articulos for select using (publicado = true);
drop policy if exists "Admin ve todos articulos" on public.articulos;
create policy "Admin ve todos articulos"
  on public.articulos for select using (
    exists (select 1 from public.perfiles where id = auth.uid() and rol in ('admin', 'fundadora'))
  );
drop policy if exists "Admin gestiona articulos - insert" on public.articulos;
create policy "Admin gestiona articulos - insert"
  on public.articulos for insert with check (
    exists (select 1 from public.perfiles where id = auth.uid() and rol in ('admin', 'fundadora'))
  );
drop policy if exists "Admin gestiona articulos - update" on public.articulos;
create policy "Admin gestiona articulos - update"
  on public.articulos for update using (
    exists (select 1 from public.perfiles where id = auth.uid() and rol in ('admin', 'fundadora'))
  );
drop policy if exists "Admin gestiona articulos - delete" on public.articulos;
create policy "Admin gestiona articulos - delete"
  on public.articulos for delete using (
    exists (select 1 from public.perfiles where id = auth.uid() and rol in ('admin', 'fundadora'))
  );

-- 5. PERMISOS DEL STORAGE (bucket "imagenes")
-- IMPORTANTE: Antes de correr esto, creá el bucket "imagenes" público desde la UI
drop policy if exists "Imagenes son publicas" on storage.objects;
create policy "Imagenes son publicas"
  on storage.objects for select using (bucket_id = 'imagenes');
drop policy if exists "Admin puede subir imagenes" on storage.objects;
create policy "Admin puede subir imagenes"
  on storage.objects for insert with check (
    bucket_id = 'imagenes' AND
    exists (select 1 from public.perfiles where id = auth.uid() and rol in ('admin', 'fundadora'))
  );
drop policy if exists "Admin puede actualizar imagenes" on storage.objects;
create policy "Admin puede actualizar imagenes"
  on storage.objects for update using (
    bucket_id = 'imagenes' AND
    exists (select 1 from public.perfiles where id = auth.uid() and rol in ('admin', 'fundadora'))
  );
drop policy if exists "Admin puede borrar imagenes" on storage.objects;
create policy "Admin puede borrar imagenes"
  on storage.objects for delete using (
    bucket_id = 'imagenes' AND
    exists (select 1 from public.perfiles where id = auth.uid() and rol in ('admin', 'fundadora'))
  );

-- 6. DESPUBLICAR CURSOS DE PRUEBA (no se borran, solo dejan de aparecer)
-- Si querés que NADA se vea en el sitio mientras Milena carga el contenido real,
-- ejecutá esta línea:
update public.cursos set publicado = false where slug in ('test-pago');
-- Si querés despublicar TODOS los cursos actuales y que Milena los publique uno por uno:
-- update public.cursos set publicado = false;

-- ─── LISTO ───
