program test_routing;
{$mode objfpc}{$H+}
uses multipcb_types,multipcb_model,multipcb_board,multipcb_netlist,multipcb_ratsnest,multipcb_router;
procedure AddPad(C:TPCBComponent;const N:string;X,Y:Double);var L:Integer;begin L:=Length(C.Pads);SetLength(C.Pads,L+1);C.Pads[L].Number:=N;C.Pads[L].Position.X:=X;C.Pads[L].Position.Y:=Y;C.Pads[L].Width:=1.8;C.Pads[L].Height:=1.8;C.Pads[L].Drill:=0.8;end;
var P:TPCBProject;B:TBoard;N:TNetlist;R:TRatsnest;C1,C2:TPCBComponent;Net:TNetConnection;A,Z:TPointMM;
begin P:=TPCBProject.Create;B:=TBoard.Create(P);N:=TNetlist.Create;R:=TRatsnest.Create;try C1:=P.AddComponent('U1','MCU','','');C1.X:=10;C1.Y:=10;AddPad(C1,'1',0,0);C2:=P.AddComponent('R1','1k','','');C2.X:=40;C2.Y:=30;AddPad(C2,'1',0,0);Net:=N.AddNet('SIG');Net.Add('U1','1','1');Net.Add('R1','1','1');R.Build(P,N);if R.Count<>1 then Halt(1);A.X:=10;A.Y:=10;Z.X:=40;Z.Y:=30;TInteractiveRouter.Route(B,A,Z,0.4,plTopCopper,'SIG',rm45Degree);if B.TrackCount<>2 then Halt(2);Writeln('MultiPCB routing: OK');finally R.Free;N.Free;B.Free;P.Free;end;end.
