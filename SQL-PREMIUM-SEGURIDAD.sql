-- ═══════════════════════════════════════════════════════════════════
-- PREMIUM: CERRAR LOS ENLACES Y AUTOMATIZAR EL CORTE
--
-- Qué arregla:
--   1. El enlace de los encuentros lo podía leer CUALQUIER persona
--      logueada (la pantalla lo escondía, la base no). Ahora no.
--   2. La grabación de los encuentros, igual.
--   3. Deja el corte de acceso 100% automático, sin que nadie
--      tenga que hacer nada el día que no se cobra.
--
-- Correlo entero en Supabase → SQL Editor. Es seguro correrlo
-- más de una vez.
-- ═══════════════════════════════════════════════════════════════════


-- ─── 1. DÍAS DE GRACIA (configurable, arranca en 0 = corte al instante)
alter table public.planes
  add column if not exists dias_gracia int default 0;

update public.planes set dias_gracia = 0 where dias_gracia is null;

comment on column public.planes.dias_gracia is
  'Días extra de acceso después de que vence, por si el cobro rebota. 0 = corte al instante.';


-- ─── 2. ¿ES PREMIUM? ───────────────────────────────────────────────
-- Antes: alcanzaba con estado = activa.
-- Ahora: manda la FECHA. Si venció, se acabó, sin importar el estado.
-- 'cancelada' corta siempre, aunque le queden días.
create or replace function public.es_premium(p_usuario uuid default null)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.suscripciones s
    left join public.planes pl on pl.id = s.plan_id
    where s.usuario_id = coalesce(p_usuario, auth.uid())
      and s.estado <> 'cancelada'
      and (
        s.vence is null                        -- cortesía sin vencimiento
        or s.vence + make_interval(days => coalesce(pl.dias_gracia, 0)) > now()
      )
  );
$$;

grant execute on function public.es_premium(uuid) to authenticated;


-- ─── 3. LOS ENCUENTROS, CERRADOS DE VERDAD ─────────────────────────
-- Un encuentro marcado "solo premium" ahora solo lo lee quien
-- está al día. El enlace y la grabación viajan adentro de esa fila,
-- así que se protegen solos.
drop policy if exists "Encuentros visibles" on public.encuentros;
create policy "Encuentros visibles"
  on public.encuentros for select
  using (
    auth.uid() is not null
    and (coalesce(publicado, true) or public.es_equipo())
    and (
      coalesce(solo_premium, true) = false
      or public.es_premium()
      or public.es_equipo()
    )
  );


-- ─── 4. LA AGENDA PÚBLICA (sin enlaces) ────────────────────────────
-- Para que quien no es premium igual vea QUE hay encuentros
-- y se entusiasme, pero sin poder entrar.
-- Ojo: acá NO van 'enlace' ni 'grabacion_url'. A propósito.
drop view if exists public.encuentros_agenda;
create view public.encuentros_agenda
with (security_invoker = false) as
select
  e.id,
  e.titulo,
  e.descripcion,
  e.fecha,
  e.duracion_minutos,
  e.solo_premium
from public.encuentros e
where coalesce(e.publicado, true) = true
order by e.fecha asc;

grant select on public.encuentros_agenda to anon, authenticated;


-- ─── 5. PAGOS QUE NO PUDIMOS ASOCIAR A NADIE ───────────────────────
-- Si alguien se suscribe en Pagopar con un email distinto al de su
-- cuenta del sitio, el pago cae acá en vez de perderse.
create table if not exists public.pagos_sin_cuenta (
  id uuid primary key default gen_random_uuid(),
  email text,
  nombre text,
  documento text,
  monto_gs int,
  referencia text,
  crudo jsonb,
  resuelto boolean default false,
  creado_en timestamptz default now()
);

alter table public.pagos_sin_cuenta enable row level security;

drop policy if exists "Solo el equipo ve los pagos sueltos" on public.pagos_sin_cuenta;
create policy "Solo el equipo ve los pagos sueltos"
  on public.pagos_sin_cuenta for select using (public.es_equipo());

drop policy if exists "El equipo resuelve los pagos sueltos" on public.pagos_sin_cuenta;
create policy "El equipo resuelve los pagos sueltos"
  on public.pagos_sin_cuenta for update using (public.es_equipo());


-- ─── 6. REGISTRAR UN PAGO Y EXTENDER LA SUSCRIPCIÓN ────────────────
-- La usa el webhook de Pagopar y también el panel.
-- Si la persona está al día, le SUMA el período a lo que le queda.
-- Si ya venció, arranca de hoy.
create or replace function public.registrar_pago_premium(
  p_email         text,
  p_monto         int default 0,
  p_referencia    text default null,
  p_periodicidad  text default 'Mensual',   -- Semanal · Quincenal · Mensual
  p_metodo        text default 'pagopar',
  p_crudo         jsonb default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid;
  v_plan  uuid;
  v_susc  public.suscripciones%rowtype;
  v_desde timestamptz;
  v_hasta timestamptz;
  v_paso  interval;
  v_per   text;
begin
  -- Cuánto dura el período que acaban de pagar
  v_per := lower(coalesce(p_periodicidad, 'mensual'));
  v_paso := case
    when v_per like 'seman%'  then interval '7 days'
    when v_per like 'quincen%' then interval '15 days'
    when v_per like 'anual%'   then interval '1 year'
    else interval '1 month'
  end;

  select id into v_uid from public.perfiles
  where lower(email) = lower(trim(p_email)) limit 1;

  -- No hay cuenta con ese email: lo guardamos para no perder el pago
  if v_uid is null then
    insert into public.pagos_sin_cuenta (email, monto_gs, referencia, crudo)
    values (trim(p_email), coalesce(p_monto,0), p_referencia, p_crudo);

    return jsonb_build_object(
      'exito', false,
      'error', 'No hay ninguna cuenta con el email ' || p_email || '. Lo anotamos en pagos_sin_cuenta.'
    );
  end if;

  select id into v_plan from public.planes where clave = 'premium' limit 1;

  select * into v_susc from public.suscripciones
  where usuario_id = v_uid
  order by vence desc nulls first
  limit 1;

  -- Si le quedan días, se los respetamos y sumamos encima
  v_desde := greatest(now(), coalesce(v_susc.vence, now()));
  v_hasta := v_desde + v_paso;

  if v_susc.id is null then
    insert into public.suscripciones
      (usuario_id, plan_id, estado, inicio, vence, monto_gs, metodo_pago, referencia_pago, renovacion_automatica)
    values
      (v_uid, v_plan, 'activa', now(), v_hasta, coalesce(p_monto,0), p_metodo, p_referencia, true);
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

  return jsonb_build_object(
    'exito', true,
    'usuario_id', v_uid,
    'vence', v_hasta,
    'periodicidad', p_periodicidad
  );
end;
$$;

revoke execute on function public.registrar_pago_premium(text,int,text,text,text,jsonb) from anon, authenticated;


-- ─── 7. CORTAR UNA SUSCRIPCIÓN AL INSTANTE ─────────────────────────
-- Para cuando Pagopar avisa que la persona canceló o que el cobro
-- falló definitivamente. Corta ya, sin esperar el vencimiento.
create or replace function public.cortar_premium(p_email text, p_motivo text default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_uid uuid; v_n int;
begin
  select id into v_uid from public.perfiles
  where lower(email) = lower(trim(p_email)) limit 1;

  if v_uid is null then
    return jsonb_build_object('exito', false, 'error', 'No hay cuenta con ese email');
  end if;

  update public.suscripciones set
    estado = 'cancelada',
    renovacion_automatica = false,
    notas = coalesce(notas || ' · ', '') || coalesce(p_motivo, 'Cancelada'),
    actualizado_en = now()
  where usuario_id = v_uid and estado <> 'cancelada';

  get diagnostics v_n = row_count;
  return jsonb_build_object('exito', true, 'cortadas', v_n);
end;
$$;

revoke execute on function public.cortar_premium(text,text) from anon, authenticated;


-- ─── 8. MARCAR LAS VENCIDAS (solo cosmético para el panel) ─────────
-- El acceso ya se corta solo por fecha. Esto es para que en el panel
-- se vean como "vencida" en vez de "activa".
create or replace function public.vencer_suscripciones()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare v_n int;
begin
  update public.suscripciones s
  set estado = 'vencida', actualizado_en = now()
  from public.planes pl
  where s.plan_id = pl.id
    and s.estado = 'activa'
    and s.vence is not null
    and s.vence + make_interval(days => coalesce(pl.dias_gracia, 0)) < now();

  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

grant execute on function public.vencer_suscripciones() to authenticated;


-- ═══════════════════════════════════════════════════════════════════
-- VERIFICACIÓN
-- ═══════════════════════════════════════════════════════════════════
select
  'listo' as estado,
  (select count(*) from public.planes) as planes,
  (select count(*) from public.suscripciones where estado = 'activa') as activas,
  (select count(*) from public.encuentros) as encuentros,
  (select count(*) from public.encuentros_agenda) as en_la_agenda_publica,
  (select dias_gracia from public.planes where clave = 'premium') as dias_gracia;

-- Prueba: esto tiene que devolver 0 filas si NO sos premium ni equipo,
-- y las filas completas si SÍ lo sos.
select id, titulo, fecha, enlace from public.encuentros where solo_premium = true;
