unit multicad_softrender;

{ MultiCAD - renderizador por software da vista 3D (ARCHITECTURE 6.4). Sem LCL.

  Raster com tres buffers: cor ($00RRGGBB), profundidade e codigo de
  selecao (Id). O Id de cada pixel e  Tag shl 20 + face + 1  (0 = fundo),
  assim "o que esta sob o mouse" e uma leitura direta (selecao exata).

  Estilos como no SolidWorks:
    dsShadedEdges   sombreado com arestas
    dsShaded        sombreado
    dsHiddenRemoved linhas ocultas removidas
    dsHiddenVisible linhas ocultas visiveis (cinza tracejado)
    dsWireframe     arame

  Arestas mostradas: arestas de recurso (entre faces com nomes diferentes,
  ou dobra > 40 graus) e silhuetas das faces curvas (frente/costas trocam).
  Luz: ambiente 0,30 + farol (luz na camera) 0,62 + brilho 0,18.
  Corte de secao opcional: descarta o lado positivo do plano; as faces de
  dentro aparecem na cor de secao. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Generics.Collections, multicad_types, multicad_mesh,
  multicad_camera;

type
  TCadDisplayStyle = (dsShadedEdges, dsShaded, dsHiddenRemoved,
    dsHiddenVisible, dsWireframe);

  TCadEdge = record
    A, B: Integer;      { vertices }
    T1, T2: Integer;    { triangulos vizinhos (T2 = -1 se borda) }
    Feature: Boolean;   { aresta de recurso (sempre visivel) }
  end;

  { Dados derivados da malha para desenhar (normais por canto e arestas). }
  TCadMeshCache = class
  public
    Mesh: TCadMesh;
    TriN: array of TCadVec3;
    CornerN: array of TCadVec3;   { 3 por triangulo }
    Edges: array of TCadEdge;
    constructor Create(AMesh: TCadMesh);
  end;

  TCadDrawOptions = record
    Color: LongWord;          { cor base $00RRGGBB }
    EdgeColor: LongWord;
    Alpha: Double;            { 1 = opaco; < 1 = previa translucida }
    Tag: Integer;             { 0..2047, vai para o Id }
    HiFaces: TCadIdArray;     { faces selecionadas }
    HiColor: LongWord;
    HoverFace: Integer;       { face sob o mouse (-1 = nenhuma) }
    HoverColor: LongWord;
  end;

  TCadRaster = class
  private
    FW, FH: Integer;
    FCam: TCadCamera;
    FClipOn: Boolean;
    FClipO, FClipN: TCadVec3;
    procedure Plot(X, Y: Integer; Depth: Single; C: LongWord; AId: Integer;
      WriteDepth: Boolean; Alpha: Double);
    procedure FillTri(const P0, P1, P2: TCadScreenPt; I0, I1, I2: Double;
      Base: LongWord; AId: Integer; WriteDepth, WriteColor: Boolean; Alpha: Double);
    procedure Line2(const P0, P1: TCadScreenPt; C: LongWord; LW: Integer;
      DepthTest: Boolean; Dash: Integer; Bias: Double; AId: Integer);
    function Shade(const N, P: TCadVec3; out Inside: Boolean): Double;
    function ClipSeg(var A, B: TCadVec3): Boolean;
  public
    Color: array of LongWord;
    Depth: array of Single;
    Id: array of Integer;
    Style: TCadDisplayStyle;
    Background1, Background2: LongWord;   { degrade de cima para baixo }
    SectionColor: LongWord;
    constructor Create;
    procedure SetSize(AW, AH: Integer);
    property Width: Integer read FW;
    property Height: Integer read FH;
    { Comeca um quadro: limpa os buffers com o degrade do fundo. }
    procedure BeginFrame(ACam: TCadCamera);
    procedure SetSection(AOn: Boolean; const AO, AN: TCadVec3);
    procedure DrawMesh(Cache: TCadMeshCache; const Opt: TCadDrawOptions);
    { Linha 3D (esbocos, eixos, contorno de planos). DepthTest = escondida
      atras das faces. }
    procedure DrawLine3D(const A, B: TCadVec3; C: LongWord; LW: Integer;
      DepthTest: Boolean; Dash: Integer = 0; AId: Integer = 0);
    procedure DrawPoint3D(const P: TCadVec3; C: LongWord; Size: Integer;
      DepthTest: Boolean; AId: Integer = 0);
    { Quadrilatero translucido (planos de referencia). Nao escreve profundidade. }
    procedure DrawQuad3D(const A, B, C, D: TCadVec3; Fill: LongWord; Alpha: Double;
      AId: Integer = 0);
    function IdAt(X, Y: Integer): Integer;
    function DepthAt(X, Y: Integer): Single;
    function ColorAt(X, Y: Integer): LongWord;
    { Pixels cujo Id e diferente do fundo (para testes). }
    function CountId(AId: Integer): Integer;
  end;

const
  CAD_STYLE_NAMES: array[TCadDisplayStyle] of string = ('Sombreado com arestas',
    'Sombreado', 'Linhas ocultas removidas', 'Linhas ocultas visíveis', 'Estrutura de arame');
  CAD_PICK_TAG_SHIFT = 20;
  CAD_PART_COLOR = $00B4BEC8;     { cinza azulado das pecas }
  CAD_EDGE_COLOR = $00202428;
  CAD_SELECT_COLOR = $003C96FF;   { azul de selecao }
  CAD_HOVER_COLOR = $00FF9A1E;    { laranja de pre-selecao }
  CAD_PREVIEW_COLOR = $00F0C832;  { amarelo da previa }

function CadDrawOptions(AColor: LongWord; ATag: Integer): TCadDrawOptions;
function CadPickCode(ATag, AFace: Integer): Integer;
procedure CadPickDecode(ACode: Integer; out ATag, AFace: Integer);
function CadRGB(R, G, B: Byte): LongWord;
function CadMix(A, B: LongWord; T: Double): LongWord;

{ Raio x triangulo (Moller-Trumbore). T = distancia ao longo de D. }
function CadRayTri(const O, D, A, B, C: TCadVec3; out T: Double): Boolean;
{ Triangulo mais proximo atingido pelo raio (-1 se nenhum). }
function CadRayMesh(M: TCadMesh; const O, D: TCadVec3; out T: Double): Integer;

implementation

const
  FEATURE_COS = 0.766;   { cos 40 graus }

function CadRGB(R, G, B: Byte): LongWord;
begin
  Result := (LongWord(R) shl 16) or (LongWord(G) shl 8) or B;
end;

function CadMix(A, B: LongWord; T: Double): LongWord;
begin
  { T = peso de A }
  Result := CadRGB(
    Round(((A shr 16) and $FF) * T + ((B shr 16) and $FF) * (1 - T)),
    Round(((A shr 8) and $FF) * T + ((B shr 8) and $FF) * (1 - T)),
    Round((A and $FF) * T + (B and $FF) * (1 - T)));
end;

function ScaleColor(C: LongWord; F: Double): LongWord;
var
  R, G, B: Integer;
begin
  R := Round(((C shr 16) and $FF) * F);
  G := Round(((C shr 8) and $FF) * F);
  B := Round((C and $FF) * F);
  Result := CadRGB(EnsureRange(R, 0, 255), EnsureRange(G, 0, 255), EnsureRange(B, 0, 255));
end;

function CadDrawOptions(AColor: LongWord; ATag: Integer): TCadDrawOptions;
begin
  Result.Color := AColor;
  Result.EdgeColor := CAD_EDGE_COLOR;
  Result.Alpha := 1;
  Result.Tag := ATag;
  Result.HiFaces := nil;
  Result.HiColor := CAD_SELECT_COLOR;
  Result.HoverFace := -1;
  Result.HoverColor := CAD_HOVER_COLOR;
end;

function CadPickCode(ATag, AFace: Integer): Integer;
begin
  Result := (ATag shl CAD_PICK_TAG_SHIFT) + AFace + 1;
end;

procedure CadPickDecode(ACode: Integer; out ATag, AFace: Integer);
begin
  if ACode <= 0 then
  begin
    ATag := -1;
    AFace := -1;
    Exit;
  end;
  ATag := ACode shr CAD_PICK_TAG_SHIFT;
  AFace := (ACode and ((1 shl CAD_PICK_TAG_SHIFT) - 1)) - 1;
end;

function CadRayTri(const O, D, A, B, C: TCadVec3; out T: Double): Boolean;
var
  E1, E2, P, Q, S: TCadVec3;
  Det, U, V: Double;
begin
  Result := False;
  T := 0;
  E1 := VSub(B, A);
  E2 := VSub(C, A);
  P := VCross(D, E2);
  Det := VDot(E1, P);
  if Abs(Det) < 1E-14 then
    Exit;
  S := VSub(O, A);
  U := VDot(S, P) / Det;
  if (U < -1E-9) or (U > 1 + 1E-9) then
    Exit;
  Q := VCross(S, E1);
  V := VDot(D, Q) / Det;
  if (V < -1E-9) or (U + V > 1 + 1E-9) then
    Exit;
  T := VDot(E2, Q) / Det;
  Result := T > 1E-9;
end;

function CadRayMesh(M: TCadMesh; const O, D: TCadVec3; out T: Double): Integer;
var
  I: Integer;
  Tr: TCadTri;
  TT: Double;
begin
  Result := -1;
  T := 1E300;
  for I := 0 to M.TriCount - 1 do
  begin
    Tr := M.Tris[I];
    if CadRayTri(O, D, M.Verts[Tr.A], M.Verts[Tr.B], M.Verts[Tr.C], TT) and (TT < T) then
    begin
      T := TT;
      Result := I;
    end;
  end;
end;

{ ---------- cache ---------- }

constructor TCadMeshCache.Create(AMesh: TCadMesh);
type
  TEdgeMap = specialize TDictionary<Int64, Integer>;
var
  NT, NV, I, K, A, B, Idx: Integer;
  Tr: TCadTri;
  Key: Int64;
  Map: TEdgeMap;
  Acc: specialize TDictionary<Int64, TCadVec3>;
  Sum, N: TCadVec3;
  Vs: array[0..2] of Integer;
  W: Double;
begin
  inherited Create;
  Mesh := AMesh;
  NT := AMesh.TriCount;
  NV := Max(1, AMesh.VertCount);
  SetLength(TriN, NT);
  SetLength(CornerN, NT * 3);
  for I := 0 to NT - 1 do
    TriN[I] := AMesh.TriNormal(I);
  { normais suaves por (vertice, face) nas faces curvas }
  Acc := specialize TDictionary<Int64, TCadVec3>.Create;
  try
    for I := 0 to NT - 1 do
    begin
      Tr := AMesh.Tris[I];
      if AMesh.Faces[Tr.Face].Surf = skPlane then
        Continue;
      W := AMesh.TriArea(I);
      Vs[0] := Tr.A; Vs[1] := Tr.B; Vs[2] := Tr.C;
      for K := 0 to 2 do
      begin
        Key := Int64(Tr.Face) * NV + Vs[K];
        if Acc.TryGetValue(Key, Sum) then
          Acc[Key] := VAdd(Sum, VScale(TriN[I], W))
        else
          Acc.Add(Key, VScale(TriN[I], W));
      end;
    end;
    for I := 0 to NT - 1 do
    begin
      Tr := AMesh.Tris[I];
      Vs[0] := Tr.A; Vs[1] := Tr.B; Vs[2] := Tr.C;
      for K := 0 to 2 do
      begin
        N := TriN[I];
        if (AMesh.Faces[Tr.Face].Surf <> skPlane) and
          Acc.TryGetValue(Int64(Tr.Face) * NV + Vs[K], Sum) and (VLen(Sum) > 1E-12) then
        begin
          Sum := VNorm(Sum);
          if VDot(Sum, N) > FEATURE_COS then
            N := Sum;
        end;
        CornerN[I * 3 + K] := N;
      end;
    end;
  finally
    Acc.Free;
  end;
  { arestas }
  Map := TEdgeMap.Create;
  try
    SetLength(Edges, 0);
    for I := 0 to NT - 1 do
    begin
      Tr := AMesh.Tris[I];
      Vs[0] := Tr.A; Vs[1] := Tr.B; Vs[2] := Tr.C;
      for K := 0 to 2 do
      begin
        A := Vs[K];
        B := Vs[(K + 1) mod 3];
        Key := Int64(Min(A, B)) * NV + Max(A, B);
        if Map.TryGetValue(Key, Idx) then
        begin
          if Edges[Idx].T2 < 0 then
            Edges[Idx].T2 := I;
        end
        else
        begin
          Idx := Length(Edges);
          SetLength(Edges, Idx + 1);
          Edges[Idx].A := A;
          Edges[Idx].B := B;
          Edges[Idx].T1 := I;
          Edges[Idx].T2 := -1;
          Map.Add(Key, Idx);
        end;
      end;
    end;
  finally
    Map.Free;
  end;
  for I := 0 to High(Edges) do
    with Edges[I] do
      if T2 < 0 then
        Feature := True
      else
        Feature := (AMesh.Tris[T1].Face <> AMesh.Tris[T2].Face) or
          (VDot(TriN[T1], TriN[T2]) < FEATURE_COS);
end;

{ ---------- raster ---------- }

constructor TCadRaster.Create;
begin
  inherited Create;
  Style := dsShadedEdges;
  Background1 := CadRGB(250, 251, 253);
  Background2 := CadRGB(196, 206, 222);
  SectionColor := CadRGB(232, 140, 120);
  SetSize(64, 64);
end;

procedure TCadRaster.SetSize(AW, AH: Integer);
begin
  FW := Max(1, AW);
  FH := Max(1, AH);
  SetLength(Color, FW * FH);
  SetLength(Depth, FW * FH);
  SetLength(Id, FW * FH);
end;

procedure TCadRaster.BeginFrame(ACam: TCadCamera);
var
  X, Y, Row: Integer;
  C: LongWord;
begin
  FCam := ACam;
  if (ACam.Width <> FW) or (ACam.Height <> FH) then
    ACam.SetViewport(FW, FH);
  for Y := 0 to FH - 1 do
  begin
    C := CadMix(Background2, Background1, Y / Max(1, FH - 1));
    Row := Y * FW;
    for X := 0 to FW - 1 do
    begin
      Color[Row + X] := C;
      Depth[Row + X] := 1E30;
      Id[Row + X] := 0;
    end;
  end;
end;

procedure TCadRaster.SetSection(AOn: Boolean; const AO, AN: TCadVec3);
begin
  FClipOn := AOn and (VLen(AN) > 1E-12);
  FClipO := AO;
  if FClipOn then
    FClipN := VNorm(AN);
end;

procedure TCadRaster.Plot(X, Y: Integer; Depth: Single; C: LongWord; AId: Integer;
  WriteDepth: Boolean; Alpha: Double);
var
  I: Integer;
begin
  if (X < 0) or (Y < 0) or (X >= FW) or (Y >= FH) then
    Exit;
  I := Y * FW + X;
  if Alpha >= 1 then
    Color[I] := C
  else
    Color[I] := CadMix(C, Color[I], Alpha);
  if WriteDepth then
    Self.Depth[I] := Depth;
  if AId <> 0 then
    Id[I] := AId;
end;

function TCadRaster.Shade(const N, P: TCadVec3; out Inside: Boolean): Double;
var
  L, H: TCadVec3;
  D, S: Double;
begin
  { farol: luz vinda da camera }
  if FCam.Perspective then
    L := VNorm(VSub(FCam.Eye, P))
  else
    L := FCam.Back;
  D := VDot(N, L);
  Inside := D < 0;
  D := Abs(D);
  H := VNorm(VAdd(L, FCam.Back));
  S := Power(Max(0, Abs(VDot(N, H))), 40);
  Result := 0.30 + 0.62 * D + 0.18 * S;
end;

procedure TCadRaster.FillTri(const P0, P1, P2: TCadScreenPt; I0, I1, I2: Double;
  Base: LongWord; AId: Integer; WriteDepth, WriteColor: Boolean; Alpha: Double);
var
  MinX, MaxX, MinY, MaxY, X, Y, Idx: Integer;
  Area, W0, W1, W2, Px, Py, Z, L: Double;
  BR, BG, BB: Integer;
begin
  Area := (P1.X - P0.X) * (P2.Y - P0.Y) - (P1.Y - P0.Y) * (P2.X - P0.X);
  if Abs(Area) < 1E-9 then
    Exit;
  MinX := Max(0, Floor(Min(P0.X, Min(P1.X, P2.X))));
  MaxX := Min(FW - 1, Ceil(Max(P0.X, Max(P1.X, P2.X))));
  MinY := Max(0, Floor(Min(P0.Y, Min(P1.Y, P2.Y))));
  MaxY := Min(FH - 1, Ceil(Max(P0.Y, Max(P1.Y, P2.Y))));
  if (MinX > MaxX) or (MinY > MaxY) then
    Exit;
  BR := (Base shr 16) and $FF;
  BG := (Base shr 8) and $FF;
  BB := Base and $FF;
  for Y := MinY to MaxY do
  begin
    Py := Y + 0.5;
    for X := MinX to MaxX do
    begin
      Px := X + 0.5;
      W0 := ((P1.X - Px) * (P2.Y - Py) - (P1.Y - Py) * (P2.X - Px)) / Area;
      W1 := ((P2.X - Px) * (P0.Y - Py) - (P2.Y - Py) * (P0.X - Px)) / Area;
      W2 := 1 - W0 - W1;
      if (W0 < -1E-7) or (W1 < -1E-7) or (W2 < -1E-7) then
        Continue;
      Z := W0 * P0.Depth + W1 * P1.Depth + W2 * P2.Depth;
      Idx := Y * FW + X;
      if Z >= Depth[Idx] then
        Continue;
      if WriteColor then
      begin
        L := W0 * I0 + W1 * I1 + W2 * I2;
        Plot(X, Y, Z, CadRGB(EnsureRange(Round(BR * L), 0, 255),
          EnsureRange(Round(BG * L), 0, 255), EnsureRange(Round(BB * L), 0, 255)),
          AId, WriteDepth, Alpha);
      end
      else
      begin
        if WriteDepth then
          Depth[Idx] := Z;
        if AId <> 0 then
          Id[Idx] := AId;
      end;
    end;
  end;
end;

procedure TCadRaster.Line2(const P0, P1: TCadScreenPt; C: LongWord; LW: Integer;
  DepthTest: Boolean; Dash: Integer; Bias: Double; AId: Integer);
var
  N, I, X, Y, DX, DY, Half: Integer;
  T, Z: Double;
  Idx: Integer;
begin
  N := Max(1, Ceil(Max(Abs(P1.X - P0.X), Abs(P1.Y - P0.Y))));
  if N > 20000 then
    Exit;
  Half := (LW - 1) div 2;
  for I := 0 to N do
  begin
    if (Dash > 0) and (((I div Dash) and 1) = 1) then
      Continue;
    T := I / N;
    X := Floor(P0.X + (P1.X - P0.X) * T);
    Y := Floor(P0.Y + (P1.Y - P0.Y) * T);
    Z := P0.Depth + (P1.Depth - P0.Depth) * T;
    for DY := -Half to LW - 1 - Half do
      for DX := -Half to LW - 1 - Half do
      begin
        if (X + DX < 0) or (Y + DY < 0) or (X + DX >= FW) or (Y + DY >= FH) then
          Continue;
        Idx := (Y + DY) * FW + X + DX;
        if DepthTest and (Z - Bias > Depth[Idx]) then
          Continue;
        Color[Idx] := C;
        if AId <> 0 then
          Id[Idx] := AId;
      end;
  end;
end;

function TCadRaster.ClipSeg(var A, B: TCadVec3): Boolean;
var
  DA, DB, T: Double;
  P: TCadVec3;
begin
  Result := True;
  if not FClipOn then
    Exit;
  DA := VDot(VSub(A, FClipO), FClipN);
  DB := VDot(VSub(B, FClipO), FClipN);
  if (DA > 0) and (DB > 0) then
    Exit(False);
  if (DA <= 0) and (DB <= 0) then
    Exit;
  T := DA / (DA - DB);
  P := VLerp(A, B, T);
  if DA > 0 then
    A := P
  else
    B := P;
end;

procedure TCadRaster.DrawMesh(Cache: TCadMeshCache; const Opt: TCadDrawOptions);
var
  M: TCadMesh;
  I, K, J, NPoly, F, AId: Integer;
  Tr: TCadTri;
  Pw: array[0..8] of TCadVec3;
  Nw: array[0..8] of TCadVec3;
  Dist: array[0..8] of Double;
  Pin: array[0..2] of TCadVec3;
  Nin: array[0..2] of TCadVec3;
  Sp: array[0..8] of TCadScreenPt;
  Lt: array[0..8] of Double;
  Base: LongWord;
  Inside, Front1, Front2, FillCol, Visible: Boolean;
  Alpha, Bias, T: Double;
  A, B: TCadVec3;
  E: TCadEdge;
  Sa, Sb: TCadScreenPt;
  HiSet: specialize TDictionary<Integer, Boolean>;

  function Facing(Tri: Integer): Boolean;
  var
    Pt: TCadVec3;
  begin
    if FCam.Perspective then
    begin
      Pt := M.Verts[M.Tris[Tri].A];
      Result := VDot(Cache.TriN[Tri], VSub(FCam.Eye, Pt)) > 0;
    end
    else
      Result := VDot(Cache.TriN[Tri], FCam.Back) > 0;
  end;

begin
  M := Cache.Mesh;
  if (M = nil) or (FCam = nil) then
    Exit;
  Alpha := EnsureRange(Opt.Alpha, 0.05, 1);
  FillCol := Style in [dsShadedEdges, dsShaded];
  HiSet := specialize TDictionary<Integer, Boolean>.Create;
  try
    for I := 0 to High(Opt.HiFaces) do
      HiSet.AddOrSetValue(Opt.HiFaces[I], True);
    { 1. faces }
    if Style <> dsWireframe then
      for I := 0 to M.TriCount - 1 do
      begin
        Tr := M.Tris[I];
        F := Tr.Face;
        Pin[0] := M.Verts[Tr.A]; Pin[1] := M.Verts[Tr.B]; Pin[2] := M.Verts[Tr.C];
        for K := 0 to 2 do
          Nin[K] := Cache.CornerN[I * 3 + K];
        { recorte pelo plano de secao (Sutherland-Hodgman) }
        if FClipOn then
        begin
          for K := 0 to 2 do
            Dist[K] := VDot(VSub(Pin[K], FClipO), FClipN);
          NPoly := 0;
          for K := 0 to 2 do
          begin
            J := (K + 1) mod 3;
            if Dist[K] <= 0 then
            begin
              Pw[NPoly] := Pin[K];
              Nw[NPoly] := Nin[K];
              Inc(NPoly);
            end;
            if (Dist[K] <= 0) <> (Dist[J] <= 0) then
            begin
              T := Dist[K] / (Dist[K] - Dist[J]);
              Pw[NPoly] := VLerp(Pin[K], Pin[J], T);
              Nw[NPoly] := VNorm(VLerp(Nin[K], Nin[J], T));
              Inc(NPoly);
            end;
          end;
          if NPoly < 3 then
            Continue;
        end
        else
        begin
          NPoly := 3;
          for K := 0 to 2 do
          begin
            Pw[K] := Pin[K];
            Nw[K] := Nin[K];
          end;
        end;
        Base := Opt.Color;
        if HiSet.ContainsKey(F) then
          Base := Opt.HiColor
        else if F = Opt.HoverFace then
          Base := Opt.HoverColor;
        Inside := False;
        for K := 0 to NPoly - 1 do
        begin
          Sp[K] := FCam.Project(Pw[K]);
          if Sp[K].Depth <= 1E-3 then
            Inside := True;   { atras do olho (perspectiva) }
          Lt[K] := Shade(Nw[K], Pw[K], Front1);
        end;
        if Inside then
          Continue;
        if FClipOn and not Facing(I) then
          Base := SectionColor;
        AId := CadPickCode(Opt.Tag, F);
        for K := 1 to NPoly - 2 do
          FillTri(Sp[0], Sp[K], Sp[K + 1], Lt[0], Lt[K], Lt[K + 1], Base, AId,
            Alpha >= 1, FillCol, Alpha);
      end;
    { 2. arestas }
    if (Style = dsShaded) and (Opt.Alpha >= 1) then
      Exit;
    Bias := Max(0.002 * FCam.Distance, 0.05);
    for I := 0 to High(Cache.Edges) do
    begin
      E := Cache.Edges[I];
      Visible := E.Feature;
      if not Visible and (E.T2 >= 0) then
      begin
        Front1 := Facing(E.T1);
        Front2 := Facing(E.T2);
        Visible := Front1 <> Front2;   { silhueta }
      end;
      if not Visible then
        Continue;
      A := M.Verts[E.A];
      B := M.Verts[E.B];
      if not ClipSeg(A, B) then
        Continue;
      Sa := FCam.Project(A);
      Sb := FCam.Project(B);
      if (Sa.Depth <= 1E-3) or (Sb.Depth <= 1E-3) then
        Continue;
      case Style of
        dsWireframe:
          Line2(Sa, Sb, Opt.EdgeColor, 1, False, 0, 0, 0);
        dsHiddenVisible:
          begin
            Line2(Sa, Sb, CadRGB(150, 156, 166), 1, False, 4, 0, 0);
            Line2(Sa, Sb, Opt.EdgeColor, 1, True, 0, Bias, 0);
          end;
      else
        Line2(Sa, Sb, Opt.EdgeColor, 1, True, 0, Bias, 0);
      end;
    end;
  finally
    HiSet.Free;
  end;
end;

procedure TCadRaster.DrawLine3D(const A, B: TCadVec3; C: LongWord; LW: Integer;
  DepthTest: Boolean; Dash: Integer; AId: Integer);
var
  PA, PB: TCadVec3;
  Sa, Sb: TCadScreenPt;
begin
  if FCam = nil then
    Exit;
  PA := A;
  PB := B;
  if not ClipSeg(PA, PB) then
    Exit;
  Sa := FCam.Project(PA);
  Sb := FCam.Project(PB);
  if (Sa.Depth <= 1E-3) or (Sb.Depth <= 1E-3) then
    Exit;
  Line2(Sa, Sb, C, LW, DepthTest, Dash, Max(0.002 * FCam.Distance, 0.05), AId);
end;

procedure TCadRaster.DrawPoint3D(const P: TCadVec3; C: LongWord; Size: Integer;
  DepthTest: Boolean; AId: Integer);
var
  S: TCadScreenPt;
  X, Y, CX, CY, H, Idx: Integer;
begin
  if FCam = nil then
    Exit;
  S := FCam.Project(P);
  if S.Depth <= 1E-3 then
    Exit;
  CX := Floor(S.X);
  CY := Floor(S.Y);
  H := Size div 2;
  for Y := CY - H to CY + H do
    for X := CX - H to CX + H do
    begin
      if (X < 0) or (Y < 0) or (X >= FW) or (Y >= FH) then
        Continue;
      Idx := Y * FW + X;
      if DepthTest and (S.Depth - Max(0.002 * FCam.Distance, 0.05) > Depth[Idx]) then
        Continue;
      Color[Idx] := C;
      if AId <> 0 then
        Id[Idx] := AId;
    end;
end;

procedure TCadRaster.DrawQuad3D(const A, B, C, D: TCadVec3; Fill: LongWord;
  Alpha: Double; AId: Integer);
var
  S: array[0..3] of TCadScreenPt;
begin
  if FCam = nil then
    Exit;
  S[0] := FCam.Project(A);
  S[1] := FCam.Project(B);
  S[2] := FCam.Project(C);
  S[3] := FCam.Project(D);
  if (S[0].Depth <= 1E-3) or (S[1].Depth <= 1E-3) or (S[2].Depth <= 1E-3) or
    (S[3].Depth <= 1E-3) then
    Exit;
  FillTri(S[0], S[1], S[2], 1, 1, 1, Fill, AId, False, True, Alpha);
  FillTri(S[0], S[2], S[3], 1, 1, 1, Fill, AId, False, True, Alpha);
end;

function TCadRaster.IdAt(X, Y: Integer): Integer;
begin
  if (X < 0) or (Y < 0) or (X >= FW) or (Y >= FH) then
    Exit(0);
  Result := Id[Y * FW + X];
end;

function TCadRaster.DepthAt(X, Y: Integer): Single;
begin
  if (X < 0) or (Y < 0) or (X >= FW) or (Y >= FH) then
    Exit(1E30);
  Result := Depth[Y * FW + X];
end;

function TCadRaster.ColorAt(X, Y: Integer): LongWord;
begin
  if (X < 0) or (Y < 0) or (X >= FW) or (Y >= FH) then
    Exit(0);
  Result := Color[Y * FW + X];
end;

function TCadRaster.CountId(AId: Integer): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(Id) do
    if Id[I] = AId then
      Inc(Result);
end;

end.
