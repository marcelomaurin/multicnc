unit multislicer_fragment;
{$mode objfpc}{$H+}
{ Corte de malha triangulada por plano alinhado a eixo.
  Reconstroi as faces de corte a partir das arestas de fronteira.
  Nao exporta malhas abertas: se a triangulacao nao conseguir fechar,
  retorna erro. Nao e um motor CSG geral para malhas invalidas. }
interface
uses Classes, SysUtils, Math, multislicer_types, multislicer_mesh;
function SplitMeshAxis(Source: TMesh; Axis: Integer; Cut: Double;
  out Below, Above: TMesh; out Reason: string): Boolean;
procedure SaveBinarySTL(Mesh: TMesh; const FileName: string);
implementation
type
  TVertices = array of TVec3;
  TEdge = record A,B: TVec3; end;
  TEdges = array of TEdge;
function Coord(const P:TVec3; Axis:Integer):Double;
begin case Axis of 0:Result:=P.X;1:Result:=P.Y;else Result:=P.Z;end;end;
function EqualP(const A,B:TVec3):Boolean;
begin Result:=(Abs(A.X-B.X)<1e-5) and (Abs(A.Y-B.Y)<1e-5) and (Abs(A.Z-B.Z)<1e-5);end;
procedure Append(var P:TVertices;const V:TVec3);
begin SetLength(P,Length(P)+1);P[High(P)]:=V;end;
procedure AddTri(M:TMesh;const A,B,C:TVec3);
var T:TTriangle;
begin
 if EqualP(A,B) or EqualP(B,C) or EqualP(C,A) then Exit;
 T.A:=A;T.B:=B;T.C:=C;M.Add(T);
end;
function Interp(const A,B:TVec3; Axis:Integer; Cut:Double):TVec3;
var F,D:Double;
begin
 D:=Coord(B,Axis)-Coord(A,Axis);
 if Abs(D)<1e-12 then F:=0 else F:=(Cut-Coord(A,Axis))/D;
 Result.X:=A.X+(B.X-A.X)*F;
 Result.Y:=A.Y+(B.Y-A.Y)*F;
 Result.Z:=A.Z+(B.Z-A.Z)*F;
end;
procedure ClipTriangle(M:TMesh;const T:TTriangle;Axis:Integer;Cut:Double;KeepBelow:Boolean);
var V,P:TVertices;I,J:Integer;InsideA,InsideB:Boolean;A,B,Q:TVec3;
begin
 SetLength(V,3);V[0]:=T.A;V[1]:=T.B;V[2]:=T.C;P:=nil;
 for I:=0 to 2 do begin
   J:=(I+1) mod 3; A:=V[I];B:=V[J];
   if KeepBelow then begin InsideA:=Coord(A,Axis)<=Cut+1e-8;InsideB:=Coord(B,Axis)<=Cut+1e-8;end
   else begin InsideA:=Coord(A,Axis)>=Cut-1e-8;InsideB:=Coord(B,Axis)>=Cut-1e-8;end;
   if InsideA then Append(P,A);
   if InsideA<>InsideB then begin Q:=Interp(A,B,Axis,Cut);Append(P,Q);end;
 end;
 for I:=1 to High(P)-1 do AddTri(M,P[0],P[I],P[I+1]);
end;
function OnPlane(const V:TVec3;Axis:Integer;Cut:Double):Boolean;
begin Result:=Abs(Coord(V,Axis)-Cut)<1e-5;end;
procedure BoundaryEdges(M:TMesh;Axis:Integer;Cut:Double;out Edges:TEdges);
var I,J,K:Integer;T:TTriangle;V:array[0..2]of TVec3;A,B:TVec3;Found:Boolean;
begin
 Edges:=nil;
 for I:=0 to M.Count-1 do begin
  T:=M.Triangle(I);V[0]:=T.A;V[1]:=T.B;V[2]:=T.C;
  for J:=0 to 2 do begin
   A:=V[J];B:=V[(J+1) mod 3];
   if not OnPlane(A,Axis,Cut) or not OnPlane(B,Axis,Cut) or EqualP(A,B) then Continue;
   Found:=False;
   for K:=0 to High(Edges) do
    if (EqualP(Edges[K].A,B) and EqualP(Edges[K].B,A)) then begin
      Edges[K]:=Edges[High(Edges)];SetLength(Edges,Length(Edges)-1);
      Found:=True;Break;
    end;
   if not Found then begin
    SetLength(Edges,Length(Edges)+1);
    Edges[High(Edges)].A:=A;Edges[High(Edges)].B:=B;
   end;
  end;
 end;
end;
function U(const V:TVec3;Axis:Integer):Double;
begin case Axis of 0:Result:=V.Y;1:Result:=V.X;else Result:=V.X;end;end;
function VCoord(const P:TVec3;Axis:Integer):Double;
begin case Axis of 0:Result:=P.Z;1:Result:=P.Z;else Result:=P.Y;end;end;
function Cross2(const A,B,C:TVec3;Axis:Integer):Double;
begin Result:=(U(B,Axis)-U(A,Axis))*(VCoord(C,Axis)-VCoord(A,Axis))-
(VCoord(B,Axis)-VCoord(A,Axis))*(U(C,Axis)-U(A,Axis));end;
function InTri(const P,A,B,C:TVec3;Axis:Integer):Boolean;
var X,Y,Z:Double;
begin X:=Cross2(A,B,P,Axis);Y:=Cross2(B,C,P,Axis);Z:=Cross2(C,A,P,Axis);
 Result:=((X>=-1e-9)and(Y>=-1e-9)and(Z>=-1e-9))or
 ((X<=1e-9)and(Y<=1e-9)and(Z<=1e-9));end;
function CapMesh(M:TMesh;Axis:Integer;Cut:Double;KeepBelow:Boolean;out Reason:string):Boolean;
var Edges:TEdges;Loop:TVertices;Used:array of Boolean;I,J,K,N,Q,Prev,Next,Index,Guard:Integer;
    A,B:TVec3;Area,Sign,Desired:Double;Poly:array of Integer;Ear,Contained:Boolean;
begin
 Result:=False;Reason:='';BoundaryEdges(M,Axis,Cut,Edges);
 Used:=nil;SetLength(Used,Length(Edges));
 for I:=0 to High(Edges) do begin
  if Used[I] then Continue;
  Loop:=nil;A:=Edges[I].A;B:=Edges[I].B;
  Append(Loop,A);Append(Loop,B);Used[I]:=True;
  Guard:=0;
  while not EqualP(B,A) do begin
   K:=-1;
   for J:=0 to High(Edges) do if not Used[J] and
     (EqualP(Edges[J].A,B) or EqualP(Edges[J].B,B)) then begin K:=J;Break;end;
   if K<0 then begin Reason:='Arestas abertas no plano de corte';Exit;end;
   if EqualP(Edges[K].A,B) then B:=Edges[K].B else B:=Edges[K].A;
   Used[K]:=True;Append(Loop,B);Inc(Guard);
   if Guard>Length(Edges)+1 then begin Reason:='Contorno de corte invalido';Exit;end;
  end;
  SetLength(Loop,Length(Loop)-1);
  if Length(Loop)<3 then Continue;
  Area:=0;
  for J:=0 to High(Loop) do Area:=Area+U(Loop[J],Axis)*VCoord(Loop[(J+1)mod Length(Loop)],Axis)
     -U(Loop[(J+1)mod Length(Loop)],Axis)*VCoord(Loop[J],Axis);
  if Abs(Area)<1e-9 then Continue;
  Sign:=1;if Area<0 then Sign:=-1;
  { Eixos: YZ normal +X; XZ normal -Y; XY normal +Z. }
  Desired:=1;if Axis=1 then Desired:=-1;
  if not KeepBelow then Desired:=-Desired;
  SetLength(Poly,Length(Loop));for J:=0 to High(Poly) do Poly[J]:=J;
  Guard:=0;
  while Length(Poly)>2 do begin
   Ear:=False;N:=Length(Poly);
   for J:=0 to N-1 do begin
    Prev:=Poly[(J+N-1)mod N];Index:=Poly[J];Next:=Poly[(J+1)mod N];
    if Cross2(Loop[Prev],Loop[Index],Loop[Next],Axis)*Sign<=1e-9 then Continue;
    Contained:=False;
    for Q:=0 to N-1 do if (Q<>(J+N-1)mod N)and(Q<>J)and(Q<>(J+1)mod N) then
      if InTri(Loop[Poly[Q]],Loop[Prev],Loop[Index],Loop[Next],Axis) then begin Contained:=True;Break;end;
    if Contained then Continue;
    if Desired*Sign>0 then AddTri(M,Loop[Prev],Loop[Index],Loop[Next])
    else AddTri(M,Loop[Next],Loop[Index],Loop[Prev]);
    for Q:=J to N-2 do Poly[Q]:=Poly[Q+1];
    SetLength(Poly,N-1);Ear:=True;Break;
   end;
   Inc(Guard);
   if not Ear or (Guard>Length(Loop)*Length(Loop)) then begin Reason:='Nao foi possivel triangular a face de corte';Exit;end;
  end;
 end;
 Result:=True;
end;
function SplitMeshAxis(Source:TMesh;Axis:Integer;Cut:Double;out Below,Above:TMesh;out Reason:string):Boolean;
var I:Integer;T:TTriangle;
begin
 Below:=nil;Above:=nil;Reason:='';Result:=False;
 if (Source=nil)or(Source.Count=0)or(Axis<0)or(Axis>2) then begin Reason:='Malha ou eixo invalido';Exit;end;
 Below:=TMesh.Create;Above:=TMesh.Create;
 try
  for I:=0 to Source.Count-1 do begin
   T:=Source.Triangle(I);ClipTriangle(Below,T,Axis,Cut,True);ClipTriangle(Above,T,Axis,Cut,False);
  end;
  if (Below.Count=0)or(Above.Count=0) then begin Reason:='Plano nao atravessa a peca';Exit;end;
  if not CapMesh(Below,Axis,Cut,True,Reason) then Exit;
  if not CapMesh(Above,Axis,Cut,False,Reason) then Exit;
  Result:=True;
 finally
  if not Result then begin FreeAndNil(Below);FreeAndNil(Above);end;
 end;
end;
procedure SaveBinarySTL(Mesh:TMesh;const FileName:string);
var F:TFileStream;Header:array[0..79]of Byte;Count:LongWord;I:Integer;T:TTriangle;
    N:array[0..2]of Single;P:array[0..8]of Single;Attr:Word;
begin
 F:=TFileStream.Create(FileName,fmCreate);
 try
  FillChar(Header,SizeOf(Header),0);F.WriteBuffer(Header,SizeOf(Header));
  Count:=Mesh.Count;F.WriteBuffer(Count,4);
  for I:=0 to Mesh.Count-1 do begin
   T:=Mesh.Triangle(I);FillChar(N,SizeOf(N),0);
   P[0]:=T.A.X;P[1]:=T.A.Y;P[2]:=T.A.Z;
   P[3]:=T.B.X;P[4]:=T.B.Y;P[5]:=T.B.Z;
   P[6]:=T.C.X;P[7]:=T.C.Y;P[8]:=T.C.Z;
   F.WriteBuffer(N,SizeOf(N));F.WriteBuffer(P,SizeOf(P));
   Attr:=0;F.WriteBuffer(Attr,2);
  end;
 finally F.Free;end;
end;
end.
