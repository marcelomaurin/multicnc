unit laserpcb_gcode;
{$mode objfpc}{$H+}
interface
uses multisuite_numfmt, Classes,SysUtils,laserpcb_job,laserpcb_types;
type TLaserGCodeExporter=class public class procedure ExportJob(J:TLaserPCBJob;const FN:string);end;
implementation
class procedure TLaserGCodeExporter.ExportJob(J:TLaserPCBJob;const FN:string);
var S:TStringList;I,K:Integer;P:TPathPoint;Power,Feed:Double;
begin S:=TStringList.Create;try S.Add('; LaserArt/LaserPCB -> MultiCNC');S.Add('G21');S.Add('G90');S.Add('M5');for K:=1 to J.Profile.Passes do begin S.Add(Format('; PASS %d/%d',[K,J.Profile.Passes]));for I:=0 to J.Count-1 do begin P:=J.Point(I);Power:=P.Power;if Power<=0 then Power:=J.Profile.Power;Feed:=P.Feed;if Feed<=0 then Feed:=J.Profile.Feed;if P.LaserOn then begin if(Power<=0)or(Feed<=0)then raise Exception.Create('Potencia/velocidade nao calibradas no ponto '+IntToStr(I));S.Add(Format('M4 S%.0f',[Power],InvariantFS));S.Add(Format('G1 X%.3f Y%.3f F%.0f',[P.X,P.Y,Feed],InvariantFS));end else begin S.Add('M5');S.Add(Format('G0 X%.3f Y%.3f',[P.X,P.Y],InvariantFS));end;end;S.Add('M5');end;S.Add('M5');S.SaveToFile(FN);finally S.Free;end;end;
end.