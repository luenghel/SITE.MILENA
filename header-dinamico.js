// ═══════════════════════════════════════════════════════
// HEADER DINÁMICO - MILENA MACHADO
// Cambia el botón "ENTRAR" por avatar + nombre cuando hay sesión
// ═══════════════════════════════════════════════════════

// Esperar a que Supabase esté listo
window.onSupabaseReady = async () => {
  await actualizarHeader();
};

async function actualizarHeader() {
  // Buscar todos los botones "ENTRAR" del sitio
  const botonesEntrar = document.querySelectorAll('a[href="/login"].btn-outline');

  if (botonesEntrar.length === 0) return;

  // Verificar si hay sesión
  const user = await obtenerUsuario();

  if (!user) {
    // No hay sesión, dejar el botón "ENTRAR" como está
    return;
  }

  // Hay sesión, obtener el perfil
  const perfil = await obtenerPerfil();
  const nombre = perfil?.nombre || user.email.split('@')[0];
  const inicial = nombre.charAt(0).toUpperCase();

  // Reemplazar cada botón "ENTRAR" por el avatar
  botonesEntrar.forEach(btn => {
    const wrapper = document.createElement('div');
    wrapper.className = 'user-menu-wrapper';
    wrapper.style.cssText = 'position:relative;display:inline-block';
    wrapper.innerHTML = `
      <button class="user-menu-btn" onclick="toggleUserMenu(event)" style="display:flex;align-items:center;gap:9px;padding:6px 14px 6px 6px;background:rgba(255,245,240,0.04);border:0.5px solid rgba(255,245,240,0.15);border-radius:24px;color:#FFF5F0;cursor:pointer;font-family:inherit;transition:all 0.25s">
        <div style="width:30px;height:30px;border-radius:50%;background:linear-gradient(135deg,#B8294A,#E8B8C4);display:flex;align-items:center;justify-content:center;font-family:Georgia,serif;font-style:italic;font-weight:500;font-size:14px;color:#FFF5F0">${inicial}</div>
        <span style="font-size:12px;font-weight:500;letter-spacing:0.04em;max-width:120px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">${nombre}</span>
        <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="6 9 12 15 18 9"/></svg>
      </button>
      <div class="user-menu-dropdown" id="userMenuDropdown" style="display:none;position:absolute;right:0;top:calc(100% + 8px);min-width:220px;background:rgba(20,8,12,0.95);backdrop-filter:blur(20px);-webkit-backdrop-filter:blur(20px);border:0.5px solid rgba(212,163,86,0.3);border-radius:13px;padding:8px;box-shadow:0 12px 32px rgba(0,0,0,0.5);z-index:200;animation:slideDown 0.2s ease-out">
        <div style="padding:10px 12px 8px;border-bottom:0.5px solid rgba(255,245,240,0.06);margin-bottom:6px">
          <div style="font-size:13px;font-weight:500;color:#FFF5F0">${nombre}</div>
          <div style="font-size:11px;color:rgba(255,245,240,0.5);margin-top:2px">${user.email}</div>
        </div>
        <a href="/perfil" style="display:flex;align-items:center;gap:10px;padding:9px 12px;font-size:12.5px;color:rgba(255,245,240,0.85);text-decoration:none;border-radius:8px;transition:background 0.2s" onmouseover="this.style.background='rgba(255,245,240,0.06)'" onmouseout="this.style.background='transparent'">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>
          Mi perfil
        </a>
        <a href="/cursos" style="display:flex;align-items:center;gap:10px;padding:9px 12px;font-size:12.5px;color:rgba(255,245,240,0.85);text-decoration:none;border-radius:8px;transition:background 0.2s" onmouseover="this.style.background='rgba(255,245,240,0.06)'" onmouseout="this.style.background='transparent'">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><path d="M12 2L2 7l10 5 10-5-10-5z"/><path d="M2 17l10 5 10-5M2 12l10 5 10-5"/></svg>
          Mis cursos
        </a>
        <a href="/comunidad" style="display:flex;align-items:center;gap:10px;padding:9px 12px;font-size:12.5px;color:rgba(255,245,240,0.85);text-decoration:none;border-radius:8px;transition:background 0.2s" onmouseover="this.style.background='rgba(255,245,240,0.06)'" onmouseout="this.style.background='transparent'">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><rect x="2" y="4" width="20" height="14" rx="2"/></svg>
          Comunidad
        </a>
        ${perfil?.rol === 'admin' || perfil?.rol === 'fundadora' ? `
        <a href="/admin" style="display:flex;align-items:center;gap:10px;padding:9px 12px;font-size:12.5px;color:#FAC775;text-decoration:none;border-radius:8px;transition:background 0.2s" onmouseover="this.style.background='rgba(212,163,86,0.08)'" onmouseout="this.style.background='transparent'">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 1 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 1 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 1 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 1 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/></svg>
          Panel Admin
        </a>` : ''}
        <div style="height:0.5px;background:rgba(255,245,240,0.06);margin:6px 4px"></div>
        <button onclick="cerrarSesion()" style="display:flex;align-items:center;gap:10px;padding:9px 12px;font-size:12.5px;color:#FF8090;background:transparent;border:none;width:100%;text-align:left;border-radius:8px;cursor:pointer;font-family:inherit;transition:background 0.2s" onmouseover="this.style.background='rgba(255,59,71,0.08)'" onmouseout="this.style.background='transparent'">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9" stroke-linecap="round" stroke-linejoin="round"/></svg>
          Cerrar sesión
        </button>
      </div>
    `;
    btn.replaceWith(wrapper);
  });

  // Agregar el CSS de animación si no existe
  if (!document.getElementById('userMenuStyles')) {
    const style = document.createElement('style');
    style.id = 'userMenuStyles';
    style.textContent = `
      @keyframes slideDown {
        from { opacity: 0; transform: translateY(-6px); }
        to { opacity: 1; transform: translateY(0); }
      }
      .user-menu-btn:hover { background: rgba(255,245,240,0.08) !important; transform: translateY(-1px); }
    `;
    document.head.appendChild(style);
  }

  // Cerrar el menú si clickean fuera
  document.addEventListener('click', (e) => {
    const dropdown = document.getElementById('userMenuDropdown');
    const wrapper = e.target.closest('.user-menu-wrapper');
    if (!wrapper && dropdown) {
      dropdown.style.display = 'none';
    }
  });
}

function toggleUserMenu(event) {
  event.stopPropagation();
  const dropdown = document.getElementById('userMenuDropdown');
  if (dropdown) {
    dropdown.style.display = dropdown.style.display === 'none' ? 'block' : 'none';
  }
}
