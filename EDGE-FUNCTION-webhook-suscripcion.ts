// ═══════════════════════════════════════════════════════════════════
// EDGE FUNCTION: avisos del LINK DE SUSCRIPCIÓN de Pagopar
//
// Escrita contra la documentación oficial:
// https://soporte.pagopar.com/portal/es/kb/articles/link-suscripcion
//
// Pagopar nos avisa tres cosas (campo "tipo_accion"):
//   · "suscripcion"    → alguien se suscribió (todavía sin pagar)
//   · "pagado"         → cobró el período. Le extendemos el acceso.
//   · "desuscripcion"  → se dio de baja. Cortamos al instante.
//
// ─── DOS REGLAS QUE PAGOPAR EXIGE ──────────────────────────────────
// 1. El token se valida así:  sha1(clave_privada + tipo_accion)
// 2. Hay que DEVOLVER EXACTAMENTE EL MISMO JSON que ellos mandaron.
//    Si no, reintentan para siempre.
//
// ─── CÓMO SE CONFIGURA ─────────────────────────────────────────────
// En Pagopar, al crear el link de suscripción, poné como
// "URL de callback" la dirección de esta función:
//   https://TU-PROYECTO.supabase.co/functions/v1/webhook-suscripcion
//
// Y en Supabase → Edge Functions → esta función:
//   · "Verify JWT" APAGADO (Pagopar no manda token de Supabase)
//   · Secret PAGOPAR_PRIVATE_KEY ya existe, la usamos de acá
// ═══════════════════════════════════════════════════════════════════

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

async function sha1(texto: string): Promise<string> {
  const datos = new TextEncoder().encode(texto)
  const hash = await crypto.subtle.digest('SHA-1', datos)
  return Array.from(new Uint8Array(hash)).map(b => b.toString(16).padStart(2, '0')).join('')
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  // Pagopar quiere su mismo JSON de vuelta, tal cual
  const devolverIgual = (crudo: string) => new Response(crudo, {
    status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  })
  const error = (msg: string, s = 400) => new Response(JSON.stringify({ error: msg }), {
    status: s, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  })

  let crudo = ''

  try {
    const PRIVATE_KEY = Deno.env.get('PAGOPAR_PRIVATE_KEY')
    if (!PRIVATE_KEY) {
      console.error('[susc] falta PAGOPAR_PRIVATE_KEY en los Secrets')
      return error('Función sin configurar', 500)
    }

    crudo = await req.text()
    console.log('[susc] recibido:', crudo.slice(0, 1200))

    let cuerpo: any
    try {
      cuerpo = JSON.parse(crudo)
    } catch (e) {
      console.error('[susc] no es JSON válido')
      return error('Cuerpo mal formado')
    }

    const tipo = String(cuerpo?.tipo_accion || '').trim()
    if (!tipo) {
      console.error('[susc] el aviso no trae tipo_accion')
      return error('Falta tipo_accion')
    }

    // ─── El candado: sha1(clave_privada + tipo_accion) ───
    const esperado = await sha1(PRIVATE_KEY + tipo)
    if (String(cuerpo?.token || '').toLowerCase() !== esperado) {
      console.warn('[susc] token incorrecto para tipo_accion="' + tipo + '"')
      return error('No autorizado', 401)
    }

    const usuario = cuerpo.usuario || {}
    const susc = cuerpo.suscripcion || {}
    const pago = cuerpo.pago || {}

    const email = String(usuario.email || '').trim()
    const monto = Math.round(Number(String(susc.monto ?? 0).replace(/[^\d.]/g, '')) || 0)
    const periodicidad = String(susc.periodicidad || 'Mensual')
    const referencia = String(pago.hash_pedido || susc.id || '') || null

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    // ─────────────────────────────────────────────────────────────
    // COBRÓ: le extendemos el acceso un período más
    // ─────────────────────────────────────────────────────────────
    if (tipo === 'pagado') {
      if (!email) {
        console.error('[susc] aviso de pago sin email')
        return devolverIgual(crudo)
      }

      const { data, error: err } = await supabase.rpc('registrar_pago_premium', {
        p_email: email,
        p_monto: monto,
        p_referencia: referencia,
        p_periodicidad: periodicidad,
        p_metodo: 'pagopar',
        p_crudo: cuerpo,
      })

      if (err) console.error('[susc] no pudimos extender:', err.message)
      else console.log('[susc] extendida para', email, '→', JSON.stringify(data))

      return devolverIgual(crudo)
    }

    // ─────────────────────────────────────────────────────────────
    // SE DIO DE BAJA: cortamos al instante
    // ─────────────────────────────────────────────────────────────
    if (tipo === 'desuscripcion') {
      if (!email) {
        console.error('[susc] aviso de baja sin email')
        return devolverIgual(crudo)
      }

      const { data, error: err } = await supabase.rpc('cortar_premium', {
        p_email: email,
        p_motivo: 'Se dio de baja en Pagopar (' + (susc.estado || 'Cancelada') + ')',
      })

      if (err) console.error('[susc] no pudimos cortar:', err.message)
      else console.log('[susc] cortada para', email, '→', JSON.stringify(data))

      return devolverIgual(crudo)
    }

    // ─────────────────────────────────────────────────────────────
    // SE SUSCRIBIÓ: todavía NO pagó. No damos acceso.
    // Lo dejamos anotado para que Milena lo vea venir.
    // El acceso llega cuando llegue el aviso "pagado".
    // ─────────────────────────────────────────────────────────────
    if (tipo === 'suscripcion') {
      console.log('[susc] nueva suscripción de', email, '· estado:', susc.estado)

      if (email) {
        try {
          const { data: perfil } = await supabase
            .from('perfiles').select('id').ilike('email', email).maybeSingle()

          if (perfil?.id) {
            await supabase.from('interesados_premium')
              .upsert({ usuario_id: perfil.id, email: email, notas: 'Se suscribió en Pagopar, esperando el primer cobro' },
                      { onConflict: 'usuario_id' })
          } else {
            // No tiene cuenta en el sitio: lo anotamos para no perderlo
            await supabase.from('pagos_sin_cuenta').insert({
              email: email,
              nombre: [usuario.nombre, usuario.apellido].filter(Boolean).join(' ') || null,
              documento: usuario.documento || null,
              monto_gs: monto,
              referencia: referencia,
              crudo: cuerpo,
            })
            console.warn('[susc] se suscribió con un email sin cuenta en el sitio:', email)
          }
        } catch (e) {
          console.error('[susc] no pudimos anotar la suscripción:', e)
        }
      }

      return devolverIgual(crudo)
    }

    console.warn('[susc] tipo_accion desconocido:', tipo)
    return devolverIgual(crudo)

  } catch (e) {
    console.error('[susc] error inesperado:', e)
    // Devolvemos su JSON igual: si respondemos error, reintentan sin parar
    return crudo ? devolverIgual(crudo) : error('Error inesperado', 500)
  }
})
