unit multicam_machine_model;
{$mode objfpc}{$H+}
interface
type TMachineModel=record MinX,MaxX,MinY,MaxY,MinZ,MaxZ:Double;RapidMMMin:Double;end;
function DefaultMachineModel:TMachineModel;
implementation
function DefaultMachineModel:TMachineModel;begin FillChar(Result,SizeOf(Result),0);end;
end.
