; picture-show3 — Inno Setup installer script
; Requires Inno Setup 6.x  (https://jrsoftware.org/isdl.php)
;
; Preferred build method — version is read automatically from main.py:
;   python install/windows/build.py
;
; Manual build steps (all from project root):
;   1. python install/windows/make_icon.py
;   2. python install/windows/compile_resources.py
;   3. pyinstaller install/windows/picture-show3.spec ^
;          --distpath install/windows/dist --workpath install/windows/build
;   4. iscc install\windows\picture-show3.iss
;      (version falls back to the #define below when not passed via /D)

#define MyAppName      "picture-show3"
; MyAppVersion can be overridden from the command line: iscc /DMyAppVersion="1.0" ...
#ifndef MyAppVersion
  #define MyAppVersion "--"
#endif
#define MyAppPublisher "Sebastian Schäfer"
#define MyAppExeName   "picture-show3.exe"
; Unique ID — do NOT change after first release (Windows uses it to identify the app)
#define MyAppId        "{{8A3F2C1D-4E6B-4F9A-B2D7-1C5E8A9F3B0E}"

[Setup]
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppVerName={#MyAppName} {#MyAppVersion}

; Default install location: C:\Program Files\picture-show3
DefaultDirName={autopf}\{#MyAppName}

; Start menu folder
DefaultGroupName={#MyAppName}
AllowNoIcons=yes

; License shown on the second page of the wizard
LicenseFile=..\..\LICENSE

; Output goes into install\windows\dist\installer\
OutputDir=dist\installer
; OutputBaseFilename can be overridden: iscc /DOutputBaseFilename="picture-show3-setup-1.0" ...
#ifndef OutputBaseFilename
  #define OutputBaseFilename "picture-show3-setup-" + StringChange(MyAppVersion, " ", "-")
#endif
OutputBaseFilename={#OutputBaseFilename}

; Icon
SetupIconFile=..\..\img\icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}

; Compression
Compression=lzma2
SolidCompression=yes

; Require 64-bit Windows
ArchitecturesInstallIn64BitMode=x64compatible
ArchitecturesAllowed=x64compatible

; Modern wizard style
WizardStyle=modern

; Minimum Windows version: Windows 10
MinVersion=10.0

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
; Desktop shortcut — unchecked by default, user opts in
Name: "desktopicon"; \
  Description: "{cm:CreateDesktopIcon}"; \
  GroupDescription: "{cm:AdditionalIcons}"; \
  Flags: unchecked

[Files]
; Main executable
Source: "dist\picture-show3\{#MyAppExeName}"; \
  DestDir: "{app}"; \
  Flags: ignoreversion

; Runtime bundle (_internal folder created by PyInstaller)
Source: "dist\picture-show3\_internal\*"; \
  DestDir: "{app}\_internal"; \
  Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
; Start menu
Name: "{group}\{#MyAppName}";                    Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"

; Desktop shortcut (only when the task above is selected)
Name: "{autodesktop}\{#MyAppName}"; \
  Filename: "{app}\{#MyAppExeName}"; \
  Tasks: desktopicon

[Run]
; Offer to launch the app after installation
Filename: "{app}\{#MyAppExeName}"; \
  Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; \
  Flags: nowait postinstall skipifsilent

[Code]
// ---------------------------------------------------------------------------
// Uninstall: ask whether to keep or delete the settings folder
// ---------------------------------------------------------------------------
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  SettingsDir: String;
  Answer: Integer;
begin
  if CurUninstallStep = usPostUninstall then
  begin
    // Settings are stored in %APPDATA%\picture-show3\
    SettingsDir := ExpandConstant('{userappdata}\picture-show3');
    if DirExists(SettingsDir) then
    begin
      Answer := MsgBox(
        'Do you want to delete your settings?' + #13#10 + #13#10 +
        SettingsDir + #13#10 + #13#10 +
        'Click Yes to delete settings and folder.' + #13#10 +
        'Click No to keep them (you can delete them manually later).',
        mbConfirmation, MB_YESNO or MB_DEFBUTTON2);
      if Answer = IDYES then
        DelTree(SettingsDir, True, True, True);
    end;
  end;
end;
