unit multipcb_gcode;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,multipcb_model;
type TGCodeExporter=class public class procedure ExportOutline(P:TPCBProject;const FN:string;Depth,Feed:Double);end;
implementation
class procedure TGCodeExporter.ExportOutline(P:TPCBProject;const FN:string;Depth,Feed:Double);
var S:TStringList;
begin S:=TStringList.Create;try S.Add('G21');S.Add('G90');S.Add('G0 Z3');S.Add('G0 X0 Y0');S.Add(Format('G1 Z%.3f F%.0f',[Depth,Feed]));S.Add(Format('G1 X%.3f Y0 F%.0f',[P.BoardWidth,Feed]));S.Add(Format('G1 X%.3f Y%.3f',[P.BoardWidth,P.BoardHeight]));S.Add(Format('G1 X0 Y%.3f',[P.BoardHeight]));S.Add('G1 X0 Y0');S.Add('G0 Z3');S.Add('M5');S.SaveToFile(FN);finally S.Free;end;end;
end.
