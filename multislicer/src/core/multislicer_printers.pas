unit multislicer_printers;

{ MultiSlicer - perfis de impressora (Etapa 2 do docs/PLANO_TAREFAS.md).

  Perfis prontos no codigo (Creality Ender-3, Generic Marlin, Generic Klipper)
  e perfis do usuario em JSON (multislicer_userdata). Um perfil do usuario com
  o mesmo nome de um pronto substitui o pronto na lista.

  G-code inicial e final aceitam variaveis, trocadas no fatiamento:
    {bed_temp} {hotend_temp} {first_layer_bed_temp} {first_layer_hotend_temp}
    {bed_x} {bed_y} {bed_z} {fan_speed}
  Vazio = bloco padrao do pipeline (aquece, G28, espera). }

{$mode objfpc}{$H+}

interface

uses Classes, SysUtils, Math, fpjson, multislicer_pipeline, multislicer_userdata;

type
  TExtruderKind = (ekBowden, ekDirect);

  TPrinterDef = record
    Name: string;
    BedX, BedY, BedZ: Double;
    PrintStartZ: Double; // degrau inicial absoluto, mm
    Nozzle, FilamentDiameter: Double;
    Flavor: TSlicerFlavor;
    Extruder: TExtruderKind;
    HeatedBed: Boolean;
    StartGCode, EndGCode: string;
    BuiltIn: Boolean;
  end;
  TPrinterDefs = array of TPrinterDef;

function BuiltinPrinters: TPrinterDefs;
function LoadPrinters: TPrinterDefs;          { prontos + do usuario }
procedure SavePrinter(const P: TPrinterDef);
function DeletePrinter(const AName: string): Boolean;
function FindPrinter(const List: TPrinterDefs; const AName: string): Integer;
function PrinterToJSON(const P: TPrinterDef): TJSONObject;
function PrinterFromJSON(O: TJSONObject): TPrinterDef;
function SamePrinter(const A, B: TPrinterDef): Boolean;

const
  EXTRUDER_NAMES: array[TExtruderKind] of string = ('Bowden', 'Direta');

implementation

const
  ENDER3_START =
    '; Creality Ender-3: aquece, referencia e linha de purga na borda esquerda' + LineEnding +
    'M140 S{first_layer_bed_temp}' + LineEnding +
    'M104 S{first_layer_hotend_temp}' + LineEnding +
    'G28' + LineEnding +
    'M190 S{first_layer_bed_temp}' + LineEnding +
    'M109 S{first_layer_hotend_temp}' + LineEnding +
    'G92 E0' + LineEnding +
    'G1 Z2.0 F3000' + LineEnding +
    'G1 X0.1 Y20 Z0.3 F5000' + LineEnding +
    'G1 X0.1 Y200 Z0.3 F1500 E15' + LineEnding +
    'G1 X0.4 Y200 Z0.3 F5000' + LineEnding +
    'G1 X0.4 Y20 Z0.3 F1500 E15' + LineEnding +
    'G92 E0' + LineEnding +
    'G1 Z2.0 F3000';
  ENDER3_END =
    'M104 S0' + LineEnding +
    'M140 S0' + LineEnding +
    'G91' + LineEnding +
    'G1 E-2 F2700' + LineEnding +
    'G1 Z10 F3000' + LineEnding +
    'G90' + LineEnding +
    'G1 X0 Y{bed_y} F3000' + LineEnding +
    'M106 S0' + LineEnding +
    'M84 X Y E';

function Def(const AName: string; X, Y, Z: Double; AFlavor: TSlicerFlavor;
  AExtruder: TExtruderKind; const AStart, AEnd: string): TPrinterDef;
begin
  Result.Name := AName;
  Result.BedX := X; Result.BedY := Y; Result.BedZ := Z;
  Result.PrintStartZ := 0;
  Result.Nozzle := 0.4; Result.FilamentDiameter := 1.75;
  Result.Flavor := AFlavor;
  Result.Extruder := AExtruder;
  Result.HeatedBed := True;
  Result.StartGCode := AStart;
  Result.EndGCode := AEnd;
  Result.BuiltIn := True;
end;

function BuiltinPrinters: TPrinterDefs;
begin
  SetLength(Result, 3);
  { Ender-3 original: mesa 235 mm, area util usual 220 x 220 x 250, Bowden }
  Result[0] := Def('Creality Ender-3', 220, 220, 250, sfMarlin, ekBowden, ENDER3_START, ENDER3_END);
  Result[1] := Def('Generic Marlin', 220, 220, 250, sfMarlin, ekDirect, '', '');
  Result[2] := Def('Generic Klipper', 220, 220, 250, sfKlipper, ekDirect, '', '');
end;

function FlavorName(F: TSlicerFlavor): string;
begin
  if F = sfKlipper then Result := 'klipper' else Result := 'marlin';
end;

function PrinterToJSON(const P: TPrinterDef): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.Add('name', P.Name);
  Result.Add('bed_x', P.BedX);
  Result.Add('bed_y', P.BedY);
  Result.Add('bed_z', P.BedZ);
  Result.Add('print_start_z', P.PrintStartZ);
  Result.Add('nozzle', P.Nozzle);
  Result.Add('filament_diameter', P.FilamentDiameter);
  Result.Add('firmware', FlavorName(P.Flavor));
  if P.Extruder = ekBowden then Result.Add('extruder', 'bowden') else Result.Add('extruder', 'direct');
  Result.Add('heated_bed', P.HeatedBed);
  Result.Add('start_gcode', P.StartGCode);
  Result.Add('end_gcode', P.EndGCode);
end;

function PrinterFromJSON(O: TJSONObject): TPrinterDef;
begin
  Result := Def(JStr(O, 'name', 'Impressora'), 220, 220, 250, sfMarlin, ekDirect, '', '');
  Result.BuiltIn := False;
  Result.BedX := EnsureRange(JFloat(O, 'bed_x', 220), 10, 2000);
  Result.BedY := EnsureRange(JFloat(O, 'bed_y', 220), 10, 2000);
  Result.BedZ := EnsureRange(JFloat(O, 'bed_z', 250), 10, 2000);
  Result.PrintStartZ := EnsureRange(JFloat(O, 'print_start_z', 0), 0, Result.BedZ - 0.01);
  Result.Nozzle := EnsureRange(JFloat(O, 'nozzle', 0.4), 0.1, 2);
  Result.FilamentDiameter := EnsureRange(JFloat(O, 'filament_diameter', 1.75), 1, 3.5);
  if SameText(JStr(O, 'firmware', 'marlin'), 'klipper') then Result.Flavor := sfKlipper;
  if SameText(JStr(O, 'extruder', 'direct'), 'bowden') then Result.Extruder := ekBowden;
  Result.HeatedBed := JBool(O, 'heated_bed', True);
  Result.StartGCode := JStr(O, 'start_gcode', '');
  Result.EndGCode := JStr(O, 'end_gcode', '');
end;

function FindPrinter(const List: TPrinterDefs; const AName: string): Integer;
var I: Integer;
begin
  for I := 0 to High(List) do
    if SameText(List[I].Name, AName) then Exit(I);
  Result := -1;
end;

function LoadPrinters: TPrinterDefs;
var SR: TSearchRec; Dir: string; O: TJSONObject; P: TPrinterDef; K: Integer;
begin
  Result := BuiltinPrinters;
  Dir := SlicerDataSubDir('printers');
  if FindFirst(Dir + '*.json', faAnyFile, SR) = 0 then
  try
    repeat
      O := LoadJSONObject(Dir + SR.Name);
      if O = nil then Continue;
      try
        P := PrinterFromJSON(O);
      finally
        O.Free;
      end;
      K := FindPrinter(Result, P.Name);
      if K < 0 then
      begin
        K := Length(Result);
        SetLength(Result, K + 1);
      end;
      Result[K] := P;
    until FindNext(SR) <> 0;
  finally
    FindClose(SR);
  end;
end;

procedure SavePrinter(const P: TPrinterDef);
var O: TJSONObject;
begin
  if Trim(P.Name) = '' then raise Exception.Create('Informe o nome do perfil de impressora.');
  O := PrinterToJSON(P);
  try
    SaveJSONObject(SlicerDataSubDir('printers') + SafeProfileFileName(P.Name), O);
  finally
    O.Free;
  end;
end;

function DeletePrinter(const AName: string): Boolean;
begin
  Result := DeleteFile(SlicerDataSubDir('printers') + SafeProfileFileName(AName));
end;

function SamePrinter(const A, B: TPrinterDef): Boolean;
begin
  Result := SameValue(A.BedX, B.BedX) and SameValue(A.BedY, B.BedY) and SameValue(A.BedZ, B.BedZ) and
    SameValue(A.PrintStartZ, B.PrintStartZ) and SameValue(A.Nozzle, B.Nozzle) and SameValue(A.FilamentDiameter, B.FilamentDiameter) and
    (A.Flavor = B.Flavor) and (A.Extruder = B.Extruder) and (A.HeatedBed = B.HeatedBed) and
    (Trim(A.StartGCode) = Trim(B.StartGCode)) and (Trim(A.EndGCode) = Trim(B.EndGCode));
end;

end.
