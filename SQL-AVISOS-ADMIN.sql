-- ═══════════════════════════════════════════════════════════════════
-- REGISTRO DE AVISOS Y SANCIONES
-- Deja constancia de cada aviso, bloqueo o eliminación
-- ═══════════════════════════════════════════════════════════════════

create table if not exists public.avisos_admin (
  id uuid primary key default gen_random_uuid(),
  destinatario_id uuid,
  destinatario_email text,
  destinatario_nombre text,
  tipo text not null,            -- aviso · bloqueo · desbloqueo · eliminacion
  motivo text,
  mensaje text,
  email_enviado boolean default false,
  hecho_por uuid references auth.users(id) on delete set null,
  creado_en timestamptz default now()
);

alter table public.avisos_admin enable row level security;

drop policy if exists "Equipo ve avisos" on public.avisos_admin;
create policy "Equipo ve avisos"
  on public.avisos_admin for select
  using (public.es_equipo());

drop policy if exists "Equipo crea avisos" on public.avisos_admin;
create policy "Equipo crea avisos"
  on public.avisos_admin for insert
  with check (public.es_equipo());

-- ─── Motivo del bloqueo visible para la persona ────────────────────
alter table public.perfiles add column if not exists motivo_bloqueo text;
alter table public.perfiles add column if not exists bloqueado_en timestamptz;

-- ─── Que al borrar el usuario se borre su perfil ───────────────────
do $$
begin
  if exists (
    select 1 from information_schema.table_constraints
    where constraint_name = 'perfiles_id_fkey' and table_name = 'perfiles'
  ) then
    alter table public.perfiles drop constraint perfiles_id_fkey;
  end if;

  alter table public.perfiles
    add constraint perfiles_id_fkey
    foreign key (id) references auth.users(id) on delete cascade;
end $$;

-- ─── VERIFICACIÓN ──────────────────────────────────────────────────
select 'listo' as estado;
