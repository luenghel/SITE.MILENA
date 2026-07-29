-- ═══════════════════════════════════════════════════════════════════
-- GÉNERO + SISTEMA DE DENUNCIAS DE LA COMUNIDAD
-- ═══════════════════════════════════════════════════════════════════

-- ─── 1. GÉNERO EN EL PERFIL ────────────────────────────────────────
-- Valores: 'f' (femenino), 'm' (masculino), 'x' (prefiere no decir)
alter table public.perfiles add column if not exists genero text default 'x';

-- ─── 2. TABLA DE DENUNCIAS ─────────────────────────────────────────
create table if not exists public.denuncias (
  id uuid primary key default gen_random_uuid(),
  post_id uuid references public.posts(id) on delete cascade,
  comentario_id uuid references public.comentarios(id) on delete cascade,
  denunciante_id uuid references auth.users(id) on delete set null,
  motivo text not null,
  detalle text,
  estado text default 'pendiente',
  creado_en timestamptz default now(),
  revisado_en timestamptz
);

-- Una denuncia por persona y por post
create unique index if not exists denuncias_unicas
  on public.denuncias (post_id, denunciante_id)
  where post_id is not null;

alter table public.denuncias enable row level security;

-- Cualquier persona logueada puede denunciar
drop policy if exists "Logueados denuncian" on public.denuncias;
create policy "Logueados denuncian"
  on public.denuncias for insert
  with check (auth.uid() = denunciante_id);

-- Cada uno ve sus propias denuncias
drop policy if exists "Ver mis denuncias" on public.denuncias;
create policy "Ver mis denuncias"
  on public.denuncias for select
  using (auth.uid() = denunciante_id);

-- El equipo ve y gestiona todas
drop policy if exists "Equipo ve denuncias" on public.denuncias;
create policy "Equipo ve denuncias"
  on public.denuncias for select
  using (public.es_equipo());

drop policy if exists "Equipo actualiza denuncias" on public.denuncias;
create policy "Equipo actualiza denuncias"
  on public.denuncias for update
  using (public.es_equipo());

drop policy if exists "Equipo borra denuncias" on public.denuncias;
create policy "Equipo borra denuncias"
  on public.denuncias for delete
  using (public.es_equipo());

-- ─── 3. OCULTAR POSTS DENUNCIADOS ──────────────────────────────────
-- Cuando el equipo oculta un post, deja de verse en la comunidad
-- pero no se borra (queda para revisar).
alter table public.posts add column if not exists oculto boolean default false;
update public.posts set oculto = false where oculto is null;

-- Que la comunidad no muestre los ocultos (salvo al equipo)
drop policy if exists "Posts visibles para logueados" on public.posts;
create policy "Posts visibles para logueados"
  on public.posts for select
  using (
    auth.uid() is not null
    and (coalesce(oculto, false) = false or public.es_equipo() or usuario_id = auth.uid())
  );

-- ─── 4. BLOQUEAR MIEMBROS ──────────────────────────────────────────
-- Un miembro bloqueado no puede publicar ni comentar
alter table public.perfiles add column if not exists bloqueado boolean default false;
update public.perfiles set bloqueado = false where bloqueado is null;

create or replace function public.puede_publicar()
returns boolean
language sql
security definer
set search_path = public
as $$
  select coalesce(
    (select not coalesce(bloqueado, false) from public.perfiles where id = auth.uid()),
    false
  );
$$;

grant execute on function public.puede_publicar() to authenticated;

drop policy if exists "Usuario publica sus posts" on public.posts;
create policy "Usuario publica sus posts"
  on public.posts for insert
  with check (auth.uid() = usuario_id and public.puede_publicar());

drop policy if exists "Usuario comenta" on public.comentarios;
create policy "Usuario comenta"
  on public.comentarios for insert
  with check (auth.uid() = usuario_id and public.puede_publicar());

-- ─── VERIFICACIÓN ──────────────────────────────────────────────────
select column_name from information_schema.columns
where table_schema='public' and table_name='perfiles'
  and column_name in ('genero','bloqueado');
