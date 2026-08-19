-- ═══════════════════════════════════════════════════════════════════
-- VERIFICACIÓN EN DOS PASOS
--   · Código por email al entrar desde un dispositivo nuevo
--   · "Confiar en este dispositivo" por 7 días de inactividad
-- ═══════════════════════════════════════════════════════════════════

-- ─── 1. DISPOSITIVOS EN LOS QUE CONFÍA ─────────────────────────────
create table if not exists public.dispositivos_confiables (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid references auth.users(id) on delete cascade,
  token_hash text not null,
  nombre text,                       -- "Chrome en Windows"
  ip text,
  creado_en timestamptz default now(),
  ultimo_uso timestamptz default now()
);

create index if not exists disp_usuario on public.dispositivos_confiables (usuario_id);
create index if not exists disp_token on public.dispositivos_confiables (token_hash);

alter table public.dispositivos_confiables enable row level security;

-- Cada una ve y borra los suyos
drop policy if exists "Ver mis dispositivos" on public.dispositivos_confiables;
create policy "Ver mis dispositivos"
  on public.dispositivos_confiables for select
  using (auth.uid() = usuario_id);

drop policy if exists "Borrar mis dispositivos" on public.dispositivos_confiables;
create policy "Borrar mis dispositivos"
  on public.dispositivos_confiables for delete
  using (auth.uid() = usuario_id);

-- ─── 2. CÓDIGOS ENVIADOS ───────────────────────────────────────────
create table if not exists public.codigos_2pasos (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid references auth.users(id) on delete cascade,
  email text not null,
  codigo_hash text not null,
  intentos int default 0,
  usado boolean default false,
  expira_en timestamptz not null,
  creado_en timestamptz default now()
);

create index if not exists cod2p_usuario on public.codigos_2pasos (usuario_id, usado);

alter table public.codigos_2pasos enable row level security;
-- Nadie lo lee desde el navegador: solo la Edge Function con clave de servicio

-- ─── 3. ¿LA PERSONA QUIERE LOS DOS PASOS? ──────────────────────────
alter table public.perfiles add column if not exists dos_pasos boolean default true;
update public.perfiles set dos_pasos = true where dos_pasos is null;

-- ─── 4. LIMPIEZA AUTOMÁTICA ────────────────────────────────────────
-- Los códigos vencidos y los dispositivos sin usar hace más de 7 días
create or replace function public.limpiar_2pasos()
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.codigos_2pasos where expira_en < now() - interval '1 day';
  delete from public.dispositivos_confiables where ultimo_uso < now() - interval '7 days';
$$;

grant execute on function public.limpiar_2pasos() to authenticated;

-- ─── VERIFICACIÓN ──────────────────────────────────────────────────
select 'listo' as estado,
  (select count(*) from information_schema.tables
   where table_schema='public'
     and table_name in ('dispositivos_confiables','codigos_2pasos')) as tablas;
