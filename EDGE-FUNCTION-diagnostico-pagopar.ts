// ═══════════════════════════════════════════════════════════════════
// EDGE FUNCTION: diagnóstico de Pagopar
//
// Prueba las claves contra endpoints que NO crean pedidos, para saber
// si el problema es del comercio o de nuestra integración.
//
// No cobra ni crea nada: solo consulta.
// ═══════════════════════════════════════════════════════════════════

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

// Llama a un endpoint y devuelve lo que responda, sin romperse
async function probar(nombre: string, url: string, cuerpo: any) {
  try {
    const r = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Accept': 'application/json' },
      body: JSON.stringify(cuerpo),
    })

    const crudo = await r.text()
    let datos: any = null
    try { datos = JSON.parse(crudo) } catch (e) { /* no era JSON */ }

    return {
      prueba: nombre,
      http: r.status,
      ok: !!(datos && datos.respuesta === true),
      respuesta: datos ? (datos.respuesta === true ? 'correcta' : (
        typeof datos.resultado === 'string' ? datos.resultado : JSON.stringify(datos.resultado)
      )) : crudo.slice(0, 300),
      datos: (datos && datos.respuesta === true) ? datos.resultado : null,
    }
  } catch (e) {
    return { prueba: nombre, http: 0, ok: false, respuesta: 'No se pudo conectar: ' + String(e?.message || e) }
  }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  const responder = (d: any, s = 200) => new Response(JSON.stringify(d, null, 2), {
    status: s, headers: { ...corsHeaders, 'Content-Type': 'application/json' }
  })

  try {
    const PUBLIC_KEY = Deno.env.get('PAGOPAR_PUBLIC_KEY')
    const PRIVATE_KEY = Deno.env.get('PAGOPAR_PRIVATE_KEY')

    if (!PUBLIC_KEY || !PRIVATE_KEY) {
      return responder({
        conclusion: '❌ Faltan las claves en Supabase',
        detalle: 'Cargá PAGOPAR_PUBLIC_KEY y PAGOPAR_PRIVATE_KEY en Settings → Edge Functions.'
      }, 400)
    }

    const pruebas = []

    // ─── 1. Formas de pago disponibles ───
    // No crea nada. Si responde, las claves son válidas y el comercio existe.
    pruebas.push(await probar(
      'Formas de pago habilitadas',
      'https://api.pagopar.com/api/forma-pago/1.1/traer/',
      {
        token: await sha1(PRIVATE_KEY + 'FORMA-PAGO'),
        token_publico: PUBLIC_KEY,
      }
    ))

    // ─── 2. Consultar un pedido inexistente ───
    // Si dice "pedido no existe", la autenticación funcionó.
    pruebas.push(await probar(
      'Consulta de pedido (autenticación)',
      'https://api.pagopar.com/api/pedidos/1.1/traer',
      {
        hash_pedido: '0000000000000000000000000000000000000000000000000000000000000000',
        token: await sha1(PRIVATE_KEY + 'CONSULTA'),
        token_publico: PUBLIC_KEY,
      }
    ))

    // ─── Qué conclusión sacamos ───
    const formasPago = pruebas[0]
    const consulta = pruebas[1]

    let conclusion = ''
    let queHacer = ''

    if (formasPago.ok) {
      conclusion = '✅ Las claves son válidas y el comercio responde'
      const n = Array.isArray(formasPago.datos) ? formasPago.datos.length : 0
      queHacer = 'Tenés ' + n + ' forma(s) de pago habilitada(s). ' +
        'Si iniciar-transaccion falla, el problema es el permiso para crear pedidos, no las claves.'
    } else if (String(formasPago.respuesta).toLowerCase().includes('token')) {
      conclusion = '❌ Las claves no coinciden'
      queHacer = 'Volvé a copiar los tokens desde el panel de Pagopar. ' +
        'Cuidado con espacios invisibles al pegar.'
    } else if (String(formasPago.respuesta).toLowerCase().includes('comercio')) {
      conclusion = '⚠️ Las claves llegan, pero el comercio está bloqueado'
      queHacer = 'Es del lado de Pagopar. Abrí un ticket al equipo de Desarrollo ' +
        'pidiendo que habiliten el entorno.'
    } else {
      conclusion = '⚠️ Respuesta inesperada'
      queHacer = 'Mirá el detalle de cada prueba más abajo.'
    }

    return responder({
      conclusion,
      que_hacer: queHacer,
      claves: {
        publica_termina_en: PUBLIC_KEY.slice(-6),
        publica_largo: PUBLIC_KEY.length,
        privada_largo: PRIVATE_KEY.length,
        // Si tienen espacios, se nota acá
        publica_limpia: PUBLIC_KEY === PUBLIC_KEY.trim(),
        privada_limpia: PRIVATE_KEY === PRIVATE_KEY.trim(),
      },
      formas_de_pago: formasPago.ok && Array.isArray(formasPago.datos)
        ? formasPago.datos.map((f: any) => f.titulo + ' (mín. Gs ' + f.monto_minimo + ', comisión ' + f.porcentaje_comision + '%)')
        : null,
      pruebas,
    })

  } catch (error) {
    return responder({ conclusion: '❌ Error inesperado', detalle: String(error?.message || error) }, 500)
  }
})
