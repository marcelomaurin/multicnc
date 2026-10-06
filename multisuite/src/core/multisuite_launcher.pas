unit multisuite_launcher;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,Process,LazFileUtils,multisuite_types;
type TSuiteLauncher=class
 private class function ResolveExecutable(const Tool:TSuiteToolInfo;const SuiteRoot:string):string;static;
 public
  class function Launch(const Tool:TSuiteToolInfo;const SuiteRoot,ProjectRoot:string;out Err:string):Boolean;static;
  class function LaunchArtifact(const Tool:TSuiteToolInfo;const SuiteRoot,ProjectRoot,ArtifactFile:string;out Err:string):Boolean;static;
 end;
implementation

function WithExeExt(const S:string):string;
begin
 Result:=S;
 {$IFDEF Windows}Result:=Result+'.exe';{$ENDIF}
end;

{ Ordem de busca do executavel:
  1. pasta do proprio executavel em uso (instalacao: tudo na mesma pasta);
  2. pasta do projeto Lazarus da ferramenta (ProjectFile do registro), ex.:
     <raiz>/multicad/src/app/multicad.exe  (arvore de desenvolvimento);
  3. <raiz>/bin;
  4. <raiz>. }
class function TSuiteLauncher.ResolveExecutable(const Tool:TSuiteToolInfo;const SuiteRoot:string):string;
var Installed,R,C:string;
begin
 Installed:=WithExeExt(IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0)))+Tool.Executable);
 if FileExists(Installed)then Exit(Installed);
 if SuiteRoot<>''then
 begin
  R:=IncludeTrailingPathDelimiter(SuiteRoot);
  if Tool.ProjectFile<>''then
  begin
   C:=WithExeExt(R+ExtractFilePath(SetDirSeparators(Tool.ProjectFile))+Tool.Executable);
   if FileExists(C)then Exit(C);
  end;
  C:=WithExeExt(R+'bin'+DirectorySeparator+Tool.Executable);
  if FileExists(C)then Exit(C);
  C:=WithExeExt(R+Tool.Executable);
  if FileExists(C)then Exit(C);
 end;
 Result:=Installed;
end;
class function RunTool(const Tool:TSuiteToolInfo;const SuiteRoot,ProjectRoot,ArtifactFile:string;out Err:string):Boolean;var P:TProcess;Exe,AF:string;begin Result:=False;Err:='';Exe:=TSuiteLauncher.ResolveExecutable(Tool,SuiteRoot);if not FileExists(Exe)then begin Err:='Executavel nao encontrado: '+Exe;Exit;end;P:=TProcess.Create(nil);try P.Executable:=Exe;if ProjectRoot<>''then begin P.Parameters.Add('--project');P.Parameters.Add(ProjectRoot);end;if ArtifactFile<>''then begin AF:=ArtifactFile;if(ProjectRoot<>'')and(not FilenameIsAbsolute(AF))then AF:=ExpandFileName(IncludeTrailingPathDelimiter(ProjectRoot)+AF);P.Parameters.Add('--file');P.Parameters.Add(AF);end;P.Options:=[];P.Execute;Result:=True;except on E:Exception do Err:=E.Message;end;P.Free;end;
class function TSuiteLauncher.Launch(const Tool:TSuiteToolInfo;const SuiteRoot,ProjectRoot:string;out Err:string):Boolean;begin Result:=RunTool(Tool,SuiteRoot,ProjectRoot,'',Err);end;
class function TSuiteLauncher.LaunchArtifact(const Tool:TSuiteToolInfo;const SuiteRoot,ProjectRoot,ArtifactFile:string;out Err:string):Boolean;begin Result:=RunTool(Tool,SuiteRoot,ProjectRoot,ArtifactFile,Err);end;
end.
