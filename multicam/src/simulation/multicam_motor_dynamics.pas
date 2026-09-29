unit multicam_motor_dynamics;
{$mode objfpc}{$H+}
interface
uses Math;
type TMotorConfig=record StepsPerMM,MaxSpeedMMMin,AccelerationMMSS,RatedTorqueNm,MaxCurrentA:Double;end;
 TMotorDynamicState=record CommandMM,ActualMM,SpeedMMMin,LoadTorqueNm,CurrentA,DriverTempC:Double;LostSteps:Int64;end;
 TMotorDynamics=class
 private FConfig:TMotorConfig;FState:TMotorDynamicState;
 public procedure Configure(const C:TMotorConfig);procedure Reset;procedure MoveTo(TargetMM,FeedMMMin,LoadTorqueNm,DtSeconds:Double);property State:TMotorDynamicState read FState;
 end;
implementation
procedure TMotorDynamics.Configure(const C:TMotorConfig);begin FConfig:=C;Reset;end;
procedure TMotorDynamics.Reset;begin FillChar(FState,SizeOf(FState),0);FState.DriverTempC:=25;end;
procedure TMotorDynamics.MoveTo(TargetMM,FeedMMMin,LoadTorqueNm,DtSeconds:Double);
var Delta,Requested,AvailableTorque,Ratio,ActualDelta,StepMM:Double;Lost:Int64;
begin if DtSeconds<=0 then Exit;FState.CommandMM:=TargetMM;Delta:=TargetMM-FState.ActualMM;Requested:=Min(Abs(FeedMMMin),FConfig.MaxSpeedMMMin);FState.SpeedMMMin:=Requested;FState.LoadTorqueNm:=Max(0,LoadTorqueNm);AvailableTorque:=FConfig.RatedTorqueNm*Max(0.15,1-0.65*(Requested/Max(1,FConfig.MaxSpeedMMMin)));if FState.LoadTorqueNm<=AvailableTorque then Ratio:=1 else Ratio:=Max(0,AvailableTorque/FState.LoadTorqueNm);ActualDelta:=Delta*Ratio;FState.ActualMM:=FState.ActualMM+ActualDelta;if FConfig.StepsPerMM>0 then begin StepMM:=1/FConfig.StepsPerMM;Lost:=Round(Abs(Delta-ActualDelta)/StepMM);FState.LostSteps:=FState.LostSteps+Lost;end;FState.CurrentA:=Min(FConfig.MaxCurrentA,FConfig.MaxCurrentA*(0.25+0.75*Min(1,FState.LoadTorqueNm/Max(0.001,FConfig.RatedTorqueNm))));FState.DriverTempC:=FState.DriverTempC+(FState.CurrentA/FConfig.MaxCurrentA)*0.08*DtSeconds-FState.DriverTempC*0.0005*DtSeconds;if FState.DriverTempC<25 then FState.DriverTempC:=25;end;
end.
