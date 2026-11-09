program test_document_workflow;
{$mode objfpc}{$H+}
uses Classes, SysUtils, multiphysics_history, multiphysics_project,
  multiphysics_types, multiphysics_mesh, multiphysics_stl,
  multiphysics_ccx, multiphysics_check;
const
  Faces: array[0..11] of Integer = (0,2,1, 0,1,3, 0,3,2, 1,2,3);
  Vertices: array[0..3, 0..2] of Single = ((0,0,0),(1000,0,0),(0,1000,0),(0,0,1000));
var
  H: TPhysicsHistory;
  P: TPhysicsProject;
  M: TFEMMesh;
  L: TStringList;
  A, B, FN, Dir, Exe: string;
  R: TSTLInspection;
  I, J, K: Integer;
  Count: LongWord;
  F: TFileStream;
  Header: array[0..79] of Char;
  Rec: packed record Normal, A, B, C: array[0..2] of Single; Attr: Word; end;
begin
  Section('Historico de projeto: cargas, ramo novo, limite');
  H := TPhysicsHistory.Create(3); P := TPhysicsProject.Create;
  try
    A := P.ToJSON; H.Reset(A);
    P.Name := 'Segundo'; P.AddBC(NewBC('Carga', 'VIGA', 'xmax', bkForce));
    B := P.ToJSON;
    Check(H.Push(B), 'alteracao registrada');
    Check(not H.Push(B), 'estado duplicado ignorado');
    P.FromJSON(H.Undo);
    Check((P.BCCount = 0) and (P.ToJSON = A), 'desfaz nome e carga');
    P.FromJSON(H.Redo);
    Check((P.BCCount = 1) and (P.Name = 'Segundo'), 'refaz documento completo');
    H.Undo; H.Push('ramo novo');
    Check(not H.CanRedo, 'nova edicao descarta ramo antigo');
    H.Push('3'); H.Push('4'); H.Push('5');
    Check((H.Undo = '4') and (H.Undo = '3') and (H.Undo = ''), 'limite de historico');
    H.Reset(A); Check(not H.CanUndo and not H.CanRedo, 'novo arquivo limpa historico');
  finally P.Free; H.Free; end;

  Dir := GetTempFileName(GetTempDir, 'mpdoc');
  DeleteFile(Dir); ForceDirectories(Dir);
  FN := IncludeTrailingPathDelimiter(Dir) + 'tetra.stl';
  M := TFEMMesh.Create; L := TStringList.Create;
  try
    Section('STL fechado, aberto, binario e truncado');
    L.Add('solid tetra');
    for I := 0 to 3 do
    begin
      L.Add('facet normal 0 0 0'); L.Add('outer loop');
      for J := 0 to 2 do
      begin
        K := Faces[3*I+J];
        L.Add(Format('vertex %.0f %.0f %.0f', [Vertices[K,0], Vertices[K,1], Vertices[K,2]]));
      end;
      L.Add('endloop'); L.Add('endfacet');
    end;
    L.Add('endsolid tetra'); L.SaveToFile(FN);
    R := InspectSTL(FN, M);
    Check(R.Closed and (R.Triangles = 4), 'ASCII fechado e orientado');
    CheckNear(R.Volume, 1/6, 1e-12, 'volume em m3, entrada em mm');
    Check(M.ElemCount = 0, 'preview nunca cria elementos FEM');
    Check(M.NodeCount = 4, 'vertices compartilhados');
    L.Delete(24); L.Delete(24); L.Delete(24); // remove vertices da ultima face
    L.SaveToFile(FN); R := InspectSTL(FN, M);
    Check(not R.Closed and (R.Volume = 0), 'superficie aberta sem volume inventado');
    F := TFileStream.Create(FN, fmCreate);
    try
      FillChar(Header, SizeOf(Header), 0); Move('solid binary'[1], Header[0], 12);
      F.WriteBuffer(Header, 80); Count := NtoLE(LongWord(4)); F.WriteBuffer(Count,4);
      for I := 0 to 3 do
      begin
        FillChar(Rec, SizeOf(Rec), 0);
        for J := 0 to 2 do
        begin
          Rec.A[J] := Vertices[Faces[3*I],J];
          Rec.B[J] := Vertices[Faces[3*I+1],J];
          Rec.C[J] := Vertices[Faces[3*I+2],J];
        end;
        F.WriteBuffer(Rec,50);
      end;
    finally F.Free; end;
    R := InspectSTL(FN, M);
    Check(R.Closed, 'binario com cabecalho solid detectado pelo tamanho');
    CheckNear(R.Volume, 1/6, 1e-12, 'volume binario');
    L.Text := 'solid bad'#10'vertex 0 0 0'#10'endsolid'; L.SaveToFile(FN);
    try R := InspectSTL(FN,M); Check(False,'STL truncado deve falhar');
    except on E: Exception do Check(M.NodeCount = 0,'falha limpa preview parcial'); end;
    FN := IncludeTrailingPathDelimiter(Dir) + 'catalog.json';
    L.Text := '{"policy":"deny-unverified","entries":[{"version":"2.23","platform":"windows","arch":"x64","status":"candidate-unverified"}]}';
    L.SaveToFile(FN);
    Check(ApprovedCCXVersion(FN) = '', 'catalogo sem homologacao bloqueia selecao automatica');
    L.Text := '{"policy":"deny-unverified","entries":[' +
      '{"version":"2.9","platform":"windows","arch":"x64","status":"approved","licenseFile":"COPYING","sha256":"' + StringOfChar('a',64) + '"},' +
      '{"version":"2.23","platform":"windows","arch":"x64","status":"approved","licenseFile":"COPYING","sha256":"' + StringOfChar('b',64) + '"}]}';
    L.SaveToFile(FN);
    Check(ApprovedCCXVersion(FN) = '2.23', 'seleciona versao numerica mais recente');
    DeleteFile(FN);
    {$IFDEF WINDOWS}
    Section('Descoberta da instalacao CalculiX gerenciada');
    Exe := IncludeTrailingPathDelimiter(Dir) + 'MultiSuite\solvers\calculix\versions\2.23\bin\ccx.exe';
    ForceDirectories(ExtractFilePath(Exe)); L.Clear; L.SaveToFile(Exe);
    FN := IncludeTrailingPathDelimiter(Dir) + 'MultiSuite\solvers\calculix\active.txt';
    L.Text := Exe; L.SaveToFile(FN);
    Check(ManagedCCX(Dir) = Exe, 'resolve versao ativa');
    L.Text := IncludeTrailingPathDelimiter(Dir) + 'outside.exe'; L.SaveToFile(FN);
    Check(ManagedCCX(Dir) = '', 'ponteiro fora de versions rejeitado');
    DeleteFile(FN); DeleteFile(Exe);
    RemoveDir(ExtractFilePath(Exe)); RemoveDir(ExtractFileDir(ExtractFileDir(Exe)));
    RemoveDir(Dir + '\MultiSuite\solvers\calculix\versions');
    RemoveDir(Dir + '\MultiSuite\solvers\calculix'); RemoveDir(Dir + '\MultiSuite\solvers'); RemoveDir(Dir + '\MultiSuite');
    {$ENDIF}
  finally
    DeleteFile(IncludeTrailingPathDelimiter(Dir) + 'tetra.stl');
    RemoveDir(Dir); L.Free; M.Free;
  end;
  Finish('documento, historico, STL e descoberta CalculiX');
end.
