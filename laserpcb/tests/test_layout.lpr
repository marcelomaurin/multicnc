program test_layout;
{$mode objfpc}{$H+}
uses Classes,SysUtils,laserpcb_layout,laserpcb_nesting;
var L:TLaserBedLayout;E:TStringList;P:TLayoutPart;
begin L:=TLaserBedLayout.Create;E:=TStringList.Create;try L.BedWidth:=200;L.BedHeight:=100;L.AddItem('A',50,30);L.AddItem('B',60,30);if not TLaserNesting.ArrangeRows(L)then Halt(1);if not L.Validate(E)then begin Writeln(E.Text);Halt(2);end;Writeln('Laser layout: OK');finally E.Free;L.Free;end;end.
