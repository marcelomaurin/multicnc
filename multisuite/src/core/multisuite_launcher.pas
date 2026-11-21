unit multisuite_launcher;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Process, multisuite_types, multisuite_paths;
type TSuiteLauncher = class
public
  class function Launch(const Tool: TSuiteToolInfo; const SuiteRoot, ProjectRoot: string; out Err: string): Boolean; static;
  class function LaunchNew(const Tool: TSuiteToolInfo; const SuiteRoot, ProjectRoot, ArtifactFile, TaskFile: string; out Err: string): Boolean; static;
  class function BuildArguments(const ProjectRoot, ArtifactFile, TaskFile: string; IsNew: Boolean): TStringList; static;
  class function LaunchArtifact(const Tool: TSuiteToolInfo; const SuiteRoot, ProjectRoot, ArtifactFile: string; out Err: string; const TaskFile: string = ''): Boolean; static;
end;
implementation
class function TSuiteLauncher.BuildArguments(const ProjectRoot, ArtifactFile, TaskFile: string; IsNew: Boolean): TStringList;
begin
  Result := TStringList.Create;
  if ProjectRoot <> '' then begin Result.Add('--project'); Result.Add(ProjectRoot); end;
  if ArtifactFile <> '' then
  begin
    if IsNew then Result.Add('--new') else Result.Add('--file');
    Result.Add(ArtifactFile);
  end;
  if TaskFile <> '' then begin Result.Add('--task'); Result.Add(TaskFile); end;
end;
function RunTool(const Tool: TSuiteToolInfo; const SuiteRoot, ProjectRoot, ArtifactFile, TaskFile: string; IsNew: Boolean; out Err: string): Boolean;
var P: TProcess; Exe, AF: string; Args: TStringList;
begin
  Result := False; Err := '';
  Exe := ToolExecutable(Tool, SuiteRoot, ExtractFilePath(ParamStr(0)));
  if not FileExists(Exe) then begin Err := 'Executavel nao encontrado: ' + Exe; Exit; end;
  AF := ArtifactFile;
  if AF <> '' then begin
    if (ProjectRoot <> '') and (ExtractFileDrive(AF) = '') and not (AF[1] in ['/', '\']) then
      AF := ExpandFileName(IncludeTrailingPathDelimiter(ProjectRoot) + AF);
    if not IsNew and not FileExists(AF) then begin Err := 'Arquivo nao encontrado: ' + AF; Exit; end;
    if IsNew and FileExists(AF) then begin Err := 'Arquivo ja existe: ' + AF; Exit; end;
  end;
  P := TProcess.Create(nil);
  try
    try
      P.Executable := Exe;
      Args := TSuiteLauncher.BuildArguments(ProjectRoot, AF, TaskFile, IsNew);
      try P.Parameters.Assign(Args); finally Args.Free; end;
      P.Options := []; P.Execute; Result := True;
    except on E: Exception do Err := E.Message; end;
  finally P.Free; end;
end;
class function TSuiteLauncher.LaunchNew(const Tool: TSuiteToolInfo; const SuiteRoot, ProjectRoot, ArtifactFile, TaskFile: string; out Err: string): Boolean;
begin
  if (ArtifactFile = '') or (TaskFile = '') or not FileExists(TaskFile) then
  begin Err := 'Informe o artefato novo e o contexto da tarefa existente'; Exit(False); end;
  Result := RunTool(Tool, SuiteRoot, ProjectRoot, ArtifactFile, TaskFile, True, Err);
end;
class function TSuiteLauncher.Launch(const Tool: TSuiteToolInfo; const SuiteRoot, ProjectRoot: string; out Err: string): Boolean;
begin Result := RunTool(Tool, SuiteRoot, ProjectRoot, '', '', False, Err); end;
class function TSuiteLauncher.LaunchArtifact(const Tool: TSuiteToolInfo; const SuiteRoot, ProjectRoot, ArtifactFile: string; out Err: string; const TaskFile: string): Boolean;
begin Result := RunTool(Tool, SuiteRoot, ProjectRoot, ArtifactFile, TaskFile, False, Err); end;
end.
