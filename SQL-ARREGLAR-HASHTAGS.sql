-- ═══════════════════════════════════════════════════════════════════
-- ARREGLAR EL BORRADO DE ETIQUETAS
--
-- El problema: faltaba el permiso para borrar. Supabase no avisa
-- cuando la seguridad bloquea un DELETE: borra cero filas y listo.
-- Por eso decía "eliminada" y al recargar volvía.
-- ═══════════════════════════════════════════════════════════════════

-- Por si la tabla no existiera
create table if not exists public.hashtags (
  id uuid primary key default gen_random_uuid(),
  nombre text unique not null,
  activo boolean default true,
  creado_en timestamptz default now()
);

alter table public.hashtags enable row level security;

-- ─── Los permisos, completos ───────────────────────────────────────
drop policy if exists "Etiquetas visibles" on public.hashtags;
drop policy if exists "Hashtags visibles" on public.hashtags;
drop policy if exists "Ver hashtags" on public.hashtags;
create policy "Etiquetas visibles"
  on public.hashtags for select using (true);

drop policy if exists "Equipo crea etiquetas" on public.hashtags;
create policy "Equipo crea etiquetas"
  on public.hashtags for insert with check (public.es_equipo());

drop policy if exists "Equipo edita etiquetas" on public.hashtags;
create policy "Equipo edita etiquetas"
  on public.hashtags for update using (public.es_equipo());

-- Este era el que faltaba
drop policy if exists "Equipo borra etiquetas" on public.hashtags;
create policy "Equipo borra etiquetas"
  on public.hashtags for delete using (public.es_equipo());

-- ─── Borrar de verdad, y avisar si no se pudo ──────────────────────
create or replace function public.borrar_etiqueta(p_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nombre text;
  v_n int;
begin
  if not public.es_equipo() then
    return jsonb_build_object('exito', false, 'error', 'Solo el equipo puede borrar etiquetas');
  end if;

  select nombre into v_nombre from public.hashtags where id = p_id;

  if v_nombre is null then
    return jsonb_build_object('exito', false, 'error', 'Esa etiqueta ya no existe');
  end if;

  delete from public.hashtags where id = p_id;
  get diagnostics v_n = row_count;

  if v_n = 0 then
    return jsonb_build_object('exito', false, 'error', 'No se pudo borrar');
  end if;

  return jsonb_build_object('exito', true, 'nombre', v_nombre);
end;
$$;

grant execute on function public.borrar_etiqueta(uuid) to authenticated;

-- ─── La vista de uso, con el nombre de columna correcto ────────────
drop view if exists public.uso_hashtags;
create view public.uso_hashtags as
select
  h.id,
  h.nombre as tag,
  h.activo,
  count(p.id) filter (where p.creado_en > now() - interval '7 days')  as posts_semana,
  count(p.id) filter (where p.creado_en > now() - interval '30 days') as posts_mes,
  count(p.id) as posts_total,
  max(p.creado_en) as ultimo_uso
from public.hashtags h
left join public.posts p on p.hashtags @> array[h.nombre]
group by h.id, h.nombre, h.activo;

grant select on public.uso_hashtags to authenticated;

-- ─── VERIFICACIÓN ──────────────────────────────────────────────────
select
  'listo' as estado,
  (select count(*) from public.hashtags) as etiquetas,
  (select count(*) from pg_policies
   where tablename = 'hashtags' and cmd = 'DELETE') as permiso_de_borrar;

select nombre, activo from public.hashtags order by nombre;
