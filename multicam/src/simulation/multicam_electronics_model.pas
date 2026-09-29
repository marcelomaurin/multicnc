unit multicam_electronics_model;
{$mode objfpc}{$H+}
interface
uses SysUtils,Math,multicam_types,multicam_electronics_types;
type TElectronicsConfig=record StepsPerMMX,StepsPerMMY,StepsPerMMZ:Double;MotorSupplyV,LogicSupplyV,MaxMotorCurrentA:Double;end;
 TElectronicsModel=class
 private FConfig:TElectronicsConfig;FState:TElectronicsState;FLast:TCamPoint;FHasLast:Boolean;procedure AxisMove(var A:TAxisElectricalState;Delta,StepsPerMM:Double);
 public procedure Configure(const C:TElectronicsConfig);procedure Reset;procedure ApplyMove(const P:TCamPoint;SpindleOn:Boolean;RPM:Integer);procedure SetLimits(X,Y,Z:Boolean);procedure SetEStop(Value:Boolean);function HasFault:Boolean;property State:TElectronicsState read FState;
 end;
implementation
procedure TElectronicsModel.Configure(const C:TElectronicsConfig);begin FConfig:=C;Reset;end;
procedure TElectronicsModel.Reset;begin FillChar(FState,SizeOf(FState),0);FState.ControllerV:=FConfig.MotorSupplyV;FState.LogicV:=FConfig.LogicSupplyV;FState.X.Enable:=elHigh;FState.Y.Enable:=elHigh;FState.Z.Enable:=elHigh;FState.X.SupplyV:=FConfig.MotorSupplyV;FState.Y.SupplyV:=FConfig.MotorSupplyV;FState.Z.SupplyV:=FConfig.MotorSupplyV;FHasLast:=False;end;
procedure TElectronicsModel.AxisMove(var A:TAxisElectricalState;Delta,StepsPerMM:Double);var N:Int64;begin if Delta>=0 then A.Dir:=elHigh else A.Dir:=elLow;N:=Round(Abs(Delta)*StepsPerMM);A.PulseCount:=A.PulseCount+N;if N>0 then A.Step:=elHigh else A.Step:=elLow;end;
procedure TElectronicsModel.ApplyMove(const P:TCamPoint;SpindleOn:Boolean;RPM:Integer);begin if FState.EStop then Exit;if FHasLast then begin AxisMove(FState.X,P.X-FLast.X,FConfig.StepsPerMMX);AxisMove(FState.Y,P.Y-FLast.Y,FConfig.StepsPerMMY);AxisMove(FState.Z,P.Z-FLast.Z,FConfig.StepsPerMMZ);end;FLast:=P;FHasLast:=True;FState.Spindle.Enable:=SpindleOn;FState.Spindle.CommandRPM:=RPM;if SpindleOn then FState.Spindle.PWM:=100 else FState.Spindle.PWM:=0;end;
procedure TElectronicsModel.SetLimits(X,Y,Z:Boolean);begin FState.LimitX:=X;FState.LimitY:=Y;FState.LimitZ:=Z;end;
procedure TElectronicsModel.SetEStop(Value:Boolean);begin FState.EStop:=Value;if Value then begin FState.X.Enable:=elLow;FState.Y.Enable:=elLow;FState.Z.Enable:=elLow;FState.Spindle.Enable:=False;FState.Spindle.PWM:=0;end;end;
function TElectronicsModel.HasFault:Boolean;begin Result:=FState.EStop or FState.X.DriverFault or FState.Y.DriverFault or FState.Z.DriverFault or FState.Spindle.Fault;end;
end.
