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
  multislicer_support, multislicer_clip,
  multisuite_geometry, multisuite_arcfit;

type
  TSlicerFlavor = (sfMarlin, sfKlipper);
  TInfillPattern = (ipGyroid, ipRectilinear);
  TPathRole = (prSkirt, prOuterWall, prInnerWall, prSolidInfill, prSparseInfill,
    prSupport, prSupportInterface, prBrim, prRaft);
  { aderencia a mesa (como no Cura): nenhuma, saia, aba (brim) ou jangada (raft) }
  TAdhesionType = (adNone, adSkirt, adBrim, adRaft);

  { peca da cena, para rotular as trajetorias no G-code (cancelar uma peca) }
  TSliceObjectLabel = record
    Name: string;
    MinX, MinY, MaxX, MaxY: Double;
  end;
  TSliceObjectLabels = array of TSliceObjectLabel;

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
    // Etapa 2 (perfis de impressora e material)
    FirstLayerHotendTemp, FirstLayerBedTemp: Integer; // 0 = igual as demais camadas
    FanPercent: Integer;             // 0..100; 0 = ventoinha desligada
    FlowPercent: Double;             // multiplicador de extrusao (100 = nominal)
    HeatedBed: Boolean;              // False = sem M140/M190
    StartGCode, EndGCode: string;    // vazio = bloco padrao; aceita {variaveis}
    MaterialName: string;
    // Etapa 4: varias pecas. Vazio ou 1 = um rotulo so (ObjectName)
    Objects: TSliceObjectLabels;
    // Etapa 6: suportes e aderencia
    Support: TSupportParams;
    Adhesion: TAdhesionType;
    BrimWidth: Double;               // mm
    RaftMargin, RaftAirGap: Double;  // mm
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
    SupportPaths, BrimPaths, RaftLayers: Integer;
    { tempo de cada fase (ms), para medir desempenho }
    MSLayers, MSSupport, MSInfill, MSGCode: Int64;
  end;

  TLayerData = record
    Z, Height: Double;
    Loops: TPolygons2D;   // contornos (externos CCW, furos CW)
    InfillRegion: TPolygons2D;
    SupportRegion: TPolygons2D;
    Paths: TExtrusionPaths;
  end;
  TLayerDataArray = array of TLayerData;

  ESliceCanceled = class(Exception);

  TModernSlicer = class
  private
    FSettings: TSliceSettings;
    FLayers: TLayerDataArray;
    FModel: array of TPolygons2D;   { regiao da peca por camada (para topo/fundo) }
    { indice em Z: triangulos ordenados pelo Z minimo e a lista dos que cortam
      a altura atual (as camadas sobem, entao e uma varredura) }
    FTris: array of TTriangle;
    FTriMinZ, FTriMaxZ: array of Double;
    FActive: array of Integer;
    FActiveN, FNextTri: Integer;
    procedure PrepareZIndex(Mesh: TMesh);
    function SliceSweep(Z: Double): TPolygons2D;
    procedure Tick(Frac: Double; AStage: Integer);
    procedure BuildLayer(Index: Integer; Mesh: TMesh);
    procedure BuildInfill(Index: Integer);
    procedure BuildSupport;
    procedure BuildBrim;
    procedure BuildSkirt;
    function BuildRaft: Integer;
  public
    class function ComputeLayerHeights(Mesh: TMesh; const S: TSliceSettings): TPolygon2D; // X=Z topo, Y=altura
    class function SliceAt(Mesh: TMesh; Z: Double): TPolygons2D;
    class function ExtrusionPerMM(Width, Height, FilamentDiameter: Double): Double;
    function Slice(Mesh: TMesh; const S: TSliceSettings; Output: TStrings): TSliceReport;
    property Layers: TLayerDataArray read FLayers;
  public
    { andamento para a tela (o fatiamento roda numa thread): 0..1 e a fase
      0 camadas, 1 suportes, 2 preenchimento, 3 G-code. CancelRequested e
      ligado por outra thread; o Slice para com ESliceCanceled. }
    Progress: Double;
    Stage: Integer;
    CancelRequested: Boolean;
  end;

const
  SLICE_STAGE_NAMES: array[0..3] of string = ('Cortando camadas', 'Calculando suportes',
    'Preenchimento', 'Gerando G-code');

function DefaultSliceSettings: TSliceSettings;
function ExpandGCodeTemplate(const Template: string; const S: TSliceSettings): string;
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
  Result.FirstLayerHotendTemp := 0;
  Result.FirstLayerBedTemp := 0;
  Result.FanPercent := 100;
  Result.FlowPercent := 100;
  Result.HeatedBed := True;
  Result.StartGCode := '';
  Result.EndGCode := '';
  Result.MaterialName := '';
  SetLength(Result.Objects, 0);
  Result.Support := DefaultSupportParams;
  Result.Adhesion := adSkirt;
  Result.BrimWidth := 8;
  Result.RaftMargin := 3;
  Result.RaftAirGap := 0.2;
end;

function FirstHotend(const S: TSliceSettings): Integer;
begin
  if S.FirstLayerHotendTemp > 0 then Result := S.FirstLayerHotendTemp else Result := S.Printer.HotendTemp;
end;

function FirstBed(const S: TSliceSettings): Integer;
begin
  if S.FirstLayerBedTemp > 0 then Result := S.FirstLayerBedTemp else Result := S.Printer.BedTemp;
end;

function FanPWM(const S: TSliceSettings): Integer;
begin
  Result := Round(255 * EnsureRange(S.FanPercent, 0, 100) / 100);
end;

function ExpandGCodeTemplate(const Template: string; const S: TSliceSettings): string;
var FS: TFormatSettings;
  procedure Sub(const Key, Value: string);
  begin
    Result := StringReplace(Result, '{' + Key + '}', Value, [rfReplaceAll, rfIgnoreCase]);
  end;
begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  Result := Template;
  Sub('first_layer_bed_temp', IntToStr(FirstBed(S)));
  Sub('first_layer_hotend_temp', IntToStr(FirstHotend(S)));
  Sub('bed_temp', IntToStr(S.Printer.BedTemp));
  Sub('hotend_temp', IntToStr(S.Printer.HotendTemp));
  Sub('bed_x', FormatFloat('0.###', S.Printer.BedX, FS));
  Sub('bed_y', FormatFloat('0.###', S.Printer.BedY, FS));
  Sub('bed_z', FormatFloat('0.###', S.Printer.MaxZ, FS));
  Sub('fan_speed', IntToStr(FanPWM(S)));
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

procedure CutTriangle(const T: TTriangle; Z: Double; var Segs: TSegments2D; var N: Integer); inline;
var V: array[0..2] of TVec3; P: array[0..1] of TPoint2D; K, J: Integer; A, B: TVec3;
begin
  V[0] := T.A; V[1] := T.B; V[2] := T.C;
  K := 0;
  for J := 0 to 2 do
    if (K < 2) and ((V[J].Z - Z) * (V[(J + 1) mod 3].Z - Z) < 0) then begin
      A := V[J]; B := V[(J + 1) mod 3];
      P[K] := Pt(A.X + (Z - A.Z) / (B.Z - A.Z) * (B.X - A.X), A.Y + (Z - A.Z) / (B.Z - A.Z) * (B.Y - A.Y));
      Inc(K);
    end;
  if K = 2 then begin
    if N >= Length(Segs) then SetLength(Segs, Max(256, N * 2));
    Segs[N].A := P[0];
    Segs[N].B := P[1];
    Inc(N);
  end;
end;

procedure TModernSlicer.PrepareZIndex(Mesh: TMesh);
var I, N: Integer; T: TTriangle; Keys: array of Double; Idx: array of Integer;

  procedure Sort(L, R: Integer);
  var I, J, Tmp: Integer; P: Double;
  begin
    repeat
      I := L; J := R; P := Keys[Idx[(L + R) shr 1]];
      repeat
        while Keys[Idx[I]] < P do Inc(I);
        while Keys[Idx[J]] > P do Dec(J);
        if I <= J then begin
          Tmp := Idx[I]; Idx[I] := Idx[J]; Idx[J] := Tmp;
          Inc(I); Dec(J);
        end;
      until I > J;
      if L < J then Sort(L, J);
      L := I;
    until I >= R;
  end;

begin
  N := Mesh.Count;
  SetLength(Keys, N); SetLength(Idx, N);
  for I := 0 to N - 1 do begin
    T := Mesh.Triangle(I);
    Keys[I] := Min(T.A.Z, Min(T.B.Z, T.C.Z));
    Idx[I] := I;
  end;
  if N > 1 then Sort(0, N - 1);
  SetLength(FTris, N); SetLength(FTriMinZ, N); SetLength(FTriMaxZ, N);
  for I := 0 to N - 1 do begin
    T := Mesh.Triangle(Idx[I]);
    FTris[I] := T;
    FTriMinZ[I] := Keys[Idx[I]];
    FTriMaxZ[I] := Max(T.A.Z, Max(T.B.Z, T.C.Z));
  end;
  SetLength(FActive, 0);
  FActiveN := 0;
  FNextTri := 0;
end;

function TModernSlicer.SliceSweep(Z: Double): TPolygons2D;
var I, K, N: Integer; Segs: TSegments2D;
begin
  Z := Z + 1e-7;   { igual ao SliceAt: evita vertices exatamente no plano }
  { entram os que comecam abaixo de Z }
  while (FNextTri <= High(FTris)) and (FTriMinZ[FNextTri] < Z) do begin
    if FActiveN >= Length(FActive) then SetLength(FActive, Max(1024, FActiveN * 2));
    FActive[FActiveN] := FNextTri;
    Inc(FActiveN);
    Inc(FNextTri);
  end;
  { saem os que terminam abaixo de Z; os outros sao cortados }
  Segs := nil; N := 0; K := 0;
  for I := 0 to FActiveN - 1 do
    if FTriMaxZ[FActive[I]] > Z then begin
      FActive[K] := FActive[I];
      Inc(K);
      CutTriangle(FTris[FActive[I]], Z, Segs, N);
    end;
  FActiveN := K;
  SetLength(Segs, N);
  Result := ChainSegments(Segs, 1e-4);
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

procedure AddPath(var Paths: TExtrusionPaths; Role: TPathRole; const P: TPolygon2D; Closed: Boolean;
  Tol: Double = 1e-4);
var N: Integer;
begin
  if Length(P) < 2 then Exit;
  N := Length(Paths);
  SetLength(Paths, N + 1);
  Paths[N].Role := Role;
  if Closed then Paths[N].Points := P else Paths[N].Points := SimplifyOpen(P, Tol);
  Paths[N].Closed := Closed;
end;

procedure TModernSlicer.BuildLayer(Index: Integer; Mesh: TMesh);
var
  W, D: Double;
  K, I: Integer;
  Ring: TPolygons2D;
begin
  W := FSettings.LineWidth;
  FLayers[Index].Loops := SliceSweep(FLayers[Index].Z - FLayers[Index].Height / 2);
  { regiao da peca (Clipper): contornos que se tocam viram um so e as paredes
    nao se sobrepoem quando o recuo fecha um estreitamento }
  FModel[Index] := RegionUnionAll(FLayers[Index].Loops);
  SetLength(FLayers[Index].Paths, 0);
  // a saia e feita depois do suporte (BuildSkirt), para envolver os dois
  // perimetros: internos primeiro (precisao dimensional), externo por ultimo
  for K := FSettings.Walls - 1 downto 0 do begin
    D := W / 2 + K * W;
    Ring := RegionOffsetMiter(FModel[Index], -D);
    for I := 0 to High(Ring) do
      if K = 0 then AddPath(FLayers[Index].Paths, prOuterWall, Ring[I], True)
      else AddPath(FLayers[Index].Paths, prInnerWall, Ring[I], True);
  end;
end;

procedure TModernSlicer.BuildInfill(Index: Integer);
var
  Region, Interior, Solid, Sparse, Lines: TPolygons2D;
  W: Double;
  I, K, T, B: Integer;
begin
  W := FSettings.LineWidth;
  // borda do preenchimento sobrepoe 25% da largura no perimetro interno
  Region := RegionOffsetMiter(FModel[Index], -(FSettings.Walls * W - 0.25 * W + W / 2));
  FLayers[Index].InfillRegion := Region;
  if Length(Region) = 0 then Exit;
  { solido onde nao ha peca em todas as Top camadas de cima e Bottom de baixo
    (por regioes: interior = intersecao das camadas vizinhas) }
  T := FSettings.TopLayers; B := FSettings.BottomLayers;
  Interior := nil;
  if (Index >= B) and (Index <= High(FLayers) - T) then
  begin
    Interior := Region;
    for K := Index - B to Index + T do
    begin
      if K = Index then Continue;
      Interior := RegionIntersect(Interior, FModel[K]);
      if Length(Interior) = 0 then Break;
    end;
  end;
  if Length(Interior) = 0 then
  begin
    Solid := Region;
    Sparse := nil;
  end
  else
  begin
    Solid := RegionDifference(Region, Interior);
    Sparse := Interior;
  end;
  // camadas solidas: retilineo 100% com angulo alternado +-45 graus
  if Length(Solid) > 0 then
  begin
    if Odd(Index) then Lines := RectilinearInfill(Solid, 45, W)
    else Lines := RectilinearInfill(Solid, -45, W);
    for I := 0 to High(Lines) do
      if PolygonPerimeter(Lines[I], False) >= W * 0.5 then
        AddPath(FLayers[Index].Paths, prSolidInfill, Lines[I], False);
  end;
  // preenchimento esparso no interior
  if (Length(Sparse) > 0) and (FSettings.InfillDensity > 0.001) then
  begin
    if FSettings.InfillPattern = ipGyroid then
      Lines := GyroidInfill(Sparse, FLayers[Index].Z, W / Min(FSettings.InfillDensity, 1), 0.3)
    else if Odd(Index) then
      Lines := RectilinearInfill(Sparse, 45, W / Min(FSettings.InfillDensity, 1))
    else
      Lines := RectilinearInfill(Sparse, -45, W / Min(FSettings.InfillDensity, 1));
    for I := 0 to High(Lines) do
      if PolygonPerimeter(Lines[I], False) >= W then
        { o gyroid sai amostrado a cada 0,3 mm: desvio de 0,02 mm (como o
          "maximum deviation" do Cura) corta muitas linhas do G-code }
        AddPath(FLayers[Index].Paths, prSparseInfill, Lines[I], False, 0.02);
  end;
end;

{ Linhas de preenchimento de uma regiao, descartando pedacos muito curtos. }
procedure AddLines(var Paths: TExtrusionPaths; Role: TPathRole; const Region: TPolygons2D;
  AngleDeg, Spacing, MinLen: Double);
var Lines: TPolygons2D; I: Integer;
begin
  if Length(Region) = 0 then Exit;
  Lines := RectilinearInfill(Region, AngleDeg, Spacing);
  for I := 0 to High(Lines) do
    if PolygonPerimeter(Lines[I], False) >= MinLen then AddPath(Paths, Role, Lines[I], False);
end;

procedure TModernSlicer.BuildSupport;
var
  Loops: array of TPolygons2D; Zs, Hs: array of Double; Reg, Ifc: TLayerRegions;
  I, N: Integer; W, Dens, IDens, Ang: Double; Base: TPolygons2D;
begin
  N := Length(FLayers);
  if (N = 0) or (FSettings.Support.Mode = spOff) then Exit;
  W := FSettings.LineWidth;
  SetLength(Loops, N); SetLength(Zs, N); SetLength(Hs, N);
  for I := 0 to N - 1 do
  begin
    Loops[I] := FLayers[I].Loops;
    Zs[I] := FLayers[I].Z;
    Hs[I] := FLayers[I].Height;
  end;
  ComputeSupport(Loops, Zs, Hs, FSettings.Support, W, FSettings.LayerHeight, Reg, Ifc);
  Dens := EnsureRange(FSettings.Support.Density, 0.03, 1);
  IDens := EnsureRange(FSettings.Support.InterfaceDensity, 0.05, 1);
  for I := 0 to N - 1 do
  begin
    if Length(Reg[I]) = 0 then Continue;
    FLayers[I].SupportRegion := Reg[I];
    { linhas cruzadas camada a camada (0 / 90 graus) deixam a coluna firme }
    if Odd(I) then Ang := 90 else Ang := 0;
    Base := RegionDifference(Reg[I], Ifc[I]);
    AddLines(FLayers[I].Paths, prSupport, Base, Ang, W / Dens, W * 2);
    if Length(Ifc[I]) > 0 then
      AddLines(FLayers[I].Paths, prSupportInterface, Ifc[I], Ang + 45, W / IDens, W);
  end;
end;

procedure TModernSlicer.BuildSkirt;
var Base, Ring: TPolygons2D; K, J: Integer; W: Double;
begin
  if (Length(FLayers) = 0) or (FSettings.Adhesion <> adSkirt) or (FSettings.SkirtLoops <= 0) then Exit;
  W := FSettings.LineWidth;
  { contorno da 1a camada da peca e do suporte: a saia nao cruza o suporte }
  Base := RegionUnion(RegionOuter(RegionUnionAll(FLayers[0].Loops)), FLayers[0].SupportRegion);
  for K := 0 to FSettings.SkirtLoops - 1 do
  begin
    Ring := RegionOuter(RegionOffset(Base, FSettings.SkirtDistance + K * W));
    for J := 0 to High(Ring) do AddPath(FLayers[0].Paths, prSkirt, Ring[J], True);
  end;
end;

procedure TModernSlicer.BuildBrim;
var Base, Ring: TPolygons2D; K, J, Loops: Integer; W: Double;
begin
  if (Length(FLayers) = 0) or (FSettings.Adhesion <> adBrim) or (FSettings.BrimWidth <= 0) then Exit;
  W := FSettings.LineWidth;
  { aba so por fora: contornos externos da 1a camada e o suporte dela }
  Base := RegionUnion(RegionOuter(RegionUnionAll(FLayers[0].Loops)), FLayers[0].SupportRegion);
  Loops := Max(1, Ceil(FSettings.BrimWidth / W));
  for K := 0 to Loops - 1 do
  begin
    Ring := RegionOuter(RegionOffset(Base, W / 2 + K * W));
    for J := 0 to High(Ring) do AddPath(FLayers[0].Paths, prBrim, Ring[J], True);
  end;
end;

function TModernSlicer.BuildRaft: Integer;
const
  BASE_H = 0.3; MID_H = 0.25;
var
  Region, Edge: TPolygons2D; Raft: TLayerDataArray; I, J, NR: Integer; W, TopH, Total, Zc: Double;
begin
  Result := 0;
  if (Length(FLayers) = 0) or (FSettings.Adhesion <> adRaft) then Exit;
  W := FSettings.LineWidth;
  Region := RegionOffset(RegionUnion(RegionUnionAll(FLayers[0].Loops), FLayers[0].SupportRegion),
    Max(1, FSettings.RaftMargin));
  if Length(Region) = 0 then Exit;
  TopH := FSettings.LayerHeight;
  NR := 4;   { base grossa, meio, dois de topo solidos }
  SetLength(Raft, NR);
  Zc := 0;
  for I := 0 to NR - 1 do
  begin
    case I of
      0: Raft[I].Height := BASE_H;
      1: Raft[I].Height := MID_H;
    else
      Raft[I].Height := TopH;
    end;
    Zc := Zc + Raft[I].Height;
    Raft[I].Z := Zc;
    Raft[I].Loops := Region;
    Raft[I].InfillRegion := Region;
    SetLength(Raft[I].Paths, 0);
    case I of
      0: begin
           { base: contorno + linhas espacadas, gruda bem na mesa }
           for J := 0 to High(Region) do
             if PolygonArea(Region[J]) > 0 then
             begin
               Edge := RegionOffset(Region, -W / 2);
               Break;
             end;
           for J := 0 to High(Edge) do AddPath(Raft[I].Paths, prRaft, Edge[J], True);
           AddLines(Raft[I].Paths, prRaft, RegionOffset(Region, -W), 0, W * 3, W);
         end;
      1: AddLines(Raft[I].Paths, prRaft, RegionOffset(Region, -W / 2), 90, W * 1.6, W);
    else
      if Odd(I) then AddLines(Raft[I].Paths, prRaft, RegionOffset(Region, -W / 2), 45, W, W)
      else AddLines(Raft[I].Paths, prRaft, RegionOffset(Region, -W / 2), -45, W, W);
    end;
  end;
  { a peca sobe a altura da jangada + a folga de ar (descola facil) }
  Total := Zc + Max(0, FSettings.RaftAirGap);
  for I := 0 to High(FLayers) do FLayers[I].Z := FLayers[I].Z + Total;
  SetLength(Raft, NR + Length(FLayers));
  for I := 0 to High(FLayers) do Raft[NR + I] := FLayers[I];
  FLayers := Raft;
  Result := NR;
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
  RoleOrder: array[0..8] of TPathRole = (prRaft, prSkirt, prBrim, prSupport, prSupportInterface,
    prInnerWall, prOuterWall, prSolidInfill, prSparseInfill);
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

procedure TModernSlicer.Tick(Frac: Double; AStage: Integer);
begin
  if CancelRequested then raise ESliceCanceled.Create('Fatiamento cancelado.');
  Progress := EnsureRange(Frac, 0, 1);
  Stage := AStage;
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
  NObj, G: Integer;
  T0: QWord;
  ObjNames: array of string;
  Groups: array of TExtrusionPaths;   { [0] = sem peca (saia); [k+1] = peca k }
  Joined: TExtrusionPaths;

  { peca de uma trajetoria: a caixa (com folga) que contem o primeiro ponto;
    se nenhuma, a de centro mais proximo. A saia nao pertence a peca. }
  function ObjectOf(const Pa: TExtrusionPath): Integer;
  var J: Integer; X, Y, D, BestD: Double;
  begin
    Result := -1;
    if (Pa.Role in [prSkirt, prBrim, prRaft, prSupport, prSupportInterface]) or (Length(Pa.Points) = 0) then Exit;
    X := Pa.Points[0].X; Y := Pa.Points[0].Y;
    for J := 0 to NObj - 1 do
      with S.Objects[J] do
        if (X >= MinX - 2) and (X <= MaxX + 2) and (Y >= MinY - 2) and (Y <= MaxY + 2) then Exit(J);
    BestD := MaxDouble;
    for J := 0 to NObj - 1 do
      with S.Objects[J] do
      begin
        D := Sqr(X - (MinX + MaxX) / 2) + Sqr(Y - (MinY + MaxY) / 2);
        if D < BestD then begin BestD := D; Result := J; end;
      end;
  end;

  procedure LabelStart(K: Integer);
  begin
    if S.Flavor = sfKlipper then Body.Add('EXCLUDE_OBJECT_START NAME=' + ObjNames[K])
    else Body.Add(Format('M486 S%d', [K]));
  end;

  procedure LabelEnd(K: Integer);
  begin
    if S.Flavor = sfKlipper then Body.Add('EXCLUDE_OBJECT_END NAME=' + ObjNames[K])
    else Body.Add('M486 S-1');
  end;

  { ordena e escreve uma lista de trajetorias da camada I }
  procedure EmitList(var L: TExtrusionPaths);
  var Q, KK: Integer;
  begin
    if Length(L) = 0 then Exit;
    OrderPaths(L, Cur, True);
    for Q := 0 to High(L) do begin
      Path := L[Q];
      if I = 0 then Speed := S.FirstLayerSpeed
      else case Path.Role of
        prOuterWall: Speed := S.OuterWallSpeed;
        prInnerWall, prSkirt, prBrim: Speed := S.WallSpeed;
        prSupport, prSupportInterface:
          if S.Support.Speed > 0 then Speed := S.Support.Speed else Speed := S.InfillSpeed;
      else
        Speed := S.InfillSpeed;
      end;
      case Path.Role of
        prSkirt, prBrim: Body.Add(';TYPE:Skirt/Brim');
        prOuterWall: Body.Add(';TYPE:External perimeter');
        prInnerWall: Body.Add(';TYPE:Perimeter');
        prSolidInfill: Body.Add(';TYPE:Solid infill');
        prSparseInfill: Body.Add(';TYPE:Internal infill');
        prSupport: Body.Add(';TYPE:Support material');
        prSupportInterface: Body.Add(';TYPE:Support material interface');
        prRaft: Body.Add(';TYPE:Raft');
      end;
      { deslocamento dentro da propria regiao nao precisa retrair }
      if Path.Role in [prSolidInfill, prSparseInfill, prRaft] then W.Region := FLayers[I].InfillRegion
      else if Path.Role in [prSupport, prSupportInterface] then W.Region := FLayers[I].SupportRegion
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
        for KK := 0 to High(Fit) do begin
          if Fit[KK].Kind = fmLine then begin
            Len := Hypot(Fit[KK].X - TX, Fit[KK].Y - TY);
            W.Extrude(Fit[KK].X, Fit[KK].Y, Len * EPM, Speed);
          end else begin
            A0 := ArcTan2(-Fit[KK].J, -Fit[KK].I);
            A1 := ArcTan2(Fit[KK].Y - (TY + Fit[KK].J), Fit[KK].X - (TX + Fit[KK].I));
            Sweep := A1 - A0;
            if Fit[KK].Kind = fmArcCCW then begin
              while Sweep <= 0 do Sweep := Sweep + 2 * Pi;
            end else
              while Sweep >= 0 do Sweep := Sweep - 2 * Pi;
            Len := Abs(Sweep) * Fit[KK].Radius;
            W.ArcExtrude(Fit[KK].Kind = fmArcCW, Fit[KK].X, Fit[KK].Y, Fit[KK].I, Fit[KK].J, Len, Len * EPM, Speed);
          end;
          TX := Fit[KK].X; TY := Fit[KK].Y;
        end;
      end else
        for KK := 1 to High(Run) do begin
          Len := Hypot(Run[KK].X - Run[KK - 1].X, Run[KK].Y - Run[KK - 1].Y);
          W.Extrude(Run[KK].X, Run[KK].Y, Len * EPM, Speed);
        end;
      Cur := Pt(W.X, W.Y);
    end;
  end;

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
  T0 := GetTickCount64;
  PrepareZIndex(Mesh);
  SetLength(FModel, Length(FLayers));
  for I := 0 to High(FLayers) do
  begin
    Tick(0.35 * I / Length(FLayers), 0);
    BuildLayer(I, Mesh);
  end;
  FTris := nil; FTriMinZ := nil; FTriMaxZ := nil; FActive := nil;
  Tick(0.35, 1);
  Result.MSLayers := GetTickCount64 - T0; T0 := GetTickCount64;
  BuildSupport;
  Result.MSSupport := GetTickCount64 - T0; T0 := GetTickCount64;
  for I := 0 to High(FLayers) do
  begin
    Tick(0.45 + 0.35 * I / Length(FLayers), 2);
    BuildInfill(I);
  end;
  Tick(0.8, 3);
  Result.MSInfill := GetTickCount64 - T0;
  BuildSkirt;
  BuildBrim;
  Result.RaftLayers := BuildRaft;
  Result.Layers := Length(FLayers);
  for I := 0 to High(FLayers) do
    for K := 0 to High(FLayers[I].Paths) do
      case FLayers[I].Paths[K].Role of
        prSupport, prSupportInterface: Inc(Result.SupportPaths);
        prBrim: Inc(Result.BrimPaths);
      end;
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
  NObj := Length(S.Objects);
  if NObj <= 1 then begin
    SetLength(ObjNames, 1);
    if NObj = 1 then ObjNames[0] := StringReplace(S.Objects[0].Name, ' ', '_', [rfReplaceAll])
    else ObjNames[0] := ObjName;
    if ObjNames[0] = '' then ObjNames[0] := 'objeto';
  end else begin
    { nomes sem espaco e unicos (o Klipper cancela pelo nome) }
    SetLength(ObjNames, NObj);
    for K := 0 to NObj - 1 do begin
      ObjNames[K] := StringReplace(S.Objects[K].Name, ' ', '_', [rfReplaceAll]);
      if ObjNames[K] = '' then ObjNames[K] := 'objeto';
      ObjNames[K] := ObjNames[K] + '_' + IntToStr(K + 1);
    end;
  end;
  T0 := GetTickCount64;
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
      Tick(0.8 + 0.2 * I / Length(FLayers), 3);
      Body.Add(';LAYER_CHANGE');
      Body.Add(Format(';LAYER:%d', [I]));
      Body.Add(';Z:' + W.N(FLayers[I].Z));
      Body.Add(';HEIGHT:' + W.N(FLayers[I].Height));
      Body.Add('{PROGRESS}');
      if S.Flavor = sfKlipper then Body.Add(Format('SET_PRINT_STATS_INFO CURRENT_LAYER=%d', [I + 1]));
      if (I = S.FanFromLayer - 1) and (S.FanPercent > 0) then Body.Add(Format('M106 S%d', [FanPWM(S)]));
      if (I = 1) and (FirstHotend(S) <> S.Printer.HotendTemp) then
        Body.Add(Format('M104 S%d', [S.Printer.HotendTemp]));
      if (I = 1) and S.HeatedBed and (FirstBed(S) <> S.Printer.BedTemp) then
        Body.Add(Format('M140 S%d', [S.Printer.BedTemp]));
      W.Retract;
      W.MoveZ(FLayers[I].Z);
      EPM := ExtrusionPerMM(FSettings.LineWidth, FLayers[I].Height, S.Printer.FilamentDiameter);
      if S.FlowPercent > 0 then EPM := EPM * S.FlowPercent / 100;
      if NObj <= 1 then begin
        LabelStart(0);
        EmitList(FLayers[I].Paths);
        LabelEnd(0);
      end else begin
        { agrupa por peca: saia primeiro (sem rotulo), depois cada peca entre rotulos }
        SetLength(Groups, 0);
        SetLength(Groups, NObj + 1);
        for P := 0 to High(FLayers[I].Paths) do begin
          G := ObjectOf(FLayers[I].Paths[P]) + 1;
          SetLength(Groups[G], Length(Groups[G]) + 1);
          Groups[G][High(Groups[G])] := FLayers[I].Paths[P];
        end;
        EmitList(Groups[0]);
        for G := 1 to NObj do
          if Length(Groups[G]) > 0 then begin
            LabelStart(G - 1);
            EmitList(Groups[G]);
            LabelEnd(G - 1);
          end;
        { a previa mostra a mesma ordem do G-code }
        SetLength(Joined, 0);
        for G := 0 to NObj do
          for P := 0 to High(Groups[G]) do begin
            SetLength(Joined, Length(Joined) + 1);
            Joined[High(Joined)] := Groups[G][P];
          end;
        FLayers[I].Paths := Joined;
      end;
      LayerTimes[I] := W.Seconds;
    end;
    W.Retract;
    Result.EstimatedSeconds := W.Seconds;
    Result.Retractions := W.Retractions;
    Result.FilamentMM := W.Filament;
    Result.FilamentGrams := W.Filament * Pi * Sqr(S.Printer.FilamentDiameter / 2) / 1000 * S.FilamentDensity;

    Output.Clear;
    { contrato da suite (docs/CONTRATO_GCODE.md): linha 1 diz quem gerou e para
      qual maquina; as linhas "; MS-..." sao lidas pelo MultiCNC
      (SuiteParseHeader). Depois vem o cabecalho que OctoPrint/Moonraker/Cura leem. }
    Output.Add('; MultiSlicer -> MultiCNC (Impressora 3D)');
    Output.Add('; MS-CONTRACT: 1');
    Output.Add('; MS-MACHINE: printer3d');
    if Length(FLayers) > 0 then
      Output.Add('; MS-BOUNDS: X0=' + W.N(MinX) + ' X1=' + W.N(MaxX) + ' Y0=' + W.N(MinY) +
        ' Y1=' + W.N(MaxY) + ' Z0=0 Z1=' + W.N(FLayers[High(FLayers)].Z));
    if S.Printer.Name <> '' then Output.Add(Copy('; MS-PRINTER: ' + S.Printer.Name, 1, 127));
    if S.MaterialName <> '' then Output.Add(Copy('; MS-MATERIAL: ' + S.MaterialName, 1, 127));
    Output.Add(Format('; MS-TEMP: HOTEND=%d BED=%d FIRST_HOTEND=%d FIRST_BED=%d',
      [S.Printer.HotendTemp, IfThen(S.HeatedBed, S.Printer.BedTemp, 0), FirstHotend(S),
       IfThen(S.HeatedBed, FirstBed(S), 0)]));
    Output.Add(Format('; MS-PRINT: TIME=%d LAYERS=%d FILAMENT_M=%s FILAMENT_G=%s',
      [Round(Result.EstimatedSeconds), Result.Layers, W.N(Result.FilamentMM / 1000, 3),
       W.N(Result.FilamentGrams, 2)]));
    if FSettings.ObjectName <> '' then Output.Add(Copy('; ' + FSettings.ObjectName, 1, 127));
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
    if S.Printer.Name <> '' then Output.Add('; printer = ' + S.Printer.Name);
    if S.MaterialName <> '' then Output.Add('; filament_type = ' + S.MaterialName);
    Output.Add(Format('; temperature = %d, first_layer_temperature = %d, bed_temperature = %d, first_layer_bed_temperature = %d',
      [S.Printer.HotendTemp, FirstHotend(S), S.Printer.BedTemp, FirstBed(S)]));
    if NObj > 1 then
      for K := 0 to NObj - 1 do
        with S.Objects[K] do
          Output.Add(Format('; object %d = %s (X %s..%s, Y %s..%s)',
            [K, ObjNames[K], W.N(MinX), W.N(MaxX), W.N(MinY), W.N(MaxY)]));
    if S.Flavor = sfKlipper then begin
      // poligono de cada objeto (envelope) para EXCLUDE_OBJECT
      if NObj <= 1 then begin
        Poly := Format('[[%s,%s],[%s,%s],[%s,%s],[%s,%s]]',
          [W.N(MinX), W.N(MinY), W.N(MaxX), W.N(MinY), W.N(MaxX), W.N(MaxY), W.N(MinX), W.N(MaxY)]);
        Output.Add(Format('EXCLUDE_OBJECT_DEFINE NAME=%s CENTER=%s,%s POLYGON=%s',
          [ObjNames[0], W.N((MinX + MaxX) / 2), W.N((MinY + MaxY) / 2), Poly]));
      end else
        for K := 0 to NObj - 1 do
          with S.Objects[K] do begin
            Poly := Format('[[%s,%s],[%s,%s],[%s,%s],[%s,%s]]',
              [W.N(MinX), W.N(MinY), W.N(MaxX), W.N(MinY), W.N(MaxX), W.N(MaxY), W.N(MinX), W.N(MaxY)]);
            Output.Add(Format('EXCLUDE_OBJECT_DEFINE NAME=%s CENTER=%s,%s POLYGON=%s',
              [ObjNames[K], W.N((MinX + MaxX) / 2), W.N((MinY + MaxY) / 2), Poly]));
          end;
      Output.Add(Format('SET_PRINT_STATS_INFO TOTAL_LAYER=%d', [Result.Layers]));
    end else
      Output.Add(Format('M486 T%d', [Max(1, NObj)]));
    Output.Add('G21');
    Output.Add('G90');
    Output.Add('M83 ; extrusao relativa');
    if Trim(S.StartGCode) <> '' then begin
      Output.Add('; --- G-code inicial do perfil da impressora ---');
      Output.Text := Output.Text + ExpandGCodeTemplate(S.StartGCode, S);
      Output.Add('; --- fim do G-code inicial ---');
      Output.Add('M83 ; extrusao relativa');
    end else begin
      if S.HeatedBed then Output.Add(Format('M140 S%d', [FirstBed(S)]));
      Output.Add(Format('M104 S%d', [FirstHotend(S)]));
      Output.Add('G28');
      if S.HeatedBed then Output.Add(Format('M190 S%d', [FirstBed(S)]));
      Output.Add(Format('M109 S%d', [FirstHotend(S)]));
    end;
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
    if Trim(S.EndGCode) <> '' then begin
      Output.Add('; --- G-code final do perfil da impressora ---');
      Output.Text := Output.Text + ExpandGCodeTemplate(S.EndGCode, S);
      Output.Add('; --- fim do G-code final ---');
    end else begin
      Output.Add('G91');
      Output.Add('G0 Z5');
      Output.Add('G90');
      Output.Add('M104 S0');
      Output.Add('M140 S0');
      Output.Add('M84');
    end;
  finally
    Body.Free;
    W.Free;
  end;
  Result.MSGCode := GetTickCount64 - T0;
end;

end.
