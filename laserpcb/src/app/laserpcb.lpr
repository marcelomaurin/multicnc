program laserpcb;
{$mode objfpc}{$H+}
uses Interfaces,Forms,laserpcb_main;
var F:TLaserPCBForm;
begin Application.Initialize;F:=TLaserPCBForm.Create(Application);Application.Run;end.
