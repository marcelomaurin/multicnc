unit multislicer_gcode;
{$mode objfpc}{$H+}
interface
uses multisuite_numfmt, Classes,SysUtils,Math,multislicer_types,multislicer_engine;
type TSlicerGCode=class public class procedure ExportLayers(Layers:TList;const P:TPrinterProfile;const FN:string);end;
implementation
class procedure TSlicerGCode.ExportLayers(Layers:TList;const P:TPrinterProfile;const FN:string);
var O:TStringList;I,J:Integer;L:TSliceLayer;S:TSegment2;E,D:Double;
begin O:=TStringList.Create;try O.Add('; MultiSlicer -> MultiCNC');O.Add('G21');O.Add('G90');O.Add('M82');O.Add(Format('M140 S%d',[P.BedTemp]));O.Add(Format('M104 S%d',[P.HotendTemp]));O.Add(Format('M190 S%d',[P.BedTemp]));O.Add(Format('M109 S%d',[P.HotendTemp]));O.Add('G28');E:=0;
 for I:=0 to Layers.Count-1 do begin L:=TSliceLayer(Layers[I]);O.Add(Format(';LAYER:%d',[I]));O.Add(Format('G0 Z%.3f F%.0f',[L.Z,P.TravelSpeed*60],InvariantFS));for J:=0 to High(L.Segments)do begin S:=L.Segments[J];O.Add(Format('G0 X%.3f Y%.3f F%.0f',[S.A.X,S.A.Y,P.TravelSpeed*60],InvariantFS));D:=Hypot(S.B.X-S.A.X,S.B.Y-S.A.Y);E:=E+D*0.04;O.Add(Format('G1 X%.3f Y%.3f E%.5f F%.0f',[S.B.X,S.B.Y,E,P.PrintSpeed*60],InvariantFS));end;end;
 O.Add('M104 S0');O.Add('M140 S0');O.Add('M84');O.SaveToFile(FN);finally O.Free;end;end;
end.
