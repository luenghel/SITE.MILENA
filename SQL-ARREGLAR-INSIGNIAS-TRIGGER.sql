-- ═══════════════════════════════════════════════════════════════════
-- ARREGLAR EL ERROR AL PUBLICAR
--
--   record "new" has no field "post_id"
--
-- El disparador de insignias leía campos que no existen en todas
-- las tablas. Ahora lee de forma segura, sin importar la tabla.
-- ═══════════════════════════════════════════════════════════════════

create or replace function public.revisar_insignias_auto()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_fila jsonb;
  v_usuario uuid;
  v_post uuid;
  v_autor uuid;
begin
  -- Leemos la fila como JSON: así podemos pedir cualquier campo
  -- sin que falle si esa tabla no lo tiene
  v_fila := to_jsonb(new);

  -- De quién son las insignias a revisar
  if tg_table_name = 'perfiles' then
    v_usuario := (v_fila->>'id')::uuid;
  else
    v_usuario := nullif(v_fila->>'usuario_id', '')::uuid;
  end if;

  if v_usuario is null then
    return new;
  end if;

  perform public.otorgar_insignias(v_usuario);

  -- Si fue un like, también revisamos a quien lo recibió:
  -- puede haber llegado a "100 likes en un post"
  if tg_table_name = 'likes' then
    v_post := nullif(v_fila->>'post_id', '')::uuid;

    if v_post is not null then
      select usuario_id into v_autor from public.posts where id = v_post;
      if v_autor is not null and v_autor <> v_usuario then
        perform public.otorgar_insignias(v_autor);
      end if;
    end if;
  end if;

  return new;
exception
  when others then
    -- Las insignias nunca deben impedir publicar, comentar o comprar
    return new;
end;
$$;

-- ─── Volvemos a colgar los disparadores ────────────────────────────
drop trigger if exists trg_insignias_registro on public.perfiles;
create trigger trg_insignias_registro
  after insert on public.perfiles
  for each row execute function public.revisar_insignias_auto();

drop trigger if exists trg_insignias_post on public.posts;
create trigger trg_insignias_post
  after insert on public.posts
  for each row execute function public.revisar_insignias_auto();

drop trigger if exists trg_insignias_comentario on public.comentarios;
create trigger trg_insignias_comentario
  after insert on public.comentarios
  for each row execute function public.revisar_insignias_auto();

drop trigger if exists trg_insignias_like on public.likes;
create trigger trg_insignias_like
  after insert on public.likes
  for each row execute function public.revisar_insignias_auto();

drop trigger if exists trg_insignias_compra on public.compras;
create trigger trg_insignias_compra
  after insert or update of estado on public.compras
  for each row execute function public.revisar_insignias_auto();

drop trigger if exists trg_insignias_progreso on public.progreso;
create trigger trg_insignias_progreso
  after insert on public.progreso
  for each row execute function public.revisar_insignias_auto();

-- ─── Lo mismo con el del camino, por las dudas ─────────────────────
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
exception
  when others then
    return new;
end;
$$;

-- ─── VERIFICACIÓN ──────────────────────────────────────────────────
select
  tgname as disparador,
  tgrelid::regclass as tabla
from pg_trigger
where tgname like 'trg_insignias%'
order by tgname;
