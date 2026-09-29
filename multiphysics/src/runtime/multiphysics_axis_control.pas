unit multiphysics_axis_control;
{$mode objfpc}{$H+}
interface
uses Math;
type
 TAxisCommand=record TargetMM,MaxSpeedMMs,AccelerationMMs2:Double;Enabled:Boolean;end;
 TAxisState=record PositionMM,VelocityMMs:Double;LimitMin,LimitMax,AtMin,AtMax:Boolean;LostSteps:Int64;end;
 TProtectionState=record MaxCurrent,MaxTemperature:Double;OverCurrent,OverTemperature,Tripped:Boolean;Reason:string;end;
procedure UpdateLimits(var A:TAxisState;MinMM,MaxMM:Double);
procedure CheckProtection(Current,Temperature:Double;var P:TProtectionState);
function StepDemand(const Cmd:TAxisCommand;const A:TAxisState;StepsPerMM,Dt:Double):Integer;
implementation
procedure UpdateLimits(var A:TAxisState;MinMM,MaxMM:Double);begin A.AtMin:=A.PositionMM<=MinMM;A.AtMax:=A.PositionMM>=MaxMM;if A.AtMin then begin A.PositionMM:=MinMM;if A.VelocityMMs<0 then A.VelocityMMs:=0;end;if A.AtMax then begin A.PositionMM:=MaxMM;if A.VelocityMMs>0 then A.VelocityMMs:=0;end;end;
procedure CheckProtection(Current,Temperature:Double;var P:TProtectionState);begin P.OverCurrent:=(P.MaxCurrent>0)and(Abs(Current)>P.MaxCurrent);P.OverTemperature:=(P.MaxTemperature>0)and(Temperature>P.MaxTemperature);P.Tripped:=P.OverCurrent or P.OverTemperature;if P.OverCurrent then P.Reason:='SOBRECORRENTE' else if P.OverTemperature then P.Reason:='SOBRETEMPERATURA' else P.Reason:='';end;
function StepDemand(const Cmd:TAxisCommand;const A:TAxisState;StepsPerMM,Dt:Double):Integer;var E,D:Double;begin Result:=0;if(not Cmd.Enabled)or(StepsPerMM<=0)or(Dt<=0)then Exit;E:=Cmd.TargetMM-A.PositionMM;if Abs(E)<(1/StepsPerMM)then Exit;D:=Min(Abs(E),Cmd.MaxSpeedMMs*Dt);Result:=Round(D*StepsPerMM);if Result<1 then Result:=1;if E<0 then Result:=-Result;end;
end.
