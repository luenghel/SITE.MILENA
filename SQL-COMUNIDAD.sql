-- ═══════════════════════════════════════════════════════════════════
-- COMUNIDAD CMM - posts, likes y comentarios
-- Seguro de ejecutar aunque las tablas ya existan
-- ═══════════════════════════════════════════════════════════════════

-- ─── 1. POSTS ───────────────────────────────────────────────────────
create table if not exists public.posts (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid references auth.users(id) on delete cascade,
  contenido text not null,
  creado_en timestamptz default now()
);

alter table public.posts add column if not exists imagen_url text;
alter table public.posts add column if not exists categoria text default 'general';
alter table public.posts add column if not exists hashtags text[];
alter table public.posts add column if not exists fijado bool default false;
alter table public.posts add column if not exists creado_en timestamptz default now();

alter table public.posts enable row level security;

drop policy if exists "Posts visibles para logueados" on public.posts;
create policy "Posts visibles para logueados"
  on public.posts for select
  using (auth.uid() is not null);

drop policy if exists "Usuario publica sus posts" on public.posts;
create policy "Usuario publica sus posts"
  on public.posts for insert
  with check (auth.uid() = usuario_id);

drop policy if exists "Usuario edita sus posts" on public.posts;
create policy "Usuario edita sus posts"
  on public.posts for update
  using (
    auth.uid() = usuario_id
    or exists (select 1 from public.perfiles where id = auth.uid() and rol in ('admin','fundadora'))
  );

drop policy if exists "Usuario borra sus posts" on public.posts;
create policy "Usuario borra sus posts"
  on public.posts for delete
  using (
    auth.uid() = usuario_id
    or exists (select 1 from public.perfiles where id = auth.uid() and rol in ('admin','fundadora'))
  );

-- ─── 2. LIKES ───────────────────────────────────────────────────────
create table if not exists public.likes (
  id uuid primary key default gen_random_uuid(),
  post_id uuid references public.posts(id) on delete cascade,
  usuario_id uuid references auth.users(id) on delete cascade,
  creado_en timestamptz default now()
);

create unique index if not exists likes_unicos on public.likes (post_id, usuario_id);

alter table public.likes enable row level security;

drop policy if exists "Likes visibles" on public.likes;
create policy "Likes visibles"
  on public.likes for select using (auth.uid() is not null);

drop policy if exists "Usuario da like" on public.likes;
create policy "Usuario da like"
  on public.likes for insert with check (auth.uid() = usuario_id);

drop policy if exists "Usuario quita su like" on public.likes;
create policy "Usuario quita su like"
  on public.likes for delete using (auth.uid() = usuario_id);

-- ─── 3. COMENTARIOS ─────────────────────────────────────────────────
create table if not exists public.comentarios (
  id uuid primary key default gen_random_uuid(),
  post_id uuid references public.posts(id) on delete cascade,
  usuario_id uuid references auth.users(id) on delete cascade,
  contenido text not null,
  creado_en timestamptz default now()
);

alter table public.comentarios add column if not exists creado_en timestamptz default now();
alter table public.comentarios enable row level security;

drop policy if exists "Comentarios visibles" on public.comentarios;
create policy "Comentarios visibles"
  on public.comentarios for select using (auth.uid() is not null);

drop policy if exists "Usuario comenta" on public.comentarios;
create policy "Usuario comenta"
  on public.comentarios for insert with check (auth.uid() = usuario_id);

drop policy if exists "Usuario borra su comentario" on public.comentarios;
create policy "Usuario borra su comentario"
  on public.comentarios for delete
  using (
    auth.uid() = usuario_id
    or exists (select 1 from public.perfiles where id = auth.uid() and rol in ('admin','fundadora'))
  );

-- ─── 4. PERFILES: que todos los logueados puedan ver nombres ────────
alter table public.perfiles add column if not exists avatar_url text;
alter table public.perfiles add column if not exists bio text;

drop policy if exists "Perfiles visibles para logueados" on public.perfiles;
create policy "Perfiles visibles para logueados"
  on public.perfiles for select
  using (auth.uid() is not null);

-- ─── 5. IMÁGENES DE POSTS: cualquier logueado puede subir ───────────
drop policy if exists "Logueados suben imagenes de posts" on storage.objects;
create policy "Logueados suben imagenes de posts"
  on storage.objects for insert
  with check (
    bucket_id = 'imagenes'
    and auth.uid() is not null
    and (storage.foldername(name))[1] = 'posts'
  );

-- ─── LISTO ──────────────────────────────────────────────────────────
