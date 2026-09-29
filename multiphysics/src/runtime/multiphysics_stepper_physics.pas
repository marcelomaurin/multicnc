unit multiphysics_stepper_physics;
{$mode objfpc}{$H+}
interface
uses Math;
type TStepperPhysical=record HoldingTorque,RunningTorque,LoadTorque,StepsPerMM:Double;CommandedSteps,ActualSteps,LostSteps:Int64;end;
function ExecuteSteps(var M:TStepperPhysical;Demand:Integer):Integer;
implementation
function ExecuteSteps(var M:TStepperPhysical;Demand:Integer):Integer;var Capacity:Double;Lost:Integer;begin Inc(M.CommandedSteps,Demand);Capacity:=M.RunningTorque;if Capacity<=0 then Capacity:=M.HoldingTorque;if Abs(M.LoadTorque)>Capacity then begin Lost:=Abs(Demand);Inc(M.LostSteps,Lost);Exit(0);end;Result:=Demand;Inc(M.ActualSteps,Result);end;
end.
