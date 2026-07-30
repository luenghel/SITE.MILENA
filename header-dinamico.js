// ═══════════════════════════════════════════════════════════════════
// HEADER DINÁMICO - MILENA MACHADO
// 1. Pinta el avatar AL INSTANTE usando el caché (sin parpadeo)
// 2. Después corrige con los datos reales de Supabase
// 3. Agrega el menú de celular (hamburguesa + barra inferior)
// ═══════════════════════════════════════════════════════════════════

(function () {
  'use strict';

  // ─── Utilidades ──────────────────────────────────────────────────
  function esc(t) {
    if (!t) return '';
    const d = document.createElement('div');
    d.textContent = t;
    return d.innerHTML;
  }

  function inicialDe(n) {
    return (n || 'A').trim().charAt(0).toUpperCase();
  }

  function colorDe(nombre) {
    const p = [
      'linear-gradient(135deg,#7A1B2E,#E8B8C4)',
      'linear-gradient(135deg,#4A0F1E,#B8294A)',
      'linear-gradient(135deg,#D4A356,#E8B8C4)',
      'linear-gradient(135deg,#7A1B2E,#C97990)',
      'linear-gradient(135deg,#B8294A,#FAC775)'
    ];
    let h = 0;
    const s = nombre || 'x';
    for (let i = 0; i < s.length; i++) h = (h + s.charCodeAt(i)) % p.length;
    return p[h];
  }

  function rutaActual() {
    return window.location.pathname.replace(/\/$/, '').replace('.html', '') || '/index';
  }

  // ─── Estilos que necesita el header ──────────────────────────────
  function inyectarEstilos() {
    if (document.getElementById('cmm-header-css')) return;
    const st = document.createElement('style');
    st.id = 'cmm-header-css';
    st.textContent = `
      .cmm-user-wrap{position:relative;display:inline-block}
      .cmm-user-btn{display:flex;align-items:center;gap:9px;padding:6px 14px 6px 6px;background:rgba(255,245,240,0.05);border:0.5px solid rgba(255,245,240,0.16);border-radius:24px;color:#FFF5F0;cursor:pointer;font-family:inherit;transition:all 0.22s;max-width:190px}
      .cmm-user-btn:hover{background:rgba(255,245,240,0.1);border-color:rgba(212,163,86,0.45)}
      .cmm-user-av{width:30px;height:30px;border-radius:50%;flex-shrink:0;display:flex;align-items:center;justify-content:center;font-family:Georgia,serif;font-style:italic;font-weight:500;font-size:14px;color:#FFF5F0;background-size:cover;background-position:center}
      .cmm-user-name{font-size:12px;font-weight:500;letter-spacing:0.04em;max-width:110px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}

      .cmm-drop{display:none;position:absolute;right:0;top:calc(100% + 8px);min-width:225px;background:rgba(24,9,15,0.97);backdrop-filter:blur(20px);-webkit-backdrop-filter:blur(20px);border:0.5px solid rgba(212,163,86,0.3);border-radius:13px;padding:8px;box-shadow:0 14px 36px rgba(0,0,0,0.55);z-index:500;animation:cmmDrop 0.18s ease-out}
      .cmm-drop.show{display:block}
      @keyframes cmmDrop{from{opacity:0;transform:translateY(-6px)}to{opacity:1;transform:translateY(0)}}
      .cmm-drop-head{padding:10px 12px 9px;border-bottom:0.5px solid rgba(255,245,240,0.07);margin-bottom:6px}
      .cmm-drop-nombre{font-size:13px;font-weight:500;color:#FFF5F0}
      .cmm-drop-mail{font-size:11px;color:rgba(255,245,240,0.5);margin-top:2px;word-break:break-all}
      .cmm-drop-item{display:flex;align-items:center;gap:10px;padding:10px 12px;font-size:12.5px;color:rgba(255,245,240,0.85);text-decoration:none;border-radius:8px;transition:background 0.18s;background:none;border:none;width:100%;text-align:left;font-family:inherit;cursor:pointer}
      .cmm-drop-item:hover{background:rgba(255,245,240,0.07)}
      .cmm-drop-item.gold{color:#FAC775}
      .cmm-drop-item.gold:hover{background:rgba(212,163,86,0.1)}
      .cmm-drop-item.danger{color:#FF8090}
      .cmm-drop-item.danger:hover{background:rgba(255,59,71,0.1)}
      .cmm-drop-sep{height:0.5px;background:rgba(255,245,240,0.07);margin:6px 0}

      /* ── Botón hamburguesa (celular) ── */
      .cmm-burger{display:none;width:42px;height:42px;border-radius:12px;background:rgba(255,245,240,0.05);border:0.5px solid rgba(255,245,240,0.16);color:#FFF5F0;cursor:pointer;align-items:center;justify-content:center;flex-shrink:0;font-family:inherit}
      .cmm-burger:active{transform:scale(0.94)}

      /* ── Panel lateral (celular) ── */
      .cmm-panel-bg{position:fixed;inset:0;background:rgba(8,3,6,0.75);backdrop-filter:blur(6px);z-index:900;opacity:0;pointer-events:none;transition:opacity 0.25s}
      .cmm-panel-bg.show{opacity:1;pointer-events:auto}
      .cmm-panel{position:fixed;top:0;right:-320px;bottom:0;width:290px;max-width:84vw;background:linear-gradient(180deg,#250914 0%,#12060A 100%);border-left:0.5px solid rgba(212,163,86,0.25);z-index:901;transition:right 0.3s cubic-bezier(0.34,1.3,0.64,1);display:flex;flex-direction:column;padding-top:env(safe-area-inset-top,0px);overflow-y:auto}
      .cmm-panel.show{right:0}
      .cmm-panel-head{padding:22px 20px 18px;border-bottom:0.5px solid rgba(255,245,240,0.08);display:flex;align-items:center;gap:12px}
      .cmm-panel-av{width:46px;height:46px;border-radius:50%;flex-shrink:0;display:flex;align-items:center;justify-content:center;font-family:Georgia,serif;font-style:italic;font-size:20px;color:#FFF5F0;background-size:cover;background-position:center}
      .cmm-panel-links{padding:14px 12px;flex:1}
      .cmm-panel-link{display:flex;align-items:center;gap:13px;padding:14px 14px;font-size:14px;color:rgba(255,245,240,0.85);text-decoration:none;border-radius:11px;margin-bottom:3px;transition:all 0.18s;background:none;border:none;width:100%;text-align:left;font-family:inherit;cursor:pointer}
      .cmm-panel-link:active{background:rgba(255,245,240,0.07)}
      .cmm-panel-link.active{background:linear-gradient(135deg,rgba(212,163,86,0.18),rgba(212,163,86,0.05));color:#FAC775;border:0.5px solid rgba(212,163,86,0.4)}
      .cmm-panel-link.gold{color:#FAC775}
      .cmm-panel-link.danger{color:#FF8090}
      .cmm-panel-close{position:absolute;top:calc(16px + env(safe-area-inset-top,0px));right:16px;width:34px;height:34px;border-radius:50%;background:rgba(255,245,240,0.07);border:none;color:#FFF5F0;cursor:pointer;display:flex;align-items:center;justify-content:center}
      .cmm-panel-foot{padding:16px 20px calc(20px + env(safe-area-inset-bottom,0px));border-top:0.5px solid rgba(255,245,240,0.08)}

      .cmm-acciones{display:flex;align-items:center;gap:12px;margin-left:auto}

      /* ── CELULAR: los links de navegación siempre visibles ── */
      @media (max-width:900px){
        .cmm-burger{display:none !important}

        .header-inner{
          flex-wrap:wrap;
          row-gap:9px;
          align-items:center;
        }
        .header-inner .logo{order:1;min-width:0;flex-shrink:1}
        .cmm-acciones{order:2;margin-left:auto}

        /* Los links pasan a una segunda fila, siempre a la vista */
        .main-header .nav-btn,
        header.main .nav-btn{
          display:inline-flex !important;
          order:3;
          padding:7px 11px !important;
          font-size:10.5px !important;
          letter-spacing:0.1em !important;
          border-radius:16px;
          background:rgba(255,245,240,0.05);
          border:0.5px solid rgba(255,245,240,0.12);
          white-space:nowrap;
        }
        .main-header .nav-btn.active,
        header.main .nav-btn.active{
          background:linear-gradient(135deg,rgba(212,163,86,0.2),rgba(212,163,86,0.06));
          border-color:rgba(212,163,86,0.5);
          color:#FAC775;
        }
        .cmm-navfila{
          order:3;
          width:100%;
          display:flex;
          gap:7px;
          overflow-x:auto;
          padding-bottom:2px;
          scrollbar-width:none;
        }
        .cmm-navfila::-webkit-scrollbar{display:none}

        .cmm-acciones .btn-outline{
          padding:9px 15px !important;
          font-size:10.5px !important;
          letter-spacing:0.12em !important;
          white-space:nowrap;
        }
        .cmm-user-name{display:none}
        .cmm-user-btn{padding:3px;max-width:none}
        .cmm-user-av{width:34px;height:34px;border:1.5px solid rgba(212,163,86,0.55)}
        .cmm-drop{right:0;min-width:210px}
        .logo-text{overflow:hidden;text-overflow:ellipsis}
      }
    `;
    document.head.appendChild(st);
  }

  // ─── Avatar (HTML) ───────────────────────────────────────────────
  function avatarHtml(s, clase) {
    if (s.avatar_url) {
      return '<div class="' + clase + '" style="background-image:url(\'' + esc(s.avatar_url) + '\')"></div>';
    }
    return '<div class="' + clase + '" style="background:' + colorDe(s.nombre) + '">' + inicialDe(s.nombre) + '</div>';
  }

  // ─── Botón de usuario en el header ───────────────────────────────
  function pintarUsuario(s) {
    const contenedores = document.querySelectorAll('a[href="/login"].btn-outline, .cmm-user-wrap');
    if (contenedores.length === 0) return;

    const esEquipo = s.rol === 'admin' || s.rol === 'fundadora';

    contenedores.forEach(function (el) {
      const wrap = document.createElement('div');
      wrap.className = 'cmm-user-wrap';
      wrap.innerHTML =
        '<button class="cmm-user-btn" type="button" data-cmm-toggle>' +
          avatarHtml(s, 'cmm-user-av') +
          '<span class="cmm-user-name">' + esc(s.nombre) + '</span>' +
          '<svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="6 9 12 15 18 9"/></svg>' +
        '</button>' +
        '<div class="cmm-drop">' +
          '<div class="cmm-drop-head">' +
            '<div class="cmm-drop-nombre">' + esc(s.nombre) + '</div>' +
            '<div class="cmm-drop-mail">' + esc(s.email) + '</div>' +
          '</div>' +
          '<a href="/perfil" class="cmm-drop-item">' +
            '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>Mi perfil</a>' +
          '<a href="/cursos" class="cmm-drop-item">' +
            '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><path d="M12 2L2 7l10 5 10-5-10-5z"/><path d="M2 17l10 5 10-5M2 12l10 5 10-5"/></svg>Mis cursos</a>' +
          '<a href="/comunidad" class="cmm-drop-item">' +
            '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><rect x="2" y="4" width="20" height="14" rx="2"/></svg>Comunidad</a>' +
          (esEquipo
            ? '<a href="/admin" class="cmm-drop-item gold">' +
              '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 1 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 1 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 1 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 1 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/></svg>Panel Admin</a>'
            : '') +
          '<div class="cmm-drop-sep"></div>' +
          '<button class="cmm-drop-item danger" type="button" data-cmm-salir>' +
            '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><polyline points="16 17 21 12 16 7"/><line x1="21" y1="12" x2="9" y2="12"/></svg>Cerrar sesión</button>' +
        '</div>';
      el.replaceWith(wrap);
    });
  }

  // ─── Panel lateral de celular ────────────────────────────────────
  function pintarPanel(s) {
    document.getElementById('cmmPanelBg')?.remove();
    document.getElementById('cmmPanel')?.remove();

    const ruta = rutaActual();
    const esEquipo = s && (s.rol === 'admin' || s.rol === 'fundadora');

    const links = [
      { href: '/index', txt: 'Inicio', icon: '<path d="M3 10l9-7 9 7v10a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/><polyline points="9 22 9 12 15 12 15 22"/>' },
      { href: '/cursos', txt: 'Cursos', icon: '<path d="M12 2L2 7l10 5 10-5-10-5z"/><path d="M2 17l10 5 10-5M2 12l10 5 10-5"/>' },
      { href: '/comunidad', txt: 'Comunidad', icon: '<rect x="2" y="4" width="20" height="14" rx="2"/>' },
      { href: '/blog', txt: 'Blog', icon: '<path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/>' }
    ];

    const bg = document.createElement('div');
    bg.className = 'cmm-panel-bg';
    bg.id = 'cmmPanelBg';

    const panel = document.createElement('div');
    panel.className = 'cmm-panel';
    panel.id = 'cmmPanel';

    let head;
    if (s) {
      head =
        '<div class="cmm-panel-head">' +
          avatarHtml(s, 'cmm-panel-av') +
          '<div style="min-width:0">' +
            '<div style="font-size:14.5px;font-weight:500">' + esc(s.nombre) + '</div>' +
            '<div style="font-size:11.5px;color:rgba(255,245,240,0.5);word-break:break-all">' + esc(s.email) + '</div>' +
          '</div>' +
        '</div>';
    } else {
      head =
        '<div class="cmm-panel-head">' +
          '<div class="cmm-panel-av" style="background:rgba(255,245,240,0.08)">M</div>' +
          '<div><div style="font-size:14px;font-weight:500">Milena Machado</div>' +
          '<div style="font-size:11.5px;color:rgba(255,245,240,0.5)">Creando Mentes Millonarias</div></div>' +
        '</div>';
    }

    let cuerpo = '<div class="cmm-panel-links">';
    links.forEach(function (l) {
      cuerpo +=
        '<a href="' + l.href + '" class="cmm-panel-link' + (ruta === l.href ? ' active' : '') + '">' +
          '<svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7">' + l.icon + '</svg>' +
          l.txt +
        '</a>';
    });

    if (s) {
      cuerpo +=
        '<a href="/perfil" class="cmm-panel-link' + (ruta === '/perfil' ? ' active' : '') + '">' +
          '<svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>Mi perfil</a>';
      if (esEquipo) {
        cuerpo +=
          '<a href="/admin" class="cmm-panel-link gold">' +
            '<svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 1 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 1 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 1 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 1 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/></svg>Panel Admin</a>';
      }
    }
    cuerpo += '</div>';

    const pie = s
      ? '<div class="cmm-panel-foot"><button class="cmm-panel-link danger" type="button" data-cmm-salir>' +
        '<svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><polyline points="16 17 21 12 16 7"/><line x1="21" y1="12" x2="9" y2="12"/></svg>Cerrar sesión</button></div>'
      : '<div class="cmm-panel-foot"><a href="/login" class="cta-gold" style="display:block;text-align:center;padding:14px;border-radius:12px;font-size:12.5px;letter-spacing:0.16em;font-weight:500;text-decoration:none">ENTRAR</a></div>';

    panel.innerHTML =
      '<button class="cmm-panel-close" type="button" data-cmm-cerrar>' +
        '<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><path d="M18 6L6 18M6 6l12 12"/></svg>' +
      '</button>' + head + cuerpo + pie;

    document.body.appendChild(bg);
    document.body.appendChild(panel);
  }

  // Deja el avatar y los 3 puntitos juntos, alineados a la derecha
  function agruparAcciones() {
    const header = document.querySelector('.header-inner');
    if (!header) return null;
    let caja = header.querySelector('.cmm-acciones');
    if (!caja) {
      caja = document.createElement('div');
      caja.className = 'cmm-acciones';
      header.appendChild(caja);
    }
    // Mover adentro el bloque de usuario (o el botón ENTRAR)
    const usuario = header.querySelector('.cmm-user-wrap') || header.querySelector('a[href="/login"].btn-outline');
    if (usuario && usuario.parentElement !== caja) {
      const cont = usuario.parentElement;
      caja.insertBefore(usuario, caja.firstChild);
      if (cont && cont !== header && cont !== caja && cont.children.length === 0) cont.remove();
    }
    return caja;
  }

  // Junta los links en una fila propia, que se desliza si no entran
  function armarFilaNav() {
    const header = document.querySelector('.header-inner');
    if (!header || header.querySelector('.cmm-navfila')) return;

    const links = header.querySelectorAll('.nav-btn');
    if (links.length === 0) return;

    const fila = document.createElement('div');
    fila.className = 'cmm-navfila';
    links.forEach(l => fila.appendChild(l));
    header.appendChild(fila);
  }

  function agregarBurger() {
    agruparAcciones();
    armarFilaNav();
  }

  function abrirPanel() {
    document.getElementById('cmmPanel')?.classList.add('show');
    document.getElementById('cmmPanelBg')?.classList.add('show');
    document.body.style.overflow = 'hidden';
  }
  function cerrarPanel() {
    document.getElementById('cmmPanel')?.classList.remove('show');
    document.getElementById('cmmPanelBg')?.classList.remove('show');
    document.body.style.overflow = '';
  }

  // ─── Eventos globales ────────────────────────────────────────────
  document.addEventListener('click', async function (e) {
    if (e.target.closest('[data-cmm-burger]')) { abrirPanel(); return; }
    if (e.target.closest('[data-cmm-cerrar]') || e.target.id === 'cmmPanelBg') { cerrarPanel(); return; }

    if (e.target.closest('[data-cmm-salir]')) {
      e.preventDefault();
      if (typeof limpiarCacheSesion === 'function') limpiarCacheSesion();
      if (typeof sb !== 'undefined' && sb) await sb.auth.signOut();
      window.location.href = '/index';
      return;
    }

    const toggle = e.target.closest('[data-cmm-toggle]');
    if (toggle) {
      e.stopPropagation();
      // La foto abre el menú, en celular y en computadora
      const drop = toggle.parentElement.querySelector('.cmm-drop');
      const abierto = drop.classList.contains('show');
      document.querySelectorAll('.cmm-drop').forEach(d => d.classList.remove('show'));
      if (!abierto) drop.classList.add('show');
      return;
    }

    if (!e.target.closest('.cmm-drop')) {
      document.querySelectorAll('.cmm-drop').forEach(d => d.classList.remove('show'));
    }
  });

  // ─── Arranque ────────────────────────────────────────────────────
  function pintar(s) {
    if (s) pintarUsuario(s);
    pintarPanel(s);
    agregarBurger();
  }

  function iniciar() {
    inyectarEstilos();

    // 1) Pintado inmediato con el caché → sin parpadeo
    const cache = (typeof leerCacheSesion === 'function') ? leerCacheSesion() : null;
    pintar(cache);

    // 2) Confirmación real cuando Supabase termina de cargar
    const esperar = setInterval(async function () {
      if (typeof sb === 'undefined' || sb === null) return;
      clearInterval(esperar);

      const real = (typeof refrescarCacheSesion === 'function') ? await refrescarCacheSesion() : null;

      const cacheDecia = cache ? cache.id : null;
      const realDice = real ? real.id : null;
      const cambioNombre = cache && real && (cache.nombre !== real.nombre || cache.avatar_url !== real.avatar_url || cache.rol !== real.rol);

      // Solo repintamos si algo cambió de verdad
      if (cacheDecia !== realDice || cambioNombre) {
        if (!real) {
          // La sesión se cayó: volvemos a mostrar ENTRAR
          document.querySelectorAll('.cmm-user-wrap').forEach(function (w) {
            const a = document.createElement('a');
            a.href = '/login';
            a.className = 'btn-outline';
            a.textContent = 'ENTRAR';
            w.replaceWith(a);
          });
          pintarPanel(null);
        } else {
          pintar(real);
        }
      }
    }, 40);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', iniciar);
  } else {
    iniciar();
  }
})();
