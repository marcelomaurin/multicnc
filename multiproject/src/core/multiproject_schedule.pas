unit multiproject_schedule;

{ Cronograma do MultiProject (fase 3, PJ-S01..S10, PJ-C01..C05).

  Adaptador do documento para o TAICPMScheduler (CHATGPT / AI Project Core):
  - grafo expandido do multiproject_graph (vinculos de resumo -> folhas);
  - calendarios do projeto (TAIWorkCalendar) e calendario de cada tarefa;
  - duracao, decorrida, restricao, data limite e modo manual de cada tarefa;
  - resumos consolidados pelo pai na estrutura de topicos.

  O resultado (datas, margens, critico) nao e gravado no .mproj: e
  recalculado ao abrir e a cada alteracao (PJ-S11). Os avisos viram
  TPJIssues com o ID da tarefa (PJ-S10). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, aitaskgraph, aiworkcalendar, aicpmscheduler,
  multiproject_types, multiproject_document;

type
  TPJSchedule = class
  private
    FProject: TPJProject;
    FResults: array of TAICPMResult;
    FIssues: TPJIssues;
    FStart, FFinish: TDateTime;
    FValid: Boolean;
    FError: string;
    function GetResult(I: Integer): TAICPMResult;
  public
    constructor Create(AProject: TPJProject);
    { False e Error preenchido quando o documento nao permite calcular
      (vinculo invalido, calendario sem expediente...) }
    function Compute: Boolean;
    function Count: Integer;
    function IndexOf(const ATaskId: string): Integer;
    function StartOf(const ATaskId: string): TDateTime;
    function FinishOf(const ATaskId: string): TDateTime;
    function CriticalIds: string;
    function CriticalCount: Integer;
    property Results[I: Integer]: TAICPMResult read GetResult; default;
    property Issues: TPJIssues read FIssues;
    property ProjectStart: TDateTime read FStart;
    property ProjectFinish: TDateTime read FFinish;
    property Valid: Boolean read FValid;
    property Error: string read FError;
  end;

implementation

uses
  multiproject_graph;

constructor TPJSchedule.Create(AProject: TPJProject);
begin
  inherited Create;
  FProject := AProject;
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

function TPJSchedule.Compute: Boolean;
var
  G: TAITaskGraph;
  Sc: TAICPMScheduler;
  I: Integer;
  T: TPJTask;
  C: TAICPMTask;
  W: TAICPMWarning;
begin
  FValid := False;
  FError := '';
  FIssues := nil;
  FResults := nil;
  G := BuildTaskGraph(FProject, FError);
  if G = nil then Exit(False);
  Sc := TAICPMScheduler.Create;
  try
    try
      Sc.ProjectCalendar := FProject.ProjectCalendar;
      for I := 0 to FProject.CalendarCount - 1 do Sc.AddCalendar(FProject.Calendars[I]);
      Sc.Graph := G;
      Sc.ProjectStart := FProject.StartDate;
      Sc.CriticalSlack := FProject.CriticalSlack;
      for I := 0 to FProject.Count - 1 do
      begin
        T := FProject[I];
        C := AINewCPMTask(T.Id, T.Duration.Minutes);
        C.IsSummary := FProject.HasChildren(I);
        C.Parent := FProject.ParentIndex(I);
        if not C.IsSummary then
        begin
          C.Elapsed := T.Duration.Elapsed;
          if T.CalendarName <> '' then
          begin
            C.Calendar := FProject.IndexOfCalendar(T.CalendarName);
            if C.Calendar < 0 then
            begin
              FError := Format('%s usa o calendario inexistente "%s"', [T.Id, T.CalendarName]);
              Exit(False);
            end;
          end;
          C.Constraint := T.Constraint;
          C.ConstraintDate := T.ConstraintDate;
          C.Deadline := T.Deadline;
          C.Manual := (T.Mode = smManual) and (T.ManualStart > 0);
          C.ManualStart := T.ManualStart;
          C.ManualFinish := T.ManualFinish;
          if (C.Constraint in [actSNET, actSNLT, actFNET, actFNLT, actMSO, actMFO]) and (C.ConstraintDate = 0) then
            C.Constraint := actASAP;   // a validacao ja acusa a restricao sem data
        end
        else
          C.Duration := 0;
        Sc.AddTask(C);
      end;
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
