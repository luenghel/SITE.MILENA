-- ═══════════════════════════════════════════════════════════════════
-- 1. MENSAJE PERSONALIZADO EN LOS ANUNCIOS
-- 2. CURSOS QUE VIENEN PRONTO
-- 3. INSIGNIAS GESTIONABLES
-- ═══════════════════════════════════════════════════════════════════

-- ─── 1. MENSAJE DEL ANUNCIO ────────────────────────────────────────
alter table public.anuncios_enviados add column if not exists mensaje text;

-- ─── 2. CURSOS QUE VIENEN PRONTO ───────────────────────────────────
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

-- ─── 3. INSIGNIAS ──────────────────────────────────────────────────
create table if not exists public.insignias (
  id uuid primary key default gen_random_uuid(),
  nombre text not null,
  descripcion text,
  icono text default '⭐',
  color text default '#FAC775',
  tipo text default 'manual',     -- manual · automatica
  criterio text,                  -- posts · comentarios · likes · cursos · antiguedad
  cantidad int default 0,         -- cuántos hacen falta
  orden int default 0,
  activa boolean default true,
  creado_en timestamptz default now()
);

alter table public.insignias enable row level security;

drop policy if exists "Insignias visibles" on public.insignias;
create policy "Insignias visibles"
  on public.insignias for select using (true);

drop policy if exists "Equipo crea insignias" on public.insignias;
create policy "Equipo crea insignias"
  on public.insignias for insert with check (public.es_equipo());

drop policy if exists "Equipo edita insignias" on public.insignias;
create policy "Equipo edita insignias"
  on public.insignias for update using (public.es_equipo());

drop policy if exists "Equipo borra insignias" on public.insignias;
create policy "Equipo borra insignias"
  on public.insignias for delete using (public.es_equipo());

-- Quién tiene cuál
create table if not exists public.usuario_insignias (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid references auth.users(id) on delete cascade,
  insignia_id uuid references public.insignias(id) on delete cascade,
  otorgada_en timestamptz default now()
);

create unique index if not exists usuario_insignia_unica
  on public.usuario_insignias (usuario_id, insignia_id);

alter table public.usuario_insignias enable row level security;

drop policy if exists "Insignias de todos visibles" on public.usuario_insignias;
create policy "Insignias de todos visibles"
  on public.usuario_insignias for select using (auth.uid() is not null);

drop policy if exists "Equipo otorga insignias" on public.usuario_insignias;
create policy "Equipo otorga insignias"
  on public.usuario_insignias for insert with check (public.es_equipo());

drop policy if exists "Equipo quita insignias" on public.usuario_insignias;
create policy "Equipo quita insignias"
  on public.usuario_insignias for delete using (public.es_equipo());

-- La que cada una elige mostrar al lado de su nombre
alter table public.perfiles add column if not exists insignia_destacada uuid references public.insignias(id) on delete set null;

-- ─── Insignias para empezar ────────────────────────────────────────
insert into public.insignias (nombre, descripcion, icono, color, tipo, criterio, cantidad, orden) values
  ('Fundadora',        'Parte del equipo de CMM',                    '👑', '#FAC775', 'manual',     null,          0,  1),
  ('Primeros pasos',   'Publicó su primer mensaje en la comunidad',  '🌱', '#9FE1CB', 'automatica', 'posts',       1,  2),
  ('Voz activa',       'Publicó 10 mensajes',                        '💬', '#E8B8C4', 'automatica', 'posts',       10, 3),
  ('Siempre presente', 'Publicó 50 mensajes',                        '🔥', '#FF8090', 'automatica', 'posts',       50, 4),
  ('Compañera',        'Dejó 25 comentarios',                        '🤝', '#9FE1CB', 'automatica', 'comentarios', 25, 5),
  ('Generosa',         'Repartió 50 diamantes',                      '💎', '#E8B8C4', 'automatica', 'likes',       50, 6),
  ('Estudiante',       'Se inscribió en su primer curso',            '📚', '#FAC775', 'automatica', 'cursos',      1,  7),
  ('Coleccionista',    'Tiene 3 cursos o más',                       '🎓', '#FAC775', 'automatica', 'cursos',      3,  8),
  ('De las primeras',  'Está desde los comienzos',                   '⭐', '#FAC775', 'manual',     null,          0,  9)
on conflict do nothing;

-- ─── VERIFICACIÓN ──────────────────────────────────────────────────
select 'listo' as estado, (select count(*) from public.insignias) as insignias;
