-- ═══════════════════════════════════════════════════════════════════
-- LIBERACIÓN PROGRAMADA DE CLASES
--   · Todo de una · A los X días · Una clase cada X días
--   · Aviso por email cuando se libera una clase
-- ═══════════════════════════════════════════════════════════════════

-- ─── 1. CÓMO SE LIBERA CADA CURSO ──────────────────────────────────
-- inmediata : todo disponible al comprar
-- espera    : todo se libera junto, X días después de comprar
-- goteo     : se libera una clase cada X días
alter table public.cursos add column if not exists modo_liberacion text default 'inmediata';
alter table public.cursos add column if not exists dias_liberacion int default 0;
alter table public.cursos add column if not exists avisar_liberacion boolean default true;

update public.cursos set modo_liberacion = 'inmediata' where modo_liberacion is null;
update public.cursos set dias_liberacion = 0 where dias_liberacion is null;
update public.cursos set avisar_liberacion = true where avisar_liberacion is null;

-- Cada clase puede tener su propio día, si querés algo a medida
alter table public.clases add column if not exists dias_desbloqueo int;

-- ─── 2. CUÁNTOS DÍAS NECESITA UNA CLASE ────────────────────────────
create or replace function public.dias_para_clase(p_clase_id uuid)
returns int
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_modo text;
  v_dias int;
  v_propio int;
  v_curso uuid;
  v_pos int;
begin
  select c.modo_liberacion, c.dias_liberacion, cl.dias_desbloqueo, cl.curso_id
    into v_modo, v_dias, v_propio, v_curso
  from public.clases cl
  join public.cursos c on c.id = cl.curso_id
  where cl.id = p_clase_id;

  if v_curso is null then return 0; end if;

  -- Si la clase tiene su propio día, manda ese
  if v_propio is not null then return v_propio; end if;

  if v_modo = 'espera' then
    return coalesce(v_dias, 0);
  end if;

  if v_modo = 'goteo' then
    -- Posición de la clase dentro del curso (la primera siempre es día 0)
    select count(*) into v_pos
    from public.clases c2
    join public.modulos m2 on m2.id = c2.modulo_id
    join public.modulos m1 on m1.id = (select modulo_id from public.clases where id = p_clase_id)
    where c2.curso_id = v_curso
      and coalesce(c2.publicado, true)
      and (
        m2.orden < m1.orden
        or (m2.orden = m1.orden and c2.orden < (select orden from public.clases where id = p_clase_id))
      );

    return coalesce(v_pos, 0) * coalesce(v_dias, 1);
  end if;

  return 0;
end;
$$;

grant execute on function public.dias_para_clase(uuid) to authenticated;

-- ─── 3. REGISTRO DE AVISOS ENVIADOS ────────────────────────────────
create table if not exists public.avisos_clases (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid references auth.users(id) on delete cascade,
  clase_id uuid references public.clases(id) on delete cascade,
  curso_id uuid references public.cursos(id) on delete cascade,
  email text,
  enviado boolean default false,
  detalle_error text,
  creado_en timestamptz default now()
);

create unique index if not exists avisos_clases_unico
  on public.avisos_clases (usuario_id, clase_id);

alter table public.avisos_clases enable row level security;

drop policy if exists "Equipo ve avisos de clases" on public.avisos_clases;
create policy "Equipo ve avisos de clases"
  on public.avisos_clases for select using (public.es_equipo());

-- ─── 4. QUÉ CLASES SE LIBERARON HOY Y NO SE AVISARON ───────────────
create or replace view public.clases_por_avisar as
select
  co.usuario_id,
  p.email,
  p.nombre,
  cl.id   as clase_id,
  cl.titulo as clase_titulo,
  cu.id   as curso_id,
  cu.titulo as curso_titulo,
  cu.slug as curso_slug,
  public.dias_para_clase(cl.id) as dias_necesarios,
  co.pagado_en
from public.compras co
join public.cursos cu on cu.id = co.curso_id
join public.clases cl on cl.curso_id = cu.id
join public.perfiles p on p.id = co.usuario_id
where co.estado = 'pagado'
  and coalesce(cl.publicado, true)
  and coalesce(cu.avisar_liberacion, true)
  and cu.modo_liberacion in ('espera','goteo')
  and public.dias_para_clase(cl.id) > 0
  -- Ya pasaron los días necesarios
  and co.pagado_en + (public.dias_para_clase(cl.id) || ' days')::interval <= now()
  -- Pero no hace más de 2 días (para no mandar avisos viejos de golpe)
  and co.pagado_en + ((public.dias_para_clase(cl.id) + 2) || ' days')::interval >= now()
  -- Y todavía no le avisamos
  and not exists (
    select 1 from public.avisos_clases a
    where a.usuario_id = co.usuario_id and a.clase_id = cl.id
  );

grant select on public.clases_por_avisar to authenticated;

-- ─── VERIFICACIÓN ──────────────────────────────────────────────────
select 'listo' as estado,
  (select count(*) from information_schema.columns
   where table_schema='public' and table_name='cursos'
     and column_name in ('modo_liberacion','dias_liberacion','avisar_liberacion')) as columnas;
