-- ═══════════════════════════════════════════════════════════════════
-- EL CAMINO DE CADA PERSONA
--
-- Registra los pasos: se registró, miró un curso, tocó comprar,
-- llegó al checkout, hizo el pedido, compró.
-- Así ves quién se interesó y se quedó en el camino.
-- ═══════════════════════════════════════════════════════════════════

create table if not exists public.eventos (
  id bigserial primary key,
  usuario_id uuid references auth.users(id) on delete cascade,
  tipo text not null,          -- registro · vio_curso · vio_checkout · clic_comprar · pedido · compra
  curso_id uuid references public.cursos(id) on delete set null,
  detalle text,
  creado_en timestamptz default now()
);

create index if not exists eventos_usuario on public.eventos (usuario_id, creado_en desc);
create index if not exists eventos_tipo on public.eventos (tipo, creado_en desc);
create index if not exists eventos_curso on public.eventos (curso_id, tipo);

alter table public.eventos enable row level security;

drop policy if exists "Anotar mi paso" on public.eventos;
create policy "Anotar mi paso"
  on public.eventos for insert
  with check (auth.uid() = usuario_id);

drop policy if exists "Equipo ve los caminos" on public.eventos;
create policy "Equipo ve los caminos"
  on public.eventos for select
  using (public.es_equipo() or auth.uid() = usuario_id);

drop policy if exists "Equipo limpia eventos" on public.eventos;
create policy "Equipo limpia eventos"
  on public.eventos for delete using (public.es_equipo());

-- ─── Anotar un paso, sin repetir el mismo en poco tiempo ───────────
create or replace function public.anotar_paso(
  p_tipo text,
  p_curso uuid default null,
  p_detalle text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_uid uuid;
begin
  v_uid := auth.uid();
  if v_uid is null then return; end if;

  -- Si ya anotamos lo mismo hace menos de 10 minutos, no lo repetimos
  if exists (
    select 1 from public.eventos
    where usuario_id = v_uid
      and tipo = p_tipo
      and coalesce(curso_id::text, '') = coalesce(p_curso::text, '')
      and creado_en > now() - interval '10 minutes'
  ) then
    return;
  end if;

  insert into public.eventos (usuario_id, tipo, curso_id, detalle)
  values (v_uid, p_tipo, p_curso, p_detalle);
end;
$$;

grant execute on function public.anotar_paso(text, uuid, text) to authenticated;

-- ─── El registro se anota solo ─────────────────────────────────────
create or replace function public.anotar_registro()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.eventos (usuario_id, tipo, detalle)
  values (new.id, 'registro', 'Se creó la cuenta');
  return new;
end;
$$;

drop trigger if exists trg_anotar_registro on public.perfiles;
create trigger trg_anotar_registro
  after insert on public.perfiles
  for each row execute function public.anotar_registro();

-- ═══════════════════════════════════════════════════════════════════
-- EL EMBUDO: cuántas personas llegaron a cada paso
-- ═══════════════════════════════════════════════════════════════════

drop view if exists public.embudo;
create view public.embudo as
select
  (select count(*) from public.perfiles)                                        as registradas,
  (select count(distinct usuario_id) from public.eventos where tipo = 'vio_curso')     as miraron_curso,
  (select count(distinct usuario_id) from public.eventos where tipo = 'clic_comprar')  as tocaron_comprar,
  (select count(distinct usuario_id) from public.eventos where tipo = 'vio_checkout')  as llegaron_al_pago,
  (select count(distinct usuario_id) from public.pedidos)                              as hicieron_pedido,
  (select count(distinct usuario_id) from public.compras where estado = 'pagado')      as compraron;

grant select on public.embudo to authenticated;

-- ═══════════════════════════════════════════════════════════════════
-- QUIÉNES SE INTERESARON Y NO COMPRARON
-- Esta es la lista para escribirles
-- ═══════════════════════════════════════════════════════════════════

drop view if exists public.interesadas_sin_comprar;
create view public.interesadas_sin_comprar as
select
  p.id            as usuario_id,
  p.nombre,
  p.email,
  p.avatar_url,
  c.id            as curso_id,
  c.titulo        as curso_titulo,
  c.slug          as curso_slug,
  c.precio_gs,
  max(e.creado_en) as ultimo_paso,
  extract(day from (now() - max(e.creado_en)))::int as dias_desde,
  -- Hasta dónde llegó
  max(case e.tipo
    when 'vio_curso'    then 1
    when 'clic_comprar' then 2
    when 'vio_checkout' then 3
    else 0
  end) as hasta_donde,
  string_agg(distinct e.tipo, ',') as pasos
from public.eventos e
join public.perfiles p on p.id = e.usuario_id
join public.cursos c   on c.id = e.curso_id
where e.tipo in ('vio_curso', 'clic_comprar', 'vio_checkout')
  -- Que no lo haya comprado
  and not exists (
    select 1 from public.compras co
    where co.usuario_id = e.usuario_id and co.curso_id = e.curso_id and co.estado = 'pagado'
  )
  -- Ni tenga un pedido pendiente (ese ya está en otra lista)
  and not exists (
    select 1 from public.pedidos pe
    where pe.usuario_id = e.usuario_id and pe.curso_id = e.curso_id and pe.estado = 'pendiente'
  )
group by p.id, p.nombre, p.email, p.avatar_url, c.id, c.titulo, c.slug, c.precio_gs
order by max(case e.tipo
    when 'vio_curso' then 1 when 'clic_comprar' then 2 when 'vio_checkout' then 3 else 0
  end) desc, max(e.creado_en) desc;

grant select on public.interesadas_sin_comprar to authenticated;

-- ═══════════════════════════════════════════════════════════════════
-- EL CAMINO DE UNA PERSONA
-- ═══════════════════════════════════════════════════════════════════

create or replace function public.camino_de(p_usuario uuid)
returns table (
  c_tipo text,
  c_detalle text,
  c_curso text,
  c_cuando timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select e.tipo, e.detalle, c.titulo, e.creado_en
  from public.eventos e
  left join public.cursos c on c.id = e.curso_id
  where e.usuario_id = p_usuario
    and (public.es_equipo() or auth.uid() = p_usuario)
  order by e.creado_en desc
  limit 60;
$$;

grant execute on function public.camino_de(uuid) to authenticated;

-- ═══════════════════════════════════════════════════════════════════
-- CUÁNTO CONVIERTE CADA CURSO
-- ═══════════════════════════════════════════════════════════════════

drop view if exists public.interes_por_curso;
create view public.interes_por_curso as
select
  c.id,
  c.titulo,
  c.precio_gs,
  count(distinct e.usuario_id) filter (where e.tipo = 'vio_curso')    as miraron,
  count(distinct e.usuario_id) filter (where e.tipo = 'clic_comprar') as tocaron_comprar,
  count(distinct co.usuario_id) filter (where co.estado = 'pagado')   as compraron
from public.cursos c
left join public.eventos e on e.curso_id = c.id
left join public.compras co on co.curso_id = c.id
where c.publicado
group by c.id, c.titulo, c.precio_gs, c.orden
order by count(distinct e.usuario_id) filter (where e.tipo = 'vio_curso') desc;

grant select on public.interes_por_curso to authenticated;

-- ─── VERIFICACIÓN ──────────────────────────────────────────────────
select * from public.embudo;
