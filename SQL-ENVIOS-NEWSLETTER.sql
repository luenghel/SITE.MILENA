-- ═══════════════════════════════════════════════════════════════════
-- REGISTRO DE ENVÍOS DEL NEWSLETTER
-- Se puede correr desde ya. Deja todo listo para el día del dominio.
-- ═══════════════════════════════════════════════════════════════════

create table if not exists public.envios_newsletter (
  id uuid primary key default gen_random_uuid(),
  articulo_id uuid references public.articulos(id) on delete set null,
  titulo text,
  destinatarios int default 0,
  fallos int default 0,
  detalle_error text,
  enviado_en timestamptz default now()
);

-- Un artículo se manda una sola vez
create unique index if not exists envios_articulo_unico
  on public.envios_newsletter (articulo_id)
  where articulo_id is not null;

alter table public.envios_newsletter enable row level security;

drop policy if exists "Equipo ve envios" on public.envios_newsletter;
create policy "Equipo ve envios"
  on public.envios_newsletter for select
  using (public.es_equipo());

drop policy if exists "Equipo borra envios" on public.envios_newsletter;
create policy "Equipo borra envios"
  on public.envios_newsletter for delete
  using (public.es_equipo());

-- ─── Baja de la lista sin necesidad de estar logueada ──────────────
-- (para el enlace "Darme de baja" del pie del email)
drop policy if exists "Cualquiera se da de baja" on public.newsletter_suscriptores;
create policy "Cualquiera se da de baja"
  on public.newsletter_suscriptores for update
  using (true)
  with check (activo = false);

-- ─── VERIFICACIÓN ──────────────────────────────────────────────────
select 'listo' as estado;
