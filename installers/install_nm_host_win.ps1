# Registra el binario como Native Messaging Host para Chrome en Windows.
# Necesario UNA vez tras instalar la app nativa.
#
# Chrome busca el manifest en el registro:
#   HKCU\Software\Google\Chrome\NativeMessagingHosts\<host_name>
#   (default) = ruta al manifest.json
#
# El manifest.json en sí va en una carpeta junto al binario.
#
# Uso:
#   .\install_nm_host_win.ps1 -Brand mitienda -ExtensionId ldkiekkbkeeoeceibniihmjgkocgdnfb
#   .\install_nm_host_win.ps1 -Brand canchaya -ExtensionId abc... -BinaryPath "C:\Program Files\CanchaYa Print\agent.exe"

param(
  [Parameter(Mandatory=$true)] [string]$Brand,
  [string]$BinaryPath = ""
)

# IDs FIJOS calculados desde la "key" RSA hardcodeada en cada manifest.
# Con la key fija el ID NO cambia entre dev/staging/prod ni entre maquinas
# — siempre es el mismo. El cliente NO tiene que pegar nada: el installer
# (.msi) llama a este script con el brand correcto y listo.
if ($Brand -eq "mitienda") {
  $HostName = "ar.mitiendapos.print"
  $ExtensionId = "mjjbahhakjijjaebjifddiocmmoilflo"
  $BinaryDefault = "$env:LOCALAPPDATA\MiTiendaPrint\mitienda-print.exe"
} elseif ($Brand -eq "canchaya") {
  $HostName = "ar.canchaya.print"
  $ExtensionId = "nblbfplhkfcmmpilpamdcholgjkjpflg"
  $BinaryDefault = "$env:LOCALAPPDATA\CanchaYaPrint\canchaya-print.exe"
} else {
  Write-Host "Brand invalido: $Brand. Usar 'mitienda' o 'canchaya'."
  exit 1
}

if ([string]::IsNullOrEmpty($BinaryPath)) {
  $BinaryPath = $BinaryDefault
}

if (-not (Test-Path $BinaryPath)) {
  Write-Host "FAIL: binario no existe: $BinaryPath"
  Write-Host "      Instalá la app nativa primero o pasá -BinaryPath con la ruta correcta."
  exit 1
}

# Carpeta para el manifest. Convencion: junto al binario.
$ManifestDir = Split-Path $BinaryPath -Parent
$ManifestPath = Join-Path $ManifestDir "$HostName.json"

# Generar el manifest JSON. allowed_origins matchea el ID de la extension
# cargada (en dev) o el ID que asigna Chrome Web Store (en prod).
$Manifest = @{
  name        = $HostName
  description = "$Brand Print Native Messaging Host"
  path        = $BinaryPath
  type        = "stdio"
  allowed_origins = @("chrome-extension://$ExtensionId/")
}
$Manifest | ConvertTo-Json -Depth 5 | Set-Content -Path $ManifestPath -Encoding UTF8

# Registrar en HKCU para que Chrome lo encuentre. Usamos HKCU (current user)
# para no requerir admin — funciona para el cajero que abre Mi Tienda POS
# en su sesion de Windows.
$RegPath = "HKCU:\Software\Google\Chrome\NativeMessagingHosts\$HostName"
New-Item -Path $RegPath -Force | Out-Null
Set-ItemProperty -Path $RegPath -Name "(Default)" -Value $ManifestPath

# Tambien para Edge (Chromium-based, usa la misma API).
$RegPathEdge = "HKCU:\Software\Microsoft\Edge\NativeMessagingHosts\$HostName"
New-Item -Path $RegPathEdge -Force | Out-Null
Set-ItemProperty -Path $RegPathEdge -Name "(Default)" -Value $ManifestPath

Write-Host "[OK] Native Messaging Host registrado"
Write-Host "     Host:    $HostName"
Write-Host "     Binario: $BinaryPath"
Write-Host "     Manifest: $ManifestPath"
Write-Host "     Extension: $ExtensionId"
Write-Host ""
Write-Host "     Registry keys:"
Write-Host "       $RegPath"
Write-Host "       $RegPathEdge"
Write-Host ""
Write-Host "Reinicia Chrome (o cerra el popup y abrilo de nuevo) para que tome el cambio."
