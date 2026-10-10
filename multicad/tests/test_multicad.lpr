program test_multicad;

{ MultiCAD - testes do nucleo (sem LCL). Fase 0: tipos e planos, unidades e
  expressoes, materiais, Ids persistentes, JSON .mcad, validacao das
  operacoes, malha rotulada (solda, malha fechada, volume) e ICadKernel. }

{$mode objfpc}{$H+}

uses
  SysUtils, Classes, Math, multicad_types, multicad_units, multicad_materials,
  multicad_feature, multicad_refgeom, multicad_sketch, multicad_extrude,
  multicad_document, multicad_mesh, multicad_kernel, multicad_solver,
  multicad_profile, multicad_triangulate, multicad_sweep, multicad_bridge, multicad_csg, multicad_revolve, multicad_rebuild,
  multicad_camera, multicad_softrender, multicad_sketchtools;

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


{ ---------- fase 1: solver ---------- }

function Ent(S: TCadSketch; AId: Integer): TSketchEntity;
begin
  Result := S.Entity(S.EntityIndex(AId));
end;

function LenOf(const E: TSketchEntity): Double;
begin
  Result := Sqrt(Sqr(E.P2.X - E.P1.X) + Sqr(E.P2.Y - E.P1.Y));
end;

function NearP(const A, B: TCadVec2; Tol: Double = 1E-6): Boolean;
begin
  Result := (Abs(A.X - B.X) <= Tol) and (Abs(A.Y - B.Y) <= Tol);
end;

{ Retangulo 80 x 50 com canto na origem, desenhado torto de proposito. }
function MakeBracketSketch(out L1: Integer): TCadSketch;
var
  S: TCadSketch;
begin
  S := TCadSketch.Create;
  S.Name := 'Esboço1';
  L1 := S.AddRectangle(0.3, -0.2, 71, 44);
  S.AddConstraint(ckCoincident, L1, 1, CAD_SKETCH_ORIGIN, 1);
  S.AddDimension(ckHorizontalDistance, L1, 0, 0, 0, 80);   { D1 }
  S.AddDimension(ckVerticalDistance, L1 + 1, 0, 0, 0, 50); { D2 }
  Result := S;
end;

procedure TestSolver;
var
  S: TCadSketch;
  R: TSketchSolveResult;
  L1, C, Ln, A, P, I, Dm: Integer;
  E, E0: TSketchEntity;
  V: Double;
  D: TCadDocument;
  Fn, Err: string;
  T0: QWord;
begin
  { retangulo totalmente definido }
  S := MakeBracketSketch(L1);
  try
    R := CadAnalyzeSketch(S);
    Check(not R.Converged, 'desenho torto ainda nao atende as cotas');
    R := CadSolveSketch(S);
    Check(R.Converged, 'retangulo converge: ' + R.Message);
    Check(R.Status = ssFullyDefined, 'retangulo com canto na origem e duas cotas: totalmente definido (' +
      CAD_SKETCH_STATUS_NAMES[R.Status] + ')');
    Check(R.DOF = 0, 'zero graus de liberdade');
    Check(NearP(Ent(S, L1).P1, V2(0, 0)) and NearP(Ent(S, L1).P2, V2(80, 0)) and
      NearP(Ent(S, L1 + 2).P1, V2(80, 50)), 'cantos em (0,0), (80,0), (80,50)');
    for I := 0 to S.EntityCount - 1 do
      Check(R.EntityState[I] = esDefined, 'linha preta (definida) ' + IntToStr(I));
    Check(R.Message = 'Totalmente definido', 'mensagem de totalmente definido');

    { mudar a cota: so o lado direito anda }
    E0 := Ent(S, L1 + 3);
    Check(S.SetDimension('D1', 100), 'muda D1 para 100');
    R := CadSolveSketch(S);
    Check(R.Converged and NearP(Ent(S, L1).P2, V2(100, 0)) and NearP(Ent(S, L1 + 2).P1, V2(100, 50)),
      'base passa para 100 mm');
    Check(NearP(Ent(S, L1 + 3).P1, E0.P1) and NearP(Ent(S, L1 + 3).P2, E0.P2), 'lado esquerdo nao se mexe');
    Check(Near(LenOf(Ent(S, L1 + 1)), 50, 1E-6), 'altura continua 50');

    { cota redundante: superdefinido }
    S.AddDimension(ckHorizontalDistance, L1 + 2, 0, 0, 0, 100);
    R := CadSolveSketch(S);
    Check(R.Status = ssOverDefined, 'cota repetida deixa superdefinido');
    Check(R.ConstraintState[S.ConstraintCount - 1] = csRedundant, 'a cota repetida aparece como redundante');
    { tornar a cota dirigida resolve e mede }
    S.SetConstraintDriving(S.ConstraintCount - 1, False);
    R := CadSolveSketch(S);
    Check(R.Status = ssFullyDefined, 'cota dirigida tira o superdefinido');
    Check(Near(S.Constraint(S.ConstraintCount - 1).Value, 100, 1E-6), 'cota dirigida mostra o valor medido');

    { conflito: altura 50 de um lado e 60 do outro }
    E0 := Ent(S, L1 + 1);
    S.AddDimension(ckVerticalDistance, L1 + 3, 0, 0, 0, 60);
    R := CadSolveSketch(S);
    Check(R.Status = ssConflict, 'cotas incompatíveis = conflito');
    Check(not R.Converged and (R.Message <> ''), 'mensagem de conflito');
    Check(NearP(Ent(S, L1 + 1).P1, E0.P1) and NearP(Ent(S, L1 + 1).P2, E0.P2), 'conflito nao deforma o esboço');
    Check(R.ConstraintState[S.ConstraintCount - 1] = csConflict, 'cota em conflito marcada');
    Check(R.EntityState[S.EntityIndex(L1 + 3)] = esProblem, 'linha da cota em conflito em vermelho');
  finally
    S.Free;
  end;

  { sem ancorar na origem: so translacao livre }
  S := TCadSketch.Create;
  try
    L1 := S.AddRectangle(5, 5, 45, 25);
    S.AddDimension(ckDistance, L1, 0, 0, 0, 40);
    S.AddDimension(ckDistance, L1 + 1, 0, 0, 0, 20);
    R := CadSolveSketch(S);
    Check((R.Status = ssUnderDefined) and (R.DOF = 2), Format('retangulo cotado e solto: 2 GL (%d)', [R.DOF]));
    Check(R.EntityState[0] = esFree, 'linha azul (livre)');
    Check(Pos('2 grau', R.Message) > 0, 'mensagem com os graus de liberdade');
  finally
    S.Free;
  end;

  { tangencia linha-circulo }
  S := TCadSketch.Create;
  try
    Ln := S.AddLine(0, 0, 60, 0);
    S.AddFixed(Ln, 0);
    C := S.AddCircle(20, 13, 10);
    S.AddConstraint(ckTangent, Ln, 0, C, 0);
    R := CadSolveSketch(S);
    E := Ent(S, C);
    Check(R.Converged and Near(Abs(E.P1.Y), E.Radius, 1E-7), 'circulo tangente a linha (distancia = raio)');
    Check(NearP(Ent(S, Ln).P1, V2(0, 0)) and NearP(Ent(S, Ln).P2, V2(60, 0)), 'linha fixa nao se mexe');
    S.AddDimension(ckDiameter, C, 0, 0, 0, 30);
    R := CadSolveSketch(S);
    E := Ent(S, C);
    Check(R.Converged and Near(E.Radius, 15, 1E-7) and Near(E.P1.Y, 15, 1E-7), 'diametro 30 tangente por cima');
    Check(R.DOF = 1, 'circulo tangente com diametro: 1 GL (desliza na linha)');
  finally
    S.Free;
  end;

  { paralela, perpendicular, igual, angulo, ponto medio, concentrica, simetrica }
  S := TCadSketch.Create;
  try
    L1 := S.AddLine(0, 0, 50, 3);
    Ln := S.AddLine(0, 20, 40, 28);
    S.AddConstraint(ckParallel, L1, 0, Ln, 0);
    S.AddConstraint(ckEqual, L1, 0, Ln, 0);
    R := CadSolveSketch(S);
    E := Ent(S, L1);
    E0 := Ent(S, Ln);
    Check(R.Converged and Near((E.P2.X - E.P1.X) * (E0.P2.Y - E0.P1.Y) - (E.P2.Y - E.P1.Y) * (E0.P2.X - E0.P1.X), 0, 1E-6),
      'linhas paralelas');
    Check(Near(LenOf(E), LenOf(E0), 1E-7), 'linhas iguais');
    A := S.AddLine(60, 0, 70, 30);
    S.AddConstraint(ckPerpendicular, L1, 0, A, 0);
    R := CadSolveSketch(S);
    E := Ent(S, L1);
    E0 := Ent(S, A);
    Check(R.Converged and Near((E.P2.X - E.P1.X) * (E0.P2.X - E0.P1.X) + (E.P2.Y - E.P1.Y) * (E0.P2.Y - E0.P1.Y), 0, 1E-6),
      'linhas perpendiculares');
    Dm := S.AddDimension(ckAngle, L1, 0, Ln, 0, 0);
    S.DeleteConstraint(Dm);
    Ln := S.AddLine(0, 50, 30, 52);
    S.AddConstraint(ckHorizontal, L1, 0, 0, 0);
    S.AddDimension(ckAngle, L1, 0, Ln, 0, 30);
    R := CadSolveSketch(S);
    E := Ent(S, Ln);
    Check(R.Converged and Near(RadToDegC(ArcTan2(E.P2.Y - E.P1.Y, E.P2.X - E.P1.X)), 30, 1E-6),
      'cota angular de 30 graus');
    Check(CadMeasureDimension(S, S.ConstraintCount - 1, V) and Near(V, 30, 1E-6), 'angulo medido 30');
    P := S.AddPoint(3, 7);
    S.AddConstraint(ckMidpoint, P, 0, L1, 0);
    R := CadSolveSketch(S);
    E := Ent(S, L1);
    Check(R.Converged and NearP(Ent(S, P).P1, V2((E.P1.X + E.P2.X) / 2, (E.P1.Y + E.P2.Y) / 2)), 'ponto medio');
  finally
    S.Free;
  end;

  S := TCadSketch.Create;
  try
    C := S.AddCircle(0, 0, 20);
    A := S.AddCircle(3, -2, 8);
    S.AddConstraint(ckConcentric, C, 0, A, 0);
    R := CadSolveSketch(S);
    Check(R.Converged and NearP(Ent(S, C).P1, Ent(S, A).P1), 'circulos concentricos');
    Ln := S.AddCenterline(0, -50, 0, 50);
    S.AddConstraint(ckVertical, Ln, 0, 0, 0);
    S.AddConstraint(ckCoincident, Ln, 1, CAD_SKETCH_ORIGIN, 1);
    P := S.AddPoint(-10, 4);
    I := S.AddPoint(13, 9);
    S.AddSymmetric(P, 0, I, 0, Ln);
    R := CadSolveSketch(S);
    Check(R.Converged and Near(Ent(S, P).P1.X, -Ent(S, I).P1.X, 1E-7) and Near(Ent(S, P).P1.Y, Ent(S, I).P1.Y, 1E-7),
      'pontos simetricos pela linha de centro');
    Check(Ent(S, Ln).Centerline and Ent(S, Ln).Construction, 'linha de centro e construcao');
  finally
    S.Free;
  end;

  { ranhura e poligono }
  S := TCadSketch.Create;
  try
    L1 := S.AddSlot(0, 0, 40, 0, 10);
    R := CadSolveSketch(S);
    Check(R.Converged and (R.Status = ssUnderDefined), 'ranhura consistente: ' + R.Message);
    Check(R.DOF = 5, Format('ranhura livre com 5 GL (%d)', [R.DOF]));
    C := S.AddPolygon(100, 0, 20, 6);
    R := CadSolveSketch(S);
    Check(R.Converged and (R.DOF = 5 + 4), Format('hexagono soma 4 GL (%d)', [R.DOF]));
    Check(Near(LenOf(Ent(S, C + 1)), 20, 1E-6), 'lado do hexagono = raio');
  finally
    S.Free;
  end;

  { arco por tres pontos e tangente linha-arco }
  S := TCadSketch.Create;
  try
    A := S.AddArc3P(10, 0, 0, 10, -10, 0);
    E := Ent(S, A);
    Check((A > 0) and NearP(E.P1, V2(0, 0), 1E-9) and Near(E.Radius, 10, 1E-9), 'arco por tres pontos');
    Check(NearP(E.P2, V2(10, 0), 1E-9), 'arco anti-horario comeca no primeiro ponto');
    Check(S.AddArc3P(0, 0, 1, 1, 2, 2) = 0, 'tres pontos colineares recusados');
  finally
    S.Free;
  end;

  { desempenho: poligono de 40 lados }
  S := TCadSketch.Create;
  try
    S.AddPolygon(0, 0, 50, 40);
    T0 := GetTickCount64;
    R := CadSolveSketch(S);
    Check(R.Converged and (R.DOF = 4), 'poligono de 40 lados resolvido');
    Check(GetTickCount64 - T0 < 5000, Format('poligono de 40 lados em menos de 5 s (%d ms)', [GetTickCount64 - T0]));
  finally
    S.Free;
  end;

  { documento: expressao entre cotas, JSON com os campos novos }
  D := TCadDocument.Create;
  try
    S := D.AddSketch('plane:1');
    L1 := S.AddRectangle(0, 0, 70, 45);
    S.AddConstraint(ckCoincident, L1, 1, CAD_SKETCH_ORIGIN, 1);
    S.AddDimension(ckHorizontalDistance, L1, 0, 0, 0, 80);
    I := S.ConstraintCount;
    S.AddDimension(ckVerticalDistance, L1 + 1, 0, 0, 0, 10);
    S.SetConstraintExpr(I, 'D1@Esboço1 / 2');
    S.AddSymmetric(L1, 1, L1, 2, L1 + 3);
    S.DeleteConstraint(S.Constraint(S.ConstraintCount - 1).Id);
    S.AddFixed(L1 + 2, 2);
    S.DeleteConstraint(S.Constraint(S.ConstraintCount - 1).Id);
    R := D.SolveSketch(S);
    Check(R.Status = ssFullyDefined, 'documento: esboço totalmente definido');
    Check(Near(S.Constraint(I).Value, 40, 1E-12) and Near(LenOf(Ent(S, L1 + 1)), 40, 1E-6),
      'D2 = D1@Esboço1 / 2 = 40');
    S.SetDimension('D1', 120);
    R := D.SolveSketch(S);
    Check(Near(LenOf(Ent(S, L1 + 1)), 60, 1E-6), 'mudar D1 atualiza D2 pela expressao');
    S.SetConstraintExpr(I, 'D7@Esboço1');
    R := D.SolveSketch(S);
    Check((R.Status = ssConflict) and (S.State = fsError) and (Pos('D2', S.Message) > 0),
      'expressao com cota inexistente marca erro no esboço');
    S.SetConstraintExpr(I, '');
    S.AddCenterline(0, 0, 0, 10);
    S.AddSymmetric(L1, 1, L1, 2, S.Entity(S.EntityCount - 1).Id);
    S.AddFixed(L1, 0);
    Fn := D.ToJSON;
    D.LoadFromJSON(Fn, Err);
    Check(D.ToJSON = Fn, 'JSON com linha de centro, simetrica e fixa identico na ida e volta');
    S := TCadSketch(D.FindByName('Esboço1'));
    Check(S.Entity(S.EntityCount - 1).Centerline, 'linha de centro preservada');
    Check(S.Constraint(S.ConstraintCount - 2).EntityC = S.Entity(S.EntityCount - 1).Id, 'terceira referencia preservada');
    Check(Length(S.Constraint(S.ConstraintCount - 1).Fix) = 4, 'valores da fixa preservados');
    Check(D.SolveAllSketches >= 0, 'resolve todos os esboços');
  finally
    D.Free;
  end;
end;

{ ---------- fase 1: perfis ---------- }

procedure TestProfiles;
var
  S: TCadSketch;
  P: TCadProfileResult;
  L1, C, Pt, I, K: Integer;
  Found: Boolean;
begin
  { retangulo com furo }
  S := TCadSketch.Create;
  try
    L1 := S.AddRectangle(0, 0, 80, 50);
    C := S.AddCircle(20, 25, 4);
    P := CadSketchProfiles(S, 0.001);
    Check(P.Ok, 'perfil do retangulo com furo: ' + P.Message);
    Check(Length(P.Regions) = 1, 'uma regiao');
    Check(Length(P.Regions[0].Holes) = 1, 'com uma ilha (furo)');
    Check(Abs(P.Regions[0].Area - (4000 - Pi * 16)) < 0.05, Format('area liquida 4000 - pi 16 (%.4f)', [P.Regions[0].Area]));
    Check(P.Regions[0].Outer.Area > 0, 'externo anti-horario');
    Check(P.Regions[0].Holes[0].Area < 0, 'ilha horaria');
    Check(P.Regions[0].Id = 'region:' + IntToStr(L1), 'Id da regiao pela menor entidade');
    Check(Length(P.Regions[0].Outer.Edges) = 4, 'laco externo com 4 entidades');
    Found := True;
    for I := 0 to High(P.Regions[0].Outer.SegEntity) do
      if (P.Regions[0].Outer.SegEntity[I] < L1) or (P.Regions[0].Outer.SegEntity[I] > L1 + 3) then
        Found := False;
    Check(Found, 'cada segmento sabe de que linha veio (nome da face lateral)');
    Check(P.Regions[0].Holes[0].SegEntity[0] = C, 'segmentos do furo apontam para o circulo');
    Check(CadFindRegion(P, 'region:' + IntToStr(L1)) = 0, 'busca da regiao pelo Id');

    { ilha dentro da ilha vira outra regiao }
    S.AddCircle(20, 25, 2);
    P := CadSketchProfiles(S, 0.001);
    Check(P.Ok and (Length(P.Regions) = 2), 'circulo dentro do furo vira segunda regiao');

    { construcao nao entra }
    S.AddLine(-10, -10, 90, 60, True);
    P := CadSketchProfiles(S);
    Check(P.Ok, 'linha de construcao ignorada');
  finally
    S.Free;
  end;

  { contorno aberto }
  S := TCadSketch.Create;
  try
    S.AddLine(0, 0, 50, 0);
    S.AddLine(50, 0, 50, 30);
    S.AddLine(50, 30, 0, 30);
    P := CadSketchProfiles(S);
    Check(not P.Ok and (Length(P.OpenPoints) = 2), 'contorno aberto: 2 extremidades soltas');
    Check(Pos('abertos', P.Message) > 0, 'mensagem "contornos abertos"');
  finally
    S.Free;
  end;

  { ramificacao }
  S := TCadSketch.Create;
  try
    S.AddRectangle(0, 0, 40, 40);
    S.AddLine(0, 0, 40, 40);
    P := CadSketchProfiles(S);
    Check(not P.Ok and (Length(P.BranchPoints) = 2), 'diagonal no retangulo: 2 pontos de ramificacao');
  finally
    S.Free;
  end;

  { contornos que se cruzam }
  S := TCadSketch.Create;
  try
    S.AddRectangle(0, 0, 40, 40);
    S.AddCircle(40, 20, 5);
    P := CadSketchProfiles(S);
    Check(not P.Ok and (Pos('cruzam', P.Message) > 0), 'circulo cruzando o retangulo recusado');
  finally
    S.Free;
  end;

  { ranhura: linhas + arcos }
  S := TCadSketch.Create;
  try
    L1 := S.AddSlot(0, 0, 40, 0, 10);
    P := CadSketchProfiles(S, 0.0005);
    Check(P.Ok and (Length(P.Regions) = 1), 'ranhura e um contorno fechado: ' + P.Message);
    Check(Abs(P.Regions[0].Area - (40 * 10 + Pi * 25)) < 0.05, Format('area da ranhura (%.4f)', [P.Regions[0].Area]));
    K := 0;
    for I := 0 to High(P.Regions[0].Outer.Edges) do
      if P.Regions[0].Outer.Edges[I].Reversed then
        Inc(K);
    Check(Length(P.Regions[0].Outer.Edges) = 4, 'ranhura com 4 entidades no laco');
  finally
    S.Free;
  end;

  { retangulo desenhado no sentido horario vira anti-horario }
  S := TCadSketch.Create;
  try
    S.AddLine(0, 0, 0, 30);
    S.AddLine(0, 30, 50, 30);
    S.AddLine(50, 30, 50, 0);
    S.AddLine(50, 0, 0, 0);
    Pt := S.AddPoint(10, 10);
    P := CadSketchProfiles(S);
    Check(P.Ok and Near(P.Regions[0].Area, 1500, 1E-9), 'laco horario reorientado, area 1500');
    Check(P.Regions[0].Outer.Edges[0].Reversed, 'arestas marcadas como percorridas ao contrario');
    Check(Pt > 0, 'ponto solto nao atrapalha o perfil');
  finally
    S.Free;
  end;

  S := TCadSketch.Create;
  try
    P := CadSketchProfiles(S);
    Check(not P.Ok and (P.Message <> ''), 'esboço vazio sem perfil');
  finally
    S.Free;
  end;
end;

{ ---------- fase 2A: triangulacao e varredura ---------- }

function SketchRegion(S: TCadSketch; ChordTol: Double = 0.002): TCadSweepRegion;
var
  P: TCadProfileResult;
begin
  P := CadSketchProfiles(S, ChordTol);
  if not P.Ok then
    raise Exception.Create('perfil invalido no teste: ' + P.Message);
  Result := CadRegionToSweep(P.Regions[0]);
end;

function RelNear(A, B, Rel: Double): Boolean;
begin
  Result := Abs(A - B) <= Rel * Abs(B);
end;

procedure TestSweep;
var
  Outer: TCadPoly2;
  Holes: TCadPoly2Array;
  Pts: TCadPoly2;
  Tris: TCadTriIdxArray;
  E: string;
  I, L1, C: Integer;
  A, A1, A2, Dl, Exact: Double;
  S: TCadSketch;
  M: TCadMesh;
  R: TCadSweepRegion;
  B: TCadBox3;
  F: Integer;
  Off: TCadPoly2;
begin
  { triangulacao com furo }
  Outer := [V2(0, 0), V2(10, 0), V2(10, 10), V2(0, 10)];
  SetLength(Holes, 1);
  Holes[0] := [V2(3, 3), V2(3, 7), V2(7, 7), V2(7, 3)];
  Check(CadTriangulate(Outer, Holes, Pts, Tris, E), 'triangula quadrado com furo: ' + E);
  A := 0;
  for I := 0 to High(Tris) do
  begin
    A1 := ((Pts[Tris[I].B].X - Pts[Tris[I].A].X) * (Pts[Tris[I].C].Y - Pts[Tris[I].A].Y) -
      (Pts[Tris[I].B].Y - Pts[Tris[I].A].Y) * (Pts[Tris[I].C].X - Pts[Tris[I].A].X)) / 2;
    Check(A1 > 0, 'triangulo anti-horario');
    A := A + A1;
  end;
  Check(Near(A, 100 - 16, 1E-9), Format('soma das areas = 84 (%.6f)', [A]));
  Check(Length(Tris) = 8, Format('8 triangulos (%d)', [Length(Tris)]));
  Outer := [V2(0, 0), V2(10, 0), V2(10, 4), V2(5, 1), V2(0, 4)];
  Check(CadTriangulate(Outer, nil, Pts, Tris, E) and (Length(Tris) = 3), 'poligono concavo');
  Check(not CadTriangulate([V2(0, 0), V2(1, 1), V2(2, 2)], nil, Pts, Tris, E), 'area nula recusada');

  { offset }
  Check(CadOffsetLoop([V2(0, 0), V2(10, 0), V2(10, 10), V2(0, 10)], 1, Off) and
    NearP(Off[0], V2(1, 1), 1E-12) and NearP(Off[2], V2(9, 9), 1E-12), 'offset para dentro em esquadria');
  Check(not CadOffsetLoop([V2(0, 0), V2(10, 0), V2(10, 10), V2(0, 10)], 6, Off), 'offset maior que a metade recusado');

  { extrusao simples no Plano Frontal }
  S := TCadSketch.Create;
  try
    L1 := S.AddRectangle(0, 0, 80, 50);
    R := SketchRegion(S);
    M := CadSweepExtrude(StdFrame(spFrontal), R, CadSketchSurfaces(S), V3(0, 0, 1), 0, 10, 0, False, 'Ext1', E);
    try
      Check(M <> nil, 'extrusao do retangulo: ' + E);
      Check(M.IsClosed and Near(M.Volume, 40000, 1E-6), 'bloco 80x50x10 fechado com 40000 mm3');
      Check(M.FaceCount = 6, Format('6 faces (%d)', [M.FaceCount]));
      Check((M.FaceIndex('Ext1/inicio') >= 0) and (M.FaceIndex('Ext1/fim') >= 0), 'faces inicio e fim');
      for I := 0 to 3 do
        Check(M.FaceIndex('Ext1/lat:' + IntToStr(L1 + I)) >= 0, 'face lateral da linha ' + IntToStr(L1 + I));
      F := M.FaceIndex('Ext1/lat:' + IntToStr(L1));
      Check(NearV(M.Faces[F].Axis, V3(0, -1, 0), 1E-9), 'lateral da linha inferior com normal -Y');
      Check(NearV(M.Faces[M.FaceIndex('Ext1/fim')].Axis, V3(0, 0, 1), 1E-9), 'tampa do fim com normal +Z');
      B := M.Bounds;
      Check(Near(B.Min.Z, 0, 1E-9) and Near(B.Max.Z, 10, 1E-9), 'Z de 0 a 10');
    finally
      M.Free;
    end;
    { sentido contrario }
    M := CadSweepExtrude(StdFrame(spFrontal), R, nil, V3(0, 0, -1), 0, 10, 0, False, 'Ext1', E);
    try
      B := M.Bounds;
      Check((M <> nil) and M.IsClosed and Near(M.Volume, 40000, 1E-6) and Near(B.Min.Z, -10, 1E-9),
        'extrusao invertida fechada e com volume positivo');
      Check(NearV(M.Faces[M.FaceIndex('Ext1/fim')].Axis, V3(0, 0, -1), 1E-9), 'fim invertido aponta para -Z');
    finally
      M.Free;
    end;
    { deslocamento do inicio }
    M := CadSweepExtrude(StdFrame(spFrontal), R, nil, V3(0, 0, 1), 5, 10, 0, False, 'Ext1', E);
    try
      B := M.Bounds;
      Check(Near(B.Min.Z, 5, 1E-9) and Near(B.Max.Z, 15, 1E-9), 'inicio deslocado 5 mm');
    finally
      M.Free;
    end;
    { plano Superior e Lateral }
    M := CadSweepExtrude(StdFrame(spSuperior), R, nil, StdFrame(spSuperior).Normal, 0, 10, 0, False, 'E', E);
    try
      B := M.Bounds;
      Check(M.IsClosed and Near(B.Max.Y, 10, 1E-9) and Near(B.Min.Z, -50, 1E-9), 'Superior: sobe em Y, desenho em -Z');
    finally
      M.Free;
    end;
    M := CadSweepExtrude(StdFrame(spLateral), R, nil, StdFrame(spLateral).Normal, 0, 10, 0, False, 'E', E);
    try
      B := M.Bounds;
      Check(M.IsClosed and Near(B.Max.X, 10, 1E-9) and Near(B.Min.Z, -80, 1E-9), 'Lateral: sai em X, desenho em -Z');
    finally
      M.Free;
    end;
    { direcao obliqua }
    M := CadSweepExtrude(StdFrame(spFrontal), R, nil, VNorm(V3(1, 0, 1)), 0, 10, 0, False, 'E', E);
    try
      Check(M.IsClosed and RelNear(M.Volume, 4000 * 10 / Sqrt(2), 1E-9), 'extrusao obliqua: area x altura');
    finally
      M.Free;
    end;
    { inclinacao: tronco de piramide }
    M := CadSweepExtrude(StdFrame(spFrontal), R, CadSketchSurfaces(S), V3(0, 0, 1), 0, 10, 5, False, 'E', E);
    try
      Dl := 10 * Tan(5 * Pi / 180);
      { cada lado encolhe 2.Dl linearmente: integral de (80-2Dl.t/h)(50-2Dl.t/h) }
      Exact := 10 * (80 * 50 - Dl * (80 + 50) + 4 / 3 * Dl * Dl);
      Check((M <> nil) and M.IsClosed and RelNear(M.Volume, Exact, 1E-9),
        Format('inclinacao de 5 graus: volume do tronco (%.4f x %.4f)', [M.Volume, Exact]));
    finally
      M.Free;
    end;
    M := CadSweepExtrude(StdFrame(spFrontal), R, nil, V3(0, 0, 1), 0, 10, 5, True, 'E', E);
    try
      Check((M <> nil) and (M.Volume > 40000), 'inclinacao para fora aumenta o volume');
    finally
      M.Free;
    end;
    M := CadSweepExtrude(StdFrame(spFrontal), R, nil, V3(0, 0, 1), 0, 300, 10, False, 'E', E);
    Check((M = nil) and (Pos('inclinação muito grande', E) > 0), 'inclinacao grande demais recusada');
    M := CadSweepExtrude(StdFrame(spFrontal), R, nil, V3(1, 0, 0), 0, 10, 0, False, 'E', E);
    Check(M = nil, 'direcao paralela ao plano recusada');
    { com furo }
    C := S.AddCircle(20, 25, 4);
    R := SketchRegion(S, 0.001);
    M := CadSweepExtrude(StdFrame(spFrontal), R, CadSketchSurfaces(S), V3(0, 0, 1), 0, 10, 0, False, 'Ext1', E);
    try
      Exact := (4000 - Pi * 16) * 10;
      Check((M <> nil) and M.IsClosed and RelNear(M.Volume, Exact, 0.005),
        Format('placa com furo dentro de 0,5%% (%.2f x %.2f)', [M.Volume, Exact]));
      F := M.FaceIndex('Ext1/lat:' + IntToStr(C));
      Check((F >= 0) and (M.Faces[F].Surf = skCylinder) and Near(M.Faces[F].Radius, 4), 'furo vira face cilindrica de raio 4');
    finally
      M.Free;
    end;
  finally
    S.Free;
  end;

  { revolucao: tubo }
  S := TCadSketch.Create;
  try
    S.AddRectangle(10, 0, 20, 30);
    R := SketchRegion(S);
    M := CadSweepRevolve(StdFrame(spFrontal), R, CadSketchSurfaces(S), V2(0, 0), V2(0, 1), 0, 360, 'Rev1', E);
    try
      Exact := Pi * (400 - 100) * 30;
      Check((M <> nil) and M.IsClosed and RelNear(M.Volume, Exact, 0.005),
        Format('tubo revolucionado dentro de 0,5%% (%.1f x %.1f)', [M.Volume, Exact]));
      Check(M.FaceIndex('Rev1/inicio') < 0, '360 graus sem tampas');
      F := M.FaceIndex('Rev1/rev:' + IntToStr(S.Entity(1).Id));
      Check((F >= 0) and (M.Faces[F].Surf = skCylinder) and Near(M.Faces[F].Radius, 20, 1E-9), 'parede externa cilindrica r=20');
      F := M.FaceIndex('Rev1/rev:' + IntToStr(S.Entity(0).Id));
      Check((F >= 0) and (M.Faces[F].Surf = skPlane), 'base plana');
      B := M.Bounds;
      Check(Near(B.Max.Y, 30, 1E-9) and Near(B.Min.Y, 0, 1E-9), 'tubo ao longo de Y');
    finally
      M.Free;
    end;
    M := CadSweepRevolve(StdFrame(spFrontal), R, nil, V2(0, 0), V2(0, 1), 0, 90, 'Rev1', E);
    try
      Check((M <> nil) and M.IsClosed and RelNear(M.Volume, Exact / 4, 0.005), 'um quarto de tubo: ' + E);
      Check((M.FaceIndex('Rev1/inicio') >= 0) and (M.FaceIndex('Rev1/fim') >= 0), '90 graus com tampas');
    finally
      M.Free;
    end;
    M := CadSweepRevolve(StdFrame(spFrontal), R, nil, V2(0, 0), V2(0, -1), 0, 90, 'Rev1', E);
    try
      Check((M <> nil) and M.IsClosed and (M.Volume > 0), 'eixo invertido tambem fecha');
    finally
      M.Free;
    end;
    M := CadSweepRevolve(StdFrame(spFrontal), R, nil, V2(15, 0), V2(15, 1), 0, 360, 'Rev1', E);
    Check((M = nil) and (Pos('cruza o eixo', E) > 0), 'perfil cruzando o eixo recusado');
  finally
    S.Free;
  end;

  { toro }
  S := TCadSketch.Create;
  try
    S.AddCircle(20, 0, 5);
    R := SketchRegion(S, 0.001);
    M := CadSweepRevolve(StdFrame(spSuperior), R, CadSketchSurfaces(S), V2(0, -10), V2(0, 10), 0, 360, 'Toro', E);
    try
      Exact := 2 * Pi * Pi * 20 * 25;
      Check((M <> nil) and M.IsClosed and RelNear(M.Volume, Exact, 0.005),
        Format('toro dentro de 0,5%% (%.1f x %.1f)', [M.Volume, Exact]));
      Check(M.Faces[0].Surf = skTorus, 'face toroidal rotulada');
    finally
      M.Free;
    end;
  finally
    S.Free;
  end;

  { ranhura extrudada }
  S := TCadSketch.Create;
  try
    S.AddSlot(0, 0, 40, 0, 10);
    R := SketchRegion(S, 0.0005);
    M := CadSweepExtrude(StdFrame(spFrontal), R, CadSketchSurfaces(S), V3(0, 0, 1), 0, 6, 0, False, 'Ras', E);
    try
      Check((M <> nil) and M.IsClosed and RelNear(M.Volume, (400 + Pi * 25) * 6, 0.005), 'ranhura extrudada');
      Check(M.FaceCount = 6, 'ranhura: 2 tampas + 2 planas + 2 cilindricas');
    finally
      M.Free;
    end;
  finally
    S.Free;
  end;
end;

{ ---------- fase 2B: booleanas ---------- }

procedure TestCSG;
var
  A, B, R, C, Cyl: TCadMesh;
  E: string;
  Parts: TList;
  I: Integer;
  T0: QWord;
  Exact, V0: Double;
  procedure FreeAll;
  begin
    FreeAndNil(B);
    FreeAndNil(R);
  end;
begin
  B := nil; R := nil;
  A := CadMakeBox(V3(0, 0, 0), V3(80, 50, 10), 'Base');
  try
    { furo passante }
    Cyl := CadMakeCylinder(V3(20, 25, -1), V3(0, 0, 1), 4, 12, 'Furo');
    try
      R := CadBoolean(A, Cyl, boDifference, E);
      Exact := 40000 - Cyl.Volume / 12 * 10;
      Check((R <> nil) and R.IsClosed, 'furo passante: malha fechada ' + E);
      Check(Near(R.Volume, Exact, 1E-6), Format('volume do bloco furado (%.6f x %.6f)', [R.Volume, Exact]));
      Check((R.FaceIndex('Base/zmax') >= 0) and (R.FaceIndex('Furo/cil') >= 0), 'nomes das faces mantidos (Base/zmax, Furo/cil)');
      Check(CadMeshComponents(R) = 1, 'uma peca');
      Check(NearV(R.Faces[R.FaceIndex('Base/zmax')].Axis, V3(0, 0, 1), 1E-9), 'normal da face de cima mantida');
    finally
      Cyl.Free;
      FreeAndNil(R);
    end;
    { bolsao a partir da face de cima (faces coplanares) }
    B := CadMakeBox(V3(10, 10, 6), V3(30, 30, 10), 'Bolsao');
    R := CadBoolean(A, B, boDifference, E);
    Check((R <> nil) and R.IsClosed and Near(R.Volume, 40000 - 20 * 20 * 4, 1E-6),
      'bolsao com topo coplanar: fechado e volume certo ' + E);
    Check(R.FaceIndex('Bolsao/zmin') >= 0, 'fundo do bolsao vem da ferramenta');
    FreeAll;
    { ressalto em cima (encostado) }
    B := CadMakeBox(V3(10, 10, 10), V3(30, 30, 20), 'Ressalto');
    R := CadBoolean(A, B, boUnion, E);
    Check((R <> nil) and R.IsClosed and Near(R.Volume, 40000 + 4000, 1E-6), 'ressalto encostado: uniao fechada ' + E);
    Check(CadMeshComponents(R) = 1, 'ressalto encostado vira uma peca so');
    FreeAll;
    { lado a lado, face inteira em comum }
    B := CadMakeBox(V3(80, 0, 0), V3(120, 50, 10), 'Lado');
    R := CadBoolean(A, B, boUnion, E);
    Check((R <> nil) and R.IsClosed and Near(R.Volume, 60000, 1E-6) and (CadMeshComponents(R) = 1),
      'blocos lado a lado se fundem ' + E);
    FreeAll;
    { separados }
    B := CadMakeBox(V3(200, 0, 0), V3(210, 10, 10), 'Longe');
    R := CadBoolean(A, B, boUnion, E);
    Check((R <> nil) and Near(R.Volume, 41000, 1E-6) and (CadMeshComponents(R) = 2), 'uniao de pecas separadas: 2 componentes');
    Parts := CadSplitComponents(R);
    try
      Check(Parts.Count = 2, 'separa em 2 malhas');
      V0 := 0;
      for I := 0 to Parts.Count - 1 do
      begin
        Check(TCadMesh(Parts[I]).IsClosed, 'parte fechada');
        V0 := V0 + TCadMesh(Parts[I]).Volume;
      end;
      Check(Near(V0, 41000, 1E-6), 'volumes das partes somam o total');
    finally
      for I := 0 to Parts.Count - 1 do
        TCadMesh(Parts[I]).Free;
      Parts.Free;
    end;
    FreeAll;
    { intersecao }
    B := CadMakeBox(V3(70, 40, -5), V3(100, 60, 5), 'X');
    R := CadBoolean(A, B, boIntersection, E);
    Check((R <> nil) and R.IsClosed and Near(R.Volume, 10 * 10 * 5, 1E-6), 'intersecao de blocos ' + E);
    FreeAll;
    { corte que nao toca }
    B := CadMakeBox(V3(200, 0, 0), V3(210, 10, 10), 'Fora');
    R := CadBoolean(A, B, boDifference, E);
    Check((R <> nil) and Near(R.Volume, 40000, 1E-6), 'corte fora da peca nao muda o volume');
    FreeAll;
    { corte que remove tudo }
    B := CadMakeBox(V3(-10, -10, -10), V3(100, 100, 100), 'Tudo');
    R := CadBoolean(A, B, boDifference, E);
    Check((R <> nil) and (R.TriCount = 0), 'corte que remove tudo deixa malha vazia');
    FreeAll;
  finally
    A.Free;
  end;

  { placa com 4 furos sucessivos (desempenho e robustez) }
  A := CadMakeBox(V3(0, 0, 0), V3(100, 60, 8), 'Placa');
  T0 := GetTickCount64;
  try
    for I := 0 to 3 do
    begin
      Cyl := CadMakeCylinder(V3(15 + I * 23, 30, -2), V3(0, 0, 1), 5, 12, 'F' + IntToStr(I));
      try
        R := CadBoolean(A, Cyl, boDifference, E);
        Check(R <> nil, 'furo ' + IntToStr(I) + ': ' + E);
        Exact := Cyl.Volume / 12 * 8;
      finally
        Cyl.Free;
      end;
      if R = nil then
        Exit;
      A.Free;
      A := R;
      R := nil;
    end;
    Check(A.IsClosed and Near(A.Volume, 48000 - 4 * Exact, 1E-5), Format('placa com 4 furos (%.4f)', [A.Volume]));
    Check(GetTickCount64 - T0 < 10000, Format('4 furos em menos de 10 s (%d ms)', [GetTickCount64 - T0]));
    { cilindro cruzando cilindro (furo transversal) }
    Cyl := CadMakeCylinder(V3(-5, 30, 4), V3(1, 0, 0), 2, 110, 'Trans');
    try
      { limite conhecido (TAREFA.md): cilindro cortando cilindro gera lascas
        demais para a malha; a operacao deve falhar com mensagem, sem quebrar
        e sem devolver malha aberta }
      R := CadBoolean(A, Cyl, boDifference, E);
      Check(((R <> nil) and R.IsClosed and (R.Volume < A.Volume)) or ((R = nil) and (E <> '')),
        'furo transversal: fechado ou recusado com mensagem');
    finally
      Cyl.Free;
      FreeAndNil(R);
    end;
  finally
    A.Free;
  end;
end;

{ ---------- fase 2C: reconstrucao e operacoes ---------- }

{ Retangulo totalmente definido no plano dado. }
function RectSketch(D: TCadDocument; const APlane: string; X0, Y0, W, H: Double): TCadSketch;
var
  L: Integer;
begin
  Result := D.AddSketch(APlane);
  L := Result.AddRectangle(X0, Y0, X0 + W, Y0 + H);
  Result.AddFixed(L, 1);
  Result.AddDimension(ckHorizontalDistance, L, 0, 0, 0, W);
  Result.AddDimension(ckVerticalDistance, L + 1, 0, 0, 0, H);
end;

function RegionsArea(S: TCadSketch): Double;
var
  P: TCadProfileResult;
  I: Integer;
begin
  P := CadSketchProfiles(S, 0.01);
  Result := 0;
  for I := 0 to High(P.Regions) do
    Result := Result + P.Regions[I].Area;
end;

procedure TestRebuild;
var
  D, D2: TCadDocument;
  RB, RB2: TCadRebuilder;
  S1, S2, S3, S4: TCadSketch;
  X1, X2, X3, X4: TCadExtrude;
  RV: TCadRevolve;
  P30, PM, PA: TCadPlane;
  E, J: string;
  V, Exact, HolesArea, Dl: Double;
  B: TCadBox3;
  Bd: TCadBody;
  F, I, L: Integer;
begin
  { ----- suporte: base + dois furos num esboco sobre a face de cima ----- }
  D := TCadDocument.Create;
  RB := TCadRebuilder.Create(D);
  try
    S1 := RectSketch(D, 'plane:1', 0, 0, 80, 50);
    X1 := D.AddExtrude(S1.Id, 10);
    Check(RB.Rebuild = 0, 'base reconstruida sem erro: ' + X1.Message);
    Check((RB.BodyCount = 1) and Near(RB.TotalVolume, 40000, 1E-6), 'base 80x50x10 = 40000 mm3');
    Check(S1.State = fsOk, 'esboço da base ok');
    Check(RB.FindFace('Ressalto-Extrusão1/fim', Bd, F), 'face do fim da base com nome estavel');
    S2 := D.AddSketch('face:Ressalto-Extrusão1/fim');
    S2.AddCircle(20, 25, 4);
    S2.AddCircle(60, 25, 4);
    X2 := D.AddExtrude(S2.Id, 0, True);
    X2.Dir1.EndCond := ecThroughAll;
    Check(RB.Rebuild = 0, 'furos passantes sem erro: ' + X2.Message);
    HolesArea := RegionsArea(S2);
    Check(Near(RB.TotalVolume, 40000 - HolesArea * 10, 1E-4),
      Format('volume com 2 furos (%.4f x %.4f)', [RB.TotalVolume, 40000 - HolesArea * 10]));
    Check(RB.FindFace('Corte-Extrusão1/lat:' + IntToStr(S2.Entity(0).Id), Bd, F) and
      (Bd.Mesh.Faces[F].Surf = skCylinder), 'parede do furo e cilindrica e tem nome estavel');
    Check(Near(RB.MassKg, CadMassKg(D.MaterialData, RB.TotalVolume), 1E-12), 'massa pelo material');
    { cache: nada mudou }
    RB.Rebuild;
    Check(RB.Recomputed = 0, Format('sem mudanca nada e recalculado (%d)', [RB.Recomputed]));
    { mudar a cota da base }
    S1.SetDimension('D1', 100);
    Check(RB.Rebuild = 0, 'reconstroi depois de mudar a cota');
    Check(Near(RB.TotalVolume, 50000 - HolesArea * 10, 1E-4), 'base 100 mm: volume atualizado e furos mantidos');
    Check(RB.Recomputed >= 2, 'recalcula a base e os furos');
    { retrocesso: antes dos furos }
    D.RollbackIndex := D.IndexOfId(X2.Id);
    RB.Rebuild;
    Check(Near(RB.TotalVolume, 50000, 1E-6), 'barra de retrocesso antes dos furos');
    D.RollbackIndex := -1;
    { suprimir os furos }
    X2.Suppressed := True;
    RB.Rebuild;
    Check(Near(RB.TotalVolume, 50000, 1E-6), 'furos suprimidos');
    X2.Suppressed := False;
    RB.Rebuild;
    { JSON ida e volta reconstroi igual }
    J := D.ToJSON;
    D2 := TCadDocument.Create;
    RB2 := TCadRebuilder.Create(D2);
    try
      Check(D2.LoadFromJSON(J, E), 'le o suporte do JSON: ' + E);
      Check((RB2.Rebuild = 0) and Near(RB2.TotalVolume, RB.TotalVolume, 1E-6), 'arquivo reaberto reconstroi o mesmo solido');
    finally
      RB2.Free;
      D2.Free;
    end;
    { referencia perdida: face apagada }
    S2.PlaneRef := 'face:Ressalto-Extrusão1/naoexiste';
    Check(RB.Rebuild >= 1, 'face inexistente gera erro');
    Check((S2.State = fsOk) and (X2.State = fsError) and (Pos('não existe', X2.Message) > 0),
      'operacao com referencia perdida fica com erro na arvore: ' + X2.Message);
    Check(Near(RB.TotalVolume, 50000, 1E-6), 'operacao com erro nao muda o solido');
  finally
    RB.Free;
    D.Free;
  end;

  { ----- condicoes finais ----- }
  D := TCadDocument.Create;
  RB := TCadRebuilder.Create(D);
  try
    S1 := RectSketch(D, 'plane:1', 0, 0, 80, 50);
    X1 := D.AddExtrude(S1.Id, 10);
    X1.Dir1.EndCond := ecMidPlane;
    RB.Rebuild;
    B := RB.Body(0).Mesh.Bounds;
    Check(Near(B.Min.Z, -5, 1E-9) and Near(B.Max.Z, 5, 1E-9), 'plano medio: Z de -5 a 5');
    X1.Dir1.EndCond := ecBlind;
    { plano a 30 mm e plano medio entre Frontal e ele }
    P30 := D.AddPlane(ptOffset, ['plane:1'], 30);
    PM := D.AddPlane(ptMidPlane, ['plane:1', 'plane:' + IntToStr(P30.Id)]);
    RB.Rebuild;
    Check(P30.FrameValid and Near(P30.Frame.Origin.Z, 30, 1E-9), 'plano deslocado a 30 mm');
    Check(PM.FrameValid and Near(PM.Frame.Origin.Z, 15, 1E-9) and NearV(PM.Frame.Normal, V3(0, 0, 1)), 'plano medio a 15 mm');
    { ate a superficie (plano paralelo) }
    S3 := RectSketch(D, 'plane:1', 100, 0, 10, 10);
    X3 := D.AddExtrude(S3.Id, 0);
    X3.Dir1.EndCond := ecUpToSurface;
    X3.Dir1.Target := 'plane:' + IntToStr(P30.Id);
    RB.Rebuild;
    Check((X3.State = fsWarning) and (Pos('corpo separado', X3.Message) > 0), 'ressalto separado avisa multicorpo');
    Check((RB.BodyCount = 2) and Near(RB.TotalVolume, 40000 + 3000, 1E-6), 'ate a superficie: 10x10x30');
    { deslocamento da superficie }
    X3.Dir1.EndCond := ecOffsetFromSurface;
    X3.Dir1.Offset := 5;
    RB.Rebuild;
    Check(Near(RB.TotalVolume, 40000 + 2500, 1E-6), 'deslocamento de 5 mm da superficie: 25 mm');
    { ate o vertice }
    S4 := D.AddSketch('plane:' + IntToStr(P30.Id));
    I := S4.AddPoint(0, 0);
    X3.Dir1.EndCond := ecUpToVertex;
    X3.Dir1.Target := Format('sketch:%d/%d.1', [S4.Id, I]);
    RB.Rebuild;
    Check((X3.State <> fsError) and Near(RB.TotalVolume, 43000, 1E-6), 'ate o vertice a 30 mm: ' + X3.Message);
    X3.Suppressed := True;
    { ate o proximo: placa em z=30..35, ressalto partindo do topo da base }
    S4 := RectSketch(D, 'plane:' + IntToStr(P30.Id), 0, 0, 80, 50);
    X4 := D.AddExtrude(S4.Id, 5);
    S3 := RectSketch(D, 'face:Ressalto-Extrusão1/fim', 10, 10, 10, 10);
    X2 := D.AddExtrude(S3.Id, 0);
    X2.Dir1.EndCond := ecUpToNext;
    RB.Rebuild;
    Check(X2.State = fsOk, 'ate o proximo sem erro: ' + X2.Message);
    Check((RB.BodyCount = 1) and Near(RB.TotalVolume, 40000 + 20000 + 10 * 10 * 20, 1E-5),
      Format('ate o proximo une base, coluna de 20 mm e placa (%d corpos, %.3f)', [RB.BodyCount, RB.TotalVolume]));
    X4.Suppressed := True;
    RB.Rebuild;
    Check((X2.State = fsError) and (Pos('inverta', X2.Message) > 0), 'ate o proximo sem face a frente gera erro');
    X4.Suppressed := False;
    { corte passante nos dois sentidos a partir do plano medio }
    S3 := D.AddSketch('plane:' + IntToStr(PM.Id));
    S3.AddCircle(40, 25, 3);
    X3 := D.AddExtrude(S3.Id, 0, True);
    X3.Dir1.EndCond := ecThroughAllBoth;
    RB.Rebuild;
    V := RegionsArea(S3);
    Check((X3.State = fsOk) and Near(RB.TotalVolume, 40000 + 20000 + 2000 - V * 15, 1E-4),
      Format('passante nos dois sentidos fura base e placa (%.4f)', [RB.TotalVolume]));
  finally
    RB.Free;
    D.Free;
  end;

  { ----- ate superficie inclinada ----- }
  D := TCadDocument.Create;
  RB := TCadRebuilder.Create(D);
  try
    S1 := D.AddSketch('plane:1');
    L := S1.AddLine(0, 40, 100, 40, True);
    PA := D.AddPlane(ptAngle, ['plane:2', Format('sketch:%d/%d', [S1.Id, L])], 30);
    S2 := RectSketch(D, 'plane:2', 0, -10, 10, 10);
    X1 := D.AddExtrude(S2.Id, 0);
    X1.Dir1.EndCond := ecUpToSurface;
    X1.Dir1.Target := 'plane:' + IntToStr(PA.Id);
    RB.Rebuild;
    Check(PA.FrameValid, 'plano em angulo: ' + PA.Message);
    Exact := 100 * (40 - 5 * Tan(30 * Pi / 180));
    Check((X1.State <> fsError) and RelNear(RB.TotalVolume, Exact, 1E-6),
      Format('ate superficie inclinada (%.4f x %.4f) %s', [RB.TotalVolume, Exact, X1.Message]));
    Check(RB.FindFace('Ressalto-Extrusão1/fim', Bd, F) and (Bd.Mesh.Faces[F].Surf = skPlane),
      'face inclinada do fim com nome estavel');
  finally
    RB.Free;
    D.Free;
  end;

  { ----- inclinacao, recurso fino, contornos, inverter lado ----- }
  D := TCadDocument.Create;
  RB := TCadRebuilder.Create(D);
  try
    S1 := RectSketch(D, 'plane:1', 0, 0, 80, 50);
    X1 := D.AddExtrude(S1.Id, 10);
    X1.Dir1.Draft := 5;
    RB.Rebuild;
    Dl := 10 * Tan(5 * Pi / 180);
    Check(Near(RB.TotalVolume, 10 * (4000 - Dl * 130 + 4 / 3 * Dl * Dl), 1E-6), 'ressalto com inclinacao de 5 graus');
    X1.Dir1.Draft := 0;
    { inverter lado a cortar: sobra so o quadrado }
    S2 := RectSketch(D, 'plane:1', 10, 10, 20, 20);
    X2 := D.AddExtrude(S2.Id, 0, True);
    X2.Dir1.EndCond := ecThroughAllBoth;
    X2.FlipSide := True;
    RB.Rebuild;
    Check(Near(RB.TotalVolume, 4000, 1E-6), 'inverter lado a cortar deixa so o quadrado');
    X2.FlipSide := False;
    RB.Rebuild;
    Check(Near(RB.TotalVolume, 36000, 1E-6), 'corte normal tira o quadrado');
    { corte que nao toca }
    S3 := RectSketch(D, 'plane:1', 200, 0, 10, 10);
    X3 := D.AddExtrude(S3.Id, 5, True);
    RB.Rebuild;
    Check((X3.State = fsWarning) and (Pos('não intercepta', X3.Message) > 0), 'corte fora avisa: ' + X3.Message);
    X3.Suppressed := True;
    { contornos selecionados }
    S3 := D.AddSketch('plane:1');
    S3.AddRectangle(100, 0, 110, 10);
    S3.AddRectangle(120, 0, 140, 10);
    X3 := D.AddExtrude(S3.Id, 5);
    X3.Merge := False;
    X3.Contours := ['region:' + IntToStr(S3.Entity(4).Id)];
    RB.Rebuild;
    Check(Near(RB.TotalVolume, 36000 + 1000, 1E-6), 'contornos selecionados: so o segundo retangulo (200x5)');
    X3.Contours := ['region:999'];
    RB.Rebuild;
    Check(X3.State = fsError, 'contorno inexistente gera erro');
  finally
    RB.Free;
    D.Free;
  end;

  { ----- recurso fino ----- }
  D := TCadDocument.Create;
  RB := TCadRebuilder.Create(D);
  try
    S1 := RectSketch(D, 'plane:1', 0, 0, 20, 20);
    X1 := D.AddExtrude(S1.Id, 10);
    X1.Thin := True;
    X1.ThinType := ttOneDirection;
    X1.ThinT1 := 2;
    RB.Rebuild;
    Check(Near(RB.TotalVolume, (24 * 24 - 20 * 20) * 10, 1E-6), 'fino fechado para fora: 1760 ' + X1.Message);
    Check(RB.FindFace(Format('Ressalto-Extrusão1/lat:%d/out', [S1.Entity(0).Id]), Bd, F) and
      RB.FindFace(Format('Ressalto-Extrusão1/lat:%d/in', [S1.Entity(0).Id]), Bd, F), 'faces /out e /in do fino');
    X1.ThinType := ttMidPlane;
    RB.Rebuild;
    Check(Near(RB.TotalVolume, (22 * 22 - 18 * 18) * 10, 1E-6), 'fino plano medio: 1600');
    X1.ThinType := ttOneDirection;
    X1.CapEnds := True;
    X1.CapThickness := 1;
    RB.Rebuild;
    Check(Near(RB.TotalVolume, 24 * 24 * 10 - 20 * 20 * 8, 1E-6),
      Format('tampar extremidades (%.3f) %s', [RB.TotalVolume, X1.Message]));
  finally
    RB.Free;
    D.Free;
  end;
  D := TCadDocument.Create;
  RB := TCadRebuilder.Create(D);
  try
    S1 := D.AddSketch('plane:1');
    S1.AddLine(0, 0, 20, 0);
    S1.AddLine(20, 0, 20, 20);
    X1 := D.AddExtrude(S1.Id, 5);
    RB.Rebuild;
    Check((X1.State = fsError) and (Pos('Recurso fino', X1.Message) > 0), 'perfil aberto sem fino: erro ' + X1.Message);
    X1.Thin := True;
    X1.ThinT1 := 2;
    RB.Rebuild;
    Check((X1.State = fsOk) and Near(RB.TotalVolume, 76 * 5, 1E-6), Format('fino aberto em L (%.4f) %s', [RB.TotalVolume, X1.Message]));
    Check(RB.FindFace('Ressalto-Extrusão1/ponta1', Bd, F) and RB.FindFace('Ressalto-Extrusão1/ponta2', Bd, F), 'pontas do fino aberto');
  finally
    RB.Free;
    D.Free;
  end;

  { ----- revolucao e corte revolucionado ----- }
  D := TCadDocument.Create;
  RB := TCadRebuilder.Create(D);
  try
    S1 := D.AddSketch('plane:1');
    S1.AddRectangle(0, 0, 10, 40);
    S1.AddCenterline(0, -5, 0, 50);
    RV := D.AddRevolve(S1.Id, 360);
    RB.Rebuild;
    Check(RV.State = fsOk, 'revolucao sem erro: ' + RV.Message);
    Check(RelNear(RB.TotalVolume, Pi * 100 * 40, 0.005), Format('eixo revolucionado r10 x 40 (%.2f)', [RB.TotalVolume]));
    S2 := D.AddSketch('plane:1');
    S2.AddRectangle(6, 30, 12, 40);
    S2.AddCenterline(0, 0, 0, 10);
    RV := D.AddRevolve(S2.Id, 360, True);
    RB.Rebuild;
    Check(RV.State = fsOk, 'corte revolucionado sem erro: ' + RV.Message);
    Check(RelNear(RB.TotalVolume, Pi * 100 * 40 - Pi * (100 - 36) * 10, 0.005), 'rebaixo revolucionado na ponta');
    S3 := D.AddSketch('plane:1');
    S3.AddRectangle(20, 0, 30, 10);
    RV := D.AddRevolve(S3.Id, 90);
    RB.Rebuild;
    Check((RV.State = fsError) and (Pos('linha de centro', RV.Message) > 0), 'revolucao sem eixo: erro');
    RV.AxisRef := Format('sketch:%d/%d', [S1.Id, S1.Entity(4).Id]);
    RB.Rebuild;
    Check(RV.State <> fsError, 'eixo de outro esboço no mesmo plano: ' + RV.Message);
  finally
    RB.Free;
    D.Free;
  end;

  { ----- primeira operacao como corte ----- }
  D := TCadDocument.Create;
  RB := TCadRebuilder.Create(D);
  try
    S1 := RectSketch(D, 'plane:1', 0, 0, 10, 10);
    X1 := D.AddExtrude(S1.Id, 5, True);
    Check((RB.Rebuild = 1) and (Pos('Corte sem corpo', X1.Message) > 0), 'corte como primeira operacao: erro');
  finally
    RB.Free;
    D.Free;
  end;
end;

procedure TestCamera;
var
  C: TCadCamera;
  F: TCadFrame;
  P, O, D, Q: TCadVec3;
  S, S2: TCadScreenPt;
  B: TCadBox3;
  I: Integer;
  AllIn: Boolean;
begin
  C := TCadCamera.Create;
  try
    C.SetViewport(800, 600);
    C.StdView(svFront);
    Check(NearV(C.Back, V3(0, 0, 1)) and NearV(C.Up, V3(0, 1, 0)) and NearV(C.Right, V3(1, 0, 0)),
      'vista Frontal: olha de +Z, X a direita, Y para cima');
    C.StdView(svTop);
    Check(NearV(C.Back, V3(0, 1, 0)) and NearV(C.Right, V3(1, 0, 0)) and NearV(C.Up, V3(0, 0, -1)),
      'vista Superior: olha de +Y, X a direita, -Z para cima');
    C.StdView(svRight);
    Check(NearV(C.Right, V3(0, 0, -1)), 'vista Direita: -Z a direita');
    C.StdView(svIso);
    Check(NearV(C.Back, VNorm(V3(1, 1, 1))) and (C.Up.Y > 0), 'isometrica com Y para cima');
    Check(Near(VDot(C.Right, C.Up), 0) and Near(VLen(C.Right), 1), 'base ortonormal');
    F := StdFrame(spSuperior);
    C.NormalTo(F, False);
    Check(NearV(C.Back, F.Normal) and NearV(C.Right, F.XDir) and NearV(C.Up, F.YDir),
      'Normal a: x do plano a direita, y para cima');
    C.NormalTo(F, True);
    Check(NearV(C.Back, VNeg(F.Normal)) and NearV(C.Up, F.YDir), 'Normal a repetido vira o lado');
    { projecao e raio }
    C.StdView(svIso);
    C.Scale := 3;
    P := V3(12, -7, 30);
    S := C.Project(P);
    C.ScreenRay(S.X, S.Y, O, D);
    Q := VSub(P, O);
    Check(VLen(VCross(Q, D)) < 1E-6, 'raio do pixel passa pelo ponto projetado (ortografica)');
    C.Perspective := True;
    S := C.Project(P);
    C.ScreenRay(S.X, S.Y, O, D);
    Check(VLen(VCross(VSub(P, O), D)) < 1E-6 * VLen(VSub(P, O)) + 1E-6,
      'raio do pixel passa pelo ponto projetado (perspectiva)');
    C.Perspective := False;
    { zoom no cursor }
    S := C.Project(P);
    C.ZoomAt(1.7, S.X, S.Y);
    S2 := C.Project(P);
    Check(Near(S.X, S2.X, 1E-6) and Near(S.Y, S2.Y, 1E-6) and Near(C.Scale, 5.1),
      'zoom mantem o ponto sob o cursor');
    { orbita mantem a base }
    C.Orbit(37, -21);
    Check(Near(VDot(C.Right, C.Up), 0) and Near(VDot(C.Back, C.Up), 0) and
      Near(VLen(C.Back), 1) and Near(VDot(VCross(C.Right, C.Up), C.Back), 1), 'orbita mantem a base direita');
    { pan }
    S := C.Project(P);
    C.Pan(10, 5);
    S2 := C.Project(P);
    Check(Near(S2.X - S.X, 10, 1E-6) and Near(S2.Y - S.Y, 5, 1E-6), 'pan segue o mouse');
    { enquadrar }
    B := BoxEmpty;
    BoxAdd(B, V3(-50, 0, 0));
    BoxAdd(B, V3(150, 80, 40));
    C.Fit(B);
    AllIn := True;
    for I := 0 to 7 do
    begin
      if (I and 1) = 0 then Q.X := B.Min.X else Q.X := B.Max.X;
      if (I and 2) = 0 then Q.Y := B.Min.Y else Q.Y := B.Max.Y;
      if (I and 4) = 0 then Q.Z := B.Min.Z else Q.Z := B.Max.Z;
      S := C.Project(Q);
      if (S.X < 0) or (S.X > 800) or (S.Y < 0) or (S.Y > 600) then
        AllIn := False;
    end;
    Check(AllIn and (C.Scale > 2), 'enquadrar (F) deixa a caixa toda na tela');
  finally
    C.Free;
  end;
end;

procedure TestRender;
var
  C: TCadCamera;
  R: TCadRaster;
  M: TCadMesh;
  Cache: TCadMeshCache;
  Opt: TCadDrawOptions;
  S: TCadScreenPt;
  Tag, Face, I, NF, Code, Cnt: Integer;
  T: Double;
  O, D: TCadVec3;
  Nm: string;
begin
  C := TCadCamera.Create;
  R := TCadRaster.Create;
  M := CadMakeBox(V3(0, 0, 0), V3(40, 30, 20), 'Caixa');
  Cache := TCadMeshCache.Create(M);
  try
    NF := 0;
    for I := 0 to High(Cache.Edges) do
      if Cache.Edges[I].Feature then
        Inc(NF);
    Check(NF = 12, Format('caixa: 12 arestas de recurso (%d)', [NF]));
    R.SetSize(200, 150);
    C.SetViewport(200, 150);
    C.StdView(svFront);
    C.Fit(M.Bounds);
    R.BeginFrame(C);
    Opt := CadDrawOptions(CAD_PART_COLOR, 3);
    R.DrawMesh(Cache, Opt);
    Code := R.IdAt(100, 75);
    CadPickDecode(Code, Tag, Face);
    Nm := '';
    if Face >= 0 then
      Nm := M.Faces[Face].Name;
    Check((Tag = 3) and (Face >= 0) and (Abs(M.Faces[Face].Axis.Z - 1) < 1E-6),
      'selecao no centro da vista Frontal pega a face +Z (' + Nm + ')');
    Check(R.IdAt(2, 2) = 0, 'canto da tela e fundo');
    Check(R.DepthAt(100, 75) < 1E29, 'profundidade escrita');
    { a borda da peca tem aresta escura }
    S := C.Project(V3(0, 15, 20));
    Check(R.ColorAt(Round(S.X), Round(S.Y)) = CAD_EDGE_COLOR, 'aresta desenhada na borda');
    { raio pelo pixel acha a mesma face }
    C.ScreenRay(100.5, 75.5, O, D);
    I := CadRayMesh(M, O, D, T);
    Check((I >= 0) and (M.Tris[I].Face = Face), 'raio de selecao acha a mesma face');
    { secao: corta metade em X }
    R.SetSection(True, V3(20, 0, 0), V3(1, 0, 0));
    R.BeginFrame(C);
    R.DrawMesh(Cache, Opt);
    S := C.Project(V3(30, 15, 20));
    Check(R.IdAt(Round(S.X), Round(S.Y)) = 0, 'secao remove o lado positivo');
    S := C.Project(V3(10, 15, 20));
    Check(R.IdAt(Round(S.X), Round(S.Y)) <> 0, 'secao mantem o lado negativo');
    R.SetSection(False, V3(0, 0, 0), V3(1, 0, 0));
    { arame nao preenche }
    R.Style := dsWireframe;
    R.BeginFrame(C);
    R.DrawMesh(Cache, Opt);
    Check(R.IdAt(100, 75) = 0, 'arame: centro vazio');
    { linhas ocultas removidas: Id mas cor de fundo }
    R.Style := dsHiddenRemoved;
    R.BeginFrame(C);
    R.DrawMesh(Cache, Opt);
    Check((R.IdAt(100, 75) <> 0) and (R.ColorAt(100, 75) <> CAD_PART_COLOR), 'HLR: superficie sem cor de peca');
    { previa translucida nao escreve profundidade }
    R.Style := dsShadedEdges;
    R.BeginFrame(C);
    Opt.Alpha := 0.5;
    R.DrawMesh(Cache, Opt);
    Check(R.DepthAt(100, 75) > 1E29, 'previa translucida nao ocupa profundidade');
    { cilindro: silhueta e aresta suave }
    Cache.Free;
    M.Free;
    M := CadMakeCylinder(V3(0, 0, 0), V3(0, 1, 0), 10, 30, 'Cil', 32);
    Cache := TCadMeshCache.Create(M);
    Cnt := 0;
    for I := 0 to High(Cache.Edges) do
      if Cache.Edges[I].Feature then
        Inc(Cnt);
    Check(Cnt = 64, Format('cilindro: so os dois circulos sao arestas de recurso (%d)', [Cnt]));
  finally
    Cache.Free;
    M.Free;
    R.Free;
    C.Free;
  end;
end;

procedure TestSketchTools;
var
  D: TCadDocument;
  S: TCadSketch;
  T: TCadSketchSession;
  E: TSketchEntity;
  N0, I, CntH, CntV, CntC: Integer;
  C: TSketchConstraint;
  V: Double;
begin
  D := TCadDocument.Create;
  try
    D.NewPart;
    S := D.AddSketch('plane:1');
    T := TCadSketchSession.Create(D, S);
    try
      T.PickTol := 1.5;
      { linha em cadeia partindo da origem, quase horizontal e depois vertical }
      T.Tool := tkLine;
      T.Click(V2(0.4, -0.3));
      T.Click(V2(50, 1.2));
      T.Click(V2(51, 30));
      T.Click(V2(0.5, 0.2));   { fecha na origem? nao: a origem ja e o inicio }
      Check(S.EntityCount = 3, Format('linha em cadeia: 3 linhas (%d)', [S.EntityCount]));
      E := S.Entity(0);
      Check(Near(E.P1.X, 0) and Near(E.P1.Y, 0), 'inicio capturado na origem');
      Check(Near(E.P2.Y, 0, 1E-6), 'linha quase horizontal travada');
      CntH := 0; CntV := 0; CntC := 0;
      for I := 0 to S.ConstraintCount - 1 do
      begin
        C := S.Constraint(I);
        case C.Kind of
          ckHorizontal: Inc(CntH);
          ckVertical: Inc(CntV);
          ckCoincident: Inc(CntC);
        end;
      end;
      Check((CntH = 1) and (CntV = 1), Format('relacoes automaticas H=%d V=%d', [CntH, CntV]));
      Check(CntC = 4, Format('coincidentes: origem, 2 juncoes e fechamento (%d)', [CntC]));
      Check(T.ClickCount = 0, 'fechar num ponto existente encerra a cadeia');
      Check(T.LastSolve.Status = ssUnderDefined, 'triangulo ainda subdefinido');
      { cota inteligente: comprimento da linha horizontal = 60 }
      N0 := S.ConstraintCount;
      I := T.AddSmartDimension(PickItem(S.Entity(0).Id, 0), PickItem(0, 0), False, '60');
      Check((I > 0) and (S.ConstraintCount = N0 + 1), 'cota de comprimento criada');
      E := S.Entity(0);
      Check(Near(Sqrt(Sqr(E.P2.X - E.P1.X) + Sqr(E.P2.Y - E.P1.Y)), 60, 1E-6), 'cota dirige o comprimento (60)');
      I := T.AddSmartDimension(PickItem(S.Entity(1).Id, 0), PickItem(0, 0), False, '40');
      Check(T.LastSolve.Status = ssFullyDefined, 'triangulo com 2 cotas: totalmente definido (' +
        CAD_SKETCH_STATUS_NAMES[T.LastSolve.Status] + ')');
      { terceira cota superdefine: vira dirigida }
      I := T.AddSmartDimension(PickItem(S.Entity(2).Id, 0), PickItem(0, 0), False, '');
      C := S.Constraint(S.ConstraintIndex(I));
      Check(not C.Driving and Near(C.Value, Sqrt(60 * 60 + 40 * 40), 1E-6), 'cota extra vira dirigida com o valor medido');
      { circulo e cota de diametro }
      T.Tool := tkCircle;
      T.Click(V2(20, 10));
      T.Click(V2(25, 10));
      Check(S.Entity(S.EntityCount - 1).Kind = seCircle, 'circulo pelo centro e raio');
      I := T.AddSmartDimension(PickItem(S.Entity(S.EntityCount - 1).Id, 0), PickItem(0, 0), False, '8');
      Check(Near(S.Entity(S.EntityCount - 1).Radius, 4, 1E-6), 'cota de diametro 8');
      { relacao pela selecao: ponto medio nao cabe em circulo }
      T.Tool := tkSelect;
      T.Click(V2(24, 10));
      Check(Length(T.Selection) = 1, 'selecionar o circulo');
      Check(not T.AddRelation(ckMidpoint), 'relacao que nao cabe e recusada');
      { retangulo }
      T.Tool := tkRectangle;
      N0 := S.EntityCount;
      T.Click(V2(-30, -20));
      T.Click(V2(-10, -5));
      Check(S.EntityCount = N0 + 4, 'retangulo de canto: 4 linhas');
      { arco de 3 pontos ligado ao fim de uma linha }
      T.Tool := tkArc3P;
      N0 := S.EntityCount;
      T.Click(V2(-10, -5));
      T.Click(V2(-10, 15));
      T.Click(V2(0, 5));
      Check(S.EntityCount = N0 + 1, 'arco de 3 pontos');
      E := S.Entity(S.EntityCount - 1);
      Check(Near(E.Radius, 10, 1E-6), 'arco de raio 10');
      { apagar }
      T.Tool := tkSelect;
      T.Click(V2(-10 + 10, 5 + 0.0001));
      N0 := S.EntityCount;
      Check(T.DeleteSelection and (S.EntityCount = N0 - 1), 'apagar a entidade selecionada');
      { angulo entre duas linhas }
      I := T.AddSmartDimension(PickItem(S.Entity(0).Id, 0), PickItem(S.Entity(1).Id, 0), True, '');
      Check((I > 0) and (S.Constraint(S.ConstraintIndex(I)).Kind = ckAngle), 'duas linhas: cota angular');
      Check(CadMeasureDimension(S, S.ConstraintIndex(I), V) and (V > 0), 'angulo medido');
    finally
      T.Free;
    end;
  finally
    D.Free;
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
  TestSolver;
  TestProfiles;
  TestSweep;
  TestCSG;
  TestRebuild;
  TestCamera;
  TestRender;
  TestSketchTools;
  Writeln(Format('MultiCAD: %d checks, %d falhas', [Passed + Failed, Failed]));
  if Failed > 0 then
    Halt(1);
  Writeln('MultiCAD: OK');
end.
