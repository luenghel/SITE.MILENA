-- ═══════════════════════════════════════════════════════════════════
-- PROGRAMAR POR FECHA EXACTA
--
-- Una cuarta opción: el módulo o la clase se abre un día y hora puntual,
-- igual para todas. Y si estaba en borrador, se publica sola.
-- ═══════════════════════════════════════════════════════════════════

alter table public.modulos add column if not exists fecha_apertura timestamptz;
alter table public.clases  add column if not exists fecha_apertura timestamptz;

-- Publicar solo al llegar la fecha
alter table public.modulos add column if not exists publicar_en_fecha boolean default false;
alter table public.clases  add column if not exists publicar_en_fecha boolean default false;

update public.modulos set publicar_en_fecha = false where publicar_en_fecha is null;
update public.clases  set publicar_en_fecha = false where publicar_en_fecha is null;

-- ─── Publica lo que ya le tocaba ───────────────────────────────────
create or replace function public.publicar_programados()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare v_total int := 0; v_n int;
begin
  update public.modulos
  set publicado = true
  where publicar_en_fecha
    and fecha_apertura is not null
    and fecha_apertura <= now()
    and coalesce(publicado, false) = false;
  get diagnostics v_n = row_count;
  v_total := v_total + v_n;

  update public.clases
  set publicado = true
  where publicar_en_fecha
    and fecha_apertura is not null
    and fecha_apertura <= now()
    and coalesce(publicado, false) = false;
  get diagnostics v_n = row_count;
  v_total := v_total + v_n;

  return v_total;
end;
$$;

grant execute on function public.publicar_programados() to authenticated;

-- ─── Cuándo se libera una clase, ahora también por fecha ───────────
create or replace function public.fecha_liberacion_clase(
  p_clase_id uuid,
  p_usuario_id uuid
)
returns timestamptz
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_tipo text;
  v_cuando text;
  v_dias int;
  v_fecha timestamptz;
  v_curso_id uuid;
  v_lanzamiento timestamptz;
  v_inscripcion timestamptz;
  v_gratis_mod boolean;
  v_gratis_cla boolean;
begin
  select
    cl.curso_id,
    m.tipo_liberacion,
    case when m.tipo_liberacion = 'modulo' then m.cuando_libera   else cl.cuando_libera   end,
    case when m.tipo_liberacion = 'modulo' then m.dias_liberacion else cl.dias_liberacion end,
    case when m.tipo_liberacion = 'modulo' then m.fecha_apertura  else cl.fecha_apertura  end,
    c.fecha_lanzamiento,
    coalesce(m.gratis, false),
    coalesce(cl.gratis, false)
  into v_curso_id, v_tipo, v_cuando, v_dias, v_fecha, v_lanzamiento, v_gratis_mod, v_gratis_cla
  from public.clases cl
  join public.modulos m on m.id = cl.modulo_id
  join public.cursos c  on c.id = cl.curso_id
  where cl.id = p_clase_id;

  if v_curso_id is null then return now(); end if;

  if v_gratis_mod or v_gratis_cla then return now() - interval '1 day'; end if;

  select min(coalesce(pagado_en, creado_en)) into v_inscripcion
  from public.compras
  where usuario_id = p_usuario_id and curso_id = v_curso_id and estado = 'pagado';

  -- Fecha exacta: igual para todas
  if v_cuando = 'fecha' then
    return coalesce(v_fecha, now());
  end if;

  if v_cuando = 'inmediata' then
    return coalesce(v_inscripcion, now());
  end if;

  if v_cuando = 'inscripcion' then
    if v_inscripcion is null then return null; end if;
    return v_inscripcion + (coalesce(v_dias, 0) || ' days')::interval;
  end if;

  if v_cuando = 'lanzamiento' then
    return coalesce(v_lanzamiento, now()) + (coalesce(v_dias, 0) || ' days')::interval;
  end if;

  return coalesce(v_inscripcion, now());
end;
$$;

grant execute on function public.fecha_liberacion_clase(uuid, uuid) to authenticated;

-- ─── Lo que está esperando su fecha ────────────────────────────────
drop view if exists public.programados;
create view public.programados as
select
  'modulo' as que,
  m.id,
  m.titulo,
  c.titulo as curso,
  c.slug as curso_slug,
  m.fecha_apertura,
  m.publicado,
  m.publicar_en_fecha
from public.modulos m
join public.cursos c on c.id = m.curso_id
where m.fecha_apertura is not null and m.fecha_apertura > now()

union all

select
  'clase' as que,
  cl.id,
  cl.titulo,
  c.titulo as curso,
  c.slug as curso_slug,
  cl.fecha_apertura,
  cl.publicado,
  cl.publicar_en_fecha
from public.clases cl
join public.cursos c on c.id = cl.curso_id
where cl.fecha_apertura is not null and cl.fecha_apertura > now();

grant select on public.programados to authenticated;

-- ─── VERIFICACIÓN ──────────────────────────────────────────────────
select count(*) as publicados_ahora from public.publicar_programados();

select que, titulo, curso,
  to_char(fecha_apertura, 'DD/MM/YYYY HH24:MI') as se_abre
from public.programados
order by fecha_apertura;
