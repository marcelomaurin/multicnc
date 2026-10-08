program multipcb_cnc_position_app;
{$mode objfpc}{$H+}
uses Interfaces,Forms,multipcb_cnc_positionform;
var F:TPCBCNCPositionForm;
begin Application.Initialize;Application.CreateForm(TPCBCNCPositionForm, F);Application.Run;end.
