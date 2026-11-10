-- ═══════════════════════════════════════════════════════════════════
-- EDITAR PUBLICACIONES DE LA COMUNIDAD
--
-- Cada una puede corregir lo suyo. Queda marcado como "editado"
-- para que se note que cambió.
-- ═══════════════════════════════════════════════════════════════════

alter table public.posts add column if not exists editado_en timestamptz;

-- ─── Solo puede editar lo suyo ─────────────────────────────────────
drop policy if exists "Editar mi post" on public.posts;
drop policy if exists "Actualizar posts" on public.posts;
drop policy if exists "Equipo edita posts" on public.posts;

create policy "Editar mi post"
  on public.posts for update
  using (auth.uid() = usuario_id or public.es_equipo())
  with check (auth.uid() = usuario_id or public.es_equipo());

-- ─── Nadie puede cambiar de autor una publicación ──────────────────
create or replace function public.proteger_autor_post()
returns trigger
language plpgsql
as $$
begin
  -- El autor y la fecha original no se tocan
  new.usuario_id := old.usuario_id;
  new.creado_en  := old.creado_en;

  -- Si cambió el contenido, lo marcamos como editado
  if (new.contenido is distinct from old.contenido)
     or (new.imagen_url is distinct from old.imagen_url)
     or (new.hashtags is distinct from old.hashtags)
     or (new.categoria is distinct from old.categoria) then
    new.editado_en := now();
  end if;

  return new;
end;
$$;

drop trigger if exists trg_proteger_autor_post on public.posts;
create trigger trg_proteger_autor_post
  before update on public.posts
  for each row execute function public.proteger_autor_post();

-- ─── VERIFICACIÓN ──────────────────────────────────────────────────
select
  'listo' as estado,
  (select count(*) from information_schema.columns
     where table_schema = 'public' and table_name = 'posts'
       and column_name = 'editado_en') as columna_editado,
  (select count(*) from pg_policies
     where tablename = 'posts' and cmd = 'UPDATE') as permiso_editar;
