unit multicad_feature;

{ MultiCAD - base das operacoes (features) da arvore.

  - Id persistente (inteiro gravado no .mcad, decisao D5). Nunca usar o
    endereco do objeto.
  - Parametros gravados por SaveParams/LoadParams (JSON).
  - Estado depois da reconstrucao: ok, aviso ou erro, com mensagem (a
    operacao com erro fica vermelha na arvore e a reconstrucao segue).
  - Cada tipo registra a sua classe para o leitor do arquivo. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpjson, multicad_types;

type
  TCadFeatureState = (fsOk, fsWarning, fsError);

  TCadFeature = class;
  TCadFeatureClass = class of TCadFeature;

  TCadFeature = class
  private
    FKind: TCadFeatureKind;
  public
    Id: Integer;
    Name: string;
    Suppressed: Boolean;
    State: TCadFeatureState;
    Message: string;
    { Expressoes dos campos numericos ("angle=Cubo.aresta*2"): a reconstrucao
      reavalia todas e grava o valor pelo SetNumParam, entao mudar uma
      variavel recalcula todos os campos que a usam. }
    Exprs: TStringList;
    constructor Create; virtual;
    destructor Destroy; override;
    { SaveParams/LoadParams + as expressoes ("exprs" no .mcad). }
    procedure SaveAll(O: TJSONObject);
    procedure LoadAll(O: TJSONObject);
    { Grava o valor do campo AKey (mm/graus). False = campo desconhecido. }
    function SetNumParam(const AKey: string; AValue: Double): Boolean; virtual;
    function ExprOf(const AKey: string): string;
    { Expressao do campo; vazio remove (valor fixo). }
    procedure SetExpr(const AKey, AExpr: string);
    procedure SaveParams(O: TJSONObject); virtual;
    { Le os parametros; erro de conteudo -> excecao com mensagem clara. }
    procedure LoadParams(O: TJSONObject); virtual;
    { Confere os parametros sem geometria. Vazio = valido. }
    function Validate: string; virtual;
    { Ids de outras operacoes de que esta depende (sketch, planos...). }
    function Dependencies: TCadIdArray; virtual;
    procedure SetState(AState: TCadFeatureState; const AMsg: string);
    property Kind: TCadFeatureKind read FKind;
  protected
    procedure SetKind(AKind: TCadFeatureKind);
  end;

procedure RegisterCadFeature(AKind: TCadFeatureKind; AClass: TCadFeatureClass);
function CadFeatureClass(AKind: TCadFeatureKind): TCadFeatureClass;
function CadFeatureKindFromCode(const ACode: string; out AKind: TCadFeatureKind): Boolean;

{ Leitura tolerante de JSON com faixa (erro -> excecao). }
function JNum(O: TJSONObject; const K: string; Def: Double): Double;
function JInt(O: TJSONObject; const K: string; Def: Integer): Integer;
function JStr(O: TJSONObject; const K, Def: string): string;
function JBool(O: TJSONObject; const K: string; Def: Boolean): Boolean;

implementation

uses multicad_log;

var
  GClasses: array[TCadFeatureKind] of TCadFeatureClass;

constructor TCadFeature.Create;
begin
  inherited Create;
  Id := 0;
  State := fsOk;
  Exprs := TStringList.Create;
end;

destructor TCadFeature.Destroy;
begin
  Exprs.Free;
  inherited Destroy;
end;

procedure TCadFeature.SaveAll(O: TJSONObject);
var
  E: TJSONObject;
  I: Integer;
begin
  SaveParams(O);
  if Exprs.Count = 0 then
    Exit;
  E := TJSONObject.Create;
  for I := 0 to Exprs.Count - 1 do
    E.Add(Exprs.Names[I], Exprs.ValueFromIndex[I]);
  O.Add('exprs', E);
end;

procedure TCadFeature.LoadAll(O: TJSONObject);
var
  D: TJSONData;
  I: Integer;
begin
  LoadParams(O);
  Exprs.Clear;
  D := O.Find('exprs');
  if D = nil then
    Exit;
  if not (D is TJSONObject) then
    raise Exception.Create('Campo "exprs" deve ser objeto');
  for I := 0 to TJSONObject(D).Count - 1 do
    if TJSONObject(D).Items[I].JSONType = jtString then
      Exprs.Values[TJSONObject(D).Names[I]] := TJSONObject(D).Items[I].AsString;
end;

function TCadFeature.SetNumParam(const AKey: string; AValue: Double): Boolean;
begin
  Result := False;
end;

function TCadFeature.ExprOf(const AKey: string): string;
begin
  Result := Exprs.Values[AKey];
end;

procedure TCadFeature.SetExpr(const AKey, AExpr: string);
var
  I: Integer;
begin
  I := Exprs.IndexOfName(AKey);
  if Trim(AExpr) = '' then
  begin
    if I >= 0 then
      Exprs.Delete(I);
  end
  else
    Exprs.Values[AKey] := Trim(AExpr);
end;

procedure TCadFeature.SetKind(AKind: TCadFeatureKind);
begin
  FKind := AKind;
end;

procedure TCadFeature.SaveParams(O: TJSONObject);
begin
end;

procedure TCadFeature.LoadParams(O: TJSONObject);
begin
end;

function TCadFeature.Validate: string;
begin
  Result := '';
end;

function TCadFeature.Dependencies: TCadIdArray;
begin
  Result := nil;
end;

procedure TCadFeature.SetState(AState: TCadFeatureState; const AMsg: string);
begin
  State := AState;
  Message := AMsg;
  if AState in [fsWarning,fsError] then
    CadLog('FEATURE.STATE',Format('id=%d name=%s state=%d message=%s',[Id,Name,Ord(AState),AMsg]));
end;

procedure RegisterCadFeature(AKind: TCadFeatureKind; AClass: TCadFeatureClass);
begin
  GClasses[AKind] := AClass;
end;

function CadFeatureClass(AKind: TCadFeatureKind): TCadFeatureClass;
begin
  Result := GClasses[AKind];
end;

function CadFeatureKindFromCode(const ACode: string; out AKind: TCadFeatureKind): Boolean;
var
  K: TCadFeatureKind;
begin
  for K := Low(TCadFeatureKind) to High(TCadFeatureKind) do
    if CAD_FEATURE_CODES[K] = ACode then
    begin
      AKind := K;
      Exit(True);
    end;
  AKind := cfSketch;
  Result := False;
end;

function JNum(O: TJSONObject; const K: string; Def: Double): Double;
var
  D: TJSONData;
begin
  D := O.Find(K);
  if D = nil then
    Exit(Def);
  if not (D.JSONType = jtNumber) then
    raise Exception.CreateFmt('Campo "%s" deve ser número', [K]);
  Result := D.AsFloat;
end;

function JInt(O: TJSONObject; const K: string; Def: Integer): Integer;
var
  D: TJSONData;
begin
  D := O.Find(K);
  if D = nil then
    Exit(Def);
  if not (D.JSONType = jtNumber) then
    raise Exception.CreateFmt('Campo "%s" deve ser número inteiro', [K]);
  Result := D.AsInteger;
end;

function JStr(O: TJSONObject; const K, Def: string): string;
var
  D: TJSONData;
begin
  D := O.Find(K);
  if D = nil then
    Exit(Def);
  if not (D.JSONType = jtString) then
    raise Exception.CreateFmt('Campo "%s" deve ser texto', [K]);
  Result := D.AsString;
end;

function JBool(O: TJSONObject; const K: string; Def: Boolean): Boolean;
var
  D: TJSONData;
begin
  D := O.Find(K);
  if D = nil then
    Exit(Def);
  if not (D.JSONType = jtBoolean) then
    raise Exception.CreateFmt('Campo "%s" deve ser true/false', [K]);
  Result := D.AsBoolean;
end;

end.
