-- ═══════════════════════════════════════════════════════════════════
-- 1. COMENTARIOS EN LAS CLASES
-- 2. OPINIONES SOBRE CADA CLASE
-- 3. INVITACIONES POR EMAIL
-- ═══════════════════════════════════════════════════════════════════

-- ═══════════════════ 1. COMENTARIOS ════════════════════════════════
create table if not exists public.comentarios_clase (
  id uuid primary key default gen_random_uuid(),
  clase_id uuid references public.clases(id) on delete cascade,
  curso_id uuid references public.cursos(id) on delete cascade,
  usuario_id uuid references auth.users(id) on delete cascade,
  responde_a uuid references public.comentarios_clase(id) on delete cascade,
  texto text not null,
  es_pregunta boolean default false,
  resuelto boolean default false,
  oculto boolean default false,
  creado_en timestamptz default now()
);

create index if not exists com_clase on public.comentarios_clase (clase_id, creado_en);
create index if not exists com_responde on public.comentarios_clase (responde_a);

alter table public.comentarios_clase enable row level security;

drop policy if exists "Ver comentarios de clase" on public.comentarios_clase;
create policy "Ver comentarios de clase"
  on public.comentarios_clase for select
  using (
    auth.uid() is not null
    and (coalesce(oculto, false) = false or public.es_equipo() or usuario_id = auth.uid())
  );

drop policy if exists "Comentar en clase" on public.comentarios_clase;
create policy "Comentar en clase"
  on public.comentarios_clase for insert
  with check (auth.uid() = usuario_id);

drop policy if exists "Editar mi comentario" on public.comentarios_clase;
create policy "Editar mi comentario"
  on public.comentarios_clase for update
  using (auth.uid() = usuario_id or public.es_equipo());

drop policy if exists "Borrar mi comentario" on public.comentarios_clase;
create policy "Borrar mi comentario"
  on public.comentarios_clase for delete
  using (auth.uid() = usuario_id or public.es_equipo());

-- ─── Me gusta en los comentarios ───
create table if not exists public.likes_comentario (
  id uuid primary key default gen_random_uuid(),
  comentario_id uuid references public.comentarios_clase(id) on delete cascade,
  usuario_id uuid references auth.users(id) on delete cascade,
  creado_en timestamptz default now()
);

create unique index if not exists like_com_unico
  on public.likes_comentario (comentario_id, usuario_id);

alter table public.likes_comentario enable row level security;

drop policy if exists "Ver me gusta" on public.likes_comentario;
create policy "Ver me gusta" on public.likes_comentario for select using (auth.uid() is not null);

drop policy if exists "Dar me gusta" on public.likes_comentario;
create policy "Dar me gusta" on public.likes_comentario for insert with check (auth.uid() = usuario_id);

drop policy if exists "Quitar mi me gusta" on public.likes_comentario;
create policy "Quitar mi me gusta" on public.likes_comentario for delete using (auth.uid() = usuario_id);

-- ─── Avisos de respuesta pendientes de enviar ───
create table if not exists public.avisos_respuesta (
  id uuid primary key default gen_random_uuid(),
  comentario_id uuid references public.comentarios_clase(id) on delete cascade,
  respuesta_id uuid references public.comentarios_clase(id) on delete cascade,
  usuario_id uuid references auth.users(id) on delete cascade,
  enviado boolean default false,
  creado_en timestamptz default now()
);

create unique index if not exists aviso_resp_unico on public.avisos_respuesta (respuesta_id);

alter table public.avisos_respuesta enable row level security;

drop policy if exists "Equipo ve avisos de respuesta" on public.avisos_respuesta;
create policy "Equipo ve avisos de respuesta"
  on public.avisos_respuesta for select using (public.es_equipo());

-- Al responder, se anota el aviso
create or replace function public.anotar_aviso_respuesta()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare v_autor uuid;
begin
  if new.responde_a is null then return new; end if;

  select usuario_id into v_autor
  from public.comentarios_clase where id = new.responde_a;

  -- No nos avisamos a nosotras mismas
  if v_autor is null or v_autor = new.usuario_id then return new; end if;

  insert into public.avisos_respuesta (comentario_id, respuesta_id, usuario_id)
  values (new.responde_a, new.id, v_autor)
  on conflict (respuesta_id) do nothing;

  return new;
end;
$$;

drop trigger if exists trg_aviso_respuesta on public.comentarios_clase;
create trigger trg_aviso_respuesta
  after insert on public.comentarios_clase
  for each row execute function public.anotar_aviso_respuesta();

-- Lo que hay que avisar
drop view if exists public.respuestas_por_avisar;
create view public.respuestas_por_avisar as
select
  a.id           as aviso_id,
  a.usuario_id,
  p.email,
  p.nombre,
  orig.texto     as mi_comentario,
  resp.texto     as la_respuesta,
  rp.nombre      as quien_respondio,
  cl.id          as clase_id,
  cl.titulo      as clase_titulo,
  cu.titulo      as curso_titulo,
  cu.slug        as curso_slug
from public.avisos_respuesta a
join public.perfiles p on p.id = a.usuario_id
join public.comentarios_clase orig on orig.id = a.comentario_id
join public.comentarios_clase resp on resp.id = a.respuesta_id
join public.perfiles rp on rp.id = resp.usuario_id
join public.clases cl on cl.id = resp.clase_id
join public.cursos cu on cu.id = resp.curso_id
where a.enviado = false
  and coalesce(p.recibir_novedades, true)
  and coalesce(resp.oculto, false) = false;

grant select on public.respuestas_por_avisar to authenticated;

-- ═══════════════════ 2. OPINIONES ══════════════════════════════════
create table if not exists public.opciones_opinion (
  id uuid primary key default gen_random_uuid(),
  clave text unique not null,
  texto text not null,
  icono text,
  positiva boolean default true,
  orden int default 0,
  activa boolean default true
);

alter table public.opciones_opinion enable row level security;

drop policy if exists "Opciones visibles" on public.opciones_opinion;
create policy "Opciones visibles" on public.opciones_opinion for select using (true);

drop policy if exists "Equipo gestiona opciones" on public.opciones_opinion;
create policy "Equipo gestiona opciones" on public.opciones_opinion for all using (public.es_equipo());

-- Las que propusimos
do $$
declare r record;
begin
  for r in select * from (values
    ('clara',      'Me quedó clarísimo',       '💡', true,  1),
    ('aplicable',  'Ya sé cómo aplicarlo',     '🎯', true,  2),
    ('encanto',    'Me encantó',               '❤️', true,  3),
    ('dudas',      'Me quedaron dudas',        '🤔', false, 4),
    ('profunda',   'La quiero más profunda',   '📚', false, 5),
    ('rapida',     'Fue muy rápida',           '🐢', false, 6),
    ('larga',      'Se me hizo larga',         '⏱️', false, 7)
  ) as t(clave, texto, icono, positiva, orden)
  loop
    if not exists (select 1 from public.opciones_opinion where clave = r.clave) then
      insert into public.opciones_opinion (clave, texto, icono, positiva, orden)
      values (r.clave, r.texto, r.icono, r.positiva, r.orden);
    end if;
  end loop;
end $$;

-- La opinión de cada persona sobre cada clase
create table if not exists public.opiniones_clase (
  id uuid primary key default gen_random_uuid(),
  clase_id uuid references public.clases(id) on delete cascade,
  curso_id uuid references public.cursos(id) on delete cascade,
  usuario_id uuid references auth.users(id) on delete cascade,
  opciones text[],
  comentario text,
  creado_en timestamptz default now()
);

create unique index if not exists opinion_unica on public.opiniones_clase (clase_id, usuario_id);

alter table public.opiniones_clase enable row level security;

-- Cada una ve la suya; el equipo ve todas
drop policy if exists "Ver mi opinión" on public.opiniones_clase;
create policy "Ver mi opinión"
  on public.opiniones_clase for select
  using (auth.uid() = usuario_id or public.es_equipo());

drop policy if exists "Dejar mi opinión" on public.opiniones_clase;
create policy "Dejar mi opinión"
  on public.opiniones_clase for insert with check (auth.uid() = usuario_id);

drop policy if exists "Cambiar mi opinión" on public.opiniones_clase;
create policy "Cambiar mi opinión"
  on public.opiniones_clase for update using (auth.uid() = usuario_id);

-- ─── Cómo viene cada clase ───
drop view if exists public.salud_clases;
create view public.salud_clases as
select
  cl.id            as clase_id,
  cl.titulo        as clase_titulo,
  cu.id            as curso_id,
  cu.titulo        as curso_titulo,
  count(o.id)      as total_opiniones,
  count(*) filter (where o.comentario is not null and o.comentario <> '') as con_comentario,
  coalesce(sum((
    select count(*) from unnest(o.opciones) x
    join public.opciones_opinion oo on oo.clave = x
    where oo.positiva
  )), 0) as senales_buenas,
  coalesce(sum((
    select count(*) from unnest(o.opciones) x
    join public.opciones_opinion oo on oo.clave = x
    where not oo.positiva
  )), 0) as senales_mejora
from public.clases cl
join public.cursos cu on cu.id = cl.curso_id
left join public.opiniones_clase o on o.clase_id = cl.id
group by cl.id, cl.titulo, cu.id, cu.titulo;

grant select on public.salud_clases to authenticated;

-- ═══════════════════ 3. INVITACIONES ═══════════════════════════════
create table if not exists public.invitaciones (
  id uuid primary key default gen_random_uuid(),
  email text not null,
  nombre text,
  codigo text unique not null,
  cursos uuid[],
  premium_meses int default 0,
  mensaje text,
  usada boolean default false,
  usada_en timestamptz,
  usuario_id uuid references auth.users(id) on delete set null,
  vence timestamptz default (now() + interval '30 days'),
  creada_por uuid references auth.users(id) on delete set null,
  creado_en timestamptz default now()
);

create index if not exists invit_codigo on public.invitaciones (codigo);
create index if not exists invit_email on public.invitaciones (lower(email));

alter table public.invitaciones enable row level security;

-- Cualquiera puede leer una invitación con su código (para poder usarla)
drop policy if exists "Leer invitación por código" on public.invitaciones;
create policy "Leer invitación por código"
  on public.invitaciones for select using (true);

drop policy if exists "Equipo crea invitaciones" on public.invitaciones;
create policy "Equipo crea invitaciones"
  on public.invitaciones for insert with check (public.es_equipo());

drop policy if exists "Equipo edita invitaciones" on public.invitaciones;
create policy "Equipo edita invitaciones"
  on public.invitaciones for update using (public.es_equipo());

drop policy if exists "Equipo borra invitaciones" on public.invitaciones;
create policy "Equipo borra invitaciones"
  on public.invitaciones for delete using (public.es_equipo());

-- ─── Canjear la invitación ─────────────────────────────────────────
create or replace function public.canjear_invitacion(p_codigo text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_inv record;
  v_uid uuid;
  v_curso uuid;
  v_dias int;
  v_dados int := 0;
begin
  v_uid := auth.uid();
  if v_uid is null then
    return jsonb_build_object('exito', false, 'error', 'Tenés que iniciar sesión primero');
  end if;

  select * into v_inv from public.invitaciones where codigo = p_codigo;

  if v_inv is null then
    return jsonb_build_object('exito', false, 'error', 'Esta invitación no existe');
  end if;
  if v_inv.usada then
    return jsonb_build_object('exito', false, 'error', 'Esta invitación ya fue usada');
  end if;
  if v_inv.vence < now() then
    return jsonb_build_object('exito', false, 'error', 'Esta invitación venció');
  end if;

  -- Los cursos
  foreach v_curso in array coalesce(v_inv.cursos, array[]::uuid[])
  loop
    select case when tipo_acceso = 'dias' then dias_acceso else null end
      into v_dias from public.cursos where id = v_curso;

    if not exists (
      select 1 from public.compras
      where usuario_id = v_uid and curso_id = v_curso and estado = 'pagado'
    ) then
      insert into public.compras (usuario_id, curso_id, monto_gs, estado, metodo_pago, pagado_en)
      values (v_uid, v_curso, 0, 'pagado', 'invitacion', now());
      v_dados := v_dados + 1;
    end if;
  end loop;

  -- El premium
  if coalesce(v_inv.premium_meses, 0) > 0 then
    insert into public.suscripciones (usuario_id, estado, inicio, vence, monto_gs, metodo_pago, notas)
    values (v_uid, 'activa', now(),
            now() + (v_inv.premium_meses || ' months')::interval,
            0, 'invitacion', 'Otorgado por invitación');
  end if;

  update public.invitaciones
  set usada = true, usada_en = now(), usuario_id = v_uid
  where id = v_inv.id;

  return jsonb_build_object(
    'exito', true,
    'cursos', v_dados,
    'premium_meses', coalesce(v_inv.premium_meses, 0)
  );
end;
$$;

grant execute on function public.canjear_invitacion(text) to authenticated;

-- ─── VERIFICACIÓN ──────────────────────────────────────────────────
select 'listo' as estado,
  (select count(*) from public.opciones_opinion) as opciones_de_opinion,
  (select count(*) from public.invitaciones) as invitaciones,
  (select count(*) from public.comentarios_clase) as comentarios;
