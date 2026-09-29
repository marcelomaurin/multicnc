unit multisuite_launcher;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,Process,multisuite_types;
type TSuiteLauncher=class
 private class function ResolveExecutable(const Tool:TSuiteToolInfo;const SuiteRoot:string):string;static;
 public
  class function Launch(const Tool:TSuiteToolInfo;const SuiteRoot,ProjectRoot:string;out Err:string):Boolean;static;
  class function LaunchArtifact(const Tool:TSuiteToolInfo;const SuiteRoot,ProjectRoot,ArtifactFile:string;out Err:string):Boolean;static;
 end;
implementation
class function TSuiteLauncher.ResolveExecutable(const Tool:TSuiteToolInfo;const SuiteRoot:string):string;
var Installed,Dev:string;
begin
 Installed:=IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)))+Tool.Executable;
 {$IFDEF Windows}Installed:=Installed+'.exe';{$ENDIF}
 if FileExists(Installed)then Exit(Installed);
 Dev:=IncludeTrailingPathDelimiter(SuiteRoot)+Tool.Executable;
 {$IFDEF Windows}Dev:=Dev+'.exe';{$ENDIF}
 if FileExists(Dev)then Exit(Dev);
 Result:=Installed;
end;
class function RunTool(const Tool:TSuiteToolInfo;const SuiteRoot,ProjectRoot,ArtifactFile:string;out Err:string):Boolean;var P:TProcess;Exe,AF:string;begin Result:=False;Err:='';Exe:=TSuiteLauncher.ResolveExecutable(Tool,SuiteRoot)if not FileExists(Exe)then begin Err:='Executavel nao encontrado: '+Exe;Exit;end;P:=TProcess.Create(nil);try P.Executable:=Exe;if ProjectRoot<>''then begin P.Parameters.Add('--project');P.Parameters.Add(ProjectRoot);end;if ArtifactFile<>''then begin AF:=ArtifactFile;if(ProjectRoot<>'')and(not FilenameIsAbsolute(AF))then AF:=ExpandFileName(IncludeTrailingPathDelimiter(ProjectRoot)+AF);P.Parameters.Add('--file');P.Parameters.Add(AF);end;P.Options:=[];P.Execute;Result:=True;except on E:Exception do Err:=E.Message;end;P.Free;end;
class function TSuiteLauncher.Launch(const Tool:TSuiteToolInfo;const SuiteRoot,ProjectRoot:string;out Err:string):Boolean;begin Result:=RunTool(Tool,SuiteRoot,ProjectRoot,'',Err);end;
class function TSuiteLauncher.LaunchArtifact(const Tool:TSuiteToolInfo;const SuiteRoot,ProjectRoot,ArtifactFile:string;out Err:string):Boolean;begin Result:=RunTool(Tool,SuiteRoot,ProjectRoot,ArtifactFile,Err);end;
end.
