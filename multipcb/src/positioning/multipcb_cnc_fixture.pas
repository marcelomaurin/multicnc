unit multipcb_cnc_fixture;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,multipcb_cnc_position;
type
 TFixtureZone=record X,Y,W,H:Double;Name:string;end;
 TPCBFixture=class
 private FZones:array of TFixtureZone;
 public WorkWidth,WorkHeight,SafeMargin:Double;procedure AddKeepOut(const N:string;X,Y,W,H:Double);
  function PointAllowed(const P:TPCBPoint):Boolean;function ValidateBoard(P:TPCBPlacement;Errors:TStrings):Boolean;
 end;
implementation
procedure TPCBFixture.AddKeepOut(const N:string;X,Y,W,H:Double);var I:Integer;begin I:=Length(FZones);SetLength(FZones,I+1);FZones[I].Name:=N;FZones[I].X:=X;FZones[I].Y:=Y;FZones[I].W:=W;FZones[I].H:=H;end;
function TPCBFixture.PointAllowed(const P:TPCBPoint):Boolean;var I:Integer;begin Result:=(P.X>=SafeMargin)and(P.Y>=SafeMargin)and(P.X<=WorkWidth-SafeMargin)and(P.Y<=WorkHeight-SafeMargin);if not Result then Exit;for I:=0 to High(FZones)do if(P.X>=FZones[I].X)and(P.X<=FZones[I].X+FZones[I].W)and(P.Y>=FZones[I].Y)and(P.Y<=FZones[I].Y+FZones[I].H)then Exit(False);end;
function TPCBFixture.ValidateBoard(P:TPCBPlacement;Errors:TStrings):Boolean;var A,B,C,D:TPCBPoint;begin Errors.Clear;A.X:=0;A.Y:=0;B.X:=P.BoardWidth;B.Y:=0;C.X:=P.BoardWidth;C.Y:=P.BoardHeight;D.X:=0;D.Y:=P.BoardHeight;A:=P.Transform(A);B:=P.Transform(B);C:=P.Transform(C);D:=P.Transform(D);if not PointAllowed(A)then Errors.Add('Canto 1 fora da area segura');if not PointAllowed(B)then Errors.Add('Canto 2 fora da area segura');if not PointAllowed(C)then Errors.Add('Canto 3 fora da area segura');if not PointAllowed(D)then Errors.Add('Canto 4 fora da area segura');Result:=Errors.Count=0;end;
end.
