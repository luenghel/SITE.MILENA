-- ═══════════════════════════════════════════════════════════════════
-- 1. VARIOS PDFs POR CLASE
-- 2. TIEMPO DE ACCESO AL CURSO
-- ═══════════════════════════════════════════════════════════════════

-- ─── 1. LOS DOCUMENTOS DE CADA CLASE ───────────────────────────────
create table if not exists public.documentos (
  id uuid primary key default gen_random_uuid(),
  clase_id uuid references public.clases(id) on delete cascade,
  curso_id uuid references public.cursos(id) on delete cascade,
  titulo text not null,
  descripcion text,
  archivo_url text not null,
  tipo text default 'pdf',            -- pdf · doc · hoja · imagen · enlace
  tamano_kb int,
  orden int default 0,
  creado_en timestamptz default now()
);

create index if not exists documentos_clase on public.documentos (clase_id, orden);

alter table public.documentos enable row level security;

-- Los ve quien tiene acceso al curso, o si la clase es de muestra
drop policy if exists "Documentos visibles" on public.documentos;
create policy "Documentos visibles"
  on public.documentos for select
  using (
    auth.uid() is not null
    and (
      public.es_equipo()
      or exists (
        select 1 from public.compras co
        where co.usuario_id = auth.uid()
          and co.curso_id = documentos.curso_id
          and co.estado = 'pagado'
      )
      or exists (
        select 1 from public.clases cl
        join public.modulos m on m.id = cl.modulo_id
        where cl.id = documentos.clase_id
          and (coalesce(cl.gratis, false) or coalesce(m.gratis, false))
      )
    )
  );

drop policy if exists "Equipo crea documentos" on public.documentos;
create policy "Equipo crea documentos" on public.documentos for insert with check (public.es_equipo());

drop policy if exists "Equipo edita documentos" on public.documentos;
create policy "Equipo edita documentos" on public.documentos for update using (public.es_equipo());

drop policy if exists "Equipo borra documentos" on public.documentos;
create policy "Equipo borra documentos" on public.documentos for delete using (public.es_equipo());

-- El tipo 'documentos': una clase que es solo un conjunto de archivos
-- (la columna tipo ya existe en clases, solo sumamos este valor posible)

-- ─── 2. CUÁNTO DURA EL ACCESO ──────────────────────────────────────
-- permanente → para siempre
-- dias       → X días desde que compró
-- Por defecto, 1 año de acceso. Se cambia curso por curso.
alter table public.cursos add column if not exists tipo_acceso text default 'dias';
alter table public.cursos add column if not exists dias_acceso int default 365;

update public.cursos set tipo_acceso = 'dias' where tipo_acceso is null;
update public.cursos set dias_acceso = 365 where dias_acceso is null and tipo_acceso = 'dias';

-- Cuándo se le vence el acceso a esta persona
alter table public.compras add column if not exists acceso_hasta timestamptz;

-- Lo calculamos para las compras que ya existen
update public.compras co
set acceso_hasta = coalesce(co.pagado_en, co.creado_en) + (c.dias_acceso || ' days')::interval
from public.cursos c
where c.id = co.curso_id
  and c.tipo_acceso = 'dias'
  and c.dias_acceso is not null
  and co.acceso_hasta is null;

-- ─── Al comprar, se calcula solo ───────────────────────────────────
create or replace function public.calcular_acceso()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tipo text;
  v_dias int;
begin
  select tipo_acceso, dias_acceso into v_tipo, v_dias
  from public.cursos where id = new.curso_id;

  if v_tipo = 'dias' and v_dias is not null and v_dias > 0 then
    new.acceso_hasta := coalesce(new.pagado_en, new.creado_en, now()) + (v_dias || ' days')::interval;
  else
    new.acceso_hasta := null;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_calcular_acceso on public.compras;
create trigger trg_calcular_acceso
  before insert or update of pagado_en, estado on public.compras
  for each row execute function public.calcular_acceso();

-- ─── ¿Todavía tiene acceso? ────────────────────────────────────────
create or replace function public.acceso_vigente(p_usuario uuid, p_curso uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.compras co
    where co.usuario_id = p_usuario
      and co.curso_id = p_curso
      and co.estado = 'pagado'
      and (co.acceso_hasta is null or co.acceso_hasta > now())
  );
$$;

grant execute on function public.acceso_vigente(uuid, uuid) to authenticated;

-- ─── VERIFICACIÓN ──────────────────────────────────────────────────
select
  c.titulo,
  case
    when c.tipo_acceso = 'dias' then c.dias_acceso || ' días'
    else 'permanente'
  end as acceso
from public.cursos c
order by c.titulo;
