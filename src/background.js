// Service worker de la extension de impresion.
//
// Vive entre 3 mundos:
//   1) UI del popup (popup.html → mensajes via chrome.runtime.sendMessage)
//   2) Web del POS (content.js → mensajes via chrome.runtime.sendMessage
//      forwardeados desde window.postMessage del POS)
//   3) Chrome printing API (chrome.printing.* — listar impresoras, submitJob)
//
// chrome.storage.local guarda el agent_token + el printer_uid configurado.
// El servidor reconoce este token igual que al agente Go (mismo endpoint
// /api/agent_pair para canjear codigo → token).

import { CURRENT_BRAND } from "./brand.js"

const STORAGE_KEYS = {
  TOKEN: "agent_token",
  CLUB_ID: "club_id",
  CLUB_NAME: "club_name",
  PRIMARY_PRINTER: "primary_printer_device_id",
  SERVER: "server_url"
}

const DEFAULT_SERVER = CURRENT_BRAND.default_server

// === Mensajeria ===
//
// Entrada desde popup.html o content.js. type discrimina la accion:
//   - "PAIR_AGENT" → canjear codigo de 6 chars por agent_token
//   - "LIST_PRINTERS" → devolver impresoras del SO (chrome.printing)
//   - "SET_PRIMARY_PRINTER" → guardar device_id elegido en storage
//   - "PRINT_TEST" → submitJob a la primary printer con un texto fijo
//   - "PRINT_JOB" → submitJob con payload arbitrario (desde el POS)
//   - "GET_STATUS" → token presente, primary printer, etc.
chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  const handler = MESSAGE_HANDLERS[msg?.type]
  if (!handler) {
    sendResponse({ ok: false, error: `Tipo desconocido: ${msg?.type}` })
    return
  }
  // Devolvemos true para mantener el canal abierto y poder responder async.
  // Sin esto, sendResponse despues de un await NO llega al caller.
  handler(msg, sender).then(sendResponse).catch((e) => {
    sendResponse({ ok: false, error: e?.message || String(e) })
  })
  return true
})

const MESSAGE_HANDLERS = {
  PAIR_AGENT: handlePairAgent,
  LIST_PRINTERS: handleListPrinters,
  SET_PRIMARY_PRINTER: handleSetPrimaryPrinter,
  PRINT_TEST: handlePrintTest,
  PRINT_JOB: handlePrintJob,
  GET_STATUS: handleGetStatus
}

async function handlePairAgent({ code, server }) {
  const baseUrl = (server || DEFAULT_SERVER).replace(/\/$/, "")
  // Pareo one-shot via /api/extension/pair/claim. El POS admin genera el
  // codigo (que vive 10 min en cache asociado al club), la extension lo
  // canjea aca y recibe el token del club.
  const url = `${baseUrl}/api/extension/pair/claim`
  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json", "Accept": "application/json" },
    body: JSON.stringify({ code })
  })
  const data = await res.json().catch(() => ({}))
  if (!res.ok) {
    throw new Error(data?.error || `Pareo falló (${res.status})`)
  }
  if (!data?.token) throw new Error("Respuesta sin token")
  await chrome.storage.local.set({
    [STORAGE_KEYS.TOKEN]: data.token,
    [STORAGE_KEYS.CLUB_ID]: data.club_id,
    [STORAGE_KEYS.CLUB_NAME]: data.club_name,
    [STORAGE_KEYS.SERVER]: baseUrl
  })
  return { ok: true, club_id: data.club_id, club_name: data.club_name }
}

async function handleListPrinters() {
  // chrome.printing solo existe en ChromeOS. En Win/Mac/Linux usamos el
  // binario nativo via chrome.runtime.connectNative — el binario enumera
  // las impresoras del SO y nos devuelve el array. Filtramos virtuales.
  const resp = await nmSend({ type: "LIST_PRINTERS" })
  if (resp?.type === "ERROR") throw new Error(resp.error || "list printers error")
  const printers = (resp?.printers || []).filter((p) => !isVirtualPrinter(p))
  return { ok: true, printers: printers.map((p) => ({ id: p.name, name: p.name, description: p.manufacturer || "" })) }
}

function isVirtualPrinter(p) {
  const name = (p.name || "").toLowerCase()
  return [
    "microsoft print to pdf",
    "microsoft xps document writer",
    "onenote",
    "fax",
    "anydesk printer",
    "save as pdf"
  ].some((needle) => name.includes(needle))
}

async function handleSetPrimaryPrinter({ device_id }) {
  if (!device_id) throw new Error("device_id requerido")
  await chrome.storage.local.set({ [STORAGE_KEYS.PRIMARY_PRINTER]: device_id })
  return { ok: true }
}

async function handlePrintTest() {
  const { [STORAGE_KEYS.PRIMARY_PRINTER]: printerName, [STORAGE_KEYS.CLUB_NAME]: clubName } =
    await chrome.storage.local.get([STORAGE_KEYS.PRIMARY_PRINTER, STORAGE_KEYS.CLUB_NAME])
  if (!printerName) throw new Error("Configurá una impresora primaria primero")

  // ESC/POS minimal: texto + corte. Mientras no haya un encoder completo,
  // alcanza para confirmar que la cadena extension → native app → printer
  // funciona end-to-end.
  const text = `\n*** PRUEBA ***\n${clubName || CURRENT_BRAND.display_name}\n${new Date().toLocaleString("es-AR")}\n\nSi ves esto, la extension funciona.\n\n\n\n`
  const bytes = encodeMinimalEscPos(text)
  return submitRawPrint(printerName, bytes)
}

async function handlePrintJob(msg) {
  const { device_id, content, escpos_base64, pdf_base64, nm_type, job_payload } = msg
  const storage = await chrome.storage.local.get([STORAGE_KEYS.PRIMARY_PRINTER])
  const printerName = device_id || storage[STORAGE_KEYS.PRIMARY_PRINTER]
  if (!printerName) throw new Error("Sin impresora destino")

  // Camino A: el server nos pasa el payload del PrintJob tal cual (comanda /
  // shelf_label). El binario nativo tiene los encoders ESC/POS full —
  // bold, doble alto, alineacion, codepage, QR, barcode, separadores —
  // solo le reenviamos el JSON y el printer_name.
  if (nm_type === "PRINT_COMANDA" || nm_type === "PRINT_LABEL") {
    return nmSendAndUnwrap({
      type: nm_type,
      printer_name: printerName,
      job: job_payload || {}
    })
  }

  // Camino B (legacy): bytes raw o texto plano.
  let bytes
  if (escpos_base64) {
    bytes = escpos_base64
  } else if (content) {
    bytes = encodeMinimalEscPos(content)
  } else if (pdf_base64) {
    throw new Error("PDF printing — no soportado todavia (proxima version)")
  } else {
    throw new Error("Sin contenido a imprimir")
  }
  return submitRawPrint(printerName, bytes)
}

async function nmSendAndUnwrap(msg) {
  const resp = await nmSend(msg)
  if (resp?.type === "PRINT_OK") return { ok: true, bytes: resp.bytes }
  throw new Error(resp?.error || `print fallo (${resp?.type || "sin respuesta"})`)
}

// Encoder minimal de ESC/POS: solo texto + alimentaciones + corte.
// Suficiente para tests. Encoder completo (codepage, alineaciones, qr,
// barcode, bold, double-height) vendra en Fase 2.
function encodeMinimalEscPos(text) {
  const lines = text.replace(/\r/g, "").split("\n")
  const ESC = 0x1b, GS = 0x1d
  const bytes = []
  // Init printer
  bytes.push(ESC, 0x40)
  for (const line of lines) {
    for (let i = 0; i < line.length; i++) bytes.push(line.charCodeAt(i) & 0xff)
    bytes.push(0x0a) // LF
  }
  // Feed + cut
  bytes.push(0x0a, 0x0a, 0x0a, 0x0a)
  bytes.push(GS, 0x56, 0x00) // GS V 0 = full cut
  // Convertir array a base64 sin pasar por Uint8Array intermedio explicito.
  let bin = ""
  for (const b of bytes) bin += String.fromCharCode(b)
  return btoa(bin)
}

// Envia PRINT_RAW al binario nativo via Native Messaging.
async function submitRawPrint(printerName, b64) {
  const resp = await nmSend({
    type: "PRINT_RAW",
    printer_name: printerName,
    b64
  })
  if (resp?.type === "PRINT_OK") {
    return { ok: true, bytes: resp.bytes }
  }
  throw new Error(resp?.error || "Print falló")
}

// nmSend: invoca el binario nativo y le manda un mensaje, espera la
// respuesta y cierra. Cada nmSend levanta un proceso (Chrome reusa hasta
// ~30s si el binario sigue vivo, pero como nosotros mandamos un mensaje y
// cerramos, cada llamada es un round-trip simple).
function nmSend(msg) {
  return new Promise((resolve, reject) => {
    let port
    try {
      port = chrome.runtime.connectNative(CURRENT_BRAND.native_host)
    } catch (e) {
      return reject(new Error(`Native app no instalada (${CURRENT_BRAND.native_host}): ${e?.message || e}`))
    }
    let settled = false
    port.onMessage.addListener((response) => {
      if (settled) return
      settled = true
      try { port.disconnect() } catch {}
      resolve(response)
    })
    port.onDisconnect.addListener(() => {
      if (settled) return
      settled = true
      const err = chrome.runtime.lastError?.message || "native port cerrado sin respuesta"
      reject(new Error(err))
    })
    try {
      port.postMessage(msg)
    } catch (e) {
      settled = true
      reject(e)
    }
  })
}

async function handleGetStatus() {
  const data = await chrome.storage.local.get(Object.values(STORAGE_KEYS))
  return {
    ok: true,
    paired: !!data[STORAGE_KEYS.TOKEN],
    club_id: data[STORAGE_KEYS.CLUB_ID] || null,
    club_name: data[STORAGE_KEYS.CLUB_NAME] || null,
    primary_printer: data[STORAGE_KEYS.PRIMARY_PRINTER] || null,
    server: data[STORAGE_KEYS.SERVER] || DEFAULT_SERVER
  }
}

