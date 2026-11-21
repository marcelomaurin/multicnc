program test_project_analysis;

{ Projeto .mphys e analise pelo projeto: biblioteca de materiais, ida e
  volta do JSON, validacao, viga em balanco resolvida pelo projeto (com
  rotulo de fidelidade), termica e termomecanica. }

{$mode objfpc}{$H+}

uses
  Classes, SysUtils, Math, multiphysics_types, multiphysics_materials,
  multiphysics_vector, multiphysics_geometry, multiphysics_project,
  multiphysics_scenario, multiphysics_analysis, multiphysics_units, multiphysics_check;

var
  Ok: Boolean;

procedure TestMaterials;
var
  I: Integer;
  M: TMaterial;
  Ok: Boolean;
begin
  Section('Biblioteca de materiais');
  Check(MaterialCount >= 25, Format('%d materiais', [MaterialCount]));
  Ok := True;
  for I := 0 to MaterialCount - 1 do
  begin
    M := MaterialByIndex(I);
    if not ((M.YoungModulus > 0) and (M.Poisson > 0) and (M.Poisson < 0.5) and (M.Density > 0) and
      (M.ThermalConductivity > 0) and (M.SpecificHeat > 0) and (FindMaterial(M.Name) = I)) then
    begin
      Ok := False;
      Writeln('        material com problema: ', M.Name);
    end;
  end;
  Check(Ok, 'todos com E, Poisson, densidade, k e c validos e achados pelo nome');
  Check(FindMaterial('nao existe') = -1, 'nome desconhecido devolve -1');
  CheckNear(MmToM(25), 0.025, 1e-12, 'unidades: mm para m');
  Check(FormatLength(0.0023) <> '', 'formatacao de comprimento');
end;

function Beam(P: TPhysicsProject): TPhysicsPart;
begin
  Result := TPhysicsPart.Create;
  Result.ID := 'VIGA'; Result.Name := 'Viga de teste';
  Result.Material := MaterialByIndex(FindMaterial('Aco carbono'));
  Result.Material.YoungModulus := 200e9; Result.Material.Poisson := 0.3;
  Result.AddPrimitive(BoxPrim('b', V3(0, 0, 0), V3(0.2, 0.01, 0.02)));
  P.AddPart(Result);
end;

procedure TestJSON;
var
  P, Q: TPhysicsProject;
  B: TBoundaryCondition;
  Part: TPhysicsPart;
  C: TContact;
  FN: string;
  Log: TStringList;
begin
  Section('Projeto .mphys');
  P := TPhysicsProject.Create; Q := TPhysicsProject.Create; Log := TStringList.Create;
  try
    P.Name := 'Teste';
    Part := Beam(P);
    Part.Position := V3(0.1, 0.2, 0.3); Part.RotZ := 30; Part.MeshSize := 0.002;
    Part := TPhysicsPart.Create;
    Part.ID := 'EIXO'; Part.Material := MaterialByIndex(FindMaterial('Aluminio'));
    Part.AddPrimitive(CylPrim('c', 'x', V3(0, 0, 0), 0.005, 0.05, 0.002, 0.004));
    Part.Primitives[0].Arc0 := 10; Part.Primitives[0].Arc1 := 200;
    Part.AddPrimitive(PrismPrim('p', 'y', V3(0, 0, 0), 0.01, [V2(0, 0), V2(0.01, 0), V2(0, 0.01)]));
    P.AddPart(Part);
    B := NewBC('Base', 'VIGA', 'xmin', bkFixed);
    B.DofMask := 5;
    P.AddBC(B);
    B := NewBC('Carga', 'VIGA', 'VIGA/b/xmax', bkForce);
    B.Z := -100;
    P.AddBC(B);
    B := NewBC('Ar', 'EIXO', 'lateral', bkConvection);
    B.Value := 10; B.Value2 := 25;
    P.AddBC(B);
    C.Name := 'Colado'; C.PartA := 'VIGA'; C.PartB := 'EIXO'; C.FrictionCoefficient := 0.2;
    C.StaticFrictionCoefficient := 0.3; C.RollingFrictionCoefficient := 0; C.ThermalConductance := 500;
    P.AddContact(C);
    P.Settings.Physics := [pkStructural, pkThermal, pkModal];
    P.Settings.Modes := 4;
    FN := GetTempDir + 'test_project_analysis' + MPHYS_EXT;
    P.SaveToFile(FN);
    Q.LoadFromFile(FN);
    Check(Q.ToJSON = P.ToJSON, 'salvar e abrir devolve o mesmo projeto (JSON identico)');
    Check((Q.PartCount = 2) and (Length(Q.Part(1).Primitives) = 2) and (Q.Part(1).Primitives[0].Kind = gpCyl), 'pecas e primitivas recuperadas');
    Check(SameValue(Q.Part(1).Primitives[0].Arc1, 200) and SameValue(Q.Part(1).Primitives[0].R2, 0.004), 'setor e cone recuperados');
    Check((Q.BCCount = 3) and (Q.BC(0).DofMask = 5) and SameValue(Q.BC(1).Z, -100) and SameValue(Q.BC(2).Value2, 25), 'condicoes recuperadas');
    Check((Q.ContactCount = 1) and SameValue(Q.Contact(0).ThermalConductance, 500), 'contato recuperado');
    Check(SameValue(Q.Part(0).RotZ, 30) and SameValue(Q.Part(0).Position.Y, 0.2), 'posicao e rotacao recuperadas');
    Check(pkModal in Q.Settings.Physics, 'configuracoes recuperadas');
    DeleteFile(FN);
    try
      Q.FromJSON('{"format": 99}');
      Check(False, 'formato desconhecido recusado');
    except
      on E: Exception do Check(Pos('99', E.Message) > 0, 'formato desconhecido recusado: ' + E.Message);
    end;
    { validacao }
    Q.Clear;
    Check(not Q.Validate(Log) and (Pos('Nenhuma peca', Log.Text) > 0), 'valida: projeto vazio');
    Log.Clear;
    Beam(Q);
    Q.Settings.Physics := [pkStructural];
    Check(not Q.Validate(Log) and (Pos('sem fixacao', Log.Text) > 0), 'valida: estrutural sem fixacao');
    Log.Clear;
    Q.AddBC(NewBC('X', 'OUTRA', 'xmin', bkFixed));
    Check(not Q.Validate(Log) and (Pos('inexistente', Log.Text) > 0), 'valida: condicao em peca inexistente');
    Log.Clear;
    Q.DeleteBC(0);
    Q.AddBC(NewBC('Base', 'VIGA', 'xmin', bkFixed));
    Q.Settings.Physics := [pkThermal];
    Check(not Q.Validate(Log) and (Pos('termica', Log.Text) > 0), 'valida: termica sem temperatura');
    Log.Clear;
    Q.Part(0).Material.YoungModulus := 0;
    Q.Settings.Physics := [pkStructural];
    Check(not Q.Validate(Log) and (Pos('invalido', Log.Text) > 0), 'valida: material invalido');
  finally
    Log.Free; Q.Free; P.Free;
  end;
end;

procedure TestAnalysis;
var
  P: TPhysicsProject;
  R: TAnalysisRun;
  B: TBoundaryCondition;
  I, G, Ref: Double;
begin
  Section('Analise pelo projeto');
  P := TPhysicsProject.Create;
  R := TAnalysisRun.Create(P);
  try
    Beam(P);
    P.AddBC(NewBC('Engaste', 'VIGA', 'xmin', bkFixed));
    B := NewBC('Carga', 'VIGA', 'VIGA/b/xmax', bkForce);
    B.Z := -100;
    P.AddBC(B);
    P.Settings.MeshSize := 0.005;
    Ok := R.Run(akStatic); Check(Ok, 'estatica resolve: ' + R.Message);
    I := 0.01 * Power(0.02, 3) / 12;
    G := 200e9 / 2.6;
    Ref := 100 * Power(0.2, 3) / (3 * 200e9 * I) + 100 * 0.2 / (5 / 6 * G * 2e-4);
    CheckNear(R.StaticRes.MaxDisp, Ref, 0.04, 'flecha maxima pelo projeto');
    Check(R.Convergence >= 0, Format('estudo de convergencia feito (%.2f%%)', [R.Convergence * 100]));
    Check(R.Fidelity = flEngineering, 'fidelidade ENGENHARIA: ' + FidelityName(R.Fidelity) + ' ' + R.FidelityReason);
    Check(R.Summary.Fidelity = 'ENGENHARIA', 'resumo carrega a fidelidade');
    { modal }
    P.Settings.Modes := 2;
    Ok := R.Run(akModal); Check(Ok, 'modal resolve: ' + R.Message);
    CheckNear(R.ModalRes.Freq[0], 203.8, 0.03, 'f1 pelo projeto');
    { sem convergencia pedida: ESTIMATIVA }
    P.Settings.CheckConvergence := False;
    R.Run(akStatic);
    Check(R.Fidelity = flEstimate, 'sem estudo de convergencia: ESTIMATIVA (' + R.FidelityReason + ')');
    P.Settings.CheckConvergence := True;
    { termica e termomecanica: barra 0..100 C presa nas pontas so em x }
    P.Clear;
    Beam(P);
    P.Part(0).Primitives[0].Size := V3(0.1, 0.01, 0.01);
    P.Settings.Physics := [pkStructural, pkThermal];
    P.Environment.AmbientTemperature := 20;
    B := NewBC('Quente', 'VIGA', 'xmin', bkTemperature); B.Value := 70; P.AddBC(B);
    B := NewBC('Quente2', 'VIGA', 'xmax', bkTemperature); B.Value := 70; P.AddBC(B);
    B := NewBC('Rx0', 'VIGA', 'xmin', bkFixed); B.DofMask := 1; P.AddBC(B);
    B := NewBC('Rx1', 'VIGA', 'xmax', bkFixed); B.DofMask := 1; P.AddBC(B);
    B := NewBC('Ry', 'VIGA', 'ymin', bkFixed); B.DofMask := 2; P.AddBC(B);
    B := NewBC('Rz', 'VIGA', 'zmin', bkFixed); B.DofMask := 4; P.AddBC(B);
    Ok := R.Run(akThermal); Check(Ok, 'termica resolve: ' + R.Message);
    CheckNear(R.ThermalRes.MaxT, 70, 1e-6, 'temperatura uniforme 70 C');
    Ok := R.Run(akThermoMechanical); Check(Ok, 'termomecanica resolve: ' + R.Message);
    CheckNear(R.StaticRes.MaxVonMises, 200e9 * P.Part(0).Material.ThermalExpansion * 50, 0.02, 'tensao termica E alfa dT');
  finally
    R.Free; P.Free;
  end;
end;

begin
  TestMaterials;
  TestJSON;
  TestAnalysis;
  Finish('projeto e analise');
end.
