program test_launcher_paths;
{$mode objfpc}{$H+}
uses SysUtils,multisuite_types,multisuite_registry;
var R:TSuiteRegistry;I:Integer;T:TSuiteToolInfo;
begin R:=TSuiteRegistry.Create;try if R.Find(stiReservedPCB)>=0 then Halt(1);for I:=0 to R.Count-1 do begin T:=R.Tool(I);if T.Executable=''then Halt(2);if Pos(DirectorySeparator,T.Executable)>0 then Halt(3);Writeln(T.Name,' -> ',T.Executable);end;finally R.Free;end;end.
