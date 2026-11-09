-- ═══════════════════════════════════════════════════════════════════
-- INSIGNIAS QUE SE REPARTEN SOLAS, DE VERDAD
--
-- Qué faltaba:
--   1. Nadie disparaba la "Bienvenida" al registrarse
--   2. "100 likes en un post" contaba todos los likes juntos
--   3. La persona nunca se enteraba de que la ganó
-- ═══════════════════════════════════════════════════════════════════

-- ─── 1. UN CRITERIO NUEVO: LIKES EN UN MISMO POST ──────────────────
-- "Top voz: 100 likes en un post" necesita contar por post,
-- no la suma de todos.

create or replace function public.otorgar_insignias(p_usuario_id uuid default null)
returns table (r_usuario uuid, r_insignia uuid, r_nombre text)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  with gente as (
    select p.id as gid from public.perfiles p
    where p_usuario_id is null or p.id = p_usuario_id
  ),
  metricas as (
    select
      g.gid as uid,
      1 as m_registro,
      (select count(*) from public.posts       x where x.usuario_id = g.gid) as m_posts,
      (select count(*) from public.comentarios x where x.usuario_id = g.gid) as m_comentarios,
      (select count(*) from public.likes       x where x.usuario_id = g.gid) as m_likes,
      (select count(*) from public.compras     x where x.usuario_id = g.gid and x.estado = 'pagado') as m_cursos,
      -- Todos los likes que recibió, sumando sus posts
      (select count(*) from public.likes l
         join public.posts po on po.id = l.post_id
         where po.usuario_id = g.gid) as m_recibidos,
      -- El post suyo que más likes tiene
      coalesce((
        select max(c) from (
          select count(*) as c
          from public.likes l
          join public.posts po on po.id = l.post_id
          where po.usuario_id = g.gid
          group by po.id
        ) t
      ), 0) as m_mejor_post,
      -- Días seguidos entrando: lo aproximamos por días con actividad
      (select count(distinct date(x.creado_en))
         from public.posts x where x.usuario_id = g.gid) as m_dias_activa
    from gente g
  ),
  ganadas as (
    select m.uid as g_uid, i.id as g_ins, i.nombre as g_nombre
    from metricas m
    cross join public.insignias i
    where i.tipo = 'automatica'
      and coalesce(i.activa, true)
      and i.cantidad > 0
      and (
        (i.criterio = 'registro'        and m.m_registro    >= i.cantidad) or
        (i.criterio = 'posts'           and m.m_posts       >= i.cantidad) or
        (i.criterio = 'comentarios'     and m.m_comentarios >= i.cantidad) or
        (i.criterio = 'likes'           and m.m_likes       >= i.cantidad) or
        (i.criterio = 'likes_recibidos' and m.m_recibidos   >= i.cantidad) or
        (i.criterio = 'likes_un_post'   and m.m_mejor_post  >= i.cantidad) or
        (i.criterio = 'dias_activa'     and m.m_dias_activa >= i.cantidad) or
        (i.criterio = 'cursos'          and m.m_cursos      >= i.cantidad)
      )
      and not exists (
        select 1 from public.usuario_insignias ui
        where ui.usuario_id = m.uid and ui.insignia_id = i.id
      )
  ),
  insertadas as (
    insert into public.usuario_insignias (usuario_id, insignia_id)
    select gn.g_uid, gn.g_ins from ganadas gn
    on conflict (usuario_id, insignia_id) do nothing
    returning usuario_insignias.usuario_id as i_usuario,
              usuario_insignias.insignia_id as i_insignia
  )
  select ins.i_usuario, ins.i_insignia, gn2.g_nombre
  from insertadas ins
  join ganadas gn2 on gn2.g_uid = ins.i_usuario and gn2.g_ins = ins.i_insignia;
end;
$$;

grant execute on function public.otorgar_insignias(uuid) to authenticated;

-- ─── 2. AVISARLE A LA PERSONA ──────────────────────────────────────
-- Para que lo vea al entrar
alter table public.usuario_insignias add column if not exists vista boolean default false;

-- Las que ya tenía, las damos por vistas
update public.usuario_insignias set vista = true where vista is null;

-- Las insignias nuevas que todavía no vio
create or replace function public.mis_insignias_nuevas()
returns table (
  n_id uuid,
  n_nombre text,
  n_descripcion text,
  n_icono text,
  n_imagen text,
  n_color text,
  n_rareza text
)
language sql
stable
security definer
set search_path = public
as $$
  select i.id, i.nombre, i.descripcion, i.icono, i.imagen_url, i.color, i.rareza
  from public.usuario_insignias ui
  join public.insignias i on i.id = ui.insignia_id
  where ui.usuario_id = auth.uid()
    and coalesce(ui.vista, false) = false
  order by ui.otorgada_en;
$$;

grant execute on function public.mis_insignias_nuevas() to authenticated;

-- Marcarlas como vistas después de mostrárselas
create or replace function public.marcar_insignias_vistas()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare v_n int;
begin
  update public.usuario_insignias
  set vista = true
  where usuario_id = auth.uid() and coalesce(vista, false) = false;

  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

grant execute on function public.marcar_insignias_vistas() to authenticated;

-- ─── 3. CUÁNDO SE REVISA ───────────────────────────────────────────
create or replace function public.revisar_insignias_auto()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare v_usuario uuid;
begin
  v_usuario := coalesce(new.usuario_id, old.usuario_id);

  -- En perfiles, el id ES la persona
  if tg_table_name = 'perfiles' then
    v_usuario := new.id;
  end if;

  if v_usuario is null then return coalesce(new, old); end if;

  perform public.otorgar_insignias(v_usuario);

  -- Si fue un like, también revisamos a quien lo recibió
  if tg_table_name = 'likes' and new.post_id is not null then
    perform public.otorgar_insignias((
      select usuario_id from public.posts where id = new.post_id
    ));
  end if;

  return coalesce(new, old);
end;
$$;

-- Al registrarse: la insignia de Bienvenida
drop trigger if exists trg_insignias_registro on public.perfiles;
create trigger trg_insignias_registro
  after insert on public.perfiles
  for each row execute function public.revisar_insignias_auto();

-- Al publicar
drop trigger if exists trg_insignias_post on public.posts;
create trigger trg_insignias_post
  after insert on public.posts
  for each row execute function public.revisar_insignias_auto();

-- Al comentar
drop trigger if exists trg_insignias_comentario on public.comentarios;
create trigger trg_insignias_comentario
  after insert on public.comentarios
  for each row execute function public.revisar_insignias_auto();

-- Al dar o recibir un like
drop trigger if exists trg_insignias_like on public.likes;
create trigger trg_insignias_like
  after insert on public.likes
  for each row execute function public.revisar_insignias_auto();

-- Al comprar o anotarse a un curso
drop trigger if exists trg_insignias_compra on public.compras;
create trigger trg_insignias_compra
  after insert or update of estado on public.compras
  for each row execute function public.revisar_insignias_auto();

-- Al terminar una clase
drop trigger if exists trg_insignias_progreso on public.progreso;
create trigger trg_insignias_progreso
  after insert on public.progreso
  for each row execute function public.revisar_insignias_auto();

-- ─── 4. AJUSTAMOS "TOP VOZ" AL CRITERIO CORRECTO ───────────────────
update public.insignias
set criterio = 'likes_un_post'
where clave = 'top_voz' and criterio = 'likes_recibidos';

-- ─── 5. PONERNOS AL DÍA CON LO QUE YA PASÓ ─────────────────────────
select count(*) as repartidas_ahora from public.otorgar_insignias(null);

-- ─── VERIFICACIÓN ──────────────────────────────────────────────────
select
  i.nombre,
  i.criterio,
  i.cantidad,
  count(ui.id) as cuantas_la_tienen
from public.insignias i
left join public.usuario_insignias ui on ui.insignia_id = i.id
where i.tipo = 'automatica' and i.activa
group by i.id, i.nombre, i.criterio, i.cantidad, i.orden
order by i.orden;
