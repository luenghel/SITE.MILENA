# Publicar CMM en Google Play

Guía paso a paso. No hace falta programar nada.

---

## Lo que vas a necesitar

- **25 dólares**, una sola vez (tarjeta internacional)
- Una cuenta de Google
- Unas 2 horas la primera vez
- El sitio ya instalable como app ✅ (eso ya está hecho)

---

## PASO 1 · Crear la cuenta de desarrollador

🔗 https://play.google.com/console/signup

1. Entrá con la cuenta de Google de Milena
2. Elegí **"Personal"** (no "Organización" — pide más papeles)
3. Pagá los 25 dólares
4. Completá los datos: nombre, dirección, teléfono

⚠️ **Google verifica la identidad.** Te van a pedir una foto de la cédula y puede tardar entre unas horas y 3 días. Hacé esto primero, mientras preparás lo demás.

---

## PASO 2 · Generar el paquete de la app

🔗 https://www.pwabuilder.com

1. Escribí `https://milenacmm.com` y tocá **Start**
2. Esperá el análisis — debería dar buen puntaje
3. Tocá **Package For Stores** → **Android**
4. Completá así:

| Campo | Qué poner |
|---|---|
| Package ID | `com.milenacmm.app` |
| App name | `Milena Machado CMM` |
| Short name | `Milena CMM` |
| Start URL | `/index` |
| Display mode | `standalone` |
| Status bar color | `#1A0A12` |
| Nav bar color | `#0E0509` |

5. **Signing key:** elegí **"Create new"**
6. Tocá **Download Package**

Vas a bajar un ZIP con:
- `app-release-bundle.aab` ← esto subís a Google
- `signing.keystore` ← 🚨 **GUARDALO Y NO LO PIERDAS**
- `assetlinks.json` ← para el paso 3

🚨 **El archivo `signing.keystore` y su contraseña son irreemplazables.** Si los perdés, no podés volver a actualizar la app nunca más — hay que publicar una nueva desde cero y las alumnas pierden la que tenían.

Guardalo en Drive y en una copia aparte.

---

## PASO 3 · Vincular el dominio con la app

Sin esto, la app abre con una barra del navegador arriba y se ve fea.

1. Del ZIP, abrí el `assetlinks.json` que te generó PWABuilder
2. Copiá ese archivo a la carpeta del sitio, dentro de `.well-known/`

En tu computadora:

```
C:\Users\lueng\Documents\GitHub\SITE.MILENA\.well-known\assetlinks.json
```

Si la carpeta `.well-known` no existe, creala.

3. Subí el cambio:

```
cd C:\Users\lueng\Documents\GitHub\SITE.MILENA
git add .
git commit -m "Vinculacion con la app de Android"
git push
```

4. Verificá que quedó: entrá a
   `https://milenacmm.com/.well-known/assetlinks.json`

   Tenés que ver el contenido del archivo.

---

## PASO 4 · Crear la ficha en Google Play

En Play Console → **Crear app**.

### Datos básicos

| Campo | Valor |
|---|---|
| Nombre | Milena Machado · CMM |
| Idioma | Español (Paraguay) |
| Tipo | Aplicación |
| Gratis o de pago | **Gratis** |

### Descripción corta (80 caracteres)

```
Cursos y comunidad de marketing para emprendedoras en Paraguay.
```

### Descripción completa

```
Creando Mentes Millonarias es la plataforma de Milena Machado para
emprendedoras que quieren vender más.

QUÉ VAS A ENCONTRAR

· Cursos de marketing digital, ventas y anuncios
· Clases en video que podés ver a tu ritmo
· Material descargable para aplicar lo que aprendés
· Una comunidad de emprendedoras que están en el mismo camino
· Encuentros en vivo con Milena

PARA QUIÉN ES

Para vos, que tenés un negocio o querés empezar uno, y necesitás
saber cómo venderlo. No hace falta experiencia previa.

TU PROGRESO, SIEMPRE A MANO

Seguí tus cursos desde donde quedaste, participá de la comunidad
y ganá insignias a medida que avanzás.

Milena Machado · Ciudad del Este, Paraguay
```

⚠️ **No menciones precios ni compras.** Si la ficha habla de vender, Google puede exigir que uses su sistema de pagos.

### Imágenes que te va a pedir

| Qué | Medida |
|---|---|
| Ícono | 512 × 512 px |
| Gráfico destacado | 1024 × 500 px |
| Capturas de celular | mínimo 2, hasta 8 |

El ícono ya lo tenés: `icon-512.png`

Para las capturas: abrí el sitio en el celular y sacá pantallazos del inicio, un curso, una clase y la comunidad.

---

## PASO 5 · Las declaraciones obligatorias

Google pide completar varios formularios. Los importantes:

**Seguridad de los datos**
- ¿Recopilás datos? **Sí**
- Qué: nombre, email, foto de perfil
- Para qué: funcionamiento de la app y gestión de la cuenta
- ¿Se comparten con terceros? **No**
- ¿Se pueden eliminar? **Sí** — poné el enlace de contacto

**Clasificación de contenido**
- Categoría: **Educación**
- Respondé que no hay violencia, contenido sexual ni apuestas
- Te va a dar clasificación "Para todos"

**Público objetivo**
- Edad: **18 y más**
- ¿Dirigida a menores? **No**

**Política de privacidad**
- 🚨 **Es obligatoria.** Necesitás una página pública con tu política.

---

## PASO 6 · Subir y enviar

1. En **Producción** → **Crear nueva versión**
2. Subí el archivo `app-release-bundle.aab`
3. Notas de la versión: `Primera versión de la app.`
4. **Enviar para revisión**

⏳ La revisión tarda entre **1 y 7 días** la primera vez.

---

## Cómo actualizar después

Acá está lo bueno: **casi nunca vas a tener que tocar Google Play.**

**Si cambiás el sitio** (diseño, páginas, textos, cursos):

```
git add .
git commit -m "Lo que sea"
git push
```

La app muestra el cambio al instante. **No hay que subir nada a Google ni esperar revisión.**

**Solo volvés a Google Play si cambia:**
- El nombre de la app
- El ícono
- Los permisos

Eso pasa una o dos veces por año.

---

## ⚠️ Cosas que te pueden rechazar

| Motivo | Cómo evitarlo |
|---|---|
| Vender sin usar el sistema de Google | La app no vende: solo da acceso |
| Falta política de privacidad | Publicala antes de enviar |
| "Es solo un sitio web" | Por eso configuramos la app instalable |
| Capturas que no son de la app | Sacalas del celular, no del escritorio |

---

## Después de Google Play

Si la app funciona y trae gente, recién ahí pensá en Apple: son **99 dólares por año** y el proceso es más estricto.

Mi consejo: esperá tres meses y mirá cuánta gente la usa.
