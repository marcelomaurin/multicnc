unit multicad_pattern;

{ MultiCAD - Padrao linear, Padrao circular e Espelhar (fase 5B).

  Repetem operacoes anteriores (ressaltos, cortes, revolucoes, furos): a
  ferramenta de cada operacao semente e copiada, movida e aplicada de novo
  (ressalto mescla, corte remove).

  Direcoes/eixos (texto): "x", "y", "z" (eixos globais), "axis:<id>",
  "sketch:<id>/<linha>", "plane:<id>" ou "face:<nome>" (normal da face plana;
  no circular, eixo da face cilindrica). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, fpjson, multicad_types, multicad_feature,
  multicad_refgeom;

type
  TCadPatternBase = class(TCadFeature)
  public
    Seeds: TCadIdArray;     { Ids das operacoes repetidas }
    procedure SaveParams(O: TJSONObject); override;
    procedure LoadParams(O: TJSONObject); override;
    function Dependencies: TCadIdArray; override;
    function Validate: string; override;
  end;

  TCadLinearPattern = class(TCadPatternBase)
  public
    Dir1: string;
    Spacing1: Double;
    Count1: Integer;
    Reverse1: Boolean;
    UseDir2: Boolean;
    Dir2: string;
    Spacing2: Double;
    Count2: Integer;
    Reverse2: Boolean;
    constructor Create; override;
    procedure SaveParams(O: TJSONObject); override;
    procedure LoadParams(O: TJSONObject); override;
    function Validate: string; override;
    function Dependencies: TCadIdArray; override;
  end;

  TCadCircularPattern = class(TCadPatternBase)
  public
    AxisRef: string;
    Count: Integer;
    Angle: Double;          { graus }
    EqualSpacing: Boolean;  { Angle = total; senao Angle = passo }
    Reverse: Boolean;
    constructor Create; override;
    procedure SaveParams(O: TJSONObject); override;
    procedure LoadParams(O: TJSONObject); override;
    function Validate: string; override;
    function Dependencies: TCadIdArray; override;
    { Passo em graus entre as copias. }
    function StepAngle: Double;
  end;

  TCadMirror = class(TCadPatternBase)
  public
    PlaneRef: string;
    constructor Create; override;
    procedure SaveParams(O: TJSONObject); override;
    procedure LoadParams(O: TJSONObject); override;
    function Validate: string; override;
    function Dependencies: TCadIdArray; override;
  end;

implementation

procedure AddDep(var A: TCadIdArray; AId: Integer);
var
  I: Integer;
begin
  if AId <= 0 then
    Exit;
  for I := 0 to High(A) do
    if A[I] = AId then
      Exit;
  SetLength(A, Length(A) + 1);
  A[High(A)] := AId;
end;

{ ---------- base ---------- }

procedure TCadPatternBase.SaveParams(O: TJSONObject);
var
  A: TJSONArray;
  I: Integer;
begin
  A := TJSONArray.Create;
  for I := 0 to High(Seeds) do
    A.Add(Seeds[I]);
  O.Add('features', A);
end;

procedure TCadPatternBase.LoadParams(O: TJSONObject);
var
  D: TJSONData;
  I: Integer;
begin
  Seeds := nil;
  D := O.Find('features');
  if D is TJSONArray then
  begin
    SetLength(Seeds, D.Count);
    for I := 0 to D.Count - 1 do
      Seeds[I] := D.Items[I].AsInteger;
  end;
end;

function TCadPatternBase.Dependencies: TCadIdArray;
var
  I: Integer;
begin
  Result := nil;
  for I := 0 to High(Seeds) do
    AddDep(Result, Seeds[I]);
end;

function TCadPatternBase.Validate: string;
begin
  if Length(Seeds) = 0 then
    Result := 'Escolha as operações a repetir'
  else
    Result := '';
end;

{ ---------- linear ---------- }

constructor TCadLinearPattern.Create;
begin
  inherited Create;
  SetKind(cfLinearPattern);
  Dir1 := 'x';
  Spacing1 := 20;
  Count1 := 3;
  Dir2 := 'y';
  Spacing2 := 20;
  Count2 := 2;
end;

procedure TCadLinearPattern.SaveParams(O: TJSONObject);
begin
  inherited SaveParams(O);
  O.Add('dir1', Dir1);
  O.Add('spacing1', Spacing1);
  O.Add('count1', Count1);
  O.Add('reverse1', Reverse1);
  O.Add('use_dir2', UseDir2);
  O.Add('dir2', Dir2);
  O.Add('spacing2', Spacing2);
  O.Add('count2', Count2);
  O.Add('reverse2', Reverse2);
end;

procedure TCadLinearPattern.LoadParams(O: TJSONObject);
begin
  inherited LoadParams(O);
  Dir1 := JStr(O, 'dir1', 'x');
  Spacing1 := JNum(O, 'spacing1', 20);
  Count1 := JInt(O, 'count1', 3);
  Reverse1 := JBool(O, 'reverse1', False);
  UseDir2 := JBool(O, 'use_dir2', False);
  Dir2 := JStr(O, 'dir2', 'y');
  Spacing2 := JNum(O, 'spacing2', 20);
  Count2 := JInt(O, 'count2', 2);
  Reverse2 := JBool(O, 'reverse2', False);
end;

function TCadLinearPattern.Validate: string;
begin
  Result := inherited Validate;
  if Result <> '' then
    Exit;
  if (Count1 < 1) or (Count1 > 500) then
    Exit('Número de cópias da direção 1 entre 1 e 500');
  if Spacing1 <= 0 then
    Exit('Espaçamento deve ser maior que zero');
  if UseDir2 then
  begin
    if (Count2 < 1) or (Count2 > 500) then
      Exit('Número de cópias da direção 2 entre 1 e 500');
    if Spacing2 <= 0 then
      Exit('Espaçamento da direção 2 deve ser maior que zero');
  end;
  if (Count1 = 1) and (not UseDir2 or (Count2 = 1)) then
    Exit('O padrão precisa de pelo menos 2 cópias');
end;

function TCadLinearPattern.Dependencies: TCadIdArray;
begin
  Result := inherited Dependencies;
  AddDep(Result, CadRefFeatureId(Dir1));
  if UseDir2 then
    AddDep(Result, CadRefFeatureId(Dir2));
end;

{ ---------- circular ---------- }

constructor TCadCircularPattern.Create;
begin
  inherited Create;
  SetKind(cfCircularPattern);
  AxisRef := 'y';
  Count := 4;
  Angle := 360;
  EqualSpacing := True;
end;

procedure TCadCircularPattern.SaveParams(O: TJSONObject);
begin
  inherited SaveParams(O);
  O.Add('axis', AxisRef);
  O.Add('count', Count);
  O.Add('angle', Angle);
  O.Add('equal', EqualSpacing);
  O.Add('reverse', Reverse);
end;

procedure TCadCircularPattern.LoadParams(O: TJSONObject);
begin
  inherited LoadParams(O);
  AxisRef := JStr(O, 'axis', 'y');
  Count := JInt(O, 'count', 4);
  Angle := JNum(O, 'angle', 360);
  EqualSpacing := JBool(O, 'equal', True);
  Reverse := JBool(O, 'reverse', False);
end;

function TCadCircularPattern.StepAngle: Double;
begin
  if not EqualSpacing then
    Result := Angle
  else if Abs(Angle - 360) < 1E-9 then
    Result := 360 / Max(1, Count)
  else
    Result := Angle / Max(1, Count - 1);
  if Reverse then
    Result := -Result;
end;

function TCadCircularPattern.Validate: string;
begin
  Result := inherited Validate;
  if Result <> '' then
    Exit;
  if (Count < 2) or (Count > 500) then
    Exit('Número de cópias entre 2 e 500');
  if (Angle <= 0) or (Angle > 360) then
    Exit('Ângulo entre 0° e 360°');
end;

function TCadCircularPattern.Dependencies: TCadIdArray;
begin
  Result := inherited Dependencies;
  AddDep(Result, CadRefFeatureId(AxisRef));
end;

{ ---------- espelhar ---------- }

constructor TCadMirror.Create;
begin
  inherited Create;
  SetKind(cfMirror);
  PlaneRef := 'plane:3';
end;

procedure TCadMirror.SaveParams(O: TJSONObject);
begin
  inherited SaveParams(O);
  O.Add('plane', PlaneRef);
end;

procedure TCadMirror.LoadParams(O: TJSONObject);
begin
  inherited LoadParams(O);
  PlaneRef := JStr(O, 'plane', 'plane:3');
end;

function TCadMirror.Validate: string;
begin
  Result := inherited Validate;
  if (Result = '') and (Trim(PlaneRef) = '') then
    Result := 'Escolha o plano (ou face plana) do espelho';
end;

function TCadMirror.Dependencies: TCadIdArray;
begin
  Result := inherited Dependencies;
  AddDep(Result, CadRefFeatureId(PlaneRef));
end;

initialization
  RegisterCadFeature(cfLinearPattern, TCadLinearPattern);
  RegisterCadFeature(cfCircularPattern, TCadCircularPattern);
  RegisterCadFeature(cfMirror, TCadMirror);

end.
