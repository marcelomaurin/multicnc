program test_layout3d;
{$mode objfpc}{$H+}
uses Classes,SysUtils,multislicer_layout3d,multislicer_arrange;
var L:TPrintBedLayout;E:TStringList;A,B:TModelPlacement;
begin L:=TPrintBedLayout.Create;E:=TStringList.Create;try A:=L.AddModel('A','',40,30,20);B:=L.AddModel('B','',50,40,30);A.RotX:=30;A.RotY:=20;if A.BoundZ<=20 then Halt(1);if not TAutoArrange3D.ArrangeRows(L)then Halt(2);if not L.Validate(E)then begin Writeln(E.Text);Halt(3);end;Writeln('3D layout: OK');finally E.Free;L.Free;end;end.
