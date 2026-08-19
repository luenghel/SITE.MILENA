-- ═══════════════════════════════════════════════════════════════════
-- BANNERS DEL HERO
--   · Una imagen para computadora y otra para celular
--   · Cada banner lleva a su propio enlace
--   · Botón configurable
-- ═══════════════════════════════════════════════════════════════════

alter table public.carruseles add column if not exists imagen_movil text;
alter table public.carruseles add column if not exists texto_boton text;
alter table public.carruseles add column if not exists mostrar_boton boolean default true;

update public.carruseles set mostrar_boton = true where mostrar_boton is null;

-- ─── VERIFICACIÓN ──────────────────────────────────────────────────
select column_name from information_schema.columns
where table_schema='public' and table_name='carruseles'
order by ordinal_position;
