unit multislicer_pipeline;

{$mode objfpc}{$H+}

{ Pipeline de fatiamento moderno do MultiSlicer.

  Malha -> alturas de camada (fixa ou adaptativa) -> corte no meio da camada
  -> contornos fechados com furos -> perimetros (offset) -> regioes de
  preenchimento -> topo/fundo solidos (retilineo alternado) + infill gyroid
  -> ordenacao de caminhos e costura (seam) -> G-code.

  G-code:
  - extrusao relativa (M83) com volume pelo modelo de cordao arredondado
    (Slic3r): area = (w - h) * h + pi * (h/2)^2;
  - sabores Marlin 2.x e Klipper: progresso M73 (P/R), rotulos de objeto
    (M486 no Marlin, EXCLUDE_OBJECT no Klipper) para cancelar uma peca no
    meio da impressao, SET_PRINT_STATS_INFO, pressure/linear advance;
  - retracao com z-hop opcional, primeira camada mais lenta, ventoinha a
    partir da camada configurada, saia (skirt);
  - arc fitting opcional nos perimetros (G2/G3 com E proporcional);
  - cabecalho com tempo e filamento estimados (;TIME:, ;Filament used:),
    reconhecido por OctoPrint/Moonraker/Mainsail/Fluidd.

  Limitacoes conhecidas: sem suportes nem pontes; regioes muito finas para
  um perimetro sao descartadas; uniao de contornos sobrepostos de malhas
  com auto-intersecao nao e resolvida. }

interface

uses Classes, SysUtils, Math, multislicer_types, multislicer_mesh, multislicer_infill,
  multisuite_geometry, multisuite_arcfit;

type
  TSlicerFlavor = (sfMarlin, sfKlipper);
  TInfillPattern = (ipGyroid, ipRectilinear);
  TPathRole = (prSkirt, prOuterWall, prInnerWall, prSolidInfill, prSparseInfill);

  TSliceSettings = record
    Printer: TPrinterProfile;
    Flavor: TSlicerFlavor;
    LayerHeight, FirstLayerHeight: Double;
    Adaptive: Boolean;
    AdaptiveMin, AdaptiveMax, CuspHeight: Double;
    LineWidth: Double;
    Walls, TopLayers, BottomLayers: Integer;
    InfillDensity: Double;           // 0..1
    InfillPattern: TInfillPattern;
    WallSpeed, OuterWallSpeed, InfillSpeed, FirstLayerSpeed, TravelSpeed: Double; // mm/s
    RetractLength, RetractSpeed, RetractMinTravel, ZHop: Double;
    PressureAdvance: Double;         // 0 = nao emitir
    ArcFitting: Boolean;
    SkirtLoops: Integer;
    SkirtDistance: Double;
    FanFromLayer: Integer;
    FilamentDensity: Double;         // g/cm3
    ObjectName: string;
  end;

  TExtrusionPath = record
    Role: TPathRole;
    Points: TPolygon2D;
    Closed: Boolean;
  end;
  TExtrusionPaths = array of TExtrusionPath;

  TSliceReport = record
    Layers: Integer;
    EstimatedSeconds: Double;
    FilamentMM, FilamentGrams: Double;
    Retractions: Integer;
    MinZ, MaxZ: Double;
    Warnings: string;
  end;

  TLayerData = record
    Z, Height: Double;
    Loops: TPolygons2D;   // contornos (externos CCW, furos CW)
    InfillRegion: TPolygons2D;
    Paths: TExtrusionPaths;
  end;
  TLayerDataArray = array of TLayerData;

  TModernSlicer = class
  private
    FSettings: TSliceSettings;
    FLayers: TLayerDataArray;
    procedure BuildLayer(Index: Integer; Mesh: TMesh);
    procedure BuildInfill(Index: Integer);
  public
    class function ComputeLayerHeights(Mesh: TMesh; const S: TSliceSettings): TPolygon2D; // X=Z topo, Y=altura
    class function SliceAt(Mesh: TMesh; Z: Double): TPolygons2D;
    class function ExtrusionPerMM(Width, Height, FilamentDiameter: Double): Double;
    function Slice(Mesh: TMesh; const S: TSliceSettings; Output: TStrings): TSliceReport;
    property Layers: TLayerDataArray read FLayers;
  end;

function DefaultSliceSettings: TSliceSettings;
procedure AddBox(M: TMesh; X0, Y0, Z0, X1, Y1, Z1: Double);

implementation

uses multislicer_profile;

function DefaultSliceSettings: TSliceSettings;
begin
  Result.Printer := DefaultPrinterProfile;
  Result.Flavor := sfMarlin;
  Result.LayerHeight := 0.2;
  Result.FirstLayerHeight := 0.25;
  Result.Adaptive := False;
  Result.AdaptiveMin := 0.08;
  Result.AdaptiveMax := 0.28;
  Result.CuspHeight := 0.05;
  Result.LineWidth := Result.Printer.Nozzle * 1.125;
  Result.Walls := 2;
  Result.TopLayers := 4;
  Result.BottomLayers := 3;
  Result.InfillDensity := 0.15;
  Result.InfillPattern := ipGyroid;
  Result.WallSpeed := 45;
  Result.OuterWallSpeed := 30;
  Result.InfillSpeed := 70;
  Result.FirstLayerSpeed := 20;
  Result.TravelSpeed := 150;
  Result.RetractLength := 0.8;
  Result.RetractSpeed := 35;
  Result.RetractMinTravel := 1.5;
  Result.ZHop := 0;
  Result.PressureAdvance := 0;
  Result.ArcFitting := True;
  Result.SkirtLoops := 1;
  Result.SkirtDistance := 3;
  Result.FanFromLayer := 2;
  Result.FilamentDensity := 1.24; // PLA
  Result.ObjectName := 'objeto';
end;

procedure AddBox(M: TMesh; X0, Y0, Z0, X1, Y1, Z1: Double);
  procedure Tri(AX, AY, AZ, BX, BY, BZ, CX, CY, CZ: Double);
  var T: TTriangle;
  begin
    T.A.X := AX; T.A.Y := AY; T.A.Z := AZ;
    T.B.X := BX; T.B.Y := BY; T.B.Z := BZ;
    T.C.X := CX; T.C.Y := CY; T.C.Z := CZ;
    M.Add(T);
  end;
  procedure Quad(AX, AY, AZ, BX, BY, BZ, CX, CY, CZ, DX, DY, DZ: Double);
  begin
    Tri(AX, AY, AZ, BX, BY, BZ, CX, CY, CZ);
    Tri(AX, AY, AZ, CX, CY, CZ, DX, DY, DZ);
  end;
begin
  Quad(X0,Y0,Z0, X0,Y1,Z0, X1,Y1,Z0, X1,Y0,Z0); // fundo
  Quad(X0,Y0,Z1, X1,Y0,Z1, X1,Y1,Z1, X0,Y1,Z1); // topo
  Quad(X0,Y0,Z0, X1,Y0,Z0, X1,Y0,Z1, X0,Y0,Z1);
  Quad(X1,Y0,Z0, X1,Y1,Z0, X1,Y1,Z1, X1,Y0,Z1);
  Quad(X1,Y1,Z0, X0,Y1,Z0, X0,Y1,Z1, X1,Y1,Z1);
  Quad(X0,Y1,Z0, X0,Y0,Z0, X0,Y0,Z1, X0,Y1,Z1);
end;

class function TModernSlicer.ExtrusionPerMM(Width, Height, FilamentDiameter: Double): Double;
var Area: Double;
begin
  // cordao com laterais arredondadas (modelo Slic3r/PrusaSlicer)
  Area := (Width - Height) * Height + Pi * Sqr(Height / 2);
  Result := Area / (Pi * Sqr(FilamentDiameter / 2));
end;

class function TModernSlicer.ComputeLayerHeights(Mesh: TMesh; const S: TSliceSettings): TPolygon2D;
var
  ZMin, ZMax, Z, H, HTry, NZ, L, UX, UY, UZ, VX, VY, VZ, TZMin, TZMax: Double;
  TMin, TMax, TNz: array of Double;
  I, N, Iter: Integer;
  T: TTriangle;
begin
  SetLength(Result, 0);
  if Mesh.Count = 0 then Exit;
  ZMin := Mesh.MinZ;
  ZMax := Mesh.MaxZ;
  N := 0;
  // primeira camada sempre com altura propria (adesao)
  Z := ZMin + Max(S.FirstLayerHeight, 0.05);
  SetLength(Result, 1);
  Result[0] := Pt(Min(Z, ZMax), Min(Z, ZMax) - ZMin);
  N := 1;
  if S.Adaptive then begin
    SetLength(TMin, Mesh.Count); SetLength(TMax, Mesh.Count); SetLength(TNz, Mesh.Count);
    for I := 0 to Mesh.Count - 1 do begin
      T := Mesh.Triangle(I);
      TMin[I] := Min(T.A.Z, Min(T.B.Z, T.C.Z));
      TMax[I] := Max(T.A.Z, Max(T.B.Z, T.C.Z));
      UX := T.B.X - T.A.X; UY := T.B.Y - T.A.Y; UZ := T.B.Z - T.A.Z;
      VX := T.C.X - T.A.X; VY := T.C.Y - T.A.Y; VZ := T.C.Z - T.A.Z;
      NZ := UX * VY - UY * VX;
      L := Sqrt(Sqr(UY * VZ - UZ * VY) + Sqr(UZ * VX - UX * VZ) + Sqr(NZ));
      if L > 0 then TNz[I] := Abs(NZ) / L else TNz[I] := 0;
    end;
  end;
  while Z < ZMax - 1e-6 do begin
    if S.Adaptive then begin
      // altura maxima tal que a "escada" (cusp) nas superficies inclinadas
      // nao passe de CuspHeight: h = cusp / |nz|
      H := S.AdaptiveMax;
      for Iter := 1 to 2 do begin
        HTry := H;
        for I := 0 to High(TMin) do begin
          TZMin := TMin[I]; TZMax := TMax[I];
          if TNz[I] > 0.9999 then begin
            // face horizontal: nao gera degrau; a camada deve terminar
            // exatamente na altura dela (degraus planos ficam na cota certa)
            if (TZMin > Z + S.AdaptiveMin - 1e-9) and (TZMin < Z + HTry - 1e-9) then
              H := Min(H, TZMin - Z);
            Continue;
          end;
          if (TZMax <= Z) or (TZMin >= Z + HTry) then Continue;
          if TNz[I] > 1e-6 then H := Min(H, S.CuspHeight / TNz[I]);
        end;
        H := Max(H, S.AdaptiveMin);
      end;
    end else
      H := S.LayerHeight;
    if H <= 0 then H := 0.2;
    if Z + H > ZMax then H := ZMax - Z;
    if H < 0.02 then Break; // sobra desprezivel
    Z := Z + H;
    SetLength(Result, N + 1);
    Result[N] := Pt(Z, H);
    Inc(N);
  end;
end;

class function TModernSlicer.SliceAt(Mesh: TMesh; Z: Double): TPolygons2D;
var
  Segs: TSegments2D;
  I, N, K: Integer;
  T: TTriangle;
  V: array[0..2] of TVec3;
  P: array[0..1] of TPoint2D;
  A, B: TVec3;
  E: Double;
begin
  SetLength(Segs, 0);
  N := 0;
  E := 1e-7; // evita vertices exatamente no plano
  Z := Z + E;
  for I := 0 to Mesh.Count - 1 do begin
    T := Mesh.Triangle(I);
    V[0] := T.A; V[1] := T.B; V[2] := T.C;
    K := 0;
    if ((V[0].Z - Z) * (V[1].Z - Z) < 0) and (K < 2) then begin
      A := V[0]; B := V[1];
      P[K] := Pt(A.X + (Z - A.Z) / (B.Z - A.Z) * (B.X - A.X), A.Y + (Z - A.Z) / (B.Z - A.Z) * (B.Y - A.Y));
      Inc(K);
    end;
    if ((V[1].Z - Z) * (V[2].Z - Z) < 0) and (K < 2) then begin
      A := V[1]; B := V[2];
      P[K] := Pt(A.X + (Z - A.Z) / (B.Z - A.Z) * (B.X - A.X), A.Y + (Z - A.Z) / (B.Z - A.Z) * (B.Y - A.Y));
      Inc(K);
    end;
    if ((V[2].Z - Z) * (V[0].Z - Z) < 0) and (K < 2) then begin
      A := V[2]; B := V[0];
      P[K] := Pt(A.X + (Z - A.Z) / (B.Z - A.Z) * (B.X - A.X), A.Y + (Z - A.Z) / (B.Z - A.Z) * (B.Y - A.Y));
      Inc(K);
    end;
    if K = 2 then begin
      SetLength(Segs, N + 1);
      Segs[N].A := P[0];
      Segs[N].B := P[1];
      Inc(N);
    end;
  end;
  Result := ChainSegments(Segs, 1e-4);
  // orientacao por profundidade de aninhamento: externos CCW, furos CW
  for I := 0 to High(Result) do begin
    K := 0;
    for N := 0 to High(Result) do
      if (N <> I) and PointInPolygon(Result[I][0], Result[N]) then Inc(K);
    if Odd(K) = PolygonIsCCW(Result[I]) then Result[I] := ReversePolygon(Result[I]);
  end;
end;

function IsHole(const P: TPolygon2D): Boolean; inline;
begin
  Result := not PolygonIsCCW(P);
end;

{ Desloca cada contorno para dentro do material (externos encolhem, furos
  crescem). }
function InsetLoops(const Loops: TPolygons2D; Delta: Double): TPolygons2D;
var I, N: Integer; R: TPolygon2D;
begin
  SetLength(Result, 0);
  N := 0;
  for I := 0 to High(Loops) do begin
    if IsHole(Loops[I]) then R := OffsetPolygon(Loops[I], Delta, jtMiter, 3)
    else R := OffsetPolygon(Loops[I], -Delta, jtMiter, 3);
    if Length(R) < 3 then Continue;
    // OffsetPolygon devolve CCW; furos voltam a CW
    if IsHole(Loops[I]) then R := ReversePolygon(R);
    SetLength(Result, N + 1);
    Result[N] := R;
    Inc(N);
  end;
end;

{ Remove pontos intermediarios colineares de uma polilinha aberta. }
function SimplifyOpen(const P: TPolygon2D; Eps: Double): TPolygon2D;
var I, N: Integer; Cross, L: Double;
begin
  if Length(P) < 3 then Exit(P);
  SetLength(Result, Length(P));
  Result[0] := P[0];
  N := 1;
  for I := 1 to High(P) - 1 do begin
    L := Hypot(P[I + 1].X - Result[N - 1].X, P[I + 1].Y - Result[N - 1].Y);
    Cross := (P[I].X - Result[N - 1].X) * (P[I + 1].Y - Result[N - 1].Y) -
      (P[I].Y - Result[N - 1].Y) * (P[I + 1].X - Result[N - 1].X);
    if (L < 1e-12) or (Abs(Cross) / L > Eps) then begin
      Result[N] := P[I];
      Inc(N);
    end;
  end;
  Result[N] := P[High(P)];
  SetLength(Result, N + 1);
end;

procedure AddPath(var Paths: TExtrusionPaths; Role: TPathRole; const P: TPolygon2D; Closed: Boolean);
var N: Integer;
begin
  if Length(P) < 2 then Exit;
  N := Length(Paths);
  SetLength(Paths, N + 1);
  Paths[N].Role := Role;
  if Closed then Paths[N].Points := P else Paths[N].Points := SimplifyOpen(P, 1e-4);
  Paths[N].Closed := Closed;
end;

procedure TModernSlicer.BuildLayer(Index: Integer; Mesh: TMesh);
var
  W, D: Double;
  K, I: Integer;
  Ring: TPolygons2D;
  Skirt: TPolygon2D;
begin
  W := FSettings.LineWidth;
  FLayers[Index].Loops := SliceAt(Mesh, FLayers[Index].Z - FLayers[Index].Height / 2);
  SetLength(FLayers[Index].Paths, 0);
  // saia na primeira camada
  if (Index = 0) and (FSettings.SkirtLoops > 0) then
    for K := 0 to FSettings.SkirtLoops - 1 do
      for I := 0 to High(FLayers[Index].Loops) do
        if not IsHole(FLayers[Index].Loops[I]) then begin
          Skirt := OffsetPolygon(FLayers[Index].Loops[I], FSettings.SkirtDistance + K * W, jtRound, 2, 0.05);
          AddPath(FLayers[Index].Paths, prSkirt, Skirt, True);
        end;
  // perimetros: internos primeiro (precisao dimensional), externo por ultimo
  for K := FSettings.Walls - 1 downto 0 do begin
    D := W / 2 + K * W;
    Ring := InsetLoops(FLayers[Index].Loops, D);
    for I := 0 to High(Ring) do
      if K = 0 then AddPath(FLayers[Index].Paths, prOuterWall, Ring[I], True)
      else AddPath(FLayers[Index].Paths, prInnerWall, Ring[I], True);
  end;
end;

{ Divide uma polilinha em trechos que satisfazem (Keep=True) ou nao o teste,
  amostrando a cada Step mm. }
type TPointTest = function(const P: TPoint2D): Boolean of object;

function SplitByTest(const Line: TPolygon2D; Step: Double; Test: TPointTest; Want: Boolean): TPolygons2D;
var I, K, Sub, N, Cnt: Integer; A, B, P0, P1, M: TPoint2D; L: Double; Cur: TPolygon2D;
  procedure Flush;
  begin
    if Cnt >= 2 then begin
      SetLength(Cur, Cnt);
      SetLength(Result, N + 1);
      Result[N] := Cur;
      Inc(N);
    end;
    Cur := nil;
    Cnt := 0;
  end;
  procedure Add(const P: TPoint2D);
  begin
    if (Cnt > 0) and (Abs(Cur[Cnt - 1].X - P.X) < 1e-12) and (Abs(Cur[Cnt - 1].Y - P.Y) < 1e-12) then Exit;
    if Cnt >= Length(Cur) then SetLength(Cur, Max(16, Cnt * 2));
    Cur[Cnt] := P;
    Inc(Cnt);
  end;
begin
  SetLength(Result, 0);
  N := 0; Cnt := 0; Cur := nil;
  for I := 1 to High(Line) do begin
    A := Line[I - 1]; B := Line[I];
    L := Hypot(B.X - A.X, B.Y - A.Y);
    Sub := Max(1, Ceil(L / Step));
    for K := 0 to Sub - 1 do begin
      P0 := Pt(A.X + (B.X - A.X) * K / Sub, A.Y + (B.Y - A.Y) * K / Sub);
      P1 := Pt(A.X + (B.X - A.X) * (K + 1) / Sub, A.Y + (B.Y - A.Y) * (K + 1) / Sub);
      M := Pt((P0.X + P1.X) / 2, (P0.Y + P1.Y) / 2);
      if Test(M) = Want then begin Add(P0); Add(P1); end else Flush;
    end;
  end;
  Flush;
end;

type
  TSolidTester = class
    Layers: ^TLayerDataArray;
    Index, Top, Bottom: Integer;
    function NeedsSolid(const P: TPoint2D): Boolean;
  end;

function TSolidTester.NeedsSolid(const P: TPoint2D): Boolean;
var K: Integer;
begin
  // solido se nao houver material acima/abaixo dentro de Top/Bottom camadas
  Result := True;
  if (Index < Bottom) or (Index > High(Layers^) - Top) then Exit;
  for K := Index - Bottom to Index - 1 do
    if not PointInPolygons(P, Layers^[K].Loops) then Exit;
  for K := Index + 1 to Index + Top do
    if not PointInPolygons(P, Layers^[K].Loops) then Exit;
  Result := False;
end;

procedure TModernSlicer.BuildInfill(Index: Integer);
var
  Region, Lines, Pieces: TPolygons2D;
  W: Double;
  I, K: Integer;
  Tester: TSolidTester;
begin
  W := FSettings.LineWidth;
  // borda do preenchimento sobrepoe 25% da largura no perimetro interno
  Region := InsetLoops(FLayers[Index].Loops, FSettings.Walls * W - 0.25 * W + W / 2);
  FLayers[Index].InfillRegion := Region;
  if Length(Region) = 0 then Exit;
  Tester := TSolidTester.Create;
  try
    Tester.Layers := @FLayers;
    Tester.Index := Index;
    Tester.Top := FSettings.TopLayers;
    Tester.Bottom := FSettings.BottomLayers;
    // camadas solidas: retilineo 100% com angulo alternado +-45 graus
    if Odd(Index) then Lines := RectilinearInfill(Region, 45, W)
    else Lines := RectilinearInfill(Region, -45, W);
    for I := 0 to High(Lines) do begin
      Pieces := SplitByTest(Lines[I], Max(W * 2, 1), @Tester.NeedsSolid, True);
      for K := 0 to High(Pieces) do AddPath(FLayers[Index].Paths, prSolidInfill, Pieces[K], False);
    end;
    // preenchimento esparso onde nao for solido
    if FSettings.InfillDensity > 0.001 then begin
      if FSettings.InfillPattern = ipGyroid then
        Lines := GyroidInfill(Region, FLayers[Index].Z, W / Min(FSettings.InfillDensity, 1), 0.3)
      else if Odd(Index) then
        Lines := RectilinearInfill(Region, 45, W / Min(FSettings.InfillDensity, 1))
      else
        Lines := RectilinearInfill(Region, -45, W / Min(FSettings.InfillDensity, 1));
      for I := 0 to High(Lines) do begin
        Pieces := SplitByTest(Lines[I], Max(W * 2, 1), @Tester.NeedsSolid, False);
        for K := 0 to High(Pieces) do
          if PolygonPerimeter(Pieces[K], False) >= W then
            AddPath(FLayers[Index].Paths, prSparseInfill, Pieces[K], False);
      end;
    end;
  finally
    Tester.Free;
  end;
end;

{ Ordena caminhos por vizinho mais proximo; laços escolhem a costura. }
procedure OrderPaths(var Paths: TExtrusionPaths; var Cur: TPoint2D; RearSeam: Boolean);
var
  Done: array of Boolean;
  Res: TExtrusionPaths;
  I, K, Best, BestIdx, N: Integer;
  D, BestD: Double;
  BestRev: Boolean;
  P: TPolygon2D;
  Role: TPathRole;
  R: Integer;
const
  RoleOrder: array[0..4] of TPathRole = (prSkirt, prInnerWall, prOuterWall, prSolidInfill, prSparseInfill);
begin
  SetLength(Done, Length(Paths));
  SetLength(Res, 0);
  N := 0;
  for R := 0 to High(RoleOrder) do begin
    Role := RoleOrder[R];
    repeat
      Best := -1; BestD := MaxDouble; BestIdx := 0; BestRev := False;
      for I := 0 to High(Paths) do begin
        if Done[I] or (Paths[I].Role <> Role) then Continue;
        P := Paths[I].Points;
        if Paths[I].Closed then begin
          for K := 0 to High(P) do begin
            D := Sqr(P[K].X - Cur.X) + Sqr(P[K].Y - Cur.Y);
            if D < BestD then begin BestD := D; Best := I; BestIdx := K; end;
          end;
        end else begin
          D := Sqr(P[0].X - Cur.X) + Sqr(P[0].Y - Cur.Y);
          if D < BestD then begin BestD := D; Best := I; BestRev := False; end;
          D := Sqr(P[High(P)].X - Cur.X) + Sqr(P[High(P)].Y - Cur.Y);
          if D < BestD then begin BestD := D; Best := I; BestRev := True; end;
        end;
      end;
      if Best < 0 then Break;
      Done[Best] := True;
      P := Paths[Best].Points;
      if Paths[Best].Closed then begin
        if RearSeam and (Paths[Best].Role = prOuterWall) then begin
          // costura alinhada atras (maior Y): fica concentrada e discreta
          BestIdx := 0;
          for K := 1 to High(P) do
            if (P[K].Y > P[BestIdx].Y + 1e-6) or
              ((Abs(P[K].Y - P[BestIdx].Y) <= 1e-6) and (P[K].X < P[BestIdx].X)) then BestIdx := K;
        end;
        SetLength(Res, N + 1);
        Res[N] := Paths[Best];
        SetLength(Res[N].Points, Length(P));
        for K := 0 to High(P) do Res[N].Points[K] := P[(BestIdx + K) mod Length(P)];
        Cur := Res[N].Points[0];
      end else begin
        SetLength(Res, N + 1);
        Res[N] := Paths[Best];
        if BestRev then Res[N].Points := ReversePolygon(P);
        Cur := Res[N].Points[High(Res[N].Points)];
      end;
      Inc(N);
    until False;
  end;
  Paths := Res;
end;

type
  TGCodeWriter = class
    S: TSliceSettings;
    Out: TStrings;
    FS: TFormatSettings;
    X, Y, Z, F: Double;
    Retracted, Known: Boolean;
    Seconds, Filament: Double;
    Region: TPolygons2D;  // regiao de preenchimento da camada atual
    Retractions: Integer;
    LastG: Integer;
    function N(V: Double; D: Integer = 3): string;
    procedure SetF(Speed: Double; var L: string);
    function InsideRegion(TX, TY: Double): Boolean;
    procedure Travel(TX, TY: Double);
    procedure Extrude(TX, TY, E, Speed: Double);
    procedure ArcExtrude(Clockwise: Boolean; TX, TY, I, J, Len, E, Speed: Double);
    procedure Retract;
    procedure Unretract;
    procedure MoveZ(TZ: Double);
  end;

function TGCodeWriter.N(V: Double; D: Integer): string;
begin
  Result := FloatToStrF(V, ffFixed, 15, D, FS);
  if Pos('.', Result) > 0 then begin
    while Result[Length(Result)] = '0' do Delete(Result, Length(Result), 1);
    if Result[Length(Result)] = '.' then Delete(Result, Length(Result), 1);
  end;
  if Result = '-0' then Result := '0';
end;

procedure TGCodeWriter.SetF(Speed: Double; var L: string);
begin
  if Abs(Speed * 60 - F) > 0.5 then begin
    L := L + ' F' + IntToStr(Round(Speed * 60));
    F := Speed * 60;
  end;
end;

{ "Only retract when crossing perimeters": um deslocamento inteiramente dentro
  da regiao de preenchimento nao deixa fio visivel e dispensa retracao. }
function TGCodeWriter.InsideRegion(TX, TY: Double): Boolean;
var Seg: TPolygon2D; Pieces: TPolygons2D;
begin
  Result := False;
  if Length(Region) = 0 then Exit;
  SetLength(Seg, 2);
  Seg[0] := Pt(X, Y);
  Seg[1] := Pt(TX, TY);
  Pieces := ClipPolylineToRegion(Seg, Region);
  Result := (Length(Pieces) = 1) and
    (Abs(PolygonPerimeter(Pieces[0], False) - Hypot(TX - X, TY - Y)) < 1e-6);
end;

procedure TGCodeWriter.Travel(TX, TY: Double);
var D: Double; L: string;
begin
  D := Hypot(TX - X, TY - Y);
  if Known and (D < 1e-6) then Exit;
  if Known and (D >= S.RetractMinTravel) and not InsideRegion(TX, TY) then Retract;
  L := 'G0 X' + N(TX) + ' Y' + N(TY);
  SetF(S.TravelSpeed, L);
  Out.Add(L);
  Seconds := Seconds + D / S.TravelSpeed;
  X := TX; Y := TY; Known := True;
end;

procedure TGCodeWriter.Extrude(TX, TY, E, Speed: Double);
var L: string;
begin
  Unretract;
  L := 'G1 X' + N(TX) + ' Y' + N(TY) + ' E' + N(E, 5);
  SetF(Speed, L);
  Out.Add(L);
  Seconds := Seconds + Hypot(TX - X, TY - Y) / Speed;
  Filament := Filament + E;
  X := TX; Y := TY;
end;

procedure TGCodeWriter.ArcExtrude(Clockwise: Boolean; TX, TY, I, J, Len, E, Speed: Double);
var L: string;
begin
  Unretract;
  if Clockwise then L := 'G2' else L := 'G3';
  L := L + ' X' + N(TX) + ' Y' + N(TY) + ' I' + N(I) + ' J' + N(J) + ' E' + N(E, 5);
  SetF(Speed, L);
  Out.Add(L);
  Seconds := Seconds + Len / Speed;
  Filament := Filament + E;
  X := TX; Y := TY;
end;

procedure TGCodeWriter.Retract;
begin
  if Retracted or (S.RetractLength <= 0) then Exit;
  Out.Add('G1 E-' + N(S.RetractLength, 5) + ' F' + IntToStr(Round(S.RetractSpeed * 60)));
  Inc(Retractions);
  F := S.RetractSpeed * 60;
  Seconds := Seconds + S.RetractLength / S.RetractSpeed;
  if S.ZHop > 0 then Out.Add('G0 Z' + N(Z + S.ZHop));
  Retracted := True;
end;

procedure TGCodeWriter.Unretract;
begin
  if not Retracted then Exit;
  if S.ZHop > 0 then Out.Add('G0 Z' + N(Z));
  Out.Add('G1 E' + N(S.RetractLength, 5) + ' F' + IntToStr(Round(S.RetractSpeed * 60)));
  F := S.RetractSpeed * 60;
  Seconds := Seconds + S.RetractLength / S.RetractSpeed;
  Retracted := False;
end;

procedure TGCodeWriter.MoveZ(TZ: Double);
var L: string;
begin
  L := 'G0 Z' + N(TZ);
  SetF(S.TravelSpeed, L);
  Out.Add(L);
  Z := TZ;
end;

function TModernSlicer.Slice(Mesh: TMesh; const S: TSliceSettings; Output: TStrings): TSliceReport;
var
  Heights: TPolygon2D;
  I, K, P: Integer;
  W: TGCodeWriter;
  Body: TStringList;
  Cur: TPoint2D;
  Path: TExtrusionPath;
  Speed, EPM, Len, Sweep, A0, A1, MinX, MinY, MaxX, MaxY, TX, TY: Double;
  Fit: TFitMoves;
  AF: TArcFitOptions;
  Run: TPolygon2D;
  LayerTimes: array of Double;
  ObjName, Poly: string;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Warnings := '';
  FSettings := S;
  if FSettings.LineWidth <= 0 then FSettings.LineWidth := FSettings.Printer.Nozzle * 1.125;
  SetLength(FLayers, 0);
  if Mesh.Count = 0 then Exit;
  Heights := ComputeLayerHeights(Mesh, FSettings);
  SetLength(FLayers, Length(Heights));
  for I := 0 to High(Heights) do begin
    FLayers[I].Z := Heights[I].X;
    FLayers[I].Height := Heights[I].Y;
  end;
  for I := 0 to High(FLayers) do BuildLayer(I, Mesh);
  for I := 0 to High(FLayers) do BuildInfill(I);
  Result.Layers := Length(FLayers);
  Result.MinZ := Mesh.MinZ;
  Result.MaxZ := Mesh.MaxZ;
  // envelope da mesa
  MinX := MaxDouble; MinY := MaxDouble; MaxX := -MaxDouble; MaxY := -MaxDouble;
  for I := 0 to High(FLayers) do
    for K := 0 to High(FLayers[I].Loops) do
      for P := 0 to High(FLayers[I].Loops[K]) do begin
        MinX := Min(MinX, FLayers[I].Loops[K][P].X); MaxX := Max(MaxX, FLayers[I].Loops[K][P].X);
        MinY := Min(MinY, FLayers[I].Loops[K][P].Y); MaxY := Max(MaxY, FLayers[I].Loops[K][P].Y);
      end;
  if (MinX < 0) or (MinY < 0) or (MaxX > S.Printer.BedX) or (MaxY > S.Printer.BedY) or
    (Result.MaxZ > S.Printer.MaxZ) then
    Result.Warnings := Result.Warnings + 'Modelo fora do volume de impressao; ';

  AF := DefaultArcFitOptions;
  AF.Tolerance := 0.05; // resolucao usual de arc welders para FDM
  AF.MinRadius := 1;
  ObjName := StringReplace(FSettings.ObjectName, ' ', '_', [rfReplaceAll]);
  W := TGCodeWriter.Create;
  Body := TStringList.Create;
  try
    W.S := FSettings;
    W.Out := Body;
    W.FS := DefaultFormatSettings;
    W.FS.DecimalSeparator := '.';
    W.F := -1;
    SetLength(LayerTimes, Length(FLayers));
    Cur := Pt(0, 0);
    for I := 0 to High(FLayers) do begin
      Body.Add(';LAYER_CHANGE');
      Body.Add(Format(';LAYER:%d', [I]));
      Body.Add(';Z:' + W.N(FLayers[I].Z));
      Body.Add(';HEIGHT:' + W.N(FLayers[I].Height));
      Body.Add('{PROGRESS}');
      if S.Flavor = sfKlipper then Body.Add(Format('SET_PRINT_STATS_INFO CURRENT_LAYER=%d', [I + 1]));
      if I = S.FanFromLayer - 1 then Body.Add('M106 S255');
      W.Retract;
      W.MoveZ(FLayers[I].Z);
      if S.Flavor = sfKlipper then Body.Add('EXCLUDE_OBJECT_START NAME=' + ObjName)
      else Body.Add('M486 S0');
      OrderPaths(FLayers[I].Paths, Cur, True);
      EPM := ExtrusionPerMM(FSettings.LineWidth, FLayers[I].Height, S.Printer.FilamentDiameter);
      for P := 0 to High(FLayers[I].Paths) do begin
        Path := FLayers[I].Paths[P];
        if I = 0 then Speed := S.FirstLayerSpeed
        else case Path.Role of
          prOuterWall: Speed := S.OuterWallSpeed;
          prInnerWall, prSkirt: Speed := S.WallSpeed;
        else
          Speed := S.InfillSpeed;
        end;
        case Path.Role of
          prSkirt: Body.Add(';TYPE:Skirt');
          prOuterWall: Body.Add(';TYPE:External perimeter');
          prInnerWall: Body.Add(';TYPE:Perimeter');
          prSolidInfill: Body.Add(';TYPE:Solid infill');
          prSparseInfill: Body.Add(';TYPE:Internal infill');
        end;
        if Path.Role in [prSolidInfill, prSparseInfill] then W.Region := FLayers[I].InfillRegion
        else SetLength(W.Region, 0);
        W.Travel(Path.Points[0].X, Path.Points[0].Y);
        // fecha os lacos voltando ao primeiro ponto
        Run := Path.Points;
        if Path.Closed then begin
          SetLength(Run, Length(Run) + 1);
          Run[High(Run)] := Run[0];
        end;
        if S.ArcFitting and Path.Closed and (Length(Run) >= 5) then begin
          Fit := FitArcs(Run, AF);
          TX := Run[0].X; TY := Run[0].Y;
          for K := 0 to High(Fit) do begin
            if Fit[K].Kind = fmLine then begin
              Len := Hypot(Fit[K].X - TX, Fit[K].Y - TY);
              W.Extrude(Fit[K].X, Fit[K].Y, Len * EPM, Speed);
            end else begin
              A0 := ArcTan2(-Fit[K].J, -Fit[K].I);
              A1 := ArcTan2(Fit[K].Y - (TY + Fit[K].J), Fit[K].X - (TX + Fit[K].I));
              Sweep := A1 - A0;
              if Fit[K].Kind = fmArcCCW then begin
                while Sweep <= 0 do Sweep := Sweep + 2 * Pi;
              end else
                while Sweep >= 0 do Sweep := Sweep - 2 * Pi;
              Len := Abs(Sweep) * Fit[K].Radius;
              W.ArcExtrude(Fit[K].Kind = fmArcCW, Fit[K].X, Fit[K].Y, Fit[K].I, Fit[K].J, Len, Len * EPM, Speed);
            end;
            TX := Fit[K].X; TY := Fit[K].Y;
          end;
        end else
          for K := 1 to High(Run) do begin
            Len := Hypot(Run[K].X - Run[K - 1].X, Run[K].Y - Run[K - 1].Y);
            W.Extrude(Run[K].X, Run[K].Y, Len * EPM, Speed);
          end;
        Cur := Pt(W.X, W.Y);
      end;
      if S.Flavor = sfKlipper then Body.Add('EXCLUDE_OBJECT_END NAME=' + ObjName)
      else Body.Add('M486 S-1');
      LayerTimes[I] := W.Seconds;
    end;
    W.Retract;
    Result.EstimatedSeconds := W.Seconds;
    Result.Retractions := W.Retractions;
    Result.FilamentMM := W.Filament;
    Result.FilamentGrams := W.Filament * Pi * Sqr(S.Printer.FilamentDiameter / 2) / 1000 * S.FilamentDensity;

    Output.Clear;
    Output.Add('; generated by MultiSlicer (MultiCNC suite)');
    if S.Flavor = sfKlipper then Output.Add(';FLAVOR:Klipper') else Output.Add(';FLAVOR:Marlin');
    Output.Add(Format(';TIME:%d', [Round(Result.EstimatedSeconds)]));
    Output.Add(';Filament used: ' + W.N(Result.FilamentMM / 1000, 4) + 'm');
    Output.Add('; filament used [g] = ' + W.N(Result.FilamentGrams, 2));
    Output.Add(Format(';LAYER_COUNT:%d', [Result.Layers]));
    Output.Add(Format('; estimated printing time (normal mode) = %dh %dm %ds',
      [Round(Result.EstimatedSeconds) div 3600, (Round(Result.EstimatedSeconds) div 60) mod 60,
       Round(Result.EstimatedSeconds) mod 60]));
    Output.Add(';MINX:' + W.N(MinX) + ' MINY:' + W.N(MinY) + ' MAXX:' + W.N(MaxX) + ' MAXY:' + W.N(MaxY));
    Output.Add('; layer_height = ' + W.N(S.LayerHeight) + ', adaptive = ' + BoolToStr(S.Adaptive, 'yes', 'no'));
    Output.Add('; walls = ' + IntToStr(S.Walls) + ', infill = ' + W.N(S.InfillDensity * 100, 0) + '%');
    if S.Flavor = sfKlipper then begin
      // poligono do objeto (envelope) para EXCLUDE_OBJECT
      Poly := Format('[[%s,%s],[%s,%s],[%s,%s],[%s,%s]]',
        [W.N(MinX), W.N(MinY), W.N(MaxX), W.N(MinY), W.N(MaxX), W.N(MaxY), W.N(MinX), W.N(MaxY)]);
      Output.Add(Format('EXCLUDE_OBJECT_DEFINE NAME=%s CENTER=%s,%s POLYGON=%s',
        [ObjName, W.N((MinX + MaxX) / 2), W.N((MinY + MaxY) / 2), Poly]));
      Output.Add(Format('SET_PRINT_STATS_INFO TOTAL_LAYER=%d', [Result.Layers]));
    end else
      Output.Add('M486 T1');
    Output.Add('G21');
    Output.Add('G90');
    Output.Add('M83 ; extrusao relativa');
    Output.Add(Format('M140 S%d', [S.Printer.BedTemp]));
    Output.Add(Format('M104 S%d', [S.Printer.HotendTemp]));
    Output.Add('G28');
    Output.Add(Format('M190 S%d', [S.Printer.BedTemp]));
    Output.Add(Format('M109 S%d', [S.Printer.HotendTemp]));
    Output.Add('M107');
    if S.PressureAdvance > 0 then begin
      if S.Flavor = sfKlipper then Output.Add('SET_PRESSURE_ADVANCE ADVANCE=' + W.N(S.PressureAdvance, 4))
      else Output.Add('M900 K' + W.N(S.PressureAdvance, 4));
    end;
    Output.Add('G92 E0');
    // insere progresso M73 (percentual e minutos restantes)
    K := 0;
    for I := 0 to Body.Count - 1 do
      if Body[I] = '{PROGRESS}' then begin
        if K = 0 then Len := 0 else Len := LayerTimes[K - 1];
        if Result.EstimatedSeconds > 0 then
          Body[I] := Format('M73 P%d R%d', [Round(100 * Len / Result.EstimatedSeconds),
            Round((Result.EstimatedSeconds - Len) / 60)])
        else
          Body[I] := 'M73 P0';
        Inc(K);
      end;
    Output.AddStrings(Body);
    Output.Add('M73 P100 R0');
    if S.Flavor = sfMarlin then Output.Add('M486 S-1');
    Output.Add('M107');
    Output.Add('G91');
    Output.Add('G0 Z5');
    Output.Add('G90');
    Output.Add('M104 S0');
    Output.Add('M140 S0');
    Output.Add('M84');
  finally
    Body.Free;
    W.Free;
  end;
end;

end.
