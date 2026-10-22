program test_multiproject_states;

{ Fase 4 (nucleo usado pela tela): exemplo do motor (Demo) e regras de
  mudanca de estado do Quadro (PJ-L06, sem a parte de artefato da fase 5). }

{$mode objfpc}{$H+}

uses
  Classes, SysUtils, aicpmscheduler, multiproject_types, multiproject_document,
  multiproject_graph, multiproject_schedule, multiproject_states, multiproject_examples;

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

procedure TestExample;
var P: TPJProject; Sc: TPJSchedule;
begin
  P := TPJProject.Create;
  Sc := TPJSchedule.Create(P);
  try
    BuildMotorExample(P);
    Check((P.Count = 17) and (P.LinkCount = 17), Format('exemplo: %d tarefas e %d vinculos', [P.Count, P.LinkCount]));
    Check(ErrorCount(P.Validate) = 0, 'exemplo sem erros de validacao');
    Check(not P.CanUndo and not P.Modified, 'exemplo abre limpo');
    Check(Sc.Compute, 'exemplo calculado: ' + Sc.Error);
    Check(Abs(Sc.ProjectFinish - (EncodeDate(2026, 11, 3) + EncodeTime(10, 0, 0, 0))) < 1 / 1440,
      'exemplo termina 03/11 10:00: ' + FormatDateTime('dd/mm hh:nn', Sc.ProjectFinish));
    Check(Sc.CriticalIds = 'T-0005,T-0006,T-0007,M-0008,T-0011,T-0014,T-0015,T-0016,M-0017',
      'caminho critico do exemplo: ' + Sc.CriticalIds);
    Check(Length(TaskChains(P)) = 1, 'uma cadeia');
    Check(P.FindTask('T-0002').TechValue('material') = 'PETG', 'especificacao tecnica do exemplo');
  finally
    Sc.Free;
    P.Free;
  end;
end;

procedure TestStates;
var P: TPJProject; Why: string; T: TPJTask; I: Integer;
begin
  P := TPJProject.Create;
  try
    BuildMotorExample(P);
    Check(not SetTaskState(P, 'T-0003', tsDone, Why), 'peca sem artefato nao conclui');
    for I := 0 to P.Count-1 do
    begin
      P[I].Artifact.Hash := 'fixture-verificada'; P[I].Artifact.Status := 'valid';
    end;
    Check(not SetTaskState(P, 'T-0006', tsInProgress, Why) and (Pos('T-0002', Why) > 0),
      'montagem espera as pecas: ' + Why);
    Check(not SetTaskState(P, 'T-0001', tsDone, Why) and (Pos('resumo', Why) > 0), 'resumo nao muda pelo quadro');
    Check(SetTaskState(P, 'T-0003', tsInProgress, Why), 'peca sem predecessora entra em andamento: ' + Why);
    Check(P.FindTask('T-0003').State = tsInProgress, 'estado aplicado');
    Check(P.UndoDescription = 'Alterar estado', 'estado entra no desfazer');
    Check(not SetTaskState(P, 'T-0002', tsDone, Why) and (Pos('criterio', Why) > 0), 'criterio pendente impede concluir: ' + Why);
    T := P.FindTask('T-0002');
    T.FuncSpec[0].State := csPassed;
    Check(SetTaskState(P, 'T-0002', tsDone, Why), 'criterio aprovado conclui: ' + Why);
    Check(SetTaskState(P, 'T-0003', tsDone, Why) and SetTaskState(P, 'T-0004', tsCancelled, Why), 'eixo concluido, base cancelada');
    Check(not SetTaskState(P, 'T-0006', tsInProgress, Why) and (Pos('T-0005', Why) > 0) and (Pos('T-0004', Why) = 0),
      'cancelada nao bloqueia; falta so o driver: ' + Why);
    P.FindTask('T-0005').FuncSpec[0].State := csWaived;
    Check(SetTaskState(P, 'T-0005', tsDone, Why) and SetTaskState(P, 'T-0006', tsInProgress, Why), 'montagem libera: ' + Why);
    Check(SetTaskState(P, 'T-0006', tsPlanned, Why), 'voltar para planejada e livre');
    Check(not SetTaskState(P, 'T-9999', tsDone, Why), 'tarefa inexistente');
  finally
    P.Free;
  end;
end;

begin
  Passed := 0; Failed := 0;
  TestExample;
  TestStates;
  if Failed = 0 then
    Writeln(Format('PASS: %d checks (exemplo do motor, estados do quadro)', [Passed]))
  else
  begin
    Writeln(Format('FAIL: %d de %d checks', [Failed, Passed + Failed]));
    Halt(1);
  end;
end.
