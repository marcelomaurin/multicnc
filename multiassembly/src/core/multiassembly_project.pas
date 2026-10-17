unit multiassembly_project;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpjson, jsonparser, multisuite_numfmt, multiassembly_types, multiassembly_geometry,
  multiassembly_library;

type
  TAssemblyProject = class
  private
    FComponents: array of TAssemblyComponent;
    FWires: array of TElectricalConnection;
    FRelations: array of TMechanicalRelation;
    FSteps: array of TManualStep;
    FModified: Boolean;
    FName: string;
    FVersion: string;
    FAuthor: string;
    FUnits: string;
    FFileName: string;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Clear;
    procedure AddComponent(const C: TAssemblyComponent);
    procedure UpdateComponent(Index: Integer; const C: TAssemblyComponent);
    procedure RemoveComponent(const ID: string);
    function DuplicateComponent(const ID, NewID: string): Boolean;

    procedure Connect(const W: TElectricalConnection);
    procedure RemoveWire(Index: Integer);

    procedure Relate(const R: TMechanicalRelation);
    procedure RemoveRelation(Index: Integer);

    procedure AddStep(const S: TManualStep);
    procedure UpdateStep(Index: Integer; const S: TManualStep);
    procedure RemoveStep(Index: Integer);
    procedure MoveStepUp(Index: Integer);
    procedure MoveStepDown(Index: Integer);
    function StepCount: Integer;
    function Step(I: Integer): TManualStep;

    function ComponentCount: Integer;
    function WireCount: Integer;
    function RelationCount: Integer;
    function Component(I: Integer): TAssemblyComponent;
    function Wire(I: Integer): TElectricalConnection;
    function Relation(I: Integer): TMechanicalRelation;
    function FindComponent(const ID: string): Integer;

    function SaveToJSON: string;
    procedure LoadFromJSON(const JSONStr: string);
    procedure SaveToFile(const AFileName: string);
    procedure LoadFromFile(const AFileName: string);

    property Name: string read FName write FName;
    property Version: string read FVersion write FVersion;
    property Author: string read FAuthor write FAuthor;
    property Units: string read FUnits write FUnits;
    property FileName: string read FFileName write FFileName;
    property IsModified: Boolean read FModified write FModified;
  end;

implementation

constructor TAssemblyProject.Create;
begin
  inherited Create;
  FName := 'Sem Titulo';
  FVersion := '1.0';
  FAuthor := 'MultiAssembly';
  FUnits := 'mm';
  FFileName := '';
  FModified := False;
  Clear;
end;

destructor TAssemblyProject.Destroy;
begin
  Clear;
  inherited Destroy;
end;

procedure TAssemblyProject.Clear;
begin
  SetLength(FComponents, 0);
  SetLength(FWires, 0);
  SetLength(FRelations, 0);
  SetLength(FSteps, 0);
  FModified := False;
end;

procedure TAssemblyProject.AddComponent(const C: TAssemblyComponent);
var
  N: Integer;
begin
  if Trim(C.ID) = '' then
    raise Exception.Create('Componente sem ID');
  if FindComponent(C.ID) >= 0 then
    raise Exception.Create('ID duplicado: ' + C.ID);
  N := Length(FComponents);
  SetLength(FComponents, N + 1);
  FComponents[N] := C;
  FModified := True;
end;

procedure TAssemblyProject.UpdateComponent(Index: Integer; const C: TAssemblyComponent);
begin
  if (Index >= 0) and (Index < Length(FComponents)) then
  begin
    FComponents[Index] := C;
    FModified := True;
  end;
end;

procedure TAssemblyProject.RemoveComponent(const ID: string);
var
  Idx, I, Count: Integer;
begin
  Idx := FindComponent(ID);
  if Idx < 0 then Exit;

  // Remove associacoes de fios
  I := 0;
  while I < Length(FWires) do
  begin
    if SameText(FWires[I].FromComponent, ID) or SameText(FWires[I].ToComponent, ID) then
      RemoveWire(I)
    else
      Inc(I);
  end;

  // Remove relacoes mecanicas
  I := 0;
  while I < Length(FRelations) do
  begin
    if SameText(FRelations[I].A, ID) or SameText(FRelations[I].B, ID) then
      RemoveRelation(I)
    else
      Inc(I);
  end;

  // Remove o componente
  Count := Length(FComponents);
  for I := Idx to Count - 2 do
    FComponents[I] := FComponents[I + 1];
  SetLength(FComponents, Count - 1);
  FModified := True;
end;

function TAssemblyProject.DuplicateComponent(const ID, NewID: string): Boolean;
var
  Idx: Integer;
  NewC: TAssemblyComponent;
begin
  Result := False;
  Idx := FindComponent(ID);
  if (Idx < 0) or (FindComponent(NewID) >= 0) then Exit;
  NewC := FComponents[Idx];
  NewC.ID := NewID;
  NewC.Position.X := NewC.Position.X + 20;
  NewC.Position.Y := NewC.Position.Y + 20;
  AddComponent(NewC);
  Result := True;
end;

procedure TAssemblyProject.Connect(const W: TElectricalConnection);
var
  N: Integer;
begin
  N := Length(FWires);
  SetLength(FWires, N + 1);
  FWires[N] := W;
  FModified := True;
end;

procedure TAssemblyProject.RemoveWire(Index: Integer);
var
  I, Count: Integer;
begin
  Count := Length(FWires);
  if (Index < 0) or (Index >= Count) then Exit;
  for I := Index to Count - 2 do
    FWires[I] := FWires[I + 1];
  SetLength(FWires, Count - 1);
  FModified := True;
end;

procedure TAssemblyProject.Relate(const R: TMechanicalRelation);
var
  N: Integer;
begin
  N := Length(FRelations);
  SetLength(FRelations, N + 1);
  FRelations[N] := R;
  FModified := True;
end;

procedure TAssemblyProject.RemoveRelation(Index: Integer);
var
  I, Count: Integer;
begin
  Count := Length(FRelations);
  if (Index < 0) or (Index >= Count) then Exit;
  for I := Index to Count - 2 do
    FRelations[I] := FRelations[I + 1];
  SetLength(FRelations, Count - 1);
  FModified := True;
end;

procedure TAssemblyProject.AddStep(const S: TManualStep);
var
  N: Integer;
begin
  N := Length(FSteps);
  SetLength(FSteps, N + 1);
  FSteps[N] := S;
  if FSteps[N].Order <= 0 then
    FSteps[N].Order := N + 1;
  FModified := True;
end;

procedure TAssemblyProject.UpdateStep(Index: Integer; const S: TManualStep);
begin
  if (Index >= 0) and (Index < Length(FSteps)) then
  begin
    FSteps[Index] := S;
    FModified := True;
  end;
end;

procedure TAssemblyProject.RemoveStep(Index: Integer);
var
  I, Count: Integer;
begin
  Count := Length(FSteps);
  if (Index < 0) or (Index >= Count) then Exit;
  for I := Index to Count - 2 do
  begin
    FSteps[I] := FSteps[I + 1];
    FSteps[I].Order := I + 1;
  end;
  SetLength(FSteps, Count - 1);
  FModified := True;
end;

procedure TAssemblyProject.MoveStepUp(Index: Integer);
var
  Tmp: TManualStep;
begin
  if (Index <= 0) or (Index >= Length(FSteps)) then Exit;
  Tmp := FSteps[Index];
  FSteps[Index] := FSteps[Index - 1];
  FSteps[Index - 1] := Tmp;
  FSteps[Index].Order := Index + 1;
  FSteps[Index - 1].Order := Index;
  FModified := True;
end;

procedure TAssemblyProject.MoveStepDown(Index: Integer);
var
  Tmp: TManualStep;
begin
  if (Index < 0) or (Index >= Length(FSteps) - 1) then Exit;
  Tmp := FSteps[Index];
  FSteps[Index] := FSteps[Index + 1];
  FSteps[Index + 1] := Tmp;
  FSteps[Index].Order := Index + 1;
  FSteps[Index + 1].Order := Index + 2;
  FModified := True;
end;

function TAssemblyProject.StepCount: Integer;
begin
  Result := Length(FSteps);
end;

function TAssemblyProject.Step(I: Integer): TManualStep;
begin
  Result := FSteps[I];
end;

function TAssemblyProject.ComponentCount: Integer;
begin
  Result := Length(FComponents);
end;

function TAssemblyProject.WireCount: Integer;
begin
  Result := Length(FWires);
end;

function TAssemblyProject.RelationCount: Integer;
begin
  Result := Length(FRelations);
end;

function TAssemblyProject.Component(I: Integer): TAssemblyComponent;
begin
  Result := FComponents[I];
end;

function TAssemblyProject.Wire(I: Integer): TElectricalConnection;
begin
  Result := FWires[I];
end;

function TAssemblyProject.Relation(I: Integer): TMechanicalRelation;
begin
  Result := FRelations[I];
end;

function TAssemblyProject.FindComponent(const ID: string): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to High(FComponents) do
    if SameText(FComponents[I].ID, ID) then
      Exit(I);
end;

function TAssemblyProject.SaveToJSON: string;
var
  Root, CompObj, VecObj, WireObj, RelObj, StepObj, PortObj: TJSONObject;
  CompsArr, WiresArr, RelsArr, StepsArr, PortsArr, CompIdsArr: TJSONArray;
  I, J: Integer;
  C: TAssemblyComponent;
  W: TElectricalConnection;
  R: TMechanicalRelation;
  S: TManualStep;
begin
  Root := TJSONObject.Create;
  try
    Root.Add('schema_version', '1.0');
    Root.Add('name', FName);
    Root.Add('version', FVersion);
    Root.Add('author', FAuthor);
    Root.Add('units', FUnits);

    // Componentes
    CompsArr := TJSONArray.Create;
    for I := 0 to High(FComponents) do
    begin
      C := FComponents[I];
      CompObj := TJSONObject.Create;
      CompObj.Add('id', C.ID);
      CompObj.Add('name', C.Name);
      CompObj.Add('model', C.Model);
      CompObj.Add('source_ref', C.SourceRef);
      CompObj.Add('category', C.Category);
      CompObj.Add('material', C.Material);
      CompObj.Add('kind', Ord(C.Kind));
      CompObj.Add('fixed', C.Fixed);
      CompObj.Add('color', C.Color);

      VecObj := TJSONObject.Create;
      VecObj.Add('x', C.Position.X);
      VecObj.Add('y', C.Position.Y);
      VecObj.Add('z', C.Position.Z);
      CompObj.Add('position', VecObj);

      VecObj := TJSONObject.Create;
      VecObj.Add('x', C.Rotation.X);
      VecObj.Add('y', C.Rotation.Y);
      VecObj.Add('z', C.Rotation.Z);
      CompObj.Add('rotation', VecObj);

      VecObj := TJSONObject.Create;
      VecObj.Add('x', C.Size.X);
      VecObj.Add('y', C.Size.Y);
      VecObj.Add('z', C.Size.Z);
      CompObj.Add('size', VecObj);

      PortsArr := TJSONArray.Create;
      for J := 0 to High(C.Ports) do
      begin
        PortObj := TJSONObject.Create;
        PortObj.Add('name', C.Ports[J].Name);
        PortObj.Add('kind', Ord(C.Ports[J].Kind));
        PortObj.Add('voltage', C.Ports[J].Voltage);
        PortsArr.Add(PortObj);
      end;
      CompObj.Add('ports', PortsArr);
      if Length(C.Geometry) > 0 then
        CompObj.Add('geometry', GeometryToJSON(C.Geometry));
      CompsArr.Add(CompObj);
    end;
    Root.Add('components', CompsArr);

    // Conexoes
    WiresArr := TJSONArray.Create;
    for I := 0 to High(FWires) do
    begin
      W := FWires[I];
      WireObj := TJSONObject.Create;
      WireObj.Add('from_component', W.FromComponent);
      WireObj.Add('from_port', W.FromPort);
      WireObj.Add('to_component', W.ToComponent);
      WireObj.Add('to_port', W.ToPort);
      WireObj.Add('caption', W.Caption);
      WiresArr.Add(WireObj);
    end;
    Root.Add('wires', WiresArr);

    // Relacoes mecanicas
    RelsArr := TJSONArray.Create;
    for I := 0 to High(FRelations) do
    begin
      R := FRelations[I];
      RelObj := TJSONObject.Create;
      RelObj.Add('a', R.A);
      RelObj.Add('b', R.B);
      RelObj.Add('kind', Ord(R.Kind));
      VecObj := TJSONObject.Create;
      VecObj.Add('x', R.Axis.X);
      VecObj.Add('y', R.Axis.Y);
      VecObj.Add('z', R.Axis.Z);
      RelObj.Add('axis', VecObj);
      RelObj.Add('ratio', R.Ratio);
      RelObj.Add('pitch_mm', R.PitchMM);
      RelObj.Add('distance', R.Distance);
      RelObj.Add('min_limit', R.MinLimit);
      RelObj.Add('max_limit', R.MaxLimit);
      RelObj.Add('current_value', R.CurrentValue);
      RelObj.Add('flipped', R.Flipped);
      VecObj := TJSONObject.Create;
      VecObj.Add('x', R.Offset.X);
      VecObj.Add('y', R.Offset.Y);
      VecObj.Add('z', R.Offset.Z);
      RelObj.Add('offset', VecObj);
      RelsArr.Add(RelObj);
    end;
    Root.Add('relations', RelsArr);

    // Etapas do manual
    StepsArr := TJSONArray.Create;
    for I := 0 to High(FSteps) do
    begin
      S := FSteps[I];
      StepObj := TJSONObject.Create;
      StepObj.Add('id', S.ID);
      StepObj.Add('order', S.Order);
      StepObj.Add('title', S.Title);
      StepObj.Add('instructions', S.Instructions);
      StepObj.Add('tools', S.Tools);
      StepObj.Add('checks', S.Checks);

      CompIdsArr := TJSONArray.Create;
      for J := 0 to High(S.ComponentIDs) do
        CompIdsArr.Add(S.ComponentIDs[J]);
      StepObj.Add('components', CompIdsArr);
      StepsArr.Add(StepObj);
    end;
    Root.Add('manual_steps', StepsArr);

    Result := Root.FormatJSON;
  finally
    Root.Free;
  end;
end;

procedure TAssemblyProject.LoadFromJSON(const JSONStr: string);
var
  Data: TJSONData;
  Root, CompObj, VecObj, WireObj, RelObj, StepObj, PortObj: TJSONObject;
  CompsArr, WiresArr, RelsArr, StepsArr, PortsArr, CompIdsArr: TJSONArray;
  I, J: Integer;
  C: TAssemblyComponent;
  W: TElectricalConnection;
  R: TMechanicalRelation;
  S: TManualStep;
begin
  if Trim(JSONStr) = '' then Exit;
  Data := GetJSON(JSONStr);
  try
    if not (Data is TJSONObject) then Exit;
    Root := TJSONObject(Data);

    Clear;
    FName := Root.Get('name', 'Sem Titulo');
    FVersion := Root.Get('version', '1.0');
    FAuthor := Root.Get('author', 'MultiAssembly');
    FUnits := Root.Get('units', 'mm');

    CompsArr := Root.Get('components', TJSONArray(nil));
    if CompsArr <> nil then
    begin
      for I := 0 to CompsArr.Count - 1 do
      begin
        CompObj := CompsArr.Objects[I];
        C.ID := CompObj.Get('id', '');
        C.Name := CompObj.Get('name', '');
        C.Model := CompObj.Get('model', '');
        C.SourceRef := CompObj.Get('source_ref', '');
        C.Category := CompObj.Get('category', '');
        C.Material := CompObj.Get('material', '');
        C.Kind := TAssemblyComponentKind(CompObj.Get('kind', 0));
        C.Fixed := CompObj.Get('fixed', False);
        C.Color := CompObj.Get('color', 0);

        VecObj := CompObj.Get('position', TJSONObject(nil));
        if VecObj <> nil then
        begin
          C.Position.X := VecObj.Get('x', 0.0);
          C.Position.Y := VecObj.Get('y', 0.0);
          C.Position.Z := VecObj.Get('z', 0.0);
        end
        else
          C.Position := Vec3(0, 0, 0);

        VecObj := CompObj.Get('rotation', TJSONObject(nil));
        if VecObj <> nil then
        begin
          C.Rotation.X := VecObj.Get('x', 0.0);
          C.Rotation.Y := VecObj.Get('y', 0.0);
          C.Rotation.Z := VecObj.Get('z', 0.0);
        end
        else
          C.Rotation := Vec3(0, 0, 0);

        VecObj := CompObj.Get('size', TJSONObject(nil));
        if VecObj <> nil then
        begin
          C.Size.X := VecObj.Get('x', 10.0);
          C.Size.Y := VecObj.Get('y', 10.0);
          C.Size.Z := VecObj.Get('z', 10.0);
        end
        else
          C.Size := Vec3(10, 10, 10);

        PortsArr := CompObj.Get('ports', TJSONArray(nil));
        if PortsArr <> nil then
        begin
          SetLength(C.Ports, PortsArr.Count);
          for J := 0 to PortsArr.Count - 1 do
          begin
            PortObj := PortsArr.Objects[J];
            C.Ports[J].Name := PortObj.Get('name', '');
            C.Ports[J].Kind := TAssemblyPortKind(PortObj.Get('kind', 0));
            C.Ports[J].Voltage := PortObj.Get('voltage', 0.0);
          end;
        end
        else
          SetLength(C.Ports, 0);

        C.Geometry := ParseGeometryJSON(CompObj.Find('geometry'));
        if Length(C.Geometry) = 0 then
          TAssemblyLibrary.RestoreGeometry(C);

        AddComponent(C);
      end;
    end;

    WiresArr := Root.Get('wires', TJSONArray(nil));
    if WiresArr <> nil then
    begin
      for I := 0 to WiresArr.Count - 1 do
      begin
        WireObj := WiresArr.Objects[I];
        W.FromComponent := WireObj.Get('from_component', '');
        W.FromPort := WireObj.Get('from_port', '');
        W.ToComponent := WireObj.Get('to_component', '');
        W.ToPort := WireObj.Get('to_port', '');
        W.Caption := WireObj.Get('caption', '');
        Connect(W);
      end;
    end;

    RelsArr := Root.Get('relations', TJSONArray(nil));
    if RelsArr <> nil then
    begin
      for I := 0 to RelsArr.Count - 1 do
      begin
        RelObj := RelsArr.Objects[I];
        R.A := RelObj.Get('a', '');
        R.B := RelObj.Get('b', '');
        R.Kind := TMechanicalRelationKind(RelObj.Get('kind', 0));
        VecObj := RelObj.Get('axis', TJSONObject(nil));
        if VecObj <> nil then
        begin
          R.Axis.X := VecObj.Get('x', 0.0);
          R.Axis.Y := VecObj.Get('y', 0.0);
          R.Axis.Z := VecObj.Get('z', 0.0);
        end
        else
          R.Axis := Vec3(0, 0, 1);
        R.Ratio := RelObj.Get('ratio', 1.0);
        R.PitchMM := RelObj.Get('pitch_mm', 0.0);
        R.Distance := RelObj.Get('distance', 0.0);
        R.MinLimit := RelObj.Get('min_limit', 0.0);
        R.MaxLimit := RelObj.Get('max_limit', 0.0);
        R.CurrentValue := RelObj.Get('current_value', 0.0);
        R.Flipped := RelObj.Get('flipped', False);
        VecObj := RelObj.Get('offset', TJSONObject(nil));
        if VecObj <> nil then
        begin
          R.Offset.X := VecObj.Get('x', 0.0);
          R.Offset.Y := VecObj.Get('y', 0.0);
          R.Offset.Z := VecObj.Get('z', 0.0);
        end
        else
          R.Offset := Vec3(0, 0, 0);
        Relate(R);
      end;
    end;

    StepsArr := Root.Get('manual_steps', TJSONArray(nil));
    if StepsArr <> nil then
    begin
      for I := 0 to StepsArr.Count - 1 do
      begin
        StepObj := StepsArr.Objects[I];
        S.ID := StepObj.Get('id', '');
        S.Order := StepObj.Get('order', I + 1);
        S.Title := StepObj.Get('title', '');
        S.Instructions := StepObj.Get('instructions', '');
        S.Tools := StepObj.Get('tools', '');
        S.Checks := StepObj.Get('checks', '');

        CompIdsArr := StepObj.Get('components', TJSONArray(nil));
        if CompIdsArr <> nil then
        begin
          SetLength(S.ComponentIDs, CompIdsArr.Count);
          for J := 0 to CompIdsArr.Count - 1 do
            S.ComponentIDs[J] := CompIdsArr.Strings[J];
        end
        else
          SetLength(S.ComponentIDs, 0);

        AddStep(S);
      end;
    end;

    FModified := False;
  finally
    Data.Free;
  end;
end;

procedure TAssemblyProject.SaveToFile(const AFileName: string);
var
  S: string;
  SL: TStringList;
begin
  S := SaveToJSON;
  SL := TStringList.Create;
  try
    SL.Text := S;
    SL.SaveToFile(AFileName);
    FFileName := AFileName;
    FModified := False;
  finally
    SL.Free;
  end;
end;

procedure TAssemblyProject.LoadFromFile(const AFileName: string);
var
  SL: TStringList;
begin
  SL := TStringList.Create;
  try
    SL.LoadFromFile(AFileName);
    LoadFromJSON(SL.Text);
    FFileName := AFileName;
    FModified := False;
  finally
    SL.Free;
  end;
end;

end.
