unit multicad_csg;

{ MultiCAD - booleanas de solidos em malha por arvore BSP (decisao D2).

  Algoritmo classico de CSG por BSP (o mesmo do csg.js de Evan Wallace):
  cada solido vira uma arvore de planos; recortar um pelo outro e juntar.
  - Cada poligono guarda a face de origem: o resultado mantem os nomes
    estaveis ("Extrude1/fim", "Corte1/lat:5").
  - Construcao e recorte iterativos (sem recursao profunda na pilha).
  - Depois da booleana: triangulacao em leque (os poligonos sao convexos),
    solda de vertices, reparo de juncoes em T (vertice no meio da aresta do
    vizinho) e recalculo da normal das faces planas.
  - Resultado sempre conferido: malha fechada e orientada. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, Math, Generics.Collections, Classes, multicad_types, multicad_mesh,
  multicad_triangulate;

type
  TCadBoolOp = (boUnion, boDifference, boIntersection);

{ A op B. Devolve nova malha (pode ter volume zero, ex. diferenca que remove
  tudo). nil e AError em falha (resultado nao fechado). }
function CadBoolean(A, B: TCadMesh; Op: TCadBoolOp; out AError: string): TCadMesh;
{ Numero de pecas separadas (componentes conexos por vertices compartilhados). }
function CadMeshComponents(M: TCadMesh): Integer;
{ Separa em pecas; o chamador libera as malhas. }
function CadSplitComponents(M: TCadMesh): TList;
{ Recalcula a normal (Axis) das faces planas pela media dos triangulos. }
procedure CadRefreshPlaneNormals(M: TCadMesh);

var
  { Diagnostico: ultima malha de booleana que nao fechou (nao liberar). }
  CadCsgLastFailed: TCadMesh = nil;
  CadCsgDebug: Boolean = False;
  CadCsgDump: string = '';

implementation

const
  EPS = 1E-6;        { mm: tolerancia de classificacao contra o plano }
  WELD_TOL = 2E-4;   { mm: solda do resultado (ruido dos cortes BSP perto de vertices) }
  TJ_TOL = 2E-4;     { mm: vertice considerado sobre a aresta vizinha (= solda) }
  NOISE_AREA = 1E-3; { mm2: laco de face menor que isso e ruido }

type
  TVArr = array of TCadVec3;

  TPoly = record
    V: TVArr;
    Face: Integer;
    N: TCadVec3;
    W: Double;
  end;
  TPolyArr = array of TPoly;

  TNode = class
    HasPlane: Boolean;
    N: TCadVec3;
    W: Double;
    Polys: TPolyArr;
    Front, Back: TNode;
    destructor Destroy; override;
  end;

destructor TNode.Destroy;
begin
  Front.Free;
  Back.Free;
  inherited;
end;

procedure Push(var A: TPolyArr; var Count: Integer; const P: TPoly);
begin
  if Count >= Length(A) then
    SetLength(A, Max(16, Count * 2));
  A[Count] := P;
  Inc(Count);
end;

function MakePoly(const V: TVArr; AFace: Integer; out P: TPoly): Boolean;
var
  I: Integer;
  Nrm: TCadVec3;
begin
  P.V := V;
  P.Face := AFace;
  { normal de Newell: robusta para poligonos com vertices quase colineares }
  Nrm := V3(0, 0, 0);
  for I := 0 to High(V) do
    with V[I] do
    begin
      Nrm.X := Nrm.X + (Y - V[(I + 1) mod Length(V)].Y) * (Z + V[(I + 1) mod Length(V)].Z);
      Nrm.Y := Nrm.Y + (Z - V[(I + 1) mod Length(V)].Z) * (X + V[(I + 1) mod Length(V)].X);
      Nrm.Z := Nrm.Z + (X - V[(I + 1) mod Length(V)].X) * (Y + V[(I + 1) mod Length(V)].Y);
    end;
  Result := VLen(Nrm) > 1E-14;
  if not Result then
    Exit;
  P.N := VNorm(Nrm);
  P.W := VDot(P.N, V[0]);
end;

procedure FlipPoly(var P: TPoly);
var
  I, N: Integer;
  T: TCadVec3;
begin
  N := Length(P.V);
  for I := 0 to N div 2 - 1 do
  begin
    T := P.V[I];
    P.V[I] := P.V[N - 1 - I];
    P.V[N - 1 - I] := T;
  end;
  P.N := VNeg(P.N);
  P.W := -P.W;
end;

const
  COPLANAR = 0;
  FRONT = 1;
  BACK = 2;
  SPANNING = 3;

{ Divide P pelo plano (N, W). }
procedure SplitPoly(const N: TCadVec3; W: Double; const P: TPoly;
  var CoFront, CoBack, Fr, Bk: TPolyArr; var NCF, NCB, NF, NB: Integer);
var
  I, J, PType, Ti, Tj: Integer;
  Types: array of Integer;
  T: Double;
  Vi, Vj, Vm: TCadVec3;
  FV, BV: TVArr;
  NFv, NBv: Integer;
  Q: TPoly;
begin
  PType := 0;
  SetLength(Types, Length(P.V));
  for I := 0 to High(P.V) do
  begin
    T := VDot(N, P.V[I]) - W;
    if T < -EPS then
      Types[I] := BACK
    else if T > EPS then
      Types[I] := FRONT
    else
      Types[I] := COPLANAR;
    PType := PType or Types[I];
  end;
  case PType of
    COPLANAR:
      if VDot(N, P.N) > 0 then
        Push(CoFront, NCF, P)
      else
        Push(CoBack, NCB, P);
    FRONT: Push(Fr, NF, P);
    BACK: Push(Bk, NB, P);
    SPANNING:
      begin
        SetLength(FV, Length(P.V) + 2);
        SetLength(BV, Length(P.V) + 2);
        NFv := 0;
        NBv := 0;
        for I := 0 to High(P.V) do
        begin
          J := (I + 1) mod Length(P.V);
          Ti := Types[I];
          Tj := Types[J];
          Vi := P.V[I];
          Vj := P.V[J];
          if Ti <> BACK then
          begin
            FV[NFv] := Vi;
            Inc(NFv);
          end;
          if Ti <> FRONT then
          begin
            BV[NBv] := Vi;
            Inc(NBv);
          end;
          if (Ti or Tj) = SPANNING then
          begin
            T := (W - VDot(N, Vi)) / VDot(N, VSub(Vj, Vi));
            Vm := VLerp(Vi, Vj, T);
            FV[NFv] := Vm;
            Inc(NFv);
            BV[NBv] := Vm;
            Inc(NBv);
          end;
        end;
        SetLength(FV, NFv);
        SetLength(BV, NBv);
        if NFv >= 3 then
        begin
          Q := P;
          Q.V := FV;
          Push(Fr, NF, Q);
        end;
        if NBv >= 3 then
        begin
          Q := P;
          Q.V := BV;
          Push(Bk, NB, Q);
        end;
      end;
  end;
end;

{ Insere poligonos na arvore (iterativo). }
procedure Build(Root: TNode; const Polys: TPolyArr; Count: Integer);
type
  TWork = record
    Node: TNode;
    P: TPolyArr;
    C: Integer;
  end;
var
  Stack: array of TWork;
  SP, I, NCF, NCB, NF, NB: Integer;
  W: TWork;
  Fr, Bk: TPolyArr;
begin
  if Count = 0 then
    Exit;
  SetLength(Stack, 1);
  Stack[0].Node := Root;
  Stack[0].P := Copy(Polys, 0, Count);
  Stack[0].C := Count;
  SP := 1;
  while SP > 0 do
  begin
    Dec(SP);
    W := Stack[SP];
    if W.C = 0 then
      Continue;
    if not W.Node.HasPlane then
    begin
      W.Node.HasPlane := True;
      W.Node.N := W.P[0].N;
      W.Node.W := W.P[0].W;
    end;
    Fr := nil; Bk := nil;
    NF := 0; NB := 0;
    NCF := Length(W.Node.Polys);
    NCB := 0;
    for I := 0 to W.C - 1 do
      SplitPoly(W.Node.N, W.Node.W, W.P[I], W.Node.Polys, W.Node.Polys, Fr, Bk, NCF, NCF, NF, NB);
    SetLength(W.Node.Polys, NCF);
    if NF > 0 then
    begin
      if W.Node.Front = nil then
        W.Node.Front := TNode.Create;
      if SP >= Length(Stack) then SetLength(Stack, SP * 2 + 4);
      Stack[SP].Node := W.Node.Front;
      Stack[SP].P := Fr;
      Stack[SP].C := NF;
      Inc(SP);
    end;
    if NB > 0 then
    begin
      if W.Node.Back = nil then
        W.Node.Back := TNode.Create;
      if SP >= Length(Stack) then SetLength(Stack, SP * 2 + 4);
      Stack[SP].Node := W.Node.Back;
      Stack[SP].P := Bk;
      Stack[SP].C := NB;
      Inc(SP);
    end;
  end;
end;

{ Recorta poligonos pela arvore: devolve so as partes fora do solido. }
function ClipPolys(Root: TNode; const Polys: TPolyArr; Count: Integer; out OutCount: Integer): TPolyArr;
type
  TWork = record
    Node: TNode;
    P: TPolyArr;
    C: Integer;
  end;
var
  Stack: array of TWork;
  SP, I, NCF, NCB, NF, NB: Integer;
  W: TWork;
  Fr, Bk, CF, CB: TPolyArr;
begin
  Result := nil;
  OutCount := 0;
  if Count = 0 then
    Exit;
  SetLength(Stack, 1);
  Stack[0].Node := Root;
  Stack[0].P := Copy(Polys, 0, Count);
  Stack[0].C := Count;
  SP := 1;
  while SP > 0 do
  begin
    Dec(SP);
    W := Stack[SP];
    if not W.Node.HasPlane then
    begin
      for I := 0 to W.C - 1 do
        Push(Result, OutCount, W.P[I]);
      Continue;
    end;
    Fr := nil; Bk := nil; CF := nil; CB := nil;
    NF := 0; NB := 0; NCF := 0; NCB := 0;
    for I := 0 to W.C - 1 do
      SplitPoly(W.Node.N, W.Node.W, W.P[I], CF, CB, Fr, Bk, NCF, NCB, NF, NB);
    { coplanares: os da frente seguem para a frente, os de tras para tras }
    for I := 0 to NCF - 1 do
      Push(Fr, NF, CF[I]);
    for I := 0 to NCB - 1 do
      Push(Bk, NB, CB[I]);
    if NF > 0 then
    begin
      if W.Node.Front <> nil then
      begin
        if SP >= Length(Stack) then SetLength(Stack, SP * 2 + 4);
        Stack[SP].Node := W.Node.Front;
        Stack[SP].P := Fr;
        Stack[SP].C := NF;
        Inc(SP);
      end
      else
        for I := 0 to NF - 1 do
          Push(Result, OutCount, Fr[I]);
    end;
    if (NB > 0) and (W.Node.Back <> nil) then
    begin
      if SP >= Length(Stack) then SetLength(Stack, SP * 2 + 4);
      Stack[SP].Node := W.Node.Back;
      Stack[SP].P := Bk;
      Stack[SP].C := NB;
      Inc(SP);
    end;
    { sem no de tras: parte de tras esta dentro do solido -> descarta }
  end;
end;

procedure ForEachNode(Root: TNode; var List: TList);
var
  Stack: TList;
  N: TNode;
begin
  Stack := TList.Create;
  try
    Stack.Add(Root);
    while Stack.Count > 0 do
    begin
      N := TNode(Stack[Stack.Count - 1]);
      Stack.Delete(Stack.Count - 1);
      List.Add(N);
      if N.Front <> nil then Stack.Add(N.Front);
      if N.Back <> nil then Stack.Add(N.Back);
    end;
  finally
    Stack.Free;
  end;
end;

procedure Invert(Root: TNode);
var
  L: TList;
  I, J: Integer;
  N: TNode;
  T: TNode;
begin
  L := TList.Create;
  try
    ForEachNode(Root, L);
    for I := 0 to L.Count - 1 do
    begin
      N := TNode(L[I]);
      for J := 0 to High(N.Polys) do
        FlipPoly(N.Polys[J]);
      N.N := VNeg(N.N);
      N.W := -N.W;
      T := N.Front;
      N.Front := N.Back;
      N.Back := T;
    end;
  finally
    L.Free;
  end;
end;

procedure ClipTo(Root, Other: TNode);
var
  L: TList;
  I, C: Integer;
  N: TNode;
begin
  L := TList.Create;
  try
    ForEachNode(Root, L);
    for I := 0 to L.Count - 1 do
    begin
      N := TNode(L[I]);
      N.Polys := ClipPolys(Other, N.Polys, Length(N.Polys), C);
      SetLength(N.Polys, C);
    end;
  finally
    L.Free;
  end;
end;

function AllPolys(Root: TNode; out Count: Integer): TPolyArr;
var
  L: TList;
  I, J: Integer;
  N: TNode;
begin
  Result := nil;
  Count := 0;
  L := TList.Create;
  try
    ForEachNode(Root, L);
    for I := 0 to L.Count - 1 do
    begin
      N := TNode(L[I]);
      for J := 0 to High(N.Polys) do
        Push(Result, Count, N.Polys[J]);
    end;
  finally
    L.Free;
  end;
end;

{ ---------- conversao ---------- }

function MeshToPolys(M: TCadMesh; const FaceMap: array of Integer; out Count: Integer): TPolyArr;
var
  I: Integer;
  T: TCadTri;
  V: TVArr;
  P: TPoly;
begin
  Result := nil;
  Count := 0;
  for I := 0 to M.TriCount - 1 do
  begin
    T := M.Tris[I];
    SetLength(V, 3);
    V[0] := M.Verts[T.A];
    V[1] := M.Verts[T.B];
    V[2] := M.Verts[T.C];
    if MakePoly(Copy(V), FaceMap[T.Face], P) then
      Push(Result, Count, P);
  end;
end;

type
  TT = record
    A, B, C, F: Integer;
  end;
  TTArr = array of TT;
  TBoolArr = array of Boolean;

procedure PushT(var Arr: TTArr; var N: Integer; A, B, C, F: Integer);
begin
  if (A = B) or (B = C) or (A = C) then
    Exit;
  if N >= Length(Arr) then
    SetLength(Arr, Max(64, N * 2));
  Arr[N].A := A; Arr[N].B := B; Arr[N].C := C; Arr[N].F := F;
  Inc(N);
end;

{ Reparo de juncoes em T em uma passada: cada aresta recebe, em ordem, os
  vertices (usados) que estao sobre ela; os dois lados de uma aresta veem o
  mesmo conjunto. Triangulo que ganhou pontos vira leque a partir do
  centroide (vertice novo, interior, fora de qualquer aresta). Triangulos
  degenerados (altura menor que a tolerancia) sao descartados: o vizinho do
  outro lado da aresta longa recebe o vertice do meio. Termina sempre. }
function RepairTJ(M: TCadMesh; var Tris: TTArr; var NT: Integer; const Skip: TBoolArr; out AError: string): Boolean;
var
  Order: TCadIdArray;
  InUse: array of Boolean;
  Done: TTArr;
  ND, I, K, Q, Lo, Hi, Md, VC, N, X, Y, Cen, TmpI: Integer;
  Cur: TT;
  Edge: array[0..2] of Integer;
  PA, PB, PV: TCadVec3;
  Dl2, T, Len, TmpD: Double;
  Ring: TCadIdArray;
  Ts: array of Double;
  Pts: TCadIdArray;
  Fr: TCadFrame;
  R2, RPts: TCadPoly2;
  RTris: TCadTriIdxArray;
  RErr: string;
  N0: TCadVec3;
  Placed: Boolean;
  function Degenerate(const Tr: TT): Boolean;
  var
    A2, LMax: Double;
    P1, P2, P3: TCadVec3;
  begin
    P1 := M.Verts[Tr.A]; P2 := M.Verts[Tr.B]; P3 := M.Verts[Tr.C];
    A2 := VLen(VCross(VSub(P2, P1), VSub(P3, P1)));
    LMax := Max(VDist(P1, P2), Max(VDist(P2, P3), VDist(P3, P1)));
    Result := (LMax < 1E-12) or (A2 / LMax < TJ_TOL);
  end;
  procedure SortByX(L, R: Integer);
  var
    A, B, Tmp: Integer;
    P: Double;
  begin
    while L < R do
    begin
      A := L; B := R;
      P := M.Verts[Order[(L + R) shr 1]].X;
      repeat
        while M.Verts[Order[A]].X < P do Inc(A);
        while M.Verts[Order[B]].X > P do Dec(B);
        if A <= B then
        begin
          Tmp := Order[A]; Order[A] := Order[B]; Order[B] := Tmp;
          Inc(A); Dec(B);
        end;
      until A > B;
      if B - L < R - A then begin SortByX(L, B); L := A; end
      else begin SortByX(A, R); R := B; end;
    end;
  end;
begin
  Result := False;
  AError := '';
  { descarta degenerados antes de tudo (so nas faces nao refeitas) }
  K := 0;
  for I := 0 to NT - 1 do
    if Skip[Tris[I].F] or not Degenerate(Tris[I]) then
    begin
      Tris[K] := Tris[I];
      Inc(K);
    end;
  NT := K;
  { so os vertices usados pelos triangulos }
  SetLength(InUse, M.VertCount);
  for I := 0 to M.VertCount - 1 do
    InUse[I] := False;
  for I := 0 to NT - 1 do
  begin
    InUse[Tris[I].A] := True;
    InUse[Tris[I].B] := True;
    InUse[Tris[I].C] := True;
  end;
  VC := 0;
  SetLength(Order, M.VertCount);
  for I := 0 to M.VertCount - 1 do
    if InUse[I] then
    begin
      Order[VC] := I;
      Inc(VC);
    end;
  SetLength(Order, VC);
  if VC > 1 then
    SortByX(0, VC - 1);
  Done := nil;
  ND := 0;
  for I := 0 to NT - 1 do
  begin
    Cur := Tris[I];
    if Skip[Cur.F] then
    begin
      PushT(Done, ND, Cur.A, Cur.B, Cur.C, Cur.F);
      Continue;
    end;
    Edge[0] := Cur.A; Edge[1] := Cur.B; Edge[2] := Cur.C;
    Ring := nil;
    for K := 0 to 2 do
    begin
      SetLength(Ring, Length(Ring) + 1);
      Ring[High(Ring)] := Edge[K];
      PA := M.Verts[Edge[K]];
      PB := M.Verts[Edge[(K + 1) mod 3]];
      Dl2 := VDot(VSub(PB, PA), VSub(PB, PA));
      Len := Sqrt(Dl2);
      Lo := 0; Hi := VC;
      while Lo < Hi do
      begin
        Md := (Lo + Hi) shr 1;
        if M.Verts[Order[Md]].X < Min(PA.X, PB.X) - TJ_TOL then Lo := Md + 1 else Hi := Md;
      end;
      N := 0;
      Ts := nil;
      Pts := nil;
      while (Lo < VC) and (M.Verts[Order[Lo]].X <= Max(PA.X, PB.X) + TJ_TOL) do
      begin
        Q := Order[Lo];
        Inc(Lo);
        if (Q = Edge[0]) or (Q = Edge[1]) or (Q = Edge[2]) then
          Continue;
        PV := M.Verts[Q];
        if (PV.Y < Min(PA.Y, PB.Y) - TJ_TOL) or (PV.Y > Max(PA.Y, PB.Y) + TJ_TOL) or
          (PV.Z < Min(PA.Z, PB.Z) - TJ_TOL) or (PV.Z > Max(PA.Z, PB.Z) + TJ_TOL) then
          Continue;
        T := VDot(VSub(PV, PA), VSub(PB, PA)) / Dl2;
        if (T * Len <= WELD_TOL) or ((1 - T) * Len <= WELD_TOL) then
          Continue;
        if VDist(PV, VLerp(PA, PB, T)) > TJ_TOL then
          Continue;
        SetLength(Ts, N + 1);
        SetLength(Pts, N + 1);
        Ts[N] := T;
        Pts[N] := Q;
        Inc(N);
      end;
      for X := 1 to N - 1 do
      begin
        Y := X;
        while (Y > 0) and (Ts[Y - 1] > Ts[Y]) do
        begin
          TmpD := Ts[Y]; Ts[Y] := Ts[Y - 1]; Ts[Y - 1] := TmpD;
          TmpI := Pts[Y]; Pts[Y] := Pts[Y - 1]; Pts[Y - 1] := TmpI;
          Dec(Y);
        end;
      end;
      for X := 0 to N - 1 do
      begin
        { vertice perto de duas arestas (triangulo muito fino): uma vez so }
        Y := 0;
        while (Y < Length(Ring)) and (Ring[Y] <> Pts[X]) do
          Inc(Y);
        if Y < Length(Ring) then
          Continue;
        SetLength(Ring, Length(Ring) + 1);
        Ring[High(Ring)] := Pts[X];
      end;
    end;
    if Length(Ring) = 3 then
    begin
      PushT(Done, ND, Cur.A, Cur.B, Cur.C, Cur.F);
      Continue;
    end;
    { anel (triangulo + pontos nas arestas): tenta triangular no plano do
      triangulo (sem vertice novo) e, se algum pedaco sair invertido, o
      leque pelo centroide; fica com a primeira opcao sem inversao }
    N0 := VCross(VSub(M.Verts[Cur.B], M.Verts[Cur.A]), VSub(M.Verts[Cur.C], M.Verts[Cur.A]));
    Fr := FrameFromNormal(M.Verts[Cur.A], N0);
    SetLength(R2, Length(Ring));
    for K := 0 to High(Ring) do
      R2[K] := FrameToLocal(Fr, M.Verts[Ring[K]]);
    Placed := False;
    if CadTriangulate(R2, nil, RPts, RTris, RErr) and (Length(RTris) = Length(Ring) - 2) then
    begin
      Placed := True;
      for K := 0 to High(RTris) do
        if VDot(VCross(VSub(M.Verts[Ring[RTris[K].B]], M.Verts[Ring[RTris[K].A]]),
          VSub(M.Verts[Ring[RTris[K].C]], M.Verts[Ring[RTris[K].A]])), N0) < 0 then
          Placed := False;
      if Placed then
        for K := 0 to High(RTris) do
          PushT(Done, ND, Ring[RTris[K].A], Ring[RTris[K].B], Ring[RTris[K].C], Cur.F);
    end;
    if Placed then
      Continue;
    Cen := M.AddVertexRaw(VScale(VAdd(VAdd(M.Verts[Cur.A], M.Verts[Cur.B]), M.Verts[Cur.C]), 1 / 3));
    for K := 0 to High(Ring) do
      PushT(Done, ND, Cen, Ring[K], Ring[(K + 1) mod Length(Ring)], Cur.F);
  end;
  Tris := Done;
  NT := ND;
  Result := True;
end;

{ Junta os fragmentos de cada face plana: arestas de contorno da face (as
  que nao tem par dentro da face, ja sem juncoes em T) -> lacos -> externos
  e furos -> triangulacao. Reduz muito o numero de triangulos depois de
  cada booleana. Face que nao der certo fica como estava. }
procedure MergePlanar(M: TCadMesh; var Tris: TTArr; var NT: Integer; out Handled: TBoolArr);
var
  F, I, J, K, L, E, NNew, NK, VC, Cur, Start, Guard, Best, Tmp, NIn, NB, Mark: Integer;
  InFace: array of Integer;
  Sum: TCadVec3;
  Fr: TCadFrame;
  Edges: specialize TDictionary<Int64, Integer>;
  OutOf: specialize TDictionary<Integer, Integer>;
  BA, BB, NextE: array of Integer;
  Used: array of Boolean;
  Loops: array of TCadIdArray;
  Loop: TCadIdArray;
  Areas: array of Double;
  P2: TCadPoly2Array;
  Parent: array of Integer;
  Holes: TCadPoly2Array;
  IdMap: TCadIdArray;
  Pts: TCadPoly2;
  TR: TCadTriIdxArray;
  Err: string;
  Ok: Boolean;
  NewT, Keep: TTArr;
  FV, Chain, AllV: TCadIdArray;
  UsedV: array of Boolean;
  Pair: specialize TPair<Int64, Integer>;
  DumpF: TextFile;
  function InPoly2(const P: TCadVec2; const Poly: TCadPoly2): Boolean;
  var
    A, B: Integer;
  begin
    Result := False;
    B := High(Poly);
    for A := 0 to High(Poly) do
    begin
      if ((Poly[A].Y > P.Y) <> (Poly[B].Y > P.Y)) and
        (P.X < (Poly[B].X - Poly[A].X) * (P.Y - Poly[A].Y) / (Poly[B].Y - Poly[A].Y) + Poly[A].X) then
        Result := not Result;
      B := A;
    end;
  end;
  procedure SortByX(var A: TCadIdArray);
    procedure QS(Lo, Hi: Integer);
    var
      X, Y, T: Integer;
      P: Double;
    begin
      while Lo < Hi do
      begin
        X := Lo; Y := Hi;
        P := M.Verts[A[(Lo + Hi) shr 1]].X;
        repeat
          while M.Verts[A[X]].X < P do Inc(X);
          while M.Verts[A[Y]].X > P do Dec(Y);
          if X <= Y then
          begin
            T := A[X]; A[X] := A[Y]; A[Y] := T;
            Inc(X); Dec(Y);
          end;
        until X > Y;
        if Y - Lo < Hi - X then begin QS(Lo, Y); Lo := X; end
        else begin QS(X, Hi); Hi := Y; end;
      end;
    end;
  begin
    if Length(A) > 1 then
      QS(0, High(A));
  end;
  { Aresta Va->Vb quebrada nos vertices de FV sobre ela, em ordem. }
  procedure SplitEdge(Va, Vb: Integer; const FVs: TCadIdArray; out Ch: TCadIdArray);
  var
    PA, PB, PV: TCadVec3;
    Dl2, T, MinX, MaxX: Double;
    Lo, Hi, Md, Q, N, X, Y: Integer;
    Ts: array of Double;
    TmpD: Double;
    TmpI: Integer;
  begin
    PA := M.Verts[Va];
    PB := M.Verts[Vb];
    Dl2 := VDot(VSub(PB, PA), VSub(PB, PA));
    SetLength(Ch, 2);
    Ch[0] := Va;
    Ch[1] := Vb;
    if Dl2 < 1E-24 then
      Exit;
    MinX := Min(PA.X, PB.X) - TJ_TOL;
    MaxX := Max(PA.X, PB.X) + TJ_TOL;
    Lo := 0; Hi := Length(FVs);
    while Lo < Hi do
    begin
      Md := (Lo + Hi) shr 1;
      if M.Verts[FVs[Md]].X < MinX then Lo := Md + 1 else Hi := Md;
    end;
    N := 0;
    Ts := nil;
    SetLength(Ch, 1);
    while (Lo < Length(FVs)) and (M.Verts[FVs[Lo]].X <= MaxX) do
    begin
      Q := FVs[Lo];
      Inc(Lo);
      if (Q = Va) or (Q = Vb) then
        Continue;
      PV := M.Verts[Q];
      if (PV.Y < Min(PA.Y, PB.Y) - TJ_TOL) or (PV.Y > Max(PA.Y, PB.Y) + TJ_TOL) or
        (PV.Z < Min(PA.Z, PB.Z) - TJ_TOL) or (PV.Z > Max(PA.Z, PB.Z) + TJ_TOL) then
        Continue;
      T := VDot(VSub(PV, PA), VSub(PB, PA)) / Dl2;
      if (T * Sqrt(Dl2) <= WELD_TOL) or ((1 - T) * Sqrt(Dl2) <= WELD_TOL) then
        Continue;
      if VDist(PV, VLerp(PA, PB, T)) > TJ_TOL then
        Continue;
      SetLength(Ts, N + 1);
      SetLength(Ch, N + 2);
      Ts[N] := T;
      Ch[N + 1] := Q;
      Inc(N);
    end;
    { ordena por T (insercao: poucos pontos) }
    for X := 1 to N - 1 do
    begin
      Y := X;
      while (Y > 0) and (Ts[Y - 1] > Ts[Y]) do
      begin
        TmpD := Ts[Y]; Ts[Y] := Ts[Y - 1]; Ts[Y - 1] := TmpD;
        TmpI := Ch[Y + 1]; Ch[Y + 1] := Ch[Y]; Ch[Y] := TmpI;
        Dec(Y);
      end;
    end;
    SetLength(Ch, N + 2);
    Ch[N + 1] := Vb;
  end;
  procedure AddAtom(Va, Vb: Integer);
  var
    KF, KR: Int64;
    C: Integer;
  begin
    KR := Int64(Vb) * VC + Va;
    if Edges.TryGetValue(KR, C) and (C > 0) then
    begin
      if C = 1 then Edges.Remove(KR) else Edges[KR] := C - 1;
      Exit;
    end;
    KF := Int64(Va) * VC + Vb;
    if Edges.TryGetValue(KF, C) then
      Edges[KF] := C + 1
    else
      Edges.Add(KF, 1);
  end;
begin
  VC := M.VertCount;
  { todos os vertices usados (de todas as faces), ordenados por X: as arestas
    do contorno sao quebradas tambem nos vertices das faces vizinhas (curvas),
    entao a triangulacao ja nasce sem juncao em T }
  SetLength(UsedV, VC);
  for I := 0 to VC - 1 do
    UsedV[I] := False;
  for I := 0 to NT - 1 do
  begin
    UsedV[Tris[I].A] := True;
    UsedV[Tris[I].B] := True;
    UsedV[Tris[I].C] := True;
  end;
  AllV := nil;
  for I := 0 to VC - 1 do
    if UsedV[I] then
    begin
      SetLength(AllV, Length(AllV) + 1);
      AllV[High(AllV)] := I;
    end;
  SortByX(AllV);
  SetLength(Handled, M.FaceCount);
  NewT := nil;
  NNew := 0;
  for F := 0 to M.FaceCount - 1 do
  begin
    Handled[F] := False;
    if M.Faces[F].Surf <> skPlane then
      Continue;
    InFace := nil;
    NIn := 0;
    Sum := V3(0, 0, 0);
    for I := 0 to NT - 1 do
      if Tris[I].F = F then
      begin
        SetLength(InFace, NIn + 1);
        InFace[NIn] := I;
        Inc(NIn);
        Sum := VAdd(Sum, VCross(VSub(M.Verts[Tris[I].B], M.Verts[Tris[I].A]),
          VSub(M.Verts[Tris[I].C], M.Verts[Tris[I].A])));
      end;
    if (NIn < 3) or (VLen(Sum) < 1E-12) then
      Continue;
    Edges := specialize TDictionary<Int64, Integer>.Create;
    OutOf := specialize TDictionary<Integer, Integer>.Create;
    try
      { arestas atomicas: cada aresta e quebrada nos vertices da face sobre ela;
        a->b e b->a se cancelam; o que sobra e o contorno }
      for I := 0 to NIn - 1 do
        for K := 0 to 2 do
        begin
          case K of
            0: begin J := Tris[InFace[I]].A; L := Tris[InFace[I]].B; end;
            1: begin J := Tris[InFace[I]].B; L := Tris[InFace[I]].C; end;
          else
            begin J := Tris[InFace[I]].C; L := Tris[InFace[I]].A; end;
          end;
          SplitEdge(J, L, AllV, Chain);
          for E := 0 to High(Chain) - 1 do
            AddAtom(Chain[E], Chain[E + 1]);
        end;
      NB := 0;
      BA := nil;
      BB := nil;
      for Pair in Edges do
        if Pair.Value > 0 then
          for E := 1 to Pair.Value do
          begin
            SetLength(BA, NB + 1);
            SetLength(BB, NB + 1);
            BA[NB] := Pair.Key div VC;
            BB[NB] := Pair.Key mod VC;
            Inc(NB);
          end;
      if NB < 3 then
        Continue;
      SetLength(NextE, NB);
      for E := 0 to NB - 1 do
      begin
        if OutOf.TryGetValue(BA[E], Tmp) then
          NextE[E] := Tmp
        else
          NextE[E] := -1;
        OutOf.AddOrSetValue(BA[E], E);
      end;
      SetLength(Used, NB);
      for E := 0 to NB - 1 do
        Used[E] := False;
      Loops := nil;
      Ok := True;
      for E := 0 to NB - 1 do
      begin
        if Used[E] then
          Continue;
        Loop := nil;
        Start := BA[E];
        Cur := E;
        Guard := 0;
        repeat
          Used[Cur] := True;
          SetLength(Loop, Length(Loop) + 1);
          Loop[High(Loop)] := BA[Cur];
          if BB[Cur] = Start then
            Break;
          Best := -1;
          if OutOf.TryGetValue(BB[Cur], Tmp) then
            while Tmp >= 0 do
            begin
              if not Used[Tmp] then
              begin
                Best := Tmp;
                Break;
              end;
              Tmp := NextE[Tmp];
            end;
          Cur := Best;
          Inc(Guard);
        until (Cur < 0) or (Guard > NB);
        if (Cur < 0) or (Guard > NB) then
        begin
          Ok := False;
          Break;
        end;
        if Length(Loop) >= 3 then
        begin
          SetLength(Loops, Length(Loops) + 1);
          Loops[High(Loops)] := Loop;
        end;
      end;
      if not Ok or (Length(Loops) = 0) then
      begin
        if CadCsgDebug then Writeln('  face ', M.Faces[F].Name, ': lacos falharam (', NB, ' arestas)');
        Continue;
      end;
      if CadCsgDebug then
        for L := 0 to High(Loops) do
          for I := 0 to High(Loops[L]) do
            if Loops[L][(I + 2) mod Length(Loops[L])] = Loops[L][I] then
              Writeln('  ESPINHO face ', M.Faces[F].Name, ' laco ', L, ' n=', Length(Loops[L]), ' em ',
                Loops[L][I], '-', Loops[L][(I + 1) mod Length(Loops[L])]);
      Fr := FrameFromNormal(M.Verts[Loops[0][0]], Sum);
      SetLength(P2, Length(Loops));
      SetLength(Areas, Length(Loops));
      for L := 0 to High(Loops) do
      begin
        SetLength(P2[L], Length(Loops[L]));
        for I := 0 to High(Loops[L]) do
          P2[L][I] := FrameToLocal(Fr, M.Verts[Loops[L][I]]);
        Areas[L] := CadPoly2Area(P2[L]);
      end;
      if CadCsgDebug then
      begin
        Writeln('  face ', M.Faces[F].Name, ' lacos=', Length(Loops));
        for L := 0 to High(Loops) do
          Writeln('    laco ', L, ' n=', Length(Loops[L]), ' area=', Areas[L]:0:5);
      end;
      { lacos de area desprezivel sao ruido da classificacao (sobras de
        arestas canceladas): descarta }
      K := 0;
      for L := 0 to High(Loops) do
        if Abs(Areas[L]) > NOISE_AREA then
        begin
          Loops[K] := Loops[L];
          P2[K] := P2[L];
          Areas[K] := Areas[L];
          Inc(K);
        end;
      SetLength(Loops, K);
      SetLength(P2, K);
      SetLength(Areas, K);
      if K = 0 then
        Continue;
      SetLength(Parent, Length(Loops));
      for L := 0 to High(Loops) do
      begin
        Parent[L] := -1;
        if Areas[L] >= 0 then
          Continue;
        for K := 0 to High(Loops) do
          if (Areas[K] > 0) and InPoly2(P2[L][0], P2[K]) then
            if (Parent[L] < 0) or (Areas[K] < Areas[Parent[L]]) then
              Parent[L] := K;
        if Parent[L] < 0 then
          Ok := False;
      end;
      if not Ok then
        Continue;
      Mark := NNew;
      for L := 0 to High(Loops) do
      begin
        if Areas[L] <= 0 then
          Continue;
        Holes := nil;
        IdMap := Copy(Loops[L]);
        for K := 0 to High(Loops) do
          if Parent[K] = L then
          begin
            SetLength(Holes, Length(Holes) + 1);
            Holes[High(Holes)] := P2[K];
            IdMap := Concat(IdMap, Loops[K]);
          end;
        if not CadTriangulate(P2[L], Holes, Pts, TR, Err) then
        begin
          if CadCsgDebug then
          begin
            Writeln('  face ', M.Faces[F].Name, ': ', Err, ' lacos=', Length(Loops));
            for K := 0 to High(Loops) do
              Writeln('    laco ', K, ' n=', Length(Loops[K]), ' area=', Areas[K]:0:4, ' pai=', Parent[K]);
          end;
          Ok := False;
          Break;
        end;
        if CadCsgDebug then
        begin
          Sum.X := 0;
          for I := 0 to High(TR) do
            Sum.X := Sum.X + ((Pts[TR[I].B].X - Pts[TR[I].A].X) * (Pts[TR[I].C].Y - Pts[TR[I].A].Y) -
              (Pts[TR[I].B].Y - Pts[TR[I].A].Y) * (Pts[TR[I].C].X - Pts[TR[I].A].X)) / 2;
          Writeln('    triangulos=', Length(TR), ' soma areas=', Sum.X:0:5);
          if CadCsgDump <> '' then
          begin
            Assign(DumpF, CadCsgDump + '_' + IntToStr(F) + '.txt');
            Rewrite(DumpF);
            Writeln(DumpF, Length(Holes) + 1);
            Writeln(DumpF, Length(P2[L]));
            for I := 0 to High(P2[L]) do Writeln(DumpF, P2[L][I].X:0:12, ' ', P2[L][I].Y:0:12);
            for K := 0 to High(Holes) do
            begin
              Writeln(DumpF, Length(Holes[K]));
              for I := 0 to High(Holes[K]) do Writeln(DumpF, Holes[K][I].X:0:12, ' ', Holes[K][I].Y:0:12);
            end;
            Close(DumpF);
          end;
        end;
        for I := 0 to High(TR) do
          PushT(NewT, NNew, IdMap[TR[I].A], IdMap[TR[I].B], IdMap[TR[I].C], F);
      end;
      if not Ok then
      begin
        NNew := Mark;
        Continue;
      end;
      Handled[F] := True;
    finally
      Edges.Free;
      OutOf.Free;
    end;
  end;
  Keep := nil;
  NK := 0;
  for I := 0 to NT - 1 do
    if not Handled[Tris[I].F] then
      PushT(Keep, NK, Tris[I].A, Tris[I].B, Tris[I].C, Tris[I].F);
  for I := 0 to NNew - 1 do
    PushT(Keep, NK, NewT[I].A, NewT[I].B, NewT[I].C, NewT[I].F);
  Tris := Keep;
  NT := NK;
end;

procedure DebugFlipped(M: TCadMesh; const Tris: TTArr; NT: Integer; const Stage: string);
var
  I, NF, F, NPos, NNeg: Integer;
  Nrm, Cen, Rad: TCadVec3;
begin
  NF := 0;
  for I := 0 to NT - 1 do
    if M.Faces[Tris[I].F].Surf = skPlane then
    begin
      Nrm := VCross(VSub(M.Verts[Tris[I].B], M.Verts[Tris[I].A]), VSub(M.Verts[Tris[I].C], M.Verts[Tris[I].A]));
      if VDot(Nrm, M.Faces[Tris[I].F].Axis) < -1E-12 then
      begin
        Inc(NF);
        if NF <= 3 then
          Writeln('    invertido em ', Stage, ': face ', M.Faces[Tris[I].F].Name, ' area2=', VLen(Nrm):0:9);
      end;
    end;
  Writeln('  ', Stage, ': ', NF, ' triangulos invertidos (planos)');
  { cilindros: sinal da normal contra o raio deve ser o mesmo na face toda }
  for F := 0 to M.FaceCount - 1 do
    if M.Faces[F].Surf = skCylinder then
    begin
      NPos := 0; NNeg := 0;
      for I := 0 to NT - 1 do
        if Tris[I].F = F then
        begin
          Nrm := VCross(VSub(M.Verts[Tris[I].B], M.Verts[Tris[I].A]), VSub(M.Verts[Tris[I].C], M.Verts[Tris[I].A]));
          Cen := VScale(VAdd(VAdd(M.Verts[Tris[I].A], M.Verts[Tris[I].B]), M.Verts[Tris[I].C]), 1 / 3);
          Rad := VSub(Cen, VAdd(M.Faces[F].Origin, VScale(M.Faces[F].Axis, VDot(VSub(Cen, M.Faces[F].Origin), M.Faces[F].Axis))));
          if VDot(Nrm, Rad) >= 0 then Inc(NPos) else Inc(NNeg);
        end;
      if (NPos > 0) and (NNeg > 0) then
        Writeln('    cilindro ', M.Faces[F].Name, ': +', NPos, ' -', NNeg);
    end;
end;

function BuildResult(const Faces: array of TCadFaceInfo; const Polys: TPolyArr;
  Count: Integer; out AError: string): TCadMesh;
var
  M: TCadMesh;
  FMap, VMap: array of Integer;
  I, J, NT: Integer;
  Tris: TTArr;
  Handled: TBoolArr;
begin
  Result := nil;
  AError := '';
  M := TCadMesh.Create(WELD_TOL);
  SetLength(FMap, Length(Faces));
  for I := 0 to High(Faces) do
    FMap[I] := M.AddFace(Faces[I]);
  Tris := nil;
  NT := 0;
  for I := 0 to Count - 1 do
    for J := 1 to High(Polys[I].V) - 1 do
      PushT(Tris, NT, M.AddVertex(Polys[I].V[0]), M.AddVertex(Polys[I].V[J]),
        M.AddVertex(Polys[I].V[J + 1]), FMap[Polys[I].Face]);
  if CadCsgDebug then Writeln('  fragmentos: ', NT, ' vertices: ', M.VertCount);
  if CadCsgDebug then DebugFlipped(M, Tris, NT, 'fragmentos');
  MergePlanar(M, Tris, NT, Handled);
  if CadCsgDebug then Writeln('  depois de juntar: ', NT);
  if CadCsgDebug then DebugFlipped(M, Tris, NT, 'juntar');
  if not RepairTJ(M, Tris, NT, Handled, AError) then
  begin
    M.Free;
    Exit;
  end;
  if CadCsgDebug then DebugFlipped(M, Tris, NT, 'reparo');
  { copia so os vertices usados, sem soldar de novo (ja estao soldados) }
  Result := TCadMesh.Create(WELD_TOL);
  for I := 0 to M.FaceCount - 1 do
    Result.AddFace(M.Faces[I]);
  SetLength(VMap, M.VertCount);
  for I := 0 to High(VMap) do
    VMap[I] := -1;
  for I := 0 to NT - 1 do
  begin
    if VMap[Tris[I].A] < 0 then VMap[Tris[I].A] := Result.AddVertexRaw(M.Verts[Tris[I].A]);
    if VMap[Tris[I].B] < 0 then VMap[Tris[I].B] := Result.AddVertexRaw(M.Verts[Tris[I].B]);
    if VMap[Tris[I].C] < 0 then VMap[Tris[I].C] := Result.AddVertexRaw(M.Verts[Tris[I].C]);
    Result.AddTri(VMap[Tris[I].A], VMap[Tris[I].B], VMap[Tris[I].C], Tris[I].F);
  end;
  M.Free;
  CadRefreshPlaneNormals(Result);
  if (Result.TriCount > 0) and not Result.CheckClosed(AError) then
  begin
    AError := 'Booleana gerou malha aberta: ' + AError;
    FreeAndNil(CadCsgLastFailed);
    CadCsgLastFailed := Result;
    Result := nil;
  end;
end;

{ Muda a ordem dos poligonos (a arvore BSP usa outros planos de corte):
  0 = original, 1 = invertida, 2 = meia volta, 3 = salto primo. }
procedure Permute(var P: TPolyArr; N, Attempt: Integer);
var
  Q: TPolyArr;
  I, S: Integer;
begin
  if (Attempt = 0) or (N < 2) then
    Exit;
  SetLength(Q, N);
  case Attempt of
    1: for I := 0 to N - 1 do Q[I] := P[N - 1 - I];
    2: for I := 0 to N - 1 do Q[I] := P[(I + N div 2) mod N];
  else
    begin
      S := 7919;
      while (N mod S = 0) or (S mod N = 0) do
        Inc(S, 2);
      for I := 0 to N - 1 do
        Q[I] := P[(Int64(I) * S) mod N];
    end;
  end;
  for I := 0 to N - 1 do
    P[I] := Q[I];
end;

function BooleanAttempt(A, B: TCadMesh; Op: TCadBoolOp; Attempt: Integer; out AError: string): TCadMesh; forward;

function CadBoolean(A, B: TCadMesh; Op: TCadBoolOp; out AError: string): TCadMesh;
var
  K: Integer;
  E: string;
begin
  { a classificacao BSP pode errar por arredondamento em casos raros
    (malha aberta no fim): tenta de novo com a arvore montada em outra ordem }
  Result := nil;
  AError := '';
  for K := 0 to 3 do
  begin
    Result := BooleanAttempt(A, B, Op, K, E);
    if Assigned(Result) then
      Exit;
    if K = 0 then
      AError := E;
  end;
end;

function BooleanAttempt(A, B: TCadMesh; Op: TCadBoolOp; Attempt: Integer; out AError: string): TCadMesh;
var
  Faces: array of TCadFaceInfo;
  MapA, MapB: array of Integer;
  I, NA, NB, NR: Integer;
  PA, PB, PR: TPolyArr;
  TA, TB: TNode;
  function FaceId(const F: TCadFaceInfo): Integer;
  var
    K: Integer;
  begin
    for K := 0 to High(Faces) do
      if Faces[K].Name = F.Name then
        Exit(K);
    Result := Length(Faces);
    SetLength(Faces, Result + 1);
    Faces[Result] := F;
  end;
begin
  Result := nil;
  AError := '';
  Faces := nil;
  SetLength(MapA, A.FaceCount);
  for I := 0 to A.FaceCount - 1 do
    MapA[I] := FaceId(A.Faces[I]);
  SetLength(MapB, B.FaceCount);
  for I := 0 to B.FaceCount - 1 do
    MapB[I] := FaceId(B.Faces[I]);
  PA := MeshToPolys(A, MapA, NA);
  PB := MeshToPolys(B, MapB, NB);
  Permute(PA, NA, Attempt);
  Permute(PB, NB, Attempt);
  TA := TNode.Create;
  TB := TNode.Create;
  try
    Build(TA, PA, NA);
    Build(TB, PB, NB);
    case Op of
      boUnion:
        begin
          ClipTo(TA, TB);
          ClipTo(TB, TA);
          Invert(TB);
          ClipTo(TB, TA);
          Invert(TB);
          PR := AllPolys(TB, NR);
          Build(TA, PR, NR);
        end;
      boDifference:
        begin
          Invert(TA);
          ClipTo(TA, TB);
          ClipTo(TB, TA);
          Invert(TB);
          ClipTo(TB, TA);
          Invert(TB);
          PR := AllPolys(TB, NR);
          Build(TA, PR, NR);
          Invert(TA);
        end;
      boIntersection:
        begin
          Invert(TA);
          ClipTo(TB, TA);
          Invert(TB);
          ClipTo(TA, TB);
          ClipTo(TB, TA);
          PR := AllPolys(TB, NR);
          Build(TA, PR, NR);
          Invert(TA);
        end;
    end;
    PR := AllPolys(TA, NR);
  finally
    TA.Free;
    TB.Free;
  end;
  Result := BuildResult(Faces, PR, NR, AError);
end;

{ ---------- componentes ---------- }

function FindRoot(var Parent: array of Integer; X: Integer): Integer;
begin
  while Parent[X] <> X do
  begin
    Parent[X] := Parent[Parent[X]];
    X := Parent[X];
  end;
  Result := X;
end;

procedure Unite(var Parent: array of Integer; A, B: Integer);
begin
  A := FindRoot(Parent, A);
  B := FindRoot(Parent, B);
  if A <> B then
    Parent[A] := B;
end;

function ComponentOf(M: TCadMesh; out Root: TCadIdArray): Integer;
var
  Parent: array of Integer;
  I: Integer;
  T: TCadTri;
  Seen: array of Boolean;
begin
  SetLength(Parent, M.VertCount);
  for I := 0 to High(Parent) do
    Parent[I] := I;
  for I := 0 to M.TriCount - 1 do
  begin
    T := M.Tris[I];
    Unite(Parent, T.A, T.B);
    Unite(Parent, T.B, T.C);
  end;
  SetLength(Root, M.VertCount);
  SetLength(Seen, M.VertCount);
  Result := 0;
  for I := 0 to M.VertCount - 1 do
    Root[I] := FindRoot(Parent, I);
  for I := 0 to M.TriCount - 1 do
    if not Seen[Root[M.Tris[I].A]] then
    begin
      Seen[Root[M.Tris[I].A]] := True;
      Inc(Result);
    end;
end;

function CadMeshComponents(M: TCadMesh): Integer;
var
  R: TCadIdArray;
begin
  Result := ComponentOf(M, R);
end;

function CadSplitComponents(M: TCadMesh): TList;
var
  R: TCadIdArray;
  I, K, F: Integer;
  Keys: array of Integer;
  Part: TCadMesh;
  T: TCadTri;
  Idx: Integer;
begin
  Result := TList.Create;
  ComponentOf(M, R);
  Keys := nil;
  for I := 0 to M.TriCount - 1 do
  begin
    T := M.Tris[I];
    Idx := -1;
    for K := 0 to High(Keys) do
      if Keys[K] = R[T.A] then
        Idx := K;
    if Idx < 0 then
    begin
      SetLength(Keys, Length(Keys) + 1);
      Idx := High(Keys);
      Keys[Idx] := R[T.A];
      Result.Add(TCadMesh.Create(M.Tolerance));
    end;
    Part := TCadMesh(Result[Idx]);
    F := Part.AddFace(M.Faces[T.Face]);
    Part.AddTri(Part.AddVertex(M.Verts[T.A]), Part.AddVertex(M.Verts[T.B]),
      Part.AddVertex(M.Verts[T.C]), F);
  end;
end;

procedure CadRefreshPlaneNormals(M: TCadMesh);
begin
  M.RefreshPlaneNormals;
end;

finalization
  FreeAndNil(CadCsgLastFailed);

end.
