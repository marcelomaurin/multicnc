unit multislicer_materials;

{ MultiSlicer - biblioteca de materiais (filamentos) (Etapa 2 do docs/PLANO_TAREFAS.md).

  Valores de partida usuais para cada filamento; o fabricante manda: confira
  a faixa de temperatura impressa no carretel. Perfis do usuario em JSON
  (multislicer_userdata); mesmo nome substitui o pronto.

  Retracao: a extrusora Bowden (Ender-3 original) precisa de retracao bem
  maior que a extrusora direta; o perfil guarda as duas e a tela usa a do
  tipo da impressora escolhida. }

{$mode objfpc}{$H+}

interface

uses Classes, SysUtils, Math, fpjson, multislicer_userdata;

type
  TMaterialDef = record
    Name, Kind: string;
    Brand, Product, SourceURL, VerifiedOn: string;
    HotendMin, HotendMax, BedMin, BedMax: Integer; { published ranges; -1 = ambient bed }
    HotendFirst, Hotend: Integer;      { C }
    BedFirst, Bed: Integer;            { C }
    FanPercent, FanFromLayer: Integer;
    Density: Double;                   { g/cm3 }
    MaxVolumetricFlow: Double;         { mm3/s; calibrar para o hotend }
    FlowPercent: Double;
    RetractBowden, RetractDirect, RetractSpeed: Double; { mm, mm, mm/s }
    CostPerKg: Double;
    Notes: string;
    BuiltIn: Boolean;
  end;
  TMaterialDefs = array of TMaterialDef;

function BuiltinMaterials: TMaterialDefs;
function FilterMaterials(const List: TMaterialDefs; const Kind: string): TMaterialDefs;
function MaterialCaption(const M: TMaterialDef): string;
function MaterialTemperatureInfo(const M: TMaterialDef): string;
function LoadMaterials: TMaterialDefs;
procedure SaveMaterial(const M: TMaterialDef);
function DeleteMaterial(const AName: string): Boolean;
function FindMaterial(const List: TMaterialDefs; const AName: string): Integer;
function MaterialToJSON(const M: TMaterialDef): TJSONObject;
function MaterialFromJSON(O: TJSONObject): TMaterialDef;

implementation

function Mat(const AName: string; HF, H, BF, B, Fan: Integer; ADensity, RB, RD, RS, Cost: Double;
  const ANotes: string): TMaterialDef;
begin
  Result := Default(TMaterialDef);
  Result.Name := AName;
  Result.Kind := AName;
  Result.HotendFirst := HF; Result.Hotend := H;
  Result.BedFirst := BF; Result.Bed := B;
  Result.FanPercent := Fan; Result.FanFromLayer := 2;
  Result.Density := ADensity;
  Result.MaxVolumetricFlow := 8;
  Result.FlowPercent := 100;
  Result.RetractBowden := RB; Result.RetractDirect := RD; Result.RetractSpeed := RS;
  Result.CostPerKg := Cost;
  Result.Notes := ANotes;
  Result.BuiltIn := True;
end;

function BuiltinMaterials: TMaterialDefs;
  procedure Commercial(BaseIndex: Integer; const Brand, Product: string;
    HMin, HMax, BMin, BMax, H, B: Integer; const URL, Detail: string);
  var N: Integer;
  begin
    N := Length(Result); SetLength(Result, N + 1);
    Result[N] := Result[BaseIndex];
    Result[N].Name := Brand + ' ' + Product;
    Result[N].Brand := Brand; Result[N].Product := Product;
    Result[N].SourceURL := URL; Result[N].VerifiedOn := '2026-10-15';
    Result[N].HotendMin := HMin; Result[N].HotendMax := HMax;
    Result[N].BedMin := BMin; Result[N].BedMax := BMax;
    Result[N].HotendFirst := H; Result[N].Hotend := H;
    Result[N].BedFirst := B; Result[N].Bed := B;
    Result[N].CostPerKg := 0; { preco nao pesquisado }
    Result[N].Notes := Detail;
  end;
begin
  SetLength(Result, 6);
  Result[0] := Mat('PLA', 205, 200, 60, 60, 100, 1.24, 5.0, 0.8, 45, 120,
    'Facil de imprimir. Ventoinha cheia a partir da 2a camada.');
  Result[1] := Mat('PETG', 240, 235, 80, 75, 40, 1.27, 5.5, 1.0, 40, 130,
    'Gruda demais em PEI liso: use cola ou fita. Pouca ventoinha; tende a fiapos.');
  Result[2] := Mat('ABS', 245, 240, 105, 100, 0, 1.04, 5.0, 0.8, 45, 110,
    'Precisa de mesa a 100 C e ambiente fechado (empena). Libera vapores: ventile o local.');
  Result[3] := Mat('ASA', 250, 245, 105, 100, 15, 1.07, 5.0, 0.8, 45, 160,
    'Resistente ao sol. Mesmos cuidados do ABS: mesa quente, ambiente fechado e ventilado.');
  Result[4] := Mat('TPU', 230, 225, 50, 50, 60, 1.21, 1.5, 0.5, 20, 180,
    'Flexivel: imprima devagar (15 a 25 mm/s). Em Bowden, pouca retracao e baixa velocidade.');
  Result[5] := Mat('Personalizado', 205, 200, 60, 60, 100, 1.24, 5.0, 0.8, 45, 120,
    'Ajuste os valores conforme o fabricante e salve com um nome.');
  Result[4].MaxVolumetricFlow := 3;
  Result[5].Kind := 'Outro';
  Commercial(0, '3D Lab', 'PLA', 200, 220, -1, 70, 210, 60,
    'https://3dlab.com.br/como-imprimir-com-filamento-pla/', 'Mesa ambiente ate 70 C; 210/60 C usados pelo fabricante.');
  Commercial(2, '3D Lab', 'ABS Premium', 220, 240, 110, 110, 235, 110,
    'https://3dlab.com.br/como-imprimir-com-filamento-abs/', '235/110 C usados pelo fabricante, com adesivo na mesa.');
  Commercial(0, 'Bambu Lab', 'PLA Basic', 190, 230, 35, 45, 210, 40,
    'https://bambulab-us.myshopify.com/products/pla-basic-filament', 'Mesa 35-45 C com cola, conforme a pagina; ajustar ao tipo de placa.');
  Commercial(2, 'Bambu Lab', 'ABS', 240, 270, 80, 100, 255, 90,
    'https://us.store.bambulab.com/products/abs-filament?variant=40475105460360', 'Mesa com cola; usar impressora fechada.');
  Commercial(0, 'Creality', 'Hyper PLA', 190, 230, -1, 60, 210, 60,
    'https://store.creality.com/eu/blogs/basics/3d-printing-retraction', 'Mesa pode ficar sem aquecimento; 60 C e um ponto inicial local.');
  Commercial(0, 'eSUN', 'PLA+', 210, 230, 45, 60, 220, 60,
    'https://www.esun3d.com/es/pla-pro-product', 'PLA+ pertence a familia PLA; conferir a linha no carretel.');
  Commercial(2, 'eSUN', 'ABS+', 230, 270, 95, 110, 250, 100,
    'https://www.esun3d.com/abs-pro-product', 'ABS+ pertence a familia ABS; fabricante recomenda camara fechada.');
  Commercial(0, 'Polymaker', 'PolyLite PLA', 190, 230, 25, 60, 210, 60,
    'https://wiki.polymaker.com/polymaker-products/more-about-our-products/documents/technical-data-sheets/pla/polylite-tm-pla', 'Ficha para bico 0,4 mm; nao se aplica a PolyLite PLA Pro.');
  Commercial(2, 'Polymaker', 'PolyLite ABS', 245, 265, 90, 100, 255, 95,
    'https://shop.polymaker.com/products/polylite-abs', 'Usar impressora fechada; ventoinha desligada.');
  Commercial(0, 'SUNLU', 'PLA (50-100 mm/s)', 200, 210, 50, 60, 205, 60,
    'https://store.sunlu.com/products/over-6kg-of-pla-pla-meta-3d-filaments-1kg-2-2lbs-fit-most-of-fdm-printer?variant=50707218006298', '200-210 C para 50-100 mm/s; fabricante indica 210-240 C para 100-200 mm/s.');
  Commercial(0, 'Voolt3D', 'PLA Velvet Preto', 190, 230, 50, 70, 210, 60,
    'https://voolt3d.com.br/produtos/filamento-pla-preto-velvet-premium/', 'Linha Velvet Preto High Speed Premium, bico 0,4 mm; conferir outras cores/linhas.');
  Commercial(2, 'Voolt3D', 'ABS Natural', 230, 265, 100, 120, 250, 110,
    'https://voolt3d.com.br/produtos/filamento-abs-natural-premium/', 'Linha Natural High Speed Premium, bico 0,4 mm; conferir outras cores/linhas.');
end;

function FilterMaterials(const List: TMaterialDefs; const Kind: string): TMaterialDefs;
var I, N: Integer;
begin
  Result := nil;
  for I := 0 to High(List) do
    if SameText(Trim(List[I].Kind), Trim(Kind)) then
    begin
      N := Length(Result); SetLength(Result, N + 1); Result[N] := List[I];
    end;
end;

function MaterialCaption(const M: TMaterialDef): string;
begin
  if M.BuiltIn and (M.Brand = '') then Result := 'Customizado (padrao ' + M.Kind + ')'
  else Result := M.Name;
  if not M.BuiltIn then Result := Result + ' (meu)';
end;

function MaterialTemperatureInfo(const M: TMaterialDef): string;
var B: string;
begin
  if M.Brand = '' then Exit(M.Notes);
  if M.BedMin < 0 then B := 'ambiente' else B := IntToStr(M.BedMin);
  Result := Format('Faixa do fabricante: bico %d-%d C; mesa %s-%d C.',
    [M.HotendMin, M.HotendMax, B, M.BedMax]) + LineEnding +
    'Valores iniciais ajustaveis. ' + M.Notes;
end;

function MaterialToJSON(const M: TMaterialDef): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.Add('name', M.Name);
  Result.Add('kind', M.Kind);
  Result.Add('brand', M.Brand);
  Result.Add('product', M.Product);
  Result.Add('source_url', M.SourceURL);
  Result.Add('verified_on', M.VerifiedOn);
  Result.Add('hotend_min', M.HotendMin);
  Result.Add('hotend_max', M.HotendMax);
  Result.Add('bed_min', M.BedMin);
  Result.Add('bed_max', M.BedMax);
  Result.Add('hotend_first_layer', M.HotendFirst);
  Result.Add('hotend', M.Hotend);
  Result.Add('bed_first_layer', M.BedFirst);
  Result.Add('bed', M.Bed);
  Result.Add('fan_percent', M.FanPercent);
  Result.Add('fan_from_layer', M.FanFromLayer);
  Result.Add('density', M.Density);
  Result.Add('flow_percent', M.FlowPercent);
  Result.Add('max_volumetric_flow', M.MaxVolumetricFlow);
  Result.Add('retract_bowden', M.RetractBowden);
  Result.Add('retract_direct', M.RetractDirect);
  Result.Add('retract_speed', M.RetractSpeed);
  Result.Add('cost_per_kg', M.CostPerKg);
  Result.Add('notes', M.Notes);
end;

function MaterialFromJSON(O: TJSONObject): TMaterialDef;
var B: TMaterialDef;
begin
  B := BuiltinMaterials[0];
  Result := B;
  Result.MaxVolumetricFlow := JFloat(O, 'max_volumetric_flow', B.MaxVolumetricFlow);
  if IsNan(Result.MaxVolumetricFlow) or IsInfinite(Result.MaxVolumetricFlow) or
    (Result.MaxVolumetricFlow <= 0) then raise Exception.Create('Vazao maxima invalida');
  Result.BuiltIn := False;
  Result.Name := JStr(O, 'name', 'Material');
  Result.Kind := JStr(O, 'kind', 'Outro');
  Result.Brand := JStr(O, 'brand', '');
  Result.Product := JStr(O, 'product', '');
  Result.SourceURL := JStr(O, 'source_url', '');
  Result.VerifiedOn := JStr(O, 'verified_on', '');
  Result.HotendMin := JInt(O, 'hotend_min', 0);
  Result.HotendMax := JInt(O, 'hotend_max', 0);
  Result.BedMin := JInt(O, 'bed_min', 0);
  Result.BedMax := JInt(O, 'bed_max', 0);
  Result.HotendFirst := EnsureRange(JInt(O, 'hotend_first_layer', B.HotendFirst), 0, 400);
  Result.Hotend := EnsureRange(JInt(O, 'hotend', B.Hotend), 0, 400);
  Result.BedFirst := EnsureRange(JInt(O, 'bed_first_layer', B.BedFirst), 0, 150);
  Result.Bed := EnsureRange(JInt(O, 'bed', B.Bed), 0, 150);
  Result.FanPercent := EnsureRange(JInt(O, 'fan_percent', B.FanPercent), 0, 100);
  Result.FanFromLayer := EnsureRange(JInt(O, 'fan_from_layer', B.FanFromLayer), 1, 50);
  Result.Density := EnsureRange(JFloat(O, 'density', B.Density), 0.5, 3);
  Result.FlowPercent := EnsureRange(JFloat(O, 'flow_percent', 100), 50, 150);
  Result.RetractBowden := EnsureRange(JFloat(O, 'retract_bowden', B.RetractBowden), 0, 15);
  Result.RetractDirect := EnsureRange(JFloat(O, 'retract_direct', B.RetractDirect), 0, 15);
  Result.RetractSpeed := EnsureRange(JFloat(O, 'retract_speed', B.RetractSpeed), 5, 150);
  Result.CostPerKg := Max(0, JFloat(O, 'cost_per_kg', 0));
  Result.Notes := JStr(O, 'notes', '');
end;

function FindMaterial(const List: TMaterialDefs; const AName: string): Integer;
var I: Integer;
begin
  for I := 0 to High(List) do
    if SameText(List[I].Name, AName) then Exit(I);
  Result := -1;
end;

function LoadMaterials: TMaterialDefs;
var SR: TSearchRec; Dir: string; O: TJSONObject; M: TMaterialDef; K: Integer;
begin
  Result := BuiltinMaterials;
  Dir := SlicerDataSubDir('materials');
  if FindFirst(Dir + '*.json', faAnyFile, SR) = 0 then
  try
    repeat
      O := LoadJSONObject(Dir + SR.Name);
      if O = nil then Continue;
      try
        M := MaterialFromJSON(O);
      finally
        O.Free;
      end;
      K := FindMaterial(Result, M.Name);
      if K < 0 then
      begin
        K := Length(Result);
        SetLength(Result, K + 1);
      end;
      Result[K] := M;
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
end;

procedure SaveMaterial(const M: TMaterialDef);
var O: TJSONObject;
begin
  if Trim(M.Name) = '' then raise Exception.Create('Informe o nome do material.');
  O := MaterialToJSON(M);
  try
    SaveJSONObject(SlicerDataSubDir('materials') + SafeProfileFileName(M.Name), O);
  finally
    O.Free;
  end;
end;

function DeleteMaterial(const AName: string): Boolean;
begin
  Result := DeleteFile(SlicerDataSubDir('materials') + SafeProfileFileName(AName));
end;

end.
