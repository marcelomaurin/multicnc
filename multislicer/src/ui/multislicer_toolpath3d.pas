unit multislicer_toolpath3d;

{ MultiSlicer - previa 3D das trajetorias (Etapa 7.2/7.3 do docs/PLANO_TAREFAS.md).

  Cada trajetoria de cada camada vira uma "fita" com a largura da linha e a
  altura da camada: topo + duas laterais (6 triangulos por segmento), como os
  tubos do Cura. As fitas sao agrupadas por camada e por papel (uma malha por
  cor) e montadas so quando a camada e mostrada pela primeira vez.

  Usa as camadas do proprio TModernSlicer (TModernSlicer.Layers), na ordem em
  que foram escritas no G-code: a camada N da previa e o N-esimo ;LAYER_CHANGE,
  e os deslocamentos ligam o fim de uma trajetoria ao inicio da seguinte.

  Girando (quadro rapido), desenha so o topo das fitas (2 triangulos). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Graphics, multisuite_geometry, multislicer_types, multislicer_pipeline,
  multicad_types, multicad_mesh, multicad_softrender;

type
  TToolpathLayerMeshes = record
    Built: Boolean;
    Full, Top: array[TPathRole] of TCadMeshCache;
    Tris: Integer;
  end;

  TToolpathPreview = class
  private
    FLayers: TLayerDataArray;     { copia da referencia: sobrevive ao motor }
    FMeshes: array of TToolpathLayerMeshes;
    FLineW: Double;
    procedure BuildLayer(I: Integer);
    procedure FreeLayer(I: Integer);
  public
    constructor Create(const ALayers: TLayerDataArray; ALineWidth: Double);
    destructor Destroy; override;
    function LayerCount: Integer;
    function LayerZ(I: Integer): Double;
    function LayerHeight(I: Integer): Double;
    { triangulos da camada (monta se preciso) }
    function LayerTris(I: Integer): Integer;
    { desenha as camadas FromLayer..UpTo; Fast = so o topo das fitas }
    procedure Draw(R: TCadRaster; FromLayer, UpTo: Integer; Fast: Boolean; Tag: Integer);
    { deslocamentos (sem extrusao) da camada I }
    procedure DrawTravels(R: TCadRaster; I: Integer; Color: LongWord);
    { segmentos de extrusao da camada I (testes) }
    function SegmentCount(I: Integer): Integer;
  end;

function RoleRGB(R: TPathRole): LongWord;   { $00RRGGBB do raster }

implementation

uses multislicer_view;

function ToCad(X, Y, Z: Double): TCadVec3; inline;
begin
  Result := V3(X, Z, -Y);   { igual ao SlicerToCad da vista 3D }
end;

function RoleRGB(R: TPathRole): LongWord;
var C: TColor;
begin
  C := ColorToRGB(SlicerRoleColor(R));
  Result := (LongWord(Red(C)) shl 16) or (LongWord(Green(C)) shl 8) or LongWord(Blue(C));
end;

constructor TToolpathPreview.Create(const ALayers: TLayerDataArray; ALineWidth: Double);
begin
  inherited Create;
  FLayers := ALayers;
  FLineW := ALineWidth;
  if FLineW <= 0 then FLineW := 0.45;
  SetLength(FMeshes, Length(FLayers));
end;

destructor TToolpathPreview.Destroy;
var I: Integer;
begin
  for I := 0 to High(FMeshes) do FreeLayer(I);
  inherited Destroy;
end;

procedure TToolpathPreview.FreeLayer(I: Integer);
var R: TPathRole;
begin
  for R := Low(TPathRole) to High(TPathRole) do
  begin
    if FMeshes[I].Full[R] <> nil then
    begin
      FMeshes[I].Full[R].Mesh.Free;
      FreeAndNil(FMeshes[I].Full[R]);
    end;
    if FMeshes[I].Top[R] <> nil then
    begin
      FMeshes[I].Top[R].Mesh.Free;
      FreeAndNil(FMeshes[I].Top[R]);
    end;
  end;
  FMeshes[I].Built := False;
end;

function TToolpathPreview.LayerCount: Integer;
begin
  Result := Length(FLayers);
end;

function TToolpathPreview.LayerZ(I: Integer): Double;
begin
  Result := FLayers[I].Z;
end;

function TToolpathPreview.LayerHeight(I: Integer): Double;
begin
  Result := FLayers[I].Height;
end;

function TToolpathPreview.SegmentCount(I: Integer): Integer;
var P: Integer;
begin
  Result := 0;
  for P := 0 to High(FLayers[I].Paths) do
    with FLayers[I].Paths[P] do
      if Closed then Inc(Result, Length(Points))
      else Inc(Result, Max(0, Length(Points) - 1));
end;

procedure TToolpathPreview.BuildLayer(I: Integer);
var
  Full, Top: array[TPathRole] of TCadMesh;
  FaceF, FaceT: array[TPathRole] of Integer;
  R: TPathRole;
  P, J, N, Last: Integer;
  Z0, Z1, HW, Ext, DX, DY, L, NX, NY, AX, AY, BX, BY: Double;
  Info: TCadFaceInfo;
  V: array[0..7] of Integer;
  Pts: TPolygon2D;

  function Fresh: TCadMesh;
  begin
    Result := TCadMesh.Create;
  end;

begin
  if FMeshes[I].Built then Exit;
  Info.Name := 'trajetoria'; Info.Surf := skPlane;
  Info.Origin := V3(0, 0, 0); Info.Axis := V3(0, 1, 0);
  Info.Radius := 0; Info.Radius2 := 0;
  for R := Low(TPathRole) to High(TPathRole) do
  begin
    Full[R] := nil; Top[R] := nil;
  end;
  Z1 := FLayers[I].Z;
  Z0 := Z1 - Max(0.02, FLayers[I].Height * 0.9);
  HW := FLineW / 2;
  Ext := FLineW * 0.4;      { prolonga as pontas: cantos sem fresta }
  FMeshes[I].Tris := 0;
  for P := 0 to High(FLayers[I].Paths) do
  begin
    R := FLayers[I].Paths[P].Role;
    Pts := FLayers[I].Paths[P].Points;
    N := Length(Pts);
    if N < 2 then Continue;
    if Full[R] = nil then
    begin
      Full[R] := Fresh; FaceF[R] := Full[R].AddFace(Info);
      Top[R] := Fresh; FaceT[R] := Top[R].AddFace(Info);
    end;
    if FLayers[I].Paths[P].Closed then Last := N - 1 else Last := N - 2;
    for J := 0 to Last do
    begin
      AX := Pts[J].X; AY := Pts[J].Y;
      BX := Pts[(J + 1) mod N].X; BY := Pts[(J + 1) mod N].Y;
      DX := BX - AX; DY := BY - AY;
      L := Hypot(DX, DY);
      if L < 1e-6 then Continue;
      DX := DX / L; DY := DY / L;
      AX := AX - DX * Ext; AY := AY - DY * Ext;
      BX := BX + DX * Ext; BY := BY + DY * Ext;
      NX := -DY * HW; NY := DX * HW;
      { 0..3 topo, 4..7 base }
      V[0] := Full[R].AddVertexRaw(ToCad(AX + NX, AY + NY, Z1));
      V[1] := Full[R].AddVertexRaw(ToCad(BX + NX, BY + NY, Z1));
      V[2] := Full[R].AddVertexRaw(ToCad(BX - NX, BY - NY, Z1));
      V[3] := Full[R].AddVertexRaw(ToCad(AX - NX, AY - NY, Z1));
      V[4] := Full[R].AddVertexRaw(ToCad(AX + NX, AY + NY, Z0));
      V[5] := Full[R].AddVertexRaw(ToCad(BX + NX, BY + NY, Z0));
      V[6] := Full[R].AddVertexRaw(ToCad(BX - NX, BY - NY, Z0));
      V[7] := Full[R].AddVertexRaw(ToCad(AX - NX, AY - NY, Z0));
      Full[R].AddTri(V[0], V[1], V[2], FaceF[R]); Full[R].AddTri(V[0], V[2], V[3], FaceF[R]);
      Full[R].AddTri(V[4], V[5], V[1], FaceF[R]); Full[R].AddTri(V[4], V[1], V[0], FaceF[R]);
      Full[R].AddTri(V[3], V[2], V[6], FaceF[R]); Full[R].AddTri(V[3], V[6], V[7], FaceF[R]);
      V[0] := Top[R].AddVertexRaw(ToCad(AX + NX, AY + NY, Z1));
      V[1] := Top[R].AddVertexRaw(ToCad(BX + NX, BY + NY, Z1));
      V[2] := Top[R].AddVertexRaw(ToCad(BX - NX, BY - NY, Z1));
      V[3] := Top[R].AddVertexRaw(ToCad(AX - NX, AY - NY, Z1));
      Top[R].AddTri(V[0], V[1], V[2], FaceT[R]); Top[R].AddTri(V[0], V[2], V[3], FaceT[R]);
      Inc(FMeshes[I].Tris, 6);
    end;
  end;
  for R := Low(TPathRole) to High(TPathRole) do
    if Full[R] <> nil then
    begin
      FMeshes[I].Full[R] := TCadMeshCache.Create(Full[R]);
      FMeshes[I].Top[R] := TCadMeshCache.Create(Top[R]);
    end;
  FMeshes[I].Built := True;
end;

function TToolpathPreview.LayerTris(I: Integer): Integer;
begin
  if (I < 0) or (I > High(FMeshes)) then Exit(0);
  BuildLayer(I);
  Result := FMeshes[I].Tris;
end;

procedure TToolpathPreview.Draw(R: TCadRaster; FromLayer, UpTo: Integer; Fast: Boolean; Tag: Integer);
var I: Integer; Role: TPathRole; Opt: TCadDrawOptions; C: TCadMeshCache; Saved: TCadDisplayStyle;
begin
  FromLayer := Max(0, FromLayer);
  UpTo := Min(UpTo, High(FMeshes));
  Saved := R.Style;
  R.Style := dsShaded;     { fitas sem arestas: cada linha ja e um tubo }
  try
    for I := FromLayer to UpTo do
    begin
      BuildLayer(I);
      for Role := Low(TPathRole) to High(TPathRole) do
      begin
        if Fast and (I < UpTo) then C := FMeshes[I].Top[Role] else C := FMeshes[I].Full[Role];
        if C = nil then Continue;
        Opt := CadDrawOptions(RoleRGB(Role), Tag);
        R.DrawMesh(C, Opt);
      end;
    end;
  finally
    R.Style := Saved;
  end;
end;

procedure TToolpathPreview.DrawTravels(R: TCadRaster; I: Integer; Color: LongWord);
var P, N: Integer; Z: Double; EX, EY: Double; Have: Boolean;
begin
  if (I < 0) or (I > High(FLayers)) then Exit;
  Z := FLayers[I].Z + 0.05;
  Have := False; EX := 0; EY := 0;
  for P := 0 to High(FLayers[I].Paths) do
    with FLayers[I].Paths[P] do
    begin
      N := Length(Points);
      if N = 0 then Continue;
      if Have and (Hypot(Points[0].X - EX, Points[0].Y - EY) > FLineW) then
        R.DrawLine3D(ToCad(EX, EY, Z), ToCad(Points[0].X, Points[0].Y, Z), Color, 1, True);
      if Closed then begin EX := Points[0].X; EY := Points[0].Y; end
      else begin EX := Points[N - 1].X; EY := Points[N - 1].Y; end;
      Have := True;
    end;
end;

end.
