#ifndef MyAppName
  #define MyAppName "MultiSuite"
#endif
#ifndef MyAppVersion
  #define MyAppVersion "0.01"
#endif
#ifndef SetupSeq
  #define SetupSeq "001"
#endif
#ifndef MyAppPublisher
  #define MyAppPublisher "Maurinsoft"
#endif
#ifndef MyAppExeName
  #define MyAppExeName "multisuite.exe"
#endif
#ifndef OutputExeName
  #define OutputExeName "setup_" + SetupSeq
#endif

[Setup]
AppId={{A9D52D62-2B20-4A38-A44B-6A975EF41F9D}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\MultiSuite
DefaultGroupName=MultiSuite
DisableProgramGroupPage=yes
OutputDir=..\..\dist
OutputBaseFilename={#OutputExeName}
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
WizardStyle=modern
UninstallDisplayIcon={app}\multisuite.exe
ChangesAssociations=yes

[Types]
Name: "full"; Description: "Instalacao Completa (Instalar todas as ferramentas)"
Name: "compact"; Description: "Instalacao Basica (Apenas MultiCNC)"
Name: "custom"; Description: "Instalacao Personalizada (Escolher as ferramentas desejadas)"; Flags: iscustom

[Components]
Name: "tools"; Description: "Ferramentas do MultiSuite"; Types: full compact custom; Flags: fixed
Name: "tools\multisuite"; Description: "MultiSuite - Painel Central Integrador / Dashboard"; Types: full custom
Name: "tools\multicnc"; Description: "MultiCNC - Controle de Maquinas CNC (GRBL, Marlin, Simulador)"; Types: full compact custom
Name: "tools\multicad"; Description: "MultiCAD - Modelagem e Desenho CAD 2D/3D"; Types: full custom
Name: "tools\multipcb"; Description: "MultiPCB - Design e Roteamento de Circuitos Impressos"; Types: full custom
Name: "tools\multiassembly"; Description: "MultiAssembly - Montagem Eletromecanica"; Types: full custom
Name: "tools\multiphysics"; Description: "MultiPhysics - Simulacao Fisica, Termica e Dinamica"; Types: full custom
Name: "tools\multicam"; Description: "MultiCAM - CAM e Simulacao CNC Router"; Types: full custom
Name: "tools\multislicer"; Description: "MultiSlicer - Fatiador para Impressao 3D"; Types: full custom
Name: "tools\makepcb"; Description: "MakePCB - Projeto de Placas do Zero (Gerber/Excellon)"; Types: full custom
Name: "tools\laserpcb"; Description: "LaserPCB - Preparacao e Gravacao de PCB a Laser"; Types: full custom
Name: "tools\laserart"; Description: "LaserArt - Vetorizacao e Gravacao de Imagens a Laser"; Types: full custom
Name: "tools\testcenter"; Description: "Central de Testes do MultiSuite"; Types: full custom
Name: "extra"; Description: "Recursos Complementares"; Types: full custom
Name: "extra\docs"; Description: "Documentacao e Manuais do Sistema"; Types: full custom

[Dirs]
Name: "{userdocs}\MultiSuite Projects"

[Files]
Source: "..\..\dist\app\multisuite.exe"; DestDir: "{app}"; Components: tools\multisuite; Flags: ignoreversion
Source: "..\..\dist\app\multicnc.exe"; DestDir: "{app}"; Components: tools\multicnc; Flags: ignoreversion
Source: "..\..\dist\app\multicad.exe"; DestDir: "{app}"; Components: tools\multicad; Flags: ignoreversion
Source: "..\..\dist\app\multipcb.exe"; DestDir: "{app}"; Components: tools\multipcb; Flags: ignoreversion
Source: "..\..\dist\app\multiassembly.exe"; DestDir: "{app}"; Components: tools\multiassembly; Flags: ignoreversion
Source: "..\..\dist\app\multiphysics.exe"; DestDir: "{app}"; Components: tools\multiphysics; Flags: ignoreversion
Source: "..\..\dist\app\multicam.exe"; DestDir: "{app}"; Components: tools\multicam; Flags: ignoreversion
Source: "..\..\dist\app\multislicer.exe"; DestDir: "{app}"; Components: tools\multislicer; Flags: ignoreversion
Source: "..\..\dist\app\makepcb.exe"; DestDir: "{app}"; Components: tools\makepcb; Flags: ignoreversion
Source: "..\..\dist\app\laserpcb.exe"; DestDir: "{app}"; Components: tools\laserpcb; Flags: ignoreversion
Source: "..\..\dist\app\laserart.exe"; DestDir: "{app}"; Components: tools\laserart; Flags: ignoreversion
Source: "..\..\dist\app\multisuite_test_center.exe"; DestDir: "{app}"; Components: tools\testcenter; Flags: ignoreversion
Source: "..\..\docs\*"; DestDir: "{app}\docs"; Components: extra\docs; Flags: ignoreversion recursesubdirs createallsubdirs

[Tasks]
Name: "desktopicon_suite"; Description: "Criar atalho do MultiSuite na area de trabalho"; GroupDescription: "Atalhos da Area de Trabalho:"; Components: tools\multisuite; Flags: unchecked
Name: "desktopicon_cnc"; Description: "Criar atalho do MultiCNC na area de trabalho"; GroupDescription: "Atalhos da Area de Trabalho:"; Components: tools\multicnc; Flags: unchecked

[Icons]
Name: "{autoprograms}\MultiSuite\MultiSuite"; Filename: "{app}\multisuite.exe"; Components: tools\multisuite
Name: "{autodesktop}\MultiSuite"; Filename: "{app}\multisuite.exe"; Tasks: desktopicon_suite; Components: tools\multisuite
Name: "{autoprograms}\MultiSuite\MultiCNC"; Filename: "{app}\multicnc.exe"; Components: tools\multicnc
Name: "{autodesktop}\MultiCNC"; Filename: "{app}\multicnc.exe"; Tasks: desktopicon_cnc; Components: tools\multicnc
Name: "{autoprograms}\MultiSuite\MultiCAD"; Filename: "{app}\multicad.exe"; Components: tools\multicad
Name: "{autoprograms}\MultiSuite\MultiPCB"; Filename: "{app}\multipcb.exe"; Components: tools\multipcb
Name: "{autoprograms}\MultiSuite\MultiAssembly"; Filename: "{app}\multiassembly.exe"; Components: tools\multiassembly
Name: "{autoprograms}\MultiSuite\MultiPhysics"; Filename: "{app}\multiphysics.exe"; Components: tools\multiphysics
Name: "{autoprograms}\MultiSuite\MultiCAM"; Filename: "{app}\multicam.exe"; Components: tools\multicam
Name: "{autoprograms}\MultiSuite\MultiSlicer"; Filename: "{app}\multislicer.exe"; Components: tools\multislicer
Name: "{autoprograms}\MultiSuite\MakePCB"; Filename: "{app}\makepcb.exe"; Components: tools\makepcb
Name: "{autoprograms}\MultiSuite\LaserPCB"; Filename: "{app}\laserpcb.exe"; Components: tools\laserpcb
Name: "{autoprograms}\MultiSuite\LaserArt"; Filename: "{app}\laserart.exe"; Components: tools\laserart
Name: "{autoprograms}\MultiSuite\Central de Testes"; Filename: "{app}\multisuite_test_center.exe"; Components: tools\testcenter

[Registry]
Root: HKA; Subkey: "Software\Classes\.msuite"; ValueType: string; ValueData: "MultiSuite.Project"; Flags: uninsdeletevalue; Components: tools\multisuite
Root: HKA; Subkey: "Software\Classes\MultiSuite.Project"; ValueType: string; ValueData: "Projeto MultiSuite"; Flags: uninsdeletekey; Components: tools\multisuite
Root: HKA; Subkey: "Software\Classes\MultiSuite.Project\DefaultIcon"; ValueType: string; ValueData: "{app}\multisuite.exe,0"; Components: tools\multisuite
Root: HKA; Subkey: "Software\Classes\MultiSuite.Project\shell\open\command"; ValueType: string; ValueData: """{app}\multisuite.exe"" ""%1"""; Components: tools\multisuite

[Run]
Filename: "{app}\multisuite.exe"; Description: "Abrir MultiSuite"; Flags: nowait postinstall skipifsilent; Components: tools\multisuite
Filename: "{app}\multicnc.exe"; Description: "Abrir MultiCNC"; Flags: nowait postinstall skipifsilent; Components: tools\multicnc and not tools\multisuite