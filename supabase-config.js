// ═══════════════════════════════════════════════════════
// CONFIGURACIÓN DE SUPABASE - MILENA MACHADO
// Proyecto: comunidad milena
// ═══════════════════════════════════════════════════════

const SUPABASE_URL = 'https://pdwooahpyustbqlrvlxz.supabase.co';
const SUPABASE_ANON_KEY = 'sb_publishable_3ED52aGMAAPuOTnFGRWM1Q_IHjmgmOp';

// Cliente de Supabase (se inicializa cuando carga la librería)
let sb = null;

// Cargar Supabase desde CDN
const supabaseScript = document.createElement('script');
supabaseScript.src = 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/dist/umd/supabase.js';
document.head.appendChild(supabaseScript);

supabaseScript.onload = () => {
  sb = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
  console.log('✅ Supabase conectado');
  if (window.onSupabaseReady) window.onSupabaseReady();
};

supabaseScript.onerror = () => {
  console.error('❌ No se pudo cargar Supabase. Verificá tu conexión a internet o que estés sirviendo el sitio con un servidor local.');
};


// ═══════════════════════════════════════════════════════
// CACHÉ DE SESIÓN  (elimina el parpadeo "ENTRAR → avatar")
// Guarda nombre/rol/avatar para pintar el header al instante,
// sin esperar a que cargue Supabase desde el CDN.
// ═══════════════════════════════════════════════════════

const CACHE_SESION = 'cmm_sesion';

function guardarCacheSesion(datos) {
  try { localStorage.setItem(CACHE_SESION, JSON.stringify(datos)); } catch(e){}
}

function leerCacheSesion() {
  try {
    const raw = localStorage.getItem(CACHE_SESION);
    return raw ? JSON.parse(raw) : null;
  } catch(e){ return null; }
}

function limpiarCacheSesion() {
  try { localStorage.removeItem(CACHE_SESION); } catch(e){}
}

// Refresca el caché con los datos reales del perfil
async function refrescarCacheSesion() {
  if (!sb) return null;
  const { data: { user } } = await sb.auth.getUser();
  if (!user) { limpiarCacheSesion(); return null; }

  const { data: perfil } = await sb
    .from('perfiles')
    .select('nombre, email, rol, avatar_url')
    .eq('id', user.id)
    .maybeSingle();

  const datos = {
    id: user.id,
    email: perfil?.email || user.email,
    nombre: perfil?.nombre || user.email.split('@')[0],
    rol: perfil?.rol || 'alumna',
    avatar_url: perfil?.avatar_url || null
  };
  guardarCacheSesion(datos);
  return datos;
}

// ═══════════════════════════════════════════════════════
// FUNCIONES DE AUTENTICACIÓN
// ═══════════════════════════════════════════════════════

// REGISTRO de nueva alumna
async function registrarse(email, password, nombre) {
  if (!sb) return { exito: false, error: 'Supabase no está conectado todavía' };
  const { data, error } = await sb.auth.signUp({
    email: email,
    password: password,
    options: {
      data: { nombre: nombre }
    }
  });
  if (error) return { exito: false, error: error.message };
  return { exito: true, data: data };
}

// LOGIN con email y contraseña
async function iniciarSesion(email, password) {
  if (!sb) return { exito: false, error: 'Supabase no está conectado todavía' };
  const { data, error } = await sb.auth.signInWithPassword({
    email: email,
    password: password
  });
  if (error) return { exito: false, error: error.message };
  return { exito: true, data: data };
}

// LOGOUT
async function cerrarSesion() {
  limpiarCacheSesion();
  if (!sb) return { exito: false, error: 'Supabase no está conectado' };
  const { error } = await sb.auth.signOut();
  if (error) return { exito: false, error: error.message };
  window.location.href = '/';
  return { exito: true };
}

// VERIFICAR si hay sesión activa
async function obtenerUsuario() {
  if (!sb) return null;
  const { data: { user } } = await sb.auth.getUser();
  return user;
}

// OBTENER perfil completo desde la tabla perfiles
async function obtenerPerfil() {
  if (!sb) return null;
  const user = await obtenerUsuario();
  if (!user) return null;
  const { data, error } = await sb
    .from('perfiles')
    .select('*')
    .eq('id', user.id)
    .single();
  if (error) return null;
  return data;
}

// RECUPERAR contraseña por email
async function recuperarPassword(email) {
  if (!sb) return { exito: false, error: 'Supabase no está conectado' };
  const { data, error } = await sb.auth.resetPasswordForEmail(email);
  if (error) return { exito: false, error: error.message };
  return { exito: true };
}

// REDIRIGIR si NO está logueado (usar en páginas privadas)
async function requerirLogin() {
  const user = await obtenerUsuario();
  if (!user) {
    window.location.href = '/login';
    return null;
  }
  return user;
}

// REDIRIGIR si YA está logueado (usar en login/registro)
async function redirigirSiLogueado() {
  const user = await obtenerUsuario();
  if (user) {
    window.location.href = '/';
  }
}


// ═══════════════════════════════════════════════════════
// SUBIR IMÁGENES AL STORAGE
// ═══════════════════════════════════════════════════════

// Subir una imagen al bucket "imagenes"
async function subirImagen(archivo, carpeta) {
  if (!sb) return { exito: false, error: 'Supabase no conectado' };
  if (!archivo) return { exito: false, error: 'No hay archivo' };

  // Generar nombre único
  const ext = archivo.name.split('.').pop().toLowerCase();
  const nombreUnico = `${carpeta || 'general'}/${Date.now()}-${Math.random().toString(36).substr(2, 9)}.${ext}`;

  const { data, error } = await sb.storage
    .from('imagenes')
    .upload(nombreUnico, archivo, {
      cacheControl: '3600',
      upsert: false
    });

  if (error) return { exito: false, error: error.message };

  // Obtener URL pública
  const { data: urlData } = sb.storage
    .from('imagenes')
    .getPublicUrl(nombreUnico);

  return { exito: true, url: urlData.publicUrl, path: nombreUnico };
}

// Borrar una imagen del storage
async function borrarImagen(path) {
  if (!sb || !path) return { exito: false };
  const { error } = await sb.storage.from('imagenes').remove([path]);
  return { exito: !error, error: error?.message };
}


// ═══════════════════════════════════════════════════════
// LLAMAR A LA FUNCIÓN DE ADMINISTRACIÓN
// Supabase asigna nombres al azar, así que la buscamos
// y recordamos la que responde.
// ═══════════════════════════════════════════════════════

const CANDIDATAS_FUNC_ADM = [
  'clever-processor',                 // FUNCION-ADM en este proyecto
  'Edge-function-admin-miembros',
  'admin-miembros', 'clever-process', 'clever-proc',
  'clever-service', 'clever-worker', 'clever-endpoint', 'clever-api',
  'clever-responder', 'clever-function', 'clever-handler'
];

function urlFuncionGuardada() {
  try { return localStorage.getItem('cmm_func_admin'); } catch(e) { return null; }
}

function guardarUrlFuncion(nombre) {
  try { localStorage.setItem('cmm_func_admin', nombre); } catch(e) {}
}

let _nombreFuncAdmin = null;

async function nombreFuncionAdmin() {
  if (_nombreFuncAdmin) return _nombreFuncAdmin;
  try {
    const { data } = await sb.from('ajustes').select('valor').eq('clave', 'func_admin').maybeSingle();
    if (data && data.valor) { _nombreFuncAdmin = data.valor.trim(); return _nombreFuncAdmin; }
  } catch(e) {}
  return urlFuncionGuardada();
}

async function llamarFuncionAdmin(cuerpo) {
  if (!sb) return { ok: false, status: 0, datos: {}, noEncontrada: true };

  const { data: { session } } = await sb.auth.getSession();
  const cabeceras = {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer ' + (session?.access_token || SUPABASE_ANON_KEY),
    'apikey': SUPABASE_ANON_KEY
  };

  const guardada = await nombreFuncionAdmin();
  const lista = guardada
    ? [guardada, ...CANDIDATAS_FUNC_ADM.filter(x => x !== guardada)]
    : CANDIDATAS_FUNC_ADM;

  for (const nombre of lista) {
    try {
      const r = await fetch(SUPABASE_URL + '/functions/v1/' + nombre, {
        method: 'POST', headers: cabeceras, body: JSON.stringify(cuerpo)
      });

      if (r.status === 404) continue;

      let d = {};
      try { d = await r.json(); } catch(e) {}

      guardarUrlFuncion(nombre);
      return { ok: r.ok, status: r.status, datos: d };
    } catch(e) {}
  }

  return { ok: false, status: 404, datos: {}, noEncontrada: true };
}

// Aviso de seguridad al cambiar la contraseña.
// Supabase ya lo manda solo con su plantilla "Password Changed",
// así que acá no hacemos nada (si no, llegarían dos emails).
// Si algún día se apaga esa opción, cambiar false por true.
const AVISO_PASSWORD_PROPIO = false;

async function avisarCambioPassword(detalle) {
  if (!AVISO_PASSWORD_PROPIO) return;
  try {
    await llamarFuncionAdmin({ accion: 'aviso-seguridad', detalle: detalle || null });
  } catch(e) {}
}


// ═══════════════════════════════════════════════════════════
// LIBERACIÓN DE CLASES
//
// Cada módulo decide UNA de dos cosas:
//   'modulo' → se libera entero, cuando diga el módulo
//   'clase'  → cada clase tiene su propia fecha
//
// Nunca se suman. Lo que diga el módulo manda.
// ═══════════════════════════════════════════════════════════

// Cuándo se libera esta clase. null = todavía no se inscribió
function fechaLiberacion(clase, modulo, curso, compra) {
  // De regalo: siempre disponible
  if ((modulo && modulo.gratis) || (clase && clase.gratis)) return 0;

  const tipo = (modulo && modulo.tipo_liberacion) || 'modulo';

  // Si el módulo se libera entero, manda el módulo. Si no, la clase.
  const cuando = (tipo === 'modulo')
    ? ((modulo && modulo.cuando_libera) || 'inmediata')
    : ((clase && clase.cuando_libera) || 'inmediata');

  const dias = (tipo === 'modulo')
    ? ((modulo && modulo.dias_liberacion) || 0)
    : ((clase && clase.dias_liberacion) || 0);

  const fechaFija = (tipo === 'modulo')
    ? (modulo && modulo.fecha_apertura)
    : (clase && clase.fecha_apertura);

  const inscripcion = compra && compra.pagado_en ? new Date(compra.pagado_en).getTime() : null;
  const lanzamiento = curso && curso.fecha_lanzamiento
    ? new Date(curso.fecha_lanzamiento).getTime()
    : (curso && curso.creado_en ? new Date(curso.creado_en).getTime() : Date.now());

  // Fecha exacta: la misma para todas
  if (cuando === 'fecha') {
    return fechaFija ? new Date(fechaFija).getTime() : Date.now();
  }

  if (cuando === 'inmediata') return inscripcion || Date.now();

  if (cuando === 'inscripcion') {
    if (!inscripcion) return null;
    return inscripcion + dias * 86400000;
  }

  if (cuando === 'lanzamiento') {
    return lanzamiento + dias * 86400000;
  }

  return inscripcion || Date.now();
}

// ¿Ya está disponible?
function claseDisponible(clase, curso, compra, todasLasClases, modulos) {
  const modulo = (modulos || []).find(m => m.id === clase.modulo_id) || null;
  const cuando = fechaLiberacion(clase, modulo, curso, compra);

  if (cuando === null) {
    return { libre: false, dias: 0, fecha: null, sinInscripcion: true };
  }

  // Contamos días de calendario, no bloques de 24 horas.
  // Si no, "en 3 horas" podía decir "mañana".
  const hoy = new Date(); hoy.setHours(0,0,0,0);
  const dia = new Date(cuando); dia.setHours(0,0,0,0);
  const faltan = Math.round((dia.getTime() - hoy.getTime()) / 86400000);

  return {
    libre: Date.now() >= cuando,
    dias: Math.max(0, faltan),
    horas: Math.max(0, Math.ceil((cuando - Date.now()) / 3600000)),
    fecha: new Date(cuando)
  };
}

// ¿Esta clase se puede ver sin comprar el curso?
function esDeRegalo(clase, modulos) {
  if (clase && clase.gratis) return true;
  const m = (modulos || []).find(x => x.id === clase.modulo_id);
  return !!(m && m.gratis);
}

function textoEspera(info) {
  if (info.libre) return '';
  if (info.sinInscripcion) return 'Anotate para desbloquearla';

  if (info.fecha) {
    const f = info.fecha;
    const hora = f.toLocaleTimeString('es-PY', { hour: '2-digit', minute: '2-digit' });
    const tieneHora = (f.getHours() !== 0 || f.getMinutes() !== 0);

    if (info.dias <= 0) {
      if (info.horas && info.horas <= 6) {
        return info.horas === 1 ? 'Se abre en 1 hora' : 'Se abre en ' + info.horas + ' horas';
      }
      return tieneHora ? 'Se abre hoy a las ' + hora : 'Se abre hoy';
    }
    if (info.dias === 1) return tieneHora ? 'Se abre mañana a las ' + hora : 'Se abre mañana';

    return 'Se abre el ' + f.toLocaleDateString('es-PY', { day: 'numeric', month: 'long' }) +
           (tieneHora ? ' a las ' + hora : '');
  }

  if (info.dias <= 0) return 'Se abre hoy';
  if (info.dias === 1) return 'Se abre mañana';
  return 'Se abre en ' + info.dias + ' días';
}

// El precio que le corresponde a esta persona
function precioParaVos(curso, esPremium) {
  if (esPremium && curso.precio_premium_gs) {
    return {
      precio: curso.precio_premium_gs,
      normal: curso.precio_gs,
      conDescuento: true
    };
  }
  return { precio: curso.precio_gs, normal: null, conDescuento: false };
}

// ═══════════════════════════════════════════════════════════
// EL CAMINO DE CADA PERSONA
// Anota los pasos para saber quién se interesó y no compró
// ═══════════════════════════════════════════════════════════

// ─── Quién es, cuando todavía no tiene cuenta ───
// Un código al azar guardado en su navegador. No dice quién es
// ni de dónde es: solo sirve para no contar diez veces a la misma.
function codigoVisitante() {
  try {
    let v = localStorage.getItem('cmm_visitante');
    if (!v) {
      v = 'v' + Date.now().toString(36) + Math.random().toString(36).slice(2, 10);
      localStorage.setItem('cmm_visitante', v);
    }
    return v;
  } catch (e) {
    // Navegador en privado: usamos uno que dura lo que dura la pestaña
    if (!window.__visitanteTemp) {
      window.__visitanteTemp = 'v' + Date.now().toString(36) + Math.random().toString(36).slice(2, 10);
    }
    return window.__visitanteTemp;
  }
}

function queDispositivo() {
  const a = navigator.userAgent || '';
  if (navigator.webdriver || /bot|crawl|spider|slurp|preview|lighthouse|headless|facebookexternalhit|whatsapp\/|telegrambot/i.test(a)) return 'bot';
  if (/iPad|Tablet|PlayBook|Silk|(Android(?!.*Mobile))/i.test(a)) return 'tablet';
  if (/Mobi|Android|iPhone|iPod|Windows Phone/i.test(a)) return 'celular';
  return 'computadora';
}

// ─── De qué anuncio vino (utm_source, fbclid...) ───
// Se guarda para toda la visita, aunque después cambie de página.
function queCampana() {
  try {
    const p = new URLSearchParams(location.search);
    let c = '';
    if (p.get('utm_source') || p.get('utm_campaign')) {
      c = [p.get('utm_source'), p.get('utm_medium'), p.get('utm_campaign')]
        .filter(Boolean).join(' · ');
    } else if (p.get('fbclid')) c = 'facebook · anuncio';
    else if (p.get('gclid')) c = 'google · anuncio';
    else if (p.get('ttclid')) c = 'tiktok · anuncio';
    if (c) sessionStorage.setItem('cmm_campana', c.slice(0, 120));
    return sessionStorage.getItem('cmm_campana') || '';
  } catch (e) { return ''; }
}

// ─── De dónde vino ───
// Instagram y Facebook abren el sitio en su propio navegador y casi
// nunca dicen de dónde venís: lo sacamos del navegador mismo.
function queReferencia() {
  const r = document.referrer || '';
  if (r && !/milenacmm\.com|vercel\.app|localhost/i.test(r)) return r;
  const a = navigator.userAgent || '';
  if (/Instagram/i.test(a)) return 'instagram-app';
  if (/FBAN|FBAV|FB_IAB/i.test(a)) return 'facebook-app';
  if (/musical_ly|TikTok|BytedanceWebview/i.test(a)) return 'tiktok-app';
  return r;
}

// La página, sin los códigos de los anuncios
function rutaLimpia() {
  try {
    const p = new URLSearchParams(location.search);
    ['utm_source','utm_medium','utm_campaign','utm_content','utm_term','fbclid','gclid','ttclid','igshid','mibextid']
      .forEach(k => p.delete(k));
    const q = p.toString();
    return (location.pathname + (q ? '?' + q : '')).slice(0, 180);
  } catch (e) { return location.pathname; }
}

function esPanel() { return /^\/admin/.test(location.pathname); }

// ═══════════════════════════════════════════════════════════
// ANOTAR CUALQUIER COSA
// Funciona con cuenta y sin cuenta. Nunca frena nada:
// no esperamos la respuesta y si falla, seguimos igual.
// El panel de admin no se cuenta.
// ═══════════════════════════════════════════════════════════
function anotarEvento(tipo, opciones) {
  const o = opciones || {};
  if (esPanel()) return;
  const disp = queDispositivo();
  if (disp === 'bot') return;
  (async function () {
    try {
      if (typeof sb === 'undefined' || !sb) return;
      await sb.rpc('anotar_evento', {
        p_tipo: tipo,
        p_visitante: codigoVisitante(),
        p_curso: o.curso || null,
        p_detalle: o.detalle || null,
        p_ruta: o.ruta || rutaLimpia(),
        p_referencia: o.referencia !== undefined ? o.referencia : queReferencia(),
        p_dispositivo: disp,
        p_campana: queCampana()
      });
    } catch (e) { /* seguimos igual */ }
  })();
}

// ═══════════════════════════════════════════════════════════
// CADA CLIC: qué tocó y en qué página
// Botones, enlaces y tarjetas. No guarda lo que escribe.
// Para ponerle un nombre fijo a algo: data-metrica="Comprar CMM"
// ═══════════════════════════════════════════════════════════
(function () {
  if (esPanel()) return;
  document.addEventListener('click', function (ev) {
    try {
      const el = ev.target.closest('[data-metrica],a,button,[onclick],[role="button"],summary');
      if (!el) return;
      if (el.matches('input,textarea,select')) return;

      let que = el.getAttribute('data-metrica') || el.getAttribute('aria-label') || '';
      if (!que) que = (el.innerText || '').replace(/\s+/g, ' ').trim();
      if (!que) { const img = el.querySelector('img[alt]'); if (img) que = img.alt; }
      if (!que) que = el.getAttribute('title') || '';
      if (!que && el.tagName === 'A') que = (el.getAttribute('href') || '').slice(0, 60);
      if (!que) que = '(' + el.tagName.toLowerCase() + ')';
      que = que.slice(0, 70);

      let destino = '';
      const a = el.tagName === 'A' ? el : el.closest('a');
      if (a && a.getAttribute('href')) {
        try {
          const u = new URL(a.getAttribute('href'), location.href);
          destino = u.host === location.host ? u.pathname + u.search : u.host + u.pathname;
        } catch (e) { destino = a.getAttribute('href'); }
      }

      anotarEvento('clic', { detalle: que, referencia: destino.slice(0, 180) });
    } catch (e) {}
  }, true);
})();

// Lo de antes, para no romper lo que ya estaba escrito
function anotarPaso(tipo, cursoId, detalle) {
  anotarEvento(tipo, { curso: cursoId, detalle: detalle });
}

// ─── La visita a esta página, apenas carga ───
function anotarVisita(detalle) {
  anotarEvento('visita', { detalle: detalle || document.title || '' });
}

// Lo llamamos solo en cuanto la página está lista
(function () {
  function arrancar() { setTimeout(anotarVisita, 800); }
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', arrancar);
  } else {
    arrancar();
  }
})();


// ═══════════════════════════════════════════════════════════
// CUÁNTO TIEMPO PASÓ MIRANDO
//
// Cuenta mientras la pestaña está a la vista. Si se va a otra
// pestaña o bloquea el celular, el reloj para. Manda lo juntado
// cada 30 segundos y cuando se va de la página.
// ═══════════════════════════════════════════════════════════
function medirTiempo(claseId, cursoId) {
  if (!claseId) return;

  let desde = Date.now();
  let acumulado = 0;
  let mandando = false;

  function juntar() {
    if (desde) {
      acumulado += Math.round((Date.now() - desde) / 1000);
      desde = Date.now();
    }
  }

  async function mandar(final) {
    juntar();
    if (acumulado < 5 || mandando) return;

    const segundos = Math.min(acumulado, 1200);
    acumulado = 0;
    mandando = true;

    try {
      if (typeof sb !== 'undefined' && sb) {
        await sb.rpc('sumar_tiempo', {
          p_clase: claseId,
          p_curso: cursoId || null,
          p_segundos: segundos
        });
      }
    } catch (e) { /* si falla, se pierde ese tramo y ya */ }

    mandando = false;
  }

  // Cada 30 segundos
  const reloj = setInterval(() => { if (!document.hidden) mandar(false); }, 30000);

  // Cuando cambia de pestaña, paramos el reloj
  document.addEventListener('visibilitychange', () => {
    if (document.hidden) { juntar(); desde = 0; mandar(false); }
    else { desde = Date.now(); }
  });

  // Cuando se va
  window.addEventListener('pagehide', () => { clearInterval(reloj); mandar(true); });
  window.addEventListener('beforeunload', () => { mandar(true); });

  return { mandar: () => mandar(true), parar: () => clearInterval(reloj) };
}
