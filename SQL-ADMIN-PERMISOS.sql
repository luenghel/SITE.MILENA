-- ═══════════════════════════════════════════════════════════════════
-- PERMISOS DE ADMINISTRACIÓN
-- Para que la fundadora pueda ver alumnas, cambiar roles y moderar
-- Correr DESPUÉS de SQL-COMUNIDAD-V2.sql
-- ═══════════════════════════════════════════════════════════════════

-- ─── 1. Fecha de registro en perfiles ──────────────────────────────
do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='perfiles' and column_name='creado_en'
  ) then
    if exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name='perfiles' and column_name='created_at'
    ) then
      alter table public.perfiles rename column created_at to creado_en;
    else
      alter table public.perfiles add column creado_en timestamptz default now();
    end if;
  end if;
end $$;

-- Rellenar la fecha de quienes no la tengan, usando la de auth
update public.perfiles p
set creado_en = u.created_at
from auth.users u
where p.id = u.id and p.creado_en is null;

-- ─── 2. Función para saber si quien consulta es del equipo ─────────
-- Evita la recursión infinita de RLS al consultar perfiles dentro de
-- una policy de la propia tabla perfiles.
create or replace function public.es_equipo()
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.perfiles
    where id = auth.uid() and rol in ('admin','fundadora')
  );
$$;

grant execute on function public.es_equipo() to authenticated;

-- ─── 3. PERFILES: ver todos, y que el equipo pueda cambiar roles ───
alter table public.perfiles enable row level security;

drop policy if exists "Perfiles visibles para logueados" on public.perfiles;
create policy "Perfiles visibles para logueados"
  on public.perfiles for select
  using (auth.uid() is not null);

drop policy if exists "Cada uno edita su perfil" on public.perfiles;
create policy "Cada uno edita su perfil"
  on public.perfiles for update
  using (auth.uid() = id);

drop policy if exists "Equipo edita cualquier perfil" on public.perfiles;
create policy "Equipo edita cualquier perfil"
  on public.perfiles for update
  using (public.es_equipo());

-- ─── 4. COMPRAS: el equipo ve todas ────────────────────────────────
alter table public.compras enable row level security;

drop policy if exists "Cada uno ve sus compras" on public.compras;
create policy "Cada uno ve sus compras"
  on public.compras for select
  using (auth.uid() = usuario_id);

drop policy if exists "Equipo ve todas las compras" on public.compras;
create policy "Equipo ve todas las compras"
  on public.compras for select
  using (public.es_equipo());

-- ─── 5. Que el equipo pueda moderar posts y comentarios ────────────
drop policy if exists "Usuario borra sus posts" on public.posts;
create policy "Usuario borra sus posts"
  on public.posts for delete
  using (auth.uid() = usuario_id or public.es_equipo());

drop policy if exists "Usuario edita sus posts" on public.posts;
create policy "Usuario edita sus posts"
  on public.posts for update
  using (auth.uid() = usuario_id or public.es_equipo());

drop policy if exists "Usuario borra su comentario" on public.comentarios;
create policy "Usuario borra su comentario"
  on public.comentarios for delete
  using (auth.uid() = usuario_id or public.es_equipo());

-- ─── VERIFICACIÓN ──────────────────────────────────────────────────
-- Tiene que devolver "true" si sos fundadora
select public.es_equipo() as soy_del_equipo;
