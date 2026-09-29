unit multislicer_types;
{$mode objfpc}{$H+}
interface
type
 TVec3=record X,Y,Z:Double;end;
 TVec2=record X,Y:Double;end;
 TTriangle=record A,B,C:TVec3;end;
 TSegment2=record A,B:TVec2;end;
 TPrinterProfile=record
  Name:string;BedX,BedY,MaxZ,Nozzle,LayerHeight,FilamentDiameter,PrintSpeed,TravelSpeed:Double;
  HotendTemp,BedTemp:Integer;
 end;
implementation
end.
