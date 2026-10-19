unit multiphysics_mesh;

{ Malha tetraedrica das pecas para o FEM.

  Cada primitiva (multiphysics_geometry) vira uma secao 2D triangulada,
  extrudada em camadas ao longo do eixo; cada prisma triangular vira 3
  tetraedros. Com os vertices do triangulo em ordem crescente de indice
  (a < b < c) e a camada de cima com o mesmo deslocamento de indice, os
  tetraedros [a b c a'] [b c a' b'] [c a' b' c'] escolhem em cada face
  lateral a diagonal "maior de baixo -> menor de cima", igual nos dois
  prismas vizinhos: a malha fica conforme sem nenhum ajuste.

  Faces de contorno: triangulos que pertencem a um so tetraedro, cada um
  com a etiqueta "PECA/PRIMITIVA/face" (ver PrimFaceNames) e normal para
  fora. ConvertToTet10 acrescenta os nos de meio de aresta (C3D10:
  4:(0,1) 5:(1,2) 6:(2,0) 7:(0,3) 8:(1,3) 9:(2,3); triangulo: 3:(0,1)
  4:(1,2) 5:(2,0)). Coordenadas em metros. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, multiphysics_vector, multiphysics_geometry;

type
  TMeshElement = record
    N: array[0..9] of Integer;
    Part: Integer;
    Body: Integer;               { primitiva de origem (malhas separadas, amarradas pelo contato) }
  end;

  TMeshFace = record
    N: array[0..5] of Integer;   { 0..2 cantos (normal para fora), 3..5 meio de aresta }
    Tag: Integer;                { indice em FaceNames; -1 = sem nome }
    Elem: Integer;
  end;

  TMeshQuality = record
    Elements: Integer;
    Inverted: Integer;           { volume <= 0 }
    Poor: Integer;               { forma < 0,1 }
    MinShape, MeanShape: Double; { 1 = tetraedro regular }
  end;

  TIntArray = array of Integer;

  TFEMMesh = class
  private
    FTagKeys: array of Int64;    { chaves dos triangulos etiquetados durante a geracao }
    FTagHi: array of Integer;
    FTagVals: array of Integer;
    FTagCount: Integer;
    FCurBody: Integer;
    procedure AddTet(A, B, C, D, Part: Integer);
    procedure TagTri(A, B, C, Tag: Integer);
    function FaceTagId(const Name: string): Integer;
  public
    Nodes: array of TVector3;
    NodeCount: Integer;
    Elems: array of TMeshElement;
    ElemCount: Integer;
    Faces: array of TMeshFace;
    FaceCount: Integer;
    Order: Integer;              { 1 = TET4, 2 = TET10 }
    BodyCount: Integer;
    BodyPart: array of Integer;  { peca de cada corpo (primitiva) }
    PartNames: TStringList;
    FaceNames: TStringList;
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    function AddPart(const Name: string): Integer;
    function AddNode(const P: TVector3): Integer;
    { gera a malha da primitiva (coordenadas da peca transformadas por T),
      tamanho alvo H (m) }
    procedure AddPrimitive(Part: Integer; const Prim: TGeoPrimitive;
      const T: TGeoTransform; H: Double);
    { monta as faces de contorno; chamar depois de todas as primitivas }
    procedure Finalize;
    procedure ConvertToTet10;
    function NodesPerElement: Integer;
    function ElemVolume(E: Integer): Double;
    function Volume: Double;
    function PartVolume(Part: Integer): Double;
    function Quality: TMeshQuality;
    function FindTag(const Name: string): Integer;
    { nos (cantos e meio) das faces com a etiqueta }
    function NodesOfTag(Tag: Integer): TIntArray;
    function TagArea(Tag: Integer): Double;
    function FaceArea(F: Integer): Double;
    function FaceNormal(F: Integer): TVector3;   { unitaria, para fora }
  end;

{ triangula um poligono simples (ear clipping); devolve triangulos com
  indices nos vertices do poligono }
function EarClip(const Poly: array of TVector2; out Tris: TIntArray): Boolean;

implementation

type
  TSection = record
    Pts: array of TVector2;
    Tris: array of Integer;      { 3 por triangulo }
  end;

function TetSignedVolume(const A, B, C, D: TVector3): Double;
begin
  Result := VDot(VSub(B, A), VCross(VSub(C, A), VSub(D, A))) / 6;
end;

function TriKey(A, B, C, N: Integer; out Hi: Integer): Int64;
var
  T: Integer;
begin
  if A > B then begin T := A; A := B; B := T; end;
  if B > C then begin T := B; B := C; C := T; end;
  if A > B then begin T := A; A := B; B := T; end;
  Result := Int64(A) * N + B;
  Hi := C;
end;

{ ---------------- secoes 2D ---------------- }

function SecAddPt(var S: TSection; U, V: Double): Integer;
begin
  Result := Length(S.Pts);
  SetLength(S.Pts, Result + 1);
  S.Pts[Result] := V2(U, V);
end;

procedure SecAddTri(var S: TSection; A, B, C: Integer);
var
  N: Integer;
  Ar: Double;
  T: Integer;
begin
  if (A = B) or (B = C) or (A = C) then Exit;
  Ar := (S.Pts[B].U - S.Pts[A].U) * (S.Pts[C].V - S.Pts[A].V) -
        (S.Pts[C].U - S.Pts[A].U) * (S.Pts[B].V - S.Pts[A].V);
  if Abs(Ar) < 1e-30 then Exit;
  if Ar < 0 then begin T := B; B := C; C := T; end;
  N := Length(S.Tris);
  SetLength(S.Tris, N + 3);
  S.Tris[N] := A; S.Tris[N + 1] := B; S.Tris[N + 2] := C;
end;

procedure RectSection(W, D, H: Double; out S: TSection);
var
  NU, NV, I, J: Integer;
  function Id(I, J: Integer): Integer; begin Result := J * (NU + 1) + I; end;
begin
  S.Pts := nil; S.Tris := nil;
  NU := Max(1, Ceil(W / H - 1e-9));
  NV := Max(1, Ceil(D / H - 1e-9));
  for J := 0 to NV do
    for I := 0 to NU do
      SecAddPt(S, W * I / NU, D * J / NV);
  for J := 0 to NV - 1 do
    for I := 0 to NU - 1 do
    begin
      SecAddTri(S, Id(I, J), Id(I + 1, J), Id(I + 1, J + 1));
      SecAddTri(S, Id(I, J), Id(I + 1, J + 1), Id(I, J + 1));
    end;
end;

{ aneis concentricos (disco, coroa, setor), zipados de dois em dois }
procedure RingSection(const P: TGeoPrimitive; H: Double; out S: TSection);
var
  NR, NOut, K, J, IA, IB, SegA, SegB: Integer;
  Full: Boolean;
  Th0, Span, Rho: Double;
  Start, Cnt: array of Integer;   { inicio e numero de nos de cada anel }
  Segs: array of Integer;          { segmentos de cada anel }

  function RingNode(K, J: Integer): Integer;
  begin
    if Cnt[K] = 1 then Exit(Start[K]);
    if Full then Result := Start[K] + (J mod Segs[K]) else Result := Start[K] + J;
  end;

begin
  S.Pts := nil; S.Tris := nil;
  Full := IsFullCircle(P);
  Th0 := DegToRad(P.Arc0 + P.Rot);
  if Full then Span := 2 * Pi else Span := DegToRad(P.Arc1 - P.Arc0);
  NR := Max(1, Ceil((P.R - P.RI) / H - 1e-9));
  if Full then NOut := Max(12, Round(Span * P.R / H))
  else NOut := Max(Max(2, Ceil(Span / (Pi / 6))), Round(Span * P.R / H));
  SetLength(Start, NR + 1); SetLength(Cnt, NR + 1); SetLength(Segs, NR + 1);
  for K := 0 to NR do
  begin
    Rho := P.RI + (P.R - P.RI) * K / NR;
    Start[K] := Length(S.Pts);
    if Rho <= 1e-12 then
    begin
      Segs[K] := 0; Cnt[K] := 1;
      SecAddPt(S, 0, 0);
      Continue;
    end;
    if Full then Segs[K] := Max(6, Round(NOut * Rho / P.R))
    else Segs[K] := Max(1, Round(NOut * Rho / P.R));
    if Full then Cnt[K] := Segs[K] else Cnt[K] := Segs[K] + 1;
    for J := 0 to Cnt[K] - 1 do
      SecAddPt(S, Rho * Cos(Th0 + Span * J / Segs[K]), Rho * Sin(Th0 + Span * J / Segs[K]));
  end;
  for K := 0 to NR - 1 do
  begin
    if Cnt[K] = 1 then
    begin
      for J := 0 to Segs[K + 1] - 1 do
        SecAddTri(S, Start[K], RingNode(K + 1, J), RingNode(K + 1, J + 1));
      Continue;
    end;
    SegA := Segs[K]; SegB := Segs[K + 1];
    IA := 0; IB := 0;
    while (IA < SegA) or (IB < SegB) do
    begin
      { avanca no anel cujo proximo no tem o menor parametro angular }
      if (IB < SegB) and ((IA >= SegA) or ((IB + 1) / SegB <= (IA + 1) / SegA)) then
      begin
        SecAddTri(S, RingNode(K, IA), RingNode(K + 1, IB), RingNode(K + 1, IB + 1));
        Inc(IB);
      end
      else
      begin
        SecAddTri(S, RingNode(K, IA), RingNode(K + 1, IB), RingNode(K, IA + 1));
        Inc(IA);
      end;
    end;
  end;
end;

function PointInTri(const P, A, B, C: TVector2): Boolean;
var
  D1, D2, D3: Double;
begin
  D1 := (B.U - A.U) * (P.V - A.V) - (B.V - A.V) * (P.U - A.U);
  D2 := (C.U - B.U) * (P.V - B.V) - (C.V - B.V) * (P.U - B.U);
  D3 := (A.U - C.U) * (P.V - C.V) - (A.V - C.V) * (P.U - C.U);
  Result := (D1 >= 0) and (D2 >= 0) and (D3 >= 0);
end;

function EarClip(const Poly: array of TVector2; out Tris: TIntArray): Boolean;
var
  Idx: array of Integer;
  N, I, J, Guard, Prev, Next, NT: Integer;
  A, B, C: TVector2;
  Ear: Boolean;
  Ccw: Boolean;
begin
  Tris := nil;
  N := Length(Poly);
  Result := N >= 3;
  if not Result then Exit;
  Ccw := PolygonArea(Poly) > 0;
  SetLength(Idx, N);
  for I := 0 to N - 1 do
    if Ccw then Idx[I] := I else Idx[I] := N - 1 - I;
  NT := 0;
  SetLength(Tris, 3 * (N - 2));
  Guard := 0;
  I := 0;
  while (N > 3) and (Guard < 10000) do
  begin
    Inc(Guard);
    Prev := (I + N - 1) mod N; Next := (I + 1) mod N;
    A := Poly[Idx[Prev]]; B := Poly[Idx[I]]; C := Poly[Idx[Next]];
    Ear := (B.U - A.U) * (C.V - A.V) - (B.V - A.V) * (C.U - A.U) > 1e-30;
    if Ear then
      for J := 0 to N - 1 do
        if (J <> Prev) and (J <> I) and (J <> Next) and PointInTri(Poly[Idx[J]], A, B, C) then
        begin
          Ear := False;
          Break;
        end;
    if Ear then
    begin
      Tris[NT] := Idx[Prev]; Tris[NT + 1] := Idx[I]; Tris[NT + 2] := Idx[Next];
      Inc(NT, 3);
      Delete(Idx, I, 1);
      Dec(N);
      if I >= N then I := 0;
    end
    else
      I := (I + 1) mod N;
  end;
  if N = 3 then
  begin
    Tris[NT] := Idx[0]; Tris[NT + 1] := Idx[1]; Tris[NT + 2] := Idx[2];
    Inc(NT, 3);
  end;
  SetLength(Tris, NT);
  Result := NT = 3 * (Length(Poly) - 2);
end;

{ poligono: ear clipping e subdivisao uniforme de cada triangulo em M^2
  (M igual para todos: arestas compartilhadas recebem os mesmos nos) }
procedure PolySection(const Poly: array of TVector2; H: Double; out S: TSection);
var
  T: TIntArray;
  Keys: TStringList;
  MaxL, L: Double;
  M, K, I, J, A, B, C: Integer;
  Grid: array of array of Integer;
  PA, PB, PC: TVector2;

  function NodeAt(U, V: Double): Integer;
  var
    Key: string;
    P: Integer;
  begin
    Key := Format('%.6f;%.6f', [U * 1e3, V * 1e3]);
    P := Keys.IndexOf(Key);
    if P >= 0 then Exit(PtrInt(Keys.Objects[P]));
    Result := SecAddPt(S, U, V);
    Keys.AddObject(Key, TObject(PtrInt(Result)));
  end;

begin
  S.Pts := nil; S.Tris := nil;
  if not EarClip(Poly, T) then Exit;
  MaxL := 0;
  for K := 0 to Length(T) div 3 - 1 do
    for I := 0 to 2 do
    begin
      PA := Poly[T[3 * K + I]]; PB := Poly[T[3 * K + (I + 1) mod 3]];
      L := Hypot(PB.U - PA.U, PB.V - PA.V);
      if L > MaxL then MaxL := L;
    end;
  M := Max(1, Ceil(MaxL / H - 1e-9));
  Keys := TStringList.Create;
  try
    Keys.Sorted := True;
    for K := 0 to Length(T) div 3 - 1 do
    begin
      PA := Poly[T[3 * K]]; PB := Poly[T[3 * K + 1]]; PC := Poly[T[3 * K + 2]];
      SetLength(Grid, M + 1);
      for I := 0 to M do
      begin
        SetLength(Grid[I], M + 1 - I);
        for J := 0 to M - I do
          Grid[I][J] := NodeAt(PA.U + (PB.U - PA.U) * I / M + (PC.U - PA.U) * J / M,
                               PA.V + (PB.V - PA.V) * I / M + (PC.V - PA.V) * J / M);
      end;
      for I := 0 to M - 1 do
        for J := 0 to M - 1 - I do
        begin
          A := Grid[I][J]; B := Grid[I + 1][J]; C := Grid[I][J + 1];
          SecAddTri(S, A, B, C);
          if J < M - 1 - I then SecAddTri(S, B, Grid[I + 1][J + 1], C);
        end;
    end;
  finally
    Keys.Free;
  end;
end;

{ ---------------- TFEMMesh ---------------- }

constructor TFEMMesh.Create;
begin
  inherited Create;
  PartNames := TStringList.Create;
  FaceNames := TStringList.Create;
  Clear;
end;

destructor TFEMMesh.Destroy;
begin
  FaceNames.Free;
  PartNames.Free;
  inherited Destroy;
end;

procedure TFEMMesh.Clear;
begin
  Nodes := nil; NodeCount := 0;
  Elems := nil; ElemCount := 0;
  Faces := nil; FaceCount := 0;
  FTagKeys := nil; FTagHi := nil; FTagVals := nil; FTagCount := 0;
  Order := 1;
  BodyCount := 0;
  BodyPart := nil;
  PartNames.Clear;
  FaceNames.Clear;
end;

function TFEMMesh.AddPart(const Name: string): Integer;
begin
  Result := PartNames.Add(Name);
end;

function TFEMMesh.AddNode(const P: TVector3): Integer;
begin
  if NodeCount >= Length(Nodes) then SetLength(Nodes, Max(64, 2 * Length(Nodes)));
  Nodes[NodeCount] := P;
  Result := NodeCount;
  Inc(NodeCount);
end;

procedure TFEMMesh.AddTet(A, B, C, D, Part: Integer);
var
  T: Integer;
begin
  if TetSignedVolume(Nodes[A], Nodes[B], Nodes[C], Nodes[D]) < 0 then
  begin
    T := B; B := C; C := T;
  end;
  if ElemCount >= Length(Elems) then SetLength(Elems, Max(64, 2 * Length(Elems)));
  FillChar(Elems[ElemCount], SizeOf(TMeshElement), $FF);
  Elems[ElemCount].N[0] := A; Elems[ElemCount].N[1] := B;
  Elems[ElemCount].N[2] := C; Elems[ElemCount].N[3] := D;
  Elems[ElemCount].Part := Part;
  Elems[ElemCount].Body := FCurBody;
  Inc(ElemCount);
end;

procedure TFEMMesh.TagTri(A, B, C, Tag: Integer);
var
  Hi: Integer;
begin
  if FTagCount >= Length(FTagKeys) then
  begin
    SetLength(FTagKeys, Max(64, 2 * Length(FTagKeys)));
    SetLength(FTagHi, Length(FTagKeys));
    SetLength(FTagVals, Length(FTagKeys));
  end;
  FTagKeys[FTagCount] := TriKey(A, B, C, MaxInt div 2, Hi);
  FTagHi[FTagCount] := Hi;
  FTagVals[FTagCount] := Tag;
  Inc(FTagCount);
end;

function TFEMMesh.FaceTagId(const Name: string): Integer;
begin
  Result := FaceNames.IndexOf(Name);
  if Result < 0 then Result := FaceNames.Add(Name);
end;

procedure TFEMMesh.AddPrimitive(Part: Integer; const Prim: TGeoPrimitive;
  const T: TGeoTransform; H: Double);
var
  S: TSection;
  Height, Rt, Rho, Scale, U, V, Fz, Th0, Th1: Double;
  NW, N2, Base, L, I, K, A, B, C, Tg, TgBase, TgTop, NE, J: Integer;
  Prefix: string;
  EdgeKeys: array of Int64;
  Mid: TVector2;

  function G(Layer, I: Integer): Integer;
  begin
    Result := Base + Layer * N2 + I;
  end;

  procedure AddEdge(P, Q: Integer);
  begin
    if P < Q then EdgeKeys[NE] := Int64(P) * N2 + Q else EdgeKeys[NE] := Int64(Q) * N2 + P;
    Inc(NE);
  end;

  procedure SortEdges(L, R: Integer);
  var
    P, Q: Integer;
    Pv, T: Int64;
  begin
    while L < R do
    begin
      Pv := EdgeKeys[(L + R) shr 1]; P := L; Q := R;
      repeat
        while EdgeKeys[P] < Pv do Inc(P);
        while Pv < EdgeKeys[Q] do Dec(Q);
        if P <= Q then
        begin
          T := EdgeKeys[P]; EdgeKeys[P] := EdgeKeys[Q]; EdgeKeys[Q] := T;
          Inc(P); Dec(Q);
        end;
      until P > Q;
      if Q - L < R - P then begin SortEdges(L, Q); L := P; end
      else begin SortEdges(P, R); R := Q; end;
    end;
  end;

  { nome da face lateral de uma aresta de contorno da secao }
  function SideName(const M: TVector2): string;
  var
    R0, Best, D, Lx, Px, Py, Qx, Qy, Tt: Double;
    J, Jn: Integer;
  begin
    case Prim.Kind of
      gpBox:
        begin
          if Abs(M.U) < 1e-9 then Exit('xmin');
          if Abs(M.U - Prim.Size.X) < 1e-9 then Exit('xmax');
          if Abs(M.V) < 1e-9 then Exit('ymin');
          Exit('ymax');
        end;
      gpCyl:
        begin
          R0 := Hypot(M.U, M.V);
          if not IsFullCircle(Prim) then
          begin
            { cortes radiais: distancia a reta pelo centro com o angulo do corte }
            if Abs(-Sin(Th0) * M.U + Cos(Th0) * M.V) < 1e-10 + 1e-7 * Prim.R then Exit('corte0');
            if Abs(-Sin(Th1) * M.U + Cos(Th1) * M.V) < 1e-10 + 1e-7 * Prim.R then Exit('corte1');
          end;
          if (Prim.RI > 0) and (Abs(R0 - Prim.RI) < Abs(R0 - Prim.R)) then Exit('interna');
          Exit('lateral');
        end;
      else
      begin
        { lado do poligono mais proximo do ponto medio }
        Best := MaxDouble; Result := 'lado0';
        for J := 0 to High(Prim.Poly) do
        begin
          Jn := (J + 1) mod Length(Prim.Poly);
          Px := Prim.Poly[J].U; Py := Prim.Poly[J].V;
          Qx := Prim.Poly[Jn].U - Px; Qy := Prim.Poly[Jn].V - Py;
          Lx := Qx * Qx + Qy * Qy;
          if Lx <= 0 then Continue;
          Tt := EnsureRange(((M.U - Px) * Qx + (M.V - Py) * Qy) / Lx, 0, 1);
          D := Hypot(M.U - (Px + Tt * Qx), M.V - (Py + Tt * Qy));
          if D < Best then begin Best := D; Result := 'lado' + IntToStr(J); end;
        end;
      end;
    end;
  end;

begin
  case Prim.Kind of
    gpBox:
      begin
        RectSection(Prim.Size.X, Prim.Size.Y, H, S);
        Height := Prim.Size.Z;
      end;
    gpCyl:
      begin
        RingSection(Prim, H, S);
        Height := Prim.H;
      end;
    else
    begin
      PolySection(Prim.Poly, H, S);
      Height := Prim.H;
    end;
  end;
  Th0 := DegToRad(Prim.Arc0 + Prim.Rot);
  Th1 := DegToRad(Prim.Arc1 + Prim.Rot);
  N2 := Length(S.Pts);
  if (N2 = 0) or (Height <= 0) then Exit;
  NW := Max(1, Ceil(Height / H - 1e-9));
  Base := NodeCount;
  FCurBody := BodyCount;
  Inc(BodyCount);
  SetLength(BodyPart, BodyCount);
  BodyPart[FCurBody] := Part;
  Prefix := PartNames[Part] + '/' + Prim.ID + '/';
  { nos: camadas ao longo do eixo; no cone o raio externo varia com a altura }
  for L := 0 to NW do
  begin
    Fz := L / NW;
    for I := 0 to N2 - 1 do
    begin
      U := S.Pts[I].U; V := S.Pts[I].V;
      if (Prim.Kind = gpCyl) and (Abs(Prim.R2 - Prim.R) > 1e-15) and (Prim.R > Prim.RI) then
      begin
        Rt := Prim.R + (Prim.R2 - Prim.R) * Fz;
        Rho := Hypot(U, V);
        if Rho > 0 then
        begin
          Scale := (Prim.RI + (Rho - Prim.RI) * (Rt - Prim.RI) / (Prim.R - Prim.RI)) / Rho;
          U := U * Scale; V := V * Scale;
        end;
      end;
      AddNode(ApplyTransform(T, PrimLocalToPart(Prim, U, V, Height * Fz)));
    end;
  end;
  { tetraedros e faces da base e do topo }
  if Prim.Kind = gpBox then TgBase := FaceTagId(Prefix + 'zmin') else TgBase := FaceTagId(Prefix + 'base');
  if Prim.Kind = gpBox then TgTop := FaceTagId(Prefix + 'zmax') else TgTop := FaceTagId(Prefix + 'topo');
  SetLength(EdgeKeys, Length(S.Tris));
  NE := 0;
  for K := 0 to Length(S.Tris) div 3 - 1 do
  begin
    A := S.Tris[3 * K]; B := S.Tris[3 * K + 1]; C := S.Tris[3 * K + 2];
    { ordena a < b < c }
    if A > B then begin I := A; A := B; B := I; end;
    if B > C then begin I := B; B := C; C := I; end;
    if A > B then begin I := A; A := B; B := I; end;
    for L := 0 to NW - 1 do
    begin
      AddTet(G(L, A), G(L, B), G(L, C), G(L + 1, A), Part);
      AddTet(G(L, B), G(L, C), G(L + 1, A), G(L + 1, B), Part);
      AddTet(G(L, C), G(L + 1, A), G(L + 1, B), G(L + 1, C), Part);
    end;
    TagTri(G(0, A), G(0, B), G(0, C), TgBase);
    TagTri(G(NW, A), G(NW, B), G(NW, C), TgTop);
    AddEdge(A, B); AddEdge(B, C); AddEdge(A, C);
  end;
  { faces laterais: arestas da secao que pertencem a um so triangulo }
  if NE > 1 then SortEdges(0, NE - 1);
  K := 0;
  while K < NE do
  begin
    J := K + 1;
    while (J < NE) and (EdgeKeys[J] = EdgeKeys[K]) do Inc(J);
    if J - K > 1 then begin K := J; Continue; end;
    A := EdgeKeys[K] div N2; B := EdgeKeys[K] mod N2;   { A < B }
    K := J;
    Mid := V2((S.Pts[A].U + S.Pts[B].U) / 2, (S.Pts[A].V + S.Pts[B].V) / 2);
    Tg := FaceTagId(Prefix + SideName(Mid));
    for L := 0 to NW - 1 do
    begin
      { diagonal: maior de baixo (B) -> menor de cima (A') }
      TagTri(G(L, A), G(L, B), G(L + 1, A), Tg);
      TagTri(G(L, B), G(L + 1, B), G(L + 1, A), Tg);
    end;
  end;
end;

procedure TFEMMesh.Finalize;
const
  Loc: array[0..3, 0..2] of Integer = ((1, 2, 3), (0, 2, 3), (0, 1, 3), (0, 1, 2));
type
  TFaceRec = record
    Key: Int64;
    Hi, Elem, Opp: Integer;     { Opp = vertice oposto (indice local) }
  end;
var
  Recs: array of TFaceRec;
  Order3: array of Integer;
  N, E, K, I, J, Lo, Hi2, M, Tag: Integer;
  A, B, C, D, Tmp: Integer;
  Nrm: TVector3;
  KeyT: Int64;
  HiT: Integer;

  function Less(const X, Y: TFaceRec): Boolean;
  begin
    Result := (X.Key < Y.Key) or ((X.Key = Y.Key) and (X.Hi < Y.Hi));
  end;

  procedure SortRecs(L, R: Integer);
  var
    P, Q: Integer;
    Pv, T: TFaceRec;
  begin
    while L < R do
    begin
      Pv := Recs[(L + R) shr 1]; P := L; Q := R;
      repeat
        while Less(Recs[P], Pv) do Inc(P);
        while Less(Pv, Recs[Q]) do Dec(Q);
        if P <= Q then
        begin
          T := Recs[P]; Recs[P] := Recs[Q]; Recs[Q] := T;
          Inc(P); Dec(Q);
        end;
      until P > Q;
      if Q - L < R - P then begin SortRecs(L, Q); L := P; end
      else begin SortRecs(P, R); R := Q; end;
    end;
  end;

  procedure SortTags(L, R: Integer);
  var
    P, Q, T: Integer;
    PK: Int64; PH: Integer; TK: Int64;
  begin
    while L < R do
    begin
      PK := FTagKeys[(L + R) shr 1]; PH := FTagHi[(L + R) shr 1]; P := L; Q := R;
      repeat
        while (FTagKeys[P] < PK) or ((FTagKeys[P] = PK) and (FTagHi[P] < PH)) do Inc(P);
        while (PK < FTagKeys[Q]) or ((PK = FTagKeys[Q]) and (PH < FTagHi[Q])) do Dec(Q);
        if P <= Q then
        begin
          TK := FTagKeys[P]; FTagKeys[P] := FTagKeys[Q]; FTagKeys[Q] := TK;
          T := FTagHi[P]; FTagHi[P] := FTagHi[Q]; FTagHi[Q] := T;
          T := FTagVals[P]; FTagVals[P] := FTagVals[Q]; FTagVals[Q] := T;
          Inc(P); Dec(Q);
        end;
      until P > Q;
      if Q - L < R - P then begin SortTags(L, Q); L := P; end
      else begin SortTags(P, R); R := Q; end;
    end;
  end;

begin
  SetLength(Nodes, NodeCount);
  SetLength(Elems, ElemCount);
  SetLength(Recs, 4 * ElemCount);
  N := 0;
  for E := 0 to ElemCount - 1 do
    for K := 0 to 3 do
    begin
      Recs[N].Key := TriKey(Elems[E].N[Loc[K, 0]], Elems[E].N[Loc[K, 1]], Elems[E].N[Loc[K, 2]], MaxInt div 2, Recs[N].Hi);
      Recs[N].Elem := E;
      Recs[N].Opp := K;
      Inc(N);
    end;
  if N > 1 then SortRecs(0, N - 1);
  if FTagCount > 1 then SortTags(0, FTagCount - 1);
  SetLength(Faces, 0);
  FaceCount := 0;
  I := 0;
  while I < N do
  begin
    J := I + 1;
    while (J < N) and (Recs[J].Key = Recs[I].Key) and (Recs[J].Hi = Recs[I].Hi) do Inc(J);
    if J - I = 1 then
    begin
      E := Recs[I].Elem; K := Recs[I].Opp;
      A := Elems[E].N[Loc[K, 0]]; B := Elems[E].N[Loc[K, 1]]; C := Elems[E].N[Loc[K, 2]];
      D := Elems[E].N[K];
      Nrm := VCross(VSub(Nodes[B], Nodes[A]), VSub(Nodes[C], Nodes[A]));
      if VDot(Nrm, VSub(Nodes[D], Nodes[A])) > 0 then begin Tmp := B; B := C; C := Tmp; end;
      { etiqueta por busca binaria }
      Tag := -1;
      KeyT := TriKey(A, B, C, MaxInt div 2, HiT);
      Lo := 0; Hi2 := FTagCount - 1;
      while Lo <= Hi2 do
      begin
        M := (Lo + Hi2) shr 1;
        if (FTagKeys[M] < KeyT) or ((FTagKeys[M] = KeyT) and (FTagHi[M] < HiT)) then Lo := M + 1
        else if (FTagKeys[M] = KeyT) and (FTagHi[M] = HiT) then begin Tag := FTagVals[M]; Break; end
        else Hi2 := M - 1;
      end;
      if FaceCount >= Length(Faces) then SetLength(Faces, Max(64, 2 * Length(Faces)));
      FillChar(Faces[FaceCount], SizeOf(TMeshFace), $FF);
      Faces[FaceCount].N[0] := A; Faces[FaceCount].N[1] := B; Faces[FaceCount].N[2] := C;
      Faces[FaceCount].Tag := Tag;
      Faces[FaceCount].Elem := E;
      Inc(FaceCount);
    end;
    I := J;
  end;
  SetLength(Faces, FaceCount);
end;

procedure TFEMMesh.ConvertToTet10;
const
  Pairs: array[0..5, 0..1] of Integer = ((0, 1), (1, 2), (2, 0), (0, 3), (1, 3), (2, 3));
  FPairs: array[0..2, 0..1] of Integer = ((0, 1), (1, 2), (2, 0));
var
  Keys: array of Int64;
  Ids: array of Integer;
  NK, E, K, I, Lo, Hi, M, NC, U: Integer;
  A, B: Integer;
  Key, T: Int64;

  function EKey(A, B: Integer): Int64;
  begin
    if A < B then Result := Int64(A) * NC + B else Result := Int64(B) * NC + A;
  end;

  procedure SortKeys(L, R: Integer);
  var
    P, Q: Integer;
    Pv: Int64;
  begin
    while L < R do
    begin
      Pv := Keys[(L + R) shr 1]; P := L; Q := R;
      repeat
        while Keys[P] < Pv do Inc(P);
        while Pv < Keys[Q] do Dec(Q);
        if P <= Q then
        begin
          T := Keys[P]; Keys[P] := Keys[Q]; Keys[Q] := T;
          Inc(P); Dec(Q);
        end;
      until P > Q;
      if Q - L < R - P then begin SortKeys(L, Q); L := P; end
      else begin SortKeys(P, R); R := Q; end;
    end;
  end;

  function MidNode(A, B: Integer): Integer;
  begin
    Key := EKey(A, B);
    Lo := 0; Hi := NK - 1;
    while Lo <= Hi do
    begin
      M := (Lo + Hi) shr 1;
      if Keys[M] < Key then Lo := M + 1
      else if Keys[M] > Key then Hi := M - 1
      else Exit(Ids[M]);
    end;
    Result := -1;
  end;

begin
  if Order = 2 then Exit;
  NC := NodeCount;
  SetLength(Keys, 6 * ElemCount);
  NK := 0;
  for E := 0 to ElemCount - 1 do
    for K := 0 to 5 do
    begin
      Keys[NK] := EKey(Elems[E].N[Pairs[K, 0]], Elems[E].N[Pairs[K, 1]]);
      Inc(NK);
    end;
  if NK > 1 then SortKeys(0, NK - 1);
  { unicos }
  U := 0;
  for I := 0 to NK - 1 do
    if (U = 0) or (Keys[I] <> Keys[U - 1]) then
    begin
      Keys[U] := Keys[I];
      Inc(U);
    end;
  NK := U;
  SetLength(Keys, NK);
  SetLength(Ids, NK);
  SetLength(Nodes, NodeCount + NK);
  for I := 0 to NK - 1 do
  begin
    A := Keys[I] div NC; B := Keys[I] mod NC;
    Ids[I] := AddNode(VScale(VAdd(Nodes[A], Nodes[B]), 0.5));
  end;
  SetLength(Nodes, NodeCount);
  for E := 0 to ElemCount - 1 do
    for K := 0 to 5 do
      Elems[E].N[4 + K] := MidNode(Elems[E].N[Pairs[K, 0]], Elems[E].N[Pairs[K, 1]]);
  for I := 0 to FaceCount - 1 do
    for K := 0 to 2 do
      Faces[I].N[3 + K] := MidNode(Faces[I].N[FPairs[K, 0]], Faces[I].N[FPairs[K, 1]]);
  Order := 2;
end;

function TFEMMesh.NodesPerElement: Integer;
begin
  if Order = 2 then Result := 10 else Result := 4;
end;

function TFEMMesh.ElemVolume(E: Integer): Double;
begin
  Result := TetSignedVolume(Nodes[Elems[E].N[0]], Nodes[Elems[E].N[1]],
    Nodes[Elems[E].N[2]], Nodes[Elems[E].N[3]]);
end;

function TFEMMesh.Volume: Double;
var
  E: Integer;
begin
  Result := 0;
  for E := 0 to ElemCount - 1 do Result := Result + ElemVolume(E);
end;

function TFEMMesh.PartVolume(Part: Integer): Double;
var
  E: Integer;
begin
  Result := 0;
  for E := 0 to ElemCount - 1 do
    if Elems[E].Part = Part then Result := Result + ElemVolume(E);
end;

function TFEMMesh.Quality: TMeshQuality;
var
  E, I, J: Integer;
  V, S, Q: Double;
  P: array[0..3] of TVector3;
begin
  Result.Elements := ElemCount; Result.Inverted := 0; Result.Poor := 0;
  Result.MinShape := 1; Result.MeanShape := 0;
  for E := 0 to ElemCount - 1 do
  begin
    for I := 0 to 3 do P[I] := Nodes[Elems[E].N[I]];
    V := ElemVolume(E);
    S := 0;
    for I := 0 to 2 do
      for J := I + 1 to 3 do
        S := S + Sqr(VLength(VSub(P[J], P[I])));
    if (V <= 0) or (S <= 0) then
    begin
      Inc(Result.Inverted);
      Q := 0;
    end
    else
      Q := 12 * Power(3 * V, 2 / 3) / S;
    if Q < 0.1 then Inc(Result.Poor);
    Result.MinShape := Min(Result.MinShape, Q);
    Result.MeanShape := Result.MeanShape + Q;
  end;
  if ElemCount > 0 then Result.MeanShape := Result.MeanShape / ElemCount else Result.MinShape := 0;
end;

function TFEMMesh.FindTag(const Name: string): Integer;
begin
  Result := FaceNames.IndexOf(Name);
end;

function TFEMMesh.NodesOfTag(Tag: Integer): TIntArray;
var
  Mark: array of Boolean;
  F, K, N, C: Integer;
begin
  Result := nil;
  SetLength(Mark, NodeCount);
  C := 0;
  for F := 0 to FaceCount - 1 do
    if Faces[F].Tag = Tag then
      for K := 0 to 5 do
      begin
        N := Faces[F].N[K];
        if (N >= 0) and not Mark[N] then begin Mark[N] := True; Inc(C); end;
      end;
  SetLength(Result, C);
  C := 0;
  for N := 0 to NodeCount - 1 do
    if Mark[N] then begin Result[C] := N; Inc(C); end;
end;

function TFEMMesh.FaceArea(F: Integer): Double;
begin
  Result := VLength(VCross(VSub(Nodes[Faces[F].N[1]], Nodes[Faces[F].N[0]]),
    VSub(Nodes[Faces[F].N[2]], Nodes[Faces[F].N[0]]))) / 2;
end;

function TFEMMesh.FaceNormal(F: Integer): TVector3;
begin
  Result := VNormalize(VCross(VSub(Nodes[Faces[F].N[1]], Nodes[Faces[F].N[0]]),
    VSub(Nodes[Faces[F].N[2]], Nodes[Faces[F].N[0]])));
end;

function TFEMMesh.TagArea(Tag: Integer): Double;
var
  F: Integer;
begin
  Result := 0;
  for F := 0 to FaceCount - 1 do
    if Faces[F].Tag = Tag then Result := Result + FaceArea(F);
end;

end.
