unit laserpcb_gcode;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,laserpcb_job,laserpcb_types;
type TLaserGCodeExporter=class public class procedure ExportJob(J:TLaserPCBJob;const FN:string);end;
implementation
class procedure TLaserGCodeExporter.ExportJob(J:TLaserPCBJob;const FN:string);
var S:TStringList;I,K:Integer;P:TPathPoint;
begin S:=TStringList.Create;try S.Add('; LaserPCB -> MultiCNC');S.Add('G21');S.Add('G90');S.Add('M5');
 for K:=1 to J.Profile.Passes do begin S.Add(Format('; PASS %d/%d',[K,J.Profile.Passes]));for I:=0 to J.Count-1 do begin P:=J.Point(I);if P.LaserOn then begin S.Add(Format('M4 S%.0f',[J.Profile.Power]));S.Add(Format('G1 X%.3f Y%.3f F%.0f',[P.X,P.Y,J.Profile.Feed]));end else begin S.Add('M5');S.Add(Format('G0 X%.3f Y%.3f',[P.X,P.Y]));end;end;S.Add('M5');end;
 S.Add('M5');S.SaveToFile(FN);finally S.Free;end;end;
end.
