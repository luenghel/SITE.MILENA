// ═══════════════════════════════════════════════════════════════════
// EDGE FUNCTION: acciones de administración sobre miembros
//
// Permite, desde el panel admin y sin entrar a Supabase:
//   · enviar un aviso por email
//   · bloquear a alguien (con motivo, y avisarle)
//   · desbloquear
//   · eliminar la cuenta por completo
//
// SEGURIDAD: verifica que quien llama sea admin o fundadora.
// Sin eso, cualquiera podría borrar cuentas.
//
// Secrets necesarios (ya cargados):
//   RESEND_API_KEY
//   EMAIL_REMITENTE
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

// ─── Plantillas de email ───────────────────────────────────────────
function plantilla(tipo: string, nombre: string, motivo: string, mensaje: string) {
  const saludo = escapar((nombre || '').split(' ')[0] || 'Hola')

  const textos: Record<string, { titulo: string; intro: string; color: string; cierre: string }> = {
    aviso: {
      titulo: 'Un mensaje del equipo',
      intro: `${saludo}, te escribimos desde la comunidad de Milena Machado.`,
      color: '#FAC775',
      cierre: 'Si tenés dudas, respondé este correo.',
    },
    bloqueo: {
      titulo: 'Tu acceso quedó suspendido',
      intro: `${saludo}, suspendimos temporalmente tu participación en la comunidad.`,
      color: '#FF8090',
      cierre: 'Podés seguir viendo los cursos que compraste. Si creés que hubo un error, respondé este correo.',
    },
    desbloqueo: {
      titulo: 'Tu acceso fue restablecido',
      intro: `${saludo}, revisamos tu caso y ya podés volver a participar en la comunidad.`,
      color: '#9FE1CB',
      cierre: '¡Te esperamos de vuelta!',
    },
    eliminacion: {
      titulo: 'Tu cuenta fue eliminada',
      intro: `${saludo}, tu cuenta en la comunidad de Milena Machado fue dada de baja.`,
      color: '#FF8090',
      cierre: 'Si creés que hubo un error, respondé este correo.',
    },
    seguridad: {
      titulo: 'Cambiaste tu contraseña',
      intro: `${saludo}, tu contraseña se cambió correctamente.`,
      color: '#9FE1CB',
      cierre: '',
    },
  }

  const t = textos[tipo] || textos.aviso

  const bloqueMotivo = motivo
    ? `<tr><td style="padding:0 0 18px">
         <div style="background:rgba(255,245,240,0.05);border-left:3px solid ${t.color};border-radius:8px;padding:14px 16px">
           <div style="font-size:10px;letter-spacing:0.18em;color:rgba(255,245,240,0.5);font-family:Arial,sans-serif;margin-bottom:6px">MOTIVO</div>
           <div style="font-size:14px;color:rgba(255,245,240,0.88);font-family:Arial,sans-serif;line-height:1.5">${escapar(motivo)}</div>
         </div>
       </td></tr>`
    : ''

  const bloqueMensaje = mensaje
    ? `<tr><td style="padding:0 0 22px">
         <p style="margin:0;font-size:14.5px;line-height:1.65;color:rgba(255,245,240,0.8);font-family:Arial,sans-serif">${escapar(mensaje).replace(/\n/g, '<br>')}</p>
       </td></tr>`
    : ''

  return `<!DOCTYPE html>
<html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;background:#0E0509">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#0E0509;padding:32px 16px">
 <tr><td align="center">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0"
         style="max-width:500px;background:#2D0A18;border-radius:18px;padding:34px 30px;font-family:Georgia,serif">

   <tr><td style="padding-bottom:20px">
     <div style="font-size:11px;letter-spacing:0.22em;color:#E8B8C4;font-family:Arial,sans-serif">MILENA MACHADO</div>
     <div style="font-size:12px;color:rgba(255,245,240,0.45);font-family:Arial,sans-serif;margin-top:3px">Creando Mentes Millonarias</div>
   </td></tr>

   <tr><td style="padding-bottom:12px">
     <h1 style="margin:0;font-size:22px;font-weight:500;color:${t.color}">${t.titulo}</h1>
   </td></tr>

   <tr><td style="padding-bottom:18px">
     <p style="margin:0;font-size:14.5px;line-height:1.6;color:rgba(255,245,240,0.82);font-family:Arial,sans-serif">${t.intro}</p>
   </td></tr>

   ${bloqueMotivo}
   ${bloqueMensaje}

   <tr><td style="padding-bottom:24px">
     <p style="margin:0;font-size:13.5px;line-height:1.6;color:rgba(255,245,240,0.65);font-family:Arial,sans-serif">${t.cierre}</p>
   </td></tr>

   ${tipo === 'seguridad' ? `
   <tr><td style="padding-bottom:24px">
     <div style="background:rgba(255,59,71,0.1);border:1px solid rgba(255,59,71,0.35);border-radius:12px;padding:18px 16px">
       <p style="margin:0 0 6px;font-size:15px;color:#FF8090;font-family:Arial,sans-serif;font-weight:bold">¿No fuiste vos?</p>
       <p style="margin:0 0 18px;font-size:13px;color:rgba(255,245,240,0.75);line-height:1.55;font-family:Arial,sans-serif">
         Alguien podría estar entrando a tu cuenta. Cambiá tu contraseña ahora mismo.
       </p>
       <a href="${SITIO}/recuperar-inicio?email={{EMAIL}}"
          style="display:inline-block;padding:15px 30px;background:#C8203A;color:#FFF5F0;text-decoration:none;border-radius:8px;font-size:12.5px;font-weight:bold;letter-spacing:0.12em;font-family:Arial,sans-serif">
         CAMBIAR MI CONTRASEÑA AHORA
       </a>
     </div>
   </td></tr>` : ''}

   ${(tipo !== 'eliminacion' && tipo !== 'seguridad') ? `
   <tr><td align="center" style="padding-bottom:24px">
     <a href="${SITIO}" style="display:inline-block;padding:14px 30px;background:#DDA63F;color:#2E0C05;text-decoration:none;border-radius:11px;font-size:12.5px;font-weight:bold;letter-spacing:0.1em;font-family:Arial,sans-serif">IR AL SITIO</a>
   </td></tr>` : ''}

   <tr><td style="border-top:1px solid rgba(255,245,240,0.1);padding-top:18px">
     <p style="margin:0 0 12px;font-size:11.5px;color:rgba(255,245,240,0.4);font-family:Arial,sans-serif">
       Este mensaje lo envía el equipo de Milena Machado.
     </p>
     ${tipo === 'aviso' ? `
     <p style="margin:0;font-size:11px;font-family:Arial,sans-serif">
       <a href="${SITIO}/baja?email={{EMAIL}}" style="color:rgba(255,245,240,0.5)">No quiero recibir más estos correos</a>
     </p>` : ''}
   </td></tr>

  </table>
 </td></tr>
</table>
</body></html>`
}

async function enviarEmail(para: string, asunto: string, html: string) {
  const KEY = Deno.env.get('RESEND_API_KEY')
  const DE = Deno.env.get('EMAIL_REMITENTE')
  if (!KEY || !DE) return { ok: false, error: 'Falta cargar RESEND_API_KEY o EMAIL_REMITENTE en los secrets' }

  const urlBaja = `${SITIO}/baja?email=${encodeURIComponent(para)}`
  const cuerpo = html.replace(/\{\{EMAIL\}\}/g, encodeURIComponent(para))

  const r = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: { 'Authorization': `Bearer ${KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      from: DE,
      to: [para],
      subject: asunto,
      html: cuerpo,
      headers: {
        'List-Unsubscribe': `<${urlBaja}>`,
        'List-Unsubscribe-Post': 'List-Unsubscribe=One-Click',
      },
    }),
  })

  if (!r.ok) {
    const crudo = await r.text()
    let explicado = crudo.slice(0, 250)
    if (r.status === 401 || crudo.includes('API key')) {
      explicado = 'La clave de Resend no es válida'
    } else if (crudo.includes('not verified')) {
      explicado = 'El dominio del remitente no está verificado en Resend'
    } else if (crudo.includes('You can only send testing emails')) {
      explicado = 'Resend está en modo prueba: solo podés enviarte a tu propio email'
    }
    return { ok: false, error: explicado }
  }
  return { ok: true }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const admin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    // ─── 1. ¿Quién está llamando? ───────────────────────────────
    const auth = req.headers.get('Authorization') || ''
    const token = auth.replace('Bearer ', '').trim()
    if (!token) {
      return new Response(JSON.stringify({ error: 'Falta la sesión' }), {
        status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    const { data: { user: quien }, error: errAuth } = await admin.auth.getUser(token)
    if (errAuth || !quien) {
      return new Response(JSON.stringify({ error: 'Sesión inválida' }), {
        status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    const cuerpo = await req.json()
    const { accion, usuario_id, motivo, mensaje, avisar, detalle } = cuerpo

    // ─── 2a. Aviso de seguridad: cada quien puede avisarse a sí ──
    // (no hace falta ser del equipo, pero solo sobre la propia cuenta)
    if (accion === 'aviso-seguridad') {
      const { data: yo } = await admin
        .from('perfiles').select('nombre, email').eq('id', quien.id).maybeSingle()

      const correo = yo?.email || quien.email
      if (!correo) {
        return new Response(JSON.stringify({ exito: true, email_enviado: false }), {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        })
      }

      const fecha = new Date().toLocaleString('es-PY', {
        timeZone: 'America/Asuncion',
        day: '2-digit', month: 'long', year: 'numeric',
        hour: '2-digit', minute: '2-digit'
      })

      const r = await enviarEmail(
        correo,
        'Cambiaste tu contraseña · Milena Machado',
        plantilla('seguridad', yo?.nombre || '', 'Cambio de contraseña · ' + fecha, detalle || '')
      )

      await admin.from('avisos_admin').insert({
        destinatario_id: quien.id,
        destinatario_email: correo,
        destinatario_nombre: yo?.nombre || null,
        tipo: 'seguridad',
        motivo: 'Cambio de contraseña',
        mensaje: null,
        email_enviado: r.ok,
        hecho_por: quien.id,
      })

      return new Response(JSON.stringify({ exito: true, email_enviado: r.ok }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    // ─── 2b. Todo lo demás: solo el equipo ──────────────────────
    const { data: perfilQuien } = await admin
      .from('perfiles').select('rol, nombre').eq('id', quien.id).maybeSingle()

    if (!perfilQuien || !['admin', 'fundadora'].includes(perfilQuien.rol)) {
      return new Response(JSON.stringify({ error: 'No tenés permiso para esto' }), {
        status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    if (!accion || !usuario_id) {
      return new Response(JSON.stringify({ error: 'Faltan datos' }), {
        status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    if (usuario_id === quien.id) {
      return new Response(JSON.stringify({ error: 'No podés aplicarte esto a vos misma' }), {
        status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    const { data: destino } = await admin
      .from('perfiles').select('id, nombre, email, rol').eq('id', usuario_id).maybeSingle()

    if (!destino) {
      return new Response(JSON.stringify({ error: 'No encontramos a esa persona' }), {
        status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    // Una fundadora no puede ser tocada por un admin
    if (destino.rol === 'fundadora' && perfilQuien.rol !== 'fundadora') {
      return new Response(JSON.stringify({ error: 'Solo la fundadora puede hacer esto sobre otra fundadora' }), {
        status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    const asuntos: Record<string, string> = {
      aviso: 'Un mensaje del equipo · Milena Machado',
      bloqueo: 'Tu acceso a la comunidad quedó suspendido',
      desbloqueo: 'Tu acceso fue restablecido',
      eliminacion: 'Tu cuenta fue eliminada',
    }

    let emailOk = false
    let detalleEmail = ''

    // ─── 4. Ejecutar ────────────────────────────────────────────
    if (accion === 'bloquear') {
      await admin.from('perfiles').update({
        bloqueado: true,
        motivo_bloqueo: motivo || 'Incumplimiento de las normas de la comunidad',
        bloqueado_en: new Date().toISOString(),
      }).eq('id', usuario_id)

    } else if (accion === 'desbloquear') {
      await admin.from('perfiles').update({
        bloqueado: false, motivo_bloqueo: null, bloqueado_en: null,
      }).eq('id', usuario_id)

    } else if (accion === 'eliminar') {
      // ─── No se elimina a quien compró: perdería lo que pagó ───
      const { data: compras } = await admin
        .from('compras').select('id').eq('usuario_id', usuario_id).eq('estado', 'pagado')

      if (compras && compras.length > 0) {
        return new Response(JSON.stringify({
          error: `Esta persona compró ${compras.length} curso(s). No se puede eliminar su cuenta porque perdería el acceso a lo que pagó. Bloqueala en su lugar.`
        }), { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
      }

      // El email se manda ANTES de borrar, si no se pierde la dirección
      if (avisar && destino.email) {
        const r = await enviarEmail(
          destino.email,
          asuntos.eliminacion,
          plantilla('eliminacion', destino.nombre || '', motivo || '', mensaje || '')
        )
        emailOk = r.ok
        if (!r.ok) detalleEmail = r.error || ''
      }

      await admin.from('avisos_admin').insert({
        destinatario_id: null,
        destinatario_email: destino.email,
        destinatario_nombre: destino.nombre,
        tipo: 'eliminacion',
        motivo: motivo || null,
        mensaje: mensaje || null,
        email_enviado: emailOk,
        hecho_por: quien.id,
      })

      const { error: errDel } = await admin.auth.admin.deleteUser(usuario_id)
      if (errDel) {
        return new Response(JSON.stringify({ error: 'No se pudo eliminar: ' + errDel.message }), {
          status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
        })
      }

      return new Response(JSON.stringify({ exito: true, accion: 'eliminar', email_enviado: emailOk, detalle_email: detalleEmail }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })

    } else if (accion !== 'aviso') {
      return new Response(JSON.stringify({ error: 'Acción desconocida' }), {
        status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      })
    }

    // ─── 5. Avisar por email ────────────────────────────────────
    const tipoEmail = accion === 'bloquear' ? 'bloqueo'
                    : accion === 'desbloquear' ? 'desbloqueo'
                    : 'aviso'

    if (avisar && destino.email) {
      const r = await enviarEmail(
        destino.email,
        asuntos[tipoEmail],
        plantilla(tipoEmail, destino.nombre || '', motivo || '', mensaje || '')
      )
      emailOk = r.ok
      if (!r.ok) detalleEmail = r.error || ''
    }

    // ─── 6. Dejar constancia ────────────────────────────────────
    await admin.from('avisos_admin').insert({
      destinatario_id: usuario_id,
      destinatario_email: destino.email,
      destinatario_nombre: destino.nombre,
      tipo: tipoEmail,
      motivo: motivo || null,
      mensaje: mensaje || null,
      email_enviado: emailOk,
      hecho_por: quien.id,
    })

    return new Response(
      JSON.stringify({ exito: true, accion, email_enviado: emailOk, detalle_email: detalleEmail }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    )

  } catch (error) {
    return new Response(JSON.stringify({ error: String(error?.message || error) }), {
      status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    })
  }
})
