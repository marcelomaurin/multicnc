program test_machines;
{ catalogo de maquinas: cada impressora do MultiCNC acha seu modelo e o
  G-code gerado fica coerente com a extrusao relativa do MultiSlicer }
{$mode objfpc}{$H+}
uses Classes, SysUtils, Math, multislicer_machines, multislicer_printers, multicnc_printer_profiles;
var
  Brands, Models: TStringList;
  I, J, K, N: Integer;
  Cat: TMachineSpecs;
  Prof: multicnc_printer_profiles.TPrinterProfile;
  P: TPrinterDef;
  S: string;
procedure Check(OK: Boolean; const Msg: string);
begin if not OK then raise Exception.Create(Msg); end;
function Model(const B, M: string): string;
var K: Integer;
begin
  K := FindMachine(B, M);
  if K < 0 then Exit('');
  Result := Cat[K].Model;
end;
begin
  try
    Cat := MachineCatalog;
    Brands := TStringList.Create; Models := TStringList.Create;
    try
      GetPrinterBrands(Brands);
      N := 0;
      for I := 0 to Brands.Count - 1 do
      begin
        GetPrinterModels(Brands[I], Models);
        for J := 0 to Models.Count - 1 do
        begin
          K := FindMachine(Brands[I], Models[J]);
          Check(K >= 0, 'MultiCNC model missing in the catalog: ' + Brands[I] + ' ' + Models[J]);
          Check(FindPrinterProfile(Brands[I], Models[J], Prof), 'MultiCNC profile');
          Check(SameValue(Cat[K].MaxHotend, Prof.MaxHotendTemp, 1) or (Cat[K].MaxHotend <= Prof.MaxHotendTemp + 30),
            'hotend limit coherent: ' + Models[J]);
          Inc(N);
        end;
      end;
      Check(N >= 15, 'all 15 MultiCNC printers checked');
    finally
      Brands.Free; Models.Free;
    end;
    Check(Model('Creality', 'Ender 3') = 'Ender-3', 'spaces and hyphens ignored');
    Check(Model('creality', 'ENDER-3 V2 Neo') = 'Ender-3 V2', 'longest prefix wins for a suffixed model');
    Check(Model('Prusa', 'MK4') = 'Original Prusa MK4', 'short Prusa name');
    Check(Model('Prusa Research', 'i3 MK3S+') = 'Original Prusa i3 MK3S+', 'name without Original');
    Check(Model('', 'Neptune 3 Pro') = 'Neptune 3 Pro', 'brand may be empty');
    Check(Model('Creality', 'Pro') = '', 'ambiguous text does not match');
    Check(Model('Maurinsoft', 'Prototipo') = '', 'unknown model');
    for I := 0 to High(Cat) do
    begin
      P := MachinePrinterDef(Cat[I], '', 0, 0, 0);
      S := P.StartGCode;
      Check((Pos('M82', S) = 0) and (Pos('{first_layer_hotend_temp}', S) > 0) and (Pos('G28', S) > 0),
        'start G-code relative and with variables: ' + Cat[I].Model);
      Check((Cat[I].Leveling = '') or (Pos(Cat[I].Leveling, S) > Pos('G28', S)), 'leveling after homing: ' + Cat[I].Model);
      Check(Pos('{bed_y}', P.EndGCode) > 0, 'end G-code presents the bed');
      Check((P.BedX > 0) and (P.BedX = Cat[I].BedX) and (Cat[I].MaxSpeed >= Cat[I].PrintSpeed), 'catalog values: ' + Cat[I].Model);
    end;
    P := MachinePrinterDef(Cat[FindMachine('Creality', 'Ender-3 S1')], 'Minha', 230, 0, 0);
    Check((P.Name = 'Minha') and (P.BedX = 230) and (P.BedY = 220) and (P.Extruder = ekDirect), 'work area overrides');
    Writeln('MultiSlicer machines: OK (', Length(Cat), ' models, MultiCNC catalog covered, fuzzy match, start/end G-code)');
  except on E: Exception do begin Writeln('FAIL: ', E.Message); Halt(1); end; end;
end.
