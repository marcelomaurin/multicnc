unit multiproject_json;

{ Formato .mproj (JSON) do MultiProject (PJ-X01, PJ-Q02, PJ-Q04, D3).

  - "format": "MultiProject", "schema_version": 1.
  - Datas em ISO 8601 local sem fuso; numeros inteiros (minutos); nada depende
    da configuracao regional.
  - Campos que esta versao nao conhece sao preservados: a gravacao parte do
    objeto lido (Raw) e substitui apenas as chaves conhecidas, mantendo a ordem.
    Vale para o projeto, para objetos aninhados (objective, options, tech_spec)
    e para cada tarefa.
  - Versao futura ou arquivo invalido: EPJFormat, sem tocar no documento.
  - Salvamento atomico: grava <arquivo>.tmp, confere a leitura e so entao
    substitui o arquivo.

  Leitura tipada, mescla, datas e gravacao atomica: aijsonutils
  (CHATGPT / AI Project Core). Duracao: aiprojectduration. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpjson, multiproject_types, multiproject_document;

const
  PJ_FORMAT = 'MultiProject';
  PJ_SCHEMA_VERSION = 1;

type
  EPJFormat = class(EPJError);

function ProjectToJSON(P: TPJProject): TJSONObject;
function ProjectToJSONText(P: TPJProject): string;
procedure ProjectFromJSON(P: TPJProject; Obj: TJSONObject);
procedure ProjectFromJSONText(P: TPJProject; const Text: string);
procedure SaveProjectFile(P: TPJProject; const FileName: string);
procedure LoadProjectFile(P: TPJProject; const FileName: string);

implementation

uses
  Contnrs, aijsonutils, aiprojectduration, aitaskgraph, aiworkcalendar, aicpmscheduler,
  multiproject_graph;

{ ---------------- gravacao ---------------- }

function CriteriaToJSON(const C: TPJCriteria): TJSONArray;
var I: Integer; O: TJSONObject;
begin
  Result := TJSONArray.Create;
  for I := 0 to High(C) do
  begin
    O := TJSONObject.Create;
    O.Add('id', C[I].Id);
    O.Add('text', C[I].Text);
    O.Add('state', CriterionStateName(C[I].State));
    O.Add('evidence', C[I].Evidence);
    Result.Add(O);
  end;
end;

function TaskToJSON(P: TPJProject; Index: Integer): TJSONObject;
var
  T: TPJTask;
  O, Spec, It: TJSONObject;
  Items: TJSONArray;
  I: Integer;
begin
  T := P[Index];
  O := TJSONObject.Create;
  O.Add('id', T.Id);
  O.Add('name', T.Name);
  O.Add('short', T.ShortDesc);
  O.Add('long', T.LongDesc);
  O.Add('parent', P.ParentId(Index));
  O.Add('kind', KindName(T.Kind));
  O.Add('process', ProcessName(T.Process));
  O.Add('state', StateName(T.State));
  O.Add('mode', ModeName(T.Mode));
  O.Add('duration', AIJSONInt(T.Duration.Minutes));
  O.Add('duration_unit', AIDurationUnitName(T.Duration.DisplayUnit));
  O.Add('elapsed', T.Duration.Elapsed);
  O.Add('estimated', T.Duration.Estimated);
  Spec := TJSONObject.Create;
  Spec.Add('type', AIConstraintCode(T.Constraint));
  Spec.Add('date', AIDateToISO(T.ConstraintDate));
  O.Add('constraint', Spec);
  O.Add('deadline', AIDateToISO(T.Deadline));
  O.Add('manual_start', AIDateToISO(T.ManualStart));
  O.Add('manual_finish', AIDateToISO(T.ManualFinish));
  O.Add('calendar', T.CalendarName);
  Spec := TJSONObject.Create;
  Items := TJSONArray.Create;
  for I := 0 to High(T.TechItems) do
  begin
    It := TJSONObject.Create;
    It.Add('key', T.TechItems[I].Key);
    It.Add('value', T.TechItems[I].Value);
    It.Add('unit', T.TechItems[I].UnitName);
    Items.Add(It);
  end;
  Spec.Add('items', Items);
  Spec.Add('text', T.TechText);
  O.Add('tech_spec', Spec);
  O.Add('func_spec', CriteriaToJSON(T.FuncSpec));
  O.Add('notes', T.Notes);
  Result := AIJSONMergeKnown(T.Raw, O);
end;

function LinkToJSON(L: TPJLink): TJSONObject;
var O: TJSONObject;
begin
  O := TJSONObject.Create;
  O.Add('from', L.FromId);
  O.Add('to', L.ToId);
  O.Add('type', AILinkTypeCode(L.LinkType, False));
  O.Add('lag', AIJSONInt(L.Lag.Minutes));
  O.Add('lag_unit', AIDurationUnitName(L.Lag.DisplayUnit));
  O.Add('lag_elapsed', L.Lag.Elapsed);
  O.Add('lag_is_percent', L.Lag.IsPercent);
  O.Add('lag_percent', L.Lag.Percent);
  O.Add('artifact', L.Artifact);
  Result := AIJSONMergeKnown(L.Raw, O);
end;

function ProjectToJSON(P: TPJProject): TJSONObject;
var
  O, Obj, Opt: TJSONObject;
  Arr: TJSONArray;
  I: Integer;
begin
  O := TJSONObject.Create;
  O.Add('schema_version', PJ_SCHEMA_VERSION);
  O.Add('format', PJ_FORMAT);
  O.Add('id', P.Id);
  O.Add('name', P.Name);
  O.Add('revision', P.Revision);
  O.Add('author', P.Author);
  Obj := TJSONObject.Create;
  Obj.Add('short', P.ObjectiveShort);
  Obj.Add('long', P.ObjectiveLong);
  Obj.Add('scope', P.ObjectiveScope);
  Obj.Add('success', CriteriaToJSON(P.ObjectiveSuccess));
  O.Add('objective', Obj);
  O.Add('start', AIDateToISO(P.StartDate));
  O.Add('status_date', AIDateToISO(P.StatusDate));
  O.Add('schedule_from', ScheduleFromName(P.ScheduleFrom));
  O.Add('calendar', P.ProjectCalendarName);
  Opt := TJSONObject.Create;
  Opt.Add('minutes_per_day', P.MinutesPerDay);
  Opt.Add('minutes_per_week', P.MinutesPerWeek);
  Opt.Add('critical_slack', AIJSONInt(P.CriticalSlack));
  O.Add('options', Opt);
  Arr := TJSONArray.Create;
  for I := 0 to P.CalendarCount - 1 do Arr.Add(P.Calendars[I].ToJSON);
  O.Add('calendars', Arr);
  O.Add('next_task_number', P.NextNumber);
  Arr := TJSONArray.Create;
  for I := 0 to P.Count - 1 do Arr.Add(TaskToJSON(P, I));
  O.Add('tasks', Arr);
  Arr := TJSONArray.Create;
  for I := 0 to P.LinkCount - 1 do Arr.Add(LinkToJSON(P.Links[I]));
  O.Add('links', Arr);
  Result := AIJSONMergeKnown(P.Raw, O);
end;

function ProjectToJSONText(P: TPJProject): string;
var O: TJSONObject;
begin
  O := ProjectToJSON(P);
  try
    Result := AIJSONFormat(O);
  finally
    O.Free;
  end;
end;

{ ---------------- leitura ---------------- }

function CriteriaFromJSON(A: TJSONArray; const Where: string): TPJCriteria;
var I: Integer; O: TJSONObject; S: string;
begin
  Result := nil;
  if A = nil then Exit;
  SetLength(Result, A.Count);
  for I := 0 to A.Count - 1 do
  begin
    if A.Items[I].JSONType = jtString then
    begin
      { forma curta: lista de textos }
      Result[I].Id := Format('F-%d', [I + 1]);
      Result[I].Text := A.Items[I].AsString;
      Result[I].State := csPending;
      Result[I].Evidence := '';
      Continue;
    end;
    if A.Items[I].JSONType <> jtObject then
      raise EPJFormat.CreateFmt('%s: criterio %d invalido', [Where, I + 1]);
    O := TJSONObject(A.Items[I]);
    Result[I].Id := AIJSONStr(O, 'id', Format('F-%d', [I + 1]));
    Result[I].Text := AIJSONStr(O, 'text');
    S := AIJSONStr(O, 'state', 'pending');
    if not TryCriterionStateFromName(S, Result[I].State) then
      raise EPJFormat.CreateFmt('%s: estado de criterio desconhecido "%s"', [Where, S]);
    Result[I].Evidence := AIJSONStr(O, 'evidence');
  end;
end;

function TaskFromJSON(O: TJSONObject): TPJTask;
var
  S: string;
  Spec, It: TJSONObject;
  Items: TJSONArray;
  I: Integer;
begin
  Result := TPJTask.Create;
  try
    Result.Id := Trim(AIJSONStr(O, 'id'));
    if Result.Id = '' then raise EPJFormat.Create('tarefa sem "id"');
    Result.Name := AIJSONStr(O, 'name');
    Result.ShortDesc := AIJSONStr(O, 'short');
    Result.LongDesc := AIJSONStr(O, 'long');
    S := AIJSONStr(O, 'kind', 'general');
    if not TryKindFromName(S, Result.Kind) then
      raise EPJFormat.CreateFmt('%s: tipo desconhecido "%s"', [Result.Id, S]);
    S := AIJSONStr(O, 'process', 'none');
    if not TryProcessFromName(S, Result.Process) then
      raise EPJFormat.CreateFmt('%s: processo desconhecido "%s"', [Result.Id, S]);
    S := AIJSONStr(O, 'state', 'planned');
    if not TryStateFromName(S, Result.State) then
      raise EPJFormat.CreateFmt('%s: estado desconhecido "%s"', [Result.Id, S]);
    S := AIJSONStr(O, 'mode', 'auto');
    if not TryModeFromName(S, Result.Mode) then
      raise EPJFormat.CreateFmt('%s: modo desconhecido "%s"', [Result.Id, S]);
    Result.Duration.Minutes := AIJSONInt64(O, 'duration', 0);
    if Result.Duration.Minutes < 0 then
      raise EPJFormat.CreateFmt('%s: duracao negativa', [Result.Id]);
    S := AIJSONStr(O, 'duration_unit', 'd');
    if not AITryDurationUnitFromName(S, Result.Duration.DisplayUnit) then
      raise EPJFormat.CreateFmt('%s: unidade de duracao desconhecida "%s"', [Result.Id, S]);
    Result.Duration.Elapsed := AIJSONBool(O, 'elapsed', False);
    Result.Duration.Estimated := AIJSONBool(O, 'estimated', False);
    Spec := AIJSONObj(O, 'constraint');
    if Spec <> nil then
    begin
      S := AIJSONStr(Spec, 'type', 'ASAP');
      if not AITryConstraintFromCode(S, Result.Constraint) then
        raise EPJFormat.CreateFmt('%s: restricao desconhecida "%s"', [Result.Id, S]);
      Result.ConstraintDate := AIJSONDate(Spec, 'date');
    end;
    Result.Deadline := AIJSONDate(O, 'deadline');
    Result.ManualStart := AIJSONDate(O, 'manual_start');
    Result.ManualFinish := AIJSONDate(O, 'manual_finish');
    Result.CalendarName := Trim(AIJSONStr(O, 'calendar'));
    Spec := AIJSONObj(O, 'tech_spec');
    if Spec <> nil then
    begin
      Items := AIJSONArr(Spec, 'items');
      if Items <> nil then
        for I := 0 to Items.Count - 1 do
        begin
          if Items.Items[I].JSONType <> jtObject then
            raise EPJFormat.CreateFmt('%s: item %d da especificacao tecnica invalido', [Result.Id, I + 1]);
          It := TJSONObject(Items.Items[I]);
          Result.AddTechItem(AIJSONStr(It, 'key'), AIJSONStr(It, 'value'), AIJSONStr(It, 'unit'));
        end;
      Result.TechText := AIJSONStr(Spec, 'text');
    end;
    Result.FuncSpec := CriteriaFromJSON(AIJSONArr(O, 'func_spec'), Result.Id);
    Result.Notes := AIJSONStr(O, 'notes');
    Result.Raw := TJSONObject(O.Clone);
  except
    Result.Free;
    raise;
  end;
end;

function LinkFromJSON(O: TJSONObject; Index: Integer): TPJLink;
var S: string;
begin
  Result := TPJLink.Create;
  try
    Result.FromId := Trim(AIJSONStr(O, 'from'));
    Result.ToId := Trim(AIJSONStr(O, 'to'));
    if (Result.FromId = '') or (Result.ToId = '') then
      raise EPJFormat.CreateFmt('vinculo %d sem "from"/"to"', [Index + 1]);
    S := AIJSONStr(O, 'type', 'FS');
    if not AITryLinkTypeFromCode(S, Result.LinkType) then
      raise EPJFormat.CreateFmt('vinculo %s -> %s: tipo desconhecido "%s"', [Result.FromId, Result.ToId, S]);
    Result.Lag := AINoLag;
    Result.Lag.Minutes := AIJSONInt64(O, 'lag', 0);
    S := AIJSONStr(O, 'lag_unit', 'd');
    if not AITryDurationUnitFromName(S, Result.Lag.DisplayUnit) then
      raise EPJFormat.CreateFmt('vinculo %s -> %s: unidade de latencia desconhecida "%s"', [Result.FromId, Result.ToId, S]);
    Result.Lag.Elapsed := AIJSONBool(O, 'lag_elapsed', False);
    Result.Lag.IsPercent := AIJSONBool(O, 'lag_is_percent', False);
    Result.Lag.Percent := AIJSONInt64(O, 'lag_percent', 0);
    Result.Artifact := AIJSONBool(O, 'artifact', False);
    Result.Raw := TJSONObject(O.Clone);
  except
    Result.Free;
    raise;
  end;
end;

procedure ProjectFromJSON(P: TPJProject; Obj: TJSONObject);
var
  Ver: Int64;
  Fmt, S, Par: string;
  ObjO, Opt, TaskObj: TJSONObject;
  Arr: TJSONArray;
  List, LinkList: TFPObjectList;
  G: TAITaskGraph;
  GErr: string;
  Stack, Ids: TStringList;
  I, MaxNum, Num: Integer;
  T: TPJTask;
  { tudo e lido antes de alterar o documento }
  NId, NName, NRev, NAuthor, NShort, NLong, NScope: string;
  NSuccess: TPJCriteria;
  NStart, NStatus: TDateTime;
  NFrom: TPJScheduleFrom;
  NMpd, NMpw, NNext, NCrit: Int64;
  NCalName: string;
  CalList: TFPObjectList;
  Cal: TAIWorkCalendar;
  K: Integer;
begin
  Fmt := AIJSONStr(Obj, 'format');
  if Fmt <> PJ_FORMAT then
    raise EPJFormat.CreateFmt('arquivo nao e do MultiProject (format = "%s")', [Fmt]);
  if Obj.Find('schema_version') = nil then
    raise EPJFormat.Create('arquivo sem "schema_version"');
  Ver := AIJSONInt64(Obj, 'schema_version', 0);
  if Ver > PJ_SCHEMA_VERSION then
    raise EPJFormat.CreateFmt('arquivo da versao %d do formato; esta versao do MultiProject le ate a %d. ' +
      'Atualize o programa; o arquivo nao foi alterado.', [Ver, PJ_SCHEMA_VERSION]);
  if Ver < 1 then
    raise EPJFormat.CreateFmt('schema_version invalido: %d', [Ver]);

  NId := AIJSONStr(Obj, 'id');
  NName := AIJSONStr(Obj, 'name');
  NRev := AIJSONStr(Obj, 'revision', 'A');
  NAuthor := AIJSONStr(Obj, 'author');
  NShort := ''; NLong := ''; NScope := ''; NSuccess := nil;
  ObjO := AIJSONObj(Obj, 'objective');
  if ObjO <> nil then
  begin
    NShort := AIJSONStr(ObjO, 'short');
    NLong := AIJSONStr(ObjO, 'long');
    NScope := AIJSONStr(ObjO, 'scope');
    NSuccess := CriteriaFromJSON(AIJSONArr(ObjO, 'success'), 'objetivo');
  end;
  NStart := AIJSONDate(Obj, 'start');
  NStatus := AIJSONDate(Obj, 'status_date');
  S := AIJSONStr(Obj, 'schedule_from', 'start');
  if not TryScheduleFromFromName(S, NFrom) then
    raise EPJFormat.CreateFmt('schedule_from desconhecido "%s"', [S]);
  NMpd := AI_DEFAULT_MINUTES_PER_DAY;
  NMpw := AI_DEFAULT_MINUTES_PER_WEEK;
  NCrit := 0;
  Opt := AIJSONObj(Obj, 'options');
  if Opt <> nil then
  begin
    NMpd := AIJSONInt64(Opt, 'minutes_per_day', NMpd);
    NMpw := AIJSONInt64(Opt, 'minutes_per_week', NMpw);
    NCrit := AIJSONInt64(Opt, 'critical_slack', 0);
  end;
  NCalName := Trim(AIJSONStr(Obj, 'calendar', PJ_CAL_STANDARD));
  if NCalName = '' then NCalName := PJ_CAL_STANDARD;
  if (NMpd <= 0) or (NMpd > 24 * 60) or (NMpw <= 0) or (NMpw > 7 * 24 * 60) then
    raise EPJFormat.Create('options: minutos por dia/semana fora da faixa');
  NNext := AIJSONInt64(Obj, 'next_task_number', 1);

  List := TFPObjectList.Create(True);
  LinkList := TFPObjectList.Create(True);
  CalList := nil;
  Stack := TStringList.Create;
  Ids := TStringList.Create;
  try
    Ids.Sorted := True;
    Ids.CaseSensitive := False;
    MaxNum := 0;
    Arr := AIJSONArr(Obj, 'tasks');
    if Arr <> nil then
      for I := 0 to Arr.Count - 1 do
      begin
        if Arr.Items[I].JSONType <> jtObject then
          raise EPJFormat.CreateFmt('tarefa %d invalida', [I + 1]);
        TaskObj := TJSONObject(Arr.Items[I]);
        T := TaskFromJSON(TaskObj);
        List.Add(T);
        if Ids.IndexOf(T.Id) >= 0 then
          raise EPJFormat.CreateFmt('ID repetido no arquivo: %s', [T.Id]);
        Ids.Add(T.Id);
        { nivel pelo pai: o pai precisa ser um ancestral aberto (ordem de topicos) }
        Par := Trim(AIJSONStr(TaskObj, 'parent'));
        while (Stack.Count > 0) and not SameText(Stack[Stack.Count - 1], Par) do
          Stack.Delete(Stack.Count - 1);
        if (Par <> '') and (Stack.Count = 0) then
          raise EPJFormat.CreateFmt('%s: o pai "%s" precisa vir antes e conter a tarefa (ordem de topicos)', [T.Id, Par]);
        T.Level := Stack.Count + 1;
        Stack.Add(T.Id);
        { o contador nunca fica abaixo do maior numero ja usado }
        Num := StrToIntDef(Copy(T.Id, 3, MaxInt), 0);
        if (Length(T.Id) > 2) and (T.Id[2] = '-') and (Num > MaxNum) then MaxNum := Num;
      end;
    if NNext <= MaxNum then NNext := MaxNum + 1;

    Arr := AIJSONArr(Obj, 'links');
    if Arr <> nil then
      for I := 0 to Arr.Count - 1 do
      begin
        if Arr.Items[I].JSONType <> jtObject then
          raise EPJFormat.CreateFmt('vinculo %d invalido', [I + 1]);
        LinkList.Add(LinkFromJSON(TJSONObject(Arr.Items[I]), I));
      end;
    for I := 0 to LinkList.Count - 1 do
      for Num := I + 1 to LinkList.Count - 1 do
        if SameText(TPJLink(LinkList[I]).FromId, TPJLink(LinkList[Num]).FromId) and
           SameText(TPJLink(LinkList[I]).ToId, TPJLink(LinkList[Num]).ToId) then
          raise EPJFormat.CreateFmt('vinculo repetido: %s -> %s',
            [TPJLink(LinkList[I]).FromId, TPJLink(LinkList[I]).ToId]);
    { calendarios: lidos antes de trocar o documento; ausentes = padrao + 24 h }
    Arr := AIJSONArr(Obj, 'calendars');
    if Arr <> nil then
    begin
      CalList := TFPObjectList.Create(True);
      for I := 0 to Arr.Count - 1 do
      begin
        if Arr.Items[I].JSONType <> jtObject then
          raise EPJFormat.CreateFmt('calendario %d invalido', [I + 1]);
        Cal := TAIWorkCalendar.Create;
        CalList.Add(Cal);
        try
          Cal.FromJSON(TJSONObject(Arr.Items[I]));
        except
          on E: EAIWorkCalendar do raise EPJFormat.Create(E.Message);
        end;
        if Trim(Cal.Name) = '' then raise EPJFormat.CreateFmt('calendario %d sem nome', [I + 1]);
        for K := 0 to CalList.Count - 2 do
          if SameText(TAIWorkCalendar(CalList[K]).Name, Cal.Name) then
            raise EPJFormat.CreateFmt('calendario repetido: %s', [Cal.Name]);
      end;
    end;

    { ciclo, tarefa inexistente ou resumo ligado a subtarefa: recusa o arquivo }
    G := BuildTaskGraphFrom(List, LinkList, GErr);
    if G = nil then raise EPJFormat.Create('vinculos invalidos: ' + GErr);
    G.Free;

    { tudo lido sem erro: substitui o conteudo do documento }
    P.Id := NId; P.Name := NName; P.Revision := NRev; P.Author := NAuthor;
    P.ObjectiveShort := NShort; P.ObjectiveLong := NLong; P.ObjectiveScope := NScope;
    P.ObjectiveSuccess := NSuccess;
    P.StartDate := NStart; P.StatusDate := NStatus; P.ScheduleFrom := NFrom;
    P.MinutesPerDay := NMpd; P.MinutesPerWeek := NMpw;
    P.NextNumber := NNext;
    P.ProjectCalendarName := NCalName;
    P.CriticalSlack := NCrit;
    if CalList <> nil then P.AdoptCalendars(CalList) else P.ResetCalendars;
    P.Raw.Free;
    P.Raw := TJSONObject(Obj.Clone);
    P.AdoptTasks(List);
    P.AdoptLinks(LinkList);
  finally
    List.Free;
    LinkList.Free;
    CalList.Free;
    Stack.Free;
    Ids.Free;
  end;
end;

procedure ProjectFromJSONText(P: TPJProject; const Text: string);
var O: TJSONObject;
begin
  try
    O := AIJSONParseObject(Text);
    try
      ProjectFromJSON(P, O);
    finally
      O.Free;
    end;
  except
    on E: EAIJSONFormat do raise EPJFormat.Create(E.Message);
  end;
end;

type
  TPJSaveCheck = class
    procedure Validate(const AText: string);
  end;

procedure TPJSaveCheck.Validate(const AText: string);
var Check: TPJProject;
begin
  { confere o que foi gravado antes de substituir o arquivo bom }
  Check := TPJProject.Create;
  try
    ProjectFromJSONText(Check, AText);
  finally
    Check.Free;
  end;
end;

procedure SaveProjectFile(P: TPJProject; const FileName: string);
var C: TPJSaveCheck;
begin
  C := TPJSaveCheck.Create;
  try
    AISaveTextFileAtomic(FileName, ProjectToJSONText(P), @C.Validate);
  finally
    C.Free;
  end;
  P.MarkSaved;
end;

procedure LoadProjectFile(P: TPJProject; const FileName: string);
begin
  if not FileExists(FileName) then
    raise EPJError.CreateFmt('arquivo nao encontrado: %s', [FileName]);
  ProjectFromJSONText(P, AIReadTextFile(FileName));
  P.ClearHistory;
  P.MarkSaved;
end;

end.
