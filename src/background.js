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
  const url = `${baseUrl}/api/agent_pair`
  // Endpoint legacy del agente Go: { code } → { token, club_id, club_name }.
  // Reusamos el mismo flow para no inventar uno nuevo.
  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json", "Accept": "application/json" },
    body: JSON.stringify({ code })
  })
  if (!res.ok) {
    const txt = await res.text().catch(() => "")
    throw new Error(`Pareo falló (${res.status}): ${txt.slice(0, 200)}`)
  }
  const data = await res.json()
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
  // chrome.printing.getPrinters lista impresoras instaladas en el SO. Tanto
  // USB como LAN, fisicas y virtuales. Filtramos las virtuales obvias para
  // que el cajero no se confunda eligiendo "Microsoft Print to PDF" como
  // termica.
  const printers = await chrome.printing.getPrinters()
  const filtered = printers.filter((p) => !isVirtualPrinter(p))
  return { ok: true, printers: filtered.map(serializePrinter) }
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

function serializePrinter(p) {
  return {
    id: p.id,
    name: p.name,
    description: p.description || "",
    is_default: !!p.isDefault,
    source: p.source || "USER"
  }
}

async function handleSetPrimaryPrinter({ device_id }) {
  if (!device_id) throw new Error("device_id requerido")
  await chrome.storage.local.set({ [STORAGE_KEYS.PRIMARY_PRINTER]: device_id })
  return { ok: true }
}

async function handlePrintTest() {
  const { [STORAGE_KEYS.PRIMARY_PRINTER]: deviceId, [STORAGE_KEYS.CLUB_NAME]: clubName } =
    await chrome.storage.local.get([STORAGE_KEYS.PRIMARY_PRINTER, STORAGE_KEYS.CLUB_NAME])
  if (!deviceId) throw new Error("Configurá una impresora primaria primero")

  const text = `\n*** PRUEBA ***\n${clubName || CURRENT_BRAND.display_name}\n${new Date().toLocaleString("es-AR")}\n\nSi ves esto, la extension funciona.\n\n\n\n`
  return submitJobAsPdf(deviceId, "Prueba", text)
}

async function handlePrintJob({ device_id, title, content }) {
  const target = device_id ||
    (await chrome.storage.local.get([STORAGE_KEYS.PRIMARY_PRINTER]))[STORAGE_KEYS.PRIMARY_PRINTER]
  if (!target) throw new Error("Sin impresora destino")
  return submitJobAsPdf(target, title || "Ticket", content || "")
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

// === chrome.printing.submitJob helper ===
//
// chrome.printing solo acepta PDF. Para "imprimir texto plano" generamos un
// PDF minimo on-the-fly con un layout monoespaciado 80mm. Cuando avancemos
// a Fase 2 (ESC/POS directo), este wrapper se reemplaza por bytes raw via
// chrome.printerProvider o por imprimir un PDF generado server-side.
async function submitJobAsPdf(printerId, title, text) {
  const pdfBlob = renderMinimalPdf(text)
  const buf = await pdfBlob.arrayBuffer()
  // Encode base64 manualmente — Blob → base64 sin FileReader (que no existe
  // en service workers MV3).
  const u8 = new Uint8Array(buf)
  let bin = ""
  for (let i = 0; i < u8.length; i++) bin += String.fromCharCode(u8[i])
  const b64 = btoa(bin)

  const job = {
    printerId,
    title: title || "Ticket",
    ticket: { version: "1.0" },
    contentType: "application/pdf",
    document: b64
  }
  // En MV3 chrome.printing.submitJob devuelve Promise. La API legacy con
  // callback tira un warning pero sigue funcionando.
  const result = await chrome.printing.submitJob({ job })
  if (result?.status === "OK" || result?.status === "INPROGRESS") {
    return { ok: true, status: result.status, job_id: result.jobId }
  }
  throw new Error(`submitJob status=${result?.status || "UNKNOWN"}`)
}

// PDF minimo de texto monoespaciado — armado a mano para evitar dependencia
// de pdf-lib en el service worker (que ya es chico, no queremos meter 500KB
// de libreria solo para un wrapper que vamos a tirar al pasar a ESC/POS).
//
// 1 pagina A6 (~80mm ancho * 200mm alto) con texto en Courier. Suficiente
// para prueba; para producción real generamos el PDF server-side.
function renderMinimalPdf(text) {
  const lines = text.split("\n")
  const lineHeight = 14
  const pageHeight = Math.max(200, lines.length * lineHeight + 40)
  const pageWidth = 226 // ~80mm a 72dpi

  // Stream de contenido: BT (begin text) … ET (end text) con cada linea.
  let stream = `BT\n/F1 10 Tf\n14 ${pageHeight - 20} Td\n`
  lines.forEach((line, i) => {
    const escaped = line.replace(/\\/g, "\\\\").replace(/\(/g, "\\(").replace(/\)/g, "\\)")
    if (i > 0) stream += `0 -${lineHeight} Td\n`
    stream += `(${escaped}) Tj\n`
  })
  stream += "ET"

  const streamLen = stream.length
  const objects = [
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
    `<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ${pageWidth} ${pageHeight}] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>`,
    `<< /Length ${streamLen} >>\nstream\n${stream}\nendstream`,
    "<< /Type /Font /Subtype /Type1 /BaseFont /Courier >>"
  ]

  let pdf = "%PDF-1.4\n"
  const offsets = [0]
  objects.forEach((obj, i) => {
    offsets.push(pdf.length)
    pdf += `${i + 1} 0 obj\n${obj}\nendobj\n`
  })
  const xrefStart = pdf.length
  pdf += `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n`
  for (let i = 1; i <= objects.length; i++) {
    pdf += `${String(offsets[i]).padStart(10, "0")} 00000 n \n`
  }
  pdf += `trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n${xrefStart}\n%%EOF`

  return new Blob([pdf], { type: "application/pdf" })
}
