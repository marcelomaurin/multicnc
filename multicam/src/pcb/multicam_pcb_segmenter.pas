unit multicam_pcb_segmenter;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,Math,multicam_types,multicam_job,multisuite_heightmap,multisuite_heightmap_bounds,multisuite_zcompensation;
type TPCBHeightMapSegmenter=class
 public class function Compensate(Source,Dest:TCamJob;Map:THeightMap;ReferenceZ,MaxCorrection,CutThresholdZ,MaxSegmentMM:Double;Errors:TStrings):Boolean;
 end;
implementation
class function TPCBHeightMapSegmenter.Compensate(Source,Dest:TCamJob;Map:THeightMap;ReferenceZ,MaxCorrection,CutThresholdZ,MaxSegmentMM:Double;Errors:TStrings):Boolean;
var I,K,N:Integer;Prev,M:TPathMove;DX,DY,DZ,D,X,Y,Z:Double;C:TZCompensator;P:TCompensatedPoint;
 procedure AddCorrected(AX,AY,AZ:Double;Rapid:Boolean);
 begin if Rapid or(AZ>CutThresholdZ)then begin Dest.AddMove(AX,AY,AZ,Rapid);Exit;end;if not PointInsideHeightMap(Map,AX,AY)then raise Exception.CreateFmt('Ponto fora do height-map X=%.3f Y=%.3f',[AX,AY]);if not C.Correct(AX,AY,AZ,P)then raise Exception.CreateFmt('Correcao Z excede limite X=%.3f Y=%.3f',[AX,AY]);Dest.AddMove(AX,AY,P.CorrectedZ,False);end;
begin Result:=False;Errors.Clear;if not Assigned(Source)or not Assigned(Dest)or not Assigned(Map)then begin Errors.Add('Job ou height-map ausente');Exit;end;if MaxSegmentMM<=0 then begin Errors.Add('MaxSegmentMM invalido');Exit;end;Dest.Clear;Dest.Name:=Source.Name+' [surface compensated]';Dest.Tool:=Source.Tool;Dest.Stock:=Source.Stock;Dest.Settings:=Source.Settings;Dest.Operation:=Source.Operation;C:=TZCompensator.Create(Map);try C.ReferenceZ:=ReferenceZ;C.MaxCorrection:=MaxCorrection;try if Source.Count=0 then begin Errors.Add('Toolpath vazio');Exit;end;Prev:=Source.Move(0);AddCorrected(Prev.P.X,Prev.P.Y,Prev.P.Z,Prev.Rapid);for I:=1 to Source.Count-1 do begin M:=Source.Move(I);DX:=M.P.X-Prev.P.X;DY:=M.P.Y-Prev.P.Y;DZ:=M.P.Z-Prev.P.Z;D:=Hypot(DX,DY);if M.Rapid or(M.P.Z>CutThresholdZ)or(Prev.P.Z>CutThresholdZ)then N:=1 else N:=Max(1,Ceil(D/MaxSegmentMM));for K:=1 to N do begin X:=Prev.P.X+DX*K/N;Y:=Prev.P.Y+DY*K/N;Z:=Prev.P.Z+DZ*K/N;AddCorrected(X,Y,Z,M.Rapid);end;Prev:=M;end;Result:=True;except on E:Exception do begin Dest.Clear;Errors.Add(E.Message);Result:=False;end;end;finally C.Free;end;end;
end.
