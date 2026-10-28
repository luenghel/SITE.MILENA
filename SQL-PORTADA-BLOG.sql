-- ═══════════════════════════════════════════════════════════════════
-- IMÁGENES DE LOS ARTÍCULOS
--
-- Son tres, porque cada lugar tiene una forma distinta:
--   1. Tarjeta en computadora → vertical  (3:4)
--   2. Tarjeta en celular      → casi cuadrada (4:5)
--   3. Banner dentro del artículo → apaisado (16:9)
--
-- Usar la misma en los tres lugares hace que se recorte mal.
-- ═══════════════════════════════════════════════════════════════════

-- La tarjeta en celular
-- La portada de la tarjeta (vertical) y la de celular
alter table public.articulos add column if not exists imagen_movil text;

-- La imagen apaisada que va DENTRO del artículo
alter table public.articulos add column if not exists imagen_banner text;

-- El banner de adentro del artículo
alter table public.articulos add column if not exists imagen_banner text;

-- ─── VERIFICACIÓN ──────────────────────────────────────────────────
select
  titulo,
  case when imagen_portada is null then '⚠️ falta' else '✓' end as tarjeta_pc,
  case when imagen_movil   is null then '— usa la de PC' else '✓' end as tarjeta_celular,
  case when imagen_banner  is null then '— usa la de PC' else '✓' end as banner_interno,
  case when publicado then 'publicado' else 'borrador' end as estado
from public.articulos
order by creado_en desc;
