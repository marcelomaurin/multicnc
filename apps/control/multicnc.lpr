program MultiCNC;
{$mode objfpc}{$H+}
uses Interfaces, Forms, uMain;
begin
  RequireDerivedFormResource := False;
  Application.Scaled := True;
  Application.Initialize;
  Application.Title := 'MultiCNC Control';
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
