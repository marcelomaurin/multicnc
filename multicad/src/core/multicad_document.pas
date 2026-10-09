unit multicad_document;

(* MultiCAD - documento de peca (.mcad, JSON).

  Formato (decisao D5):
    { "format": "multicad", "version": 1, "name": "...", "units": "mm",
      "material": "Aço 1020", "next_id": 12, "rollback": -1,
      "features": [ {"id": 1, "kind": "plane", "name": "Plano Frontal",
                     "suppressed": false, "params": {...}}, ... ] }
  - Ids persistentes: contador gravado; carregar nunca reaproveita um Id.
  - Documento novo: Plano Frontal (1), Plano Superior (2), Plano Lateral (3)
    e Origem (4), como a arvore do SolidWorks.
  - Erro na leitura nao altera o documento aberto; gravar usa arquivo
    temporario e so troca no fim. *)

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpjson, jsonparser, multicad_types, multicad_feature,
  multicad_refgeom, multicad_sketch, multicad_extrude, multicad_materials,
  multicad_solver;

const
  MCAD_FORMAT = 'multicad';
  MCAD_VERSION = 1;
  MCAD_EXT = '.mcad';
  MCAD_ID_FRONTAL = 1;
  MCAD_ID_SUPERIOR = 2;
  MCAD_ID_LATERAL = 3;
  MCAD_ID_ORIGIN = 4;

type
  TCadDocument = class
  private
    FFeatures: TFPList;
    FNextId: Integer;
    function GetFeature(I: Integer): TCadFeature;
    procedure FreeFeatures;
    function ResolveVar(const AName: string; out AValue: Double): Boolean;
  public
    Name: string;
    FileName: string;
    Material: string;
    { Indice da barra de retrocesso: -1 = no fim; senao so as operacoes com
      indice < RollbackIndex entram na reconstrucao. }
    RollbackIndex: Integer;
    Modified: Boolean;
    constructor Create;
    destructor Destroy; override;
    { Documento novo com os planos padrao e a origem. }
    procedure NewPart;
    function NewId: Integer;
    property NextId: Integer read FNextId;
    function Count: Integer;
    property Features[I: Integer]: TCadFeature read GetFeature; default;
    function Feature(I: Integer): TCadFeature;
    function IndexOfId(AId: Integer): Integer;
    function FindById(AId: Integer): TCadFeature;
    function FindByName(const AName: string): TCadFeature;
    function StdPlane(P: TCadStdPlane): TCadPlane;
    { Nome automatico como no SolidWorks: "Esboço1", "Ressalto-Extrusão2". }
    function AutoName(AKind: TCadFeatureKind): string;
    { Acrescenta no fim (ou antes da barra de retrocesso). Da Id e nome se faltarem. }
    procedure AddFeature(F: TCadFeature);
    function AddSketch(const APlaneRef: string = 'plane:1'; const AName: string = ''): TCadSketch;
    function AddExtrude(ASketchId: Integer; ADepth: Double; AIsCut: Boolean = False): TCadExtrude;
    { Remove; recusa (False + mensagem) se outra operacao depende dela. }
    function DeleteFeature(AId: Integer; out AError: string): Boolean;
    { Operacoes que dependem (direta ou indiretamente) de AId. }
    function Dependents(AId: Integer): TCadIdArray;
    { Confere todas as operacoes e marca o estado. Devolve o numero de erros. }
    function ValidateAll: Integer;
    { Avalia expressao com as cotas do documento ("D1@Esboço1"). }
    function Eval(const AText: string; out AValue: Double; out AError: string): Boolean;
    function MaterialData: TCadMaterial;
    { Avalia as expressoes das cotas do esboco ("D1@Esboço1 / 2") e grava os
      valores. Devolve False e a mensagem na primeira expressao com erro. }
    function ApplyExpressions(S: TCadSketch; out AError: string): Boolean;
    { Expressoes + solver; marca o estado da operacao (ok, aviso se
      subdefinido nao importa: so conflito e superdefinido sao erro/aviso). }
    function SolveSketch(S: TCadSketch): TSketchSolveResult;
    { Resolve todos os esboços na ordem da arvore. Devolve quantos falharam. }
    function SolveAllSketches: Integer;

    function ToJSON: string;
    function LoadFromJSON(const AText: string; out AError: string): Boolean;
    function SaveToFile(const AFileName: string; out AError: string): Boolean;
    function LoadFromFile(const AFileName: string; out AError: string): Boolean;
  end;

const
  CAD_AUTO_PREFIX: array[TCadFeatureKind] of string = ('Origem', 'Plano', 'Eixo',
    'Esboço', 'Ressalto-Extrusão', 'Corte-Extrusão', 'Revolução',
    'Corte-Revolução', 'Furo', 'Filete', 'Chanfro', 'Casca', 'PadrãoL',
    'PadrãoC', 'Espelho');

implementation

uses
  multicad_units;

constructor TCadDocument.Create;
begin
  inherited Create;
  FFeatures := TFPList.Create;
  NewPart;
end;

destructor TCadDocument.Destroy;
begin
  FreeFeatures;
  FFeatures.Free;
  inherited;
end;

procedure TCadDocument.FreeFeatures;
var
  I: Integer;
begin
  for I := FFeatures.Count - 1 downto 0 do
    TObject(FFeatures[I]).Free;
  FFeatures.Clear;
end;

procedure TCadDocument.NewPart;
var
  P: TCadStdPlane;
  F: TCadFeature;
begin
  FreeFeatures;
  FNextId := 1;
  Name := 'Peça1';
  FileName := '';
  Material := CAD_DEFAULT_MATERIAL;
  RollbackIndex := -1;
  for P := Low(TCadStdPlane) to High(TCadStdPlane) do
  begin
    F := TCadPlane.CreateStd(P);
    F.Id := NewId;
    FFeatures.Add(F);
  end;
  F := TCadOrigin.Create;
  F.Id := NewId;
  FFeatures.Add(F);
  Modified := False;
end;

function TCadDocument.NewId: Integer;
begin
  Result := FNextId;
  Inc(FNextId);
end;

function TCadDocument.GetFeature(I: Integer): TCadFeature;
begin
  Result := TCadFeature(FFeatures[I]);
end;

function TCadDocument.Count: Integer;
begin
  Result := FFeatures.Count;
end;

function TCadDocument.Feature(I: Integer): TCadFeature;
begin
  Result := GetFeature(I);
end;

function TCadDocument.IndexOfId(AId: Integer): Integer;
var
  I: Integer;
begin
  for I := 0 to FFeatures.Count - 1 do
    if GetFeature(I).Id = AId then
      Exit(I);
  Result := -1;
end;

function TCadDocument.FindById(AId: Integer): TCadFeature;
var
  I: Integer;
begin
  I := IndexOfId(AId);
  if I >= 0 then
    Result := GetFeature(I)
  else
    Result := nil;
end;

function TCadDocument.FindByName(const AName: string): TCadFeature;
var
  I: Integer;
begin
  for I := 0 to FFeatures.Count - 1 do
    if SameText(GetFeature(I).Name, AName) then
      Exit(GetFeature(I));
  Result := nil;
end;

function TCadDocument.StdPlane(P: TCadStdPlane): TCadPlane;
var
  I: Integer;
  F: TCadFeature;
begin
  for I := 0 to FFeatures.Count - 1 do
  begin
    F := GetFeature(I);
    if (F is TCadPlane) and (TCadPlane(F).PlaneType = ptStandard) and
      (TCadPlane(F).Std = P) then
      Exit(TCadPlane(F));
  end;
  Result := nil;
end;

function TCadDocument.AutoName(AKind: TCadFeatureKind): string;
var
  N: Integer;
begin
  N := 1;
  repeat
    Result := CAD_AUTO_PREFIX[AKind] + IntToStr(N);
    Inc(N);
  until FindByName(Result) = nil;
end;

procedure TCadDocument.AddFeature(F: TCadFeature);
begin
  if F.Id <= 0 then
    F.Id := NewId
  else
  begin
    if IndexOfId(F.Id) >= 0 then
      raise Exception.CreateFmt('Id repetido: %d', [F.Id]);
    if F.Id >= FNextId then
      FNextId := F.Id + 1;
  end;
  if F.Name = '' then
    F.Name := AutoName(F.Kind);
  if (RollbackIndex >= 0) and (RollbackIndex < FFeatures.Count) then
  begin
    FFeatures.Insert(RollbackIndex, F);
    Inc(RollbackIndex);
  end
  else
    FFeatures.Add(F);
  Modified := True;
end;

function TCadDocument.AddSketch(const APlaneRef, AName: string): TCadSketch;
begin
  Result := TCadSketch.Create;
  Result.PlaneRef := APlaneRef;
  Result.Name := AName;
  AddFeature(Result);
end;

function TCadDocument.AddExtrude(ASketchId: Integer; ADepth: Double;
  AIsCut: Boolean): TCadExtrude;
begin
  if AIsCut then
    Result := TCadExtrudeCut.Create
  else
    Result := TCadExtrude.Create;
  Result.SketchId := ASketchId;
  Result.Dir1.Depth := ADepth;
  if AIsCut then
    Result.Dir1.EndCond := ecBlind;
  AddFeature(Result);
end;

function Contains(const A: TCadIdArray; V: Integer): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(A) do
    if A[I] = V then
      Exit(True);
  Result := False;
end;

function TCadDocument.Dependents(AId: Integer): TCadIdArray;
var
  I, J: Integer;
  Deps: TCadIdArray;
  Changed: Boolean;
  F: TCadFeature;
begin
  Result := nil;
  repeat
    Changed := False;
    for I := 0 to FFeatures.Count - 1 do
    begin
      F := GetFeature(I);
      if (F.Id = AId) or Contains(Result, F.Id) then
        Continue;
      Deps := F.Dependencies;
      for J := 0 to High(Deps) do
        if (Deps[J] = AId) or Contains(Result, Deps[J]) then
        begin
          SetLength(Result, Length(Result) + 1);
          Result[High(Result)] := F.Id;
          Changed := True;
          Break;
        end;
    end;
  until not Changed;
end;

function TCadDocument.DeleteFeature(AId: Integer; out AError: string): Boolean;
var
  I: Integer;
  F: TCadFeature;
  D: TCadIdArray;
begin
  Result := False;
  AError := '';
  I := IndexOfId(AId);
  if I < 0 then
  begin
    AError := 'Operação não encontrada';
    Exit;
  end;
  F := GetFeature(I);
  if F.Kind = cfOrigin then
  begin
    AError := 'A origem não pode ser excluída';
    Exit;
  end;
  if (F is TCadPlane) and (TCadPlane(F).PlaneType = ptStandard) then
  begin
    AError := 'Os planos padrão não podem ser excluídos';
    Exit;
  end;
  D := Dependents(AId);
  if Length(D) > 0 then
  begin
    AError := Format('"%s" é usada por %d operação(ões); exclua-as antes',
      [F.Name, Length(D)]);
    Exit;
  end;
  FFeatures.Delete(I);
  F.Free;
  if (RollbackIndex > I) then
    Dec(RollbackIndex);
  Modified := True;
  Result := True;
end;

function TCadDocument.ValidateAll: Integer;
var
  I, J: Integer;
  F: TCadFeature;
  Msg: string;
  Deps: TCadIdArray;
begin
  Result := 0;
  for I := 0 to FFeatures.Count - 1 do
  begin
    F := GetFeature(I);
    Msg := F.Validate;
    if Msg = '' then
    begin
      Deps := F.Dependencies;
      for J := 0 to High(Deps) do
        if IndexOfId(Deps[J]) < 0 then
        begin
          Msg := Format('Referência perdida (Id %d)', [Deps[J]]);
          Break;
        end
        else if IndexOfId(Deps[J]) > I then
        begin
          Msg := Format('Depende de "%s", que está depois na árvore',
            [FindById(Deps[J]).Name]);
          Break;
        end;
    end;
    if Msg <> '' then
    begin
      F.SetState(fsError, Msg);
      Inc(Result);
    end
    else
      F.SetState(fsOk, '');
  end;
end;

function TCadDocument.ResolveVar(const AName: string; out AValue: Double): Boolean;
var
  P: Integer;
  Dim, Owner: string;
  F: TCadFeature;
begin
  Result := False;
  AValue := 0;
  P := Pos('@', AName);
  if P <= 1 then
    Exit;
  Dim := Copy(AName, 1, P - 1);
  Owner := Copy(AName, P + 1, MaxInt);
  F := FindByName(Owner);
  if F is TCadSketch then
    Result := TCadSketch(F).FindDimension(Dim, AValue);
end;

function TCadDocument.Eval(const AText: string; out AValue: Double;
  out AError: string): Boolean;
begin
  Result := CadTryEval(AText, AValue, AError, vkLength, @ResolveVar);
end;

function TCadDocument.MaterialData: TCadMaterial;
begin
  if not CadFindMaterial(Material, Result) then
    CadFindMaterial(CAD_DEFAULT_MATERIAL, Result);
end;

function TCadDocument.ApplyExpressions(S: TCadSketch; out AError: string): Boolean;
var
  I: Integer;
  C: TSketchConstraint;
  V: Double;
  Err: string;
  Kind: TCadValueKind;
begin
  AError := '';
  Result := True;
  for I := 0 to S.ConstraintCount - 1 do
  begin
    C := S.Constraint(I);
    if (C.Expr = '') or not IsDimensionKind(C.Kind) or not C.Driving then
      Continue;
    if C.Kind = ckAngle then
      Kind := vkAngle
    else
      Kind := vkLength;
    if not CadTryEval(C.Expr, V, Err, Kind, @ResolveVar) then
    begin
      AError := Format('%s@%s: %s', [C.DimName, S.Name, Err]);
      Exit(False);
    end;
    S.SetConstraintValue(I, V);
  end;
end;

function TCadDocument.SolveSketch(S: TCadSketch): TSketchSolveResult;
var
  Err: string;
begin
  if not ApplyExpressions(S, Err) then
  begin
    Result := Default(TSketchSolveResult);
    Result.Status := ssConflict;
    Result.Message := Err;
    S.SetState(fsError, Err);
    Exit;
  end;
  Result := CadSolveSketch(S);
  case Result.Status of
    ssConflict: S.SetState(fsError, Result.Message);
    ssOverDefined: S.SetState(fsWarning, Result.Message);
  else
    if Result.Message <> '' then
      S.SetState(fsOk, Result.Message)
    else
      S.SetState(fsOk, '');
  end;
end;

function TCadDocument.SolveAllSketches: Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to Count - 1 do
    if (GetFeature(I) is TCadSketch) and not GetFeature(I).Suppressed then
      if SolveSketch(TCadSketch(GetFeature(I))).Status = ssConflict then
        Inc(Result);
end;

function TCadDocument.ToJSON: string;
var
  Root, FO, P: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
  F: TCadFeature;
begin
  Root := TJSONObject.Create;
  try
    Root.Add('format', MCAD_FORMAT);
    Root.Add('version', MCAD_VERSION);
    Root.Add('name', Name);
    Root.Add('units', 'mm');
    Root.Add('material', Material);
    Root.Add('next_id', FNextId);
    Root.Add('rollback', RollbackIndex);
    Arr := TJSONArray.Create;
    for I := 0 to FFeatures.Count - 1 do
    begin
      F := GetFeature(I);
      FO := TJSONObject.Create;
      FO.Add('id', F.Id);
      FO.Add('kind', CAD_FEATURE_CODES[F.Kind]);
      FO.Add('name', F.Name);
      FO.Add('suppressed', F.Suppressed);
      P := TJSONObject.Create;
      F.SaveParams(P);
      FO.Add('params', P);
      Arr.Add(FO);
    end;
    Root.Add('features', Arr);
    Result := Root.FormatJSON([], 2);
  finally
    Root.Free;
  end;
end;

function TCadDocument.LoadFromJSON(const AText: string; out AError: string): Boolean;
var
  Data, FD: TJSONData;
  Root, FO, P: TJSONObject;
  Arr: TJSONArray;
  List: TFPList;
  I, J, MaxId, Ver: Integer;
  K: TCadFeatureKind;
  Cls: TCadFeatureClass;
  F: TCadFeature;
  NewName, NewMat: string;
  NewNext, NewRoll: Integer;
begin
  Result := False;
  AError := '';
  Data := nil;
  List := TFPList.Create;
  try
    try
      Data := GetJSON(AText);
      if not (Data is TJSONObject) then
        raise Exception.Create('O arquivo não é um documento MultiCAD');
      Root := TJSONObject(Data);
      if JStr(Root, 'format', '') <> MCAD_FORMAT then
        raise Exception.Create('O arquivo não é um documento MultiCAD (format)');
      Ver := JInt(Root, 'version', 0);
      if (Ver < 1) or (Ver > MCAD_VERSION) then
        raise Exception.CreateFmt('Versão %d do arquivo não suportada (esta versão lê até %d)',
          [Ver, MCAD_VERSION]);
      if JStr(Root, 'units', 'mm') <> 'mm' then
        raise Exception.Create('Unidade do arquivo deve ser mm');
      NewName := JStr(Root, 'name', 'Peça1');
      NewMat := JStr(Root, 'material', CAD_DEFAULT_MATERIAL);
      NewNext := JInt(Root, 'next_id', 1);
      NewRoll := JInt(Root, 'rollback', -1);
      FD := Root.Find('features');
      if not (FD is TJSONArray) then
        raise Exception.Create('Lista de operações ausente');
      Arr := TJSONArray(FD);
      MaxId := 0;
      for I := 0 to Arr.Count - 1 do
      begin
        if not (Arr.Items[I] is TJSONObject) then
          raise Exception.CreateFmt('Operação %d inválida', [I + 1]);
        FO := TJSONObject(Arr.Items[I]);
        if not CadFeatureKindFromCode(JStr(FO, 'kind', ''), K) then
          raise Exception.CreateFmt('Operação de tipo desconhecido "%s"', [JStr(FO, 'kind', '')]);
        Cls := CadFeatureClass(K);
        if Cls = nil then
          raise Exception.CreateFmt('Tipo "%s" ainda não suportado nesta versão',
            [CAD_FEATURE_NAMES[K]]);
        F := Cls.Create;
        List.Add(F);
        F.Id := JInt(FO, 'id', 0);
        if F.Id <= 0 then
          raise Exception.CreateFmt('Operação %d sem Id', [I + 1]);
        for J := 0 to List.Count - 2 do
          if TCadFeature(List[J]).Id = F.Id then
            raise Exception.CreateFmt('Id repetido: %d', [F.Id]);
        if F.Id > MaxId then
          MaxId := F.Id;
        F.Name := JStr(FO, 'name', '');
        F.Suppressed := JBool(FO, 'suppressed', False);
        FD := FO.Find('params');
        if FD <> nil then
        begin
          if not (FD is TJSONObject) then
            raise Exception.CreateFmt('Parâmetros inválidos em "%s"', [F.Name]);
          P := TJSONObject(FD);
          try
            F.LoadParams(P);
          except
            on E: Exception do
              raise Exception.CreateFmt('%s: %s', [F.Name, E.Message]);
          end;
        end;
        if F.Kind <> K then
          raise Exception.CreateFmt('Tipo inconsistente em "%s"', [F.Name]);
      end;
      if (NewRoll < -1) or (NewRoll > List.Count) then
        NewRoll := -1;
      { tudo certo: troca o conteudo }
      FreeFeatures;
      for I := 0 to List.Count - 1 do
        FFeatures.Add(List[I]);
      List.Clear;
      Name := NewName;
      Material := NewMat;
      if NewNext <= MaxId then
        NewNext := MaxId + 1;
      FNextId := NewNext;
      RollbackIndex := NewRoll;
      Modified := False;
      Result := True;
    except
      on E: Exception do
        AError := E.Message;
    end;
  finally
    for I := 0 to List.Count - 1 do
      TObject(List[I]).Free;
    List.Free;
    Data.Free;
  end;
end;

function TCadDocument.SaveToFile(const AFileName: string; out AError: string): Boolean;
var
  SL: TStringList;
  Tmp, Bak: string;
begin
  Result := False;
  AError := '';
  Tmp := AFileName + '.tmp';
  SL := TStringList.Create;
  try
    try
      SL.Text := ToJSON;
      SL.SaveToFile(Tmp);
      Bak := AFileName + '.bak';
      if FileExists(Bak) then
        DeleteFile(Bak);
      if FileExists(AFileName) and not RenameFile(AFileName, Bak) then
        raise Exception.Create('Não foi possível substituir ' + AFileName);
      if not RenameFile(Tmp, AFileName) then
      begin
        if FileExists(Bak) then
          RenameFile(Bak, AFileName);
        raise Exception.Create('Não foi possível gravar ' + AFileName);
      end;
      if FileExists(Bak) then
        DeleteFile(Bak);
      FileName := AFileName;
      Modified := False;
      Result := True;
    except
      on E: Exception do
      begin
        AError := E.Message;
        if FileExists(Tmp) then
          DeleteFile(Tmp);
      end;
    end;
  finally
    SL.Free;
  end;
end;

function TCadDocument.LoadFromFile(const AFileName: string; out AError: string): Boolean;
var
  SL: TStringList;
begin
  Result := False;
  AError := '';
  if not FileExists(AFileName) then
  begin
    AError := 'Arquivo não encontrado: ' + AFileName;
    Exit;
  end;
  SL := TStringList.Create;
  try
    try
      SL.LoadFromFile(AFileName);
    except
      on E: Exception do
      begin
        AError := E.Message;
        Exit;
      end;
    end;
    Result := LoadFromJSON(SL.Text, AError);
    if Result then
      FileName := AFileName;
  finally
    SL.Free;
  end;
end;

end.
