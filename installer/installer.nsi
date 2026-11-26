Unicode true

!include "MUI2.nsh"
!include "FileFunc.nsh"
!include "LogicLib.nsh"
!include "x64.nsh"

!define APPNAME      "NOMIND Connect"
!define APPVERSION   "1.0"
!define COMPANY      "NOMIND"
!define EXENAME      "NOMIND Connect.exe"
!define UNKEY        "Software\Microsoft\Windows\CurrentVersion\Uninstall\NOMIND Connect"
!define RUNKEY       "Software\Microsoft\Windows\CurrentVersion\Run"
!define GUARDNAME    "NOMIND Connect Guard"

Name "${APPNAME}"
OutFile "..\NOMIND-Connect-Setup.exe"
InstallDir "$PROGRAMFILES64\${APPNAME}"
InstallDirRegKey HKLM "Software\NOMIND Connect" "InstallDir"
RequestExecutionLevel admin
SetCompressor /SOLID lzma
ShowInstDetails show
ShowUninstDetails show

VIProductVersion "1.0.0.0"
VIAddVersionKey "ProductName" "${APPNAME}"
VIAddVersionKey "FileDescription" "Установщик NOMIND Connect"
VIAddVersionKey "FileVersion" "1.0.0.0"
VIAddVersionKey "ProductVersion" "${APPVERSION}"
VIAddVersionKey "CompanyName" "${COMPANY}"
VIAddVersionKey "LegalCopyright" "${COMPANY}"

!define MUI_ICON   "..\nomind.ico"
!define MUI_UNICON "..\nomind.ico"
!define MUI_ABORTWARNING
!define MUI_FINISHPAGE_RUN "$INSTDIR\${EXENAME}"
!define MUI_FINISHPAGE_RUN_TEXT "Запустить NOMIND Connect"
!define MUI_DIRECTORYPAGE_TEXT_TOP "Программа будет установлена в выбранную папку. Можно указать любой диск — папка создастся сама."

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "Russian"

Function .onInit
  ${If} ${RunningX64}
    SetRegView 64
  ${EndIf}
FunctionEnd

Function un.onInit
  ${If} ${RunningX64}
    SetRegView 64
  ${EndIf}
FunctionEnd

Section "NOMIND Connect" SecMain
  SetShellVarContext current
  SetOutPath "$INSTDIR"

  ; Если поверх уже установленной версии — сначала аккуратно закрываем её.
  IfFileExists "$INSTDIR\NOMINDStop.ps1" 0 noOld
    nsExec::ExecToLog 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$INSTDIR\NOMINDStop.ps1"'
    Pop $0
  noOld:

  ; Всё содержимое папки (staging готовится сборщиком, без runtime).
  File /r "stage\*.*"

  CreateDirectory "$INSTDIR\runtime"

  CreateShortCut "$DESKTOP\${APPNAME}.lnk" "$INSTDIR\${EXENAME}" "" "$INSTDIR\${EXENAME}" 0
  CreateDirectory "$SMPROGRAMS\${APPNAME}"
  CreateShortCut "$SMPROGRAMS\${APPNAME}\${APPNAME}.lnk" "$INSTDIR\${EXENAME}" "" "$INSTDIR\${EXENAME}" 0
  CreateShortCut "$SMPROGRAMS\${APPNAME}\Удалить ${APPNAME}.lnk" "$INSTDIR\uninstall.exe"

  WriteRegStr HKLM "Software\NOMIND Connect" "InstallDir" "$INSTDIR"

  WriteRegStr HKLM "${UNKEY}" "DisplayName"     "${APPNAME}"
  WriteRegStr HKLM "${UNKEY}" "DisplayVersion"  "${APPVERSION}"
  WriteRegStr HKLM "${UNKEY}" "Publisher"       "${COMPANY}"
  WriteRegStr HKLM "${UNKEY}" "DisplayIcon"     "$INSTDIR\${EXENAME}"
  WriteRegStr HKLM "${UNKEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKLM "${UNKEY}" "UninstallString" '"$INSTDIR\uninstall.exe"'
  WriteRegStr HKLM "${UNKEY}" "QuietUninstallString" '"$INSTDIR\uninstall.exe" /S'
  WriteRegDWORD HKLM "${UNKEY}" "NoModify" 1
  WriteRegDWORD HKLM "${UNKEY}" "NoRepair" 1
  ${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
  WriteRegDWORD HKLM "${UNKEY}" "EstimatedSize" "$0"

  ; Автозапуск сторожа при входе в Windows (тот же ключ, что пишет сама программа).
  WriteRegStr HKCU "${RUNKEY}" "${GUARDNAME}" 'wscript.exe "$INSTDIR\NOMINDGuard.vbs"'

  WriteUninstaller "$INSTDIR\uninstall.exe"
SectionEnd

Section "Uninstall"
  SetShellVarContext current

  ; Снять прокси и погасить xray, иначе после удаления не будет интернета.
  IfFileExists "$INSTDIR\NOMINDStop.ps1" 0 noStop
    nsExec::ExecToLog 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$INSTDIR\NOMINDStop.ps1"'
    Pop $0
  noStop:

  Delete "$DESKTOP\${APPNAME}.lnk"
  Delete "$SMPROGRAMS\${APPNAME}\${APPNAME}.lnk"
  Delete "$SMPROGRAMS\${APPNAME}\Удалить ${APPNAME}.lnk"
  RMDir  "$SMPROGRAMS\${APPNAME}"

  DeleteRegValue HKCU "${RUNKEY}" "${GUARDNAME}"
  DeleteRegKey HKLM "${UNKEY}"
  DeleteRegKey HKLM "Software\NOMIND Connect"

  MessageBox MB_YESNO|MB_ICONQUESTION "Удалить также настройки, список серверов и логи (папка %APPDATA%\NOMIND Connect)?" /SD IDNO IDNO skipData
    RMDir /r "$APPDATA\NOMIND Connect"
  skipData:

  RMDir /r "$INSTDIR"
SectionEnd
