// Branding centralizado. El build script reemplaza esto por la variante del
// brand que se está empaquetando (Mi Tienda o CanchaYa).
//
// Durante development (carga descomprimida) leemos directamente la const
// BRAND de aca. Para production, el build script genera dos paquetes:
//   dist/mitienda/  → BRAND = "mitienda"
//   dist/canchaya/  → BRAND = "canchaya"
//
// El nombre del source de los mensajes window.postMessage es
// `${BRAND}-print` para que el POS pueda discriminar (si un cliente
// instala ambas extensiones, cada POS solo responde a la suya).

// Default para development: Mi Tienda. Cambialo a "canchaya" si vas a
// debuggear contra el POS de CanchaYa local.
export const BRAND = "mitienda"

export const BRANDS = {
  mitienda: {
    display_name: "Mi Tienda Print",
    source_id: "mitienda-print",
    default_server: "https://mitiendapos.com.ar",
    // Nombre del Native Messaging Host. El binario nativo registra un
    // manifest en este nombre — Chrome lo busca cuando la extension hace
    // connectNative(NATIVE_HOST). Convencion: dominio invertido + ".print".
    native_host: "ar.mitiendapos.print",
    color: "#f97316" // orange-500
  },
  canchaya: {
    display_name: "CanchaYa Print",
    source_id: "canchaya-print",
    default_server: "https://canchaya.ar",
    native_host: "ar.canchaya.print",
    color: "#BEFF00" // lime
  }
}

export const CURRENT_BRAND = BRANDS[BRAND]
