program multislicer_position;
{$mode objfpc}{$H+}
uses Interfaces,Forms,multislicer_positionform;
var F:TPosition3DForm;
begin Application.Initialize;Application.CreateForm(TPosition3DForm, F);Application.Run;end.
