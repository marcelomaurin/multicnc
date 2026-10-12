unit multislicer_mesh;
{$mode objfpc}{$H+}
{ Malha de triangulos do MultiSlicer. Cresce em blocos (malhas de centenas de
  milhares de triangulos carregam sem realocar a cada triangulo). }
interface
uses SysUtils,multislicer_types;
type TMesh=class
 private FTriangles:array of TTriangle;FCount:Integer;
  procedure SetCapacity(N:Integer);function GetCapacity:Integer;
 public procedure Clear;procedure Add(const T:TTriangle);function Count:Integer;function Triangle(I:Integer):TTriangle;
  procedure SetTriangle(I:Integer;const T:TTriangle);function MinZ:Double;function MaxZ:Double;
  property Capacity:Integer read GetCapacity write SetCapacity;
 end;
implementation
procedure TMesh.SetCapacity(N:Integer);begin if N<FCount then N:=FCount;SetLength(FTriangles,N);end;
function TMesh.GetCapacity:Integer;begin Result:=Length(FTriangles);end;
procedure TMesh.Clear;begin SetLength(FTriangles,0);FCount:=0;end;
procedure TMesh.Add(const T:TTriangle);begin if FCount=Length(FTriangles)then begin if FCount<64 then SetLength(FTriangles,64)else SetLength(FTriangles,FCount*2);end;FTriangles[FCount]:=T;Inc(FCount);end;
function TMesh.Count:Integer;begin Result:=FCount;end;
function TMesh.Triangle(I:Integer):TTriangle;begin Result:=FTriangles[I];end;
procedure TMesh.SetTriangle(I:Integer;const T:TTriangle);begin FTriangles[I]:=T;end;
function TMesh.MinZ:Double;var I:Integer;T:TTriangle;begin if FCount=0 then Exit(0);Result:=FTriangles[0].A.Z;for I:=0 to FCount-1 do begin T:=FTriangles[I];if T.A.Z<Result then Result:=T.A.Z;if T.B.Z<Result then Result:=T.B.Z;if T.C.Z<Result then Result:=T.C.Z;end;end;
function TMesh.MaxZ:Double;var I:Integer;T:TTriangle;begin if FCount=0 then Exit(0);Result:=FTriangles[0].A.Z;for I:=0 to FCount-1 do begin T:=FTriangles[I];if T.A.Z>Result then Result:=T.A.Z;if T.B.Z>Result then Result:=T.B.Z;if T.C.Z>Result then Result:=T.C.Z;end;end;
end.
