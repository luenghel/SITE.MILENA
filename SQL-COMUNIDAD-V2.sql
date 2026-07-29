-- ═══════════════════════════════════════════════════════════════════
-- COMUNIDAD CMM - VERSION 2 (se adapta a las tablas que ya existen)
-- Seguro de ejecutar aunque el SQL anterior haya fallado a la mitad
-- ═══════════════════════════════════════════════════════════════════

-- ─── PASO 1: crear las tablas si no existen ────────────────────────
create table if not exists public.posts (
  id uuid primary key default gen_random_uuid()
);

create table if not exists public.likes (
  id uuid primary key default gen_random_uuid()
);

create table if not exists public.comentarios (
  id uuid primary key default gen_random_uuid()
);

-- ─── PASO 2: normalizar nombres de columnas ────────────────────────
-- Si la columna existe con otro nombre, la renombra.
-- Si no existe de ninguna forma, la crea.

do $$
declare
  t text;
  candidatos text[];
  c text;
  encontrada boolean;
begin
  -- ══ usuario_id en posts, likes y comentarios ══
  foreach t in array array['posts','likes','comentarios'] loop
    if not exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name=t and column_name='usuario_id'
    ) then
      encontrada := false;
      candidatos := array['autor_id','user_id','author_id','perfil_id','usuario','id_usuario'];
      foreach c in array candidatos loop
        if not encontrada and exists (
          select 1 from information_schema.columns
          where table_schema='public' and table_name=t and column_name=c
        ) then
          execute format('alter table public.%I rename column %I to usuario_id', t, c);
          encontrada := true;
        end if;
      end loop;
      if not encontrada then
        execute format('alter table public.%I add column usuario_id uuid references auth.users(id) on delete cascade', t);
      end if;
    end if;
  end loop;

  -- ══ post_id en likes y comentarios ══
  foreach t in array array['likes','comentarios'] loop
    if not exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name=t and column_name='post_id'
    ) then
      encontrada := false;
      candidatos := array['publicacion_id','id_post','post'];
      foreach c in array candidatos loop
        if not encontrada and exists (
          select 1 from information_schema.columns
          where table_schema='public' and table_name=t and column_name=c
        ) then
          execute format('alter table public.%I rename column %I to post_id', t, c);
          encontrada := true;
        end if;
      end loop;
      if not encontrada then
        execute format('alter table public.%I add column post_id uuid references public.posts(id) on delete cascade', t);
      end if;
    end if;
  end loop;

  -- ══ contenido en posts y comentarios ══
  foreach t in array array['posts','comentarios'] loop
    if not exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name=t and column_name='contenido'
    ) then
      encontrada := false;
      candidatos := array['texto','content','body','mensaje','descripcion'];
      foreach c in array candidatos loop
        if not encontrada and exists (
          select 1 from information_schema.columns
          where table_schema='public' and table_name=t and column_name=c
        ) then
          execute format('alter table public.%I rename column %I to contenido', t, c);
          encontrada := true;
        end if;
      end loop;
      if not encontrada then
        execute format('alter table public.%I add column contenido text', t);
      end if;
    end if;
  end loop;

  -- ══ creado_en en las tres tablas ══
  foreach t in array array['posts','likes','comentarios'] loop
    if not exists (
      select 1 from information_schema.columns
      where table_schema='public' and table_name=t and column_name='creado_en'
    ) then
      encontrada := false;
      candidatos := array['created_at','fecha','fecha_creacion','creado'];
      foreach c in array candidatos loop
        if not encontrada and exists (
          select 1 from information_schema.columns
          where table_schema='public' and table_name=t and column_name=c
        ) then
          execute format('alter table public.%I rename column %I to creado_en', t, c);
          encontrada := true;
        end if;
      end loop;
      if not encontrada then
        execute format('alter table public.%I add column creado_en timestamptz default now()', t);
      end if;
    end if;
  end loop;

  -- ══ imagen_url en posts ══
  if not exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='posts' and column_name='imagen_url'
  ) then
    encontrada := false;
    candidatos := array['imagen','image_url','foto_url','foto'];
    foreach c in array candidatos loop
      if not encontrada and exists (
        select 1 from information_schema.columns
        where table_schema='public' and table_name='posts' and column_name=c
      ) then
        execute format('alter table public.posts rename column %I to imagen_url', c);
        encontrada := true;
      end if;
    end loop;
    if not encontrada then
      alter table public.posts add column imagen_url text;
    end if;
  end if;

  -- ══ fijado en posts ══
  if not exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='posts' and column_name='fijado'
  ) then
    encontrada := false;
    candidatos := array['pinned','fijo','destacado','anclado'];
    foreach c in array candidatos loop
      if not encontrada and exists (
        select 1 from information_schema.columns
        where table_schema='public' and table_name='posts' and column_name=c
      ) then
        execute format('alter table public.posts rename column %I to fijado', c);
        encontrada := true;
      end if;
    end loop;
    if not encontrada then
      alter table public.posts add column fijado boolean default false;
    end if;
  end if;
end $$;

-- ─── PASO 3: columnas que faltan sí o sí ───────────────────────────
alter table public.posts add column if not exists categoria text default 'general';
alter table public.posts add column if not exists hashtags text[];
alter table public.perfiles add column if not exists avatar_url text;
alter table public.perfiles add column if not exists bio text;

-- ─── PASO 4: quitar restricciones viejas que puedan molestar ───────
alter table public.posts alter column contenido drop not null;
alter table public.posts alter column fijado set default false;
update public.posts set fijado = false where fijado is null;
update public.posts set categoria = 'general' where categoria is null;

-- ─── PASO 5: un solo like por persona y por post ───────────────────
create unique index if not exists likes_unicos on public.likes (post_id, usuario_id);

-- ─── PASO 6: permisos (RLS) ────────────────────────────────────────
alter table public.posts enable row level security;
alter table public.likes enable row level security;
alter table public.comentarios enable row level security;
alter table public.perfiles enable row level security;

-- POSTS
drop policy if exists "Posts visibles para logueados" on public.posts;
create policy "Posts visibles para logueados"
  on public.posts for select using (auth.uid() is not null);

drop policy if exists "Usuario publica sus posts" on public.posts;
create policy "Usuario publica sus posts"
  on public.posts for insert with check (auth.uid() = usuario_id);

drop policy if exists "Usuario edita sus posts" on public.posts;
create policy "Usuario edita sus posts"
  on public.posts for update using (
    auth.uid() = usuario_id
    or exists (select 1 from public.perfiles where id = auth.uid() and rol in ('admin','fundadora'))
  );

drop policy if exists "Usuario borra sus posts" on public.posts;
create policy "Usuario borra sus posts"
  on public.posts for delete using (
    auth.uid() = usuario_id
    or exists (select 1 from public.perfiles where id = auth.uid() and rol in ('admin','fundadora'))
  );

-- LIKES
drop policy if exists "Likes visibles" on public.likes;
create policy "Likes visibles"
  on public.likes for select using (auth.uid() is not null);

drop policy if exists "Usuario da like" on public.likes;
create policy "Usuario da like"
  on public.likes for insert with check (auth.uid() = usuario_id);

drop policy if exists "Usuario quita su like" on public.likes;
create policy "Usuario quita su like"
  on public.likes for delete using (auth.uid() = usuario_id);

-- COMENTARIOS
drop policy if exists "Comentarios visibles" on public.comentarios;
create policy "Comentarios visibles"
  on public.comentarios for select using (auth.uid() is not null);

drop policy if exists "Usuario comenta" on public.comentarios;
create policy "Usuario comenta"
  on public.comentarios for insert with check (auth.uid() = usuario_id);

drop policy if exists "Usuario borra su comentario" on public.comentarios;
create policy "Usuario borra su comentario"
  on public.comentarios for delete using (
    auth.uid() = usuario_id
    or exists (select 1 from public.perfiles where id = auth.uid() and rol in ('admin','fundadora'))
  );

-- PERFILES: que todos los logueados vean nombres y avatares
drop policy if exists "Perfiles visibles para logueados" on public.perfiles;
create policy "Perfiles visibles para logueados"
  on public.perfiles for select using (auth.uid() is not null);

-- ─── PASO 7: subir fotos a los posts ───────────────────────────────
drop policy if exists "Logueados suben imagenes de posts" on storage.objects;
create policy "Logueados suben imagenes de posts"
  on storage.objects for insert with check (
    bucket_id = 'imagenes'
    and auth.uid() is not null
    and (storage.foldername(name))[1] = 'posts'
  );

-- ─── VERIFICACIÓN: mostrá esto si algo falla ───────────────────────
select table_name, column_name, data_type
from information_schema.columns
where table_schema = 'public'
  and table_name in ('posts','likes','comentarios')
order by table_name, ordinal_position;
