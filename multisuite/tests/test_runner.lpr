program test_runner;
{$mode objfpc}{$H+}
uses Classes, SysUtils, {$IFDEF UNIX}BaseUnix,{$ENDIF}
  multisuite_test_catalog, multisuite_test_types, multisuite_test_runner;
var Base, Child, Exe: string; Input, Output: TFileStream; D: TTestDefinition;
  R: TTestResult; Reports: TTestResultArray; I: Integer;
procedure Check(OK: Boolean; const Msg: string);
begin if not OK then raise Exception.Create(Msg); end;
begin
  if Pos('runner-child', ExtractFileName(ParamStr(0))) = 1 then begin
    Writeln('cwd=', GetCurrentDir);
    for I := 1 to 2048 do Writeln(StringOfChar('x', 64));
    Writeln(StdErr, 'stderr captured'); Halt(7);
  end;
  Base := GetTempFileName(GetTempDir, 'mst'); DeleteFile(Base); ForceDirectories(Base);
  Child := 'runner-child'; {$IFDEF WINDOWS}Child := Child + '.exe';{$ENDIF}
  Exe := Base + DirectorySeparator + Child;
  Input := TFileStream.Create(ParamStr(0), fmOpenRead or fmShareDenyNone);
  try Output := TFileStream.Create(Exe, fmCreate); try Output.CopyFrom(Input, 0); finally Output.Free; end; finally Input.Free; end;
  {$IFDEF UNIX}fpchmod(Exe, &755);{$ENDIF}
  try
    D.Tool := 'test'; D.Name := 'pipe'; D.Source := ''; D.Executable := 'runner-child';
    R := TSuiteTestRunner.RunOne(Base, D);
    Check((R.Status = tsFailed) and (R.ExitCode = 7), Format('nonzero exit is classified as failed: status=%s exit=%d output=%s', [TestStatusName(R.Status), R.ExitCode, Copy(R.Output, 1, 100)]));
    Check((Length(R.Output) > 128000) and (Pos('stderr captured', R.Output) > 0), 'drains large stdout and stderr without deadlock');
    Check(Pos('cwd=' + Base, R.Output) = 0, 'installed directory is not used for writable test output');
    // Reproduce the flat installed layout: multisuite is an app file, not a directory.
    with TFileStream.Create(Base + '/multisuite', fmCreate) do Free;
    ForceDirectories(Base + '/tests/multisuite');
    Check(RenameFile(Exe, Base + '/tests/multisuite/' + Child), 'stage module test');
    Exe := Base + '/tests/multisuite/' + Child;
    D.Executable := 'multisuite/tests/runner-child';
    R := TSuiteTestRunner.RunOne(Base, D);
    Check((R.Status = tsFailed) and (R.ExitCode = 7), 'module test found beside flat installed apps');
    ForceDirectories(Base + '/tests/multicnc');
    Check(RenameFile(Exe, Base + '/tests/multicnc/' + Child), 'stage root test');
    Exe := Base + '/tests/multicnc/' + Child;
    D.Executable := 'tests/runner-child';
    R := TSuiteTestRunner.RunOne(Base, D);
    Check((R.Status = tsFailed) and (R.ExitCode = 7), 'root CNC test found in installed test directory');
    D.Executable := 'missing'; R := TSuiteTestRunner.RunOne(Base, D);
    Check((R.Status = tsMissing) and (R.DurationMS = 0), 'missing test is never reported as passed');
    SetLength(Reports, 1); Reports[0] := R;
    TSuiteTestRunner.SaveReport(Base + '/reports/result.txt', Reports);
    Check(FileExists(Base + '/reports/result.txt'), 'report directory is created');
    Writeln('Test runner: OK (pipes, stderr, exit status, installed paths, temporary workdir, missing, reports)');
  finally
    DeleteFile(Exe); DeleteFile(Base + '/multisuite');
    DeleteFile(Base + '/reports/result.txt'); RemoveDir(Base + '/reports');
    RemoveDir(Base + '/tests/multisuite'); RemoveDir(Base + '/tests/multicnc');
    RemoveDir(Base + '/tests'); RemoveDir(Base);
  end;
end.
