program routerpcb;

{ RouterPCB - fresagem de placas de circuito impresso na CNC Router: isolacao,
  furacao, recorte e nivelamento a partir da pasta Gerber + Excellon do
  MakePCB. Gera G-code para o MultiCNC (modo CNC Router).

  Uso: routerpcb [--file <pasta_ou_arquivo>] | routerpcb <pasta_ou_arquivo> }

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, SysUtils, Forms, routerpcb_main, multisuite_context;

{$R *.res}

var
  F: TRouterPCBForm;
  C: TSuiteContext;
  FN: string;
begin
  RequireDerivedFormResource := False;
  Application.Title := 'RouterPCB';
  Application.Initialize;
  C := ReadSuiteContext;
  FN := C.FileName;
  if (FN = '') and (ParamCount >= 1) and (Copy(ParamStr(1), 1, 2) <> '--') then
    FN := ExpandFileName(ParamStr(1));
  Application.CreateForm(TRouterPCBForm, F);
  F.Caption := ContextCaption(F.Caption, C);
  if (FN <> '') and (FileExists(FN) or DirectoryExists(FN)) then F.OpenFile(FN);
  F.Show;
  Application.Run;
end.
