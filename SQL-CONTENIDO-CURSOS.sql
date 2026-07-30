-- ═══════════════════════════════════════════════════════════════════
-- CONTENIDO DE LOS CURSOS
--   · Módulos y clases (como Kiwify / Hotmart)
--   · Tipos de contenido: curso, club, canal, material
--   · Secciones del catálogo, editables desde el admin
-- ═══════════════════════════════════════════════════════════════════

-- ─── 1. CURSOS: campos nuevos ──────────────────────────────────────
-- tipo:    curso · club · canal · material · comunidad
-- seccion: principal (Marketing Digital) · acompana (Acompañá más)
alter table public.cursos add column if not exists tipo text default 'curso';
alter table public.cursos add column if not exists seccion text default 'principal';
alter table public.cursos add column if not exists enlace_externo text;
alter table public.cursos add column if not exists etiqueta text;
alter table public.cursos add column if not exists nota_precio text;
alter table public.cursos add column if not exists acceso text default 'pago';
-- acceso: pago · gratis · suscripcion

update public.cursos set tipo = 'curso'        where tipo is null;
update public.cursos set seccion = 'principal' where seccion is null;
update public.cursos set acceso = case when coalesce(precio_gs,0) = 0 then 'gratis' else 'pago' end
  where acceso is null;

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
alter table public.modulos add column if not exists publicado boolean default true;
alter table public.modulos add column if not exists orden int default 0;

alter table public.modulos enable row level security;

drop policy if exists "Modulos publicados visibles" on public.modulos;
create policy "Modulos publicados visibles"
  on public.modulos for select
  using (coalesce(publicado, true) = true or public.es_equipo());

drop policy if exists "Equipo crea modulos" on public.modulos;
create policy "Equipo crea modulos"
  on public.modulos for insert with check (public.es_equipo());

drop policy if exists "Equipo edita modulos" on public.modulos;
create policy "Equipo edita modulos"
  on public.modulos for update using (public.es_equipo());

drop policy if exists "Equipo borra modulos" on public.modulos;
create policy "Equipo borra modulos"
  on public.modulos for delete using (public.es_equipo());

-- ─── 3. CLASES ─────────────────────────────────────────────────────
create table if not exists public.clases (
  id uuid primary key default gen_random_uuid(),
  modulo_id uuid references public.modulos(id) on delete cascade,
  curso_id uuid references public.cursos(id) on delete cascade,
  titulo text not null,
  orden int default 0,
  creado_en timestamptz default now()
);

alter table public.clases add column if not exists modulo_id uuid references public.modulos(id) on delete cascade;
alter table public.clases add column if not exists curso_id uuid references public.cursos(id) on delete cascade;
alter table public.clases add column if not exists descripcion text;
alter table public.clases add column if not exists tipo text default 'video';
-- tipo: video · pdf · texto · enlace · audio
alter table public.clases add column if not exists video_url text;
alter table public.clases add column if not exists archivo_url text;
alter table public.clases add column if not exists contenido text;
alter table public.clases add column if not exists duracion_minutos int default 0;
alter table public.clases add column if not exists orden int default 0;
alter table public.clases add column if not exists publicado boolean default true;
alter table public.clases add column if not exists gratis boolean default false;
-- gratis = clase de muestra, se ve sin comprar

update public.clases set tipo = 'video' where tipo is null;
update public.clases set publicado = true where publicado is null;
update public.clases set gratis = false where gratis is null;

alter table public.clases enable row level security;

drop policy if exists "Clases visibles" on public.clases;
create policy "Clases visibles"
  on public.clases for select
  using (coalesce(publicado, true) = true or public.es_equipo());

drop policy if exists "Equipo crea clases" on public.clases;
create policy "Equipo crea clases"
  on public.clases for insert with check (public.es_equipo());

drop policy if exists "Equipo edita clases" on public.clases;
create policy "Equipo edita clases"
  on public.clases for update using (public.es_equipo());

drop policy if exists "Equipo borra clases" on public.clases;
create policy "Equipo borra clases"
  on public.clases for delete using (public.es_equipo());

-- ─── 4. MATERIALES DE APOYO (PDF, plantillas, enlaces) ─────────────
create table if not exists public.materiales (
  id uuid primary key default gen_random_uuid(),
  clase_id uuid references public.clases(id) on delete cascade,
  curso_id uuid references public.cursos(id) on delete cascade,
  titulo text not null,
  tipo text default 'pdf',           -- pdf · enlace · imagen · archivo
  url text not null,
  orden int default 0,
  creado_en timestamptz default now()
);

alter table public.materiales enable row level security;

drop policy if exists "Materiales visibles" on public.materiales;
create policy "Materiales visibles"
  on public.materiales for select using (auth.uid() is not null);

drop policy if exists "Equipo gestiona materiales - insert" on public.materiales;
create policy "Equipo gestiona materiales - insert"
  on public.materiales for insert with check (public.es_equipo());

drop policy if exists "Equipo gestiona materiales - update" on public.materiales;
create policy "Equipo gestiona materiales - update"
  on public.materiales for update using (public.es_equipo());

drop policy if exists "Equipo gestiona materiales - delete" on public.materiales;
create policy "Equipo gestiona materiales - delete"
  on public.materiales for delete using (public.es_equipo());

-- ─── 5. PROGRESO DE LA ALUMNA ──────────────────────────────────────
create table if not exists public.progreso (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid references auth.users(id) on delete cascade,
  clase_id uuid references public.clases(id) on delete cascade,
  curso_id uuid references public.cursos(id) on delete cascade,
  completada boolean default false,
  segundos_vistos int default 0,
  actualizado_en timestamptz default now()
);

alter table public.progreso add column if not exists clase_id uuid references public.clases(id) on delete cascade;
alter table public.progreso add column if not exists curso_id uuid references public.cursos(id) on delete cascade;
alter table public.progreso add column if not exists completada boolean default false;
alter table public.progreso add column if not exists segundos_vistos int default 0;
alter table public.progreso add column if not exists actualizado_en timestamptz default now();

create unique index if not exists progreso_unico on public.progreso (usuario_id, clase_id);

alter table public.progreso enable row level security;

drop policy if exists "Cada una ve su progreso" on public.progreso;
create policy "Cada una ve su progreso"
  on public.progreso for select using (auth.uid() = usuario_id or public.es_equipo());

drop policy if exists "Cada una guarda su progreso" on public.progreso;
create policy "Cada una guarda su progreso"
  on public.progreso for insert with check (auth.uid() = usuario_id);

drop policy if exists "Cada una actualiza su progreso" on public.progreso;
create policy "Cada una actualiza su progreso"
  on public.progreso for update using (auth.uid() = usuario_id);

-- ─── 6. ACCESO A CURSOS GRATIS ─────────────────────────────────────
-- Que una alumna pueda darse acceso sola a lo gratuito,
-- sin pasar por el checkout ni por Pagopar.
drop policy if exists "Alta en cursos gratis" on public.compras;
create policy "Alta en cursos gratis"
  on public.compras for insert
  with check (
    auth.uid() = usuario_id
    and coalesce(monto_gs, 0) = 0
    and exists (
      select 1 from public.cursos c
      where c.id = curso_id
        and (coalesce(c.precio_gs, 0) = 0 or c.acceso = 'gratis')
    )
  );

-- ─── 7. CONTAR MÓDULOS Y CLASES SOLO ───────────────────────────────
create or replace function public.recontar_curso()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  cid uuid;
begin
  cid := coalesce(new.curso_id, old.curso_id);
  if cid is null then return coalesce(new, old); end if;

  update public.cursos set
    modulos_count = (select count(*) from public.modulos where curso_id = cid and coalesce(publicado,true)),
    clases_count  = (select count(*) from public.clases  where curso_id = cid and coalesce(publicado,true)),
    duracion_minutos = (select coalesce(sum(duracion_minutos),0) from public.clases where curso_id = cid and coalesce(publicado,true))
  where id = cid;

  return coalesce(new, old);
end;
$$;

drop trigger if exists trg_recontar_clases on public.clases;
create trigger trg_recontar_clases
  after insert or update or delete on public.clases
  for each row execute function public.recontar_curso();

drop trigger if exists trg_recontar_modulos on public.modulos;
create trigger trg_recontar_modulos
  after insert or update or delete on public.modulos
  for each row execute function public.recontar_curso();

-- ─── VERIFICACIÓN ──────────────────────────────────────────────────
select 'listo' as estado,
  (select count(*) from public.modulos) as modulos,
  (select count(*) from public.clases) as clases;
