program test_sketch_pattern;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Math, multicad_types, multicad_document, multicad_sketch,
  multicad_sketchpattern, multicad_sketchtools, multicad_extrude, multicad_rebuild;
var D,Loaded: TCadDocument; S: TCadSketch; T: TCadSketchSession;
  P: TCadSketchPatternSettings; Seeds: TCadIdArray; E: TSketchEntity;
  Error: string; Id,Before,I,Checks: Integer; RB: TCadRebuilder; Ex: TCadExtrude;
procedure Check(OK: Boolean; const Msg: string);
begin Inc(Checks);if not OK then raise Exception.Create(Msg);end;
procedure Near(A,B: Double; const Msg: string);
begin Check(Abs(A-B)<1E-8,Msg);end;
begin
  D:=TCadDocument.Create;Loaded:=TCadDocument.Create;T:=nil;
  try
    try
      S:=D.AddSketch('plane:1');Id:=S.AddLine(1,2,4,6,True);
      SetLength(Seeds,2);Seeds[0]:=Id;Seeds[1]:=Id;
      P:=DefaultSketchPattern(skpLinear);P.CountX:=3;P.CountY:=2;P.SpacingX:=-10;P.SpacingY:=15;
      Check(CadSketchPattern(S,Seeds,P,Error)=5,'Deduplicated 3x2 grid has 5 new lines');
      Check((S.EntityCount=6) and (S.ConstraintCount=0),'Independent geometry only');
      E:=S.Entity(5);Check(E.Kind=seLine,'Copies remain lines');Near(E.P1.X,-19,'Last X');Near(E.P1.Y,17,'Last Y');
      Near(E.P2.X,-16,'Endpoint X');Near(E.P2.Y,21,'Endpoint Y');Check(E.Construction,'Construction flag');
      Near(S.Entity(0).P1.X,1,'Original unchanged');
      for I:=1 to S.EntityCount-1 do Check(S.Entity(I).Id<>Id,'Fresh persistent ID');
      Before:=S.EntityCount;P.CountX:=1;P.CountY:=3;P.SpacingX:=0;
      Check(CadSketchPattern(S,[Id],P,Error)=2,'Y-only pattern');
      Near(S.Entity(S.EntityCount-1).P1.Y,32,'Y-only last point');
      P.CountX:=1;P.CountY:=1;Before:=S.EntityCount;
      Check((CadSketchPattern(S,[Id],P,Error)=0) and (Error<>''),'Single instance rejected');
      P.CountX:=1000;P.CountY:=1000;
      Check((CadSketchPattern(S,[Id],P,Error)=0) and (S.EntityCount=Before),'Large request rejected atomically');
      P:=DefaultSketchPattern(skpLinear);
      Check(CadSketchPattern(S,[],P,Error)=0,'Empty selection rejected');
      Check(CadSketchPattern(S,[99999],P,Error)=0,'Invalid ID rejected');
      P.SpacingX:=NaN;Check(CadSketchPattern(S,[Id],P,Error)=0,'NaN rejected');
      P.SpacingX:=1E9;Check(CadSketchPattern(S,[Id],P,Error)=0,'Coordinate overflow rejected');
      Check(S.EntityCount=Before,'Invalid requests do not change sketch');
      S:=D.AddSketch('plane:3');Id:=S.AddCircle(12,20,2);
      P:=DefaultSketchPattern(skpCircular);P.CountX:=4;P.Center:=V2(10,20);
      Check(CadSketchPattern(S,[Id],P,Error)=3,'Full circle creates 3 copies');
      Near(S.Entity(1).P1.X,10,'Quarter circle X');Near(S.Entity(1).P1.Y,22,'Quarter circle Y');
      Near(S.Entity(2).P1.X,8,'Half circle X');Near(S.Entity(3).P1.Y,18,'Last not duplicate original');
      Near(S.Entity(3).Radius,2,'Circle radius preserved');
      Check(S.Entity(3).Kind=seCircle,'Copies remain circles');
      P.Angle:=-180;P.CountX:=3;Before:=S.EntityCount;
      Check(CadSketchPattern(S,[Id],P,Error)=2,'Partial clockwise pattern');
      Near(S.Entity(Before).P1.Y,18,'Clockwise quarter');Near(S.Entity(Before+1).P1.X,8,'Partial includes final angle');
      Id:=S.AddArc(10,20,12,20,10,22);P.Angle:=90;P.CountX:=2;
      Check(CadSketchPattern(S,[Id],P,Error)=1,'Arc pattern');E:=S.Entity(S.EntityCount-1);
      Near(E.P1.X,10,'Arc center X');Near(E.P2.Y,22,'Arc rotated start');Near(E.P3.X,8,'Arc rotated end');
      Near(E.Radius,2,'Arc radius');Check(E.Kind=seArc,'Copies remain arcs');
      Id:=S.AddCenterline(10,20,12,20);
      Check(CadSketchPattern(S,[Id],P,Error)=1,'Centerline pattern');
      E:=S.Entity(S.EntityCount-1);Check((E.Kind=seLine) and E.Construction and E.Centerline,'Centerline kind and flags retained');
      Id:=S.AddPoint(12,20);T:=TCadSketchSession.Create(D,S);
      SetLength(T.Selection,1);T.Selection[0]:=PickItem(Id,1);
      Check(T.ApplyPattern(P),'Session repeats selected point entity');Check(Length(T.Selection)=0,'Session selection cleared on success');
      Check(T.Tool=tkSelect,'Selection tool restored');
      Before:=S.EntityCount;P.Angle:=720;
      Check(not T.ApplyPattern(P),'Session failure reported');Check(S.EntityCount=Before,'Failure leaves geometry unchanged');
      Check(Loaded.LoadFromJSON(D.ToJSON,Error),'Roundtrip document');
      S:=TCadSketch(Loaded.FindById(S.Id));Check(S.EntityCount=Before,'Persisted all copies');
      E:=S.Entity(S.EntityCount-1);Near(E.P1.X,10,'Persisted point X');Near(E.P1.Y,22,'Persisted point Y');
      Id:=S.AddReferencePoint(SketchPointRef(D.Feature(4).Id,1,1),V2(1,1));Before:=S.EntityCount;
      P:=DefaultSketchPattern(skpLinear);
      Check((CadSketchPattern(S,[Id],P,Error)=0) and (S.EntityCount=Before),'External reference rejected atomically');
      { A pattern must produce real closed profiles usable by extrusion. }
      FreeAndNil(T);D.NewPart;S:=D.AddSketch('plane:1');Id:=S.AddRectangle(0,0,10,5);
      P:=DefaultSketchPattern(skpLinear);P.CountX:=3;P.SpacingX:=20;
      Check(CadSketchPattern(S,[Id,Id+1,Id+2,Id+3],P,Error)=8,'Two complete rectangle copies');
      Ex:=D.AddExtrude(S.Id,2);Ex.Merge:=False;
      RB:=TCadRebuilder.Create(D);
      try
        Check(RB.Rebuild=0,'Pattern profiles extrude without errors: '+Ex.Message);
        Near(RB.TotalVolume,300,'Extruded volume includes all three profiles');
        for I:=0 to RB.BodyCount-1 do Check(RB.Body(I).Mesh.CheckClosed(Error),'Extruded pattern is closed');
      finally RB.Free;end;
      WriteLn('PASS: ',Checks,' sketch pattern checks');
    finally T.Free;Loaded.Free;D.Free;end;
  except on E:Exception do begin WriteLn('FAIL: ',E.Message);Halt(1);end;end;
end.
