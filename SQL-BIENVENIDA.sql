-- ═══════════════════════════════════════════════════════════════════
-- EMAIL DE BIENVENIDA AL INSCRIBIRSE
-- Ajusta la tabla de avisos para poder registrar también la bienvenida
-- ═══════════════════════════════════════════════════════════════════

-- La bienvenida se guarda con clase_id vacío, así que el índice
-- que exigía usuario+clase únicos ya no sirve tal cual.
drop index if exists public.avisos_clases_unico;

create unique index if not exists avisos_clases_unico
  on public.avisos_clases (usuario_id, clase_id)
  where clase_id is not null;

-- Una sola bienvenida por persona y curso
create unique index if not exists avisos_bienvenida_unica
  on public.avisos_clases (usuario_id, curso_id)
  where clase_id is null;

-- ─── VERIFICACIÓN ──────────────────────────────────────────────────
select 'listo' as estado,
  (select count(*) from public.avisos_clases where clase_id is null) as bienvenidas_enviadas;
