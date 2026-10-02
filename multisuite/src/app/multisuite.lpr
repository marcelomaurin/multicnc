program multisuite;
{$mode objfpc}{$H+}
uses Interfaces, Forms, SysUtils, Dialogs, multisuite_main, multisuite_context;
var F: TMultiSuiteForm; C: TSuiteContext; FN: string;
begin
  RequireDerivedFormResource := False; Application.Initialize;
  F := TMultiSuiteForm.Create(Application); C := ReadSuiteContext; FN := C.FileName;
  // Associacoes Windows/Linux entregam o arquivo como primeiro argumento.
  if (FN = '') and (ParamCount > 0) and (Copy(ParamStr(1), 1, 2) <> '--') then FN := ParamStr(1);
  if FN <> '' then
    try F.OpenProject(FN); except on E: Exception do ShowMessage(E.Message); end;
  F.Show; Application.Run;
end.
