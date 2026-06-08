#!/usr/bin/env node
// Build script — genera dist/mitienda/ y dist/canchaya/ a partir de src/.
//
// Para cada brand:
//   1. Copia todos los archivos de src/ a dist/{brand}/
//   2. Renombra manifest.{brand}.json → manifest.json (descarta los otros)
//   3. Reemplaza el placeholder `const BRAND = "mitienda"` en brand.js y
//      content.js por el brand que toca.
//
// Uso:  node build.js
//
// Después de buildear: subir dist/mitienda/ y dist/canchaya/ por separado
// al Chrome Web Store (cada uno es un producto independiente).

const fs = require("fs")
const path = require("path")

const SRC = path.join(__dirname, "src")
const DIST = path.join(__dirname, "dist")
const BRANDS = ["mitienda", "canchaya"]

function rmrf(p) {
  if (fs.existsSync(p)) fs.rmSync(p, { recursive: true, force: true })
}

function copyDir(src, dst) {
  fs.mkdirSync(dst, { recursive: true })
  for (const entry of fs.readdirSync(src, { withFileTypes: true })) {
    const s = path.join(src, entry.name)
    const d = path.join(dst, entry.name)
    if (entry.isDirectory()) copyDir(s, d)
    else fs.copyFileSync(s, d)
  }
}

function build(brand) {
  const out = path.join(DIST, brand)
  rmrf(out)
  copyDir(SRC, out)

  // Manifest: usar el del brand correcto y descartar los demás.
  const target = brand === "mitienda" ? "manifest.json" : `manifest.${brand}.json`
  if (target !== "manifest.json") {
    fs.copyFileSync(path.join(out, target), path.join(out, "manifest.json"))
  }
  for (const f of fs.readdirSync(out)) {
    if (f.startsWith("manifest.") && f !== "manifest.json") {
      fs.rmSync(path.join(out, f))
    }
  }

  // Patchear BRAND en brand.js y content.js (que tienen un default hardcoded).
  for (const f of ["brand.js", "content.js"]) {
    const p = path.join(out, f)
    if (!fs.existsSync(p)) continue
    const txt = fs.readFileSync(p, "utf8")
    const patched = txt.replace(/const BRAND = "mitienda"/g, `const BRAND = "${brand}"`)
                       .replace(/export const BRAND = "mitienda"/g, `export const BRAND = "${brand}"`)
    fs.writeFileSync(p, patched)
  }

  console.log(`✓ ${brand} → ${path.relative(__dirname, out)}/`)
}

rmrf(DIST)
BRANDS.forEach(build)
console.log("\nPara subir al Chrome Web Store:")
console.log("  cd dist/mitienda && zip -r ../mitienda-print-extension.zip .")
console.log("  cd dist/canchaya && zip -r ../canchaya-print-extension.zip .")
