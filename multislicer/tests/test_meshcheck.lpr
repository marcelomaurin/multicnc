program test_meshcheck;
{ conferencia da malha ao abrir: fechada, normais, escala (Etapa 9.2) }
{$mode objfpc}{$H+}
uses Classes, SysUtils, Math, multislicer_types, multislicer_mesh, multislicer_pipeline, multislicer_meshcheck;
var M, M2: TMesh; R: TMeshReport; I: Integer;
procedure Check(OK: Boolean; const Msg: string);
begin if not OK then begin Writeln('FAIL: ', Msg); Halt(1); end; end;
begin
  M := TMesh.Create; M2 := TMesh.Create;
  try
    AddBox(M, 10, 10, 0, 30, 20, 5);
    R := CheckMesh(M);
    Check((R.Triangles = 12) and MeshIsClosed(R) and (R.Degenerate = 0), 'caixa fechada');
    Check(SameValue(R.Volume, 20 * 10 * 5, 1e-6) and not NormalsInverted(R), 'volume positivo');
    Check(SameValue(R.SizeX, 20, 1e-9) and (R.Units = muOk) and (MeshReportText(R) = ''), 'tamanho e sem avisos');
    FlipNormals(M);
    R := CheckMesh(M);
    Check(NormalsInverted(R) and SameValue(R.Volume, -1000, 1e-6), 'normais invertidas detectadas');
    FlipNormals(M);
    Check(not NormalsInverted(CheckMesh(M)), 'desvirar corrige');
    { tira um triangulo: 3 arestas soltas }
    for I := 0 to M.Count - 2 do M2.Add(M.Triangle(I));
    R := CheckMesh(M2);
    Check((R.OpenEdges = 3) and not MeshIsClosed(R) and not NormalsInverted(R), 'malha aberta');
    Check(Pos('Malha aberta (3 arestas soltas)', MeshReportText(R)) = 1, 'aviso de malha aberta');
    { duplicado: aresta usada por 4 faces }
    M2.Clear; for I := 0 to M.Count - 1 do begin M2.Add(M.Triangle(I)); M2.Add(M.Triangle(I)); end;
    Check(CheckMesh(M2).NonManifoldEdges > 0, 'nao manifold');
    { em polegadas: 1 x 0,5 x 0,25 }
    M2.Clear; AddBox(M2, 0, 0, 0, 1, 0.5, 0.25);
    R := CheckMesh(M2);
    Check((R.Units = muTiny) and (Pos('polegadas', MeshReportText(R)) > 0), 'peca em polegadas');
    M2.Clear; AddBox(M2, 0, 0, 0, 2500, 100, 100);
    Check(CheckMesh(M2).Units = muHuge, 'peca enorme');
    Writeln('MultiSlicer malha: OK (fechada, aberta, nao manifold, normais invertidas, polegadas, enorme)');
  finally
    M.Free; M2.Free;
  end;
end.
