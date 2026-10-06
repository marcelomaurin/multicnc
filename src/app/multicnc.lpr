program multicnc;
{$mode objfpc}{$H+}
uses Interfaces, Forms, mainform, multisuite_context;

{$R *.res}

var F: TMainForm; C: TSuiteContext;
begin
  Application.Initialize;
  C := ReadSuiteContext;
  Application.CreateForm(TMainForm, F);
  F.Caption := ContextCaption(F.Caption, C);
  F.Hint := 'Projeto: ' + C.ProjectRoot + ' | Arquivo: ' + C.FileName;
  F.ShowHint := True;
  Application.Run;
end.
