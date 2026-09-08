-- ═══════════════════════════════════════════════════════════════════
-- PREMIUM: RECONOCER QUIÉN SE SUSCRIBIÓ POR EL LINK DE PAGOPAR
--
-- El problema que resuelve:
--   Pagopar nos avisa el pago con el EMAIL que la persona usó
--   allá. Si ese email no es el mismo de su cuenta en el sitio,
--   no sabemos a quién darle el acceso.
--
--   Acá dejamos tres redes:
--     1. Anotamos el intento ANTES de mandarla a Pagopar
--     2. El webhook cruza por email
--     3. Si no cruza, queda para asignar a mano en un click
--
-- Correlo DESPUÉS de SQL-PREMIUM-SEGURIDAD.sql
-- ═══════════════════════════════════════════════════════════════════


-- ─── 1. QUIÉN APRETÓ "QUIERO SER PREMIUM" ──────────────────────────
create table if not exists public.intentos_suscripcion (
  id uuid primary key default gen_random_uuid(),
  usuario_id uuid references auth.users(id) on delete cascade,
  email text,
  creado_en timestamptz default now()
);

create index if not exists intentos_susc_fecha on public.intentos_suscripcion (creado_en desc);

alter table public.intentos_suscripcion enable row level security;

drop policy if exists "Anoto mi intento" on public.intentos_suscripcion;
create policy "Anoto mi intento"
  on public.intentos_suscripcion for insert
  with check (auth.uid() = usuario_id);

drop policy if exists "El equipo ve los intentos" on public.intentos_suscripcion;
create policy "El equipo ve los intentos"
  on public.intentos_suscripcion for select
  using (auth.uid() = usuario_id or public.es_equipo());


-- ─── 2. EXTENDER EL ACCESO DE UNA PERSONA CONCRETA ─────────────────
-- El motor que usan todas las demás. Trabaja con el id, no con el email.
create or replace function public.extender_premium(
  p_usuario       uuid,
  p_monto         int default 0,
  p_referencia    text default null,
  p_periodicidad  text default 'Mensual',
  p_metodo        text default 'pagopar'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_plan  uuid;
  v_susc  public.suscripciones%rowtype;
  v_hasta timestamptz;
  v_paso  interval;
  v_per   text;
begin
  if p_usuario is null then
    return jsonb_build_object('exito', false, 'error', 'Falta la persona');
  end if;

  v_per := lower(coalesce(p_periodicidad, 'mensual'));
  v_paso := case
    when v_per like 'seman%'   then interval '7 days'
    when v_per like 'quincen%' then interval '15 days'
    when v_per like 'anual%'   then interval '1 year'
    else interval '1 month'
  end;

  select id into v_plan from public.planes where clave = 'premium' limit 1;

  select * into v_susc from public.suscripciones
  where usuario_id = p_usuario
  order by vence desc nulls first
  limit 1;

  -- Si le quedan días, se los respetamos y sumamos encima
  v_hasta := greatest(now(), coalesce(v_susc.vence, now())) + v_paso;

  if v_susc.id is null then
    insert into public.suscripciones
      (usuario_id, plan_id, estado, inicio, vence, monto_gs, metodo_pago, referencia_pago, renovacion_automatica)
    values
      (p_usuario, v_plan, 'activa', now(), v_hasta, coalesce(p_monto,0), p_metodo, p_referencia, true);
  else
    update public.suscripciones set
      plan_id = coalesce(plan_id, v_plan),
      estado = 'activa',
      vence = v_hasta,
      monto_gs = coalesce(nullif(p_monto,0), monto_gs),
      metodo_pago = coalesce(p_metodo, metodo_pago),
      referencia_pago = coalesce(p_referencia, referencia_pago),
      renovacion_automatica = true,
      actualizado_en = now()
    where id = v_susc.id;
  end if;

  return jsonb_build_object('exito', true, 'usuario_id', p_usuario, 'vence', v_hasta);
end;
$$;

revoke execute on function public.extender_premium(uuid,int,text,text,text) from anon, authenticated;


-- ─── 3. EL WEBHOOK CRUZA POR EMAIL, Y SI NO, GUARDA ────────────────
create or replace function public.registrar_pago_premium(
  p_email         text,
  p_monto         int default 0,
  p_referencia    text default null,
  p_periodicidad  text default 'Mensual',
  p_metodo        text default 'pagopar',
  p_crudo         jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_uid uuid;
begin
  select id into v_uid from public.perfiles
  where lower(email) = lower(trim(p_email)) limit 1;

  if v_uid is null then
    insert into public.pagos_sin_cuenta (email, monto_gs, referencia, crudo)
    values (trim(p_email), coalesce(p_monto,0), p_referencia, p_crudo);

    return jsonb_build_object(
      'exito', false,
      'error', 'Sin cuenta con el email ' || p_email || '. Quedó en pagos_sin_cuenta para asignar a mano.'
    );
  end if;

  return public.extender_premium(v_uid, p_monto, p_referencia, p_periodicidad, p_metodo);
end;
$$;

revoke execute on function public.registrar_pago_premium(text,int,text,text,text,jsonb) from anon, authenticated;


-- ─── 4. ASIGNAR A MANO UN PAGO QUE NO CRUZÓ ────────────────────────
-- La usa el panel. Milena elige a la persona y listo.
create or replace function public.asignar_pago_sin_cuenta(
  p_pago     uuid,
  p_usuario  uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pago public.pagos_sin_cuenta%rowtype;
  v_res  jsonb;
  v_per  text;
begin
  if not public.es_equipo() then
    return jsonb_build_object('exito', false, 'error', 'Solo el equipo puede hacer esto');
  end if;

  select * into v_pago from public.pagos_sin_cuenta where id = p_pago;
  if v_pago.id is null then
    return jsonb_build_object('exito', false, 'error', 'No encontramos ese pago');
  end if;
  if v_pago.resuelto then
    return jsonb_build_object('exito', false, 'error', 'Ese pago ya fue asignado');
  end if;

  v_per := coalesce(v_pago.crudo #>> '{suscripcion,periodicidad}', 'Mensual');

  v_res := public.extender_premium(
    p_usuario, coalesce(v_pago.monto_gs, 0), v_pago.referencia, v_per, 'pagopar'
  );

  if (v_res->>'exito')::boolean then
    update public.pagos_sin_cuenta set resuelto = true where id = p_pago;
  end if;

  return v_res;
end;
$$;

grant execute on function public.asignar_pago_sin_cuenta(uuid, uuid) to authenticated;


-- ─── 5. CANDIDATAS SUGERIDAS PARA CADA PAGO SUELTO ─────────────────
-- Muestra a quienes apretaron "Quiero ser premium" en los últimos
-- 30 días, para que asignar sea un click y no una búsqueda.
drop view if exists public.pagos_para_asignar;
create view public.pagos_para_asignar
with (security_invoker = true) as
select
  p.id,
  p.email        as email_pagopar,
  p.nombre       as nombre_pagopar,
  p.documento,
  p.monto_gs,
  p.referencia,
  p.creado_en,
  (
    select coalesce(jsonb_agg(c order by c->>'cuando' desc), '[]'::jsonb)
    from (
      select distinct on (i.usuario_id)
        jsonb_build_object(
          'usuario_id', i.usuario_id,
          'nombre', pe.nombre,
          'email', pe.email,
          'cuando', i.creado_en
        ) as c
      from public.intentos_suscripcion i
      join public.perfiles pe on pe.id = i.usuario_id
      where i.creado_en > p.creado_en - interval '30 days'
        and i.creado_en < p.creado_en + interval '2 days'
      order by i.usuario_id, i.creado_en desc
    ) s
  ) as candidatas
from public.pagos_sin_cuenta p
where p.resuelto = false
order by p.creado_en desc;

grant select on public.pagos_para_asignar to authenticated;


-- ═══════════════════════════════════════════════════════════════════
-- VERIFICACIÓN
-- ═══════════════════════════════════════════════════════════════════
select
  'listo' as estado,
  (select count(*) from public.intentos_suscripcion) as intentos,
  (select count(*) from public.pagos_sin_cuenta where resuelto = false) as pagos_sin_asignar;
