// ═══════════════════════════════════════════════════════════════════
// EDGE FUNCTION: webhook de Pagopar
//
// Pagopar llama acá cuando se confirma un pago.
// Verifica la firma, marca la compra como pagada y manda la bienvenida.
//
// Pagopar espera que le devolvamos el mismo JSON que nos mandó.
// ═══════════════════════════════════════════════════════════════════

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

async function sha1(texto: string): Promise<string> {
  const datos = new TextEncoder().encode(texto)
  const hash = await crypto.subtle.digest('SHA-1', datos)
  return Array.from(new Uint8Array(hash)).map(b => b.toString(16).padStart(2, '0')).join('')
}

// Le avisamos a la alumna que ya tiene su curso
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
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${clave}`,
          },
          body: JSON.stringify({ accion: 'bienvenida', curso_id: cursoId, usuario_id: usuarioId }),
        })
        if (r.status === 404) continue
        console.log('[webhook] bienvenida enviada vía', n)
        return
      } catch (e) { /* probamos el siguiente */ }
    }
  } catch (e) {
    console.error('[webhook] no se pudo mandar la bienvenida:', e?.message)
  }
}

Deno.serve(async (req) => {
  const responder = (d: any, s = 200) => new Response(
    typeof d === 'string' ? d : JSON.stringify(d),
    { status: s, headers: { 'Content-Type': 'application/json' } }
  )

  try {
    const PRIVATE_KEY = Deno.env.get('PAGOPAR_PRIVATE_KEY')
    if (!PRIVATE_KEY) {
      console.error('[webhook] falta PAGOPAR_PRIVATE_KEY')
      return responder({ error: 'Falta la clave privada' }, 500)
    }

    // ─── Leer lo que manda Pagopar ───
    const crudo = await req.text()
    console.log('[webhook] recibido:', crudo.slice(0, 600))

    if (!crudo || !crudo.trim()) {
      return responder({ error: 'Sin datos' }, 400)
    }

    let cuerpo: any
    try {
      cuerpo = JSON.parse(crudo)
    } catch (e) {
      return responder({ error: 'Datos mal formados' }, 400)
    }

    // Pagopar manda { resultado: [ {...} ] }, pero contemplamos otras formas
    const r = Array.isArray(cuerpo?.resultado) ? cuerpo.resultado[0]
            : (cuerpo?.resultado || cuerpo)

    if (!r) return responder({ error: 'Sin datos del pedido' }, 400)

    const hashPedido = r.hash_pedido || r.hash
    const tokenRecibido = r.token
    const pagado = (r.pagado === true || r.pagado === 'true' || r.pagado === 1)

    if (!hashPedido) {
      console.error('[webhook] no vino el hash del pedido')
      return responder({ error: 'Falta el hash del pedido' }, 400)
    }

    // ─── Verificar la firma ───
    const tokenEsperado = await sha1(PRIVATE_KEY + hashPedido)

    if (tokenRecibido !== tokenEsperado) {
      console.error('[webhook] la firma no coincide para', hashPedido)
      return responder({ error: 'Firma inválida' }, 403)
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    // ─── Buscar la compra ───
    const { data: compra } = await supabase
      .from('compras')
      .select('id, estado, usuario_id, curso_id')
      .eq('pagopar_id', hashPedido)
      .maybeSingle()

    if (!compra) {
      console.error('[webhook] no encontramos la compra con hash', hashPedido)
      // Le respondemos bien igual: no queremos que Pagopar reintente sin parar
      return responder(cuerpo.resultado || cuerpo)
    }

    // ─── Ya estaba pagada: no la procesamos dos veces ───
    if (compra.estado === 'pagado' && pagado) {
      console.log('[webhook] esta compra ya estaba confirmada')
      return responder(cuerpo.resultado || cuerpo)
    }

    if (pagado) {
      const { error } = await supabase.from('compras').update({
        estado: 'pagado',
        pagado_en: new Date().toISOString(),
      }).eq('id', compra.id);

      if (error) {
        console.error('[webhook] no se pudo actualizar la compra:', error.message)
      } else {
        console.log('[webhook] compra confirmada:', compra.id)

        // La bienvenida, solo si sabemos a quién
        if (compra.usuario_id && compra.curso_id) {
          await mandarBienvenida(supabase, compra.curso_id, compra.usuario_id)
        } else {
          console.error('[webhook] la compra no tiene usuario o curso: no mandamos la bienvenida')
        }
      }
    } else {
      // Solo cancelamos si seguía pendiente
      if (compra.estado === 'pendiente') {
        await supabase.from('compras').update({ estado: 'cancelado' }).eq('id', compra.id)
        console.log('[webhook] compra cancelada:', compra.id)
      }
    }

    // ─── Pagopar espera que le devolvamos su propio JSON ───
    return responder(cuerpo.resultado || cuerpo)

  } catch (error) {
    console.error('[webhook] error inesperado:', error)
    return responder({ error: String(error?.message || error) }, 500)
  }
})
