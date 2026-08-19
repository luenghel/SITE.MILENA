// ═══════════════════════════════════════════════════════════════════
// EDGE FUNCTION: avisar clases liberadas
//
// Revisa qué clases se le liberaron a cada alumna y le manda un email.
// Pensada para ejecutarse UNA VEZ POR DÍA.
//
// Se puede llamar a mano desde el admin, o programarla con pg_cron.
// ═══════════════════════════════════════════════════════════════════

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const SITIO = 'https://milenacmm.com'

function escapar(t: string) {
  return (t || '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
}

function plantilla(nombre: string, curso: string, clases: string[], slug: string) {
  const saludo = escapar((nombre || '').split(' ')[0] || 'Hola')
  const enlace = `${SITIO}/curso-detalle?id=${encodeURIComponent(slug)}`
  const varias = clases.length > 1

  const lista = clases.map(c =>
    `<tr><td style="padding:9px 0;border-bottom:1px solid rgba(255,245,240,0.08)">
       <span style="color:#FAC775;margin-right:9px">▶</span>
       <span style="color:rgba(255,245,240,0.9);font-size:14.5px;font-family:Arial,sans-serif">${escapar(c)}</span>
     </td></tr>`
  ).join('')

  return `<!DOCTYPE html>
<html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;background:#0E0509">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#0E0509;padding:32px 16px">
 <tr><td align="center">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0"
         style="max-width:520px;background:#2D0A18;border-radius:18px;padding:34px 30px;font-family:Georgia,serif">

   <tr><td style="padding-bottom:22px">
     <div style="font-size:11px;letter-spacing:0.22em;color:#E8B8C4;font-family:Arial,sans-serif">MILENA MACHADO</div>
     <div style="font-size:12px;color:rgba(255,245,240,0.45);font-family:Arial,sans-serif;margin-top:3px">Creando Mentes Millonarias</div>
   </td></tr>

   <tr><td style="padding-bottom:12px">
     <h1 style="margin:0;font-size:24px;font-weight:500;color:#FAC775">
       ${varias ? 'Se liberaron clases nuevas' : 'Se liberó una clase nueva'}
     </h1>
   </td></tr>

   <tr><td style="padding-bottom:20px">
     <p style="margin:0;font-size:14.5px;line-height:1.6;color:rgba(255,245,240,0.82);font-family:Arial,sans-serif">
       ${saludo}, ya ${varias ? 'están disponibles' : 'está disponible'} en <strong style="color:#FFF5F0">${escapar(curso)}</strong>:
     </p>
   </td></tr>

   <tr><td style="padding-bottom:26px">
     <table role="presentation" width="100%" cellpadding="0" cellspacing="0"
            style="background:rgba(255,245,240,0.04);border-radius:12px;padding:6px 16px">
       ${lista}
     </table>
   </td></tr>

   <tr><td align="center" style="padding-bottom:26px">
     <a href="${enlace}"
        style="display:inline-block;padding:16px 34px;background:#DDA63F;color:#2E0C05;text-decoration:none;border-radius:8px;font-size:13px;font-weight:bold;letter-spacing:0.14em;font-family:Arial,sans-serif">
       IR A ESTUDIAR
     </a>
   </td></tr>

   <tr><td style="border-top:1px solid rgba(255,245,240,0.1);padding-top:20px">
     <p style="margin:0 0 12px;font-size:11.5px;line-height:1.6;color:rgba(255,245,240,0.45);font-family:Arial,sans-serif">
       Recibís este correo porque tenés acceso a este curso.
     </p>
     <p style="margin:0;font-size:11px;font-family:Arial,sans-serif">
       <a href="${SITIO}/baja?email={{EMAIL}}" style="color:rgba(255,245,240,0.5)">No quiero recibir más estos avisos</a>
     </p>
   </td></tr>

  </table>
 </td></tr>
</table>
</body></html>`
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const KEY = Deno.env.get('RESEND_API_KEY')
    const DE = Deno.env.get('EMAIL_REMITENTE')

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    // ─── Qué clases hay que avisar ───
    const { data: pendientes, error } = await supabase
      .from('clases_por_avisar')
      .select('*')

    if (error) {
      return new Response(JSON.stringify({
        error: 'No pudimos leer las clases pendientes: ' + error.message +
               '. Puede que falte correr SQL-LIBERACION-CLASES.sql.'
      }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    const lista = pendientes || []

    if (lista.length === 0) {
      return new Response(JSON.stringify({ exito: true, avisos: 0, mensaje: 'No hay clases nuevas para avisar' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    if (!KEY || !DE) {
      return new Response(JSON.stringify({
        error: 'Faltan los secrets RESEND_API_KEY o EMAIL_REMITENTE'
      }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    // ─── Agrupamos por alumna y curso: un solo email, no uno por clase ───
    const grupos: Record<string, any> = {}
    for (const p of lista) {
      const clave = p.usuario_id + '|' + p.curso_id
      if (!grupos[clave]) {
        grupos[clave] = {
          usuario_id: p.usuario_id,
          curso_id: p.curso_id,
          email: p.email,
          nombre: p.nombre,
          curso: p.curso_titulo,
          slug: p.curso_slug,
          clases: [] as any[],
        }
      }
      grupos[clave].clases.push({ id: p.clase_id, titulo: p.clase_titulo })
    }

    let enviados = 0
    let fallidos = 0
    const errores: string[] = []

    for (const clave of Object.keys(grupos)) {
      const g = grupos[clave]
      if (!g.email) continue

      const titulos = g.clases.map((c: any) => c.titulo)
      const html = plantilla(g.nombre, g.curso, titulos, g.slug)
        .replace(/\{\{EMAIL\}\}/g, encodeURIComponent(g.email))

      const asunto = titulos.length > 1
        ? `${titulos.length} clases nuevas en ${g.curso}`
        : `Nueva clase: ${titulos[0]}`

      let ok = false
      let detalle = ''

      try {
        const r = await fetch('https://api.resend.com/emails', {
          method: 'POST',
          headers: { 'Authorization': `Bearer ${KEY}`, 'Content-Type': 'application/json' },
          body: JSON.stringify({
            from: DE,
            to: [g.email],
            subject: asunto,
            html: html,
            headers: {
              'List-Unsubscribe': `<${SITIO}/baja?email=${encodeURIComponent(g.email)}>`,
              'List-Unsubscribe-Post': 'List-Unsubscribe=One-Click',
            },
          }),
        })
        ok = r.ok
        if (!ok) detalle = (await r.text()).slice(0, 200)
      } catch (e) {
        detalle = String(e?.message || e)
      }

      // Dejamos constancia igual, para no reintentar en bucle
      const filas = g.clases.map((c: any) => ({
        usuario_id: g.usuario_id,
        clase_id: c.id,
        curso_id: g.curso_id,
        email: g.email,
        enviado: ok,
        detalle_error: ok ? null : detalle,
      }))

      await supabase.from('avisos_clases').upsert(filas, { onConflict: 'usuario_id,clase_id' })

      if (ok) enviados++
      else { fallidos++; if (detalle) errores.push(detalle) }

      // Resend permite 2 por segundo
      await new Promise(r => setTimeout(r, 550))
    }

    return new Response(JSON.stringify({
      exito: true,
      avisos: enviados,
      fallidos,
      clases: lista.length,
      detalle_error: errores.length ? errores[0] : null,
    }), { headers: { ...corsHeaders, 'Content-Type': 'application/json' } })

  } catch (error) {
    return new Response(JSON.stringify({ error: String(error?.message || error) }), {
      status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }
})
