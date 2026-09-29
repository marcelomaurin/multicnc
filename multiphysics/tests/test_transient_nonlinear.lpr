program test_transient_nonlinear;
{$mode objfpc}{$H+}
uses Math,multiphysics_mna,multiphysics_nonlinear;
var S:TMNASolver;V,N:Integer;D,M:TNonLinearResult;I:Integer;
begin S:=TMNASolver.Create;try S.Clear;S.TimeStep:=0.001;V:=S.AddNode('VCC');N:=S.AddNode('RC');S.AddVoltageSource(V,0,10);S.AddResistor(V,N,1000);S.AddCapacitor(N,0,0.000001);for I:=1 to 10 do if not S.Solve then Halt(1);if(S.NodeVoltage(N)<=0)or(S.NodeVoltage(N)>=10)then Halt(2);finally S.Free;end;D:=SolveDiode(0.7,1e-12,0.026);if D.Current<=0 then Halt(3);M:=SolveMOSFET(1,5,2,0.5);if M.Current<=0 then Halt(4);Writeln('PASS transient and nonlinear models');end.
