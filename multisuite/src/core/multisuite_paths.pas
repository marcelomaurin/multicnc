unit multisuite_paths;
{$mode objfpc}{$H+}
interface
uses SysUtils, multisuite_types;
function SuiteRootForExecutable(const Executable: string): string;
function ToolExecutable(const Tool: TSuiteToolInfo; const SuiteRoot, ExecutableDir: string): string;
function TestCenterExecutable(const SuiteRoot, ExecutableDir: string): string;
function SuiteConfigDir: string;
implementation
function ExeName(const S: string): string;
begin
  Result := S;
  {$IFDEF Windows}Result := Result + '.exe';{$ENDIF}
end;
function SuiteRootForExecutable(const Executable: string): string;
var Dir, Parent: string;
begin
  Result := ExtractFileDir(ExpandFileName(Executable)); Dir := Result;
  repeat
    if FileExists(IncludeTrailingPathDelimiter(Dir) + 'multisuite/src/core/multisuite_registry.pas') then Exit(Dir);
    Parent := ExtractFileDir(Dir);
    if Parent = Dir then Break;
    Dir := Parent;
  until Dir = '';
  // Instalacao: executaveis lado a lado. Nunca presume que a raiz e '/'.
end;
function ToolExecutable(const Tool: TSuiteToolInfo; const SuiteRoot, ExecutableDir: string): string;
var Dev: string;
begin
  Result := IncludeTrailingPathDelimiter(ExecutableDir) + ExeName(Tool.Executable);
  if FileExists(Result) then Exit;
  Dev := IncludeTrailingPathDelimiter(SuiteRoot) + ExeName(Tool.Executable);
  if FileExists(Dev) then Exit(Dev);
  Dev := IncludeTrailingPathDelimiter(SuiteRoot) + ExtractFilePath(Tool.ProjectFile) + ExeName(Tool.Executable);
  if FileExists(Dev) then Exit(Dev);
end;
function TestCenterExecutable(const SuiteRoot, ExecutableDir: string): string;
begin
  Result := IncludeTrailingPathDelimiter(ExecutableDir) + ExeName('multisuite_test_center');
  if FileExists(Result) then Exit;
  Result := IncludeTrailingPathDelimiter(SuiteRoot) + 'multisuite/src/testing/' + ExeName('multisuite_test_center');
end;
function SuiteConfigDir: string;
begin
  Result := GetEnvironmentVariable('MULTISUITE_CONFIG_DIR');
  if Result = '' then Result := GetAppConfigDir(False);
  Result := IncludeTrailingPathDelimiter(ExpandFileName(Result));
end;
end.
