unit multipcb_heightmap;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,Math;
type
 TProbePoint=record X,Y,Z:Double;Valid:Boolean;end;
 THeightMap=class
 private FPoints:array of TProbePoint;
 public procedure Clear;procedure Add(X,Y,Z:Double);function Count:Integer;function Point(I:Integer):TProbePoint;
  function InterpolateIDW(X,Y:Double;out Z:Double):Boolean;function Validate(Errors:TStrings):Boolean;
 end;
implementation
procedure THeightMap.Clear;begin SetLength(FPoints,0);end;
procedure THeightMap.Add(X,Y,Z:Double);var N:Integer;begin N:=Length(FPoints);SetLength(FPoints,N+1);FPoints[N].X:=X;FPoints[N].Y:=Y;FPoints[N].Z:=Z;FPoints[N].Valid:=True;end;
function THeightMap.Count:Integer;begin Result:=Length(FPoints);end;
function THeightMap.Point(I:Integer):TProbePoint;begin Result:=FPoints[I];end;
function THeightMap.InterpolateIDW(X,Y:Double;out Z:Double):Boolean;
var I:Integer;P:TProbePoint;D,W,SW,SZ:Double;
begin Result:=False;Z:=0;SW:=0;SZ:=0;for I:=0 to High(FPoints)do begin P:=FPoints[I];if not P.Valid then Continue;D:=Hypot(X-P.X,Y-P.Y);if D<1e-9 then begin Z:=P.Z;Exit(True);end;W:=1/(D*D);SW:=SW+W;SZ:=SZ+W*P.Z;end;if SW>0 then begin Z:=SZ/SW;Result:=True;end;end;
function THeightMap.Validate(Errors:TStrings):Boolean;var I:Integer;begin Errors.Clear;if Count<3 then Errors.Add('Height-map requer pelo menos 3 pontos');for I:=0 to Count-1 do if not FPoints[I].Valid then Errors.Add('Ponto de probe invalido: '+IntToStr(I));Result:=Errors.Count=0;end;
end.
