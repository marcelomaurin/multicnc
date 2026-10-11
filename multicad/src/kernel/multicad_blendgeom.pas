unit multicad_blendgeom;

{ MultiCAD - geometria de arestas, filete/chanfro e casca sobre a malha.

  - Arestas do solido: pares de faces rotuladas vizinhas; a cadeia de
    segmentos entre duas faces sai da malha (lado da face A, sentido
    anti-horario dela).
  - Ferramenta do filete/chanfro: secao 2D no canto (tangente as duas faces)
    varrida ao longo da aresta reta, ou revolucionada em torno do eixo do
    cilindro (aresta circular). Aresta convexa -> ferramenta de corte;
    concava -> ferramenta de uniao (acrescenta material).
  - Casca: malha deslocada (cada vertice resolve d.n = t para as normais das
    faces vizinhas, minimos quadrados) e diferenca entre as duas. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Generics.Collections, multicad_types, multicad_mesh;

type
  TCadEdgeChain = record
    Pts: array of TCadVec3;
    Closed: Boolean;
    TriA, TriB: Integer;      { triangulos vizinhos do primeiro segmento }
  end;
  TCadEdgeChains = array of TCadEdgeChain;

  { Aresta do solido para a vista (desenho e selecao). }
  TCadEdgeInfo = record
    FaceA, FaceB: Integer;
    Chain: TCadEdgeChain;
  end;
  TCadEdgeInfos = array of TCadEdgeInfo;

  TCadBlendKind = (bkFillet, bkChamfer);

  TCadBlendParams = record
    Kind: TCadBlendKind;
    Radius: Double;          { filete }
    D1, D2: Double;          { chanfro: distancia sobre a face A e a B }
    ChordTol: Double;
  end;

{ Cadeias de segmentos entre as faces FA e FB. }
function CadEdgeChains(M: TCadMesh; FA, FB: Integer): TCadEdgeChains;
{ Faces vizinhas da face F (indices). }
function CadFaceNeighbors(M: TCadMesh; F: Integer): TCadIdArray;
{ Todas as arestas visiveis (faces diferentes e nao coplanares). }
function CadAllEdges(M: TCadMesh): TCadEdgeInfos;
{ Ferramenta para uma cadeia. IsCut: True = corte (aresta convexa). }
function CadBlendTool(M: TCadMesh; FA, FB: Integer; const Chain: TCadEdgeChain;
  const P: TCadBlendParams; const APrefix: string; out IsCut: Boolean;
  out AError: string): TCadMesh;
{ Copia deslocada: faces normais andam TKeep pela normal (negativo = para
  dentro), faces em Removed andam TRemoved. }
function CadOffsetMesh(M: TCadMesh; TKeep, TRemoved: Double;
  const Removed: array of Boolean; out AError: string): TCadMesh;

implementation

type
  TEdgeMap = specialize TDictionary<Int64, Integer>;

function BuildEdgeMap(M: TCadMesh): TEdgeMap;
var
  I, J, N: Integer;
  T: TCadTri;
  Idx: array[0..2] of Integer;
begin
  Result := TEdgeMap.Create;
  N := M.VertCount;
  for I := 0 to M.TriCount - 1 do
  begin
    T := M.Tris[I];
    Idx[0] := T.A;
    Idx[1] := T.B;
    Idx[2] := T.C;
    for J := 0 to 2 do
      Result.AddOrSetValue(Int64(Idx[J]) * N + Idx[(J + 1) mod 3], I);
  end;
end;

function TriVert(const T: TCadTri; K: Integer): Integer;
begin
  case K mod 3 of
    0: Result := T.A;
    1: Result := T.B;
  else
    Result := T.C;
  end;
end;

type
  TSeg = record
    A, B, TA, TB: Integer;
  end;

function ChainsFromSegs(M: TCadMesh; const Segs: array of TSeg): TCadEdgeChains;
var
  Used: array of Boolean;
  StartOf: specialize TDictionary<Integer, Integer>;
  EndSet: specialize TDictionary<Integer, Integer>;
  I, Cur, N: Integer;
  C: TCadEdgeChain;

  procedure Walk(S: Integer);
  begin
    C := Default(TCadEdgeChain);
    C.TriA := Segs[S].TA;
    C.TriB := Segs[S].TB;
    SetLength(C.Pts, 1);
    C.Pts[0] := M.Verts[Segs[S].A];
    Cur := S;
    while (Cur >= 0) and not Used[Cur] do
    begin
      Used[Cur] := True;
      N := Length(C.Pts);
      SetLength(C.Pts, N + 1);
      C.Pts[N] := M.Verts[Segs[Cur].B];
      if not StartOf.TryGetValue(Segs[Cur].B, Cur) then
        Cur := -1;
    end;
    C.Closed := (Length(C.Pts) > 3) and VSame(C.Pts[0], C.Pts[High(C.Pts)], 1E-9);
    if C.Closed then
      SetLength(C.Pts, Length(C.Pts) - 1);
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := C;
  end;

begin
  Result := nil;
  SetLength(Used, Length(Segs));
  StartOf := specialize TDictionary<Integer, Integer>.Create;
  EndSet := specialize TDictionary<Integer, Integer>.Create;
  try
    for I := 0 to High(Segs) do
    begin
      StartOf.AddOrSetValue(Segs[I].A, I);
      EndSet.AddOrSetValue(Segs[I].B, I);
    end;
    { cadeias abertas: comecam num vertice que nao e fim de outro segmento }
    for I := 0 to High(Segs) do
      if not Used[I] and not EndSet.ContainsKey(Segs[I].A) then
        Walk(I);
    for I := 0 to High(Segs) do
      if not Used[I] then
        Walk(I);
  finally
    StartOf.Free;
    EndSet.Free;
  end;
end;

function CadEdgeChains(M: TCadMesh; FA, FB: Integer): TCadEdgeChains;
var
  Map: TEdgeMap;
  I, J, N, Nb: Integer;
  T: TCadTri;
  Segs: array of TSeg;
  S: TSeg;
begin
  Segs := nil;
  Map := BuildEdgeMap(M);
  try
    N := M.VertCount;
    for I := 0 to M.TriCount - 1 do
    begin
      T := M.Tris[I];
      if T.Face <> FA then
        Continue;
      for J := 0 to 2 do
        if Map.TryGetValue(Int64(TriVert(T, J + 1)) * N + TriVert(T, J), Nb) and
          (M.Tris[Nb].Face = FB) then
        begin
          S.A := TriVert(T, J);
          S.B := TriVert(T, J + 1);
          S.TA := I;
          S.TB := Nb;
          SetLength(Segs, Length(Segs) + 1);
          Segs[High(Segs)] := S;
        end;
    end;
  finally
    Map.Free;
  end;
  Result := ChainsFromSegs(M, Segs);
end;

function CadFaceNeighbors(M: TCadMesh; F: Integer): TCadIdArray;
var
  Map: TEdgeMap;
  I, J, K, N, Nb, G: Integer;
  T: TCadTri;
  Found: Boolean;
begin
  Result := nil;
  Map := BuildEdgeMap(M);
  try
    N := M.VertCount;
    for I := 0 to M.TriCount - 1 do
    begin
      T := M.Tris[I];
      if T.Face <> F then
        Continue;
      for J := 0 to 2 do
        if Map.TryGetValue(Int64(TriVert(T, J + 1)) * N + TriVert(T, J), Nb) then
        begin
          G := M.Tris[Nb].Face;
          if G = F then
            Continue;
          Found := False;
          for K := 0 to High(Result) do
            if Result[K] = G then
              Found := True;
          if not Found then
          begin
            SetLength(Result, Length(Result) + 1);
            Result[High(Result)] := G;
          end;
        end;
    end;
  finally
    Map.Free;
  end;
end;

function CadAllEdges(M: TCadMesh): TCadEdgeInfos;
var
  Map: TEdgeMap;
  I, J, N, Nb, K: Integer;
  T: TCadTri;
  Pairs: specialize TDictionary<Int64, Integer>;
  Lists: array of array of TSeg;
  PA, PB: array of Integer;
  S: TSeg;
  Key: Int64;
  Ch: TCadEdgeChains;
begin
  Result := nil;
  Lists := nil;
  PA := nil;
  PB := nil;
  Map := BuildEdgeMap(M);
  Pairs := specialize TDictionary<Int64, Integer>.Create;
  try
    N := M.VertCount;
    for I := 0 to M.TriCount - 1 do
    begin
      T := M.Tris[I];
      for J := 0 to 2 do
        if Map.TryGetValue(Int64(TriVert(T, J + 1)) * N + TriVert(T, J), Nb) then
        begin
          if M.Tris[Nb].Face = T.Face then
            Continue;
          if T.Face > M.Tris[Nb].Face then
            Continue;   { cada aresta uma vez: do lado da face de menor indice }
          { costura invisivel entre faces coplanares }
          if VDot(M.TriNormal(I), M.TriNormal(Nb)) > 0.99999 then
            Continue;
          Key := Int64(T.Face) * M.FaceCount + M.Tris[Nb].Face;
          if not Pairs.TryGetValue(Key, K) then
          begin
            K := Length(Lists);
            Pairs.Add(Key, K);
            SetLength(Lists, K + 1);
            SetLength(PA, K + 1);
            SetLength(PB, K + 1);
            PA[K] := T.Face;
            PB[K] := M.Tris[Nb].Face;
          end;
          S.A := TriVert(T, J);
          S.B := TriVert(T, J + 1);
          S.TA := I;
          S.TB := Nb;
          SetLength(Lists[K], Length(Lists[K]) + 1);
          Lists[K][High(Lists[K])] := S;
        end;
    end;
    for K := 0 to High(Lists) do
    begin
      Ch := ChainsFromSegs(M, Lists[K]);
      for J := 0 to High(Ch) do
      begin
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)].FaceA := PA[K];
        Result[High(Result)].FaceB := PB[K];
        Result[High(Result)].Chain := Ch[J];
      end;
    end;
  finally
    Pairs.Free;
    Map.Free;
  end;
end;

{ ---------- ferramenta do filete/chanfro ---------- }

function ThirdVert(M: TCadMesh; ATri: Integer; const P, Q: TCadVec3): TCadVec3;
var
  T: TCadTri;
  K: Integer;
  V: TCadVec3;
  Best, D: Double;
begin
  T := M.Tris[ATri];
  Result := M.Verts[T.A];
  Best := -1;
  for K := 0 to 2 do
  begin
    V := M.Verts[TriVert(T, K)];
    D := Min(VDist(V, P), VDist(V, Q));
    if D > Best then
    begin
      Best := D;
      Result := V;
    end;
  end;
end;

type
  TV2 = record
    X, Y: Double;
  end;
  TV2Arr = array of TV2;

function V2(X, Y: Double): TV2;
begin
  Result.X := X;
  Result.Y := Y;
end;

function V2Add(const A, B: TV2): TV2;
begin
  Result := V2(A.X + B.X, A.Y + B.Y);
end;

function V2Scale(const A: TV2; S: Double): TV2;
begin
  Result := V2(A.X * S, A.Y * S);
end;

function V2Norm(const A: TV2): TV2;
var
  L: Double;
begin
  L := Sqrt(A.X * A.X + A.Y * A.Y);
  if L < 1E-15 then
    Result := V2(0, 0)
  else
    Result := V2(A.X / L, A.Y / L);
end;

function V2Dot(const A, B: TV2): Double;
begin
  Result := A.X * B.X + A.Y * B.Y;
end;

{ Secao 2D da ferramenta no canto (origem = aresta). tA, tB: direcoes das
  faces a partir da aresta; nA, nB: normais para fora. Devolve o poligono e
  quantos pontos (a partir do primeiro) formam a face nova (arco/chanfro);
  QIdx = ponto de onde o poligono e estrelado (para tampar em leque). }
function Section2D(const tA, tB, nA, nB: TV2; const P: TCadBlendParams;
  out Poly: TV2Arr; out NFace, QIdx: Integer; out IsCut: Boolean; out Center: TV2;
  out AError: string): Boolean;
const
  { a ferramenta nunca encosta tangente nem tem vertice sobre as faces do
    solido (a booleana fica instavel): passa DEPTH mm alem delas }
  DEPTH0 = 0.004;
var
  DEPTH, CT: Double;
  Th, L, Phi, E, S, Al, Step, Rs, Ps, Ex1, Ex2: Double;
  Bis, T1, T2, A, B, U: TV2;
  I, N: Integer;

  procedure Push(const Q: TV2);
  begin
    SetLength(Poly, Length(Poly) + 1);
    Poly[High(Poly)] := Q;
  end;

  function ArcPt(Psi, Scale: Double): TV2;
  begin
    Result := V2Add(Center, V2Scale(V2Add(V2Scale(A, Sin(Phi - Psi)), V2Scale(B, Sin(Psi))),
      Scale / Sin(Phi)));
  end;

begin
  DEPTH := DEPTH0;
  { arco grosso perto da tangencia (faces quase paralelas quebram a booleana
    BSP); a vista suaviza a sombra das faces curvas }
  CT := 0.05;
  Result := False;
  Poly := nil;
  NFace := 0;
  QIdx := 0;
  AError := '';
  Center := V2(0, 0);
  Th := ArcCos(EnsureRange(V2Dot(tA, tB), -1, 1));
  if (Th < DegToRad(1)) or (Th > DegToRad(179)) then
  begin
    AError := 'faces quase tangentes';
    Exit;
  end;
  IsCut := V2Dot(tA, nB) < 0;   { convexa }
  if IsCut then S := 1 else S := -1;
  if P.Kind = bkFillet then
  begin
    L := P.Radius / Tan(Th / 2);
    E := EnsureRange(0.1 * P.Radius, 0.05, 0.5);
    Bis := V2Norm(V2Add(tA, tB));
    Center := V2Scale(Bis, P.Radius / Sin(Th / 2));
    T1 := V2Scale(tA, L);
    T2 := V2Scale(tB, L);
    A := V2(T1.X - Center.X, T1.Y - Center.Y);
    B := V2(T2.X - Center.X, T2.Y - Center.Y);
    Phi := Pi - Th;
    { arco de tangente a tangente: a ferramenta encosta nas faces exatamente
      nos aneis T1/T2 (vertices sobre o solido) e sai em diagonal }
    N := Max(2, Ceil(CadCircleSegments(P.Radius, Max(P.ChordTol, CT)) * Phi / (2 * Pi)));
    N := Min(N, Max(2, Ceil(Phi / DegToRad(15))));
    Step := Phi / N;
    { The tangent endpoints stay at radius R. Only the N-1 internal points
      are scaled: sector area is R^2*sin(Step)*(2*Rs+(N-2)*Rs^2)/2.
      Preserve that area without moving the tangent endpoints. }
    if N=2 then Rs := Phi / (2 * Sin(Step))
    else Rs := (Sqrt(1 + (N-2) * Phi / Sin(Step)) - 1) / (N-2);
    Push(T1);
    for I := 1 to N - 1 do
      Push(ArcPt(I * Step, Rs));
    Push(T2);
    NFace := Length(Poly);
    T1 := Poly[0];
    T2 := Poly[High(Poly)];
  end
  else
  begin
    E := EnsureRange(0.1 * Max(P.D1, P.D2), 0.05, 0.5);
    T1 := V2Scale(tA, P.D1);
    T2 := V2Scale(tB, P.D2);
    U := V2Norm(V2(T1.X - T2.X, T1.Y - T2.Y));
    Ex1 := DEPTH / Max(Abs(V2Dot(U, nA)), 0.05);
    Ex2 := DEPTH / Max(Abs(V2Dot(U, nB)), 0.05);
    T1 := V2Add(T1, V2Scale(U, Ex1));
    T2 := V2Add(T2, V2Scale(U, -Ex2));
    Push(T1);
    Push(T2);
    NFace := 2;
  end;
  { sai do solido em diagonal (cruza as faces num angulo franco) }
  if P.Kind = bkFillet then
  begin
    Push(V2Add(T2, V2Add(V2Scale(tB, E), V2Scale(nB, S * E))));
    QIdx := Length(Poly);
    Push(V2Scale(V2Norm(V2Add(nA, nB)), S * E * 2));
    Push(V2Add(T1, V2Add(V2Scale(tA, E), V2Scale(nA, S * E))));
  end
  else
  begin
    Push(V2Add(T2, V2Scale(nB, S * E)));
    QIdx := Length(Poly);
    Push(V2Scale(V2Norm(V2Add(nA, nB)), S * E * 2));
    Push(V2Add(T1, V2Scale(nA, S * E)));
  end;
  Result := True;
end;

function OrientOut(M: TCadMesh; out AError: string): Boolean;
begin
  if M.Volume < 0 then
    M.Flip;
  M.RefreshPlaneNormals;
  Result := M.CheckClosed(AError);
end;

function FaceNormal(M: TCadMesh; ATri: Integer): TCadVec3;
var
  F: TCadFaceInfo;
begin
  F := M.Faces[M.Tris[ATri].Face];
  if (F.Surf = skPlane) and (VLen(F.Axis) > 0.5) then
    Result := VNorm(F.Axis)
  else
    Result := M.TriNormal(ATri);
end;

function StraightTool(M: TCadMesh; const Chain: TCadEdgeChain; const P: TCadBlendParams;
  const APrefix: string; out IsCut: Boolean; out AError: string): TCadMesh;
var
  P0, Pn, D, NA3, NB3, TA3, TB3, X3, Y3, Base0, Base1, Org: TCadVec3;
  tA, tB, nA, nB, Cen: TV2;
  Poly: TV2Arr;
  NFace, QIdx, I, J, FaceNew, FaceAux, FCap0, FCap1, K: Integer;
  Ext: Double;
  Bot, Top: array of TCadVec3;

  function W(const Q: TV2): TCadVec3;
  begin
    Result := VAdd(VScale(X3, Q.X), VScale(Y3, Q.Y));
  end;

  function To2(const V: TCadVec3): TV2;
  begin
    Result := V2(VDot(V, X3), VDot(V, Y3));
  end;

begin
  Result := nil;
  P0 := Chain.Pts[0];
  Pn := Chain.Pts[High(Chain.Pts)];
  D := VSub(Pn, P0);
  if VLen(D) < 1E-6 then
  begin
    AError := 'aresta degenerada';
    Exit;
  end;
  D := VNorm(D);
  { normal da face plana (o triangulo vizinho pode ser uma lasca de area
    zero deixada pela booleana: normal nula e ferramenta vazia) }
  NA3 := FaceNormal(M, Chain.TriA);
  NB3 := FaceNormal(M, Chain.TriB);
  { o lado de dentro da face fica a esquerda da aresta (sentido do triangulo) }
  TA3 := VNorm(VCross(NA3, D));
  TB3 := VNorm(VCross(NB3, VNeg(D)));
  { base da secao: X = tA, Y perpendicular em relacao a D }
  X3 := TA3;
  Y3 := VNorm(VCross(D, X3));
  tA := To2(TA3);
  tB := To2(TB3);
  nA := To2(NA3);
  nB := To2(NB3);
  if not Section2D(tA, tB, nA, nB, P, Poly, NFace, QIdx, IsCut, Cen, AError) then
    Exit;
  if P.Kind = bkFillet then
    Ext := EnsureRange(0.05 * P.Radius, 0.02, 0.5)
  else
    Ext := EnsureRange(0.05 * Max(P.D1, P.D2), 0.02, 0.5);
  Base0 := VSub(P0, VScale(D, Ext));
  Base1 := VAdd(Pn, VScale(D, Ext));
  SetLength(Bot, Length(Poly));
  SetLength(Top, Length(Poly));
  for I := 0 to High(Poly) do
  begin
    Bot[I] := VAdd(Base0, W(Poly[I]));
    Top[I] := VAdd(Base1, W(Poly[I]));
  end;
  Result := TCadMesh.Create;
  Org := VAdd(P0, W(Cen));
  if P.Kind = bkFillet then
    FaceNew := Result.AddFace(CadFaceInfo(APrefix, skCylinder, Org, D, P.Radius))
  else
    FaceNew := Result.AddPlaneFace(APrefix, P0, VCross(D, VSub(W(Poly[1]), W(Poly[0]))));
  FaceAux := Result.AddPlaneFace(APrefix + '/aux', P0, NA3);
  FCap0 := Result.AddPlaneFace(APrefix + '/ini', Base0, VNeg(D));
  FCap1 := Result.AddPlaneFace(APrefix + '/fim', Base1, D);
  for I := 0 to High(Poly) do
  begin
    J := (I + 1) mod Length(Poly);
    if I < NFace - 1 then
      K := FaceNew
    else
      K := FaceAux;
    Result.AddQuadP(Bot[I], Bot[J], Top[J], Top[I], K);
  end;
  { tampas em leque a partir do ponto Q }
  for I := 0 to High(Poly) do
  begin
    J := (I + 1) mod Length(Poly);
    if (I = QIdx) or (J = QIdx) then
      Continue;
    Result.AddTriP(Bot[QIdx], Bot[J], Bot[I], FCap0);
    Result.AddTriP(Top[QIdx], Top[I], Top[J], FCap1);
  end;
  if not OrientOut(Result, AError) then
  begin
    FreeAndNil(Result);
    AError := 'ferramenta inválida (' + AError + ')';
  end;
end;

function CircularTool(M: TCadMesh; FA, FB: Integer; const Chain: TCadEdgeChain;
  const P: TCadBlendParams; const APrefix: string; out IsCut: Boolean;
  out AError: string): TCadMesh;
var
  InfoA, InfoB, Cyl: TCadFaceInfo;
  PlaneIsA: Boolean;
  Ax, AOrg, O, Mi, Rho, Q, Vp, Vc, NP3, NC3: TCadVec3;
  R0, Z0, Sp, Sc: Double;
  tP, tC, nP, nC, tA, tB, nA, nB, Cen: TV2;
  Poly: TV2Arr;
  NFace, QIdx, I, J, K, Nn, FaceNew, FaceAux: Integer;
  Dirs, Pts, Mid: array of TCadVec3;
  Dist: array of Double;
  N0: Integer;
  Ring: array of array of TCadVec3;
  TriP, TriC: Integer;

  function AxisPoint(const V: TCadVec3): TCadVec3;
  begin
    Result := VAdd(AOrg, VScale(Ax, VDot(VSub(V, AOrg), Ax)));
  end;

  function Sgn(X: Double): Double;
  begin
    if X < 0 then Result := -1 else Result := 1;
  end;

begin
  Result := nil;
  InfoA := M.Faces[FA];
  InfoB := M.Faces[FB];
  PlaneIsA := InfoA.Surf = skPlane;
  if PlaneIsA then
  begin
    Cyl := InfoB;
    TriP := Chain.TriA;
    TriC := Chain.TriB;
  end
  else
  begin
    Cyl := InfoA;
    TriP := Chain.TriB;
    TriC := Chain.TriA;
  end;
  if not Chain.Closed then
  begin
    AError := 'aresta circular parcial ainda não suportada';
    Exit;
  end;
  Ax := VNorm(Cyl.Axis);
  AOrg := Cyl.Origin;
  O := AxisPoint(Chain.Pts[0]);
  R0 := VDist(Chain.Pts[0], O);
  { direcoes 2D: x = radial, y = axial (a partir da aresta) }
  Mi := VLerp(Chain.Pts[0], Chain.Pts[1], 0.5);
  Rho := VNorm(VSub(Mi, AxisPoint(Mi)));
  NP3 := FaceNormal(M, TriP);
  NC3 := M.TriNormal(TriC);
  { direcao para dentro de cada face: a esquerda do segmento no sentido do
    triangulo (Pts[0] -> Pts[1] na face A, ao contrario na B) }
  Vp := VSub(Chain.Pts[1], Chain.Pts[0]);
  if PlaneIsA then
  begin
    Vp := VCross(NP3, Vp);
    Vc := VCross(NC3, VNeg(VSub(Chain.Pts[1], Chain.Pts[0])));
  end
  else
  begin
    Vc := VCross(NC3, Vp);
    Vp := VCross(NP3, VNeg(VSub(Chain.Pts[1], Chain.Pts[0])));
  end;
  Sp := Sgn(VDot(Vp, Rho));
  Sc := Sgn(VDot(Vc, Ax));
  tP := V2(Sp, 0);
  tC := V2(0, Sc);
  nP := V2(0, Sgn(VDot(NP3, Ax)));
  nC := V2(Sgn(VDot(NC3, Rho)), 0);
  if PlaneIsA then
  begin
    tA := tP; nA := nP; tB := tC; nB := nC;
  end
  else
  begin
    tA := tC; nA := nC; tB := tP; nB := nP;
  end;
  if not Section2D(tA, tB, nA, nB, P, Poly, NFace, QIdx, IsCut, Cen, AError) then
    Exit;
  Z0 := VDot(VSub(O, AOrg), Ax);
  for I := 0 to High(Poly) do
    if R0 + Poly[I].X < 1E-3 then
    begin
      AError := 'raio maior que o furo/ressalto';
      Exit;
    end;
  { pontos do poligono do solido (sem os intermediarios colineares) }
  Pts := nil;
  N0 := Length(Chain.Pts);
  for J := 0 to N0 - 1 do
  begin
    Q := VCross(VSub(Chain.Pts[J], Chain.Pts[(J + N0 - 1) mod N0]),
      VSub(Chain.Pts[(J + 1) mod N0], Chain.Pts[J]));
    if VLen(Q) > 1E-9 * Max(1, Sqr(R0)) then
    begin
      SetLength(Pts, Length(Pts) + 1);
      Pts[High(Pts)] := Chain.Pts[J];
    end;
  end;
  Nn := Length(Pts);
  if Nn < 3 then
  begin
    AError := 'aresta circular degenerada';
    Exit;
  end;
  { aneis = offset paralelo exato do poligono do solido (cada faceta anda X
    pela sua normal): perto da tangencia as faces da ferramenta ficam
    paralelas as facetas, sem cruzamentos rasantes que quebram a booleana }
  SetLength(Dirs, Nn);
  SetLength(Mid, Nn);
  SetLength(Dist, Nn);
  for J := 0 to Nn - 1 do
  begin
    { normal (para fora do eixo) da faceta J -> J+1 }
    Q := VNorm(VCross(VSub(Pts[(J + 1) mod Nn], Pts[J]), Ax));
    if VDot(Q, VSub(Pts[J], AxisPoint(Pts[J]))) < 0 then
      Q := VNeg(Q);
    Mid[J] := Q;
  end;
  for J := 0 to Nn - 1 do
  begin
    Dirs[J] := VNorm(VAdd(Mid[(J + Nn - 1) mod Nn], Mid[J]));
    Dist[J] := 1 / Max(0.2, VDot(Dirs[J], Mid[J]));
  end;
  SetLength(Ring, Length(Poly), Nn);
  for I := 0 to High(Poly) do
    for J := 0 to Nn - 1 do
      Ring[I][J] := VAdd(VAdd(Pts[J], VScale(Ax, Poly[I].Y)), VScale(Dirs[J], Poly[I].X * Dist[J]));
  Result := TCadMesh.Create;
  Q := VAdd(AOrg, VScale(Ax, Z0 + Cen.Y));
  if P.Kind = bkFillet then
    FaceNew := Result.AddFace(CadFaceInfo(APrefix, skTorus, Q, Ax, R0 + Cen.X, P.Radius))
  else
    FaceNew := Result.AddFace(CadFaceInfo(APrefix, skCone, O, Ax, R0));
  FaceAux := Result.AddFace(CadFaceInfo(APrefix + '/aux', skOther, O, Ax));
  for I := 0 to High(Poly) do
  begin
    K := (I + 1) mod Length(Poly);
    for J := 0 to Nn - 1 do
      if I < NFace - 1 then
        Result.AddQuadP(Ring[I][J], Ring[K][J], Ring[K][(J + 1) mod Nn], Ring[I][(J + 1) mod Nn], FaceNew)
      else
        Result.AddQuadP(Ring[I][J], Ring[K][J], Ring[K][(J + 1) mod Nn], Ring[I][(J + 1) mod Nn], FaceAux);
  end;
  if not OrientOut(Result, AError) then
  begin
    FreeAndNil(Result);
    AError := 'ferramenta inválida (' + AError + ')';
  end;
end;

function CadBlendTool(M: TCadMesh; FA, FB: Integer; const Chain: TCadEdgeChain;
  const P: TCadBlendParams; const APrefix: string; out IsCut: Boolean;
  out AError: string): TCadMesh;
var
  SA, SB: TCadSurfKind;
begin
  Result := nil;
  IsCut := True;
  AError := '';
  if Length(Chain.Pts) < 2 then
  begin
    AError := 'aresta vazia';
    Exit;
  end;
  SA := M.Faces[FA].Surf;
  SB := M.Faces[FB].Surf;
  if (SA = skPlane) and (SB = skPlane) then
  begin
    if Chain.Closed then
      AError := 'aresta fechada entre planos'
    else
      Result := StraightTool(M, Chain, P, APrefix, IsCut, AError);
  end
  else if ((SA = skPlane) and (SB = skCylinder)) or ((SA = skCylinder) and (SB = skPlane)) then
    Result := CircularTool(M, FA, FB, Chain, P, APrefix, IsCut, AError)
  else
    AError := 'tipo de aresta ainda não suportado (só reta entre planos e circular entre plano e cilindro)';
end;

{ ---------- casca ---------- }

function Solve3(const A: array of Double; const B: TCadVec3; out X: TCadVec3): Boolean;
var
  Det: Double;
  M: array[0..8] of Double;
  I: Integer;
begin
  for I := 0 to 8 do
    M[I] := A[I];
  Det := M[0] * (M[4] * M[8] - M[5] * M[7]) - M[1] * (M[3] * M[8] - M[5] * M[6]) +
    M[2] * (M[3] * M[7] - M[4] * M[6]);
  Result := Abs(Det) > 1E-18;
  if not Result then
    Exit;
  X.X := (B.X * (M[4] * M[8] - M[5] * M[7]) - M[1] * (B.Y * M[8] - M[5] * B.Z) +
    M[2] * (B.Y * M[7] - M[4] * B.Z)) / Det;
  X.Y := (M[0] * (B.Y * M[8] - M[5] * B.Z) - B.X * (M[3] * M[8] - M[5] * M[6]) +
    M[2] * (M[3] * B.Z - B.Y * M[6])) / Det;
  X.Z := (M[0] * (M[4] * B.Z - B.Y * M[7]) - M[1] * (M[3] * B.Z - B.Y * M[6]) +
    B.X * (M[3] * M[7] - M[4] * M[6])) / Det;
end;

function CadOffsetMesh(M: TCadMesh; TKeep, TRemoved: Double;
  const Removed: array of Boolean; out AError: string): TCadMesh;
type
  TNList = array of TCadVec3;
var
  Ns: array of TNList;
  Ts: array of array of Double;
  I, K, V, J: Integer;
  T: TCadTri;
  N, D, B: TCadVec3;
  Tv: Double;
  Dup: Boolean;
  A: array[0..8] of Double;
const
  EPS = 1E-7;
begin
  AError := '';
  SetLength(Ns, M.VertCount);
  SetLength(Ts, M.VertCount);
  for I := 0 to M.TriCount - 1 do
  begin
    T := M.Tris[I];
    if M.TriArea(I) < 1E-12 then
      Continue;
    N := M.TriNormal(I);
    if (T.Face >= 0) and (T.Face <= High(Removed)) and Removed[T.Face] then
      Tv := TRemoved
    else
      Tv := TKeep;
    for K := 0 to 2 do
    begin
      V := TriVert(T, K);
      Dup := False;
      for J := 0 to High(Ns[V]) do
        if (VDot(Ns[V][J], N) > 0.999999) and (Abs(Ts[V][J] - Tv) < 1E-12) then
          Dup := True;
      if Dup then
        Continue;
      SetLength(Ns[V], Length(Ns[V]) + 1);
      Ns[V][High(Ns[V])] := N;
      SetLength(Ts[V], Length(Ts[V]) + 1);
      Ts[V][High(Ts[V])] := Tv;
    end;
  end;
  Result := M.Clone;
  for V := 0 to M.VertCount - 1 do
  begin
    FillChar(A, SizeOf(A), 0);
    B := V3(0, 0, 0);
    for J := 0 to High(Ns[V]) do
    begin
      N := Ns[V][J];
      A[0] += N.X * N.X; A[1] += N.X * N.Y; A[2] += N.X * N.Z;
      A[3] += N.Y * N.X; A[4] += N.Y * N.Y; A[5] += N.Y * N.Z;
      A[6] += N.Z * N.X; A[7] += N.Z * N.Y; A[8] += N.Z * N.Z;
      B := VAdd(B, VScale(N, Ts[V][J]));
    end;
    A[0] += EPS; A[4] += EPS; A[8] += EPS;
    if not Solve3(A, B, D) then
      D := V3(0, 0, 0);
    Result.SetVert(V, VAdd(M.Verts[V], D));
  end;
  Result.RefreshPlaneNormals;
end;

end.
