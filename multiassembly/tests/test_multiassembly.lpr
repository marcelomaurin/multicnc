program test_multiassembly;
{$mode objfpc}{$H+}
uses multiassembly_project,multiassembly_demo;
var P:TAssemblyProject;
begin P:=TAssemblyProject.Create;try TAssemblyDemo.BuildCNC(P);if P.ComponentCount<10 then Halt(1);if P.WireCount<10 then Halt(2);if P.RelationCount<3 then Halt(3);if P.FindComponent('MX')<0 then Halt(4);if P.FindComponent('CTRL')<0 then Halt(5);Writeln('MultiAssembly: OK components=',P.ComponentCount,' wires=',P.WireCount,' relations=',P.RelationCount);finally P.Free;end;end.
