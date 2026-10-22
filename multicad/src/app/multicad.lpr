program multicad;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, Forms, SysUtils, multicad_main, multisuite_context, multisuite_taskpanel, multicad_log;

{$R *.res}

var
  F: TMainForm;
  C: TSuiteContext;
begin
  CadLogStart;
  try
  try
  RequireDerivedFormResource := False;
  Application.Scaled := True;
  Application.Initialize;
  C := ReadSuiteContext;
  Application.CreateForm(TMainForm,F);
  F.Hint := 'Projeto: ' + C.ProjectRoot;
  F.Show;
  Application.ProcessMessages;
  if (C.FileName <> '') and FileExists(C.FileName) and
    SameText(ExtractFileExt(C.FileName), '.mcad') then
    F.OpenFile(C.FileName);
  if (C.NewFileName <> '') and not FileExists(C.NewFileName) and
    SameText(ExtractFileExt(C.NewFileName), '.mcad') then
    F.SetNewTarget(C.NewFileName);
  ShowSuiteTaskPanel(F, C.TaskFile);
  if CadLogError<>'' then
    Application.MessageBox(PChar('Nao foi possivel gravar o log: '+CadLogError),'MultiCAD',0);
  Application.Run;
  except on E:Exception do
  begin CadLogException('inicializacao/execucao',E);Application.ShowException(E);ExitCode:=1;end;end;
  finally CadLogStop;end;
end.
