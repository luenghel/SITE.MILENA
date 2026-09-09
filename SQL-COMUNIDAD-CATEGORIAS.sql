-- ═══════════════════════════════════════════════════════════════════
-- CATEGORÍAS DE LA COMUNIDAD, EDITABLES DESDE EL PANEL
-- + ETIQUETAS BLINDADAS: solo las crea el equipo
--
-- Qué cambia:
--   1. Las categorías (General, Anuncios, Consejos…) dejan de estar
--      escritas a mano en el código. Las creás y ordenás vos.
--   2. Las etiquetas (#hashtags) solo las puede crear el equipo.
--      Antes, con las reglas de la base, cualquiera podía inventarse
--      una desde afuera del sitio.
--   3. Un post no puede llevar una etiqueta que no exista.
--
-- Correlo entero en Supabase → SQL Editor. Es seguro repetirlo.
-- ═══════════════════════════════════════════════════════════════════


-- ─── 1. LAS CATEGORÍAS ─────────────────────────────────────────────
create table if not exists public.categorias (
  id uuid primary key default gen_random_uuid(),
  clave text unique not null,          -- lo que se guarda en el post: 'consejos'
  nombre text not null,                -- lo que se ve: 'Consejo'
  emoji text,                          -- 💡
  orden int default 0,
  activa boolean default true,
  solo_equipo boolean default false,   -- true = solo el equipo puede publicar acá
  creado_en timestamptz default now()
);

create index if not exists categorias_orden on public.categorias (orden);

alter table public.categorias enable row level security;

drop policy if exists "Categorías visibles" on public.categorias;
create policy "Categorías visibles"
  on public.categorias for select using (true);

drop policy if exists "Equipo crea categorías" on public.categorias;
create policy "Equipo crea categorías"
  on public.categorias for insert with check (public.es_equipo());

drop policy if exists "Equipo edita categorías" on public.categorias;
create policy "Equipo edita categorías"
  on public.categorias for update using (public.es_equipo());

drop policy if exists "Equipo borra categorías" on public.categorias;
create policy "Equipo borra categorías"
  on public.categorias for delete using (public.es_equipo());


-- ─── 2. LAS QUE YA TENÍAS, TAL CUAL ────────────────────────────────
-- Se cargan solo si no existen: si después las editás, no se pisan.
insert into public.categorias (clave, nombre, emoji, orden, activa, solo_equipo)
values
  ('general',   'General',  null, 1, true, false),
  ('consejos',  'Consejo',  '💡', 2, true, false),
  ('avances',   'Avance',   '🚀', 3, true, false),
  ('preguntas', 'Pregunta', '❓', 4, true, false),
  ('logros',    'Logro',    '🏆', 5, true, false),
  ('anuncios',  'Anuncio',  '📌', 6, true, true)
on conflict (clave) do nothing;


-- ─── 3. LAS ETIQUETAS, BLINDADAS ───────────────────────────────────
-- Por si la tabla no existiera todavía
create table if not exists public.hashtags (
  id uuid primary key default gen_random_uuid(),
  nombre text unique not null,
  creado_en timestamptz default now()
);

alter table public.hashtags enable row level security;

-- Ver, todas. Crear, borrar y editar: SOLO el equipo.
drop policy if exists "Hashtags visibles" on public.hashtags;
drop policy if exists "Etiquetas visibles" on public.hashtags;
create policy "Etiquetas visibles"
  on public.hashtags for select using (true);

drop policy if exists "Cualquiera crea hashtags" on public.hashtags;
drop policy if exists "Usuario crea hashtags" on public.hashtags;
drop policy if exists "Equipo crea etiquetas" on public.hashtags;
create policy "Equipo crea etiquetas"
  on public.hashtags for insert with check (public.es_equipo());

drop policy if exists "Equipo edita etiquetas" on public.hashtags;
create policy "Equipo edita etiquetas"
  on public.hashtags for update using (public.es_equipo());

drop policy if exists "Equipo borra etiquetas" on public.hashtags;
create policy "Equipo borra etiquetas"
  on public.hashtags for delete using (public.es_equipo());


-- ─── 4. UN POST NO PUEDE INVENTAR ETIQUETAS ────────────────────────
-- Esconder el botón en la pantalla no alcanza: alguien podría mandar
-- un post con etiquetas nuevas desde afuera del sitio. Acá lo cortamos
-- en la base, que es donde no se puede esquivar.
create or replace function public.limpiar_hashtags_post()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare v_ok text[];
begin
  if new.hashtags is null or array_length(new.hashtags, 1) is null then
    return new;
  end if;

  -- Nos quedamos solo con las que existen de verdad
  select array_agg(distinct h.nombre)
    into v_ok
  from public.hashtags h
  where h.nombre = any(new.hashtags);

  new.hashtags := v_ok;   -- las inventadas se caen solas
  return new;
end;
$$;

drop trigger if exists posts_limpiar_hashtags on public.posts;
create trigger posts_limpiar_hashtags
  before insert or update of hashtags on public.posts
  for each row execute function public.limpiar_hashtags_post();


-- ─── 5. TAMPOCO PUEDE INVENTAR CATEGORÍAS ──────────────────────────
-- Si manda una categoría que no existe, o una que es solo del equipo,
-- el post cae en 'general' en vez de romper nada.
create or replace function public.validar_categoria_post()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare v_cat public.categorias%rowtype;
begin
  if new.categoria is null or trim(new.categoria) = '' then
    new.categoria := 'general';
    return new;
  end if;

  select * into v_cat from public.categorias
  where clave = new.categoria and activa = true;

  if v_cat.id is null then
    new.categoria := 'general';
  elsif v_cat.solo_equipo and not public.es_equipo() then
    new.categoria := 'general';
  end if;

  return new;
end;
$$;

drop trigger if exists posts_validar_categoria on public.posts;
create trigger posts_validar_categoria
  before insert or update of categoria on public.posts
  for each row execute function public.validar_categoria_post();


-- ═══════════════════════════════════════════════════════════════════
-- VERIFICACIÓN
-- ═══════════════════════════════════════════════════════════════════
select 'listo' as estado,
  (select count(*) from public.categorias where activa) as categorias_activas,
  (select count(*) from public.hashtags) as etiquetas;

select clave, nombre, emoji, orden, activa, solo_equipo
from public.categorias order by orden;
