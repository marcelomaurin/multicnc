program makerouter;

{ MakeRouter - projeto e usinagem de madeira na CNC Router (desenho, percursos,
  simulacao e G-code com zero virtual para o MultiCNC).

  Uso: makerouter [--file <projeto.mrouter>] | makerouter <projeto.mrouter> }

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, SysUtils, Forms, makerouter_main, multisuite_context;

{$R *.res}

var
  F: TMakeRouterForm;
  C: TSuiteContext;
  FN: string;
begin
  RequireDerivedFormResource := False;
  Application.Title := 'MakeRouter';
  Application.Initialize;
  C := ReadSuiteContext;
  FN := C.FileName;
  if (FN = '') and (ParamCount >= 1) and (Copy(ParamStr(1), 1, 2) <> '--') then
    FN := ExpandFileName(ParamStr(1));
  Application.CreateForm(TMakeRouterForm, F);
  F.Caption := ContextCaption(F.Caption, C);
  if (FN <> '') and FileExists(FN) then F.OpenFile(FN);
  F.Show;
  Application.Run;
end.
