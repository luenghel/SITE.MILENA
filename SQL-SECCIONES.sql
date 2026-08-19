-- ═══════════════════════════════════════════════════════════════════
-- FILAS DEL CATÁLOGO, EDITABLES
-- En vez de las 3 fijas, creás las que quieras y las ordenás.
-- ═══════════════════════════════════════════════════════════════════

create table if not exists public.secciones (
  id uuid primary key default gen_random_uuid(),
  clave text unique not null,
  nombre text not null,
  subtitulo text,
  etiqueta text,                    -- ej: "GRATIS", "NUEVO"
  color_etiqueta text,
  orden int default 0,
  activa boolean default true,
  mostrar_home boolean default true,
  mostrar_catalogo boolean default true,
  creado_en timestamptz default now()
);

alter table public.secciones enable row level security;

drop policy if exists "Secciones visibles" on public.secciones;
create policy "Secciones visibles"
  on public.secciones for select using (true);

drop policy if exists "Equipo crea secciones" on public.secciones;
create policy "Equipo crea secciones"
  on public.secciones for insert with check (public.es_equipo());

drop policy if exists "Equipo edita secciones" on public.secciones;
create policy "Equipo edita secciones"
  on public.secciones for update using (public.es_equipo());

drop policy if exists "Equipo borra secciones" on public.secciones;
create policy "Equipo borra secciones"
  on public.secciones for delete using (public.es_equipo());

-- ─── Las que ya venían ─────────────────────────────────────────────
do $$
declare
  r record;
begin
  for r in
    select * from (values
      ('principal', 'Marketing Digital',    null::text,                      null::text,     null::text,     1),
      ('acompana',  'Acompañá más',         null::text,                      null::text,     null::text,     2),
      ('gratis',    'Contenidos gratuitos', null::text,                      'GRATIS',       '#5DCAA5',      3)
    ) as t(clave, nombre, subtitulo, etiqueta, color_etiqueta, orden)
  loop
    if not exists (select 1 from public.secciones where clave = r.clave) then
      insert into public.secciones (clave, nombre, subtitulo, etiqueta, color_etiqueta, orden)
      values (r.clave, r.nombre, r.subtitulo, r.etiqueta, r.color_etiqueta, r.orden);
    end if;
  end loop;
end $$;

-- ─── Los cursos que ya tenías conservan su fila ────────────────────
update public.cursos set seccion = 'principal'
where seccion is null or seccion not in (select clave from public.secciones)
  and seccion <> 'oculto';

-- ─── VERIFICACIÓN ──────────────────────────────────────────────────
select
  s.orden, s.clave, s.nombre,
  coalesce(s.etiqueta, '—') as etiqueta,
  (select count(*) from public.cursos c where c.seccion = s.clave and c.publicado) as cursos_publicados
from public.secciones s
order by s.orden;
