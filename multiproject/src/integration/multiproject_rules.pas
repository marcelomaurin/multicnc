unit multiproject_rules;

{ Regras de dominio A01..A08. Gerar e decidir trabalham numa copia e aplicam
  a mudanca como um unico comando. Nenhum arquivo de ferramenta e alterado. }
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, multiproject_types, multiproject_document;
function PJGenerateSuggestions(P: TPJProject; out Reason: string; const ProjectFile: string = ''): Integer;
function PJDecideSuggestions(P: TPJProject; const IDs: array of string; Accept: Boolean; out Reason: string): Boolean;
function PJCanStartFabrication(P: TPJProject; T: TPJTask; out Reason: string): Boolean;
function PJSetFabricationGate(P: TPJProject; Enabled: Boolean; out Reason: string): Boolean;
function PJRuleEnabled(P: TPJProject; const Rule: string): Boolean;
function PJIsFabrication(K: TPJTaskKind): Boolean;
implementation
uses fpjson, jsonparser, aitaskgraph, aiprojectduration, multiproject_json, multiproject_kinds;
function PJIsFabrication(K: TPJTaskKind): Boolean;
begin Result := PJKindInfo(K).Fabrication or (K = tkLathe); end;
function PJRuleEnabled(P: TPJProject; const Rule: string): Boolean;
var I: Integer;
begin
  Result := False;
  for I := 0 to High(P.EnabledRules) do if SameText(P.EnabledRules[I], Rule) then Exit(True);
end;
function Key(const Rule: string; Kind: TPJTaskKind; const Sources: TPJStrings): string;
var L: TStringList; I: Integer;
begin
  L := TStringList.Create;
  try
    for I := 0 to High(Sources) do L.Add(Sources[I]);
    L.Sort; Result := Rule + ':' + KindName(Kind) + ':' + L.CommaText;
  finally L.Free; end;
end;
function FindGenerated(P: TPJProject; const Rule: string; Kind: TPJTaskKind; const Sources: TPJStrings): TPJTask;
var I: Integer; S: string;
begin
  S := Key(Rule, Kind, Sources); Result := nil;
  for I := 0 to P.Count-1 do
    if (P[I].Origin.By = 'rule') and
      (Key(P[I].Origin.Rule, P[I].Kind, P[I].Origin.Sources) = S) then Exit(P[I]);
end;
function Ready(T: TPJTask): Boolean;
begin
  Result := (T <> nil) and (T.State in [tsReview, tsDone]);
  if Result and PJKindInfo(T.Kind).RequiresArtifact then
    Result := (T.Artifact.Hash <> '') and ((T.Artifact.Status = 'valid') or (T.Artifact.Status = 'ready'));
end;
function Approved(T: TPJTask): Boolean;
var I: Integer;
begin
  Result := Ready(T) and (T.State = tsDone);
  if Result then for I := 0 to High(T.FuncSpec) do
    if not (T.FuncSpec[I].State in [csPassed, csWaived]) then Exit(False);
end;
procedure Append(var A: TPJStrings; const S: string);
begin SetLength(A, Length(A)+1); A[High(A)] := S; end;
procedure CopySpecs(FromTask, ToTask: TPJTask);
var I: Integer;
begin
  ToTask.TechItems := Copy(FromTask.TechItems, 0, Length(FromTask.TechItems));
  ToTask.TechText := FromTask.TechText; ToTask.LongDesc := FromTask.LongDesc;
  ToTask.FuncSpec := Copy(FromTask.FuncSpec, 0, Length(FromTask.FuncSpec));
  for I := 0 to High(ToTask.FuncSpec) do
  begin ToTask.FuncSpec[I].State := csPending; ToTask.FuncSpec[I].Evidence := ''; end;
end;
procedure Link(P: TPJProject; const FromId, ToId: string; Artifact: Boolean);
var Err: string;
begin
  if P.IndexOfLink(FromId, ToId) >= 0 then Exit;
  if not P.AddLink(FromId, ToId, atlFS, AINoLag, Artifact, Err) then raise EPJError.Create(Err);
end;
function Suggest(P: TPJProject; const Rule: string; Kind: TPJTaskKind;
  const Sources: TPJStrings; const Name, Scope: string; out Created: Boolean): TPJTask;
begin
  Created := False;
  Result := FindGenerated(P, Rule, Kind, Sources);
  if Result <> nil then Exit;
  Result := P.AddTask('', Kind, Name, Name);
  Result.State := tsSuggested; Result.Origin.By := 'rule'; Result.Origin.Rule := Rule;
  Result.Origin.Scope := Scope; Result.Origin.Sources := Copy(Sources, 0, Length(Sources));
  Result.Duration := AIMakeDuration(P.MinutesPerDay, aduDay, False, True);
  if Kind = tkMilestone then Result.Duration.Minutes := 0;
  Created := True;
end;
procedure SuggestMachine(P: TPJProject; T: TPJTask);
var I: Integer; M: TPJMachineTypes;
begin
  M := MachineTypesFor(T.Kind);
  for I := 0 to P.ResourceCount-1 do
    if (P.Resources[I].RType = rtMachine) and (P.Resources[I].MachineType in M) then
    begin
      T.AddTechItem('maquina_sugerida', P.Resources[I].Name, '');
      if (T.Kind = tkPCBFab) and (P.Resources[I].MachineType = pmRouter) then
        T.AddTechItem('ferramenta_sugerida', 'RouterPCB', '');
      Exit;
    end;
end;
function Present(const S: string): Boolean;
begin Result := (Trim(S) <> '') and not SameText(S,'false') and not SameText(S,'nao') and (S <> '0'); end;
function SourceProcess(T: TPJTask): TPJProcess;
var S: string;
begin
  Result := T.Process;
  if Result <> prNone then Exit;
  S := T.TechValue('processo');
  if S = '' then S := T.TechValue('process');
  TryProcessFromName(S, Result);
end;
function Study(T: TPJTask): string;
var I: Integer; K: string;
  procedure Add(const S: string);
  begin if Pos(S, Result) = 0 then begin if Result <> '' then Result := Result + ', '; Result := Result + S; end; end;
begin
  Result := '';
  for I := 0 to High(T.TechItems) do
  begin
    K := LowerCase(T.TechItems[I].Key);
    if (Pos('carga',K)>0) or (Pos('forca',K)>0) then Add('static');
    if (Pos('temperatura',K)>0) or (Pos('termic',K)>0) then Add('thermal');
    if (Pos('rotacao',K)>0) or (Pos('rpm',K)>0) then Add('modal');
    if (Pos('tensao',K)>0) or (Pos('corrente',K)>0) then Add('circuit');
  end;
  if Result = '' then Result := 'static';
end;
procedure ApplyGates(P: TPJProject);
var I, J, K: Integer; F, G, Src: TPJTask; Chained: Boolean;
begin
  if not P.FabricationGate then Exit;
  for I := 0 to P.Count-1 do
  begin
    F := P[I];
    if not PJIsFabrication(F.Kind) or (F.Origin.By <> 'rule') or (F.State <> tsPlanned) then Continue;
    Chained := False;
    for K := 0 to High(F.Origin.Sources) do
    begin
      Src := P.FindTask(F.Origin.Sources[K]);
      if (Src <> nil) and PJIsFabrication(Src.Kind) then Chained := True;
    end;
    if Chained then Continue;
    for J := 0 to P.Count-1 do
    begin
      G := P[J];
      if (G.Origin.Rule = 'A05') and (G.State in [tsPlanned, tsDone]) and
        ((G.Origin.Scope = '') or (G.Origin.Scope = F.Origin.Scope)) then Link(P, G.Id, F.Id, False);
    end;
  end;
end;
function PJCanStartFabrication(P: TPJProject; T: TPJTask; out Reason: string): Boolean;
var IDs: TStringList; N, I: Integer; Pred: TPJTask;
begin
  Reason := ''; Result := True;
  if not P.FabricationGate or not PJIsFabrication(T.Kind) or (T.Origin.By <> 'rule') then Exit;
  Result := False; Reason := T.Id + ': aguarda o marco Liberado para fabricacao concluido';
  IDs := TStringList.Create;
  try
    IDs.Add(T.Id); N := 0;
    while N < IDs.Count do
    begin
      for I := 0 to P.LinkCount-1 do if (P.Links[I].ToId = IDs[N]) and (P.Links[I].LinkType = atlFS) then
      begin
        Pred := P.FindTask(P.Links[I].FromId);
        if Pred = nil then Continue;
        if (Pred.Origin.Rule = 'A05') and (Pred.State = tsDone) then begin Reason := ''; Exit(True); end;
        if IDs.IndexOf(Pred.Id) < 0 then IDs.Add(Pred.Id);
      end;
      Inc(N);
    end;
  finally IDs.Free; end;
end;
procedure ReadAssemblyChecklist(P: TPJProject; T: TPJTask; const ProjectFile: string; var Warnings: string);
var I,J: Integer; A: TPJTask; FN,Text,CheckText: string; L: TStringList; D: TJSONData; Steps: TJSONArray; Step: TJSONObject;
begin
  for I:=0 to P.Count-1 do
  begin
    A:=P[I];
    if (A.Kind<>tkAssembly) or (A.State=tsCancelled) or (A.Artifact.Path='') then Continue;
    FN:=A.Artifact.Path;
    if (ExtractFileDrive(FN)='') and not (FN[1] in ['/', '\']) then
    begin
      if ProjectFile='' then Continue;
      FN:=ExpandFileName(ExtractFilePath(ExpandFileName(ProjectFile))+FN);
    end;
    if not FileExists(FN) then Continue;
    L:=TStringList.Create; D:=nil;
    try
      try
        L.LoadFromFile(FN); D:=GetJSON(L.Text);
        if not (D is TJSONObject) then raise EPJError.Create('Esperado objeto JSON');
        Steps:=TJSONObject(D).Get('manual_steps',TJSONArray(nil));
        if (Steps=nil) or (Steps.Count=0) then Continue;
        T.Notes:=T.Notes+LineEnding+'Manual: '+A.Artifact.Path;
        for J:=0 to Steps.Count-1 do
        begin
          Step:=Steps.Objects[J]; Text:=Step.Get('title',''); CheckText:=Step.Get('checks','');
          if CheckText='' then CheckText:=Step.Get('instructions','');
          if CheckText<>'' then T.AddCriterion(A.Id+':manual:'+IntToStr(J+1),Text+': '+CheckText);
          T.Notes:=T.Notes+LineEnding+Text+': '+Step.Get('instructions','')+' / Ferramentas: '+Step.Get('tools','');
        end;
        Link(P,A.Id,T.Id,True);
      except on E: Exception do Warnings:=Warnings+A.Id+': nao foi possivel ler o manual: '+E.Message+LineEnding; end;
    finally D.Free; L.Free; end;
  end;
end;
function GenerateInPlace(P: TPJProject; out Reason: string; const ProjectFile: string): Integer;
var InitialCount, I, J, K, GroupIndex, Groups: Integer; Src, T, F, E, GroupTask, C: TPJTask;
    Made, AllReady, HasChild, Failed: Boolean; Scope, Name, Text, Target: string;
    Sources: TPJStrings; Kind: TPJTaskKind; Proc: TPJProcess; Targets: TStringList;
begin
  InitialCount := P.Count; Reason := '';
  { A01/A02: proposals may be scheduled before the design is ready. }
  for I := 0 to InitialCount-1 do
  begin
    Src := P[I];
    if Src.State = tsCancelled then Continue;
    if (Src.Origin.By = 'rule') and (Src.State = tsSuggested) then Continue;
    Scope := P.ParentId(I);
    if (Src.Kind = tkPart) and PJRuleEnabled(P,'A01') then
    begin
      Proc := SourceProcess(Src); Name := ''; Kind := tkGeneral;
      case Proc of
        prPrint3D: begin Kind := tkPrint3D; Name := 'Imprimir '; end;
        prRouter: begin Kind := tkRouter; Name := 'Usinar '; end;
        prLaserCut: begin Kind := tkLaserCut; Name := 'Cortar '; end;
        prLathe: begin Kind := tkLathe; Name := 'Tornear '; end;
      end;
      if Name <> '' then
      begin
        F := Suggest(P,'A01',Kind,[Src.Id],Name+Src.Name,Scope,Made);
        if Made then begin CopySpecs(Src,F); Link(P,Src.Id,F.Id,True); SuggestMachine(P,F); end;
        if Present(Src.TechValue('gravacao')) and (F.State <> tsCancelled) then
        begin
          E := Suggest(P,'A01',tkLaserArt,[F.Id],'Gravar '+Src.TechValue('gravacao'),Scope,Made);
          if Made then begin CopySpecs(Src,E); Link(P,F.Id,E.Id,True); SuggestMachine(P,E); end;
        end;
      end;
    end;
    if (Src.Kind = tkElectronics) and PJRuleEnabled(P,'A02') then
    begin
      T := Suggest(P,'A02',tkPCBFab,[Src.Id],'Fabricar placa '+Src.Name,Scope,Made);
      if Made then begin CopySpecs(Src,T); Link(P,Src.Id,T.Id,True); SuggestMachine(P,T); end;
      if Present(Src.TechValue('componentes')) or Present(Src.TechValue('bom')) then
      begin
        T := Suggest(P,'A02',tkPurchase,[Src.Id],'Comprar componentes de '+Src.Name,Scope,Made);
        if Made then begin CopySpecs(Src,T); Link(P,Src.Id,T.Id,True); end;
      end;
    end;
  end;
  { A03: process subsystems from deepest to root; a sole top-level container
    does not create a second, identical objective assembly. }
  if PJRuleEnabled(P,'A03') then
  for GroupIndex := InitialCount-1 downto -1 do
  begin
    if GroupIndex >= 0 then
    begin
      GroupTask := P[GroupIndex];
      if not P.HasChildren(GroupIndex) or (GroupTask.State = tsCancelled) then Continue;
      Scope := GroupTask.Id; Name := 'Montagem virtual de '+GroupTask.Name;
    end
    else begin Scope := ''; Name := 'Montagem virtual'; end;
    Sources := nil; AllReady := True; Groups := 0;
    for J := 0 to InitialCount-1 do if P.ParentId(J) = Scope then
    begin
      Src := P[J]; if Src.State = tsCancelled then Continue;
      if Src.Kind in [tkPart, tkElectronics] then
      begin Append(Sources, Src.Id); AllReady := AllReady and Ready(Src); end
      else if P.HasChildren(J) then
      begin
        Inc(Groups); T := nil;
        for K := 0 to P.Count-1 do
          if (P[K].Origin.Rule='A03') and (P[K].Origin.Scope=Src.Id) and (P[K].State<>tsCancelled) then T := P[K];
        if T = nil then AllReady := False
        else begin Append(Sources,T.Id); AllReady := AllReady and Ready(T); end;
      end;
    end;
    if (GroupIndex = -1) and (Groups = 1) and (Length(Sources)=1) then Continue;
    if not AllReady or (Length(Sources)=0) then Continue;
    T := Suggest(P,'A03',tkAssembly,Sources,Name,Scope,Made);
    if Made then for J := 0 to High(Sources) do
    begin
      Src := P.FindTask(Sources[J]); Link(P,Src.Id,T.Id,True);
      for K := 0 to High(Src.TechItems) do T.AddTechItem(Src.TechItems[K].Key,Src.TechItems[K].Value,Src.TechItems[K].UnitName);
      for K := 0 to High(Src.FuncSpec) do T.AddCriterion(Src.Id+':'+Src.FuncSpec[K].Id,Src.FuncSpec[K].Text);
    end;
  end;
  for I := 0 to InitialCount-1 do
  begin
    Src := P[I]; Scope := Src.Origin.Scope;
    if (Src.Kind=tkAssembly) and Ready(Src) and PJRuleEnabled(P,'A04') then
    begin
      T := Suggest(P,'A04',tkValidation,[Src.Id],'Validar '+Src.Name,Scope,Made);
      if Made then begin CopySpecs(Src,T); T.AddTechItem('estudo_sugerido',Study(Src),''); Link(P,Src.Id,T.Id,True); end;
    end;
    if (Src.Kind=tkValidation) and Approved(Src) and PJRuleEnabled(P,'A05') then
    begin
      T := Suggest(P,'A05',tkMilestone,[Src.Id],'Liberado para fabricacao',Scope,Made);
      if Made then Link(P,Src.Id,T.Id,False);
    end;
    if (Src.Kind in [tkValidation,tkFunctionalTest]) and (Src.State<>tsCancelled) and PJRuleEnabled(P,'A07') then
    begin
      Failed := False; Text := '';
      for J := 0 to High(Src.FuncSpec) do if Src.FuncSpec[J].State=csFailed then
      begin Failed := True; Text := Text + Src.FuncSpec[J].Text+': '+Src.FuncSpec[J].Evidence+LineEnding; end;
      if Failed then
      begin
        Target := Src.TechValue('revisar_tarefa');
        if Target = '' then Reason := Reason + Src.Id+': informe revisar_tarefa na especificacao tecnica.'+LineEnding
        else
        begin
          Targets := TStringList.Create;
          try
            Targets.StrictDelimiter := True; Targets.Delimiter := ';'; Targets.DelimitedText := Target;
            for J := 0 to Targets.Count-1 do
            begin
              C := P.FindTask(Trim(Targets[J]));
              if (C=nil) or not (C.Kind in [tkPart,tkElectronics]) then
                raise EPJError.Create('Revisao exige ID de peca ou placa: '+Targets[J]);
              T := Suggest(P,'A07',C.Kind,[Src.Id,C.Id],'Revisar '+C.Name,Scope,Made);
              if Made then
              begin
                CopySpecs(C,T); T.Process := C.Process; T.Notes := Text;
                Link(P,Src.Id,T.Id,True); Link(P,C.Id,T.Id,True);
              end;
            end;
          finally Targets.Free; end;
        end;
      end;
    end;
  end;
  if PJRuleEnabled(P,'A06') then
  begin
    Sources := nil; AllReady := True;
    for I := 0 to InitialCount-1 do
    begin
      Src := P[I];
      if not PJIsFabrication(Src.Kind) or (Src.State=tsCancelled) then Continue;
      AllReady := AllReady and (Src.State=tsDone);
      HasChild := False;
      for J := 0 to P.LinkCount-1 do if P.Links[J].FromId=Src.Id then
      begin
        T := P.FindTask(P.Links[J].ToId);
        if (T<>nil) and PJIsFabrication(T.Kind) and (T.State<>tsCancelled) then HasChild := True;
      end;
      if not HasChild then Append(Sources,Src.Id);
    end;
    if AllReady and (Length(Sources)>0) then
    begin
      T := Suggest(P,'A06',tkPhysicalAssembly,Sources,'Montagem fisica','',Made);
      if Made then
      begin
        T.Notes := 'Checklist: conferir pecas e componentes; montar conforme o manual do MultiAssembly; conferir fixacoes e ligacoes.';
        ReadAssemblyChecklist(P,T,ProjectFile,Reason);
        for J := 0 to High(Sources) do Link(P,Sources[J],T.Id,True);
        { Purchasing is a physical prerequisite, even though it has no machine. }
        for J := 0 to InitialCount-1 do if (P[J].Kind=tkPurchase) and (P[J].State<>tsCancelled) then Link(P,P[J].Id,T.Id,False);
      end;
    end;
    for I := 0 to InitialCount-1 do
    begin
      Src := P[I];
      if (Src.Kind=tkPhysicalAssembly) and (Src.State=tsDone) then
      begin
        T := Suggest(P,'A06',tkFunctionalTest,[Src.Id],'Teste funcional','',Made);
        if Made then
        begin
          T.FuncSpec := Copy(P.ObjectiveSuccess,0,Length(P.ObjectiveSuccess));
          for J := 0 to High(T.FuncSpec) do begin T.FuncSpec[J].State:=csPending; T.FuncSpec[J].Evidence:=''; end;
          Link(P,Src.Id,T.Id,False);
        end;
      end;
      if (Src.Kind=tkFunctionalTest) and Approved(Src) then
      begin
        T := Suggest(P,'A06',tkMilestone,[Src.Id],'Objetivo concluido','',Made);
        if Made then Link(P,Src.Id,T.Id,False);
      end;
    end;
  end;
  Result := P.Count-InitialCount;
end;
procedure ApplyCopy(P, Q: TPJProject; const Caption: string);
var O: TJSONObject;
begin
  O := ProjectToJSON(Q);
  try
    P.BeginChange(Caption);
    try ProjectFromJSON(P,O); finally P.EndChange; end;
  finally O.Free; end;
end;
function PJSetFabricationGate(P: TPJProject; Enabled: Boolean; out Reason: string): Boolean;
var Q: TPJProject; I: Integer; F,G: TPJTask;
begin
  Result:=True; Reason:='';
  if P.FabricationGate=Enabled then Exit;
  Q:=TPJProject.Create;
  try
    try
      ProjectFromJSONText(Q,ProjectToJSONText(P)); Q.FabricationGate:=Enabled;
      if Enabled then ApplyGates(Q)
      else for I:=Q.LinkCount-1 downto 0 do
      begin
        G:=Q.FindTask(Q.Links[I].FromId); F:=Q.FindTask(Q.Links[I].ToId);
        if (G<>nil) and (F<>nil) and (G.Origin.Rule='A05') and PJIsFabrication(F.Kind) and
          (F.Origin.By='rule') and (F.State in [tsPlanned,tsSuggested,tsBlocked,tsOutdated]) then
          Q.RemoveLink(G.Id,F.Id);
      end;
      ApplyCopy(P,Q,'Alterar liberacao para fabricacao');
    except on E: Exception do begin Reason:=E.Message; Result:=False; end; end;
  finally Q.Free; end;
end;
function PJGenerateSuggestions(P: TPJProject; out Reason: string; const ProjectFile: string): Integer;
var Q: TPJProject;
begin
  Q := TPJProject.Create;
  try
    try
      ProjectFromJSONText(Q,ProjectToJSONText(P));
      Result := GenerateInPlace(Q,Reason,ProjectFile);
      ApplyGates(Q);
      if ProjectToJSONText(P)<>ProjectToJSONText(Q) then ApplyCopy(P,Q,'Gerar sugestoes');
    except on E: Exception do begin Result := -1; Reason := E.Message; end; end;
  finally Q.Free; end;
end;
function PJDecideSuggestions(P: TPJProject; const IDs: array of string; Accept: Boolean; out Reason: string): Boolean;
var Q: TPJProject; I,J,N: Integer; T: TPJTask; Selected: Boolean; Caption: string;
begin
  Result := False; Reason := ''; Q := TPJProject.Create;
  try
    try
      ProjectFromJSONText(Q,ProjectToJSONText(P)); N := 0;
      for J := 0 to High(IDs) do
      begin
        T := Q.FindTask(IDs[J]);
        if (T=nil) or (T.State<>tsSuggested) then raise EPJError.Create('Sugestao inexistente ou ja decidida: '+IDs[J]);
      end;
      for I := 0 to Q.Count-1 do
      begin
        T := Q[I]; Selected := Length(IDs)=0;
        for J := 0 to High(IDs) do if IDs[J]=T.Id then Selected := True;
        if Selected and (T.State=tsSuggested) then
        begin
          if Accept then T.State:=tsPlanned else T.State:=tsCancelled;
          Inc(N);
        end;
      end;
      if N=0 then begin Reason:='Nenhuma sugestao selecionada'; Exit; end;
      if Accept then ApplyGates(Q);
      if Accept then Caption:='Aceitar sugestoes' else Caption:='Recusar sugestoes';
      ApplyCopy(P,Q,Caption); Result := True;
    except on E: Exception do Reason:=E.Message; end;
  finally Q.Free; end;
end;
end.
