unit multiphysics_electrical_faults;
{$mode objfpc}{$H+}
interface
uses Math;
type
 TElectricalFaultKind=(efNone,efOpenCircuit,efShortCircuit,efLeakage,efOverCurrent);
 TShortCircuitState=record Active:Boolean;Resistance,Current,Power,Temperature,Energy:Double;Tripped,Damaged:Boolean;end;
 TProtectionModel=record CurrentLimit,TripDelay,FuseI2t,AccumulatedI2t,ElapsedOverCurrent:Double;end;
procedure InitShort(var S:TShortCircuitState;Resistance,AmbientC:Double);
procedure ShortCircuitStep(var S:TShortCircuitState;var P:TProtectionModel;Voltage,Dt,ThermalCapacity,CoolingWPerK,AmbientC:Double);
implementation
procedure InitShort(var S:TShortCircuitState;Resistance,AmbientC:Double);begin FillChar(S,SizeOf(S),0);S.Active:=True;S.Resistance:=Max(1e-6,Resistance);S.Temperature:=AmbientC;end;
procedure ShortCircuitStep(var S:TShortCircuitState;var P:TProtectionModel;Voltage,Dt,ThermalCapacity,CoolingWPerK,AmbientC:Double);var Heat:Double;begin if(Dt<=0)or not S.Active or S.Tripped then Exit;S.Current:=Abs(Voltage)/Max(1e-6,S.Resistance);S.Power:=Sqr(S.Current)*S.Resistance;S.Energy:=S.Energy+S.Power*Dt;if S.Current>P.CurrentLimit then begin P.ElapsedOverCurrent:=P.ElapsedOverCurrent+Dt;P.AccumulatedI2t:=P.AccumulatedI2t+Sqr(S.Current)*Dt;end else P.ElapsedOverCurrent:=0;if((P.TripDelay>0)and(P.ElapsedOverCurrent>=P.TripDelay))or((P.FuseI2t>0)and(P.AccumulatedI2t>=P.FuseI2t))then begin S.Tripped:=True;S.Active:=False;S.Current:=0;S.Power:=0;Exit;end;if ThermalCapacity>0 then begin Heat:=S.Power-CoolingWPerK*(S.Temperature-AmbientC);S.Temperature:=S.Temperature+Heat/ThermalCapacity*Dt;end;if S.Temperature>=180 then S.Damaged:=True;end;
end.
