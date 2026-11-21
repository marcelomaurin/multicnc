unit multicad_gear;

{ MultiCAD - Engrenagem (operacao parametrica).

  Gera o solido de uma engrenagem (multicad_gears) e o posiciona:
  - PlaneRef: plano ou face plana da face de base (padrao Plano Frontal);
  - CenterRef: ponto do centro ("sketch:<id>/<ent>.<pt>", "origin"; vazio =
    origem do plano), projetado no plano;
  - Angle: giro em torno do eixo (posicao do primeiro dente);
  - Reverse: cresce para o outro lado do plano; Offset: afasta do plano.
  Cremalheira: o ponto e o inicio da linha primitiva; comprimento ao longo
  do eixo X do plano (girado por Angle), dentes para +Y.
  Por padrao a engrenagem e um corpo separado (componente proprio); com
  Mesclar resultado ela se une ao corpo que tocar. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpjson, multicad_types, multicad_feature, multicad_refgeom,
  multicad_gears;

type
  TCadGear = class(TCadFeature)
  public
    Spec: TCadGearSpec;
    PlaneRef: string;
    CenterRef: string;
    Angle: Double;
    Reverse: Boolean;
    Offset: Double;
    Merge: Boolean;
    constructor Create; override;
    procedure SaveParams(O: TJSONObject); override;
    procedure LoadParams(O: TJSONObject); override;
    function Validate: string; override;
    function Dependencies: TCadIdArray; override;
    function SetNumParam(const AKey: string; AValue: Double): Boolean; override;
  end;

implementation

constructor TCadGear.Create;
begin
  inherited Create;
  SetKind(cfGear);
  Spec := CadGearDefaults;
  PlaneRef := 'plane:1';
  CenterRef := '';
  { componente proprio: corpo separado; "Mesclar resultado" une ao corpo
    que tocar (engrenagem feita junto com o eixo) }
  Merge := False;
end;

procedure TCadGear.SaveParams(O: TJSONObject);
begin
  O.Add('gear_kind', CAD_GEAR_KIND_CODES[Spec.Kind]);
  O.Add('teeth', CAD_GEAR_TEETH_CODES[Spec.Teeth]);
  O.Add('module', Spec.Module);
  O.Add('count', Spec.Count);
  O.Add('pressure', Spec.Pressure);
  O.Add('helix', Spec.Helix);
  O.Add('left_hand', Spec.LeftHand);
  O.Add('width', Spec.Width);
  O.Add('shift', Spec.Shift);
  O.Add('backlash', Spec.Backlash);
  O.Add('bore', Spec.Bore);
  O.Add('key_width', Spec.KeyWidth);
  O.Add('key_depth', Spec.KeyDepth);
  O.Add('outer_d', Spec.OuterD);
  O.Add('rack_height', Spec.RackHeight);
  O.Add('plane', PlaneRef);
  if CenterRef <> '' then
    O.Add('center', CenterRef);
  O.Add('angle', Angle);
  O.Add('reverse', Reverse);
  O.Add('offset', Offset);
  O.Add('merge', Merge);
end;

procedure TCadGear.LoadParams(O: TJSONObject);
var
  S: string;
  K: TCadGearKind;
  T: TCadGearTeeth;
  Found: Boolean;
begin
  Spec := CadGearDefaults;
  S := JStr(O, 'gear_kind', 'external');
  Found := False;
  for K := Low(TCadGearKind) to High(TCadGearKind) do
    if CAD_GEAR_KIND_CODES[K] = S then
    begin
      Spec.Kind := K;
      Found := True;
    end;
  if not Found then
    raise Exception.CreateFmt('Tipo de engrenagem desconhecido "%s"', [S]);
  S := JStr(O, 'teeth', 'straight');
  Found := False;
  for T := Low(TCadGearTeeth) to High(TCadGearTeeth) do
    if CAD_GEAR_TEETH_CODES[T] = S then
    begin
      Spec.Teeth := T;
      Found := True;
    end;
  if not Found then
    raise Exception.CreateFmt('Tipo de dente desconhecido "%s"', [S]);
  Spec.Module := JNum(O, 'module', 1);
  Spec.Count := JInt(O, 'count', 20);
  Spec.Pressure := JNum(O, 'pressure', 20);
  Spec.Helix := JNum(O, 'helix', 15);
  Spec.LeftHand := JBool(O, 'left_hand', False);
  Spec.Width := JNum(O, 'width', 10);
  Spec.Shift := JNum(O, 'shift', 0);
  Spec.Backlash := JNum(O, 'backlash', 0);
  Spec.Bore := JNum(O, 'bore', 0);
  Spec.KeyWidth := JNum(O, 'key_width', 0);
  Spec.KeyDepth := JNum(O, 'key_depth', 0);
  Spec.OuterD := JNum(O, 'outer_d', 0);
  Spec.RackHeight := JNum(O, 'rack_height', 0);
  PlaneRef := JStr(O, 'plane', 'plane:1');
  CenterRef := JStr(O, 'center', '');
  Angle := JNum(O, 'angle', 0);
  Reverse := JBool(O, 'reverse', False);
  Offset := JNum(O, 'offset', 0);
  Merge := JBool(O, 'merge', False);
end;

function TCadGear.Validate: string;
begin
  if PlaneRef = '' then
    Exit('Escolha o plano ou a face plana da engrenagem');
  Result := CadGearValidate(Spec);
end;

function TCadGear.Dependencies: TCadIdArray;

  procedure Add(const ARef: string);
  var
    Id: Integer;
  begin
    Id := CadRefFeatureId(ARef);
    if Id <= 0 then
      Exit;
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := Id;
  end;

begin
  Result := nil;
  Add(PlaneRef);
  Add(CenterRef);
end;

function TCadGear.SetNumParam(const AKey: string; AValue: Double): Boolean;
begin
  Result := True;
  if AKey = 'module' then
    Spec.Module := AValue
  else if AKey = 'count' then
    Spec.Count := Round(AValue)
  else if AKey = 'pressure' then
    Spec.Pressure := AValue
  else if AKey = 'helix' then
    Spec.Helix := AValue
  else if AKey = 'width' then
    Spec.Width := AValue
  else if AKey = 'shift' then
    Spec.Shift := AValue
  else if AKey = 'backlash' then
    Spec.Backlash := AValue
  else if AKey = 'bore' then
    Spec.Bore := AValue
  else if AKey = 'key_width' then
    Spec.KeyWidth := AValue
  else if AKey = 'key_depth' then
    Spec.KeyDepth := AValue
  else if AKey = 'outer_d' then
    Spec.OuterD := AValue
  else if AKey = 'rack_height' then
    Spec.RackHeight := AValue
  else if AKey = 'angle' then
    Angle := AValue
  else if AKey = 'offset' then
    Offset := AValue
  else
    Result := inherited SetNumParam(AKey, AValue);
end;

initialization
  RegisterCadFeature(cfGear, TCadGear);

end.
