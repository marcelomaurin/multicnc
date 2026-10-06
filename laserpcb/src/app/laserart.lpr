program laserart;

{ LaserArt - editor de arte para laser da suite MultiSuite.
  Parametros: --project <pasta> --file <arquivo> (contrato MultiSuite) ou
  apenas o caminho de um .lart/.svg/.png/.jpg/.bmp. }

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, Forms, SysUtils, laserart_main, multisuite_context;

{$R *.res}

var
  F: TLaserArtForm;
  C: TSuiteContext;
begin
  RequireDerivedFormResource := False;
  Application.Title := 'LaserArt';
  Application.Initialize;
  C := ReadSuiteContext;
  Application.CreateForm(TLaserArtForm, F);
  F.ProjectRoot := C.ProjectRoot;
  if (C.FileName <> '') and FileExists(C.FileName) then
    F.OpenFile(C.FileName)
  else if (ParamCount > 0) and (Copy(ParamStr(1), 1, 2) <> '--') and FileExists(ParamStr(1)) then
    F.OpenFile(ParamStr(1));
  Application.Run;
end.
