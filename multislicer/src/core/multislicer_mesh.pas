unit multislicer_mesh;
{$mode objfpc}{$H+}
interface
uses SysUtils,multislicer_types;
type TMesh=class
 private FTriangles:array of TTriangle;
 public procedure Clear;procedure Add(const T:TTriangle);function Count:Integer;function Triangle(I:Integer):TTriangle;function MinZ:Double;function MaxZ:Double;
 end;
implementation
procedure TMesh.Clear;begin SetLength(FTriangles,0);end;
procedure TMesh.Add(const T:TTriangle);var N:Integer;begin N:=Length(FTriangles);SetLength(FTriangles,N+1);FTriangles[N]:=T;end;
function TMesh.Count:Integer;begin Result:=Length(FTriangles);end;
function TMesh.Triangle(I:Integer):TTriangle;begin Result:=FTriangles[I];end;
function TMesh.MinZ:Double;var I:Integer;T:TTriangle;begin if Count=0 then Exit(0);Result:=FTriangles[0].A.Z;for I:=0 to Count-1 do begin T:=FTriangles[I];if T.A.Z<Result then Result:=T.A.Z;if T.B.Z<Result then Result:=T.B.Z;if T.C.Z<Result then Result:=T.C.Z;end;end;
function TMesh.MaxZ:Double;var I:Integer;T:TTriangle;begin if Count=0 then Exit(0);Result:=FTriangles[0].A.Z;for I:=0 to Count-1 do begin T:=FTriangles[I];if T.A.Z>Result then Result:=T.A.Z;if T.B.Z>Result then Result:=T.B.Z;if T.C.Z>Result then Result:=T.C.Z;end;end;
end.
