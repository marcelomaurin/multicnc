program multipcb;
{$mode objfpc}{$H+}
uses Interfaces,Forms,multipcb_main;
var F:TMultiPCBForm;
begin Application.Initialize;F:=TMultiPCBForm.Create(Application);Application.Run;end.
