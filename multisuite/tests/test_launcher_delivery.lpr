program test_launcher_delivery;
{$mode objfpc}{$H+}
uses Classes, SysUtils, {$IFDEF UNIX}BaseUnix,{$ENDIF}
  multisuite_types, multisuite_registry, multisuite_paths, multisuite_launcher;
var R: TSuiteRegistry; T: TSuiteToolInfo; S: TStringList; Base, Repo, Installed, Project,
  Exe, Artifact, ErrorText: string; Start: QWord; I: Integer;
procedure Check(OK: Boolean; const Msg: string);
begin if not OK then raise Exception.Create(Msg); end;
procedure CopySelf(const Target: string);
var Input, Output: TFileStream;
begin
  ForceDirectories(ExtractFileDir(Target));
  Input := TFileStream.Create(ParamStr(0), fmOpenRead or fmShareDenyNone);
  try
    Output := TFileStream.Create(Target, fmCreate);
    try Output.CopyFrom(Input, 0); finally Output.Free; end;
  finally Input.Free; end;
  {$IFDEF UNIX}fpchmod(Target, &755);{$ENDIF}
end;
begin
  if (ParamCount > 0) and (ParamStr(1) = '--project') then begin
    S := TStringList.Create;
    try
      for I := 1 to ParamCount do S.Add(ParamStr(I));
      S.SaveToFile(IncludeTrailingPathDelimiter(ParamStr(2)) + 'args.tmp');
      RenameFile(IncludeTrailingPathDelimiter(ParamStr(2)) + 'args.tmp',
        IncludeTrailingPathDelimiter(ParamStr(2)) + 'args.txt');
    finally S.Free; end;
    Halt(0);
  end;
  Base := GetTempFileName(GetTempDir, 'msu'); DeleteFile(Base); ForceDirectories(Base);
  Repo := Base + '/repo'; Installed := Base + '/installed'; Project := Base + '/projeto com espacos';
  ForceDirectories(Repo + '/multisuite/src/core'); ForceDirectories(Installed); ForceDirectories(Project);
  S := TStringList.Create; R := TSuiteRegistry.Create;
  try
    S.Text := 'root marker'; S.SaveToFile(Repo + '/multisuite/src/core/multisuite_registry.pas');
    T := R.Tool(R.Find(stiMultiCNC)); Exe := Repo + '/src/app/multicnc';
    {$IFDEF WINDOWS}Exe := Exe + '.exe';{$ENDIF}
    CopySelf(Exe);
    Check(ExpandFileName(ToolExecutable(T, Repo, Installed)) = ExpandFileName(Exe), 'development executable uses project directory');
    Check(SuiteRootForExecutable(Exe) = ExpandFileName(Repo), 'development root is detected by source marker');
    CopySelf(Installed + '/multicnc' + ExtractFileExt(Exe));
    Check(ExpandFileName(ToolExecutable(T, Repo, Installed)) = ExpandFileName(Installed + '/multicnc' + ExtractFileExt(Exe)), 'installed binary has priority');
    Artifact := Project + '/arquivo com espacos.nc'; S.Text := 'G0 X10'; S.SaveToFile(Artifact);
    Check(TSuiteLauncher.LaunchArtifact(T, Repo, Project, 'arquivo com espacos.nc', ErrorText), 'launcher accepts real artifact: ' + ErrorText);
    Start := GetTickCount64;
    while not FileExists(Project + '/args.txt') and (GetTickCount64 - Start < 5000) do Sleep(10);
    Check(FileExists(Project + '/args.txt'), 'child receives context');
    S.LoadFromFile(Project + '/args.txt');
    Check((S.Count = 4) and (S[0] = '--project') and (S[1] = Project) and
      (S[2] = '--file') and (S[3] = ExpandFileName(Artifact)), 'spaces and absolute file context survive launch');
    Check(not TSuiteLauncher.LaunchArtifact(T, Repo, Project, 'missing.nc', ErrorText), 'missing artifact is rejected');
    Check(Pos('Arquivo nao encontrado', ErrorText) > 0, 'specific missing-file feedback');
    Writeln('Launcher delivery: OK (installed/development paths, project, file, spaces, missing artifact)');
  finally
    R.Free; S.Free; DeleteFile(Artifact); DeleteFile(Project + '/args.txt'); RemoveDir(Project);
    DeleteFile(Exe); RemoveDir(Repo + '/src/app'); RemoveDir(Repo + '/src');
    DeleteFile(Repo + '/multisuite/src/core/multisuite_registry.pas'); RemoveDir(Repo + '/multisuite/src/core');
    RemoveDir(Repo + '/multisuite/src'); RemoveDir(Repo + '/multisuite'); RemoveDir(Repo);
    DeleteFile(Installed + '/multicnc' + ExtractFileExt(Exe)); RemoveDir(Installed); RemoveDir(Base);
  end;
end.
