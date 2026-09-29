program test_cnc_cycle;
{$mode objfpc}{$H+}
uses Math,multiphysics_axis_control,multiphysics_stepper_physics;
var C:TAxisCommand;A:TAxisState;P:TProtectionState;M:TStepperPhysical;D,E,I:Integer;
begin C.TargetMM:=100;C.MaxSpeedMMs:=50;C.Enabled:=True;M.StepsPerMM:=80;M.RunningTorque:=1.2;M.LoadTorque:=0.5;P.MaxCurrent:=3;P.MaxTemperature:=80;for I:=1 to 3000 do begin D:=StepDemand(C,A,M.StepsPerMM,0.001);E:=ExecuteSteps(M,D);A.PositionMM:=A.PositionMM+E/M.StepsPerMM;UpdateLimits(A,0,120);if Abs(A.PositionMM-C.TargetMM)<1/M.StepsPerMM then Break;end;if Abs(A.PositionMM-100)>0.02 then Halt(1);if M.LostSteps<>0 then Halt(2);M.LoadTorque:=2;D:=ExecuteSteps(M,100);if(D<>0)or(M.LostSteps=0)then Halt(3);A.PositionMM:=130;UpdateLimits(A,0,120);if not A.AtMax then Halt(4);CheckProtection(4,25,P);if(not P.Tripped)or(not P.OverCurrent)then Halt(5);CheckProtection(1,90,P);if(not P.Tripped)or(not P.OverTemperature)then Halt(6);Writeln('PASS CNC X=100mm, lost-step, limit and protection');end.
