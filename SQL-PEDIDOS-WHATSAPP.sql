-- ═══════════════════════════════════════════════════════════════════
-- PEDIDOS MANUALES
--
-- Mientras no haya pasarela: la alumna toca "Comprar", queda el pedido
-- registrado y se abre WhatsApp. Vos confirmás el pago y das el acceso
-- con un clic desde el panel.
-- ═══════════════════════════════════════════════════════════════════

create table if not exists public.pedidos (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid references auth.users(id) on delete cascade,
  curso_id uuid references public.cursos(id) on delete set null,
  plan_premium boolean default false,      -- es la suscripción, no un curso
  meses_premium int default 0,
  nombre text,
  email text,
  telefono text,
  monto_gs int default 0,
  estado text default 'pendiente',         -- pendiente · pagado · cancelado
  metodo_pago text,                        -- transferencia · tigo · efectivo
  notas text,
  codigo text unique,                      -- el número corto que dice en WhatsApp
  confirmado_en timestamptz,
  confirmado_por uuid references auth.users(id) on delete set null,
  creado_en timestamptz default now()
);

create index if not exists pedidos_estado on public.pedidos (estado, creado_en desc);
create index if not exists pedidos_usuario on public.pedidos (usuario_id);

alter table public.pedidos enable row level security;

drop policy if exists "Ver mis pedidos" on public.pedidos;
create policy "Ver mis pedidos"
  on public.pedidos for select
  using (auth.uid() = usuario_id or public.es_equipo());

drop policy if exists "Crear mi pedido" on public.pedidos;
create policy "Crear mi pedido"
  on public.pedidos for insert
  with check (auth.uid() = usuario_id);

drop policy if exists "Equipo gestiona pedidos" on public.pedidos;
create policy "Equipo gestiona pedidos"
  on public.pedidos for update using (public.es_equipo());

drop policy if exists "Equipo borra pedidos" on public.pedidos;
create policy "Equipo borra pedidos"
  on public.pedidos for delete using (public.es_equipo());

-- ─── Un código corto para identificarlo en WhatsApp ────────────────
create or replace function public.codigo_pedido()
returns trigger
language plpgsql
as $$
begin
  if new.codigo is null then
    new.codigo := 'P' || to_char(now(), 'MMDD') || '-' ||
                  upper(substr(md5(random()::text), 1, 4));
  end if;
  return new;
end;
$$;

drop trigger if exists trg_codigo_pedido on public.pedidos;
create trigger trg_codigo_pedido
  before insert on public.pedidos
  for each row execute function public.codigo_pedido();

-- ─── Confirmar el pago y dar el acceso, de una ─────────────────────
create or replace function public.confirmar_pedido(
  p_pedido uuid,
  p_metodo text default 'transferencia',
  p_notas text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_ped record;
begin
  if not public.es_equipo() then
    return jsonb_build_object('exito', false, 'error', 'Solo el equipo puede confirmar pedidos');
  end if;

  select * into v_ped from public.pedidos where id = p_pedido;

  if v_ped is null then
    return jsonb_build_object('exito', false, 'error', 'No encontramos ese pedido');
  end if;
  if v_ped.estado = 'pagado' then
    return jsonb_build_object('exito', false, 'error', 'Este pedido ya estaba confirmado');
  end if;

  -- El curso
  if v_ped.curso_id is not null then
    if not exists (
      select 1 from public.compras
      where usuario_id = v_ped.usuario_id and curso_id = v_ped.curso_id and estado = 'pagado'
    ) then
      insert into public.compras (usuario_id, curso_id, monto_gs, estado, metodo_pago, pagado_en)
      values (v_ped.usuario_id, v_ped.curso_id, coalesce(v_ped.monto_gs, 0),
              'pagado', coalesce(p_metodo, 'transferencia'), now());
    end if;
  end if;

  -- O la suscripción premium
  if v_ped.plan_premium and coalesce(v_ped.meses_premium, 0) > 0 then
    insert into public.suscripciones
      (usuario_id, estado, inicio, vence, monto_gs, metodo_pago, notas)
    values (
      v_ped.usuario_id, 'activa', now(),
      -- Si ya tenía, le sumamos desde donde vencía
      greatest(now(), coalesce((
        select max(vence) from public.suscripciones
        where usuario_id = v_ped.usuario_id and estado = 'activa'
      ), now())) + (v_ped.meses_premium || ' months')::interval,
      coalesce(v_ped.monto_gs, 0),
      coalesce(p_metodo, 'transferencia'),
      'Confirmado desde el panel'
    );
  end if;

  update public.pedidos
  set estado = 'pagado',
      metodo_pago = coalesce(p_metodo, metodo_pago),
      notas = coalesce(p_notas, notas),
      confirmado_en = now(),
      confirmado_por = auth.uid()
  where id = p_pedido;

  return jsonb_build_object(
    'exito', true,
    'usuario_id', v_ped.usuario_id,
    'curso_id', v_ped.curso_id,
    'premium', v_ped.plan_premium
  );
end;
$$;

grant execute on function public.confirmar_pedido(uuid, text, text) to authenticated;

-- ─── Los pedidos, con los datos para el panel ──────────────────────
drop view if exists public.pedidos_detalle;
create view public.pedidos_detalle as
select
  pe.id,
  pe.codigo,
  pe.estado,
  pe.monto_gs,
  pe.metodo_pago,
  pe.notas,
  pe.creado_en,
  pe.confirmado_en,
  pe.plan_premium,
  pe.meses_premium,
  pe.usuario_id,
  coalesce(pe.nombre, p.nombre) as nombre,
  coalesce(pe.email, p.email)   as email,
  pe.telefono,
  p.avatar_url,
  c.titulo as curso_titulo,
  c.slug   as curso_slug,
  extract(day from (now() - pe.creado_en))::int as dias_esperando
from public.pedidos pe
left join public.perfiles p on p.id = pe.usuario_id
left join public.cursos c   on c.id = pe.curso_id
order by
  case when pe.estado = 'pendiente' then 0 else 1 end,
  pe.creado_en desc;

grant select on public.pedidos_detalle to authenticated;

-- ═══════════════════════════════════════════════════════════════════
-- DATOS PARA EL PAGO MANUAL (editables desde el panel)
-- ═══════════════════════════════════════════════════════════════════

do $$
declare r record;
begin
  for r in select * from (values
    ('pago_whatsapp',      '595986200740'),
    ('pago_banco',         ''),
    ('pago_titular',       ''),
    ('pago_cuenta',        ''),
    ('pago_ruc',           ''),
    ('pago_tigo',          ''),
    ('pago_instrucciones', 'Hacé la transferencia y mandanos el comprobante por WhatsApp. Te damos el acceso en el día.')
  ) as t(clave, valor)
  loop
    if not exists (select 1 from public.ajustes where clave = r.clave) then
      insert into public.ajustes (clave, valor) values (r.clave, r.valor);
    end if;
  end loop;
end $$;

-- ─── VERIFICACIÓN ──────────────────────────────────────────────────
select 'listo' as estado,
  (select count(*) from public.pedidos) as pedidos,
  (select count(*) from public.ajustes where clave like 'pago_%') as datos_de_pago;
