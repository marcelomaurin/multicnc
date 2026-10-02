#define MyAppName "MultiSuite"
#include "..\..\dist\version.iss"
#define MyAppPublisher "Maurinsoft"
#define MyAppExeName "multisuite.exe"

[Setup]
AppId={{A9D52D62-2B20-4A38-A44B-6A975EF41F9D}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
VersionInfoVersion={#MyBinaryVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\MultiSuite
DefaultGroupName=MultiSuite
DisableProgramGroupPage=yes
OutputDir=..\..\dist
OutputBaseFilename=MultiSuite-Setup-{#MyAppVersion}-win64
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
WizardStyle=modern
UninstallDisplayIcon={app}\multisuite.exe
ChangesAssociations=yes

[Dirs]
Name: "{userdocs}\MultiSuite Projects"

[Files]
Source: "..\..\dist\app\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\MultiSuite"; Filename: "{app}\multisuite.exe"
Name: "{autodesktop}\MultiSuite"; Filename: "{app}\multisuite.exe"; Tasks: desktopicon
Name: "{autoprograms}\MultiSuite\Central de Testes"; Filename: "{app}\multisuite_test_center.exe"
Name: "{autoprograms}\MultiSuite\MultiCNC"; Filename: "{app}\multicnc.exe"

[Tasks]
Name: "desktopicon"; Description: "Criar atalho do MultiSuite na area de trabalho"; GroupDescription: "Atalhos:"; Flags: unchecked

[Registry]
Root: HKA; Subkey: "Software\Classes\.msuite"; ValueType: string; ValueData: "MultiSuite.Project"; Flags: uninsdeletevalue
Root: HKA; Subkey: "Software\Classes\MultiSuite.Project"; ValueType: string; ValueData: "Projeto MultiSuite"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\MultiSuite.Project\DefaultIcon"; ValueType: string; ValueData: "{app}\multisuite.exe,0"
Root: HKA; Subkey: "Software\Classes\MultiSuite.Project\shell\open\command"; ValueType: string; ValueData: """{app}\multisuite.exe"" ""%1"""

[Run]
Filename: "{app}\multisuite.exe"; Description: "Abrir MultiSuite"; Flags: nowait postinstall skipifsilent
