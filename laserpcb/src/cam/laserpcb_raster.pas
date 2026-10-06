unit laserpcb_raster;

{ Base raster do LaserPCB.

  TLPMask    imagem binaria (0/1) com origem e resolucao em mm, Y para cima.
             Desenha poligonos (regra nao-zero), camadas Gerber com
             polaridade (LPD/LPC, composicao local de aberturas com furo),
             furos Excellon, e operacoes booleanas entre mascaras.
  TLPField   campo de distancias (mm) calculado com a transformada de
             distancia euclidiana exata (Felzenszwalb & Huttenlocher).
  LPIsoContours  contornos fechados de um nivel do campo (marching
             squares com interpolacao linear).

  Por que raster: a isolacao (deslocamento de contornos), uniao de cobre
  e remocao de areas ficam simples e robustas, sem depender de biblioteca
  de booleanas de poligonos. A precisao e a resolucao escolhida (padrao
  0,02 mm), bem abaixo do diametro do feixe. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, laserpcb_geom, laserpcb_gerber, laserpcb_excellon;

type
  TLPMask = class
  private
    FW, FH: Integer;
    FX0, FY0, FRes: Double;
    procedure FillItem(const Paths: TLPPaths; Value: Byte; Target: TLPMask);
  public
    Data: array of Byte;
    constructor Create(const Area: TLPRect; ARes: Double);
    constructor CreateLike(Other: TLPMask);
    function Clone: TLPMask;
    procedure Clear(Value: Byte = 0);
    function Get(I, J: Integer): Byte; inline;
    procedure SetPx(I, J: Integer; V: Byte); inline;
    function PixelX(I: Integer): Double; inline;
    function PixelY(J: Integer): Double; inline;
    function ColOf(X: Double): Integer; inline;
    function RowOf(Y: Double): Integer; inline;
    { preenche contornos (nao-zero) com Value }
    procedure FillPaths(const Paths: TLPPaths; Value: Byte = 1);
    { desenha um objeto Gerber respeitando a polaridade }
    procedure DrawShape(const S: TLPGShape);
    procedure DrawGerber(L: TLPGerberLayer);
    { furos (e rasgos) com o diametro da ferramenta + Grow (mm) }
    procedure DrawHoles(D: TLPDrillFile; Value: Byte; Grow: Double = 0);
    procedure Invert;
    procedure AndMask(Other: TLPMask);
    procedure OrMask(Other: TLPMask);
    procedure AndNotMask(Other: TLPMask);
    function CountSet: Integer;
    function Area: TLPRect;
    property Width: Integer read FW;
    property Height: Integer read FH;
    property X0: Double read FX0;
    property Y0: Double read FY0;
    property Res: Double read FRes;
  end;

  { campo de distancias em mm ate o pixel mais proximo com Mask = Feature }
  TLPField = class
  public
    W, H: Integer;
    X0, Y0, Res: Double;
    D: array of Single;
    constructor Create(M: TLPMask; Feature: Byte; MaxDist: Double = 0);
    function Get(I, J: Integer): Single; inline;
  end;

{ contornos fechados onde o campo cruza Level (mm); pixels fora da imagem
  contam como "longe" (o contorno sempre fecha). Simplifica com Tol (mm). }
function LPIsoContours(F: TLPField; Level: Double; Tol: Double): TLPPaths;

{ contornos fechados da borda de uma mascara (pixels = 1) }
function LPMaskContours(M: TLPMask; Tol: Double): TLPPaths;

implementation

const
  INF = 1e20;

{ ---------------- TLPMask ---------------- }

constructor TLPMask.Create(const Area: TLPRect; ARes: Double);
begin
  inherited Create;
  FRes := Max(ARes, 1e-4);
  FX0 := Area.MinX;
  FY0 := Area.MinY;
  FW := Max(1, Ceil(LPRectWidth(Area) / FRes));
  FH := Max(1, Ceil(LPRectHeight(Area) / FRes));
  SetLength(Data, FW * FH);
end;

constructor TLPMask.CreateLike(Other: TLPMask);
begin
  inherited Create;
  FRes := Other.FRes;
  FX0 := Other.FX0;
  FY0 := Other.FY0;
  FW := Other.FW;
  FH := Other.FH;
  SetLength(Data, FW * FH);
end;

function TLPMask.Clone: TLPMask;
begin
  Result := TLPMask.CreateLike(Self);
  if Length(Data) > 0 then
    Move(Data[0], Result.Data[0], Length(Data));
end;

procedure TLPMask.Clear(Value: Byte);
begin
  if Length(Data) > 0 then FillChar(Data[0], Length(Data), Value);
end;

function TLPMask.Get(I, J: Integer): Byte;
begin
  if (I < 0) or (J < 0) or (I >= FW) or (J >= FH) then Exit(0);
  Result := Data[J * FW + I];
end;

procedure TLPMask.SetPx(I, J: Integer; V: Byte);
begin
  if (I < 0) or (J < 0) or (I >= FW) or (J >= FH) then Exit;
  Data[J * FW + I] := V;
end;

function TLPMask.PixelX(I: Integer): Double;
begin
  Result := FX0 + (I + 0.5) * FRes;
end;

function TLPMask.PixelY(J: Integer): Double;
begin
  Result := FY0 + (J + 0.5) * FRes;
end;

function TLPMask.ColOf(X: Double): Integer;
begin
  Result := Floor((X - FX0) / FRes);
end;

function TLPMask.RowOf(Y: Double): Integer;
begin
  Result := Floor((Y - FY0) / FRes);
end;

function TLPMask.Area: TLPRect;
begin
  Result.MinX := FX0;
  Result.MinY := FY0;
  Result.MaxX := FX0 + FW * FRes;
  Result.MaxY := FY0 + FH * FRes;
  Result.Valid := True;
end;

type
  TXing = record
    X: Double;
    Dir: Integer;
  end;

{ preenchimento por linhas de varredura, regra nao-zero; escreve em Target }
procedure TLPMask.FillItem(const Paths: TLPPaths; Value: Byte; Target: TLPMask);
var
  B: TLPRect;
  J0, J1, J, I, K, N, P, I0, I1, Wind, Cnt: Integer;
  Y, XA: Double;
  Xs: array of TXing;
  T: TXing;
  A, C: TLPPoint;
  Row: PByte;
begin
  B := LPPathsBounds(Paths);
  if not B.Valid then Exit;
  J0 := Max(0, Ceil((B.MinY - Target.FY0) / Target.FRes - 0.5));
  J1 := Min(Target.FH - 1, Floor((B.MaxY - Target.FY0) / Target.FRes - 0.5));
  SetLength(Xs, 64);
  for J := J0 to J1 do
  begin
    Y := Target.FY0 + (J + 0.5) * Target.FRes;
    Cnt := 0;
    for P := 0 to High(Paths) do
    begin
      N := Length(Paths[P]);
      if N < 2 then Continue;
      for K := 0 to N - 1 do
      begin
        A := Paths[P][K];
        if K = N - 1 then C := Paths[P][0] else C := Paths[P][K + 1];
        if (A.Y <= Y) = (C.Y <= Y) then Continue;
        XA := A.X + (Y - A.Y) * (C.X - A.X) / (C.Y - A.Y);
        if Cnt >= Length(Xs) then SetLength(Xs, Cnt * 2);
        Xs[Cnt].X := XA;
        if C.Y > A.Y then Xs[Cnt].Dir := 1 else Xs[Cnt].Dir := -1;
        Inc(Cnt);
      end;
    end;
    if Cnt < 2 then Continue;
    { ordena (insercao: poucas intersecoes por linha) }
    for I := 1 to Cnt - 1 do
    begin
      T := Xs[I];
      K := I - 1;
      while (K >= 0) and (Xs[K].X > T.X) do
      begin
        Xs[K + 1] := Xs[K];
        Dec(K);
      end;
      Xs[K + 1] := T;
    end;
    Row := @Target.Data[J * Target.FW];
    Wind := 0;
    for K := 0 to Cnt - 2 do
    begin
      Wind := Wind + Xs[K].Dir;
      if Wind = 0 then Continue;
      I0 := Max(0, Ceil((Xs[K].X - Target.FX0) / Target.FRes - 0.5));
      I1 := Min(Target.FW - 1, Ceil((Xs[K + 1].X - Target.FX0) / Target.FRes - 0.5) - 1);
      if I1 >= I0 then FillChar(Row[I0], I1 - I0 + 1, Value);
    end;
  end;
end;

procedure TLPMask.FillPaths(const Paths: TLPPaths; Value: Byte);
begin
  FillItem(Paths, Value, Self);
end;

procedure TLPMask.DrawShape(const S: TLPGShape);
var
  K, I, J, LI0, LJ0: Integer;
  B, R: TLPRect;
  Loc: TLPMask;
  V: Byte;
begin
  if Length(S.Items) = 0 then Exit;
  if S.Dark then V := 1 else V := 0;
  if (Length(S.Items) = 1) and S.Items[0].Dark then
  begin
    FillItem(S.Items[0].Paths, V, Self);
    Exit;
  end;
  { composicao local: itens claros so apagam a propria abertura }
  B := LPEmptyRect;
  for K := 0 to High(S.Items) do
    if S.Items[K].Dark then LPRectIncludeRect(B, LPPathsBounds(S.Items[K].Paths));
  if not B.Valid then Exit;
  LI0 := Max(0, ColOf(B.MinX) - 1);
  LJ0 := Max(0, RowOf(B.MinY) - 1);
  R.MinX := FX0 + LI0 * FRes;
  R.MinY := FY0 + LJ0 * FRes;
  R.MaxX := Min(FX0 + FW * FRes, B.MaxX + 2 * FRes);
  R.MaxY := Min(FY0 + FH * FRes, B.MaxY + 2 * FRes);
  R.Valid := True;
  if (R.MaxX <= R.MinX) or (R.MaxY <= R.MinY) then Exit;
  Loc := TLPMask.Create(R, FRes);
  try
    for K := 0 to High(S.Items) do
      if S.Items[K].Dark then
        Loc.FillItem(S.Items[K].Paths, 1, Loc)
      else
        Loc.FillItem(S.Items[K].Paths, 0, Loc);
    for J := 0 to Loc.FH - 1 do
      for I := 0 to Loc.FW - 1 do
        if Loc.Data[J * Loc.FW + I] <> 0 then
          SetPx(LI0 + I, LJ0 + J, V);
  finally
    Loc.Free;
  end;
end;

procedure TLPMask.DrawGerber(L: TLPGerberLayer);
var
  I: Integer;
begin
  for I := 0 to L.ShapeCount - 1 do
    DrawShape(L.Shape(I));
  if L.Negative then Invert;
end;

procedure TLPMask.DrawHoles(D: TLPDrillFile; Value: Byte; Grow: Double);
var
  I: Integer;
  R: Double;
  Ps: TLPPaths;
begin
  for I := 0 to High(D.Holes) do
  begin
    if (D.Holes[I].Tool < 0) or (D.Holes[I].Tool > High(D.Tools)) then Continue;
    R := D.Tools[D.Holes[I].Tool].Diameter + 2 * Grow;
    if R <= 0 then Continue;
    Ps := nil;
    if D.Holes[I].Slot then
      LPAddPath(Ps, LPCapsule(D.Holes[I].X, D.Holes[I].Y, D.Holes[I].X2, D.Holes[I].Y2, R, FRes / 2))
    else
      LPAddPath(Ps, LPCircle(D.Holes[I].X, D.Holes[I].Y, R / 2, FRes / 2));
    FillItem(Ps, Value, Self);
  end;
end;

procedure TLPMask.Invert;
var
  I: Integer;
begin
  for I := 0 to High(Data) do
    Data[I] := 1 - Ord(Data[I] <> 0);
end;

procedure TLPMask.AndMask(Other: TLPMask);
var
  I: Integer;
begin
  for I := 0 to Min(High(Data), High(Other.Data)) do
    if Other.Data[I] = 0 then Data[I] := 0;
end;

procedure TLPMask.OrMask(Other: TLPMask);
var
  I: Integer;
begin
  for I := 0 to Min(High(Data), High(Other.Data)) do
    if Other.Data[I] <> 0 then Data[I] := 1;
end;

procedure TLPMask.AndNotMask(Other: TLPMask);
var
  I: Integer;
begin
  for I := 0 to Min(High(Data), High(Other.Data)) do
    if Other.Data[I] <> 0 then Data[I] := 0;
end;

function TLPMask.CountSet: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(Data) do
    if Data[I] <> 0 then Inc(Result);
end;

{ ---------------- TLPField (EDT) ---------------- }

{ transformada 1D da distancia ao quadrado (Felzenszwalb & Huttenlocher) }
procedure DT1D(const F: array of Double; N: Integer; var D: array of Double;
  var V: array of Integer; var Z: array of Double);
var
  K, Q: Integer;
  S: Double;
begin
  K := 0;
  V[0] := 0;
  Z[0] := -INF;
  Z[1] := INF;
  for Q := 1 to N - 1 do
  begin
    S := ((F[Q] + Sqr(Double(Q))) - (F[V[K]] + Sqr(Double(V[K])))) / (2.0 * Q - 2.0 * V[K]);
    while S <= Z[K] do
    begin
      Dec(K);
      S := ((F[Q] + Sqr(Double(Q))) - (F[V[K]] + Sqr(Double(V[K])))) / (2.0 * Q - 2.0 * V[K]);
    end;
    Inc(K);
    V[K] := Q;
    Z[K] := S;
    Z[K + 1] := INF;
  end;
  K := 0;
  for Q := 0 to N - 1 do
  begin
    while Z[K + 1] < Q do Inc(K);
    D[Q] := Sqr(Double(Q - V[K])) + F[V[K]];
  end;
end;

constructor TLPField.Create(M: TLPMask; Feature: Byte; MaxDist: Double);
var
  I, J, N: Integer;
  F, Dd, Z: array of Double;
  V: array of Integer;
  Big: Double;
begin
  inherited Create;
  W := M.Width;
  H := M.Height;
  X0 := M.X0;
  Y0 := M.Y0;
  Res := M.Res;
  SetLength(D, W * H);
  N := Max(W, H);
  SetLength(F, N);
  SetLength(Dd, N);
  SetLength(Z, N + 1);
  SetLength(V, N);
  { "infinito" finito: mantem a aritmetica do envelope estavel }
  Big := Sqr(Double(W + H)) * 4 + 1;
  { colunas }
  for I := 0 to W - 1 do
  begin
    for J := 0 to H - 1 do
      if (M.Data[J * W + I] <> 0) = (Feature <> 0) then F[J] := 0 else F[J] := Big;
    DT1D(F, H, Dd, V, Z);
    for J := 0 to H - 1 do D[J * W + I] := Dd[J];
  end;
  { linhas }
  for J := 0 to H - 1 do
  begin
    for I := 0 to W - 1 do F[I] := D[J * W + I];
    DT1D(F, W, Dd, V, Z);
    for I := 0 to W - 1 do
      if Dd[I] >= Big then D[J * W + I] := INF
      else D[J * W + I] := Sqrt(Dd[I]) * Res;
  end;
  if MaxDist > 0 then ;
end;

function TLPField.Get(I, J: Integer): Single;
begin
  if (I < 0) or (J < 0) or (I >= W) or (J >= H) then Exit(INF);
  Result := D[J * W + I];
end;

{ ---------------- marching squares ---------------- }

type
  TEdgeLink = record
    Key: Int64;
    A, B: Int64;   { as duas arestas ligadas a esta (outras pontas) }
    X, Y: Double;
    Used: Boolean;
  end;

  { tabela hash simples Int64 -> indice }
  TEdgeTable = class
  private
    FKeys: array of Int64;
    FVals: array of Integer;
    FMask: Int64;
    FCount: Integer;
  public
    Links: array of TEdgeLink;
    LinkCount: Integer;
    constructor Create(Cap: Integer);
    function Find(Key: Int64): Integer;
    function Ensure(Key: Int64; X, Y: Double): Integer;
    procedure Connect(K1, K2: Int64; X1, Y1, X2, Y2: Double);
  end;

constructor TEdgeTable.Create(Cap: Integer);
var
  N: Int64;
begin
  inherited Create;
  N := 1024;
  while N < Cap * 2 do N := N * 2;
  SetLength(FKeys, N);
  SetLength(FVals, N);
  for N := 0 to High(FKeys) do FKeys[N] := -1;
  FMask := Length(FKeys) - 1;
  SetLength(Links, 1024);
end;

function TEdgeTable.Find(Key: Int64): Integer;
var
  H: Int64;
begin
  H := (Key * 2654435761) and FMask;
  while FKeys[H] <> -1 do
  begin
    if FKeys[H] = Key then Exit(FVals[H]);
    H := (H + 1) and FMask;
  end;
  Result := -1;
end;

function TEdgeTable.Ensure(Key: Int64; X, Y: Double): Integer;
var
  H, I: Int64;
  OldK: array of Int64;
  OldV: array of Integer;
begin
  Result := Find(Key);
  if Result >= 0 then Exit;
  if FCount * 2 >= Length(FKeys) then
  begin
    OldK := FKeys;
    OldV := FVals;
    SetLength(FKeys, Length(OldK) * 2);
    SetLength(FVals, Length(OldK) * 2);
    for I := 0 to High(FKeys) do FKeys[I] := -1;
    FMask := Length(FKeys) - 1;
    FCount := 0;
    for I := 0 to High(OldK) do
      if OldK[I] <> -1 then
      begin
        H := (OldK[I] * 2654435761) and FMask;
        while FKeys[H] <> -1 do H := (H + 1) and FMask;
        FKeys[H] := OldK[I];
        FVals[H] := OldV[I];
        Inc(FCount);
      end;
  end;
  H := (Key * 2654435761) and FMask;
  while FKeys[H] <> -1 do H := (H + 1) and FMask;
  FKeys[H] := Key;
  if LinkCount >= Length(Links) then SetLength(Links, LinkCount * 2);
  Links[LinkCount].Key := Key;
  Links[LinkCount].A := -1;
  Links[LinkCount].B := -1;
  Links[LinkCount].X := X;
  Links[LinkCount].Y := Y;
  Links[LinkCount].Used := False;
  FVals[H] := LinkCount;
  Result := LinkCount;
  Inc(LinkCount);
  Inc(FCount);
end;

procedure TEdgeTable.Connect(K1, K2: Int64; X1, Y1, X2, Y2: Double);
var
  I1, I2: Integer;
begin
  I1 := Ensure(K1, X1, Y1);
  I2 := Ensure(K2, X2, Y2);
  if Links[I1].A = -1 then Links[I1].A := K2 else Links[I1].B := K2;
  if Links[I2].A = -1 then Links[I2].A := K1 else Links[I2].B := K1;
end;

{ amostra com borda "longe" (pixel virtual fora da imagem) }
function Sample(F: TLPField; I, J: Integer): Double; inline;
begin
  if (I < 0) or (J < 0) or (I >= F.W) or (J >= F.H) then Exit(INF);
  Result := F.D[J * F.W + I];
end;

function LPIsoContours(F: TLPField; Level: Double; Tol: Double): TLPPaths;
var
  Tab: TEdgeTable;
  I, J, Idx, Code: Integer;
  V0, V1, V2, V3, C: Double;
  WE: Int64;
  { chaves das arestas da celula (I,J) com cantos (I,J),(I+1,J),(I+1,J+1),(I,J+1) }
  KB, KR, KT, KL: Int64;
  XB, YB, XR, YR, XT, YT, XL, YL: Double;
  Cur, Prev, Nxt: Int64;
  P: TLPPath;
  L: TEdgeLink;
  Cell: Double;

  function Lerp(A, B: Double): Double; inline;
  begin
    if Abs(B - A) < 1e-12 then Exit(0.5);
    Result := EnsureRange((Level - A) / (B - A), 0, 1);
  end;

  function PX(I0: Integer): Double; inline;
  begin
    Result := F.X0 + (I0 + 0.5) * Cell;
  end;

  function PY(J0: Integer): Double; inline;
  begin
    Result := F.Y0 + (J0 + 0.5) * Cell;
  end;

begin
  Result := nil;
  Cell := F.Res;
  WE := F.W + 2;
  Tab := TEdgeTable.Create(4096);
  try
    { celulas de -1..W-1 / -1..H-1: a moldura virtual fecha os contornos }
    for J := -1 to F.H - 1 do
      for I := -1 to F.W - 1 do
      begin
        V0 := Sample(F, I, J);
        V1 := Sample(F, I + 1, J);
        V2 := Sample(F, I + 1, J + 1);
        V3 := Sample(F, I, J + 1);
        Code := 0;
        if V0 < Level then Code := Code or 1;
        if V1 < Level then Code := Code or 2;
        if V2 < Level then Code := Code or 4;
        if V3 < Level then Code := Code or 8;
        if (Code = 0) or (Code = 15) then Continue;
        { chaves unicas: aresta horizontal (I,J)->(I+1,J) = 2*idx; vertical (I,J)->(I,J+1) = 2*idx+1 }
        KB := 2 * ((Int64(J) + 1) * WE + (I + 1));
        KT := 2 * ((Int64(J) + 2) * WE + (I + 1));
        KL := 2 * ((Int64(J) + 1) * WE + (I + 1)) + 1;
        KR := 2 * ((Int64(J) + 1) * WE + (I + 2)) + 1;
        XB := PX(I) + Lerp(V0, V1) * Cell; YB := PY(J);
        XT := PX(I) + Lerp(V3, V2) * Cell; YT := PY(J + 1);
        XL := PX(I); YL := PY(J) + Lerp(V0, V3) * Cell;
        XR := PX(I + 1); YR := PY(J) + Lerp(V1, V2) * Cell;
        case Code of
          1, 14: Tab.Connect(KL, KB, XL, YL, XB, YB);
          2, 13: Tab.Connect(KB, KR, XB, YB, XR, YR);
          3, 12: Tab.Connect(KL, KR, XL, YL, XR, YR);
          4, 11: Tab.Connect(KR, KT, XR, YR, XT, YT);
          6, 9: Tab.Connect(KB, KT, XB, YB, XT, YT);
          7, 8: Tab.Connect(KL, KT, XL, YL, XT, YT);
          5, 10:
            begin
              { sela: decide pelo centro }
              C := (V0 + V1 + V2 + V3) / 4;
              if (C < Level) = (Code = 5) then
              begin
                Tab.Connect(KL, KT, XL, YL, XT, YT);
                Tab.Connect(KB, KR, XB, YB, XR, YR);
              end
              else
              begin
                Tab.Connect(KL, KB, XL, YL, XB, YB);
                Tab.Connect(KR, KT, XR, YR, XT, YT);
              end;
            end;
        end;
      end;
    { percorre os ciclos }
    for Idx := 0 to Tab.LinkCount - 1 do
    begin
      if Tab.Links[Idx].Used then Continue;
      P := nil;
      Prev := -1;
      Cur := Tab.Links[Idx].Key;
      repeat
        I := Tab.Find(Cur);
        if (I < 0) or Tab.Links[I].Used then Break;
        Tab.Links[I].Used := True;
        L := Tab.Links[I];
        LPAddPoint(P, L.X, L.Y);
        if (L.A <> Prev) and (L.A <> -1) then Nxt := L.A else Nxt := L.B;
        if Nxt = -1 then Break;
        Prev := Cur;
        Cur := Nxt;
      until False;
      if Length(P) >= 3 then
      begin
        LPAddPoint(P, P[0].X, P[0].Y);
        if Tol > 0 then P := LPSimplify(P, Tol);
        if Length(P) >= 3 then LPAddPath(Result, P);
      end;
    end;
  finally
    Tab.Free;
  end;
end;

function LPMaskContours(M: TLPMask; Tol: Double): TLPPaths;
var
  F: TLPField;
  I: Integer;
begin
  { campo 0 (dentro) / 1 (fora): nivel 0,5 = borda }
  F := TLPField.Create(M, 1, 0);
  try
    for I := 0 to High(F.D) do
      if M.Data[I] <> 0 then F.D[I] := 0 else F.D[I] := 1;
    Result := LPIsoContours(F, 0.5, Tol);
  finally
    F.Free;
  end;
end;

end.
