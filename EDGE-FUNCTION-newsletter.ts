// ═══════════════════════════════════════════════════════════════════
// EDGE FUNCTION: enviar-newsletter
//
// Manda un artículo del blog a todos los suscriptores.
//
// ⚠️ ANTES DE USARLA hay que cargar 2 secrets en Supabase:
//    RESEND_API_KEY   →  la clave de Resend (empieza con re_)
//    EMAIL_REMITENTE  →  ej: Milena Machado <hola@milenamachado.com>
//
// Se llama desde el admin con: { articulo_id: "..." }
// ═══════════════════════════════════════════════════════════════════

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const SITIO = 'https://site-milena.vercel.app'   // ← cambiar por el dominio propio

function escapar(t: string) {
  return (t || '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
}

// ─── Plantilla del email, con la identidad de la marca ─────────────
function plantilla(articulo: any) {
  const titulo = escapar(articulo.titulo)
  const resumen = escapar(articulo.resumen || '')
  const enlace = `${SITIO}/articulo?id=${encodeURIComponent(articulo.slug)}`
  const categoria = escapar((articulo.categoria || 'MARKETING').toUpperCase())
  const minutos = articulo.tiempo_lectura || 5

  const portada = articulo.imagen_portada
    ? `<tr><td style="padding:0 0 26px">
         <img src="${articulo.imagen_portada}" alt="" width="100%"
              style="display:block;width:100%;max-width:480px;border-radius:14px;border:0">
       </td></tr>`
    : ''

  return `<!DOCTYPE html>
<html lang="es">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;background:#0E0509;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#0E0509;padding:32px 16px;">
  <tr><td align="center">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0"
           style="max-width:520px;background:#2D0A18;border-radius:18px;padding:34px 30px;font-family:Georgia,'Times New Roman',serif;">

      <tr><td style="padding-bottom:22px;">
        <div style="font-size:11px;letter-spacing:0.22em;color:#E8B8C4;font-family:Arial,sans-serif;">MILENA MACHADO</div>
        <div style="font-size:12px;color:rgba(255,245,240,0.45);font-family:Arial,sans-serif;margin-top:3px;">Creando Mentes Millonarias</div>
      </td></tr>

      ${portada}

      <tr><td style="padding-bottom:10px;">
        <span style="display:inline-block;padding:5px 12px;background:rgba(212,163,86,0.15);border:1px solid rgba(212,163,86,0.4);border-radius:20px;font-size:10px;letter-spacing:0.14em;color:#FAC775;font-family:Arial,sans-serif;">
          ${categoria} · ${minutos} MIN
        </span>
      </td></tr>

      <tr><td style="padding-bottom:14px;">
        <h1 style="margin:0;font-size:26px;line-height:1.2;font-weight:500;color:#FFF5F0;">${titulo}</h1>
      </td></tr>

      <tr><td style="padding-bottom:28px;">
        <p style="margin:0;font-size:15px;line-height:1.6;color:rgba(255,245,240,0.78);font-family:Arial,sans-serif;">${resumen}</p>
      </td></tr>

      <tr><td align="center" style="padding-bottom:28px;">
        <a href="${enlace}"
           style="display:inline-block;padding:16px 34px;background:#FAC775;color:#3D1208;text-decoration:none;border-radius:12px;font-size:13px;font-weight:bold;letter-spacing:0.12em;font-family:Arial,sans-serif;">
          VER MATERIAL COMPLETO
        </a>
      </td></tr>

      <tr><td style="border-top:1px solid rgba(255,245,240,0.1);padding-top:20px;">
        <p style="margin:0;font-size:11.5px;line-height:1.6;color:rgba(255,245,240,0.4);font-family:Arial,sans-serif;">
          Recibís este correo porque te suscribiste al newsletter de Milena Machado.<br>
          <a href="${SITIO}/baja?email={{EMAIL}}" style="color:rgba(255,245,240,0.55);">Darme de baja</a>
        </p>
      </td></tr>

    </table>
  </td></tr>
</table>
</body></html>`
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY')
    const EMAIL_REMITENTE = Deno.env.get('EMAIL_REMITENTE')

    if (!RESEND_API_KEY || !EMAIL_REMITENTE) {
      return new Response(
        JSON.stringify({ error: 'Falta configurar RESEND_API_KEY o EMAIL_REMITENTE en los secrets de Supabase' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      )
    }

    const { articulo_id } = await req.json()
    if (!articulo_id) {
      return new Response(JSON.stringify({ error: 'Falta el articulo_id' }), {
        status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    // ─── Traer el artículo ───────────────────────────────────────
    const { data: articulo, error: errArt } = await supabase
      .from('articulos').select('*').eq('id', articulo_id).single()

    if (errArt || !articulo) {
      return new Response(JSON.stringify({ error: 'No encontramos ese artículo' }), {
        status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    if (!articulo.publicado) {
      return new Response(JSON.stringify({ error: 'El artículo todavía es borrador. Publicalo antes de enviarlo.' }), {
        status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    // ─── No mandar dos veces el mismo ────────────────────────────
    const { data: yaEnviado } = await supabase
      .from('envios_newsletter').select('id').eq('articulo_id', articulo_id).maybeSingle()

    if (yaEnviado) {
      return new Response(JSON.stringify({ error: 'Este artículo ya fue enviado a los suscriptores' }), {
        status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    // ─── Traer los suscriptores activos ──────────────────────────
    const { data: subs } = await supabase
      .from('newsletter_suscriptores').select('email').eq('activo', true)

    const destinatarios = (subs || []).map(s => s.email).filter(Boolean)

    if (destinatarios.length === 0) {
      return new Response(JSON.stringify({ error: 'No hay suscriptores en la lista' }), {
        status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    const htmlBase = plantilla(articulo)
    const asunto = articulo.titulo

    // ─── Enviar en tandas de 100 (límite de Resend) ──────────────
    let enviados = 0
    const fallos: string[] = []

    for (let i = 0; i < destinatarios.length; i += 100) {
      const tanda = destinatarios.slice(i, i + 100)

      const lote = tanda.map(email => ({
        from: EMAIL_REMITENTE,
        to: [email],
        subject: asunto,
        html: htmlBase.replace('{{EMAIL}}', encodeURIComponent(email)),
      }))

      const resp = await fetch('https://api.resend.com/emails/batch', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${RESEND_API_KEY}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(lote),
      })

      if (resp.ok) {
        enviados += tanda.length
      } else {
        const detalle = await resp.text()
        fallos.push(detalle.slice(0, 200))
      }

      // Respetamos el límite de 2 peticiones por segundo
      if (i + 100 < destinatarios.length) {
        await new Promise(r => setTimeout(r, 600))
      }
    }

    // ─── Dejar registro del envío ────────────────────────────────
    await supabase.from('envios_newsletter').insert({
      articulo_id: articulo_id,
      titulo: articulo.titulo,
      destinatarios: enviados,
      fallos: fallos.length,
      detalle_error: fallos.length ? fallos.join(' | ') : null,
    })

    return new Response(
      JSON.stringify({
        exito: true,
        enviados,
        total: destinatarios.length,
        fallos: fallos.length,
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    return new Response(JSON.stringify({ error: String(error?.message || error) }), {
      status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }
})
