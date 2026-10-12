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
    HotendFirst, Hotend: Integer;      { C }
    BedFirst, Bed: Integer;            { C }
    FanPercent, FanFromLayer: Integer;
    Density: Double;                   { g/cm3 }
    FlowPercent: Double;
    RetractBowden, RetractDirect, RetractSpeed: Double; { mm, mm, mm/s }
    CostPerKg: Double;
    Notes: string;
    BuiltIn: Boolean;
  end;
  TMaterialDefs = array of TMaterialDef;

function BuiltinMaterials: TMaterialDefs;
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
  Result.Name := AName;
  Result.Kind := AName;
  Result.HotendFirst := HF; Result.Hotend := H;
  Result.BedFirst := BF; Result.Bed := B;
  Result.FanPercent := Fan; Result.FanFromLayer := 2;
  Result.Density := ADensity;
  Result.FlowPercent := 100;
  Result.RetractBowden := RB; Result.RetractDirect := RD; Result.RetractSpeed := RS;
  Result.CostPerKg := Cost;
  Result.Notes := ANotes;
  Result.BuiltIn := True;
end;

function BuiltinMaterials: TMaterialDefs;
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
  Result[5].Kind := 'Outro';
end;

function MaterialToJSON(const M: TMaterialDef): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.Add('name', M.Name);
  Result.Add('kind', M.Kind);
  Result.Add('hotend_first_layer', M.HotendFirst);
  Result.Add('hotend', M.Hotend);
  Result.Add('bed_first_layer', M.BedFirst);
  Result.Add('bed', M.Bed);
  Result.Add('fan_percent', M.FanPercent);
  Result.Add('fan_from_layer', M.FanFromLayer);
  Result.Add('density', M.Density);
  Result.Add('flow_percent', M.FlowPercent);
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
  Result.BuiltIn := False;
  Result.Name := JStr(O, 'name', 'Material');
  Result.Kind := JStr(O, 'kind', 'Outro');
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
