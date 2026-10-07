unit laserart_svgimport;

{ Importador SVG do LaserArt.

  - Unidades: mm, cm, in, pt, pc, px (96 dpi). viewBox define a escala das
    coordenadas internas (preserveAspectRatio padrao: meet, centralizado).
  - transform em qualquer elemento: translate, scale, rotate(a [cx cy]),
    skewX, skewY, matrix(a b c d e f), acumulados pelos grupos.
  - Elementos: line, rect (rx/ry), circle, ellipse, polyline, polygon e path
    com todos os comandos (M L H V C S Q T A Z, absolutos e relativos).
    Curvas e arcos sao convertidos em segmentos com passo de ~0,25 mm.
  - Estilo: stroke/fill por atributo ou "style", herdados dos grupos.
    A cor do contorno (ou do preenchimento, se nao houver contorno) escolhe
    a camada de cor mais proxima da paleta, como no LightBurn.
  - Ignorados (com aviso): text, image, use, elementos ocultos e defs.
  - Y do SVG cresce para baixo: convertido para Y para cima (mesa). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Graphics, DOM, XMLRead, laserart_model, laserart_geom;

type
  TLASvgResult = record
    Shapes: Integer;
    Paths: Integer;
    Skipped: Integer;
    SkippedKinds: string;
    WidthMM, HeightMM: Double;
  end;

{ Importa o arquivo e acrescenta ao documento um objeto vetorial por cor.
  DefaultLayer e usada quando a cor nao pode ser determinada. }
function ImportSVGFile(Doc: TLADocument; const FileName: string;
  DefaultLayer: Integer; Added: TList = nil; KeepCoordinates: Boolean = False;
  ToleranceMM: Double = 0.25): TLASvgResult;
function ImportSVGString(Doc: TLADocument; const SVG, BaseName: string;
  DefaultLayer: Integer; Added: TList = nil; KeepCoordinates: Boolean = False;
  ToleranceMM: Double = 0.25): TLASvgResult;
{ cor CSS/SVG -> TColor; False para "none" ou valor desconhecido }
function ParseSvgColor(const S: string; out C: TColor): Boolean;
function NearestLayer(C: TColor): Integer;

implementation

type
  TMat = record
    A, B, C, D, E, F: Double;
  end;

  TStyle = record
    Stroke, Fill: string;
    Hidden: Boolean;
  end;

  TLayerBucket = record
    Paths: TLAPaths;
  end;

  TImporter = class
  private
    FBuckets: array[0..LA_LAYER_COUNT - 1] of TLayerBucket;
    FPageH: Double;
    FDefaultLayer: Integer;
    FKeepCoordinates: Boolean;
    FSkipped: Integer;
    FSkippedKinds: TStringList;
    FPathCount: Integer;
    { construcao do caminho corrente }
    FCur: TLAPath;
    FCurN: Integer;
    FM: TMat;
    FTol: Double;
    procedure Skip(const Kind: string);
    procedure BeginPath;
    procedure AddPt(X, Y: Double);
    procedure EndPath(Closed: Boolean; Layer: Integer);
    function MMScale: Double;
    procedure ShapeRect(E: TDOMElement; Layer: Integer);
    procedure ShapeEllipse(CX, CY, RX, RY: Double; Layer: Integer);
    procedure ShapePoly(const Pts: string; Closed: Boolean; Layer: Integer);
    procedure ShapePath(const D: string; Layer: Integer);
    procedure Walk(Node: TDOMNode; const M: TMat; const St: TStyle);
  public
    constructor Create;
    destructor Destroy; override;
    function Run(XML: TXMLDocument; Doc: TLADocument; const BaseName: string;
      Added: TList): TLASvgResult;
  end;

function Identity: TMat;
begin
  Result.A := 1; Result.B := 0; Result.C := 0; Result.D := 1; Result.E := 0; Result.F := 0;
end;

function MatMul(const P, Q: TMat): TMat;
begin
  Result.A := P.A * Q.A + P.C * Q.B;
  Result.B := P.B * Q.A + P.D * Q.B;
  Result.C := P.A * Q.C + P.C * Q.D;
  Result.D := P.B * Q.C + P.D * Q.D;
  Result.E := P.A * Q.E + P.C * Q.F + P.E;
  Result.F := P.B * Q.E + P.D * Q.F + P.F;
end;

function MatOf(A, B, C, D, E, F: Double): TMat;
begin
  Result.A := A; Result.B := B; Result.C := C; Result.D := D; Result.E := E; Result.F := F;
end;

{ ---------------------------------------------------------------------------- }
{ Leitura de numeros                                                           }

var
  FSDot: TFormatSettings;

type
  TNumReader = record
    S: string;
    P: Integer;
  end;

procedure NR_Init(var R: TNumReader; const S: string);
begin
  R.S := S;
  R.P := 1;
end;

procedure NR_SkipSep(var R: TNumReader);
begin
  while (R.P <= Length(R.S)) and (R.S[R.P] in [' ', #9, #10, #13, ',']) do
    Inc(R.P);
end;

function NR_HasNumber(var R: TNumReader): Boolean;
begin
  NR_SkipSep(R);
  Result := (R.P <= Length(R.S)) and (R.S[R.P] in ['0'..'9', '.', '-', '+']);
end;

function NR_Number(var R: TNumReader; out V: Double): Boolean;
var
  Start: Integer;
  Dot, Digits: Boolean;
begin
  V := 0;
  NR_SkipSep(R);
  Start := R.P;
  if (R.P <= Length(R.S)) and (R.S[R.P] in ['-', '+']) then Inc(R.P);
  Dot := False; Digits := False;
  while R.P <= Length(R.S) do
  begin
    if R.S[R.P] in ['0'..'9'] then
      Digits := True
    else if (R.S[R.P] = '.') and not Dot then
      Dot := True
    else
      Break;
    Inc(R.P);
  end;
  if Digits and (R.P <= Length(R.S)) and (R.S[R.P] in ['e', 'E']) and
     (R.P + 1 <= Length(R.S)) and (R.S[R.P + 1] in ['0'..'9', '-', '+']) then
  begin
    Inc(R.P);
    if R.S[R.P] in ['-', '+'] then Inc(R.P);
    while (R.P <= Length(R.S)) and (R.S[R.P] in ['0'..'9']) do Inc(R.P);
  end;
  Result := Digits and TryStrToFloat(Copy(R.S, Start, R.P - Start), V, FSDot);
  if not Result then
    R.P := Max(R.P, Start + 1);
end;

{ flag de arco: um unico caractere 0/1, mesmo sem separador }
function NR_Flag(var R: TNumReader; out V: Boolean): Boolean;
begin
  NR_SkipSep(R);
  Result := (R.P <= Length(R.S)) and (R.S[R.P] in ['0', '1']);
  if Result then
  begin
    V := R.S[R.P] = '1';
    Inc(R.P);
  end;
end;

function ParseFloatDefault(const S: string; Def: Double): Double;
var
  R: TNumReader;
begin
  NR_Init(R, S);
  if not NR_Number(R, Result) then
    Result := Def;
end;

{ comprimento com unidade -> mm; % e desconhecidos -> px }
function LengthToMM(const S: string; out MM: Double): Boolean;
var
  R: TNumReader;
  V: Double;
  U: string;
begin
  NR_Init(R, Trim(S));
  Result := NR_Number(R, V);
  if not Result then Exit;
  U := LowerCase(Trim(Copy(R.S, R.P, MaxInt)));
  if U = 'mm' then MM := V
  else if U = 'cm' then MM := V * 10
  else if U = 'in' then MM := V * 25.4
  else if U = 'pt' then MM := V * 25.4 / 72
  else if U = 'pc' then MM := V * 25.4 / 6
  else if U = '%' then Result := False
  else MM := V * 25.4 / 96;
end;

{ ---------------------------------------------------------------------------- }
{ Cores                                                                        }

function ParseSvgColor(const S: string; out C: TColor): Boolean;
const
  Names: array[0..21] of string = ('black', 'white', 'red', 'green', 'blue',
    'yellow', 'cyan', 'aqua', 'magenta', 'fuchsia', 'gray', 'grey', 'silver',
    'maroon', 'olive', 'lime', 'teal', 'navy', 'purple', 'orange', 'brown', 'pink');
  Vals: array[0..21] of LongInt = ($000000, $FFFFFF, $FF0000, $008000, $0000FF,
    $FFFF00, $00FFFF, $00FFFF, $FF00FF, $FF00FF, $808080, $808080, $C0C0C0,
    $800000, $808000, $00FF00, $008080, $000080, $800080, $FFA500, $A52A2A, $FFC0CB);
var
  T, H: string;
  I, V: Integer;
  R: TNumReader;
  CR, CG, CB: Double;
begin
  Result := False;
  C := clBlack;
  T := LowerCase(Trim(S));
  if (T = '') or (T = 'none') or (T = 'transparent') then Exit;
  if T = 'currentcolor' then Exit(True);
  if Copy(T, 1, 4) = 'url(' then Exit(True); { gradiente: trata como preto }
  if T[1] = '#' then
  begin
    H := Copy(T, 2, MaxInt);
    if Length(H) = 3 then
      H := H[1] + H[1] + H[2] + H[2] + H[3] + H[3];
    if (Length(H) >= 6) and TryStrToInt('$' + Copy(H, 1, 6), V) then
    begin
      C := RGBToColor((V shr 16) and $FF, (V shr 8) and $FF, V and $FF);
      Exit(True);
    end;
    Exit;
  end;
  if Copy(T, 1, 4) = 'rgb(' then
  begin
    NR_Init(R, Copy(T, 5, Length(T) - 5));
    if NR_Number(R, CR) and NR_Number(R, CG) and NR_Number(R, CB) then
    begin
      if Pos('%', T) > 0 then
      begin
        CR := CR * 2.55; CG := CG * 2.55; CB := CB * 2.55;
      end;
      C := RGBToColor(EnsureRange(Round(CR), 0, 255), EnsureRange(Round(CG), 0, 255),
        EnsureRange(Round(CB), 0, 255));
      Exit(True);
    end;
    Exit;
  end;
  for I := 0 to High(Names) do
    if Names[I] = T then
    begin
      V := Vals[I];
      C := RGBToColor((V shr 16) and $FF, (V shr 8) and $FF, V and $FF);
      Exit(True);
    end;
end;

function NearestLayer(C: TColor): Integer;
var
  I: Integer;
  D, Best: Double;
  A, B: TColor;
begin
  A := ColorToRGB(C);
  Result := 0;
  Best := MaxDouble;
  for I := 0 to LA_LAYER_COUNT - 1 do
  begin
    B := ColorToRGB(LayerColor(I));
    D := 2 * Sqr(Red(A) - Red(B)) + 4 * Sqr(Green(A) - Green(B)) + 3 * Sqr(Blue(A) - Blue(B));
    if D < Best then
    begin
      Best := D;
      Result := I;
    end;
  end;
end;

{ ---------------------------------------------------------------------------- }
{ Atributos e estilo                                                           }

function LocalName(const N: string): string;
var
  P: Integer;
begin
  P := Pos(':', N);
  if P > 0 then
    Result := LowerCase(Copy(N, P + 1, MaxInt))
  else
    Result := LowerCase(N);
end;

function StyleValue(E: TDOMElement; const Key: string): string;
var
  St, Item, K: string;
  P, Q: Integer;
begin
  Result := '';
  St := E.GetAttribute('style');
  while St <> '' do
  begin
    P := Pos(';', St);
    if P = 0 then P := Length(St) + 1;
    Item := Copy(St, 1, P - 1);
    Delete(St, 1, P);
    Q := Pos(':', Item);
    if Q = 0 then Continue;
    K := LowerCase(Trim(Copy(Item, 1, Q - 1)));
    if K = Key then
      Exit(Trim(Copy(Item, Q + 1, MaxInt)));
  end;
  if E.HasAttribute(Key) then
    Result := Trim(E.GetAttribute(Key));
end;

function NumAttr(E: TDOMElement; const N: string; Def: Double = 0): Double;
begin
  if E.HasAttribute(N) then
    Result := ParseFloatDefault(E.GetAttribute(N), Def)
  else
    Result := Def;
end;

function ParseTransform(const S: string): TMat;
var
  P, Q: Integer;
  Name, Args: string;
  V: array[0..5] of Double;
  N: Integer;
  R: TNumReader;
  T: TMat;
  A: Double;
begin
  Result := Identity;
  P := 1;
  while P <= Length(S) do
  begin
    while (P <= Length(S)) and not (S[P] in ['a'..'z', 'A'..'Z']) do Inc(P);
    Q := P;
    while (Q <= Length(S)) and (S[Q] in ['a'..'z', 'A'..'Z']) do Inc(Q);
    Name := LowerCase(Copy(S, P, Q - P));
    P := Q;
    while (P <= Length(S)) and (S[P] <> '(') do Inc(P);
    Q := P + 1;
    while (Q <= Length(S)) and (S[Q] <> ')') do Inc(Q);
    if P > Length(S) then Break;
    Args := Copy(S, P + 1, Q - P - 1);
    P := Q + 1;
    NR_Init(R, Args);
    N := 0;
    while (N < 6) and NR_HasNumber(R) and NR_Number(R, V[N]) do Inc(N);
    T := Identity;
    if (Name = 'matrix') and (N = 6) then
      T := MatOf(V[0], V[1], V[2], V[3], V[4], V[5])
    else if (Name = 'translate') and (N >= 1) then
    begin
      if N = 1 then V[1] := 0;
      T := MatOf(1, 0, 0, 1, V[0], V[1]);
    end
    else if (Name = 'scale') and (N >= 1) then
    begin
      if N = 1 then V[1] := V[0];
      T := MatOf(V[0], 0, 0, V[1], 0, 0);
    end
    else if (Name = 'rotate') and (N >= 1) then
    begin
      A := DegToRad(V[0]);
      T := MatOf(Cos(A), Sin(A), -Sin(A), Cos(A), 0, 0);
      if N >= 3 then
        T := MatMul(MatMul(MatOf(1, 0, 0, 1, V[1], V[2]), T), MatOf(1, 0, 0, 1, -V[1], -V[2]));
    end
    else if (Name = 'skewx') and (N >= 1) then
      T := MatOf(1, 0, Tan(DegToRad(V[0])), 1, 0, 0)
    else if (Name = 'skewy') and (N >= 1) then
      T := MatOf(1, Tan(DegToRad(V[0])), 0, 1, 0, 0);
    Result := MatMul(Result, T);
  end;
end;

{ ---------------------------------------------------------------------------- }
{ TImporter                                                                    }

constructor TImporter.Create;
begin
  inherited Create;
  FSkippedKinds := TStringList.Create;
  FSkippedKinds.Sorted := True;
  FSkippedKinds.Duplicates := dupIgnore;
end;

destructor TImporter.Destroy;
begin
  FSkippedKinds.Free;
  inherited Destroy;
end;

procedure TImporter.Skip(const Kind: string);
begin
  Inc(FSkipped);
  FSkippedKinds.Add(Kind);
end;

function TImporter.MMScale: Double;
begin
  Result := Sqrt(Abs(FM.A * FM.D - FM.B * FM.C));
  if Result < 1e-9 then Result := 1;
end;

procedure TImporter.BeginPath;
begin
  FCurN := 0;
  SetLength(FCur.Pts, 32);
end;

procedure TImporter.AddPt(X, Y: Double);
var
  TX, TY: Double;
begin
  TX := FM.A * X + FM.C * Y + FM.E;
  TY := FM.B * X + FM.D * Y + FM.F;
  TY := FPageH - TY;
  if (FCurN > 0) and (Abs(FCur.Pts[FCurN - 1].X - TX) < 1e-6) and
     (Abs(FCur.Pts[FCurN - 1].Y - TY) < 1e-6) then
    Exit;
  if FCurN >= Length(FCur.Pts) then
    SetLength(FCur.Pts, FCurN * 2);
  FCur.Pts[FCurN] := LAPoint(TX, TY);
  Inc(FCurN);
end;

procedure TImporter.EndPath(Closed: Boolean; Layer: Integer);
var
  N: Integer;
begin
  if FCurN >= 2 then
  begin
    { ponto final igual ao inicial: fecha sem repetir }
    if (FCurN > 2) and (Hypot(FCur.Pts[0].X - FCur.Pts[FCurN - 1].X,
        FCur.Pts[0].Y - FCur.Pts[FCurN - 1].Y) < 1e-4) then
    begin
      Dec(FCurN);
      Closed := True;
    end;
    SetLength(FCur.Pts, FCurN);
    FCur.Closed := Closed and (FCurN >= 3);
    FCur := SimplifyPath(FCur, Min(0.02, FTol));
    N := Length(FBuckets[Layer].Paths);
    SetLength(FBuckets[Layer].Paths, N + 1);
    FBuckets[Layer].Paths[N] := FCur;
    Inc(FPathCount);
  end;
  FCur.Pts := nil;
  BeginPath;
end;

procedure TImporter.ShapeEllipse(CX, CY, RX, RY: Double; Layer: Integer);
var
  I, N: Integer;
  A: Double;
begin
  if (RX <= 0) or (RY <= 0) then Exit;
  N := EnsureRange(Round(2 * Pi * Max(RX, RY) * MMScale / FTol / 2), 24, 360);
  BeginPath;
  for I := 0 to N - 1 do
  begin
    A := 2 * Pi * I / N;
    AddPt(CX + RX * Cos(A), CY + RY * Sin(A));
  end;
  EndPath(True, Layer);
end;

procedure TImporter.ShapeRect(E: TDOMElement; Layer: Integer);
var
  X, Y, W, H, RX, RY, A: Double;
  I, J, N: Integer;
  CX, CY: Double;
begin
  X := NumAttr(E, 'x'); Y := NumAttr(E, 'y');
  W := NumAttr(E, 'width'); H := NumAttr(E, 'height');
  if (W <= 0) or (H <= 0) then Exit;
  RX := NumAttr(E, 'rx', -1); RY := NumAttr(E, 'ry', -1);
  if (RX < 0) and (RY >= 0) then RX := RY;
  if (RY < 0) and (RX >= 0) then RY := RX;
  RX := Min(Max(RX, 0), W / 2); RY := Min(Max(RY, 0), H / 2);
  BeginPath;
  if (RX <= 0) or (RY <= 0) then
  begin
    AddPt(X, Y); AddPt(X + W, Y); AddPt(X + W, Y + H); AddPt(X, Y + H);
  end
  else
  begin
    N := 8;
    for I := 0 to 3 do
    begin
      case I of
        0: begin CX := X + W - RX; CY := Y + RY; end;
        1: begin CX := X + W - RX; CY := Y + H - RY; end;
        2: begin CX := X + RX; CY := Y + H - RY; end;
      else
        begin CX := X + RX; CY := Y + RY; end;
      end;
      for J := 0 to N do
      begin
        A := DegToRad(-90 + I * 90 + 90 * J / N);
        AddPt(CX + RX * Cos(A), CY + RY * Sin(A));
      end;
    end;
  end;
  EndPath(True, Layer);
end;

procedure TImporter.ShapePoly(const Pts: string; Closed: Boolean; Layer: Integer);
var
  R: TNumReader;
  X, Y: Double;
begin
  NR_Init(R, Pts);
  BeginPath;
  while NR_HasNumber(R) and NR_Number(R, X) and NR_Number(R, Y) do
    AddPt(X, Y);
  EndPath(Closed, Layer);
end;

procedure TImporter.ShapePath(const D: string; Layer: Integer);
var
  R: TNumReader;
  Cmd, LastCmd: Char;
  CX, CY, SX, SY, X1, Y1, X2, Y2, X, Y, QX, QY, LCX, LCY: Double;
  RX, RY, Rot: Double;
  Large, Sweep, Rel, Open: Boolean;

  function Segs(L: Double): Integer;
  begin
    Result := EnsureRange(Ceil(L * MMScale / FTol), 2, 200);
  end;

  procedure Cubic(AX1, AY1, AX2, AY2, AX, AY: Double);
  var
    I, N: Integer;
    T, U: Double;
  begin
    N := Segs(Hypot(AX1 - CX, AY1 - CY) + Hypot(AX2 - AX1, AY2 - AY1) + Hypot(AX - AX2, AY - AY2));
    for I := 1 to N do
    begin
      T := I / N; U := 1 - T;
      AddPt(U * U * U * CX + 3 * U * U * T * AX1 + 3 * U * T * T * AX2 + T * T * T * AX,
            U * U * U * CY + 3 * U * U * T * AY1 + 3 * U * T * T * AY2 + T * T * T * AY);
    end;
  end;

  procedure Quad(AX1, AY1, AX, AY: Double);
  var
    I, N: Integer;
    T, U: Double;
  begin
    N := Segs(Hypot(AX1 - CX, AY1 - CY) + Hypot(AX - AX1, AY - AY1));
    for I := 1 to N do
    begin
      T := I / N; U := 1 - T;
      AddPt(U * U * CX + 2 * U * T * AX1 + T * T * AX, U * U * CY + 2 * U * T * AY1 + T * T * AY);
    end;
  end;

  { SVG 1.1, apendice F.6.5: extremidades -> centro }
  procedure Arc(ARX, ARY, APhi: Double; ALarge, ASweep: Boolean; AX, AY: Double);
  var
    Phi, CP, SP, DX, DY, X1P, Y1P, L, Sq, Coef, CXP, CYP, CCX, CCY: Double;
    T1, DT, UX, UY, VX, VY, T: Double;
    I, N: Integer;

    function Ang(AUX, AUY, AVX, AVY: Double): Double;
    begin
      Result := ArcTan2(AUX * AVY - AUY * AVX, AUX * AVX + AUY * AVY);
    end;

  begin
    ARX := Abs(ARX); ARY := Abs(ARY);
    if (ARX < 1e-9) or (ARY < 1e-9) then
    begin
      AddPt(AX, AY);
      Exit;
    end;
    Phi := DegToRad(APhi);
    CP := Cos(Phi); SP := Sin(Phi);
    DX := (CX - AX) / 2; DY := (CY - AY) / 2;
    X1P := CP * DX + SP * DY;
    Y1P := -SP * DX + CP * DY;
    L := Sqr(X1P) / Sqr(ARX) + Sqr(Y1P) / Sqr(ARY);
    if L > 1 then
    begin
      ARX := ARX * Sqrt(L); ARY := ARY * Sqrt(L);
    end;
    Sq := (Sqr(ARX) * Sqr(ARY) - Sqr(ARX) * Sqr(Y1P) - Sqr(ARY) * Sqr(X1P)) /
          (Sqr(ARX) * Sqr(Y1P) + Sqr(ARY) * Sqr(X1P));
    Coef := Sqrt(Max(0, Sq));
    if ALarge = ASweep then Coef := -Coef;
    CXP := Coef * ARX * Y1P / ARY;
    CYP := -Coef * ARY * X1P / ARX;
    CCX := CP * CXP - SP * CYP + (CX + AX) / 2;
    CCY := SP * CXP + CP * CYP + (CY + AY) / 2;
    UX := (X1P - CXP) / ARX; UY := (Y1P - CYP) / ARY;
    VX := (-X1P - CXP) / ARX; VY := (-Y1P - CYP) / ARY;
    T1 := Ang(1, 0, UX, UY);
    DT := Ang(UX, UY, VX, VY);
    if (not ASweep) and (DT > 0) then DT := DT - 2 * Pi
    else if ASweep and (DT < 0) then DT := DT + 2 * Pi;
    N := Segs(Abs(DT) * Max(ARX, ARY));
    for I := 1 to N do
    begin
      T := T1 + DT * I / N;
      AddPt(CCX + ARX * Cos(T) * CP - ARY * Sin(T) * SP,
            CCY + ARX * Cos(T) * SP + ARY * Sin(T) * CP);
    end;
  end;

begin
  NR_Init(R, D);
  CX := 0; CY := 0; SX := 0; SY := 0;
  LCX := 0; LCY := 0; QX := 0; QY := 0;
  Cmd := ' '; LastCmd := ' ';
  Open := False;
  BeginPath;
  while True do
  begin
    NR_SkipSep(R);
    if R.P > Length(R.S) then Break;
    if R.S[R.P] in ['A'..'Z', 'a'..'z'] then
    begin
      Cmd := R.S[R.P];
      Inc(R.P);
    end
    else if Cmd = ' ' then
      Break
    else if Cmd in ['M'] then
      Cmd := 'L'                 { pares depois de M sao L }
    else if Cmd = 'm' then
      Cmd := 'l';
    Rel := Cmd in ['a'..'z'];
    case UpCase(Cmd) of
      'M':
        begin
          if not (NR_Number(R, X) and NR_Number(R, Y)) then Break;
          if Rel then begin X := X + CX; Y := Y + CY; end;
          if Open then EndPath(False, Layer);
          CX := X; CY := Y; SX := X; SY := Y;
          AddPt(X, Y);
          Open := True;
        end;
      'L':
        begin
          if not (NR_Number(R, X) and NR_Number(R, Y)) then Break;
          if Rel then begin X := X + CX; Y := Y + CY; end;
          AddPt(X, Y);
          CX := X; CY := Y;
        end;
      'H':
        begin
          if not NR_Number(R, X) then Break;
          if Rel then X := X + CX;
          AddPt(X, CY);
          CX := X;
        end;
      'V':
        begin
          if not NR_Number(R, Y) then Break;
          if Rel then Y := Y + CY;
          AddPt(CX, Y);
          CY := Y;
        end;
      'C':
        begin
          if not (NR_Number(R, X1) and NR_Number(R, Y1) and NR_Number(R, X2) and
                  NR_Number(R, Y2) and NR_Number(R, X) and NR_Number(R, Y)) then Break;
          if Rel then
          begin
            X1 := X1 + CX; Y1 := Y1 + CY; X2 := X2 + CX; Y2 := Y2 + CY;
            X := X + CX; Y := Y + CY;
          end;
          Cubic(X1, Y1, X2, Y2, X, Y);
          LCX := X2; LCY := Y2;
          CX := X; CY := Y;
        end;
      'S':
        begin
          if not (NR_Number(R, X2) and NR_Number(R, Y2) and NR_Number(R, X) and
                  NR_Number(R, Y)) then Break;
          if Rel then begin X2 := X2 + CX; Y2 := Y2 + CY; X := X + CX; Y := Y + CY; end;
          if UpCase(LastCmd) in ['C', 'S'] then
          begin
            X1 := 2 * CX - LCX; Y1 := 2 * CY - LCY;
          end
          else
          begin
            X1 := CX; Y1 := CY;
          end;
          Cubic(X1, Y1, X2, Y2, X, Y);
          LCX := X2; LCY := Y2;
          CX := X; CY := Y;
        end;
      'Q':
        begin
          if not (NR_Number(R, X1) and NR_Number(R, Y1) and NR_Number(R, X) and
                  NR_Number(R, Y)) then Break;
          if Rel then begin X1 := X1 + CX; Y1 := Y1 + CY; X := X + CX; Y := Y + CY; end;
          Quad(X1, Y1, X, Y);
          QX := X1; QY := Y1;
          CX := X; CY := Y;
        end;
      'T':
        begin
          if not (NR_Number(R, X) and NR_Number(R, Y)) then Break;
          if Rel then begin X := X + CX; Y := Y + CY; end;
          if UpCase(LastCmd) in ['Q', 'T'] then
          begin
            X1 := 2 * CX - QX; Y1 := 2 * CY - QY;
          end
          else
          begin
            X1 := CX; Y1 := CY;
          end;
          Quad(X1, Y1, X, Y);
          QX := X1; QY := Y1;
          CX := X; CY := Y;
        end;
      'A':
        begin
          if not (NR_Number(R, RX) and NR_Number(R, RY) and NR_Number(R, Rot) and
                  NR_Flag(R, Large) and NR_Flag(R, Sweep) and NR_Number(R, X) and
                  NR_Number(R, Y)) then Break;
          if Rel then begin X := X + CX; Y := Y + CY; end;
          Arc(RX, RY, Rot, Large, Sweep, X, Y);
          CX := X; CY := Y;
        end;
      'Z':
        begin
          if Open then EndPath(True, Layer);
          CX := SX; CY := SY;
          { inicio implicito do proximo subcaminho (descartado se vier um M) }
          AddPt(CX, CY);
          Open := True;
        end;
    else
      Break;
    end;
    LastCmd := Cmd;
  end;
  if Open then EndPath(False, Layer);
end;

procedure TImporter.Walk(Node: TDOMNode; const M: TMat; const St: TStyle);
var
  Child: TDOMNode;
  E: TDOMElement;
  Name, V: string;
  M2: TMat;
  St2: TStyle;
  Col: TColor;
  Layer: Integer;
begin
  Child := Node.FirstChild;
  while Child <> nil do
  begin
    if Child.NodeType = ELEMENT_NODE then
    begin
      E := TDOMElement(Child);
      Name := LocalName(E.TagName);
      St2 := St;
      V := StyleValue(E, 'stroke'); if V <> '' then St2.Stroke := V;
      V := StyleValue(E, 'fill'); if V <> '' then St2.Fill := V;
      if (LowerCase(StyleValue(E, 'display')) = 'none') or
         (LowerCase(StyleValue(E, 'visibility')) = 'hidden') then
        St2.Hidden := True;
      M2 := M;
      if E.HasAttribute('transform') then
        M2 := MatMul(M, ParseTransform(E.GetAttribute('transform')));

      if St2.Hidden then
        Skip('oculto')
      else if (Name = 'g') or (Name = 'a') or (Name = 'switch') then
        Walk(E, M2, St2)
      else if Name = 'svg' then
      begin
        { svg aninhado: x/y deslocam }
        M2 := MatMul(M2, MatOf(1, 0, 0, 1, NumAttr(E, 'x'), NumAttr(E, 'y')));
        Walk(E, M2, St2);
      end
      else if (Name = 'line') or (Name = 'rect') or (Name = 'circle') or
              (Name = 'ellipse') or (Name = 'polyline') or (Name = 'polygon') or
              (Name = 'path') then
      begin
        if ParseSvgColor(St2.Stroke, Col) then
          Layer := NearestLayer(Col)
        else if ParseSvgColor(St2.Fill, Col) then
          Layer := NearestLayer(Col)
        else
          Layer := FDefaultLayer;
        FM := M2;
        if Name = 'line' then
        begin
          BeginPath;
          AddPt(NumAttr(E, 'x1'), NumAttr(E, 'y1'));
          AddPt(NumAttr(E, 'x2'), NumAttr(E, 'y2'));
          EndPath(False, Layer);
        end
        else if Name = 'rect' then
          ShapeRect(E, Layer)
        else if Name = 'circle' then
          ShapeEllipse(NumAttr(E, 'cx'), NumAttr(E, 'cy'), NumAttr(E, 'r'), NumAttr(E, 'r'), Layer)
        else if Name = 'ellipse' then
          ShapeEllipse(NumAttr(E, 'cx'), NumAttr(E, 'cy'), NumAttr(E, 'rx'), NumAttr(E, 'ry'), Layer)
        else if Name = 'polyline' then
          ShapePoly(E.GetAttribute('points'), False, Layer)
        else if Name = 'polygon' then
          ShapePoly(E.GetAttribute('points'), True, Layer)
        else
          ShapePath(E.GetAttribute('d'), Layer);
      end
      else if (Name = 'text') or (Name = 'image') or (Name = 'use') or (Name = 'foreignobject') then
        Skip(Name)
      { defs, symbol, clipPath, mask, marker, pattern, style, title, desc, metadata:
        nao desenham diretamente }
      ;
    end;
    Child := Child.NextSibling;
  end;
end;

function TImporter.Run(XML: TXMLDocument; Doc: TLADocument; const BaseName: string;
  Added: TList): TLASvgResult;
var
  Root: TDOMElement;
  WMM, HMM, VX, VY, VW, VH, S, SX, SY: Double;
  HasW, HasH, HasVB: Boolean;
  R: TNumReader;
  M: TMat;
  St: TStyle;
  I, J, K: Integer;
  Sh: TLAShape;
  W, H: Double;
  B, All: TLABox;
  DX, DY: Double;
  Aspect: string;
  Created: TList;
begin
  FillChar(Result, SizeOf(Result), 0);
  Root := XML.DocumentElement;
  if (Root = nil) or (LocalName(Root.TagName) <> 'svg') then
    raise Exception.Create('Arquivo nao e SVG');

  HasW := Root.HasAttribute('width') and LengthToMM(Root.GetAttribute('width'), WMM);
  HasH := Root.HasAttribute('height') and LengthToMM(Root.GetAttribute('height'), HMM);
  HasVB := False;
  if Root.HasAttribute('viewBox') then
  begin
    NR_Init(R, Root.GetAttribute('viewBox'));
    HasVB := NR_Number(R, VX) and NR_Number(R, VY) and NR_Number(R, VW) and
      NR_Number(R, VH) and (VW > 0) and (VH > 0);
  end;

  if HasVB then
  begin
    if not HasW then WMM := VW * 25.4 / 96;
    if not HasH then HMM := VH * 25.4 / 96;
    SX := WMM / VW;
    SY := HMM / VH;
    Aspect := LowerCase(Trim(Root.GetAttribute('preserveAspectRatio')));
    if Aspect = '' then Aspect := 'xmidymid meet';
    if Aspect = 'none' then
      M := MatOf(SX, 0, 0, SY, -VX * SX, -VY * SY)
    else
    begin
      if Pos('slice', Aspect) > 0 then S := Max(SX, SY) else S := Min(SX, SY);
      DX := (WMM - VW * S) / 2; DY := (HMM - VH * S) / 2;
      if Pos('xmin', Aspect) > 0 then DX := 0;
      if Pos('xmax', Aspect) > 0 then DX := WMM - VW * S;
      if Pos('ymin', Aspect) > 0 then DY := 0;
      if Pos('ymax', Aspect) > 0 then DY := HMM - VH * S;
      M := MatOf(S, 0, 0, S, -VX * S + DX, -VY * S + DY);
    end;
  end
  else
  begin
    S := 25.4 / 96;
    if not HasW then WMM := 0;
    if not HasH then HMM := 0;
    M := MatOf(S, 0, 0, S, 0, 0);
  end;
  Result.WidthMM := WMM;
  Result.HeightMM := HMM;
  FPageH := HMM;

  St.Stroke := '';
  St.Fill := 'black';
  St.Hidden := False;
  if StyleValue(Root, 'stroke') <> '' then St.Stroke := StyleValue(Root, 'stroke');
  if StyleValue(Root, 'fill') <> '' then St.Fill := StyleValue(Root, 'fill');
  if Root.HasAttribute('transform') then
    M := MatMul(M, ParseTransform(Root.GetAttribute('transform')));
  Walk(Root, M, St);

  { um objeto vetorial por camada (cor) }
  Created := TList.Create;
  try
    All := EmptyBox;
    for I := 0 to LA_LAYER_COUNT - 1 do
    begin
      if Length(FBuckets[I].Paths) = 0 then Continue;
      Sh := TLAShape.Create(skPath);
      Sh.Layer := I;
      Sh.Name := BaseName + Format(' (C%.2d)', [I]);
      Sh.Local := FBuckets[I].Paths;
      B := PathsBox(Sh.Local);
      NormalizePaths(Sh.Local, W, H);
      Sh.LocalW := Max(W, 0.01);
      Sh.LocalH := Max(H, 0.01);
      Sh.W := Sh.LocalW;
      Sh.H := Sh.LocalH;
      Sh.X := B.X1;
      Sh.Y := B.Y1;
      All := UnionBox(All, B);
      Created.Add(Sh);
    end;
    { se a pagina nao cabe na mesa, traz o desenho para o canto (10, 10) }
    if not FKeepCoordinates and All.Valid and ((All.X1 < 0) or (All.Y1 < 0) or (All.X2 > Doc.BedW) or (All.Y2 > Doc.BedH)) then
    begin
      DX := 10 - All.X1;
      DY := 10 - All.Y1;
      for K := 0 to Created.Count - 1 do
      begin
        Sh := TLAShape(Created[K]);
        Sh.X := Sh.X + DX;
        Sh.Y := Sh.Y + DY;
      end;
    end;
    for K := 0 to Created.Count - 1 do
    begin
      Doc.Add(TLAShape(Created[K]));
      if Added <> nil then Added.Add(Created[K]);
    end;
    Result.Shapes := Created.Count;
  finally
    Created.Free;
  end;
  Result.Paths := FPathCount;
  Result.Skipped := FSkipped;
  for J := 0 to FSkippedKinds.Count - 1 do
  begin
    if Result.SkippedKinds <> '' then Result.SkippedKinds := Result.SkippedKinds + ', ';
    Result.SkippedKinds := Result.SkippedKinds + FSkippedKinds[J];
  end;
end;

function ImportSVGString(Doc: TLADocument; const SVG, BaseName: string;
  DefaultLayer: Integer; Added: TList; KeepCoordinates: Boolean;
  ToleranceMM: Double): TLASvgResult;
var
  XML: TXMLDocument;
  St: TStringStream;
  Imp: TImporter;
begin
  St := TStringStream.Create(SVG);
  Imp := TImporter.Create;
  XML := nil;
  try
    ReadXMLFile(XML, St);
    Imp.FDefaultLayer := EnsureRange(DefaultLayer, 0, LA_LAYER_COUNT - 1);
    if IsNan(ToleranceMM) or IsInfinite(ToleranceMM) or (ToleranceMM <= 0) then
      raise Exception.Create('Tolerancia SVG deve ser positiva e finita');
    Imp.FKeepCoordinates := KeepCoordinates;
    Imp.FTol := ToleranceMM;
    Result := Imp.Run(XML, Doc, BaseName, Added);
  finally
    XML.Free;
    Imp.Free;
    St.Free;
  end;
end;

function ImportSVGFile(Doc: TLADocument; const FileName: string;
  DefaultLayer: Integer; Added: TList; KeepCoordinates: Boolean;
  ToleranceMM: Double): TLASvgResult;
var
  SL: TStringList;
begin
  SL := TStringList.Create;
  try
    SL.LoadFromFile(FileName);
    Result := ImportSVGString(Doc, SL.Text, ChangeFileExt(ExtractFileName(FileName), ''),
      DefaultLayer, Added, KeepCoordinates, ToleranceMM);
  finally
    SL.Free;
  end;
end;

initialization
  FSDot := DefaultFormatSettings;
  FSDot.DecimalSeparator := '.';
  FSDot.ThousandSeparator := #0;

end.
