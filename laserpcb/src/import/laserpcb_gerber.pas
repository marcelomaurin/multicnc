unit laserpcb_gerber;

{ Leitor Gerber RS-274X (e X2) do LaserPCB.

  Converte o arquivo em objetos graficos em milimetros:
  - Shapes: poligonos com polaridade (escuro/claro) na ordem do arquivo;
    e o que o rasterizador desenha (cobre, mascara, serigrafia).
  - Traces: linha de centro dos desenhos D01 (com largura da abertura);
    usados para contorno da placa e cortes.
  - Flashes: posicao e abertura de cada D03 (pads, fiduciais).

  Suporta: %FS (L/T, A/I), %MO / G70 / G71, %AD (C, R, O, P), %AM (macros
  com variaveis/expressoes e primitivas 0, 1, 4, 5, 6, 7, 20, 21, 22),
  D01/D02/D03, G01/G02/G03, G74/G75, G36/G37 (regioes), %LP (D/C),
  %LM/%LR/%LS (transformacao da abertura), %SR (step and repeat),
  %IP NEG, %OF, %TF.FileFunction (X2). Blocos %AB nao sao suportados
  (gera aviso). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, StrUtils, laserpcb_geom;

type
  { um poligono (um ou mais contornos, regra nao-zero) com exposicao }
  TLPGItem = record
    Paths: TLPPaths;
    Dark: Boolean;
  end;
  TLPGItems = array of TLPGItem;

  { objeto grafico: itens compostos localmente e aplicados na imagem com
    a polaridade Dark (LPD) ou clara (LPC) }
  TLPGShape = record
    Items: TLPGItems;
    Dark: Boolean;
  end;

  TLPTrace = record
    Path: TLPPath;
    Width: Double;
  end;

  TLPFlash = record
    X, Y: Double;
    Aperture: Integer;
    SizeX, SizeY: Double;  { caixa da abertura (mm) }
    Round: Boolean;
    Dark: Boolean;
  end;

  TLPApertureKind = (akCircle, akRect, akObround, akPolygon, akMacro);

  TLPAperture = record
    Code: Integer;
    Kind: TLPApertureKind;
    Params: array of Double;
    Shape: TLPGItems;      { geometria na origem (mm) }
    SizeX, SizeY: Double;
    Width: Double;         { largura de traco (circulo: diametro) }
    Defined: Boolean;
  end;

  TLPGerberLayer = class
  private
    FShapes: array of TLPGShape;
    FTraces: array of TLPTrace;
    FFlashes: array of TLPFlash;
    FShapeCount, FTraceCount, FFlashCount: Integer;
  public
    FileName: string;
    FileFunction: string;   { X2 %TF.FileFunction }
    Negative: Boolean;      { %IPNEG }
    Bounds: TLPRect;
    Warnings: TStringList;
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    procedure AddShape(const S: TLPGShape);
    procedure AddTrace(const P: TLPPath; W: Double);
    procedure AddFlash(const F: TLPFlash);
    function ShapeCount: Integer;
    function Shape(I: Integer): TLPGShape;
    function TraceCount: Integer;
    function Trace(I: Integer): TLPTrace;
    function FlashCount: Integer;
    function Flash(I: Integer): TLPFlash;
    { contornos das linhas de centro unidas (para contorno/outline) }
    function TracePaths(JoinTol: Double = 0.01): TLPPaths;
    { aplica uma matriz em toda a geometria }
    procedure Transform(const M: TLPMatrix);
  end;

  TLPGerberReader = class
  public
    { Tol: erro maximo de corda ao aproximar arcos/circulos (mm) }
    class function LoadFromFile(const FileName: string; Layer: TLPGerberLayer;
      Tol: Double = 0.005): Boolean;
    class function LoadFromString(const Text: string; Layer: TLPGerberLayer;
      Tol: Double = 0.005): Boolean;
  end;

{ primitivas uteis tambem fora do leitor }
function LPCapsule(X1, Y1, X2, Y2, W, Tol: Double): TLPPath;
function LPRectPath(CX, CY, W, H: Double): TLPPath;
function LPObround(CX, CY, W, H, Tol: Double): TLPPath;
function LPConvexHull(const Pts: TLPPath): TLPPath;

implementation

const
  IN2MM = 25.4;

var
  InvFS: TFormatSettings;

function FloatInv(const S: string; Def: Double): Double;
begin
  if not TryStrToFloat(Trim(S), Result, InvFS) then Result := Def;
end;

{ ---------------- primitivas ---------------- }

function LPRectPath(CX, CY, W, H: Double): TLPPath;
begin
  Result := nil;
  LPAddPoint(Result, CX - W / 2, CY - H / 2);
  LPAddPoint(Result, CX + W / 2, CY - H / 2);
  LPAddPoint(Result, CX + W / 2, CY + H / 2);
  LPAddPoint(Result, CX - W / 2, CY + H / 2);
  LPAddPoint(Result, CX - W / 2, CY - H / 2);
end;

procedure AddArcPts(var P: TLPPath; CX, CY, R, A0, A1, Tol: Double);
var
  I, N: Integer;
  A: Double;
begin
  N := LPArcSegments(R, A1 - A0, Tol);
  for I := 0 to N do
  begin
    A := A0 + (A1 - A0) * I / N;
    LPAddPoint(P, CX + R * Cos(A), CY + R * Sin(A));
  end;
end;

function LPCapsule(X1, Y1, X2, Y2, W, Tol: Double): TLPPath;
var
  A, R: Double;
begin
  Result := nil;
  R := W / 2;
  if Hypot(X2 - X1, Y2 - Y1) < 1e-9 then
    Exit(LPCircle(X1, Y1, R, Tol));
  A := ArcTan2(Y2 - Y1, X2 - X1);
  AddArcPts(Result, X2, Y2, R, A - Pi / 2, A + Pi / 2, Tol);
  AddArcPts(Result, X1, Y1, R, A + Pi / 2, A + 3 * Pi / 2, Tol);
  LPAddPoint(Result, Result[0].X, Result[0].Y);
end;

function LPObround(CX, CY, W, H, Tol: Double): TLPPath;
var
  R: Double;
begin
  if Abs(W - H) < 1e-9 then Exit(LPCircle(CX, CY, W / 2, Tol));
  if W > H then
  begin
    R := H / 2;
    Result := LPCapsule(CX - W / 2 + R, CY, CX + W / 2 - R, CY, H, Tol);
  end
  else
  begin
    R := W / 2;
    Result := LPCapsule(CX, CY - H / 2 + R, CX, CY + H / 2 - R, W, Tol);
  end;
end;

function Cross(const O, A, B: TLPPoint): Double;
begin
  Result := (A.X - O.X) * (B.Y - O.Y) - (A.Y - O.Y) * (B.X - O.X);
end;

{ Andrew monotone chain }
function LPConvexHull(const Pts: TLPPath): TLPPath;
var
  P: TLPPath;
  H: TLPPath;
  I, J, K, N, T: Integer;
  Tmp: TLPPoint;
begin
  P := Copy(Pts);
  N := Length(P);
  { ordena por X, depois Y (insercao; listas pequenas) }
  for I := 1 to N - 1 do
  begin
    Tmp := P[I];
    J := I - 1;
    while (J >= 0) and ((P[J].X > Tmp.X) or ((P[J].X = Tmp.X) and (P[J].Y > Tmp.Y))) do
    begin
      P[J + 1] := P[J];
      Dec(J);
    end;
    P[J + 1] := Tmp;
  end;
  if N < 3 then Exit(P);
  SetLength(H, 2 * N);
  K := 0;
  for I := 0 to N - 1 do
  begin
    while (K >= 2) and (Cross(H[K - 2], H[K - 1], P[I]) <= 0) do Dec(K);
    H[K] := P[I];
    Inc(K);
  end;
  T := K + 1;
  for I := N - 2 downto 0 do
  begin
    while (K >= T) and (Cross(H[K - 2], H[K - 1], P[I]) <= 0) do Dec(K);
    H[K] := P[I];
    Inc(K);
  end;
  SetLength(H, K); { o ultimo repete o primeiro }
  Result := H;
end;

function Item(const P: TLPPath; Dark: Boolean): TLPGItem;
begin
  Result.Paths := nil;
  LPAddPath(Result.Paths, P);
  Result.Dark := Dark;
end;

procedure AddItem(var Items: TLPGItems; const It: TLPGItem);
var
  N: Integer;
begin
  N := Length(Items);
  SetLength(Items, N + 1);
  Items[N] := It;
end;

function TransformItems(const Items: TLPGItems; const M: TLPMatrix): TLPGItems;
var
  I: Integer;
begin
  SetLength(Result, Length(Items));
  for I := 0 to High(Items) do
  begin
    Result[I].Dark := Items[I].Dark;
    Result[I].Paths := LPApplyPaths(M, Items[I].Paths);
  end;
end;

function ItemsBounds(const Items: TLPGItems): TLPRect;
var
  I: Integer;
begin
  Result := LPEmptyRect;
  for I := 0 to High(Items) do
    LPRectIncludeRect(Result, LPPathsBounds(Items[I].Paths));
end;

{ ---------------- TLPGerberLayer ---------------- }

constructor TLPGerberLayer.Create;
begin
  inherited Create;
  Warnings := TStringList.Create;
  Clear;
end;

destructor TLPGerberLayer.Destroy;
begin
  Warnings.Free;
  inherited Destroy;
end;

procedure TLPGerberLayer.Clear;
begin
  SetLength(FShapes, 0);
  SetLength(FTraces, 0);
  SetLength(FFlashes, 0);
  FShapeCount := 0;
  FTraceCount := 0;
  FFlashCount := 0;
  FileFunction := '';
  Negative := False;
  Bounds := LPEmptyRect;
  Warnings.Clear;
end;

procedure TLPGerberLayer.AddShape(const S: TLPGShape);
begin
  if FShapeCount >= Length(FShapes) then
    SetLength(FShapes, Max(64, FShapeCount * 2));
  FShapes[FShapeCount] := S;
  Inc(FShapeCount);
  if S.Dark then
    LPRectIncludeRect(Bounds, ItemsBounds(S.Items));
end;

procedure TLPGerberLayer.AddTrace(const P: TLPPath; W: Double);
begin
  if FTraceCount >= Length(FTraces) then
    SetLength(FTraces, Max(64, FTraceCount * 2));
  FTraces[FTraceCount].Path := P;
  FTraces[FTraceCount].Width := W;
  Inc(FTraceCount);
end;

procedure TLPGerberLayer.AddFlash(const F: TLPFlash);
begin
  if FFlashCount >= Length(FFlashes) then
    SetLength(FFlashes, Max(64, FFlashCount * 2));
  FFlashes[FFlashCount] := F;
  Inc(FFlashCount);
end;

function TLPGerberLayer.ShapeCount: Integer;
begin
  Result := FShapeCount;
end;

function TLPGerberLayer.Shape(I: Integer): TLPGShape;
begin
  Result := FShapes[I];
end;

function TLPGerberLayer.TraceCount: Integer;
begin
  Result := FTraceCount;
end;

function TLPGerberLayer.Trace(I: Integer): TLPTrace;
begin
  Result := FTraces[I];
end;

function TLPGerberLayer.FlashCount: Integer;
begin
  Result := FFlashCount;
end;

function TLPGerberLayer.Flash(I: Integer): TLPFlash;
begin
  Result := FFlashes[I];
end;

function TLPGerberLayer.TracePaths(JoinTol: Double): TLPPaths;
var
  Segs: TLPPaths;
  Used: array of Boolean;
  I, J, N: Integer;
  Cur: TLPPath;
  Grew: Boolean;
  P: TLPPath;
begin
  Result := nil;
  Segs := nil;
  for I := 0 to FTraceCount - 1 do
    LPAddPath(Segs, FTraces[I].Path);
  N := Length(Segs);
  SetLength(Used, N);
  for I := 0 to N - 1 do
  begin
    if Used[I] then Continue;
    Used[I] := True;
    Cur := Copy(Segs[I]);
    repeat
      Grew := False;
      for J := 0 to N - 1 do
      begin
        if Used[J] then Continue;
        P := Segs[J];
        if LPDist(Cur[High(Cur)], P[0]) <= JoinTol then
          Cur := Concat(Cur, Copy(P, 1, Length(P) - 1))
        else if LPDist(Cur[High(Cur)], P[High(P)]) <= JoinTol then
        begin
          P := LPReversed(P);
          Cur := Concat(Cur, Copy(P, 1, Length(P) - 1));
        end
        else if LPDist(Cur[0], P[High(P)]) <= JoinTol then
          Cur := Concat(Copy(P, 0, Length(P) - 1), Cur)
        else if LPDist(Cur[0], P[0]) <= JoinTol then
        begin
          P := LPReversed(P);
          Cur := Concat(Copy(P, 0, Length(P) - 1), Cur);
        end
        else
          Continue;
        Used[J] := True;
        Grew := True;
      end;
    until not Grew;
    if (Length(Cur) > 2) and (LPDist(Cur[0], Cur[High(Cur)]) <= JoinTol) then
      Cur[High(Cur)] := Cur[0];
    LPAddPath(Result, Cur);
  end;
end;

procedure TLPGerberLayer.Transform(const M: TLPMatrix);
var
  I: Integer;
  P: TLPPoint;
  Paths: TLPPaths;
begin
  Bounds := LPEmptyRect;
  for I := 0 to FShapeCount - 1 do
  begin
    FShapes[I].Items := TransformItems(FShapes[I].Items, M);
    if FShapes[I].Dark then
      LPRectIncludeRect(Bounds, ItemsBounds(FShapes[I].Items));
  end;
  for I := 0 to FTraceCount - 1 do
  begin
    SetLength(Paths, 1);
    Paths[0] := FTraces[I].Path;
    Paths := LPApplyPaths(M, Paths);
    FTraces[I].Path := Paths[0];
  end;
  for I := 0 to FFlashCount - 1 do
  begin
    P := LPApply(M, LPPoint(FFlashes[I].X, FFlashes[I].Y));
    FFlashes[I].X := P.X;
    FFlashes[I].Y := P.Y;
  end;
end;

{ ---------------- expressoes de macro ---------------- }

type
  TMacroVars = array of Double;

  TExprParser = class
  private
    S: string;
    P: Integer;
    Vars: ^TMacroVars;
    function Peek: Char;
    function Expr: Double;
    function Term: Double;
    function Factor: Double;
  public
    function Eval(const AText: string; var AVars: TMacroVars): Double;
  end;

function TExprParser.Peek: Char;
begin
  while (P <= Length(S)) and (S[P] in [' ', #9]) do Inc(P);
  if P <= Length(S) then Result := S[P] else Result := #0;
end;

function TExprParser.Factor: Double;
var
  St, Idx: Integer;
  C: Char;
  V: Double;
begin
  C := Peek;
  if C = '-' then
  begin
    Inc(P);
    Exit(-Factor);
  end;
  if C = '+' then
  begin
    Inc(P);
    Exit(Factor);
  end;
  if C = '(' then
  begin
    Inc(P);
    Result := Expr;
    if Peek = ')' then Inc(P);
    Exit;
  end;
  if C = '$' then
  begin
    Inc(P);
    St := P;
    while (P <= Length(S)) and (S[P] in ['0'..'9']) do Inc(P);
    Idx := StrToIntDef(Copy(S, St, P - St), 0);
    if (Idx >= 1) and (Idx <= High(Vars^)) then
      Result := Vars^[Idx]
    else
      Result := 0;
    Exit;
  end;
  St := P;
  while (P <= Length(S)) and (S[P] in ['0'..'9', '.']) do Inc(P);
  V := FloatInv(Copy(S, St, P - St), 0);
  Result := V;
end;

function TExprParser.Term: Double;
var
  C: Char;
  R: Double;
begin
  Result := Factor;
  repeat
    C := Peek;
    if C in ['x', 'X'] then
    begin
      Inc(P);
      Result := Result * Factor;
    end
    else if C = '/' then
    begin
      Inc(P);
      R := Factor;
      if R <> 0 then Result := Result / R else Result := 0;
    end
    else
      Break;
  until False;
end;

function TExprParser.Expr: Double;
var
  C: Char;
begin
  Result := Term;
  repeat
    C := Peek;
    if C = '+' then
    begin
      Inc(P);
      Result := Result + Term;
    end
    else if C = '-' then
    begin
      Inc(P);
      Result := Result - Term;
    end
    else
      Break;
  until False;
end;

function TExprParser.Eval(const AText: string; var AVars: TMacroVars): Double;
begin
  S := AText;
  P := 1;
  Vars := @AVars;
  Result := Expr;
end;

{ ---------------- leitor ---------------- }

type
  TMacro = record
    Name: string;
    Body: TStringList;
  end;

  TGerberState = class
  public
    Layer: TLPGerberLayer;
    Tol: Double;
    Units: Double;           { fator para mm }
    IntDigits, DecDigits: Integer;
    OmitTrailing: Boolean;   { T: zeros a direita omitidos }
    Incremental: Boolean;
    Apertures: array of TLPAperture;
    Macros: array of TMacro;
    CurAp: Integer;          { indice em Apertures, -1 nenhum }
    X, Y: Double;            { posicao atual (mm) }
    Interp: Integer;         { 1 linear, 2 CW, 3 CCW }
    MultiQuadrant: Boolean;
    InRegion: Boolean;
    RegionContour: TLPPath;
    RegionItems: TLPGItems;
    Dark: Boolean;
    { transformacao das aberturas }
    LMx, LMy: Boolean;
    LRot, LScale: Double;
    { step and repeat }
    SRx, SRy: Integer;
    SRdx, SRdy: Double;
    SRStartShape, SRStartTrace, SRStartFlash: Integer;
    { trace corrente }
    CurTrace: TLPPath;
    CurTraceW: Double;
    OffX, OffY: Double;
    LastD: Integer;
    Expr: TExprParser;
    constructor Create(ALayer: TLPGerberLayer; ATol: Double);
    destructor Destroy; override;
    function ParseCoord(const V: string): Double;
    function FindAperture(Code: Integer): Integer;
    function FindMacro(const N: string): Integer;
    procedure FlushTrace;
    procedure CloseStepRepeat;
    procedure Extended(const Cmd: string);
    procedure Word(const W: string);
    procedure DefineAperture(const Cmd: string);
    procedure BuildMacroShape(var Ap: TLPAperture; MacroIdx: Integer);
    function ApertureMatrix: TLPMatrix;
    procedure DoFlash(PX, PY: Double);
    procedure DoDraw(X1, Y1, X2, Y2: Double);
    procedure DoArc(X1, Y1, X2, Y2, I, J: Double; CW: Boolean);
    procedure EmitStroke(const Pts: TLPPath);
  end;

constructor TGerberState.Create(ALayer: TLPGerberLayer; ATol: Double);
begin
  inherited Create;
  Layer := ALayer;
  Tol := ATol;
  Units := 1;
  IntDigits := 3;
  DecDigits := 6;
  CurAp := -1;
  Interp := 1;
  MultiQuadrant := True;
  Dark := True;
  LRot := 0;
  LScale := 1;
  SRx := 1;
  SRy := 1;
  LastD := 1;
  Expr := TExprParser.Create;
end;

destructor TGerberState.Destroy;
var
  I: Integer;
begin
  for I := 0 to High(Macros) do
    Macros[I].Body.Free;
  Expr.Free;
  inherited Destroy;
end;

function TGerberState.ParseCoord(const V: string): Double;
var
  S: string;
  Neg: Boolean;
  Total: Integer;
begin
  S := Trim(V);
  if S = '' then Exit(0);
  if Pos('.', S) > 0 then
    Exit(FloatInv(S, 0) * Units);
  Neg := False;
  if S[1] in ['+', '-'] then
  begin
    Neg := S[1] = '-';
    Delete(S, 1, 1);
  end;
  Total := IntDigits + DecDigits;
  if OmitTrailing then
    while Length(S) < Total do S := S + '0'
  else
    while Length(S) < DecDigits do S := '0' + S;
  Result := StrToInt64Def(S, 0) / IntPower(10, DecDigits) * Units;
  if OmitTrailing and (Length(S) > Total) then
    Result := StrToInt64Def(Copy(S, 1, Total), 0) / IntPower(10, DecDigits) * Units;
  if Neg then Result := -Result;
end;

function TGerberState.FindAperture(Code: Integer): Integer;
var
  I: Integer;
begin
  for I := 0 to High(Apertures) do
    if Apertures[I].Code = Code then Exit(I);
  Result := -1;
end;

function TGerberState.FindMacro(const N: string): Integer;
var
  I: Integer;
begin
  for I := 0 to High(Macros) do
    if SameText(Macros[I].Name, N) then Exit(I);
  Result := -1;
end;

function TGerberState.ApertureMatrix: TLPMatrix;
begin
  Result := LPIdentity;
  if LMx then Result := LPMul(Result, LPScale(-1, 1));
  if LMy then Result := LPMul(Result, LPScale(1, -1));
  if LRot <> 0 then Result := LPMul(Result, LPRotate(LRot));
  if LScale <> 1 then Result := LPMul(Result, LPScale(LScale, LScale));
end;

procedure TGerberState.FlushTrace;
begin
  if Length(CurTrace) >= 2 then
    Layer.AddTrace(CurTrace, CurTraceW);
  CurTrace := nil;
end;

procedure TGerberState.CloseStepRepeat;
var
  I, J, K, NS, NT, NF: Integer;
  S: TLPGShape;
  T: TLPTrace;
  F: TLPFlash;
  M: TLPMatrix;
  P: TLPPaths;
begin
  FlushTrace;
  if (SRx <= 1) and (SRy <= 1) then Exit;
  NS := Layer.ShapeCount;
  NT := Layer.TraceCount;
  NF := Layer.FlashCount;
  for I := 0 to SRx - 1 do
    for J := 0 to SRy - 1 do
    begin
      if (I = 0) and (J = 0) then Continue;
      M := LPTranslate(I * SRdx, J * SRdy);
      for K := SRStartShape to NS - 1 do
      begin
        S := Layer.Shape(K);
        S.Items := TransformItems(S.Items, M);
        Layer.AddShape(S);
      end;
      for K := SRStartTrace to NT - 1 do
      begin
        T := Layer.Trace(K);
        SetLength(P, 1);
        P[0] := T.Path;
        P := LPApplyPaths(M, P);
        Layer.AddTrace(P[0], T.Width);
      end;
      for K := SRStartFlash to NF - 1 do
      begin
        F := Layer.Flash(K);
        F.X := F.X + I * SRdx;
        F.Y := F.Y + J * SRdy;
        Layer.AddFlash(F);
      end;
    end;
  SRx := 1;
  SRy := 1;
end;

procedure SplitParams(const S: string; L: TStrings; Sep: Char);
begin
  L.Clear;
  L.StrictDelimiter := True;
  L.Delimiter := Sep;
  L.DelimitedText := S;
end;

procedure TGerberState.BuildMacroShape(var Ap: TLPAperture; MacroIdx: Integer);
var
  Vars: TMacroVars;
  Body: TStringList;
  Prm: TStringList;
  Line, Def: string;
  I, K, Code, N, Eq: Integer;
  V: array of Double;
  Exposure: Boolean;
  P: TLPPath;
  Rot, CX, CY, D, W, H, A, OD, ID, Gap, Thick: Double;
  M: TLPMatrix;
  It: TLPGItem;

  function Val(Idx: Integer): Double;
  begin
    if Idx <= High(V) then Result := V[Idx] else Result := 0;
  end;

  procedure AddRot(const Path: TLPPath; Dk: Boolean; RotDeg: Double);
  var
    Ps: TLPPaths;
  begin
    Ps := nil;
    LPAddPath(Ps, Path);
    if RotDeg <> 0 then Ps := LPApplyPaths(LPRotate(RotDeg), Ps);
    It.Paths := Ps;
    It.Dark := Dk;
    AddItem(Ap.Shape, It);
  end;

begin
  { variaveis: $1.. = parametros do %AD }
  SetLength(Vars, Length(Ap.Params) + 1 + 32);
  for I := 0 to High(Ap.Params) do
    Vars[I + 1] := Ap.Params[I];
  Body := Macros[MacroIdx].Body;
  Prm := TStringList.Create;
  try
    for K := 0 to Body.Count - 1 do
    begin
      Line := Trim(Body[K]);
      if Line = '' then Continue;
      if Line[1] = '0' then
        if (Length(Line) = 1) or (Line[2] in [' ', ',']) then Continue; { comentario }
      if Line[1] = '$' then
      begin
        Eq := Pos('=', Line);
        if Eq > 0 then
        begin
          N := StrToIntDef(Copy(Line, 2, Eq - 2), 0);
          if N >= Length(Vars) then SetLength(Vars, N + 1);
          Def := Copy(Line, Eq + 1, MaxInt);
          if N > 0 then Vars[N] := Expr.Eval(Def, Vars);
        end;
        Continue;
      end;
      SplitParams(Line, Prm, ',');
      if Prm.Count = 0 then Continue;
      Code := StrToIntDef(Trim(Prm[0]), -1);
      SetLength(V, Prm.Count);
      for I := 1 to Prm.Count - 1 do
        V[I] := Expr.Eval(Prm[I], Vars);
      Exposure := Val(1) <> 0;
      if (Code <> 6) and (Code <> 7) and (Prm.Count > 1) and (Round(Val(1)) = 2) then
        Exposure := not Exposure; { 2 = alterna (antigo) }
      case Code of
        1: { circulo: exp, diametro, cx, cy [, rot] }
          begin
            P := LPCircle(Val(3), Val(4), Val(2) / 2, Tol);
            AddRot(P, Exposure, Val(5));
          end;
        2, 20: { linha vetorial: exp, largura, x1, y1, x2, y2, rot }
          begin
            W := Val(2);
            A := ArcTan2(Val(6) - Val(4), Val(5) - Val(3));
            P := nil;
            LPAddPoint(P, Val(3) + W / 2 * Sin(A), Val(4) - W / 2 * Cos(A));
            LPAddPoint(P, Val(5) + W / 2 * Sin(A), Val(6) - W / 2 * Cos(A));
            LPAddPoint(P, Val(5) - W / 2 * Sin(A), Val(6) + W / 2 * Cos(A));
            LPAddPoint(P, Val(3) - W / 2 * Sin(A), Val(4) + W / 2 * Cos(A));
            LPAddPoint(P, P[0].X, P[0].Y);
            AddRot(P, Exposure, Val(7));
          end;
        21: { linha central: exp, largura, altura, cx, cy, rot }
          AddRot(LPRectPath(Val(4), Val(5), Val(2), Val(3)), Exposure, Val(6));
        22: { linha inferior-esquerda (antigo): exp, w, h, x, y, rot }
          AddRot(LPRectPath(Val(4) + Val(2) / 2, Val(5) + Val(3) / 2, Val(2), Val(3)), Exposure, Val(6));
        4: { contorno: exp, n, x0, y0, ..., xn, yn, rot }
          begin
            N := Round(Val(2));
            P := nil;
            for I := 0 to N do
              LPAddPoint(P, Val(3 + 2 * I), Val(4 + 2 * I));
            AddRot(P, Exposure, Val(3 + 2 * (N + 1)));
          end;
        5: { poligono: exp, vertices, cx, cy, diametro, rot }
          begin
            N := Max(3, Round(Val(2)));
            P := nil;
            for I := 0 to N do
              LPAddPoint(P, Val(3) + Val(5) / 2 * Cos(2 * Pi * I / N),
                Val(4) + Val(5) / 2 * Sin(2 * Pi * I / N));
            AddRot(P, Exposure, Val(6));
          end;
        6: { moire: cx, cy, d ext, espessura anel, folga, n aneis, esp cruz, comp cruz, rot }
          begin
            CX := Val(1); CY := Val(2); D := Val(3);
            Thick := Val(4); Gap := Val(5);
            Rot := Val(9);
            for I := 0 to Round(Val(6)) - 1 do
            begin
              if D <= 0 then Break;
              AddRot(LPCircle(CX, CY, D / 2, Tol), True, Rot);
              if D - 2 * Thick > 0 then
                AddRot(LPCircle(CX, CY, D / 2 - Thick, Tol), False, Rot);
              D := D - 2 * (Thick + Gap);
            end;
            AddRot(LPRectPath(CX, CY, Val(8), Val(7)), True, Rot);
            AddRot(LPRectPath(CX, CY, Val(7), Val(8)), True, Rot);
          end;
        7: { termico: cx, cy, d ext, d int, folga, rot }
          begin
            CX := Val(1); CY := Val(2); OD := Val(3); ID := Val(4); Gap := Val(5);
            Rot := Val(6);
            AddRot(LPCircle(CX, CY, OD / 2, Tol), True, Rot);
            AddRot(LPCircle(CX, CY, ID / 2, Tol), False, Rot);
            AddRot(LPRectPath(CX, CY, OD + 1, Gap), False, Rot);
            AddRot(LPRectPath(CX, CY, Gap, OD + 1), False, Rot);
          end;
      else
        Layer.Warnings.Add(Format('Macro %s: primitiva %d ignorada', [Macros[MacroIdx].Name, Code]));
      end;
    end;
  finally
    Prm.Free;
  end;
  if Units <> 1 then
  begin
    M := LPScale(Units, Units);
    Ap.Shape := TransformItems(Ap.Shape, M);
  end;
end;

procedure TGerberState.DefineAperture(const Cmd: string);
var
  S, Name, Mods: string;
  I, Comma, Idx: Integer;
  Prm: TStringList;
  Ap: TLPAperture;
  P: TLPPath;
  R: TLPRect;
  N: Integer;
  Rot: Double;
begin
  { ADD10C,0.5X0.2 }
  S := Copy(Cmd, 3, MaxInt);
  if (S = '') or (S[1] <> 'D') then Exit;
  Delete(S, 1, 1);
  I := 1;
  while (I <= Length(S)) and (S[I] in ['0'..'9']) do Inc(I);
  Ap.Code := StrToIntDef(Copy(S, 1, I - 1), -1);
  Delete(S, 1, I - 1);
  Comma := Pos(',', S);
  if Comma > 0 then
  begin
    Name := Copy(S, 1, Comma - 1);
    Mods := Copy(S, Comma + 1, MaxInt);
  end
  else
  begin
    Name := S;
    Mods := '';
  end;
  Prm := TStringList.Create;
  try
    SplitParams(Mods, Prm, 'X');
    SetLength(Ap.Params, Prm.Count);
    for I := 0 to Prm.Count - 1 do
      Ap.Params[I] := FloatInv(Trim(Prm[I]), 0);
  finally
    Prm.Free;
  end;
  if Mods = '' then SetLength(Ap.Params, 0);
  Ap.Shape := nil;
  Ap.Defined := True;
  Ap.Width := 0;
  if Name = 'C' then
  begin
    Ap.Kind := akCircle;
    if Length(Ap.Params) > 0 then
    begin
      P := LPCircle(0, 0, Ap.Params[0] * Units / 2, Tol);
      AddItem(Ap.Shape, Item(P, True));
      Ap.Width := Ap.Params[0] * Units;
    end;
    if Length(Ap.Params) > 1 then
      AddItem(Ap.Shape, Item(LPCircle(0, 0, Ap.Params[1] * Units / 2, Tol), False));
  end
  else if (Name = 'R') or (Name = 'O') then
  begin
    if Name = 'R' then Ap.Kind := akRect else Ap.Kind := akObround;
    if Length(Ap.Params) >= 2 then
    begin
      if Name = 'R' then
        P := LPRectPath(0, 0, Ap.Params[0] * Units, Ap.Params[1] * Units)
      else
        P := LPObround(0, 0, Ap.Params[0] * Units, Ap.Params[1] * Units, Tol);
      AddItem(Ap.Shape, Item(P, True));
      Ap.Width := Min(Ap.Params[0], Ap.Params[1]) * Units;
    end;
    if Length(Ap.Params) > 2 then
      AddItem(Ap.Shape, Item(LPCircle(0, 0, Ap.Params[2] * Units / 2, Tol), False));
  end
  else if Name = 'P' then
  begin
    Ap.Kind := akPolygon;
    if Length(Ap.Params) >= 2 then
    begin
      N := Max(3, Round(Ap.Params[1]));
      if Length(Ap.Params) > 2 then Rot := Ap.Params[2] else Rot := 0;
      P := nil;
      for I := 0 to N do
        LPAddPoint(P, Ap.Params[0] * Units / 2 * Cos(DegToRad(Rot) + 2 * Pi * I / N),
          Ap.Params[0] * Units / 2 * Sin(DegToRad(Rot) + 2 * Pi * I / N));
      AddItem(Ap.Shape, Item(P, True));
      Ap.Width := Ap.Params[0] * Units;
    end;
    if Length(Ap.Params) > 3 then
      AddItem(Ap.Shape, Item(LPCircle(0, 0, Ap.Params[3] * Units / 2, Tol), False));
  end
  else
  begin
    Ap.Kind := akMacro;
    Idx := FindMacro(Name);
    if Idx < 0 then
      Layer.Warnings.Add('Abertura D' + IntToStr(Ap.Code) + ': macro desconhecida ' + Name)
    else
      BuildMacroShape(Ap, Idx);
  end;
  R := ItemsBounds(Ap.Shape);
  Ap.SizeX := LPRectWidth(R);
  Ap.SizeY := LPRectHeight(R);
  if Ap.Width = 0 then Ap.Width := Min(Ap.SizeX, Ap.SizeY);
  I := FindAperture(Ap.Code);
  if I < 0 then
  begin
    I := Length(Apertures);
    SetLength(Apertures, I + 1);
  end;
  Apertures[I] := Ap;
end;

procedure TGerberState.DoFlash(PX, PY: Double);
var
  S: TLPGShape;
  F: TLPFlash;
  M: TLPMatrix;
begin
  FlushTrace;
  if CurAp < 0 then
  begin
    Layer.Warnings.Add('D03 sem abertura selecionada');
    Exit;
  end;
  M := LPMul(ApertureMatrix, LPTranslate(PX, PY));
  S.Items := TransformItems(Apertures[CurAp].Shape, M);
  S.Dark := Dark;
  if Length(S.Items) > 0 then Layer.AddShape(S);
  F.X := PX;
  F.Y := PY;
  F.Aperture := Apertures[CurAp].Code;
  F.SizeX := Apertures[CurAp].SizeX * LScale;
  F.SizeY := Apertures[CurAp].SizeY * LScale;
  F.Round := Apertures[CurAp].Kind = akCircle;
  F.Dark := Dark;
  Layer.AddFlash(F);
end;

{ traco de uma polilinha com a abertura atual: circulo -> capsulas;
  outras (convexas) -> casco convexo da abertura nas duas pontas }
procedure TGerberState.EmitStroke(const Pts: TLPPath);
var
  I, K: Integer;
  S: TLPGShape;
  Ap: TLPAperture;
  Hull, ApPts: TLPPath;
  Tr: TLPPaths;
begin
  if CurAp < 0 then
  begin
    Layer.Warnings.Add('D01 sem abertura selecionada');
    Exit;
  end;
  Ap := Apertures[CurAp];
  S.Dark := Dark;
  S.Items := nil;
  if Ap.Kind = akCircle then
  begin
    for I := 1 to High(Pts) do
      AddItem(S.Items, Item(LPCapsule(Pts[I - 1].X, Pts[I - 1].Y, Pts[I].X, Pts[I].Y,
        Ap.Width * LScale, Tol), True));
  end
  else
  begin
    if Length(Ap.Shape) = 0 then Exit;
    Tr := TransformItems(Ap.Shape, ApertureMatrix)[0].Paths;
    if Length(Tr) = 0 then Exit;
    ApPts := Tr[0];
    for I := 1 to High(Pts) do
    begin
      Hull := nil;
      for K := 0 to High(ApPts) do
      begin
        LPAddPoint(Hull, ApPts[K].X + Pts[I - 1].X, ApPts[K].Y + Pts[I - 1].Y);
        LPAddPoint(Hull, ApPts[K].X + Pts[I].X, ApPts[K].Y + Pts[I].Y);
      end;
      Hull := LPConvexHull(Hull);
      AddItem(S.Items, Item(Hull, True));
    end;
  end;
  if Length(S.Items) > 0 then Layer.AddShape(S);
  { linha de centro }
  if (Length(CurTrace) > 0) and (LPDist(CurTrace[High(CurTrace)], Pts[0]) < 1e-6)
     and (Abs(CurTraceW - Ap.Width) < 1e-9) then
  begin
    for I := 1 to High(Pts) do
      LPAddPoint(CurTrace, Pts[I].X, Pts[I].Y);
  end
  else
  begin
    FlushTrace;
    CurTrace := Copy(Pts);
    CurTraceW := Ap.Width * LScale;
  end;
end;

procedure TGerberState.DoDraw(X1, Y1, X2, Y2: Double);
var
  P: TLPPath;
begin
  P := nil;
  LPAddPoint(P, X1, Y1);
  LPAddPoint(P, X2, Y2);
  if InRegion then
  begin
    if Length(RegionContour) = 0 then LPAddPoint(RegionContour, X1, Y1);
    LPAddPoint(RegionContour, X2, Y2);
  end
  else
    EmitStroke(P);
end;

procedure TGerberState.DoArc(X1, Y1, X2, Y2, I, J: Double; CW: Boolean);
var
  CX, CY, R, A0, A1, Sweep, BestErr, Err, TCX, TCY, S0: Double;
  K, N, SX, SY: Integer;
  P: TLPPath;
begin
  if MultiQuadrant then
  begin
    CX := X1 + I;
    CY := Y1 + J;
  end
  else
  begin
    { quadrante unico: I/J sem sinal; escolhe o centro coerente }
    BestErr := MaxDouble;
    CX := X1 + I; CY := Y1 + J;
    for SX := -1 to 1 do
      for SY := -1 to 1 do
      begin
        if (SX = 0) or (SY = 0) then Continue;
        TCX := X1 + SX * Abs(I);
        TCY := Y1 + SY * Abs(J);
        Err := Abs(Hypot(X1 - TCX, Y1 - TCY) - Hypot(X2 - TCX, Y2 - TCY));
        A0 := ArcTan2(Y1 - TCY, X1 - TCX);
        A1 := ArcTan2(Y2 - TCY, X2 - TCX);
        if CW then S0 := A0 - A1 else S0 := A1 - A0;
        while S0 < 0 do S0 := S0 + 2 * Pi;
        if S0 > Pi / 2 + 1e-3 then Err := Err + 1000;
        if Err < BestErr then
        begin
          BestErr := Err; CX := TCX; CY := TCY;
        end;
      end;
  end;
  R := Hypot(X1 - CX, Y1 - CY);
  A0 := ArcTan2(Y1 - CY, X1 - CX);
  A1 := ArcTan2(Y2 - CY, X2 - CX);
  if CW then
  begin
    Sweep := A1 - A0;
    while Sweep >= 0 do Sweep := Sweep - 2 * Pi;
    if MultiQuadrant and (Hypot(X2 - X1, Y2 - Y1) < 1e-9) then Sweep := -2 * Pi
    else if (not MultiQuadrant) and (Sweep < -Pi) then Sweep := Sweep + 2 * Pi;
    if Sweep < -2 * Pi then Sweep := Sweep + 2 * Pi;
  end
  else
  begin
    Sweep := A1 - A0;
    while Sweep <= 0 do Sweep := Sweep + 2 * Pi;
    if MultiQuadrant and (Hypot(X2 - X1, Y2 - Y1) < 1e-9) then Sweep := 2 * Pi
    else if (not MultiQuadrant) and (Sweep > Pi) then Sweep := Sweep - 2 * Pi;
    if Sweep > 2 * Pi then Sweep := Sweep - 2 * Pi;
  end;
  N := LPArcSegments(R, Sweep, Tol);
  P := nil;
  for K := 0 to N do
    LPAddPoint(P, CX + R * Cos(A0 + Sweep * K / N), CY + R * Sin(A0 + Sweep * K / N));
  P[0].X := X1; P[0].Y := Y1;
  P[High(P)].X := X2; P[High(P)].Y := Y2;
  if InRegion then
  begin
    if Length(RegionContour) = 0 then LPAddPoint(RegionContour, X1, Y1);
    for K := 1 to High(P) do
      LPAddPoint(RegionContour, P[K].X, P[K].Y);
  end
  else
    EmitStroke(P);
end;

procedure TGerberState.Extended(const Cmd: string);
var
  C, S: string;
  P, I: Integer;
  Vals: TStringList;
begin
  C := Copy(Cmd, 1, 2);
  if C = 'FS' then
  begin
    S := Cmd;
    OmitTrailing := Pos('T', Copy(S, 3, 2)) > 0;
    Incremental := Pos('I', Copy(S, 3, 3)) > 0;
    P := Pos('X', S);
    if (P > 0) and (P + 2 <= Length(S)) then
    begin
      IntDigits := StrToIntDef(S[P + 1], 3);
      DecDigits := StrToIntDef(S[P + 2], 6);
    end;
  end
  else if C = 'MO' then
  begin
    if Pos('IN', Cmd) = 3 then Units := IN2MM else Units := 1;
  end
  else if C = 'AD' then
    DefineAperture(Cmd)
  else if C = 'LP' then
  begin
    FlushTrace;
    Dark := Copy(Cmd, 3, 1) <> 'C';
  end
  else if C = 'LM' then
  begin
    S := Copy(Cmd, 3, MaxInt);
    LMx := (S = 'X') or (S = 'XY');
    LMy := (S = 'Y') or (S = 'XY');
  end
  else if C = 'LR' then
    LRot := FloatInv(Copy(Cmd, 3, MaxInt), 0)
  else if C = 'LS' then
    LScale := FloatInv(Copy(Cmd, 3, MaxInt), 1)
  else if C = 'IP' then
    Layer.Negative := Pos('NEG', Cmd) > 0
  else if C = 'OF' then
  begin
    S := Cmd;
    P := Pos('A', S);
    I := Pos('B', S);
    if P > 0 then
      OffX := FloatInv(Copy(S, P + 1, IfThen(I > 0, I - P - 1, MaxInt)), 0) * Units;
    if I > 0 then
      OffY := FloatInv(Copy(S, I + 1, MaxInt), 0) * Units;
  end
  else if C = 'SR' then
  begin
    CloseStepRepeat;
    Vals := TStringList.Create;
    try
      S := Copy(Cmd, 3, MaxInt);
      SRx := 1; SRy := 1; SRdx := 0; SRdy := 0;
      P := 1;
      while P <= Length(S) do
      begin
        C := S[P];
        Inc(P);
        I := P;
        while (P <= Length(S)) and (S[P] in ['0'..'9', '.', '-', '+']) do Inc(P);
        case C of
          'X': SRx := Max(1, StrToIntDef(Copy(S, I, P - I), 1));
          'Y': SRy := Max(1, StrToIntDef(Copy(S, I, P - I), 1));
          'I': SRdx := FloatInv(Copy(S, I, P - I), 0) * Units;
          'J': SRdy := FloatInv(Copy(S, I, P - I), 0) * Units;
        end;
      end;
    finally
      Vals.Free;
    end;
    SRStartShape := Layer.ShapeCount;
    SRStartTrace := Layer.TraceCount;
    SRStartFlash := Layer.FlashCount;
  end
  else if Copy(Cmd, 1, 3) = 'TF.' then
  begin
    if Pos('.FileFunction', Cmd) = 3 then
      Layer.FileFunction := Copy(Cmd, Length('TF.FileFunction,') + 1, MaxInt);
  end
  else if C = 'AB' then
    Layer.Warnings.Add('Blocos de abertura (%AB) nao suportados')
  else if (C = 'IR') or (C = 'MI') or (C = 'SF') then
    Layer.Warnings.Add('Comando antigo %' + C + ' ignorado');
end;

procedure TGerberState.Word(const W: string);
var
  P, St, Code, D, Idx: Integer;
  L: Char;
  HasX, HasY, HasI, HasJ: Boolean;
  NX, NY, NI, NJ, V: Double;
  Num: string;
  Item0: TLPGItem;
  Shp: TLPGShape;
begin
  if W = '' then Exit;
  HasX := False; HasY := False; HasI := False; HasJ := False;
  NX := X; NY := Y; NI := 0; NJ := 0;
  D := -1;
  P := 1;
  while P <= Length(W) do
  begin
    L := UpCase(W[P]);
    Inc(P);
    St := P;
    while (P <= Length(W)) and (W[P] in ['0'..'9', '.', '-', '+']) do Inc(P);
    Num := Copy(W, St, P - St);
    case L of
      'G':
        begin
          Code := StrToIntDef(Num, -1);
          case Code of
            1: Interp := 1;
            2: Interp := 2;
            3: Interp := 3;
            4: Exit; { comentario }
            36:
              begin
                FlushTrace;
                InRegion := True;
                RegionContour := nil;
                RegionItems := nil;
              end;
            37:
              begin
                if Length(RegionContour) > 2 then
                begin
                  Item0.Paths := nil;
                  LPAddPath(Item0.Paths, RegionContour);
                  Item0.Dark := True;
                  AddItem(RegionItems, Item0);
                end;
                RegionContour := nil;
                { cada contorno e uma regiao propria (uniao) }
                for Idx := 0 to High(RegionItems) do
                begin
                  Shp.Items := nil;
                  AddItem(Shp.Items, RegionItems[Idx]);
                  Shp.Dark := Dark;
                  Layer.AddShape(Shp);
                end;
                RegionItems := nil;
                InRegion := False;
              end;
            54, 55: ; { selecao de abertura/flash (antigo) }
            70: Units := IN2MM;
            71: Units := 1;
            74: MultiQuadrant := False;
            75: MultiQuadrant := True;
            90: Incremental := False;
            91: Incremental := True;
          end;
        end;
      'X':
        begin
          V := ParseCoord(Num);
          if Incremental then NX := X + V else NX := V + OffX;
          HasX := True;
        end;
      'Y':
        begin
          V := ParseCoord(Num);
          if Incremental then NY := Y + V else NY := V + OffY;
          HasY := True;
        end;
      'I':
        begin
          NI := ParseCoord(Num);
          HasI := True;
        end;
      'J':
        begin
          NJ := ParseCoord(Num);
          HasJ := True;
        end;
      'D':
        begin
          Code := StrToIntDef(Num, -1);
          if Code >= 10 then
          begin
            FlushTrace;
            CurAp := FindAperture(Code);
            if CurAp < 0 then
              Layer.Warnings.Add('Abertura D' + Num + ' nao definida');
          end
          else
            D := Code;
        end;
      'M':
        begin
          Code := StrToIntDef(Num, -1);
          if (Code = 2) or (Code = 0) or (Code = 1) then
          begin
            FlushTrace;
            CloseStepRepeat;
          end;
        end;
      'N': ; { numero de sequencia }
    end;
  end;
  { coordenada sem D herda o ultimo D (modal, antigo) }
  if D >= 0 then LastD := D
  else if HasX or HasY then D := LastD;
  case D of
    1:
      begin
        if Interp = 1 then
          DoDraw(X, Y, NX, NY)
        else
          DoArc(X, Y, NX, NY, NI, NJ, Interp = 2);
      end;
    2:
      begin
        FlushTrace;
        if InRegion and (Length(RegionContour) > 2) then
        begin
          Item0.Paths := nil;
          LPAddPath(Item0.Paths, RegionContour);
          Item0.Dark := True;
          AddItem(RegionItems, Item0);
        end;
        RegionContour := nil;
      end;
    3: DoFlash(NX, NY);
  end;
  X := NX;
  Y := NY;
end;

{ divide o arquivo em blocos estendidos (%...%) e palavras (...*) }
class function TLPGerberReader.LoadFromString(const Text: string; Layer: TLPGerberLayer;
  Tol: Double): Boolean;
var
  St: TGerberState;
  P, N, Q, I, K: Integer;
  Blk, Cmd, W: string;
  Cmds: TStringList;
  M: TMacro;
begin
  Layer.Clear;
  St := TGerberState.Create(Layer, Tol);
  Cmds := TStringList.Create;
  try
    N := Length(Text);
    P := 1;
    while P <= N do
    begin
      if Text[P] = '%' then
      begin
        Q := PosEx('%', Text, P + 1);
        if Q = 0 then Q := N + 1;
        Blk := Copy(Text, P + 1, Q - P - 1);
        Blk := StringReplace(StringReplace(Blk, #13, '', [rfReplaceAll]), #10, '', [rfReplaceAll]);
        P := Q + 1;
        if Copy(Blk, 1, 2) = 'AM' then
        begin
          { macro: AMnome*corpo*...* }
          Cmds.Clear;
          Cmds.StrictDelimiter := True;
          Cmds.Delimiter := '*';
          Cmds.DelimitedText := Blk;
          M.Name := Copy(Cmds[0], 3, MaxInt);
          M.Body := TStringList.Create;
          for I := 1 to Cmds.Count - 1 do
            if Trim(Cmds[I]) <> '' then M.Body.Add(Trim(Cmds[I]));
          K := St.FindMacro(M.Name);
          if K >= 0 then
          begin
            St.Macros[K].Body.Free;
            St.Macros[K] := M;
          end
          else
          begin
            SetLength(St.Macros, Length(St.Macros) + 1);
            St.Macros[High(St.Macros)] := M;
          end;
        end
        else
        begin
          Cmds.Clear;
          Cmds.StrictDelimiter := True;
          Cmds.Delimiter := '*';
          Cmds.DelimitedText := Blk;
          for I := 0 to Cmds.Count - 1 do
          begin
            Cmd := Trim(Cmds[I]);
            if Cmd <> '' then St.Extended(Cmd);
          end;
        end;
      end
      else if Text[P] in [#13, #10, ' ', #9] then
        Inc(P)
      else
      begin
        Q := PosEx('*', Text, P);
        if Q = 0 then Q := N + 1;
        W := Copy(Text, P, Q - P);
        W := StringReplace(StringReplace(W, #13, '', [rfReplaceAll]), #10, '', [rfReplaceAll]);
        P := Q + 1;
        if Copy(W, 1, 3) = 'G04' then Continue;
        St.Word(W);
      end;
    end;
    St.FlushTrace;
    St.CloseStepRepeat;
  finally
    Cmds.Free;
    St.Free;
  end;
  Result := (Layer.ShapeCount > 0) or (Layer.TraceCount > 0);
end;

class function TLPGerberReader.LoadFromFile(const FileName: string; Layer: TLPGerberLayer;
  Tol: Double): Boolean;
var
  F: TStringList;
begin
  Result := False;
  if not FileExists(FileName) then Exit;
  F := TStringList.Create;
  try
    F.LoadFromFile(FileName);
    Result := LoadFromString(F.Text, Layer, Tol);
    Layer.FileName := FileName;
  finally
    F.Free;
  end;
end;

initialization
  InvFS := DefaultFormatSettings;
  InvFS.DecimalSeparator := '.';
  InvFS.ThousandSeparator := #0;
end.
