unit multipcb_ratsnest;
{$mode objfpc}{$H+}
interface
uses SysUtils,multipcb_types,multipcb_model,multipcb_netlist,multipcb_board;
type TRatsLine=record A,B:TPointMM;NetName:string;end;
 TRatsnest=class
 private FLines:array of TRatsLine;function FindComponent(P:TPCBProject;const Ref:string):TPCBComponent;function PadPoint(C:TPCBComponent;const Pad:string;out Pt:TPointMM):Boolean;
 public procedure Build(P:TPCBProject;N:TNetlist;B:TBoard=nil);function Count:Integer;function Line(I:Integer):TRatsLine;
 end;
implementation
function TRatsnest.FindComponent(P:TPCBProject;const Ref:string):TPCBComponent;var I:Integer;begin Result:=nil;for I:=0 to P.Components.Count-1 do if SameText(TPCBComponent(P.Components[I]).Ref,Ref)then Exit(TPCBComponent(P.Components[I]));end;
function TRatsnest.PadPoint(C:TPCBComponent;const Pad:string;out Pt:TPointMM):Boolean;var I:Integer;begin Result:=False;for I:=0 to High(C.Pads)do if SameText(C.Pads[I].Number,Pad)then begin Pt.X:=C.X+C.Pads[I].Position.X;Pt.Y:=C.Y+C.Pads[I].Position.Y;Exit(True);end;end;
procedure TRatsnest.Build(P:TPCBProject;N:TNetlist;B:TBoard);var I,J,K:Integer;Net:TNetConnection;C1,C2:TPCBComponent;A,B:TPointMM;begin SetLength(FLines,0);for I:=0 to N.Count-1 do begin Net:=N.Net(I);if Assigned(B) and B.NetHasTrack(Net.Name) then Continue;for J:=1 to High(Net.Endpoints)do begin C1:=FindComponent(P,Net.Endpoints[J-1].ComponentRef);C2:=FindComponent(P,Net.Endpoints[J].ComponentRef);if Assigned(C1)and Assigned(C2)and PadPoint(C1,Net.Endpoints[J-1].PadNumber,A)and PadPoint(C2,Net.Endpoints[J].PadNumber,B)then begin K:=Length(FLines);SetLength(FLines,K+1);FLines[K].A:=A;FLines[K].B:=B;FLines[K].NetName:=Net.Name;end;end;end;end;
function TRatsnest.Count:Integer;begin Result:=Length(FLines);end;function TRatsnest.Line(I:Integer):TRatsLine;begin Result:=FLines[I];end;
end.
