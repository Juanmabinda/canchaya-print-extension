#!/bin/bash
# Empaqueta un .pkg para Mac que:
#   1. Copia el binario nativo a /Library/Application Support/<Brand>Print/
#      (rutas system-wide para que aplique a todos los usuarios).
#   2. En postinstall registra el Native Messaging Host para Chrome y Edge
#      en el HOME del usuario que instaló (cada usuario de la Mac usa el
#      mismo binario).
#
# Uso:
#   ./build_pkg_mac.sh mitienda /path/al/binario/mitienda-print
#   ./build_pkg_mac.sh canchaya /path/al/binario/canchaya-print
#
# Output: dist/<Brand>PrintAgent-X.Y.Z.pkg

set -euo pipefail

BRAND="${1:-}"
BINARY_SRC="${2:-}"
VERSION="${3:-0.10.4}"

if [[ -z "$BRAND" || -z "$BINARY_SRC" ]]; then
  echo "Uso: $0 <mitienda|canchaya> <ruta_al_binario> [version]"
  exit 1
fi

case "$BRAND" in
  mitienda)
    DISPLAY="Mi Tienda Print"
    BUNDLE_ID="ar.mitiendapos.print.agent"
    INSTALL_DIR_REL="MiTiendaPrint"
    BINARY_NAME="mitienda-print"
    ;;
  canchaya)
    DISPLAY="CanchaYa Print"
    BUNDLE_ID="ar.canchaya.print.agent"
    INSTALL_DIR_REL="CanchaYaPrint"
    BINARY_NAME="canchaya-print"
    ;;
  *)
    echo "Brand invalido: $BRAND"
    exit 1
    ;;
esac

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT/build/$BRAND"
PAYLOAD_DIR="$BUILD_DIR/payload"
SCRIPTS_DIR="$BUILD_DIR/scripts"
OUT_DIR="$ROOT/dist"

rm -rf "$BUILD_DIR"
mkdir -p "$PAYLOAD_DIR/Library/Application Support/$INSTALL_DIR_REL"
mkdir -p "$SCRIPTS_DIR"
mkdir -p "$OUT_DIR"

# 1. Payload: el binario va a /Library/Application Support/<Brand>Print/
cp "$BINARY_SRC" "$PAYLOAD_DIR/Library/Application Support/$INSTALL_DIR_REL/$BINARY_NAME"
chmod 755 "$PAYLOAD_DIR/Library/Application Support/$INSTALL_DIR_REL/$BINARY_NAME"

# 2. Postinstall: registra el NM host. Importante: $HOME en postinstall
# refiere al usuario que esta instalando (no a root) → registramos en su
# carpeta personal de Chrome. Si la Mac tiene varios usuarios, cada uno
# tiene que ejecutar el postinstall (corre auto con el pkg).
cat > "$SCRIPTS_DIR/postinstall" <<POSTINSTALL
#!/bin/bash
set -e

# IDs FIJOS calculados de la "key" RSA del manifest de la extension Chrome.
# Como la key esta hardcodeada, el ID NO cambia entre dev/prod ni entre
# instalaciones — siempre es el mismo. Por eso no hay que pedirle nada al
# cliente.
EXT_ID_MITIENDA="mjjbahhakjijjaebjifddiocmmoilflo"
EXT_ID_CANCHAYA="nblbfplhkfcmmpilpamdcholgjkjpflg"

BRAND="$BRAND"
HOST_NAME="$BUNDLE_ID"
case "\$BRAND" in
  mitienda) HOST_NAME="ar.mitiendapos.print"; EXT_ID="\$EXT_ID_MITIENDA" ;;
  canchaya) HOST_NAME="ar.canchaya.print";    EXT_ID="\$EXT_ID_CANCHAYA" ;;
esac

BINARY_PATH="/Library/Application Support/$INSTALL_DIR_REL/$BINARY_NAME"

# Detectar el HOME del usuario real (no root). Si el pkg corre con sudo,
# \$HOME puede ser /var/root — usamos USER_HOME del entorno o getent.
TARGET_USER="\${USER:-\$(stat -f '%Su' /dev/console)}"
USER_HOME=\$(eval echo "~\$TARGET_USER")

# Chrome.
CHROME_DIR="\$USER_HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
mkdir -p "\$CHROME_DIR"
cat > "\$CHROME_DIR/\$HOST_NAME.json" <<EOF
{
  "name": "\$HOST_NAME",
  "description": "$DISPLAY Native Messaging Host",
  "path": "\$BINARY_PATH",
  "type": "stdio",
  "allowed_origins": ["chrome-extension://\$EXT_ID/"]
}
EOF
chown "\$TARGET_USER" "\$CHROME_DIR/\$HOST_NAME.json"

# Edge (Chromium, mismo API).
EDGE_DIR="\$USER_HOME/Library/Application Support/Microsoft Edge/NativeMessagingHosts"
mkdir -p "\$EDGE_DIR"
cp "\$CHROME_DIR/\$HOST_NAME.json" "\$EDGE_DIR/\$HOST_NAME.json"
chown "\$TARGET_USER" "\$EDGE_DIR/\$HOST_NAME.json"

# Brave (Chromium).
BRAVE_DIR="\$USER_HOME/Library/Application Support/BraveSoftware/Brave-Browser/NativeMessagingHosts"
mkdir -p "\$BRAVE_DIR"
cp "\$CHROME_DIR/\$HOST_NAME.json" "\$BRAVE_DIR/\$HOST_NAME.json"
chown "\$TARGET_USER" "\$BRAVE_DIR/\$HOST_NAME.json"

echo "$DISPLAY Native Messaging Host registrado para \$TARGET_USER"
exit 0
POSTINSTALL
chmod +x "$SCRIPTS_DIR/postinstall"

# 3. pkgbuild
PKG_OUT="$OUT_DIR/${INSTALL_DIR_REL}Agent-${VERSION}.pkg"
pkgbuild \
  --root "$PAYLOAD_DIR" \
  --scripts "$SCRIPTS_DIR" \
  --identifier "$BUNDLE_ID" \
  --version "$VERSION" \
  --install-location "/" \
  "$PKG_OUT"

echo ""
echo "✓ $PKG_OUT"
echo "  Doble click para instalar. El postinstall registra el NM host"
echo "  para Chrome, Edge y Brave del usuario actual."
