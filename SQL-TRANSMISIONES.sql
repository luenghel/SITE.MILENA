-- ═══════════════════════════════════════════════════════════════════
-- TRANSMISIONES EN VIVO DE LA COMUNIDAD PREMIUM
--
--   · Solo las premium al día pueden ver y comentar
--   · La grabación queda disponible 24 horas (configurable)
--   · El contador de conectadas lo ve SOLO el equipo
--
-- Correlo DESPUÉS de SQL-PREMIUM-SEGURIDAD.sql
-- ═══════════════════════════════════════════════════════════════════


-- ─── 1. LAS TRANSMISIONES ──────────────────────────────────────────
create table if not exists public.transmisiones (
  id uuid primary key default gen_random_uuid(),
  titulo text not null,
  descripcion text,

  -- 'programada' · 'en_vivo' · 'terminada'
  estado text not null default 'programada',

  -- Cuándo arranca (para el contador de la pantalla)
  empieza_en timestamptz,

  -- Se llenan solos al arrancar y al terminar
  inicio_real timestamptz,
  fin_real timestamptz,

  -- Cuántas horas queda la grabación después de terminar
  horas_replay int default 24,

  -- El id del video en el proveedor (Cloudflare Stream, etc.)
  -- Mientras probamos, se puede pegar acá una URL de prueba.
  video_uid text,
  video_url_prueba text,

  creado_en timestamptz default now()
);

create index if not exists transmisiones_estado on public.transmisiones (estado, empieza_en desc);

alter table public.transmisiones enable row level security;


-- ─── 2. HASTA CUÁNDO SE PUEDE VER ──────────────────────────────────
-- En vivo: siempre.
-- Terminada: hasta fin_real + horas_replay.
create or replace function public.transmision_disponible(t public.transmisiones)
returns boolean
language sql
stable
as $$
  select case
    when t.estado = 'en_vivo' then true
    when t.estado = 'terminada' and t.fin_real is not null
      then t.fin_real + make_interval(hours => coalesce(t.horas_replay, 24)) > now()
    else false
  end;
$$;


-- ─── 3. QUIÉN VE QUÉ ───────────────────────────────────────────────
-- El equipo ve todo. Las premium ven solo lo que está disponible.
-- El resto no ve nada.
drop policy if exists "Transmisiones visibles" on public.transmisiones;
create policy "Transmisiones visibles"
  on public.transmisiones for select
  using (
    public.es_equipo()
    or (public.es_premium() and public.transmision_disponible(transmisiones))
  );

drop policy if exists "Equipo crea transmisiones" on public.transmisiones;
create policy "Equipo crea transmisiones"
  on public.transmisiones for insert with check (public.es_equipo());

drop policy if exists "Equipo edita transmisiones" on public.transmisiones;
create policy "Equipo edita transmisiones"
  on public.transmisiones for update using (public.es_equipo());

drop policy if exists "Equipo borra transmisiones" on public.transmisiones;
create policy "Equipo borra transmisiones"
  on public.transmisiones for delete using (public.es_equipo());


-- ─── 4. LA AGENDA, PARA LAS QUE NO SON PREMIUM ─────────────────────
-- Ven que hay algo y cuándo. Nada más: ni el video ni el chat.
drop view if exists public.transmisiones_agenda;
create view public.transmisiones_agenda
with (security_invoker = false) as
select
  t.id,
  t.titulo,
  t.descripcion,
  t.empieza_en,
  t.estado
from public.transmisiones t
where t.estado in ('programada', 'en_vivo')
order by t.empieza_en asc;

grant select on public.transmisiones_agenda to anon, authenticated;


-- ─── 5. EL CHAT ────────────────────────────────────────────────────
create table if not exists public.mensajes_vivo (
  id bigint generated always as identity primary key,
  transmision_id uuid references public.transmisiones(id) on delete cascade,
  usuario_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  texto text not null check (char_length(trim(texto)) between 1 and 400),
  oculto boolean default false,
  creado_en timestamptz default now()
);

create index if not exists mensajes_vivo_trans on public.mensajes_vivo (transmision_id, creado_en);

alter table public.mensajes_vivo enable row level security;

-- Leer: el equipo todo; las premium, lo que no está oculto
drop policy if exists "Premium lee el chat" on public.mensajes_vivo;
create policy "Premium lee el chat"
  on public.mensajes_vivo for select
  using (
    public.es_equipo()
    or (public.es_premium() and coalesce(oculto, false) = false)
  );

-- Escribir: solo premium, solo en su nombre, y solo si no está bloqueada
drop policy if exists "Premium escribe en el chat" on public.mensajes_vivo;
create policy "Premium escribe en el chat"
  on public.mensajes_vivo for insert
  with check (
    usuario_id = auth.uid()
    and public.es_premium()
    and not exists (
      select 1 from public.perfiles p
      where p.id = auth.uid() and coalesce(p.bloqueado, false) = true
    )
  );

-- Moderar: solo el equipo
drop policy if exists "Equipo modera el chat" on public.mensajes_vivo;
create policy "Equipo modera el chat"
  on public.mensajes_vivo for update using (public.es_equipo());

drop policy if exists "Equipo borra del chat" on public.mensajes_vivo;
create policy "Equipo borra del chat"
  on public.mensajes_vivo for delete using (public.es_equipo());


-- ─── 6. LA TRANSMISIÓN QUE HAY QUE MOSTRAR AHORA ───────────────────
-- Devuelve una sola fila: la que está en vivo, o la última grabación
-- que todavía esté dentro de las 24 horas.
create or replace function public.transmision_actual()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  t public.transmisiones%rowtype;
  v_hasta timestamptz;
begin
  if not (public.es_premium() or public.es_equipo()) then
    return jsonb_build_object('hay', false, 'motivo', 'sin-acceso');
  end if;

  -- Primero, la que esté en vivo
  select * into t from public.transmisiones
  where estado = 'en_vivo'
  order by coalesce(inicio_real, empieza_en) desc
  limit 1;

  -- Si no hay, la última grabación que siga dentro de la ventana
  if t.id is null then
    select * into t from public.transmisiones
    where estado = 'terminada'
      and fin_real is not null
      and fin_real + make_interval(hours => coalesce(horas_replay, 24)) > now()
    order by fin_real desc
    limit 1;
  end if;

  if t.id is null then
    -- Nada para ver: devolvemos la próxima programada, si la hay
    select * into t from public.transmisiones
    where estado = 'programada' and empieza_en is not null and empieza_en > now()
    order by empieza_en asc
    limit 1;

    if t.id is null then
      return jsonb_build_object('hay', false, 'motivo', 'nada');
    end if;

    return jsonb_build_object(
      'hay', false,
      'motivo', 'programada',
      'titulo', t.titulo,
      'descripcion', t.descripcion,
      'empieza_en', t.empieza_en
    );
  end if;

  v_hasta := case
    when t.estado = 'terminada' and t.fin_real is not null
      then t.fin_real + make_interval(hours => coalesce(t.horas_replay, 24))
    else null
  end;

  return jsonb_build_object(
    'hay', true,
    'id', t.id,
    'titulo', t.titulo,
    'descripcion', t.descripcion,
    'estado', t.estado,
    'video_uid', t.video_uid,
    'video_url_prueba', t.video_url_prueba,
    'inicio_real', t.inicio_real,
    'fin_real', t.fin_real,
    'disponible_hasta', v_hasta,
    'horas_replay', coalesce(t.horas_replay, 24)
  );
end;
$$;

grant execute on function public.transmision_actual() to authenticated;


-- ─── 7. ARRANCAR Y TERMINAR, DESDE EL PANEL ────────────────────────
create or replace function public.arrancar_transmision(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.es_equipo() then
    return jsonb_build_object('exito', false, 'error', 'Solo el equipo');
  end if;

  -- Una sola en vivo a la vez
  update public.transmisiones
  set estado = 'terminada', fin_real = coalesce(fin_real, now())
  where estado = 'en_vivo' and id <> p_id;

  update public.transmisiones
  set estado = 'en_vivo', inicio_real = coalesce(inicio_real, now()), fin_real = null
  where id = p_id;

  return jsonb_build_object('exito', true);
end;
$$;

create or replace function public.terminar_transmision(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare v_hasta timestamptz;
begin
  if not public.es_equipo() then
    return jsonb_build_object('exito', false, 'error', 'Solo el equipo');
  end if;

  update public.transmisiones
  set estado = 'terminada', fin_real = now()
  where id = p_id;

  select fin_real + make_interval(hours => coalesce(horas_replay, 24))
    into v_hasta
  from public.transmisiones where id = p_id;

  return jsonb_build_object('exito', true, 'disponible_hasta', v_hasta);
end;
$$;

grant execute on function public.arrancar_transmision(uuid) to authenticated;
grant execute on function public.terminar_transmision(uuid) to authenticated;


-- ═══════════════════════════════════════════════════════════════════
-- VERIFICACIÓN
-- ═══════════════════════════════════════════════════════════════════
select 'listo' as estado,
  (select count(*) from public.transmisiones) as transmisiones,
  (select count(*) from public.mensajes_vivo) as mensajes;
