program laserpcb_layout_app;
{$mode objfpc}{$H+}
uses Interfaces,Forms,laserpcb_layoutform;
var F:TLaserLayoutForm;
begin Application.Initialize;F:=TLaserLayoutForm.Create(Application);Application.Run;end.
