# canchaya-print-extension

Extensión Chrome para imprimir desde **Mi Tienda POS** (mitiendapos.com.ar) y
**CanchaYa** (canchaya.ar). Reemplazo del agente standalone Go/Tauri para
clubes con setup simple: una PC con Chrome + impresora térmica USB o LAN.

> **Estado**: Fase 0 — POC inicial. Pareo + listado de impresoras + impresión
> de prueba.

## Por qué una extensión Chrome

- **Cero instalación**: 1 click desde Chrome Web Store, sin admin de Windows.
- **Update automático**: cuando publicás versión nueva, llega sola.
- **Sin firewall, sin puertos locales, sin token.txt**.
- **Soporta USB + LAN** (cualquiera instalada como impresora del SO).
- **Mismo flujo de pareo** que el agente legacy (endpoint `/api/agent_pair`).

## Limitaciones conocidas

- Solo Chromium (Chrome, Edge, Brave). NO Safari, NO Firefox, NO iOS.
- Para LAN sin driver instalado en el SO → Fase 2 (fetch raw a `IP:9100`).
- Para fiscal (Hasar/Epson 2G) → fuera de scope. Sigue agente standalone.

## Estructura

```
src/
├── manifest.json    # Manifest V3
├── background.js    # Service worker — handlers de mensajes + chrome.printing
├── content.js       # Bridge entre window.postMessage del POS y el background
├── popup.html       # UI del icono de la extension
└── popup.js         # Logica del popup
```

## Probar local (development)

1. `chrome://extensions` → activar **Modo de desarrollador**.
2. **Cargar descomprimida** → seleccionar `src/`.
3. Click en el ícono de la extensión.
4. Pegar un código de pareo desde Mi Tienda POS → Configuración → Impresoras.
5. Elegir impresora → Imprimir prueba.

## Brand split

La extensión se publica como dos productos separados en Chrome Web Store:

- **Mi Tienda Print** (origenes `mitiendapos.com.ar`, ícono naranja)
- **CanchaYa Print** (origenes `canchaya.ar`, ícono lime)

Mismo código fuente, diferentes `manifest.json` + assets. Script de build
(pendiente) genera ambos paquetes a partir de `src/` + un `brand.json`.

## Protocolo POS ↔ Extensión

Web del POS envía via `window.postMessage`:

```js
window.postMessage({
  source: "mitienda-print",
  type: "PING" | "PRINT_JOB" | "LIST_PRINTERS" | "GET_STATUS",
  request_id: crypto.randomUUID(),
  payload: { ... }
}, "*")
```

Extensión responde via `window.postMessage` con
`source: "mitienda-print-response"` y el mismo `request_id`.

Para detectar si la extensión está instalada:

```js
const detect = () => new Promise((resolve) => {
  const id = crypto.randomUUID()
  const handler = (e) => {
    if (e.data?.source === "mitienda-print-response" && e.data.request_id === id) {
      window.removeEventListener("message", handler)
      resolve(e.data)
    }
  }
  window.addEventListener("message", handler)
  window.postMessage({ source: "mitienda-print", type: "PING", request_id: id }, "*")
  setTimeout(() => { window.removeEventListener("message", handler); resolve(null) }, 500)
})
```
