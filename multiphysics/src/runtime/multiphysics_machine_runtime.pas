unit multiphysics_machine_runtime;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,Math,multiphysics_graph,multiphysics_axis_control,multiphysics_stepper_physics;
type
 TAxisRuntime=class
 public Name:string;Command:TAxisCommand;State:TAxisState;Motor:TStepperPhysical;MinMM,MaxMM,Temperature,Current:Double;
 end;
 TMachineRuntime=class
 private FAxes:TList;FSpindleRPM,FSpindleTarget,FTime,FDT:Double;FEnabled:Boolean;FTripReason:string;
  function AxisByName(const N:string):TAxisRuntime;
 public constructor Create;destructor Destroy;override;procedure Clear;function AddAxis(const N:string;MinMM,MaxMM,StepsPerMM,Torque:Double):TAxisRuntime;procedure CommandAxis(const N:string;TargetMM,SpeedMMs:Double);procedure SetSpindle(RPM:Double);procedure Start;procedure Stop;procedure Step;function AxisCount:Integer;function Axis(I:Integer):TAxisRuntime;property SpindleRPM:Double read FSpindleRPM;property Enabled:Boolean read FEnabled;property TripReason:string read FTripReason;
 end;
implementation
constructor TMachineRuntime.Create;begin inherited;FAxes:=TList.Create;FDT:=0.001;end;
destructor TMachineRuntime.Destroy;begin Clear;FAxes.Free;inherited;end;
procedure TMachineRuntime.Clear;var I:Integer;begin for I:=0 to FAxes.Count-1 do TObject(FAxes[I]).Free;FAxes.Clear;end;
function TMachineRuntime.AddAxis(const N:string;MinMM,MaxMM,StepsPerMM,Torque:Double):TAxisRuntime;begin Result:=TAxisRuntime.Create;Result.Name:=N;Result.MinMM:=MinMM;Result.MaxMM:=MaxMM;Result.Motor.StepsPerMM:=StepsPerMM;Result.Motor.RunningTorque:=Torque;Result.Command.MaxSpeedMMs:=50;FAxes.Add(Result);end;
function TMachineRuntime.AxisByName(const N:string):TAxisRuntime;var I:Integer;begin Result:=nil;for I:=0 to FAxes.Count-1 do if SameText(TAxisRuntime(FAxes[I]).Name,N)then Exit(TAxisRuntime(FAxes[I]));end;
procedure TMachineRuntime.CommandAxis(const N:string;TargetMM,SpeedMMs:Double);var A:TAxisRuntime;begin A:=AxisByName(N);if A=nil then Exit;A.Command.TargetMM:=TargetMM;A.Command.MaxSpeedMMs:=SpeedMMs;A.Command.Enabled:=True;end;
procedure TMachineRuntime.SetSpindle(RPM:Double);begin FSpindleTarget:=Max(0,RPM);end;
procedure TMachineRuntime.Start;begin FEnabled:=True;FTripReason:='';end;procedure TMachineRuntime.Stop;begin FEnabled:=False;FSpindleTarget:=0;end;
procedure TMachineRuntime.Step;var I,D,E:Integer;A:TAxisRuntime;P:TProtectionState;begin if not FEnabled then Exit;for I:=0 to FAxes.Count-1 do begin A:=TAxisRuntime(FAxes[I]);D:=StepDemand(A.Command,A.State,A.Motor.StepsPerMM,FDT);E:=ExecuteSteps(A.Motor,D);if A.Motor.StepsPerMM>0 then A.State.PositionMM:=A.State.PositionMM+E/A.Motor.StepsPerMM;A.Current:=0.5+Abs(E)*0.002;A.Temperature:=A.Temperature+(Sqr(A.Current)*0.02-(A.Temperature-25)*0.01)*FDT;if A.Temperature=0 then A.Temperature:=25;UpdateLimits(A.State,A.MinMM,A.MaxMM);P.MaxCurrent:=5;P.MaxTemperature:=90;CheckProtection(A.Current,A.Temperature,P);if P.Tripped then begin FTripReason:=A.Name+': '+P.Reason;FEnabled:=False;Exit;end;end;FSpindleRPM:=FSpindleRPM+(FSpindleTarget-FSpindleRPM)*Min(1,5*FDT);FTime:=FTime+FDT;end;
function TMachineRuntime.AxisCount:Integer;begin Result:=FAxes.Count;end;function TMachineRuntime.Axis(I:Integer):TAxisRuntime;begin Result:=TAxisRuntime(FAxes[I]);end;
end.
