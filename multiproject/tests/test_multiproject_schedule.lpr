program test_multiproject_schedule;

{ Fase 3 do MultiProject (multiproject/docs/TAREFA.md, itens 3.0 a 3.5):
  cronograma do exemplo do motor (README) calculado pelo TAICPMScheduler do
  CHATGPT / AI Project Core, com valores conferidos a mao:
  - calendario padrao seg-sex 08-12/13-17 e feriados BR; inicio 26/10/2026 08:00;
  - Finados (02/11) empurra o teste funcional para terca 03/11;
  - impressao de 14 h decorridas atravessa a noite;
  - caminho critico, margens, resumo, restricao, data limite, calendario da
    tarefa, .mproj com calendarios e 2000 tarefas. }

{$mode objfpc}{$H+}

uses
  Classes, SysUtils, aiprojectduration, aitaskgraph, aiworkcalendar, aicpmscheduler,
  multiproject_types, multiproject_document, multiproject_json, multiproject_graph,
  multiproject_schedule;

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

function DT(M, D, H, N: Word): TDateTime;
begin
  Result := EncodeDate(2026, M, D) + EncodeTime(H, N, 0, 0);
end;

function S(T: TDateTime): string;
begin
  Result := FormatDateTime('dd/mm hh:nn', T);
end;

function SameT(A, B: TDateTime): Boolean;
begin
  Result := Abs(A - B) < 0.5 / 1440;
end;

procedure Dates(Sc: TPJSchedule; const Id: string; AStart, AFinish: TDateTime);
begin
  Check(SameT(Sc.StartOf(Id), AStart) and SameT(Sc.FinishOf(Id), AFinish),
    Format('%s: %s - %s, esperado %s - %s', [Id, S(Sc.StartOf(Id)), S(Sc.FinishOf(Id)), S(AStart), S(AFinish)]));
end;

procedure Slack(Sc: TPJSchedule; const Id: string; Total: Int64);
var R: TAICPMResult;
begin
  R := Sc[Sc.IndexOf(Id)];
  Check(R.TotalSlack = Total, Format('%s: margem total %d, esperado %d', [Id, R.TotalSlack, Total]));
end;

function Link(P: TPJProject; const A, B: string): Boolean;
var Err: string;
begin
  Result := P.AddLink(A, B, atlFS, AINoLag, True, Err);
  if not Result then Writeln('  (vinculo ', A, ' -> ', B, ' recusado: ', Err, ')');
end;

function BuildMotor: TPJProject;
var P: TPJProject;
  procedure Add(AKind: TPJTaskKind; const AName, ADur: string);
  var T: TPJTask; Err: string;
  begin
    T := P.AddTask('', AKind, AName, AName);
    if not P.SetDurationText(T.Id, ADur, Err) then raise Exception.Create(Err);
  end;
begin
  P := TPJProject.Create;
  P.Name := 'Motor DC didatico';
  P.ObjectiveShort := 'Motor DC 12 V';
  P.StartDate := DT(10, 26, 8, 0);
  P.ResetCalendars;
  Add(tkPart, 'Carcaca', '1d');                 // T-0001
  Add(tkPart, 'Eixo', '4h');                    // T-0002
  Add(tkPart, 'Base MDF', '4h');                // T-0003
  Add(tkElectronics, 'Driver ponte H', '2d');   // T-0004
  Add(tkAssembly, 'Montagem virtual', '1d');    // T-0005
  Add(tkValidation, 'Validacao', '1d');         // T-0006
  Add(tkMilestone, 'Liberado p/ fabricacao', '0d'); // M-0007
  Add(tkPrint3D, 'Imprimir carcaca', '14eh');   // T-0008
  Add(tkLathe, 'Tornear eixo', '4h');           // T-0009
  Add(tkLaserCut, 'Cortar base', '2h');         // T-0010
  Add(tkLaserArt, 'Gravar logo', '1h');         // T-0011
  Add(tkPCBFab, 'Fabricar placa', '4h');        // T-0012
  Add(tkPhysicalAssembly, 'Montagem fisica', '4h'); // T-0013
  Add(tkFunctionalTest, 'Teste funcional', '2h');   // T-0014
  Add(tkMilestone, 'Objetivo concluido', '0d');     // M-0015
  Link(P, 'T-0001', 'T-0005'); Link(P, 'T-0002', 'T-0005');
  Link(P, 'T-0003', 'T-0005'); Link(P, 'T-0004', 'T-0005');
  Link(P, 'T-0005', 'T-0006'); Link(P, 'T-0006', 'M-0007');
  Link(P, 'M-0007', 'T-0008'); Link(P, 'M-0007', 'T-0009');
  Link(P, 'M-0007', 'T-0010'); Link(P, 'M-0007', 'T-0012');
  Link(P, 'T-0010', 'T-0011');
  Link(P, 'T-0008', 'T-0013'); Link(P, 'T-0009', 'T-0013');
  Link(P, 'T-0011', 'T-0013'); Link(P, 'T-0012', 'T-0013');
  Link(P, 'T-0013', 'T-0014'); Link(P, 'T-0014', 'M-0015');
  P.ClearHistory;
  P.Modified := False;
  Result := P;
end;

procedure CheckMotor(Sc: TPJSchedule; const Tag: string);
begin
  Check(Sc.Valid, Tag + 'calculado: ' + Sc.Error);
  if not Sc.Valid then Exit;
  Dates(Sc, 'T-0004', DT(10, 26, 8, 0), DT(10, 27, 17, 0));
  Dates(Sc, 'T-0001', DT(10, 26, 8, 0), DT(10, 26, 17, 0));
  Dates(Sc, 'T-0002', DT(10, 26, 8, 0), DT(10, 26, 12, 0));
  Dates(Sc, 'T-0005', DT(10, 28, 8, 0), DT(10, 28, 17, 0));
  Dates(Sc, 'T-0006', DT(10, 29, 8, 0), DT(10, 29, 17, 0));
  Dates(Sc, 'M-0007', DT(10, 29, 17, 0), DT(10, 29, 17, 0));
  Dates(Sc, 'T-0008', DT(10, 29, 17, 0), DT(10, 30, 7, 0));
  Dates(Sc, 'T-0009', DT(10, 30, 8, 0), DT(10, 30, 12, 0));
  Dates(Sc, 'T-0010', DT(10, 30, 8, 0), DT(10, 30, 10, 0));
  Dates(Sc, 'T-0011', DT(10, 30, 10, 0), DT(10, 30, 11, 0));
  Dates(Sc, 'T-0012', DT(10, 30, 8, 0), DT(10, 30, 12, 0));
  Dates(Sc, 'T-0013', DT(10, 30, 13, 0), DT(10, 30, 17, 0));
  Dates(Sc, 'T-0014', DT(11, 3, 8, 0), DT(11, 3, 10, 0));
  Dates(Sc, 'M-0015', DT(11, 3, 10, 0), DT(11, 3, 10, 0));
  Check(SameT(Sc.ProjectFinish, DT(11, 3, 10, 0)), Tag + 'termino do projeto 03/11 10:00: ' + S(Sc.ProjectFinish));
  Slack(Sc, 'T-0001', 480);
  Slack(Sc, 'T-0002', 720);
  Slack(Sc, 'T-0008', 360);
  Slack(Sc, 'T-0010', 60);
  Slack(Sc, 'T-0011', 60);
  Slack(Sc, 'T-0013', 0);
  Check(Sc.CriticalIds = 'T-0004,T-0005,T-0006,M-0007,T-0009,T-0012,T-0013,T-0014,M-0015',
    Tag + 'caminho critico: ' + Sc.CriticalIds);
end;

procedure TestMotor;
var P: TPJProject; Sc: TPJSchedule;
begin
  P := BuildMotor;
  Sc := TPJSchedule.Create(P);
  try
    Sc.Compute;
    CheckMotor(Sc, '');
    Check(Length(Sc.Issues) = 0, 'sem avisos');
    { sem o feriado de Finados o teste funcional fica na segunda }
    P.ProjectCalendar.RemoveException(EncodeDate(2026, 11, 2));
    Sc.Compute;
    Dates(Sc, 'T-0014', DT(11, 2, 8, 0), DT(11, 2, 10, 0));
  finally
    Sc.Free;
    P.Free;
  end;
end;

procedure TestDocumentFields;
var P: TPJProject; Sc: TPJSchedule; T: TPJTask; Cal: TAIWorkCalendar; I: Integer; Found: Boolean;
begin
  P := BuildMotor;
  Sc := TPJSchedule.Create(P);
  try
    { material da base chega na terca: SNET }
    T := P.FindTask('T-0003');
    T.Constraint := actSNET; T.ConstraintDate := DT(10, 27, 8, 0);
    { data limite do objetivo na segunda (feriado): nao e atendida }
    P.FindTask('M-0015').Deadline := DT(11, 2, 17, 0);
    { teste funcional com a oficina aberta sabado de manha }
    Cal := P.AddCalendar('oficina', P.ProjectCalendar);
    Cal.SetWeekDay(7, [480, 720]);
    P.FindTask('T-0014').CalendarName := 'oficina';
    Check(ErrorCount(P.Validate) = 0, 'validacao sem erros');
    Check(Sc.Compute, 'calculado: ' + Sc.Error);
    Dates(Sc, 'T-0003', DT(10, 27, 8, 0), DT(10, 27, 12, 0));
    Slack(Sc, 'T-0003', 240);
    Dates(Sc, 'T-0014', DT(10, 31, 8, 0), DT(10, 31, 10, 0));
    Dates(Sc, 'M-0015', DT(10, 31, 10, 0), DT(10, 31, 10, 0));
    Found := False;
    for I := 0 to High(Sc.Issues) do
      if (Sc.Issues[I].TaskId = 'M-0015') and (Pos('data limite', Sc.Issues[I].Message) > 0) then Found := True;
    Check(not Found, 'com o sabado a data limite e atendida');
    { sem o calendario da oficina, a data limite estoura }
    P.FindTask('T-0014').CalendarName := '';
    Sc.Compute;
    Found := False;
    for I := 0 to High(Sc.Issues) do
      if (Sc.Issues[I].TaskId = 'M-0015') and (Pos('data limite', Sc.Issues[I].Message) > 0) then Found := True;
    Check(Found, 'aviso de data limite com o ID da tarefa');
    Check(Sc[Sc.IndexOf('M-0015')].TotalSlack < 0, 'margem negativa no objetivo');
    { calendario inexistente }
    P.FindTask('T-0014').CalendarName := 'nao_existe';
    Check(not Sc.Compute and (Pos('nao_existe', Sc.Error) > 0), 'calendario inexistente: ' + Sc.Error);
    Check(ErrorCount(P.Validate) > 0, 'validacao acusa o calendario inexistente');
    P.FindTask('T-0014').CalendarName := '';
    { restricao sem data e erro de validacao }
    P.FindTask('T-0002').Constraint := actMSO;
    Check(ErrorCount(P.Validate) > 0, 'restricao sem data acusada');
  finally
    Sc.Free;
    P.Free;
  end;
end;

procedure TestSummary;
var P: TPJProject; Sc: TPJSchedule; Sm: TPJTask; Err: string;
begin
  P := TPJProject.Create;
  Sc := TPJSchedule.Create(P);
  try
    P.StartDate := DT(10, 26, 8, 0);
    P.ResetCalendars;
    Sm := P.AddTask('', tkSummary, 'Projeto', 'pecas e placa');             // T-0001
    P.AddTask(Sm.Id, tkPart, 'Carcaca', 'c').Duration := AIMakeDuration(480);   // T-0002
    P.AddTask(Sm.Id, tkElectronics, 'Driver', 'd').Duration := AIMakeDuration(960); // T-0003
    P.AddTask('', tkAssembly, 'Montagem', 'm').Duration := AIMakeDuration(480);  // T-0004
    Check(P.AddLink(Sm.Id, 'T-0004', atlFS, AINoLag, True, Err), 'resumo -> montagem: ' + Err);
    Check(Sc.Compute, 'calculado: ' + Sc.Error);
    Dates(Sc, 'T-0001', DT(10, 26, 8, 0), DT(10, 27, 17, 0));
    Dates(Sc, 'T-0004', DT(10, 28, 8, 0), DT(10, 28, 17, 0));
    Check(Sc[0].Critical and (Sc.CriticalIds = 'T-0003,T-0004'), 'criticas (resumo fora da lista): ' + Sc.CriticalIds);
    Slack(Sc, 'T-0002', 480);
  finally
    Sc.Free;
    P.Free;
  end;
end;

procedure TestFile;
var P, Q: TPJProject; Sc: TPJSchedule; FN: string; Cal: TAIWorkCalendar;
begin
  FN := IncludeTrailingPathDelimiter(GetTempDir(False)) + 'motor_cronograma.mproj';
  P := BuildMotor;
  Q := TPJProject.Create;
  Sc := TPJSchedule.Create(Q);
  try
    P.FindTask('T-0003').Constraint := actSNET;
    P.FindTask('T-0003').ConstraintDate := DT(10, 27, 8, 0);
    P.FindTask('M-0015').Deadline := DT(11, 4, 17, 0);
    Cal := P.AddCalendar('oficina', P.ProjectCalendar);
    Cal.AddException(EncodeDate(2026, 10, 28), 'Inventario', [480, 720]);
    P.FindTask('T-0009').CalendarName := 'oficina';
    P.CriticalSlack := 60;
    SaveProjectFile(P, FN);
    LoadProjectFile(Q, FN);
    Check(Q.CalendarCount = 3, 'tres calendarios lidos');
    Check(Q.FindCalendar('oficina').WorkingMinutesOfDay(EncodeDate(2026, 10, 28)) = 240, 'excecao do calendario lida');
    Check(not Q.ProjectCalendar.IsWorkingDay(EncodeDate(2026, 11, 2)), 'feriado do calendario padrao lido');
    Check((Q.FindTask('T-0003').Constraint = actSNET) and SameT(Q.FindTask('T-0003').ConstraintDate, DT(10, 27, 8, 0)), 'restricao lida');
    Check(SameT(Q.FindTask('M-0015').Deadline, DT(11, 4, 17, 0)), 'data limite lida');
    Check(Q.FindTask('T-0009').CalendarName = 'oficina', 'calendario da tarefa lido');
    Check(Q.CriticalSlack = 60, 'limiar de critica lido');
    Check(Sc.Compute, 'calculado depois de ler: ' + Sc.Error);
    Dates(Sc, 'T-0003', DT(10, 27, 8, 0), DT(10, 27, 12, 0));
    Check(Pos('T-0010', Sc.CriticalIds) > 0, 'limiar de 60 min torna o corte critico: ' + Sc.CriticalIds);
  finally
    Sc.Free;
    P.Free;
    Q.Free;
  end;
  DeleteFile(FN);
  { arquivo antigo sem calendarios recebe padrao + 24 h }
  Q := TPJProject.Create;
  try
    ProjectFromJSONText(Q, '{ "schema_version": 1, "format": "MultiProject", "start": "2026-10-26T08:00:00" }');
    Check((Q.CalendarCount = 2) and (Q.FindCalendar('24h') <> nil) and
      not Q.ProjectCalendar.IsWorkingDay(EncodeDate(2026, 11, 2)), 'arquivo sem calendarios usa o padrao com feriados');
  finally
    Q.Free;
  end;
end;

procedure TestUndoKeepsSchedule;
var P: TPJProject; Sc: TPJSchedule; Err: string;
begin
  P := BuildMotor;
  Sc := TPJSchedule.Create(P);
  try
    Check(P.SetDurationText('T-0004', '3d', Err), 'driver 3d');
    Sc.Compute;
    Dates(Sc, 'T-0005', DT(10, 29, 8, 0), DT(10, 29, 17, 0));
    Check(P.Undo, 'desfazer');
    Sc.Compute;
    CheckMotor(Sc, 'depois do desfazer: ');
  finally
    Sc.Free;
    P.Free;
  end;
end;

procedure TestScale;
var P: TPJProject; Sc: TPJSchedule; Text: string; I, A, B, N: Integer; T0, Ms: QWord;
begin
  RandSeed := 11;
  P := TPJProject.Create;
  Sc := TPJSchedule.Create(P);
  try
    Text := '{ "schema_version": 1, "format": "MultiProject", "start": "2026-10-26T08:00:00", "tasks": [';
    for I := 1 to 2000 do
    begin
      if I > 1 then Text := Text + ',';
      Text := Text + Format('{"id":"T-%.4d","name":"t","short":"s","duration":%d,"duration_unit":"h"}', [I, 60 * (1 + Random(16))]);
    end;
    Text := Text + '], "links": [';
    N := 0;
    while N < 4000 do
    begin
      A := 1 + Random(1999);
      B := A + 1 + Random(30);
      if B > 2000 then Continue;
      if Pos(Format('"T-%.4d","to":"T-%.4d"', [A, B]), Text) > 0 then Continue;
      if N > 0 then Text := Text + ',';
      Text := Text + Format('{"from":"T-%.4d","to":"T-%.4d","type":"%s"}', [A, B, AILinkTypeCode(TAITaskLinkType(Random(4)), False)]);
      Inc(N);
    end;
    Text := Text + '] }';
    ProjectFromJSONText(P, Text);
    T0 := GetTickCount64;
    Check(Sc.Compute, '2000 tarefas calculadas: ' + Sc.Error);
    Ms := GetTickCount64 - T0;
    Writeln(Format('  cronograma de 2000 tarefas e 4000 vinculos: %d ms', [Ms]));
    Check(Ms < 1000, Format('cronograma de 2000 tarefas em %d ms', [Ms]));
  finally
    Sc.Free;
    P.Free;
  end;
end;

begin
  Passed := 0; Failed := 0;
  TestMotor;
  TestDocumentFields;
  TestSummary;
  TestFile;
  TestUndoKeepsSchedule;
  TestScale;
  if Failed = 0 then
    Writeln(Format('PASS: %d checks (motor do README, caminho critico, margens, Finados, restricao, data limite, calendarios, resumo, .mproj, 2000 tarefas)', [Passed]))
  else
  begin
    Writeln(Format('FAIL: %d de %d checks', [Failed, Passed + Failed]));
    Halt(1);
  end;
end.
