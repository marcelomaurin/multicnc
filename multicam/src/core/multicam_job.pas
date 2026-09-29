unit multicam_job;
{$mode objfpc}{$H+}
interface
uses SysUtils,multicam_types;
type TCamJob=class
 private FMoves:array of TPathMove;
 public Name:string;Tool:TTool;Stock:TStock;Settings:TCamSettings;Operation:TCamOperation;
  procedure Clear;procedure AddMove(X,Y,Z:Double;Rapid:Boolean);function Count:Integer;function Move(I:Integer):TPathMove;
 end;
implementation
procedure TCamJob.Clear;begin SetLength(FMoves,0);end;
procedure TCamJob.AddMove(X,Y,Z:Double;Rapid:Boolean);var N:Integer;begin N:=Length(FMoves);SetLength(FMoves,N+1);FMoves[N].P.X:=X;FMoves[N].P.Y:=Y;FMoves[N].P.Z:=Z;FMoves[N].Rapid:=Rapid;FMoves[N].SpindleOn:=not Rapid;end;
function TCamJob.Count:Integer;begin Result:=Length(FMoves);end;
function TCamJob.Move(I:Integer):TPathMove;begin Result:=FMoves[I];end;
end.
