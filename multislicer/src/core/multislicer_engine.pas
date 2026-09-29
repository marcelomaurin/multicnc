unit multislicer_engine;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,Math,multislicer_types,multislicer_mesh;
type
 TSliceLayer=class public Z:Double;Segments:array of TSegment2;procedure Add(const S:TSegment2);end;
 TSlicer=class
 private function Edge(const A,B:TVec3;Z:Double;out P:TVec2):Boolean;
 public procedure Slice(M:TMesh;LayerHeight:Double;Layers:TList);
 end;
implementation
procedure TSliceLayer.Add(const S:TSegment2);var N:Integer;begin N:=Length(Segments);SetLength(Segments,N+1);Segments[N]:=S;end;
function TSlicer.Edge(const A,B:TVec3;Z:Double;out P:TVec2):Boolean;var T:Double;
begin Result:=False;if SameValue(A.Z,B.Z)then Exit;if(Z<Min(A.Z,B.Z))or(Z>Max(A.Z,B.Z))then Exit;T:=(Z-A.Z)/(B.Z-A.Z);P.X:=A.X+T*(B.X-A.X);P.Y:=A.Y+T*(B.Y-A.Y);Result:=True;end;
procedure TSlicer.Slice(M:TMesh;LayerHeight:Double;Layers:TList);
var Z,ZMax:Double;I,N:Integer;T:TTriangle;P:array[0..2]of TVec2;S:TSegment2;L:TSliceLayer;
begin if LayerHeight<=0 then Exit;Z:=M.MinZ+LayerHeight;ZMax:=M.MaxZ;while Z<=ZMax+1e-9 do begin L:=TSliceLayer.Create;L.Z:=Z;for I:=0 to M.Count-1 do begin T:=M.Triangle(I);N:=0;if Edge(T.A,T.B,Z,P[N])then Inc(N);if(N<2)and Edge(T.B,T.C,Z,P[N])then Inc(N);if(N<2)and Edge(T.C,T.A,Z,P[N])then Inc(N);if N=2 then begin S.A:=P[0];S.B:=P[1];L.Add(S);end;end;Layers.Add(L);Z:=Z+LayerHeight;end;end;
end.
