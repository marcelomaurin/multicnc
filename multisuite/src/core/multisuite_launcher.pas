unit multisuite_launcher;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Process, multisuite_types, multisuite_paths;
type TSuiteLauncher = class
public
  class function Launch(const Tool: TSuiteToolInfo; const SuiteRoot, ProjectRoot: string; out Err: string): Boolean; static;
  class function LaunchArtifact(const Tool: TSuiteToolInfo; const SuiteRoot, ProjectRoot, ArtifactFile: string; out Err: string): Boolean; static;
end;
implementation
function RunTool(const Tool: TSuiteToolInfo; const SuiteRoot, ProjectRoot, ArtifactFile: string; out Err: string): Boolean;
var P: TProcess; Exe, AF: string;
begin
  Result := False; Err := '';
  Exe := ToolExecutable(Tool, SuiteRoot, ExtractFilePath(ParamStr(0)));
  if not FileExists(Exe) then begin Err := 'Executavel nao encontrado: ' + Exe; Exit; end;
  AF := ArtifactFile;
  if AF <> '' then begin
    if (ProjectRoot <> '') and (ExtractFileDrive(AF) = '') and not (AF[1] in ['/', '\']) then
      AF := ExpandFileName(IncludeTrailingPathDelimiter(ProjectRoot) + AF);
    if not FileExists(AF) then begin Err := 'Arquivo nao encontrado: ' + AF; Exit; end;
  end;
  P := TProcess.Create(nil);
  try
    try
      P.Executable := Exe;
      if ProjectRoot <> '' then begin P.Parameters.Add('--project'); P.Parameters.Add(ProjectRoot); end;
      if AF <> '' then begin P.Parameters.Add('--file'); P.Parameters.Add(AF); end;
      P.Options := []; P.Execute; Result := True;
    except on E: Exception do Err := E.Message; end;
  finally P.Free; end;
end;
class function TSuiteLauncher.Launch(const Tool: TSuiteToolInfo; const SuiteRoot, ProjectRoot: string; out Err: string): Boolean;
begin Result := RunTool(Tool, SuiteRoot, ProjectRoot, '', Err); end;
class function TSuiteLauncher.LaunchArtifact(const Tool: TSuiteToolInfo; const SuiteRoot, ProjectRoot, ArtifactFile: string; out Err: string): Boolean;
begin Result := RunTool(Tool, SuiteRoot, ProjectRoot, ArtifactFile, Err); end;
end.
