program multislicer;
{$mode objfpc}{$H+}
uses Interfaces,Forms,multislicer_main;
var F:TMultiSlicerForm;
begin Application.Initialize;F:=TMultiSlicerForm.Create(Application);Application.Run;end.
