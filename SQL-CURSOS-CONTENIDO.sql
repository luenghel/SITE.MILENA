-- ═══════════════════════════════════════════════════════════════════
-- CONTENIDO DE LOS CURSOS
--   · Módulos y clases con video
--   · Secciones del home
--   · Acceso a cursos gratis
-- ═══════════════════════════════════════════════════════════════════

-- ─── 1. SECCIÓN DEL CURSO EN EL SITIO ──────────────────────────────
-- 'principal'  → fila "Marketing Digital"
-- 'acompana'   → fila "Acompañá más"
alter table public.cursos add column if not exists seccion text default 'principal';
alter table public.cursos add column if not exists es_gratis boolean default false;
alter table public.cursos add column if not exists nivel text;
alter table public.cursos add column if not exists que_aprendes text[];

update public.cursos set seccion = 'principal' where seccion is null;
update public.cursos set es_gratis = (precio_gs = 0) where es_gratis is null;

-- ─── 2. MÓDULOS ────────────────────────────────────────────────────
create table if not exists public.modulos (
  id uuid primary key default gen_random_uuid(),
  curso_id uuid references public.cursos(id) on delete cascade,
  titulo text not null,
  descripcion text,
  orden int default 0,
  publicado boolean default true,
  creado_en timestamptz default now()
);

alter table public.modulos add column if not exists descripcion text;
alter table public.modulos add column if not exists orden int default 0;
alter table public.modulos add column if not exists publicado boolean default true;
alter table public.modulos add column if not exists creado_en timestamptz default now();

alter table public.modulos enable row level security;

drop policy if exists "Modulos visibles" on public.modulos;
create policy "Modulos visibles"
  on public.modulos for select using (true);

drop policy if exists "Equipo gestiona modulos - insert" on public.modulos;
create policy "Equipo gestiona modulos - insert"
  on public.modulos for insert with check (public.es_equipo());

drop policy if exists "Equipo gestiona modulos - update" on public.modulos;
create policy "Equipo gestiona modulos - update"
  on public.modulos for update using (public.es_equipo());

drop policy if exists "Equipo gestiona modulos - delete" on public.modulos;
create policy "Equipo gestiona modulos - delete"
  on public.modulos for delete using (public.es_equipo());

-- ─── 3. CLASES ─────────────────────────────────────────────────────
create table if not exists public.clases (
  id uuid primary key default gen_random_uuid(),
  modulo_id uuid references public.modulos(id) on delete cascade,
  titulo text not null,
  orden int default 0,
  creado_en timestamptz default now()
);

alter table public.clases add column if not exists curso_id uuid references public.cursos(id) on delete cascade;
alter table public.clases add column if not exists descripcion text;
alter table public.clases add column if not exists video_url text;
alter table public.clases add column if not exists video_id text;
alter table public.clases add column if not exists duracion_min int default 0;
alter table public.clases add column if not exists material_url text;
alter table public.clases add column if not exists material_nombre text;
alter table public.clases add column if not exists es_muestra boolean default false;
alter table public.clases add column if not exists publicado boolean default true;
alter table public.clases add column if not exists orden int default 0;
alter table public.clases add column if not exists creado_en timestamptz default now();

alter table public.clases enable row level security;

drop policy if exists "Clases visibles" on public.clases;
create policy "Clases visibles"
  on public.clases for select using (true);

drop policy if exists "Equipo gestiona clases - insert" on public.clases;
create policy "Equipo gestiona clases - insert"
  on public.clases for insert with check (public.es_equipo());

drop policy if exists "Equipo gestiona clases - update" on public.clases;
create policy "Equipo gestiona clases - update"
  on public.clases for update using (public.es_equipo());

drop policy if exists "Equipo gestiona clases - delete" on public.clases;
create policy "Equipo gestiona clases - delete"
  on public.clases for delete using (public.es_equipo());

-- ─── 4. PROGRESO DE CADA ALUMNA ────────────────────────────────────
create table if not exists public.progreso (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid references auth.users(id) on delete cascade,
  clase_id uuid references public.clases(id) on delete cascade,
  completada boolean default false,
  segundos_vistos int default 0,
  actualizado_en timestamptz default now()
);

alter table public.progreso add column if not exists clase_id uuid references public.clases(id) on delete cascade;
alter table public.progreso add column if not exists completada boolean default false;
alter table public.progreso add column if not exists segundos_vistos int default 0;
alter table public.progreso add column if not exists actualizado_en timestamptz default now();

create unique index if not exists progreso_unico on public.progreso (usuario_id, clase_id);

alter table public.progreso enable row level security;

drop policy if exists "Cada uno ve su progreso" on public.progreso;
create policy "Cada uno ve su progreso"
  on public.progreso for select using (auth.uid() = usuario_id or public.es_equipo());

drop policy if exists "Cada uno guarda su progreso" on public.progreso;
create policy "Cada uno guarda su progreso"
  on public.progreso for insert with check (auth.uid() = usuario_id);

drop policy if exists "Cada uno actualiza su progreso" on public.progreso;
create policy "Cada uno actualiza su progreso"
  on public.progreso for update using (auth.uid() = usuario_id);

-- ─── 5. ACCESO A CURSOS GRATIS ─────────────────────────────────────
-- Para los gratis se crea una "compra" de Gs 0 sin pasar por Pagopar
drop policy if exists "Usuario registra su compra gratis" on public.compras;
create policy "Usuario registra su compra gratis"
  on public.compras for insert
  with check (
    auth.uid() = usuario_id
    and monto_gs = 0
    and estado = 'pagado'
    and exists (
      select 1 from public.cursos c
      where c.id = curso_id and (c.precio_gs = 0 or c.es_gratis = true)
    )
  );

-- ─── 6. CONTADORES AUTOMÁTICOS ─────────────────────────────────────
-- Mantiene modulos_count, clases_count y duracion al día
create or replace function public.recalcular_curso(p_curso uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.cursos c
  set
    modulos_count = (select count(*) from public.modulos m where m.curso_id = p_curso),
    clases_count = (
      select count(*) from public.clases cl
      join public.modulos m on m.id = cl.modulo_id
      where m.curso_id = p_curso
    ),
    duracion_minutos = (
      select coalesce(sum(cl.duracion_min), 0) from public.clases cl
      join public.modulos m on m.id = cl.modulo_id
      where m.curso_id = p_curso
    )
  where c.id = p_curso;
end;
$$;

grant execute on function public.recalcular_curso(uuid) to authenticated;

-- ─── VERIFICACIÓN ──────────────────────────────────────────────────
select 'listo' as estado,
  (select count(*) from information_schema.columns
   where table_schema='public' and table_name='clases'
     and column_name in ('video_url','duracion_min','es_muestra')) as columnas_clases;
