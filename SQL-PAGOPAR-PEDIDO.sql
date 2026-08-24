-- ═══════════════════════════════════════════════════════════════════
-- PAGOPAR: guardar el número de pedido
-- Sirve para cruzar la compra con lo que informa Pagopar.
-- ═══════════════════════════════════════════════════════════════════

alter table public.compras add column if not exists pagopar_pedido text;

create index if not exists compras_pagopar_pedido
  on public.compras (pagopar_pedido);

create index if not exists compras_pagopar_id
  on public.compras (pagopar_id);

-- ─── VERIFICACIÓN ──────────────────────────────────────────────────
select column_name
from information_schema.columns
where table_schema = 'public' and table_name = 'compras'
  and column_name in ('usuario_id','pagopar_id','pagopar_pedido','estado','monto_gs')
order by column_name;
