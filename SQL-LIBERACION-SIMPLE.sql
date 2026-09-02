-- ═══════════════════════════════════════════════════════════════════
-- LIBERACIÓN SIMPLIFICADA
--
-- Cada módulo decide una de dos cosas:
--   'modulo' → se libera entero, en la fecha que diga el módulo
--   'clase'  → cada clase tiene su propia fecha
--
-- Nunca se suman. La decisión del módulo manda sobre todo.
-- ═══════════════════════════════════════════════════════════════════

-- ─── 1. EL MÓDULO DECIDE ───────────────────────────────────────────
-- Cómo se libera: entero o clase por clase
alter table public.modulos add column if not exists tipo_liberacion text default 'modulo';

-- Cuándo (solo si tipo_liberacion = 'modulo')
--   inmediata   → al inscribirse
--   inscripcion → X días después de inscribirse
--   lanzamiento → X días después del lanzamiento del curso
alter table public.modulos add column if not exists cuando_libera text default 'inmediata';
alter table public.modulos add column if not exists dias_liberacion int default 0;

-- Módulo de regalo: se ve sin comprar el curso
alter table public.modulos add column if not exists gratis boolean default false;

update public.modulos set tipo_liberacion = 'modulo'    where tipo_liberacion is null;
update public.modulos set cuando_libera = 'inmediata'   where cuando_libera is null;
update public.modulos set dias_liberacion = 0           where dias_liberacion is null;
update public.modulos set gratis = false                where gratis is null;

-- Pasamos la configuración vieja a la nueva
update public.modulos
set cuando_libera = case
      when modo_liberacion = 'inscripcion' then 'inscripcion'
      when modo_liberacion = 'lanzamiento' then 'lanzamiento'
      else 'inmediata'
    end
where modo_liberacion is not null and modo_liberacion <> 'heredar';

-- ─── 2. LA CLASE, SOLO SI EL MÓDULO LO DELEGA ──────────────────────
alter table public.clases add column if not exists cuando_libera text default 'inmediata';
update public.clases set cuando_libera = 'inmediata' where cuando_libera is null;

update public.clases
set cuando_libera = case
      when modo_liberacion = 'inscripcion' then 'inscripcion'
      when modo_liberacion = 'lanzamiento' then 'lanzamiento'
      else 'inmediata'
    end
where modo_liberacion is not null and modo_liberacion <> 'heredar';

-- ─── 3. PRECIO ESPECIAL PARA LA COMUNIDAD PREMIUM ──────────────────
alter table public.cursos add column if not exists precio_premium_gs int;

-- ─── 4. CUÁNDO SE LIBERA UNA CLASE ─────────────────────────────────
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
  v_curso_id uuid;
  v_lanzamiento timestamptz;
  v_inscripcion timestamptz;
  v_gratis_mod boolean;
  v_gratis_cla boolean;
begin
  select
    cl.curso_id,
    m.tipo_liberacion,
    -- Si el módulo se libera entero, manda el módulo. Si no, la clase.
    case when m.tipo_liberacion = 'modulo' then m.cuando_libera   else cl.cuando_libera   end,
    case when m.tipo_liberacion = 'modulo' then m.dias_liberacion else cl.dias_liberacion end,
    c.fecha_lanzamiento,
    coalesce(m.gratis, false),
    coalesce(cl.gratis, false)
  into v_curso_id, v_tipo, v_cuando, v_dias, v_lanzamiento, v_gratis_mod, v_gratis_cla
  from public.clases cl
  join public.modulos m on m.id = cl.modulo_id
  join public.cursos c  on c.id = cl.curso_id
  where cl.id = p_clase_id;

  if v_curso_id is null then return now(); end if;

  -- De regalo: disponible siempre, sin importar nada más
  if v_gratis_mod or v_gratis_cla then return now() - interval '1 day'; end if;

  -- Cuándo se inscribió
  select min(coalesce(pagado_en, creado_en)) into v_inscripcion
  from public.compras
  where usuario_id = p_usuario_id and curso_id = v_curso_id and estado = 'pagado';

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

-- ─── VERIFICACIÓN ──────────────────────────────────────────────────
select
  c.titulo as curso,
  m.orden as mod_orden,
  m.titulo as modulo,
  case when m.tipo_liberacion = 'clase' then 'clase por clase' else 'módulo entero' end as se_libera,
  case
    when m.tipo_liberacion = 'clase' then '(cada clase)'
    when m.cuando_libera = 'inmediata' then 'al inscribirse'
    when m.cuando_libera = 'inscripcion' then m.dias_liberacion || 'd tras inscribirse'
    when m.cuando_libera = 'lanzamiento' then m.dias_liberacion || 'd tras lanzamiento'
  end as cuando,
  case when m.gratis then 'sí' else 'no' end as de_regalo
from public.modulos m
join public.cursos c on c.id = m.curso_id
order by c.titulo, m.orden;
