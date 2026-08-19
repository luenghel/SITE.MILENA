// ═══════════════════════════════════════════════════════════════════
// EDGE FUNCTION: verificación en dos pasos
//
// Acciones:
//   revisar   → ¿este dispositivo es de confianza?
//   enviar    → genera un código de 6 dígitos y lo manda por email
//   verificar → comprueba el código y, si corresponde, confía en el equipo
//
// Los códigos se guardan cifrados: ni nosotros podemos leerlos.
// ═══════════════════════════════════════════════════════════════════

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const SITIO = 'https://milenacmm.com'
const DIAS_CONFIANZA = 7
const MINUTOS_CODIGO = 10
const MAX_INTENTOS = 5

// ─── Cifrado del código ────────────────────────────────────────────
async function hashear(texto: string) {
  const datos = new TextEncoder().encode(texto + '::cmm::2pasos')
  const buf = await crypto.subtle.digest('SHA-256', datos)
  return Array.from(new Uint8Array(buf)).map(b => b.toString(16).padStart(2, '0')).join('')
}

function generarCodigo() {
  const n = crypto.getRandomValues(new Uint32Array(1))[0] % 1000000
  return String(n).padStart(6, '0')
}

function escapar(t: string) {
  return (t || '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
}

// ─── Nombre legible del dispositivo ────────────────────────────────
function nombrarDispositivo(ua: string) {
  const u = (ua || '').toLowerCase()
  let navegador = 'un navegador'
  if (u.includes('edg/')) navegador = 'Edge'
  else if (u.includes('chrome') && !u.includes('edg/')) navegador = 'Chrome'
  else if (u.includes('firefox')) navegador = 'Firefox'
  else if (u.includes('safari') && !u.includes('chrome')) navegador = 'Safari'

  let sistema = 'un dispositivo'
  if (u.includes('iphone')) sistema = 'iPhone'
  else if (u.includes('ipad')) sistema = 'iPad'
  else if (u.includes('android')) sistema = 'Android'
  else if (u.includes('windows')) sistema = 'Windows'
  else if (u.includes('mac os')) sistema = 'Mac'
  else if (u.includes('linux')) sistema = 'Linux'

  return `${navegador} en ${sistema}`
}

// ─── El email con el código ────────────────────────────────────────
function plantilla(nombre: string, codigo: string, dispositivo: string, cuando: string, emailDestino: string) {
  const saludo = escapar((nombre || '').split(' ')[0] || 'Hola')

  return `<!DOCTYPE html>
<html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;background:#0E0509">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#0E0509;padding:32px 16px">
 <tr><td align="center">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0"
         style="max-width:480px;background:#2D0A18;border-radius:16px;padding:36px 30px;font-family:Georgia,serif;text-align:center">

   <tr><td>
     <div style="font-size:13px;letter-spacing:0.2em;color:#E8B8C4;margin-bottom:4px">MILENA MACHADO</div>
     <div style="font-size:11px;color:rgba(255,245,240,0.4);margin-bottom:24px">Creando Mentes Millonarias</div>
   </td></tr>

   <tr><td>
     <h1 style="font-size:23px;font-weight:500;margin:0 0 10px;color:#FFF5F0">Confirmá que sos vos</h1>
     <p style="font-size:14px;color:rgba(255,245,240,0.72);margin:0 0 24px;font-family:Arial,sans-serif;line-height:1.6">
       ${saludo}, alguien está entrando a tu cuenta desde un dispositivo nuevo.
       Si sos vos, usá este código:
     </p>
   </td></tr>

   <tr><td>
     <div style="font-size:38px;letter-spacing:0.28em;font-weight:600;color:#FAC775;background:rgba(212,163,86,0.12);border:1px solid rgba(212,163,86,0.4);border-radius:12px;padding:18px">
       ${codigo}
     </div>
   </td></tr>

   <tr><td style="padding-top:22px">
     <table role="presentation" width="100%" cellpadding="0" cellspacing="0"
            style="background:rgba(255,245,240,0.04);border-radius:10px;padding:14px 16px;text-align:left">
       <tr><td style="font-size:12px;color:rgba(255,245,240,0.5);font-family:Arial,sans-serif;padding-bottom:5px">DISPOSITIVO</td></tr>
       <tr><td style="font-size:13.5px;color:rgba(255,245,240,0.85);font-family:Arial,sans-serif">${escapar(dispositivo)}</td></tr>
       <tr><td style="font-size:12px;color:rgba(255,245,240,0.5);font-family:Arial,sans-serif;padding:10px 0 5px">CUÁNDO</td></tr>
       <tr><td style="font-size:13.5px;color:rgba(255,245,240,0.85);font-family:Arial,sans-serif">${escapar(cuando)}</td></tr>
     </table>
   </td></tr>

   <tr><td style="padding-top:26px">
     <div style="background:rgba(255,59,71,0.1);border:1px solid rgba(255,59,71,0.35);border-radius:12px;padding:18px 16px">
       <p style="margin:0 0 6px;font-size:15px;color:#FF8090;font-family:Arial,sans-serif;font-weight:bold">
         ¿No fuiste vos?
       </p>
       <p style="margin:0 0 18px;font-size:13px;color:rgba(255,245,240,0.75);line-height:1.55;font-family:Arial,sans-serif">
         Alguien tiene tu contraseña. No compartas el código y cambiala ahora mismo.
       </p>
       <a href="${SITIO}/recuperar-inicio?email=${encodeURIComponent(emailDestino)}"
          style="display:inline-block;padding:15px 30px;background:#C8203A;color:#FFF5F0;text-decoration:none;border-radius:8px;font-size:12.5px;font-weight:bold;letter-spacing:0.12em;font-family:Arial,sans-serif">
         CAMBIAR MI CONTRASEÑA AHORA
       </a>
     </div>
   </td></tr>

   <tr><td style="padding-top:22px">
     <p style="margin:0;font-size:12px;color:rgba(255,245,240,0.45);font-family:Arial,sans-serif;line-height:1.6">
       El código vence en ${MINUTOS_CODIGO} minutos.
     </p>
   </td></tr>

  </table>
 </td></tr>
</table>
</body></html>`
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  const json = (d: any, s = 200) => new Response(JSON.stringify(d), {
    status: s, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  })

  try {
    const admin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    const cuerpo = await req.json()
    const { accion, email, token_dispositivo, codigo, confiar } = cuerpo

    if (!email) return json({ error: 'Falta el email' }, 400)

    // ─── Buscar a la persona ───
    const { data: perfil } = await admin
      .from('perfiles')
      .select('id, nombre, email, dos_pasos')
      .ilike('email', email.trim())
      .maybeSingle()

    if (!perfil) {
      // No confirmamos ni desmentimos que exista
      return json({ requiere: false })
    }

    const ua = req.headers.get('user-agent') || ''
    const ip = req.headers.get('x-forwarded-for')?.split(',')[0]?.trim() || ''
    const dispositivo = nombrarDispositivo(ua)

    // ═══ REVISAR: ¿hace falta el código? ═══
    if (accion === 'revisar') {
      if (perfil.dos_pasos === false) return json({ requiere: false })

      if (token_dispositivo) {
        const th = await hashear(token_dispositivo)
        const limite = new Date(Date.now() - DIAS_CONFIANZA * 86400000).toISOString()

        const { data: disp } = await admin
          .from('dispositivos_confiables')
          .select('id, ultimo_uso')
          .eq('usuario_id', perfil.id)
          .eq('token_hash', th)
          .gte('ultimo_uso', limite)
          .maybeSingle()

        if (disp) {
          // Renovamos los 7 días
          await admin.from('dispositivos_confiables')
            .update({ ultimo_uso: new Date().toISOString() })
            .eq('id', disp.id)
          return json({ requiere: false, confiable: true })
        }
      }

      return json({ requiere: true, dispositivo })
    }

    // ═══ ENVIAR: mandamos el código ═══
    if (accion === 'enviar') {
      const KEY = Deno.env.get('RESEND_API_KEY')
      const DE = Deno.env.get('EMAIL_REMITENTE')
      if (!KEY || !DE) return json({ error: 'Falta configurar el envío de emails' }, 400)

      // Si ya mandamos uno hace menos de 1 minuto, no repetimos
      const haceUnMinuto = new Date(Date.now() - 60000).toISOString()
      const { data: reciente } = await admin
        .from('codigos_2pasos')
        .select('id')
        .eq('usuario_id', perfil.id)
        .eq('usado', false)
        .gte('creado_en', haceUnMinuto)
        .maybeSingle()

      if (reciente) return json({ exito: true, ya_enviado: true })

      const cod = generarCodigo()
      const ch = await hashear(cod)

      // Anulamos los códigos anteriores
      await admin.from('codigos_2pasos')
        .update({ usado: true })
        .eq('usuario_id', perfil.id)
        .eq('usado', false)

      await admin.from('codigos_2pasos').insert({
        usuario_id: perfil.id,
        email: perfil.email,
        codigo_hash: ch,
        expira_en: new Date(Date.now() + MINUTOS_CODIGO * 60000).toISOString(),
      })

      const cuando = new Date().toLocaleString('es-PY', {
        timeZone: 'America/Asuncion',
        day: '2-digit', month: 'long', year: 'numeric',
        hour: '2-digit', minute: '2-digit'
      })

      const r = await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: { 'Authorization': `Bearer ${KEY}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({
          from: DE,
          to: [perfil.email],
          subject: `${cod} es tu código de acceso · Milena Machado`,
          html: plantilla(perfil.nombre || '', cod, dispositivo, cuando, perfil.email),
        }),
      })

      if (!r.ok) {
        const crudo = await r.text()
        let msg = 'No pudimos enviar el código'
        if (crudo.includes('not verified')) msg = 'El dominio del remitente no está verificado en Resend'
        else if (r.status === 401) msg = 'La clave de Resend no es válida'
        return json({ error: msg }, 400)
      }

      return json({ exito: true, dispositivo })
    }

    // ═══ VERIFICAR: comprobamos el código ═══
    if (accion === 'verificar') {
      if (!codigo) return json({ error: 'Falta el código' }, 400)

      const { data: reg } = await admin
        .from('codigos_2pasos')
        .select('*')
        .eq('usuario_id', perfil.id)
        .eq('usado', false)
        .order('creado_en', { ascending: false })
        .limit(1)
        .maybeSingle()

      if (!reg) return json({ error: 'No hay ningún código pendiente. Pedí uno nuevo.' }, 400)

      if (new Date(reg.expira_en).getTime() < Date.now()) {
        await admin.from('codigos_2pasos').update({ usado: true }).eq('id', reg.id)
        return json({ error: 'El código venció. Pedí uno nuevo.' }, 400)
      }

      if ((reg.intentos || 0) >= MAX_INTENTOS) {
        await admin.from('codigos_2pasos').update({ usado: true }).eq('id', reg.id)
        return json({ error: 'Demasiados intentos fallidos. Pedí un código nuevo.' }, 400)
      }

      const ch = await hashear(String(codigo).trim())

      if (ch !== reg.codigo_hash) {
        await admin.from('codigos_2pasos')
          .update({ intentos: (reg.intentos || 0) + 1 })
          .eq('id', reg.id)
        const quedan = MAX_INTENTOS - (reg.intentos || 0) - 1
        return json({
          error: quedan > 0
            ? `Ese código no es correcto. Te quedan ${quedan} intento(s).`
            : 'Ese código no es correcto. Pedí uno nuevo.'
        }, 400)
      }

      // ✓ Correcto
      await admin.from('codigos_2pasos').update({ usado: true }).eq('id', reg.id)

      let nuevoToken = null
      if (confiar) {
        nuevoToken = crypto.randomUUID() + '-' + crypto.randomUUID()
        const th = await hashear(nuevoToken)

        await admin.from('dispositivos_confiables').insert({
          usuario_id: perfil.id,
          token_hash: th,
          nombre: dispositivo,
          ip: ip || null,
        })
      }

      return json({ exito: true, token_dispositivo: nuevoToken })
    }

    return json({ error: 'Acción desconocida' }, 400)

  } catch (error) {
    return json({ error: String(error?.message || error) }, 500)
  }
})
