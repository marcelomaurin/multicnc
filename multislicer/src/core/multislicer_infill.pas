unit multislicer_infill;

{$mode objfpc}{$H+}

{ Padroes de preenchimento para impressao 3D.

  - Gyroid: superficie minima triplamente periodica
      sin(x)cos(y) + sin(y)cos(z) + sin(z)cos(x) = 0
    Padrao padrao em fatiadores modernos (Prusa/Orca/Cura): isotropico,
    resistente em todas as direcoes, sem cruzamentos de linhas na mesma
    camada (bico nao bate) e com caminhos continuos. A cada camada a curva
    muda suavemente com Z.
  - Retilineo: linhas paralelas em angulo dado, usado para camadas solidas
    (topo/fundo) com angulo alternado.

  As linhas sao geradas sobre o retangulo envolvente e recortadas pela regiao
  (poligonos com regra par-impar). }

interface

uses Math, multisuite_geometry;

{ Spacing = distancia media entre linhas (mm) = largura / densidade. }
function GyroidInfill(const Region: TPolygons2D; Z, Spacing: Double;
  Resolution: Double = 0.25): TPolygons2D;
function RectilinearInfill(const Region: TPolygons2D; AngleDeg, Spacing: Double;
  Offset: Double = 0): TPolygons2D;
procedure RegionBounds(const Region: TPolygons2D; out MinX, MinY, MaxX, MaxY: Double);

implementation

procedure RegionBounds(const Region: TPolygons2D; out MinX, MinY, MaxX, MaxY: Double);
var I: Integer; A, B, C, D: Double; First: Boolean;
begin
  MinX := 0; MinY := 0; MaxX := 0; MaxY := 0;
  First := True;
  for I := 0 to High(Region) do begin
    if Length(Region[I]) = 0 then Continue;
    PolygonBounds(Region[I], A, B, C, D);
    if First then begin
      MinX := A; MinY := B; MaxX := C; MaxY := D;
      First := False;
    end else begin
      MinX := Min(MinX, A); MinY := Min(MinY, B);
      MaxX := Max(MaxX, C); MaxY := Max(MaxY, D);
    end;
  end;
end;

procedure AppendClipped(var Result: TPolygons2D; const Line: TPolygon2D; const Region: TPolygons2D);
var Pieces: TPolygons2D; I, N: Integer;
begin
  if Length(Line) < 2 then Exit;
  Pieces := ClipPolylineToRegion(Line, Region);
  N := Length(Result);
  SetLength(Result, N + Length(Pieces));
  for I := 0 to High(Pieces) do Result[N + I] := Pieces[I];
end;

function GyroidInfill(const Region: TPolygons2D; Z, Spacing, Resolution: Double): TPolygons2D;
var
  MinX, MinY, MaxX, MaxY, K, Zs, SinZ, CosZ, U, UStart, UEnd, VStart, VEnd,
  A, B, C, R, Phi, Acs, V, Base, Step: Double;
  SolveY: Boolean;
  Branch, NIdx, NMin, NMax, Cnt, Samples, I: Integer;
  Line: TPolygon2D;

  procedure Flush;
  begin
    if Cnt >= 2 then begin
      SetLength(Line, Cnt);
      AppendClipped(Result, Line, Region);
    end;
    Cnt := 0;
    SetLength(Line, 0);
  end;

  procedure Add(PX, PY: Double);
  begin
    if Cnt >= Length(Line) then SetLength(Line, Max(64, Cnt * 2));
    Line[Cnt] := Pt(PX, PY);
    Inc(Cnt);
  end;

begin
  SetLength(Result, 0);
  if (Spacing <= 0) or (Length(Region) = 0) then Exit;
  RegionBounds(Region, MinX, MinY, MaxX, MaxY);
  // Um periodo 2*pi contem duas paredes do gyroid em cada direcao.
  K := Pi / Spacing;              // mm -> radianos
  Zs := Z * K;
  SinZ := Sin(Zs);
  CosZ := Cos(Zs);
  // Resolve na variavel com coeficiente constante maior (sem singularidade).
  SolveY := Abs(CosZ) >= Abs(SinZ);
  if SolveY then begin
    UStart := MinX * K; UEnd := MaxX * K; VStart := MinY * K; VEnd := MaxY * K;
  end else begin
    UStart := MinY * K; UEnd := MaxY * K; VStart := MinX * K; VEnd := MaxX * K;
  end;
  Step := Max(Resolution, 0.05) * K;
  Samples := Max(2, Ceil((UEnd - UStart) / Step) + 1);
  NMin := Floor(VStart / (2 * Pi)) - 1;
  NMax := Ceil(VEnd / (2 * Pi)) + 1;
  Cnt := 0;
  for Branch := 0 to 1 do
    for NIdx := NMin to NMax do begin
      Cnt := 0;
      for I := 0 to Samples - 1 do begin
        U := UStart + (UEnd - UStart) * I / (Samples - 1);
        if SolveY then begin
          // sin(x)cos(y) + cos(z)sin(y) = -sin(z)cos(x)
          A := Sin(U); B := CosZ; C := -SinZ * Cos(U);
          Phi := ArcTan2(B, A);
        end else begin
          // cos(y)sin(x) + sin(z)cos(x) = -sin(y)cos(z)   (U = y, resolve x)
          A := Cos(U); B := SinZ; C := -Sin(U) * CosZ;
          // fase continua (B tem sinal fixo nesta camada; ArcTan2 saltaria em +-pi)
          Phi := ArcTan(A / B);
          if B < 0 then Phi := Phi + Pi;
        end;
        R := Hypot(A, B);
        if (R < 1e-12) or (Abs(C) > R) then begin Flush; Continue; end;
        Acs := ArcCos(C / R);
        if Branch = 0 then Base := Phi + Acs else Base := Phi - Acs;
        V := Base + 2 * Pi * NIdx;
        if (V < VStart - 2 * Pi) or (V > VEnd + 2 * Pi) then begin Flush; Continue; end;
        if SolveY then Add(U / K, V / K) else Add(V / K, U / K);
      end;
      Flush;
    end;
end;

function RectilinearInfill(const Region: TPolygons2D; AngleDeg, Spacing, Offset: Double): TPolygons2D;
var
  MinX, MinY, MaxX, MaxY, CX, CY, Rad, Ca, Sa, D, Half: Double;
  Line: TPolygon2D;
  K, N: Integer;
begin
  SetLength(Result, 0);
  if (Spacing <= 0) or (Length(Region) = 0) then Exit;
  RegionBounds(Region, MinX, MinY, MaxX, MaxY);
  CX := (MinX + MaxX) / 2; CY := (MinY + MaxY) / 2;
  Half := Hypot(MaxX - MinX, MaxY - MinY) / 2 + Spacing;
  Rad := DegToRad(AngleDeg);
  Ca := Cos(Rad); Sa := Sin(Rad);
  N := Ceil(Half / Spacing);
  SetLength(Line, 2);
  for K := -N to N do begin
    D := K * Spacing + Offset;
    // linha na direcao (Ca, Sa), deslocada D na normal (-Sa, Ca)
    if Odd(K) then begin
      Line[0] := Pt(CX - Sa * D - Ca * Half, CY + Ca * D - Sa * Half);
      Line[1] := Pt(CX - Sa * D + Ca * Half, CY + Ca * D + Sa * Half);
    end else begin
      Line[1] := Pt(CX - Sa * D - Ca * Half, CY + Ca * D - Sa * Half);
      Line[0] := Pt(CX - Sa * D + Ca * Half, CY + Ca * D + Sa * Half);
    end;
    AppendClipped(Result, Line, Region);
  end;
end;

end.
