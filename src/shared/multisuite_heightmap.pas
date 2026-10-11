unit multisuite_heightmap;
{$mode objfpc}{$H+}
{ Height-map de superficie obtido por probing.

  Interpolacao:
  - Interpolate: metodo recomendado. Quando os pontos formam uma grade
    retangular completa (caso tipico de autolevel em PCB), usa interpolacao
    bilinear por celula - a mesma abordagem dos senders modernos (bCNC,
    Candle, cncjs autolevel). Fora da grade, ou com pontos esparsos, recai
    para IDW (inverse distance weighting).
  - InterpolateIDW: mantido por compatibilidade. }
interface
uses Classes,SysUtils,Math;
type
 TProbePoint=record X,Y,Z:Double;Valid:Boolean;end;
 THeightMap=class
 private
  FPoints:array of TProbePoint;
  FGridDirty:Boolean;
  FGridOK:Boolean;
  FGX,FGY:array of Double;
  FGZ:array of Double; // FGZ[iy*Length(FGX)+ix]
  procedure BuildGrid;
 public
  procedure Clear;
  procedure Add(X,Y,Z:Double);
  function Count:Integer;
  function Point(I:Integer):TProbePoint;
  function InterpolateIDW(X,Y:Double;out Z:Double):Boolean;
  function InterpolateBilinear(X,Y:Double;out Z:Double):Boolean;
  function Interpolate(X,Y:Double;out Z:Double):Boolean;
  function IsRegularGrid:Boolean;
  function Validate(Errors:TStrings):Boolean;
 end;
implementation

const GRID_EPS=1e-6;

procedure THeightMap.Clear;begin SetLength(FPoints,0);FGridDirty:=True;end;

procedure THeightMap.Add(X,Y,Z:Double);
var N:Integer;
begin
 N:=Length(FPoints);SetLength(FPoints,N+1);
 FPoints[N].X:=X;FPoints[N].Y:=Y;FPoints[N].Z:=Z;FPoints[N].Valid:=True;
 FGridDirty:=True;
end;

function THeightMap.Count:Integer;begin Result:=Length(FPoints);end;
function THeightMap.Point(I:Integer):TProbePoint;begin Result:=FPoints[I];end;

procedure InsertSorted(var A:array of Double;var N:Integer;V:Double);
var I,J:Integer;
begin
 for I:=0 to N-1 do if Abs(A[I]-V)<GRID_EPS then Exit;
 I:=N;while(I>0)and(A[I-1]>V)do Dec(I);
 for J:=N downto I+1 do A[J]:=A[J-1];
 A[I]:=V;Inc(N);
end;

function IndexOf(const A:array of Double;V:Double):Integer;
var I:Integer;
begin
 for I:=0 to High(A) do if Abs(A[I]-V)<GRID_EPS then Exit(I);
 Result:=-1;
end;

procedure THeightMap.BuildGrid;
var I,NX,NY,IX,IY,Valid:Integer;Filled:array of Boolean;
begin
 FGridDirty:=False;FGridOK:=False;
 SetLength(FGX,Length(FPoints));SetLength(FGY,Length(FPoints));
 NX:=0;NY:=0;Valid:=0;
 for I:=0 to High(FPoints) do if FPoints[I].Valid then begin
  InsertSorted(FGX,NX,FPoints[I].X);InsertSorted(FGY,NY,FPoints[I].Y);Inc(Valid);
 end;
 SetLength(FGX,NX);SetLength(FGY,NY);
 if(NX<2)or(NY<2)or(NX*NY<>Valid)then Exit;
 SetLength(FGZ,NX*NY);SetLength(Filled,NX*NY);
 for I:=0 to High(FPoints) do if FPoints[I].Valid then begin
  IX:=IndexOf(FGX,FPoints[I].X);IY:=IndexOf(FGY,FPoints[I].Y);
  if Filled[IY*NX+IX] then Exit; // ponto duplicado: nao e grade limpa
  Filled[IY*NX+IX]:=True;FGZ[IY*NX+IX]:=FPoints[I].Z;
 end;
 for I:=0 to High(Filled) do if not Filled[I] then Exit;
 FGridOK:=True;
end;

function THeightMap.IsRegularGrid:Boolean;
begin
 if FGridDirty then BuildGrid;
 Result:=FGridOK;
end;

function THeightMap.InterpolateBilinear(X,Y:Double;out Z:Double):Boolean;
var IX,IY,NX:Integer;TX,TY,Z00,Z10,Z01,Z11:Double;
begin
 Z:=0;Result:=False;
 if not IsRegularGrid then Exit;
 NX:=Length(FGX);
 if(X<FGX[0]-GRID_EPS)or(X>FGX[High(FGX)]+GRID_EPS)or
   (Y<FGY[0]-GRID_EPS)or(Y>FGY[High(FGY)]+GRID_EPS)then Exit;
 IX:=0;while(IX<High(FGX)-1)and(X>FGX[IX+1])do Inc(IX);
 IY:=0;while(IY<High(FGY)-1)and(Y>FGY[IY+1])do Inc(IY);
 TX:=EnsureRange((X-FGX[IX])/(FGX[IX+1]-FGX[IX]),0,1);
 TY:=EnsureRange((Y-FGY[IY])/(FGY[IY+1]-FGY[IY]),0,1);
 Z00:=FGZ[IY*NX+IX];Z10:=FGZ[IY*NX+IX+1];
 Z01:=FGZ[(IY+1)*NX+IX];Z11:=FGZ[(IY+1)*NX+IX+1];
 Z:=(Z00*(1-TX)+Z10*TX)*(1-TY)+(Z01*(1-TX)+Z11*TX)*TY;
 Result:=True;
end;

function THeightMap.InterpolateIDW(X,Y:Double;out Z:Double):Boolean;
var I:Integer;P:TProbePoint;D,W,SW,SZ:Double;
begin
 Result:=False;Z:=0;SW:=0;SZ:=0;
 for I:=0 to High(FPoints)do begin
  P:=FPoints[I];if not P.Valid then Continue;
  D:=Hypot(X-P.X,Y-P.Y);
  if D<1e-9 then begin Z:=P.Z;Exit(True);end;
  W:=1/(D*D);SW:=SW+W;SZ:=SZ+W*P.Z;
 end;
 if SW>0 then begin Z:=SZ/SW;Result:=True;end;
end;

function THeightMap.Interpolate(X,Y:Double;out Z:Double):Boolean;
begin
 Result:=InterpolateBilinear(X,Y,Z);
 if not Result then Result:=InterpolateIDW(X,Y,Z);
end;

function THeightMap.Validate(Errors:TStrings):Boolean;
var I:Integer;
begin
 Errors.Clear;
 if Count<3 then Errors.Add('Height-map requer pelo menos 3 pontos');
 for I:=0 to Count-1 do if not FPoints[I].Valid then Errors.Add('Ponto de probe invalido: '+IntToStr(I));
 Result:=Errors.Count=0;
end;

end.
