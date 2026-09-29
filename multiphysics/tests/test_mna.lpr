program test_mna;
{$mode objfpc}{$H+}
uses Math,multiphysics_mna;
var S:TMNASolver;V,N1:Integer;
begin S:=TMNASolver.Create;try S.Clear;V:=S.AddNode('VCC');N1:=S.AddNode('MID');S.AddVoltageSource(V,0,10);S.AddResistor(V,N1,1000);S.AddResistor(N1,0,1000);if not S.Solve then begin Writeln(S.LastError);Halt(1);end;if Abs(S.NodeVoltage(V)-10)>1e-6 then Halt(2);if Abs(S.NodeVoltage(N1)-5)>1e-6 then Halt(3);if Abs(S.ResistorCurrent(0)-0.005)>1e-6 then Halt(4);Writeln('PASS MNA divider Vmid=',S.NodeVoltage(N1):0:3);finally S.Free;end;end.
