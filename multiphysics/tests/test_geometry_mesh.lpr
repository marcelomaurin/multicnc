program test_geometry_mesh;

{ Geometria e malha: volume e centroide analiticos das primitivas, volume da
  malha, conformidade (faces internas em 2 elementos), faces etiquetadas,
  orientacao das normais e conversao TET10. }

{$mode objfpc}{$H+}

uses
  SysUtils, Math, multiphysics_vector, multiphysics_geometry, multiphysics_mesh,
  multiphysics_check;

procedure TestAnalytic;
var
  P: TGeoPrimitive;
  C: TVector3;
begin
  Section('Primitivas: volume e centroide analiticos');
  P := BoxPrim('b', V3(1, 2, 3), V3(0.2, 0.1, 0.05));
  CheckNear(PrimVolume(P), 0.001, 1e-12, 'caixa: volume');
  C := PrimCentroid(P);
  Check(SameValue(C.X, 1.1, 1e-12) and SameValue(C.Y, 2.05, 1e-12) and SameValue(C.Z, 3.025, 1e-12), 'caixa: centroide');
  P := CylPrim('c', 'z', V3(0, 0, 0), 0.01, 0.1);
  CheckNear(PrimVolume(P), Pi * 1e-4 * 0.1, 1e-12, 'cilindro: volume');
  P := CylPrim('t', 'x', V3(0, 0, 0), 0.02, 0.1, 0.015);
  CheckNear(PrimVolume(P), Pi * (4e-4 - 2.25e-4) * 0.1, 1e-12, 'tubo: volume');
  C := PrimCentroid(P);
  CheckNear(C.X, 0.05, 1e-12, 'tubo no eixo x: centroide em x = h/2');
  P := CylPrim('k', 'z', V3(0, 0, 0), 0.02, 0.06, 0, 0);
  CheckNear(PrimVolume(P), Pi * 4e-4 * 0.06 / 3, 1e-12, 'cone: volume');
  CheckNear(PrimCentroid(P).Z, 0.015, 1e-12, 'cone: centroide a h/4 da base');
  P := CylPrim('s', 'z', V3(0, 0, 0), 0.01, 0.02);
  P.Arc0 := 0; P.Arc1 := 180;
  CheckNear(PrimVolume(P), Pi * 1e-4 * 0.02 / 2, 1e-12, 'meio cilindro: volume');
  CheckNear(PrimCentroid(P).Y, 4 * 0.01 / (3 * Pi), 1e-4, 'meio cilindro: centroide 4R/(3 pi)');
  P := PrismPrim('p', 'z', V3(0, 0, 0), 0.01, [V2(0, 0), V2(0.03, 0), V2(0, 0.04)]);
  CheckNear(PrimVolume(P), 0.5 * 0.03 * 0.04 * 0.01, 1e-12, 'prisma triangular: volume');
  CheckNear(PrimCentroid(P).X, 0.01, 1e-12, 'prisma: centroide x = a/3');
end;

{ todas as faces internas sao compartilhadas por 2 tetraedros: equivale a
  soma das areas de contorno = area analitica da superficie }
procedure CheckMesh(M: TFEMMesh; const Tag: string; VolRef, VolTol, AreaRef, AreaTol: Double);
var
  Q: TMeshQuality;
  F, Untagged: Integer;
  A, Out: Double;
  C, N: TVector3;
  E: Integer;
begin
  Q := M.Quality;
  Check(Q.Inverted = 0, Format('%s: nenhum tetraedro invertido (%d elementos, forma min %.3f)', [Tag, Q.Elements, Q.MinShape]));
  CheckNear(M.Volume, VolRef, VolTol, Tag + ': volume da malha');
  A := 0; Untagged := 0; Out := 0;
  for F := 0 to M.FaceCount - 1 do
  begin
    A := A + M.FaceArea(F);
    if M.Faces[F].Tag < 0 then Inc(Untagged);
    { normal para fora: aponta para longe do centroide do elemento dono }
    E := M.Faces[F].Elem;
    C := VScale(VAdd(VAdd(M.Nodes[M.Elems[E].N[0]], M.Nodes[M.Elems[E].N[1]]),
      VAdd(M.Nodes[M.Elems[E].N[2]], M.Nodes[M.Elems[E].N[3]])), 0.25);
    N := M.FaceNormal(F);
    if VDot(N, VSub(M.Nodes[M.Faces[F].N[0]], C)) <= 0 then Out := Out + 1;
  end;
  CheckNear(A, AreaRef, AreaTol, Tag + ': area de contorno (malha conforme)');
  Check(Untagged = 0, Format('%s: todas as faces de contorno etiquetadas (%d sem nome)', [Tag, Untagged]));
  Check(Out = 0, Tag + ': normais das faces para fora');
end;

procedure TestMeshes;
var
  M: TFEMMesh;
  P: TGeoPrimitive;
  Part, T, I: Integer;
  Ids: TIntArray;
  Ok: Boolean;
begin
  Section('Malha das primitivas');
  M := TFEMMesh.Create;
  try
    Part := M.AddPart('VIGA');
    M.AddPrimitive(Part, BoxPrim('b', V3(0, 0, 0), V3(0.2, 0.01, 0.02)), IdentityTransform, 0.005);
    M.Finalize;
    CheckMesh(M, 'caixa 200x10x20', 0.2 * 0.01 * 0.02, 1e-9, 2 * (0.2 * 0.01 + 0.2 * 0.02 + 0.01 * 0.02), 1e-9);
    T := M.FindTag('VIGA/b/xmin');
    Check(T >= 0, 'face VIGA/b/xmin existe');
    CheckNear(M.TagArea(T), 0.01 * 0.02, 1e-9, 'area da face xmin');
    Ids := M.NodesOfTag(T);
    Ok := Length(Ids) > 0;
    for I := 0 to High(Ids) do Ok := Ok and (Abs(M.Nodes[Ids[I]].X) < 1e-12);
    Check(Ok, Format('%d nos da face xmin com x = 0', [Length(Ids)]));
    M.ConvertToTet10;
    Ids := M.NodesOfTag(T);
    Ok := Length(Ids) > 0;
    for I := 0 to High(Ids) do Ok := Ok and (Abs(M.Nodes[Ids[I]].X) < 1e-12);
    Check(Ok and (M.Order = 2), Format('TET10: %d nos na face xmin, todos em x = 0', [Length(Ids)]));
    Ok := True;
    for I := 0 to M.ElemCount - 1 do
      Ok := Ok and (M.Elems[I].N[9] >= 0) and
        (VLength(VSub(M.Nodes[M.Elems[I].N[4]], VScale(VAdd(M.Nodes[M.Elems[I].N[0]], M.Nodes[M.Elems[I].N[1]]), 0.5))) < 1e-12);
    Check(Ok, 'TET10: nos de meio de aresta no lugar certo');

    M.Clear;
    Part := M.AddPart('EIXO');
    M.AddPrimitive(Part, CylPrim('c', 'z', V3(0, 0, 0), 0.01, 0.05), IdentityTransform, 0.002);
    M.Finalize;
    CheckMesh(M, 'cilindro R10 h50', Pi * 1e-4 * 0.05, 0.01, 2 * Pi * 1e-4 + 2 * Pi * 0.01 * 0.05, 0.01);
    Check(M.FindTag('EIXO/c/lateral') >= 0, 'face lateral do cilindro');

    M.Clear;
    Part := M.AddPart('TUBO');
    P := CylPrim('t', 'y', V3(0, 0, 0), 0.02, 0.03, 0.016);
    M.AddPrimitive(Part, P, EulerTransform(V3(1, 0, 0), 0, 0, 30), 0.002);
    M.Finalize;
    CheckMesh(M, 'tubo girado', PrimVolume(P), 0.01,
      2 * Pi * (4e-4 - 2.56e-4) + 2 * Pi * (0.02 + 0.016) * 0.03, 0.01);
    Check(M.FindTag('TUBO/t/interna') >= 0, 'face interna do tubo');

    M.Clear;
    Part := M.AddPart('SETOR');
    P := CylPrim('s', 'z', V3(0, 0, 0), 0.02, 0.01, 0.005);
    P.Arc0 := 0; P.Arc1 := 90;
    M.AddPrimitive(Part, P, IdentityTransform, 0.002);
    M.Finalize;
    CheckMesh(M, 'setor 90 graus de coroa', PrimVolume(P), 0.01,
      2 * (Pi / 4) * (4e-4 - 0.25e-4) + (Pi / 2) * (0.02 + 0.005) * 0.01 + 2 * 0.015 * 0.01, 0.01);
    Check((M.FindTag('SETOR/s/corte0') >= 0) and (M.FindTag('SETOR/s/corte1') >= 0), 'faces de corte do setor');
    CheckNear(M.TagArea(M.FindTag('SETOR/s/corte0')), 0.015 * 0.01, 1e-9, 'area do corte0');

    M.Clear;
    Part := M.AddPart('CONE');
    P := CylPrim('k', 'z', V3(0, 0, 0), 0.02, 0.04, 0, 0.01);
    M.AddPrimitive(Part, P, IdentityTransform, 0.002);
    M.Finalize;
    Check(M.Quality.Inverted = 0, 'tronco de cone: sem tetraedro invertido');
    CheckNear(M.Volume, PrimVolume(P), 0.01, 'tronco de cone: volume');

    M.Clear;
    Part := M.AddPart('L');
    P := PrismPrim('p', 'x', V3(0, 0, 0), 0.05,
      [V2(0, 0), V2(0.04, 0), V2(0.04, 0.005), V2(0.005, 0.005), V2(0.005, 0.03), V2(0, 0.03)]);
    M.AddPrimitive(Part, P, IdentityTransform, 0.003);
    M.Finalize;
    CheckMesh(M, 'prisma em L', PrimVolume(P), 1e-9,
      2 * Abs(PolygonArea(P.Poly)) + 2 * (0.04 + 0.03) * 0.05, 1e-9);
    Check(M.FindTag('L/p/lado3') >= 0, 'faces laterais do prisma nomeadas');
    CheckNear(M.TagArea(M.FindTag('L/p/lado0')), 0.04 * 0.05, 1e-9, 'area do lado0');

    { duas pecas na mesma malha: volumes por peca }
    M.Clear;
    M.AddPart('A'); M.AddPart('B');
    M.AddPrimitive(0, BoxPrim('b', V3(0, 0, 0), V3(0.01, 0.01, 0.01)), IdentityTransform, 0.005);
    M.AddPrimitive(1, BoxPrim('b', V3(0, 0, 0.01), V3(0.01, 0.01, 0.02)), IdentityTransform, 0.005);
    M.Finalize;
    CheckNear(M.PartVolume(1), 2e-6, 1e-9, 'duas pecas: volume da peca B');
    Check((M.FindTag('A/b/zmax') >= 0) and (M.FindTag('B/b/zmin') >= 0), 'duas pecas: faces de contato separadas');
  finally
    M.Free;
  end;
end;

begin
  TestAnalytic;
  TestMeshes;
  Finish('geometria e malha');
end.
