-- ═══════════════════════════════════════════════════════════════════
-- INSIGNIAS: FOTO, RAREZA Y CLAVE
-- Une lo que muestra el perfil con lo que se edita en el admin.
-- ═══════════════════════════════════════════════════════════════════

-- ─── 0. LA TABLA, SI NO EXISTIERA ──────────────────────────────────
create table if not exists public.insignias (
  id uuid primary key default gen_random_uuid(),
  nombre text not null
);

-- ─── 1. TODAS LAS COLUMNAS QUE NECESITAMOS ─────────────────────────
-- Se agregan una por una: si la tabla ya existía con otra forma,
-- así queda completa sin perder nada.
alter table public.insignias add column if not exists clave       text;
alter table public.insignias add column if not exists nombre      text;
alter table public.insignias add column if not exists descripcion text;
alter table public.insignias add column if not exists icono       text default '⭐';
alter table public.insignias add column if not exists imagen_url  text;
alter table public.insignias add column if not exists color       text default '#FAC775';
alter table public.insignias add column if not exists rareza      text default 'comun';
alter table public.insignias add column if not exists tipo        text default 'manual';
alter table public.insignias add column if not exists criterio    text;
alter table public.insignias add column if not exists cantidad    int default 0;
alter table public.insignias add column if not exists orden       int default 0;
alter table public.insignias add column if not exists activa      boolean default true;
alter table public.insignias add column if not exists creado_en   timestamptz default now();

update public.insignias set rareza = 'comun'    where rareza is null;
update public.insignias set color = '#FAC775'   where color is null;
update public.insignias set icono = '⭐'         where icono is null;
update public.insignias set tipo = 'manual'     where tipo is null;
update public.insignias set activa = true       where activa is null;
update public.insignias set cantidad = 0        where cantidad is null;
update public.insignias set orden = 0           where orden is null;

-- ─── La tabla de quién tiene cuál ──────────────────────────────────
create table if not exists public.usuario_insignias (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid references auth.users(id) on delete cascade,
  insignia_id uuid references public.insignias(id) on delete cascade,
  otorgada_en timestamptz default now()
);

alter table public.usuario_insignias add column if not exists otorgada_en timestamptz default now();

create unique index if not exists usuario_insignia_unica
  on public.usuario_insignias (usuario_id, insignia_id);

-- ─── Permisos ──────────────────────────────────────────────────────
alter table public.insignias enable row level security;
alter table public.usuario_insignias enable row level security;

drop policy if exists "Insignias visibles" on public.insignias;
create policy "Insignias visibles" on public.insignias for select using (true);

drop policy if exists "Equipo crea insignias" on public.insignias;
create policy "Equipo crea insignias" on public.insignias for insert with check (public.es_equipo());

drop policy if exists "Equipo edita insignias" on public.insignias;
create policy "Equipo edita insignias" on public.insignias for update using (public.es_equipo());

drop policy if exists "Equipo borra insignias" on public.insignias;
create policy "Equipo borra insignias" on public.insignias for delete using (public.es_equipo());

drop policy if exists "Insignias de todos visibles" on public.usuario_insignias;
create policy "Insignias de todos visibles" on public.usuario_insignias for select using (auth.uid() is not null);

drop policy if exists "Equipo otorga insignias" on public.usuario_insignias;
create policy "Equipo otorga insignias" on public.usuario_insignias for insert with check (public.es_equipo());

drop policy if exists "Equipo quita insignias" on public.usuario_insignias;
create policy "Equipo quita insignias" on public.usuario_insignias for delete using (public.es_equipo());

-- La que cada una elige mostrar
alter table public.perfiles add column if not exists insignia_destacada uuid;

-- Una clave por insignia, para reconocerlas
update public.insignias
set clave = lower(regexp_replace(translate(nombre, 'áéíóúÁÉÍÓÚñÑ', 'aeiouAEIOUnN'), '[^a-zA-Z0-9]+', '_', 'g'))
where clave is null or clave = '';

-- Si quedaron claves repetidas, les agregamos un número
with repetidas as (
  select id, clave,
         row_number() over (partition by clave order by creado_en, id) as n
  from public.insignias
  where clave is not null
)
update public.insignias i
set clave = r.clave || '_' || r.n
from repetidas r
where i.id = r.id and r.n > 1;

-- Ahora sí, el índice (completo, no parcial)
drop index if exists public.insignias_clave_unica;
create unique index insignias_clave_unica on public.insignias (clave);

-- ─── 2. LAS 9 QUE YA SE VEN EN EL PERFIL ───────────────────────────
-- Vamos una por una: si existe la actualizamos, si no la creamos.
do $$
declare
  r record;
begin
  for r in
    select * from (values
      ('bienvenida',    'Bienvenida',    'Te uniste a CMM',                '👋', '#E8B8C4', 'comun',      'automatica', 'registro',        1,  1),
      ('primer_post',   'Primer post',   'Posteaste en la comunidad',      '✏️', '#E8B8C4', 'comun',      'automatica', 'posts',           1,  2),
      ('primer_curso',  'Primer curso',  'Comprate tu primer curso',       '🎓', '#E8B8C4', 'comun',      'automatica', 'cursos',          1,  3),
      ('conversadora',  'Conversadora',  '10 comentarios en la comunidad', '💬', '#C0C0C0', 'rara',       'automatica', 'comentarios',     10, 4),
      ('constancia',    'Constancia',    '10 publicaciones tuyas',         '🔥', '#C0C0C0', 'rara',       'automatica', 'posts',           10, 5),
      ('top_voz',       'Top voz',       '25 me gusta recibidos',          '⭐', '#FAC775', 'epica',      'automatica', 'likes_recibidos', 25, 6),
      ('creadora',      'Creadora',      '25 publicaciones tuyas',         '🚀', '#FAC775', 'epica',      'automatica', 'posts',           25, 7),
      ('coleccionista', 'Coleccionista', '3 cursos comprados',             '📚', '#FAC775', 'epica',      'automatica', 'cursos',          3,  8),
      ('mente_cmm',     'Mente CMM',     'Tenés el curso principal',       '💎', '#7ABAF5', 'legendaria', 'manual',     null,              0,  9)
    ) as t(clave, nombre, descripcion, icono, color, rareza, tipo, criterio, cantidad, orden)
  loop
    -- Si ya existe una con ese nombre pero sin clave, se la ponemos
    update public.insignias
    set clave = r.clave
    where clave is distinct from r.clave
      and lower(nombre) = lower(r.nombre)
      and not exists (select 1 from public.insignias i2 where i2.clave = r.clave);

    if exists (select 1 from public.insignias where clave = r.clave) then
      update public.insignias set
        nombre      = r.nombre,
        descripcion = coalesce(descripcion, r.descripcion),
        icono       = coalesce(nullif(icono, ''), r.icono),
        color       = coalesce(nullif(color, ''), r.color),
        rareza      = coalesce(nullif(rareza, ''), r.rareza),
        tipo        = r.tipo,
        criterio    = r.criterio,
        cantidad    = r.cantidad,
        orden       = r.orden,
        activa      = true
      where clave = r.clave;
    else
      insert into public.insignias
        (clave, nombre, descripcion, icono, color, rareza, tipo, criterio, cantidad, orden, activa)
      values
        (r.clave, r.nombre, r.descripcion, r.icono, r.color, r.rareza, r.tipo, r.criterio, r.cantidad, r.orden, true);
    end if;
  end loop;
end $$;

-- ─── 3. OTORGAR, AHORA CON LOS CRITERIOS NUEVOS ────────────────────
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
      (select count(*) from public.likes l
         join public.posts po on po.id = l.post_id
         where po.usuario_id = g.gid) as m_recibidos
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

-- ─── 4. REPARTIMOS LAS GANADAS ─────────────────────────────────────
select count(*) as otorgadas_ahora from public.otorgar_insignias(null);


-- ═══════════════════════════════════════════════════════════════════
-- CURSOS QUE VIENEN PRONTO + MENSAJE EN LOS ANUNCIOS
-- ═══════════════════════════════════════════════════════════════════

alter table public.anuncios_enviados add column if not exists mensaje text;

alter table public.cursos add column if not exists proximamente boolean default false;
alter table public.cursos add column if not exists fecha_disponible timestamptz;
alter table public.cursos add column if not exists texto_proximamente text;
alter table public.cursos add column if not exists que_incluye text;

update public.cursos set proximamente = false where proximamente is null;

-- Quiénes quieren que les avisemos cuando salga
create table if not exists public.interesados_curso (
  id uuid primary key default gen_random_uuid(),
  curso_id uuid references public.cursos(id) on delete cascade,
  usuario_id uuid references auth.users(id) on delete cascade,
  email text,
  avisado boolean default false,
  creado_en timestamptz default now()
);

create unique index if not exists interesados_unicos
  on public.interesados_curso (curso_id, usuario_id);

alter table public.interesados_curso enable row level security;

drop policy if exists "Anotarse como interesada" on public.interesados_curso;
create policy "Anotarse como interesada"
  on public.interesados_curso for insert
  with check (auth.uid() = usuario_id);

drop policy if exists "Ver mi interés" on public.interesados_curso;
create policy "Ver mi interés"
  on public.interesados_curso for select
  using (auth.uid() = usuario_id or public.es_equipo());

drop policy if exists "Sacarme de la lista" on public.interesados_curso;
create policy "Sacarme de la lista"
  on public.interesados_curso for delete
  using (auth.uid() = usuario_id);

-- Quién quiere recibir novedades
alter table public.perfiles add column if not exists recibir_novedades boolean default true;
update public.perfiles set recibir_novedades = true where recibir_novedades is null;

-- ─── VERIFICACIÓN ──────────────────────────────────────────────────
select
  i.orden, i.icono, i.nombre, i.rareza,
  coalesce(i.criterio, 'manual') as se_gana_por,
  i.cantidad,
  (select count(*) from public.usuario_insignias ui where ui.insignia_id = i.id) as la_tienen
from public.insignias i
order by i.orden;
