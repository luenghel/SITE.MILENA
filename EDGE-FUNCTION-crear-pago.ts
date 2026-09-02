// ═══════════════════════════════════════════════════════════════════
// EDGE FUNCTION: crear pago en Pagopar
//
// Arma el pedido, lo manda a Pagopar y devuelve el enlace de pago.
// Guarda la compra como pendiente hasta que el webhook la confirme.
// ═══════════════════════════════════════════════════════════════════

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

// Pagopar firma con SHA1, igual que sha1() de PHP
async function sha1(texto: string): Promise<string> {
  const datos = new TextEncoder().encode(texto)
  const hash = await crypto.subtle.digest('SHA-1', datos)
  return Array.from(new Uint8Array(hash)).map(b => b.toString(16).padStart(2, '0')).join('')
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
      return responder({
        error: 'Faltan las claves de Pagopar. Cargá PAGOPAR_PUBLIC_KEY y PAGOPAR_PRIVATE_KEY en Supabase → Settings → Edge Functions.'
      }, 400)
    }

    // ─── Leer lo que nos mandaron ───
    let cuerpo: any = {}
    try {
      const crudo = await req.text()
      if (!crudo || !crudo.trim()) {
        return responder({ error: 'No llegaron los datos de la compra. Probá de nuevo desde el sitio.' }, 400)
      }
      cuerpo = JSON.parse(crudo)
    } catch (e) {
      return responder({ error: 'Los datos de la compra llegaron mal formados.' }, 400)
    }

    const { curso_slug, email, nombre, telefono, documento, usuario_id } = cuerpo

    if (!curso_slug) return responder({ error: 'Falta indicar el curso' }, 400)
    if (!email) return responder({ error: 'Falta el email' }, 400)
    if (!nombre) return responder({ error: 'Falta el nombre' }, 400)

    // Pagopar exige la cédula, solo números y de 5 a 24 dígitos
    const doc = String(documento || '').replace(/[^0-9]/g, '')
    if (doc.length < 5) {
      return responder({ error: 'Necesitamos tu número de cédula (al menos 5 dígitos) para procesar el pago.' }, 400)
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    )

    // ─── El curso ───
    const { data: curso, error: errCurso } = await supabase
      .from('cursos').select('*').eq('slug', curso_slug).maybeSingle()

    if (errCurso) return responder({ error: 'No pudimos leer el curso: ' + errCurso.message }, 500)
    if (!curso) return responder({ error: 'No encontramos ese curso' }, 404)

    const monto = Number(curso.precio_gs || 0)
    if (monto <= 0) {
      return responder({ error: 'Este curso no tiene precio cargado. Si es gratis, no pasa por Pagopar.' }, 400)
    }

    // ─── Quién compra ───
    // Sin esto, después no sabemos a quién darle el curso
    let compradorId = usuario_id || null

    if (!compradorId && email) {
      const { data: perfil } = await supabase
        .from('perfiles').select('id').ilike('email', String(email).trim()).maybeSingle()
      if (perfil) compradorId = perfil.id
    }

    if (!compradorId) {
      return responder({
        error: 'No pudimos identificar tu cuenta. Iniciá sesión antes de comprar.'
      }, 400)
    }

    // ─── El pedido ───
    // Pagopar exige entre Gs 1.000 y Gs 50.000.000
    if (monto < 1000) {
      return responder({ error: 'Pagopar no acepta cobros menores a Gs 1.000. Este curso cuesta Gs ' + monto + '.' }, 400)
    }
    if (monto > 50000000) {
      return responder({ error: 'Pagopar no acepta cobros mayores a Gs 50.000.000.' }, 400)
    }

    // El token se firma con el monto en texto, pero el campo va como número.
    // En PHP es strval(floatval(monto)): 5000 → "5000"
    const montoStr = String(monto)
    const idPedido = 'CMM-' + Date.now() + '-' + Math.random().toString(36).slice(2, 7)
    const token = await sha1(PRIVATE_KEY + idPedido + montoStr)

    const vence = new Date()
    vence.setDate(vence.getDate() + 3)
    const venceStr = vence.toISOString().slice(0, 19).replace('T', ' ')

    const pedido = {
      token: token,
      public_key: PUBLIC_KEY,
      monto_total: monto,
      tipo_pedido: 'VENTA-COMERCIO',
      fecha_maxima_pago: venceStr,
      id_pedido_comercio: idPedido,
      descripcion_resumen: String(curso.titulo).slice(0, 100),
      // La documentación pide que este campo exista, aunque sea vacío
      descripcion: String(curso.descripcion || curso.titulo).slice(0, 200),
      comprador: {
        ruc: '',
        email: String(email).trim(),
        ciudad: '1',
        nombre: String(nombre).trim(),
        telefono: (() => {
          const t = String(telefono || '').replace(/[^0-9]/g, '')
          if (!t) return ''
          if (t.startsWith('595')) return '+' + t
          if (t.startsWith('0')) return '+595' + t.slice(1)
          return '+595' + t
        })(),
        direccion: 'Paraguay',
        // Pagopar solo acepta números, entre 5 y 24 caracteres
        documento: String(documento || '').replace(/[^0-9]/g, '').slice(0, 24),
        coordenadas: '',
        razon_social: String(nombre).trim(),
        tipo_documento: 'CI',
        direccion_referencia: '',
      },
      compras_items: [{
        ciudad: '1',
        nombre: String(curso.titulo).slice(0, 100),
        cantidad: 1,
        categoria: '909',
        public_key: PUBLIC_KEY,
        url_imagen: curso.foto_portada || '',
        descripcion: String(curso.titulo).slice(0, 100),
        id_producto: 1,
        precio_total: monto,
        vendedor_telefono: '',
        vendedor_direccion: '',
        vendedor_direccion_referencia: '',
        vendedor_direccion_coordenadas: '',
      }],
    }

    // ─── Llamar a Pagopar ───
    // Si Pagopar te da otra dirección para pruebas, cambiala acá
    const URL_PAGOPAR = 'https://api.pagopar.com/api/comercios/2.0/iniciar-transaccion'

    let respuesta: Response
    try {
      respuesta = await fetch(URL_PAGOPAR, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Accept': 'application/json' },
        body: JSON.stringify(pedido),
      })
    } catch (e) {
      return responder({ error: 'No pudimos conectarnos con Pagopar: ' + String(e?.message || e) }, 502)
    }

    // Leemos como texto primero: así vemos el mensaje real aunque no sea JSON
    const crudo = await respuesta.text()

    console.log('[pagopar] estado HTTP:', respuesta.status)
    console.log('[pagopar] respuesta:', crudo.slice(0, 600))

    if (!crudo || !crudo.trim()) {
      return responder({
        error: 'Pagopar respondió vacío (HTTP ' + respuesta.status + '). ' +
               'Suele pasar si el token privado no coincide o el comercio no está habilitado.',
        estado_http: respuesta.status,
      }, 502)
    }

    let datos: any
    try {
      datos = JSON.parse(crudo)
    } catch (e) {
      return responder({
        error: 'Pagopar no devolvió JSON. Esto suele indicar un problema de configuración del comercio.',
        respuesta_pagopar: crudo.slice(0, 400),
        estado_http: respuesta.status,
      }, 502)
    }

    // ─── ¿Salió bien? ───
    if (!datos.respuesta) {
      let motivo = ''
      if (typeof datos.resultado === 'string') motivo = datos.resultado
      else if (Array.isArray(datos.resultado)) motivo = JSON.stringify(datos.resultado)
      else if (datos.mensaje) motivo = datos.mensaje
      else motivo = JSON.stringify(datos).slice(0, 300)

      // Traducimos los más comunes
      const m = motivo.toLowerCase()
      let ayuda = ''
      if (m.includes('virtual')) {
        ayuda = ' → El comercio todavía no está habilitado para productos virtuales.'
      } else if (m.includes('token')) {
        ayuda = ' → Revisá que PAGOPAR_PRIVATE_KEY sea exactamente el token privado de tu panel.'
      } else if (m.includes('public')) {
        ayuda = ' → Revisá PAGOPAR_PUBLIC_KEY.'
      } else if (m.includes('categoria')) {
        ayuda = ' → La categoría del producto no es válida para tu comercio.'
      }

      return responder({
        error: 'Pagopar rechazó el pedido: ' + motivo + ayuda,
        // Todo lo que nos dijo Pagopar, sin recortar
        diagnostico: {
          respuesta_cruda: crudo.slice(0, 800),
          estado_http: respuesta.status,
          url_usada: URL_PAGOPAR,
          public_key_termina_en: PUBLIC_KEY.slice(-6),
          private_key_largo: PRIVATE_KEY.length,
          monto_enviado: montoStr,
          id_pedido: idPedido,
        }
      }, 400)
    }

    // ─── El hash del pedido ───
    const hash = Array.isArray(datos.resultado)
      ? (datos.resultado[0]?.data || datos.resultado[0]?.hash)
      : (datos.resultado?.data || datos.resultado?.hash)

    if (!hash) {
      return responder({
        error: 'Pagopar aceptó el pedido pero no devolvió el código de pago.',
        respuesta_pagopar: JSON.stringify(datos).slice(0, 400),
      }, 502)
    }

    // ─── Guardar la compra pendiente ───
    const { error: errCompra } = await supabase.from('compras').insert({
      usuario_id: compradorId,
      curso_id: curso.id,
      monto_gs: monto,
      estado: 'pendiente',
      metodo_pago: 'pagopar',
      pagopar_id: hash,
      pagopar_pedido: idPedido,
    })

    if (errCompra) {
      console.error('[pagopar] no se pudo guardar la compra:', errCompra.message)
      // No frenamos el pago: el webhook la puede crear después
    }

    return responder({
      exito: true,
      hash: hash,
      url_pago: 'https://www.pagopar.com/pagos/' + hash,
    })

  } catch (error) {
    console.error('[pagopar] error inesperado:', error)
    return responder({ error: 'Error inesperado: ' + String(error?.message || error) }, 500)
  }
})
