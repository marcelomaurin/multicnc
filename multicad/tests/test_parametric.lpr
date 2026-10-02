program test_parametric;
{$mode objfpc}{$H+}
{ MultiCAD parametrico: solver de restricoes, graus de liberdade, extrusao
  com furo, malha fechada, STL/3MF e fluxo CAD -> MultiSlicer. }
uses Classes, SysUtils, Math, multicad_types, multicad_sketch, multicad_extrude,
  multicad_constraint_solver, multicad_mesh, multisuite_geometry,
  multislicer_types, multislicer_mesh, multislicer_stl, multislicer_3mf, multislicer_pipeline;

procedure Check(Value: Boolean; const Msg: string);
begin
  if not Value then begin WriteLn('FALHOU: ', Msg); Halt(1); end;
end;

function LineLen(S: TCadSketch; I: Integer): Double;
var E: TSketchEntity;
begin
  E := S.Entity(I);
  Result := Hypot(E.P2.X - E.P1.X, E.P2.Y - E.P1.Y);
end;

var
  S: TCadSketch;
  Solver: TSketchSolver;
  R: TSolveResult;
  E: TSketchEntity;
  Ex: TCadExtrude;
  Mesh: TCadMesh;
  Pr: TCadProfiles;
  Tris: TPolygons2D;
  CircleArea, Area, ExpectedVol: Double;
  I, DistIdx: Integer;
  FN, FN3: string;
  SM: TMesh;
  Slicer: TModernSlicer;
  G: TStringList;
  Rep: TSliceReport;
begin
  { Retangulo desenhado "a mao" (torto) e restrito }
  S := TCadSketch.Create('Sketch1');
  try
    S.AddLine(0.3, -0.2, 41.0, 1.1);   // 0: base
    S.AddLine(41.0, 1.1, 39.2, 29.4);  // 1: direita
    S.AddLine(39.2, 29.4, -0.8, 31.0); // 2: topo
    S.AddLine(-0.8, 31.0, 0.3, -0.2);  // 3: esquerda
    S.AddConstraint(ckFixed, 0, -1, 0);
    S.AddConstraint(ckHorizontal, 0, -1, 0);
    S.AddConstraint(ckHorizontal, 2, -1, 0);
    S.AddConstraint(ckVertical, 1, -1, 0);
    S.AddConstraint(ckVertical, 3, -1, 0);
    for I := 0 to 3 do S.AddConstraint(ckCoincident, I, (I + 1) mod 4, 0);
    S.AddConstraint(ckDistance, 0, -1, 40);
    DistIdx := S.AddConstraint(ckDistance, 1, -1, 30);
    Solver := TSketchSolver.Create(S);
    try
      R := Solver.Solve;
    finally
      Solver.Free;
    end;
    Check(R.Converged, Format('solver convergiu (residuo %.2e)', [R.Residual]));
    Check(Abs(LineLen(S, 0) - 40) < 1e-6, 'base = 40');
    Check(Abs(LineLen(S, 1) - 30) < 1e-6, 'lateral = 30');
    Check(Abs(S.Entity(0).P1.X - 0.3) < 1e-9, 'ponto fixo mantido');
    Check(Abs(S.Entity(1).P2.Y - S.Entity(2).P1.Y) < 1e-9, 'coincidencia');
    // 16 parametros e 16 equacoes (fixo 2 + H/V 4 + coincidencias 8 + cotas 2);
    // com H/V nos quatro lados, uma das coincidencias fica redundante, entao o
    // solver pode reportar "redundante" com DOF = 0
    Check(R.DOF = 0, Format('totalmente restrito (DOF=%d, posto %d de %d eq.)', [R.DOF, R.Rank, R.Equations]));
    Check(R.Status in [ssFullyConstrained, ssRedundant], 'status: ' + SketchStatusText(R.Status));
    // sem a cota da lateral: 1 grau de liberdade (altura livre)
    S.DeleteConstraint(DistIdx);
    Solver := TSketchSolver.Create(S);
    try R := Solver.Solve; finally Solver.Free; end;
    Check(R.DOF = 1, Format('subrestrito com DOF=1 (%d)', [R.DOF]));
    // cota conflitante: topo com 50 mm e base 40 mm horizontais e paralelas
    S.AddConstraint(ckDistance, 1, -1, 30);
    S.AddConstraint(ckDistance, 2, -1, 50);
    Solver := TSketchSolver.Create(S);
    try R := Solver.Solve; finally Solver.Free; end;
    Check(R.Status = ssConflicting, 'conflito detectado: ' + SketchStatusText(R.Status));
  finally
    S.Free;
  end;

  { Paralelismo, perpendicularidade, angulo, raio e igualdade }
  S := TCadSketch.Create('Sketch2');
  try
    S.AddLine(0, 0, 10, 1);       // 0
    S.AddLine(0, 5, 9, 7);        // 1
    S.AddLine(20, 0, 22, 10);     // 2
    S.AddCircle(50, 50, 4);       // 3
    S.AddCircle(70, 50, 7);       // 4
    S.AddConstraint(ckFixed, 0, -1, 0);
    S.AddConstraint(ckHorizontal, 0, -1, 0);
    S.AddConstraint(ckParallel, 0, 1, 0);
    S.AddConstraint(ckPerpendicular, 0, 2, 0);
    S.AddConstraint(ckEqual, 0, 1, 0);
    S.AddConstraint(ckRadius, 3, -1, 5);
    S.AddConstraint(ckEqual, 3, 4, 0);
    Solver := TSketchSolver.Create(S);
    try R := Solver.Solve; finally Solver.Free; end;
    Check(R.Converged, 'sketch 2 convergiu');
    E := S.Entity(1);
    Check(Abs(E.P2.Y - E.P1.Y) < 1e-6, 'paralela a horizontal');
    Check(Abs(LineLen(S, 1) - LineLen(S, 0)) < 1e-6, 'comprimentos iguais');
    E := S.Entity(2);
    Check(Abs(E.P2.X - E.P1.X) < 1e-6, 'perpendicular');
    Check((Abs(S.Entity(3).Radius - 5) < 1e-6) and (Abs(S.Entity(4).Radius - 5) < 1e-6), 'raio e igualdade');
    Check(R.DOF > 0, 'ainda ha graus de liberdade (posicoes livres)');
    S.AddConstraint(ckAngle, 0, 1, 30);
    S.AddConstraint(ckDistance, 0, -1, 10);
    Solver := TSketchSolver.Create(S);
    try R := Solver.Solve; finally Solver.Free; end;
    // paralela + angulo 30 graus: conflito
    Check(R.Status = ssConflicting, 'paralela com angulo de 30 graus conflita');
  finally
    S.Free;
  end;

  { Extrusao com furo -> malha fechada, volume correto }
  S := TCadSketch.Create('Placa');
  Ex := TCadExtrude.Create('Extrude1', S.ID, 5, False);
  Mesh := TCadMesh.Create;
  try
    S.AddRectangle(0, 0, 40, 30);
    S.AddCircle(20, 15, 6);
    Pr := SketchProfiles(S, 0.01);
    Check((Length(Pr.Outer) = 1) and (Length(Pr.Holes) = 1), 'perfil com um furo');
    CircleArea := Abs(PolygonArea(Pr.Holes[0]));
    // perda de area da discretizacao ~ 2/3 * flecha * perimetro = 0.25 mm2
    Check(Abs(CircleArea - Pi * 36) < 0.3, Format('circulo discretizado (%.4f)', [CircleArea]));
    Tris := TriangulatePolygon(Pr.Outer[0], Pr.Holes);
    Area := 0;
    for I := 0 to High(Tris) do Area := Area + PolygonArea(Tris[I]);
    Check(Abs(Area - (1200 - CircleArea)) < 1e-6, Format('triangulacao com furo (area %.4f)', [Area]));
    ExtrudeSketch(S, Ex, Mesh);
    ExpectedVol := (1200 - CircleArea) * 5;
    Check(Abs(Mesh.Volume - ExpectedVol) < 1e-4, Format('volume %.4f vs %.4f', [Mesh.Volume, ExpectedVol]));
    Check(Mesh.IsClosed, 'malha fechada (manifold)');
    FN := GetTempFileName(GetTempDir, 'cad') + '.stl';
    Mesh.SaveSTL(FN);
    FN3 := ChangeFileExt(FN, '.3mf');
    Mesh.Save3MF(FN3, 'Placa com furo');
    Check(FileExists(FN3), '3MF gravado');

    { CAD -> MultiSlicer }
    SM := TMesh.Create;
    Slicer := TModernSlicer.Create;
    G := TStringList.Create;
    try
      Check(TSTLImporter.Load(FN, SM) and (SM.Count = Mesh.Count), 'STL do CAD lido pelo slicer');
      SM.Clear;
      Check(T3MFImporter.Load(FN3, SM) and (SM.Count = Mesh.Count), '3MF do CAD lido pelo slicer');
      Check(Abs(SM.MaxZ - 5) < 1e-6, 'altura no 3MF');
      // desloca para a mesa e fatia
      Rep := Slicer.Slice(SM, DefaultSliceSettings, G);
      Check(Rep.Layers = 25, Format('placa de 5 mm em 25 camadas (%d)', [Rep.Layers]));
      Check(Length(Slicer.Layers[10].Loops) = 2, 'furo aparece no fatiamento');
    finally
      G.Free;
      Slicer.Free;
      SM.Free;
    end;
    DeleteFile(FN);
    DeleteFile(FN3);
  finally
    Mesh.Free;
    Ex.Free;
    S.Free;
  end;
  WriteLn('MultiCAD parametrico: OK (restricoes LM, DOF, conflitos, extrusao com furo, STL/3MF -> slicer)');
end.
