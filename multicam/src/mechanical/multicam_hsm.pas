unit multicam_hsm;

{$mode objfpc}{$H+}

{ Estrategias de usinagem de alta velocidade (HSM) para CNC Router.

  - TrochoidalSlot: fresamento trocoidal de rasgos. A ferramenta descreve
    lacos circulares avancando um pequeno passo por volta, mantendo o
    engajamento radial baixo e constante. Permite usar toda a altura de corte
    da fresa com avanco alto, reduzindo calor, vibracao e quebra de fresa.
  - OffsetPocket: pocket por offsets paralelos ao contorno, de dentro para
    fora e sem retracao entre aneis, com entrada helicoidal (ou rampa quando a
    helice nao cabe). Sentido de corte constante (concordante por padrao).
  - CompensatedProfile: perfil de contorno qualquer com compensacao de raio
    (offset arredondado nos cantos), sobremetal, entrada em rampa ao longo do
    contorno (sem mergulho vertical), passe de acabamento e tabs.

  Convencao de sentido com spindle M3 (horario): corte concordante (climb)
  e anti-horario em paredes internas e horario em contornos externos.

  As rotinas geram movimentos em TCamJob; o pos-processador (multicam_gcode)
  converte para G-code, opcionalmente com G2/G3 por arc fitting. }

interface

uses SysUtils, Math, multicam_types, multicam_job, multicam_geometry,
  multisuite_geometry;

type
  TCutSide = (csOutside, csInside, csOnLine);

  TTabSettings = record
    Count: Integer;      // 0 = sem tabs
    Width: Double;       // mm ao longo do contorno (sem contar o raio da fresa)
    Height: Double;      // mm acima da profundidade final
  end;

  THSMCAM = class
  public
    class function ContourToPolygon(C: TCamContour): TPolygon2D;
    class function PolygonCentroid(const P: TPolygon2D): TPoint2D;
    class function DepthLevels(FinalDepth, StepDown: Double): TPolygon2D;
    class procedure TrochoidalSlot(J: TCamJob; X1, Y1, X2, Y2, SlotWidth,
      FinalDepth, StepOverFraction: Double; Climb: Boolean = True;
      PointsPerLoop: Integer = 36);
    { Retorna o numero de aneis por nivel (0 = regiao menor que a fresa). }
    class function OffsetPocket(J: TCamJob; const Region: TPolygon2D;
      FinalDepth: Double; Climb: Boolean = True): Integer;
    class procedure CompensatedProfile(J: TCamJob; const Shape: TPolygon2D;
      Side: TCutSide; FinalDepth, Allowance: Double; FinishPass: Boolean;
      const Tabs: TTabSettings; Climb: Boolean = True);
  end;

function NoTabs: TTabSettings;

implementation

const
  RAMP_ANGLE_DEG = 3.0;  // angulo de rampa/helice conservador para fresas de topo

function NoTabs: TTabSettings;
begin
  Result.Count := 0;
  Result.Width := 0;
  Result.Height := 0;
end;

class function THSMCAM.ContourToPolygon(C: TCamContour): TPolygon2D;
var I, N: Integer;
begin
  SetLength(Result, 0);
  if C = nil then Exit;
  N := C.Count;
  if C.Closed then Dec(N); // ultimo ponto repete o primeiro
  SetLength(Result, N);
  for I := 0 to N - 1 do Result[I] := Pt(C.Point(I).X, C.Point(I).Y);
end;

class function THSMCAM.PolygonCentroid(const P: TPolygon2D): TPoint2D;
var I, K: Integer; A, F, CX, CY: Double;
begin
  A := 0; CX := 0; CY := 0;
  K := High(P);
  for I := 0 to High(P) do begin
    F := P[K].X * P[I].Y - P[I].X * P[K].Y;
    A := A + F;
    CX := CX + (P[K].X + P[I].X) * F;
    CY := CY + (P[K].Y + P[I].Y) * F;
    K := I;
  end;
  if Abs(A) < 1e-12 then begin
    Result := Pt(0, 0);
    for I := 0 to High(P) do begin Result.X := Result.X + P[I].X; Result.Y := Result.Y + P[I].Y; end;
    if Length(P) > 0 then begin Result.X := Result.X / Length(P); Result.Y := Result.Y / Length(P); end;
  end else
    Result := Pt(CX / (3 * A), CY / (3 * A));
end;

{ Niveis de profundidade iguais (nenhum passe mais raso que os outros);
  usa o campo X de cada ponto como Z. }
class function THSMCAM.DepthLevels(FinalDepth, StepDown: Double): TPolygon2D;
var N, I: Integer;
begin
  SetLength(Result, 0);
  if (FinalDepth >= 0) or (StepDown <= 0) then Exit;
  N := Max(1, Ceil(Abs(FinalDepth) / StepDown - 1e-9));
  SetLength(Result, N);
  for I := 1 to N do begin
    Result[I - 1].X := FinalDepth * I / N;
    Result[I - 1].Y := 0;
  end;
end;

class procedure THSMCAM.TrochoidalSlot(J: TCamJob; X1, Y1, X2, Y2, SlotWidth,
  FinalDepth, StepOverFraction: Double; Climb: Boolean; PointsPerLoop: Integer);
var
  Len, UX, UY, VX, VY, R, Step, T, A, CX, CY, Z, Dir: Double;
  Loops, I, Total, L: Integer;
  Levels: TPolygon2D;
begin
  J.Clear;
  J.Operation := coPocket;
  Len := Hypot(X2 - X1, Y2 - Y1);
  if (J.Tool.Diameter <= 0) or (FinalDepth >= 0) then Exit;
  R := (SlotWidth - J.Tool.Diameter) / 2;   // raio do laco (centro da ferramenta)
  if R < 0.05 * J.Tool.Diameter then
    raise Exception.Create('Trocoidal exige rasgo mais largo que a ferramenta (>= 1,1 x D).');
  if StepOverFraction <= 0 then StepOverFraction := 0.1;
  Step := J.Tool.Diameter * StepOverFraction; // avanco do centro por volta
  if PointsPerLoop < 12 then PointsPerLoop := 12;
  if Len > 1e-9 then begin
    UX := (X2 - X1) / Len; UY := (Y2 - Y1) / Len;
  end else begin
    UX := 1; UY := 0;
  end;
  VX := -UY; VY := UX;                       // normal a esquerda
  if Climb then Dir := 1 else Dir := -1;     // anti-horario = concordante
  Loops := Max(1, Ceil(Len / Step));
  Total := Loops * PointsPerLoop;
  // Usa a altura de corte inteira; so divide quando excede o comprimento util.
  if (J.Tool.FluteLength > 0) and (Abs(FinalDepth) > J.Tool.FluteLength * 0.9) then
    Levels := DepthLevels(FinalDepth, J.Tool.FluteLength * 0.9)
  else begin
    SetLength(Levels, 1);
    Levels[0].X := FinalDepth;
  end;
  for L := 0 to High(Levels) do begin
    Z := Levels[L].X;
    // entrada: centro do primeiro laco (furo/rampa previa recomendados)
    J.AddMove(X1 + R * UX, Y1 + R * UY, J.Settings.SafeZ, True);
    J.AddMove(X1 + R * UX, Y1 + R * UY, Z, False);
    for I := 1 to Total do begin
      T := I / Total;
      A := Dir * 2 * Pi * I / PointsPerLoop;
      CX := X1 + UX * Len * T;
      CY := Y1 + UY * Len * T;
      J.AddMove(CX + R * (Cos(A) * UX + Sin(A) * VX),
                CY + R * (Cos(A) * UY + Sin(A) * VY), Z, False);
    end;
    // volta completa no fim para limpar a ponta do rasgo
    for I := 1 to PointsPerLoop do begin
      A := Dir * 2 * Pi * I / PointsPerLoop;
      J.AddMove(X2 + R * (Cos(A) * UX + Sin(A) * VX),
                Y2 + R * (Cos(A) * UY + Sin(A) * VY), Z, False);
    end;
    J.AddMove(X2 + R * UX, Y2 + R * UY, J.Settings.SafeZ, True);
  end;
end;

function RotateToNearest(const Ring: TPolygon2D; const Q: TPoint2D): TPolygon2D;
var I, Best: Integer; D, BestD: Double;
begin
  Best := 0;
  BestD := MaxDouble;
  for I := 0 to High(Ring) do begin
    D := Sqr(Ring[I].X - Q.X) + Sqr(Ring[I].Y - Q.Y);
    if D < BestD then begin BestD := D; Best := I; end;
  end;
  SetLength(Result, Length(Ring));
  for I := 0 to High(Ring) do Result[I] := Ring[(Best + I) mod Length(Ring)];
end;

procedure CutRing(J: TCamJob; const Ring: TPolygon2D; Z: Double);
var I: Integer;
begin
  for I := 0 to High(Ring) do J.AddMove(Ring[I].X, Ring[I].Y, Z, False);
  J.AddMove(Ring[0].X, Ring[0].Y, Z, False);
end;

procedure Helix(J: TCamJob; CX, CY, Radius, ZFrom, ZTo, Pitch: Double);
var Turns, N, I: Integer; A, T: Double;
begin
  Turns := Max(1, Ceil(Abs(ZTo - ZFrom) / Max(Pitch, 1e-3)));
  N := Turns * 24;
  J.AddMove(CX + Radius, CY, ZFrom, False);
  for I := 1 to N do begin
    T := I / N;
    A := 2 * Pi * Turns * T;   // anti-horario
    J.AddMove(CX + Radius * Cos(A), CY + Radius * Sin(A), ZFrom + (ZTo - ZFrom) * T, False);
  end;
  // volta plana no fundo
  for I := 1 to 24 do
    J.AddMove(CX + Radius * Cos(2 * Pi * I / 24), CY + Radius * Sin(2 * Pi * I / 24), ZTo, False);
end;

class function THSMCAM.OffsetPocket(J: TCamJob; const Region: TPolygon2D;
  FinalDepth: Double; Climb: Boolean): Integer;
var
  Rings: TPolygons2D;
  Ring: TPolygon2D;
  Levels: TPolygon2D;
  D, Step, ZPrev, Z, HelixR, Pitch, Room: Double;
  L, I, N: Integer;
  C, Last: TPoint2D;
begin
  J.Clear;
  J.Operation := coPocket;
  Result := 0;
  if (J.Tool.Diameter <= 0) or (J.Settings.StepOver <= 0) or (J.Settings.StepDown <= 0) or
    (FinalDepth >= 0) or (Length(Region) < 3) then Exit;
  // StepOver pode vir como fracao do diametro (<=1) ou em mm (>1, legado)
  if J.Settings.StepOver <= 1 then Step := J.Tool.Diameter * J.Settings.StepOver
  else Step := Min(J.Settings.StepOver, J.Tool.Diameter * 0.9);
  // Aneis: primeiro a D/2 da parede, depois a cada Step para dentro.
  N := 0;
  SetLength(Rings, 0);
  D := -J.Tool.Diameter / 2;
  repeat
    Ring := OffsetPolygon(Region, D, jtRound, 2, 0.005);
    if Length(Ring) >= 3 then begin
      if not Climb then Ring := ReversePolygon(Ring);
      SetLength(Rings, N + 1);
      Rings[N] := Ring;
      Inc(N);
    end;
    D := D - Step;
  until (Length(Ring) < 3) or (N > 2000);
  Result := N;
  if N = 0 then Exit;
  Levels := DepthLevels(FinalDepth, J.Settings.StepDown);
  // Pitch da helice: no maximo StepDown e no maximo a rampa de 3 graus.
  C := PolygonCentroid(Rings[N - 1]);
  Room := DistanceToPolygon(C, Rings[N - 1]);
  if not PointInPolygon(C, Rings[N - 1]) then Room := 0;
  HelixR := Min(J.Tool.Diameter * 0.25, Room);
  ZPrev := 0;
  for L := 0 to High(Levels) do begin
    Z := Levels[L].X;
    if HelixR >= J.Tool.Diameter * 0.1 then begin
      Pitch := Min(J.Settings.StepDown, 2 * Pi * HelixR * Tan(DegToRad(RAMP_ANGLE_DEG)) * 4);
      J.AddMove(C.X + HelixR, C.Y, J.Settings.SafeZ, True);
      J.AddMove(C.X + HelixR, C.Y, ZPrev, True);
      Helix(J, C.X, C.Y, HelixR, ZPrev, Z, Pitch);
      Last := Pt(C.X + HelixR, C.Y);
    end else begin
      // sem espaco para helice: rampa ao longo do anel mais interno
      Ring := Rings[N - 1];
      J.AddMove(Ring[0].X, Ring[0].Y, J.Settings.SafeZ, True);
      J.AddMove(Ring[0].X, Ring[0].Y, ZPrev, True);
      for I := 1 to High(Ring) do
        J.AddMove(Ring[I].X, Ring[I].Y, ZPrev + (Z - ZPrev) * I / Length(Ring), False);
      J.AddMove(Ring[0].X, Ring[0].Y, Z, False);
      Last := Ring[0];
    end;
    // de dentro para fora, ligando aneis no fundo (sem retrair)
    for I := N - 1 downto 0 do begin
      Ring := RotateToNearest(Rings[I], Last);
      CutRing(J, Ring, Z);
      Last := Ring[0];
    end;
    J.AddMove(Last.X, Last.Y, J.Settings.SafeZ, True);
    ZPrev := Z;
  end;
end;

{ Ponto a uma distancia S ao longo do anel fechado. }
function PointAlong(const Ring: TPolygon2D; const Cum: array of Double; S: Double): TPoint2D;
var I, N: Integer; P, T: Double;
begin
  N := Length(Ring);
  P := Cum[N];
  S := S - Floor(S / P) * P;
  I := 0;
  while (I < N - 1) and (Cum[I + 1] < S) do Inc(I);
  T := (S - Cum[I]) / Max(Cum[I + 1] - Cum[I], 1e-12);
  Result := Pt(Ring[I].X + (Ring[(I + 1) mod N].X - Ring[I].X) * T,
               Ring[I].Y + (Ring[(I + 1) mod N].Y - Ring[I].Y) * T);
end;

{ Percorre o anel de S0 a S1 (S1 pode passar de uma volta) com Z variando
  linearmente de Z0 a Z1; nas janelas de tab o Z nao desce abaixo de TabTop. }
procedure WalkRing(J: TCamJob; const Ring: TPolygon2D; S0, S1, Z0, Z1: Double;
  const TabStart, TabEnd: array of Double; TabTop: Double; UseTabs: Boolean);
var
  Cum, Br: array of Double;
  N, I, K, NB, Laps: Integer;
  P, S, Tmp, ZR, ZB, ZA: Double;
  Q: TPoint2D;

  procedure AddBr(V: Double);
  begin
    if (V < S0 - 1e-9) or (V > S1 + 1e-9) then Exit;
    if NB >= Length(Br) then SetLength(Br, Max(32, NB * 2));
    Br[NB] := V;
    Inc(NB);
  end;

  function InTab(V: Double): Boolean;
  var T: Integer; M: Double;
  begin
    Result := False;
    if not UseTabs then Exit;
    M := V - Floor(V / P) * P;
    for T := 0 to High(TabStart) do
      if (M > TabStart[T]) and (M < TabEnd[T]) then Exit(True);
  end;

  function ZAt(V: Double; Tab: Boolean): Double;
  begin
    if S1 - S0 > 1e-12 then Result := Z0 + (Z1 - Z0) * (V - S0) / (S1 - S0) else Result := Z1;
    if Tab then Result := Max(Result, TabTop);
  end;

begin
  N := Length(Ring);
  SetLength(Cum, N + 1);
  Cum[0] := 0;
  for I := 1 to N do
    Cum[I] := Cum[I - 1] + Hypot(Ring[I mod N].X - Ring[I - 1].X, Ring[I mod N].Y - Ring[I - 1].Y);
  P := Cum[N];
  if P < 1e-9 then Exit;
  NB := 0;
  SetLength(Br, 0);
  AddBr(S0);
  AddBr(S1);
  Laps := Ceil(S1 / P) + 1;
  for K := 0 to Laps do begin
    for I := 0 to N - 1 do AddBr(K * P + Cum[I]);
    if UseTabs then
      for I := 0 to High(TabStart) do begin
        AddBr(K * P + TabStart[I]);
        AddBr(K * P + TabEnd[I]);
      end;
  end;
  // ordena
  for I := 1 to NB - 1 do begin
    Tmp := Br[I];
    K := I - 1;
    while (K >= 0) and (Br[K] > Tmp) do begin Br[K + 1] := Br[K]; Dec(K); end;
    Br[K + 1] := Tmp;
  end;
  S := -MaxDouble;
  for I := 0 to NB - 1 do begin
    if Br[I] - S < 1e-9 then Continue;
    S := Br[I];
    Q := PointAlong(Ring, Cum, S);
    ZB := ZAt(S, InTab(S - 1e-6));
    ZA := ZAt(S, InTab(S + 1e-6));
    if I = 0 then ZB := ZA;
    J.AddMove(Q.X, Q.Y, ZB, False);
    if Abs(ZA - ZB) > 1e-9 then J.AddMove(Q.X, Q.Y, ZA, False);
  end;
end;

class procedure THSMCAM.CompensatedProfile(J: TCamJob; const Shape: TPolygon2D;
  Side: TCutSide; FinalDepth, Allowance: Double; FinishPass: Boolean;
  const Tabs: TTabSettings; Climb: Boolean);
var
  Ring, FinishRing: TPolygon2D;
  Levels: TPolygon2D;
  R, Per, RampLen, ZPrev, Z, TabTop, Spacing: Double;
  TabBeg, TabFin: array of Double;
  L, I: Integer;
  Last: Boolean;

  function MakeRing(Extra: Double): TPolygon2D;
  begin
    case Side of
      csOutside: Result := OffsetPolygon(Shape, R + Extra, jtRound, 2, 0.005);
      csInside: Result := OffsetPolygon(Shape, -(R + Extra), jtRound, 2, 0.005);
    else
      Result := RemoveDuplicatePoints(Shape);
    end;
    if Length(Result) < 3 then Exit;
    if not PolygonIsCCW(Result) then Result := ReversePolygon(Result);
    // externo: concordante = horario; interno: concordante = anti-horario
    if (Side = csOutside) = Climb then Result := ReversePolygon(Result);
  end;

begin
  J.Clear;
  if Side = csInside then J.Operation := coProfileInside else J.Operation := coProfileOutside;
  if (J.Tool.Diameter <= 0) or (J.Settings.StepDown <= 0) or (FinalDepth >= 0) or
    (Length(Shape) < 3) then Exit;
  R := J.Tool.Diameter / 2;
  Ring := MakeRing(Max(0, Allowance));
  if Length(Ring) < 3 then
    raise Exception.Create('Contorno menor que a ferramenta para o perfil interno.');
  Per := PolygonPerimeter(Ring);
  // Tabs igualmente espacados; largura inclui o diametro da fresa.
  SetLength(TabBeg, 0);
  SetLength(TabFin, 0);
  TabTop := FinalDepth + Max(0, Tabs.Height);
  if (Tabs.Count > 0) and (Tabs.Height > 0) then begin
    SetLength(TabBeg, Tabs.Count);
    SetLength(TabFin, Tabs.Count);
    Spacing := Per / Tabs.Count;
    for I := 0 to Tabs.Count - 1 do begin
      TabBeg[I] := Spacing * (I + 0.5) - (Tabs.Width + J.Tool.Diameter) / 2;
      TabFin[I] := Spacing * (I + 0.5) + (Tabs.Width + J.Tool.Diameter) / 2;
    end;
  end;
  Levels := DepthLevels(FinalDepth, J.Settings.StepDown);
  J.AddMove(Ring[0].X, Ring[0].Y, J.Settings.SafeZ, True);
  ZPrev := 0;
  J.AddMove(Ring[0].X, Ring[0].Y, ZPrev, True);
  for L := 0 to High(Levels) do begin
    Z := Levels[L].X;
    Last := (L = High(Levels)) and not FinishPass;
    // rampa de RAMP_ANGLE_DEG ao longo do proprio contorno
    RampLen := Min(Per, Max(J.Tool.Diameter * 2, Abs(Z - ZPrev) / Tan(DegToRad(RAMP_ANGLE_DEG))));
    // a rampa nao pode atravessar um tab (sairia do tab descendo na vertical)
    if (Length(TabBeg) > 0) and (Z < TabTop) and (TabBeg[0] > 1e-3) then
      RampLen := Min(RampLen, TabBeg[0]);
    WalkRing(J, Ring, 0, RampLen, ZPrev, Z, TabBeg, TabFin, TabTop,
      (Length(TabBeg) > 0) and (Z < TabTop));
    // volta completa na profundidade, terminando onde a rampa acabou
    WalkRing(J, Ring, RampLen, RampLen + Per, Z, Z, TabBeg, TabFin, TabTop,
      (Length(TabBeg) > 0) and (Z < TabTop));
    // volta ao inicio do anel para o proximo nivel
    WalkRing(J, Ring, RampLen, Per, Z, Z, TabBeg, TabFin, TabTop,
      (Length(TabBeg) > 0) and (Z < TabTop));
    ZPrev := Z;
    if Last then Break;
  end;
  if FinishPass then begin
    FinishRing := MakeRing(0);
    if Length(FinishRing) >= 3 then begin
      J.AddMove(J.Move(J.Count - 1).P.X, J.Move(J.Count - 1).P.Y, J.Settings.SafeZ, True);
      J.AddMove(FinishRing[0].X, FinishRing[0].Y, J.Settings.SafeZ, True);
      J.AddMove(FinishRing[0].X, FinishRing[0].Y, FinalDepth + 0.5, True);
      J.AddMove(FinishRing[0].X, FinishRing[0].Y, FinalDepth, False);
      WalkRing(J, FinishRing, 0, PolygonPerimeter(FinishRing), FinalDepth, FinalDepth,
        TabBeg, TabFin, TabTop, Length(TabBeg) > 0);
    end;
  end;
  J.AddMove(J.Move(J.Count - 1).P.X, J.Move(J.Count - 1).P.Y, J.Settings.SafeZ, True);
end;

end.
