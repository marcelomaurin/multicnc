unit laserpcb_job;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,laserpcb_types;
type
 TLaserPCBJob=class
 private FPoints:array of TPathPoint;
 public Name:string;Width,Height:Double;Side:TPCBLayerSide;Mirror:Boolean;Profile:TLaserProfile;
  procedure Clear;procedure AddPoint(X,Y:Double;OnOff:Boolean);function Count:Integer;function Point(I:Integer):TPathPoint;procedure ApplyBottomMirror;
 end;
implementation
procedure TLaserPCBJob.Clear;begin SetLength(FPoints,0);end;
procedure TLaserPCBJob.AddPoint(X,Y:Double;OnOff:Boolean);var N:Integer;begin N:=Length(FPoints);SetLength(FPoints,N+1);FPoints[N].X:=X;FPoints[N].Y:=Y;FPoints[N].LaserOn:=OnOff;end;
function TLaserPCBJob.Count:Integer;begin Result:=Length(FPoints);end;
function TLaserPCBJob.Point(I:Integer):TPathPoint;begin Result:=FPoints[I];end;
procedure TLaserPCBJob.ApplyBottomMirror;var I:Integer;begin if not Mirror then Exit;for I:=0 to High(FPoints)do FPoints[I].X:=Width-FPoints[I].X;end;
end.
