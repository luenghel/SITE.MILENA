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
