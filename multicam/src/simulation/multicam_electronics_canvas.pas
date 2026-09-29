unit multicam_electronics_canvas;
{$mode objfpc}{$H+}
interface
uses Classes,Controls,Graphics,SysUtils,multicam_electronics_types;
type TElectronicsCanvas=class(TCustomControl)
 private FState:TElectronicsState;
 protected procedure Paint;override;
 public procedure SetState(const S:TElectronicsState);
 end;
implementation
procedure TElectronicsCanvas.SetState(const S:TElectronicsState);begin FState:=S;Invalidate;end;
procedure TElectronicsCanvas.Paint;var Y:Integer;procedure Line(const S:string);begin Canvas.TextOut(12,Y,S);Inc(Y,20);end;
begin Canvas.Brush.Color:=clWhite;Canvas.FillRect(ClientRect);Y:=12;Line(Format('CONTROLADORA  Logic %.1fV  Motor %.1fV',[FState.LogicV,FState.ControllerV]));Line(Format('X STEP=%d DIR=%d EN=%d Pulsos=%d Fault=%s',[Ord(FState.X.Step),Ord(FState.X.Dir),Ord(FState.X.Enable),FState.X.PulseCount,BoolToStr(FState.X.DriverFault,True)]));Line(Format('Y STEP=%d DIR=%d EN=%d Pulsos=%d Fault=%s',[Ord(FState.Y.Step),Ord(FState.Y.Dir),Ord(FState.Y.Enable),FState.Y.PulseCount,BoolToStr(FState.Y.DriverFault,True)]));Line(Format('Z STEP=%d DIR=%d EN=%d Pulsos=%d Fault=%s',[Ord(FState.Z.Step),Ord(FState.Z.Dir),Ord(FState.Z.Enable),FState.Z.PulseCount,BoolToStr(FState.Z.DriverFault,True)]));Line(Format('LIMIT X=%s Y=%s Z=%s  ESTOP=%s',[BoolToStr(FState.LimitX,True),BoolToStr(FState.LimitY,True),BoolToStr(FState.LimitZ,True),BoolToStr(FState.EStop,True)]));Line(Format('X real %.3f cmd %.3f lost %d temp %.1fC',[FState.X.ActualMM,FState.X.CommandMM,FState.X.LostSteps,FState.X.DriverTempC]));Line(Format('Y real %.3f cmd %.3f lost %d temp %.1fC',[FState.Y.ActualMM,FState.Y.CommandMM,FState.Y.LostSteps,FState.Y.DriverTempC]));Line(Format('Z real %.3f cmd %.3f lost %d temp %.1fC',[FState.Z.ActualMM,FState.Z.CommandMM,FState.Z.LostSteps,FState.Z.DriverTempC]));Line(Format('SPINDLE EN=%s PWM=%.1f%% CMD=%.0f RPM FB=%.0f RPM Fault=%s',[BoolToStr(FState.Spindle.Enable,True),FState.Spindle.PWM,FState.Spindle.CommandRPM,FState.Spindle.FeedbackRPM,BoolToStr(FState.Spindle.Fault,True)]));end;
end.
