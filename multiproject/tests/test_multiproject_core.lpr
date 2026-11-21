program test_multiproject_core;

{ Fase 1 do MultiProject (multiproject/docs/TAREFA.md, itens 1.3 a 1.7):
  tarefas com os 6 campos, estrutura de topicos/EAP, IDs estaveis, desfazer e
  refazer de cada comando, durações, .mproj (ida e volta identica, campos
  desconhecidos, versao futura, regional com virgula, gravacao atomica) e
  validacao. Sem LCL. }

{$mode objfpc}{$H+}

uses
  Classes, SysUtils, fpjson, aiprojectduration, aijsonutils,
  multiproject_types, multiproject_document, multiproject_json;

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

function Outline(P: TPJProject): string;
var I: Integer;
begin
  { "WBS:ID" por linha, para comparar a arvore inteira }
  Result := '';
  for I := 0 to P.Count - 1 do
  begin
    if I > 0 then Result := Result + ' ';
    Result := Result + P.WBS(I) + ':' + P[I].Id;
  end;
end;

function HasIssue(const L: TPJIssues; const TaskId: string; Sev: TPJSeverity; const Part: string): Boolean;
var I: Integer;
begin
  for I := 0 to High(L) do
    if SameText(L[I].TaskId, TaskId) and (L[I].Severity = Sev) and (Pos(Part, L[I].Message) > 0) then
      Exit(True);
  Result := False;
end;

{ JSON do documento sem a linha do contador de IDs, que de proposito nao volta
  com o desfazer }
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

{ Motor DC: 2 subsistemas com tarefas, como no README do modulo }
function BuildMotor: TPJProject;
var P: TPJProject; S1, S2, T: TPJTask;
begin
  P := TPJProject.Create;
  P.Id := 'P-2026-0001';
  P.Name := 'Motor DC didatico';
  P.ObjectiveShort := 'Construir um motor DC escovado de 12 V';
  S1 := P.AddTask('', tkSummary, 'Estrutura', 'Pecas mecanicas do motor');   // T-0001
  T := P.AddTask(S1.Id, tkPart, 'Carcaca do estator', 'Carcaca que fixa os imas'); // T-0002
  T.Process := prPrint3D;
  T.LongDesc := 'Carcaca impressa em PETG.';
  T.AddTechItem('material', 'PETG', '');
  T.AddTechItem('diametro_externo', '60', 'mm');
  T.TechText := 'Encaixe H7 para o rolamento 608.';
  T.AddCriterion('F-1', 'Suporta 60 C sem deformar');
  T := P.AddTask(S1.Id, tkPart, 'Eixo do rotor', 'Eixo de aco 5 mm');        // T-0003
  T.Process := prLathe;
  S2 := P.AddTask('', tkSummary, 'Eletronica', 'Driver e alimentacao');      // T-0004
  P.AddTask(S2.Id, tkElectronics, 'Driver ponte H', 'Placa de acionamento'); // T-0005
  P.AddTask('', tkMilestone, 'Objetivo concluido', 'Motor funcionando');     // M-0006
  P.ClearHistory;
  P.Modified := False;
  Result := P;
end;

procedure TestStructure;
var P: TPJProject; Kids: TPJIntArray; Msg: string;
begin
  P := BuildMotor;
  try
    Check(Outline(P) = '1:T-0001 1.1:T-0002 1.2:T-0003 2:T-0004 2.1:T-0005 3:M-0006',
      'EAP inicial: ' + Outline(P));
    Check(P.IsSummary(0) and not P.IsSummary(1), 'resumo pela existencia de filhas');
    Check(P.ParentId(2) = 'T-0001', 'pai de T-0003');
    Check(P.ParentId(3) = '', 'filha do objetivo');
    Kids := P.ChildIndexes(-1);
    Check(Length(Kids) = 3, 'tres filhas do objetivo');
    Check(P.FindTask('M-0006').Duration.Minutes = 0, 'marco com duracao zero');
    Check(P.IndexOfWBS('2.1') = 4, 'busca pelo codigo EAP');
    { recuar: Eletronica vira filha de Estrutura (e leva a filha junto) }
    Check(P.Indent('T-0004'), 'recuar T-0004');
    Check(Outline(P) = '1:T-0001 1.1:T-0002 1.2:T-0003 1.3:T-0004 1.3.1:T-0005 2:M-0006',
      'EAP depois de recuar: ' + Outline(P));
    Check(not P.Indent('T-0001'), 'a primeira tarefa nao recua');
    Check(not P.Indent('T-0002'), 'nao recua sem irma anterior no mesmo nivel');
    { avancar volta ao nivel 1 }
    Check(P.Outdent('T-0004'), 'avancar T-0004');
    Check(Outline(P) = '1:T-0001 1.1:T-0002 1.2:T-0003 2:T-0004 2.1:T-0005 3:M-0006',
      'EAP depois de avancar: ' + Outline(P));
    Check(not P.Outdent('T-0001'), 'nivel 1 nao avanca');
    { avancar no meio: as irmas seguintes viram filhas (como no Project) }
    Check(P.Outdent('T-0002'), 'avancar T-0002');
    Check(Outline(P) = '1:T-0001 2:T-0002 2.1:T-0003 3:T-0004 3.1:T-0005 4:M-0006',
      'avancar no meio adota as irmas seguintes: ' + Outline(P));
    Check(P.Undo, 'desfazer avancar');
    { mover com a subarvore }
    Check(P.MoveDown('T-0001'), 'descer Estrutura');
    Check(Outline(P) = '1:T-0004 1.1:T-0005 2:T-0001 2.1:T-0002 2.2:T-0003 3:M-0006',
      'mover leva a subarvore: ' + Outline(P));
    Check(P.MoveUp('T-0003'), 'subir T-0003 entre irmas');
    Check(Outline(P) = '1:T-0004 1.1:T-0005 2:T-0001 2.1:T-0003 2.2:T-0002 3:M-0006',
      'subir entre irmas: ' + Outline(P));
    Check(not P.MoveUp('T-0003'), 'nao sobe acima do pai');
    Check(not P.MoveDown('M-0006'), 'ultima nao desce');
    Check(P.CheckOutline(Msg), 'estrutura valida: ' + Msg);
  finally
    P.Free;
  end;
end;

procedure TestIds;
var P: TPJProject; T: TPJTask;
begin
  P := BuildMotor;
  try
    Check(P.DeleteTask('T-0004'), 'excluir resumo com filha');
    Check((P.FindTask('T-0004') = nil) and (P.FindTask('T-0005') = nil), 'excluir leva a subarvore');
    T := P.AddTask('', tkGeneral, 'Nova', 'Depois de excluir');
    Check(T.Id = 'T-0007', 'ID nao reaproveitado: ' + T.Id);
    T := P.AddTask('', tkMilestone, 'Marco', 'M');
    Check(T.Id = 'M-0008', 'marco usa o mesmo contador: ' + T.Id);
    Check(P.Undo and (P.FindTask('M-0008') = nil), 'desfazer insercao');
    T := P.AddTask('', tkGeneral, 'Outra', 'O');
    Check(T.Id = 'T-0009', 'contador nao volta depois de desfazer: ' + T.Id);
  finally
    P.Free;
  end;
end;

procedure TestUndo;
var P: TPJProject; Before, Err: string;
begin
  P := BuildMotor;
  try
    Check(not P.CanUndo and not P.Modified, 'historico limpo');
    Before := Body(P);
    P.InsertTask(1, tkGeneral, 'X', 'x');
    Check(P.Modified and (P.UndoDescription = 'Inserir tarefa'), 'inserir marca alterado');
    Check(P.Undo and (Body(P) = Before), 'desfazer inserir');
    Check(P.Redo and (P.Count = 7), 'refazer inserir');
    Check(P.Undo, 'desfazer de novo');
    P.DeleteTask('T-0001');
    Check(P.Undo and (Body(P) = Before), 'desfazer excluir');
    P.Indent('T-0004');
    Check(P.Undo and (Body(P) = Before), 'desfazer recuar');
    P.MoveDown('T-0001');
    Check(P.Undo and (Body(P) = Before), 'desfazer mover');
    P.SetKind('T-0002', tkPurchase);
    Check(P.Undo and (P.FindTask('T-0002').Kind = tkPart), 'desfazer tipo');
    Check(P.SetDurationText('T-0002', '14eh', Err), 'duracao decorrida: ' + Err);
    Check(P.FindTask('T-0002').Duration.Elapsed and (P.FindTask('T-0002').Duration.Minutes = 840), '14eh = 840 min');
    Check(P.Undo and (Body(P) = Before), 'desfazer duracao');
    Check(not P.SetDurationText('M-0006', '1d', Err) and (Pos('marco', Err) > 0), 'marco recusa duracao: ' + Err);
    Check(not P.SetDurationText('T-0002', 'xyz', Err), 'duracao invalida recusada');
    { edicao livre agrupada = um passo }
    P.BeginChange('Editar descricoes');
    P.FindTask('T-0002').Name := 'Carcaca v2';
    P.BeginChange('interno');
    P.FindTask('T-0003').ShortDesc := 'Eixo 6 mm';
    P.EndChange;
    P.EndChange;
    Check(P.UndoDescription = 'Editar descricoes', 'grupo e um passo');
    Check(P.Undo and (Body(P) = Before), 'desfazer grupo inteiro');
    Check(not P.CanUndo, 'sem mais passos');
    Check(P.NextNumber = 8, 'contador nao volta com o desfazer');
    { a tarefa restaurada continua editavel (objetos novos) }
    P.FindTask('T-0002').Name := 'ok';
    Check(P.FindTask('T-0002').Name = 'ok', 'tarefa restaurada editavel');
  finally
    P.Free;
  end;
end;

procedure TestValidate;
var P: TPJProject; L: TPJIssues; T: TPJTask;
begin
  P := BuildMotor;
  try
    L := P.Validate;
    Check(ErrorCount(L) = 0, 'exemplo valido');
    Check(HasIssue(L, 'T-0005', svWarning, 'Impressao') = False, 'eletronica nao pede processo');
    T := P.AddTask('', tkGeneral, '', '');
    L := P.Validate;
    Check(HasIssue(L, T.Id, svError, 'nome'), 'recusa tarefa sem nome');
    Check(HasIssue(L, T.Id, svError, 'descricao curta'), 'recusa tarefa sem descricao curta');
    T.Name := 'Nome'; T.ShortDesc := 'curta';
    T := P.AddTask('', tkPart, 'Peca sem processo', 'p');
    L := P.Validate;
    Check(HasIssue(L, T.Id, svWarning, 'processo'), 'aviso de peca sem processo');
    P.FindTask('M-0006').Duration.Minutes := 60;
    L := P.Validate;
    Check(HasIssue(L, 'M-0006', svError, 'marco'), 'marco com duracao e erro');
    P.FindTask('M-0006').Duration.Minutes := 0;
    P.FindTask('T-0002').Kind := tkSummary;
    L := P.Validate;
    Check(HasIssue(L, 'T-0002', svWarning, 'resumo sem subtarefas'), 'resumo sem filhas');
    P.FindTask('T-0001').Kind := tkPart;
    P.FindTask('T-0001').Process := prRouter;
    L := P.Validate;
    Check(HasIssue(L, 'T-0001', svWarning, 'subtarefas'), 'tarefa com filhas e tipo peca');
    P.ObjectiveShort := '';
    L := P.Validate;
    Check(HasIssue(L, '', svWarning, 'objetivo'), 'objetivo sem descricao');
  finally
    P.Free;
  end;
end;

procedure TestJSONRoundTrip;
var
  P, Q: TPJProject;
  FN, A, B: string;
  T: TPJTask;
begin
  FN := TmpDir + 'motor.mproj';
  P := BuildMotor;
  Q := TPJProject.Create;
  try
    P.StartDate := EncodeDate(2026, 10, 26) + EncodeTime(8, 0, 0, 0);
    P.FindTask('T-0002').Duration := AIMakeDuration(720, aduDay, False, True);
    SaveProjectFile(P, FN);
    Check(not P.Modified, 'gravar limpa o alterado');
    Check(not FileExists(FN + '.tmp') and not FileExists(FN + '.bak'), 'sem .tmp/.bak');
    A := AIReadTextFile(FN);
    LoadProjectFile(Q, FN);
    Check(Outline(Q) = Outline(P), 'EAP igual depois de ler');
    T := Q.FindTask('T-0002');
    Check((T.Name = 'Carcaca do estator') and (T.ShortDesc = 'Carcaca que fixa os imas') and
      (T.LongDesc = 'Carcaca impressa em PETG.'), 'nome e descricoes');
    Check((Length(T.TechItems) = 2) and (T.TechValue('diametro_externo') = '60') and
      (T.TechItems[1].UnitName = 'mm') and (T.TechText = 'Encaixe H7 para o rolamento 608.'),
      'especificacao tecnica');
    Check((Length(T.FuncSpec) = 1) and (T.FuncSpec[0].Text = 'Suporta 60 C sem deformar') and
      (T.FuncSpec[0].State = csPending), 'especificacao funcional');
    Check((T.Kind = tkPart) and (T.Process = prPrint3D), 'tipo e processo');
    Check((T.Duration.Minutes = 720) and T.Duration.Estimated and (Q.FormatDur(T.Duration) = '1.5d?'),
      'duracao estimada 1.5d?');
    Check(Q.StartDate = P.StartDate, 'data de inicio');
    Check(Q.NextNumber = P.NextNumber, 'contador de IDs');
    { segunda gravacao identica byte a byte }
    SaveProjectFile(Q, FN);
    B := AIReadTextFile(FN);
    Check(A = B, 'segunda gravacao identica');
  finally
    P.Free;
    Q.Free;
  end;
end;

procedure TestUnknownFields;
var
  P: TPJProject;
  Text, Out_: string;
begin
  { campos de versoes futuras (links, artifact, opcoes) sobrevivem a ler+gravar }
  Text :=
    '{ "schema_version": 1, "format": "MultiProject", "id": "P-1", "name": "N",' +
    '  "futuro": { "x": 1 },' +
    '  "options": { "minutes_per_day": 420, "minutes_per_week": 2100, "fabrication_gate": true },' +
    '  "links": [ { "from": "T-0002", "to": "T-0003", "type": "FS", "futuro_link": 1 } ],' +
    '  "tasks": [' +
    '    { "id": "T-0001", "name": "A", "short": "a", "kind": "part", "process": "router",' +
    '      "artifact": { "path": "pecas/T-0001_a.mcad", "status": "none" } },' +
    '    { "id": "T-0002", "name": "B", "short": "b", "parent": "T-0001", "func_spec": ["roda", "liga"] },' +
    '    { "id": "T-0003", "name": "C", "short": "c" } ] }';
  P := TPJProject.Create;
  try
    ProjectFromJSONText(P, Text);
    Check(P.MinutesPerDay = 420, 'minutos por dia lidos');
    Check(P.NextNumber = 4, 'contador acima do maior ID');
    Check(P[1].Level = 2, 'nivel pelo pai');
    Check((Length(P[1].FuncSpec) = 2) and (P[1].FuncSpec[1].Text = 'liga'), 'forma curta dos criterios');
    Check(P.FormatDur(AIMakeDuration(420, aduDay)) = '1d', 'dia de 7 h');
    P.BeginChange('editar'); P[0].Name := 'A2'; P.EndChange;
    Out_ := ProjectToJSONText(P);
    Check(Pos('"futuro"', Out_) > 0, 'campo desconhecido do projeto preservado');
    Check(Pos('"fabrication_gate" : true', Out_) > 0, 'opcao desconhecida preservada');
    Check(Pos('"futuro_link" : 1', Out_) > 0, 'campo desconhecido do vinculo preservado');
    Check((P.LinkCount = 1) and (P.Links[0].ToId = 'T-0003'), 'vinculo lido');
    Check(Pos('pecas/T-0001_a.mcad', Out_) > 0, 'artefato da tarefa preservado');
    Check(Pos('"A2"', Out_) > 0, 'alteracao gravada');
    Check(Pos('"futuro"', Out_) < Pos('"options"', Out_), 'ordem original mantida');
  finally
    P.Free;
  end;
end;

procedure ExpectFormatError(const Text, Part, What: string);
var P: TPJProject; Msg: string;
begin
  P := TPJProject.Create;
  try
    P.Name := 'intacto';
    Msg := '';
    try
      ProjectFromJSONText(P, Text);
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
var P: TPJProject; FN, Original: string; Raised: Boolean;
begin
  ExpectFormatError('{ "schema_version": 2, "format": "MultiProject" }', 'versao 2', 'versao futura');
  ExpectFormatError('{ "schema_version": 1, "format": "Outro" }', 'nao e do MultiProject', 'outro formato');
  ExpectFormatError('{ "format": "MultiProject" }', 'schema_version', 'sem versao');
  ExpectFormatError('{ quebrado', 'JSON invalido', 'JSON quebrado');
  ExpectFormatError('{ "schema_version": 1, "format": "MultiProject", "tasks": [ {"id":"T-0001","kind":"foguete"} ] }',
    'tipo desconhecido', 'tipo desconhecido');
  ExpectFormatError('{ "schema_version": 1, "format": "MultiProject", "tasks": [ {"id":"T-0001"}, {"id":"T-0001"} ] }',
    'ID repetido', 'ID repetido');
  ExpectFormatError('{ "schema_version": 1, "format": "MultiProject", "tasks": [ {"id":"T-0002","parent":"T-0001"}, {"id":"T-0001"} ] }',
    'ordem de topicos', 'pai depois da filha');
  ExpectFormatError('{ "schema_version": 1, "format": "MultiProject", "start": "26/10/2026" }',
    'data invalida', 'data no formato brasileiro');
  ExpectFormatError('{ "schema_version": 1, "format": "MultiProject", "tasks": [ {"id":"T-0001","duration":"8h"} ] }',
    'numero', 'duracao em texto');
  { arquivo de versao futura no disco nao e alterado ao tentar abrir }
  FN := TmpDir + 'futuro.mproj';
  Original := '{ "schema_version": 9, "format": "MultiProject", "id": "X" }';
  AIWriteTextFile(FN, Original);
  P := TPJProject.Create;
  try
    Raised := False;
    try LoadProjectFile(P, FN); except on EPJFormat do Raised := True; end;
    Check(Raised and (AIReadTextFile(FN) = Original), 'versao futura no disco intacta');
  finally
    P.Free;
  end;
end;

procedure TestRegional;
var P: TPJProject; A, B, Err: string; Keep: Char; D: TAIDuration;
begin
  P := BuildMotor;
  try
    P.StartDate := EncodeDate(2026, 10, 26);
    P.FindTask('T-0002').Duration := AIMakeDuration(720, aduDay);
    A := ProjectToJSONText(P);
    Keep := DefaultFormatSettings.DecimalSeparator;
    DefaultFormatSettings.DecimalSeparator := ',';
    try
      B := ProjectToJSONText(P);
      Check(A = B, 'arquivo igual com regional virgula');
      Check(P.FormatDur(P.FindTask('T-0002').Duration) = '1.5d', 'exibe com ponto');
      Check(P.ParseDur('1,5d', D, Err) and (D.Minutes = 720), 'aceita virgula digitada');
    finally
      DefaultFormatSettings.DecimalSeparator := Keep;
    end;
  finally
    P.Free;
  end;
end;

begin
  Passed := 0; Failed := 0;
  TmpDir := IncludeTrailingPathDelimiter(GetTempDir(False)) + 'multiproject_test_' + IntToStr(GetProcessID) + PathDelim;
  ForceDirectories(TmpDir);
  TestStructure;
  TestIds;
  TestUndo;
  TestValidate;
  TestJSONRoundTrip;
  TestUnknownFields;
  TestBadFiles;
  TestRegional;
  DeleteFile(TmpDir + 'motor.mproj');
  DeleteFile(TmpDir + 'futuro.mproj');
  RemoveDir(TmpDir);
  if Failed = 0 then
    Writeln(Format('PASS: %d checks (EAP, IDs, desfazer, validacao, .mproj, campos desconhecidos, arquivos invalidos, regional)', [Passed]))
  else
  begin
    Writeln(Format('FAIL: %d de %d checks', [Failed, Passed + Failed]));
    Halt(1);
  end;
end.
