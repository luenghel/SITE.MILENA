-- ═══════════════════════════════════════════════════════════════════
-- NOMBRES DE LAS EDGE FUNCTIONS
-- Supabase les pone nombres al azar. Los guardamos acá para que
-- el sitio los encuentre desde cualquier dispositivo.
-- ═══════════════════════════════════════════════════════════════════

create table if not exists public.ajustes (
  clave text primary key,
  valor text,
  actualizado_en timestamptz default now()
);

alter table public.ajustes enable row level security;

-- Cualquiera puede leer (el login necesita saber a qué función llamar)
drop policy if exists "Ajustes visibles" on public.ajustes;
create policy "Ajustes visibles"
  on public.ajustes for select
  using (true);

-- Solo el equipo puede cambiarlos
drop policy if exists "Equipo edita ajustes" on public.ajustes;
create policy "Equipo edita ajustes"
  on public.ajustes for insert
  with check (public.es_equipo());

drop policy if exists "Equipo actualiza ajustes" on public.ajustes;
create policy "Equipo actualiza ajustes"
  on public.ajustes for update
  using (public.es_equipo());

-- Valores iniciales (los vas a completar desde el panel)
insert into public.ajustes (clave, valor) values
  ('func_dos_pasos', null),
  ('func_admin', null),
  ('func_newsletter', 'bright-api'),
  ('func_avisos_clases', null)
on conflict (clave) do nothing;

-- ─── VERIFICACIÓN ──────────────────────────────────────────────────
select clave, coalesce(valor, '(sin configurar)') as valor from public.ajustes order by clave;
