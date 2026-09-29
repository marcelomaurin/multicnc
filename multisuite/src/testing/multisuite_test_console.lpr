program multisuite_test_console;
{$mode objfpc}{$H+}
uses SysUtils,multisuite_test_types,multisuite_test_runner;
var R:TTestResultArray;I,Pass,Fail:Integer;Root,Report:string;
begin Root:=ExpandFileName(ExtractFilePath(ParamStr(0))+'..'+DirectorySeparator+'..'+DirectorySeparator+'..'+DirectorySeparator);if ParamCount>0 then Root:=ExpandFileName(ParamStr(1));R:=TSuiteTestRunner.RunAll(Root);Pass:=0;Fail:=0;for I:=0 to High(R)do begin Writeln('[',TestStatusName(R[I].Status),'] ',R[I].Tool,' / ',R[I].Name,' (',R[I].DurationMS,' ms)');if R[I].Status=tsPassed then Inc(Pass)else Inc(Fail);end;Report:=IncludeTrailingPathDelimiter(Root)+'multisuite_test_report.txt';TSuiteTestRunner.SaveReport(Report,R);Writeln('PASS=',Pass,' PROBLEMAS=',Fail);Writeln('Relatorio: ',Report);if Fail>0 then Halt(1);end.
