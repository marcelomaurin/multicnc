unit multicam_spindle_dynamics;
{$mode objfpc}{$H+}
interface
uses Math;
type TSpindleConfig=record MaxRPM,RampRPMPerSec,RatedPowerW:Double;end;
 TSpindleDynamicState=record CommandRPM,ActualRPM,LoadW:Double;Enabled,Fault:Boolean;end;
 TSpindleDynamics=class
 private FConfig:TSpindleConfig;FState:TSpindleDynamicState;
 public procedure Configure(const C:TSpindleConfig);procedure Reset;procedure Update(Enabled:Boolean;CommandRPM,LoadW,Dt:Double);property State:TSpindleDynamicState read FState;
 end;
implementation
procedure TSpindleDynamics.Configure(const C:TSpindleConfig);begin FConfig:=C;Reset;end;
procedure TSpindleDynamics.Reset;begin FillChar(FState,SizeOf(FState),0);end;
procedure TSpindleDynamics.Update(Enabled:Boolean;CommandRPM,LoadW,Dt:Double);var Target,Step:Double;
begin FState.Enabled:=Enabled;FState.LoadW:=Max(0,LoadW);if Enabled then Target:=Min(Max(0,CommandRPM),FConfig.MaxRPM)else Target:=0;FState.CommandRPM:=Target;Step:=Max(0,FConfig.RampRPMPerSec)*Dt;if FState.ActualRPM<Target then FState.ActualRPM:=Min(Target,FState.ActualRPM+Step)else FState.ActualRPM:=Max(Target,FState.ActualRPM-Step);FState.Fault:=(FConfig.RatedPowerW>0)and(FState.LoadW>FConfig.RatedPowerW);if FState.Fault then FState.ActualRPM:=FState.ActualRPM*0.98;end;
end.
