unit multipcb_excellon;
{$mode objfpc}{$H+}
interface
uses multisuite_numfmt, Classes,SysUtils,multipcb_model;
type TExcellonExporter=class public class procedure ExportDrill(P:TPCBProject;const FN:string);end;
implementation
class procedure TExcellonExporter.ExportDrill(P:TPCBProject;const FN:string);
var S:TStringList;I,J:Integer;C:TPCBComponent;
begin S:=TStringList.Create;try S.Add('M48');S.Add('METRIC');S.Add('%');for I:=0 to P.Components.Count-1 do begin C:=TPCBComponent(P.Components[I]);for J:=0 to High(C.Pads)do if C.Pads[J].Drill>0 then S.Add(Format('X%.3fY%.3f',[C.X+C.Pads[J].Position.X,C.Y+C.Pads[J].Position.Y],InvariantFS));end;S.Add('M30');S.SaveToFile(FN);finally S.Free;end;end;
end.
