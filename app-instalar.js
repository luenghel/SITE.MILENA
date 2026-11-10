// ═══════════════════════════════════════════════════════════════════
// LA APP: instalación y actualizaciones
//
// · Registra el service worker
// · Ofrece instalarla en el celular
// · Avisa cuando hay una versión nueva
// ═══════════════════════════════════════════════════════════════════

(function () {
  'use strict';

  let pedidoInstalar = null;

  // ─── Registrar el service worker ─────────────────────────────────
  if ('serviceWorker' in navigator) {
    window.addEventListener('load', function () {
      navigator.serviceWorker.register('/sw.js')
        .then(function (reg) {
          // ¿Llegó una versión nueva?
          reg.addEventListener('updatefound', function () {
            const nuevo = reg.installing;
            if (!nuevo) return;

            nuevo.addEventListener('statechange', function () {
              // Hay algo nuevo esperando, y ya había una versión antes
              if (nuevo.state === 'installed' && navigator.serviceWorker.controller) {
                mostrarAvisoActualizacion(reg);
              }
            });
          });

          // Revisamos cada media hora por si hay novedades
          setInterval(function () { reg.update(); }, 30 * 60 * 1000);
        })
        .catch(function () { /* si falla, el sitio anda igual */ });

      // Cuando se activa la versión nueva, recargamos
      let recargando = false;
      navigator.serviceWorker.addEventListener('controllerchange', function () {
        if (recargando) return;
        recargando = true;
        window.location.reload();
      });
    });
  }

  // ─── El aviso de versión nueva ───────────────────────────────────
  function mostrarAvisoActualizacion(reg) {
    if (document.getElementById('avisoVersion')) return;

    const caja = document.createElement('div');
    caja.id = 'avisoVersion';
    caja.innerHTML =
      '<div class="av-texto">' +
        '<strong>Hay una versión nueva</strong>' +
        '<span>Actualizá para ver los últimos cambios</span>' +
      '</div>' +
      '<button class="av-btn" id="avActualizar">ACTUALIZAR</button>' +
      '<button class="av-x" id="avCerrar" aria-label="Cerrar">×</button>';

    document.body.appendChild(caja);
    requestAnimationFrame(function () { caja.classList.add('show'); });

    document.getElementById('avActualizar').onclick = function () {
      if (reg.waiting) reg.waiting.postMessage('actualizar');
      caja.classList.remove('show');
    };

    document.getElementById('avCerrar').onclick = function () {
      caja.classList.remove('show');
      setTimeout(function () { caja.remove(); }, 400);
    };
  }

  // ─── Ofrecer instalarla ──────────────────────────────────────────
  window.addEventListener('beforeinstallprompt', function (e) {
    e.preventDefault();
    pedidoInstalar = e;

    // Si ya la rechazó hace poco, no insistimos
    const rechazado = localStorage.getItem('cmm_instalar_no');
    if (rechazado && (Date.now() - parseInt(rechazado)) < 14 * 86400000) return;

    // Esperamos un rato: que primero vea el sitio
    setTimeout(mostrarInvitacionInstalar, 20000);
  });

  function mostrarInvitacionInstalar() {
    if (!pedidoInstalar) return;
    if (document.getElementById('invInstalar')) return;

    const caja = document.createElement('div');
    caja.id = 'invInstalar';
    caja.innerHTML =
      '<div class="inst-ico">' +
        '<img src="/icon-192.png" alt="">' +
      '</div>' +
      '<div class="inst-texto">' +
        '<strong>Tenelo a mano</strong>' +
        '<span>Agregá CMM a tu pantalla de inicio y entrá con un toque</span>' +
      '</div>' +
      '<button class="inst-btn" id="instSi">INSTALAR</button>' +
      '<button class="inst-x" id="instNo" aria-label="Ahora no">×</button>';

    document.body.appendChild(caja);
    requestAnimationFrame(function () { caja.classList.add('show'); });

    document.getElementById('instSi').onclick = async function () {
      caja.classList.remove('show');
      if (!pedidoInstalar) return;

      pedidoInstalar.prompt();
      const r = await pedidoInstalar.userChoice;
      if (r.outcome !== 'accepted') {
        localStorage.setItem('cmm_instalar_no', String(Date.now()));
      }
      pedidoInstalar = null;
      setTimeout(function () { caja.remove(); }, 400);
    };

    document.getElementById('instNo').onclick = function () {
      localStorage.setItem('cmm_instalar_no', String(Date.now()));
      caja.classList.remove('show');
      setTimeout(function () { caja.remove(); }, 400);
    };
  }

  // Si ya la instaló, no volvemos a ofrecerla
  window.addEventListener('appinstalled', function () {
    localStorage.setItem('cmm_instalada', '1');
    pedidoInstalar = null;
    document.getElementById('invInstalar')?.remove();
  });

  // ─── Los estilos ─────────────────────────────────────────────────
  const css = document.createElement('style');
  css.textContent = `
    #avisoVersion, #invInstalar {
      position: fixed;
      left: 50%;
      bottom: 18px;
      transform: translate(-50%, 130%);
      z-index: 9998;
      width: min(430px, calc(100vw - 28px));
      display: flex;
      align-items: center;
      gap: 13px;
      padding: 14px 16px;
      background: #2A0D18;
      border: 0.5px solid rgba(212,163,86,0.45);
      border-radius: 15px;
      box-shadow: 0 14px 40px rgba(0,0,0,0.55);
      transition: transform 0.45s cubic-bezier(0.34,1.3,0.64,1);
      font-family: inherit;
    }
    #avisoVersion.show, #invInstalar.show { transform: translate(-50%, 0); }

    .av-texto, .inst-texto { flex: 1; min-width: 0; display: flex; flex-direction: column; gap: 3px; }
    .av-texto strong, .inst-texto strong { font-size: 13.5px; color: #FFF5F0; font-weight: 500; }
    .av-texto span, .inst-texto span { font-size: 11.5px; color: rgba(255,245,240,0.6); line-height: 1.4; }

    .inst-ico {
      width: 42px; height: 42px; border-radius: 11px;
      overflow: hidden; flex-shrink: 0;
      border: 0.5px solid rgba(255,245,240,0.15);
    }
    .inst-ico img { width: 100%; height: 100%; object-fit: cover; }

    .av-btn, .inst-btn {
      padding: 10px 15px;
      background: linear-gradient(135deg,#EFB85C,#DDA63F);
      border: none; border-radius: 9px;
      color: #2E0C05;
      font-size: 11px; font-weight: 600; letter-spacing: 0.08em;
      cursor: pointer; font-family: inherit; white-space: nowrap;
    }
    .av-btn:active, .inst-btn:active { transform: scale(0.96); }

    .av-x, .inst-x {
      background: none; border: none;
      color: rgba(255,245,240,0.4);
      font-size: 22px; line-height: 1;
      cursor: pointer; padding: 0 2px;
      font-family: inherit;
    }
    .av-x:hover, .inst-x:hover { color: #FFF5F0; }

    @media (max-width: 480px) {
      #avisoVersion, #invInstalar { bottom: 12px; padding: 12px 13px; gap: 10px; }
      .inst-ico { width: 36px; height: 36px; }
      .av-btn, .inst-btn { padding: 9px 12px; font-size: 10.5px; }
    }
  `;
  document.head.appendChild(css);
})();
