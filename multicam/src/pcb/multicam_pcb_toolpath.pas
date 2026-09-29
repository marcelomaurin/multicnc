unit multicam_pcb_toolpath;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,Math,multicam_types,multicam_job,multipcb_heightmap,multipcb_zcompensation;
type TPCBToolpathCompensator=class
 public class function ApplyHeightMap(Source,Dest:TCamJob;Map:THeightMap;ReferenceZ,MaxCorrection,CutThresholdZ:Double;Errors:TStrings):Boolean;
 end;
implementation
class function TPCBToolpathCompensator.ApplyHeightMap(Source,Dest:TCamJob;Map:THeightMap;ReferenceZ,MaxCorrection,CutThresholdZ:Double;Errors:TStrings):Boolean;
var I:Integer;M:TPathMove;C:TZCompensator;P:TCompensatedPoint;
begin Result:=False;Errors.Clear;if not Assigned(Source)or not Assigned(Dest)or not Assigned(Map)then begin Errors.Add('Job ou height-map ausente');Exit;end;
 Dest.Clear;Dest.Name:=Source.Name+' [Z compensated]';Dest.Tool:=Source.Tool;Dest.Stock:=Source.Stock;Dest.Settings:=Source.Settings;Dest.Operation:=Source.Operation;
 C:=TZCompensator.Create(Map);try C.ReferenceZ:=ReferenceZ;C.MaxCorrection:=MaxCorrection;for I:=0 to Source.Count-1 do begin M:=Source.Move(I);
  if(not M.Rapid)and(M.P.Z<=CutThresholdZ)then begin
   if not C.Correct(M.P.X,M.P.Y,M.P.Z,P)then begin Errors.Add(Format('Compensacao Z invalida em X=%.3f Y=%.3f',[M.P.X,M.P.Y]));Exit;end;
   Dest.AddMove(M.P.X,M.P.Y,P.CorrectedZ,False);
  end else Dest.AddMove(M.P.X,M.P.Y,M.P.Z,M.Rapid);
 end;Result:=True;finally C.Free;end;end;
end.
