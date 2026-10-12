unit multislicer_scene;

{ MultiSlicer - cena de impressao (Etapa 3 do docs/PLANO_TAREFAS.md). Sem LCL.

  A cena guarda as pecas colocadas na mesa. Cada peca (TSliceObject) guarda a
  malha original do arquivo e a sua transformacao; a malha na mesa
  (WorldMesh) e recalculada so quando a transformacao muda.

  Transformacao, nesta ordem, em torno do centro da caixa da malha original:
    escala por eixo (espelho = escala negativa)
    -> rotacao X, depois Y, depois Z (graus)
    -> translacao: o centro XY da caixa vai para (X, Y) da mesa e o ponto
       mais baixo vai para Z = Lift (0 = assentada na mesa, como no Cura).
  Espelho em numero impar de eixos inverte a ordem dos vertices de cada
  triangulo, para as normais continuarem para fora.

  Coordenadas da mesa: origem no canto inferior esquerdo, Z para cima, mm.
  O fatiamento usa MergedMesh (todas as pecas ja na mesa). }

{$mode objfpc}{$H+}

interface

uses Classes, SysUtils, Math, Contnrs, multislicer_types, multislicer_mesh;

type
  TBox3 = record
    Min, Max: TVec3;
    Empty: Boolean;
  end;

  TSliceObject = class
  private
    FSource: TMesh;           { malha original (posse) }
    FWorld: TMesh;            { malha na mesa (cache) }
    FWorldBox: TBox3;
    FDirty: Boolean;
    FVersion: Integer;
    FShapeVersion: Integer;
    FSourceCenter: TVec3;
    FX, FY, FLift: Double;
    FRotX, FRotY, FRotZ: Double;
    FScaleX, FScaleY, FScaleZ: Double;
    FMirrorX, FMirrorY, FMirrorZ: Boolean;
    procedure Rebuild;
    procedure Changed;
    procedure SetX(V: Double);
    procedure SetY(V: Double);
    procedure SetLift(V: Double);
    procedure SetRotX(V: Double);
    procedure SetRotY(V: Double);
    procedure SetRotZ(V: Double);
    procedure SetScaleX(V: Double);
    procedure SetScaleY(V: Double);
    procedure SetScaleZ(V: Double);
    procedure SetMirrorX(V: Boolean);
    procedure SetMirrorY(V: Boolean);
    procedure SetMirrorZ(V: Boolean);
    function GetWorld: TMesh;
    function GetWorldBox: TBox3;
  public
    Name, SourceFile: string;
    Selected, Locked: Boolean;
    constructor Create(ASource: TMesh; const AName, AFile: string);  { assume a posse de ASource }
    destructor Destroy; override;
    function Clone: TSliceObject;
    procedure MoveBy(DX, DY: Double);
    procedure SetScaleUniform(S: Double);
    function TransformPoint(const P: TVec3): TVec3;
    function SourceSize: TVec3;
    function Size: TVec3;                       { tamanho na mesa }
    property Source: TMesh read FSource;
    property WorldMesh: TMesh read GetWorld;
    property WorldBox: TBox3 read GetWorldBox;
    property Version: Integer read FVersion;            { muda a cada alteracao, inclusive arrastar }
    property ShapeVersion: Integer read FShapeVersion;  { muda quando a forma muda (nao ao arrastar) }
    property X: Double read FX write SetX;
    property Y: Double read FY write SetY;
    property Lift: Double read FLift write SetLift;
    property RotX: Double read FRotX write SetRotX;
    property RotY: Double read FRotY write SetRotY;
    property RotZ: Double read FRotZ write SetRotZ;
    property ScaleX: Double read FScaleX write SetScaleX;
    property ScaleY: Double read FScaleY write SetScaleY;
    property ScaleZ: Double read FScaleZ write SetScaleZ;
    property MirrorX: Boolean read FMirrorX write SetMirrorX;
    property MirrorY: Boolean read FMirrorY write SetMirrorY;
    property MirrorZ: Boolean read FMirrorZ write SetMirrorZ;
  end;

  TSliceScene = class
  private
    FItems: TObjectList;
    FVersion: Integer;
    function GetItem(I: Integer): TSliceObject;
  public
    BedX, BedY, BedZ: Double;
    Spacing: Double;      { folga minima entre pecas (mm) }
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    function Count: Integer;
    { Acrescenta a peca (posse de AMesh) num lugar livre da mesa. }
    function Add(AMesh: TMesh; const AName, AFile: string): TSliceObject;
    function AddObject(O: TSliceObject; FindPlace: Boolean): TSliceObject;
    procedure Delete(I: Integer);
    procedure DeleteSelected;
    function Duplicate(I: Integer): TSliceObject;
    function IndexOf(O: TSliceObject): Integer;
    procedure SelectOnly(I: Integer);    { -1 = nenhuma }
    procedure ToggleSelect(I: Integer);
    function SelectedCount: Integer;
    function FirstSelected: Integer;
    procedure CenterObject(I: Integer);
    { Primeiro lugar livre (centro da caixa) para uma peca do tamanho dado. }
    function FindFreeSpot(SX, SY: Double; Ignore: Integer; out PX, PY: Double): Boolean;
    function Overlaps(I, J: Integer): Boolean;
    function Inside(I: Integer): Boolean;
    function Validate(Errors: TStrings): Boolean;
    procedure MergedMesh(Dest: TMesh);
    function Bounds: TBox3;
    function TriangleCount: Integer;
    procedure Touch;                     { avisa mudanca (vista redesenha) }
    property Items[I: Integer]: TSliceObject read GetItem; default;
    property Version: Integer read FVersion;
  end;

function MeshBox(M: TMesh): TBox3;
procedure BoxInclude(var B: TBox3; const P: TVec3);
function Vec3(AX, AY, AZ: Double): TVec3;

implementation

function Vec3(AX, AY, AZ: Double): TVec3;
begin
  Result.X := AX; Result.Y := AY; Result.Z := AZ;
end;

procedure BoxInclude(var B: TBox3; const P: TVec3);
begin
  if B.Empty then
  begin
    B.Min := P; B.Max := P; B.Empty := False;
    Exit;
  end;
  B.Min.X := Min(B.Min.X, P.X); B.Min.Y := Min(B.Min.Y, P.Y); B.Min.Z := Min(B.Min.Z, P.Z);
  B.Max.X := Max(B.Max.X, P.X); B.Max.Y := Max(B.Max.Y, P.Y); B.Max.Z := Max(B.Max.Z, P.Z);
end;

function MeshBox(M: TMesh): TBox3;
var I: Integer; T: TTriangle;
begin
  Result.Empty := True;
  Result.Min := Vec3(0, 0, 0); Result.Max := Result.Min;
  if M = nil then Exit;
  for I := 0 to M.Count - 1 do
  begin
    T := M.Triangle(I);
    BoxInclude(Result, T.A); BoxInclude(Result, T.B); BoxInclude(Result, T.C);
  end;
end;

{ ---------------- TSliceObject ---------------- }

constructor TSliceObject.Create(ASource: TMesh; const AName, AFile: string);
var B: TBox3;
begin
  inherited Create;
  FSource := ASource;
  FWorld := TMesh.Create;
  Name := AName;
  SourceFile := AFile;
  B := MeshBox(FSource);
  FSourceCenter := Vec3((B.Min.X + B.Max.X) / 2, (B.Min.Y + B.Max.Y) / 2, (B.Min.Z + B.Max.Z) / 2);
  FScaleX := 1; FScaleY := 1; FScaleZ := 1;
  FDirty := True;
end;

destructor TSliceObject.Destroy;
begin
  FWorld.Free;
  FSource.Free;
  inherited Destroy;
end;

function TSliceObject.Clone: TSliceObject;
var M: TMesh; I: Integer;
begin
  M := TMesh.Create;
  for I := 0 to FSource.Count - 1 do M.Add(FSource.Triangle(I));
  Result := TSliceObject.Create(M, Name, SourceFile);
  Result.FX := FX; Result.FY := FY; Result.FLift := FLift;
  Result.FRotX := FRotX; Result.FRotY := FRotY; Result.FRotZ := FRotZ;
  Result.FScaleX := FScaleX; Result.FScaleY := FScaleY; Result.FScaleZ := FScaleZ;
  Result.FMirrorX := FMirrorX; Result.FMirrorY := FMirrorY; Result.FMirrorZ := FMirrorZ;
  Result.Locked := Locked;
end;

procedure TSliceObject.Changed;
begin
  FDirty := True;
  Inc(FVersion);
  Inc(FShapeVersion);
end;

procedure TSliceObject.SetX(V: Double); begin if V <> FX then begin FX := V; Changed; end; end;
procedure TSliceObject.SetY(V: Double); begin if V <> FY then begin FY := V; Changed; end; end;
procedure TSliceObject.SetLift(V: Double); begin V := Max(0, V); if V <> FLift then begin FLift := V; Changed; end; end;
procedure TSliceObject.SetRotX(V: Double); begin if V <> FRotX then begin FRotX := V; Changed; end; end;
procedure TSliceObject.SetRotY(V: Double); begin if V <> FRotY then begin FRotY := V; Changed; end; end;
procedure TSliceObject.SetRotZ(V: Double); begin if V <> FRotZ then begin FRotZ := V; Changed; end; end;
procedure TSliceObject.SetScaleX(V: Double); begin V := EnsureRange(V, 0.001, 1000); if V <> FScaleX then begin FScaleX := V; Changed; end; end;
procedure TSliceObject.SetScaleY(V: Double); begin V := EnsureRange(V, 0.001, 1000); if V <> FScaleY then begin FScaleY := V; Changed; end; end;
procedure TSliceObject.SetScaleZ(V: Double); begin V := EnsureRange(V, 0.001, 1000); if V <> FScaleZ then begin FScaleZ := V; Changed; end; end;
procedure TSliceObject.SetMirrorX(V: Boolean); begin if V <> FMirrorX then begin FMirrorX := V; Changed; end; end;
procedure TSliceObject.SetMirrorY(V: Boolean); begin if V <> FMirrorY then begin FMirrorY := V; Changed; end; end;
procedure TSliceObject.SetMirrorZ(V: Boolean); begin if V <> FMirrorZ then begin FMirrorZ := V; Changed; end; end;

procedure TSliceObject.SetScaleUniform(S: Double);
begin
  S := EnsureRange(S, 0.001, 1000);
  FScaleX := S; FScaleY := S; FScaleZ := S;
  Changed;
end;

procedure TSliceObject.MoveBy(DX, DY: Double);
var I: Integer; T: TTriangle;
begin
  if Locked or ((DX = 0) and (DY = 0)) then Exit;
  FX := FX + DX; FY := FY + DY;
  Inc(FVersion);
  if FDirty then Exit;
  { translacao pura (arrastar na mesa): desloca o cache, sem refazer rotacoes }
  for I := 0 to FWorld.Count - 1 do
  begin
    T := FWorld.Triangle(I);
    T.A.X := T.A.X + DX; T.A.Y := T.A.Y + DY;
    T.B.X := T.B.X + DX; T.B.Y := T.B.Y + DY;
    T.C.X := T.C.X + DX; T.C.Y := T.C.Y + DY;
    FWorld.SetTriangle(I, T);
  end;
  FWorldBox.Min.X := FWorldBox.Min.X + DX; FWorldBox.Max.X := FWorldBox.Max.X + DX;
  FWorldBox.Min.Y := FWorldBox.Min.Y + DY; FWorldBox.Max.Y := FWorldBox.Max.Y + DY;
end;

{ escala/espelho e rotacao em torno do centro da malha original }
function TSliceObject.TransformPoint(const P: TVec3): TVec3;
var PX, PY, PZ, T, A, SX, SY, SZ: Double;
begin
  SX := FScaleX; if FMirrorX then SX := -SX;
  SY := FScaleY; if FMirrorY then SY := -SY;
  SZ := FScaleZ; if FMirrorZ then SZ := -SZ;
  PX := (P.X - FSourceCenter.X) * SX;
  PY := (P.Y - FSourceCenter.Y) * SY;
  PZ := (P.Z - FSourceCenter.Z) * SZ;
  if FRotX <> 0 then
  begin
    A := DegToRad(FRotX);
    T := PY; PY := T * Cos(A) - PZ * Sin(A); PZ := T * Sin(A) + PZ * Cos(A);
  end;
  if FRotY <> 0 then
  begin
    A := DegToRad(FRotY);
    T := PX; PX := T * Cos(A) + PZ * Sin(A); PZ := -T * Sin(A) + PZ * Cos(A);
  end;
  if FRotZ <> 0 then
  begin
    A := DegToRad(FRotZ);
    T := PX; PX := T * Cos(A) - PY * Sin(A); PY := T * Sin(A) + PY * Cos(A);
  end;
  Result := Vec3(PX, PY, PZ);
end;

procedure TSliceObject.Rebuild;
var I, N, Mirrors: Integer; T, R: TTriangle; Tmp: array of TTriangle; B: TBox3; DX, DY, DZ: Double;
begin
  N := FSource.Count;
  SetLength(Tmp, N);
  Mirrors := Ord(FMirrorX) + Ord(FMirrorY) + Ord(FMirrorZ);
  B.Empty := True;
  for I := 0 to N - 1 do
  begin
    T := FSource.Triangle(I);
    R.A := TransformPoint(T.A);
    if Odd(Mirrors) then
    begin
      R.B := TransformPoint(T.C);
      R.C := TransformPoint(T.B);
    end
    else
    begin
      R.B := TransformPoint(T.B);
      R.C := TransformPoint(T.C);
    end;
    BoxInclude(B, R.A); BoxInclude(B, R.B); BoxInclude(B, R.C);
    Tmp[I] := R;
  end;
  DX := 0; DY := 0; DZ := 0;
  if not B.Empty then
  begin
    DX := FX - (B.Min.X + B.Max.X) / 2;
    DY := FY - (B.Min.Y + B.Max.Y) / 2;
    DZ := FLift - B.Min.Z;
  end;
  FWorld.Clear;
  FWorld.Capacity := N;
  for I := 0 to N - 1 do
  begin
    R := Tmp[I];
    R.A.X := R.A.X + DX; R.A.Y := R.A.Y + DY; R.A.Z := R.A.Z + DZ;
    R.B.X := R.B.X + DX; R.B.Y := R.B.Y + DY; R.B.Z := R.B.Z + DZ;
    R.C.X := R.C.X + DX; R.C.Y := R.C.Y + DY; R.C.Z := R.C.Z + DZ;
    FWorld.Add(R);
  end;
  FWorldBox := B;
  if not B.Empty then
  begin
    FWorldBox.Min := Vec3(B.Min.X + DX, B.Min.Y + DY, B.Min.Z + DZ);
    FWorldBox.Max := Vec3(B.Max.X + DX, B.Max.Y + DY, B.Max.Z + DZ);
  end;
  FDirty := False;
end;

function TSliceObject.GetWorld: TMesh;
begin
  if FDirty then Rebuild;
  Result := FWorld;
end;

function TSliceObject.GetWorldBox: TBox3;
begin
  if FDirty then
  begin
    { caixa sem montar a malha inteira: transforma so os vertices }
    Rebuild;
  end;
  Result := FWorldBox;
end;

function TSliceObject.SourceSize: TVec3;
var B: TBox3;
begin
  B := MeshBox(FSource);
  Result := Vec3(B.Max.X - B.Min.X, B.Max.Y - B.Min.Y, B.Max.Z - B.Min.Z);
end;

function TSliceObject.Size: TVec3;
var B: TBox3;
begin
  B := WorldBox;
  Result := Vec3(B.Max.X - B.Min.X, B.Max.Y - B.Min.Y, B.Max.Z - B.Min.Z);
end;

{ ---------------- TSliceScene ---------------- }

constructor TSliceScene.Create;
begin
  inherited Create;
  FItems := TObjectList.Create(True);
  BedX := 220; BedY := 220; BedZ := 250;
  Spacing := 4;
end;

destructor TSliceScene.Destroy;
begin
  FItems.Free;
  inherited Destroy;
end;

procedure TSliceScene.Touch;
begin
  Inc(FVersion);
end;

procedure TSliceScene.Clear;
begin
  FItems.Clear;
  Touch;
end;

function TSliceScene.Count: Integer;
begin
  Result := FItems.Count;
end;

function TSliceScene.GetItem(I: Integer): TSliceObject;
begin
  Result := TSliceObject(FItems[I]);
end;

function TSliceScene.IndexOf(O: TSliceObject): Integer;
begin
  Result := FItems.IndexOf(O);
end;

function BoxesOverlap(const A, B: TBox3; Gap: Double): Boolean;
begin
  Result := not ((A.Max.X + Gap <= B.Min.X) or (B.Max.X + Gap <= A.Min.X) or
    (A.Max.Y + Gap <= B.Min.Y) or (B.Max.Y + Gap <= A.Min.Y));
end;

function TSliceScene.FindFreeSpot(SX, SY: Double; Ignore: Integer; out PX, PY: Double): Boolean;
var Ring, K, Steps: Integer; Step, CX, CY: Double; Cand: TBox3; Ok: Boolean;

  function TrySpot(X0, Y0: Double): Boolean;
  var J: Integer;
  begin
    Result := False;
    Cand.Empty := False;
    Cand.Min := Vec3(X0 - SX / 2, Y0 - SY / 2, 0);
    Cand.Max := Vec3(X0 + SX / 2, Y0 + SY / 2, 0);
    if (Cand.Min.X < 0) or (Cand.Min.Y < 0) or (Cand.Max.X > BedX) or (Cand.Max.Y > BedY) then Exit;
    for J := 0 to Count - 1 do
      if (J <> Ignore) and BoxesOverlap(Cand, Items[J].WorldBox, Spacing) then Exit;
    PX := X0; PY := Y0;
    Result := True;
  end;

begin
  CX := BedX / 2; CY := BedY / 2;
  PX := CX; PY := CY;
  if TrySpot(CX, CY) then Exit(True);
  { aneis quadrados em volta do centro, passo de 5 mm }
  Step := 5;
  Steps := Ceil(Max(BedX, BedY) / Step);
  for Ring := 1 to Steps do
  begin
    for K := -Ring to Ring do
    begin
      Ok := TrySpot(CX + K * Step, CY - Ring * Step) or TrySpot(CX + K * Step, CY + Ring * Step) or
        TrySpot(CX - Ring * Step, CY + K * Step) or TrySpot(CX + Ring * Step, CY + K * Step);
      if Ok then Exit(True);
    end;
  end;
  { sem lugar: fica no centro e a validacao avisa }
  PX := CX; PY := CY;
  Result := False;
end;

function TSliceScene.AddObject(O: TSliceObject; FindPlace: Boolean): TSliceObject;
var S: TVec3; PX, PY: Double;
begin
  Result := O;
  if FindPlace then
  begin
    O.X := BedX / 2; O.Y := BedY / 2;
    S := O.Size;
    FindFreeSpot(S.X, S.Y, -1, PX, PY);
    O.X := PX; O.Y := PY;
  end;
  FItems.Add(O);
  Touch;
end;

function TSliceScene.Add(AMesh: TMesh; const AName, AFile: string): TSliceObject;
begin
  Result := AddObject(TSliceObject.Create(AMesh, AName, AFile), True);
end;

procedure TSliceScene.Delete(I: Integer);
begin
  FItems.Delete(I);
  Touch;
end;

procedure TSliceScene.DeleteSelected;
var I: Integer;
begin
  for I := Count - 1 downto 0 do
    if Items[I].Selected then FItems.Delete(I);
  Touch;
end;

function TSliceScene.Duplicate(I: Integer): TSliceObject;
begin
  Result := Items[I].Clone;
  Result.Name := Items[I].Name;
  AddObject(Result, True);
end;

procedure TSliceScene.SelectOnly(I: Integer);
var J: Integer;
begin
  for J := 0 to Count - 1 do Items[J].Selected := J = I;
  Touch;
end;

procedure TSliceScene.ToggleSelect(I: Integer);
begin
  if (I < 0) or (I >= Count) then Exit;
  Items[I].Selected := not Items[I].Selected;
  Touch;
end;

function TSliceScene.SelectedCount: Integer;
var I: Integer;
begin
  Result := 0;
  for I := 0 to Count - 1 do if Items[I].Selected then Inc(Result);
end;

function TSliceScene.FirstSelected: Integer;
var I: Integer;
begin
  for I := 0 to Count - 1 do if Items[I].Selected then Exit(I);
  Result := -1;
end;

procedure TSliceScene.CenterObject(I: Integer);
begin
  if (I < 0) or (I >= Count) or Items[I].Locked then Exit;
  Items[I].X := BedX / 2;
  Items[I].Y := BedY / 2;
  Touch;
end;

function TSliceScene.Overlaps(I, J: Integer): Boolean;
begin
  Result := BoxesOverlap(Items[I].WorldBox, Items[J].WorldBox, 0);
end;

function TSliceScene.Inside(I: Integer): Boolean;
var B: TBox3;
begin
  B := Items[I].WorldBox;
  Result := B.Empty or ((B.Min.X >= -1e-6) and (B.Min.Y >= -1e-6) and (B.Max.X <= BedX + 1e-6) and
    (B.Max.Y <= BedY + 1e-6) and (B.Max.Z <= BedZ + 1e-6));
end;

function TSliceScene.Validate(Errors: TStrings): Boolean;
var I, J: Integer; B: TBox3; FS: TFormatSettings;
begin
  FS := DefaultFormatSettings; FS.DecimalSeparator := '.';
  if Count = 0 then Errors.Add('Abra um modelo STL ou 3MF.');
  for I := 0 to Count - 1 do
  begin
    B := Items[I].WorldBox;
    if not Inside(I) then
    begin
      if B.Max.Z > BedZ + 1e-6 then
        Errors.Add(Format('%s: tem %.1f mm de altura; a impressora vai ate %.0f mm.',
          [Items[I].Name, B.Max.Z, BedZ], FS))
      else
        Errors.Add(Format('%s: sai da mesa (X %.1f..%.1f, Y %.1f..%.1f; mesa %.0f x %.0f mm).',
          [Items[I].Name, B.Min.X, B.Max.X, B.Min.Y, B.Max.Y, BedX, BedY], FS));
    end;
    for J := I + 1 to Count - 1 do
      if Overlaps(I, J) then
        Errors.Add(Format('%s e %s se sobrepoem na mesa.', [Items[I].Name, Items[J].Name]));
  end;
  Result := Errors.Count = 0;
end;

procedure TSliceScene.MergedMesh(Dest: TMesh);
var I, K: Integer; M: TMesh;
begin
  Dest.Clear;
  for I := 0 to Count - 1 do
  begin
    M := Items[I].WorldMesh;
    for K := 0 to M.Count - 1 do Dest.Add(M.Triangle(K));
  end;
end;

function TSliceScene.Bounds: TBox3;
var I: Integer; B: TBox3;
begin
  Result.Empty := True;
  Result.Min := Vec3(0, 0, 0); Result.Max := Result.Min;
  for I := 0 to Count - 1 do
  begin
    B := Items[I].WorldBox;
    if B.Empty then Continue;
    BoxInclude(Result, B.Min);
    BoxInclude(Result, B.Max);
  end;
end;

function TSliceScene.TriangleCount: Integer;
var I: Integer;
begin
  Result := 0;
  for I := 0 to Count - 1 do Inc(Result, Items[I].Source.Count);
end;

end.
