program test_sketch_trim;
{$mode objfpc}{$H+}{$codepage utf8}
uses SysUtils, Math, multicad_types, multicad_document, multicad_sketch,
  multicad_sketchtools, multicad_sketchtrim, multicad_profile, multicad_rebuild,
  multicad_extrude, multicad_solver;
var
  D, Loaded: TCadDocument; S: TCadSketch; T: TCadSketchSession;
  Cut: TCadTrimSegment; E: TSketchEntity; Id, RightId, C1, C2, DimId, I, Checks: Integer;
  Before, Error: string; P: TCadProfileResult; RB: TCadRebuilder;

procedure Check(OK: Boolean; const Msg: string);
begin Inc(Checks); if not OK then raise Exception.Create(Msg); end;
procedure Near(A, B: Double; const Msg: string);
begin Check(Abs(A - B) < 1E-7, Msg + Format(' (%.9f / %.9f)', [A, B])); end;
procedure Fresh;
begin
  FreeAndNil(T); D.NewPart; S := D.AddSketch('plane:1');
end;
procedure Session;
begin T := TCadSketchSession.Create(D, S); T.PickTol := 0.1; T.Tool := tkTrim; end;
function Entity(AId: Integer): TSketchEntity;
begin Result := S.Entity(S.EntityIndex(AId)); end;
procedure Bounds(AId: Integer; X1, Y1, X2, Y2: Double);
var Line: TSketchEntity;
begin
  Line := Entity(AId); Near(Line.P1.X, X1, 'Start X'); Near(Line.P1.Y, Y1, 'Start Y');
  Near(Line.P2.X, X2, 'End X'); Near(Line.P2.Y, Y2, 'End Y');
end;
procedure ValidRefs;
var I: Integer; C: TSketchConstraint;
begin
  for I := 0 to S.ConstraintCount - 1 do
  begin
    C := S.Constraint(I);
    Check((C.EntityA <= 0) or (S.EntityIndex(C.EntityA) >= 0), 'Valid A reference');
    Check((C.EntityB <= 0) or (S.EntityIndex(C.EntityB) >= 0), 'Valid B reference');
    Check((C.EntityC <= 0) or (S.EntityIndex(C.EntityC) >= 0), 'Valid C reference');
  end;
end;
begin
  D := TCadDocument.Create; Loaded := TCadDocument.Create; T := nil;
  try
    try
      Fresh; Id := S.AddLine(0, 0, 10, 0);
      C1 := S.AddLine(3, -5, 3, 5); C2 := S.AddLine(7, -5, 7, 5); Session;
      Before := D.ToJSON;
      Check(CadSketchTrimPreview(S, V2(5, 0.02), 0.1, Cut), 'Middle preview');
      Near(Cut.A.X, 3, 'Left intersection'); Near(Cut.B.X, 7, 'Right intersection');
      Check(D.ToJSON = Before, 'Preview never mutates document');
      T.GridSnap := True; T.GridStep := 100; T.MouseMove(V2(5, 0.02));
      Near(T.Cursor.P.X, 5, 'Trim cursor ignores grid');
      Check(T.Click(V2(5, 0.02)), 'Click removes middle portion');
      Check((S.EntityCount = 4) and (T.Tool = tkTrim), 'Two survivors and tool remains active');
      RightId := S.Entity(3).Id; Check(RightId <> Id, 'New stable ID for second survivor');
      Bounds(Id, 0, 0, 3, 0); Bounds(RightId, 7, 0, 10, 0);
      Bounds(C1, 3, -5, 3, 5); Bounds(C2, 7, -5, 7, 5);
      Before := D.ToJSON; Check(Loaded.LoadFromJSON(Before, Error), 'Trim roundtrip');
      Check(Loaded.ToJSON = Before, 'Geometry and IDs persist exactly');
      Check(not T.Click(V2(5, 0)), 'Click in removed gap is harmless');
      Check(D.ToJSON = Before, 'Miss leaves history state unchanged');
      T.Tool := tkSelect; Check(T.ClickCount = 0, 'Finishing Trim leaves no pending click');

      Fresh; Id := S.AddLine(0, 0, 10, 0); S.AddLine(5, -3, 5, 3);
      DimId := S.AddDimension(ckDistance, Id, 0, 0, 0, 10);
      C1 := S.AddFixed(Id, 2); C2 := S.AddConstraint(ckCoincident, Id, 1, CAD_SKETCH_ORIGIN, 1);
      Session; Check(T.Click(V2(2, 0)), 'Cut start up to first crossing');
      Bounds(Id, 5, 0, 10, 0); Check(S.EntityCount = 2, 'Endpoint cut does not split');
      Check(S.ConstraintIndex(DimId) < 0, 'Old length dimension removed');
      for I := 0 to S.ConstraintCount - 1 do
        Check(not ((S.Constraint(I).Kind = ckCoincident) and
          (S.Constraint(I).EntityB = CAD_SKETCH_ORIGIN)), 'Relation to removed start removed');
      Check(S.ConstraintIndex(C1) >= 0, 'Fixed surviving endpoint retained'); ValidRefs;
      Check(T.LastSolve.Status <> ssConflict, 'Trim does not restore old length via solver');

      Fresh; Id := S.AddLine(0, 0, 10, 0); S.AddLine(3, -5, 3, 5); S.AddLine(7, -5, 7, 5);
      C1 := S.AddFixed(Id, 1); C2 := S.AddFixed(Id, 2);
      S.AddConstraint(ckHorizontal, Id, 0, 0, 0); Session;
      Check(T.Click(V2(5, 0)), 'Constrained middle split'); RightId := S.Entity(3).Id;
      Check(S.Constraint(S.ConstraintIndex(C1)).EntityA = Id, 'Start constraint keeps original ID');
      Check(S.Constraint(S.ConstraintIndex(C2)).EntityA = RightId, 'End constraint remapped to new ID');
      Bounds(Id, 0, 0, 3, 0); Bounds(RightId, 7, 0, 10, 0); ValidRefs;
      Check(T.LastSolve.Status <> ssConflict, 'Split direction and fixed endpoints are consistent');

      Fresh; Id := S.AddLine(0, 0, 10, 0); S.AddFixed(Id, 0); S.AddLine(5, -2, 5, 2); Session;
      Check(T.Click(V2(8, 0)), 'Trim a fully fixed line'); Bounds(Id, 0, 0, 5, 0);
      Check(T.LastSolve.Status <> ssConflict, 'Fixed relation recaptured on surviving geometry'); ValidRefs;

      Fresh; Id := S.AddLine(0, 0, 10, 0); S.AddFixed(Id, 1);
      S.AddConstraint(ckHorizontal, Id, 0, 0, 0);
      C1 := S.AddLine(5, -2, 5, 2); S.AddConstraint(ckVertical, C1, 0, 0, 0);
      S.AddDimension(ckHorizontalDistance, C1, 1, CAD_SKETCH_ORIGIN, 1, 5); Session;
      Check(T.Click(V2(8, 0)), 'Trim binds the new endpoint to cutting line');
      Check(S.SetDimension('D1', 6), 'Move cutting line through its driving dimension'); T.Solve;
      Near(Entity(Id).P2.X, 6, 'New endpoint follows its cutting line parametrically');
      Near(Entity(Id).P1.X, 0, 'Old anchored endpoint remains fixed'); ValidRefs;

      Fresh; Id := S.AddLine(0, 0, 10, 0); Session;
      Check(T.Click(V2(5, 0)) and (S.EntityCount = 0), 'No intersections removes entire line');
      Check(not T.Click(V2(5, 0)), 'Empty sketch is harmless');
      Fresh; S.AddCircle(0, 0, 2); Session; Before := D.ToJSON;
      Check(not T.Click(V2(2, 0)) and (D.ToJSON = Before), 'Trim target limited to straight lines');

      Fresh; Id := S.AddLine(-5, 0, 5, 0); S.AddCircle(0, 0, 2); Session;
      Check(T.Click(V2(0, 0)), 'Circle bounds a line cut');
      Bounds(Id, -5, 0, -2, 0); Bounds(S.Entity(2).Id, 2, 0, 5, 0);
      Fresh; Id := S.AddLine(-5, 1, 5, 1); S.AddArc(0, 0, 2, 0, -2, 0); Session;
      Check(T.Click(V2(0, 1)), 'Upper semicircle bounds cut');
      Near(Entity(Id).P2.X, -Sqrt(3), 'Exact arc-line intersection');
      Fresh; Id := S.AddLine(-5, -1, 5, -1); S.AddArc(0, 0, 2, 0, -2, 0); Session;
      Check(T.Click(V2(0, -1)) and (S.EntityIndex(Id) < 0), 'Unused half of arc is not an intersection');
      Fresh; Id := S.AddLine(-5, 0, 5, 0); S.AddCircle(0, 1, 1); Session;
      Check(T.Click(V2(-2, 0)), 'Tangent intersection is deduplicated'); Bounds(Id, 0, 0, 5, 0);

      Fresh; Id := S.AddLine(10, 10, 0, 0); S.AddLine(7, 0, 7, 10); S.AddLine(3, 0, 3, 10); Session;
      Check(T.Click(V2(5, 5)), 'Reversed diagonal trims in local coordinates');
      Bounds(Id, 10, 10, 7, 7); Bounds(S.Entity(3).Id, 3, 3, 0, 0);
      Fresh; Id := S.AddLine(0, 0, 10, 0); S.AddLine(3, 2, 3, 5); S.AddLine(0, 2, 10, 2); Session;
      Check(T.Click(V2(5, 0)) and (S.EntityIndex(Id) < 0), 'Infinite extensions and parallel lines do not bound a trim');
      Fresh; Id := S.AddLine(0, 0, 10, 0); S.AddLine(3, 0, 7, 0); Session;
      Check(T.Click(V2(1, 0)), 'Collinear overlap endpoints bound a trim'); Bounds(Id, 3, 0, 10, 0);
      Fresh; Id := S.AddLine(0, 0, 10, 0); S.AddLine(3, -5, 3, 5); S.AddLine(3 + 1E-10, -5, 3 + 1E-10, 5);
      S.AddLine(7, -5, 7, 5); Session;
      Before := D.ToJSON; Check(not T.Click(V2(3, 0)), 'Exact intersection is ambiguous and harmless');
      Check(D.ToJSON = Before, 'Ambiguous click is atomic');
      Check(T.Click(V2(5, 0)), 'Near duplicate intersections do not make tiny slivers');
      Check(S.EntityCount = 5, 'Only two nondegenerate survivors');

      Fresh; Id := S.AddCenterline(0, 0, 10, 0); S.AddLine(3, -2, 3, 2); S.AddLine(7, -2, 7, 2); Session;
      Check(T.Click(V2(5, 0)), 'Construction line can be trimmed in active sketch');
      E := S.Entity(3); Check(Entity(Id).Construction and E.Construction and E.Centerline, 'Both survivors keep construction/center flags');
      Fresh; Id := S.AddLine(0, 0, 0, 0); Session; Before := D.ToJSON;
      Check(not T.Click(V2(0, 0)) and (D.ToJSON = Before), 'Degenerate line is ignored');
      Check(not S.TrimLine(Id, 0, NaN), 'Invalid trim parameters rejected');

      Fresh; Id := S.AddLine(-5, 0, 15, 0);
      S.AddLine(10, 0, 10, 10); S.AddLine(10, 10, 0, 10); S.AddLine(0, 10, 0, 0); Session;
      Check(T.Click(V2(-2, 0)) and T.Click(V2(12, 0)), 'Repeated trims remove protruding ends');
      P := CadSketchProfiles(S); Check(P.Ok and (Length(P.Regions) = 1), 'Trim produces closed usable profile');
      D.AddExtrude(S.Id, 2); RB := TCadRebuilder.Create(D);
      try
        Check(RB.Rebuild = 0, 'Trimmed profile rebuilds'); Near(RB.TotalVolume, 200, 'Extruded trimmed area');
        for I := 0 to RB.BodyCount - 1 do Check(RB.Body(I).Mesh.CheckClosed(Error), 'Extruded mesh is closed');
      finally RB.Free; end;
      WriteLn('PASS: ', Checks, ' trim geometry, constraints, associative endpoints, persistence and extrusion checks');
    finally T.Free; Loaded.Free; D.Free; end;
  except on E: Exception do begin WriteLn('FAIL: ', E.Message); Halt(1); end; end;
end.
