program multipcb_cnc_position_app;
{$mode objfpc}{$H+}
uses Interfaces,Forms,multipcb_cnc_positionform;
var F:TPCBCNCPositionForm;
begin Application.Initialize;F:=TPCBCNCPositionForm.Create(Application);Application.Run;end.
