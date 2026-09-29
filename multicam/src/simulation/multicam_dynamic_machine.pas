unit multicam_dynamic_machine;
{$mode objfpc}{$H+}
interface
uses Math,multicam_types,multicam_motor_dynamics,multicam_cut_load,multicam_electronics_types;
type TDynamicMachine=class
 private FX,FY,FZ:TMotorDynamics;
 public constructor Create;destructor Destroy;override;procedure Configure(StepsX,StepsY,StepsZ:Double);procedure Reset;procedure ApplyMove(const FromP,ToP:TCamPoint;const Tool:TTool;Feed:Double;Cutting:Boolean;Dt:Double);procedure CopyToElectronics(var E:TElectronicsState);function Position:TCamPoint;
 end;
implementation
constructor TDynamicMachine.Create;begin inherited;FX:=TMotorDynamics.Create;FY:=TMotorDynamics.Create;FZ:=TMotorDynamics.Create;end;
destructor TDynamicMachine.Destroy;begin FZ.Free;FY.Free;FX.Free;inherited;end;
procedure TDynamicMachine.Configure(StepsX,StepsY,StepsZ:Double);var C:TMotorConfig;begin C.StepsPerMM:=StepsX;C.MaxSpeedMMMin:=3000;C.AccelerationMMSS:=150;C.RatedTorqueNm:=1.2;C.MaxCurrentA:=3;FX.Configure(C);C.StepsPerMM:=StepsY;FY.Configure(C);C.StepsPerMM:=StepsZ;C.MaxSpeedMMMin:=800;C.RatedTorqueNm:=1.5;FZ.Configure(C);end;
procedure TDynamicMachine.Reset;begin FX.Reset;FY.Reset;FZ.Reset;end;
procedure TDynamicMachine.ApplyMove(const FromP,ToP:TCamPoint;const Tool:TTool;Feed:Double;Cutting:Boolean;Dt:Double);var Load,Depth:Double;begin Load:=0;if Cutting then begin Depth:=Max(0,-ToP.Z);Load:=TCutLoadModel.EstimateTorque(Tool,Depth,Feed);end;FX.MoveTo(ToP.X,Feed,Load,Dt);FY.MoveTo(ToP.Y,Feed,Load,Dt);FZ.MoveTo(ToP.Z,Min(Feed,800),Load,Dt);end;
procedure TDynamicMachine.CopyToElectronics(var E:TElectronicsState);begin E.X.CommandMM:=FX.State.CommandMM;E.X.ActualMM:=FX.State.ActualMM;E.X.LostSteps:=FX.State.LostSteps;E.X.MotorCurrentA:=FX.State.CurrentA;E.X.DriverTempC:=FX.State.DriverTempC;E.Y.CommandMM:=FY.State.CommandMM;E.Y.ActualMM:=FY.State.ActualMM;E.Y.LostSteps:=FY.State.LostSteps;E.Y.MotorCurrentA:=FY.State.CurrentA;E.Y.DriverTempC:=FY.State.DriverTempC;E.Z.CommandMM:=FZ.State.CommandMM;E.Z.ActualMM:=FZ.State.ActualMM;E.Z.LostSteps:=FZ.State.LostSteps;E.Z.MotorCurrentA:=FZ.State.CurrentA;E.Z.DriverTempC:=FZ.State.DriverTempC;end;
function TDynamicMachine.Position:TCamPoint;begin Result.X:=FX.State.ActualMM;Result.Y:=FY.State.ActualMM;Result.Z:=FZ.State.ActualMM;end;
end.
