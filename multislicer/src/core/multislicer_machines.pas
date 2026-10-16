unit multislicer_machines;

{ MultiSlicer - catalogo de maquinas por marca e modelo.

  O MultiCNC guarda os equipamentos do usuario (nome, tipo, marca, modelo,
  porta, area de trabalho). Aqui, a partir da marca e do modelo, o MultiSlicer
  completa o resto da configuracao de impressao: bico, filamento, extrusora,
  firmware, mesa aquecida, temperaturas maximas, nivelamento, velocidades e
  retracao, e monta o G-code inicial e final.

  Fontes (pesquisa de 2026-10):
  - definicoes de maquina do UltiMaker Cura (resources/definitions), que dao
    volume, extrusora, retracao e velocidade padrao de cada modelo;
  - fichas tecnicas dos fabricantes e revendas (temperaturas maximas,
    nivelamento, velocidade maxima) quando o Cura nao define.
  Retracao 0 = usa a do material (o material ja separa Bowden e direta).

  O G-code do Cura usa extrusao absoluta (M82) e variaveis proprias; aqui ele
  e reescrito para a extrusao relativa (M83, ligada antes do bloco inicial) e
  para as variaveis do MultiSlicer. }

{$mode objfpc}{$H+}

interface

uses Classes, SysUtils, Math, StrUtils, multislicer_pipeline, multislicer_printers;

type
  TMachineSpec = record
    Brand, Model: string;
    BedX, BedY, BedZ: Double;        { area util de impressao (mm) }
    Nozzle, FilamentDia: Double;
    Extruder: TExtruderKind;
    Flavor: TSlicerFlavor;
    HeatedBed: Boolean;
    MaxHotend, MaxBed: Double;       { graus C }
    HomeCmd: string;                 { 'G28' ou 'G28 W' (Prusa) }
    Leveling: string;                { '' manual, 'M420 S1' malha salva, 'G29' / 'G80' mede }
    LevelingName: string;
    PrintSpeed, MaxSpeed: Double;    { mm/s: recomendada e limite }
    RetractLen, RetractSpeed: Double;
    Source: string;
  end;
  TMachineSpecs = array of TMachineSpec;

function MachineCatalog: TMachineSpecs;
procedure GetMachineBrands(AList: TStrings);
procedure GetMachineModels(const ABrand: string; AList: TStrings);
{ procura por marca + modelo (sem diferenca de maiusculas, espacos ou hifens);
  aceita modelo com sufixo ("Ender-3 V2 Neo" acha "Ender-3 V2"). -1 = nao achou }
function FindMachine(const ABrand, AModel: string): Integer;
function MachineStartGCode(const M: TMachineSpec): string;
function MachineEndGCode(const M: TMachineSpec): string;
{ perfil de impressora pronto para o MultiSlicer; area > 0 substitui a do catalogo }
function MachinePrinterDef(const M: TMachineSpec; const AName: string; WorkX, WorkY, WorkZ: Double): TPrinterDef;
function NormalizeMachineText(const S: string): string;

implementation

var
  Catalog: TMachineSpecs;

procedure Add(const ABrand, AModel: string; X, Y, Z: Double; AExtruder: TExtruderKind;
  AMaxHotend, AMaxBed: Double; const AHome, ALevel, ALevelName: string;
  ASpeed, AMaxSpeed, ARetract, ARetractSpeed: Double; const ASource: string);
var M: TMachineSpec;
begin
  M := Default(TMachineSpec);
  M.Brand := ABrand; M.Model := AModel;
  M.BedX := X; M.BedY := Y; M.BedZ := Z;
  M.Nozzle := 0.4; M.FilamentDia := 1.75;
  M.Extruder := AExtruder;
  M.Flavor := sfMarlin;
  M.HeatedBed := True;
  M.MaxHotend := AMaxHotend; M.MaxBed := AMaxBed;
  M.HomeCmd := AHome;
  M.Leveling := ALevel; M.LevelingName := ALevelName;
  M.PrintSpeed := ASpeed; M.MaxSpeed := AMaxSpeed;
  M.RetractLen := ARetract; M.RetractSpeed := ARetractSpeed;
  M.Source := ASource;
  SetLength(Catalog, Length(Catalog) + 1);
  Catalog[High(Catalog)] := M;
end;

procedure BuildCatalog;
begin
  if Length(Catalog) > 0 then Exit;
  { Creality }
  Add('Creality', 'Ender-3', 220, 220, 250, ekBowden, 260, 110, 'G28', '', 'manual',
    50, 180, 0, 0, 'Cura creality_ender3; MatterHackers');
  Add('Creality', 'Ender-3 Pro', 220, 220, 250, ekBowden, 260, 110, 'G28', '', 'manual',
    50, 180, 0, 0, 'Cura creality_ender3pro');
  Add('Creality', 'Ender-3 V2', 220, 220, 250, ekBowden, 255, 110, 'G28', '', 'manual',
    50, 120, 0, 0, 'Ficha Creality / 3dprintingspace');
  Add('Creality', 'Ender-3 S1', 220, 220, 270, ekDirect, 260, 100, 'G28', 'M420 S1', 'CR Touch (malha salva)',
    60, 150, 0.8, 40, 'Cura creality_ender3s1; MatterHackers');
  Add('Creality', 'Ender-3 V3 SE', 220, 220, 250, ekDirect, 260, 100, 'G28', 'M420 S1', 'automatico (malha salva)',
    180, 250, 0.8, 40, 'Cura creality_ender3v3se');
  Add('Creality', 'CR-10', 300, 300, 400, ekBowden, 260, 110, 'G28', '', 'manual',
    50, 100, 0, 0, 'Cura creality_cr10');
  Add('Creality', 'Ender-5 Pro', 220, 220, 300, ekBowden, 260, 125, 'G28', '', 'manual',
    80, 180, 0, 0, 'Cura creality_ender5; ficha Creality (Capricorn, V4.2.2)');
  { Prusa Research }
  Add('Prusa Research', 'Original Prusa i3 MK3S+', 250, 210, 210, ekDirect, 300, 120, 'G28 W', 'G80', 'SuperPINDA (mede a malha)',
    60, 200, 0.8, 35, 'Cura prusa_i3_mk3; ficha Prusa');
  Add('Prusa Research', 'Original Prusa MK4', 250, 210, 220, ekDirect, 290, 120, 'G28', 'G29', 'celula de carga (mede a malha)',
    100, 200, 0.8, 35, 'Ficha Prusa / 123-3d');
  Add('Prusa Research', 'Original Prusa Mini+', 180, 180, 180, ekBowden, 280, 100, 'G28', 'G29', 'SuperPINDA (mede a malha)',
    50, 180, 3.2, 70, 'Ficha Prusa / printedsolid');
  { Anycubic }
  Add('Anycubic', 'Mega S (i3 Mega)', 210, 210, 205, ekBowden, 250, 110, 'G28', '', 'manual',
    50, 100, 6, 30, 'Cura anycubic_i3_mega_s');
  Add('Anycubic', 'Kobra Neo', 220, 220, 250, ekDirect, 260, 110, 'G28', 'M420 S1', 'LeviQ 25 pontos (malha salva)',
    60, 100, 0.8, 35, 'Ficha Anycubic / 3djake');
  Add('Anycubic', 'Chiron', 400, 400, 450, ekBowden, 260, 100, 'G28', '', 'manual (sensor opcional)',
    50, 100, 0, 0, 'Cura anycubic_chiron');
  { Elegoo }
  Add('Elegoo', 'Neptune 3 Pro', 225, 225, 280, ekDirect, 260, 100, 'G28', '', 'automatico, 36 pontos (firmware)',
    60, 180, 1, 40, 'Cura elegoo_neptune_3pro');
  Add('Elegoo', 'Neptune 3 Plus', 320, 320, 400, ekDirect, 260, 100, 'G28', '', 'automatico, 49 pontos (firmware)',
    60, 180, 1, 40, 'Cura elegoo_neptune_3plus');
  Add('Elegoo', 'Neptune 2S', 220, 220, 250, ekBowden, 260, 100, 'G28', '', 'manual',
    50, 150, 5, 40, 'Cura elegoo_neptune_2s');
  { Artillery }
  Add('Artillery', 'Sidewinder X2', 300, 300, 400, ekDirect, 240, 130, 'G28', 'M420 S1', 'sensor de toque (malha salva)',
    60, 150, 0.8, 35, 'Ficha Artillery / clevercreations; Cura artillery_sidewinder_x1');
end;

function MachineCatalog: TMachineSpecs;
begin
  BuildCatalog;
  Result := Copy(Catalog);
end;

procedure GetMachineBrands(AList: TStrings);
var I: Integer;
begin
  BuildCatalog;
  AList.Clear;
  for I := 0 to High(Catalog) do
    if AList.IndexOf(Catalog[I].Brand) < 0 then
      AList.Add(Catalog[I].Brand);
end;

procedure GetMachineModels(const ABrand: string; AList: TStrings);
var I: Integer;
begin
  BuildCatalog;
  AList.Clear;
  for I := 0 to High(Catalog) do
    if (ABrand = '') or SameText(Catalog[I].Brand, ABrand) then
      if AList.IndexOf(Catalog[I].Model) < 0 then
        AList.Add(Catalog[I].Model);
end;

function NormalizeMachineText(const S: string): string;
var I: Integer; C: Char;
begin
  Result := '';
  for I := 1 to Length(S) do
  begin
    C := LowerCase(S[I]);
    if C in ['a'..'z', '0'..'9'] then Result := Result + C;
  end;
end;

function HasDigit(const S: string): Boolean;
var I: Integer;
begin
  for I := 1 to Length(S) do
    if S[I] in ['0'..'9'] then Exit(True);
  Result := False;
end;

function FindMachine(const ABrand, AModel: string): Integer;
var
  I, BestLen: Integer;
  B, M, CB, CM, Joined: string;
  BrandOk: Boolean;
begin
  BuildCatalog;
  Result := -1;
  B := NormalizeMachineText(ABrand);
  M := NormalizeMachineText(AModel);
  if M = '' then Exit;
  BestLen := 0;
  for I := 0 to High(Catalog) do
  begin
    CB := NormalizeMachineText(Catalog[I].Brand);
    CM := NormalizeMachineText(Catalog[I].Model);
    { a marca pode vir vazia, abreviada ("Prusa") ou repetida dentro do modelo }
    BrandOk := (B = '') or (Pos(B, CB) > 0) or (Pos(CB, B) > 0) or (Pos(B, CM) > 0);
    if not BrandOk then Continue;
    Joined := CB + CM;
    if (M = CM) or (B + M = Joined) then Exit(I);
    { "Prusa MK4" ou "i3 MK3S+" contra "Original Prusa MK4": tira o "original" }
    if StringReplace(CM, 'original', '', []) = StringReplace(M, 'original', '', []) then Exit(I);
    { so o fim do nome: "MK4" acha "Original Prusa MK4" }
    if (Length(M) >= 3) and HasDigit(M) and (Length(CM) > Length(M)) and
       (Copy(CM, Length(CM) - Length(M) + 1, Length(M)) = M) and (Length(M) > BestLen) then
    begin
      Result := I;
      BestLen := Length(M);
    end;
    { modelo com sufixo: fica com o mais longo contido no texto do usuario }
    if (Pos(CM, M) = 1) and (Length(CM) > BestLen) then
    begin
      Result := I;
      BestLen := Length(CM);
    end;
  end;
end;

function Num(V: Double; Decimals: Integer = 1): string;
var FS: TFormatSettings;
begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  Result := FloatToStrF(V, ffFixed, 15, Decimals, FS);
end;

function MachineStartGCode(const M: TMachineSpec): string;
var
  L: TStringList;
  Probe: Boolean;
  Y0, Y1, EPer: Double;
begin
  L := TStringList.Create;
  try
    Probe := (M.Leveling = 'G29') or (M.Leveling = 'G80');
    L.Add('; ' + M.Brand + ' ' + M.Model + ': aquece, referencia' +
      IfThen(M.Leveling <> '', ', nivela', '') + ' e linha de purga');
    if M.HeatedBed then L.Add('M140 S{first_layer_bed_temp}');
    { quem mede a malha mede com o bico morno (sem escorrer na mesa) }
    if Probe then L.Add('M104 S160') else L.Add('M104 S{first_layer_hotend_temp}');
    if M.HeatedBed then L.Add('M190 S{first_layer_bed_temp}');
    L.Add(M.HomeCmd);
    if M.Leveling <> '' then
    begin
      if Probe then L.Add('M109 S160');
      L.Add(M.Leveling + ' ; nivelamento: ' + M.LevelingName);
    end;
    if Probe then L.Add('M104 S{first_layer_hotend_temp}');
    L.Add('M109 S{first_layer_hotend_temp}');
    { linha de purga dupla na borda esquerda (extrusao relativa) }
    Y0 := 20;
    Y1 := Min(M.BedY - 20, 200);
    EPer := 0.083 * Sqr(1.75 / Max(1, M.FilamentDia)) * (M.Nozzle / 0.4);
    L.Add('G92 E0');
    L.Add('G1 Z2.0 F3000');
    L.Add('G1 X0.1 Y' + Num(Y0) + ' Z0.3 F5000');
    L.Add('G1 X0.1 Y' + Num(Y1) + ' Z0.3 F1500 E' + Num((Y1 - Y0) * EPer, 2));
    L.Add('G1 X0.4 Y' + Num(Y1) + ' Z0.3 F5000');
    L.Add('G1 X0.4 Y' + Num(Y0) + ' Z0.3 F1500 E' + Num((Y1 - Y0) * EPer, 2));
    L.Add('G92 E0');
    L.Add('G1 Z2.0 F3000');
    Result := TrimRight(L.Text);
  finally
    L.Free;
  end;
end;

function MachineEndGCode(const M: TMachineSpec): string;
begin
  Result :=
    'M104 S0' + LineEnding +
    IfThen(M.HeatedBed, 'M140 S0' + LineEnding, '') +
    'G91' + LineEnding +
    'G1 E-' + Num(IfThen(M.Extruder = ekBowden, 2, 1)) + ' F2700' + LineEnding +
    'G1 Z10 F3000' + LineEnding +
    'G90' + LineEnding +
    'G1 X0 Y{bed_y} F3000' + LineEnding +
    'M106 S0' + LineEnding +
    'M84 X Y E';
end;

function MachinePrinterDef(const M: TMachineSpec; const AName: string; WorkX, WorkY, WorkZ: Double): TPrinterDef;
begin
  Result := Default(TPrinterDef);
  Result.Name := AName;
  if Result.Name = '' then Result.Name := M.Brand + ' ' + M.Model;
  if WorkX > 0 then Result.BedX := WorkX else Result.BedX := M.BedX;
  if WorkY > 0 then Result.BedY := WorkY else Result.BedY := M.BedY;
  if WorkZ > 0 then Result.BedZ := WorkZ else Result.BedZ := M.BedZ;
  Result.Nozzle := M.Nozzle;
  Result.FilamentDiameter := M.FilamentDia;
  Result.Flavor := M.Flavor;
  Result.Extruder := M.Extruder;
  Result.HeatedBed := M.HeatedBed;
  Result.StartGCode := MachineStartGCode(M);
  Result.EndGCode := MachineEndGCode(M);
  Result.BuiltIn := True;
end;

end.
