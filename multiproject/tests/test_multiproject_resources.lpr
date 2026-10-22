program test_multiproject_resources;

{ Testes de console da fase 7 do MultiProject: recursos (pessoas, maquinas,
  material), atribuicoes, compatibilidade maquina x tarefa, superalocacao,
  nivelamento e limpeza, coluna Recursos no estilo do Project, .mproj e
  importacao das maquinas do cadastro do MultiCNC. }

{$mode objfpc}{$H+}

uses
  Classes, SysUtils, fpjson, jsonparser, aiprojectduration, aitaskgraph, aiworkcalendar,
  aicpmscheduler, airesourceload, multiproject_types, multiproject_document,
  multiproject_json, multiproject_schedule, multiproject_resources, multiproject_examples;

var
  Passed, Failed: Integer;

procedure Check(Cond: Boolean; const What: string);
begin
  if Cond then Inc(Passed)
  else
  begin
    Inc(Failed);
    Writeln('FALHOU: ', What);
  end;
end;

function HasIssue(const Issues: TPJIssues; const Part: string; Sev: TPJSeverity): Boolean;
var I: Integer;
begin
  for I := 0 to High(Issues) do
    if (Issues[I].Severity = Sev) and (Pos(Part, Issues[I].Message) > 0) then Exit(True);
  Result := False;
end;

function IssuesText(const Issues: TPJIssues): string;
var I: Integer;
begin
  Result := '';
  for I := 0 to High(Issues) do Result := Result + LineEnding + '   ' + Issues[I].Message;
end;

function Overlap(S: TPJSchedule; const A, B: string): Boolean;
begin
  Result := (S.StartOf(A) < S.FinishOf(B) - 0.5 / 1440) and (S.StartOf(B) < S.FinishOf(A) - 0.5 / 1440);
end;

procedure TestExample;
var
  P: TPJProject;
  S: TPJSchedule;
  Issues: TPJIssues;
begin
  P := TPJProject.Create;
  S := TPJSchedule.Create(P);
  try
    BuildMotorExample(P);
    Check(P.ResourceCount = 8, Format('8 recursos no exemplo (%d)', [P.ResourceCount]));
    Check(P.FindResource('R-001').Name = 'Ana', 'R-001 = Ana');
    Check(P.FindResource('ender-3').RType = rtMachine, 'busca por nome sem caixa');
    Check(P.ResourcesText('T-0007') = 'Ana; Bruno[50%]', 'coluna Recursos: ' + P.ResourcesText('T-0007'));
    Check(StringReplace(P.ResourcesText('T-0010'), ',', '.', [rfReplaceAll]) = 'Ender-3; PETG[0.12 kg]', 'material com quantidade: ' + P.ResourcesText('T-0010'));
    Check(Length(P.AssignmentsOfTask('T-0012')) = 2, 'laser e Carla no corte');
    Check(Length(P.AssignmentsOfResource('R-001')) = 5, 'cinco tarefas da Ana');
    Issues := P.Validate;
    Check(ErrorCount(Issues) = 0, 'exemplo sem erros' + IssuesText(Issues));
    Check(not HasIssue(Issues, 'sem maquina', svWarning), 'toda fabricacao tem maquina');
    { o cronograma nao muda com os recursos: mesmo termino da fase 3 }
    Check(S.Compute, 'cronograma: ' + S.Error);
    Check(FormatDateTime('dd"/"mm"/"yyyy hh":"nn', S.ProjectFinish) = '03/11/2026 10:00',
      'termino continua 03/11 10:00: ' + FormatDateTime('dd/mm hh:nn', S.ProjectFinish));
    { os conflitos do exemplo }
    Check(S.ResourceOverallocated('Ana'), 'Ana superalocada (tres pecas no mesmo dia)');
    Check(S.ResourceOverallocated('Laser 10 W'), 'laser superalocado (corte e placa)');
    Check(S.ResourceOverallocated('Carla'), 'Carla superalocada (torno e corte)');
    Check(not S.ResourceOverallocated('Bruno'), 'Bruno sem conflito');
    Check(not S.ResourceOverallocated('Ender-3'), 'Ender-3 sem conflito');
    Check(S.TaskOverallocated('T-0003') and not S.TaskOverallocated('T-0005'), 'tarefa marcada');
    Check(S.OverloadCount >= 3, Format('tres ou mais conflitos (%d)', [S.OverloadCount]));
    Check(HasIssue(S.Issues, 'Ana superalocado de 26/10/2026 08:00', svWarning), 'aviso com recurso e periodo' + IssuesText(S.Issues));
    Check(HasIssue(S.Issues, 'nivele', svWarning), 'aviso diz a correcao');
    Check(Abs(S.ResourcePeak('Ana') - 3) < 1E-6, 'pico da Ana 300%');
    Check(S.ResourceWork('Ana') = 480 + 240 + 240 + 480 + 480, 'trabalho da Ana 32 h');
    Check(S.ResourceWork('PETG') = 0, 'material sem trabalho');
  finally
    S.Free;
    P.Free;
  end;
end;

procedure TestLevel;
var
  P: TPJProject;
  S: TPJSchedule;
  R: TPJLevelResult;
  Finish0: TDateTime;
begin
  P := TPJProject.Create;
  S := TPJSchedule.Create(P);
  try
    BuildMotorExample(P);
    S.Compute;
    Finish0 := S.ProjectFinish;
    R := LevelProject(P, False);
    try
      Check(R.Error = '', 'nivelar sem erro: ' + R.Error);
      Check(R.Ok and (R.Unresolved.Count = 0), 'nivelamento resolve todos os conflitos');
      Check(R.Moved >= 3, Format('tarefas atrasadas (%d)', [R.Moved]));
      Check(SameText(P.UndoDescription, 'Nivelar recursos'), 'um passo de desfazer: ' + P.UndoDescription);
      Check(Pos('sem superalocacao', LevelSummary(R)) > 0, 'resumo: ' + LevelSummary(R));
      Check(Pos('termino passa de', LevelSummary(R)) > 0, 'resumo diz o novo termino');
    finally
      R.Unresolved.Free;
    end;
    Check(P.HasLeveling, 'documento com nivelamento');
    Check(S.Compute and (S.OverloadCount = 0), Format('sem superalocacao depois de nivelar (%d)', [S.OverloadCount]));
    Check(not Overlap(S, 'T-0002', 'T-0003') and not Overlap(S, 'T-0003', 'T-0004') and not Overlap(S, 'T-0002', 'T-0004'),
      'pecas da Ana em sequencia');
    Check(not Overlap(S, 'T-0012', 'T-0014'), 'laser: corte e placa em sequencia');
    Check(not Overlap(S, 'T-0011', 'T-0012'), 'Carla: torno e corte em sequencia');
    Check(S.ProjectFinish >= Finish0, 'o termino nao adianta');
  finally
    S.Free;
    P.Free;
  end;
end;

procedure TestLevelPersistAndClear;
var
  P, Q: TPJProject;
  S: TPJSchedule;
  R: TPJLevelResult;
  Finish0, Finish1: TDateTime;
begin
  P := TPJProject.Create;
  Q := TPJProject.Create;
  S := TPJSchedule.Create(P);
  try
    BuildMotorExample(P);
    S.Compute;
    Finish0 := S.ProjectFinish;
    R := LevelProject(P, False);
    R.Unresolved.Free;
    S.Compute;
    Finish1 := S.ProjectFinish;
    ProjectFromJSONText(Q, ProjectToJSONText(P));
    Check(Q.HasLeveling, '.mproj guarda o atraso de nivelamento');
    with TPJSchedule.Create(Q) do
    try
      Check(Compute and (Abs(ProjectFinish - Finish1) < 1 / 1440) and (OverloadCount = 0),
        'arquivo reaberto: mesmo termino nivelado');
    finally
      Free;
    end;
    { desfazer volta ao conflito }
    Check(P.Undo and not P.HasLeveling, 'desfazer o nivelamento');
    Check(S.Compute and (S.OverloadCount > 0), 'conflitos voltam ao desfazer');
    Check(P.Redo and P.HasLeveling, 'refazer');
    { limpar }
    Check(ClearLeveling(P), 'limpar nivelamento');
    Check(not P.HasLeveling and SameText(P.UndoDescription, 'Limpar nivelamento'), 'limpar e um passo');
    Check(S.Compute and (Abs(S.ProjectFinish - Finish0) < 1 / 1440), 'limpar restaura as datas');
    Check(not ClearLeveling(P), 'limpar sem nivelamento nao faz nada');
    { dentro da margem: nao atrasa o termino }
    R := LevelProject(P, True);
    try
      S.Compute;
      Check(Abs(S.ProjectFinish - Finish0) < 1 / 1440, 'nivelar dentro da margem mantem o termino');
      Check(R.Unresolved.Count > 0, 'dentro da margem sobram conflitos');
      Check(Pos('sem solucao', LevelSummary(R)) > 0, 'resumo com conflitos restantes');
    finally
      R.Unresolved.Free;
    end;
    { prioridade: a montagem virtual nao, mas as pecas: T-0004 com prioridade alta fica no inicio }
    ClearLeveling(P);
    Check(P.SetPriority('T-0004', 900), 'prioridade');
    Check(not P.SetPriority('T-0004', 2000), 'prioridade fora da faixa');
    R := LevelProject(P, False);
    R.Unresolved.Free;
    S.Compute;
    Check(Abs(S.StartOf('T-0004') - (EncodeDate(2026, 10, 26) + EncodeTime(8, 0, 0, 0))) < 1 / 1440,
      'tarefa de prioridade alta fica no inicio');
    { tarefa em andamento nao se move }
    ClearLeveling(P);
    P.SetPriority('T-0004', 500);
    P.FindTask('T-0003').State := tsInProgress;
    R := LevelProject(P, False);
    R.Unresolved.Free;
    S.Compute;
    Check(P.FindTask('T-0003').LevelStart = 0, 'tarefa em andamento nao e atrasada');
  finally
    S.Free;
    Q.Free;
    P.Free;
  end;
end;

procedure TestAssignAndValidate;
var
  P: TPJProject;
  Err: string;
  Issues: TPJIssues;
  N: Integer;
begin
  P := TPJProject.Create;
  try
    BuildMotorExample(P);
    { compatibilidade maquina x tarefa }
    Check(P.Assign('T-0010', 'Laser 10 W', 1, Err), 'atribuir aceita (a validacao acusa)');
    Issues := P.Validate;
    Check(HasIssue(Issues, 'T-0010 (Impressao 3D) precisa de Impressora 3D, mas Laser 10 W e Laser', svError),
      'laser numa impressao e erro' + IssuesText(Issues));
    P.Unassign('T-0010', 'Laser 10 W');
    P.Unassign('T-0011', 'Torno');
    Issues := P.Validate;
    Check(HasIssue(Issues, 'T-0011 (Usinagem de torno) sem maquina atribuida: escolha Torno', svWarning),
      'fabricacao sem maquina e aviso' + IssuesText(Issues));
    Check(P.Assign('T-0014', 'CNC Router', 1, Err), 'placa no router');
    Check(not HasIssue(P.Validate, 'T-0014 (Impressao de placa) precisa', svError), 'placa aceita router ou laser');
    Check(P.Assign('T-0003', 'Ender-3', 1, Err), 'maquina em tarefa de projeto');
    Check(HasIssue(P.Validate, 'nao usa maquina', svWarning), 'maquina em tarefa de projeto e aviso');
    { recusas }
    Check(not P.Assign('T-0001', 'Ana', 1, Err) and (Pos('resumo', Err) > 0), 'resumo recusado: ' + Err);
    Check(not P.Assign('T-0002', 'Ninguem', 1, Err) and (Pos('inexistente', Err) > 0), 'recurso inexistente');
    Check(not P.Assign('T-9999', 'Ana', 1, Err), 'tarefa inexistente');
    Check(not P.Assign('T-0002', 'Ana', 0, Err) and (Pos('maiores que zero', Err) > 0), 'unidades zero');
    { atribuir de novo muda as unidades }
    N := P.AssignmentCount;
    Check(P.Assign('T-0002', 'Ana', 0.5, Err) and (P.AssignmentCount = N), 'reatribuir nao duplica');
    Check(P.ResourcesText('T-0002') = 'Ana[50%]', 'unidades atualizadas: ' + P.ResourcesText('T-0002'));
    { coluna Recursos }
    Check(P.SetResourcesText('T-0004', 'Carla; Ana[25%]', Err), 'digitar recursos: ' + Err);
    Check(P.ResourcesText('T-0004') = 'Carla; Ana[25%]', 'lido de volta: ' + P.ResourcesText('T-0004'));
    Check(SameText(P.UndoDescription, 'Recursos da tarefa'), 'digitar e um passo: ' + P.UndoDescription);
    Check(not P.SetResourcesText('T-0004', 'Carla; Zeca', Err) and (Pos('Zeca', Err) > 0), 'nome desconhecido: ' + Err);
    Check(P.ResourcesText('T-0004') = 'Carla; Ana[25%]', 'recusa nao altera');
    Check(not P.SetResourcesText('T-0004', 'Ana[50', Err), 'colchete aberto');
    Check(not P.SetResourcesText('T-0004', 'Ana[xx%]', Err), 'unidades invalidas');
    Check(P.SetResourcesText('T-0004', 'R-003, r-001[100%]', Err) and (P.ResourcesText('T-0004') = 'Carla; Ana'),
      'por ID e com virgula: ' + P.ResourcesText('T-0004'));
    Check(P.SetResourcesText('T-0004', '', Err) and (P.ResourcesText('T-0004') = ''), 'apagar os recursos');
    { excluir tarefa e recurso leva as atribuicoes }
    N := P.AssignmentCount;
    P.DeleteTask('T-0016');
    Check(P.AssignmentCount = N - 2, 'excluir tarefa remove as atribuicoes');
    P.Undo;
    Check(P.AssignmentCount = N, 'desfazer devolve as atribuicoes');
    Check(P.DeleteResource('Carla'), 'excluir recurso');
    Check((P.FindResource('Carla') = nil) and (P.ResourcesText('T-0015') = ''), 'atribuicoes da Carla saem');
    P.Undo;
    Check(P.ResourcesText('T-0015') = 'Carla', 'desfazer devolve a Carla');
    { novo recurso }
    Check(P.AddResource('Assistente', rtAI).Id = 'R-009', 'proximo ID R-009');
    Check(P.FindResource('PETG').MaxUnits = 0, 'material sem limite');
    Check(P.AddResource('Fresadora', rtMachine).CalendarName = PJ_CAL_24H, 'maquina nova em 24 h');
    try
      P.AddResource('Ana', rtPerson);
      Check(False, 'nome repetido aceito');
    except
      on E: EPJError do Check(True, '');
    end;
    { validacao de recurso }
    P.FindResource('Fresadora').CalendarName := 'turno-x';
    Check(HasIssue(P.Validate, 'Fresadora usa o calendario inexistente', svError), 'calendario do recurso inexistente');
    Check(HasIssue(P.Validate, 'Fresadora: maquina sem tipo', svWarning), 'maquina sem tipo');
    Check(MachineTypesCaption(MachineTypesFor(tkPCBFab)) = 'CNC Router ou Laser', 'texto dos tipos de maquina');
  finally
    P.Free;
  end;
end;

procedure TestJSON;
var
  P, Q: TPJProject;
  O: TJSONObject;
  Txt: string;
  Ok: Boolean;
begin
  P := TPJProject.Create;
  Q := TPJProject.Create;
  try
    BuildMotorExample(P);
    P.FindTask('T-0002').Priority := 700;
    O := ProjectToJSON(P);
    try
      Check(O.Arrays['resources'].Count = 8, 'resources no arquivo');
      Check(O.Arrays['resources'].Objects[0].Integers['max_units'] = 100, 'max_units em %');
      Check(O.Arrays['resources'].Objects[3].Strings['machine_type'] = 'printer3d', 'machine_type');
      Check(O.Arrays['resources'].Objects[3].Strings['calendar'] = '24h', 'calendario da maquina');
      Check(O.Arrays['assignments'].Objects[0].Strings['task'] = 'T-0002', 'atribuicao task');
      { campo desconhecido no recurso e na atribuicao sobrevive }
      O.Arrays['resources'].Objects[0].Add('cor_x', 'azul');
      O.Arrays['assignments'].Objects[0].Add('nota_x', 'fica');
      Txt := O.FormatJSON;
    finally
      O.Free;
    end;
    ProjectFromJSONText(Q, Txt);
    Check(Q.ResourceCount = 8, 'recursos lidos');
    Check(Q.AssignmentCount = P.AssignmentCount, 'atribuicoes lidas');
    Check(Q.ResourcesText('T-0007') = 'Ana; Bruno[50%]', 'unidades de volta: ' + Q.ResourcesText('T-0007'));
    Check(StringReplace(Q.ResourcesText('T-0010'), ',', '.', [rfReplaceAll]) = 'Ender-3; PETG[0.12 kg]', 'quantidade de volta: ' + Q.ResourcesText('T-0010'));
    Check(Q.FindResource('Ana').Email = 'ana@oficina.local', 'email');
    Check(Q.FindResource('Ana').Role = 'Projetista mecanica', 'funcao');
    Check(Q.FindResource('Ender-3').MachineType = pmPrinter3D, 'tipo de maquina');
    Check(Q.FindTask('T-0002').Priority = 700, 'prioridade');
    Txt := ProjectToJSONText(Q);
    Check(Pos('"cor_x"', Txt) > 0, 'campo desconhecido do recurso preservado');
    Check(Pos('"nota_x"', Txt) > 0, 'campo desconhecido da atribuicao preservado');
    { arquivos invalidos nao tocam no documento }
    Ok := False;
    try
      ProjectFromJSONText(Q, StringReplace(Txt, '"printer3d"', '"teleporte"', []));
    except
      on E: EPJFormat do Ok := Pos('teleporte', E.Message) > 0;
    end;
    Check(Ok and (Q.ResourceCount = 8), 'tipo de maquina invalido recusado');
    Ok := False;
    try
      ProjectFromJSONText(Q, StringReplace(Txt, '"R-002"', '"R-001"', []));
    except
      on E: EPJFormat do Ok := Pos('repetido', E.Message) > 0;
    end;
    Check(Ok, 'ID de recurso repetido recusado');
    Ok := False;
    try
      ProjectFromJSONText(Q, StringReplace(Txt, '"priority" : 700', '"priority" : 5000', []));
    except
      on E: EPJFormat do Ok := Pos('prioridade', E.Message) > 0;
    end;
    Check(Ok, 'prioridade fora da faixa recusada');
    { arquivo da fase 1 (sem recursos) continua abrindo }
    P.Clear;
    P.Name := 'Velho';
    Txt := ProjectToJSONText(P);
    Txt := StringReplace(Txt, '"resources" : [],', '', []);
    ProjectFromJSONText(Q, Txt);
    Check((Q.ResourceCount = 0) and (Q.Name = 'Velho'), 'arquivo sem recursos abre');
  finally
    Q.Free;
    P.Free;
  end;
end;

procedure TestImport;
var
  P: TPJProject;
  F: string;
  L: TStringList;
  Added, Updated: Integer;
  Err: string;
begin
  F := GetTempDir + 'mp_equipment_test.json';
  L := TStringList.Create;
  try
    L.Text := '{"version":1,"equipment":[' +
      '{"name":"Ender-3","machine_type":2,"protocol":1,"connection":1,"host":"127.0.0.1","tcp_port":9000},' +
      '{"name":"Laser Ortur","machine_type":1,"protocol":0,"connection":1,"host":"127.0.0.1","tcp_port":9001},' +
      '{"name":"Router 3018","machine_type":0,"protocol":0,"connection":1,"host":"127.0.0.1","tcp_port":9002}]}';
    L.SaveToFile(F);
  finally
    L.Free;
  end;
  P := TPJProject.Create;
  try
    BuildMotorExample(P);
    Check(ImportMachines(P, F, Added, Updated, Err), 'importar: ' + Err);
    Check((Added = 2) and (Updated = 1), Format('2 novas e 1 atualizada (%d/%d)', [Added, Updated]));
    Check(P.FindResource('Laser Ortur').MachineType = pmLaser, 'laser importado');
    Check(P.FindResource('Router 3018').MachineType = pmRouter, 'router importado');
    Check(P.FindResource('Router 3018').CalendarName = PJ_CAL_24H, 'maquina importada em 24 h');
    Check(P.FindResource('Router 3018').Group = 'Oficina', 'grupo Oficina');
    Check(SameText(P.UndoDescription, 'Importar maquinas do MultiCNC'), 'importar e um passo');
    Check(ImportMachines(P, F, Added, Updated, Err) and (Added = 0) and (Updated = 3), 'importar de novo so atualiza');
    Check(not ImportMachines(P, F + '.nao', Added, Updated, Err) and (Pos('nao encontrado', Err) > 0), 'arquivo ausente');
    L := TStringList.Create;
    try
      L.Text := '{"version":9,"equipment":[]}';
      L.SaveToFile(F);
    finally
      L.Free;
    end;
    Check(not ImportMachines(P, F, Added, Updated, Err) and (Pos('invalido', Err) > 0), 'cadastro invalido: ' + Err);
    Check(Length(CompatibleResources(P, 'T-0010')) >= 4, 'impressao: Ender-3 e as pessoas e material');
    Check(Pos('Impressora 3D', ResourceCaption(P.FindResource('Ender-3'))) = 1, 'legenda da maquina');
  finally
    P.Free;
    DeleteFile(F);
  end;
end;

begin
  Passed := 0; Failed := 0;
  TestExample;
  TestLevel;
  TestLevelPersistAndClear;
  TestAssignAndValidate;
  TestJSON;
  TestImport;
  if Failed = 0 then
    Writeln(Format('PASS: %d checks (recursos, atribuicoes, compatibilidade, superalocacao, nivelamento, .mproj, maquinas do MultiCNC)', [Passed]))
  else
  begin
    Writeln(Format('FAIL: %d de %d checks', [Failed, Passed + Failed]));
    Halt(1);
  end;
end.
