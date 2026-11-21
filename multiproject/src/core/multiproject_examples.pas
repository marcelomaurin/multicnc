unit multiproject_examples;

{ Exemplo do README do MultiProject: construir um motor DC didatico.
  Usado pelo botao Demo da tela e pelos testes. As duracoes sao as do teste
  do cronograma (fase 3): o projeto termina na terca 03/11/2026 10:00.

  Equipe e oficina (fase 7): tres pessoas e quatro maquinas. As maquinas com
  operador usam o calendario do projeto; so a impressora roda 24 h. Sem
  nivelar ha conflitos de proposito: Ana em tres pecas no mesmo dia, o laser
  e a Carla com duas fabricacoes ao mesmo tempo. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, aiprojectduration, aitaskgraph, multiproject_types, multiproject_document;

procedure BuildMotorExample(P: TPJProject);
procedure BuildMotorSeed(P: TPJProject);
procedure BuildMotorRuleExample(P: TPJProject);
procedure BuildRuleExample(P: TPJProject);

implementation

uses multiproject_rules;

procedure BuildMotorSeed(P: TPJProject);
var T: TPJTask; R: TPJResource;
begin
  P.Clear; P.Id:='P-MOTOR-DC'; P.Name:='Motor DC didatico';
  P.ObjectiveShort:='Construir um motor DC escovado de 12 V para aula';
  P.ObjectiveLong:='Carcaca impressa, eixo torneado, base MDF com logo e driver ponte H.';
  SetLength(P.ObjectiveSuccess,1); P.ObjectiveSuccess[0].Id:='OK-1';
  P.ObjectiveSuccess[0].Text:='3000 rpm +/- 10% a 12 V sem carga';
  P.ObjectiveSuccess[0].State:=csPending;
  P.StartDate:=EncodeDate(2026,10,26)+EncodeTime(8,0,0,0);
  T:=P.AddTask('',tkPart,'Carcaca do estator','Carcaca que fixa os imas'); T.Process:=prPrint3D;
  T.AddTechItem('material','PETG',''); T.AddTechItem('diametro_externo','60','mm');
  T.AddTechItem('temperatura','60','C'); T.AddTechItem('carga','5','N');
  T.AddCriterion('F-1','Suporta 60 C sem deformar');
  T:=P.AddTask('',tkPart,'Eixo do rotor','Eixo de aco 5 mm'); T.Process:=prLathe;
  T.AddTechItem('material','aco 1045',''); T.AddTechItem('diametro','5','mm');
  T.AddTechItem('comprimento','80','mm'); T.AddTechItem('rotacao','3000','rpm');
  T.AddTechItem('operacoes','Facear;Desbastar;Acabar;Chanfrar;Conferir cotas','');
  T:=P.AddTask('',tkPart,'Base em MDF','Base de fixacao do motor'); T.Process:=prLaserCut;
  T.AddTechItem('espessura','3','mm'); T.AddTechItem('gravacao','logo','');
  T:=P.AddTask('',tkElectronics,'Driver ponte H','Placa de acionamento do motor');
  T.AddTechItem('tensao','12','V'); T.AddTechItem('corrente','2','A');
  T.AddCriterion('F-1','Inverte o sentido de rotacao pelo sinal DIR');
  R:=P.AddResource('Ender-3',rtMachine); R.MachineType:=pmPrinter3D; R.CalendarName:=PJ_CAL_24H;
  R:=P.AddResource('Laser 10 W',rtMachine); R.MachineType:=pmLaser;
  R:=P.AddResource('Torno',rtMachine); R.MachineType:=pmLathe;
  P.ClearHistory; P.MarkSaved;
end;
procedure BuildMotorRuleExample(P: TPJProject);
begin BuildMotorSeed(P); BuildRuleExample(P); end;
procedure BuildRuleExample(P: TPJProject);
var I,J,N,Pass: Integer; Why: string; HasGate: Boolean;
begin
  { Construct the sample DAG through the rules, then reset all approvals and
    artifacts: a distributed example never claims real completed work. }
  for Pass:=1 to 10 do
  begin
    for I:=0 to P.Count-1 do
    begin
      P[I].State:=tsDone;
      P[I].Artifact.Hash:='example-only'; P[I].Artifact.Status:='valid';
      for J:=0 to High(P[I].FuncSpec) do P[I].FuncSpec[J].State:=csPassed;
    end;
    N:=PJGenerateSuggestions(P,Why);
    if N<0 then raise EPJError.Create(Why);
    if N=0 then Break;
    if not PJDecideSuggestions(P,[],True,Why) then raise EPJError.Create(Why);
  end;
  for I:=0 to P.Count-1 do
  begin
    P[I].State:=tsPlanned; P[I].Artifact:=Default(TPJArtifact);
    P[I].Artifact.Status:='none'; P[I].Artifact.Size:=-1; P[I].Artifact.MTime:=-1;
    for J:=0 to High(P[I].FuncSpec) do begin P[I].FuncSpec[J].State:=csPending; P[I].FuncSpec[J].Evidence:=''; end;
  end;
  HasGate:=False;
  for I:=0 to P.Count-1 do if P[I].Origin.Rule='A05' then begin P[I].State:=tsSuggested; HasGate:=True; end;
  if HasGate and not PJDecideSuggestions(P,[],True,Why) then raise EPJError.Create(Why);
  P.ClearHistory; P.MarkSaved;
end;

procedure BuildMotorExample(P: TPJProject);
var
  Pj, Fab, Fim: TPJTask;

  function Add(const AParent: string; AKind: TPJTaskKind; const AName, AShort, ADur: string;
    AProcess: TPJProcess = prNone): TPJTask;
  var Err: string;
  begin
    Result := P.AddTask(AParent, AKind, AName, AShort);
    Result.Process := AProcess;
    if not P.SetDurationText(Result.Id, ADur, Err) then raise EPJError.Create(Err);
  end;

  function Res(const AName: string; AType: TPJResourceType; const ARole: string;
    AMachine: TPJMachineType = pmNone; const ACal: string = ''): TPJResource;
  begin
    Result := P.AddResource(AName, AType);
    Result.Role := ARole;
    Result.MachineType := AMachine;
    Result.CalendarName := ACal;
    if AType = rtMachine then Result.Group := 'Oficina' else Result.Group := 'Equipe';
  end;

  procedure A(const ATask, AResource: string; AUnits: Double = 1);
  var Err: string;
  begin
    if not P.Assign(ATask, AResource, AUnits, Err) then raise EPJError.Create(Err);
  end;

  { varios recursos de uma vez: atribuicao inicial, a duracao nao muda }
  procedure AS_(const ATask, AText: string);
  var Err: string;
  begin
    if not P.SetResourcesText(ATask, AText, Err) then raise EPJError.Create(Err);
  end;

  procedure Cost(const AName: string; ARate, APerUse: Double; AUnitCost: Double = 0);
  var R: TPJResource;
  begin
    R := P.FindResource(AName);
    R.Rate := ARate;
    R.PerUse := APerUse;
    R.UnitCost := AUnitCost;
  end;

  procedure L(const A, B: string; Artifact: Boolean = True);
  var Err: string;
  begin
    if not P.AddLink(A, B, atlFS, AINoLag, Artifact, Err) then raise EPJError.Create(Err);
  end;

var T: TPJTask;
begin
  P.Clear;
  P.Id := 'P-2026-0001';
  P.Name := 'Motor DC didatico';
  P.Revision := 'A';
  P.ObjectiveShort := 'Construir um motor DC escovado de 12 V para aula';
  P.ObjectiveLong := 'Motor com carcaca impressa, eixo torneado, base em MDF cortada a laser ' +
    'com o logo gravado e driver ponte H proprio.';
  P.ObjectiveScope := 'Uma unidade funcional e o dossie de fabricacao.';
  SetLength(P.ObjectiveSuccess, 1);
  P.ObjectiveSuccess[0].Id := 'OK-1';
  P.ObjectiveSuccess[0].Text := '3000 rpm +/- 10% a 12 V sem carga';
  P.ObjectiveSuccess[0].State := csPending;
  P.StartDate := EncodeDate(2026, 10, 26) + EncodeTime(8, 0, 0, 0);
  P.ResetCalendars;

  Pj := Add('', tkSummary, 'Projeto', 'Pecas e placa do motor', '0d');
  T := Add(Pj.Id, tkPart, 'Carcaca do estator', 'Carcaca que fixa os imas', '1d', prPrint3D);
  T.AddTechItem('material', 'PETG', '');
  T.AddTechItem('diametro_externo', '60', 'mm');
  T.TechText := 'Encaixe H7 para o rolamento 608.';
  T.AddCriterion('F-1', 'Suporta 60 C sem deformar');
  T := Add(Pj.Id, tkPart, 'Eixo do rotor', 'Eixo de aco 5 mm', '4h', prLathe);
  T.AddTechItem('material', 'aco 1045', '');
  T.AddTechItem('diametro', '5', 'mm');
  T := Add(Pj.Id, tkPart, 'Base em MDF', 'Base de fixacao do motor', '4h', prLaserCut);
  T.AddTechItem('espessura', '3', 'mm');
  T := Add(Pj.Id, tkElectronics, 'Driver ponte H', 'Placa de acionamento do motor', '2d');
  T.AddTechItem('tensao', '12', 'V');
  T.AddTechItem('corrente', '2', 'A');
  T.AddCriterion('F-1', 'Inverte o sentido de rotacao pelo sinal DIR');

  Add('', tkAssembly, 'Montagem virtual', 'Unir as pecas e a placa no MultiAssembly', '1d');
  T := Add('', tkValidation, 'Validacao', 'Estudo termico e estrutural no MultiPhysics', '1d');
  T.AddCriterion('F-1', 'Temperatura da carcaca abaixo de 60 C a 2 A');
  Add('', tkMilestone, 'Liberado para fabricacao', 'Validacao aprovada', '0d');

  Fab := Add('', tkSummary, 'Fabricacao', 'Pecas e placa fabricadas', '0d');
  Add(Fab.Id, tkPrint3D, 'Imprimir carcaca', 'PETG na Ender-3', '14eh');
  Add(Fab.Id, tkLathe, 'Tornear eixo', 'Folha de processo do eixo', '4h');
  Add(Fab.Id, tkLaserCut, 'Cortar base', 'MDF 3 mm no laser', '2h');
  Add(Fab.Id, tkLaserArt, 'Gravar logo', 'Logo na base de MDF', '1h');
  Add(Fab.Id, tkPCBFab, 'Fabricar placa', 'Driver no LaserPCB', '4h');

  Add('', tkPhysicalAssembly, 'Montagem fisica', 'Montar o motor pelo manual', '4h');
  T := Add('', tkFunctionalTest, 'Teste funcional', 'Medir rotacao e corrente', '2h');
  T.AddCriterion('OK-1', '3000 rpm +/- 10% a 12 V sem carga');
  Fim := Add('', tkMilestone, 'Objetivo concluido', 'Motor funcionando', '0d');

  { IDs: T-0001 Projeto; T-0002..T-0005 pecas e placa; T-0006 montagem;
    T-0007 validacao; M-0008 liberado; T-0009 Fabricacao; T-0010..T-0014
    fabricacoes; T-0015 montagem fisica; T-0016 teste; M-0017 fim }
  L('T-0002', 'T-0006'); L('T-0003', 'T-0006'); L('T-0004', 'T-0006'); L('T-0005', 'T-0006');
  L('T-0006', 'T-0007'); L('T-0007', 'M-0008', False);
  L('M-0008', 'T-0010', False); L('M-0008', 'T-0011', False);
  L('M-0008', 'T-0012', False); L('M-0008', 'T-0014', False);
  L('T-0012', 'T-0013');
  L('T-0010', 'T-0015'); L('T-0011', 'T-0015'); L('T-0013', 'T-0015'); L('T-0014', 'T-0015');
  L('T-0015', 'T-0016', False); L('T-0016', Fim.Id, False);

  { equipe e oficina: R-001..R-008 }
  Res('Ana', rtPerson, 'Projetista mecanica').Email := 'ana@oficina.local';
  Res('Bruno', rtPerson, 'Eletronica').Email := 'bruno@oficina.local';
  Res('Carla', rtPerson, 'Fabricacao').Email := 'carla@oficina.local';
  Res('Ender-3', rtMachine, '', pmPrinter3D, PJ_CAL_24H).Equipment := 'Ender-3';
  Res('Laser 10 W', rtMachine, '', pmLaser).Equipment := 'Laser 10 W';
  Res('Torno', rtMachine, '', pmLathe);
  Res('CNC Router', rtMachine, '', pmRouter).Equipment := 'CNC Router';
  Res('PETG', rtMaterial, '').MaterialUnit := 'kg';
  { custos de referencia (R$): hora da equipe, hora e preparacao das maquinas }
  Cost('Ana', 90, 0); Cost('Bruno', 90, 0); Cost('Carla', 70, 0);
  Cost('Ender-3', 3, 5); Cost('Laser 10 W', 12, 5); Cost('Torno', 25, 15);
  Cost('CNC Router', 20, 10); Cost('PETG', 0, 0, 120);
  A('T-0002', 'Ana'); A('T-0003', 'Ana'); A('T-0004', 'Ana');
  A('T-0005', 'Bruno');
  A('T-0006', 'Ana'); AS_('T-0007', 'Ana; Bruno[50%]');
  A('T-0010', 'Ender-3'); A('T-0010', 'PETG', 0.12);
  A('T-0011', 'Torno'); A('T-0011', 'Carla');
  A('T-0012', 'Laser 10 W'); A('T-0012', 'Carla');
  A('T-0013', 'Laser 10 W'); A('T-0013', 'Carla');
  A('T-0014', 'Laser 10 W'); A('T-0014', 'Bruno');
  A('T-0015', 'Carla');
  AS_('T-0016', 'Bruno; Carla[50%]');
  P.ClearHistory;
  P.Modified := False;
end;

end.
