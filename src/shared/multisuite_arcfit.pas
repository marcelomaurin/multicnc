unit multisuite_arcfit;

{$mode objfpc}{$H+}

{ Ajuste de arcos (arc fitting) para pos-processadores.

  Converte sequencias de pequenos segmentos de reta - comuns em trajetorias
  geradas a partir de malhas, offsets e SVG - em comandos G2/G3. Mesmo
  principio do "Arc Welder" usado por fatiadores modernos (Prusa/Orca/Cura):
  - arquivos G-code bem menores;
  - menos linhas no buffer serial (GRBL/Marlin/grblHAL), movimento mais suave
    em controladores de 8 bits;
  - o desvio maximo de cada ponto original ao arco fica dentro de Tolerance.

  So agrupa pontos com Z constante (arcos planos XY / G17). }

interface

uses Math, SysUtils, multisuite_geometry;

type
  TFitMoveKind = (fmLine, fmArcCW, fmArcCCW);

  TFitMove = record
    Kind: TFitMoveKind;
    X, Y: Double;     // destino
    I, J: Double;     // centro relativo ao ponto inicial (G91.1)
    Radius: Double;
  end;
  TFitMoves = array of TFitMove;

  TArcFitOptions = record
    Tolerance: Double;      // mm - desvio maximo permitido
    MinPoints: Integer;     // pontos minimos para formar um arco (>= 4)
    MinRadius: Double;      // mm
    MaxRadius: Double;      // mm (raios enormes ~ retas)
  end;

function DefaultArcFitOptions: TArcFitOptions;

{ Path[0] e o ponto inicial (posicao atual); o resultado contem os movimentos
  ate Path[High]. }
function FitArcs(const Path: TPolygon2D; const Opt: TArcFitOptions): TFitMoves;

{ Formata G1/G2/G3 com ponto decimal invariante. }
function FormatFitMove(const M: TFitMove; Decimals: Integer = 3): string;

implementation

function DefaultArcFitOptions: TArcFitOptions;
begin
  Result.Tolerance := 0.01;
  Result.MinPoints := 4;
  Result.MinRadius := 0.2;
  Result.MaxRadius := 2000;
end;

function CircleFrom3(const A, B, C: TPoint2D; out CX, CY, R: Double): Boolean;
var D: Double;
begin
  D := 2 * (A.X * (B.Y - C.Y) + B.X * (C.Y - A.Y) + C.X * (A.Y - B.Y));
  Result := Abs(D) > 1e-12;
  if not Result then Exit;
  CX := ((Sqr(A.X) + Sqr(A.Y)) * (B.Y - C.Y) + (Sqr(B.X) + Sqr(B.Y)) * (C.Y - A.Y) +
    (Sqr(C.X) + Sqr(C.Y)) * (A.Y - B.Y)) / D;
  CY := ((Sqr(A.X) + Sqr(A.Y)) * (C.X - B.X) + (Sqr(B.X) + Sqr(B.Y)) * (A.X - C.X) +
    (Sqr(C.X) + Sqr(C.Y)) * (B.X - A.X)) / D;
  R := Hypot(A.X - CX, A.Y - CY);
end;

{ Verifica se Path[S..E] cabe num arco unico dentro da tolerancia. }
function TryArc(const Path: TPolygon2D; S, E: Integer; const Opt: TArcFitOptions;
  out CX, CY, R: Double; out CCW: Boolean): Boolean;
var K, Mid: Integer; Cross, Dir, Prev, Ang, Total, MX, MY: Double;
begin
  Result := False;
  Mid := (S + E) div 2;
  if not CircleFrom3(Path[S], Path[Mid], Path[E], CX, CY, R) then Exit;
  if (R < Opt.MinRadius) or (R > Opt.MaxRadius) then Exit;
  // sentido pelo produto vetorial dos primeiros pontos
  Cross := (Path[S + 1].X - Path[S].X) * (Path[Mid].Y - Path[S].Y) -
    (Path[S + 1].Y - Path[S].Y) * (Path[Mid].X - Path[S].X);
  if Abs(Cross) < 1e-15 then
    Cross := (Path[Mid].X - Path[S].X) * (Path[E].Y - Path[S].Y) -
      (Path[Mid].Y - Path[S].Y) * (Path[E].X - Path[S].X);
  CCW := Cross > 0;
  if CCW then Dir := 1 else Dir := -1;
  Total := 0;
  Prev := ArcTan2(Path[S].Y - CY, Path[S].X - CX);
  for K := S + 1 to E do begin
    // pontos sobre o circulo
    if Abs(Hypot(Path[K].X - CX, Path[K].Y - CY) - R) > Opt.Tolerance then Exit;
    // ponto medio de cada corda: flecha (sagitta) dentro da tolerancia
    MX := (Path[K].X + Path[K - 1].X) / 2;
    MY := (Path[K].Y + Path[K - 1].Y) / 2;
    if Abs(Hypot(MX - CX, MY - CY) - R) > Opt.Tolerance then Exit;
    // varredura monotonica no sentido escolhido
    Ang := ArcTan2(Path[K].Y - CY, Path[K].X - CX);
    Cross := (Ang - Prev) * Dir;
    while Cross < -Pi do Cross := Cross + 2 * Pi;
    while Cross > Pi do Cross := Cross - 2 * Pi;
    if Cross <= 1e-9 then Exit;
    Total := Total + Cross;
    Prev := Ang;
  end;
  // evita circulos completos ambiguos (inicio = fim)
  Result := Total < 2 * Pi - 1e-3;
end;

function FitArcs(const Path: TPolygon2D; const Opt: TArcFitOptions): TFitMoves;
var
  S, E, BestE, N: Integer;
  CX, CY, R, BCX, BCY, BR: Double;
  CCW, BCCW: Boolean;
  MinPts: Integer;

  procedure Emit(Kind: TFitMoveKind; const P: TPoint2D; I, J, Rad: Double);
  begin
    if N >= Length(Result) then SetLength(Result, Max(16, N * 2));
    Result[N].Kind := Kind;
    Result[N].X := P.X;
    Result[N].Y := P.Y;
    Result[N].I := I;
    Result[N].J := J;
    Result[N].Radius := Rad;
    Inc(N);
  end;

begin
  SetLength(Result, 0);
  N := 0;
  MinPts := Max(4, Opt.MinPoints);
  S := 0;
  while S < High(Path) do begin
    BestE := -1;
    E := S + MinPts - 1;
    // cresce a janela enquanto o arco continuar valido
    while (E <= High(Path)) and TryArc(Path, S, E, Opt, CX, CY, R, CCW) do begin
      BestE := E;
      BCX := CX; BCY := CY; BR := R; BCCW := CCW;
      Inc(E);
    end;
    if BestE > 0 then begin
      if BCCW then
        Emit(fmArcCCW, Path[BestE], BCX - Path[S].X, BCY - Path[S].Y, BR)
      else
        Emit(fmArcCW, Path[BestE], BCX - Path[S].X, BCY - Path[S].Y, BR);
      S := BestE;
    end else begin
      Emit(fmLine, Path[S + 1], 0, 0, 0);
      Inc(S);
    end;
  end;
  SetLength(Result, N);
end;

function FormatFitMove(const M: TFitMove; Decimals: Integer): string;
var FS: TFormatSettings; F: string;
begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  F := '%.' + IntToStr(Decimals) + 'f';
  case M.Kind of
    fmLine: Result := Format('G1 X' + F + ' Y' + F, [M.X, M.Y], FS);
    fmArcCW: Result := Format('G2 X' + F + ' Y' + F + ' I' + F + ' J' + F, [M.X, M.Y, M.I, M.J], FS);
    fmArcCCW: Result := Format('G3 X' + F + ' Y' + F + ' I' + F + ' J' + F, [M.X, M.Y, M.I, M.J], FS);
  end;
end;

end.
