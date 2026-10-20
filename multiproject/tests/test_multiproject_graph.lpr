program test_multiproject_graph;

{ Fase 2 do MultiProject (multiproject/docs/TAREFA.md, itens 2.1 a 2.6):
  vinculos TI/II/TT/IT com latencia, grafo pelo aitaskgraph (CHATGPT / AI
  Project Core), recusa de ciclo com caminho sem alterar o documento, cadeias,
  em cadeia x em paralelo, coluna Predecessoras, vinculos de resumo, desfazer,
  .mproj com vinculos e arquivos invalidos. Usa o exemplo do motor do README. }

{$mode objfpc}{$H+}

uses
  Classes, SysUtils, Math, aiprojectduration, aitaskgraph, aijsonutils,
  multiproject_types, multiproject_document, multiproject_json, multiproject_graph;

var
  Passed, Failed: Integer;
  TmpDir: string;

procedure Check(Cond: Boolean; const What: string);
begin
  if Cond then Inc(Passed)
  else
  begin
    Inc(Failed);
    Writeln('FALHOU: ', What);
  end;
end;

function Body(P: TPJProject): string;
var L: TStringList; I: Integer;
begin
  L := TStringList.Create;
  try
    L.Text := ProjectToJSONText(P);
    for I := L.Count - 1 downto 0 do
      if Pos('"next_task_number"', L[I]) > 0 then L.Delete(I);
    Result := L.Text;
  finally
    L.Free;
  end;
end;

function Link(P: TPJProject; const A, B: string; T: TAITaskLinkType = atlFS; Art: Boolean = True): Boolean;
var Err: string;
begin
  Result := P.AddLink(A, B, T, AINoLag, Art, Err);
  if not Result then Writeln('  (vinculo ', A, ' -> ', B, ' recusado: ', Err, ')');
end;

{ grafo do README: 4 projetos em paralelo -> montagem -> validacao -> marco ->
  fabricacoes (corte -> arte encadeadas) -> montagem fisica -> teste -> fim }
function BuildMotor: TPJProject;
var P: TPJProject; T: TPJTask;
  procedure Add(AKind: TPJTaskKind; const AName: string; AProcess: TPJProcess = prNone);
  begin
    T := P.AddTask('', AKind, AName, AName);
    T.Process := AProcess;
  end;
begin
  P := TPJProject.Create;
  P.Name := 'Motor DC didatico';
  P.ObjectiveShort := 'Motor DC 12 V';
  Add(tkPart, 'Carcaca', prPrint3D);        // T-0001
  Add(tkPart, 'Eixo', prLathe);             // T-0002
  Add(tkPart, 'Base MDF', prLaserCut);      // T-0003
  Add(tkElectronics, 'Driver ponte H');     // T-0004
  Add(tkAssembly, 'Montagem virtual');      // T-0005
  Add(tkValidation, 'Validacao');           // T-0006
  Add(tkMilestone, 'Liberado p/ fabricacao'); // M-0007
  Add(tkPrint3D, 'Imprimir carcaca');       // T-0008
  Add(tkLathe, 'Tornear eixo');             // T-0009
  Add(tkLaserCut, 'Cortar base');           // T-0010
  Add(tkLaserArt, 'Gravar logo');           // T-0011
  Add(tkPCBFab, 'Fabricar placa');          // T-0012
  Add(tkPhysicalAssembly, 'Montagem fisica'); // T-0013
  Add(tkFunctionalTest, 'Teste funcional'); // T-0014
  Add(tkMilestone, 'Objetivo concluido');   // M-0015
  Link(P, 'T-0001', 'T-0005'); Link(P, 'T-0002', 'T-0005');
  Link(P, 'T-0003', 'T-0005'); Link(P, 'T-0004', 'T-0005');
  Link(P, 'T-0005', 'T-0006'); Link(P, 'T-0006', 'M-0007', atlFS, False);
  Link(P, 'M-0007', 'T-0008', atlFS, False); Link(P, 'M-0007', 'T-0009', atlFS, False);
  Link(P, 'M-0007', 'T-0010', atlFS, False); Link(P, 'M-0007', 'T-0012', atlFS, False);
  Link(P, 'T-0010', 'T-0011');
  Link(P, 'T-0008', 'T-0013'); Link(P, 'T-0009', 'T-0013');
  Link(P, 'T-0011', 'T-0013'); Link(P, 'T-0012', 'T-0013');
  Link(P, 'T-0013', 'T-0014', atlFS, False); Link(P, 'T-0014', 'M-0015', atlFS, False);
  P.ClearHistory;
  P.Modified := False;
  Result := P;
end;

procedure TestMotor;
var P: TPJProject; C: TPJChains; Err, Before: string;
begin
  P := BuildMotor;
  try
    Check(P.LinkCount = 17, '17 vinculos do README');
    Check(P.CheckLinks(Err), 'grafo do motor valido: ' + Err);
    C := TaskChains(P);
    Check(Length(C) = 1, 'o motor e uma cadeia so');
    Check(TaskRelation(P, 'T-0001', 'T-0002') = atrParallel, 'carcaca e eixo em paralelo');
    Check(TaskRelation(P, 'T-0001', 'T-0013') = atrPredecessor, 'carcaca antes da montagem fisica (em cadeia)');
    Check(TaskRelation(P, 'T-0013', 'T-0004') = atrSuccessor, 'montagem fisica depois do driver');
    Check(TaskRelation(P, 'T-0010', 'T-0011') = atrPredecessor, 'corte -> arte encadeados');
    Check(TaskRelation(P, 'T-0008', 'T-0011') = atrParallel, 'impressao e arte em paralelo');
    Check(RelationCaption(atrParallel) = 'em paralelo', 'rotulo da relacao');
    Check(P.PredecessorsText('T-0005') = 'T-0001;T-0002;T-0003;T-0004', 'predecessoras da montagem: ' + P.PredecessorsText('T-0005'));
    Check(P.SuccessorsText('M-0007') = 'T-0008;T-0009;T-0010;T-0012', 'sucessoras do marco');
    { ciclo: teste funcional -> carcaca fecharia o laco }
    Before := Body(P);
    Check(not P.AddLink('T-0014', 'T-0001', atlFS, AINoLag, False, Err), 'ciclo recusado');
    Check(Pos('T-0014 -> T-0001 -> T-0005 -> T-0006 -> M-0007 -> T-0008 -> T-0013 -> T-0014', Err) > 0,
      'caminho do ciclo na mensagem: ' + Err);
    Check((Body(P) = Before) and not P.CanUndo and not P.Modified, 'documento intacto apos a recusa');
    Check(not P.AddLink('T-0001', 'T-0005', atlSS, AINoLag, False, Err) and (Pos('ja existe', Err) > 0), 'duplicado recusado');
    Check(not P.AddLink('T-0001', 'T-0001', atlFS, AINoLag, False, Err), 'auto-vinculo recusado');
    Check(not P.AddLink('T-0001', 'T-9999', atlFS, AINoLag, False, Err) and (Pos('inexistente', Err) > 0), 'tarefa inexistente');
    Check(ErrorCount(P.Validate) = 0, 'validacao sem erros');
  finally
    P.Free;
  end;
end;

procedure TestChains;
var P: TPJProject; C: TPJChains; I: Integer;
begin
  P := TPJProject.Create;
  try
    for I := 1 to 7 do P.AddTask('', tkGeneral, 'T' + IntToStr(I), 'x');
    Link(P, 'T-0001', 'T-0002'); Link(P, 'T-0002', 'T-0003');
    Link(P, 'T-0004', 'T-0005', atlSS);
    Link(P, 'T-0007', 'T-0006', atlFF);
    C := TaskChains(P);
    Check(Length(C) = 3, 'tres cadeias');
    Check((Length(C[0]) = 3) and (C[0][0] = 0) and (C[1][0] = 3) and (C[2][0] = 5), 'cadeias na ordem das tarefas');
    Check((Length(C[2]) = 2) and (C[2][1] = 6), 'terceira cadeia {T-0006, T-0007}');
    Check(TaskRelation(P, 'T-0001', 'T-0004') = atrParallel, 'cadeias diferentes = paralelo');
  finally
    P.Free;
  end;
end;

procedure TestEditing;
var P: TPJProject; Err, Before: string; L: TAITaskLag;
begin
  P := BuildMotor;
  try
    Before := Body(P);
    Check(P.RemoveLink('T-0010', 'T-0011'), 'desvincular corte -> arte');
    Check(TaskRelation(P, 'T-0010', 'T-0011') = atrParallel, 'agora em paralelo');
    Check(P.Undo and (Body(P) = Before), 'desfazer desvincular');
    Check(P.Redo and (P.IndexOfLink('T-0010', 'T-0011') < 0), 'refazer desvincular');
    Check(P.Undo, 'desfazer de novo');
    { latencia de cura: arte comeca 24 h corridas depois do corte }
    Check(AITryParseLag('+24eh', 480, 2400, L, Err), 'latencia');
    Check(P.UpdateLink('T-0010', 'T-0011', atlFS, L, True, Err), 'alterar vinculo: ' + Err);
    Check(P.PredecessorsText('T-0011') = 'T-0010TI+24eh', 'predecessoras com latencia: ' + P.PredecessorsText('T-0011'));
    Check(P.Undo and (Body(P) = Before), 'desfazer alterar vinculo');
    Check(not P.UpdateLink('T-0001', 'T-0002', atlFS, L, True, Err), 'alterar vinculo inexistente');
    { coluna Predecessoras }
    Check(P.SetPredecessorsText('T-0005', 'T-0001;T-0002II+2h;T-0003TT-10%;T-0004', Err), 'digitar predecessoras: ' + Err);
    Check(P.PredecessorsText('T-0005') = 'T-0001;T-0002II+2h;T-0003TT-10%;T-0004', 'ida e volta: ' + P.PredecessorsText('T-0005'));
    Check(P.Links[P.IndexOfLink('T-0002', 'T-0005')].Artifact, 'entrega artefato mantida ao redigitar');
    Check(P.UndoDescription = 'Alterar predecessoras', 'um passo de desfazer');
    Check(P.Undo and (Body(P) = Before), 'desfazer predecessoras');
    Check(P.SetPredecessorsText('T-0005', 'T-0001; T-0004', Err) and (P.PredecessorsText('T-0005') = 'T-0001;T-0004'),
      'remover predecessoras digitando');
    Check(P.Undo, 'desfazer remocao');
    Before := Body(P);
    Check(not P.SetPredecessorsText('T-0001', 'T-0013', Err) and (Pos('ciclo', Err) > 0), 'predecessora que fecha ciclo: ' + Err);
    Check(not P.SetPredecessorsText('T-0001', 'T-0001', Err) and (Pos('si mesma', Err) > 0), 'predecessora de si mesma');
    Check(not P.SetPredecessorsText('T-0001', 'T-0099', Err) and (Pos('desconhecida', Err) > 0), 'predecessora desconhecida: ' + Err);
    Check(not P.SetPredecessorsText('T-0001', 'T-0002TI+abc', Err), 'latencia invalida');
    Check(Body(P) = Before, 'recusas nao alteram o documento');
    Check(P.SetPredecessorsText('T-0001', '', Err), 'vazio = sem predecessoras');
    { excluir tarefa leva os vinculos }
    Check(P.DeleteTask('T-0010'), 'excluir corte');
    Check((P.IndexOfLink('M-0007', 'T-0010') < 0) and (P.IndexOfLink('T-0010', 'T-0011') < 0), 'vinculos da tarefa excluida saem');
    Check(P.CheckLinks(Err), 'grafo valido depois de excluir');
    Check(P.Undo and (P.IndexOfLink('T-0010', 'T-0011') >= 0), 'desfazer exclusao devolve os vinculos');
  finally
    P.Free;
  end;
end;

procedure TestLinkChain;
var P: TPJProject; Err, Before: string; I: Integer;
begin
  P := TPJProject.Create;
  try
    for I := 1 to 4 do P.AddTask('', tkGeneral, 'T' + IntToStr(I), 'x');
    P.ClearHistory;
    Check(P.LinkChain(['T-0001', 'T-0002', 'T-0003'], Err), 'Ctrl+F2 em cadeia');
    Check((P.LinkCount = 2) and (P.UndoDescription = 'Vincular tarefas') and P.CanUndo, 'cadeia criada');
    P.Undo;
    Check((P.LinkCount = 0) and not P.CanUndo, 'cadeia e um unico desfazer');
    P.Redo;
    Before := Body(P);
    Check(not P.LinkChain(['T-0004', 'T-0003', 'T-0001'], Err) and (Pos('ciclo', Err) > 0), 'cadeia que fecha ciclo: ' + Err);
    Check(Body(P) = Before, 'cadeia recusada nao deixa vinculo pela metade');
  finally
    P.Free;
  end;
end;

procedure TestSummaries;
var P: TPJProject; S, A, B, X: TPJTask; Err, Before: string;
begin
  P := TPJProject.Create;
  try
    S := P.AddTask('', tkSummary, 'Estrutura', 's');   // T-0001
    A := P.AddTask(S.Id, tkPart, 'Peca A', 'a');        // T-0002
    B := P.AddTask(S.Id, tkPart, 'Peca B', 'b');        // T-0003
    X := P.AddTask('', tkAssembly, 'Montagem', 'm');    // T-0004
    Check(P.AddLink(S.Id, X.Id, atlFS, AINoLag, True, Err), 'resumo -> montagem: ' + Err);
    Check(TaskRelation(P, A.Id, X.Id) = atrPredecessor, 'vinculo do resumo vale para a folha A');
    Check(TaskRelation(P, B.Id, X.Id) = atrPredecessor, 'e para a folha B');
    Check(Length(TaskChains(P)) = 1, 'folhas do resumo na mesma cadeia');
    Check(Length(LeafIndexes(P, 0)) = 2, 'duas folhas no resumo');
    Check(not P.AddLink(S.Id, A.Id, atlFS, AINoLag, False, Err) and (Pos('proprias subtarefas', Err) > 0),
      'resumo -> propria subtarefa recusado: ' + Err);
    Check(not P.AddLink(X.Id, A.Id, atlFS, AINoLag, False, Err) and (Pos('subtarefas', Err) > 0) and (Pos('ciclo', Err) > 0),
      'ciclo pelas subtarefas: ' + Err);
    { recuar a montagem para dentro do resumo deixaria resumo -> propria subtarefa }
    Before := Body(P);
    Check(not P.Indent(X.Id), 'recuo que invalida vinculo e recusado');
    Check(Pos('vinculo invalido', P.LastError) > 0, 'motivo do recuo recusado: ' + P.LastError);
    Check((Body(P) = Before) and (P.UndoDescription = 'Vincular tarefas'), 'recuo recusado nao altera nem grava desfazer');
    { avancar A cria a tarefa de nivel 1 A e B vira filha dela: A -> X continua valido }
    Check(P.Outdent(A.Id), 'avancar peca A: ' + P.LastError);
    Check(P.CheckLinks(Err), 'grafo valido apos avancar');
  finally
    P.Free;
  end;
end;

procedure TestFile;
var P, Q: TPJProject; FN, A, B, Err: string; L: TAITaskLag;
begin
  FN := TmpDir + 'motor_links.mproj';
  P := BuildMotor;
  Q := TPJProject.Create;
  try
    AITryParseLag('-10%', 480, 2400, L, Err);
    P.UpdateLink('T-0003', 'T-0005', atlSS, L, True, Err);
    AITryParseLag('+24eh', 480, 2400, L, Err);
    P.UpdateLink('T-0010', 'T-0011', atlFF, L, False, Err);
    SaveProjectFile(P, FN);
    LoadProjectFile(Q, FN);
    Check(Q.LinkCount = 17, 'vinculos lidos');
    Check(Q.PredecessorsText('T-0005') = P.PredecessorsText('T-0005'), 'predecessoras iguais: ' + Q.PredecessorsText('T-0005'));
    Check(Q.PredecessorsText('T-0011') = 'T-0010TT+24eh', 'latencia decorrida lida: ' + Q.PredecessorsText('T-0011'));
    Check(Q.Links[Q.IndexOfLink('T-0003', 'T-0005')].Artifact and not Q.Links[Q.IndexOfLink('T-0010', 'T-0011')].Artifact,
      'entrega artefato lida');
    A := AIReadTextFile(FN);
    Check(Pos('"type" : "SS"', A) > 0, 'tipo gravado com o codigo do Project (FS/SS/FF/SF)');
    SaveProjectFile(Q, FN);
    B := AIReadTextFile(FN);
    Check(A = B, 'segunda gravacao identica com vinculos');
  finally
    P.Free;
    Q.Free;
  end;
  DeleteFile(FN);
end;

procedure ExpectBad(const Links, Part, What: string);
var P: TPJProject; Msg: string;
begin
  P := TPJProject.Create;
  try
    P.Name := 'intacto';
    Msg := '';
    try
      ProjectFromJSONText(P,
        '{ "schema_version": 1, "format": "MultiProject", "name": "novo", "tasks": [' +
        '{"id":"T-0001","name":"S"},{"id":"T-0002","name":"A","parent":"T-0001"},' +
        '{"id":"T-0003","name":"B"},{"id":"T-0004","name":"C"} ], "links": [' + Links + '] }');
    except
      on E: EPJFormat do Msg := E.Message;
    end;
    Check((Msg <> '') and (Pos(Part, Msg) > 0), What + ': "' + Msg + '"');
    Check(P.Name = 'intacto', What + ': documento nao alterado');
  finally
    P.Free;
  end;
end;

procedure TestBadFiles;
begin
  ExpectBad('{"from":"T-0003","to":"T-0004"},{"from":"T-0004","to":"T-0003"}', 'ciclo', 'arquivo com ciclo');
  ExpectBad('{"from":"T-0003","to":"T-0099"}', 'inexistente', 'vinculo para tarefa inexistente');
  ExpectBad('{"from":"T-0003","to":"T-0004"},{"from":"T-0003","to":"T-0004","type":"SS"}', 'repetido', 'vinculo repetido');
  ExpectBad('{"from":"T-0001","to":"T-0002"}', 'proprias subtarefas', 'resumo ligado a subtarefa');
  ExpectBad('{"from":"T-0003","to":"T-0004","type":"XX"}', 'tipo desconhecido', 'tipo de vinculo desconhecido');
  ExpectBad('{"to":"T-0004"}', 'from', 'vinculo sem origem');
end;

procedure TestScale;
var
  P: TPJProject;
  I, A, B: Integer;
  Links: TStringList;
  G: TAITaskGraph;
  Err, Text: string;
  T0, Ms: QWord;
begin
  { 2000 tarefas e 4000 vinculos para frente (aciclico): montar o grafo e rapido }
  RandSeed := 42;
  Links := TStringList.Create;
  P := TPJProject.Create;
  try
    Text := '{ "schema_version": 1, "format": "MultiProject", "tasks": [';
    for I := 1 to 2000 do
    begin
      if I > 1 then Text := Text + ',';
      Text := Text + Format('{"id":"T-%.4d","name":"t","short":"s"}', [I]);
    end;
    Text := Text + '], "links": [';
    I := 0;
    while Links.Count < 4000 do
    begin
      A := 1 + Random(1999);
      B := A + 1 + Random(Min(50, 2000 - A));
      if Links.IndexOf(Format('%d>%d', [A, B])) >= 0 then Continue;
      Links.Add(Format('%d>%d', [A, B]));
      if I > 0 then Text := Text + ',';
      Text := Text + Format('{"from":"T-%.4d","to":"T-%.4d"}', [A, B]);
      Inc(I);
    end;
    Text := Text + '] }';
    ProjectFromJSONText(P, Text);
    Check((P.Count = 2000) and (P.LinkCount = 4000), '2000 tarefas e 4000 vinculos lidos');
    T0 := GetTickCount64;
    G := BuildTaskGraph(P, Err);
    try
      Check(G <> nil, 'grafo grande valido: ' + Err);
      if G <> nil then Check(Length(G.TopologicalOrder) = 2000, 'ordem topologica de 2000 tarefas');
    finally
      G.Free;
    end;
    Ms := GetTickCount64 - T0;
    Check(Ms < 1000, Format('grafo de 2000 tarefas em %d ms', [Ms]));
  finally
    P.Free;
    Links.Free;
  end;
end;

begin
  Passed := 0; Failed := 0;
  TmpDir := IncludeTrailingPathDelimiter(GetTempDir(False));
  TestMotor;
  TestChains;
  TestEditing;
  TestLinkChain;
  TestSummaries;
  TestFile;
  TestBadFiles;
  TestScale;
  if Failed = 0 then
    Writeln(Format('PASS: %d checks (motor do README, ciclo, cadeias, predecessoras, resumos, desfazer, .mproj, 2000 tarefas)', [Passed]))
  else
  begin
    Writeln(Format('FAIL: %d de %d checks', [Failed, Passed + Failed]));
    Halt(1);
  end;
end.
