program test_multicad;

{ MultiCAD - testes do nucleo (sem LCL). Fase 0: tipos e planos, unidades e
  expressoes, materiais, Ids persistentes, JSON .mcad, validacao das
  operacoes, malha rotulada (solda, malha fechada, volume) e ICadKernel. }

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, Math, multicad_types, multicad_units, multicad_materials,
  multicad_feature, multicad_refgeom, multicad_sketch, multicad_extrude,
  multicad_document, multicad_mesh, multicad_kernel;

var
  Passed, Failed: Integer;

procedure Check(Cond: Boolean; const What: string);
begin
  if Cond then
    Inc(Passed)
  else
  begin
    Inc(Failed);
    Writeln('FALHOU: ', What);
  end;
end;

function Near(A, B: Double; Tol: Double = 1E-9): Boolean;
begin
  Result := Abs(A - B) <= Tol;
end;

function NearV(const A, B: TCadVec3; Tol: Double = 1E-9): Boolean;
begin
  Result := VDist(A, B) <= Tol;
end;

{ ---------- tipos e planos ---------- }

procedure TestFrames;
var
  F: TCadFrame;
  P: TCadVec3;
  L: TCadVec2;
  M, MI: TCadMat4;
begin
  F := StdFrame(spFrontal);
  Check(NearV(F.Normal, V3(0, 0, 1)) and NearV(F.XDir, V3(1, 0, 0)) and NearV(F.YDir, V3(0, 1, 0)),
    'Plano Frontal: normal +Z, x +X, y +Y');
  F := StdFrame(spSuperior);
  Check(NearV(F.Normal, V3(0, 1, 0)) and NearV(F.XDir, V3(1, 0, 0)) and NearV(F.YDir, V3(0, 0, -1)),
    'Plano Superior: normal +Y, x +X, y -Z');
  F := StdFrame(spLateral);
  Check(NearV(F.Normal, V3(1, 0, 0)) and NearV(F.XDir, V3(0, 0, -1)) and NearV(F.YDir, V3(0, 1, 0)),
    'Plano Lateral: normal +X, x -Z, y +Y');
  Check(FrameValid(StdFrame(spFrontal)) and FrameValid(StdFrame(spSuperior)) and
    FrameValid(StdFrame(spLateral)), 'planos padrao ortonormais e destros');

  F := StdFrame(spSuperior);
  P := FrameToWorld(F, V2(10, 20));
  Check(NearV(P, V3(10, 0, -20)), 'ponto (10,20) no Superior vai para (10,0,-20)');
  L := FrameToLocal(F, P);
  Check(Near(L.X, 10) and Near(L.Y, 20), 'ida e volta no referencial');
  Check(Near(FrameDistance(FrameOffset(F, 15), V3(0, 0, 0)), -15), 'plano deslocado 15 mm');

  F := FrameFromNormal(V3(1, 2, 3), V3(0, 0, -1));
  Check(FrameValid(F), 'referencial de face com normal -Z valido');
  Check(NearV(F.XDir, V3(1, 0, 0)), 'face: x = projecao do X global');
  F := FrameFromNormal(V3(0, 0, 0), V3(1, 0, 0));
  Check(FrameValid(F) and NearV(F.XDir, V3(0, 0, 1)), 'face com normal X usa o Z global como x');

  M := MatMul(MatTranslate(5, 6, 7), MatRotate(V3(0, 0, 1), 90));
  P := MatPoint(M, V3(1, 0, 0));
  Check(NearV(P, V3(5, 7, 7), 1E-12), 'rotacao de 90 graus em Z e translacao');
  MI := MatRigidInverse(M);
  Check(NearV(MatPoint(MI, P), V3(1, 0, 0), 1E-12), 'inversa rigida');
end;

{ ---------- unidades e expressoes ---------- }

type
  TVars = class
    function Resolve(const AName: string; out AValue: Double): Boolean;
  end;

function TVars.Resolve(const AName: string; out AValue: Double): Boolean;
begin
  Result := SameText(AName, 'D1@Esboço1') or SameText(AName, 'Largura');
  if SameText(AName, 'Largura') then
    AValue := 80
  else
    AValue := 50;
end;

procedure TestUnits;
var
  V: Double;
  E: string;
  R: TVars;
begin
  Check(Near(CadEval('80/2'), 40), '80/2 = 40');
  Check(Near(CadEval('1in'), 25.4), '1in = 25,4 mm');
  Check(Near(CadEval('2"'), 50.8), '2" = 50,8 mm');
  Check(Near(CadEval('12,5'), 12.5), 'virgula decimal');
  Check(Near(CadEval('1.5cm + 3mm'), 18), 'cm + mm');
  Check(Near(CadEval('0.1 m'), 100), 'metro');
  Check(Near(CadEval('-(2+3)*4'), -20), 'parenteses e menos unario');
  Check(Near(CadEval('2^3'), 8), 'potencia');
  Check(Near(CadEval('sqrt(16) + abs(-1)'), 5), 'sqrt e abs');
  Check(Near(CadEval('30', vkAngle), 30), 'angulo em graus');
  Check(Near(CadEval('pi rad', vkAngle), 180, 1E-9), 'pi rad = 180 graus');
  Check(Near(CadEval('cos(60)', vkNumber), 0.5, 1E-12), 'cos em graus');
  Check(Near(CadEval('1e-3'), 0.001), 'notacao cientifica');
  Check(not CadTryEval('2+', V, E), 'expressao incompleta recusada');
  Check(E <> '', 'mensagem de erro preenchida');
  Check(not CadTryEval('abc', V, E), 'variavel desconhecida recusada');
  Check(not CadTryEval('10/0', V, E), 'divisao por zero recusada');
  Check(not CadTryEval('5 kg', V, E), 'unidade desconhecida recusada');
  Check(not CadTryEval('5 deg', V, E, vkLength), 'angulo em comprimento recusado');
  Check(not CadTryEval('', V, E), 'expressao vazia recusada');
  R := TVars.Create;
  try
    Check(Near(CadEval('D1@Esboço1 + 5', vkLength, @R.Resolve), 55), 'variavel D1@Esboço1');
    Check(Near(CadEval('Largura/2', vkLength, @R.Resolve), 40), 'variavel global');
  finally
    R.Free;
  end;
  Check(CadFmt(40) = '40', 'formato sem zeros');
  Check(CadFmt(12.345, 2) = '12.35', 'formato 2 casas com ponto');
  Check(CadFmt(-0.0001, 2) = '0', 'sem -0');
  Check(CadFmtLength(25.4) = '25.4 mm', 'formato mm');
end;

{ ---------- materiais ---------- }

procedure TestMaterials;
var
  M: TCadMaterial;
  Fn, E: string;
  SL: TStringList;
  N: Integer;
begin
  Check(CadMaterialCount >= 12, 'biblioteca com 12 materiais');
  Check(CadFindMaterial('Aço 1020', M) and Near(M.Density, 7870), 'aço 1020: 7870 kg/m3');
  Check(CadFindMaterial('alumínio 6061-T6', M), 'busca sem diferenciar maiusculas');
  Check(Near(CadMassKg(M, 1E6), 2.7, 1E-12), '1000 cm3 de aluminio = 2,7 kg');
  Check(not CadFindMaterial('Unobtainium', M), 'material inexistente');

  N := CadMaterialCount;
  Fn := GetTempDir + 'mcad_materials_test.json';
  SL := TStringList.Create;
  try
    SL.Text := '[{"name":"Bronze TM23","density":8800,"e_gpa":100,"poisson":0.34},' +
      '{"name":"Aço 1020","density":7900,"e_gpa":200,"poisson":0.29}]';
    SL.SaveToFile(Fn);
    Check(CadLoadMaterials(Fn, E), 'carrega materiais do arquivo: ' + E);
    Check(CadMaterialCount = N + 1, 'acrescenta so o novo material');
    Check(CadFindMaterial('Aço 1020', M) and Near(M.Density, 7900), 'substitui pelo nome');
    SL.Text := '[{"name":"Sem densidade"}]';
    SL.SaveToFile(Fn);
    Check(not CadLoadMaterials(Fn, E) and (CadMaterialCount = N + 1),
      'arquivo invalido recusado sem alterar a biblioteca');
  finally
    SL.Free;
    DeleteFile(Fn);
  end;
end;

{ ---------- documento, Ids e JSON ---------- }

procedure TestDocument;
var
  D, D2: TCadDocument;
  S: TCadSketch;
  X, C: TCadExtrude;
  J1, J2, E, Fn: string;
  V: Double;
  I: Integer;
  Ids: array of Integer;
begin
  D := TCadDocument.Create;
  D2 := TCadDocument.Create;
  try
    Check(D.Count = 4, 'documento novo: 3 planos + origem');
    Check((D.StdPlane(spFrontal).Id = MCAD_ID_FRONTAL) and
      (D.StdPlane(spSuperior).Id = MCAD_ID_SUPERIOR) and
      (D.StdPlane(spLateral).Id = MCAD_ID_LATERAL), 'Ids fixos dos planos padrao');
    Check(D.FindById(MCAD_ID_ORIGIN).Kind = cfOrigin, 'origem com Id 4');
    Check(D.StdPlane(spFrontal).Name = 'Plano Frontal', 'nome do plano em portugues');

    S := D.AddSketch('plane:1');
    Check(S.Name = 'Esboço1', 'nome automatico Esboço1');
    I := S.AddRectangle(0, 0, 80, 50);
    Check((S.EntityCount = 4) and (S.EntityIndex(I + 3) = 3), 'retangulo com 4 linhas de Ids seguidos');
    Check(S.ConstraintCount = 8, 'retangulo com 4 coincidentes, 2 horizontais e 2 verticais');
    S.AddDimension(ckHorizontalDistance, I, 1, I, 2, 80);
    S.AddDimension(ckVerticalDistance, I + 1, 1, I + 1, 2, 50);
    S.AddCircle(20, 25, 4);
    X := D.AddExtrude(S.Id, 10);
    Check(X.Name = 'Ressalto-Extrusão1', 'nome automatico do ressalto');
    Check(X.Validate = '', 'ressalto cego valido');
    C := D.AddExtrude(S.Id, 5, True);
    Check((C.Kind = cfCut) and (C.Name = 'Corte-Extrusão1'), 'corte com nome automatico');
    C.Dir1.EndCond := ecThroughAll;
    Check(C.Validate = '', 'corte passante valido');
    X.Dir1.EndCond := ecThroughAll;
    Check(X.Validate <> '', 'ressalto passante recusado (so existe no corte)');
    X.Dir1.EndCond := ecMidPlane;
    X.UseDir2 := True;
    Check(X.Validate <> '', 'Direcao 2 recusada com plano medio');
    X.UseDir2 := False;
    X.Dir1.EndCond := ecUpToSurface;
    Check(X.Validate <> '', 'ate a superficie sem referencia recusado');
    X.Dir1.Target := 'face:Ressalto-Extrusão1/fim';
    Check(X.Validate = '', 'ate a superficie com referencia valido');
    X.Dir1.EndCond := ecBlind;
    X.Dir1.Depth := 0;
    Check(X.Validate <> '', 'profundidade zero recusada');
    X.Dir1.Depth := 10;
    X.Dir1.Draft := 95;
    Check(X.Validate <> '', 'inclinacao de 95 graus recusada');
    X.Dir1.Draft := 5;
    X.Thin := True;
    X.ThinT1 := 0;
    Check(X.Validate <> '', 'recurso fino sem espessura recusado');
    X.ThinT1 := 2;
    X.Thin := False;
    X.Contours := ['region:1'];
    Check(X.Validate = '', 'ressalto com inclinacao e contorno valido');

    Check(D.Eval('D1@Esboço1 / 2', V, E) and Near(V, 40), 'expressao com cota do documento');
    Check(not D.Eval('D9@Esboço1', V, E), 'cota inexistente recusada');

    Check(D.ValidateAll = 0, 'documento sem erros');
    Check((Length(D.Dependents(S.Id)) = 2), 'ressalto e corte dependem do esboço');
    Check(not D.DeleteFeature(S.Id, E) and (E <> ''), 'nao exclui esboço usado');
    Check(not D.DeleteFeature(MCAD_ID_FRONTAL, E), 'nao exclui plano padrao');
    Check(Length(D.Dependents(MCAD_ID_FRONTAL)) = 3, 'dependencia indireta (plano -> esboço -> operacoes)');

    { JSON ida e volta }
    J1 := D.ToJSON;
    Check(D2.LoadFromJSON(J1, E), 'le o proprio JSON: ' + E);
    J2 := D2.ToJSON;
    Check(J1 = J2, 'JSON identico depois de ida e volta (Ids estaveis)');
    Check(D2.Count = D.Count, 'mesmo numero de operacoes');
    SetLength(Ids, D.Count);
    for I := 0 to D.Count - 1 do
      Ids[I] := D[I].Id;
    for I := 0 to D2.Count - 1 do
      Check(D2[I].Id = Ids[I], 'Id preservado: ' + D2[I].Name);
    Check(TCadExtrude(D2.FindByName('Ressalto-Extrusão1')).Dir1.Draft = 5, 'inclinacao preservada');
    Check(TCadExtrude(D2.FindByName('Corte-Extrusão1')).Dir1.EndCond = ecThroughAll, 'condicao preservada');
    Check(TCadSketch(D2.FindById(S.Id)).ConstraintCount = 10, 'restricoes e cotas preservadas');
    Check(D2.NextId = D.NextId, 'contador de Ids preservado');
    Check(D2.AddSketch().Id = D.NextId, 'novo Id continua do contador (nao reaproveita)');

    { arquivos invalidos nao alteram o documento aberto }
    I := D2.Count;
    Check(not D2.LoadFromJSON('{ isto nao e json', E) and (D2.Count = I), 'JSON quebrado recusado sem alterar');
    Check(not D2.LoadFromJSON('{"format":"outro","version":1,"features":[]}', E), 'formato errado recusado');
    Check(not D2.LoadFromJSON('{"format":"multicad","version":99,"features":[]}', E) and (Pos('99', E) > 0),
      'versao futura recusada com mensagem');
    Check(not D2.LoadFromJSON('{"format":"multicad","version":1,"features":[' +
      '{"id":1,"kind":"plane","params":{"type":"standard","std":"frontal"}},' +
      '{"id":1,"kind":"origin"}]}', E), 'Id repetido recusado');
    Check(not D2.LoadFromJSON('{"format":"multicad","version":1,"features":[' +
      '{"id":1,"kind":"teletransporte"}]}', E), 'tipo desconhecido recusado');
    Check(not D2.LoadFromJSON('{"format":"multicad","version":1,"features":[' +
      '{"id":5,"kind":"extrude","name":"X","params":{"sketch":2,"dir1":{"end":"voar"}}}]}', E) and
      (Pos('X', E) > 0), 'condicao final desconhecida recusada com o nome da operacao');
    Check(D2.Count = I, 'documento intacto depois das recusas');

    { referencia perdida vira erro na arvore, sem quebrar o arquivo }
    Check(D2.LoadFromJSON('{"format":"multicad","version":1,"next_id":3,"features":[' +
      '{"id":1,"kind":"plane","name":"Plano Frontal","params":{"type":"standard","std":"frontal"}},' +
      '{"id":2,"kind":"extrude","name":"Ressalto-Extrusão1","params":{"sketch":9,"dir1":{"end":"blind","depth":10}}}]}', E),
      'arquivo com referencia perdida abre: ' + E);
    Check((D2.ValidateAll = 1) and (D2.FindById(2).State = fsError), 'operacao com referencia perdida marcada com erro');

    { gravar e ler arquivo }
    Fn := GetTempDir + 'mcad_test_doc' + MCAD_EXT;
    Check(D.SaveToFile(Fn, E), 'grava .mcad: ' + E);
    Check(D.SaveToFile(Fn, E), 'regrava por cima');
    Check(not FileExists(Fn + '.tmp') and not FileExists(Fn + '.bak'), 'sem arquivos temporarios');
    Check(D2.LoadFromFile(Fn, E) and (D2.ToJSON = J1), 'le o arquivo gravado');
    Check(not D2.LoadFromFile(Fn + '.naoexiste', E), 'arquivo inexistente recusado');
    DeleteFile(Fn);

    { barra de retrocesso: operacao nova entra antes da barra }
    D.RollbackIndex := 5;
    S := D.AddSketch('plane:2');
    Check(D.IndexOfId(S.Id) = 5, 'operacao nova entra na barra de retrocesso');
    Check(D.RollbackIndex = 6, 'barra anda depois da insercao');
  finally
    D.Free;
    D2.Free;
  end;
end;

procedure TestPlanes;
var
  P: TCadPlane;
begin
  P := TCadPlane.Create;
  try
    P.PlaneType := ptOffset;
    Check(P.Validate <> '', 'plano deslocado sem referencia recusado');
    P.Refs := ['plane:1'];
    P.Distance := 0;
    Check(P.Validate <> '', 'deslocamento zero recusado');
    P.Distance := 25;
    Check(P.Validate = '', 'plano deslocado valido');
    Check((Length(P.Dependencies) = 1) and (P.Dependencies[0] = 1), 'plano depende do Plano Frontal');
    P.PlaneType := ptThreePoints;
    Check(P.Validate <> '', 'tres pontos com uma referencia recusado');
    Check(CadRefFeatureId('sketch:7/3') = 7, 'referencia sketch:7/3 aponta para a operacao 7');
    Check(CadRefFeatureId('face:Extrude2/topo') = 0, 'face nao aponta Id direto');
  finally
    P.Free;
  end;
end;

{ ---------- malha e nucleo ---------- }

procedure TestMesh;
var
  M, Cyl, M2: TCadMesh;
  E: string;
  MP: TCadMassProps;
  I, N: Integer;
  Exact: Double;
  K: ICadKernel;
  B: TCadBox3;
begin
  M := CadMakeBox(V3(0, 0, 0), V3(80, 50, 10), 'Base');
  try
    Check(M.VertCount = 8, 'bloco com 8 vertices soldados');
    Check(M.TriCount = 12, 'bloco com 12 triangulos');
    Check(M.FaceCount = 6, 'bloco com 6 faces rotuladas');
    Check(M.CheckClosed(E), 'bloco fechado: ' + E);
    Check(Near(M.Volume, 40000, 1E-6), 'volume do bloco 80x50x10');
    Check(Near(M.Area, 2 * (80 * 50 + 80 * 10 + 50 * 10), 1E-6), 'area do bloco');
    MP := M.MassProps;
    Check(NearV(MP.Centroid, V3(40, 25, 5), 1E-9), 'centro de massa do bloco');
    Check(Near(M.FaceArea(M.FaceIndex('Base/zmax')), 4000, 1E-9), 'area da face Base/zmax');
    Check(M.Faces[M.FaceIndex('Base/zmax')].Surf = skPlane, 'face plana rotulada');
    N := M.FaceIndex('Base/xmax');
    for I := 0 to M.TriCount - 1 do
      if M.Tris[I].Face = N then
        Check(NearV(M.TriNormal(I), V3(1, 0, 0)), 'normal para fora na face xmax');
    Check(Near(CadMassKg(CadMaterial(CadMaterialIndex('Aço 1045')), MP.Volume), 0.314, 1E-12),
      'massa do bloco de aço 1045 = 0,314 kg');

    { solda: vertice a menos de 0,001 mm e o mesmo }
    N := M.VertCount;
    Check(M.AddVertex(V3(80.0004, 50, 10)) < N, 'solda a menos da tolerancia');
    Check(M.AddVertex(V3(80.002, 50, 10)) = N, 'vertice novo fora da tolerancia');

    { malha aberta detectada }
    M2 := TCadMesh.Create;
    try
      I := M2.AddPlaneFace('A/f', V3(0, 0, 0), V3(0, 0, 1));
      M2.AddTriP(V3(0, 0, 0), V3(1, 0, 0), V3(0, 1, 0), I);
      Check(not M2.CheckClosed(E) and (Pos('aberta', E) > 0), 'malha aberta detectada');
      Check(not M2.AddTriP(V3(0, 0, 0), V3(0.0001, 0, 0), V3(0, 1, 0), I), 'triangulo degenerado ignorado');
    finally
      M2.Free;
    end;

    { transformacao mantem volume e nomes }
    M.Transform(MatMul(MatTranslate(10, 0, 0), MatRotate(V3(0, 1, 0), 30)));
    Check(Near(M.Volume, 40000, 1E-6) and M.IsClosed, 'transformacao rigida mantem volume');
    Check(M.FaceIndex('Base/zmax') >= 0, 'nomes mantidos');
    M.Flip;
    Check(Near(M.Volume, -40000, 1E-6), 'inverter orientacao troca o sinal do volume');
  finally
    M.Free;
  end;

  Cyl := CadMakeCylinder(V3(0, 0, 0), V3(0, 1, 0), 10, 30, 'Rev1');
  try
    Check(Cyl.CheckClosed(E), 'cilindro fechado: ' + E);
    Exact := Pi * 100 * 30;
    Check(Abs(Cyl.Volume - Exact) / Exact < 0.005, Format('volume do cilindro dentro de 0,5%% (%.1f x %.1f)', [Cyl.Volume, Exact]));
    Check(Cyl.Faces[Cyl.FaceIndex('Rev1/cil')].Surf = skCylinder, 'face cilindrica rotulada');
    Check(Near(Cyl.Faces[Cyl.FaceIndex('Rev1/cil')].Radius, 10), 'raio guardado na face');
    B := Cyl.Bounds;
    Check(Near(B.Max.Y, 30, 1E-9) and Near(B.Min.Y, 0, 1E-9), 'cilindro ao longo de Y');
    MP := Cyl.MassProps;
    Check(NearV(MP.Centroid, V3(0, 15, 0), 1E-6), 'centro de massa do cilindro');
  finally
    Cyl.Free;
  end;
  Check(CadCircleSegments(10) mod 4 = 0, 'segmentos do circulo multiplos de 4');
  Check(CadCircleSegments(100) > CadCircleSegments(1), 'mais segmentos em raio maior');

  K := CadKernel;
  Check(kcPrimitives in K.Capabilities, 'nucleo Pascal com primitivas');
  Check(not (kcStep in K.Capabilities), 'STEP so com OpenCascade');
  M := K.MakeBox(V3(0, 0, 0), V3(10, 10, 10), 'B');
  try
    Check(K.CheckSolid(M, E), 'nucleo aceita o bloco');
    M.Flip;
    Check(not K.CheckSolid(M, E), 'nucleo recusa solido invertido');
  finally
    M.Free;
  end;
end;

begin
  Passed := 0;
  Failed := 0;
  TestFrames;
  TestUnits;
  TestMaterials;
  TestDocument;
  TestPlanes;
  TestMesh;
  Writeln(Format('MultiCAD: %d checks, %d falhas', [Passed + Failed, Failed]));
  if Failed > 0 then
    Halt(1);
  Writeln('MultiCAD: OK');
end.
