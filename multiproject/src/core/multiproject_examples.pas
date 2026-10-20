unit multiproject_examples;

{ Exemplo do README do MultiProject: construir um motor DC didatico.
  Usado pelo botao Demo da tela e pelos testes. As duracoes sao as do teste
  do cronograma (fase 3): o projeto termina na terca 03/11/2026 10:00. }

{$mode objfpc}{$H+}

interface

uses
  SysUtils, aiprojectduration, aitaskgraph, multiproject_types, multiproject_document;

procedure BuildMotorExample(P: TPJProject);

implementation

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
  P.ClearHistory;
  P.Modified := False;
end;

end.
