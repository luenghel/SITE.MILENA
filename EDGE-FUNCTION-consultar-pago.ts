// ═══════════════════════════════════════════════════════════════════
// EDGE FUNCTION: consultar el estado de un pedido en Pagopar
//
// Es el PASO 3 del circuito que pide Pagopar para el pase a producción.
//
// Sirve para dos cosas:
//   · Completar la integración que exigen
//   · Recuperar pagos: si el webhook falla, preguntamos directamente
//     y confirmamos la compra igual
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

// La misma bienvenida que manda el webhook
async function mandarBienvenida(supabase: any, cursoId: string, usuarioId: string) {
  try {
    const { data } = await supabase
      .from('ajustes').select('valor').eq('clave', 'func_avisos_clases').maybeSingle()

    const nombres = data?.valor
      ? [data.valor.trim(), 'AVISAR-CLASES', 'avisar-clases']
      : ['AVISAR-CLASES', 'avisar-clases']

    const url = Deno.env.get('SUPABASE_URL')
    const clave = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')

    for (const n of nombres) {
      try {
        const r = await fetch(`${url}/functions/v1/${n}`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${clave}` },
          body: JSON.stringify({ accion: 'bienvenida', curso_id: cursoId, usuario_id: usuarioId }),
        })
        if (r.status === 404) continue
        return
      } catch (e) { /* siguiente */ }
    }
  } catch (e) { /* la bienvenida no es crítica */ }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  const responder = (d: any, s = 200) => new Response(JSON.stringify(d), {
    status: s, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  })

  try {
    const PUBLIC_KEY = Deno.env.get('PAGOPAR_PUBLIC_KEY')
    const PRIVATE_KEY = Deno.env.get('PAGOPAR_PRIVATE_KEY')

    if (!PUBLIC_KEY || !PRIVATE_KEY) {
      return responder({ error: 'Faltan las claves de Pagopar' }, 400)
    }

    // ─── Qué pedido consultamos ───
    let cuerpo: any = {}
    try {
      const crudo = await req.text()
      cuerpo = crudo && crudo.trim() ? JSON.parse(crudo) : {}
    } catch (e) {
      return responder({ error: 'Datos mal formados' }, 400)
    }

    const hash = cuerpo.hash || cuerpo.hash_pedido
    if (!hash) return responder({ error: 'Falta el hash del pedido' }, 400)

    // ─── Preguntarle a Pagopar ───
    const token = await sha1(PRIVATE_KEY + 'CONSULTA')

    let respuesta: Response
    try {
      respuesta = await fetch('https://api.pagopar.com/api/pedidos/1.1/traer', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Accept': 'application/json' },
        body: JSON.stringify({
          hash_pedido: hash,
          token: token,
          token_publico: PUBLIC_KEY,
        }),
      })
    } catch (e) {
      return responder({ error: 'No pudimos conectarnos con Pagopar: ' + String(e?.message || e) }, 502)
    }

    const crudo = await respuesta.text()
    console.log('[consulta] HTTP', respuesta.status, '·', crudo.slice(0, 500))

    if (!crudo || !crudo.trim()) {
      return responder({ error: 'Pagopar respondió vacío (HTTP ' + respuesta.status + ')' }, 502)
    }

    let datos: any
    try {
      datos = JSON.parse(crudo)
    } catch (e) {
      return responder({
        error: 'Pagopar no devolvió JSON',
        respuesta_pagopar: crudo.slice(0, 400),
      }, 502)
    }

    if (!datos.respuesta) {
      const motivo = typeof datos.resultado === 'string'
        ? datos.resultado
        : JSON.stringify(datos.resultado || datos).slice(0, 300)
      return responder({ error: 'Pagopar rechazó la consulta: ' + motivo }, 400)
    }

    const pedido = Array.isArray(datos.resultado) ? datos.resultado[0] : datos.resultado
    const pagado = (pedido?.pagado === true || pedido?.pagado === 'true' || pedido?.pagado === 1)

    // ─── Si está pagado y todavía figuraba pendiente, lo confirmamos ───
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    const { data: compra } = await supabase
      .from('compras')
      .select('id, estado, usuario_id, curso_id')
      .eq('pagopar_id', hash)
      .maybeSingle()

    let seConfirmoAhora = false

    if (compra && pagado && compra.estado !== 'pagado') {
      const { error } = await supabase.from('compras').update({
        estado: 'pagado',
        pagado_en: new Date().toISOString(),
      }).eq('id', compra.id)

      if (!error) {
        seConfirmoAhora = true
        console.log('[consulta] recuperamos un pago que el webhook no había registrado:', compra.id)
        if (compra.usuario_id && compra.curso_id) {
          await mandarBienvenida(supabase, compra.curso_id, compra.usuario_id)
        }
      }
    }

    return responder({
      exito: true,
      pagado: pagado,
      estado: pagado ? 'pagado' : (compra?.estado || 'pendiente'),
      confirmado_ahora: seConfirmoAhora,
      forma_pago: pedido?.forma_pago || null,
      monto: pedido?.monto || null,
      fecha_pago: pedido?.fecha_pago || null,
      pedido: pedido || null,
    })

  } catch (error) {
    console.error('[consulta] error inesperado:', error)
    return responder({ error: String(error?.message || error) }, 500)
  }
})
