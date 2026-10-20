unit multiproject_types;

{ Tipos comuns do MultiProject: enums com nome em texto (gravado no .mproj),
  itens da especificacao tecnica, criterios de aceite e diagnosticos.

  Regra: valores novos de enum entram SEMPRE no fim. No arquivo o valor e
  gravado pelo nome (KindName etc.), nunca pelo ordinal. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils;

type
  EPJError = class(Exception);

  TPJTaskKind = (tkSummary, tkMilestone, tkGeneral, tkPurchase, tkPart,
    tkElectronics, tkAssembly, tkValidation, tkPrint3D, tkRouter, tkLaserCut,
    tkLaserArt, tkLathe, tkPCBFab, tkPhysicalAssembly, tkFunctionalTest);

  { processo de fabricacao previsto para uma peca (regra PJ-A01) }
  TPJProcess = (prNone, prPrint3D, prRouter, prLaserCut, prLathe);

  TPJTaskState = (tsSuggested, tsPlanned, tsInProgress, tsReview, tsDone,
    tsBlocked, tsOutdated, tsCancelled);

  TPJScheduleMode = (smAuto, smManual);

  { vinculos: TAITaskLinkType (aitaskgraph, CHATGPT / AI Project Core) }

  { restricoes: TAIConstraintType (aicpmscheduler, CHATGPT / AI Project Core) }

  TPJResourceType = (rtPerson, rtAI, rtMachine, rtMaterial, rtCost);

  TPJCriterionState = (csPending, csPassed, csFailed, csWaived);

  TPJScheduleFrom = (sfStart, sfFinish);

  { item da especificacao tecnica: chave / valor / unidade }
  TPJSpecItem = record
    Key, Value, UnitName: string;
  end;
  TPJSpecItems = array of TPJSpecItem;

  { criterio de aceite da especificacao funcional }
  TPJCriterion = record
    Id, Text: string;
    State: TPJCriterionState;
    Evidence: string;
  end;
  TPJCriteria = array of TPJCriterion;

  TPJIntArray = array of Integer;

  TPJSeverity = (svError, svWarning);

  TPJIssue = record
    TaskId: string;
    Severity: TPJSeverity;
    Message: string;
  end;
  TPJIssues = array of TPJIssue;

function KindName(K: TPJTaskKind): string;
function TryKindFromName(const S: string; out K: TPJTaskKind): Boolean;
function KindCaption(K: TPJTaskKind): string;
function ProcessName(P: TPJProcess): string;
function TryProcessFromName(const S: string; out P: TPJProcess): Boolean;
function StateName(S: TPJTaskState): string;
function TryStateFromName(const S: string; out V: TPJTaskState): Boolean;
function StateCaption(S: TPJTaskState): string;
function ModeName(M: TPJScheduleMode): string;
function TryModeFromName(const S: string; out M: TPJScheduleMode): Boolean;
function ResourceTypeName(R: TPJResourceType): string;
function TryResourceTypeFromName(const S: string; out R: TPJResourceType): Boolean;
function CriterionStateName(C: TPJCriterionState): string;
function TryCriterionStateFromName(const S: string; out C: TPJCriterionState): Boolean;
function ScheduleFromName(S: TPJScheduleFrom): string;
function TryScheduleFromFromName(const S: string; out V: TPJScheduleFrom): Boolean;

procedure AddIssue(var Issues: TPJIssues; const ATaskId: string;
  ASeverity: TPJSeverity; const AMessage: string);
function ErrorCount(const Issues: TPJIssues): Integer;

implementation

const
  KIND_NAMES: array[TPJTaskKind] of string = ('summary', 'milestone', 'general',
    'purchase', 'part', 'electronics', 'assembly', 'validation', 'print3d',
    'router', 'laser_cut', 'laser_art', 'lathe', 'pcb_fab', 'physical_assembly',
    'functional_test');
  KIND_CAPTIONS: array[TPJTaskKind] of string = ('Resumo', 'Marco', 'Geral',
    'Compra', 'Peca mecanica', 'Eletronica', 'Montagem', 'Teste e validacao',
    'Impressao 3D', 'Usinagem CNC Router', 'Corte laser', 'Arte laser',
    'Usinagem de torno', 'Impressao de placa', 'Montagem fisica',
    'Teste funcional');
  PROCESS_NAMES: array[TPJProcess] of string = ('none', 'print3d', 'router',
    'laser_cut', 'lathe');
  STATE_NAMES: array[TPJTaskState] of string = ('suggested', 'planned',
    'in_progress', 'review', 'done', 'blocked', 'outdated', 'cancelled');
  STATE_CAPTIONS: array[TPJTaskState] of string = ('Sugerida', 'Planejada',
    'Em andamento', 'Pronta para revisao', 'Concluida', 'Bloqueada',
    'Desatualizada', 'Cancelada');
  MODE_NAMES: array[TPJScheduleMode] of string = ('auto', 'manual');
  RESOURCE_NAMES: array[TPJResourceType] of string = ('person', 'ai', 'machine',
    'material', 'cost');
  CRITERION_NAMES: array[TPJCriterionState] of string = ('pending', 'passed',
    'failed', 'waived');
  FROM_NAMES: array[TPJScheduleFrom] of string = ('start', 'finish');

function KindName(K: TPJTaskKind): string;
begin
  Result := KIND_NAMES[K];
end;

function TryKindFromName(const S: string; out K: TPJTaskKind): Boolean;
var I: TPJTaskKind;
begin
  for I := Low(I) to High(I) do
    if SameText(S, KIND_NAMES[I]) then begin K := I; Exit(True); end;
  K := tkGeneral;
  Result := False;
end;

function KindCaption(K: TPJTaskKind): string;
begin
  Result := KIND_CAPTIONS[K];
end;

function ProcessName(P: TPJProcess): string;
begin
  Result := PROCESS_NAMES[P];
end;

function TryProcessFromName(const S: string; out P: TPJProcess): Boolean;
var I: TPJProcess;
begin
  for I := Low(I) to High(I) do
    if SameText(S, PROCESS_NAMES[I]) then begin P := I; Exit(True); end;
  P := prNone;
  Result := False;
end;

function StateName(S: TPJTaskState): string;
begin
  Result := STATE_NAMES[S];
end;

function TryStateFromName(const S: string; out V: TPJTaskState): Boolean;
var I: TPJTaskState;
begin
  for I := Low(I) to High(I) do
    if SameText(S, STATE_NAMES[I]) then begin V := I; Exit(True); end;
  V := tsPlanned;
  Result := False;
end;

function StateCaption(S: TPJTaskState): string;
begin
  Result := STATE_CAPTIONS[S];
end;

function ModeName(M: TPJScheduleMode): string;
begin
  Result := MODE_NAMES[M];
end;

function TryModeFromName(const S: string; out M: TPJScheduleMode): Boolean;
var I: TPJScheduleMode;
begin
  for I := Low(I) to High(I) do
    if SameText(S, MODE_NAMES[I]) then begin M := I; Exit(True); end;
  M := smAuto;
  Result := False;
end;

function ResourceTypeName(R: TPJResourceType): string;
begin
  Result := RESOURCE_NAMES[R];
end;

function TryResourceTypeFromName(const S: string; out R: TPJResourceType): Boolean;
var I: TPJResourceType;
begin
  for I := Low(I) to High(I) do
    if SameText(S, RESOURCE_NAMES[I]) then begin R := I; Exit(True); end;
  R := rtPerson;
  Result := False;
end;

function CriterionStateName(C: TPJCriterionState): string;
begin
  Result := CRITERION_NAMES[C];
end;

function TryCriterionStateFromName(const S: string; out C: TPJCriterionState): Boolean;
var I: TPJCriterionState;
begin
  for I := Low(I) to High(I) do
    if SameText(S, CRITERION_NAMES[I]) then begin C := I; Exit(True); end;
  C := csPending;
  Result := False;
end;

function ScheduleFromName(S: TPJScheduleFrom): string;
begin
  Result := FROM_NAMES[S];
end;

function TryScheduleFromFromName(const S: string; out V: TPJScheduleFrom): Boolean;
var I: TPJScheduleFrom;
begin
  for I := Low(I) to High(I) do
    if SameText(S, FROM_NAMES[I]) then begin V := I; Exit(True); end;
  V := sfStart;
  Result := False;
end;

procedure AddIssue(var Issues: TPJIssues; const ATaskId: string;
  ASeverity: TPJSeverity; const AMessage: string);
begin
  SetLength(Issues, Length(Issues) + 1);
  Issues[High(Issues)].TaskId := ATaskId;
  Issues[High(Issues)].Severity := ASeverity;
  Issues[High(Issues)].Message := AMessage;
end;

function ErrorCount(const Issues: TPJIssues): Integer;
var I: Integer;
begin
  Result := 0;
  for I := 0 to High(Issues) do
    if Issues[I].Severity = svError then Inc(Result);
end;

end.
