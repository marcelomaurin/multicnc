program test_eda;
{$mode objfpc}{$H+}
uses multipcb_model,multipcb_schematic,multipcb_board,multipcb_types;
var P:TPCBProject;S:TSchematic;B:TBoard;
begin P:=TPCBProject.Create;S:=TSchematic.Create;B:=TBoard.Create(P);try P.AddComponent('U1','MCU','mcu','dip');S.AddSymbol('U1','MCU','mcu',0,0);S.AddWire(0,0,20,0,'VCC');B.AddTrack(10,10,40,10,0.4,plTopCopper,'VCC');B.AddVia(40,10,1.6,0.8,'VCC');if(S.SymbolCount<>1)or(S.WireCount<>1)or(B.TrackCount<>1)or(B.ViaCount<>1)then Halt(1);Writeln('MultiPCB EDA: OK');finally B.Free;S.Free;P.Free;end;end.
