unit multisuite_test_runner;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Process, multisuite_test_types, multisuite_test_catalog;
type TSuiteTestRunner = class
public
  class function RunOne(const Root: string; const D: TTestDefinition): TTestResult; static;
  class function RunAll(const Root: string): TTestResultArray; static;
  class procedure SaveReport(const FN: string; const R: TTestResultArray); static;
end;
implementation

class function TSuiteTestRunner.RunOne(const Root: string; const D: TTestDefinition): TTestResult;
var P: TProcess; Exe, Work, ModuleName: string; Start: QWord; N: Integer;
  Buffer: array[0..8191] of Char; Chunk: string; TimedOut: Boolean;
begin
  Result.Name := D.Name; Result.Tool := D.Tool; Result.Executable := D.Executable;
  Result.ExitCode := -1; Result.DurationMS := 0; Result.Output := '';
  Exe := ExpandFileName(IncludeTrailingPathDelimiter(Root) + D.Executable);
  {$IFDEF Windows}Exe := Exe + '.exe';{$ENDIF}
  if not FileExists(Exe) then begin
    // Installed apps are flat files named after their modules. Their tests
    // live below tests/<module>/ rather than <module>/tests/.
    if Pos('tests/', D.Executable) = 1 then ModuleName := 'multicnc'
    else if Pos('/', D.Executable) > 0 then
      ModuleName := Copy(D.Executable, 1, Pos('/', D.Executable) - 1)
    else ModuleName := '';
    if ModuleName <> '' then begin
      Exe := IncludeTrailingPathDelimiter(Root) + 'tests' + DirectorySeparator +
        ModuleName + DirectorySeparator + ExtractFileName(D.Executable);
      {$IFDEF Windows}Exe := Exe + '.exe';{$ENDIF}
    end;
  end;
  if not FileExists(Exe) then begin
    Result.Status := tsMissing; Result.Output := 'Teste nao incluido/compilado: ' + Exe; Exit;
  end;
  Work := GetTempFileName(GetTempDir, 'mst'); DeleteFile(Work);
  if not ForceDirectories(Work) then begin
    Result.Status := tsError; Result.Output := 'Nao foi possivel criar uma pasta temporaria.'; Exit;
  end;
  P := TProcess.Create(nil);
  try
    P.Executable := Exe; P.CurrentDirectory := Work;
    P.Options := [poUsePipes, poStderrToOutPut];
    Start := GetTickCount64; TimedOut := False;
    try
      P.Execute;
      repeat
        while P.Output.NumBytesAvailable > 0 do begin
          N := P.Output.Read(Buffer, SizeOf(Buffer));
          if N > 0 then begin
            SetString(Chunk, PChar(@Buffer[0]), N);
            if Length(Result.Output) < 1024 * 1024 then Result.Output := Result.Output + Chunk;
          end;
        end;
        if not P.Running and (P.Output.NumBytesAvailable = 0) then Break;
        if GetTickCount64 - Start > 30000 then begin
          P.Terminate(-1); TimedOut := True; Break;
        end;
        Sleep(5);
      until False;
      Result.DurationMS := GetTickCount64 - Start;
      if TimedOut then begin
        Result.Status := tsError; Result.Output := Result.Output + LineEnding + 'Tempo limite de 30 segundos excedido.';
      end else begin
        Result.ExitCode := P.ExitCode;
        if P.ExitStatus = 0 then Result.Status := tsPassed
        else begin
          Result.Status := tsFailed;
          // FPC/Unix retorna zero em ExitCode quando houve um sinal.
          if Result.ExitCode = 0 then Result.ExitCode := -P.ExitStatus;
        end;
      end;
    except on E: Exception do begin Result.Status := tsError; Result.Output := E.Message; end; end;
  finally
    P.Free; RemoveDir(Work);
  end;
end;

class function TSuiteTestRunner.RunAll(const Root: string): TTestResultArray;
var C: TTestDefinitions; I: Integer;
begin
  C := DefaultTestCatalog; SetLength(Result, Length(C));
  for I := 0 to High(C) do Result[I] := RunOne(Root, C[I]);
end;

class procedure TSuiteTestRunner.SaveReport(const FN: string; const R: TTestResultArray);
var S: TStringList; I: Integer;
begin
  S := TStringList.Create;
  try
    S.Add('MultiSuite Test Report');
    for I := 0 to High(R) do begin
      S.Add(Format('[%s] %s / %s | exit=%d | %d ms',
        [TestStatusName(R[I].Status), R[I].Tool, R[I].Name, R[I].ExitCode, R[I].DurationMS]));
      if R[I].Output <> '' then S.Add(Trim(R[I].Output));
    end;
    if ExtractFileDir(FN) <> '' then
      if not ForceDirectories(ExtractFileDir(FN)) then raise EInOutError.Create('Nao foi possivel criar a pasta do relatorio.');
    S.SaveToFile(FN);
  finally S.Free; end;
end;
end.
