#!/bin/bash
# Registra el binario como Native Messaging Host para Chrome en Mac.
# Necesario UNA vez tras instalar la app nativa.
#
# Para que la extension pueda hacer chrome.runtime.connectNative(HOST_NAME),
# Chrome busca un manifest en:
#   ~/Library/Application Support/Google/Chrome/NativeMessagingHosts/<host>.json
#
# El manifest dice "este host es <binario>" + "estas extensions pueden hablarme".

set -e

BRAND="${1:-mitienda}"  # mitienda o canchaya

# IDs FIJOS calculados desde la "key" RSA hardcodeada en cada manifest.
# Con la key fija el ID NO cambia entre dev/staging/prod ni entre maquinas
# — siempre es el mismo. El cliente NO tiene que pegar nada: el installer
# (.pkg / .msi) llama a este script con el brand correcto y listo.
case "$BRAND" in
  mitienda)
    HOST_NAME="ar.mitiendapos.print"
    BINARY_NAME="mitienda-print"
    EXT_ID="mjjbahhakjijjaebjifddiocmmoilflo"
    ;;
  canchaya)
    HOST_NAME="ar.canchaya.print"
    BINARY_NAME="canchaya-print"
    EXT_ID="nblbfplhkfcmmpilpamdcholgjkjpflg"
    ;;
  *)
    echo "Brand invalido: $BRAND. Usar 'mitienda' o 'canchaya'."
    exit 1
    ;;
esac

# Ruta del binario. En production deberia estar en /Applications/<Brand> Print.app/Contents/MacOS/<binary>.
# Para development apuntamos al binario en /tmp.
BINARY_PATH="${BINARY_PATH:-/tmp/${BINARY_NAME}-mac}"

if [ ! -x "$BINARY_PATH" ]; then
  echo "⚠  El binario no existe o no es ejecutable: $BINARY_PATH"
  echo "   Compilá primero o seteá BINARY_PATH=/ruta/al/binario"
  exit 1
fi

TARGET_DIR="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
mkdir -p "$TARGET_DIR"

cat > "$TARGET_DIR/${HOST_NAME}.json" <<EOF
{
  "name": "${HOST_NAME}",
  "description": "${BRAND} Print Native Messaging Host",
  "path": "${BINARY_PATH}",
  "type": "stdio",
  "allowed_origins": [
    "chrome-extension://${EXT_ID}/"
  ]
}
EOF

echo "✓ Native Messaging Host registrado"
echo "  Host: ${HOST_NAME}"
echo "  Binario: ${BINARY_PATH}"
echo "  Manifest: ${TARGET_DIR}/${HOST_NAME}.json"
echo "  Extension permitida: ${EXT_ID}"
echo ""
echo "Reiniciá Chrome para que tome el cambio (o cerrá el popup y abrilo de nuevo)."
