unit multiphysics_circuit_models;
{$mode objfpc}{$H+}
interface
uses Math;
type
 TResistorModel=record Resistance:Double;end;
 TCapacitorModel=record Capacitance,Voltage:Double;end;
 TInductorModel=record Inductance,Current:Double;end;
 TDiodeModel=record ForwardVoltage,OnResistance:Double;end;
 TMOSFETModel=record RdsOn,Threshold:Double;end;
 TRelayModel=record CoilResistance,PullInVoltage:Double;Closed:Boolean;end;
function ResistorCurrent(const R:TResistorModel;V:Double):Double;
function CapacitorStep(var C:TCapacitorModel;Current,Dt:Double):Double;
function InductorStep(var L:TInductorModel;Voltage,Dt:Double):Double;
function DiodeCurrent(const D:TDiodeModel;V:Double):Double;
function MOSFETCurrent(const M:TMOSFETModel;Vds,Vgs:Double):Double;
procedure RelayStep(var R:TRelayModel;CoilVoltage:Double);
implementation
function ResistorCurrent(const R:TResistorModel;V:Double):Double;begin if R.Resistance>0 then Result:=V/R.Resistance else Result:=0;end;
function CapacitorStep(var C:TCapacitorModel;Current,Dt:Double):Double;begin if C.Capacitance>0 then C.Voltage:=C.Voltage+(Current/C.Capacitance)*Dt;Result:=C.Voltage;end;
function InductorStep(var L:TInductorModel;Voltage,Dt:Double):Double;begin if L.Inductance>0 then L.Current:=L.Current+(Voltage/L.Inductance)*Dt;Result:=L.Current;end;
function DiodeCurrent(const D:TDiodeModel;V:Double):Double;begin if(V>D.ForwardVoltage)and(D.OnResistance>0)then Result:=(V-D.ForwardVoltage)/D.OnResistance else Result:=0;end;
function MOSFETCurrent(const M:TMOSFETModel;Vds,Vgs:Double):Double;begin if(Vgs>=M.Threshold)and(M.RdsOn>0)then Result:=Vds/M.RdsOn else Result:=0;end;
procedure RelayStep(var R:TRelayModel;CoilVoltage:Double);begin R.Closed:=Abs(CoilVoltage)>=R.PullInVoltage;end;
end.
