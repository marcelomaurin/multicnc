unit multicam_simulation_player;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,Math,multicam_types,multicam_job;
type TBeforeSimulationMove=function(Index:Integer):Boolean of object;
 TPlayerState=(psStopped,psPlaying,psPaused,psFinished);
 TSimulationPlayer=class
 private FBeforeMove:TBeforeSimulationMove;FJob:TCamJob;FIndex:Integer;FState:TPlayerState;FSpeed:Double;FPosition:TCamPoint;FOnChange:TNotifyEvent;procedure Changed;
 public property BeforeMove:TBeforeSimulationMove read FBeforeMove write FBeforeMove;procedure Load(AJob:TCamJob);procedure Play;procedure Pause;procedure Stop;function Step:Boolean;property State:TPlayerState read FState;property Speed:Double read FSpeed write FSpeed;property Index:Integer read FIndex;property Position:TCamPoint read FPosition;property OnChange:TNotifyEvent read FOnChange write FOnChange;
 end;
implementation
procedure TSimulationPlayer.Changed;begin if Assigned(FOnChange)then FOnChange(Self);end;
procedure TSimulationPlayer.Load(AJob:TCamJob);begin FJob:=AJob;FIndex:=-1;FSpeed:=1;FState:=psStopped;FillChar(FPosition,SizeOf(FPosition),0);Changed;end;
procedure TSimulationPlayer.Play;begin if Assigned(FJob)and(FJob.Count>0)then begin if FState=psFinished then FIndex:=-1;FState:=psPlaying;Changed;end;end;
procedure TSimulationPlayer.Pause;begin if FState=psPlaying then begin FState:=psPaused;Changed;end;end;
procedure TSimulationPlayer.Stop;begin FIndex:=-1;FState:=psStopped;Changed;end;
function TSimulationPlayer.Step:Boolean;begin Result:=False;if not Assigned(FJob)then Exit;if FIndex+1>=FJob.Count then begin FState:=psFinished;Changed;Exit;end;if Assigned(FBeforeMove) and not FBeforeMove(FIndex+1)then begin FState:=psPaused;Changed;Exit;end;Inc(FIndex);FPosition:=FJob.Move(FIndex).P;Result:=True;Changed;if FIndex=FJob.Count-1 then FState:=psFinished;end;
end.
