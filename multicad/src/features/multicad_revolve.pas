unit multicad_revolve;

{ MultiCAD - Ressalto/Base revolucionado e Corte revolucionado
  (ARCHITECTURE.md 3B, "Revolucao (mesmo padrao)").

  Eixo: AxisRef vazio = linha de centro do esboco (a primeira); senao
  "sketch:<id>/<entidade>" (linha do esboco) ou "axis:<id>" (eixo de
  referencia). Condicoes: Cego (angulo), Plano medio, Direcao 2 com angulo
  proprio. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpjson, multicad_types, multicad_feature, multicad_refgeom;

type
  TCadRevolveCond = (rcBlind, rcMidPlane);

  TCadRevolve = class(TCadFeature)
  public
    SketchId: Integer;
    AxisRef: string;
    Cond: TCadRevolveCond;
    Angle: Double;          { graus }
    Reverse: Boolean;
    UseDir2: Boolean;
    Angle2: Double;
    Contours: TCadStrArray;
    Merge: Boolean;         { so ressalto }
    FlipSide: Boolean;      { so corte }
    constructor Create; override;
    function IsCut: Boolean;
    procedure SaveParams(O: TJSONObject); override;
    procedure LoadParams(O: TJSONObject); override;
    function Validate: string; override;
    function Dependencies: TCadIdArray; override;
  end;

  TCadRevolveCut = class(TCadRevolve)
  public
    constructor Create; override;
  end;

const
  CAD_REVOLVE_COND_CODES: array[TCadRevolveCond] of string = ('blind', 'mid_plane');
  CAD_REVOLVE_COND_NAMES: array[TCadRevolveCond] of string = ('Cego', 'Plano médio');

implementation

constructor TCadRevolve.Create;
begin
  inherited Create;
  SetKind(cfRevolve);
  Cond := rcBlind;
  Angle := 360;
  Angle2 := 0;
  Merge := True;
end;

function TCadRevolve.IsCut: Boolean;
begin
  Result := Kind = cfRevolveCut;
end;

procedure TCadRevolve.SaveParams(O: TJSONObject);
begin
  O.Add('sketch', SketchId);
  if AxisRef <> '' then
    O.Add('axis', AxisRef);
  O.Add('cond', CAD_REVOLVE_COND_CODES[Cond]);
  O.Add('angle', Angle);
  O.Add('reverse', Reverse);
  if UseDir2 then
    O.Add('angle2', Angle2);
  if Length(Contours) > 0 then
    SaveStrArray(O, 'contours', Contours);
  if IsCut then
    O.Add('flip_side', FlipSide)
  else
    O.Add('merge', Merge);
end;

procedure TCadRevolve.LoadParams(O: TJSONObject);
var
  S: string;
  C: TCadRevolveCond;
  Found: Boolean;
begin
  SketchId := JInt(O, 'sketch', 0);
  AxisRef := JStr(O, 'axis', '');
  S := JStr(O, 'cond', 'blind');
  Found := False;
  for C := Low(TCadRevolveCond) to High(TCadRevolveCond) do
    if CAD_REVOLVE_COND_CODES[C] = S then
    begin
      Cond := C;
      Found := True;
    end;
  if not Found then
    raise Exception.CreateFmt('Condição de revolução desconhecida "%s"', [S]);
  Angle := JNum(O, 'angle', 360);
  Reverse := JBool(O, 'reverse', False);
  UseDir2 := O.Find('angle2') <> nil;
  Angle2 := JNum(O, 'angle2', 0);
  Contours := LoadStrArray(O, 'contours');
  Merge := JBool(O, 'merge', True);
  FlipSide := JBool(O, 'flip_side', False);
end;

function TCadRevolve.Validate: string;
begin
  Result := '';
  if SketchId <= 0 then
    Exit('Escolha o esboço da revolução');
  if (Angle <= CAD_ANGLE_TOL) or (Angle > 360) then
    Exit('Ângulo deve ficar entre 0° e 360°');
  if UseDir2 then
  begin
    if Cond = rcMidPlane then
      Exit('Direção 2 não existe com "Plano médio"');
    if (Angle2 <= CAD_ANGLE_TOL) or (Angle + Angle2 > 360 + 1E-9) then
      Exit('Direção 2: a soma dos ângulos deve ficar entre 0° e 360°');
  end;
end;

function TCadRevolve.Dependencies: TCadIdArray;
var
  RefId: Integer;
begin
  Result := nil;
  if SketchId > 0 then
  begin
    SetLength(Result, 1);
    Result[0] := SketchId;
  end;
  RefId := CadRefFeatureId(AxisRef);
  if (RefId > 0) and (RefId <> SketchId) then
  begin
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := RefId;
  end;
end;

constructor TCadRevolveCut.Create;
begin
  inherited Create;
  SetKind(cfRevolveCut);
end;

initialization
  RegisterCadFeature(cfRevolve, TCadRevolve);
  RegisterCadFeature(cfRevolveCut, TCadRevolveCut);

end.
