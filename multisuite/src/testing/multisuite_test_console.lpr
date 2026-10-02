program multisuite_test_console;
{$mode objfpc}{$H+}
uses SysUtils, multisuite_paths, multisuite_test_types, multisuite_test_runner;
var R: TTestResultArray; I, Pass, Fail: Integer; Root, Report: string;
begin
  Root := SuiteRootForExecutable(ParamStr(0));
  if ParamCount > 0 then Root := ExpandFileName(ParamStr(1));
  R := TSuiteTestRunner.RunAll(Root); Pass := 0; Fail := 0;
  for I := 0 to High(R) do begin
    Writeln('[', TestStatusName(R[I].Status), '] ', R[I].Tool, ' / ', R[I].Name, ' (', R[I].DurationMS, ' ms)');
    if R[I].Status = tsPassed then Inc(Pass) else begin Inc(Fail); Writeln(R[I].Output); end;
  end;
  Report := SuiteConfigDir + 'reports' + DirectorySeparator + 'multisuite_test_report.txt';
  TSuiteTestRunner.SaveReport(Report, R);
  Writeln('PASS=', Pass, ' PROBLEMAS=', Fail); Writeln('Relatorio: ', Report);
  if Fail > 0 then Halt(1);
end.
