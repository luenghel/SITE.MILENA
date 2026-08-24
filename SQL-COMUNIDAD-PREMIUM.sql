-- ═══════════════════════════════════════════════════════════════════
-- COMUNIDAD PREMIUM
--   · Suscripción mensual
--   · Publicaciones exclusivas
--   · Encuentros semanales cerrados
-- ═══════════════════════════════════════════════════════════════════

-- ─── 1. PLANES ─────────────────────────────────────────────────────
create table if not exists public.planes (
  id uuid primary key default gen_random_uuid(),
  clave text unique not null,
  nombre text not null,
  descripcion text,
  precio_gs int default 0,
  precio_anterior_gs int,
  periodo text default 'mensual',        -- mensual · anual
  beneficios text,                       -- una línea por beneficio
  destacado boolean default false,
  activo boolean default true,
  orden int default 0,
  creado_en timestamptz default now()
);

alter table public.planes enable row level security;

drop policy if exists "Planes visibles" on public.planes;
create policy "Planes visibles" on public.planes for select using (true);

drop policy if exists "Equipo crea planes" on public.planes;
create policy "Equipo crea planes" on public.planes for insert with check (public.es_equipo());

drop policy if exists "Equipo edita planes" on public.planes;
create policy "Equipo edita planes" on public.planes for update using (public.es_equipo());

drop policy if exists "Equipo borra planes" on public.planes;
create policy "Equipo borra planes" on public.planes for delete using (public.es_equipo());

-- El plan con el que arrancamos
do $$
begin
  if not exists (select 1 from public.planes where clave = 'premium') then
    insert into public.planes (clave, nombre, descripcion, precio_gs, periodo, beneficios, destacado, orden)
    values (
      'premium',
      'Comunidad Premium',
      'Estrategias exclusivas y encuentros semanales cerrados sobre ventas, marketing y anuncios digitales.',
      150000,
      'mensual',
      'Encuentros semanales en vivo, cerrados' || chr(10) ||
      'Estrategias exclusivas que no publicamos en la comunidad abierta' || chr(10) ||
      'Análisis de anuncios y campañas reales' || chr(10) ||
      'Espacio para preguntas y devoluciones personalizadas' || chr(10) ||
      'Grabaciones de todos los encuentros',
      true,
      1
    );
  end if;
end $$;

-- ─── 2. SUSCRIPCIONES ──────────────────────────────────────────────
create table if not exists public.suscripciones (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid references auth.users(id) on delete cascade,
  plan_id uuid references public.planes(id) on delete set null,
  estado text default 'activa',          -- activa · vencida · cancelada · pendiente
  inicio timestamptz default now(),
  vence timestamptz,
  monto_gs int default 0,
  metodo_pago text,                      -- pagopar · transferencia · manual · cortesia
  referencia_pago text,
  renovacion_automatica boolean default false,
  notas text,
  creado_en timestamptz default now(),
  actualizado_en timestamptz default now()
);

create index if not exists susc_usuario on public.suscripciones (usuario_id, estado);
create index if not exists susc_vence on public.suscripciones (vence);

alter table public.suscripciones enable row level security;

drop policy if exists "Ver mi suscripción" on public.suscripciones;
create policy "Ver mi suscripción"
  on public.suscripciones for select
  using (auth.uid() = usuario_id or public.es_equipo());

drop policy if exists "Equipo gestiona suscripciones - insert" on public.suscripciones;
create policy "Equipo gestiona suscripciones - insert"
  on public.suscripciones for insert with check (public.es_equipo());

drop policy if exists "Equipo gestiona suscripciones - update" on public.suscripciones;
create policy "Equipo gestiona suscripciones - update"
  on public.suscripciones for update using (public.es_equipo());

drop policy if exists "Equipo gestiona suscripciones - delete" on public.suscripciones;
create policy "Equipo gestiona suscripciones - delete"
  on public.suscripciones for delete using (public.es_equipo());

-- ─── 3. ¿ESTA PERSONA ES PREMIUM? ──────────────────────────────────
create or replace function public.es_premium(p_usuario uuid default null)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.suscripciones s
    where s.usuario_id = coalesce(p_usuario, auth.uid())
      and s.estado = 'activa'
      and (s.vence is null or s.vence > now())
  );
$$;

grant execute on function public.es_premium(uuid) to authenticated;

-- ─── 4. PUBLICACIONES EXCLUSIVAS ───────────────────────────────────
alter table public.posts add column if not exists premium boolean default false;
update public.posts set premium = false where premium is null;

-- Los posts premium solo los ven las suscriptas (o el equipo, o su autora)
drop policy if exists "Posts visibles para logueados" on public.posts;
create policy "Posts visibles para logueados"
  on public.posts for select
  using (
    auth.uid() is not null
    and (coalesce(oculto, false) = false and coalesce(pendiente_aprobacion, false) = false
         or public.es_equipo() or usuario_id = auth.uid())
    and (coalesce(premium, false) = false
         or public.es_premium() or public.es_equipo() or usuario_id = auth.uid())
  );

-- ─── 5. ENCUENTROS SEMANALES ───────────────────────────────────────
create table if not exists public.encuentros (
  id uuid primary key default gen_random_uuid(),
  titulo text not null,
  descripcion text,
  fecha timestamptz not null,
  duracion_minutos int default 60,
  enlace text,                           -- Zoom, Meet, etc.
  grabacion_url text,
  solo_premium boolean default true,
  publicado boolean default true,
  creado_en timestamptz default now()
);

create index if not exists encuentros_fecha on public.encuentros (fecha);

alter table public.encuentros enable row level security;

-- Todas ven que existe; el enlace se muestra solo a las premium (desde el sitio)
drop policy if exists "Encuentros visibles" on public.encuentros;
create policy "Encuentros visibles"
  on public.encuentros for select
  using (auth.uid() is not null and (coalesce(publicado, true) or public.es_equipo()));

drop policy if exists "Equipo crea encuentros" on public.encuentros;
create policy "Equipo crea encuentros" on public.encuentros for insert with check (public.es_equipo());

drop policy if exists "Equipo edita encuentros" on public.encuentros;
create policy "Equipo edita encuentros" on public.encuentros for update using (public.es_equipo());

drop policy if exists "Equipo borra encuentros" on public.encuentros;
create policy "Equipo borra encuentros" on public.encuentros for delete using (public.es_equipo());

-- ─── 6. VENCER LAS QUE YA PASARON ──────────────────────────────────
create or replace function public.vencer_suscripciones()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare v_n int;
begin
  update public.suscripciones
  set estado = 'vencida', actualizado_en = now()
  where estado = 'activa' and vence is not null and vence < now();

  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

grant execute on function public.vencer_suscripciones() to authenticated;

-- ─── 7. QUIÉNES SON PREMIUM, PARA EL PANEL ─────────────────────────
drop view if exists public.premium_activas;
create view public.premium_activas as
select
  s.id,
  s.usuario_id,
  p.nombre,
  p.email,
  p.avatar_url,
  s.estado,
  s.inicio,
  s.vence,
  s.monto_gs,
  s.metodo_pago,
  s.renovacion_automatica,
  case
    when s.vence is null then null
    else greatest(0, extract(day from (s.vence - now()))::int)
  end as dias_restantes
from public.suscripciones s
join public.perfiles p on p.id = s.usuario_id
order by s.vence desc nulls first;

grant select on public.premium_activas to authenticated;

-- ─── VERIFICACIÓN ──────────────────────────────────────────────────
select 'listo' as estado,
  (select count(*) from public.planes) as planes,
  (select count(*) from public.suscripciones where estado = 'activa') as suscripciones_activas,
  (select count(*) from public.encuentros) as encuentros;
