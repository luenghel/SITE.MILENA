-- ═══════════════════════════════════════════════════════════════════
-- ANUNCIOS POR EMAIL
--   · Clase nueva agregada a un curso → avisa a sus alumnas
--   · Curso nuevo publicado → avisa a toda la comunidad
-- ═══════════════════════════════════════════════════════════════════

create table if not exists public.anuncios_enviados (
  id uuid primary key default gen_random_uuid(),
  tipo text not null,               -- clase_nueva · curso_nuevo
  referencia_id uuid,               -- id de la clase o del curso
  titulo text,
  destinatarios int default 0,
  fallidos int default 0,
  detalle_error text,
  enviado_por uuid references auth.users(id) on delete set null,
  enviado_en timestamptz default now()
);

-- Un mismo curso o clase se anuncia una sola vez
create unique index if not exists anuncios_unicos
  on public.anuncios_enviados (tipo, referencia_id)
  where referencia_id is not null;

alter table public.anuncios_enviados enable row level security;

drop policy if exists "Equipo ve anuncios" on public.anuncios_enviados;
create policy "Equipo ve anuncios"
  on public.anuncios_enviados for select using (public.es_equipo());

drop policy if exists "Equipo borra anuncios" on public.anuncios_enviados;
create policy "Equipo borra anuncios"
  on public.anuncios_enviados for delete using (public.es_equipo());

-- ─── Quién quiere recibir novedades ────────────────────────────────
alter table public.perfiles add column if not exists recibir_novedades boolean default true;
update public.perfiles set recibir_novedades = true where recibir_novedades is null;

-- ─── VERIFICACIÓN ──────────────────────────────────────────────────
select 'listo' as estado,
  (select count(*) from public.perfiles where coalesce(recibir_novedades,true)) as personas_a_avisar;
