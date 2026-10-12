unit multislicer_support;

{ MultiSlicer - suportes (hastes de apoio) (Etapa 6 do docs/PLANO_TAREFAS.md).

  Entrada: os contornos de cada camada (Loops, externos anti-horario, furos
  horario), a altura de topo e a espessura de cada camada. Saida: por camada,
  a regiao de suporte e a parte dela que e interface (mais densa, encosta na
  peca).

  1. Saliencia da camada i: o que a camada i tem e a camada i-1, alargada por
     h * tan(angulo), nao sustenta (angulo medido da vertical, como no Cura:
     50 graus = paredes mais deitadas que 50 graus precisam de apoio).
     So o ruido numerico e descartado aqui; faixas finas saem na coluna (passo 5).
  2. A coluna desce: S(i) = fecha[S(i+1) U O(i+1+g)] - peca(i) alargada da folga XY,
     onde g = camadas de folga Z entre o topo do suporte e a peca.
     "Tocando a mesa": em vez de peca(i), usa tudo o que existe da camada i para
     baixo - se a coluna encontra a peca, para (nao apoia na peca).
  3. Bloqueadores (caixas) tiram o suporte automatico do seu volume.
  4. Hastes manuais: cilindros da mesa ate o ponto clicado (menos a folga Z),
     desviando so da propria camada da peca.
  5. Interface: as InterfaceLayers camadas logo abaixo de uma saliencia (e o
     topo das hastes). }

{$mode objfpc}{$H+}

interface

uses Classes, SysUtils, Math, multisuite_geometry, multislicer_clip;

type
  TSupportMode = (spOff, spAuto, spManual);

  TSupportPillar = record
    X, Y, ZTop, Diameter: Double;
  end;
  TSupportPillars = array of TSupportPillar;

  TSupportBlocker = record
    MinX, MinY, MinZ, MaxX, MaxY, MaxZ: Double;
  end;
  TSupportBlockers = array of TSupportBlocker;

  TSupportParams = record
    Mode: TSupportMode;
    Everywhere: Boolean;        { False = so tocando a mesa }
    AngleDeg: Double;           { angulo de saliencia, da vertical }
    XYGap, ZGap: Double;        { mm }
    JoinDistance: Double;       { frestas menores que isso viram uma regiao so (mm) }
    Density: Double;            { 0..1 }
    InterfaceLayers: Integer;
    InterfaceDensity: Double;   { 0..1 }
    Speed: Double;              { mm/s; 0 = velocidade do preenchimento }
    Pillars: TSupportPillars;
    Blockers: TSupportBlockers;
  end;

  TLayerRegions = array of TPolygons2D;

function DefaultSupportParams: TSupportParams;
{ saliencia de Cur sobre Below }
function OverhangRegion(const Below, Cur: TPolygons2D; LayerH, AngleDeg, LineW: Double): TPolygons2D;
procedure ComputeSupport(const Loops: array of TPolygons2D; const Z, H: array of Double;
  const P: TSupportParams; LineW, NominalH: Double; out Regions, Interfaces: TLayerRegions);

implementation

function DefaultSupportParams: TSupportParams;
begin
  Result.Mode := spOff;
  Result.Everywhere := False;
  Result.AngleDeg := 50;
  Result.XYGap := 0.7;
  Result.ZGap := 0.2;
  Result.JoinDistance := 2;
  Result.Density := 0.15;
  Result.InterfaceLayers := 2;
  Result.InterfaceDensity := 0.7;
  Result.Speed := 50;
  Result.Pillars := nil;
  Result.Blockers := nil;
end;

function OverhangRegion(const Below, Cur: TPolygons2D; LayerH, AngleDeg, LineW: Double): TPolygons2D;
var D: Double;
begin
  if Length(Cur) = 0 then Exit(nil);
  D := LayerH * Tan(DegToRad(EnsureRange(AngleDeg, 0, 89)));
  Result := RegionDifference(Cur, RegionOffset(Below, D));
  { so tira ruido numerico: numa superficie curva a saliencia de cada camada e
    um anel fino (0,1 a 0,2 mm) - ele precisa ficar, pois a coluna acumula os
    aneis de cima; a limpeza de faixas finas e feita na coluna acumulada }
  Result := RegionOpen(Result, Min(0.03, LineW * 0.05));
end;

procedure ComputeSupport(const Loops: array of TPolygons2D; const Z, H: array of Double;
  const P: TSupportParams; LineW, NominalH: Double; out Regions, Interfaces: TLayerRegions);
var
  N, I, J, K, G, NI: Integer;
  L, O, Bl, S: TLayerRegions;
  Need, Block, Cut, Pil, Over: TPolygons2D;
  Bot, TopZ: Double;
begin
  N := Length(Loops);
  Regions := nil; Interfaces := nil;
  SetLength(Regions, N);
  SetLength(Interfaces, N);
  if (N = 0) or (P.Mode = spOff) then Exit;
  SetLength(L, N); SetLength(O, N); SetLength(S, N);
  for I := 0 to N - 1 do L[I] := RegionUnionAll(Loops[I]);
  { 1. saliencias }
  if P.Mode = spAuto then
    for I := 1 to N - 1 do
      O[I] := OverhangRegion(L[I - 1], L[I], H[I], P.AngleDeg, LineW);
  { folga Z em camadas }
  if NominalH <= 0 then NominalH := 0.2;
  G := Round(P.ZGap / NominalH);
  if (P.ZGap > 0) and (G < 1) then G := 1;
  NI := Max(0, P.InterfaceLayers);
  { "tocando a mesa": tudo o que ha da camada i para baixo }
  if not P.Everywhere then
  begin
    SetLength(Bl, N);
    Bl[0] := L[0];
    for I := 1 to N - 1 do Bl[I] := RegionUnion(Bl[I - 1], L[I]);
  end;
  { 2. a coluna desce a partir de cada saliencia }
  for I := N - 2 downto 0 do
  begin
    Need := S[I + 1];
    if I + 1 + G <= N - 1 then Need := RegionUnion(Need, O[I + 1 + G]);
    if Length(Need) = 0 then Continue;
    if P.Everywhere then Block := L[I] else Block := Bl[I];
    { fechamento: em superficie curva a coluna e uma pilha de aneis com frestas
      finas entre eles; junta tudo (como "support join distance" do Cura) e so
      depois desconta a peca com a folga XY }
    if P.JoinDistance > 0 then Need := RegionOffset(RegionOffset(Need, P.JoinDistance / 2), -P.JoinDistance / 2);
    S[I] := RegionDifference(Need, RegionOffset(Block, P.XYGap));
    { 3. bloqueadores }
    for K := 0 to High(P.Blockers) do
      with P.Blockers[K] do
      begin
        Bot := Z[I] - H[I];
        if (Z[I] >= MinZ) and (Bot <= MaxZ) then
        begin
          SetLength(Cut, 1);
          Cut[0] := RectPolygon(MinX, MinY, MaxX, MaxY);
          S[I] := RegionDifference(S[I], Cut);
        end;
      end;
  end;
  { 4. hastes manuais }
  for I := 0 to N - 1 do
  begin
    Pil := nil;
    for K := 0 to High(P.Pillars) do
      if Z[I] <= P.Pillars[K].ZTop - P.ZGap + 1e-6 then
      begin
        SetLength(Pil, Length(Pil) + 1);
        Pil[High(Pil)] := CirclePolygon(P.Pillars[K].X, P.Pillars[K].Y, Max(0.4, P.Pillars[K].Diameter / 2), 20);
      end;
    if Length(Pil) > 0 then
      S[I] := RegionUnion(S[I], RegionDifference(Pil, RegionOffset(L[I], P.XYGap)));
  end;
  { 5. interface e limpeza }
  for I := 0 to N - 1 do
  begin
    if Length(S[I]) = 0 then Continue;
    S[I] := RegionOpen(S[I], LineW * 0.45);
    if Length(S[I]) = 0 then Continue;
    Regions[I] := S[I];
    if NI = 0 then Continue;
    Over := nil;
    for J := 1 to NI do
      if I + G + J <= N - 1 then Over := RegionUnion(Over, O[I + G + J]);
    { topo das hastes }
    for K := 0 to High(P.Pillars) do
    begin
      TopZ := P.Pillars[K].ZTop - P.ZGap;
      if (Z[I] <= TopZ + 1e-6) and (Z[I] > TopZ - NI * NominalH - 1e-6) then
      begin
        SetLength(Pil, 1);
        Pil[0] := CirclePolygon(P.Pillars[K].X, P.Pillars[K].Y, Max(0.4, P.Pillars[K].Diameter / 2), 20);
        Over := RegionUnion(Over, Pil);
      end;
    end;
    if Length(Over) > 0 then
      Interfaces[I] := RegionIntersect(S[I], RegionOffset(Over, LineW));
  end;
end;

end.
