program test_registry;
{$mode objfpc}{$H+}
uses multisuite_types,multisuite_registry;
var R:TSuiteRegistry;
begin R:=TSuiteRegistry.Create;try if R.Count<>8 then Halt(1);if R.Find(stiMultiCAD)<0 then Halt(2);if R.Find(stiMultiCNC)<0 then Halt(3);if R.Find(stiMultiAssembly)<0 then Halt(4);Writeln('MultiSuite registry: OK tools=',R.Count);finally R.Free;end;end.
