unit multislicer_quality;

{ MultiSlicer - perfis de qualidade (Etapa 5 do docs/PLANO_TAREFAS.md).

  Perfis prontos (como os do Cura): Fino 0,1 / Normal 0,2 / Rascunho 0,3 mm,
  para bico de 0,4 mm. Perfis do usuario em JSON (multislicer_userdata,
  pasta "quality"); mesmo nome substitui o pronto.

  Largura de linha em % do bico (100 a 120% e o usual). Velocidades em mm/s. }

{$mode objfpc}{$H+}

interface

uses Classes, SysUtils, Math, fpjson, multislicer_pipeline, multislicer_userdata;

type
  TQualityDef = record
    Name: string;
    LayerHeight, FirstLayerHeight: Double;
    LineWidthPct: Double;
    Walls, TopLayers, BottomLayers: Integer;
    InfillPercent: Integer;
    Pattern: TInfillPattern;
    WallSpeed, OuterWallSpeed, InfillSpeed, FirstLayerSpeed, TravelSpeed: Double;
    Adaptive, ArcFitting: Boolean;
    ZHop, PressureAdvance: Double;
    Notes: string;
    BuiltIn: Boolean;
  end;
  TQualityDefs = array of TQualityDef;

function BuiltinQualities: TQualityDefs;
function LoadQualities: TQualityDefs;
procedure SaveQuality(const Q: TQualityDef);
function DeleteQuality(const AName: string): Boolean;
function FindQuality(const List: TQualityDefs; const AName: string): Integer;
function QualityToJSON(const Q: TQualityDef): TJSONObject;
function QualityFromJSON(O: TJSONObject): TQualityDef;
function SameQuality(const A, B: TQualityDef): Boolean;
{ confere a coerencia com o bico; devolve a primeira mensagem de erro ou '' }
function CheckQuality(const Q: TQualityDef; Nozzle: Double): string;

implementation

function Q(const AName: string; LH, FLH: Double; AWalls, ATop, ABottom, AInfill: Integer;
  WS, OWS, IS_, FS: Double; const ANotes: string): TQualityDef;
begin
  Result.Name := AName;
  Result.LayerHeight := LH; Result.FirstLayerHeight := FLH;
  Result.LineWidthPct := 112.5;
  Result.Walls := AWalls; Result.TopLayers := ATop; Result.BottomLayers := ABottom;
  Result.InfillPercent := AInfill;
  Result.Pattern := ipGyroid;
  Result.WallSpeed := WS; Result.OuterWallSpeed := OWS; Result.InfillSpeed := IS_;
  Result.FirstLayerSpeed := FS; Result.TravelSpeed := 150;
  Result.Adaptive := False; Result.ArcFitting := True;
  Result.ZHop := 0; Result.PressureAdvance := 0;
  Result.Notes := ANotes;
  Result.BuiltIn := True;
end;

function BuiltinQualities: TQualityDefs;
begin
  SetLength(Result, 3);
  { topo/fundo com espessura parecida (~0,7 mm topo, ~0,5 mm fundo) nos tres }
  Result[0] := Q('Fino', 0.1, 0.2, 3, 7, 5, 20, 40, 25, 60, 20,
    'Camadas de 0,1 mm: acabamento liso, impressao bem mais demorada.');
  Result[1] := Q('Normal', 0.2, 0.2, 3, 4, 3, 20, 50, 30, 70, 20,
    'Equilibrio entre acabamento e tempo. Bom ponto de partida.');
  Result[2] := Q('Rascunho', 0.3, 0.3, 2, 3, 2, 15, 60, 40, 80, 25,
    'Camadas de 0,3 mm: rapido, para prototipo e teste de encaixe.');
end;

function PatternName(P: TInfillPattern): string;
begin
  if P = ipRectilinear then Result := 'rectilinear' else Result := 'gyroid';
end;

function QualityToJSON(const Q: TQualityDef): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.Add('name', Q.Name);
  Result.Add('layer_height', Q.LayerHeight);
  Result.Add('first_layer_height', Q.FirstLayerHeight);
  Result.Add('line_width_percent', Q.LineWidthPct);
  Result.Add('walls', Q.Walls);
  Result.Add('top_layers', Q.TopLayers);
  Result.Add('bottom_layers', Q.BottomLayers);
  Result.Add('infill_percent', Q.InfillPercent);
  Result.Add('infill_pattern', PatternName(Q.Pattern));
  Result.Add('wall_speed', Q.WallSpeed);
  Result.Add('outer_wall_speed', Q.OuterWallSpeed);
  Result.Add('infill_speed', Q.InfillSpeed);
  Result.Add('first_layer_speed', Q.FirstLayerSpeed);
  Result.Add('travel_speed', Q.TravelSpeed);
  Result.Add('adaptive', Q.Adaptive);
  Result.Add('arc_fitting', Q.ArcFitting);
  Result.Add('z_hop', Q.ZHop);
  Result.Add('pressure_advance', Q.PressureAdvance);
  Result.Add('notes', Q.Notes);
end;

function QualityFromJSON(O: TJSONObject): TQualityDef;
var B: TQualityDef;
begin
  B := BuiltinQualities[1];
  Result := B;
  Result.BuiltIn := False;
  Result.Name := JStr(O, 'name', 'Qualidade');
  Result.LayerHeight := EnsureRange(JFloat(O, 'layer_height', B.LayerHeight), 0.02, 1);
  Result.FirstLayerHeight := EnsureRange(JFloat(O, 'first_layer_height', B.FirstLayerHeight), 0.02, 1);
  Result.LineWidthPct := EnsureRange(JFloat(O, 'line_width_percent', B.LineWidthPct), 60, 200);
  Result.Walls := EnsureRange(JInt(O, 'walls', B.Walls), 1, 20);
  Result.TopLayers := EnsureRange(JInt(O, 'top_layers', B.TopLayers), 0, 50);
  Result.BottomLayers := EnsureRange(JInt(O, 'bottom_layers', B.BottomLayers), 0, 50);
  Result.InfillPercent := EnsureRange(JInt(O, 'infill_percent', B.InfillPercent), 0, 100);
  if SameText(JStr(O, 'infill_pattern', 'gyroid'), 'rectilinear') then Result.Pattern := ipRectilinear
  else Result.Pattern := ipGyroid;
  Result.WallSpeed := EnsureRange(JFloat(O, 'wall_speed', B.WallSpeed), 1, 1000);
  Result.OuterWallSpeed := EnsureRange(JFloat(O, 'outer_wall_speed', B.OuterWallSpeed), 1, 1000);
  Result.InfillSpeed := EnsureRange(JFloat(O, 'infill_speed', B.InfillSpeed), 1, 1000);
  Result.FirstLayerSpeed := EnsureRange(JFloat(O, 'first_layer_speed', B.FirstLayerSpeed), 1, 1000);
  Result.TravelSpeed := EnsureRange(JFloat(O, 'travel_speed', B.TravelSpeed), 1, 1000);
  Result.Adaptive := JBool(O, 'adaptive', False);
  Result.ArcFitting := JBool(O, 'arc_fitting', True);
  Result.ZHop := EnsureRange(JFloat(O, 'z_hop', 0), 0, 10);
  Result.PressureAdvance := EnsureRange(JFloat(O, 'pressure_advance', 0), 0, 2);
  Result.Notes := JStr(O, 'notes', '');
end;

function FindQuality(const List: TQualityDefs; const AName: string): Integer;
var I: Integer;
begin
  for I := 0 to High(List) do
    if SameText(List[I].Name, AName) then Exit(I);
  Result := -1;
end;

function LoadQualities: TQualityDefs;
var SR: TSearchRec; Dir: string; O: TJSONObject; QD: TQualityDef; K: Integer;
begin
  Result := BuiltinQualities;
  Dir := SlicerDataSubDir('quality');
  if FindFirst(Dir + '*.json', faAnyFile, SR) = 0 then
  try
    repeat
      O := LoadJSONObject(Dir + SR.Name);
      if O = nil then Continue;
      try
        QD := QualityFromJSON(O);
      finally
        O.Free;
      end;
      K := FindQuality(Result, QD.Name);
      if K < 0 then
      begin
        K := Length(Result);
        SetLength(Result, K + 1);
      end;
      Result[K] := QD;
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
end;

procedure SaveQuality(const Q: TQualityDef);
var O: TJSONObject;
begin
  if Trim(Q.Name) = '' then raise Exception.Create('Informe o nome do perfil de qualidade.');
  O := QualityToJSON(Q);
  try
    SaveJSONObject(SlicerDataSubDir('quality') + SafeProfileFileName(Q.Name), O);
  finally
    O.Free;
  end;
end;

function DeleteQuality(const AName: string): Boolean;
begin
  Result := DeleteFile(SlicerDataSubDir('quality') + SafeProfileFileName(AName));
end;

function SameQuality(const A, B: TQualityDef): Boolean;
begin
  Result := SameValue(A.LayerHeight, B.LayerHeight) and SameValue(A.FirstLayerHeight, B.FirstLayerHeight) and
    SameValue(A.LineWidthPct, B.LineWidthPct) and (A.Walls = B.Walls) and (A.TopLayers = B.TopLayers) and
    (A.BottomLayers = B.BottomLayers) and (A.InfillPercent = B.InfillPercent) and (A.Pattern = B.Pattern) and
    SameValue(A.WallSpeed, B.WallSpeed) and SameValue(A.OuterWallSpeed, B.OuterWallSpeed) and
    SameValue(A.InfillSpeed, B.InfillSpeed) and SameValue(A.FirstLayerSpeed, B.FirstLayerSpeed) and
    SameValue(A.TravelSpeed, B.TravelSpeed) and (A.Adaptive = B.Adaptive) and (A.ArcFitting = B.ArcFitting) and
    SameValue(A.ZHop, B.ZHop) and SameValue(A.PressureAdvance, B.PressureAdvance);
end;

function CheckQuality(const Q: TQualityDef; Nozzle: Double): string;
var FS: TFormatSettings;
begin
  FS := DefaultFormatSettings; FS.DecimalSeparator := ',';
  Result := '';
  if Q.LayerHeight > Nozzle * 0.8 + 1e-9 then
    Result := Format('A altura de camada deve ser no maximo 80%% do diametro do bico (%.2f mm).', [Nozzle * 0.8], FS)
  else if Q.FirstLayerHeight > Nozzle * 0.8 + 1e-9 then
    Result := Format('A altura da 1a camada deve ser no maximo 80%% do diametro do bico (%.2f mm).', [Nozzle * 0.8], FS)
  else if Q.LayerHeight < Nozzle * 0.1 - 1e-9 then
    Result := Format('Altura de camada muito pequena para o bico de %.2f mm.', [Nozzle], FS)
  else if (Q.LineWidthPct < 80) or (Q.LineWidthPct > 150) then
    Result := 'A largura de linha deve ficar entre 80% e 150% do bico.'
  else if Nozzle * Q.LineWidthPct / 100 < Q.LayerHeight * 1.05 then
    Result := 'A largura de linha precisa ser maior que a altura de camada.'
  else if (Q.WallSpeed <= 0) or (Q.OuterWallSpeed <= 0) or (Q.InfillSpeed <= 0) or
    (Q.FirstLayerSpeed <= 0) or (Q.TravelSpeed <= 0) then
    Result := 'Todas as velocidades devem ser maiores que zero.'
  else if Q.FirstLayerSpeed > Q.WallSpeed * 1.5 then
    Result := 'A 1a camada deve ser impressa devagar (no maximo 1,5 vez a velocidade das paredes).';
end;

end.
