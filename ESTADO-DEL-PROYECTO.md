# CMM — Estado del proyecto

Pegá este texto al inicio de un chat nuevo para retomar sin perder contexto.

---

## Qué es

Plataforma de cursos y comunidad para **Milena Machado** — "Creando Mentes Millonarias", Paraguay.
En producción: **https://milenacmm.com**

**Yo (LuenYo) no soy desarrollador.** Necesito archivos completos listos para copiar y pegar,
instrucciones paso a paso, y que me hables en español/portugués mezclado.

---

## Stack

| Pieza | Qué usamos |
|---|---|
| Frontend | HTML/CSS/JS puro, sin framework |
| Repo | `luenghel/SITE.MILENA` en GitHub |
| Hosting | Vercel (despliegue automático al hacer push) |
| Base de datos | Supabase — proyecto `pdwooahpyustbqlrvlxz` |
| Emails | Resend, dominio `mail.milenacmm.com` verificado |
| Pagos | Pagopar (Paraguay) |

**Flujo de trabajo:** me pasás un ZIP con todo el sitio → lo subo a GitHub → Vercel publica solo.

---

## Edge Functions en Supabase

Supabase les pone nombres distintos a los que elegís. Estos son los reales:

| Para qué | Nombre visible | URL real |
|---|---|---|
| Crear pago | crear-pago | `rapid-endpoint` |
| Confirmar pago | webhook-pago | `rapid-worker` |
| Consultar estado | consultar-pago | *(anotar)* |
| Diagnóstico Pagopar | diagnostico-pagopar | *(anotar)* |
| Newsletter | bright-api | `bright-api` |
| Gestión de miembros | FUNCION-ADM | `clever-processor` |
| Avisos de clases | AVISAR-CLASES | `AVISAR-CLASES` |
| Verificación en 2 pasos | Edge-function-dos-pasos | igual |

Los nombres se guardan en la tabla `ajustes` y se configuran desde
**Admin → Newsletter → ⚙️ Funciones de Supabase**.

---

## PAGOPAR — dónde quedamos

**Situación al cerrar la última sesión:**

- El registro tenía **DOS comercios**. El habilitado es **"Milena Gysel Machado Portillo"**.
  Estuvimos usando las claves del comercio equivocado — eso causó todos los errores.
- Acabo de cambiar los tokens en Supabase por los del comercio correcto.
- Entorno: **staging**, habilitado por 30 días (desde el 26/08/2026).
- **Sobre la IP:** Pagopar confirmó que puedo poner cualquier IP estática al pasar a
  producción y ellos **desactivan el control de IP**. Supabase sirve sin problema.

**Errores que fuimos resolviendo, en orden:**

1. `Unexpected end of JSON input` → la función no manejaba respuestas vacías
2. `Comercio de desarrollo no habilitado` → acceso de staging vencido
3. `Jsonb: No coinciden los campos o la cantidad no es 9` → mandábamos 10 campos
4. `No habilitado para productos virtuales` → era el comercio equivocado

**Estructura que exige Pagopar** (la función ya lo verifica antes de llamar):
- 9 campos en el nivel principal
- 11 en `comprador`
- 13 en cada `compras_items`

**Los 3 pasos del circuito** (hay que completarlos para pasar a producción):
1. Crear pedido desde el sitio
2. Pagopar avisa al webhook y este devuelve el JSON
3. El sitio consulta el estado del pedido

**Pendiente:** completar los 3 pasos con las claves nuevas y hacer el pase a producción.

---

## Qué está construido y funcionando

**Cursos**
- Módulos y clases, con tipos: video, PDF, texto, enlace, solo documentos
- Varios PDF por clase
- Liberación: el módulo decide si se abre entero o clase por clase.
  Opciones: al inscribirse · X días tras inscribirse · X días tras el lanzamiento · fecha exacta
- Módulos y clases de regalo (se ven sin comprar)
- Publicación programada por fecha
- Tiempo de acceso: **1 año por defecto**, con contador y botón de renovar
- Precio especial para suscriptoras premium
- Cursos "próximamente" con lista de interesadas
- Enlaces cortos: `/clase?curso=cmm&c=3`

**Comunidad**
- Publicaciones, comentarios, diamantes (no corazones)
- Moderación por severidad, detección de enlaces
- Insignias configurables: nombre, imagen, ícono, color, rareza, cómo se ganan
- Cada una elige qué insignia mostrar junto a su nombre

**Comunidad Premium**
- Suscripción mensual, encuentros semanales, publicaciones exclusivas
- Página `/premium` editable: video, texto, precio opcional
- Gestión manual de accesos desde el panel

**Clases**
- Comentarios con respuestas, me gusta y aviso por email
- Opiniones por clase con 7 opciones, y vista de "qué regrabar" en el admin

**Emails** (todos con la marca)
- Bienvenida al inscribirse
- Clase liberada / clase nueva / curso nuevo
- Respuesta a un comentario
- Invitación con acceso
- Verificación en dos pasos

**Otros**
- Enviar acceso por email desde Alumnas (crea cuenta o usa la existente)
- Filas del catálogo configurables
- Verificación en dos pasos al entrar desde un dispositivo nuevo

---

## Cómo trabajamos

**Lo que funciona bien:**
- ZIP completo del sitio en cada entrega
- Archivos SQL separados, con verificación al final
- Verificar el código antes de entregar

**Errores que se repitieron y hay que evitar:**
1. Funciones que se llaman desde el HTML pero no existen
2. IDs duplicados (el navegador usa el primero, el resto queda invisible)
3. Variables usadas pero nunca declaradas
4. Funciones completas que nunca se llaman
5. CSS de celular que queda fuera de su `@media` y se aplica en escritorio
6. Ediciones que borran código que ya funcionaba

**Verificaciones que hay que correr antes de cada entrega:**
- Sintaxis del JavaScript
- Funciones invocadas desde HTML que existan
- IDs sin duplicar
- Variables declaradas
- Funciones que se usen
- Llaves de CSS balanceadas
- `<div>` balanceados
- Nada suelto después de `</html>`

---

## Diseño

- Fondo vino oscuro en todo el sitio, **excepto el checkout** (crema)
- Dorado `#EFB85C → #DDA63F` para los botones
- Georgia cursiva para los títulos
- 💎 diamantes, nunca corazones
- **Nunca tocar el escritorio cuando se arregla el celular**
- Referencia de diseño: `luanacarolina.entregadigital.app.br`

---

## Pendientes

1. **Pagopar** — completar los 3 pasos y pasar a producción
2. Pedir de baja el comercio duplicado
3. Convertir el sitio en app instalable (PWA) — pendiente de decidir
4. Cupones de descuento — no construido
