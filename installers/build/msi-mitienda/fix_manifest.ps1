param([string]$Brand)
$ErrorActionPreference = "Continue"
$installDir = if ($Brand -eq "canchaya") { "CanchaYaPrint" } else { "MiTiendaPrint" }
$binaryName = if ($Brand -eq "canchaya") { "canchaya-print.exe" } else { "mitienda-print.exe" }
$hostName   = if ($Brand -eq "canchaya") { "ar.canchaya.print" } else { "ar.mitiendapos.print" }
$extId      = if ($Brand -eq "canchaya") { "nblbfplhkfcmmpilpamdcholgjkjpflg" } else { "mjjbahhakjijjaebjifddiocmmoilflo" }
$display    = if ($Brand -eq "canchaya") { "CanchaYa Print" } else { "Mi Tienda Print" }

$dir = Join-Path $env:LOCALAPPDATA $installDir
$binPath = Join-Path $dir $binaryName
$jsonPath = Join-Path $dir "$hostName.json"

$obj = [ordered]@{
  name = $hostName
  description = "$display Native Messaging Host"
  path = $binPath
  type = "stdio"
  allowed_origins = @("chrome-extension://$extId/")
}
$json = $obj | ConvertTo-Json -Depth 5
Set-Content -Path $jsonPath -Value $json -Encoding UTF8

# Tambien copiamos a Edge y Brave si tienen sus paths de NM hosts
# expandidos (sino, Chrome solo usa registry → lee el del registry que
# apunta a [INSTALLDIR]<host>.json, que es el que acabamos de reescribir).
# No es necesario duplicar el archivo — los 3 registry keys ya apuntan al
# mismo JSON. Pero verifico que la escritura quedo bien.
if (Test-Path $jsonPath) {
  Write-Host "Manifest reescrito en $jsonPath con path absoluto."
} else {
  Write-Error "ERROR: no se pudo escribir $jsonPath"
  exit 1
}
