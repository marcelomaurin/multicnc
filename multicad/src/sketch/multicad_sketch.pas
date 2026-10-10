unit multicad_sketch;

{ MultiCAD - esboco (sketch): entidades, restricoes e cotas.

  Ids persistentes por entidade (o nome estavel das faces usa esse Id, ex.
  "Extrude2/lat:7"). O solver esta em multicad_solver e os perfis em
  multicad_profile.

  Pontos das entidades (no referencial do plano, mm):
    ponto   P1
    linha   P1 inicio, P2 fim
    arco    P1 centro, P2 inicio, P3 fim (sentido anti-horario)
    circulo P1 centro, Radius
  Referencia a ponto em restricao: (entidade, indice) com indice
    0 = a entidade inteira, 1 = P1, 2 = P2, 3 = P3.
  Entidade CAD_SKETCH_ORIGIN (-1) = origem do esboco (ponto fixo 0,0). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, fpjson, multicad_types, multicad_feature, multicad_refgeom;

const
  CAD_SKETCH_ORIGIN = -1;

type
  TSketchEntity = record
    Id: Integer;
    Kind: TSketchEntityKind;
    P1, P2, P3: TCadVec2;
    Radius: Double;
    Construction: Boolean;
    Centerline: Boolean;   { linha de centro (eixo de revolucao); e construcao }
  end;

  TSketchConstraint = record
    Id: Integer;
    Kind: TConstraintKind;
    EntityA, PointA: Integer;
    EntityB, PointB: Integer;
    EntityC, PointC: Integer;  { simetrica: linha de simetria }
    Value: Double;       { mm ou graus (cotas) }
    Expr: string;        { expressao digitada, ex. "D1@Esboço1/2" }
    DimName: string;     { "D1" (nome completo: D1@<sketch>) }
    Driving: Boolean;    { cota dirigente (comanda) ou dirigida (so mostra) }
    Fix: array of Double; { fixa: coordenadas guardadas }
    TextOff: TCadVec2;   { cota: posicao do texto relativa ao ponto base (mm) }
    HasTextOff: Boolean; { False = posicao automatica }
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
    function AddCenterline(X1, Y1, X2, Y2: Double): Integer;
    { Arco pelo centro, inicio e fim (anti-horario). O fim e ajustado ao raio. }
    function AddArc(CX, CY, X1, Y1, X2, Y2: Double): Integer;
    { Arco por tres pontos (inicio, ponto no meio, fim). 0 se colineares. }
    function AddArc3P(X1, Y1, XM, YM, X2, Y2: Double): Integer;
    function AddCircle(X, Y, R: Double): Integer;
    { Quatro linhas com cantos coincidentes, 2 horizontais e 2 verticais.
      Devolve o Id da primeira (inferior); as outras sao Id+1 (direita),
      Id+2 (superior), Id+3 (esquerda). }
    function AddRectangle(X1, Y1, X2, Y2: Double): Integer;
    { Ranhura reta: centros C1-C2, largura W (= 2R). Duas linhas + dois arcos
      tangentes. Devolve o Id da primeira linha. }
    function AddSlot(X1, Y1, X2, Y2, W: Double): Integer;
    { Poligono regular inscrito: N lados iguais e circulo de construcao.
      Devolve o Id do circulo de construcao. }
    function AddPolygon(CX, CY, R: Double; N: Integer; AStartDeg: Double = 90): Integer;
    function AddConstraint(AKind: TConstraintKind; AEntA, APtA, AEntB, APtB: Integer;
      AValue: Double = 0): Integer;
    function AddSymmetric(AEntA, APtA, AEntB, APtB, ALine: Integer): Integer;
    { Fixa a entidade (APt=0) ou um ponto na posicao atual. }
    function AddFixed(AEnt, APt: Integer): Integer;
    function AddDimension(AKind: TConstraintKind; AEntA, APtA, AEntB, APtB: Integer;
      AValue: Double): Integer;
    procedure DeleteConstraint(AId: Integer);
    { Apaga a entidade e as restricoes/cotas que a usam. }
    procedure DeleteEntity(AId: Integer);
    function EntityCount: Integer;
    function ConstraintCount: Integer;
    function Entity(I: Integer): TSketchEntity;
    function Constraint(I: Integer): TSketchConstraint;
    procedure SetEntity(I: Integer; const E: TSketchEntity);
    procedure SetConstraintValue(I: Integer; AValue: Double);
    procedure SetConstraintExpr(I: Integer; const AExpr: string);
    procedure SetConstraintDriving(I: Integer; ADriving: Boolean);
    { Posicao do texto da cota (arrastar), relativa ao ponto base. }
    procedure SetConstraintTextOffset(I: Integer; const AOff: TCadVec2);
    { Troca as referencias da restricao (filete/chanfro: canto virtual). }
    procedure SetConstraintRefs(I, AEntA, APtA, AEntB, APtB: Integer);
    function EntityIndex(AId: Integer): Integer;
    function ConstraintIndex(AId: Integer): Integer;
    function DimensionIndex(const ADimName: string): Integer;
    function FindDimension(const ADimName: string; out AValue: Double): Boolean;
    { Muda o valor de uma cota pelo nome ("D1"). False se nao existe. }
    function SetDimension(const ADimName: string; AValue: Double): Boolean;
    { Ponto de uma entidade (indice 1..3) ou a origem. }
    function PointOf(AEnt, APt: Integer; out P: TCadVec2): Boolean;
    procedure SaveParams(O: TJSONObject); override;
    procedure LoadParams(O: TJSONObject); override;
    function Validate: string; override;
    function Dependencies: TCadIdArray; override;
  end;

function IsDimensionKind(K: TConstraintKind): Boolean;
{ Linhas de restricao/cota em portugues, como no SolidWorks. }
function CadConstraintName(K: TConstraintKind): string;

implementation

function IsDimensionKind(K: TConstraintKind): Boolean;
begin
  Result := K in [ckDistance, ckHorizontalDistance, ckVerticalDistance,
    ckRadius, ckDiameter, ckAngle];
end;

function CadConstraintName(K: TConstraintKind): string;
const
  N: array[TConstraintKind] of string = ('Coincidente', 'Horizontal',
    'Vertical', 'Paralela', 'Perpendicular', 'Tangente', 'Igual',
    'Concêntrica', 'Ponto médio', 'Fixa', 'Simétrica', 'Cota',
    'Cota horizontal', 'Cota vertical', 'Cota de raio', 'Cota de diâmetro',
    'Cota angular');
begin
  Result := N[K];
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
  Result := Default(TSketchEntity);
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

function TCadSketch.AddCenterline(X1, Y1, X2, Y2: Double): Integer;
var
  I: Integer;
begin
  Result := AddLine(X1, Y1, X2, Y2, True);
  I := EntityIndex(Result);
  FEntities[I].Centerline := True;
end;

function TCadSketch.AddArc(CX, CY, X1, Y1, X2, Y2: Double): Integer;
var
  E: TSketchEntity;
  R, L: Double;
begin
  E := BlankEntity(seArc);
  R := Sqrt(Sqr(X1 - CX) + Sqr(Y1 - CY));
  L := Sqrt(Sqr(X2 - CX) + Sqr(Y2 - CY));
  E.P1 := V2(CX, CY);
  E.P2 := V2(X1, Y1);
  if L > CAD_EPS then
    E.P3 := V2(CX + (X2 - CX) * R / L, CY + (Y2 - CY) * R / L)
  else
    E.P3 := V2(X2, Y2);
  E.Radius := R;
  Result := AddEntity(E);
end;

function TCadSketch.AddArc3P(X1, Y1, XM, YM, X2, Y2: Double): Integer;
var
  D, UX, UY, Cr: Double;
  S1, S2: Double;
begin
  { circunferencia pelos tres pontos }
  D := 2 * (X1 * (YM - Y2) + XM * (Y2 - Y1) + X2 * (Y1 - YM));
  if Abs(D) < 1E-12 then
    Exit(0);
  S1 := X1 * X1 + Y1 * Y1;
  S2 := XM * XM + YM * YM;
  UX := (S1 * (YM - Y2) + S2 * (Y2 - Y1) + (X2 * X2 + Y2 * Y2) * (Y1 - YM)) / D;
  UY := (S1 * (X2 - XM) + S2 * (X1 - X2) + (X2 * X2 + Y2 * Y2) * (XM - X1)) / D;
  { sentido: se o ponto do meio fica a esquerda de 1->2, o arco e anti-horario }
  { (M-1) x (2-1) > 0: o triangulo 1, M, 2 e anti-horario }
  Cr := (XM - X1) * (Y2 - Y1) - (YM - Y1) * (X2 - X1);
  if Cr > 0 then
    Result := AddArc(UX, UY, X1, Y1, X2, Y2)
  else
    Result := AddArc(UX, UY, X2, Y2, X1, Y1);
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

function TCadSketch.AddSlot(X1, Y1, X2, Y2, W: Double): Integer;
var
  DX, DY, L, NX, NY, R: Double;
  LA, LB, A1, A2: Integer;
begin
  R := W / 2;
  DX := X2 - X1;
  DY := Y2 - Y1;
  L := Sqrt(DX * DX + DY * DY);
  if (L < CAD_TOL) or (R < CAD_TOL) then
    Exit(0);
  NX := -DY / L * R;  { normal a esquerda }
  NY := DX / L * R;
  LA := AddLine(X1 - NX, Y1 - NY, X2 - NX, Y2 - NY);   { lado direito, 1 -> 2 }
  A2 := AddArc(X2, Y2, X2 - NX, Y2 - NY, X2 + NX, Y2 + NY);
  LB := AddLine(X2 + NX, Y2 + NY, X1 + NX, Y1 + NY);   { lado esquerdo, 2 -> 1 }
  A1 := AddArc(X1, Y1, X1 + NX, Y1 + NY, X1 - NX, Y1 - NY);
  AddConstraint(ckCoincident, LA, 2, A2, 2);
  AddConstraint(ckCoincident, A2, 3, LB, 1);
  AddConstraint(ckCoincident, LB, 2, A1, 2);
  AddConstraint(ckCoincident, A1, 3, LA, 1);
  AddConstraint(ckTangent, LA, 0, A2, 0);
  AddConstraint(ckTangent, LB, 0, A2, 0);
  AddConstraint(ckTangent, LB, 0, A1, 0);
  AddConstraint(ckTangent, LA, 0, A1, 0);
  AddConstraint(ckEqual, A1, 0, A2, 0);
  Result := LA;
end;

function TCadSketch.AddPolygon(CX, CY, R: Double; N: Integer; AStartDeg: Double): Integer;
var
  I, C: Integer;
  Ids: array of Integer;
  A0, A1: Double;
begin
  if (N < 3) or (R < CAD_TOL) then
    Exit(0);
  C := AddCircle(CX, CY, R);
  FEntities[EntityIndex(C)].Construction := True;
  SetLength(Ids, N);
  for I := 0 to N - 1 do
  begin
    A0 := DegToRadC(AStartDeg + 360 * I / N);
    A1 := DegToRadC(AStartDeg + 360 * (I + 1) / N);
    Ids[I] := AddLine(CX + R * Cos(A0), CY + R * Sin(A0), CX + R * Cos(A1), CY + R * Sin(A1));
  end;
  for I := 0 to N - 1 do
  begin
    AddConstraint(ckCoincident, Ids[I], 2, Ids[(I + 1) mod N], 1);
    AddConstraint(ckCoincident, Ids[I], 1, C, 0);  { vertice no circulo }
    if I > 0 then
      AddConstraint(ckEqual, Ids[0], 0, Ids[I], 0);
  end;
  Result := C;
end;

function TCadSketch.AddConstraint(AKind: TConstraintKind; AEntA, APtA, AEntB,
  APtB: Integer; AValue: Double): Integer;
var
  C: TSketchConstraint;
  N: Integer;
begin
  C := Default(TSketchConstraint);
  C.Kind := AKind;
  C.EntityA := AEntA;
  C.PointA := APtA;
  C.EntityB := AEntB;
  C.PointB := APtB;
  C.Value := AValue;
  C.Driving := True;
  N := Length(FConstraints);
  C.Id := 1;
  if N > 0 then
    C.Id := FConstraints[N - 1].Id + 1;
  SetLength(FConstraints, N + 1);
  FConstraints[N] := C;
  Result := C.Id;
end;

function TCadSketch.AddSymmetric(AEntA, APtA, AEntB, APtB, ALine: Integer): Integer;
begin
  Result := AddConstraint(ckSymmetric, AEntA, APtA, AEntB, APtB);
  FConstraints[High(FConstraints)].EntityC := ALine;
end;

function TCadSketch.AddFixed(AEnt, APt: Integer): Integer;
var
  I, K: Integer;
  E: TSketchEntity;
  F: array of Double;
  procedure Put(const P: TCadVec2);
  begin
    SetLength(F, Length(F) + 2);
    F[High(F) - 1] := P.X;
    F[High(F)] := P.Y;
  end;
begin
  F := nil;
  I := EntityIndex(AEnt);
  if I < 0 then
    Exit(0);
  E := FEntities[I];
  if APt > 0 then
  begin
    case APt of
      1: Put(E.P1);
      2: Put(E.P2);
      3: Put(E.P3);
    end;
  end
  else
    case E.Kind of
      sePoint: Put(E.P1);
      seLine: begin Put(E.P1); Put(E.P2); end;
      seArc: begin Put(E.P1); Put(E.P2); Put(E.P3); end;
      seCircle:
        begin
          Put(E.P1);
          SetLength(F, Length(F) + 1);
          F[High(F)] := E.Radius;
        end;
    end;
  Result := AddConstraint(ckFixed, AEnt, APt, 0, 0);
  K := High(FConstraints);
  FConstraints[K].Fix := Copy(F);
end;

function TCadSketch.AddDimension(AKind: TConstraintKind; AEntA, APtA, AEntB,
  APtB: Integer; AValue: Double): Integer;
begin
  Result := AddConstraint(AKind, AEntA, APtA, AEntB, APtB, AValue);
  FConstraints[High(FConstraints)].DimName := 'D' + IntToStr(FNextDim);
  Inc(FNextDim);
end;

procedure TCadSketch.DeleteConstraint(AId: Integer);
var
  I, J: Integer;
begin
  I := ConstraintIndex(AId);
  if I < 0 then
    Exit;
  for J := I to High(FConstraints) - 1 do
    FConstraints[J] := FConstraints[J + 1];
  SetLength(FConstraints, Length(FConstraints) - 1);
end;

procedure TCadSketch.DeleteEntity(AId: Integer);
var
  I, J: Integer;
begin
  I := EntityIndex(AId);
  if I < 0 then
    Exit;
  for J := I to High(FEntities) - 1 do
    FEntities[J] := FEntities[J + 1];
  SetLength(FEntities, Length(FEntities) - 1);
  for J := High(FConstraints) downto 0 do
    if (FConstraints[J].EntityA = AId) or (FConstraints[J].EntityB = AId) or
      (FConstraints[J].EntityC = AId) then
      DeleteConstraint(FConstraints[J].Id);
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

procedure TCadSketch.SetEntity(I: Integer; const E: TSketchEntity);
begin
  FEntities[I].P1 := E.P1;
  FEntities[I].P2 := E.P2;
  FEntities[I].P3 := E.P3;
  FEntities[I].Radius := E.Radius;
  FEntities[I].Construction := E.Construction;
  FEntities[I].Centerline := E.Centerline;
end;

procedure TCadSketch.SetConstraintValue(I: Integer; AValue: Double);
begin
  FConstraints[I].Value := AValue;
end;

procedure TCadSketch.SetConstraintExpr(I: Integer; const AExpr: string);
begin
  FConstraints[I].Expr := AExpr;
end;

procedure TCadSketch.SetConstraintTextOffset(I: Integer; const AOff: TCadVec2);
begin
  FConstraints[I].TextOff := AOff;
  FConstraints[I].HasTextOff := True;
end;

procedure TCadSketch.SetConstraintRefs(I, AEntA, APtA, AEntB, APtB: Integer);
begin
  FConstraints[I].EntityA := AEntA;
  FConstraints[I].PointA := APtA;
  FConstraints[I].EntityB := AEntB;
  FConstraints[I].PointB := APtB;
end;

procedure TCadSketch.SetConstraintDriving(I: Integer; ADriving: Boolean);
begin
  FConstraints[I].Driving := ADriving;
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

function TCadSketch.ConstraintIndex(AId: Integer): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FConstraints) do
    if FConstraints[I].Id = AId then
      Exit(I);
  Result := -1;
end;

function TCadSketch.DimensionIndex(const ADimName: string): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FConstraints) do
    if SameText(FConstraints[I].DimName, ADimName) then
      Exit(I);
  Result := -1;
end;

function TCadSketch.FindDimension(const ADimName: string; out AValue: Double): Boolean;
var
  I: Integer;
begin
  I := DimensionIndex(ADimName);
  Result := I >= 0;
  if Result then
    AValue := FConstraints[I].Value
  else
    AValue := 0;
end;

function TCadSketch.SetDimension(const ADimName: string; AValue: Double): Boolean;
var
  I: Integer;
begin
  I := DimensionIndex(ADimName);
  Result := I >= 0;
  if Result then
  begin
    FConstraints[I].Value := AValue;
    FConstraints[I].Expr := '';
  end;
end;

function TCadSketch.PointOf(AEnt, APt: Integer; out P: TCadVec2): Boolean;
var
  I: Integer;
begin
  P := V2(0, 0);
  if AEnt = CAD_SKETCH_ORIGIN then
    Exit(True);
  I := EntityIndex(AEnt);
  if I < 0 then
    Exit(False);
  Result := True;
  case APt of
    0, 1: P := FEntities[I].P1;
    2: P := FEntities[I].P2;
    3: P := FEntities[I].P3;
  else
    Result := False;
  end;
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
  Ents, Cons, Fx: TJSONArray;
  E: TJSONObject;
  I, J: Integer;
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
    if FEntities[I].Centerline then
      E.Add('centerline', True);
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
    if FConstraints[I].EntityC <> 0 then
      E.Add('c', TJSONArray.Create([FConstraints[I].EntityC, FConstraints[I].PointC]));
    if Length(FConstraints[I].Fix) > 0 then
    begin
      Fx := TJSONArray.Create;
      for J := 0 to High(FConstraints[I].Fix) do
        Fx.Add(FConstraints[I].Fix[J]);
      E.Add('fix', Fx);
    end;
    if IsDimensionKind(FConstraints[I].Kind) then
    begin
      E.Add('value', FConstraints[I].Value);
      E.Add('dim', FConstraints[I].DimName);
      if FConstraints[I].Expr <> '' then
        E.Add('expr', FConstraints[I].Expr);
      E.Add('driving', FConstraints[I].Driving);
      if FConstraints[I].HasTextOff then
        E.Add('text', TJSONArray.Create([FConstraints[I].TextOff.X, FConstraints[I].TextOff.Y]));
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
  Ents, Cons, Fx: TJSONData;
  EO: TJSONObject;
  I, J: Integer;
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
      E.Centerline := JBool(EO, 'centerline', False);
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
      C := Default(TSketchConstraint);
      C.Kind := CK;
      C.Id := JInt(EO, 'id', I + 1);
      LoadRef(EO, 'a', C.EntityA, C.PointA);
      LoadRef(EO, 'b', C.EntityB, C.PointB);
      LoadRef(EO, 'c', C.EntityC, C.PointC);
      Fx := EO.Find('fix');
      if Fx <> nil then
      begin
        if not (Fx is TJSONArray) then
          raise Exception.Create('"fix" deve ser lista');
        SetLength(C.Fix, Fx.Count);
        for J := 0 to Fx.Count - 1 do
          C.Fix[J] := Fx.Items[J].AsFloat;
      end;
      C.Value := JNum(EO, 'value', 0);
      C.DimName := JStr(EO, 'dim', '');
      C.Expr := JStr(EO, 'expr', '');
      C.Driving := JBool(EO, 'driving', True);
      Fx := EO.Find('text');
      if (Fx is TJSONArray) and (Fx.Count = 2) then
      begin
        C.TextOff := V2(Fx.Items[0].AsFloat, Fx.Items[1].AsFloat);
        C.HasTextOff := True;
      end;
      SetLength(FConstraints, Length(FConstraints) + 1);
      FConstraints[High(FConstraints)] := C;
    end;
  if JInt(O, 'next_entity', 1) > FNextEntityId then
    FNextEntityId := JInt(O, 'next_entity', 1);
  FNextDim := Max(1, JInt(O, 'next_dim', 1));
end;

function TCadSketch.Validate: string;
var
  I: Integer;
  function BadRef(AEnt: Integer): Boolean;
  begin
    Result := (AEnt <> 0) and (AEnt <> CAD_SKETCH_ORIGIN) and (EntityIndex(AEnt) < 0);
  end;
begin
  Result := '';
  if PlaneRef = '' then
    Exit('Esboço sem plano');
  for I := 0 to High(FEntities) do
    if (FEntities[I].Kind in [seArc, seCircle]) and (FEntities[I].Radius <= CAD_TOL) then
      Exit(Format('Raio inválido na entidade %d', [FEntities[I].Id]));
  for I := 0 to High(FConstraints) do
  begin
    if BadRef(FConstraints[I].EntityA) or BadRef(FConstraints[I].EntityB) or
      BadRef(FConstraints[I].EntityC) then
      Exit(Format('Restrição %d aponta para entidade inexistente', [FConstraints[I].Id]));
    if IsDimensionKind(FConstraints[I].Kind) and FConstraints[I].Driving and
      (FConstraints[I].Value <= 0) and (FConstraints[I].Kind <> ckAngle) then
      Exit(Format('Cota %s deve ser maior que zero', [FConstraints[I].DimName]));
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
