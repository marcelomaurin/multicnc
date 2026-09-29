program multislicer_position;
{$mode objfpc}{$H+}
uses Interfaces,Forms,multislicer_positionform;
var F:TPosition3DForm;
begin Application.Initialize;F:=TPosition3DForm.Create(Application);Application.Run;end.
