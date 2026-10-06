program simucnc;
{$mode objfpc}{$H+}
uses Interfaces, Forms, simuform;

{$R *.res}

var F: TMainForm;
begin
  RequireDerivedFormResource := False;
  Application.Title := 'SimuCNC';
  Application.Initialize;
  Application.CreateForm(TMainForm, F);
  Application.Run;
end.
