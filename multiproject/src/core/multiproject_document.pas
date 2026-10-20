unit multiproject_document;

{ Documento do MultiProject: objetivo, tarefas em estrutura de topicos (EAP),
  comandos com desfazer/refazer e validacao (fase 1 de multiproject/docs/TAREFA.md).

  Estrutura de topicos como no Microsoft Project: a lista de tarefas e plana,
  em ordem de exibicao, e cada tarefa tem um nivel (1 = filha do objetivo).
  O pai de uma tarefa e a tarefa anterior mais proxima com nivel - 1.
  Invariante: Level[0] = 1 e Level[i] <= Level[i-1] + 1.

  O codigo EAP e calculado (nunca gravado). O ID e estavel e nunca reaproveitado
  (PJ-T10): T-0001 para tarefas, M-0001 para marcos, mesmo contador.

  Vinculos (fase 2, PJ-G01..G07): TI/II/TT/IT com latencia, guardados no
  documento e conferidos pelo grafo (aitaskgraph, via multiproject_graph).
  Vinculo em tarefa de resumo vale para as folhas dela; o grafo expandido e
  sempre aciclico, entao ligar um resumo a propria subtarefa e recusado.

  Reuso do CHATGPT / AI Project Core: TAIUndoHistory (desfazer por fotos do
  documento em JSON), TAIDuration (duracao), TAITaskGraph (grafo). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Contnrs, fpjson, aiprojectduration, aiundohistory, aitaskgraph,
  aiworkcalendar, aicpmscheduler, multiproject_types;

const
  PJ_UNDO_LIMIT = 100;
  PJ_CAL_STANDARD = 'padrao';
  PJ_CAL_24H = '24h';

type
  TPJTask = class
  public
    Id: string;
    Name: string;
    ShortDesc: string;
    LongDesc: string;
    TechItems: TPJSpecItems;
    TechText: string;
    FuncSpec: TPJCriteria;
    Kind: TPJTaskKind;
    Process: TPJProcess;
    State: TPJTaskState;
    Mode: TPJScheduleMode;
    Duration: TAIDuration;
    { cronograma (fase 3, PJ-S01..S05, PJ-T16, PJ-C04) }
    Constraint: TAIConstraintType;
    ConstraintDate: TDateTime;
    Deadline: TDateTime;           // 0 = sem data limite
    ManualStart, ManualFinish: TDateTime;
    CalendarName: string;          // '' = calendario do projeto
    Notes: string;
    Level: Integer;
    { objeto JSON lido do arquivo: preserva campos que esta versao nao conhece }
    Raw: TJSONObject;
    constructor Create;
    destructor Destroy; override;
    procedure AddTechItem(const AKey, AValue, AUnit: string);
    procedure AddCriterion(const AId, AText: string);
    function TechValue(const AKey: string): string;
  end;

  { vinculo predecessora -> sucessora (aresta do grafo) }
  TPJLink = class
  public
    FromId, ToId: string;
    LinkType: TAITaskLinkType;
    Lag: TAITaskLag;
    { a sucessora consome o arquivo da predecessora (PJ-G06) }
    Artifact: Boolean;
    Raw: TJSONObject;
    destructor Destroy; override;
  end;

  TPJProject = class
  private
    FTasks: TFPObjectList;
    FLinks: TFPObjectList;
    FCalendars: TFPObjectList;
    FLastError: string;
    FHistory: TAIUndoHistory;
    FModified: Boolean;
    function GetCalendarCount: Integer;
    function GetCalendar(I: Integer): TAIWorkCalendar;
    function GetLinkCount: Integer;
    function GetLink(I: Integer): TPJLink;
    function IdExists(const AId: string): Boolean;
    function LevelsKeepGraph(AFirst, ALast, ADelta: Integer; out Err: string): Boolean;
    function GetCount: Integer;
    function GetTask(I: Integer): TPJTask;
    procedure RestoreSnapshot(const Snap: string);
    function SnapshotText: string;
    procedure RequireIndex(I: Integer);
  public
    Id: string;
    Name: string;
    Revision: string;
    Author: string;
    ObjectiveShort: string;
    ObjectiveLong: string;
    ObjectiveScope: string;
    ObjectiveSuccess: TPJCriteria;
    StartDate: TDateTime;
    StatusDate: TDateTime;
    ScheduleFrom: TPJScheduleFrom;
    MinutesPerDay: Integer;
    MinutesPerWeek: Integer;
    NextNumber: Integer;
    ProjectCalendarName: string;
    CriticalSlack: Int64;          // minutos; critica = margem total <= limiar
    Raw: TJSONObject;
    constructor Create;
    destructor Destroy; override;
    procedure Clear;

    { --- consulta --- }
    function IndexOfId(const AId: string): Integer;
    function FindTask(const AId: string): TPJTask;
    function ParentIndex(I: Integer): Integer;
    function ParentId(I: Integer): string;
    function SubtreeEnd(I: Integer): Integer;
    function HasChildren(I: Integer): Boolean;
    function IsSummary(I: Integer): Boolean;
    function ChildIndexes(I: Integer): TPJIntArray;
    function WBS(I: Integer): string;
    function IndexOfWBS(const Code: string): Integer;
    function FormatDur(const D: TAIDuration): string;
    function ParseDur(const S: string; out D: TAIDuration; out Err: string): Boolean;

    { --- comandos (cada um e um passo de desfazer) --- }
    function NewTaskId(AKind: TPJTaskKind): string;
    function InsertTask(AtIndex: Integer; AKind: TPJTaskKind; const AName, AShort: string): TPJTask;
    function AddTask(const AParentId: string; AKind: TPJTaskKind; const AName, AShort: string): TPJTask;
    function DeleteTask(const AId: string): Boolean;
    function Indent(const AId: string): Boolean;
    function Outdent(const AId: string): Boolean;
    function MoveUp(const AId: string): Boolean;
    function MoveDown(const AId: string): Boolean;
    function SetKind(const AId: string; AKind: TPJTaskKind): Boolean;
    function SetDurationText(const AId, AText: string; out Err: string): Boolean;

    { --- vinculos (PJ-G01..G07) --- }
    function IndexOfLink(const AFromId, AToId: string): Integer;
    function AddLink(const AFromId, AToId: string; AType: TAITaskLinkType;
      const ALag: TAITaskLag; AArtifact: Boolean; out Err: string): Boolean;
    function UpdateLink(const AFromId, AToId: string; AType: TAITaskLinkType;
      const ALag: TAITaskLag; AArtifact: Boolean; out Err: string): Boolean;
    function RemoveLink(const AFromId, AToId: string): Boolean;
    { vincula a selecao em cadeia TI (Ctrl+F2 do Project) }
    function LinkChain(const AIds: array of string; out Err: string): Boolean;
    function PredecessorsText(const ATaskId: string): string;
    function SuccessorsText(const ATaskId: string): string;
    function SetPredecessorsText(const ATaskId, AText: string; out Err: string): Boolean;
    function CheckLinks(out Err: string): Boolean;

    { --- calendarios (PJ-C01..C05) --- }
    function FindCalendar(const AName: string): TAIWorkCalendar;
    function IndexOfCalendar(const AName: string): Integer;
    function ProjectCalendar: TAIWorkCalendar;
    function AddCalendar(const AName: string; ATemplate: TAIWorkCalendar = nil): TAIWorkCalendar;
    procedure ResetCalendars;
    procedure AdoptCalendars(AList: TFPObjectList);

    { edicao livre de campos: BeginChange antes, EndChange depois }
    procedure BeginChange(const Desc: string);
    procedure EndChange;
    function Undo: Boolean;
    function Redo: Boolean;
    function CanUndo: Boolean;
    function CanRedo: Boolean;
    function UndoDescription: string;
    function RedoDescription: string;
    procedure ClearHistory;

    { --- validacao (PJ-T10, PJ-T13, PJ-T15) --- }
    function Validate: TPJIssues;
    function CheckOutline(out Msg: string): Boolean;

    { usado pelo leitor do arquivo (multiproject_json) }
    procedure AdoptTasks(AList: TFPObjectList);
    procedure AdoptLinks(AList: TFPObjectList);
    procedure MarkSaved;

    property Count: Integer read GetCount;
    property Tasks[I: Integer]: TPJTask read GetTask; default;
    property CalendarCount: Integer read GetCalendarCount;
    property Calendars[I: Integer]: TAIWorkCalendar read GetCalendar;
    property LinkCount: Integer read GetLinkCount;
    property Links[I: Integer]: TPJLink read GetLink;
    { motivo da ultima recusa de Indent/Outdent }
    property LastError: string read FLastError;
    property Modified: Boolean read FModified write FModified;
  end;

implementation

uses
  multiproject_json, multiproject_graph;

{ ---------------- TPJLink ---------------- }

destructor TPJLink.Destroy;
begin
  Raw.Free;
  inherited Destroy;
end;

{ ---------------- TPJTask ---------------- }

constructor TPJTask.Create;
begin
  inherited Create;
  Kind := tkGeneral;
  Process := prNone;
  State := tsPlanned;
  Mode := smAuto;
  Duration := AIMakeDuration(AI_DEFAULT_MINUTES_PER_DAY, aduDay, False, True);
  Constraint := actASAP;
  Level := 1;
end;

destructor TPJTask.Destroy;
begin
  Raw.Free;
  inherited Destroy;
end;

procedure TPJTask.AddTechItem(const AKey, AValue, AUnit: string);
begin
  SetLength(TechItems, Length(TechItems) + 1);
  TechItems[High(TechItems)].Key := AKey;
  TechItems[High(TechItems)].Value := AValue;
  TechItems[High(TechItems)].UnitName := AUnit;
end;

procedure TPJTask.AddCriterion(const AId, AText: string);
begin
  SetLength(FuncSpec, Length(FuncSpec) + 1);
  FuncSpec[High(FuncSpec)].Id := AId;
  FuncSpec[High(FuncSpec)].Text := AText;
  FuncSpec[High(FuncSpec)].State := csPending;
  FuncSpec[High(FuncSpec)].Evidence := '';
end;

function TPJTask.TechValue(const AKey: string): string;
var I: Integer;
begin
  for I := 0 to High(TechItems) do
    if SameText(TechItems[I].Key, AKey) then Exit(TechItems[I].Value);
  Result := '';
end;

{ ---------------- TPJProject ---------------- }

constructor TPJProject.Create;
begin
  inherited Create;
  FTasks := TFPObjectList.Create(True);
  FLinks := TFPObjectList.Create(True);
  FCalendars := TFPObjectList.Create(True);
  FHistory := TAIUndoHistory.Create(PJ_UNDO_LIMIT);
  Clear;
end;

destructor TPJProject.Destroy;
begin
  FLinks.Free;
  FTasks.Free;
  FCalendars.Free;
  FHistory.Free;
  Raw.Free;
  inherited Destroy;
end;

procedure TPJProject.Clear;
begin
  FLinks.Clear;
  FTasks.Clear;
  FreeAndNil(Raw);
  Id := '';
  Name := '';
  Revision := 'A';
  Author := '';
  ObjectiveShort := '';
  ObjectiveLong := '';
  ObjectiveScope := '';
  ObjectiveSuccess := nil;
  StartDate := Date + EncodeTime(8, 0, 0, 0);
  StatusDate := 0;
  ScheduleFrom := sfStart;
  MinutesPerDay := AI_DEFAULT_MINUTES_PER_DAY;
  MinutesPerWeek := AI_DEFAULT_MINUTES_PER_WEEK;
  NextNumber := 1;
  ProjectCalendarName := PJ_CAL_STANDARD;
  CriticalSlack := 0;
  ResetCalendars;
  ClearHistory;
  FModified := False;
end;

function TPJProject.GetCount: Integer;
begin
  Result := FTasks.Count;
end;

function TPJProject.GetTask(I: Integer): TPJTask;
begin
  Result := TPJTask(FTasks[I]);
end;

procedure TPJProject.RequireIndex(I: Integer);
begin
  if (I < 0) or (I >= Count) then
    raise EPJError.CreateFmt('indice de tarefa invalido: %d', [I]);
end;

function TPJProject.IndexOfId(const AId: string): Integer;
var I: Integer;
begin
  for I := 0 to Count - 1 do
    if SameText(Tasks[I].Id, AId) then Exit(I);
  Result := -1;
end;

function TPJProject.FindTask(const AId: string): TPJTask;
var I: Integer;
begin
  I := IndexOfId(AId);
  if I < 0 then Result := nil else Result := Tasks[I];
end;

function TPJProject.ParentIndex(I: Integer): Integer;
var J: Integer;
begin
  RequireIndex(I);
  for J := I - 1 downto 0 do
    if Tasks[J].Level < Tasks[I].Level then Exit(J);
  Result := -1;
end;

function TPJProject.ParentId(I: Integer): string;
var P: Integer;
begin
  P := ParentIndex(I);
  if P < 0 then Result := '' else Result := Tasks[P].Id;
end;

function TPJProject.SubtreeEnd(I: Integer): Integer;
begin
  RequireIndex(I);
  Result := I;
  while (Result + 1 < Count) and (Tasks[Result + 1].Level > Tasks[I].Level) do
    Inc(Result);
end;

function TPJProject.HasChildren(I: Integer): Boolean;
begin
  RequireIndex(I);
  Result := (I + 1 < Count) and (Tasks[I + 1].Level > Tasks[I].Level);
end;

function TPJProject.IsSummary(I: Integer): Boolean;
begin
  Result := HasChildren(I);
end;

function TPJProject.ChildIndexes(I: Integer): TPJIntArray;
var J, E, L: Integer;
begin
  Result := nil;
  if I < 0 then
  begin
    { filhas do objetivo: nivel 1 }
    for J := 0 to Count - 1 do
      if Tasks[J].Level = 1 then
      begin
        SetLength(Result, Length(Result) + 1);
        Result[High(Result)] := J;
      end;
    Exit;
  end;
  E := SubtreeEnd(I);
  L := Tasks[I].Level + 1;
  for J := I + 1 to E do
    if Tasks[J].Level = L then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := J;
    end;
end;

function TPJProject.WBS(I: Integer): string;
var
  Counters: array of Integer;
  J, K, L: Integer;
begin
  RequireIndex(I);
  Counters := nil;
  for J := 0 to I do
  begin
    L := Tasks[J].Level;
    if Length(Counters) < L then SetLength(Counters, L);
    Inc(Counters[L - 1]);
    for K := L to High(Counters) do Counters[K] := 0;
  end;
  Result := '';
  for K := 0 to Tasks[I].Level - 1 do
  begin
    if K > 0 then Result := Result + '.';
    Result := Result + IntToStr(Counters[K]);
  end;
end;

function TPJProject.IndexOfWBS(const Code: string): Integer;
var I: Integer;
begin
  for I := 0 to Count - 1 do
    if WBS(I) = Code then Exit(I);
  Result := -1;
end;

function TPJProject.FormatDur(const D: TAIDuration): string;
begin
  Result := AIFormatDuration(D, MinutesPerDay, MinutesPerWeek);
end;

function TPJProject.ParseDur(const S: string; out D: TAIDuration; out Err: string): Boolean;
begin
  Result := AITryParseDuration(S, MinutesPerDay, MinutesPerWeek, D, Err);
end;

{ ---------------- historico ---------------- }

function TPJProject.SnapshotText: string;
begin
  Result := ProjectToJSONText(Self);
end;

procedure TPJProject.RestoreSnapshot(const Snap: string);
var Keep: Boolean; HighWater: Integer;
begin
  { a leitura recria o documento; o historico fica intacto e nao grava fotos.
    O contador de IDs nunca volta: um ID desfeito pode ja ter dado nome a um
    arquivo (T-0008_peca.mcad) e nao pode ser entregue a outra tarefa. }
  FHistory.Suspend;
  Keep := FModified;
  HighWater := NextNumber;
  try
    ProjectFromJSONText(Self, Snap);
  finally
    FHistory.Resume;
    FModified := Keep;
    if NextNumber < HighWater then NextNumber := HighWater;
  end;
end;

procedure TPJProject.BeginChange(const Desc: string);
begin
  FHistory.BeginChange(Desc, SnapshotText);
end;

procedure TPJProject.EndChange;
begin
  if FHistory.EndChange then FModified := True;
end;

function TPJProject.CanUndo: Boolean;
begin
  Result := FHistory.CanUndo;
end;

function TPJProject.CanRedo: Boolean;
begin
  Result := FHistory.CanRedo;
end;

function TPJProject.UndoDescription: string;
begin
  Result := FHistory.UndoDescription;
end;

function TPJProject.RedoDescription: string;
begin
  Result := FHistory.RedoDescription;
end;

function TPJProject.Undo: Boolean;
begin
  Result := CanUndo;
  if not Result then Exit;
  RestoreSnapshot(FHistory.Undo(SnapshotText));
  FModified := True;
end;

function TPJProject.Redo: Boolean;
begin
  Result := CanRedo;
  if not Result then Exit;
  RestoreSnapshot(FHistory.Redo(SnapshotText));
  FModified := True;
end;

procedure TPJProject.ClearHistory;
begin
  FHistory.Clear;
end;

procedure TPJProject.MarkSaved;
begin
  FModified := False;
end;

{ ---------------- comandos ---------------- }

function TPJProject.NewTaskId(AKind: TPJTaskKind): string;
var Prefix: string;
begin
  if AKind = tkMilestone then Prefix := 'M-' else Prefix := 'T-';
  { o contador nunca volta: excluir uma tarefa nao libera o numero }
  repeat
    Result := Prefix + Format('%.4d', [NextNumber]);
    Inc(NextNumber);
  until (IndexOfId('T-' + Copy(Result, 3, MaxInt)) < 0) and
        (IndexOfId('M-' + Copy(Result, 3, MaxInt)) < 0);
end;

function TPJProject.InsertTask(AtIndex: Integer; AKind: TPJTaskKind;
  const AName, AShort: string): TPJTask;
begin
  if (AtIndex < 0) or (AtIndex > Count) then
    raise EPJError.CreateFmt('posicao de insercao invalida: %d', [AtIndex]);
  BeginChange('Inserir tarefa');
  try
    Result := TPJTask.Create;
    Result.Id := NewTaskId(AKind);
    Result.Name := AName;
    Result.ShortDesc := AShort;
    Result.Kind := AKind;
    if AKind = tkMilestone then Result.Duration := AIMakeDuration(0, aduDay);
    { como no Project: a nova linha fica no nivel da linha onde entra }
    if AtIndex < Count then Result.Level := Tasks[AtIndex].Level
    else if Count > 0 then Result.Level := Tasks[Count - 1].Level
    else Result.Level := 1;
    FTasks.Insert(AtIndex, Result);
  finally
    EndChange;
  end;
end;

function TPJProject.AddTask(const AParentId: string; AKind: TPJTaskKind;
  const AName, AShort: string): TPJTask;
var P, At: Integer;
begin
  if AParentId = '' then
  begin
    Result := InsertTask(Count, AKind, AName, AShort);
    Result.Level := 1;
    Exit;
  end;
  P := IndexOfId(AParentId);
  if P < 0 then
    raise EPJError.CreateFmt('tarefa pai inexistente: %s', [AParentId]);
  At := SubtreeEnd(P) + 1;
  BeginChange('Inserir tarefa');
  try
    Result := InsertTask(At, AKind, AName, AShort);
    Result.Level := Tasks[P].Level + 1;
  finally
    EndChange;
  end;
end;

function TPJProject.DeleteTask(const AId: string): Boolean;
var I, E, J, A, B: Integer;
begin
  I := IndexOfId(AId);
  Result := I >= 0;
  if not Result then Exit;
  E := SubtreeEnd(I);
  BeginChange('Excluir tarefa');
  try
    { os vinculos das tarefas excluidas saem junto }
    for J := FLinks.Count - 1 downto 0 do
    begin
      A := IndexOfId(Links[J].FromId);
      B := IndexOfId(Links[J].ToId);
      if ((A >= I) and (A <= E)) or ((B >= I) and (B <= E)) then FLinks.Delete(J);
    end;
    for J := E downto I do FTasks.Delete(J);
  finally
    EndChange;
  end;
end;

function TPJProject.Indent(const AId: string): Boolean;
var I, E, J: Integer;
begin
  I := IndexOfId(AId);
  { so recua se a anterior estiver no mesmo nivel ou mais funda:
    a tarefa vira filha da irma anterior }
  FLastError := '';
  Result := (I > 0) and (Tasks[I].Level <= Tasks[I - 1].Level);
  if not Result then Exit;
  E := SubtreeEnd(I);
  { a nova hierarquia muda os vinculos expandidos dos resumos: confere antes }
  Result := LevelsKeepGraph(I, E, +1, FLastError);
  if not Result then Exit;
  BeginChange('Recuar tarefa');
  try
    for J := I to E do Inc(Tasks[J].Level);
  finally
    EndChange;
  end;
end;

function TPJProject.Outdent(const AId: string): Boolean;
var I, E, J: Integer;
begin
  I := IndexOfId(AId);
  FLastError := '';
  Result := (I >= 0) and (Tasks[I].Level > 1);
  if not Result then Exit;
  E := SubtreeEnd(I);
  Result := LevelsKeepGraph(I, E, -1, FLastError);
  if not Result then Exit;
  BeginChange('Avancar tarefa');
  try
    { como no Project: a subarvore sobe um nivel; as irmas seguintes passam a
      ser filhas da tarefa avancada }
    for J := I to E do Dec(Tasks[J].Level);
  finally
    EndChange;
  end;
end;

function TPJProject.MoveUp(const AId: string): Boolean;
var I, E, P, J, N: Integer;
begin
  I := IndexOfId(AId);
  Result := False;
  if I <= 0 then Exit;
  { irma anterior: primeira tarefa acima com o mesmo nivel, sem passar pelo pai }
  P := -1;
  for J := I - 1 downto 0 do
  begin
    if Tasks[J].Level < Tasks[I].Level then Break;
    if Tasks[J].Level = Tasks[I].Level then begin P := J; Break; end;
  end;
  if P < 0 then Exit;
  E := SubtreeEnd(I);
  N := E - I + 1;
  BeginChange('Mover tarefa');
  try
    { leva o bloco [I..E] para a posicao P, mantendo a ordem interna }
    FTasks.OwnsObjects := False;
    try
      for J := 0 to N - 1 do FTasks.Move(I + J, P + J);
    finally
      FTasks.OwnsObjects := True;
    end;
  finally
    EndChange;
  end;
  Result := True;
end;

function TPJProject.MoveDown(const AId: string): Boolean;
var I, N: Integer;
begin
  I := IndexOfId(AId);
  Result := False;
  if I < 0 then Exit;
  N := SubtreeEnd(I) + 1;
  if (N >= Count) or (Tasks[N].Level <> Tasks[I].Level) then Exit;
  { descer = subir a irma seguinte }
  BeginChange('Mover tarefa');
  try
    Result := MoveUp(Tasks[N].Id);
  finally
    EndChange;
  end;
end;

function TPJProject.SetKind(const AId: string; AKind: TPJTaskKind): Boolean;
var T: TPJTask;
begin
  T := FindTask(AId);
  Result := T <> nil;
  if not Result or (T.Kind = AKind) then Exit;
  BeginChange('Alterar tipo');
  try
    T.Kind := AKind;
    if AKind = tkMilestone then T.Duration := AIMakeDuration(0, aduDay);
  finally
    EndChange;
  end;
end;

function TPJProject.SetDurationText(const AId, AText: string; out Err: string): Boolean;
var T: TPJTask; D: TAIDuration;
begin
  Err := '';
  T := FindTask(AId);
  if T = nil then
  begin
    Err := 'tarefa inexistente: ' + AId;
    Exit(False);
  end;
  Result := ParseDur(AText, D, Err);
  if not Result then Exit;
  if (T.Kind = tkMilestone) and (D.Minutes <> 0) then
  begin
    Err := T.Id + ' e um marco: a duracao deve ser zero';
    Exit(False);
  end;
  BeginChange('Alterar duracao');
  try
    T.Duration := D;
  finally
    EndChange;
  end;
end;

procedure TPJProject.AdoptLinks(AList: TFPObjectList);
var I: Integer;
begin
  FLinks.Clear;
  AList.OwnsObjects := False;
  for I := 0 to AList.Count - 1 do FLinks.Add(AList[I]);
end;

procedure TPJProject.AdoptTasks(AList: TFPObjectList);
var I: Integer;
begin
  FTasks.Clear;
  AList.OwnsObjects := False;
  for I := 0 to AList.Count - 1 do FTasks.Add(AList[I]);
end;

{ ---------------- calendarios ---------------- }

function TPJProject.GetCalendarCount: Integer;
begin
  Result := FCalendars.Count;
end;

function TPJProject.GetCalendar(I: Integer): TAIWorkCalendar;
begin
  Result := TAIWorkCalendar(FCalendars[I]);
end;

function TPJProject.IndexOfCalendar(const AName: string): Integer;
var I: Integer;
begin
  for I := 0 to CalendarCount - 1 do
    if SameText(Calendars[I].Name, AName) then Exit(I);
  Result := -1;
end;

function TPJProject.FindCalendar(const AName: string): TAIWorkCalendar;
var I: Integer;
begin
  I := IndexOfCalendar(AName);
  if I < 0 then Result := nil else Result := Calendars[I];
end;

function TPJProject.ProjectCalendar: TAIWorkCalendar;
begin
  Result := FindCalendar(ProjectCalendarName);
  if Result = nil then Result := FindCalendar(PJ_CAL_STANDARD);
  if Result = nil then
    raise EPJError.CreateFmt('calendario do projeto "%s" inexistente', [ProjectCalendarName]);
end;

function TPJProject.AddCalendar(const AName: string; ATemplate: TAIWorkCalendar): TAIWorkCalendar;
begin
  if Trim(AName) = '' then raise EPJError.Create('calendario sem nome');
  if IndexOfCalendar(AName) >= 0 then
    raise EPJError.CreateFmt('ja existe o calendario "%s"', [AName]);
  BeginChange('Novo calendario');
  try
    Result := TAIWorkCalendar.Create(AName);
    if ATemplate <> nil then
    begin
      Result.Assign(ATemplate);
      Result.Name := AName;
    end;
    FCalendars.Add(Result);
  finally
    EndChange;
  end;
end;

procedure TPJProject.ResetCalendars;
var C: TAIWorkCalendar; Y: Word; M, D: Word;
begin
  { Padrao (seg-sex 08-12/13-17) com feriados nacionais e 24 Horas (maquinas) }
  FCalendars.Clear;
  DecodeDate(StartDate, Y, M, D);
  C := TAIWorkCalendar.Create(PJ_CAL_STANDARD);
  C.SetStandard;
  C.AddBrazilianHolidays(Y - 1, Y + 5);
  FCalendars.Add(C);
  C := TAIWorkCalendar.Create(PJ_CAL_24H);
  C.Set24Hours;
  FCalendars.Add(C);
end;

procedure TPJProject.AdoptCalendars(AList: TFPObjectList);
var I: Integer;
begin
  FCalendars.Clear;
  AList.OwnsObjects := False;
  for I := 0 to AList.Count - 1 do FCalendars.Add(AList[I]);
end;

{ ---------------- vinculos ---------------- }

function TPJProject.GetLinkCount: Integer;
begin
  Result := FLinks.Count;
end;

function TPJProject.GetLink(I: Integer): TPJLink;
begin
  Result := TPJLink(FLinks[I]);
end;

function TPJProject.IdExists(const AId: string): Boolean;
begin
  Result := IndexOfId(Trim(AId)) >= 0;
end;

function TPJProject.IndexOfLink(const AFromId, AToId: string): Integer;
var I: Integer;
begin
  for I := 0 to LinkCount - 1 do
    if SameText(Links[I].FromId, AFromId) and SameText(Links[I].ToId, AToId) then Exit(I);
  Result := -1;
end;

function TPJProject.CheckLinks(out Err: string): Boolean;
var G: TAITaskGraph;
begin
  G := BuildTaskGraph(Self, Err);
  Result := G <> nil;
  G.Free;
end;

function TPJProject.LevelsKeepGraph(AFirst, ALast, ADelta: Integer; out Err: string): Boolean;
var J: Integer;
begin
  Err := '';
  if LinkCount = 0 then Exit(True);
  for J := AFirst to ALast do Inc(Tasks[J].Level, ADelta);
  try
    Result := CheckLinks(Err);
  finally
    for J := AFirst to ALast do Dec(Tasks[J].Level, ADelta);
  end;
  if not Result then Err := 'a mudanca de nivel deixaria um vinculo invalido: ' + Err;
end;

function TPJProject.AddLink(const AFromId, AToId: string; AType: TAITaskLinkType;
  const ALag: TAITaskLag; AArtifact: Boolean; out Err: string): Boolean;
var L: TPJLink;
begin
  Err := '';
  Result := False;
  if not IdExists(AFromId) then begin Err := 'tarefa inexistente: ' + AFromId; Exit; end;
  if not IdExists(AToId) then begin Err := 'tarefa inexistente: ' + AToId; Exit; end;
  if SameText(AFromId, AToId) then
  begin
    Err := Format('%s nao pode depender de si mesma', [AFromId]);
    Exit;
  end;
  if IndexOfLink(AFromId, AToId) >= 0 then
  begin
    Err := Format('ja existe vinculo de %s para %s', [AFromId, AToId]);
    Exit;
  end;
  L := TPJLink.Create;
  L.FromId := FindTask(AFromId).Id;
  L.ToId := FindTask(AToId).Id;
  L.LinkType := AType;
  L.Lag := ALag;
  L.Artifact := AArtifact;
  { experimenta no grafo antes de entrar no historico }
  FLinks.Add(L);
  if not CheckLinks(Err) then
  begin
    FLinks.Delete(FLinks.Count - 1);
    Exit;
  end;
  FLinks.OwnsObjects := False;
  FLinks.Delete(FLinks.Count - 1);
  FLinks.OwnsObjects := True;
  BeginChange('Vincular tarefas');
  try
    FLinks.Add(L);
  finally
    EndChange;
  end;
  Result := True;
end;

function TPJProject.UpdateLink(const AFromId, AToId: string; AType: TAITaskLinkType;
  const ALag: TAITaskLag; AArtifact: Boolean; out Err: string): Boolean;
var I: Integer; L: TPJLink;
begin
  Err := '';
  I := IndexOfLink(AFromId, AToId);
  if I < 0 then
  begin
    Err := Format('nao ha vinculo de %s para %s', [AFromId, AToId]);
    Exit(False);
  end;
  L := Links[I];
  if (L.LinkType = AType) and AISameLag(L.Lag, ALag) and (L.Artifact = AArtifact) then Exit(True);
  { tipo e latencia nao mudam a estrutura do grafo: nao ha ciclo novo }
  BeginChange('Alterar vinculo');
  try
    L.LinkType := AType;
    L.Lag := ALag;
    L.Artifact := AArtifact;
  finally
    EndChange;
  end;
  Result := True;
end;

function TPJProject.RemoveLink(const AFromId, AToId: string): Boolean;
var I: Integer;
begin
  I := IndexOfLink(AFromId, AToId);
  Result := I >= 0;
  if not Result then Exit;
  BeginChange('Desvincular tarefas');
  try
    FLinks.Delete(I);
  finally
    EndChange;
  end;
end;

function TPJProject.LinkChain(const AIds: array of string; out Err: string): Boolean;
var I: Integer; Keep: Integer;
begin
  Err := '';
  Result := True;
  if Length(AIds) < 2 then Exit;
  Keep := FLinks.Count;
  BeginChange('Vincular tarefas');
  try
    for I := 1 to High(AIds) do
      if IndexOfLink(AIds[I - 1], AIds[I]) < 0 then
        if not AddLink(AIds[I - 1], AIds[I], atlFS, AINoLag, False, Err) then
        begin
          { desfaz os vinculos que ja entraram nesta cadeia }
          while FLinks.Count > Keep do FLinks.Delete(FLinks.Count - 1);
          Result := False;
          Break;
        end;
  finally
    EndChange;
  end;
end;

function TPJProject.PredecessorsText(const ATaskId: string): string;
var I: Integer; Item: TAIPredecessorItem;
begin
  Result := '';
  for I := 0 to LinkCount - 1 do
    if SameText(Links[I].ToId, ATaskId) then
    begin
      Item.Id := Links[I].FromId;
      Item.LinkType := Links[I].LinkType;
      Item.Lag := Links[I].Lag;
      if Result <> '' then Result := Result + ';';
      Result := Result + AIFormatPredecessor(Item, MinutesPerDay, MinutesPerWeek);
    end;
end;

function TPJProject.SuccessorsText(const ATaskId: string): string;
var I: Integer; Item: TAIPredecessorItem;
begin
  Result := '';
  for I := 0 to LinkCount - 1 do
    if SameText(Links[I].FromId, ATaskId) then
    begin
      Item.Id := Links[I].ToId;
      Item.LinkType := Links[I].LinkType;
      Item.Lag := Links[I].Lag;
      if Result <> '' then Result := Result + ';';
      Result := Result + AIFormatPredecessor(Item, MinutesPerDay, MinutesPerWeek);
    end;
end;

function TPJProject.SetPredecessorsText(const ATaskId, AText: string; out Err: string): Boolean;
var
  Items: TAIPredecessorItems;
  T: TPJTask;
  Old, New_: TFPObjectList;
  I, J: Integer;
  L, Prev: TPJLink;
begin
  Result := False;
  T := FindTask(ATaskId);
  if T = nil then begin Err := 'tarefa inexistente: ' + ATaskId; Exit; end;
  if not AITryParsePredecessors(AText, MinutesPerDay, MinutesPerWeek, @IdExists, Items, Err) then
  begin
    Err := T.Id + ': ' + Err;
    Exit;
  end;
  for I := 0 to High(Items) do
    if SameText(Items[I].Id, T.Id) then
    begin
      Err := Format('%s nao pode depender de si mesma', [T.Id]);
      Exit;
    end;
  { monta a lista nova: vinculos de outras tarefas + as predecessoras digitadas,
    mantendo "entrega artefato" e campos desconhecidos dos vinculos que ja existiam }
  Old := FLinks;
  New_ := TFPObjectList.Create(True);
  try
    for I := 0 to Old.Count - 1 do
      if not SameText(TPJLink(Old[I]).ToId, T.Id) then
      begin
        L := TPJLink.Create;
        Prev := TPJLink(Old[I]);
        L.FromId := Prev.FromId; L.ToId := Prev.ToId; L.LinkType := Prev.LinkType;
        L.Lag := Prev.Lag; L.Artifact := Prev.Artifact;
        if Prev.Raw <> nil then L.Raw := TJSONObject(Prev.Raw.Clone);
        New_.Add(L);
      end;
    for I := 0 to High(Items) do
    begin
      L := TPJLink.Create;
      L.FromId := FindTask(Items[I].Id).Id;
      L.ToId := T.Id;
      L.LinkType := Items[I].LinkType;
      L.Lag := Items[I].Lag;
      J := IndexOfLink(L.FromId, T.Id);
      if J >= 0 then
      begin
        L.Artifact := Links[J].Artifact;
        if Links[J].Raw <> nil then L.Raw := TJSONObject(Links[J].Raw.Clone);
      end;
      New_.Add(L);
    end;
    FLinks := New_;
    try
      Result := CheckLinks(Err);
    finally
      FLinks := Old;
    end;
    if not Result then Exit;
    BeginChange('Alterar predecessoras');
    try
      FLinks.Clear;
      New_.OwnsObjects := False;
      for I := 0 to New_.Count - 1 do FLinks.Add(New_[I]);
    finally
      EndChange;
    end;
  finally
    New_.Free;
  end;
end;

{ ---------------- validacao ---------------- }

function TPJProject.CheckOutline(out Msg: string): Boolean;
var I: Integer;
begin
  Msg := '';
  for I := 0 to Count - 1 do
  begin
    if (I = 0) and (Tasks[I].Level <> 1) then
    begin
      Msg := Format('%s: a primeira tarefa deve estar no nivel 1', [Tasks[I].Id]);
      Exit(False);
    end;
    if Tasks[I].Level < 1 then
    begin
      Msg := Format('%s: nivel invalido %d', [Tasks[I].Id, Tasks[I].Level]);
      Exit(False);
    end;
    if (I > 0) and (Tasks[I].Level > Tasks[I - 1].Level + 1) then
    begin
      Msg := Format('%s: nivel %d depois de %s no nivel %d',
        [Tasks[I].Id, Tasks[I].Level, Tasks[I - 1].Id, Tasks[I - 1].Level]);
      Exit(False);
    end;
  end;
  Result := True;
end;

function TPJProject.Validate: TPJIssues;
var
  I, J: Integer;
  T: TPJTask;
  Msg: string;
  Ids: TStringList;
begin
  Result := nil;
  if IndexOfCalendar(ProjectCalendarName) < 0 then
    AddIssue(Result, '', svError, Format('calendario do projeto "%s" inexistente', [ProjectCalendarName]));
  if Trim(ObjectiveShort) = '' then
    AddIssue(Result, '', svWarning, 'o objetivo nao tem descricao curta');
  if not CheckOutline(Msg) then
    AddIssue(Result, '', svError, 'estrutura de topicos invalida: ' + Msg);
  Ids := TStringList.Create;
  try
    Ids.Sorted := True;
    Ids.CaseSensitive := False;
    for I := 0 to Count - 1 do
    begin
      T := Tasks[I];
      if Trim(T.Id) = '' then
        AddIssue(Result, '', svError, Format('linha %d sem ID', [I + 1]))
      else if Ids.IndexOf(T.Id) >= 0 then
        AddIssue(Result, T.Id, svError, 'ID repetido: ' + T.Id)
      else
        Ids.Add(T.Id);
      if Trim(T.Name) = '' then
        AddIssue(Result, T.Id, svError, T.Id + ': a tarefa precisa de um nome');
      if Trim(T.ShortDesc) = '' then
        AddIssue(Result, T.Id, svError, T.Id + ': a tarefa precisa de uma descricao curta');
      if (T.Kind = tkMilestone) and (T.Duration.Minutes <> 0) then
        AddIssue(Result, T.Id, svError, T.Id + ': marco com duracao diferente de zero');
      if T.Duration.Minutes < 0 then
        AddIssue(Result, T.Id, svError, T.Id + ': duracao negativa');
      if HasChildren(I) and not (T.Kind in [tkSummary, tkGeneral]) then
        AddIssue(Result, T.Id, svWarning, Format('%s tem subtarefas e tipo "%s"; tarefas com subtarefas sao resumos',
          [T.Id, KindCaption(T.Kind)]))
      else if (T.Kind = tkSummary) and not HasChildren(I) then
        AddIssue(Result, T.Id, svWarning, T.Id + ': resumo sem subtarefas');
      if (T.CalendarName <> '') and (IndexOfCalendar(T.CalendarName) < 0) then
        AddIssue(Result, T.Id, svError, Format('%s usa o calendario inexistente "%s"', [T.Id, T.CalendarName]));
      if (T.Constraint in [actSNET, actSNLT, actFNET, actFNLT, actMSO, actMFO]) and (T.ConstraintDate = 0) then
        AddIssue(Result, T.Id, svError, Format('%s: restricao %s sem data', [T.Id, AIConstraintCode(T.Constraint)]));
      if (T.Mode = smManual) and (T.ManualStart = 0) then
        AddIssue(Result, T.Id, svWarning, T.Id + ': tarefa manual sem data de inicio');
      if (T.Kind = tkPart) and (T.Process = prNone) then
        AddIssue(Result, T.Id, svWarning, T.Id + ': peca sem processo de fabricacao definido');
      for J := 0 to High(T.FuncSpec) do
        if Trim(T.FuncSpec[J].Text) = '' then
          AddIssue(Result, T.Id, svWarning, Format('%s: criterio de aceite %d vazio', [T.Id, J + 1]));
    end;
  finally
    Ids.Free;
  end;
  if not CheckLinks(Msg) then
    AddIssue(Result, '', svError, 'vinculos invalidos: ' + Msg);
end;

end.
