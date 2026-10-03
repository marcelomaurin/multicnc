unit multicam_gcode;
{$mode objfpc}{$H+}
interface
uses multisuite_numfmt, Classes,SysUtils,multicam_types,multicam_job;
type TCamGCode=class public class procedure ExportJob(J:TCamJob;const FN:string);end;
implementation
class procedure TCamGCode.ExportJob(J:TCamJob;const FN:string);
var S:TStringList;I:Integer;M:TPathMove;
begin S:=TStringList.Create;try S.Add('; MultiCAM -> MultiCNC');S.Add('G21');S.Add('G90');S.Add('M5');if(J.Tool.SpindleRPM>0)then S.Add(Format('M3 S%d',[J.Tool.SpindleRPM]));for I:=0 to J.Count-1 do begin M:=J.Move(I);if M.Rapid then S.Add(Format('G0 X%.3f Y%.3f Z%.3f',[M.P.X,M.P.Y,M.P.Z],InvariantFS)) else if I>0 then begin if M.P.Z<J.Move(I-1).P.Z then S.Add(Format('G1 X%.3f Y%.3f Z%.3f F%.0f',[M.P.X,M.P.Y,M.P.Z,J.Tool.Plunge],InvariantFS))else S.Add(Format('G1 X%.3f Y%.3f Z%.3f F%.0f',[M.P.X,M.P.Y,M.P.Z,J.Tool.Feed],InvariantFS));end;end;S.Add('M5');S.Add(Format('G0 Z%.3f',[J.Settings.SafeZ],InvariantFS));S.SaveToFile(FN);finally S.Free;end;end;
end.
