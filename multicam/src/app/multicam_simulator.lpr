program multicam_simulator;
{$mode objfpc}{$H+}
uses Interfaces,Forms,multicam_simulator_form;
var F:TSimulatorForm;
begin RequireDerivedFormResource:=False;Application.Initialize;F:=TSimulatorForm.Create(nil);try Application.Run;finally F.Free;end;end.
