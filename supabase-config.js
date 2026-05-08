// ═══════════════════════════════════════════════════════
// CONFIGURACIÓN DE SUPABASE - MILENA MACHADO
// Proyecto: comunidad milena
// ═══════════════════════════════════════════════════════

const SUPABASE_URL = 'https://pdwooahpyustbqlrvlxz.supabase.co';
const SUPABASE_ANON_KEY = 'sb_publishable_3ED52aGMAAPuOTnFGRWM1Q_IHjmgmOp';

// Cargar Supabase desde CDN
const supabaseScript = document.createElement('script');
supabaseScript.src = 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/dist/umd/supabase.js';
document.head.appendChild(supabaseScript);

let supabase;

supabaseScript.onload = () => {
  supabase = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
  console.log('✅ Supabase conectado');
  if (window.onSupabaseReady) window.onSupabaseReady();
};

// ═══════════════════════════════════════════════════════
// FUNCIONES DE AUTENTICACIÓN
// ═══════════════════════════════════════════════════════

// REGISTRO de nueva alumna
async function registrarse(email, password, nombre) {
  const { data, error } = await supabase.auth.signUp({
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
  const { data, error } = await supabase.auth.signInWithPassword({
    email: email,
    password: password
  });
  if (error) return { exito: false, error: error.message };
  return { exito: true, data: data };
}

// LOGOUT
async function cerrarSesion() {
  const { error } = await supabase.auth.signOut();
  if (error) return { exito: false, error: error.message };
  window.location.href = 'index.html';
  return { exito: true };
}

// VERIFICAR si hay sesión activa
async function obtenerUsuario() {
  const { data: { user } } = await supabase.auth.getUser();
  return user;
}

// OBTENER perfil completo desde la tabla perfiles
async function obtenerPerfil() {
  const user = await obtenerUsuario();
  if (!user) return null;
  const { data, error } = await supabase
    .from('perfiles')
    .select('*')
    .eq('id', user.id)
    .single();
  if (error) return null;
  return data;
}

// RECUPERAR contraseña por email
async function recuperarPassword(email) {
  const { data, error } = await supabase.auth.resetPasswordForEmail(email);
  if (error) return { exito: false, error: error.message };
  return { exito: true };
}

// REDIRIGIR si NO está logueado (usar en páginas privadas)
async function requerirLogin() {
  const user = await obtenerUsuario();
  if (!user) {
    window.location.href = 'login.html';
    return null;
  }
  return user;
}

// REDIRIGIR si YA está logueado (usar en login/registro)
async function redirigirSiLogueado() {
  const user = await obtenerUsuario();
  if (user) {
    window.location.href = 'index.html';
  }
}
