-- ═══════════════════════════════════════════════════════════════════
-- PAGOPAR: guardar el número de pedido
-- Sirve para cruzar la compra con lo que informa Pagopar.
-- ═══════════════════════════════════════════════════════════════════

alter table public.compras add column if not exists pagopar_pedido text;

create index if not exists compras_pagopar_pedido
  on public.compras (pagopar_pedido);

create index if not exists compras_pagopar_id
  on public.compras (pagopar_id);


-- ─── Estados posibles de una compra ────────────────────────────────
-- pendiente · pagado · cancelado · reversado
-- Si tenías una restricción que no incluye "reversado", la ampliamos
do $$
begin
  if exists (
    select 1 from pg_constraint
    where conname like '%compras%estado%' and contype = 'c'
  ) then
    execute (
      select 'alter table public.compras drop constraint ' || conname
      from pg_constraint
      where conname like '%compras%estado%' and contype = 'c' limit 1
    );
  end if;
end $$;

alter table public.compras
  add constraint compras_estado_valido
  check (estado in ('pendiente','pagado','cancelado','reversado'));

-- ─── VERIFICACIÓN ──────────────────────────────────────────────────
select column_name
from information_schema.columns
where table_schema = 'public' and table_name = 'compras'
  and column_name in ('usuario_id','pagopar_id','pagopar_pedido','estado','monto_gs')
order by column_name;
