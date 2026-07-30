// ═══════════════════════════════════════════════════════════════════
// FUERZA DE CONTRASEÑA
// Reglas y medidor visual, compartido por login y recuperación.
// ═══════════════════════════════════════════════════════════════════

// Contraseñas que la gente usa y que un atacante prueba primero
const PASSWORDS_COMUNES = [
  '123456', '123456789', '12345678', 'password', 'contrasena', 'contraseña',
  'qwerty', 'abc123', '111111', '1234567', 'iloveyou', 'admin', 'welcome',
  'monkey', 'dragon', 'sunshine', 'princess', 'football', 'letmein',
  'milena', 'milena123', 'paraguay', 'asuncion', 'marketing', 'senha',
  '12345', '1234', 'senha123', 'password1', 'qwerty123', 'cmm123'
];

function evaluarPassword(pass) {
  const p = pass || '';

  const reglas = {
    largo:      p.length >= 8,
    mayuscula:  /[A-ZÁÉÍÓÚÑ]/.test(p),
    minuscula:  /[a-záéíóúñ]/.test(p),
    numero:     /[0-9]/.test(p),
    simbolo:    /[^A-Za-z0-9áéíóúñÁÉÍÓÚÑ]/.test(p)
  };

  const faltantes = [];
  if (!reglas.largo)     faltantes.push('Necesita al menos 8 caracteres');
  if (!reglas.mayuscula) faltantes.push('Falta una letra mayúscula');
  if (!reglas.minuscula) faltantes.push('Falta una letra minúscula');
  if (!reglas.numero)    faltantes.push('Falta un número');
  if (!reglas.simbolo)   faltantes.push('Falta un símbolo, como . - _ ! @ #');

  // Patrones fáciles de adivinar
  const bajo = p.toLowerCase();
  let comun = false;
  for (const c of PASSWORDS_COMUNES) {
    // Es común si ES la palabra, o si la palabra ocupa más de la mitad
    // ("milena123" se rechaza, "Milena2026!Casa" no)
    if (bajo === c) { comun = true; break; }
    if (c.length >= 5 && bajo.includes(c) && c.length / p.length > 0.6) { comun = true; break; }
  }
  const repetida = /^(.)\1+$/.test(p);                        // aaaaaa
  const secuencia = /012345|123456|234567|345678|456789|abcdef|qwerty/i.test(p);

  const cumplidas = Object.values(reglas).filter(Boolean).length;

  // Puntaje de 0 a 100
  let puntos = 0;
  puntos += Math.min(p.length, 16) * 3;                       // hasta 48
  puntos += cumplidas * 8;                                    // hasta 40
  if (p.length >= 12) puntos += 12;
  if (comun || repetida || secuencia) puntos = Math.min(puntos, 25);
  puntos = Math.max(0, Math.min(100, puntos));

  let nivel, etiqueta, color;
  if (comun || repetida || secuencia) {
    nivel = 0; etiqueta = 'Muy fácil de adivinar'; color = '#FF5A6E';
  } else if (puntos < 40 || cumplidas < 3) {
    nivel = 1; etiqueta = 'Débil'; color = '#FF8090';
  } else if (puntos < 65 || cumplidas < 5) {
    nivel = 2; etiqueta = 'Aceptable'; color = '#FAC775';
  } else if (puntos < 85) {
    nivel = 3; etiqueta = 'Buena'; color = '#9FE1CB';
  } else {
    nivel = 4; etiqueta = 'Excelente'; color = '#5DCAA5';
  }

  if (comun) faltantes.unshift('Esa contraseña es de las más usadas del mundo. Elegí otra.');
  else if (repetida) faltantes.unshift('No repitas el mismo caracter.');
  else if (secuencia) faltantes.unshift('Evitá secuencias como 123456 o qwerty.');

  return {
    reglas,
    faltantes,
    puntos,
    nivel,
    etiqueta,
    color,
    // Se acepta con las 5 reglas y sin patrones obvios
    aceptable: cumplidas === 5 && !comun && !repetida && !secuencia
  };
}

// ─── Medidor visual ────────────────────────────────────────────────
function crearMedidorPassword(idContenedor, idInput) {
  const cont = document.getElementById(idContenedor);
  const input = document.getElementById(idInput);
  if (!cont || !input) return null;

  if (!document.getElementById('css-medidor-pass')) {
    const st = document.createElement('style');
    st.id = 'css-medidor-pass';
    st.textContent = `
      .mp-wrap{margin-top:9px;display:none}
      .mp-wrap.show{display:block}
      .mp-barra{height:5px;border-radius:3px;background:rgba(255,245,240,0.1);overflow:hidden;display:flex;gap:3px}
      .mp-tramo{flex:1;background:rgba(255,245,240,0.1);border-radius:3px;transition:background 0.3s}
      .mp-fila{display:flex;justify-content:space-between;align-items:center;margin-top:7px;gap:10px}
      .mp-etiqueta{font-size:11.5px;font-weight:500;transition:color 0.3s}
      .mp-reglas{display:flex;flex-wrap:wrap;gap:5px;margin-top:8px}
      .mp-regla{font-size:10.5px;padding:3px 8px;border-radius:12px;background:rgba(255,245,240,0.05);border:0.5px solid rgba(255,245,240,0.12);color:rgba(255,245,240,0.5);transition:all 0.25s;display:inline-flex;align-items:center;gap:4px}
      .mp-regla.ok{background:rgba(93,202,165,0.14);border-color:rgba(93,202,165,0.4);color:#9FE1CB}
      .mp-aviso{font-size:11px;color:#FF8090;margin-top:7px;line-height:1.45}
    `;
    document.head.appendChild(st);
  }

  cont.innerHTML = `
    <div class="mp-wrap" id="${idContenedor}_wrap">
      <div class="mp-barra">
        <div class="mp-tramo"></div><div class="mp-tramo"></div>
        <div class="mp-tramo"></div><div class="mp-tramo"></div>
      </div>
      <div class="mp-fila">
        <span class="mp-etiqueta" id="${idContenedor}_etq"></span>
      </div>
      <div class="mp-reglas">
        <span class="mp-regla" data-r="largo">8+ caracteres</span>
        <span class="mp-regla" data-r="mayuscula">Mayúscula</span>
        <span class="mp-regla" data-r="minuscula">Minúscula</span>
        <span class="mp-regla" data-r="numero">Número</span>
        <span class="mp-regla" data-r="simbolo">Símbolo</span>
      </div>
      <div class="mp-aviso" id="${idContenedor}_aviso"></div>
    </div>
  `;

  const wrap = document.getElementById(idContenedor + '_wrap');
  const etq = document.getElementById(idContenedor + '_etq');
  const aviso = document.getElementById(idContenedor + '_aviso');
  const tramos = cont.querySelectorAll('.mp-tramo');
  const reglasEl = cont.querySelectorAll('.mp-regla');

  function pintar() {
    const v = input.value;
    if (!v) { wrap.classList.remove('show'); return; }
    wrap.classList.add('show');

    const r = evaluarPassword(v);

    tramos.forEach((t, i) => {
      t.style.background = i < Math.max(1, r.nivel) && r.nivel > 0
        ? r.color
        : (r.nivel === 0 && i === 0 ? r.color : 'rgba(255,245,240,0.1)');
    });

    etq.textContent = r.etiqueta;
    etq.style.color = r.color;

    reglasEl.forEach(el => {
      el.classList.toggle('ok', !!r.reglas[el.dataset.r]);
    });

    const grave = r.faltantes.find(f => f.includes('mundo') || f.includes('repitas') || f.includes('secuencias'));
    aviso.textContent = grave || '';
  }

  input.addEventListener('input', pintar);
  return { pintar, evaluar: () => evaluarPassword(input.value) };
}
