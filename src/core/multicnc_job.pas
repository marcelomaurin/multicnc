unit multicnc_job;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,multicnc_interfaces;
type TJobState=(jsEmpty,jsReady,jsRunning,jsPaused,jsDone,jsCancelled,jsError);
 TMultiCNCJob=class
 private FLines:TStringList;FIndex:Integer;FState:TJobState;
 public constructor Create;destructor Destroy;override;
  function LoadFile(const FN:string):Boolean; function Start:Boolean;procedure Pause;procedure Resume;procedure Cancel;
  function NextLine(out L:string):Boolean; function Progress:Double;
  property State:TJobState read FState;
 end;
implementation
constructor TMultiCNCJob.Create;begin FLines:=TStringList.Create;FState:=jsEmpty;end;
destructor TMultiCNCJob.Destroy;begin FLines.Free;inherited;end;
function TMultiCNCJob.LoadFile(const FN:string):Boolean;begin Result:=FileExists(FN);if not Result then Exit;FLines.LoadFromFile(FN);FIndex:=0;FState:=jsReady;end;
function TMultiCNCJob.Start:Boolean;begin Result:=FLines.Count>0;if Result then begin FIndex:=0;FState:=jsRunning;end;end;
procedure TMultiCNCJob.Pause;begin if FState=jsRunning then FState:=jsPaused;end;
procedure TMultiCNCJob.Resume;begin if FState=jsPaused then FState:=jsRunning;end;
procedure TMultiCNCJob.Cancel;begin FState:=jsCancelled;end;
function TMultiCNCJob.NextLine(out L:string):Boolean;
begin Result:=False;L:='';if FState<>jsRunning then Exit;while FIndex<FLines.Count do begin L:=Trim(FLines[FIndex]);Inc(FIndex);if (L<>'')and(L[1]<>';') then Exit(True);end;FState:=jsDone;end;
function TMultiCNCJob.Progress:Double;begin if FLines.Count=0 then Exit(0);Result:=100.0*FIndex/FLines.Count;end;
end.
