-- ═══════════════════════════════════════════════════════════════════
-- MODERACIÓN AUTOMÁTICA
-- Una denuncia oculta el post y deja al autor en revisión,
-- hasta que el equipo lo apruebe o lo elimine.
-- Correr DESPUÉS de SQL-GENERO-Y-DENUNCIAS.sql
-- ═══════════════════════════════════════════════════════════════════

-- ─── 1. Estado "en revisión" del perfil ────────────────────────────
alter table public.perfiles add column if not exists en_revision boolean default false;
update public.perfiles set en_revision = false where en_revision is null;

-- Contadores acumulados (para las métricas del panel)
alter table public.perfiles add column if not exists denuncias_recibidas int default 0;
update public.perfiles set denuncias_recibidas = 0 where denuncias_recibidas is null;

-- ─── 2. Al recibir una denuncia: ocultar y poner en revisión ───────
create or replace function public.al_denunciar()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  autor uuid;
begin
  if new.post_id is not null then
    update public.posts
      set oculto = true
      where id = new.post_id
      returning usuario_id into autor;

    if autor is not null then
      update public.perfiles
        set en_revision = true,
            denuncias_recibidas = coalesce(denuncias_recibidas, 0) + 1
        where id = autor;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_al_denunciar on public.denuncias;
create trigger trg_al_denunciar
  after insert on public.denuncias
  for each row execute function public.al_denunciar();

-- ─── 3. Quien está en revisión o bloqueado no puede publicar ───────
create or replace function public.puede_publicar()
returns boolean
language sql
security definer
set search_path = public
as $$
  select coalesce(
    (select not coalesce(bloqueado, false) and not coalesce(en_revision, false)
     from public.perfiles where id = auth.uid()),
    false
  );
$$;

grant execute on function public.puede_publicar() to authenticated;

-- ─── 4. Función para que el equipo apruebe un post ─────────────────
-- Muestra el post de nuevo, marca las denuncias como revisadas
-- y libera al autor.
create or replace function public.aprobar_post(p_post_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  autor uuid;
begin
  if not public.es_equipo() then
    raise exception 'Solo el equipo puede aprobar publicaciones';
  end if;

  update public.posts
    set oculto = false
    where id = p_post_id
    returning usuario_id into autor;

  update public.denuncias
    set estado = 'descartada', revisado_en = now()
    where post_id = p_post_id and estado = 'pendiente';

  if autor is not null then
    -- Solo lo liberamos si no le quedan otras denuncias pendientes
    if not exists (
      select 1 from public.denuncias d
      join public.posts p on p.id = d.post_id
      where p.usuario_id = autor and d.estado = 'pendiente'
    ) then
      update public.perfiles set en_revision = false where id = autor;
    end if;
  end if;
end;
$$;

grant execute on function public.aprobar_post(uuid) to authenticated;

-- ─── 5. Función para confirmar la denuncia (post queda oculto) ─────
create or replace function public.confirmar_denuncia(p_post_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.es_equipo() then
    raise exception 'Solo el equipo puede moderar';
  end if;

  update public.posts set oculto = true where id = p_post_id;

  update public.denuncias
    set estado = 'confirmada', revisado_en = now()
    where post_id = p_post_id and estado = 'pendiente';
end;
$$;

grant execute on function public.confirmar_denuncia(uuid) to authenticated;

-- ─── 6. Liberar a un autor manualmente ─────────────────────────────
create or replace function public.liberar_autor(p_usuario_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.es_equipo() then
    raise exception 'Solo el equipo puede hacer esto';
  end if;
  update public.perfiles set en_revision = false where id = p_usuario_id;
end;
$$;

grant execute on function public.liberar_autor(uuid) to authenticated;

-- ─── VERIFICACIÓN ──────────────────────────────────────────────────
select column_name from information_schema.columns
where table_schema='public' and table_name='perfiles'
  and column_name in ('en_revision','bloqueado','denuncias_recibidas','genero');
