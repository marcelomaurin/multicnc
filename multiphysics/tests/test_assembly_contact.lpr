program test_assembly_contact;

{ Contato colado (MP-3.3) e importacao da montagem do MultiAssembly (MP-2.1):
  - duas caixas empilhadas coladas = uma caixa unica;
  - viga dividida em duas pecas com malhas diferentes = viga inteira;
  - CNC de demonstracao do MultiAssembly: pecas, posicoes, contatos, e a
    reacao vertical igual ao peso total sob gravidade. }

{$mode objfpc}{$H+}

uses
  Classes, SysUtils, Math, multiphysics_types, multiphysics_materials,
  multiphysics_vector, multiphysics_geometry, multiphysics_mesh, multiphysics_contact,
  multiphysics_project, multiphysics_scenario, multiphysics_analysis,
  multiphysics_assembly_import, multiassembly_types, multiassembly_project,
  multiassembly_demo, multiphysics_check;

var
  Ok: Boolean;

function Steel: TMaterial;
begin
  Result := MaterialByIndex(FindMaterial('Aco carbono'));
  Result.YoungModulus := 200e9;
  Result.Poisson := 0.3;
end;

function AddBox(P: TPhysicsProject; const ID: string; const At, Size: TVector3; H: Double = 0): TPhysicsPart;
begin
  Result := TPhysicsPart.Create;
  Result.ID := ID;
  Result.Material := Steel;
  Result.AddPrimitive(BoxPrim('b', At, Size));
  Result.MeshSize := H;
  P.AddPart(Result);
end;

procedure AddContact(P: TPhysicsProject; const A, B: string);
var
  C: TContact;
begin
  C.Name := A + '-' + B; C.PartA := A; C.PartB := B;
  C.FrictionCoefficient := 0; C.StaticFrictionCoefficient := 0;
  C.RollingFrictionCoefficient := 0; C.ThermalConductance := 0;
  P.AddContact(C);
end;

function Solve(P: TPhysicsProject; Kind: TAnalysisKind; out R: TAnalysisRun): Boolean;
begin
  R := TAnalysisRun.Create(P);
  P.Settings.CheckConvergence := False;
  Result := R.Run(Kind);
  if not Result then Writeln('        ', R.Message);
end;

procedure TestStacked;
var
  P: TPhysicsProject;
  R: TAnalysisRun;
  B: TBoundaryCondition;
  Single, Joined: Double;
begin
  Section('Caixas empilhadas coladas x caixa unica');
  P := TPhysicsProject.Create;
  try
    P.Settings.MeshSize := 0.004;
    AddBox(P, 'U', V3(0, 0, 0), V3(0.01, 0.01, 0.03));
    P.AddBC(NewBC('Base', 'U', 'zmin', bkFixed));
    B := NewBC('Carga', 'U', 'zmax', bkForce); B.Z := -1000; P.AddBC(B);
    Check(Solve(P, akStatic, R), 'caixa unica resolve');
    Single := R.StaticRes.MaxDisp;
    R.Free;
    P.Clear;
    P.Settings.MeshSize := 0.004;
    AddBox(P, 'A', V3(0, 0, 0), V3(0.01, 0.01, 0.01));
    AddBox(P, 'B', V3(0, 0, 0.01), V3(0.01, 0.01, 0.02), 0.003);
    AddContact(P, 'A', 'B');
    P.AddBC(NewBC('Base', 'A', 'zmin', bkFixed));
    B := NewBC('Carga', 'B', 'zmax', bkForce); B.Z := -1000; P.AddBC(B);
    Ok := Solve(P, akStatic, R); Check(Ok, 'duas caixas coladas resolvem: ' + R.Message);
    Check(Pos('nos amarrados', R.Log.Text) > 0, 'contato gerou amarracoes');
    Joined := R.StaticRes.MaxDisp;
    CheckNear(Joined, Single, 0.02, 'deslocamento do topo igual ao da caixa unica');
    CheckNear(Single, 1000 * 0.03 / (200e9 * 1e-4), 0.05, 'e proximo de F L / (E A)');
    R.Free;
    { sem o contato a peca de cima fica solta }
    P.DeleteContact(0);
    Ok := Solve(P, akStatic, R); Check(not Ok, 'sem contato: peca solta e recusada (' + R.Message + ')');
    R.Free;
  finally
    P.Free;
  end;
end;

procedure TestSplitBeam;
var
  P: TPhysicsProject;
  R: TAnalysisRun;
  B: TBoundaryCondition;
  Whole, Split, F1, F2: Double;
begin
  Section('Viga em balanco dividida em duas pecas (malhas diferentes)');
  P := TPhysicsProject.Create;
  try
    P.Settings.MeshSize := 0.005;
    AddBox(P, 'V', V3(0, 0, 0), V3(0.2, 0.01, 0.02));
    P.AddBC(NewBC('Engaste', 'V', 'xmin', bkFixed));
    B := NewBC('Carga', 'V', 'xmax', bkForce); B.Z := -100; P.AddBC(B);
    Check(Solve(P, akStatic, R), 'viga inteira resolve');
    Whole := R.StaticRes.MaxDisp;
    R.Free;
    Check(Solve(P, akModal, R), 'viga inteira: modal');
    F1 := R.ModalRes.Freq[0];
    R.Free;
    P.Clear;
    P.Settings.MeshSize := 0.005;
    P.Settings.Modes := 2;
    AddBox(P, 'V1', V3(0, 0, 0), V3(0.1, 0.01, 0.02));
    AddBox(P, 'V2', V3(0.1, 0, 0), V3(0.1, 0.01, 0.02), 0.004);
    AddContact(P, 'V1', 'V2');
    P.AddBC(NewBC('Engaste', 'V1', 'xmin', bkFixed));
    B := NewBC('Carga', 'V2', 'xmax', bkForce); B.Z := -100; P.AddBC(B);
    Ok := Solve(P, akStatic, R); Check(Ok, 'viga em duas pecas resolve: ' + R.Message);
    Split := R.StaticRes.MaxDisp;
    CheckNear(Split, Whole, 0.02, 'flecha igual a da viga inteira');
    R.Free;
    Check(Solve(P, akModal, R), 'viga em duas pecas: modal');
    F2 := R.ModalRes.Freq[0];
    CheckNear(F2, F1, 0.02, '1a frequencia igual a da viga inteira');
    R.Free;
  finally
    P.Free;
  end;
end;

procedure TestImport;
var
  AP: TAssemblyProject;
  P: TPhysicsProject;
  R: TAnalysisRun;
  Log: TStringList;
  I, J, K, Frame: Integer;
  C: TAssemblyComponent;
  Q2: TMeshQuality;
  M: TFEMMesh;
  Lo, Hi, Q: TVector3;
  Ok: Boolean;
  Weight: Double;
begin
  Section('Importacao da CNC de demonstracao do MultiAssembly');
  AP := TAssemblyProject.Create; P := TPhysicsProject.Create; Log := TStringList.Create;
  try
    TAssemblyDemo.BuildCNC(AP);
    Check(ImportAssembly(AP, P, Log), 'importa: ' + Log.Text);
    Check(P.PartCount = AP.ComponentCount, Format('%d pecas para %d componentes', [P.PartCount, AP.ComponentCount]));
    Check(P.ContactCount > 0, Format('%d contatos detectados', [P.ContactCount]));
    P.Settings.MeshSize := 0.008;
    P.Settings.Quadratic := False;
    P.Settings.CheckConvergence := False;
    R := TAnalysisRun.Create(P);
    try
      Ok := R.MeshOnly(Q2);
      Check(Ok and (Q2.Inverted = 0), Format('malha da montagem: %d elementos, nenhum invertido', [Q2.Elements]));
      M := R.Mesh;
      { envolvente de cada peca = posicao .. posicao + tamanho (pecas sem rotacao) }
      Ok := True;
      for I := 0 to AP.ComponentCount - 1 do
      begin
        C := AP.Component(I);
        if (C.Rotation.X <> 0) or (C.Rotation.Y <> 0) or (C.Rotation.Z <> 0) then Continue;
        Lo := V3(1e9, 1e9, 1e9); Hi := V3(-1e9, -1e9, -1e9);
        for J := 0 to M.ElemCount - 1 do
          if M.Elems[J].Part = P.FindPart(C.ID) then
            for K := 0 to 3 do
            begin
              Q := M.Nodes[M.Elems[J].N[K]];
              Lo := V3(Min(Lo.X, Q.X), Min(Lo.Y, Q.Y), Min(Lo.Z, Q.Z));
              Hi := V3(Max(Hi.X, Q.X), Max(Hi.Y, Q.Y), Max(Hi.Z, Q.Z));
            end;
        if (Abs(Lo.X - C.Position.X / 1000) > 1e-6) or (Abs(Lo.Z - C.Position.Z / 1000) > 1e-6) or
           (Abs(Hi.X - (C.Position.X + C.Size.X) / 1000) > 1e-6) or (Abs(Hi.Z - (C.Position.Z + C.Size.Z) / 1000) > 1e-6) then
        begin
          Ok := False;
          Writeln(Format('        %s: malha [%.4f..%.4f] x [%.4f..%.4f], esperado [%.4f..%.4f]', [C.ID, Lo.X, Hi.X, Lo.Z, Hi.Z,
            C.Position.X / 1000, (C.Position.X + C.Size.X) / 1000]));
        end;
      end;
      Check(Ok, 'cada peca ocupa posicao .. posicao + tamanho da montagem');
      { estrutura presa e gravidade: a reacao vertical equilibra o peso }
      Frame := P.FindPart('FRAME');
      Check(Frame >= 0, 'peca FRAME importada');
      if P.BCCount = 1 then P.AddBC(NewBC('Base', 'FRAME', 'zmin', bkFixed));
      Ok := R.Run(akStatic);
      if not Ok then Writeln(R.Log.Text);
      Check(Ok, 'montagem resolve sob gravidade: ' + R.Message);
      Weight := 0;
      for I := 0 to P.PartCount - 1 do Weight := Weight + R.Mesh.PartVolume(I) * P.Part(I).Material.Density * 9.80665;
      CheckNear(R.StaticRes.Reaction.Z, Weight, 1e-4, Format('reacao vertical = peso total (%.3f N)', [Weight]));
      Check(Pos('nos amarrados', R.Log.Text) > 0, 'pecas presas a estrutura pelos contatos');
    finally
      R.Free;
    end;
  finally
    Log.Free; P.Free; AP.Free;
  end;
end;

begin
  TestStacked;
  TestSplitBeam;
  TestImport;
  Finish('contato colado e importacao da montagem');
end.
