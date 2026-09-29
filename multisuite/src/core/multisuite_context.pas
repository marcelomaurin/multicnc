unit multisuite_context;
{$mode objfpc}{$H+}
interface
uses SysUtils;
type TSuiteContext=record ProjectRoot,FileName:string;end;
function ReadSuiteContext:TSuiteContext;
implementation
function ReadSuiteContext:TSuiteContext;var I:Integer;begin Result.ProjectRoot:='';Result.FileName:='';I:=1;while I<=ParamCount do begin if SameText(ParamStr(I),'--project')and(I<ParamCount)then begin Inc(I);Result.ProjectRoot:=ExpandFileName(ParamStr(I));end else if SameText(ParamStr(I),'--file')and(I<ParamCount)then begin Inc(I);Result.FileName:=ExpandFileName(ParamStr(I));end;Inc(I);end;end;
end.
