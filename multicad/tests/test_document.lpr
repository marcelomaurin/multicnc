program test_multicad_document;
{$mode objfpc}{$H+}
uses SysUtils,multicad_document,multicad_sketch,multicad_extrude;
var D:TCadDocument;S:TCadSketch;E:TCadExtrude;
begin D:=TCadDocument.Create;try S:=D.AddSketch('Sketch1');S.AddRectangle(0,0,40,30);if S.EntityCount<>4 then Halt(1);E:=TCadExtrude.Create('Extrude1',S.ID,10,False);D.AddFeature(E);if D.Count<>2 then Halt(2);if E.Depth<>10 then Halt(3);Writeln('MultiCAD document: OK');finally D.Free;end;end.
