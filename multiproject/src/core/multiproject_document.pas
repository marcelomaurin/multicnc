unit multiproject_document;

{ Documento do MultiProject: objetivo, tarefas em estrutura de topicos (EAP),
  comandos com desfazer/refazer e validacao (fase 1 de multiproject/docs/TAREFA.md).

  Estrutura de topicos como no Microsoft Project: a lista de tarefas e plana,
  em ordem de exibicao, e cada tarefa tem um nivel (1 = filha do objetivo).
  O pai de uma tarefa e a tarefa anterior mais proxima com nivel - 1.
  Invariante: Level[0] = 1 e Level[i] <= Level[i-1] + 1.

  O codigo EAP e calculado (nunca gravado). O ID e estavel e nunca reaproveitado
  (PJ-T10): T-0001 para tarefas, M-0001 para marcos, mesmo contador.

  Desfazer/refazer (PJ-U01): cada alteracao guarda uma foto do documento em JSON
  antes de mudar. BeginChange/EndChange aninhados viram um unico passo. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Contnrs, fpjson, aiprojectduration, aiundohistory, multiproject_types;

const
  PJ_UNDO_LIMIT = 100;

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

  TPJProject = class
  private
    FTasks: TFPObjectList;
    FHistory: TAIUndoHistory;
    FModified: Boolean;
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
    procedure MarkSaved;

    property Count: Integer read GetCount;
    property Tasks[I: Integer]: TPJTask read GetTask; default;
    property Modified: Boolean read FModified write FModified;
  end;

implementation

uses
  multiproject_json;

{ ---------------- TPJTask ---------------- }

constructor TPJTask.Create;
begin
  inherited Create;
  Kind := tkGeneral;
  Process := prNone;
  State := tsPlanned;
  Mode := smAuto;
  Duration := AIMakeDuration(AI_DEFAULT_MINUTES_PER_DAY, aduDay, False, True);
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
  FHistory := TAIUndoHistory.Create(PJ_UNDO_LIMIT);
  Clear;
end;

destructor TPJProject.Destroy;
begin
  FTasks.Free;
  FHistory.Free;
  Raw.Free;
  inherited Destroy;
end;

procedure TPJProject.Clear;
begin
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
var I, E, J: Integer;
begin
  I := IndexOfId(AId);
  Result := I >= 0;
  if not Result then Exit;
  E := SubtreeEnd(I);
  BeginChange('Excluir tarefa');
  try
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
  Result := (I > 0) and (Tasks[I].Level <= Tasks[I - 1].Level);
  if not Result then Exit;
  E := SubtreeEnd(I);
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
  Result := (I >= 0) and (Tasks[I].Level > 1);
  if not Result then Exit;
  E := SubtreeEnd(I);
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

procedure TPJProject.AdoptTasks(AList: TFPObjectList);
var I: Integer;
begin
  FTasks.Clear;
  AList.OwnsObjects := False;
  for I := 0 to AList.Count - 1 do FTasks.Add(AList[I]);
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
      if (T.Kind = tkPart) and (T.Process = prNone) then
        AddIssue(Result, T.Id, svWarning, T.Id + ': peca sem processo de fabricacao definido');
      for J := 0 to High(T.FuncSpec) do
        if Trim(T.FuncSpec[J].Text) = '' then
          AddIssue(Result, T.Id, svWarning, Format('%s: criterio de aceite %d vazio', [T.Id, J + 1]));
    end;
  finally
    Ids.Free;
  end;
end;

end.
