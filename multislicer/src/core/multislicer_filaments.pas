unit multislicer_filaments;

{ MultiSlicer - catalogo de filamentos por tipo, marca e modelo.

  Permite selecionar tipo de material (PLA, ABS, PETG, TPU, ASA), marca comercial
  (Voolt3D, 3D Fila, eSun, Creality, Sunlu, Prusament, Generico) e modelo especifico,
  preenchendo automaticamente as temperaturas recomendadas de bico (1a camada e
  demais) e mesa (1a camada e demais), alem de densidade, ventoinha e retracao. }

{ objfpc}{+}

interface

uses Classes, SysUtils, Math;

type
  TFilamentSpec = record
    Kind: string;           { PLA, ABS, PETG, TPU, ASA }
    Brand: string;          { Voolt3D, 3D Fila, eSun, Creality, Sunlu, Prusament, Generico }
    Model: string;          { PLA Premium, EasyFill, PLA+, etc. }
    HotendFirst: Integer;   { C }
    Hotend: Integer;        { C }
    BedFirst: Integer;      { C }
    Bed: Integer;           { C }
    FanPercent: Integer;    { % }
    FanFromLayer: Integer;
    Density: Double;        { g/cm3 }
    FlowPercent: Double;    { % }
    RetractBowden: Double;  { mm }
    RetractDirect: Double;  { mm }
    RetractSpeed: Double;   { mm/s }
    CostPerKg: Double;      { R$/kg }
    Notes: string;
  end;
  TFilamentSpecs = array of TFilamentSpec;

function FilamentCatalog: TFilamentSpecs;
procedure GetFilamentKinds(AList: TStrings);
procedure GetFilamentBrands(const AKind: string; AList: TStrings);
procedure GetFilamentModels(const AKind, ABrand: string; AList: TStrings);
function FindFilament(const AKind, ABrand, AModel: string; out Spec: TFilamentSpec): Boolean;

implementation

var
  FCatalog: TFilamentSpecs;

procedure AddFilament(const AKind, ABrand, AModel: string;
  HF, H, BF, B, Fan, FanLayer: Integer;
  ADensity, AFlow, ARB, ARD, ARS, ACost: Double;
  const ANotes: string);
var
  S: TFilamentSpec;
begin
  S.Kind := AKind;
  S.Brand := ABrand;
  S.Model := AModel;
  S.HotendFirst := HF;
  S.Hotend := H;
  S.BedFirst := BF;
  S.Bed := B;
  S.FanPercent := Fan;
  S.FanFromLayer := FanLayer;
  S.Density := ADensity;
  S.FlowPercent := AFlow;
  S.RetractBowden := ARB;
  S.RetractDirect := ARD;
  S.RetractSpeed := ARS;
  S.CostPerKg := ACost;
  S.Notes := ANotes;

  SetLength(FCatalog, Length(FCatalog) + 1);
  FCatalog[High(FCatalog)] := S;
end;

procedure BuildFilamentCatalog;
begin
  if Length(FCatalog) > 0 then Exit;

  { PLA - Voolt3D }
  AddFilament('PLA', 'Voolt3D', 'PLA Premium', 205, 200, 60, 60, 100, 2,
    1.24, 100, 5.0, 0.8, 45, 110,
    'Voolt3D PLA Premium: facil de imprimir, mesa 50-60 C, bico 195-215 C.');
  AddFilament('PLA', 'Voolt3D', 'PLA High Speed', 215, 210, 60, 60, 100, 2,
    1.24, 100, 5.0, 0.8, 45, 125,
    'Voolt3D PLA High Speed: alta fluidez para altas velocidades, bico 200-225 C.');
  AddFilament('PLA', 'Voolt3D', 'PLA Silk', 215, 210, 60, 60, 100, 2,
    1.24, 100, 5.0, 0.8, 45, 130,
    'Voolt3D PLA Silk: acabamento brilhante/metalizado, bico 205-225 C.');

  { PLA - 3D Fila }
  AddFilament('PLA', '3D Fila', 'PLA EasyFill', 205, 200, 60, 60, 100, 2,
    1.24, 100, 5.0, 0.8, 45, 115,
    '3D Fila EasyFill: facil adesao e estabilidade dimensional, bico 190-210 C.');
  AddFilament('PLA', '3D Fila', 'PLA Standard Puro', 210, 205, 60, 60, 100, 2,
    1.25, 100, 5.0, 0.8, 45, 120,
    '3D Fila PLA Puro: polimero de alta pureza, bico 200-220 C, mesa 50-65 C.');

  { PLA - eSun }
  AddFilament('PLA', 'eSun', 'PLA+ (PLA Plus)', 215, 210, 60, 60, 100, 2,
    1.24, 100, 5.0, 0.8, 45, 130,
    'eSun PLA+: tenacidade e resistencia a impacto elevadas, bico 205-225 C.');
  AddFilament('PLA', 'eSun', 'ePLA-HS (High Speed)', 220, 215, 60, 60, 100, 2,
    1.23, 100, 4.5, 0.8, 45, 135,
    'eSun ePLA-HS: ideal para velocidades acima de 150 mm/s, bico 210-230 C.');

  { PLA - Creality }
  AddFilament('PLA', 'Creality', 'CR-PLA', 205, 200, 55, 55, 100, 2,
    1.24, 100, 5.0, 0.8, 45, 115,
    'Creality CR-PLA: formulado para impressoras Creality, bico 195-210 C.');
  AddFilament('PLA', 'Creality', 'Hyper PLA', 215, 210, 60, 55, 100, 2,
    1.25, 100, 4.5, 0.8, 45, 140,
    'Creality Hyper PLA: resfriamento ultrarrapido para alta velocidade, bico 210-230 C.');
  AddFilament('PLA', 'Creality', 'Ender-PLA', 200, 195, 55, 50, 100, 2,
    1.24, 100, 5.0, 0.8, 45, 100,
    'Creality Ender Series PLA: bico 190-210 C, mesa 50-60 C.');

  { PLA - Sunlu }
  AddFilament('PLA', 'Sunlu', 'PLA+', 210, 205, 55, 55, 100, 2,
    1.24, 100, 5.0, 0.8, 45, 110,
    'Sunlu PLA+: baixa retracao e boa resistencia de impacto, bico 200-215 C.');

  { PLA - Prusament }
  AddFilament('PLA', 'Prusament', 'Prusament PLA', 215, 215, 60, 60, 100, 2,
    1.24, 100, 4.0, 0.8, 40, 160,
    'Prusament PLA: precisao dimensional rigorosa +-0.02 mm, bico 215 C, mesa 60 C.');

  { PLA - Generico }
  AddFilament('PLA', 'Generico', 'PLA Padrao', 205, 200, 60, 60, 100, 2,
    1.24, 100, 5.0, 0.8, 45, 100,
    'PLA generico: mesa 50-60 C, bico 195-210 C.');

  { ABS - Voolt3D }
  AddFilament('ABS', 'Voolt3D', 'ABS Premium', 245, 240, 105, 100, 0, 2,
    1.04, 100, 5.0, 0.8, 45, 110,
    'Voolt3D ABS Premium: requer mesa a 100 C e ambiente fechado para evitar empenamento.');

  { ABS - 3D Fila }
  AddFilament('ABS', '3D Fila', 'ABS Premium+', 240, 235, 105, 100, 0, 2,
    1.05, 100, 5.0, 0.8, 45, 120,
    '3D Fila ABS Premium+: alta resistencia mecânica e termica, bico 230-250 C.');
  AddFilament('ABS', '3D Fila', 'ABS Alta Fluidez', 245, 240, 110, 105, 0, 2,
    1.04, 100, 5.0, 0.8, 45, 125,
    '3D Fila ABS Alta Fluidez: mesa 100-110 C, bico 235-255 C.');

  { ABS - eSun }
  AddFilament('ABS', 'eSun', 'ABS+', 245, 240, 105, 100, 10, 2,
    1.06, 100, 5.0, 0.8, 45, 135,
    'eSun ABS+: formula modificada com menor empenamento e odor reduzido.');

  { ABS - Creality }
  AddFilament('ABS', 'Creality', 'CR-ABS', 240, 235, 100, 95, 0, 2,
    1.05, 100, 5.0, 0.8, 45, 120,
    'Creality CR-ABS: bico 230-250 C, mesa 90-110 C.');

  { ABS - Sunlu }
  AddFilament('ABS', 'Sunlu', 'ABS', 240, 235, 100, 100, 0, 2,
    1.04, 100, 5.0, 0.8, 45, 115,
    'Sunlu ABS: alta resistencia, bico 230-250 C, mesa 95-105 C.');

  { ABS - Generico }
  AddFilament('ABS', 'Generico', 'ABS Padrao', 245, 240, 105, 100, 0, 2,
    1.04, 100, 5.0, 0.8, 45, 100,
    'ABS generico: mesa 100 C, ambiente fechado e sem vento.');

  { PETG - Voolt3D }
  AddFilament('PETG', 'Voolt3D', 'PETG Premium', 240, 235, 80, 75, 40, 2,
    1.27, 100, 5.5, 1.0, 40, 120,
    'Voolt3D PETG: facilidade de PLA e resistencia de ABS, bico 230-250 C, mesa 70-80 C.');

  { PETG - 3D Fila }
  AddFilament('PETG', '3D Fila', 'PETG XT', 235, 230, 80, 75, 40, 2,
    1.27, 100, 5.5, 1.0, 40, 125,
    '3D Fila PETG XT: alta resistencia quimica e impacto, bico 225-245 C.');
  AddFilament('PETG', '3D Fila', 'PETG High Speed', 245, 240, 85, 80, 50, 2,
    1.27, 100, 5.0, 1.0, 40, 135,
    '3D Fila PETG High Speed: alta fluidez para velocidade, bico 240-260 C.');

  { PETG - eSun }
  AddFilament('PETG', 'eSun', 'PETG', 240, 235, 80, 75, 40, 2,
    1.27, 100, 5.5, 1.0, 40, 130,
    'eSun PETG: otima transparencia e estabilidade dimensional, bico 230-250 C.');

  { PETG - Creality }
  AddFilament('PETG', 'Creality', 'CR-PETG', 235, 230, 75, 70, 40, 2,
    1.27, 100, 5.5, 1.0, 40, 120,
    'Creality CR-PETG: bico 230-250 C, mesa 70-80 C.');

  { PETG - Sunlu }
  AddFilament('PETG', 'Sunlu', 'PETG', 235, 230, 75, 70, 40, 2,
    1.27, 100, 5.5, 1.0, 40, 115,
    'Sunlu PETG: bico 220-240 C, mesa 70-80 C.');

  { PETG - Prusament }
  AddFilament('PETG', 'Prusament', 'Prusament PETG', 245, 240, 85, 80, 50, 2,
    1.27, 100, 5.0, 1.0, 40, 160,
    'Prusament PETG: bico 240-250 C, mesa 80-90 C, boa resistencia mecanica.');

  { PETG - Generico }
  AddFilament('PETG', 'Generico', 'PETG Padrao', 240, 235, 80, 75, 40, 2,
    1.27, 100, 5.5, 1.0, 40, 105,
    'PETG generico: mesa 75 C, bico 235 C.');

  { TPU - Voolt3D }
  AddFilament('TPU', 'Voolt3D', 'TPU 95A', 225, 220, 50, 50, 60, 2,
    1.21, 100, 1.5, 0.5, 20, 170,
    'Voolt3D TPU 95A: elastico e duravel, imprimir em baixa velocidade (20 mm/s).');

  { TPU - 3D Fila }
  AddFilament('TPU', '3D Fila', 'TPU Flex', 225, 220, 50, 45, 60, 2,
    1.21, 100, 1.5, 0.5, 20, 180,
    '3D Fila Flex: flexivel de alta resistencia, bico 215-235 C, mesa 40-60 C.');

  { TPU - eSun }
  AddFilament('TPU', 'eSun', 'eTPU-95A', 225, 220, 50, 50, 60, 2,
    1.21, 100, 1.5, 0.5, 20, 180,
    'eSun eTPU-95A: flexivel Shore 95A, bico 210-230 C.');

  { TPU - Creality }
  AddFilament('TPU', 'Creality', 'CR-TPU', 220, 215, 50, 50, 60, 2,
    1.21, 100, 1.5, 0.5, 20, 175,
    'Creality CR-TPU: flexivel dureza 95A, bico 210-230 C.');

  { TPU - Sunlu }
  AddFilament('TPU', 'Sunlu', 'TPU 95A', 220, 215, 50, 50, 60, 2,
    1.21, 100, 1.5, 0.5, 20, 160,
    'Sunlu TPU: flexivel Shore 95A, bico 205-225 C.');

  { TPU - Generico }
  AddFilament('TPU', 'Generico', 'TPU Flexivel', 230, 225, 50, 50, 60, 2,
    1.21, 100, 1.5, 0.5, 20, 150,
    'TPU generico: imprima devagar (15 a 25 mm/s), pouco tracionamento.');

  { ASA - Voolt3D }
  AddFilament('ASA', 'Voolt3D', 'ASA', 250, 245, 105, 100, 15, 2,
    1.07, 100, 5.0, 0.8, 45, 150,
    'Voolt3D ASA: resistente a UV e intemperies externas, mesa 95-105 C.');

  { ASA - 3D Fila }
  AddFilament('ASA', '3D Fila', 'ASA', 250, 245, 105, 100, 15, 2,
    1.07, 100, 5.0, 0.8, 45, 160,
    '3D Fila ASA: resistencia UV superior ao ABS, bico 240-260 C.');

  { ASA - eSun }
  AddFilament('ASA', 'eSun', 'eASA', 250, 245, 105, 100, 15, 2,
    1.07, 100, 5.0, 0.8, 45, 160,
    'eSun eASA: estabilidade termica e anti-UV, bico 240-260 C.');

  { ASA - Prusament }
  AddFilament('ASA', 'Prusament', 'Prusament ASA', 260, 255, 110, 105, 20, 2,
    1.07, 100, 4.0, 0.8, 40, 180,
    'Prusament ASA: precisao e alta resistencia a intemperies, bico 255-265 C.');

  { ASA - Generico }
  AddFilament('ASA', 'Generico', 'ASA Padrao', 250, 245, 105, 100, 15, 2,
    1.07, 100, 5.0, 0.8, 45, 140,
    'ASA generico: mesa quente e ambiente fechado.');
end;

function FilamentCatalog: TFilamentSpecs;
begin
  BuildFilamentCatalog;
  Result := Copy(FCatalog);
end;

procedure GetFilamentKinds(AList: TStrings);
var
  I: Integer;
begin
  BuildFilamentCatalog;
  AList.Clear;
  for I := 0 to High(FCatalog) do
    if AList.IndexOf(FCatalog[I].Kind) < 0 then
      AList.Add(FCatalog[I].Kind);
end;

procedure GetFilamentBrands(const AKind: string; AList: TStrings);
var
  I: Integer;
begin
  BuildFilamentCatalog;
  AList.Clear;
  for I := 0 to High(FCatalog) do
  begin
    if (AKind = '') or SameText(FCatalog[I].Kind, AKind) then
      if AList.IndexOf(FCatalog[I].Brand) < 0 then
        AList.Add(FCatalog[I].Brand);
  end;
end;

procedure GetFilamentModels(const AKind, ABrand: string; AList: TStrings);
var
  I: Integer;
begin
  BuildFilamentCatalog;
  AList.Clear;
  for I := 0 to High(FCatalog) do
  begin
    if ((AKind = '') or SameText(FCatalog[I].Kind, AKind)) and
       ((ABrand = '') or SameText(FCatalog[I].Brand, ABrand)) then
      if AList.IndexOf(FCatalog[I].Model) < 0 then
        AList.Add(FCatalog[I].Model);
  end;
end;

function FindFilament(const AKind, ABrand, AModel: string; out Spec: TFilamentSpec): Boolean;
var
  I: Integer;
begin
  BuildFilamentCatalog;
  for I := 0 to High(FCatalog) do
  begin
    if SameText(FCatalog[I].Kind, AKind) and
       SameText(FCatalog[I].Brand, ABrand) and
       SameText(FCatalog[I].Model, AModel) then
    begin
      Spec := FCatalog[I];
      Exit(True);
    end;
  end;
  { Busca tolerante se marca for vazia ou modelo exato }
  for I := 0 to High(FCatalog) do
  begin
    if (SameText(FCatalog[I].Model, AModel) or (Pos(UpperCase(AModel), UpperCase(FCatalog[I].Model)) > 0)) and
       ((AKind = '') or SameText(FCatalog[I].Kind, AKind)) then
    begin
      Spec := FCatalog[I];
      Exit(True);
    end;
  end;
  Result := False;
end;

end.
