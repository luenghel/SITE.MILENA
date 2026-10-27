-- ═══════════════════════════════════════════════════════════════════
-- PORTADA DE LOS ARTÍCULOS
--   · Una imagen vertical para computadora
--   · Otra más cuadrada para celular
-- ═══════════════════════════════════════════════════════════════════

alter table public.articulos add column if not exists imagen_movil text;

-- ─── VERIFICACIÓN ──────────────────────────────────────────────────
select
  titulo,
  case when imagen_portada is null then '⚠️ falta' else '✓' end as portada_pc,
  case when imagen_movil   is null then '— usa la de PC' else '✓' end as portada_celular,
  case when publicado then 'publicado' else 'borrador' end as estado
from public.articulos
order by creado_en desc;
