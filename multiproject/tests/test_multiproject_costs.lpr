program test_multiproject_costs;

{ Testes de console da fase 7 do MultiProject, itens 7.5 a 7.7:
  - tipos de tarefa (unidades fixas, duracao fixa, trabalho fixo) e
    controlada pelo empenho, com Trabalho = Duracao x Unidades (PJ-T19);
  - custos: taxa por hora, custo por uso, material, recurso de custo, custo
    fixo com acumulacao, resumo e projeto (PJ-$01, $02);
  - estimativa da fabricacao pelo G-code e pelo MultiSlicer, aceita num passo
    de desfazer, com o filamento lancado como material (PJ-L08, PJ-$03);
  - lista de materiais do MultiAssembly na tarefa de compra (PJ-$03);
  - componentes genericos aitasktype e aicostmodel (AI Project Core);
  - .mproj: ida e volta dos campos novos e recusa de valores invalidos. }

{$mode objfpc}{$H+}

uses
  Classes, SysUtils, Math, aiprojectduration, aitasktype, aicostmodel,
  multiproject_types, multiproject_document, multiproject_json, multiproject_examples,
  multiproject_estimates, multiproject_bom, multiassembly_types, multiassembly_project;

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

function Near(A, B: Double; Tol: Double = 0.005): Boolean;
begin
  Result := Abs(A - B) <= Tol;
end;

function Units(P: TPJProject; const T, R: string): Double;
var A: Integer;
begin
  A := P.IndexOfAssignment(T, P.FindResource(R).Id);
  if A < 0 then Exit(-1);
  Result := P.Assignments[A].Units;
end;

procedure WriteText(const FileName, Text: string);
var L: TStringList;
begin
  ForceDirectories(ExtractFilePath(FileName));
  L := TStringList.Create;
  try
    L.Text := Text;
    L.SaveToFile(FileName);
  finally
    L.Free;
  end;
end;

{ ---------------- componentes genericos ---------------- }

procedure TestTaskTypeCore;
var R: TAITaskTypeResult; T: TAITaskType;
begin
  Check(AIWorkOf(480, 1.5) = 720, 'trabalho = duracao x unidades');
  Check(AIWorkOf(480, 0) = 0, 'sem unidades nao ha trabalho');
  Check(AITryTaskTypeFromName('fixed_work', T) and (T = attFixedWork), 'nome do tipo');
  Check(not AITryTaskTypeFromName('fixo', T), 'tipo desconhecido recusado');
  Check(AIIsEffortDriven(attFixedWork, False), 'trabalho fixo e sempre pelo empenho');
  { duracao muda }
  R := AIOnDurationChange(attFixedUnits, 480, 960, 1);
  Check(R.Ok and (R.Duration = 960) and Near(R.UnitScale, 1) and (R.Work = 960), 'unidades fixas: duracao dobra o trabalho');
  R := AIOnDurationChange(attFixedDuration, 480, 960, 1);
  Check(R.Ok and Near(R.UnitScale, 1) and (R.Work = 960), 'duracao fixa: trabalho acompanha');
  R := AIOnDurationChange(attFixedWork, 480, 960, 1);
  Check(R.Ok and Near(R.UnitScale, 0.5) and (R.Work = 480), 'trabalho fixo: unidades caem a metade');
  R := AIOnDurationChange(attFixedWork, 480, 0, 1);
  Check(not R.Ok, 'trabalho fixo nao aceita duracao zero com recurso');
  R := AIOnDurationChange(attFixedWork, 480, 960, 0);
  Check(R.Ok and Near(R.UnitScale, 1) and (R.Work = 0), 'sem recurso a duracao muda livre');
  { trabalho digitado }
  R := AIOnWorkChange(attFixedUnits, 480, 2, 1920);
  Check(R.Ok and (R.Duration = 960) and Near(R.UnitScale, 1), 'unidades fixas: trabalho muda a duracao');
  R := AIOnWorkChange(attFixedDuration, 480, 1, 240);
  Check(R.Ok and (R.Duration = 480) and Near(R.UnitScale, 0.5) and (R.Work = 240), 'duracao fixa: trabalho muda as unidades');
  R := AIOnWorkChange(attFixedWork, 480, 1, 0);
  Check(R.Ok and (R.Duration = 0), 'trabalho zero zera a duracao');
  R := AIOnWorkChange(attFixedWork, 480, 0, 600);
  Check(not R.Ok and (Pos('atribua', R.Error) > 0), 'trabalho sem recurso recusado');
  { recursos incluidos (empenho) }
  R := AIOnUnitsChange(attFixedUnits, True, True, 960, 1, 2);
  Check(R.Ok and (R.Duration = 480) and (R.Work = 960), 'empenho, unidades fixas: dois recursos na metade do tempo');
  R := AIOnUnitsChange(attFixedDuration, True, True, 960, 1, 2);
  Check(R.Ok and (R.Duration = 960) and Near(R.UnitScale, 0.5) and (R.Work = 960), 'empenho, duracao fixa: unidades redistribuidas');
  R := AIOnUnitsChange(attFixedUnits, False, True, 960, 1, 2);
  Check(R.Ok and (R.Duration = 960) and (R.Work = 1920), 'sem empenho: incluir recurso soma trabalho');
  R := AIOnUnitsChange(attFixedWork, False, True, 960, 2, 1);
  Check(R.Ok and (R.Duration = 1920), 'trabalho fixo: retirar recurso alonga');
  { unidades de quem ja estava }
  R := AIOnUnitsChange(attFixedUnits, False, False, 960, 1, 0.5);
  Check(R.Ok and (R.Duration = 1920), 'unidades fixas: meio periodo dobra a duracao');
  R := AIOnUnitsChange(attFixedDuration, True, False, 960, 1, 0.5);
  Check(R.Ok and (R.Duration = 960) and (R.Work = 480), 'duracao fixa: unidades mudam o trabalho');
  R := AIOnUnitsChange(attFixedWork, True, True, 960, 0, 1);
  Check(R.Ok and (R.Duration = 960), 'primeira atribuicao nao mexe na duracao');
end;

procedure TestCostCore;
var C: TAICostBreakdown; V: Double; A: TAICostAccrual;
begin
  Check(Near(AIWorkCost(90, 60), 90), '1 h 30 a R$ 60/h = R$ 90');
  Check(AIWorkCost(90, -1) = 0, 'taxa negativa vale zero');
  Check(Near(AIMaterialCost(0.12, 120), 14.4), '0,12 kg a R$ 120/kg');
  Check(AITryCostAccrualFromName('end', A) and (A = acaEnd), 'acumulacao no fim');
  Check(Near(AIAccruedFraction(acaStart, 0.01), 1) and Near(AIAccruedFraction(acaStart, 0), 0), 'no inicio');
  Check(Near(AIAccruedFraction(acaEnd, 0.99), 0) and Near(AIAccruedFraction(acaEnd, 1), 1), 'no fim');
  Check(Near(AIAccruedFraction(acaProrated, 0.25), 0.25), 'rateado');
  Check(Near(AIAccruedFractionAt(acaProrated, 10, 14, 11), 0.25), 'rateado por datas');
  Check(Near(AIAccruedFractionAt(acaEnd, 10, 10, 10), 1), 'marco vence na data');
  AIClearCost(C);
  C.Work := 100; C.PerUse := 10; C.Fixed := 50;
  Check(Near(AICostTotal(C), 160), 'total por origem');
  Check(Near(AICostToDate(C, acaEnd, 0.5), 50 + 10), 'vencido na metade: trabalho rateado, uso no inicio');
  Check(AIFormatMoney(1234.5) = 'R$ 1.234,50', 'formato R$: ' + AIFormatMoney(1234.5));
  Check(AIFormatMoney(-0.5, '') = '-0,50', 'negativo sem simbolo');
  Check(AIFormatMoney(1000000) = 'R$ 1.000.000,00', 'milhoes');
  Check(AITryParseMoney('R$ 1.234,50', V) and Near(V, 1234.5), 'le R$ 1.234,50');
  Check(AITryParseMoney('1,234.50', V) and Near(V, 1234.5), 'le 1,234.50');
  Check(AITryParseMoney('12,5', V) and Near(V, 12.5), 'le 12,5');
  Check(AITryParseMoney('12.5', V) and Near(V, 12.5), 'le 12.5');
  Check(AITryParseMoney('1.500', V) and Near(V, 1500), 'le 1.500 como milhar');
  Check(AITryParseMoney('150', V) and Near(V, 150), 'le inteiro');
  Check(not AITryParseMoney('doze', V), 'texto recusado');
  Check(not AITryParseMoney('', V), 'vazio recusado');
end;

{ ---------------- tipo de tarefa no documento ---------------- }

procedure TestTaskTypeDocument;
var
  P: TPJProject;
  T, M: TPJTask;
  Err: string;
  R: TPJResource;
begin
  P := TPJProject.Create;
  try
    P.StartDate := EncodeDate(2026, 10, 26) + EncodeTime(8, 0, 0, 0);
    P.ResetCalendars;
    T := P.AddTask('', tkPart, 'Carcaca', 'peca');
    M := P.AddTask('', tkPrint3D, 'Imprimir', 'impressao');
    Check(P.EffectiveTaskType(T) = attFixedWork, 'peca: trabalho fixo por padrao (pessoa)');
    Check(P.EffectiveTaskType(M) = attFixedDuration, 'impressao: duracao fixa por padrao (maquina)');
    P.AddResource('Ana', rtPerson);
    P.AddResource('Bruno', rtPerson);
    P.AddResource('Ender-3', rtMachine);
    R := P.AddResource('Frete', rtCost);
    R := P.AddResource('PLA', rtMaterial);
    R.MaterialUnit := 'kg';
    Check(P.SetDurationText(T.Id, '2d', Err), 'duracao 2d');
    Check(P.SetResourcesText(T.Id, 'Ana', Err), 'Ana na peca');
    Check(P.TaskWork(T.Id) = 960, 'trabalho 16 h');
    Check(P.FormatWork(P.TaskWork(T.Id)) = '16h', 'formato do trabalho: ' + P.FormatWork(P.TaskWork(T.Id)));
    { trabalho fixo: dobrar a duracao poe Ana a 50% }
    Check(P.SetDurationText(T.Id, '4d', Err), 'duracao 4d: ' + Err);
    Check(Near(Units(P, T.Id, 'Ana'), 0.5, 1E-6), 'Ana a 50%');
    Check(P.TaskWork(T.Id) = 960, 'trabalho continua 16 h');
    Check(P.UndoDescription = 'Alterar duracao', 'um passo de desfazer: ' + P.UndoDescription);
    P.Undo;
    T := P.FindTask('T-0001');
    Check(Near(Units(P, T.Id, 'Ana'), 1, 1E-6) and (T.Duration.Minutes = 960), 'desfazer volta duracao e unidades');
    { empenho: incluir Bruno divide a duracao }
    Check(P.Assign(T.Id, 'Bruno', 1, Err), 'Bruno incluido');
    T := P.FindTask(T.Id);
    Check(T.Duration.Minutes = 480, 'dois recursos: 1 dia');
    Check(P.TaskWork(T.Id) = 960, 'mesmo trabalho com dois');
    Check(P.Unassign(T.Id, 'Bruno'), 'Bruno retirado');
    T := P.FindTask(T.Id);
    Check(T.Duration.Minutes = 960, 'sem Bruno: volta a 2 dias');
    { atribuicao inicial em lote nao mexe na duracao }
    Check(P.SetResourcesText(T.Id, '', Err) and P.SetResourcesText(T.Id, 'Ana; Bruno[50%]', Err), 'lote: ' + Err);
    T := P.FindTask(T.Id);
    Check(T.Duration.Minutes = 960, 'atribuicao inicial: duracao fica');
    Check(P.TaskWork(T.Id) = 1440, 'trabalho 24 h (100% + 50%)');
    { mudar so as unidades: trabalho fixo muda a duracao }
    Check(P.SetResourcesText(T.Id, 'Ana; Bruno', Err), 'Bruno a 100%');
    T := P.FindTask(T.Id);
    Check(T.Duration.Minutes = 720, 'mesmo trabalho com 200%: 1,5 dia');
    { trabalho digitado }
    Check(P.SetWorkText(T.Id, '32', Err), 'trabalho 32 h: ' + Err);
    T := P.FindTask(T.Id);
    Check(T.Duration.Minutes = 960, '32 h com 200% = 2 dias');
    Check(not P.SetWorkText(T.Id, '2ed', Err), 'trabalho decorrido recusado');
    { tipo explicito }
    Check(P.SetTaskType(T.Id, False, attFixedDuration, False), 'duracao fixa');
    T := P.FindTask(T.Id);
    Check(P.SetWorkText(T.Id, '16h', Err), 'trabalho 16 h na duracao fixa');
    T := P.FindTask(T.Id);
    Check((T.Duration.Minutes = 960) and Near(Units(P, T.Id, 'Ana'), 0.5, 1E-6) and
      Near(Units(P, T.Id, 'Bruno'), 0.5, 1E-6), 'duracao fixa: unidades caem para 50%');
    Check(P.SetTaskType(T.Id, False, attFixedUnits, True), 'unidades fixas pelo empenho');
    T := P.FindTask(T.Id);
    Check(P.EffectiveTaskType(T) = attFixedUnits, 'tipo gravado');
    Check(P.SetDurationText(T.Id, '4d', Err), 'unidades fixas: 4d');
    T := P.FindTask(T.Id);
    Check(P.TaskWork(T.Id) = 1920, 'unidades fixas: trabalho dobra');
    { maquina e duracao fixa: incluir pessoa nao mexe na impressao }
    M := P.FindTask('T-0002');
    Check(P.SetDurationText(M.Id, '6h', Err) and P.Assign(M.Id, 'Ender-3', 1, Err), 'impressao 6h');
    Check(P.Assign(M.Id, 'Ana', 0.1, Err), 'Ana a 10% na impressao');
    M := P.FindTask(M.Id);
    Check(M.Duration.Minutes = 360, 'impressao continua 6h');
    { material e custo nao entram no trabalho; material acima de 100 e aceito }
    Check(P.SetResourcesText(M.Id, 'Ender-3; PLA[150 kg]; Frete[R$ 1.250,00]', Err), 'material e custo');
    Check(P.SetResourcesText(M.Id, P.ResourcesText(M.Id), Err), 'coluna lida de volta: ' + Err);
    M := P.FindTask(M.Id);
    Check(Near(P.TaskWorkUnits(M.Id), 1), 'so a maquina conta como trabalho');
    Check(Near(P.Assignments[P.IndexOfAssignment(M.Id, P.FindResource('Frete').Id)].Cost, 1250), 'frete R$ 1.250');
    Check(Near(P.Assignments[P.IndexOfAssignment(M.Id, P.FindResource('PLA').Id)].Quantity, 150), '150 kg aceitos');
    Check(Pos('Frete[R$ 1.250,00]', P.ResourcesText(M.Id)) > 0, 'coluna Recursos com o valor: ' + P.ResourcesText(M.Id));
    Check(not P.Assign(M.Id, 'Ana', 101, Err), 'pessoa a 10100% recusada');
    { marco nao tem trabalho }
    Check(P.TaskWork('inexistente') = 0, 'tarefa inexistente sem trabalho');
  finally
    P.Free;
  end;
end;

{ ---------------- custos no documento ---------------- }

procedure TestCostsDocument;
var
  P, Q: TPJProject;
  C: TAICostBreakdown;
  Err, Text: string;
  T: TPJTask;
  Total: Double;
  I: Integer;
begin
  P := TPJProject.Create;
  Q := TPJProject.Create;
  try
    BuildMotorExample(P);
    { carcaca: 1 d de Ana a R$ 90/h }
    C := P.TaskCost('T-0002');
    Check(Near(C.Work, 720) and Near(AICostTotal(C), 720), 'carcaca R$ 720: ' + FloatToStr(AICostTotal(C)));
    { impressao: 14 h de Ender-3 a R$ 3 + uso R$ 5 + 0,12 kg de PETG a R$ 120 }
    C := P.TaskCost('T-0010');
    Check(Near(C.Work, 42) and Near(C.PerUse, 5) and Near(C.Material, 14.4), 'impressao por origem');
    Check(Near(AICostTotal(C), 61.4), 'impressao R$ 61,40: ' + FloatToStr(AICostTotal(C)));
    { resumo soma as filhas }
    Total := 0;
    for I in P.ChildIndexes(P.IndexOfId('T-0009')) do Total := Total + AICostTotal(P.TaskCost(P[I].Id));
    Check(Near(AICostTotal(P.TaskCost('T-0009')), Total), 'resumo Fabricacao = soma das fabricacoes');
    { custo fixo }
    Check(P.SetFixedCost('T-0014', 180, acaEnd), 'custo fixo da placa');
    Check(P.UndoDescription = 'Custo fixo', 'custo fixo e um passo');
    Check(Near(P.TaskCost('T-0014').Fixed, 180), 'custo fixo somado');
    Check(Near(P.TaskCost('T-0009').Fixed, 180), 'resumo leva o custo fixo da filha');
    Check(not P.SetFixedCost('T-0014', -1, acaEnd), 'custo fixo negativo recusado');
    Check(P.SetFixedCost('T-0009', 20, acaStart), 'custo fixo no resumo');
    Check(Near(P.TaskCost('T-0009').Fixed, 200), 'resumo: filhas + o proprio');
    { projeto = soma do nivel 1 }
    Total := 0;
    for I := 0 to P.Count - 1 do
      if P[I].Level = 1 then Total := Total + AICostTotal(P.TaskCost(P[I].Id));
    Check(Near(AICostTotal(P.ProjectCost), Total) and (Total > 0), 'custo do projeto');
    { tarefa cancelada nao custa }
    T := P.FindTask('T-0013');
    P.BeginChange('cancelar'); T.State := tsCancelled; P.EndChange;
    Check(AICostTotal(P.TaskCost('T-0013')) = 0, 'cancelada sem custo');
    P.Undo;
    { material com origem }
    Check(P.SetMaterialQuantity('T-0010', 'PETG', 0.2, 'multislicer', Err), 'material do MultiSlicer: ' + Err);
    Check(P.Assignments[P.IndexOfAssignment('T-0010', P.FindResource('PETG').Id)].Source = 'multislicer', 'origem gravada');
    { editar a coluna sem mudar a quantidade mantem a origem; mudar apaga }
    Text := P.ResourcesText('T-0010');
    Check(P.SetResourcesText('T-0010', 'Ender-3; PETG[0.2 kg]', Err), 'coluna reescrita');
    Check(P.Assignments[P.IndexOfAssignment('T-0010', P.FindResource('PETG').Id)].Source = 'multislicer', 'origem mantida');
    Check(P.SetResourcesText('T-0010', 'Ender-3; PETG[0.3 kg]', Err), 'quantidade digitada');
    Check(P.Assignments[P.IndexOfAssignment('T-0010', P.FindResource('PETG').Id)].Source = '', 'digitada vira do usuario');
    Check(not P.SetMaterialQuantity('T-0010', 'Ana', 1, 'bom', Err), 'pessoa nao e material');
    { .mproj: ida e volta }
    T := P.FindTask('T-0002');
    P.SetTaskType('T-0002', False, attFixedUnits, True);
    T.Estimate.Minutes := 125; T.Estimate.MassG := 33.456; T.Estimate.Source := 'multislicer';
    T.Estimate.Material := 'PETG'; T.Estimate.Date := '2026-10-26T09:00:00';
    ProjectFromJSONText(Q, ProjectToJSONText(P));
    Check(not Q.FindTask('T-0002').TaskTypeAuto and (Q.FindTask('T-0002').TaskType = attFixedUnits) and
      Q.FindTask('T-0002').EffortDriven, 'tipo e empenho no arquivo');
    Check(Q.FindTask('T-0003').TaskTypeAuto, 'tipo automatico continua automatico');
    Check(Near(Q.FindTask('T-0014').FixedCost, 180) and (Q.FindTask('T-0014').FixedCostAccrual = acaEnd), 'custo fixo no arquivo');
    Check(Near(Q.FindResource('Ana').Rate, 90) and Near(Q.FindResource('Torno').PerUse, 15) and
      Near(Q.FindResource('PETG').UnitCost, 120), 'taxas no arquivo');
    Check((Q.FindTask('T-0002').Estimate.Minutes = 125) and Near(Q.FindTask('T-0002').Estimate.MassG, 33.46) and
      (Q.FindTask('T-0002').Estimate.Date = '2026-10-26T09:00:00'), 'estimativa no arquivo');
    Check(Near(AICostTotal(Q.ProjectCost), AICostTotal(P.ProjectCost)), 'mesmo custo depois de ler');
    Check(Pos('"rate" : 90', ProjectToJSONText(P)) > 0, 'taxa inteira sem casas: R$ 90');
    { valores invalidos }
    Text := StringReplace(ProjectToJSONText(P), '"rate" : 90', '"rate" : -90', []);
    try
      ProjectFromJSONText(Q, Text);
      Check(False, 'taxa negativa aceita');
    except
      on E: Exception do Check(Pos('negativo', E.Message) > 0, 'taxa negativa recusada: ' + E.Message);
    end;
    Text := StringReplace(ProjectToJSONText(P), '"fixed_cost_accrual" : "end"', '"fixed_cost_accrual" : "depois"', []);
    try
      ProjectFromJSONText(Q, Text);
      Check(False, 'acumulacao invalida aceita');
    except
      on E: Exception do Check(Pos('acumulacao', E.Message) > 0, 'acumulacao invalida recusada');
    end;
    Text := StringReplace(ProjectToJSONText(P), '"task_type" : "fixed_units"', '"task_type" : "fixo"', []);
    try
      ProjectFromJSONText(Q, Text);
      Check(False, 'tipo invalido aceito');
    except
      on E: Exception do Check(Pos('tipo de tarefa', E.Message) > 0, 'tipo de tarefa invalido recusado');
    end;
  finally
    Q.Free;
    P.Free;
  end;
end;

{ ---------------- estimativas ---------------- }

const
  SLICER_GCODE =
    '; MS-CONTRACT: 1' + LineEnding +
    '; MS-MACHINE: printer3d' + LineEnding +
    '; MS-PRINTER: Ender-3' + LineEnding +
    '; MS-MATERIAL: PETG' + LineEnding +
    '; MS-TEMP: HOTEND=235 BED=80 FIRST_HOTEND=240 FIRST_BED=85' + LineEnding +
    '; MS-PRINT: TIME=12600 LAYERS=210 FILAMENT_M=14.200 FILAMENT_G=42.50' + LineEnding +
    'G28' + LineEnding + 'G1 X10 Y10 F3000' + LineEnding + 'G1 X20 Y10 E1' + LineEnding;

function RouterGCode: string;
var I: Integer;
begin
  Result := '; MS-CONTRACT: 1' + LineEnding + '; MS-MACHINE: router' + LineEnding +
    'G21' + LineEnding + 'G90' + LineEnding + 'M3 S12000' + LineEnding + 'G0 X0 Y0 Z5' + LineEnding;
  for I := 1 to 40 do
    Result := Result + Format('G1 X%d Y0 Z-1 F600', [I * 5]) + LineEnding +
      Format('G1 X%d Y100 F600', [I * 5]) + LineEnding;
  Result := Result + 'M5' + LineEnding;
end;

procedure TestEstimates;
var
  P: TPJProject;
  R: TPJEstimateResult;
  ProjFile, Msg, Err, Equip: string;
  T: TPJTask;
  Before: Double;
  Undo: string;
begin
  ProjFile := TmpDir + 'motor.mproj';
  WriteText(TmpDir + 'fabricacao' + PathDelim + 'carcaca.gcode', SLICER_GCODE);
  WriteText(TmpDir + 'fabricacao' + PathDelim + 'carcaca.mslice', '{"format":"mslice"}');
  WriteText(TmpDir + 'fabricacao' + PathDelim + 'base.gcode', RouterGCode);
  { arquivo direto }
  R := PJEstimateGCode(tkPrint3D, TmpDir + 'fabricacao' + PathDelim + 'carcaca.gcode', 0, 0, 0, '');
  Check(R.Ok and (R.Estimate.Minutes = 210) and Near(R.Estimate.MassG, 42.5) and
    (R.Estimate.Material = 'PETG') and (R.Estimate.Source = 'multislicer'), 'MS-PRINT: 3 h 30 e 42,5 g: ' + R.Message);
  Check(R.Estimate.Machine = 'Ender-3', 'impressora do cabecalho');
  Check(Length(R.Estimate.Date) = 19, 'data ISO da estimativa');
  R := PJEstimateGCode(tkRouter, TmpDir + 'fabricacao' + PathDelim + 'base.gcode', 0, 0, 0, '');
  Check(R.Ok and (R.Estimate.Source = 'gcode') and (R.Estimate.Minutes >= 13) and (R.Estimate.Minutes <= 20),
    Format('router pelo planejador: ~14 min de corte a 600 mm/min (%d min) %s', [R.Estimate.Minutes, R.Message]));
  Check(Pos('generico', R.Estimate.Note) > 0, 'sem maquina: aviso do envelope generico');
  R := PJEstimateGCode(tkRouter, TmpDir + 'nao_existe.gcode', 0, 0, 0, '');
  Check(not R.Ok and (Pos('nao encontrado', R.Message) > 0), 'G-code ausente');
  Check(PJFindGCodeFor(TmpDir + 'fabricacao' + PathDelim + 'carcaca.mslice') <> '', 'G-code ao lado do .mslice');
  Check(PJFindGCodeFor(TmpDir + 'fabricacao' + PathDelim + 'sem.lart') = '', 'documento sem G-code');
  { pela tarefa do exemplo }
  P := TPJProject.Create;
  try
    BuildMotorExample(P);
    R := PJEstimateTask(P, 'T-0002', ProjFile);
    Check(not R.Ok and (Pos('impressao', R.Message) > 0), 'peca nao e fabricacao');
    R := PJEstimateTask(P, 'T-0010', ProjFile);
    Check(not R.Ok and (Pos('Vincule', R.Message) > 0), 'sem arquivo vinculado');
    T := P.FindTask('T-0010');
    T.Artifact.Path := 'fabricacao' + PathDelim + 'carcaca.mslice';
    R := PJEstimateTask(P, 'T-0010', ProjFile);
    Check(R.Ok and (R.Estimate.Minutes = 210), 'impressao pelo .mslice + .gcode: ' + R.Message);
    Check(R.Estimate.FileName = 'fabricacao' + PathDelim + 'carcaca.gcode', 'arquivo relativo: ' + R.Estimate.FileName);
    Check(Pos('MultiSlicer: 3h30', PJEstimateCaption(R.Estimate)) = 1, 'legenda: ' + PJEstimateCaption(R.Estimate));
    Check(Pos('43 g PETG', PJEstimateCaption(R.Estimate)) > 0, 'legenda com a massa: ' + PJEstimateCaption(R.Estimate));
    { sugerir nao muda a duracao }
    Check(P.SetEstimate('T-0010', R.Estimate), 'estimativa guardada');
    Check(P.FindTask('T-0010').Duration.Minutes = 840, 'sugestao nao altera a duracao');
    Before := AICostTotal(P.TaskCost('T-0010'));
    { aceitar: duracao + filamento num passo }
    Check(P.AcceptEstimate('T-0010', Msg), 'aceitar: ' + Msg);
    T := P.FindTask('T-0010');
    Check(T.Duration.Minutes = 210, 'duracao 3 h 30');
    Check(Near(P.Assignments[P.IndexOfAssignment('T-0010', P.FindResource('PETG').Id)].Quantity, 0.0425, 1E-6),
      'PETG 0,0425 kg do MultiSlicer');
    Check(P.Assignments[P.IndexOfAssignment('T-0010', P.FindResource('PETG').Id)].Source = 'multislicer', 'origem MultiSlicer');
    Check(AICostTotal(P.TaskCost('T-0010')) < Before, 'custo menor com o tempo real');
    Undo := P.UndoDescription;
    Check(Undo = 'Aplicar estimativa', 'um passo de desfazer: ' + Undo);
    P.Undo;
    Check((P.FindTask('T-0010').Duration.Minutes = 840) and
      Near(P.Assignments[P.IndexOfAssignment('T-0010', P.FindResource('PETG').Id)].Quantity, 0.12),
      'desfazer volta duracao e material');
    { router com maquina do cadastro do MultiCNC }
    T := P.FindTask('T-0012');
    T.Artifact.Path := 'fabricacao' + PathDelim + 'base.gcode';
    Equip := TmpDir + 'multicnc.json';
    WriteText(Equip, '{"version":1,"equipment":[{"name":"Laser 10 W","machine_type":1,' +
      '"work_x":400,"work_y":400,"work_z":50}]}');
    R := PJEstimateTask(P, 'T-0012', ProjFile, Equip);
    Check(R.Ok and (R.Estimate.Machine = 'Laser 10 W'), 'maquina atribuida na estimativa: ' + R.Message);
    { material ausente: avisa sem quebrar }
    T := P.FindTask('T-0010');
    T.Estimate.Minutes := 60; T.Estimate.MassG := 10; T.Estimate.Material := 'TPU';
    Check(P.SetResourcesText('T-0010', 'Ender-3', Err), 'sem material');
    Check(P.AcceptEstimate('T-0010', Msg) and (Pos('cadastre o material', Msg) > 0), 'aviso de material: ' + Msg);
    Check(not P.AcceptEstimate('T-0002', Msg), 'tarefa sem estimativa');
  finally
    P.Free;
  end;
end;

{ ---------------- lista de materiais do MultiAssembly ---------------- }

procedure TestBOM;
var
  P: TPJProject;
  A: TAssemblyProject;
  C: TAssemblyComponent;
  FileName: string;
  R: TPJBOMResult;
  Buy: TPJTask;
  Res: TPJResource;

  procedure Comp(const AId, AModel: string; AKind: TAssemblyComponentKind);
  begin
    C := Default(TAssemblyComponent);
    C.ID := AId; C.Name := AId; C.Model := AModel; C.Kind := AKind;
    C.Size.X := 10; C.Size.Y := 10; C.Size.Z := 10;
    A.AddComponent(C);
  end;

begin
  FileName := TmpDir + 'montagens' + PathDelim + 'motor.massembly';
  ForceDirectories(ExtractFilePath(FileName));
  A := TAssemblyProject.Create;
  try
    A.Name := 'Motor';
    Comp('B1', '608', ackBearing);
    Comp('B2', '608', ackBearing);
    Comp('S1', 'M3x10', ackFastenerScrew);
    Comp('S2', 'M3x10', ackFastenerScrew);
    Comp('S3', 'M3x10', ackFastenerScrew);
    Comp('P1', 'carcaca', ackMechanicalPart);
    Comp('PCB1', 'driver', ackPCB);
    A.SaveToFile(FileName);
  finally
    A.Free;
  end;
  P := TPJProject.Create;
  try
    BuildMotorExample(P);
    P.FindTask('T-0006').Artifact.Path := 'montagens' + PathDelim + 'motor.massembly';
    Check(PJFindAssemblyFile(P, TmpDir + 'motor.mproj') = FileName, 'montagem achada pela tarefa');
    R := PJImportBOM(P, 'T-0002', FileName);
    Check(not R.Ok and (Pos('compra', R.Message) > 0), 'so em tarefa de compra');
    Buy := P.AddTask('', tkPurchase, 'Comprar componentes', 'rolamentos e parafusos');
    R := PJImportBOM(P, Buy.Id, TmpDir + 'nada.massembly');
    Check(not R.Ok and (Pos('Vincule', R.Message) > 0), 'montagem ausente');
    R := PJImportBOM(P, Buy.Id, FileName);
    Check(R.Ok and (R.Added = 2) and (R.Skipped = 2), 'dois itens comprados, peca e placa fora: ' + R.Message);
    Check(P.UndoDescription = 'Lista de materiais do MultiAssembly', 'um passo de desfazer');
    Res := P.FindResource('Rolamento 608');
    Check((Res <> nil) and (Res.RType = rtMaterial) and (Res.MaterialUnit = 'un') and (Res.Group = 'Compras'),
      'rolamento como material');
    Check(Near(P.Assignments[P.IndexOfAssignment(Buy.Id, Res.Id)].Quantity, 2) and
      (P.Assignments[P.IndexOfAssignment(Buy.Id, Res.Id)].Source = 'bom'), 'dois rolamentos da lista');
    Check(Near(P.Assignments[P.IndexOfAssignment(Buy.Id, P.FindResource('Parafuso M3x10').Id)].Quantity, 3), 'tres parafusos');
    { custo unitario cadastrado depois entra no custo da compra; reimportar mantem }
    Res.UnitCost := 12.5;
    R := PJImportBOM(P, Buy.Id, FileName);
    Check(R.Ok and (R.Added = 0) and (R.Updated = 2), 'reimportar atualiza');
    Check(Near(P.FindResource('Rolamento 608').UnitCost, 12.5), 'custo unitario mantido');
    Check(Near(P.TaskCost(Buy.Id).Material, 25), 'compra R$ 25 em rolamentos');
    P.Undo; P.Undo;
    Check(P.FindResource('Rolamento 608') = nil, 'desfazer remove os itens');
  finally
    P.Free;
  end;
end;

begin
  Passed := 0; Failed := 0;
  TmpDir := IncludeTrailingPathDelimiter(GetTempDir(False)) + 'mproj_custos_' + IntToStr(GetProcessID) + PathDelim;
  ForceDirectories(TmpDir);
  TestTaskTypeCore;
  TestCostCore;
  TestTaskTypeDocument;
  TestCostsDocument;
  TestEstimates;
  TestBOM;
  if Failed = 0 then
    Writeln(Format('PASS: %d checks (tipos de tarefa, empenho, custos, acumulacao, estimativa por G-code e MultiSlicer, lista de materiais, .mproj)', [Passed]))
  else
  begin
    Writeln(Format('FAIL: %d de %d checks', [Failed, Passed + Failed]));
    Halt(1);
  end;
end.
