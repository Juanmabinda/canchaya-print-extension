// Content script — corre en cada pagina del POS (mitiendapos.com.ar).
// Hace de puente entre window.postMessage del POS y el service worker.
//
// La web del POS detecta la extension asi:
//   window.postMessage({ source: "mitienda-print", type: "PING" }, "*")
// y escucha la respuesta. Si llega un PONG, hay extension instalada y el
// POS puede mostrar la UI "modo extension". Si no llega, fallback al
// agente standalone como hoy.
//
// Para imprimir el POS hace:
//   window.postMessage({
//     source: "mitienda-print",
//     type: "PRINT_JOB",
//     payload: { title, content, device_id? }
//   }, "*")
// Y el content script lo reenvia al service worker.

// El BRAND lo inyecta el build script. Para development sin build,
// fallback a "mitienda".
const BRAND = "mitienda"
const SOURCE = `${BRAND}-print`
const RESPONSE_SOURCE = `${BRAND}-print-response`

// Log de carga: si el cajero abre F12 en el POS y NO ve esto, el
// content_script no se esta inyectando (sin permisos al sitio, mismatch
// de matches en manifest, o desactivada para este host).
try {
  console.info(`[${SOURCE}] content_script cargado v${chrome.runtime.getManifest().version}`)
} catch (e) {
  console.info(`[${SOURCE}] content_script cargado (sin runtime?)`, e)
}

window.addEventListener("message", async (event) => {
  // Solo procesamos mensajes del mismo window (no de iframes externos).
  if (event.source !== window) return
  const data = event.data
  if (!data || data.source !== SOURCE) return

  const requestId = data.request_id || null
  console.debug(`[${SOURCE}] msg recibido:`, data.type, "req=", requestId)
  try {
    if (data.type === "PING") {
      // Responder inmediato sin tocar el service worker — sirve para que el
      // POS detecte que la extension esta instalada.
      respond(requestId, { ok: true, type: "PONG", version: chrome.runtime.getManifest().version })
      return
    }
    // El resto se forwardea al background.
    const reply = await chrome.runtime.sendMessage({ type: data.type, ...(data.payload || {}) })
    respond(requestId, reply)
  } catch (e) {
    respond(requestId, { ok: false, error: e?.message || String(e) })
  }
})

function respond(requestId, payload) {
  window.postMessage({
    source: RESPONSE_SOURCE,
    request_id: requestId,
    ...payload
  }, "*")
}
