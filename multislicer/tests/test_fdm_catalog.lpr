program test_fdm_catalog;
{$mode objfpc}{$H+}
uses Classes,SysUtils,Math,fpjson,multisuite_fdm_catalog,multislicer_machines,
  multislicer_printers,multicnc_printer_profiles;
procedure Check(V:Boolean;const Msg:string);
begin if not V then raise Exception.Create(Msg);end;
var I,K:Integer;M:TFDMModel;C:TMachineSpecs;P:TPrinterProfile;D,D2:TPrinterDef;
    B:TPrinterDefs;Names:TStringList;O:TJSONObject;
begin
  C:=MachineCatalog;B:=BuiltinPrinters;Names:=TStringList.Create;
  try
    for I:=0 to FDM_MODEL_COUNT-1 do begin
      M:=FDM_MODELS[I];K:=FindMachine(M.Brand,M.Model);
      Check(K>=0,'machine lookup '+M.Model);
      Check(FindPrinterProfile(M.Brand,M.Model,P),'controller lookup '+M.Model);
      Check((P.VolumeX=M.X) and (P.VolumeY=M.Y) and (P.VolumeZ=M.Z),'consistent volumes');
      Check(P.CatalogOnly and (P.BaudRate=0),'no invented raw serial support');
      Check((P.SourceURL=M.SourceURL) and (P.VerifiedOn='2026-10-15'),'source/date');
      GetPrinterModels(M.Brand,Names);Check(Names.IndexOf(M.Model)>=0,'UI model list');
      D:=MachinePrinterDef(C[K],'Oficina',0,0,0);
      Check((D.VendorWorkflow<>'') and (D.StartGCode='') and (D.EndGCode=''),'vendor workflow');
      Check((D.Nozzle=0.4) and (D.FilamentDiameter=1.75) and (D.MaxPrintSpeed>0),'dimensional defaults');
      Check(FindPrinter(B,M.Brand+' '+M.Model)>=0,'slicer preset list');
      O:=PrinterToJSON(D);
      try D2:=PrinterFromJSON(O);Check(SamePrinter(D,D2),'metadata round trip');finally O.Free;end;
    end;
    Check(FindPrinterProfile('Creality','K2',P) and (P.VolumeX=260) and (P.MaxHotendTemp=300) and (P.MaxBedTemp=100),'K2 distinct');
    Check(FindPrinterProfile('Creality','K2 Pro',P) and (P.VolumeX=300) and (P.MaxBedTemp=110),'K2 Pro distinct');
    Check(FindPrinterProfile('Creality','K2 Plus',P) and (P.VolumeX=350) and (P.MaxHotendTemp=350),'K2 Plus distinct');
    Check(C[FindMachine('Creality','K2 Pro Combo')].Model='K2 Pro','combo maps to exact variant');
    Check(C[FindMachine('Creality','Creality K2 Plus')].Model='K2 Plus','brand prefix exact');
    Check(FindMachine('Creality','K2 Unknown')=-1,'unknown variant not base K2');
    Check(C[FindMachine('Prusa','MK4S')].Model='Original Prusa MK4S','MK4S not MK4');
    Check(FindPrinterProfile('Bambu Lab','X1 Carbon',P) and (P.MaxBedTemp=110),'X1C conservative voltage limit');
    Check(FindPrinterProfile('Creality','Ender-3 V2',P) and not P.CatalogOnly and (P.BaudRate=115200),'legacy behavior');
    Check(PRINTER_PROFILE_COUNT=26,'26 controller models');
    Writeln('PASS: 11 researched FDM models, exact variants, sources, persistence, compatibility and legacy profiles');
  finally Names.Free;end;
end.
