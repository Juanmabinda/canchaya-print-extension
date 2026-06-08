#!/bin/bash
# Empaqueta un installer .exe (NSIS) para Windows que:
#   1. Copia el binario nativo a %LOCALAPPDATA%\<Brand>Print\<brand>-print.exe
#   2. Registra el Native Messaging Host en HKCU\Software\Google\Chrome\
#      NativeMessagingHosts\<host>
#   3. Tambien lo registra para Edge y Brave.
#
# Cross-compile + makensis corren en Mac, no necesitamos VM Windows.
#
# Uso:
#   ./build_installer_win.sh mitienda
#   ./build_installer_win.sh canchaya

set -euo pipefail

BRAND="${1:-}"
VERSION="${2:-0.10.4}"

if [[ -z "$BRAND" ]]; then
  echo "Uso: $0 <mitienda|canchaya> [version]"
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AGENT_REPO="${AGENT_REPO:-$HOME/juanma/canchaya-print-agent}"

case "$BRAND" in
  mitienda)
    DISPLAY="Mi Tienda Print"
    INSTALL_DIR="MiTiendaPrint"
    BINARY_NAME="mitienda-print"
    HOST_NAME="ar.mitiendapos.print"
    EXT_ID="mjjbahhakjijjaebjifddiocmmoilflo"
    DEFAULT_SERVER="https://mitiendapos.com.ar"
    BRAND_LDFLAGS="-X main.defaultServer=https://mitiendapos.com.ar -X main.brandName=Mi\\ Tienda -X main.brandSlug=mitienda-print -X main.brandEnvVar=MITIENDA_URL -X main.brandID=mitienda -X main.brandHomepage=https://mitiendapos.com.ar -X main.brandTokenEnvVar=MITIENDA_AGENT_TOKEN -X main.brandManagedEnvVar=MITIENDA_AGENT_MANAGED"
    ;;
  canchaya)
    DISPLAY="CanchaYa Print"
    INSTALL_DIR="CanchaYaPrint"
    BINARY_NAME="canchaya-print"
    HOST_NAME="ar.canchaya.print"
    EXT_ID="nblbfplhkfcmmpilpamdcholgjkjpflg"
    DEFAULT_SERVER="https://canchaya.ar"
    BRAND_LDFLAGS="-X main.defaultServer=https://canchaya.ar -X main.brandName=CanchaYa -X main.brandSlug=canchaya-print -X main.brandEnvVar=CANCHAYA_URL -X main.brandID=canchaya -X main.brandHomepage=https://canchaya.ar -X main.brandTokenEnvVar=CANCHAYA_AGENT_TOKEN -X main.brandManagedEnvVar=CANCHAYA_AGENT_MANAGED"
    ;;
  *)
    echo "Brand invalido: $BRAND"
    exit 1
    ;;
esac

BUILD_DIR="$ROOT/installers/build/win-$BRAND"
OUT_DIR="$ROOT/installers/dist"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$OUT_DIR"

# 1. Cross-compile el binario para Windows desde Mac. CGO desactivado para
# que no necesite mingw — el agente Go no usa cgo en su path normal.
echo "==> Cross-compile $BINARY_NAME.exe"
pushd "$AGENT_REPO" > /dev/null
LDFLAGS="-s -w"
case "$BRAND" in
  mitienda)
    LDFLAGS="$LDFLAGS -X main.defaultServer=https://mitiendapos.com.ar"
    LDFLAGS="$LDFLAGS -X 'main.brandName=Mi Tienda'"
    LDFLAGS="$LDFLAGS -X main.brandSlug=mitienda-print"
    LDFLAGS="$LDFLAGS -X main.brandEnvVar=MITIENDA_URL"
    LDFLAGS="$LDFLAGS -X main.brandID=mitienda"
    LDFLAGS="$LDFLAGS -X main.brandHomepage=https://mitiendapos.com.ar"
    LDFLAGS="$LDFLAGS -X main.brandTokenEnvVar=MITIENDA_AGENT_TOKEN"
    LDFLAGS="$LDFLAGS -X main.brandManagedEnvVar=MITIENDA_AGENT_MANAGED"
    ;;
  canchaya)
    LDFLAGS="$LDFLAGS -X main.defaultServer=https://canchaya.ar"
    LDFLAGS="$LDFLAGS -X main.brandName=CanchaYa"
    LDFLAGS="$LDFLAGS -X main.brandSlug=canchaya-print"
    LDFLAGS="$LDFLAGS -X main.brandEnvVar=CANCHAYA_URL"
    LDFLAGS="$LDFLAGS -X main.brandID=canchaya"
    LDFLAGS="$LDFLAGS -X main.brandHomepage=https://canchaya.ar"
    LDFLAGS="$LDFLAGS -X main.brandTokenEnvVar=CANCHAYA_AGENT_TOKEN"
    LDFLAGS="$LDFLAGS -X main.brandManagedEnvVar=CANCHAYA_AGENT_MANAGED"
    ;;
esac
GOOS=windows GOARCH=amd64 CGO_ENABLED=0 go build \
  -ldflags "$LDFLAGS" \
  -o "$BUILD_DIR/$BINARY_NAME.exe" .
popd > /dev/null
ls -la "$BUILD_DIR/$BINARY_NAME.exe"

# 2. Genera el .nsi inline. El installer corre como usuario actual (HKCU,
# %LOCALAPPDATA%) — no requiere admin. Eso evita el prompt UAC.
cat > "$BUILD_DIR/installer.nsi" <<NSI
; NSIS installer para $DISPLAY Native Messaging Agent.
; Instala el binario en %LOCALAPPDATA%\\$INSTALL_DIR\\ y registra el NM host.

!define APP_NAME "$DISPLAY Agent"
!define APP_VERSION "$VERSION"
!define INSTALL_FOLDER "$INSTALL_DIR"
!define BINARY_NAME "$BINARY_NAME.exe"
!define HOST_NAME "$HOST_NAME"
!define EXT_ID "$EXT_ID"

Name "\${APP_NAME}"
OutFile "$OUT_DIR\\${INSTALL_DIR}Agent-${VERSION}.exe"
RequestExecutionLevel user
SetCompressor /SOLID lzma
InstallDir "\$LOCALAPPDATA\\\${INSTALL_FOLDER}"

; UI minimalista (sin license, sin pages confusas para el cajero).
!include "MUI2.nsh"
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_LANGUAGE "Spanish"

Section
  SetOutPath "\$INSTDIR"
  File "$BINARY_NAME.exe"

  ; Manifest del NM host — JSON que apunta al binario + permite la extension.
  ; NSIS: comillas simples como delimitador → comillas dobles dentro sin escape.
  ; \$INSTDIR se expande al destino real (%LOCALAPPDATA%\\<INSTALL_DIR>).
  ; Las \\\\ se vuelven \\ literal en el JSON (path Windows con \\ entre folders).
  FileOpen \$0 '\$INSTDIR\\\${HOST_NAME}.json' w
  FileWrite \$0 '{\$\\n'
  FileWrite \$0 '  "name": "\${HOST_NAME}",\$\\n'
  FileWrite \$0 '  "description": "\${APP_NAME} Native Messaging Host",\$\\n'
  FileWrite \$0 '  "path": "\$INSTDIR\\\\\${BINARY_NAME}",\$\\n'
  FileWrite \$0 '  "type": "stdio",\$\\n'
  FileWrite \$0 '  "allowed_origins": ["chrome-extension://\${EXT_ID}/"]\$\\n'
  FileWrite \$0 '}\$\\n'
  FileClose \$0

  ; Registry HKCU — Chrome busca el manifest aca.
  WriteRegStr HKCU "Software\\Google\\Chrome\\NativeMessagingHosts\\\${HOST_NAME}" "" "\$INSTDIR\\\${HOST_NAME}.json"
  ; Edge (Chromium).
  WriteRegStr HKCU "Software\\Microsoft\\Edge\\NativeMessagingHosts\\\${HOST_NAME}" "" "\$INSTDIR\\\${HOST_NAME}.json"
  ; Brave (Chromium).
  WriteRegStr HKCU "Software\\BraveSoftware\\Brave-Browser\\NativeMessagingHosts\\\${HOST_NAME}" "" "\$INSTDIR\\\${HOST_NAME}.json"

  ; Uninstaller para Programs and Features.
  WriteUninstaller '\$INSTDIR\\Uninstall.exe'
  WriteRegStr HKCU 'Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\\${HOST_NAME}' 'DisplayName' '\${APP_NAME}'
  WriteRegStr HKCU 'Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\\${HOST_NAME}' 'DisplayVersion' '\${APP_VERSION}'
  WriteRegStr HKCU 'Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\\${HOST_NAME}' 'UninstallString' '"\$INSTDIR\\Uninstall.exe"'
  WriteRegStr HKCU 'Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\\${HOST_NAME}' 'InstallLocation' '\$INSTDIR'
SectionEnd

Section "Uninstall"
  Delete "\$INSTDIR\\\${BINARY_NAME}"
  Delete "\$INSTDIR\\\${HOST_NAME}.json"
  Delete "\$INSTDIR\\Uninstall.exe"
  RMDir "\$INSTDIR"

  DeleteRegKey HKCU "Software\\Google\\Chrome\\NativeMessagingHosts\\\${HOST_NAME}"
  DeleteRegKey HKCU "Software\\Microsoft\\Edge\\NativeMessagingHosts\\\${HOST_NAME}"
  DeleteRegKey HKCU "Software\\BraveSoftware\\Brave-Browser\\NativeMessagingHosts\\\${HOST_NAME}"
  DeleteRegKey HKCU "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\\${HOST_NAME}"
SectionEnd
NSI

# 3. makensis compila el .nsi a .exe.
echo "==> makensis..."
makensis "$BUILD_DIR/installer.nsi" 2>&1 | tail -5

OUT_EXE="$OUT_DIR/${INSTALL_DIR}Agent-${VERSION}.exe"
if [[ -f "$OUT_EXE" ]]; then
  echo ""
  echo "✓ $OUT_EXE"
  ls -lh "$OUT_EXE"
else
  echo "✗ NSIS no genero el .exe"
  exit 1
fi
