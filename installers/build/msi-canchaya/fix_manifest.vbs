' fix_manifest.vbs <brand>
' Reescribe el manifest JSON del NM host con el path absoluto del binario.
Option Explicit

Dim brand
brand = ""
If WScript.Arguments.Count > 0 Then
  brand = LCase(WScript.Arguments(0))
End If

Dim installDir, binaryName, hostName, extId, display
If brand = "canchaya" Then
  installDir = "CanchaYaPrint"
  binaryName = "canchaya-print.exe"
  hostName = "ar.canchaya.print"
  extId = "nblbfplhkfcmmpilpamdcholgjkjpflg"
  display = "CanchaYa Print"
Else
  installDir = "MiTiendaPrint"
  binaryName = "mitienda-print.exe"
  hostName = "ar.mitiendapos.print"
  extId = "mjjbahhakjijjaebjifddiocmmoilflo"
  display = "Mi Tienda Print"
End If

Dim shell, localAppData, dir, binPath, jsonPath
Set shell = CreateObject("WScript.Shell")
localAppData = shell.ExpandEnvironmentStrings("%LOCALAPPDATA%")
dir = localAppData & "\" & installDir
binPath = dir & "\" & binaryName
jsonPath = dir & "\" & hostName & ".json"

' Asegurar que el directorio existe (deberia, lo crea el .msi)
Dim fso
Set fso = CreateObject("Scripting.FileSystemObject")
If Not fso.FolderExists(dir) Then
  fso.CreateFolder dir
End If

' Escapar las barras para JSON
Dim binPathJson
binPathJson = Replace(binPath, "\", "\\")

Dim json
json = "{" & vbCrLf
json = json & "  ""name"": """ & hostName & """," & vbCrLf
json = json & "  ""description"": """ & display & " Native Messaging Host""," & vbCrLf
json = json & "  ""path"": """ & binPathJson & """," & vbCrLf
json = json & "  ""type"": ""stdio""," & vbCrLf
json = json & "  ""allowed_origins"": [""chrome-extension://" & extId & "/""]" & vbCrLf
json = json & "}"

Dim file
Set file = fso.OpenTextFile(jsonPath, 2, True) ' 2 = ForWriting
file.Write json
file.Close

WScript.Echo "Manifest reescrito: " & jsonPath
