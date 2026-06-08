; NSIS installer para Mi Tienda Print Native Messaging Agent.
; Instala el binario en %LOCALAPPDATA%\MiTiendaPrint\ y registra el NM host.

!define APP_NAME "Mi Tienda Print Agent"
!define APP_VERSION "0.10.4"
!define INSTALL_FOLDER "MiTiendaPrint"
!define BINARY_NAME "mitienda-print.exe"
!define HOST_NAME "ar.mitiendapos.print"
!define EXT_ID "mjjbahhakjijjaebjifddiocmmoilflo"

Name "${APP_NAME}"
OutFile "/Users/andress/juanma/canchaya-print-extension/installers/dist\MiTiendaPrintAgent-0.10.4.exe"
RequestExecutionLevel user
SetCompressor /SOLID lzma
InstallDir "$LOCALAPPDATA\${INSTALL_FOLDER}"

; UI minimalista (sin license, sin pages confusas para el cajero).
!include "MUI2.nsh"
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_LANGUAGE "Spanish"

Section
  SetOutPath "$INSTDIR"
  File "mitienda-print.exe"

  ; Manifest del NM host — JSON que apunta al binario + permite la extension.
  ; NSIS: comillas simples como delimitador → comillas dobles dentro sin escape.
  ; $INSTDIR se expande al destino real (%LOCALAPPDATA%\<INSTALL_DIR>).
  ; Las \\ se vuelven \ literal en el JSON (path Windows con \ entre folders).
  FileOpen $0 '$INSTDIR\${HOST_NAME}.json' w
  FileWrite $0 '{$\n'
  FileWrite $0 '  "name": "${HOST_NAME}",$\n'
  FileWrite $0 '  "description": "${APP_NAME} Native Messaging Host",$\n'
  FileWrite $0 '  "path": "$INSTDIR\\${BINARY_NAME}",$\n'
  FileWrite $0 '  "type": "stdio",$\n'
  FileWrite $0 '  "allowed_origins": ["chrome-extension://${EXT_ID}/"]$\n'
  FileWrite $0 '}$\n'
  FileClose $0

  ; Registry HKCU — Chrome busca el manifest aca.
  WriteRegStr HKCU "Software\Google\Chrome\NativeMessagingHosts\${HOST_NAME}" "" "$INSTDIR\${HOST_NAME}.json"
  ; Edge (Chromium).
  WriteRegStr HKCU "Software\Microsoft\Edge\NativeMessagingHosts\${HOST_NAME}" "" "$INSTDIR\${HOST_NAME}.json"
  ; Brave (Chromium).
  WriteRegStr HKCU "Software\BraveSoftware\Brave-Browser\NativeMessagingHosts\${HOST_NAME}" "" "$INSTDIR\${HOST_NAME}.json"

  ; Uninstaller para Programs and Features.
  WriteUninstaller '$INSTDIR\Uninstall.exe'
  WriteRegStr HKCU 'Software\Microsoft\Windows\CurrentVersion\Uninstall\${HOST_NAME}' 'DisplayName' '${APP_NAME}'
  WriteRegStr HKCU 'Software\Microsoft\Windows\CurrentVersion\Uninstall\${HOST_NAME}' 'DisplayVersion' '${APP_VERSION}'
  WriteRegStr HKCU 'Software\Microsoft\Windows\CurrentVersion\Uninstall\${HOST_NAME}' 'UninstallString' '"$INSTDIR\Uninstall.exe"'
  WriteRegStr HKCU 'Software\Microsoft\Windows\CurrentVersion\Uninstall\${HOST_NAME}' 'InstallLocation' '$INSTDIR'
SectionEnd

Section "Uninstall"
  Delete "$INSTDIR\${BINARY_NAME}"
  Delete "$INSTDIR\${HOST_NAME}.json"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"

  DeleteRegKey HKCU "Software\Google\Chrome\NativeMessagingHosts\${HOST_NAME}"
  DeleteRegKey HKCU "Software\Microsoft\Edge\NativeMessagingHosts\${HOST_NAME}"
  DeleteRegKey HKCU "Software\BraveSoftware\Brave-Browser\NativeMessagingHosts\${HOST_NAME}"
  DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\${HOST_NAME}"
SectionEnd
