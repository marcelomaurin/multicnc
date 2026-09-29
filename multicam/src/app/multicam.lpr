program multicam;
{$mode objfpc}{$H+}
uses Interfaces,Forms,multicam_main;
var F:TMultiCAMForm;
begin Application.Initialize;F:=TMultiCAMForm.Create(Application);Application.Run;end.
