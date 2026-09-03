-- ═══════════════════════════════════════════════════════════════════
-- ENLACES LINDOS PARA LAS CLASES
--
--   Antes:  /clase?curso=cmm&clase=d1acb8ba-3a68-487f-b0fd-0d658e51bb19
--   Ahora:  /clase?curso=cmm&c=3
--
-- Cada clase tiene un número dentro de su curso, que no cambia
-- aunque reordenes o borres otras.
-- ═══════════════════════════════════════════════════════════════════

alter table public.clases add column if not exists numero int;

-- ─── Numeramos las que ya existen ──────────────────────────────────
with ordenadas as (
  select
    cl.id,
    row_number() over (
      partition by cl.curso_id
      order by m.orden, cl.orden, cl.creado_en
    ) as n
  from public.clases cl
  join public.modulos m on m.id = cl.modulo_id
)
update public.clases c
set numero = o.n
from ordenadas o
where c.id = o.id and c.numero is null;

-- Un número por curso, sin repetir
create unique index if not exists clase_numero_unico
  on public.clases (curso_id, numero) where numero is not null;

-- ─── A las nuevas se les asigna solo ───────────────────────────────
create or replace function public.numerar_clase()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.numero is null then
    select coalesce(max(numero), 0) + 1 into new.numero
    from public.clases where curso_id = new.curso_id;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_numerar_clase on public.clases;
create trigger trg_numerar_clase
  before insert on public.clases
  for each row execute function public.numerar_clase();

-- ─── VERIFICACIÓN ──────────────────────────────────────────────────
select
  cu.slug as curso,
  cl.numero,
  cl.titulo,
  '/clase?curso=' || cu.slug || '&c=' || cl.numero as enlace
from public.clases cl
join public.cursos cu on cu.id = cl.curso_id
order by cu.slug, cl.numero;
