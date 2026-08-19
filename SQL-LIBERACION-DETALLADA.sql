-- ═══════════════════════════════════════════════════════════════════
-- LIBERACIÓN POR MÓDULO Y POR CLASE
--
-- Tres formas de liberar, se elige UNA:
--   inmediata    → apenas se inscribe
--   inscripcion  → X días después de que la persona se inscribió
--   lanzamiento  → X días después de la fecha de lanzamiento del curso
--
-- Manda lo más específico: la clase pisa al módulo, y el módulo al curso.
-- ═══════════════════════════════════════════════════════════════════

-- ─── 1. FECHA DE LANZAMIENTO DEL CURSO ─────────────────────────────
alter table public.cursos add column if not exists fecha_lanzamiento timestamptz;

-- Si no la definiste, tomamos la fecha en que se creó
update public.cursos
set fecha_lanzamiento = coalesce(creado_en, now())
where fecha_lanzamiento is null;

-- ─── 2. CONFIGURACIÓN EN MÓDULOS ───────────────────────────────────
-- heredar = usa lo que diga el curso
alter table public.modulos add column if not exists modo_liberacion text default 'heredar';
alter table public.modulos add column if not exists dias_liberacion int default 0;

update public.modulos set modo_liberacion = 'heredar' where modo_liberacion is null;
update public.modulos set dias_liberacion = 0 where dias_liberacion is null;

-- ─── 3. CONFIGURACIÓN EN CLASES ────────────────────────────────────
alter table public.clases add column if not exists modo_liberacion text default 'heredar';
alter table public.clases add column if not exists dias_liberacion int default 0;

update public.clases set modo_liberacion = 'heredar' where modo_liberacion is null;
update public.clases set dias_liberacion = 0 where dias_liberacion is null;

-- Pasamos el campo viejo al nuevo, si lo habías usado
update public.clases
set modo_liberacion = 'inscripcion', dias_liberacion = dias_desbloqueo
where dias_desbloqueo is not null and modo_liberacion = 'heredar';

-- ─── 4. CUÁNDO SE LIBERA UNA CLASE, PARA UNA PERSONA ───────────────
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
  v_modo text;
  v_dias int;
  v_curso_id uuid;
  v_lanzamiento timestamptz;
  v_inscripcion timestamptz;
  v_modo_curso text;
  v_dias_curso int;
  v_pos int;
begin
  select
    cl.curso_id,
    -- Lo más específico manda: clase → módulo → curso
    case
      when cl.modo_liberacion is not null and cl.modo_liberacion <> 'heredar' then cl.modo_liberacion
      when m.modo_liberacion is not null and m.modo_liberacion <> 'heredar'  then m.modo_liberacion
      else null
    end,
    case
      when cl.modo_liberacion is not null and cl.modo_liberacion <> 'heredar' then cl.dias_liberacion
      when m.modo_liberacion is not null and m.modo_liberacion <> 'heredar'  then m.dias_liberacion
      else null
    end,
    c.fecha_lanzamiento,
    c.modo_liberacion,
    c.dias_liberacion
  into v_curso_id, v_modo, v_dias, v_lanzamiento, v_modo_curso, v_dias_curso
  from public.clases cl
  join public.modulos m on m.id = cl.modulo_id
  join public.cursos c  on c.id = cl.curso_id
  where cl.id = p_clase_id;

  if v_curso_id is null then return now(); end if;

  -- Cuándo se inscribió
  select min(coalesce(pagado_en, creado_en)) into v_inscripcion
  from public.compras
  where usuario_id = p_usuario_id and curso_id = v_curso_id and estado = 'pagado';

  -- ─── Configuración propia de la clase o del módulo ───
  if v_modo is not null then
    if v_modo = 'inmediata' then
      return coalesce(v_inscripcion, now());
    elsif v_modo = 'inscripcion' then
      if v_inscripcion is null then return null; end if;
      return v_inscripcion + (coalesce(v_dias,0) || ' days')::interval;
    elsif v_modo = 'lanzamiento' then
      return coalesce(v_lanzamiento, now()) + (coalesce(v_dias,0) || ' days')::interval;
    end if;
  end if;

  -- ─── Si no, lo que diga el curso ───
  if v_modo_curso = 'espera' then
    if v_inscripcion is null then return null; end if;
    return v_inscripcion + (coalesce(v_dias_curso,0) || ' days')::interval;
  end if;

  if v_modo_curso = 'goteo' then
    if v_inscripcion is null then return null; end if;

    select count(*) into v_pos
    from public.clases c2
    join public.modulos m2 on m2.id = c2.modulo_id
    join public.modulos m1 on m1.id = (select modulo_id from public.clases where id = p_clase_id)
    where c2.curso_id = v_curso_id
      and coalesce(c2.publicado, true)
      and (
        m2.orden < m1.orden
        or (m2.orden = m1.orden and c2.orden < (select orden from public.clases where id = p_clase_id))
      );

    return v_inscripcion + ((coalesce(v_pos,0) * coalesce(v_dias_curso,1)) || ' days')::interval;
  end if;

  -- Por defecto: disponible
  return coalesce(v_inscripcion, now());
end;
$$;

grant execute on function public.fecha_liberacion_clase(uuid, uuid) to authenticated;

-- ─── 5. LAS QUE SE LIBERARON Y NO SE AVISARON ──────────────────────
-- La borramos primero: al cambiar sus columnas, "create or replace" falla
drop view if exists public.clases_por_avisar;

create view public.clases_por_avisar as
select
  co.usuario_id,
  p.email,
  p.nombre,
  cl.id     as clase_id,
  cl.titulo as clase_titulo,
  cu.id     as curso_id,
  cu.titulo as curso_titulo,
  cu.slug   as curso_slug,
  public.fecha_liberacion_clase(cl.id, co.usuario_id) as se_libera
from public.compras co
join public.cursos cu on cu.id = co.curso_id
join public.clases cl on cl.curso_id = cu.id
join public.perfiles p on p.id = co.usuario_id
where co.estado = 'pagado'
  and coalesce(cl.publicado, true)
  and coalesce(cu.avisar_liberacion, true)
  and coalesce(p.recibir_novedades, true)
  and public.fecha_liberacion_clase(cl.id, co.usuario_id) is not null
  -- Ya se liberó
  and public.fecha_liberacion_clase(cl.id, co.usuario_id) <= now()
  -- Pero hace poco (no mandamos avisos viejos de golpe)
  and public.fecha_liberacion_clase(cl.id, co.usuario_id) >= now() - interval '2 days'
  -- No se liberó junto con la inscripción (esas no se avisan)
  and public.fecha_liberacion_clase(cl.id, co.usuario_id) > coalesce(co.pagado_en, co.creado_en) + interval '1 hour'
  and not exists (
    select 1 from public.avisos_clases a
    where a.usuario_id = co.usuario_id and a.clase_id = cl.id
  );

grant select on public.clases_por_avisar to authenticated;

-- ─── VERIFICACIÓN ──────────────────────────────────────────────────
select 'listo' as estado,
  (select count(*) from information_schema.columns
   where table_schema='public' and table_name='clases'
     and column_name in ('modo_liberacion','dias_liberacion')) as columnas_clases,
  (select count(*) from information_schema.columns
   where table_schema='public' and table_name='modulos'
     and column_name in ('modo_liberacion','dias_liberacion')) as columnas_modulos;
