unit multipcb_drc_geometry;
{$mode objfpc}{$H+}
interface
uses Classes,SysUtils,Math,multipcb_model,multipcb_board;
type TGeometryDRC=class
 public class procedure Check(P:TPCBProject;B:TBoard;Clearance,MinTrack,MinDrill:Double;Errors:TStrings);
 end;
implementation
class procedure TGeometryDRC.Check(P:TPCBProject;B:TBoard;Clearance,MinTrack,MinDrill:Double;Errors:TStrings);
var I,J:Integer;T:TTrack;V:TVia;C:TPCBComponent;
begin Errors.Clear;if Clearance<=0 then Errors.Add('DRC: clearance deve ser maior que zero');for I:=0 to B.TrackCount-1 do begin T:=B.TrackAt(I);if T.Width<MinTrack then Errors.Add(Format('DRC: trilha %d abaixo da largura minima',[I+1]));if(T.A.X<0)or(T.A.Y<0)or(T.B.X<0)or(T.B.Y<0)or(T.A.X>P.BoardWidth)or(T.B.X>P.BoardWidth)or(T.A.Y>P.BoardHeight)or(T.B.Y>P.BoardHeight)then Errors.Add(Format('DRC: trilha %d fora da placa',[I+1]));end;for I:=0 to B.ViaCount-1 do begin V:=B.ViaAt(I);if V.Drill<MinDrill then Errors.Add(Format('DRC: via %d com furo abaixo do minimo',[I+1]));if V.Drill>=V.Diameter then Errors.Add(Format('DRC: via %d sem anel anular',[I+1]));end;for I:=0 to P.Components.Count-1 do begin C:=TPCBComponent(P.Components[I]);for J:=0 to High(C.Pads)do if(C.Pads[J].Drill>0)and(C.Pads[J].Drill<MinDrill)then Errors.Add('DRC: '+C.Ref+' pad '+C.Pads[J].Number+' com furo abaixo do minimo');end;end;
end.
