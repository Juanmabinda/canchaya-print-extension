#!/bin/bash
# Empaqueta un installer .msi para Windows (cross-build desde Mac via wixl).
#
# Diseno:
#  - Binario en %LOCALAPPDATA%\<Brand>Print\<brand>-print.exe.
#  - Manifest del NM host en la MISMA carpeta del binario, como archivo
#    static — wixl no soporta CustomActions para generar archivos en
#    install-time. El JSON ya viene con el path absoluto resuelto.
#  - Registry HKCU para Chrome / Edge / Brave apuntando al manifest.
#  - InstallScope = perUser (HKCU + LOCALAPPDATA, sin UAC).
#  - Compilado con Go 1.20.14 para que el binario corra desde Win7 SP1
#    en adelante (Go 1.21+ dropeo Win7/8).
#
# Uso:
#   ./build_installer_win_msi.sh mitienda 0.10.6

set -euo pipefail

BRAND="${1:-}"
VERSION="${2:-0.10.6}"

if [[ -z "$BRAND" ]]; then
  echo "Uso: $0 <mitienda|canchaya> [version]"
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AGENT_REPO="${AGENT_REPO:-$HOME/juanma/canchaya-print-agent}"
GO120="${GO120:-$HOME/go/bin/go1.20.14}"

case "$BRAND" in
  mitienda)
    DISPLAY="Mi Tienda Print"
    INSTALL_DIR="MiTiendaPrint"
    BINARY_NAME="mitienda-print"
    HOST_NAME="ar.mitiendapos.print"
    EXT_ID="mjjbahhakjijjaebjifddiocmmoilflo"
    DEFAULT_SERVER="https://mitiendapos.com.ar"
    MANUFACTURER="Mi Tienda POS"
    LDFLAGS_BRAND="-X main.defaultServer=https://mitiendapos.com.ar -X 'main.brandName=Mi Tienda' -X main.brandSlug=mitienda-print -X main.brandEnvVar=MITIENDA_URL -X main.brandID=mitienda -X main.brandHomepage=https://mitiendapos.com.ar -X main.brandTokenEnvVar=MITIENDA_AGENT_TOKEN -X main.brandManagedEnvVar=MITIENDA_AGENT_MANAGED"
    # UpgradeCode FIJO (no cambiar entre versiones) — wixl lo usa para que el
    # MSI nuevo REEMPLACE al viejo en lugar de instalar dos veces.
    UPGRADE_CODE="3a5e1f02-7c44-4d97-9d3b-3a0c1e9f5b40"
    ;;
  canchaya)
    DISPLAY="CanchaYa Print"
    INSTALL_DIR="CanchaYaPrint"
    BINARY_NAME="canchaya-print"
    HOST_NAME="ar.canchaya.print"
    EXT_ID="nblbfplhkfcmmpilpamdcholgjkjpflg"
    DEFAULT_SERVER="https://canchaya.ar"
    MANUFACTURER="CanchaYa"
    LDFLAGS_BRAND="-X main.defaultServer=https://canchaya.ar -X main.brandName=CanchaYa -X main.brandSlug=canchaya-print -X main.brandEnvVar=CANCHAYA_URL -X main.brandID=canchaya -X main.brandHomepage=https://canchaya.ar -X main.brandTokenEnvVar=CANCHAYA_AGENT_TOKEN -X main.brandManagedEnvVar=CANCHAYA_AGENT_MANAGED"
    UPGRADE_CODE="6c2d5a91-bf38-4612-a8d4-7e94d2c5b1c8"
    ;;
  *)
    echo "Brand invalido: $BRAND"
    exit 1
    ;;
esac

BUILD_DIR="$ROOT/installers/build/msi-$BRAND"
OUT_DIR="$ROOT/installers/dist"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$OUT_DIR"

# 1. Cross-build el binario con Go 1.20 → corre desde Win7 SP1 hasta Win11.
echo "==> Cross-compile $BINARY_NAME.exe (Go 1.20 → soporta Win7+)"
pushd "$AGENT_REPO" > /dev/null
LDFLAGS="-s -w $LDFLAGS_BRAND"
GOOS=windows GOARCH=amd64 CGO_ENABLED=0 "$GO120" build \
  -ldflags "$LDFLAGS" \
  -o "$BUILD_DIR/$BINARY_NAME.exe" .
popd > /dev/null
ls -la "$BUILD_DIR/$BINARY_NAME.exe"

# 2. Manifest JSON del NM host. Path absoluto: %LOCALAPPDATA% se resuelve a
#    C:\Users\<user>\AppData\Local en install-time. Lo escribimos con %ENV%
#    embebido — Chrome NO expande variables en el "path", asi que el JSON
#    final tiene que tener un path concreto.
#    Solucion: en lugar de %LOCALAPPDATA%, el path queda relativo al MSI:
#    Wix InstallFolder = LocalAppDataFolder\INSTALL_DIR. Wix copia el JSON
#    despues de escribir las variables [APPDATA]. Pero JSON no soporta
#    propiedades de Wix dentro. Workaround: generar el JSON con un sentinel
#    y reescribirlo con una CustomAction. wixl SOPORTA WixCA en modo basico:
#    usamos "WixSilentExec" para correr cmd.exe que reescribe el archivo
#    con el path real (envvar %LOCALAPPDATA%).
#
# Mas simple aun: el archivo JSON lo metemos como wxs File con un
# placeholder, y NO lo tocamos despues. El path en el JSON es relativo
# al manifest: ".\<binary>". Chrome desde la version 80 soporta paths
# relativos en el "path" del manifest (los resuelve relativo al JSON).
cat > "$BUILD_DIR/${HOST_NAME}.json" <<JSON
{
  "name": "${HOST_NAME}",
  "description": "${DISPLAY} Native Messaging Host",
  "path": "${BINARY_NAME}.exe",
  "type": "stdio",
  "allowed_origins": ["chrome-extension://${EXT_ID}/"]
}
JSON

# 3. Generar GUIDs deterministicos para los componentes (uno por archivo,
# uno por registry value). wixl matchea por GUID al hacer upgrade.
COMP_BINARY_GUID="$(uuidgen)"
COMP_MANIFEST_GUID="$(uuidgen)"
COMP_REG_CHROME_GUID="$(uuidgen)"
COMP_REG_EDGE_GUID="$(uuidgen)"
COMP_REG_BRAVE_GUID="$(uuidgen)"
PRODUCT_GUID="$(uuidgen)"

# 4. WiX XML. Estructura minimal: perUser install, LocalAppDataFolder como
# raiz, dos archivos + tres registry entries.
cat > "$BUILD_DIR/installer.wxs" <<WXS
<?xml version="1.0" encoding="UTF-8"?>
<Wix xmlns="http://schemas.microsoft.com/wix/2006/wi">
  <Product Id="${PRODUCT_GUID}"
           Name="${DISPLAY} Agent"
           Language="1033"
           Version="${VERSION}.0"
           Manufacturer="${MANUFACTURER}"
           UpgradeCode="${UPGRADE_CODE}">

    <Package InstallerVersion="200"
             Compressed="yes"
             InstallScope="perUser"
             Description="${DISPLAY} Native Messaging Host" />

    <!-- Upgrade explicito (mas portable que MajorUpgrade en wixl): el viejo
         MSI con mismo UpgradeCode se desinstala automaticamente cuando se
         instala uno nuevo con version mayor. -->
    <Upgrade Id="${UPGRADE_CODE}">
      <UpgradeVersion Minimum="0.0.0"
                      Maximum="${VERSION}.0"
                      IncludeMinimum="yes"
                      IncludeMaximum="no"
                      Property="OLDERVERSIONBEINGUPGRADED" />
    </Upgrade>
    <InstallExecuteSequence>
      <RemoveExistingProducts After="InstallInitialize" />
    </InstallExecuteSequence>

    <Media Id="1" Cabinet="agent.cab" EmbedCab="yes" />

    <Directory Id="TARGETDIR" Name="SourceDir">
      <Directory Id="LocalAppDataFolder">
        <Directory Id="INSTALLDIR" Name="${INSTALL_DIR}">

          <Component Id="cmpBinary"
                     Guid="${COMP_BINARY_GUID}"
                     Win64="yes">
            <RegistryValue Root="HKCU"
                           Key="Software\\${MANUFACTURER}\\${INSTALL_DIR}"
                           Name="Installed"
                           Type="integer"
                           Value="1"
                           KeyPath="yes" />
            <File Id="filBinary"
                  Name="${BINARY_NAME}.exe"
                  Source="${BUILD_DIR}/${BINARY_NAME}.exe" />
            <RemoveFolder Id="rmInstallDir" On="uninstall" />
          </Component>

          <Component Id="cmpManifest"
                     Guid="${COMP_MANIFEST_GUID}"
                     Win64="yes">
            <RegistryValue Root="HKCU"
                           Key="Software\\${MANUFACTURER}\\${INSTALL_DIR}"
                           Name="ManifestInstalled"
                           Type="integer"
                           Value="1"
                           KeyPath="yes" />
            <File Id="filManifest"
                  Name="${HOST_NAME}.json"
                  Source="${BUILD_DIR}/${HOST_NAME}.json" />
          </Component>

          <!-- Tres entries de registry, uno por navegador. KeyPath en el
               propio RegistryValue para que wix lo trackee. -->
          <Component Id="cmpRegChrome"
                     Guid="${COMP_REG_CHROME_GUID}"
                     Win64="yes">
            <RegistryKey Root="HKCU"
                         Key="Software\\Google\\Chrome\\NativeMessagingHosts\\${HOST_NAME}">
              <RegistryValue Type="string"
                             Value="[INSTALLDIR]${HOST_NAME}.json"
                             KeyPath="yes" />
            </RegistryKey>
          </Component>

          <Component Id="cmpRegEdge"
                     Guid="${COMP_REG_EDGE_GUID}"
                     Win64="yes">
            <RegistryKey Root="HKCU"
                         Key="Software\\Microsoft\\Edge\\NativeMessagingHosts\\${HOST_NAME}">
              <RegistryValue Type="string"
                             Value="[INSTALLDIR]${HOST_NAME}.json"
                             KeyPath="yes" />
            </RegistryKey>
          </Component>

          <Component Id="cmpRegBrave"
                     Guid="${COMP_REG_BRAVE_GUID}"
                     Win64="yes">
            <RegistryKey Root="HKCU"
                         Key="Software\\BraveSoftware\\Brave-Browser\\NativeMessagingHosts\\${HOST_NAME}">
              <RegistryValue Type="string"
                             Value="[INSTALLDIR]${HOST_NAME}.json"
                             KeyPath="yes" />
            </RegistryKey>
          </Component>

        </Directory>
      </Directory>
    </Directory>

    <Feature Id="Main" Title="${DISPLAY} Agent" Level="1">
      <ComponentRef Id="cmpBinary" />
      <ComponentRef Id="cmpManifest" />
      <ComponentRef Id="cmpRegChrome" />
      <ComponentRef Id="cmpRegEdge" />
      <ComponentRef Id="cmpRegBrave" />
    </Feature>

  </Product>
</Wix>
WXS

# 5. wixl compila el .wxs a .msi.
OUT_MSI="$OUT_DIR/${INSTALL_DIR}Agent-${VERSION}.msi"
echo "==> wixl..."
wixl -v --arch x64 -o "$OUT_MSI" "$BUILD_DIR/installer.wxs" 2>&1 | tail -8

if [[ -f "$OUT_MSI" ]]; then
  echo ""
  echo "✓ $OUT_MSI"
  ls -lh "$OUT_MSI"
else
  echo "✗ wixl no genero el .msi"
  exit 1
fi
