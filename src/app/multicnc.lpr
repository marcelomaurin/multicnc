program multicnc;
{$mode objfpc}{$H+}
uses Interfaces, Forms, SysUtils, Dialogs, mainform, multisuite_context;
var F: TMainForm; C: TSuiteContext;
begin
  Application.Initialize;
  C := ReadSuiteContext;
  Application.CreateForm(TMainForm, F);
  F.Caption := ContextCaption(F.Caption, C);
  F.Hint := 'Projeto: ' + C.ProjectRoot + ' | Arquivo: ' + C.FileName;
  F.ShowHint := True;
  if C.FileName <> '' then
    try F.OpenFile(C.FileName); except on E: Exception do ShowMessage(E.Message); end;
  Application.Run;
end.
