-- ═══════════════════════════════════════════════════════════════════
-- MODERACIÓN AVANZADA
--   · Denuncias con gravedad (las graves ocultan y restringen al toque)
--   · Enlaces con aprobación previa
--   · Métricas de participación por miembro
-- Correr DESPUÉS de SQL-GENERO-Y-DENUNCIAS.sql
-- ═══════════════════════════════════════════════════════════════════

-- ─── 1. COLUMNAS NUEVAS ────────────────────────────────────────────
alter table public.posts add column if not exists pendiente_aprobacion boolean default false;
alter table public.posts add column if not exists tiene_enlace boolean default false;
alter table public.posts add column if not exists motivo_ocultado text;

alter table public.comentarios add column if not exists oculto boolean default false;
alter table public.comentarios add column if not exists pendiente_aprobacion boolean default false;
alter table public.comentarios add column if not exists tiene_enlace boolean default false;

alter table public.denuncias add column if not exists gravedad text default 'normal';
alter table public.denuncias add column if not exists accion_tomada text;

alter table public.perfiles add column if not exists motivo_bloqueo text;
alter table public.perfiles add column if not exists bloqueado_en timestamptz;

update public.posts set pendiente_aprobacion = false where pendiente_aprobacion is null;
update public.posts set tiene_enlace = false where tiene_enlace is null;
update public.comentarios set oculto = false where oculto is null;
update public.comentarios set pendiente_aprobacion = false where pendiente_aprobacion is null;

-- ─── 2. TRIGGER: una denuncia grave oculta y restringe al instante ──
create or replace function public.procesar_denuncia()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  autor uuid;
  nivel text;
begin
  -- Gravedad según el motivo
  if new.motivo in ('sexual', 'violencia', 'odio') then
    nivel := 'critica';
  elsif new.motivo in ('acoso', 'fraude', 'ilegal', 'autolesion', 'menores') then
    nivel := 'alta';
  else
    nivel := 'normal';
  end if;

  new.gravedad := nivel;

  if new.post_id is null then
    return new;
  end if;

  select usuario_id into autor from public.posts where id = new.post_id;

  -- CRÍTICA: se oculta el post y se restringe a quien lo publicó
  if nivel = 'critica' then
    update public.posts
      set oculto = true, motivo_ocultado = new.motivo
      where id = new.post_id;

    if autor is not null then
      update public.perfiles
        set bloqueado = true,
            motivo_bloqueo = 'Denuncia por ' || new.motivo || ' (pendiente de revisión)',
            bloqueado_en = now()
        where id = autor;
    end if;

    new.accion_tomada := 'post_oculto_y_autor_restringido';

  -- ALTA: se oculta el post, pero no se restringe a la persona
  elsif nivel = 'alta' then
    update public.posts
      set oculto = true, motivo_ocultado = new.motivo
      where id = new.post_id;

    new.accion_tomada := 'post_oculto';

  -- NORMAL: solo queda en la cola de revisión
  else
    new.accion_tomada := 'en_revision';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_procesar_denuncia on public.denuncias;
create trigger trg_procesar_denuncia
  before insert on public.denuncias
  for each row execute function public.procesar_denuncia();

-- ─── 3. VISIBILIDAD: ocultos y pendientes no se muestran ───────────
drop policy if exists "Posts visibles para logueados" on public.posts;
create policy "Posts visibles para logueados"
  on public.posts for select
  using (
    auth.uid() is not null
    and (
      (coalesce(oculto, false) = false and coalesce(pendiente_aprobacion, false) = false)
      or public.es_equipo()
      or usuario_id = auth.uid()      -- el autor siempre ve lo suyo
    )
  );

drop policy if exists "Comentarios visibles" on public.comentarios;
create policy "Comentarios visibles"
  on public.comentarios for select
  using (
    auth.uid() is not null
    and (
      (coalesce(oculto, false) = false and coalesce(pendiente_aprobacion, false) = false)
      or public.es_equipo()
      or usuario_id = auth.uid()
    )
  );

-- ─── 4. Que el equipo pueda aprobar comentarios ────────────────────
drop policy if exists "Equipo modera comentarios" on public.comentarios;
create policy "Equipo modera comentarios"
  on public.comentarios for update
  using (public.es_equipo());

-- ─── 5. MÉTRICAS DE PARTICIPACIÓN POR MIEMBRO ──────────────────────
create or replace view public.metricas_miembros as
select
  p.id,
  p.nombre,
  p.email,
  p.rol,
  p.genero,
  p.avatar_url,
  p.bloqueado,
  p.motivo_bloqueo,
  p.creado_en,
  (select count(*) from public.posts        x where x.usuario_id = p.id) as posts,
  (select count(*) from public.comentarios  x where x.usuario_id = p.id) as comentarios,
  (select count(*) from public.likes        x where x.usuario_id = p.id) as likes_dados,
  (select count(*) from public.denuncias    x where x.denunciante_id = p.id) as denuncias_hechas,
  (select count(*) from public.denuncias    d
     join public.posts po on po.id = d.post_id
     where po.usuario_id = p.id) as denuncias_recibidas,
  (select count(*) from public.likes l
     join public.posts po on po.id = l.post_id
     where po.usuario_id = p.id) as likes_recibidos,
  (select count(*) from public.compras c
     where c.usuario_id = p.id and c.estado = 'pagado') as cursos_comprados
from public.perfiles p;

grant select on public.metricas_miembros to authenticated;

-- ─── VERIFICACIÓN ──────────────────────────────────────────────────
select 'listo' as estado,
  (select count(*) from information_schema.columns
   where table_schema='public' and table_name='posts'
     and column_name in ('pendiente_aprobacion','tiene_enlace','motivo_ocultado')) as columnas_posts;
