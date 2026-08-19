-- ═══════════════════════════════════════════════════════════════════
-- OTORGAR INSIGNIAS AUTOMÁTICAS
-- Revisa lo que hizo cada persona y le da las que se ganó.
-- ═══════════════════════════════════════════════════════════════════

create or replace function public.otorgar_insignias(p_usuario_id uuid default null)
returns table (usuario_id uuid, insignia_id uuid, nombre text)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  with gente as (
    select p.id
    from public.perfiles p
    where p_usuario_id is null or p.id = p_usuario_id
  ),
  metricas as (
    select
      g.id as uid,
      (select count(*) from public.posts       x where x.usuario_id = g.id) as posts,
      (select count(*) from public.comentarios x where x.usuario_id = g.id) as comentarios,
      (select count(*) from public.likes       x where x.usuario_id = g.id) as likes,
      (select count(*) from public.compras     x where x.usuario_id = g.id and x.estado = 'pagado') as cursos
    from gente g
  ),
  ganadas as (
    select m.uid, i.id as ins_id, i.nombre as ins_nombre
    from metricas m
    cross join public.insignias i
    where i.tipo = 'automatica'
      and coalesce(i.activa, true)
      and i.cantidad > 0
      and (
        (i.criterio = 'posts'       and m.posts       >= i.cantidad) or
        (i.criterio = 'comentarios' and m.comentarios >= i.cantidad) or
        (i.criterio = 'likes'       and m.likes       >= i.cantidad) or
        (i.criterio = 'cursos'      and m.cursos      >= i.cantidad)
      )
      and not exists (
        select 1 from public.usuario_insignias ui
        where ui.usuario_id = m.uid and ui.insignia_id = i.id
      )
  ),
  insertadas as (
    insert into public.usuario_insignias (usuario_id, insignia_id)
    select g.uid, g.ins_id from ganadas g
    on conflict (usuario_id, insignia_id) do nothing
    returning usuario_insignias.usuario_id, usuario_insignias.insignia_id
  )
  select i.usuario_id, i.insignia_id, g.ins_nombre
  from insertadas i
  join ganadas g on g.uid = i.usuario_id and g.ins_id = i.insignia_id;
end;
$$;

grant execute on function public.otorgar_insignias(uuid) to authenticated;

-- ─── Cada quien puede revisar las suyas ────────────────────────────
create or replace function public.revisar_mis_insignias()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nuevas int;
begin
  select count(*) into v_nuevas
  from public.otorgar_insignias(auth.uid());
  return coalesce(v_nuevas, 0);
end;
$$;

grant execute on function public.revisar_mis_insignias() to authenticated;

-- ─── El equipo puede dar y quitar a mano ───────────────────────────
drop policy if exists "Equipo otorga insignias" on public.usuario_insignias;
create policy "Equipo otorga insignias"
  on public.usuario_insignias for insert
  with check (public.es_equipo());

drop policy if exists "Equipo quita insignias" on public.usuario_insignias;
create policy "Equipo quita insignias"
  on public.usuario_insignias for delete
  using (public.es_equipo());

-- ─── Repartimos las que ya se ganaron ──────────────────────────────
select count(*) as insignias_otorgadas_ahora from public.otorgar_insignias(null);

-- ─── VERIFICACIÓN ──────────────────────────────────────────────────
select
  i.nombre,
  i.icono,
  case when i.tipo = 'automatica' then 'automática' else 'manual' end as tipo,
  (select count(*) from public.usuario_insignias ui where ui.insignia_id = i.id) as la_tienen
from public.insignias i
order by i.orden;
