unit multislicer_profile;
{$mode objfpc}{$H+}
interface
uses multislicer_types;
function DefaultPrinterProfile:TPrinterProfile;
implementation
function DefaultPrinterProfile:TPrinterProfile;
begin Result.Name:='Generic Marlin';Result.BedX:=220;Result.BedY:=220;Result.MaxZ:=250;Result.Nozzle:=0.4;Result.LayerHeight:=0.2;Result.FilamentDiameter:=1.75;Result.PrintSpeed:=50;Result.TravelSpeed:=120;Result.HotendTemp:=200;Result.BedTemp:=60;end;
end.
