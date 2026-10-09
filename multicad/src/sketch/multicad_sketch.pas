unit multicad_sketch;

{ MultiCAD - esboco (sketch): entidades, restricoes e cotas.

  Fase 0: modelo de dados com Ids persistentes por entidade (o nome
  estavel das faces usa esse Id, ex. "Extrude2/lat:7") e JSON.
  Fase 1: solver Newton/LM, graus de liberdade e perfis.

  Pontos das entidades (no referencial do plano, mm):
    ponto   P1
    linha   P1 inicio, P2 fim
    arco    P1 centro, P2 inicio, P3 fim (sentido anti-horario)
    circulo P1 centro, Radius
  Referencia a ponto em restricao: (entidade, indice) com indice
    0 = a entidade inteira, 1 = P1, 2 = P2, 3 = P3. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpjson, multicad_types, multicad_feature, multicad_refgeom;

type
  TSketchEntity = record
    Id: Integer;
    Kind: TSketchEntityKind;
    P1, P2, P3: TCadVec2;
    Radius: Double;
    Construction: Boolean;
  end;

  TSketchConstraint = record
    Id: Integer;
    Kind: TConstraintKind;
    EntityA, PointA: Integer;
    EntityB, PointB: Integer;
    Value: Double;       { mm ou graus (cotas) }
    Expr: string;        { expressao digitada, ex. "D1@Esboço1/2" }
    DimName: string;     { "D1" (nome completo: D1@<sketch>) }
    Driving: Boolean;    { cota dirigente (comanda) ou dirigida (so mostra) }
  end;

  TCadSketch = class(TCadFeature)
  private
    FEntities: array of TSketchEntity;
    FConstraints: array of TSketchConstraint;
    FNextEntityId: Integer;
    FNextDim: Integer;
    function NewEntityId: Integer;
    function AddEntity(const E: TSketchEntity): Integer;
  public
    PlaneRef: string;   { "plane:1" ou "face:<nome estavel>" }
    constructor Create; override;
    procedure Clear;
    function AddPoint(X, Y: Double): Integer;
    function AddLine(X1, Y1, X2, Y2: Double; AConstruction: Boolean = False): Integer;
    function AddArc(CX, CY, X1, Y1, X2, Y2: Double): Integer;
    function AddCircle(X, Y, R: Double): Integer;
    { Quatro linhas; devolve o Id da primeira (as outras sao Id+1..Id+3). }
    function AddRectangle(X1, Y1, X2, Y2: Double): Integer;
    function AddConstraint(AKind: TConstraintKind; AEntA, APtA, AEntB, APtB: Integer;
      AValue: Double = 0): Integer;
    function AddDimension(AKind: TConstraintKind; AEntA, APtA, AEntB, APtB: Integer;
      AValue: Double): Integer;
    function EntityCount: Integer;
    function ConstraintCount: Integer;
    function Entity(I: Integer): TSketchEntity;
    function Constraint(I: Integer): TSketchConstraint;
    function EntityIndex(AId: Integer): Integer;
    function FindDimension(const ADimName: string; out AValue: Double): Boolean;
    procedure SaveParams(O: TJSONObject); override;
    procedure LoadParams(O: TJSONObject); override;
    function Validate: string; override;
    function Dependencies: TCadIdArray; override;
  end;

function IsDimensionKind(K: TConstraintKind): Boolean;

implementation

function IsDimensionKind(K: TConstraintKind): Boolean;
begin
  Result := K in [ckDistance, ckHorizontalDistance, ckVerticalDistance,
    ckRadius, ckDiameter, ckAngle];
end;

constructor TCadSketch.Create;
begin
  inherited Create;
  SetKind(cfSketch);
  PlaneRef := 'plane:1';
  FNextEntityId := 1;
  FNextDim := 1;
end;

procedure TCadSketch.Clear;
begin
  SetLength(FEntities, 0);
  SetLength(FConstraints, 0);
  FNextEntityId := 1;
  FNextDim := 1;
end;

function TCadSketch.NewEntityId: Integer;
begin
  Result := FNextEntityId;
  Inc(FNextEntityId);
end;

function TCadSketch.AddEntity(const E: TSketchEntity): Integer;
var
  N: Integer;
begin
  N := Length(FEntities);
  SetLength(FEntities, N + 1);
  FEntities[N] := E;
  if FEntities[N].Id <= 0 then
    FEntities[N].Id := NewEntityId
  else if FEntities[N].Id >= FNextEntityId then
    FNextEntityId := FEntities[N].Id + 1;
  Result := FEntities[N].Id;
end;

function BlankEntity(AKind: TSketchEntityKind): TSketchEntity;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Kind := AKind;
end;

function TCadSketch.AddPoint(X, Y: Double): Integer;
var
  E: TSketchEntity;
begin
  E := BlankEntity(sePoint);
  E.P1 := V2(X, Y);
  Result := AddEntity(E);
end;

function TCadSketch.AddLine(X1, Y1, X2, Y2: Double; AConstruction: Boolean): Integer;
var
  E: TSketchEntity;
begin
  E := BlankEntity(seLine);
  E.P1 := V2(X1, Y1);
  E.P2 := V2(X2, Y2);
  E.Construction := AConstruction;
  Result := AddEntity(E);
end;

function TCadSketch.AddArc(CX, CY, X1, Y1, X2, Y2: Double): Integer;
var
  E: TSketchEntity;
begin
  E := BlankEntity(seArc);
  E.P1 := V2(CX, CY);
  E.P2 := V2(X1, Y1);
  E.P3 := V2(X2, Y2);
  E.Radius := Sqrt(Sqr(X1 - CX) + Sqr(Y1 - CY));
  Result := AddEntity(E);
end;

function TCadSketch.AddCircle(X, Y, R: Double): Integer;
var
  E: TSketchEntity;
begin
  E := BlankEntity(seCircle);
  E.P1 := V2(X, Y);
  E.Radius := R;
  Result := AddEntity(E);
end;

function TCadSketch.AddRectangle(X1, Y1, X2, Y2: Double): Integer;
var
  L1, L2, L3, L4: Integer;
begin
  L1 := AddLine(X1, Y1, X2, Y1);
  L2 := AddLine(X2, Y1, X2, Y2);
  L3 := AddLine(X2, Y2, X1, Y2);
  L4 := AddLine(X1, Y2, X1, Y1);
  { cantos coincidentes, como o retangulo do SolidWorks }
  AddConstraint(ckCoincident, L1, 2, L2, 1);
  AddConstraint(ckCoincident, L2, 2, L3, 1);
  AddConstraint(ckCoincident, L3, 2, L4, 1);
  AddConstraint(ckCoincident, L4, 2, L1, 1);
  AddConstraint(ckHorizontal, L1, 0, 0, 0);
  AddConstraint(ckHorizontal, L3, 0, 0, 0);
  AddConstraint(ckVertical, L2, 0, 0, 0);
  AddConstraint(ckVertical, L4, 0, 0, 0);
  Result := L1;
end;

function TCadSketch.AddConstraint(AKind: TConstraintKind; AEntA, APtA, AEntB,
  APtB: Integer; AValue: Double): Integer;
var
  C: TSketchConstraint;
  N: Integer;
begin
  C.Kind := AKind;
  C.EntityA := AEntA;
  C.PointA := APtA;
  C.EntityB := AEntB;
  C.PointB := APtB;
  C.Value := AValue;
  C.Expr := '';
  C.DimName := '';
  C.Driving := True;
  N := Length(FConstraints);
  C.Id := N + 1;
  if N > 0 then
    C.Id := FConstraints[N - 1].Id + 1;
  SetLength(FConstraints, N + 1);
  FConstraints[N] := C;
  Result := C.Id;
end;

function TCadSketch.AddDimension(AKind: TConstraintKind; AEntA, APtA, AEntB,
  APtB: Integer; AValue: Double): Integer;
begin
  Result := AddConstraint(AKind, AEntA, APtA, AEntB, APtB, AValue);
  FConstraints[High(FConstraints)].DimName := 'D' + IntToStr(FNextDim);
  Inc(FNextDim);
end;

function TCadSketch.EntityCount: Integer;
begin
  Result := Length(FEntities);
end;

function TCadSketch.ConstraintCount: Integer;
begin
  Result := Length(FConstraints);
end;

function TCadSketch.Entity(I: Integer): TSketchEntity;
begin
  Result := FEntities[I];
end;

function TCadSketch.Constraint(I: Integer): TSketchConstraint;
begin
  Result := FConstraints[I];
end;

function TCadSketch.EntityIndex(AId: Integer): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FEntities) do
    if FEntities[I].Id = AId then
      Exit(I);
  Result := -1;
end;

function TCadSketch.FindDimension(const ADimName: string; out AValue: Double): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(FConstraints) do
    if SameText(FConstraints[I].DimName, ADimName) then
    begin
      AValue := FConstraints[I].Value;
      Exit(True);
    end;
  AValue := 0;
  Result := False;
end;

function KindFromCode(const S: string; out K: TSketchEntityKind): Boolean;
var
  I: TSketchEntityKind;
begin
  for I := Low(TSketchEntityKind) to High(TSketchEntityKind) do
    if CAD_ENTITY_CODES[I] = S then
    begin
      K := I;
      Exit(True);
    end;
  K := sePoint;
  Result := False;
end;

function CKindFromCode(const S: string; out K: TConstraintKind): Boolean;
var
  I: TConstraintKind;
begin
  for I := Low(TConstraintKind) to High(TConstraintKind) do
    if CAD_CONSTRAINT_CODES[I] = S then
    begin
      K := I;
      Exit(True);
    end;
  K := ckCoincident;
  Result := False;
end;

procedure SaveV2(O: TJSONObject; const K: string; const V: TCadVec2);
begin
  O.Add(K, TJSONArray.Create([V.X, V.Y]));
end;

function LoadV2(O: TJSONObject; const K: string): TCadVec2;
var
  D: TJSONData;
begin
  D := O.Find(K);
  if D = nil then
    Exit(V2(0, 0));
  if not (D is TJSONArray) or (D.Count <> 2) then
    raise Exception.CreateFmt('Ponto "%s" deve ser [x, y]', [K]);
  Result := V2(D.Items[0].AsFloat, D.Items[1].AsFloat);
end;

procedure TCadSketch.SaveParams(O: TJSONObject);
var
  Ents, Cons: TJSONArray;
  E: TJSONObject;
  I: Integer;
begin
  O.Add('plane', PlaneRef);
  O.Add('next_entity', FNextEntityId);
  O.Add('next_dim', FNextDim);
  Ents := TJSONArray.Create;
  for I := 0 to High(FEntities) do
  begin
    E := TJSONObject.Create;
    E.Add('id', FEntities[I].Id);
    E.Add('kind', CAD_ENTITY_CODES[FEntities[I].Kind]);
    SaveV2(E, 'p1', FEntities[I].P1);
    if FEntities[I].Kind in [seLine, seArc] then
      SaveV2(E, 'p2', FEntities[I].P2);
    if FEntities[I].Kind = seArc then
      SaveV2(E, 'p3', FEntities[I].P3);
    if FEntities[I].Kind in [seArc, seCircle] then
      E.Add('r', FEntities[I].Radius);
    if FEntities[I].Construction then
      E.Add('construction', True);
    Ents.Add(E);
  end;
  O.Add('entities', Ents);
  Cons := TJSONArray.Create;
  for I := 0 to High(FConstraints) do
  begin
    E := TJSONObject.Create;
    E.Add('id', FConstraints[I].Id);
    E.Add('kind', CAD_CONSTRAINT_CODES[FConstraints[I].Kind]);
    E.Add('a', TJSONArray.Create([FConstraints[I].EntityA, FConstraints[I].PointA]));
    if FConstraints[I].EntityB <> 0 then
      E.Add('b', TJSONArray.Create([FConstraints[I].EntityB, FConstraints[I].PointB]));
    if IsDimensionKind(FConstraints[I].Kind) then
    begin
      E.Add('value', FConstraints[I].Value);
      E.Add('dim', FConstraints[I].DimName);
      if FConstraints[I].Expr <> '' then
        E.Add('expr', FConstraints[I].Expr);
      E.Add('driving', FConstraints[I].Driving);
    end;
    Cons.Add(E);
  end;
  O.Add('constraints', Cons);
end;

procedure LoadRef(O: TJSONObject; const K: string; out AEnt, APt: Integer);
var
  D: TJSONData;
begin
  AEnt := 0;
  APt := 0;
  D := O.Find(K);
  if D = nil then
    Exit;
  if not (D is TJSONArray) or (D.Count <> 2) then
    raise Exception.CreateFmt('Referência "%s" deve ser [entidade, ponto]', [K]);
  AEnt := D.Items[0].AsInteger;
  APt := D.Items[1].AsInteger;
  if (APt < 0) or (APt > 3) then
    raise Exception.CreateFmt('Índice de ponto inválido em "%s"', [K]);
end;

procedure TCadSketch.LoadParams(O: TJSONObject);
var
  Ents, Cons: TJSONData;
  EO: TJSONObject;
  I: Integer;
  E: TSketchEntity;
  C: TSketchConstraint;
  K: TSketchEntityKind;
  CK: TConstraintKind;
begin
  Clear;
  PlaneRef := JStr(O, 'plane', 'plane:1');
  Ents := O.Find('entities');
  if (Ents <> nil) and not (Ents is TJSONArray) then
    raise Exception.Create('"entities" deve ser lista');
  if Ents <> nil then
    for I := 0 to Ents.Count - 1 do
    begin
      if not (Ents.Items[I] is TJSONObject) then
        raise Exception.Create('Entidade inválida');
      EO := TJSONObject(Ents.Items[I]);
      if not KindFromCode(JStr(EO, 'kind', ''), K) then
        raise Exception.CreateFmt('Entidade de tipo desconhecido "%s"', [JStr(EO, 'kind', '')]);
      E := BlankEntity(K);
      E.Id := JInt(EO, 'id', 0);
      if E.Id <= 0 then
        raise Exception.Create('Entidade sem Id');
      if EntityIndex(E.Id) >= 0 then
        raise Exception.CreateFmt('Id de entidade repetido: %d', [E.Id]);
      E.P1 := LoadV2(EO, 'p1');
      E.P2 := LoadV2(EO, 'p2');
      E.P3 := LoadV2(EO, 'p3');
      E.Radius := JNum(EO, 'r', 0);
      E.Construction := JBool(EO, 'construction', False);
      AddEntity(E);
    end;
  Cons := O.Find('constraints');
  if (Cons <> nil) and not (Cons is TJSONArray) then
    raise Exception.Create('"constraints" deve ser lista');
  if Cons <> nil then
    for I := 0 to Cons.Count - 1 do
    begin
      if not (Cons.Items[I] is TJSONObject) then
        raise Exception.Create('Restrição inválida');
      EO := TJSONObject(Cons.Items[I]);
      if not CKindFromCode(JStr(EO, 'kind', ''), CK) then
        raise Exception.CreateFmt('Restrição de tipo desconhecido "%s"', [JStr(EO, 'kind', '')]);
      C.Kind := CK;
      C.Id := JInt(EO, 'id', I + 1);
      LoadRef(EO, 'a', C.EntityA, C.PointA);
      LoadRef(EO, 'b', C.EntityB, C.PointB);
      C.Value := JNum(EO, 'value', 0);
      C.DimName := JStr(EO, 'dim', '');
      C.Expr := JStr(EO, 'expr', '');
      C.Driving := JBool(EO, 'driving', True);
      SetLength(FConstraints, Length(FConstraints) + 1);
      FConstraints[High(FConstraints)] := C;
    end;
  { contadores gravados nunca voltam para tras }
  if JInt(O, 'next_entity', 1) > FNextEntityId then
    FNextEntityId := JInt(O, 'next_entity', 1);
  FNextDim := JInt(O, 'next_dim', 1);
end;

function TCadSketch.Validate: string;
var
  I: Integer;
begin
  Result := '';
  if PlaneRef = '' then
    Exit('Esboço sem plano');
  for I := 0 to High(FEntities) do
    if (FEntities[I].Kind in [seArc, seCircle]) and (FEntities[I].Radius <= CAD_TOL) then
      Exit(Format('Raio inválido na entidade %d', [FEntities[I].Id]));
  for I := 0 to High(FConstraints) do
  begin
    if (FConstraints[I].EntityA <> 0) and (EntityIndex(FConstraints[I].EntityA) < 0) then
      Exit(Format('Restrição %d aponta para entidade inexistente %d',
        [FConstraints[I].Id, FConstraints[I].EntityA]));
    if (FConstraints[I].EntityB <> 0) and (EntityIndex(FConstraints[I].EntityB) < 0) then
      Exit(Format('Restrição %d aponta para entidade inexistente %d',
        [FConstraints[I].Id, FConstraints[I].EntityB]));
  end;
end;

function TCadSketch.Dependencies: TCadIdArray;
var
  RefId: Integer;
begin
  Result := nil;
  RefId := CadRefFeatureId(PlaneRef);
  if RefId > 0 then
  begin
    SetLength(Result, 1);
    Result[0] := RefId;
  end;
end;

initialization
  RegisterCadFeature(cfSketch, TCadSketch);

end.
