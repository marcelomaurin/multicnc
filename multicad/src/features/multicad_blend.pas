unit multicad_blend;

{ MultiCAD - Filete, Chanfro e Casca no solido (fase 6).

  Arestas (texto estavel, pelos nomes das duas faces):
    "edge:<faceA>|<faceB>"  todas as arestas entre as duas faces
    "face:<nome>"           todas as arestas da face (como no SolidWorks)
  Suportado nesta versao: arestas retas entre faces planas e arestas
  circulares entre face plana e face cilindrica (circulo completo). Aresta
  convexa = remove material; concava = acrescenta. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, fpjson, multicad_types, multicad_feature,
  multicad_refgeom;

type
  TCadChamferMode = (cmDistance, cmDistanceDistance, cmDistanceAngle);

  TCadBlendBase = class(TCadFeature)
  public
    Edges: TCadStrArray;
    procedure SaveParams(O: TJSONObject); override;
    procedure LoadParams(O: TJSONObject); override;
    function Validate: string; override;
  end;

  TCadFillet3D = class(TCadBlendBase)
  public
    Radius: Double;
    constructor Create; override;
    procedure SaveParams(O: TJSONObject); override;
    procedure LoadParams(O: TJSONObject); override;
    function Validate: string; override;
  end;

  TCadChamfer3D = class(TCadBlendBase)
  public
    Mode: TCadChamferMode;
    Distance: Double;
    Distance2: Double;
    Angle: Double;          { graus (modo distancia-angulo) }
    Flip: Boolean;          { troca o lado das distancias }
    constructor Create; override;
    procedure SaveParams(O: TJSONObject); override;
    procedure LoadParams(O: TJSONObject); override;
    function Validate: string; override;
    { Distancias sobre a primeira e a segunda face. }
    procedure Distances(out D1, D2: Double);
  end;

  TCadShell = class(TCadFeature)
  public
    Thickness: Double;
    Faces: TCadStrArray;    { faces removidas ("face:<nome>") }
    Outward: Boolean;       { espessura para fora }
    constructor Create; override;
    procedure SaveParams(O: TJSONObject); override;
    procedure LoadParams(O: TJSONObject); override;
    function Validate: string; override;
  end;

const
  CAD_CHAMFER_MODE_CODES: array[TCadChamferMode] of string = ('distance', 'distance_distance',
    'distance_angle');
  CAD_CHAMFER_MODE_NAMES: array[TCadChamferMode] of string = ('Distância igual',
    'Distância-distância', 'Ângulo-distância');

{ Referencia de aresta pelas duas faces (ordem fixa, para comparar). }
function CadEdgeRef(const FaceA, FaceB: string): string;
function CadParseEdgeRef(const ARef: string; out FaceA, FaceB: string): Boolean;

implementation

function CadEdgeRef(const FaceA, FaceB: string): string;
begin
  if CompareStr(FaceA, FaceB) <= 0 then
    Result := 'edge:' + FaceA + '|' + FaceB
  else
    Result := 'edge:' + FaceB + '|' + FaceA;
end;

function CadParseEdgeRef(const ARef: string; out FaceA, FaceB: string): Boolean;
var
  S: string;
  P: Integer;
begin
  FaceA := '';
  FaceB := '';
  Result := False;
  if Copy(ARef, 1, 5) <> 'edge:' then
    Exit;
  S := Copy(ARef, 6, MaxInt);
  P := Pos('|', S);
  if P <= 1 then
    Exit;
  FaceA := Copy(S, 1, P - 1);
  FaceB := Copy(S, P + 1, MaxInt);
  Result := (FaceA <> '') and (FaceB <> '');
end;

{ ---------- base ---------- }

procedure TCadBlendBase.SaveParams(O: TJSONObject);
begin
  SaveStrArray(O, 'edges', Edges);
end;

procedure TCadBlendBase.LoadParams(O: TJSONObject);
begin
  Edges := LoadStrArray(O, 'edges');
end;

function TCadBlendBase.Validate: string;
var
  I: Integer;
  A, B: string;
begin
  Result := '';
  if Length(Edges) = 0 then
    Exit('Selecione arestas ou faces');
  for I := 0 to High(Edges) do
    if not CadParseEdgeRef(Edges[I], A, B) and (Copy(Edges[I], 1, 5) <> 'face:') then
      Exit('Referência inválida: ' + Edges[I]);
end;

{ ---------- filete ---------- }

constructor TCadFillet3D.Create;
begin
  inherited Create;
  SetKind(cfFillet);
  Radius := 2;
end;

procedure TCadFillet3D.SaveParams(O: TJSONObject);
begin
  inherited SaveParams(O);
  O.Add('radius', Radius);
end;

procedure TCadFillet3D.LoadParams(O: TJSONObject);
begin
  inherited LoadParams(O);
  Radius := JNum(O, 'radius', 2);
end;

function TCadFillet3D.Validate: string;
begin
  Result := inherited Validate;
  if (Result = '') and (Radius <= 0) then
    Result := 'Raio deve ser maior que zero';
end;

{ ---------- chanfro ---------- }

constructor TCadChamfer3D.Create;
begin
  inherited Create;
  SetKind(cfChamfer);
  Mode := cmDistance;
  Distance := 1;
  Distance2 := 1;
  Angle := 45;
end;

procedure TCadChamfer3D.SaveParams(O: TJSONObject);
begin
  inherited SaveParams(O);
  O.Add('mode', CAD_CHAMFER_MODE_CODES[Mode]);
  O.Add('distance', Distance);
  if Mode = cmDistanceDistance then
    O.Add('distance2', Distance2);
  if Mode = cmDistanceAngle then
    O.Add('angle', Angle);
  if Flip then
    O.Add('flip', True);
end;

procedure TCadChamfer3D.LoadParams(O: TJSONObject);
var
  S: string;
  M: TCadChamferMode;
begin
  inherited LoadParams(O);
  S := JStr(O, 'mode', 'distance');
  Mode := cmDistance;
  for M := Low(M) to High(M) do
    if CAD_CHAMFER_MODE_CODES[M] = S then
      Mode := M;
  Distance := JNum(O, 'distance', 1);
  Distance2 := JNum(O, 'distance2', Distance);
  Angle := JNum(O, 'angle', 45);
  Flip := JBool(O, 'flip', False);
end;

function TCadChamfer3D.Validate: string;
begin
  Result := inherited Validate;
  if Result <> '' then
    Exit;
  if Distance <= 0 then
    Exit('Distância deve ser maior que zero');
  if (Mode = cmDistanceDistance) and (Distance2 <= 0) then
    Exit('Segunda distância deve ser maior que zero');
  if (Mode = cmDistanceAngle) and ((Angle <= 0.5) or (Angle >= 89.5)) then
    Exit('Ângulo deve ficar entre 0,5° e 89,5°');
end;

procedure TCadChamfer3D.Distances(out D1, D2: Double);
begin
  D1 := Distance;
  case Mode of
    cmDistanceDistance: D2 := Distance2;
    cmDistanceAngle: D2 := Distance * Tan(DegToRad(Angle));
  else
    D2 := Distance;
  end;
  if Flip then
  begin
    D1 := D2;
    D2 := Distance;
  end;
end;

{ ---------- casca ---------- }

constructor TCadShell.Create;
begin
  inherited Create;
  SetKind(cfShell);
  Thickness := 1;
end;

procedure TCadShell.SaveParams(O: TJSONObject);
begin
  O.Add('thickness', Thickness);
  SaveStrArray(O, 'faces', Faces);
  if Outward then
    O.Add('outward', True);
end;

procedure TCadShell.LoadParams(O: TJSONObject);
begin
  Thickness := JNum(O, 'thickness', 1);
  Faces := LoadStrArray(O, 'faces');
  Outward := JBool(O, 'outward', False);
end;

function TCadShell.Validate: string;
begin
  Result := '';
  if Thickness <= 0 then
    Result := 'Espessura deve ser maior que zero';
end;

initialization
  RegisterCadFeature(cfFillet, TCadFillet3D);
  RegisterCadFeature(cfChamfer, TCadChamfer3D);
  RegisterCadFeature(cfShell, TCadShell);

end.
