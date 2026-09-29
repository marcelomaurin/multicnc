unit multiphysics_machine_faults;
{$mode objfpc}{$H+}
interface
uses SysUtils,multiphysics_machine_runtime;
type TMachineFault=(mfNone,mfOpenCircuit,mfShortCircuit,mfAxisLocked,mfSensorFailed,mfLimitStuck,mfCorrosion,mfOxidation,mfOverCurrent);
procedure InjectAxisFault(A:TAxisRuntime;Fault:TMachineFault);
implementation
procedure InjectAxisFault(A:TAxisRuntime;Fault:TMachineFault);begin case Fault of mfOpenCircuit:begin A.Current:=0;A.Command.Enabled:=False;end;mfShortCircuit:begin A.Current:=10;end;mfAxisLocked:begin A.Motor.LoadTorque:=A.Motor.RunningTorque*2;end;mfSensorFailed:begin A.State.PositionMM:=0;end;mfLimitStuck:begin A.State.AtMin:=True;A.Command.Enabled:=False;end;end;end;
end.
