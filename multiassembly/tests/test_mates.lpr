program test_mates;

{ Uniao por referencia: motor NEMA 17 inserido no furo do suporte em L,
  parafuso no furo da cantoneira, persistencia e reaplicacao pelo solver. }

{$mode objfpc}{$H+}

uses
  SysUtils, Math, multiassembly_types, multiassembly_geometry, multiassembly_library,
  multiassembly_project, multiassembly_solver, multiassembly_mates;

var
  Fails: Integer = 0;

procedure Check(Cond: Boolean; const Msg: string);
begin
  if not Cond then
  begin
    Writeln('FALHOU: ', Msg);
    Inc(Fails);
  end;
end;

function Near(const A, B: TAssemblyVec3; Tol: Double = 0.05): Boolean;
begin
  Result := Vec3Dist(A, B) <= Tol;
end;

{ procura a face de uma primitiva que satisfaz o filtro e devolve sua referencia local }
function FindFeature(const C: TAssemblyComponent; Kind: TAssemblyPrimitiveKind; Part: Integer;
  RMin, RMax: Double; const Normal: TAssemblyVec3): TMateFeature;
var
  M: TAssemblyMesh;
  G: TAssemblyGeometry;
  I: Integer;
  P: TAssemblyPrimitive;
begin
  Result := Default(TMateFeature);
  G := ComponentGeometry(C);
  BuildMesh(G, M);
  for I := 0 to M.Count - 1 do
  begin
    if (M.Faces[I].Prim < 0) or (M.Faces[I].Part <> Part) then Continue;
    P := G[M.Faces[I].Prim];
    if (P.Kind <> Kind) or (P.R < RMin) or (P.R > RMax) then Continue;
    if (Vec3Len(Normal) > 0) and (Vec3Dot(M.Faces[I].N, Normal) < 0.99) then Continue;
    Result := MeshToLocalFeature(FaceFeature(G, M, I), M, C.Size);
    Exit;
  end;
end;

var
  Lib, P: string;
  Motor, Bracket, Screw, Corner: TAssemblyComponent;
  FMotor, FHole, FScrew, FCornerHole, W1, W2: TMateFeature;
  NP, NR: TAssemblyVec3;
  Proj, Proj2: TAssemblyProject;
  Solver: TKinematicSolver;
  Rel: TMechanicalRelation;
  Kind: TMechanicalRelationKind;
  M: TMat3;
  E: TAssemblyVec3;
  JSON: string;
begin
  Lib := ExpandFileName(ExtractFilePath(ParamStr(0)) + '../../models/components/mec');
  if ParamCount >= 1 then Lib := ParamStr(1);
  TAssemblyLibrary.SetLibraryFolder(Lib);

  { Euler <-> matriz }
  E := Vec3(12, -33, 71);
  M := MatFromEuler(E);
  Check(Near(EulerFromMat(M), E, 1e-6), 'EulerFromMat inverte MatFromEuler');

  Motor := TAssemblyLibrary.LoadComponentFromFile(Lib + '/motores/motor_passo_nema17_42mm.json', 'MOTOR', 100, 0, 0);
  Bracket := TAssemblyLibrary.LoadComponentFromFile(Lib + '/placas_suportes/suporte_motor_nema17.json', 'SUP', 0, 0, 0);
  Check(Length(Motor.Geometry) > 5, 'motor com geometria');
  Check(Length(Bracket.Geometry) > 5, 'suporte com geometria');

  { tampa superior do piloto do motor (cilindro r 11) e furo central do suporte (disco r 11,5, lado -Y) }
  FMotor := FindFeature(Motor, agpCylinder, FP_TOP, 10.9, 11.1, Vec3(0, 0, 1));
  FHole := FindFeature(Bracket, agpDisk, FP_DISK, 11.4, 11.6, Vec3(0, -1, 0));
  Check(FMotor.Valid and FMotor.HasPlane and FMotor.HasAxis, 'piloto do motor: plano + eixo');
  Check(FHole.Valid and FHole.HasPlane and FHole.HasAxis, 'furo do suporte: plano + eixo');

  Check(SuggestMateKind(FMotor, FHole, Kind) and (Kind = mrInsert), 'par piloto/furo sugere Inserir');

  W2 := FeatureToWorld(Bracket, Bracket.Position, Bracket.Rotation, FHole);
  Check(SolveMatePose(Motor, Motor.Position, Motor.Rotation, FMotor, W2, mrInsert, False, 0, 0, NP, NR),
    'SolveMatePose Inserir');
  W1 := FeatureToWorld(Motor, NP, NR, FMotor);
  Check(Near(W1.AxisPoint, W2.AxisPoint), Format('centro do piloto no centro do furo (%.2f mm)',
    [Vec3Dist(W1.AxisPoint, W2.AxisPoint)]));
  Check(Vec3Dot(W1.PlaneNormal, W2.PlaneNormal) < -0.999, 'face do piloto contra a face do suporte');

  { parafuso M5 abaulado (cabeca) com a face superior da cantoneira: coincidente }
  Screw := TAssemblyLibrary.LoadComponentFromFile(Lib + '/fixadores/parafuso_m5x10_abaulado.json', 'PAR', 50, 50, 50);
  Corner := TAssemblyLibrary.LoadComponentFromFile(Lib + '/fixadores/cantoneira_esquadro_2020.json', 'CANT', 0, 0, 0);
  FScrew := FindFeature(Screw, agpCylinder, FP_BOTTOM, 4.7, 4.8, Vec3(0, 0, -1)); // apoio da cabeca
  FCornerHole := FindFeature(Corner, agpDisk, FP_DISK, 2.7, 2.8, Vec3(0, 0, 1));   // furo da aba horizontal
  Check(FScrew.Valid and FCornerHole.Valid, 'referencias do parafuso e da cantoneira');

  { projeto: suporte fixo, motor inserido, parafuso inserido na cantoneira }
  Proj := TAssemblyProject.Create;
  try
    Bracket.Fixed := True;
    Proj.AddComponent(Bracket);
    Proj.AddComponent(Motor);
    Corner.Position := Vec3(200, 0, 0);
    Proj.AddComponent(Corner);
    Proj.AddComponent(Screw);

    Rel := Default(TMechanicalRelation);
    Rel.A := 'MOTOR'; Rel.B := 'SUP'; Rel.Kind := mrInsert; Rel.HasRefs := True;
    Rel.RefA := FMotor; Rel.RefB := FHole; Rel.Ratio := 1;
    Rel.Axis := DominantAxis(W2.AxisDir);
    Proj.Relate(Rel);

    Rel := Default(TMechanicalRelation);
    Rel.A := 'PAR'; Rel.B := 'CANT'; Rel.Kind := mrInsert; Rel.HasRefs := True;
    Rel.RefA := FScrew; Rel.RefB := FCornerHole; Rel.Ratio := 1;
    Rel.Axis := Vec3(0, 0, 1);
    Proj.Relate(Rel);

    { cantoneira presa ao suporte por coincidencia de faces planas }
    Rel := Default(TMechanicalRelation);
    Rel.A := 'CANT'; Rel.B := 'SUP'; Rel.Kind := mrCoincident; Rel.HasRefs := True;
    Rel.RefA := FindFeature(Corner, agpBox, FP_BOX, 0, 1e9, Vec3(0, 0, -1));
    Rel.RefB := FindFeature(Bracket, agpBox, FP_BOX, 0, 1e9, Vec3(0, 0, 1));
    Rel.Axis := Vec3(0, 0, 1);
    Check(Rel.RefA.Valid and Rel.RefB.Valid, 'faces planas da cantoneira e do suporte');
    Proj.Relate(Rel);

    Solver := TKinematicSolver.Create(Proj);
    try
      Solver.Solve;
      Motor := Proj.Component(Proj.FindComponent('MOTOR'));
      W1 := FeatureToWorld(Motor, Motor.Position, Motor.Rotation, FMotor);
      W2 := FeatureToWorld(Bracket, Bracket.Position, Bracket.Rotation, FHole);
      Check(Near(W1.AxisPoint, W2.AxisPoint), 'solver: motor no furo');

      Corner := Proj.Component(Proj.FindComponent('CANT'));
      Screw := Proj.Component(Proj.FindComponent('PAR'));
      Check(Abs(Corner.Position.Z - 3.0) < 0.05, Format('solver: cantoneira apoiada na base (z=%.2f)', [Corner.Position.Z]));
      W1 := FeatureToWorld(Screw, Screw.Position, Screw.Rotation, FScrew);
      W2 := FeatureToWorld(Corner, Corner.Position, Corner.Rotation, FCornerHole);
      Check(Near(W1.AxisPoint, W2.AxisPoint), Format('solver: cabeca do parafuso no furo da cantoneira (%.2f mm)',
        [Vec3Dist(W1.AxisPoint, W2.AxisPoint)]));

      { persistencia: salvar, recarregar e resolver de novo mantem a montagem }
      JSON := Proj.SaveToJSON;
      Proj2 := TAssemblyProject.Create;
      try
        Proj2.LoadFromJSON(JSON);
        Check(Proj2.RelationCount = 3, 'relacoes recarregadas');
        Check(Proj2.Relation(0).HasRefs and Proj2.Relation(0).RefA.HasAxis, 'referencias recarregadas');
        Check(Length(Proj2.Component(1).Geometry) > 5, 'geometria salva no projeto');
        Solver.Free;
        Solver := TKinematicSolver.Create(Proj2);
        Solver.Solve;
        Check(Near(Proj2.Component(Proj2.FindComponent('PAR')).Position, Screw.Position),
          'reabrir e resolver mantem a posicao do parafuso');
      finally
        Proj2.Free;
      end;
    finally
      Solver.Free;
    end;
  finally
    Proj.Free;
  end;

  if Fails = 0 then
    Writeln('MultiAssembly unioes: OK (Inserir, Coincidente, solver, persistencia)')
  else
  begin
    Writeln(Fails, ' falha(s)');
    Halt(1);
  end;
end.
