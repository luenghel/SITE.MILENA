-- ═══════════════════════════════════════════════════════════════════
-- CATEGORÍAS DE LA COMUNIDAD, EDITABLES
--
-- Antes estaban escritas en el código. Ahora las manejás desde el panel.
-- ═══════════════════════════════════════════════════════════════════

create table if not exists public.categorias_comunidad (
  id uuid primary key default gen_random_uuid(),
  clave text unique not null,
  nombre text not null,
  icono text,
  descripcion text,
  solo_equipo boolean default false,   -- solo Milena puede publicar acá
  orden int default 0,
  activa boolean default true,
  creado_en timestamptz default now()
);

alter table public.categorias_comunidad enable row level security;

drop policy if exists "Categorías visibles" on public.categorias_comunidad;
create policy "Categorías visibles"
  on public.categorias_comunidad for select using (true);

drop policy if exists "Equipo crea categorías" on public.categorias_comunidad;
create policy "Equipo crea categorías"
  on public.categorias_comunidad for insert with check (public.es_equipo());

drop policy if exists "Equipo edita categorías" on public.categorias_comunidad;
create policy "Equipo edita categorías"
  on public.categorias_comunidad for update using (public.es_equipo());

drop policy if exists "Equipo borra categorías" on public.categorias_comunidad;
create policy "Equipo borra categorías"
  on public.categorias_comunidad for delete using (public.es_equipo());

-- ─── Las que ya estaban en el código ───────────────────────────────
do $$
declare r record;
begin
  for r in select * from (values
    ('general',   'General',   '',   'Todo lo demás',                     false, 1),
    ('anuncios',  'Anuncios',  '📌', 'Novedades del equipo',              true,  2),
    ('consejos',  'Consejos',  '💡', 'Tips y aprendizajes',               false, 3),
    ('avances',   'Avances',   '🚀', 'Lo que vas logrando',               false, 4),
    ('preguntas', 'Preguntas', '❓', 'Dudas para la comunidad',           false, 5),
    ('logros',    'Logros',    '🏆', 'Celebrá tus ventas y resultados',   false, 6)
  ) as t(clave, nombre, icono, descripcion, solo_equipo, orden)
  loop
    if not exists (select 1 from public.categorias_comunidad where clave = r.clave) then
      insert into public.categorias_comunidad (clave, nombre, icono, descripcion, solo_equipo, orden)
      values (r.clave, r.nombre, r.icono, r.descripcion, r.solo_equipo, r.orden);
    end if;
  end loop;
end $$;

-- ═══════════════════════════════════════════════════════════════════
-- LAS INSIGNIAS SE REPARTEN SOLAS
--
-- Antes había que tocar "Repartir a todas" en el panel.
-- Ahora se revisa cuando la persona publica, comenta o da un like.
-- ═══════════════════════════════════════════════════════════════════

create or replace function public.revisar_insignias_auto()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare v_usuario uuid;
begin
  -- De quién revisamos las insignias
  v_usuario := coalesce(new.usuario_id, old.usuario_id);
  if v_usuario is null then return coalesce(new, old); end if;

  -- Las suyas
  perform public.otorgar_insignias(v_usuario);

  -- Si fue un like, también revisamos a quien lo recibió:
  -- puede haber llegado a "100 likes en un post"
  if tg_table_name = 'likes' and new.post_id is not null then
    perform public.otorgar_insignias((
      select usuario_id from public.posts where id = new.post_id
    ));
  end if;

  return coalesce(new, old);
end;
$$;

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

-- Al dar un like
drop trigger if exists trg_insignias_like on public.likes;
create trigger trg_insignias_like
  after insert on public.likes
  for each row execute function public.revisar_insignias_auto();

-- Al comprar o anotarse a un curso
drop trigger if exists trg_insignias_compra on public.compras;
create trigger trg_insignias_compra
  after insert or update of estado on public.compras
  for each row execute function public.revisar_insignias_auto();

-- ═══════════════════════════════════════════════════════════════════
-- CUÁNTO SE USA CADA ETIQUETA (para el panel, con datos reales)
-- ═══════════════════════════════════════════════════════════════════

drop view if exists public.uso_hashtags;
create view public.uso_hashtags as
select
  h.id,
  h.tag,
  h.activo,
  count(p.id) filter (where p.creado_en > now() - interval '7 days')  as posts_semana,
  count(p.id) filter (where p.creado_en > now() - interval '30 days') as posts_mes,
  count(p.id) as posts_total,
  max(p.creado_en) as ultimo_uso
from public.hashtags h
left join public.posts p on p.hashtags @> array[h.tag]
group by h.id, h.tag, h.activo;

grant select on public.uso_hashtags to authenticated;

-- ─── VERIFICACIÓN ──────────────────────────────────────────────────
select 'listo' as estado,
  (select count(*) from public.categorias_comunidad) as categorias,
  (select count(*) from public.insignias where tipo = 'automatica') as insignias_automaticas,
  (select count(*) from public.hashtags) as etiquetas;

-- Las insignias que ahora se reparten solas
select nombre, criterio, cantidad
from public.insignias
where tipo = 'automatica' and activa
order by orden;
