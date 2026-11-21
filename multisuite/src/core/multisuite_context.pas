unit multisuite_context;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type TSuiteContext = record
  ProjectRoot, FileName, NewFileName, TaskFile: string;
end;
function ParseSuiteContext(const Args: array of string): TSuiteContext;
function ReadSuiteContext: TSuiteContext;
function ContextCaption(const Base: string; const C: TSuiteContext): string;
implementation
function ParseSuiteContext(const Args: array of string): TSuiteContext;
var I: Integer; Key, Value: string;
begin
  Result := Default(TSuiteContext);
  I := 0;
  while I <= High(Args) do
  begin
    Key := LowerCase(Args[I]);
    if (Key = '--project') or (Key = '--file') or (Key = '--new') or (Key = '--task') then
    begin
      if (I < High(Args)) and (Copy(Args[I+1], 1, 2) <> '--') and (Args[I+1] <> '') then
      begin
        Inc(I); Value := ExpandFileName(Args[I]);
        if Key = '--project' then Result.ProjectRoot := Value
        else if Key = '--file' then Result.FileName := Value
        else if Key = '--new' then Result.NewFileName := Value
        else Result.TaskFile := Value;
      end;
    end;
    Inc(I);
  end;
  { An existing document always takes precedence over a new target. }
  if Result.FileName <> '' then Result.NewFileName := '';
end;
function ReadSuiteContext: TSuiteContext;
var A: array of string; I: Integer;
begin
  SetLength(A, ParamCount);
  for I := 1 to ParamCount do A[I-1] := ParamStr(I);
  Result := ParseSuiteContext(A);
end;
function ContextCaption(const Base: string; const C: TSuiteContext): string;
begin
  Result := Base;
  if C.FileName <> '' then Result := Result + ' - ' + ExtractFileName(C.FileName)
  else if C.NewFileName <> '' then Result := Result + ' - ' + ExtractFileName(C.NewFileName)
  else if C.ProjectRoot <> '' then Result := Result + ' - ' + ExtractFileName(ExcludeTrailingPathDelimiter(C.ProjectRoot));
end;
end.
