unit multiphysics_project;

{ Projeto do MultiPhysics (.mphys, JSON): pecas com material e geometria,
  condicoes de contorno, contatos, ambiente e configuracoes de analise.
  Tudo em SI. Formato versionado ("format": 1); versao desconhecida e
  recusada. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, fpjson, jsonparser,
  multiphysics_types, multiphysics_vector, multiphysics_geometry;

const
  MPHYS_FORMAT = 1;
  MPHYS_EXT = '.mphys';

type
  PBoundaryCondition = ^TBoundaryCondition;
  PContact = ^TContact;

  TPhysicsPart = class
  public
    ID, Name, GeometryFile: string;
    Kind: string;                       { tipo vindo do MultiAssembly (informativo) }
    Material: TMaterial;
    Primitives: array of TGeoPrimitive; { coordenadas da peca, em metros }
    Position: TVector3;                 { m }
    RotX, RotY, RotZ: Double;           { graus }
    Scale: TVector3;                    { escala por eixo (montagem: geometria -> tamanho da peca) }
    Pivot: TVector3;                    { centro de rotacao, m (montagem: meio da caixa) }
    MeshSize: Double;                   { m; 0 = usa o tamanho global }
    Suppressed: Boolean;                { fora da analise }
    constructor Create;
    procedure AddPrimitive(const P: TGeoPrimitive);
    function Transform: TGeoTransform;
    function Volume: Double;
    function Mass: Double;
  end;

  TPhysicsProject = class
  private
    FParts, FBCs, FContacts: TList;
  public
    Name, AssemblyFile, FileName: string;
    Environment: TEnvironment;
    Settings: TAnalysisSettings;
    Modified: Boolean;
    constructor Create;
    destructor Destroy; override;
    procedure Clear;
    procedure AddPart(P: TPhysicsPart);
    procedure DeletePart(I: Integer);
    function FindPart(const ID: string): Integer;
    procedure AddBC(const B: TBoundaryCondition);
    procedure SetBC(I: Integer; const B: TBoundaryCondition);
    procedure DeleteBC(I: Integer);
    procedure AddContact(const C: TContact);
    procedure SetContact(I: Integer; const C: TContact);
    procedure DeleteContact(I: Integer);
    function PartCount: Integer;
    function Part(I: Integer): TPhysicsPart;
    function BCCount: Integer;
    function BC(I: Integer): TBoundaryCondition;
    function ContactCount: Integer;
    function Contact(I: Integer): TContact;
    function ToJSON: string;
    procedure FromJSON(const S: string);
    procedure SaveToFile(const FN: string);
    procedure LoadFromFile(const FN: string);
    { o que falta para as analises pedidas em Settings.Physics; True se nada }
    function Validate(Log: TStrings): Boolean;
  end;

function NewBC(const Name, PartID, Face: string; Kind: TBoundaryKind): TBoundaryCondition;

implementation

function NewBC(const Name, PartID, Face: string; Kind: TBoundaryKind): TBoundaryCondition;
begin
  Result.Name := Name; Result.TargetID := PartID; Result.TargetFace := Face;
  Result.Kind := Kind;
  Result.X := 0; Result.Y := 0; Result.Z := 0; Result.Value := 0; Result.Value2 := 0;
  Result.DofMask := 0;
end;

{ ---------------- TPhysicsPart ---------------- }

constructor TPhysicsPart.Create;
begin
  inherited Create;
  Scale := V3(1, 1, 1);
  Pivot := V3(0, 0, 0);
end;

procedure TPhysicsPart.AddPrimitive(const P: TGeoPrimitive);
begin
  SetLength(Primitives, Length(Primitives) + 1);
  Primitives[High(Primitives)] := P;
end;

function TPhysicsPart.Transform: TGeoTransform;
begin
  Result := AffineTransform(Position, Pivot, Scale, RotX, RotY, RotZ);
end;

function TPhysicsPart.Volume: Double;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to High(Primitives) do Result := Result + PrimVolume(Primitives[I]);
  Result := Result * Abs(Scale.X * Scale.Y * Scale.Z);
end;

function TPhysicsPart.Mass: Double;
begin
  Result := Volume * Material.Density;
end;

{ ---------------- TPhysicsProject ---------------- }

constructor TPhysicsProject.Create;
begin
  inherited Create;
  FParts := TList.Create;
  FBCs := TList.Create;
  FContacts := TList.Create;
  Clear;
end;

destructor TPhysicsProject.Destroy;
begin
  Clear;
  FContacts.Free;
  FBCs.Free;
  FParts.Free;
  inherited Destroy;
end;

procedure TPhysicsProject.Clear;
var
  I: Integer;
begin
  for I := 0 to FParts.Count - 1 do TObject(FParts[I]).Free;
  for I := 0 to FBCs.Count - 1 do Dispose(PBoundaryCondition(FBCs[I]));
  for I := 0 to FContacts.Count - 1 do Dispose(PContact(FContacts[I]));
  FParts.Clear; FBCs.Clear; FContacts.Clear;
  Name := 'Novo projeto'; AssemblyFile := ''; FileName := '';
  FillChar(Environment, SizeOf(Environment), 0);
  Environment.AmbientTemperature := 20;
  Environment.GravityZ := -9.80665;
  FillChar(Settings, SizeOf(Settings), 0);
  Settings.Physics := [pkStructural];
  Settings.MeshSize := 0.005;
  Settings.TimeStep := 0.01;
  Settings.TotalTime := 1;
  Settings.Modes := 6;
  Settings.Quadratic := True;
  Settings.CheckConvergence := True;
  Settings.Solver := 0;
  Modified := False;
end;

procedure TPhysicsProject.AddPart(P: TPhysicsPart);
begin
  FParts.Add(P);
  Modified := True;
end;

procedure TPhysicsProject.DeletePart(I: Integer);
begin
  TObject(FParts[I]).Free;
  FParts.Delete(I);
  Modified := True;
end;

function TPhysicsProject.FindPart(const ID: string): Integer;
var
  I: Integer;
begin
  for I := 0 to FParts.Count - 1 do
    if SameText(Part(I).ID, ID) then Exit(I);
  Result := -1;
end;

procedure TPhysicsProject.AddBC(const B: TBoundaryCondition);
var
  P: PBoundaryCondition;
begin
  New(P);
  P^ := B;
  FBCs.Add(P);
  Modified := True;
end;

procedure TPhysicsProject.SetBC(I: Integer; const B: TBoundaryCondition);
begin
  PBoundaryCondition(FBCs[I])^ := B;
  Modified := True;
end;

procedure TPhysicsProject.DeleteBC(I: Integer);
begin
  Dispose(PBoundaryCondition(FBCs[I]));
  FBCs.Delete(I);
  Modified := True;
end;

procedure TPhysicsProject.AddContact(const C: TContact);
var
  P: PContact;
begin
  New(P);
  P^ := C;
  FContacts.Add(P);
  Modified := True;
end;

procedure TPhysicsProject.SetContact(I: Integer; const C: TContact);
begin
  PContact(FContacts[I])^ := C;
  Modified := True;
end;

procedure TPhysicsProject.DeleteContact(I: Integer);
begin
  Dispose(PContact(FContacts[I]));
  FContacts.Delete(I);
  Modified := True;
end;

function TPhysicsProject.PartCount: Integer; begin Result := FParts.Count; end;
function TPhysicsProject.Part(I: Integer): TPhysicsPart; begin Result := TPhysicsPart(FParts[I]); end;
function TPhysicsProject.BCCount: Integer; begin Result := FBCs.Count; end;
function TPhysicsProject.BC(I: Integer): TBoundaryCondition; begin Result := PBoundaryCondition(FBCs[I])^; end;
function TPhysicsProject.ContactCount: Integer; begin Result := FContacts.Count; end;
function TPhysicsProject.Contact(I: Integer): TContact; begin Result := PContact(FContacts[I])^; end;

{ ---------------- JSON ---------------- }

function Vec3JSON(const V: TVector3): TJSONArray;
begin
  Result := TJSONArray.Create([V.X, V.Y, V.Z]);
end;

function JSONVec3(A: TJSONArray): TVector3;
begin
  Result := V3(0, 0, 0);
  if (A = nil) or (A.Count < 3) then Exit;
  Result := V3(A.Floats[0], A.Floats[1], A.Floats[2]);
end;

function MaterialJSON(const M: TMaterial): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.Add('name', M.Name);
  Result.Add('class', Ord(M.MaterialClass));
  Result.Add('density', M.Density);
  Result.Add('young', M.YoungModulus);
  Result.Add('poisson', M.Poisson);
  Result.Add('conductivity', M.ThermalConductivity);
  Result.Add('specific_heat', M.SpecificHeat);
  Result.Add('expansion', M.ThermalExpansion);
  Result.Add('yield', M.YieldStrength);
  Result.Add('resistivity', M.ElectricalResistivity);
  Result.Add('permeability', M.RelativePermeability);
  Result.Add('emissivity', M.Emissivity);
  Result.Add('max_service_temp', M.MaxServiceTemperature);
  Result.Add('melting_temp', M.MeltingTemperature);
end;

function JSONMaterial(O: TJSONObject): TMaterial;
begin
  FillChar(Result, SizeOf(Result), 0);
  if O = nil then Exit;
  Result.Name := O.Get('name', '');
  Result.MaterialClass := TMaterialClass(EnsureRange(O.Get('class', Ord(mcOther)), 0, Ord(High(TMaterialClass))));
  Result.Density := O.Get('density', 0.0);
  Result.YoungModulus := O.Get('young', 0.0);
  Result.Poisson := O.Get('poisson', 0.0);
  Result.ThermalConductivity := O.Get('conductivity', 0.0);
  Result.SpecificHeat := O.Get('specific_heat', 0.0);
  Result.ThermalExpansion := O.Get('expansion', 0.0);
  Result.YieldStrength := O.Get('yield', 0.0);
  Result.ElectricalResistivity := O.Get('resistivity', 0.0);
  Result.RelativePermeability := O.Get('permeability', 0.0);
  Result.Emissivity := O.Get('emissivity', 0.0);
  Result.MaxServiceTemperature := O.Get('max_service_temp', 0.0);
  Result.MeltingTemperature := O.Get('melting_temp', 0.0);
end;

const
  PrimKindNames: array[TGeoPrimKind] of string = ('box', 'cyl', 'prism');

function PrimJSON(const P: TGeoPrimitive): TJSONObject;
var
  A: TJSONArray;
  I: Integer;
begin
  Result := TJSONObject.Create;
  Result.Add('type', PrimKindNames[P.Kind]);
  Result.Add('id', P.ID);
  Result.Add('axis', string(P.Axis));
  Result.Add('at', Vec3JSON(P.At));
  case P.Kind of
    gpBox: Result.Add('size', Vec3JSON(P.Size));
    gpCyl:
      begin
        Result.Add('r', P.R); Result.Add('h', P.H);
        Result.Add('ri', P.RI); Result.Add('r2', P.R2);
        Result.Add('arc', TJSONArray.Create([P.Arc0, P.Arc1]));
        Result.Add('rot', P.Rot);
      end;
    gpPrism:
      begin
        Result.Add('h', P.H);
        A := TJSONArray.Create;
        for I := 0 to High(P.Poly) do A.Add(TJSONArray.Create([P.Poly[I].U, P.Poly[I].V]));
        Result.Add('poly', A);
      end;
  end;
end;

function JSONPrim(O: TJSONObject): TGeoPrimitive;
var
  T, Ax: string;
  A, Pt: TJSONArray;
  I: Integer;
begin
  T := O.Get('type', 'box');
  Ax := O.Get('axis', 'z');
  if Ax = '' then Ax := 'z';
  if T = 'cyl' then
  begin
    Result := CylPrim(O.Get('id', ''), Ax[1], JSONVec3(O.Get('at', TJSONArray(nil))),
      O.Get('r', 0.0), O.Get('h', 0.0), O.Get('ri', 0.0), O.Get('r2', -1.0));
    A := O.Get('arc', TJSONArray(nil));
    if (A <> nil) and (A.Count = 2) then begin Result.Arc0 := A.Floats[0]; Result.Arc1 := A.Floats[1]; end;
    Result.Rot := O.Get('rot', 0.0);
  end
  else if T = 'prism' then
  begin
    Result := PrismPrim(O.Get('id', ''), Ax[1], JSONVec3(O.Get('at', TJSONArray(nil))), O.Get('h', 0.0), []);
    A := O.Get('poly', TJSONArray(nil));
    if A <> nil then
    begin
      SetLength(Result.Poly, A.Count);
      for I := 0 to A.Count - 1 do
      begin
        Pt := A.Arrays[I];
        Result.Poly[I] := V2(Pt.Floats[0], Pt.Floats[1]);
      end;
    end;
  end
  else
    Result := BoxPrim(O.Get('id', ''), JSONVec3(O.Get('at', TJSONArray(nil))), JSONVec3(O.Get('size', TJSONArray(nil))));
end;

function TPhysicsProject.ToJSON: string;
var
  Root, O, E, S: TJSONObject;
  A, PA, Ph: TJSONArray;
  I, J: Integer;
  P: TPhysicsPart;
  B: TBoundaryCondition;
  C: TContact;
  K: TPhysicsKind;
begin
  Root := TJSONObject.Create;
  try
    Root.Add('format', MPHYS_FORMAT);
    Root.Add('app', 'MultiPhysics');
    Root.Add('name', Name);
    Root.Add('assembly', AssemblyFile);
    A := TJSONArray.Create;
    for I := 0 to PartCount - 1 do
    begin
      P := Part(I);
      O := TJSONObject.Create;
      O.Add('id', P.ID); O.Add('name', P.Name); O.Add('kind', P.Kind);
      O.Add('geometry_file', P.GeometryFile);
      O.Add('material', MaterialJSON(P.Material));
      O.Add('position', Vec3JSON(P.Position));
      O.Add('rotation', TJSONArray.Create([P.RotX, P.RotY, P.RotZ]));
      O.Add('scale', Vec3JSON(P.Scale));
      O.Add('pivot', Vec3JSON(P.Pivot));
      O.Add('mesh_size', P.MeshSize);
      O.Add('suppressed', P.Suppressed);
      PA := TJSONArray.Create;
      for J := 0 to High(P.Primitives) do PA.Add(PrimJSON(P.Primitives[J]));
      O.Add('geometry', PA);
      A.Add(O);
    end;
    Root.Add('parts', A);
    A := TJSONArray.Create;
    for I := 0 to BCCount - 1 do
    begin
      B := BC(I);
      O := TJSONObject.Create;
      O.Add('name', B.Name); O.Add('part', B.TargetID); O.Add('face', B.TargetFace);
      O.Add('kind', Ord(B.Kind));
      O.Add('vector', TJSONArray.Create([B.X, B.Y, B.Z]));
      O.Add('value', B.Value); O.Add('value2', B.Value2); O.Add('dof_mask', B.DofMask);
      A.Add(O);
    end;
    Root.Add('boundary_conditions', A);
    A := TJSONArray.Create;
    for I := 0 to ContactCount - 1 do
    begin
      C := Contact(I);
      O := TJSONObject.Create;
      O.Add('name', C.Name); O.Add('part_a', C.PartA); O.Add('part_b', C.PartB);
      O.Add('friction', C.FrictionCoefficient); O.Add('static_friction', C.StaticFrictionCoefficient);
      O.Add('rolling_friction', C.RollingFrictionCoefficient); O.Add('thermal_conductance', C.ThermalConductance);
      A.Add(O);
    end;
    Root.Add('contacts', A);
    E := TJSONObject.Create;
    E.Add('ambient_temperature', Environment.AmbientTemperature);
    E.Add('gravity', TJSONArray.Create([Environment.GravityX, Environment.GravityY, Environment.GravityZ]));
    E.Add('fluid_density', Environment.FluidDensity);
    E.Add('fluid_viscosity', Environment.FluidViscosity);
    E.Add('flow', TJSONArray.Create([Environment.FlowX, Environment.FlowY, Environment.FlowZ]));
    E.Add('drag_coefficient', Environment.DragCoefficient);
    Root.Add('environment', E);
    S := TJSONObject.Create;
    Ph := TJSONArray.Create;
    for K := Low(TPhysicsKind) to High(TPhysicsKind) do
      if K in Settings.Physics then Ph.Add(Ord(K));
    S.Add('physics', Ph);
    S.Add('mesh_size', Settings.MeshSize);
    S.Add('time_step', Settings.TimeStep);
    S.Add('total_time', Settings.TotalTime);
    S.Add('modes', Settings.Modes);
    S.Add('nonlinear', Settings.NonLinear);
    S.Add('quadratic', Settings.Quadratic);
    S.Add('check_convergence', Settings.CheckConvergence);
    S.Add('solver', Settings.Solver);
    Root.Add('settings', S);
    Result := Root.FormatJSON;
  finally
    Root.Free;
  end;
end;

procedure TPhysicsProject.FromJSON(const S: string);
var
  D: TJSONData;
  Root, O, E, St: TJSONObject;
  A, PA, V: TJSONArray;
  I, J, Fmt: Integer;
  P: TPhysicsPart;
  B: TBoundaryCondition;
  C: TContact;
begin
  D := GetJSON(S);
  try
    if not (D is TJSONObject) then raise Exception.Create('Arquivo .mphys invalido');
    Root := TJSONObject(D);
    Fmt := Root.Get('format', 0);
    if (Fmt < 1) or (Fmt > MPHYS_FORMAT) then
      raise Exception.CreateFmt('Formato .mphys %d nao suportado (esta versao le ate %d)', [Fmt, MPHYS_FORMAT]);
    Clear;
    Name := Root.Get('name', 'Projeto');
    AssemblyFile := Root.Get('assembly', '');
    A := Root.Get('parts', TJSONArray(nil));
    if A <> nil then
      for I := 0 to A.Count - 1 do
      begin
        O := A.Objects[I];
        P := TPhysicsPart.Create;
        P.ID := O.Get('id', ''); P.Name := O.Get('name', ''); P.Kind := O.Get('kind', '');
        P.GeometryFile := O.Get('geometry_file', '');
        P.Material := JSONMaterial(O.Get('material', TJSONObject(nil)));
        P.Position := JSONVec3(O.Get('position', TJSONArray(nil)));
        V := O.Get('rotation', TJSONArray(nil));
        if (V <> nil) and (V.Count = 3) then begin P.RotX := V.Floats[0]; P.RotY := V.Floats[1]; P.RotZ := V.Floats[2]; end;
        if O.Find('scale') <> nil then P.Scale := JSONVec3(O.Get('scale', TJSONArray(nil)));
        P.Pivot := JSONVec3(O.Get('pivot', TJSONArray(nil)));
        P.MeshSize := O.Get('mesh_size', 0.0);
        P.Suppressed := O.Get('suppressed', False);
        PA := O.Get('geometry', TJSONArray(nil));
        if PA <> nil then
          for J := 0 to PA.Count - 1 do P.AddPrimitive(JSONPrim(PA.Objects[J]));
        FParts.Add(P);
      end;
    A := Root.Get('boundary_conditions', TJSONArray(nil));
    if A <> nil then
      for I := 0 to A.Count - 1 do
      begin
        O := A.Objects[I];
        B := NewBC(O.Get('name', ''), O.Get('part', ''), O.Get('face', ''),
          TBoundaryKind(EnsureRange(O.Get('kind', 0), 0, Ord(High(TBoundaryKind)))));
        V := O.Get('vector', TJSONArray(nil));
        if (V <> nil) and (V.Count = 3) then begin B.X := V.Floats[0]; B.Y := V.Floats[1]; B.Z := V.Floats[2]; end;
        B.Value := O.Get('value', 0.0); B.Value2 := O.Get('value2', 0.0); B.DofMask := O.Get('dof_mask', 0);
        AddBC(B);
      end;
    A := Root.Get('contacts', TJSONArray(nil));
    if A <> nil then
      for I := 0 to A.Count - 1 do
      begin
        O := A.Objects[I];
        C.Name := O.Get('name', ''); C.PartA := O.Get('part_a', ''); C.PartB := O.Get('part_b', '');
        C.FrictionCoefficient := O.Get('friction', 0.0); C.StaticFrictionCoefficient := O.Get('static_friction', 0.0);
        C.RollingFrictionCoefficient := O.Get('rolling_friction', 0.0); C.ThermalConductance := O.Get('thermal_conductance', 0.0);
        AddContact(C);
      end;
    E := Root.Get('environment', TJSONObject(nil));
    if E <> nil then
    begin
      Environment.AmbientTemperature := E.Get('ambient_temperature', 20.0);
      V := E.Get('gravity', TJSONArray(nil));
      if (V <> nil) and (V.Count = 3) then
      begin
        Environment.GravityX := V.Floats[0]; Environment.GravityY := V.Floats[1]; Environment.GravityZ := V.Floats[2];
      end;
      Environment.FluidDensity := E.Get('fluid_density', 0.0);
      Environment.FluidViscosity := E.Get('fluid_viscosity', 0.0);
      V := E.Get('flow', TJSONArray(nil));
      if (V <> nil) and (V.Count = 3) then
      begin
        Environment.FlowX := V.Floats[0]; Environment.FlowY := V.Floats[1]; Environment.FlowZ := V.Floats[2];
      end;
      Environment.DragCoefficient := E.Get('drag_coefficient', 0.0);
    end;
    St := Root.Get('settings', TJSONObject(nil));
    if St <> nil then
    begin
      Settings.Physics := [];
      V := St.Get('physics', TJSONArray(nil));
      if V <> nil then
        for I := 0 to V.Count - 1 do
          if (V.Integers[I] >= 0) and (V.Integers[I] <= Ord(High(TPhysicsKind))) then
            Include(Settings.Physics, TPhysicsKind(V.Integers[I]));
      Settings.MeshSize := St.Get('mesh_size', 0.005);
      Settings.TimeStep := St.Get('time_step', 0.01);
      Settings.TotalTime := St.Get('total_time', 1.0);
      Settings.Modes := St.Get('modes', 6);
      Settings.NonLinear := St.Get('nonlinear', False);
      Settings.Quadratic := St.Get('quadratic', True);
      Settings.CheckConvergence := St.Get('check_convergence', True);
      Settings.Solver := St.Get('solver', 0);
    end;
    Modified := False;
  finally
    D.Free;
  end;
end;

procedure TPhysicsProject.SaveToFile(const FN: string);
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    L.Text := ToJSON;
    L.SaveToFile(FN);
    FileName := FN;
    Modified := False;
  finally
    L.Free;
  end;
end;

procedure TPhysicsProject.LoadFromFile(const FN: string);
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    L.LoadFromFile(FN);
    FromJSON(L.Text);
    FileName := FN;
  finally
    L.Free;
  end;
end;

function TPhysicsProject.Validate(Log: TStrings): Boolean;
var
  I, Active, Fixes, Thermal: Integer;
  P: TPhysicsPart;
  B: TBoundaryCondition;
  C: TContact;
  M: TMaterial;
  Mech: Boolean;

  procedure Need(const Msg: string);
  begin
    Log.Add(Msg);
    Result := False;
  end;

begin
  Result := True;
  Active := 0;
  for I := 0 to PartCount - 1 do
  begin
    P := Part(I);
    if P.Suppressed then Continue;
    Inc(Active);
    M := P.Material;
    if M.Name = '' then Need(Format('Peca %s sem material.', [P.ID]))
    else
    begin
      if (M.YoungModulus <= 0) or (M.Poisson <= -1) or (M.Poisson >= 0.5) then
        Need(Format('Peca %s: material %s com E ou Poisson invalido.', [P.ID, M.Name]));
      if M.Density <= 0 then Need(Format('Peca %s: densidade invalida.', [P.ID]));
      if (pkThermal in Settings.Physics) and (M.ThermalConductivity <= 0) then
        Need(Format('Peca %s: condutividade termica invalida.', [P.ID]));
    end;
    if Length(P.Primitives) = 0 then Need(Format('Peca %s sem geometria (importe da montagem ou adicione uma primitiva).', [P.ID]));
  end;
  if Active = 0 then Need('Nenhuma peca ativa no projeto.');
  if Settings.MeshSize <= 0 then Need('Tamanho de malha deve ser maior que zero.');
  Fixes := 0; Thermal := 0;
  for I := 0 to BCCount - 1 do
  begin
    B := BC(I);
    if (B.Kind <> bkGravity) and (FindPart(B.TargetID) < 0) then
      Need(Format('Condicao "%s" aponta para a peca inexistente "%s".', [B.Name, B.TargetID]));
    if B.Kind in [bkFixed, bkDisplacement] then Inc(Fixes);
    if B.Kind in [bkTemperature, bkConvection] then Inc(Thermal);
  end;
  Mech := (pkStructural in Settings.Physics) or (pkModal in Settings.Physics);
  if Mech and (Fixes = 0) and (pkStructural in Settings.Physics) then
    Need('Analise estrutural sem fixacao: fixe ao menos uma face.');
  if (pkThermal in Settings.Physics) and (Thermal = 0) then
    Need('Analise termica sem temperatura fixa nem conveccao.');
  for I := 0 to ContactCount - 1 do
  begin
    C := Contact(I);
    if (FindPart(C.PartA) < 0) or (FindPart(C.PartB) < 0) then
      Need(Format('Contato "%s" aponta para peca inexistente.', [C.Name]));
  end;
end;

end.
