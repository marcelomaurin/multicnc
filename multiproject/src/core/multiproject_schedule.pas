unit multiproject_schedule;

{ Cronograma do MultiProject (fase 3, PJ-S01..S10, PJ-C01..C05).

  Adaptador do documento para o TAICPMScheduler (CHATGPT / AI Project Core):
  - grafo expandido do multiproject_graph (vinculos de resumo -> folhas);
  - calendarios do projeto (TAIWorkCalendar) e calendario de cada tarefa;
  - duracao, decorrida, restricao, data limite e modo manual de cada tarefa;
  - resumos consolidados pelo pai na estrutura de topicos.

  O resultado (datas, margens, critico) nao e gravado no .mproj: e
  recalculado ao abrir e a cada alteracao (PJ-S11). Os avisos viram
  TPJIssues com o ID da tarefa (PJ-S10).

  Recursos (fase 7, PJ-R03..R05, PJ-C03): depois do cronograma, a carga de
  cada recurso (TAIResourceLoad, AI Project Core) acha as superalocacoes, que
  viram avisos com o recurso, o periodo e as tarefas. Tarefa sem calendario
  proprio e com maquina atribuida usa o calendario da maquina (impressora 24 h).
  O atraso do nivelamento (TPJTask.LevelStart) entra como "nao iniciar antes". }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, aitaskgraph, aiworkcalendar, aicpmscheduler, airesourceload,
  multiproject_types, multiproject_document;

type
  TPJSchedule = class
  private
    FProject: TPJProject;
    FLoad: TAIResourceLoad;
    FResIndex: array of Integer;       // recurso do documento -> recurso da carga
    FResults: array of TAICPMResult;
    FIssues: TPJIssues;
    FStart, FFinish: TDateTime;
    FValid: Boolean;
    FError: string;
    function GetResult(I: Integer): TAICPMResult;
    function TaskName(Task: Integer): string;
  public
    constructor Create(AProject: TPJProject);
    destructor Destroy; override;
    { False e Error preenchido quando o documento nao permite calcular
      (vinculo invalido, calendario sem expediente...) }
    function Compute: Boolean;
    function Count: Integer;
    function IndexOf(const ATaskId: string): Integer;
    function StartOf(const ATaskId: string): TDateTime;
    function FinishOf(const ATaskId: string): TDateTime;
    function CriticalIds: string;
    function CriticalCount: Integer;
    { recursos }
    function OverloadCount: Integer;
    function ResourceOverallocated(const AResourceId: string): Boolean;
    function TaskOverallocated(const ATaskId: string): Boolean;
    { a tarefa esta num conflito deste recurso }
    function AssignmentOverallocated(const ATaskId, AResourceId: string): Boolean;
    function ResourceWork(const AResourceId: string): Int64;
    function ResourcePeak(const AResourceId: string): Double;
    property Load: TAIResourceLoad read FLoad;
    property Results[I: Integer]: TAICPMResult read GetResult; default;
    property Issues: TPJIssues read FIssues;
    property ProjectStart: TDateTime read FStart;
    property ProjectFinish: TDateTime read FFinish;
    property Valid: Boolean read FValid;
    property Error: string read FError;
  end;

{ usados tambem pelo nivelamento (multiproject_resources) }
function PJFillScheduler(P: TPJProject; Sc: TAICPMScheduler; G: TAITaskGraph; out Err: string): Boolean;
function PJFillLoad(P: TPJProject; L: TAIResourceLoad; out ResIndex: TPJIntArray): Boolean;
procedure PJSyncLoadDates(L: TAIResourceLoad; Sc: TAICPMScheduler);

implementation

uses
  multiproject_graph;

constructor TPJSchedule.Create(AProject: TPJProject);
begin
  inherited Create;
  FProject := AProject;
  FLoad := TAIResourceLoad.Create;
  FLoad.OnTaskName := @TaskName;
end;

destructor TPJSchedule.Destroy;
begin
  FLoad.Free;
  inherited Destroy;
end;

function TPJSchedule.TaskName(Task: Integer): string;
begin
  if (Task >= 0) and (Task < FProject.Count) then Result := FProject[Task].Id
  else Result := '?';
end;

function TPJSchedule.OverloadCount: Integer;
begin
  Result := FLoad.OverloadCount;
end;

function TPJSchedule.ResourceOverallocated(const AResourceId: string): Boolean;
var R: Integer;
begin
  R := FProject.IndexOfResource(AResourceId);
  Result := (R >= 0) and (R <= High(FResIndex)) and FLoad.IsOverallocated(FResIndex[R]);
end;

function TPJSchedule.TaskOverallocated(const ATaskId: string): Boolean;
begin
  Result := FLoad.TaskOverloaded(FProject.IndexOfId(ATaskId));
end;

function TPJSchedule.AssignmentOverallocated(const ATaskId, AResourceId: string): Boolean;
var R, T, O, K: Integer; Ov: TAIOverload;
begin
  Result := False;
  R := FProject.IndexOfResource(AResourceId);
  T := FProject.IndexOfId(ATaskId);
  if (R < 0) or (R > High(FResIndex)) or (T < 0) then Exit;
  for O := 0 to FLoad.OverloadCount - 1 do
  begin
    Ov := FLoad.Overloads[O];
    if Ov.Resource <> FResIndex[R] then Continue;
    for K in Ov.Assignments do
      if FLoad.Assignments[K].Task = T then Exit(True);
  end;
end;

function TPJSchedule.ResourceWork(const AResourceId: string): Int64;
var R: Integer;
begin
  R := FProject.IndexOfResource(AResourceId);
  if (R < 0) or (R > High(FResIndex)) then Exit(0);
  Result := FLoad.ResourceWork(FResIndex[R]);
end;

function TPJSchedule.ResourcePeak(const AResourceId: string): Double;
var R: Integer;
begin
  R := FProject.IndexOfResource(AResourceId);
  if (R < 0) or (R > High(FResIndex)) then Exit(0);
  Result := FLoad.PeakUnits(FResIndex[R]);
end;

function TPJSchedule.GetResult(I: Integer): TAICPMResult;
begin
  if not FValid then raise EPJError.Create('cronograma nao calculado: ' + FError);
  Result := FResults[I];
end;

function TPJSchedule.Count: Integer;
begin
  Result := Length(FResults);
end;

function TPJSchedule.IndexOf(const ATaskId: string): Integer;
begin
  Result := FProject.IndexOfId(ATaskId);
end;

function TPJSchedule.StartOf(const ATaskId: string): TDateTime;
begin
  Result := Results[IndexOf(ATaskId)].Start;
end;

function TPJSchedule.FinishOf(const ATaskId: string): TDateTime;
begin
  Result := Results[IndexOf(ATaskId)].Finish;
end;

function TPJSchedule.CriticalCount: Integer;
var I: Integer;
begin
  Result := 0;
  if not FValid then Exit;
  for I := 0 to High(FResults) do
    if FResults[I].Critical and not FProject.HasChildren(I) then Inc(Result);
end;

function TPJSchedule.CriticalIds: string;
var I: Integer;
begin
  Result := '';
  if not FValid then Exit;
  for I := 0 to High(FResults) do
    if FResults[I].Critical and not FProject.HasChildren(I) then
    begin
      if Result <> '' then Result := Result + ',';
      Result := Result + FProject[I].Id;
    end;
end;

{ calendario em que a tarefa trabalha: o dela, senao o da primeira maquina
  atribuida, senao o do projeto (-1) }
function TaskCalendarIndex(P: TPJProject; I: Integer; out Err: string): Integer;
var T: TPJTask; A, R: Integer; Res: TPJResource;
begin
  Err := '';
  T := P[I];
  if T.CalendarName <> '' then
  begin
    Result := P.IndexOfCalendar(T.CalendarName);
    if Result < 0 then Err := Format('%s usa o calendario inexistente "%s"', [T.Id, T.CalendarName]);
    Exit;
  end;
  Result := -1;
  for A in P.AssignmentsOfTask(T.Id) do
  begin
    R := P.IndexOfResource(P.Assignments[A].ResourceId);
    if R < 0 then Continue;
    Res := P.Resources[R];
    if (Res.RType = rtMachine) and (Res.CalendarName <> '') then
    begin
      Result := P.IndexOfCalendar(Res.CalendarName);
      if Result < 0 then Err := Format('%s usa o calendario inexistente "%s"', [Res.Name, Res.CalendarName]);
      Exit;
    end;
  end;
end;

function PJFillScheduler(P: TPJProject; Sc: TAICPMScheduler; G: TAITaskGraph; out Err: string): Boolean;
var
  I: Integer;
  T: TPJTask;
  C: TAICPMTask;
begin
  Err := '';
  Sc.Clear;
  Sc.ProjectCalendar := P.ProjectCalendar;
  for I := 0 to P.CalendarCount - 1 do Sc.AddCalendar(P.Calendars[I]);
  Sc.Graph := G;
  Sc.ProjectStart := P.StartDate;
  Sc.CriticalSlack := P.CriticalSlack;
  for I := 0 to P.Count - 1 do
  begin
    T := P[I];
    C := AINewCPMTask(T.Id, T.Duration.Minutes);
    C.IsSummary := P.HasChildren(I);
    C.Parent := P.ParentIndex(I);
    if not C.IsSummary then
    begin
      C.Elapsed := T.Duration.Elapsed;
      C.Calendar := TaskCalendarIndex(P, I, Err);
      if Err <> '' then Exit(False);
      C.Constraint := T.Constraint;
      C.ConstraintDate := T.ConstraintDate;
      C.Deadline := T.Deadline;
      C.Manual := (T.Mode = smManual) and (T.ManualStart > 0);
      C.ManualStart := T.ManualStart;
      C.ManualFinish := T.ManualFinish;
      C.LevelStart := T.LevelStart;
      if (C.Constraint in [actSNET, actSNLT, actFNET, actFNLT, actMSO, actMFO]) and (C.ConstraintDate = 0) then
        C.Constraint := actASAP;   // a validacao ja acusa a restricao sem data
    end
    else
      C.Duration := 0;
    Sc.AddTask(C);
  end;
  Result := True;
end;

function PJFillLoad(P: TPJProject; L: TAIResourceLoad; out ResIndex: TPJIntArray): Boolean;
var
  I, T, R: Integer;
  Res: TPJResource;
  Kind: TAIResourceKind;
  Cal: TAIWorkCalendar;
  X: TPJAssignment;
begin
  L.Clear;
  SetLength(ResIndex, P.ResourceCount);
  for I := 0 to P.ResourceCount - 1 do
  begin
    Res := P.Resources[I];
    case Res.RType of
      rtMaterial: Kind := arkMaterial;
      rtCost: Kind := arkCost;
    else
      Kind := arkWork;
    end;
    if Res.CalendarName <> '' then Cal := P.FindCalendar(Res.CalendarName) else Cal := nil;
    if Cal = nil then Cal := P.ProjectCalendar;
    ResIndex[I] := L.AddResource(AINewResource(Res.Id, Res.Name, Res.MaxUnits, Kind, Cal));
  end;
  for I := 0 to P.AssignmentCount - 1 do
  begin
    X := P.Assignments[I];
    T := P.IndexOfId(X.TaskId);
    R := P.IndexOfResource(X.ResourceId);
    if (T < 0) or (R < 0) or P.HasChildren(T) or (P[T].State = tsCancelled) then Continue;
    L.AddAssignment(T, ResIndex[R], X.Units, 0, 0);
  end;
  Result := True;
end;

procedure PJSyncLoadDates(L: TAIResourceLoad; Sc: TAICPMScheduler);
var A, T: Integer;
begin
  for A := 0 to L.AssignmentCount - 1 do
  begin
    T := L.Assignments[A].Task;
    L.SetAssignmentDates(A, Sc.Results[T].Start, Sc.Results[T].Finish);
  end;
  L.Compute;
end;

function TPJSchedule.Compute: Boolean;
var
  G: TAITaskGraph;
  Sc: TAICPMScheduler;
  I: Integer;
  W: TAICPMWarning;
  Ov: TAIOverload;
  Idx: TPJIntArray;
begin
  FValid := False;
  FError := '';
  FIssues := nil;
  FResults := nil;
  FLoad.Clear;
  FResIndex := nil;
  G := BuildTaskGraph(FProject, FError);
  if G = nil then Exit(False);
  Sc := TAICPMScheduler.Create;
  try
    try
      if not PJFillScheduler(FProject, Sc, G, FError) then Exit(False);
      Sc.Run;
    except
      on E: EAIWorkCalendar do begin FError := 'calendario: ' + E.Message; Exit(False); end;
      on E: EAICPMScheduler do begin FError := E.Message; Exit(False); end;
    end;
    SetLength(FResults, Sc.TaskCount);
    for I := 0 to Sc.TaskCount - 1 do FResults[I] := Sc.Results[I];
    for I := 0 to Sc.WarningCount - 1 do
    begin
      W := Sc.Warnings[I];
      AddIssue(FIssues, FProject[W.Task].Id, svWarning, W.Message);
    end;
    { carga dos recursos e superalocacao (PJ-R04) }
    PJFillLoad(FProject, FLoad, Idx);
    SetLength(FResIndex, Length(Idx));
    for I := 0 to High(Idx) do FResIndex[I] := Idx[I];
    PJSyncLoadDates(FLoad, Sc);
    for I := 0 to FLoad.OverloadCount - 1 do
    begin
      Ov := FLoad.Overloads[I];
      AddIssue(FIssues, FProject[FLoad.Assignments[Ov.Assignments[0]].Task].Id, svWarning,
        FLoad.OverloadMessage(I) + ': nivele (etapa 5) ou troque o recurso');
    end;
    FStart := Sc.ProjectStart;
    FFinish := Sc.ProjectFinish;
    FValid := True;
    Result := True;
  finally
    Sc.Free;
    G.Free;
  end;
end;

end.
