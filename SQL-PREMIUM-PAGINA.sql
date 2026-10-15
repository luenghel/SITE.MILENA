-- ═══════════════════════════════════════════════════════════════════
-- PÁGINA PREMIUM EDITABLE
-- Para armarla con video, con texto, o con las dos cosas.
-- ═══════════════════════════════════════════════════════════════════

alter table public.planes add column if not exists mostrar_precio boolean default false;
alter table public.planes add column if not exists video_url text;
alter table public.planes add column if not exists titulo_pagina text;
alter table public.planes add column if not exists contenido text;
alter table public.planes add column if not exists texto_boton text;
alter table public.planes add column if not exists enlace_boton text;

-- Por ahora, sin precio a la vista
update public.planes set mostrar_precio = false where mostrar_precio is null;

update public.planes
set
  titulo_pagina = coalesce(titulo_pagina, 'Comunidad Premium'),
  texto_boton   = coalesce(texto_boton, 'QUIERO SER PREMIUM')
where clave = 'premium';


-- ─── QUIÉNES QUIEREN SUMARSE ───────────────────────────────────────
create table if not exists public.interesados_premium (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid references auth.users(id) on delete cascade,
  email text,
  contactada boolean default false,
  notas text,
  creado_en timestamptz default now()
);

create unique index if not exists interesados_premium_unico
  on public.interesados_premium (usuario_id);

alter table public.interesados_premium enable row level security;

drop policy if exists "Anotarme como interesada" on public.interesados_premium;
create policy "Anotarme como interesada"
  on public.interesados_premium for insert
  with check (auth.uid() = usuario_id);

drop policy if exists "Ver interesadas" on public.interesados_premium;
create policy "Ver interesadas"
  on public.interesados_premium for select
  using (auth.uid() = usuario_id or public.es_equipo());

drop policy if exists "Equipo actualiza interesadas" on public.interesados_premium;
create policy "Equipo actualiza interesadas"
  on public.interesados_premium for update using (public.es_equipo());

drop policy if exists "Equipo borra interesadas" on public.interesados_premium;
create policy "Equipo borra interesadas"
  on public.interesados_premium for delete using (public.es_equipo());

-- ─── VERIFICACIÓN ──────────────────────────────────────────────────
select clave, nombre, mostrar_precio,
  case when video_url is null then 'sin video' else 'con video' end as video,
  case when contenido is null then 'sin texto' else 'con texto' end as contenido
from public.planes;
