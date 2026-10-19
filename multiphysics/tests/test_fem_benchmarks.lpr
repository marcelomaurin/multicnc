program test_fem_benchmarks;

{ Benchmarks analiticos do FEM proprio (docs/TAREFA.md, secao 6):
  B1 barra em tracao, B2 viga em balanco, B4 parede termica, B5 aleta com
  conveccao, B6 tensao termica, B7 1a frequencia da viga em balanco,
  B8 viga livre-livre (6 modos rigidos + 1a flexao). }

{$mode objfpc}{$H+}

uses
  SysUtils, Math, DateUtils, multiphysics_vector, multiphysics_geometry,
  multiphysics_mesh, multiphysics_sparse, multiphysics_fem, multiphysics_check;

var
  Ok: Boolean;

const
  E_STEEL = 200e9;
  NU_STEEL = 0.3;
  RHO_STEEL = 7850;

function Steel: TFEMMaterial;
begin
  Result := FEMMaterial('Aco', E_STEEL, NU_STEEL, RHO_STEEL, 50, 12e-6, 250e6);
end;

function BoxMesh(Lx, Ly, Lz, H: Double; Quadratic: Boolean): TFEMMesh;
begin
  Result := TFEMMesh.Create;
  Result.AddPart('P');
  Result.AddPrimitive(0, BoxPrim('b', V3(0, 0, 0), V3(Lx, Ly, Lz)), IdentityTransform, H);
  Result.Finalize;
  if Quadratic then Result.ConvertToTet10;
end;

function Tag(M: TFEMMesh; const Face: string): Integer;
begin
  Result := M.FindTag('P/b/' + Face);
end;

function Roller(M: TFEMMesh; const Face: string; Dof: Integer): TFEMLoad;
begin
  Result := FixLoad(Tag(M, Face));
  Result.Mask[0] := Dof = 0; Result.Mask[1] := Dof = 1; Result.Mask[2] := Dof = 2;
end;

function NearestNode(M: TFEMMesh; const P: TVector3): Integer;
var
  I: Integer;
  D, Best: Double;
begin
  Result := 0; Best := MaxDouble;
  for I := 0 to M.NodeCount - 1 do
  begin
    D := VLength(VSub(M.Nodes[I], P));
    if D < Best then begin Best := D; Result := I; end;
  end;
end;

{ media de uma componente do deslocamento nos nos de uma face }
function MeanU(M: TFEMMesh; const U: TDoubleArray; TagId, Dof: Integer): Double;
var
  Ids: TIntArray;
  I: Integer;
begin
  Ids := M.NodesOfTag(TagId);
  Result := 0;
  for I := 0 to High(Ids) do Result := Result + U[3 * Ids[I] + Dof];
  if Length(Ids) > 0 then Result := Result / Length(Ids);
end;

procedure B1;
var
  M: TFEMMesh;
  F: TFEMModel;
  R: TStaticResult;
  Q: Integer;
begin
  Section('B1 barra 100x10x10 mm em tracao, 1 kN');
  for Q := 0 to 1 do
  begin
    M := BoxMesh(0.1, 0.01, 0.01, 0.005, Q = 1);
    F := TFEMModel.Create(M);
    try
      SetLength(F.Materials, 1); F.Materials[0] := Steel;
      F.AddLoad(Roller(M, 'xmin', 0));
      F.AddLoad(Roller(M, 'ymin', 1));
      F.AddLoad(Roller(M, 'zmin', 2));
      F.AddLoad(ForceLoad(Tag(M, 'xmax'), V3(1000, 0, 0)));
      Ok := F.SolveStatic(R); Check(Ok, 'resolve: ' + R.Message);
      CheckNear(MeanU(M, R.U, Tag(M, 'xmax'), 0), 1000 * 0.1 / (E_STEEL * 1e-4), 0.01,
        Format('TET%d: alongamento F L / (E A)', [M.NodesPerElement]));
      CheckNear(R.VonMises[NearestNode(M, V3(0.05, 0.005, 0.005))], 10e6, 0.01,
        Format('TET%d: tensao F/A no meio', [M.NodesPerElement]));
      CheckNear(R.Reaction.X, -1000, 1e-6, Format('TET%d: reacao = -F', [M.NodesPerElement]));
    finally
      F.Free; M.Free;
    end;
  end;
end;

procedure B2;
var
  M: TFEMMesh;
  F: TFEMModel;
  R: TStaticResult;
  I, Ref, G: Double;
  T0: TDateTime;
begin
  Section('B2 viga em balanco 200x10x20 mm, 100 N na ponta');
  M := BoxMesh(0.2, 0.01, 0.02, 0.005, True);
  F := TFEMModel.Create(M);
  try
    SetLength(F.Materials, 1); F.Materials[0] := Steel;
    F.AddLoad(FixLoad(Tag(M, 'xmin')));
    F.AddLoad(ForceLoad(Tag(M, 'xmax'), V3(0, 0, -100)));
    T0 := Now;
    Ok := F.SolveStatic(R); Check(Ok, 'resolve: ' + R.Message);
    Writeln(Format('        %d graus de liberdade, %d ms', [R.Dofs, MilliSecondsBetween(Now, T0)]));
    I := 0.01 * Power(0.02, 3) / 12;
    G := E_STEEL / (2 * (1 + NU_STEEL));
    { Euler-Bernoulli + cisalhamento (Timoshenko, kappa 5/6) }
    Ref := 100 * Power(0.2, 3) / (3 * E_STEEL * I) + 100 * 0.2 / (5 / 6 * G * 2e-4);
    CheckNear(-MeanU(M, R.U, Tag(M, 'xmax'), 2), Ref, 0.03, 'flecha na ponta P L^3/(3 E I) + cisalhamento');
    CheckNear(R.VonMises[NearestNode(M, V3(0.1, 0.005, 0.02))], 100 * 0.1 * 0.01 / I, 0.05,
      'tensao de flexao M c / I no meio do vao, fibra superior');
    CheckNear(R.Reaction.Z, 100, 1e-6, 'reacao vertical = 100 N');
    { PCG da o mesmo resultado que o Cholesky }
    F.ForceIterative := True;
    Ok := F.SolveStatic(R); Check(Ok, 'PCG resolve: ' + R.Message);
    CheckNear(-MeanU(M, R.U, Tag(M, 'xmax'), 2), Ref, 0.03,
      Format('PCG: mesma flecha (%d iteracoes)', [R.Solve.Iterations]));
  finally
    F.Free; M.Free;
  end;
end;

procedure B4;
var
  M: TFEMMesh;
  F: TFEMModel;
  R: TThermalResult;
begin
  Section('B4 parede 50 mm, 100 C / 20 C, k = 50');
  M := BoxMesh(0.05, 0.01, 0.01, 0.005, True);
  F := TFEMModel.Create(M);
  try
    SetLength(F.Materials, 1); F.Materials[0] := Steel;
    F.AddLoad(TemperatureLoad(Tag(M, 'xmin'), 100));
    F.AddLoad(TemperatureLoad(Tag(M, 'xmax'), 20));
    Ok := F.SolveThermal(R); Check(Ok, 'resolve: ' + R.Message);
    CheckNear(R.T[NearestNode(M, V3(0.025, 0.005, 0.005))], 60, 0.005, 'temperatura no meio = 60 C');
    CheckNear(R.T[NearestNode(M, V3(0.0125, 0.0, 0.01))], 80, 0.005, 'temperatura a 1/4 = 80 C');
    CheckNear(R.HeatIn, 50 * 1e-4 * 80 / 0.05, 0.005, 'fluxo k A dT / L = 8 W');
  finally
    F.Free; M.Free;
  end;
end;

procedure B5;
var
  M: TFEMMesh;
  F: TFEMModel;
  R: TThermalResult;
  Al: TFEMMaterial;
  Mm, Theta: Double;
  X: Double;
begin
  Section('B5 aleta 100x5x5 mm de aluminio, h = 25, ponta adiabatica');
  M := BoxMesh(0.1, 0.005, 0.005, 0.0025, True);
  F := TFEMModel.Create(M);
  try
    Al := FEMMaterial('Aluminio', 69e9, 0.33, 2700, 200, 23e-6, 150e6);
    SetLength(F.Materials, 1); F.Materials[0] := Al;
    F.AddLoad(TemperatureLoad(Tag(M, 'xmin'), 100));
    F.AddLoad(ConvectionLoad(Tag(M, 'ymin'), 25, 20));
    F.AddLoad(ConvectionLoad(Tag(M, 'ymax'), 25, 20));
    F.AddLoad(ConvectionLoad(Tag(M, 'zmin'), 25, 20));
    F.AddLoad(ConvectionLoad(Tag(M, 'zmax'), 25, 20));
    Ok := F.SolveThermal(R); Check(Ok, 'resolve: ' + R.Message);
    Mm := Sqrt(25 * 0.02 / (200 * 25e-6));
    for X in [0.05, 0.1] do
    begin
      Theta := Cosh(Mm * (0.1 - X)) / Cosh(Mm * 0.1);
      CheckNear(R.T[NearestNode(M, V3(X, 0.0025, 0.0025))] - 20, 80 * Theta, 0.01,
        Format('theta(x = %.0f mm) = cosh(m(L-x))/cosh(mL)', [X * 1000]));
    end;
  finally
    F.Free; M.Free;
  end;
end;

procedure B6;
var
  M: TFEMMesh;
  F: TFEMModel;
  R: TStaticResult;
  I: Integer;
begin
  Section('B6 barra presa nas pontas aquecida 50 K');
  M := BoxMesh(0.1, 0.01, 0.01, 0.005, True);
  F := TFEMModel.Create(M);
  try
    SetLength(F.Materials, 1); F.Materials[0] := Steel;
    F.AddLoad(Roller(M, 'xmin', 0));
    F.AddLoad(Roller(M, 'xmax', 0));
    F.AddLoad(Roller(M, 'ymin', 1));
    F.AddLoad(Roller(M, 'zmin', 2));
    F.RefTemperature := 20;
    SetLength(F.Temperature, M.NodeCount);
    for I := 0 to M.NodeCount - 1 do F.Temperature[I] := 70;
    Ok := F.SolveStatic(R); Check(Ok, 'resolve: ' + R.Message);
    CheckNear(R.VonMises[NearestNode(M, V3(0.05, 0.005, 0.005))], E_STEEL * 12e-6 * 50, 0.02, '|sigma| = E alfa dT = 120 MPa');
    Check(Abs(R.Reaction.X) < 1e-6 * 12000, 'reacoes das duas pontas se anulam');
  finally
    F.Free; M.Free;
  end;
end;

procedure B7B8;
var
  M: TFEMMesh;
  F: TFEMModel;
  R: TModalResult;
  I, A, L, Ref, RefFree, Beta: Double;
  T0: TDateTime;
  K: Integer;
  Rigid: Boolean;
begin
  Section('B7 viga em balanco 200x10x20 mm: 1a frequencia');
  M := BoxMesh(0.2, 0.01, 0.02, 0.005, True);
  F := TFEMModel.Create(M);
  try
    SetLength(F.Materials, 1); F.Materials[0] := Steel;
    F.AddLoad(FixLoad(Tag(M, 'xmin')));
    T0 := Now;
    Ok := F.SolveModal(3, R); Check(Ok, 'resolve: ' + R.Message);
    Writeln(Format('        %d ms', [MilliSecondsBetween(Now, T0)]));
    I := 0.02 * Power(0.01, 3) / 12;   { flexao na direcao fina (y) }
    A := 2e-4; L := 0.2;
    Beta := 1.875104;
    Ref := Sqr(Beta) / (2 * Pi) * Sqrt(E_STEEL * I / (RHO_STEEL * A * Power(L, 4)));
    CheckNear(R.Freq[0], Ref, 0.03, 'f1 = 1,875^2/(2 pi) sqrt(E I / (rho A L^4))');
    { segunda: flexao na direcao alta (z), I 4x maior: f2 = 2 f1 }
    CheckNear(R.Freq[1], 2 * Ref, 0.03, 'f2 (flexao em z) = 2 f1');
    { massa efetiva do 1o modo de flexao da viga em balanco: 61,3% da massa }
    CheckNear(R.EffMass[0][1], 0.613, 0.03, 'massa efetiva do 1o modo (y) = 61,3%');
    Check(R.EffMass[0][0] < 0.01, 'modo de flexao em y quase nao mobiliza massa em x');
  finally
    F.Free;
  end;
  Section('B8 viga livre-livre: 6 modos rigidos e 1a flexao');
  F := TFEMModel.Create(M);
  try
    SetLength(F.Materials, 1); F.Materials[0] := Steel;
    Ok := F.SolveModal(7, R); Check(Ok, 'resolve: ' + R.Message);
    RefFree := Sqr(4.730041) / (2 * Pi) * Sqrt(E_STEEL * I / (RHO_STEEL * A * Power(L, 4)));
    Rigid := Length(R.Freq) = 7;
    if Rigid then
      for K := 0 to 5 do Rigid := Rigid and (R.Freq[K] < 0.01 * RefFree);
    Check(Rigid, 'seis primeiras frequencias ~ 0 (corpo rigido)');
    if Length(R.Freq) = 7 then
      CheckNear(R.Freq[6], RefFree, 0.03, 'f7 = 4,730^2/(2 pi) sqrt(E I / (rho A L^4))');
  finally
    F.Free; M.Free;
  end;
end;

begin
  B1;
  B2;
  B4;
  B5;
  B6;
  B7B8;
  Finish('benchmarks FEM B1-B8');
end.
