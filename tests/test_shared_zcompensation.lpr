program test_shared_zcompensation;
{$mode objfpc}{$H+}
uses SysUtils,multisuite_heightmap,multisuite_zcompensation;
var H:THeightMap;C:TZCompensator;P:TCompensatedPoint;
begin H:=THeightMap.Create;C:=TZCompensator.Create(H);try H.Add(0,0,0);H.Add(10,0,0.2);H.Add(0,10,0);H.Add(10,10,0.2);C.ReferenceZ:=0;C.MaxCorrection:=0.5;if not C.Correct(10,5,-0.10,P)then Halt(1);if Abs(P.CorrectedZ-0.10)>0.01 then Halt(2);C.MaxCorrection:=0.05;if C.Correct(10,5,-0.10,P)then Halt(3);Writeln('Z compensation: OK');finally C.Free;H.Free;end;end.
