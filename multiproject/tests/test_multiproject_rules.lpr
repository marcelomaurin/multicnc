program test_multiproject_rules;
{$mode objfpc}{$H+}
uses Classes, SysUtils, fpjson, aitaskgraph, multiproject_types,
  multiproject_document, multiproject_json, multiproject_graph, multiproject_states,
  multiproject_rules, multiproject_examples, multiproject_templates,
  multiproject_lathe, multiproject_checks, multiproject_kinds;
var Passed: Integer;
procedure Check(B: Boolean; const Msg: string);
begin if not B then raise Exception.Create(Msg); Inc(Passed); end;
function TaskOf(P: TPJProject; K: TPJTaskKind; const Rule: string=''): TPJTask;
var I: Integer;
begin
  Result:=nil;
  for I:=0 to P.Count-1 do if (P[I].Kind=K) and ((Rule='') or (P[I].Origin.Rule=Rule)) then Exit(P[I]);
end;
function CountOf(P: TPJProject; K: TPJTaskKind): Integer;
var I: Integer;
begin Result:=0; for I:=0 to P.Count-1 do if P[I].Kind=K then Inc(Result); end;
procedure Complete(T: TPJTask);
var I: Integer;
begin
  T.State:=tsDone; T.Artifact.Status:='valid'; T.Artifact.Hash:='fixture-validada';
  for I:=0 to High(T.FuncSpec) do T.FuncSpec[I].State:=csPassed;
end;
procedure AcceptAll(P: TPJProject);
var Why: string;
begin Check(PJDecideSuggestions(P,[],True,Why),'aceitar sugestoes: '+Why); end;
procedure Acyclic(P: TPJProject);
var Why: string; G: TAITaskGraph;
begin G:=BuildTaskGraph(P,Why); Check(G<>nil,'grafo aciclico: '+Why); G.Free; end;
procedure TestProgression;
var P: TPJProject; N,I: Integer; Why, FabId, SrcId, GateId, Before: string; T: TPJTask;
begin
  P:=TPJProject.Create;
  try
    BuildMotorSeed(P); Check(P.Count=4,'somente quatro tarefas de projeto');
    N:=PJGenerateSuggestions(P,Why); Check(N=5,'fabrica cinco tarefas a partir dos processos: '+Why);
    Check(CountOf(P,tkAssembly)=0,'montagem aguarda projetos prontos');
    Check(PJGenerateSuggestions(P,Why)=0,'gerar novamente nao duplica');
    FabId:=TaskOf(P,tkPrint3D).Id; SrcId:=TaskOf(P,tkPrint3D).Origin.Sources[0];
    Check(P.IndexOfLink(SrcId,FabId)>=0,'fabricacao recebe artefato do projeto');
    Check(TaskOf(P,tkPrint3D).TechValue('maquina_sugerida')='Ender-3','sugere maquina compativel');
    AcceptAll(P); Check(P.UndoDescription='Aceitar sugestoes','aceitar lote e um comando');
    Check(P.Undo,'desfaz lote'); Check(P.FindTask(FabId).State=tsSuggested,'desfaz todas as decisoes');
    Check(P.Redo,'refaz lote'); Check(P.FindTask(FabId).State=tsPlanned,'refaz todas as decisoes');
    Check(not CanSetState(P,FabId,tsInProgress,Why) and (Pos('Liberado',Why)>0),'gate bloqueia antes da validacao');
    for I:=0 to 3 do Complete(P[I]);
    Check(PJGenerateSuggestions(P,Why)=1,'projetos prontos geram uma montagem'); AcceptAll(P);
    Complete(TaskOf(P,tkAssembly));
    Check(PJGenerateSuggestions(P,Why)=1,'montagem pronta gera validacao'); AcceptAll(P);
    T:=TaskOf(P,tkValidation);
    Check(Pos('static',T.TechValue('estudo_sugerido'))>0,'carga sugere estudo estatico');
    Check(Pos('thermal',T.TechValue('estudo_sugerido'))>0,'temperatura sugere estudo termico');
    Check(Pos('modal',T.TechValue('estudo_sugerido'))>0,'rotacao sugere estudo modal');
    Check(Pos('circuit',T.TechValue('estudo_sugerido'))>0,'tensao sugere circuito');
    Check(Length(T.FuncSpec)>=2,'criterios do projeto vao para o estudo');
    Check(PJGenerateSuggestions(P,Why)=0,'validacao pendente nao libera fabricacao');
    Complete(T); Check(PJGenerateSuggestions(P,Why)=1,'validacao aprovada sugere liberacao');
    GateId:=TaskOf(P,tkMilestone,'A05').Id;
    Check(P.IndexOfLink(GateId,FabId)<0,'proposta nao muda vinculos do plano existente');
    AcceptAll(P); Check(P.IndexOfLink(GateId,FabId)>=0,'aceitar liberacao liga as fabricacoes');
    Check(not CanSetState(P,FabId,tsInProgress,Why),'marco ainda planejado bloqueia');
    Complete(P.FindTask(GateId)); Check(CanSetState(P,FabId,tsInProgress,Why),'liberacao concluida permite iniciar: '+Why);
    for I:=0 to P.Count-1 do if PJIsFabrication(P[I].Kind) then Complete(P[I]);
    Check(PJGenerateSuggestions(P,Why)=1,'fabricacoes concluidas geram montagem fisica'); AcceptAll(P);
    Complete(TaskOf(P,tkPhysicalAssembly));
    Check(PJGenerateSuggestions(P,Why)=1,'montagem fisica gera teste funcional'); AcceptAll(P);
    T:=TaskOf(P,tkFunctionalTest); Check(Length(T.FuncSpec)=Length(P.ObjectiveSuccess),'teste recebe criterios do objetivo');
    Check(PJGenerateSuggestions(P,Why)=0,'teste pendente nao encerra objetivo');
    Complete(T); Check(PJGenerateSuggestions(P,Why)=1,'teste aprovado gera marco final'); AcceptAll(P);
    Check((P.Count=15) and (P.LinkCount=21),Format('motor completo: %d tarefas, %d vinculos',[P.Count,P.LinkCount]));
    Before:=ProjectToJSONText(P); Check(PJGenerateSuggestions(P,Why)=0,'motor completo idempotente');
    Check(Before=ProjectToJSONText(P),'sem sugestoes nao muda o projeto'); Acyclic(P);
  finally P.Free; end;
end;
procedure TestDecisionsAndRevision;
var P,Q: TPJProject; Why,Id,Before,TargetId: string; T: TPJTask;
begin
  P:=TPJProject.Create; Q:=TPJProject.Create;
  try
    BuildMotorSeed(P); Check(PJGenerateSuggestions(P,Why)=5,'prepara sugestoes para recusa');
    Id:=TaskOf(P,tkPrint3D).Id;
    Check(PJDecideSuggestions(P,[Id],False,Why),'recusa individual');
    Check(P.FindTask(Id).State=tsCancelled,'recusa preserva registro de origem');
    Check(PJGenerateSuggestions(P,Why)=0,'recusada nao reaparece');
    ProjectFromJSONText(Q,ProjectToJSONText(P)); Check(PJGenerateSuggestions(Q,Why)=0,'deduplicacao sobrevive ao arquivo');
    Before:=ProjectToJSONText(P);
    Check(not PJDecideSuggestions(P,[Id,'inexistente'],True,Why),'decisao invalida recusada');
    Check(Before=ProjectToJSONText(P),'decisao invalida nao aplica parcialmente');
    TargetId:=P[0].Id;
    T:=P.AddTask('',tkValidation,'Estudo','Estudo'); T.AddCriterion('F1','Temperatura limite');
    T.FuncSpec[0].State:=csFailed; T.FuncSpec[0].Evidence:='Medidos 90 C';
    T.AddTechItem('revisar_tarefa',TargetId,'');
    Check(PJGenerateSuggestions(P,Why)=1,'reprovacao gera revisao');
    T:=TaskOf(P,tkPart,'A07'); Check(T<>nil,'revisao conserva tipo da peca');
    Check(Pos('90 C',T.Notes)>0,'evidencia acompanha revisao');
    Check(T.Origin.Sources[1]=TargetId,'origem aponta peca a revisar'); Acyclic(P);
    Check(PJGenerateSuggestions(P,Why)=0,'reprovacao repetida nao duplica');
    T:=P.AddTask('',tkValidation,'Estudo invalido','Estudo invalido'); T.AddCriterion('X','Falhou');
    T.FuncSpec[0].State:=csFailed; T.AddTechItem('revisar_tarefa','T-9999','');
    Before:=ProjectToJSONText(P);
    Check(PJGenerateSuggestions(P,Why)=-1,'alvo invalido recusa geracao');
    Check(Before=ProjectToJSONText(P),'erro de regra nao aplica parcialmente');
  finally Q.Free; P.Free; end;
end;
procedure TestOptionsAndGroups;
var P: TPJProject; Why,GroupId,FabId: string; I: Integer; T: TPJTask; Res: TPJResource;
begin
  P:=TPJProject.Create;
  try
    BuildMotorSeed(P); P.FabricationGate:=False;
    for I:=0 to 3 do Complete(P[I]);
    Check(PJGenerateSuggestions(P,Why)=6,'gate desligado gera fabricacoes e montagem'); AcceptAll(P);
    FabId:=TaskOf(P,tkPrint3D).Id;
    Check(CanSetState(P,FabId,tsInProgress,Why),'sem gate fabricacao depende so da peca');
    Check(P.PredecessorsText(FabId)=P.FindTask(FabId).Origin.Sources[0],'sem gate unico predecessor e a peca');
    P.EnabledRules:=[]; P.MarkSaved;
    Check(PJGenerateSuggestions(P,Why)=0,'regras desligadas nao geram'); Check(not P.Modified,'geracao vazia nao suja documento');
    P.Clear;
    Res:=P.AddResource('Router da oficina',rtMachine); Res.MachineType:=pmRouter;
    P.AddTask('',tkElectronics,'Driver','Driver').AddTechItem('componentes','R1;U1','');
    Check(PJGenerateSuggestions(P,Why)=2,'placa com componentes gera compra e fabricacao');
    Check(TaskOf(P,tkPCBFab).TechValue('ferramenta_sugerida')='RouterPCB','usa router disponivel para placa');
    P.Clear;
    T:=P.AddTask('',tkSummary,'Mecanica','Mecanica'); GroupId:=T.Id;
    Complete(P.AddTask(GroupId,tkPart,'Eixo','Eixo'));
    T:=P.AddTask('',tkSummary,'Eletronica','Eletronica'); GroupId:=T.Id;
    Complete(P.AddTask(GroupId,tkElectronics,'Driver','Driver'));
    Check(PJGenerateSuggestions(P,Why)=3,'duas montagens de subsistema e uma fabricacao de placa'); AcceptAll(P);
    for I:=0 to P.Count-1 do if P[I].Kind=tkAssembly then Complete(P[I]);
    Check(PJGenerateSuggestions(P,Why)=3,'montagem do objetivo e validacoes dos subsistemas');
    Check(CountOf(P,tkAssembly)=3,'montagem de subsistemas e do objetivo'); Acyclic(P);
  finally P.Free; end;
end;
procedure TestTemplatesAndSheet;
var P,Q: TPJProject; I,J: Integer; Why,OldId,FN,Text: string; T: TPJTask; Verified: Boolean; L: TStringList;
begin
  P:=TPJProject.Create; Q:=TPJProject.Create; L:=TStringList.Create;
  FN:=GetTempDir(False)+'multiproject-lathe-'+IntToStr(GetProcessID)+'.md';
  try
    BuildMotorRuleExample(Q); Check(Q.Count=15,'exemplo motor gerado pelas regras');
    Check(Q.LinkCount=21,'exemplo inclui dependencias de artefato e liberacao');
    for I:=0 to Q.Count-1 do Check((Q[I].State=tsPlanned) and (Q[I].Artifact.Hash=''),'exemplo sem conclusoes ou artefatos ficticios');
    OldId:=Q[0].Id; PJCreateFromTemplate(P,Q);
    Check(P.FindTask(OldId)=nil,'modelo atribui IDs novos');
    for I:=0 to P.LinkCount-1 do Check((P.FindTask(P.Links[I].FromId)<>nil) and (P.FindTask(P.Links[I].ToId)<>nil),'modelo remapeia vinculos');
    for I:=0 to P.Count-1 do for J:=0 to High(P[I].Origin.Sources) do Check(P.FindTask(P[I].Origin.Sources[J])<>nil,'modelo remapeia origens');
    Acyclic(P); T:=TaskOf(P,tkLathe); Text:=PJLatheSheet(P,T);
    Check((Pos('aco 1045',Text)>0) and (Pos('A definir',Text)>0),'folha usa especificacao sem inventar parametros');
    Check(Pos('Facear',Text)>0,'folha traz operacoes da especificacao');
    PJSaveLatheSheet(P,T,FN);
    Check(PJCheckArtifact(tkLathe,FN,Verified,Why) and Verified,'folha anexavel e verificada: '+Why);
    try PJSaveLatheSheet(P,T,FN); Check(False,'nao deveria sobrescrever folha'); except on E: EPJError do Check(Pos('existe',E.Message)>0,'preserva folha existente'); end;
    L.LoadFromFile(FN); Check(L.Text=Text,'folha existente preservada');
  finally DeleteFile(FN); L.Free; Q.Free; P.Free; end;
end;
procedure TestManualAndGateSwitch;
var P: TPJProject; A,F: TPJTask; Why,FN,GateId,FabId,AssemblyId: string; L: TStringList;
begin
  P:=TPJProject.Create; L:=TStringList.Create;
  FN:=GetTempDir(False)+'multiproject-manual-'+IntToStr(GetProcessID)+'.massembly';
  try
    L.Text:='{"manual_steps":[{"id":"S1","title":"Fixar base","instructions":"Apertar os parafusos","tools":"Chave Allen","checks":"Base sem folga"}]}';
    L.SaveToFile(FN);
    A:=P.AddTask('',tkAssembly,'Montagem','Montagem'); Complete(A); A.Artifact.Path:=FN; AssemblyId:=A.Id;
    F:=P.AddTask('',tkRouter,'Fabricar base','Fabricar base'); Complete(F);
    Check(PJGenerateSuggestions(P,Why)>0,'montagem fisica sugerida com manual');
    F:=TaskOf(P,tkPhysicalAssembly);
    Check((Length(F.FuncSpec)=1) and (Pos('Base sem folga',F.FuncSpec[0].Text)>0),'checklist recebe verificacoes do manual');
    Check(P.IndexOfLink(AssemblyId,F.Id)>=0,'manual gera vinculo para detectar desatualizacao');
    L.LoadFromFile(FN); Check(Pos('Base sem folga',L.Text)>0,'manual de origem preservado');
    BuildMotorRuleExample(P); GateId:=TaskOf(P,tkMilestone,'A05').Id; FabId:=TaskOf(P,tkPrint3D).Id;
    Check(P.IndexOfLink(GateId,FabId)>=0,'modelo possui gate');
    Check(PJSetFabricationGate(P,False,Why),'desliga gate de plano existente');
    Check(P.IndexOfLink(GateId,FabId)<0,'remove dependencias futuras ao desligar');
    Check(P.Undo,'desfaz mudanca de gate'); Check(P.FabricationGate and (P.IndexOfLink(GateId,FabId)>=0),'gate e vinculos restaurados juntos');
    Check(PJSetFabricationGate(P,False,Why) and PJSetFabricationGate(P,True,Why),'religa gate');
    Check(P.IndexOfLink(GateId,FabId)>=0,'religa dependencias futuras');
    Complete(P.FindTask(FabId));
    Check(PJSetFabricationGate(P,False,Why),'desliga com tarefa concluida');
    Check(P.FindTask(FabId).State=tsDone,'nao altera tarefa concluida');
    Acyclic(P);
  finally DeleteFile(FN); L.Free; P.Free; end;
end;
begin
  try TestProgression; TestDecisionsAndRevision; TestOptionsAndGroups; TestTemplatesAndSheet; TestManualAndGateSwitch;
    Writeln('PASS: ',Passed,' checks (regras A01..A08, gate, origens, revisao, modelos e torno)');
  except on E: Exception do begin Writeln('FAIL: ',E.Message); Halt(1); end; end;
end.
