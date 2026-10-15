program test_simucnc_server;
{ Actual SimuCNC form/server for automated TCP tests. No administrator manifest:
  loopback TCP needs no driver installation. The production app is unchanged. }
{$mode objfpc}{$H+}
uses Interfaces, Forms, simuform;
var F:TMainForm;
begin
  RequireDerivedFormResource:=False;
  Application.Initialize;
  Application.CreateForm(TMainForm,F);
  Application.Run;
end.
