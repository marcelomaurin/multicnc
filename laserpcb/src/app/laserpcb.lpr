program laserpcb;
{$mode objfpc}{$H+}
uses Interfaces, Forms, laserpcb_main, multisuite_context;

{$R *.res}

var
  F: TLaserPCBForm;
  C: TSuiteContext;
begin
  RequireDerivedFormResource := False;
  Application.Title := 'LaserPCB';
  Application.Initialize;
  C := ReadSuiteContext;
  Application.CreateForm(TLaserPCBForm, F);
  F.Caption := ContextCaption(F.Caption, C);
  F.Hint := 'Projeto: ' + C.ProjectRoot + ' | Arquivo: ' + C.FileName;
  F.ShowHint := True;
  if C.FileName <> '' then F.OpenFile(C.FileName);
  F.Show;
  Application.Run;
end.
