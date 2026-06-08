// Logica del popup. Habla solo con el service worker via chrome.runtime.sendMessage.

const $ = (id) => document.getElementById(id)

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
  const r = await chrome.runtime.sendMessage({ type: "LIST_PRINTERS" })
  const sel = $("printer-select")
  sel.innerHTML = '<option value="">— elegí una —</option>'
  if (!r?.ok) {
    $("printer-status").textContent = `Error: ${r?.error || "no se pudo listar"}`
    return
  }
  r.printers.forEach((p) => {
    const opt = document.createElement("option")
    opt.value = p.id
    opt.textContent = p.name + (p.is_default ? " (default)" : "")
    if (p.id === preselectId) opt.selected = true
    sel.appendChild(opt)
  })
  $("printer-status").textContent = `${r.printers.length} impresoras detectadas`
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
  const r = await chrome.runtime.sendMessage({ type: "PAIR_AGENT", code })
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
  $("printer-status").textContent = "Enviando…"
  $("printer-status").className = "small muted"
  const r = await chrome.runtime.sendMessage({ type: "PRINT_TEST" })
  $("printer-status").textContent = r?.ok
    ? `Enviado — status ${r.status}`
    : `Error: ${r?.error || "no se pudo imprimir"}`
  $("printer-status").className = r?.ok ? "small ok" : "small err"
})

refreshStatus()
