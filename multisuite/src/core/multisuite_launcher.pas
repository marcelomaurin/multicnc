unit multisuite_launcher;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,Process,multisuite_types;
type TSuiteLauncher=class public class function Launch(const Tool:TSuiteToolInfo;const SuiteRoot,ProjectRoot:string;out Err:string):Boolean;static;end;
implementation
class function TSuiteLauncher.Launch(const Tool:TSuiteToolInfo;const SuiteRoot,ProjectRoot:string;out Err:string):Boolean;var P:TProcess;Exe:string;begin Result:=False;Err:='';Exe:=IncludeTrailingPathDelimiter(SuiteRoot)+Tool.Executable;{$IFDEF Windows}Exe:=Exe+'.exe';{$ENDIF}if not FileExists(Exe)then begin Err:='Executavel nao encontrado: '+Exe;Exit;end;P:=TProcess.Create(nil);try P.Executable:=Exe;if ProjectRoot<>''then begin P.Parameters.Add('--project');P.Parameters.Add(ProjectRoot);end;P.Options:=[];P.Execute;Result:=True;except on E:Exception do Err:=E.Message;end;P.Free;end;
end.
