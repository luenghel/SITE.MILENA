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
// LIBERACIÓN PROGRAMADA DE CLASES
//
// Tres formas, se elige UNA:
//   inmediata    → apenas se inscribe
//   inscripcion  → X días después de inscribirse
//   lanzamiento  → X días después del lanzamiento del curso
//
// Manda lo más específico: clase → módulo → curso.
// ═══════════════════════════════════════════════════════════

// Devuelve { modo, dias, origen } resolviendo la herencia
function configLiberacion(clase, modulo, curso) {
  if (clase && clase.modo_liberacion && clase.modo_liberacion !== 'heredar') {
    return { modo: clase.modo_liberacion, dias: clase.dias_liberacion || 0, origen: 'clase' };
  }
  if (modulo && modulo.modo_liberacion && modulo.modo_liberacion !== 'heredar') {
    return { modo: modulo.modo_liberacion, dias: modulo.dias_liberacion || 0, origen: 'modulo' };
  }
  return { modo: null, dias: 0, origen: 'curso' };
}

// Cuándo se libera esta clase para esta persona. null = no se sabe (no inscripta)
function fechaLiberacion(clase, modulo, curso, compra, todasLasClases, modulos) {
  const cfg = configLiberacion(clase, modulo, curso);
  const inscripcion = compra && compra.pagado_en ? new Date(compra.pagado_en).getTime() : null;
  const lanzamiento = curso && curso.fecha_lanzamiento
    ? new Date(curso.fecha_lanzamiento).getTime()
    : (curso && curso.creado_en ? new Date(curso.creado_en).getTime() : Date.now());

  // ─── Configuración propia de la clase o del módulo ───
  if (cfg.modo) {
    if (cfg.modo === 'inmediata') return inscripcion || Date.now();
    if (cfg.modo === 'inscripcion') {
      if (!inscripcion) return null;
      return inscripcion + cfg.dias * 86400000;
    }
    if (cfg.modo === 'lanzamiento') {
      return lanzamiento + cfg.dias * 86400000;
    }
  }

  // ─── Si no, lo que diga el curso ───
  const modoCurso = (curso && curso.modo_liberacion) || 'inmediata';
  const diasCurso = (curso && curso.dias_liberacion) || 0;

  if (modoCurso === 'espera') {
    if (!inscripcion) return null;
    return inscripcion + diasCurso * 86400000;
  }

  if (modoCurso === 'goteo') {
    if (!inscripcion) return null;
    const planas = [];
    (modulos || []).forEach(m => {
      (todasLasClases || [])
        .filter(x => x.modulo_id === m.id)
        .sort((a, b) => (a.orden || 0) - (b.orden || 0))
        .forEach(x => planas.push(x));
    });
    const pos = planas.findIndex(x => x.id === clase.id);
    return inscripcion + (pos < 0 ? 0 : pos) * (diasCurso || 1) * 86400000;
  }

  return inscripcion || Date.now();
}

// ¿Ya está disponible?
function claseDisponible(clase, curso, compra, todasLasClases, modulos) {
  const modulo = (modulos || []).find(m => m.id === clase.modulo_id) || null;
  const cuando = fechaLiberacion(clase, modulo, curso, compra, todasLasClases, modulos);

  if (cuando === null) {
    return { libre: false, dias: 0, fecha: null, sinInscripcion: true };
  }

  const faltan = Math.ceil((cuando - Date.now()) / 86400000);
  return {
    libre: Date.now() >= cuando,
    dias: Math.max(0, faltan),
    fecha: new Date(cuando)
  };
}

function textoEspera(info) {
  if (info.libre) return '';
  if (info.sinInscripcion) return 'Anotate para desbloquearla';
  if (info.dias <= 0) return 'Se libera hoy';
  if (info.dias === 1) return 'Se libera mañana';
  if (info.fecha) {
    return 'Se libera el ' + info.fecha.toLocaleDateString('es-PY', { day: 'numeric', month: 'long' });
  }
  return 'Se libera en ' + info.dias + ' días';
}


// ═══════════════════════════════════════════════════════════
// EMAIL DE BIENVENIDA AL INSCRIBIRSE
// Se llama después de crear el registro de inscripción.
// Si falla, no pasa nada: la persona ya tiene su acceso.
// ═══════════════════════════════════════════════════════════

const CANDIDATAS_AVISOS_JS = [
  'AVISAR-CLASES', 'avisar-clases', 'avisar-clases-liberadas',
  'quiet-api', 'quiet-worker', 'quiet-endpoint'
];

async function darBienvenida(cursoId, usuarioId) {
  if (!sb || !cursoId || !usuarioId) return;

  try {
    const { data: { session } } = await sb.auth.getSession();
    const cab = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ' + (session?.access_token || SUPABASE_ANON_KEY),
      'apikey': SUPABASE_ANON_KEY
    };

    // El nombre de la función lo tenemos guardado
    let guardada = null;
    try {
      const { data } = await sb.from('ajustes').select('valor').eq('clave', 'func_avisos_clases').maybeSingle();
      if (data && data.valor) guardada = data.valor.trim();
    } catch (e) {}

    const lista = guardada
      ? [guardada, ...CANDIDATAS_AVISOS_JS.filter(x => x !== guardada)]
      : CANDIDATAS_AVISOS_JS;

    for (const nombre of lista) {
      try {
        const r = await fetch(SUPABASE_URL + '/functions/v1/' + nombre, {
          method: 'POST',
          headers: cab,
          body: JSON.stringify({ accion: 'bienvenida', curso_id: cursoId, usuario_id: usuarioId })
        });
        if (r.status === 404) continue;
        return;
      } catch (e) {}
    }
  } catch (e) {
    // Nunca frenamos la inscripción por un problema de email
  }
}
