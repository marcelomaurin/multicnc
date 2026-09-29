program test_electromagnetics;
{$mode objfpc}{$H+}
uses Math,multiphysics_electromagnetics;
var C:TCoilModel;B,L,E,M:Double;
begin FillChar(C,SizeOf(C),0);C.Turns:=500;C.Length:=0.1;C.Area:=0.0001;C.RelativePermeability:=100;C.Resistance:=10;C.Current:=1;B:=SolenoidField(C);if B<=0 then Halt(1);L:=CoilInductance(C);if L<=0 then Halt(2);E:=FaradayEMF(100,0.002,0.001,0.01);if E>=0 then Halt(3);M:=MutualInductance(0.1,0.2,0.8);if M<=0 then Halt(4);C.Current:=0;C.Inductance:=L;CoilStep(C,12,0.001);if(C.Current<=0)or(C.Flux<=0)then Halt(5);if MagneticForce(B,0.001,1)<=0 then Halt(6);Writeln('PASS electromagnetics');end.
