program simucnc;
{$mode objfpc}{$H+}
uses Interfaces, Forms, simuform;
var F: TMainForm;
begin
  Application.Initialize;
  Application.CreateForm(TMainForm, F);
  F.Caption := 'SimuCNC - Simulador de Impressora 3D Marlin';
  Application.Run;
end.
