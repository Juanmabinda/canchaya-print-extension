// Logica del popup. Habla solo con el service worker via chrome.runtime.sendMessage.

const $ = (id) => document.getElementById(id)

// Hosts validos del POS — coinciden con host_permissions del manifest.
// Cuando el popup se abre, leemos la URL de la tab activa y, si matchea
// un host del POS, usamos ese origen como server. Asi el cajero no
// tiene que elegir entre prod / staging manualmente — se detecta del
// browser.
const POS_HOSTS = [
  "mitiendapos.com.ar",
  "staging.mitiendapos.com.ar",
  "canchaya.ar",
  "staging.canchaya.ar",
  "canchalibre.app",
  "staging.canchalibre.app"
]

let detectedServer = null  // origen autodetectado, null si no hay tab POS

async function detectServerFromActiveTab() {
  try {
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true })
    if (!tab?.url) return null
    const u = new URL(tab.url)
    if (POS_HOSTS.includes(u.host)) return `${u.protocol}//${u.host}`
    return null
  } catch {
    return null
  }
}

async function refreshStatus() {
  const s = await chrome.runtime.sendMessage({ type: "GET_STATUS" })
  if (!s?.ok) return
  $("status-pill").classList.toggle("online", s.paired)
  $("status-pill").classList.toggle("offline", !s.paired)
  $("status-pill").textContent = s.paired ? "Conectada" : "No conectada"

  $("pair-section").hidden = s.paired
  $("paired-section").hidden = !s.paired
  $("printer-section").hidden = !s.paired

  $("club-name").textContent = s.club_name || `Club #${s.club_id || "?"}`

  if (s.paired) await loadPrinters(s.primary_printer)
}

async function loadPrinters(preselectId) {
  // Spinner mientras el binario nativo arranca + enumera impresoras. En
  // Mac la primera vez CUPS auto-crea la cola USB en raw mode lo que puede
  // tardar 5-10s; en Win es instantaneo. Mostramos feedback claro.
  const sel = $("printer-select"), saveBtn = $("save-printer-btn"),
        testBtn = $("test-btn"), loading = $("printer-loading"),
        status = $("printer-status")
  loading.hidden = false
  sel.hidden = true; saveBtn.hidden = true; testBtn.hidden = true
  status.textContent = ""

  const r = await chrome.runtime.sendMessage({ type: "LIST_PRINTERS" })

  loading.hidden = true
  sel.hidden = false; saveBtn.hidden = false; testBtn.hidden = false

  sel.innerHTML = '<option value="">— elegí una —</option>'
  if (!r?.ok) {
    status.textContent = `Error: ${r?.error || "no se pudo listar"}`
    status.className = "small err"
    return
  }
  r.printers.forEach((p) => {
    const opt = document.createElement("option")
    opt.value = p.id
    opt.textContent = p.name + (p.is_default ? " (default)" : "")
    if (p.id === preselectId) opt.selected = true
    sel.appendChild(opt)
  })
  status.textContent = `${r.printers.length} impresora${r.printers.length === 1 ? "" : "s"} detectada${r.printers.length === 1 ? "" : "s"}`
  status.className = "small muted"
}

$("pair-btn").addEventListener("click", async () => {
  const code = $("code").value.trim().toUpperCase()
  if (!code) {
    $("pair-status").textContent = "Pegá el código primero"
    $("pair-status").className = "small err"
    return
  }
  $("pair-status").textContent = "Conectando…"
  $("pair-status").className = "small muted"
  // detectedServer viene del auto-detect de la tab activa al cargar el
  // popup. Si es null (no hay tab del POS abierta) el background usa
  // CURRENT_BRAND.default_server (prod).
  const r = await chrome.runtime.sendMessage({ type: "PAIR_AGENT", code, server: detectedServer })
  if (r?.ok) {
    $("pair-status").textContent = `OK — ${r.club_name || "club #" + r.club_id}`
    $("pair-status").className = "small ok"
    await refreshStatus()
  } else {
    $("pair-status").textContent = r?.error || "Falló el pareo"
    $("pair-status").className = "small err"
  }
})

$("unpair-btn").addEventListener("click", async () => {
  await chrome.storage.local.clear()
  await refreshStatus()
})

$("save-printer-btn").addEventListener("click", async () => {
  const id = $("printer-select").value
  if (!id) {
    $("printer-status").textContent = "Elegí una impresora primero"
    $("printer-status").className = "small err"
    return
  }
  const r = await chrome.runtime.sendMessage({ type: "SET_PRIMARY_PRINTER", device_id: id })
  $("printer-status").textContent = r?.ok ? "Guardada" : `Error: ${r?.error}`
  $("printer-status").className = r?.ok ? "small ok" : "small err"
})

$("test-btn").addEventListener("click", async () => {
  $("printer-status").innerHTML = '<span class="spinner"></span> Imprimiendo…'
  $("printer-status").className = "small muted"
  const r = await chrome.runtime.sendMessage({ type: "PRINT_TEST" })
  if (r?.ok) {
    $("printer-status").textContent = `✓ Impreso${r.bytes ? ` (${r.bytes} bytes)` : ""}`
    $("printer-status").className = "small ok"
  } else {
    $("printer-status").textContent = `Error: ${r?.error || "no se pudo imprimir"}`
    $("printer-status").className = "small err"
  }
})

async function init() {
  detectedServer = await detectServerFromActiveTab()
  if (detectedServer) {
    $("detected-server").textContent = `📡 ${new URL(detectedServer).host}`
    $("detected-server").className = "small ok"
  } else {
    $("detected-server").textContent = "Abrí una pestaña del POS para detectar el server"
  }
  await refreshStatus()
}

init()
