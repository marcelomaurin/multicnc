unit multiproject_states;

{ Estados da tarefa e transicoes (PJ-L06, parte da fase 4 usada pelo Quadro).

  Regras desta fase:
  - Concluida exige: predecessoras TI (de inicio ou termino) concluidas ou
    canceladas; criterios de aceite aprovados ou dispensados.
  - Em andamento exige predecessoras TI concluidas (II nao bloqueia).
  - Resumo nao muda de estado pelo quadro (o estado vem das filhas).
  Pronta para revisao e concluida exigem artefato valido nos tipos que o usam.
  Cada recusa diz a tarefa e o motivo. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, aitaskgraph, multiproject_types, multiproject_document;

function CanSetState(P: TPJProject; const ATaskId: string; ANew: TPJTaskState;
  out Reason: string): Boolean;
function SetTaskState(P: TPJProject; const ATaskId: string; ANew: TPJTaskState;
  out Reason: string): Boolean;

implementation

uses multiproject_kinds;

function OpenFSPredecessors(P: TPJProject; const ATaskId: string): string;
var I: Integer; L: TPJLink; T: TPJTask;
begin
  Result := '';
  for I := 0 to P.LinkCount - 1 do
  begin
    L := P.Links[I];
    if not SameText(L.ToId, ATaskId) or (L.LinkType <> atlFS) then Continue;
    T := P.FindTask(L.FromId);
    if (T <> nil) and not (T.State in [tsDone, tsCancelled]) then
    begin
      if Result <> '' then Result := Result + ', ';
      Result := Result + T.Id;
    end;
  end;
end;

function CanSetState(P: TPJProject; const ATaskId: string; ANew: TPJTaskState;
  out Reason: string): Boolean;
var T: TPJTask; I: Integer; Open: string;
begin
  Reason := '';
  T := P.FindTask(ATaskId);
  if T = nil then
  begin
    Reason := 'tarefa inexistente: ' + ATaskId;
    Exit(False);
  end;

  if (T.State = ANew) and P.HasChildren(P.IndexOfId(T.Id)) then Exit(True);
  if P.HasChildren(P.IndexOfId(T.Id)) then
  begin
    Reason := T.Id + ' e um resumo: o estado vem das subtarefas';
    Exit(False);
  end;
  if ANew in [tsInProgress, tsDone] then
  begin
    Open := OpenFSPredecessors(P, T.Id);
    if Open <> '' then
    begin
      Reason := Format('%s espera a conclusao de %s', [T.Id, Open]);
      Exit(False);
    end;
  end;
  if ANew = tsDone then
    for I := 0 to High(T.FuncSpec) do
      if not (T.FuncSpec[I].State in [csPassed, csWaived]) then
      begin
        Reason := Format('%s: criterio de aceite "%s" ainda %s', [T.Id, T.FuncSpec[I].Text,
          CriterionStateName(T.FuncSpec[I].State)]);
        Exit(False);
      end;
  if (ANew in [tsReview, tsDone]) and PJKindInfo(T.Kind).RequiresArtifact and
    ((T.Artifact.Hash = '') or not (T.Artifact.Status = 'valid') and not (T.Artifact.Status = 'ready')) then
  begin
    Reason := T.Id + ': exige artefato valido; ' + T.Artifact.CheckMessage;
    Exit(False);
  end;
  Result := True;
end;

function SetTaskState(P: TPJProject; const ATaskId: string; ANew: TPJTaskState;
  out Reason: string): Boolean;
var T: TPJTask;
begin
  Result := CanSetState(P, ATaskId, ANew, Reason);
  if not Result then Exit;
  T := P.FindTask(ATaskId);
  if T.State = ANew then Exit;
  P.BeginChange('Alterar estado');
  try
    T.State := ANew;
  finally
    P.EndChange;
  end;
end;

end.
