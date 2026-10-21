unit multiproject_resources;

{ Recursos do MultiProject (fase 7, PJ-R01..R05).

  - Nivelamento (PJ-R05): monta o cronograma do documento, entrega a carga dos
    recursos ao TAIResourceLeveler (CHATGPT / AI Project Core) e grava o
    resultado em TPJTask.LevelStart num unico passo de desfazer. Antes de
    nivelar, limpa o nivelamento anterior (como o Project). Tarefa em
    andamento, concluida ou cancelada nao se move; a prioridade da tarefa
    (0..1000) decide quem fica.
  - Limpar nivelamento: zera LevelStart e o cronograma volta ao original.
  - Importar maquinas do MultiCNC (PJ-R02): le o cadastro de equipamentos
    (multicnc_equipment, somente leitura) e cria ou atualiza um recurso do
    tipo maquina por equipamento, com o calendario 24 h. Nada e apagado: um
    equipamento que sumiu do cadastro continua como recurso.
  - Maquinas compativeis com a tarefa (combo da tela) e resumo da carga. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, aitaskgraph, aiworkcalendar, aicpmscheduler, airesourceload,
  multiproject_types, multiproject_document;

type
  TPJLevelResult = record
    Ok: Boolean;                 // sem conflito depois de nivelar
    Moved: Integer;              // tarefas atrasadas
    Unresolved: TStringList;     // conflitos que sobraram (o chamador libera)
    Error: string;               // o cronograma nao pode ser montado
    FinishBefore, FinishAfter: TDateTime;
  end;

function LevelProject(P: TPJProject; AWithinSlack: Boolean): TPJLevelResult;
function ClearLeveling(P: TPJProject): Boolean;
function LevelSummary(const R: TPJLevelResult): string;

{ importa as maquinas do cadastro do MultiCNC (EquipmentFileName, ou AFileName) }
function ImportMachines(P: TPJProject; const AFileName: string; out Added, Updated: Integer;
  out Err: string): Boolean;

{ recursos do tipo maquina que fazem a tarefa (todos os de trabalho se a tarefa nao usa maquina) }
function CompatibleResources(P: TPJProject; const ATaskId: string): TPJIntArray;
function ResourceCaption(R: TPJResource): string;

implementation

uses
  multiproject_graph, multiproject_schedule, multicnc_types, multicnc_equipment;

function LevelProject(P: TPJProject; AWithinSlack: Boolean): TPJLevelResult;
var
  G: TAITaskGraph;
  Sc: TAICPMScheduler;
  L: TAIResourceLoad;
  Lv: TAIResourceLeveler;
  Opt: TAILevelOptions;
  Idx: TPJIntArray;
  I: Integer;
  T: TPJTask;
  Changed: Boolean;
begin
  Result.Ok := False;
  Result.Moved := 0;
  Result.Unresolved := TStringList.Create;
  Result.Error := '';
  Result.FinishBefore := 0;
  Result.FinishAfter := 0;
  G := BuildTaskGraph(P, Result.Error);
  if G = nil then Exit;
  Sc := TAICPMScheduler.Create;
  L := TAIResourceLoad.Create;
  Lv := TAIResourceLeveler.Create(Sc, L);
  try
    try
      if not PJFillScheduler(P, Sc, G, Result.Error) then Exit;
      Sc.ClearLeveling;
      Sc.Run;
      Result.FinishBefore := Sc.ProjectFinish;
      PJFillLoad(P, L, Idx);
      for I := 0 to P.Count - 1 do
      begin
        T := P[I];
        Lv.SetPriority(I, T.Priority);
        Lv.SetDoNotLevel(I, T.State in [tsInProgress, tsDone, tsCancelled]);
      end;
      Opt := AIDefaultLevelOptions;
      Opt.WithinSlack := AWithinSlack;
      Result.Ok := Lv.Level(Opt);
      for I := 0 to Lv.UnresolvedCount - 1 do Result.Unresolved.Add(Lv.Unresolved[I]);
      Result.FinishAfter := Sc.ProjectFinish;
    except
      on E: EAIWorkCalendar do begin Result.Error := 'calendario: ' + E.Message; Exit; end;
      on E: EAICPMScheduler do begin Result.Error := E.Message; Exit; end;
    end;
    { grava os atrasos num passo so }
    Changed := False;
    for I := 0 to P.Count - 1 do
      if Abs(P[I].LevelStart - Sc.Tasks[I].LevelStart) > 0.5 / 1440 then Changed := True;
    if Changed then
    begin
      P.BeginChange('Nivelar recursos');
      try
        for I := 0 to P.Count - 1 do P[I].LevelStart := Sc.Tasks[I].LevelStart;
      finally
        P.EndChange;
      end;
    end;
    Result.Moved := Lv.DelayCount;
  finally
    Lv.Free;
    L.Free;
    Sc.Free;
    G.Free;
  end;
end;

function ClearLeveling(P: TPJProject): Boolean;
var I: Integer;
begin
  Result := P.HasLeveling;
  if not Result then Exit;
  P.BeginChange('Limpar nivelamento');
  try
    for I := 0 to P.Count - 1 do P[I].LevelStart := 0;
  finally
    P.EndChange;
  end;
end;

function LevelSummary(const R: TPJLevelResult): string;
begin
  if R.Error <> '' then Exit('Nao foi possivel nivelar: ' + R.Error);
  if R.Moved = 0 then Result := 'Nenhuma tarefa precisou mudar'
  else if R.Moved = 1 then Result := '1 tarefa atrasada'
  else Result := Format('%d tarefas atrasadas', [R.Moved]);
  if (R.FinishAfter > R.FinishBefore + 0.5 / 1440) then
    Result := Result + Format('; termino passa de %s para %s',
      [FormatDateTime('dd"/"mm hh":"nn', R.FinishBefore), FormatDateTime('dd"/"mm hh":"nn', R.FinishAfter)]);
  if R.Unresolved.Count > 0 then
    Result := Result + Format('; %d conflito(s) sem solucao', [R.Unresolved.Count])
  else
    Result := Result + '; sem superalocacao';
end;

function MapMachine(K: TMachineType): TPJMachineType;
begin
  case K of
    mtRouter: Result := pmRouter;
    mtLaser: Result := pmLaser;
    mtPrinter3D: Result := pmPrinter3D;
  else
    Result := pmOther;
  end;
end;

function ImportMachines(P: TPJProject; const AFileName: string; out Added, Updated: Integer;
  out Err: string): Boolean;
var
  Store: TEquipmentStore;
  I, R: Integer;
  E: TEquipmentProfile;
  Res: TPJResource;
  FileName: string;
begin
  Added := 0;
  Updated := 0;
  Err := '';
  if AFileName <> '' then FileName := AFileName else FileName := EquipmentFileName;
  if not FileExists(FileName) then
  begin
    Err := 'cadastro de maquinas do MultiCNC nao encontrado: ' + FileName;
    Exit(False);
  end;
  Store := TEquipmentStore.Create(FileName);
  try
    try
      Store.Load;
    except
      on Ex: Exception do
      begin
        Err := 'cadastro de maquinas do MultiCNC invalido: ' + Ex.Message;
        Exit(False);
      end;
    end;
    if Store.Count = 0 then
    begin
      Err := 'o cadastro do MultiCNC nao tem maquinas';
      Exit(False);
    end;
    P.BeginChange('Importar maquinas do MultiCNC');
    try
      for I := 0 to Store.Count - 1 do
      begin
        E := Store.Item(I);
        Res := nil;
        for R := 0 to P.ResourceCount - 1 do
          if SameText(P.Resources[R].Equipment, E.Name) or
             ((P.Resources[R].RType = rtMachine) and SameText(P.Resources[R].Name, E.Name)) then
            Res := P.Resources[R];
        if Res = nil then
        begin
          if P.IndexOfResource(E.Name) >= 0 then Continue;   // nome ja usado por outro tipo
          Res := P.AddResource(E.Name, rtMachine);
          Res.Group := 'Oficina';
          Inc(Added);
        end
        else
          Inc(Updated);
        Res.RType := rtMachine;
        Res.Equipment := E.Name;
        Res.MachineType := MapMachine(E.MachineType);
        Res.MaxUnits := 1;
        if Res.CalendarName = '' then Res.CalendarName := PJ_CAL_24H;
      end;
    finally
      P.EndChange;
    end;
    Result := True;
  finally
    Store.Free;
  end;
end;

function CompatibleResources(P: TPJProject; const ATaskId: string): TPJIntArray;
var
  T: TPJTask;
  Need: TPJMachineTypes;
  I: Integer;
  Res: TPJResource;
begin
  Result := nil;
  T := P.FindTask(ATaskId);
  if T = nil then Exit;
  Need := MachineTypesFor(T.Kind);
  for I := 0 to P.ResourceCount - 1 do
  begin
    Res := P.Resources[I];
    if Res.RType = rtMachine then
    begin
      if (Need = []) or not (Res.MachineType in Need) then Continue;
    end
    else if Res.RType = rtCost then
      Continue;
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := I;
  end;
end;

function ResourceCaption(R: TPJResource): string;
begin
  case R.RType of
    rtMachine: Result := MachineTypeCaption(R.MachineType);
    rtPerson: if R.Role <> '' then Result := R.Role else Result := 'Pessoa';
  else
    Result := ResourceTypeCaption(R.RType);
  end;
  if R.RType in [rtPerson, rtAI, rtMachine] then
    Result := Result + '  ' + IntToStr(Round(R.MaxUnits * 100)) + '%';
  if R.CalendarName <> '' then Result := Result + '  ' + R.CalendarName;
end;

end.
