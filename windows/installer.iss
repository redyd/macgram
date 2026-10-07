; Installeur Windows (Inno Setup), après `flutter build windows --release` :
;   ISCC /DAppVer=1.0.0 windows\installer.iss
; Installation par utilisateur, sans droits administrateur.
; Mise à jour : relancer l'installeur d'une version plus récente. L'AppId ne doit jamais changer,
; c'est lui qui fait reconnaître l'installation existante (même dossier, app fermée puis remplacée).
; Le define s'appelle AppVer car `Ver` est une variable réservée du préprocesseur.
; ponytail: le runtime Visual C++ n'est pas embarqué (présent sur presque tous les PC) ;
; ajouter vc_redist à [Run] si quelqu'un signale un msvcp140.dll manquant.

[Setup]
AppId={{A0814AE8-F49E-4644-9B03-70944712B6A8}
AppName=macgram
AppVersion={#AppVer}
VersionInfoVersion={#AppVer}
AppPublisherURL=https://github.com/redyd/macgram
DefaultDirName={autopf}\macgram
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
LicenseFile=..\LICENSE
SetupIconFile=runner\resources\app_icon.ico
UninstallDisplayIcon={app}\macgram.exe
OutputDir=..
OutputBaseFilename=macgram-windows-x64-setup
WizardStyle=modern

[Languages]
Name: "fr"; MessagesFile: "compiler:Languages\French.isl"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs

[Icons]
Name: "{autoprograms}\macgram"; Filename: "{app}\macgram.exe"

[Run]
Filename: "{app}\macgram.exe"; Description: "{cm:LaunchProgram,macgram}"; Flags: nowait postinstall skipifsilent
