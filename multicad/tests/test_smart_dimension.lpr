program test_smart_dimension;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils,Math,multicad_feature,multicad_types,multicad_sketch,multicad_document,
  multicad_sketchtools,multicad_solver,multicad_refgeom,multicad_extrude,multicad_rebuild;
type TAnswer=class
  Value:string;
  function Ask(Sender:TObject;const Caption:string;var Text:string;var RefOnly:Boolean):Boolean;
end;
function TAnswer.Ask(Sender:TObject;const Caption:string;var Text:string;var RefOnly:Boolean):Boolean;
begin Text:=Value;RefOnly:=False;Result:=True;end;
var D,D2:TCadDocument;S,Source:TCadSketch;T:TCadSketchSession;RB:TCadRebuilder;
  Refs:TCadReferencePoints;C:TSketchConstraint;E:TSketchEntity;G:TCadDimGeom;
  Answer:TAnswer;Idx,Id,SourceId,SourceEntity,ActiveId,I:Integer;Err:string;P:TCadVec2;
procedure Check(OK:Boolean;const Msg:string);
begin if not OK then raise Exception.Create(Msg);end;
function Near(A,B:Double):Boolean;begin Result:=Abs(A-B)<1E-6;end;
function Current:TSketchConstraint;
begin Idx:=S.ConstraintIndex(T.PlacingDim);Check(Idx>=0,'Dimension preview exists');Result:=S.Constraint(Idx);end;
begin
  D:=TCadDocument.Create;D2:=TCadDocument.Create;T:=nil;RB:=TCadRebuilder.Create(D);Answer:=TAnswer.Create;
  try
    try
      S:=D.AddSketch('plane:1');S.AddLine(10,10,40,50);T:=TCadSketchSession.Create(D,S);T.PickTol:=0.2;T.Tool:=tkDimension;
      T.Click(V2(25,30));C:=Current;Check(C.Kind=ckDistance,'Line midpoint selects actual length');
      T.MouseMove(V2(25,65));C:=Current;Check((C.Kind=ckHorizontalDistance) and Near(C.Value,30),'Above segment infers X=30');
      Check(T.DimGeometry(Idx,G) and Near(G.DA.Y,G.DB.Y),'Horizontal preview is horizontal');
      T.MouseMove(V2(55,30));C:=Current;Check((C.Kind=ckVerticalDistance) and Near(C.Value,40),'Beside segment infers Y=40');
      T.MouseMove(V2(55,65));C:=Current;Check((C.Kind=ckDistance) and Near(C.Value,50),'Outside both spans infers aligned length=50');
      T.Click(V2(55,65));Check((T.PlacingDim=0) and (S.Constraint(0).Kind=ckDistance),'Final click retains inferred kind');
      T.Free;T:=nil;
      S:=D.AddSketch('plane:1');Id:=S.AddPoint(30,40);T:=TCadSketchSession.Create(D,S);T.PickTol:=0.2;T.Tool:=tkDimension;
      T.Click(V2(0,0));T.Click(V2(30,40));T.MouseMove(V2(15,60));C:=Current;
      Check((C.Kind=ckHorizontalDistance) and Near(C.Value,30),'Two points infer X');
      Answer.Value:='60';T.OnAskDim:=@Answer.Ask;T.Click(V2(15,60));E:=S.Entity(S.EntityIndex(Id));
      Check(Near(E.P1.X,60) and Near(E.P1.Y,40),'X dimension drives only X');
      T.Free;T:=nil;
      Source:=D.AddSketch('plane:1');SourceEntity:=Source.AddLine(7,9,17,9);SourceId:=Source.Id;
      S:=D.AddSketch('plane:2');ActiveId:=S.Id;Id:=S.AddPoint(12,14);T:=TCadSketchSession.Create(D,S);T.PickTol:=0.2;T.Tool:=tkDimension;
      SetLength(Refs,1);Refs[0].Ref:=SketchPointRef(Source.Id,SourceEntity,1);Refs[0].P:=V2(7,0);T.SetReferencePoints(Refs);
      T.Click(V2(7,0));T.Click(V2(12,14));T.MouseMove(V2(10,20));C:=Current;
      Check((C.Kind=ckHorizontalDistance) and Near(C.Value,5),'Background source point selected for X positioning');
      Answer.Value:='10';T.OnAskDim:=@Answer.Ask;T.Click(V2(10,20));
      Check(Near(S.Entity(S.EntityIndex(Id)).P1.X,17),'Reference dimension moves active geometry');
      Check(Near(Source.Entity(0).P1.X,7),'Reference dimension does not move source geometry');
      Check(T.LastSolve.VarCount=2,'Projected source point has no solver variables');
      Check(RB.Rebuild=0,'Referenced sketches rebuild');
      E:=Source.Entity(0);E.P1.X:=9;Source.SetEntity(0,E);Check(RB.Rebuild=0,'Source movement rebuilds dependents');
      Check(Near(S.Entity(S.EntityIndex(Id)).P1.X,19),'Source movement updates driving dimension');
      Check(SketchReferencePoint(Source,SourceEntity,4,P) and Near(P.X,13) and Near(P.Y,9),'Line midpoint reference');
      I:=Source.AddCircle(50,20,3);Check(SketchReferencePoint(Source,I,1,P) and Near(P.X,50) and Near(P.Y,20),'Circle center reference');
      Check(D2.LoadFromJSON(D.ToJSON,Err),'Reference JSON reload: '+Err);
      S:=TCadSketch(D2.FindById(ActiveId));Check(S.Entity(1).SourceRef=Refs[0].Ref,'Reference link persists in file');
      Check(not D.DeleteFeature(SourceId,Err),'Source deletion blocked by dependency');
      T.Free;T:=nil;
      S:=TCadSketch(D.FindById(ActiveId));Source.DeleteEntity(SourceEntity);
      Check(RB.Rebuild>0,'Missing source point is reported');Check(S.State=fsError,'Missing reference marks active sketch with error');
      Source.AddLine(7,9,17,9); { new ID must not silently reconnect the missing reference }
      Check(RB.Rebuild>0,'Reference identity is persistent, not entity array position');
      S:=D.AddSketch('plane:1');S.AddPoint(20,10);T:=TCadSketchSession.Create(D,S);T.Tool:=tkDimension;T.PickTol:=0.2;
      Refs[0].P:=V2(7,9);T.SetReferencePoints(Refs);T.Click(V2(7,9));T.Click(V2(20,10));Check(S.EntityCount=2,'Preview imports reference point');
      T.Cancel;Check((S.ConstraintCount=0) and (S.EntityCount=1),'Escape removes preview and unused reference proxy');
      WriteLn('PASS: X/Y/aligned inference, diagonal line midpoint, driving value, associative projected references, persistence, missing reference and Escape');
    finally T.Free;RB.Free;D.Free;D2.Free;Answer.Free;end;
  except on E:Exception do begin WriteLn('FAIL: ',E.Message);Halt(1);end;end;
end.
