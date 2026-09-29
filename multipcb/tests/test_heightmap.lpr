program test_heightmap;
{$mode objfpc}{$H+}
uses Classes,SysUtils,multipcb_heightmap;
var H:THeightMap;E:TStringList;Z:Double;
begin H:=THeightMap.Create;E:=TStringList.Create;try H.Add(0,0,0);H.Add(10,0,0.1);H.Add(0,10,0.2);H.Add(10,10,0.3);if not H.Validate(E)then Halt(1);if not H.InterpolateIDW(5,5,Z)then Halt(2);if Abs(Z-0.15)>0.001 then Halt(3);Writeln('HeightMap: OK Z=',Z:0:3);finally E.Free;H.Free;end;end.
