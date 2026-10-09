unit multicad_refgeom;

{ MultiCAD - geometria de referencia: origem, planos e eixos
  (ARCHITECTURE.md, secao 3A).

  Referencias a outras entidades sao textos estaveis:
    "plane:<id>"  "axis:<id>"  "face:<nome estavel>"  "edge:<nome>"
    "vertex:<nome>"  "sketch:<id>/<entidade>"
  Na fase 0 os planos padrao ja calculam o referencial; os outros tipos
  guardam os parametros e sao resolvidos pela reconstrucao (fase 2). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpjson, multicad_types, multicad_feature;

type
  TCadPlaneType = (ptStandard, ptOffset, ptParallelPoint, ptAngle, ptMidPlane,
    ptThreePoints, ptLinePoint, ptNormalCurve, ptTangent, ptCoincident);

  TCadAxisType = (atCylinder, atEdge, atTwoPlanes, atTwoPoints, atPointFace);

const
  CAD_PLANE_TYPE_CODES: array[TCadPlaneType] of string = ('standard', 'offset',
    'parallel_point', 'angle', 'mid_plane', 'three_points', 'line_point',
    'normal_curve', 'tangent', 'coincident');
  CAD_PLANE_TYPE_NAMES: array[TCadPlaneType] of string = ('Padrão', 'Deslocado',
    'Paralelo por ponto', 'Em ângulo', 'Plano médio', 'Por três pontos',
    'Por linha e ponto', 'Normal à curva', 'Tangente à face cilíndrica',
    'Coincidente');
  { Quantidade de referencias exigida por tipo. }
  CAD_PLANE_TYPE_REFS: array[TCadPlaneType] of Integer = (0, 1, 2, 2, 2, 3, 2,
    2, 2, 1);
  CAD_AXIS_TYPE_CODES: array[TCadAxisType] of string = ('cylinder', 'edge',
    'two_planes', 'two_points', 'point_face');
  CAD_AXIS_TYPE_REFS: array[TCadAxisType] of Integer = (1, 1, 2, 2, 2);

type
  TCadOrigin = class(TCadFeature)
  public
    constructor Create; override;
  end;

  TCadPlane = class(TCadFeature)
  public
    PlaneType: TCadPlaneType;
    Std: TCadStdPlane;
    Refs: TCadStrArray;
    Distance: Double;   { mm (deslocado) }
    Angle: Double;      { graus (em angulo) }
    Flip: Boolean;
    Count: Integer;     { numero de planos (deslocado / em angulo) }
    { Referencial calculado: padrao ja na criacao, outros na reconstrucao. }
    Frame: TCadFrame;
    FrameValid: Boolean;
    constructor Create; override;
    constructor CreateStd(AStd: TCadStdPlane);
    procedure SaveParams(O: TJSONObject); override;
    procedure LoadParams(O: TJSONObject); override;
    function Validate: string; override;
    function Dependencies: TCadIdArray; override;
  end;

  TCadAxis = class(TCadFeature)
  public
    AxisType: TCadAxisType;
    Refs: TCadStrArray;
    Origin, Direction: TCadVec3;
    Valid: Boolean;
    constructor Create; override;
    procedure SaveParams(O: TJSONObject); override;
    procedure LoadParams(O: TJSONObject); override;
    function Validate: string; override;
    function Dependencies: TCadIdArray; override;
  end;

{ Id da operacao em referencias "plane:5", "axis:7", "sketch:3/12" (0 se nao for). }
function CadRefFeatureId(const ARef: string): Integer;
procedure SaveStrArray(O: TJSONObject; const K: string; const A: TCadStrArray);
function LoadStrArray(O: TJSONObject; const K: string): TCadStrArray;
procedure SaveVec3(O: TJSONObject; const K: string; const V: TCadVec3);
function LoadVec3(O: TJSONObject; const K: string; const Def: TCadVec3): TCadVec3;

implementation

function CadRefFeatureId(const ARef: string): Integer;
var
  P, Q: Integer;
  Pre, Rest: string;
begin
  Result := 0;
  P := Pos(':', ARef);
  if P = 0 then
    Exit;
  Pre := Copy(ARef, 1, P - 1);
  if (Pre <> 'plane') and (Pre <> 'axis') and (Pre <> 'sketch') and (Pre <> 'feature') then
    Exit;
  Rest := Copy(ARef, P + 1, MaxInt);
  Q := Pos('/', Rest);
  if Q > 0 then
    Rest := Copy(Rest, 1, Q - 1);
  Result := StrToIntDef(Rest, 0);
end;

procedure SaveStrArray(O: TJSONObject; const K: string; const A: TCadStrArray);
var
  Arr: TJSONArray;
  I: Integer;
begin
  Arr := TJSONArray.Create;
  for I := 0 to High(A) do
    Arr.Add(A[I]);
  O.Add(K, Arr);
end;

function LoadStrArray(O: TJSONObject; const K: string): TCadStrArray;
var
  D: TJSONData;
  I: Integer;
begin
  Result := nil;
  D := O.Find(K);
  if D = nil then
    Exit;
  if not (D is TJSONArray) then
    raise Exception.CreateFmt('Campo "%s" deve ser lista', [K]);
  SetLength(Result, D.Count);
  for I := 0 to D.Count - 1 do
  begin
    if D.Items[I].JSONType <> jtString then
      raise Exception.CreateFmt('Campo "%s" deve ser lista de textos', [K]);
    Result[I] := D.Items[I].AsString;
  end;
end;

procedure SaveVec3(O: TJSONObject; const K: string; const V: TCadVec3);
begin
  O.Add(K, TJSONArray.Create([V.X, V.Y, V.Z]));
end;

function LoadVec3(O: TJSONObject; const K: string; const Def: TCadVec3): TCadVec3;
var
  D: TJSONData;
begin
  D := O.Find(K);
  if D = nil then
    Exit(Def);
  if not (D is TJSONArray) or (D.Count <> 3) then
    raise Exception.CreateFmt('Campo "%s" deve ser [x, y, z]', [K]);
  Result := V3(D.Items[0].AsFloat, D.Items[1].AsFloat, D.Items[2].AsFloat);
end;

function RefsDeps(const A: TCadStrArray): TCadIdArray;
var
  I, Id: Integer;
begin
  Result := nil;
  for I := 0 to High(A) do
  begin
    Id := CadRefFeatureId(A[I]);
    if Id > 0 then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := Id;
    end;
  end;
end;

{ TCadOrigin }

constructor TCadOrigin.Create;
begin
  inherited Create;
  SetKind(cfOrigin);
  Name := 'Origem';
end;

{ TCadPlane }

constructor TCadPlane.Create;
begin
  inherited Create;
  SetKind(cfPlane);
  PlaneType := ptOffset;
  Count := 1;
  FrameValid := False;
end;

constructor TCadPlane.CreateStd(AStd: TCadStdPlane);
begin
  Create;
  PlaneType := ptStandard;
  Std := AStd;
  Name := CAD_STD_PLANE_NAMES[AStd];
  Frame := StdFrame(AStd);
  FrameValid := True;
end;

procedure TCadPlane.SaveParams(O: TJSONObject);
begin
  O.Add('type', CAD_PLANE_TYPE_CODES[PlaneType]);
  if PlaneType = ptStandard then
  begin
    case Std of
      spFrontal: O.Add('std', 'frontal');
      spSuperior: O.Add('std', 'superior');
      spLateral: O.Add('std', 'lateral');
    end;
    Exit;
  end;
  SaveStrArray(O, 'refs', Refs);
  O.Add('distance', Distance);
  O.Add('angle', Angle);
  O.Add('flip', Flip);
  O.Add('count', Count);
end;

procedure TCadPlane.LoadParams(O: TJSONObject);
var
  T, S: string;
  K: TCadPlaneType;
  Found: Boolean;
begin
  T := JStr(O, 'type', 'offset');
  Found := False;
  for K := Low(TCadPlaneType) to High(TCadPlaneType) do
    if CAD_PLANE_TYPE_CODES[K] = T then
    begin
      PlaneType := K;
      Found := True;
    end;
  if not Found then
    raise Exception.CreateFmt('Tipo de plano desconhecido "%s"', [T]);
  if PlaneType = ptStandard then
  begin
    S := JStr(O, 'std', 'frontal');
    if S = 'frontal' then Std := spFrontal
    else if S = 'superior' then Std := spSuperior
    else if S = 'lateral' then Std := spLateral
    else
      raise Exception.CreateFmt('Plano padrão desconhecido "%s"', [S]);
    Frame := StdFrame(Std);
    FrameValid := True;
    Exit;
  end;
  Refs := LoadStrArray(O, 'refs');
  Distance := JNum(O, 'distance', 0);
  Angle := JNum(O, 'angle', 0);
  Flip := JBool(O, 'flip', False);
  Count := JInt(O, 'count', 1);
  FrameValid := False;
end;

function TCadPlane.Validate: string;
begin
  Result := '';
  if PlaneType = ptStandard then
    Exit;
  if Length(Refs) < CAD_PLANE_TYPE_REFS[PlaneType] then
    Exit(Format('%s precisa de %d referência(s)',
      [CAD_PLANE_TYPE_NAMES[PlaneType], CAD_PLANE_TYPE_REFS[PlaneType]]));
  if (Count < 1) or (Count > 100) then
    Exit('Número de planos deve ficar entre 1 e 100');
  if (PlaneType = ptOffset) and (Abs(Distance) < CAD_TOL) then
    Exit('Distância do plano deslocado deve ser diferente de zero');
  if (PlaneType = ptAngle) and ((Abs(Angle) < CAD_ANGLE_TOL) or (Abs(Angle) >= 360)) then
    Exit('Ângulo do plano deve ficar entre 0° e 360°');
end;

function TCadPlane.Dependencies: TCadIdArray;
begin
  Result := RefsDeps(Refs);
end;

{ TCadAxis }

constructor TCadAxis.Create;
begin
  inherited Create;
  SetKind(cfAxis);
  AxisType := atCylinder;
  Direction := V3(0, 0, 1);
end;

procedure TCadAxis.SaveParams(O: TJSONObject);
begin
  O.Add('type', CAD_AXIS_TYPE_CODES[AxisType]);
  SaveStrArray(O, 'refs', Refs);
end;

procedure TCadAxis.LoadParams(O: TJSONObject);
var
  T: string;
  K: TCadAxisType;
  Found: Boolean;
begin
  T := JStr(O, 'type', 'cylinder');
  Found := False;
  for K := Low(TCadAxisType) to High(TCadAxisType) do
    if CAD_AXIS_TYPE_CODES[K] = T then
    begin
      AxisType := K;
      Found := True;
    end;
  if not Found then
    raise Exception.CreateFmt('Tipo de eixo desconhecido "%s"', [T]);
  Refs := LoadStrArray(O, 'refs');
  Valid := False;
end;

function TCadAxis.Validate: string;
begin
  if Length(Refs) < CAD_AXIS_TYPE_REFS[AxisType] then
    Result := Format('Eixo precisa de %d referência(s)', [CAD_AXIS_TYPE_REFS[AxisType]])
  else
    Result := '';
end;

function TCadAxis.Dependencies: TCadIdArray;
begin
  Result := RefsDeps(Refs);
end;

initialization
  RegisterCadFeature(cfOrigin, TCadOrigin);
  RegisterCadFeature(cfPlane, TCadPlane);
  RegisterCadFeature(cfAxis, TCadAxis);

end.
