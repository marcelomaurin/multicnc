unit multicad_extrude;

{ MultiCAD - Ressalto/Base extrudado e Corte extrudado
  (ARCHITECTURE.md, secao 3B).

  Fase 0: parametros completos do PropertyManager, validacao das regras
  (quais condicoes valem para ressalto e corte) e JSON.
  Fase 2: geometria (varredura do perfil + booleana). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpjson, multicad_types, multicad_feature, multicad_refgeom;

type
  TCadExtrudeStart = (esSketchPlane, esSurface, esVertex, esOffset);

  TCadEndCondition = (ecBlind, ecThroughAll, ecThroughAllBoth, ecUpToNext,
    ecUpToVertex, ecUpToSurface, ecOffsetFromSurface, ecUpToBody, ecMidPlane);

  TCadThinType = (ttOneDirection, ttMidPlane, ttTwoDirections);

  TCadExtrudeDir = record
    EndCond: TCadEndCondition;
    Depth: Double;          { mm }
    DepthExpr: string;      { expressao digitada (opcional) }
    Reverse: Boolean;
    DirRef: string;         { vazio = normal ao sketch; senao aresta/linha/eixo }
    Target: string;         { face, vertice ou corpo das condicoes "ate" }
    Offset: Double;         { deslocamento da superficie }
    OffsetReverse: Boolean;
    TranslateSurface: Boolean;
    Draft: Double;          { graus; 0 = sem inclinacao }
    DraftOutward: Boolean;
  end;

  TCadExtrude = class(TCadFeature)
  public
    SketchId: Integer;
    StartKind: TCadExtrudeStart;
    StartRef: string;
    StartOffset: Double;
    StartReverse: Boolean;
    Dir1: TCadExtrudeDir;
    UseDir2: Boolean;
    Dir2: TCadExtrudeDir;
    Thin: Boolean;
    ThinType: TCadThinType;
    ThinT1, ThinT2: Double;
    ThinReverse: Boolean;
    CapEnds: Boolean;
    CapThickness: Double;
    Contours: TCadStrArray;   { regioes do sketch; vazio = todas }
    Merge: Boolean;           { so ressalto }
    FlipSide: Boolean;        { so corte: inverter lado a cortar }
    ScopeAll: Boolean;        { escopo do recurso }
    ScopeAuto: Boolean;
    ScopeBodies: TCadStrArray;
    constructor Create; override;
    function IsCut: Boolean;
    procedure SaveParams(O: TJSONObject); override;
    procedure LoadParams(O: TJSONObject); override;
    function Validate: string; override;
    function Dependencies: TCadIdArray; override;
  end;

  TCadExtrudeCut = class(TCadExtrude)
  public
    constructor Create; override;
  end;

const
  CAD_START_CODES: array[TCadExtrudeStart] of string = ('sketch_plane',
    'surface', 'vertex', 'offset');
  CAD_START_NAMES: array[TCadExtrudeStart] of string = ('Plano do esboço',
    'Superfície/Face/Plano', 'Vértice', 'Deslocamento');
  CAD_END_CODES: array[TCadEndCondition] of string = ('blind', 'through_all',
    'through_all_both', 'up_to_next', 'up_to_vertex', 'up_to_surface',
    'offset_from_surface', 'up_to_body', 'mid_plane');
  CAD_END_NAMES: array[TCadEndCondition] of string = ('Cego', 'Passante',
    'Passante - ambos', 'Até o próximo', 'Até o vértice', 'Até a superfície',
    'Deslocamento da superfície', 'Até o corpo', 'Plano médio');
  CAD_THIN_CODES: array[TCadThinType] of string = ('one_direction',
    'mid_plane', 'two_directions');
  CAD_THIN_NAMES: array[TCadThinType] of string = ('Uma direção', 'Plano médio',
    'Duas direções');

{ Condicao disponivel para ressalto (IsCut=False) ou corte (tabela 3B). }
function CadEndAllowed(C: TCadEndCondition; IsCut: Boolean): Boolean;
function CadEndNeedsDepth(C: TCadEndCondition): Boolean;
function CadEndNeedsTarget(C: TCadEndCondition): Boolean;
function CadDefaultDir(ADepth: Double): TCadExtrudeDir;

implementation

function CadEndAllowed(C: TCadEndCondition; IsCut: Boolean): Boolean;
begin
  if C in [ecThroughAll, ecThroughAllBoth] then
    Result := IsCut
  else
    Result := True;
end;

function CadEndNeedsDepth(C: TCadEndCondition): Boolean;
begin
  Result := C in [ecBlind, ecMidPlane];
end;

function CadEndNeedsTarget(C: TCadEndCondition): Boolean;
begin
  Result := C in [ecUpToVertex, ecUpToSurface, ecOffsetFromSurface, ecUpToBody];
end;

function CadDefaultDir(ADepth: Double): TCadExtrudeDir;
begin
  Result := Default(TCadExtrudeDir);
  Result.EndCond := ecBlind;
  Result.Depth := ADepth;
  Result.DepthExpr := '';
  Result.DirRef := '';
  Result.Target := '';
end;

function EndFromCode(const S: string): TCadEndCondition;
var
  C: TCadEndCondition;
begin
  for C := Low(TCadEndCondition) to High(TCadEndCondition) do
    if CAD_END_CODES[C] = S then
      Exit(C);
  raise Exception.CreateFmt('Condição final desconhecida "%s"', [S]);
end;

procedure SaveDir(O: TJSONObject; const K: string; const D: TCadExtrudeDir);
var
  J: TJSONObject;
begin
  J := TJSONObject.Create;
  J.Add('end', CAD_END_CODES[D.EndCond]);
  J.Add('depth', D.Depth);
  if D.DepthExpr <> '' then J.Add('depth_expr', D.DepthExpr);
  J.Add('reverse', D.Reverse);
  if D.DirRef <> '' then J.Add('dir_ref', D.DirRef);
  if D.Target <> '' then J.Add('target', D.Target);
  if D.EndCond = ecOffsetFromSurface then
  begin
    J.Add('offset', D.Offset);
    J.Add('offset_reverse', D.OffsetReverse);
    J.Add('translate_surface', D.TranslateSurface);
  end;
  if D.Draft <> 0 then
  begin
    J.Add('draft', D.Draft);
    J.Add('draft_outward', D.DraftOutward);
  end;
  O.Add(K, J);
end;

function LoadDir(O: TJSONObject; const K: string; ADef: Double): TCadExtrudeDir;
var
  D: TJSONData;
  J: TJSONObject;
begin
  Result := CadDefaultDir(ADef);
  D := O.Find(K);
  if D = nil then
    Exit;
  if not (D is TJSONObject) then
    raise Exception.CreateFmt('"%s" deve ser objeto', [K]);
  J := TJSONObject(D);
  Result.EndCond := EndFromCode(JStr(J, 'end', 'blind'));
  Result.Depth := JNum(J, 'depth', ADef);
  Result.DepthExpr := JStr(J, 'depth_expr', '');
  Result.Reverse := JBool(J, 'reverse', False);
  Result.DirRef := JStr(J, 'dir_ref', '');
  Result.Target := JStr(J, 'target', '');
  Result.Offset := JNum(J, 'offset', 0);
  Result.OffsetReverse := JBool(J, 'offset_reverse', False);
  Result.TranslateSurface := JBool(J, 'translate_surface', False);
  Result.Draft := JNum(J, 'draft', 0);
  Result.DraftOutward := JBool(J, 'draft_outward', False);
end;

{ TCadExtrude }

constructor TCadExtrude.Create;
begin
  inherited Create;
  SetKind(cfExtrude);
  StartKind := esSketchPlane;
  Dir1 := CadDefaultDir(10);
  Dir2 := CadDefaultDir(10);
  ThinType := ttOneDirection;
  ThinT1 := 1;
  ThinT2 := 1;
  CapThickness := 1;
  Merge := True;
  ScopeAll := True;
  ScopeAuto := True;
end;

function TCadExtrude.IsCut: Boolean;
begin
  Result := Kind = cfCut;
end;

procedure TCadExtrude.SaveParams(O: TJSONObject);
var
  T: TJSONObject;
begin
  O.Add('sketch', SketchId);
  O.Add('start', CAD_START_CODES[StartKind]);
  if StartRef <> '' then O.Add('start_ref', StartRef);
  if StartKind = esOffset then
  begin
    O.Add('start_offset', StartOffset);
    O.Add('start_reverse', StartReverse);
  end;
  SaveDir(O, 'dir1', Dir1);
  if UseDir2 then
    SaveDir(O, 'dir2', Dir2);
  if Thin then
  begin
    T := TJSONObject.Create;
    T.Add('type', CAD_THIN_CODES[ThinType]);
    T.Add('t1', ThinT1);
    if ThinType = ttTwoDirections then T.Add('t2', ThinT2);
    T.Add('reverse', ThinReverse);
    T.Add('cap_ends', CapEnds);
    if CapEnds then T.Add('cap_thickness', CapThickness);
    O.Add('thin', T);
  end;
  if Length(Contours) > 0 then
    SaveStrArray(O, 'contours', Contours);
  if IsCut then
    O.Add('flip_side', FlipSide)
  else
    O.Add('merge', Merge);
  O.Add('scope_all', ScopeAll);
  if not ScopeAll then
  begin
    O.Add('scope_auto', ScopeAuto);
    SaveStrArray(O, 'scope_bodies', ScopeBodies);
  end;
end;

procedure TCadExtrude.LoadParams(O: TJSONObject);
var
  S: string;
  K: TCadExtrudeStart;
  TT: TCadThinType;
  Found: Boolean;
  D: TJSONData;
  T: TJSONObject;
begin
  SketchId := JInt(O, 'sketch', 0);
  S := JStr(O, 'start', 'sketch_plane');
  Found := False;
  for K := Low(TCadExtrudeStart) to High(TCadExtrudeStart) do
    if CAD_START_CODES[K] = S then
    begin
      StartKind := K;
      Found := True;
    end;
  if not Found then
    raise Exception.CreateFmt('Início desconhecido "%s"', [S]);
  StartRef := JStr(O, 'start_ref', '');
  StartOffset := JNum(O, 'start_offset', 0);
  StartReverse := JBool(O, 'start_reverse', False);
  Dir1 := LoadDir(O, 'dir1', 10);
  UseDir2 := O.Find('dir2') <> nil;
  Dir2 := LoadDir(O, 'dir2', 10);
  D := O.Find('thin');
  Thin := D <> nil;
  if Thin then
  begin
    if not (D is TJSONObject) then
      raise Exception.Create('"thin" deve ser objeto');
    T := TJSONObject(D);
    S := JStr(T, 'type', 'one_direction');
    Found := False;
    for TT := Low(TCadThinType) to High(TCadThinType) do
      if CAD_THIN_CODES[TT] = S then
      begin
        ThinType := TT;
        Found := True;
      end;
    if not Found then
      raise Exception.CreateFmt('Tipo de recurso fino desconhecido "%s"', [S]);
    ThinT1 := JNum(T, 't1', 1);
    ThinT2 := JNum(T, 't2', ThinT1);
    ThinReverse := JBool(T, 'reverse', False);
    CapEnds := JBool(T, 'cap_ends', False);
    CapThickness := JNum(T, 'cap_thickness', 1);
  end;
  Contours := LoadStrArray(O, 'contours');
  Merge := JBool(O, 'merge', True);
  FlipSide := JBool(O, 'flip_side', False);
  ScopeAll := JBool(O, 'scope_all', True);
  ScopeAuto := JBool(O, 'scope_auto', True);
  ScopeBodies := LoadStrArray(O, 'scope_bodies');
end;

function CheckDir(const D: TCadExtrudeDir; IsCut: Boolean; const Title: string): string;
begin
  Result := '';
  if not CadEndAllowed(D.EndCond, IsCut) then
    Exit(Format('%s: "%s" só existe no corte', [Title, CAD_END_NAMES[D.EndCond]]));
  if CadEndNeedsDepth(D.EndCond) and (D.Depth <= CAD_TOL) then
    Exit(Format('%s: profundidade deve ser maior que zero', [Title]));
  if CadEndNeedsTarget(D.EndCond) and (D.Target = '') then
    Exit(Format('%s: escolha a referência de "%s"', [Title, CAD_END_NAMES[D.EndCond]]));
  if (D.EndCond = ecOffsetFromSurface) and (D.Offset < 0) then
    Exit(Format('%s: deslocamento não pode ser negativo (use Inverter)', [Title]));
  if (D.Draft < 0) or (D.Draft >= 89) then
    Exit(Format('%s: inclinação deve ficar entre 0° e 89°', [Title]));
end;

function TCadExtrude.Validate: string;
begin
  if SketchId <= 0 then
    Exit('Escolha o esboço da operação');
  if (StartKind in [esSurface, esVertex]) and (StartRef = '') then
    Exit('Escolha a referência do início');
  if (StartKind = esOffset) and (Abs(StartOffset) < CAD_TOL) then
    Exit('Deslocamento do início deve ser diferente de zero');
  Result := CheckDir(Dir1, IsCut, 'Direção 1');
  if Result <> '' then
    Exit;
  if UseDir2 then
  begin
    if Dir1.EndCond in [ecMidPlane, ecThroughAllBoth] then
      Exit('Direção 2 não existe com "' + CAD_END_NAMES[Dir1.EndCond] + '"');
    if Dir2.EndCond in [ecMidPlane, ecThroughAllBoth] then
      Exit('Direção 2: "' + CAD_END_NAMES[Dir2.EndCond] + '" não é permitido');
    Result := CheckDir(Dir2, IsCut, 'Direção 2');
    if Result <> '' then
      Exit;
  end;
  if Thin then
  begin
    if ThinT1 <= CAD_TOL then
      Exit('Espessura do recurso fino deve ser maior que zero');
    if (ThinType = ttTwoDirections) and (ThinT2 <= CAD_TOL) then
      Exit('Espessura 2 do recurso fino deve ser maior que zero');
    if CapEnds and (CapThickness <= CAD_TOL) then
      Exit('Espessura da tampa deve ser maior que zero');
  end;
  if (not ScopeAll) and (not ScopeAuto) and (Length(ScopeBodies) = 0) then
    Exit('Escopo do recurso: escolha ao menos um corpo');
  Result := '';
end;

function TCadExtrude.Dependencies: TCadIdArray;
var
  RefId: Integer;
  procedure AddId(AId: Integer);
  begin
    if AId <= 0 then
      Exit;
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := AId;
  end;
begin
  Result := nil;
  AddId(SketchId);
  RefId := CadRefFeatureId(StartRef);
  AddId(RefId);
  AddId(CadRefFeatureId(Dir1.Target));
  AddId(CadRefFeatureId(Dir1.DirRef));
  if UseDir2 then
  begin
    AddId(CadRefFeatureId(Dir2.Target));
    AddId(CadRefFeatureId(Dir2.DirRef));
  end;
end;

{ TCadExtrudeCut }

constructor TCadExtrudeCut.Create;
begin
  inherited Create;
  SetKind(cfCut);
  Dir1.EndCond := ecBlind;
end;

initialization
  RegisterCadFeature(cfExtrude, TCadExtrude);
  RegisterCadFeature(cfCut, TCadExtrudeCut);

end.
