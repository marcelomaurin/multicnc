program multicad;
{$mode objfpc}{$H+}
uses Interfaces,Forms,multicad_main;
var F:TMainForm;
begin Application.Initialize;F:=TMainForm.Create(Application);F.Show;Application.Run;end.
