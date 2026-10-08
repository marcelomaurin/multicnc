program multicam_simulator;
{$mode objfpc}{$H+}
uses Interfaces,Forms,multicam_simulator_form;
var F:TSimulatorForm;
begin RequireDerivedFormResource:=False;Application.Initialize;Application.CreateForm(TSimulatorForm, F);F.Show;Application.Run;end.
