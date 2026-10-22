program test_multiproject_ui;

{ Fase 4 (item 4.8): tela do MultiProject sob Xvfb.
  Abre o exemplo do motor, confere as tres vistas (Gantt, Rede, Quadro),
  a pagina da tarefa, edicao na tabela (aceita e recusada), inserir/recuar/
  desfazer, vinculo pela rede, movimento recusado no quadro, filtros e
  agrupamento, salvar/abrir, layout em 1024 x 768 e que fechar a janela
  encerra o aplicativo (Application.CreateForm).
  Opcional: --shot <prefixo> salva capturas (precisa de "import" do ImageMagick).
  Linux: xvfb-run -a ./test_multiproject_ui }

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, Classes, SysUtils, Forms, Controls, Process,
  aiprojectduration, aiganttview, ainetworkview, aiboardview,
  multiproject_types, multiproject_document, multiproject_views, multiproject_main;

type
  TFailFast = class
    procedure OnException(Sender: TObject; E: Exception);
  end;

var
  Passed, Failed: Integer;
  F: TMultiProjectForm;
  ShotPrefix: string;

procedure TFailFast.OnException(Sender: TObject; E: Exception);
begin
  { sem dialogo modal no teste: excecao na tela e falha imediata }
  Writeln('EXCECAO NA TELA: ', E.ClassName, ': ', E.Message);
  Halt(2);
end;

procedure Check(Cond: Boolean; const What: string);
begin
  if Cond then Inc(Passed)
  else
  begin
    Inc(Failed);
    Writeln('FALHOU: ', What);
  end;
end;

procedure Pump;
var I: Integer;
begin
  for I := 1 to 5 do
  begin
    Application.ProcessMessages;
    Sleep(10);
  end;
end;

procedure Shot(const AName: string);
var Output: string;
begin
  if ShotPrefix = '' then Exit;
  Pump;
  F.Repaint;
  Pump;
  RunCommand('import', ['-window', 'root', ShotPrefix + AName + '.png'], Output);
end;

function GanttRowOf(const AId: string): Integer;
begin
  Result := F.Gantt.IndexOfId(AId);
end;

procedure TestExample;
begin
  F.LoadExample;
  Pump;
  Check(F.Gantt.RowCount = 17, Format('Gantt com as 17 tarefas: %d', [F.Gantt.RowCount]));
  Check(F.Network.NodeCount = 15, Format('Rede com as 15 folhas: %d', [F.Network.NodeCount]));
  Check(F.Board.CardCount = 15, Format('Quadro com 15 cartoes: %d', [F.Board.CardCount]));
  Check(F.Gantt.Row(GanttRowOf('T-0005')).Critical, 'driver critico no Gantt');
  Check(not F.Gantt.Row(GanttRowOf('T-0002')).Critical, 'carcaca nao critica');
  Check(F.Gantt.Row(GanttRowOf('T-0001')).Kind = agbSummary, 'resumo Projeto');
  Check(F.Gantt.Row(GanttRowOf('M-0017')).Kind = agbMilestone, 'marco final');
  Check(F.Gantt.Row(GanttRowOf('T-0006')).Cells[GC_PRED] = 'T-0002;T-0003;T-0004;T-0005', 'coluna de predecessoras');
  Check(Pos('03/11/2026 10:00', F.InfoLabel.Caption) > 0, 'rodape com o termino previsto: ' + F.InfoLabel.Caption);
  Check(F.ChainList.Items.Count = 1, 'lista de cadeias');
  Shot('01_gantt');
end;

procedure TestSelectionAndTaskPage;
begin
  F.SelectTask('T-0002');
  Pump;
  Check(F.Gantt.Row(F.Gantt.Selected).Id = 'T-0002', 'selecao no Gantt');
  Check(F.Network.Node(F.Network.Selected).Id = 'T-0002', 'selecao sincronizada na rede');
  Check(F.Board.Card(F.Board.Selected).Id = 'T-0002', 'selecao sincronizada no quadro');
  Check(Pos('em paralelo com', F.InfoLabel.Caption) > 0, 'rodape mostra cadeia x paralelo');
  Check(F.OpenToolButton.Caption = 'Abrir no MultiCAD', 'botao com o nome da ferramenta: ' + F.OpenToolButton.Caption);
  F.ShowStep(PAGE_TASK);
  Pump;
  Check(F.TName.Text = 'Carcaca do estator', 'pagina da tarefa: nome');
  Check(F.TShort.Text = 'Carcaca que fixa os imas', 'pagina da tarefa: descricao curta');
  Check(F.TTechGrid.Cells[0, 1] = 'material', 'pagina da tarefa: especificacao tecnica');
  Check(F.TFuncGrid.Cells[0, 1] = 'Suporta 60 C sem deformar', 'pagina da tarefa: criterio de aceite');
  Check(F.TDuration.Text = '1d', 'pagina da tarefa: duracao');
  Shot('02_tarefa');
  { aplicar pela pagina: muda o nome e a duracao num passo de desfazer }
  F.TName.Text := 'Carcaca do estator v2';
  F.TDuration.Text := '2d';
  F.TConstraint.ItemIndex := 2;   // SNET sem data
  F.TConstraintDate.Text := '';
  F.TaskApplyForTest;
  Check(Pos('precisa de data', F.StatusText) > 0, 'restricao sem data recusada: ' + F.StatusText);
  F.TConstraint.ItemIndex := 0;
  F.TaskApplyForTest;
  Check((F.Doc.FindTask('T-0002').Name = 'Carcaca do estator v2') and (F.Doc.FindTask('T-0002').Duration.Minutes = 960),
    'aplicar a pagina da tarefa');
  Check(F.Doc.UndoDescription = 'Editar tarefa', 'aplicar e um passo de desfazer');
  F.Doc.Undo;
  F.RefreshAll;
  F.ShowStep(1);
end;

procedure TestGanttEditing;
var R: Integer;
begin
  R := GanttRowOf('T-0005');
  F.Gantt.EditCell(R, GC_DUR);
  Check(F.Gantt.Editing, 'editor da duracao aberto');
  F.Gantt.Editor.Text := '3 d';
  F.Gantt.FinishEdit(True);
  Pump;
  Check(F.Doc.FindTask('T-0005').Duration.Minutes = 3 * 480, 'duracao editada na tabela');
  Check(Pos('04/11/2026', F.InfoLabel.Caption) > 0, 'cronograma recalculado depois da edicao: ' + F.InfoLabel.Caption);
  R := GanttRowOf('T-0005');
  Check(F.Gantt.Row(R).Cells[GC_DUR] = '3d', 'celula normalizada');
  F.Gantt.EditCell(R, GC_DUR);
  F.Gantt.Editor.Text := '3x';
  F.Gantt.FinishEdit(True);
  Pump;
  Check((F.Doc.FindTask('T-0005').Duration.Minutes = 3 * 480) and (Pos('T-0005', F.StatusText) > 0),
    'duracao invalida recusada com a mensagem: ' + F.StatusText);
  R := GanttRowOf('T-0002');
  F.Gantt.EditCell(R, GC_PRED);
  F.Gantt.Editor.Text := 'T-0016';
  F.Gantt.FinishEdit(True);
  Pump;
  Check(Pos('ciclo', F.StatusText) > 0, 'predecessora que fecha ciclo recusada: ' + F.StatusText);
  F.Doc.Undo;
  F.RefreshAll;
  Check(F.Doc.FindTask('T-0005').Duration.Minutes = 960, 'desfazer a duracao');
end;

procedure TestCommands;
var N: Integer; Id: string;
begin
  N := F.Doc.Count;
  F.SelectTask('T-0004');
  F.KindCombo.ItemIndex := F.KindCombo.Items.IndexOf(KindCaption(tkElectronics));
  F.InsertClickForTest;
  Check(F.Doc.Count = N + 1, 'inserir tarefa');
  Id := F.SelectedTask.Id;
  Check((F.Doc.IndexOfId(Id) = F.Doc.IndexOfId('T-0004') + 1) and (F.SelectedTask.Kind = tkElectronics),
    'nova tarefa abaixo da selecionada, do tipo escolhido');
  Check(F.Doc.FindTask(Id).Level = 2, 'nova tarefa no nivel da selecionada');
  F.IndentClickForTest;
  Check(F.Doc.FindTask(Id).Level = 3, 'recuar pela tela');
  F.UndoClickForTest;
  F.UndoClickForTest;
  Check(F.Doc.Count = N, 'desfazer a insercao');
end;

procedure TestNetworkAndBoard;
var A, B, C: Integer; Accept: Boolean; Reason: string;
begin
  F.ShowView(VIEW_NETWORK);
  Pump;
  Shot('03_rede');
  A := F.Network.IndexOfId('T-0002');
  B := F.Network.IndexOfId('T-0010');
  F.Network.OnCreateLink(F.Network, A, B, False);
  Pump;
  Check(F.Doc.IndexOfLink('T-0002', 'T-0010') >= 0, 'vinculo criado arrastando na rede');
  A := F.Network.IndexOfId('T-0016');
  B := F.Network.IndexOfId('T-0002');
  F.Network.OnCreateLink(F.Network, A, B, False);
  Pump;
  Check(Pos('ciclo', F.StatusText) > 0, 'ciclo recusado na rede: ' + F.StatusText);
  F.Doc.Undo;
  F.RefreshAll;
  F.ShowView(VIEW_BOARD);
  Pump;
  Shot('04_quadro');
  C := F.Board.IndexOfId('T-0006');
  Check(not F.Board.TryMoveCard(C, 4, Reason) and (Pos('espera', Reason) > 0), 'quadro recusa concluir com predecessora aberta: ' + Reason);
  C := F.Board.IndexOfId('T-0003');
  Accept := F.Board.TryMoveCard(C, 2, Reason);
  Pump;
  Check(Accept and (F.Doc.FindTask('T-0003').State = tsInProgress), 'quadro move para em andamento');
  F.Doc.Undo;
  F.RefreshAll;
  F.ShowView(VIEW_GANTT);
end;

procedure TestFilters;
var I, Crit: Integer;
begin
  F.FilterCombo.ItemIndex := 1;
  F.FilterCombo.OnChange(F.FilterCombo);
  Pump;
  Crit := 0;
  for I := 0 to F.Gantt.RowCount - 1 do
    if F.Gantt.Row(I).Critical then Inc(Crit);
  Check((Crit = 9) and (F.Gantt.RowCount = 11), Format('filtro criticas: %d linhas, %d criticas', [F.Gantt.RowCount, Crit]));
  F.FilterCombo.ItemIndex := 0;
  F.GroupCombo.ItemIndex := 1;
  F.FilterCombo.OnChange(F.FilterCombo);
  Pump;
  Check(F.Gantt.Row(0).Id = '', 'agrupar por tipo cria linha de grupo');
  Check(F.Gantt.RowCount > 15, 'grupos + tarefas');
  F.GroupCombo.ItemIndex := 0;
  F.FilterCombo.OnChange(F.FilterCombo);
  Pump;
  Check(F.Gantt.RowCount = 17, 'volta ao EAP');
end;

procedure TestResources;
var R, B, Row: Integer; Reason: string; I: Integer; Found: Boolean;
begin
  F.LoadExample;
  Pump;
  Check(Pos('Superalocacao:', F.InfoLabel.Caption) > 0, 'rodape mostra a superalocacao: ' + F.InfoLabel.Caption);
  R := GanttRowOf('T-0003');
  Check(Pos('Ana', F.Gantt.Row(R).Cells[GC_RES]) = 1, 'coluna Recursos: ' + F.Gantt.Row(R).Cells[GC_RES]);
  Check(Pos('(!)', F.Gantt.Row(R).Cells[GC_RES]) > 0, 'coluna Recursos marca o conflito');
  Check(Pos('(!)', F.Gantt.Row(GanttRowOf('T-0005')).Cells[GC_RES]) = 0, 'sem marca sem conflito');
  { etapa 4 abre a vista Equipe }
  F.ShowStep(3);
  Pump;
  Check((F.CurrentView = VIEW_TEAM) and F.Team.Visible, 'etapa Recursos abre a vista Equipe');
  Check(F.Team.RowCount = 8, Format('Equipe: 7 recursos + sem recurso (%d)', [F.Team.RowCount]));
  Check(F.Team.Row(0).Overallocated and (F.Team.Row(0).Title = 'Ana'), 'Ana em vermelho');
  Check(not F.Team.Row(F.Team.IndexOfRow('R-002')).Overallocated, 'Bruno sem conflito');
  Check(F.Team.OverloadBandCount >= 3, Format('faixas de conflito (%d)', [F.Team.OverloadBandCount]));
  Check(F.Team.LanesOf(0) = 3, Format('tres tarefas da Ana empilhadas (%d)', [F.Team.LanesOf(0)]));
  Found := False;
  for I := 0 to F.Team.BarCount - 1 do
    if (F.Team.Bar(I).Id = 'T-0003') and F.Team.Bar(I).Overloaded then Found := True;
  Check(Found, 'barra em conflito marcada');
  Check(F.ResList.Items.Count = 8, 'planilha com 8 recursos');
  F.ResList.ItemIndex := 0;
  F.ResList.OnClick(F.ResList);
  Check(F.RName.Text = 'Ana', 'recurso selecionado na pagina');
  Check(Pos('Superalocado', F.ResInfo.Caption) > 0, 'pagina mostra o conflito: ' + F.ResInfo.Caption);
  Shot('06_equipe');
  { reatribuir arrastando: aceito para outra pessoa, recusado para maquina errada }
  B := -1;
  for I := 0 to F.Team.BarCount - 1 do
    if F.Team.Bar(I).Id = 'T-0004' then B := I;
  Row := F.Team.IndexOfRow('R-003');
  Check(F.Team.TryReassign(B, Row, Reason), 'reatribuir T-0004 para Carla: ' + Reason);
  Pump;
  Check(F.Doc.ResourcesText('T-0004') = 'Carla', 'documento reatribuido: ' + F.Doc.ResourcesText('T-0004'));
  Check(SameText(F.Doc.UndoDescription, 'Reatribuir recurso'), 'reatribuir e um passo');
  B := -1;
  for I := 0 to F.Team.BarCount - 1 do
    if F.Team.Bar(I).Id = 'T-0010' then B := I;
  Check(not F.Team.TryReassign(B, F.Team.IndexOfRow('R-005'), Reason) and (Pos('Impressora 3D', Reason) > 0),
    'maquina incompativel recusada: ' + Reason);
  Check(StringReplace(F.Doc.ResourcesText('T-0010'), ',', '.', [rfReplaceAll]) = 'Ender-3; PETG[0.12 kg]', 'recusa nao altera');
  F.Doc.Undo;
  F.RefreshAll;
  { pagina da tarefa: recursos e conflito }
  F.SelectTask('T-0012');
  F.ShowStep(PAGE_TASK);
  Pump;
  Check(F.TResEdit.Text = 'Laser 10 W; Carla', 'recursos na pagina da tarefa: ' + F.TResEdit.Text);
  Check(Pos('Conflito', F.TResInfo.Caption) > 0, 'pagina da tarefa avisa o conflito: ' + F.TResInfo.Caption);
  Found := False;
  for I := 0 to F.TResCombo.Items.Count - 1 do
    if Pos('Ender-3', F.TResCombo.Items[I]) = 1 then Found := True;
  Check(not Found and (F.TResCombo.Items.Count > 0), 'combo so com recursos compativeis (sem impressora no corte)');
  F.TResEdit.Text := 'Laser 10 W; Zeca';
  F.TaskResApplyForTest;
  Check((Pos('Zeca', F.StatusText) > 0) and (F.Doc.ResourcesText('T-0012') = 'Laser 10 W; Carla'),
    'nome desconhecido recusado: ' + F.StatusText);
  F.TResEdit.Text := 'Laser 10 W; Ana[50%]';
  F.TaskResApplyForTest;
  Check(F.Doc.ResourcesText('T-0012') = 'Laser 10 W; Ana[50%]', 'recursos aplicados pela pagina');
  F.Doc.Undo;
  F.RefreshAll;
  { editar a coluna Recursos no Gantt }
  F.ShowStep(1);
  R := GanttRowOf('T-0003');
  F.Gantt.EditCell(R, GC_RES);
  F.Gantt.Editor.Text := F.Gantt.Row(R).Cells[GC_RES] + '; Bruno[25%]';
  F.Gantt.FinishEdit(True);
  Pump;
  Check(F.Doc.ResourcesText('T-0003') = 'Ana; Bruno[25%]', 'coluna Recursos editada (marca ignorada): ' +
    F.Doc.ResourcesText('T-0003'));
  F.Doc.Undo;
  F.RefreshAll;
  { nivelar e limpar }
  F.ShowStep(4);
  F.LevelForTest(False);
  Pump;
  Check(F.Sched.OverloadCount = 0, 'nivelar resolve os conflitos');
  Check(Pos('sem superalocacao', F.StatusText) > 0, 'status do nivelamento: ' + F.StatusText);
  Check(Pos('Superalocacao', F.InfoLabel.Caption) = 0, 'rodape sem superalocacao');
  F.ShowView(VIEW_TEAM);
  Pump;
  Check(F.Team.OverloadBandCount = 0, 'Equipe sem faixas de conflito');
  Shot('07_nivelado');
  F.ClearLevelForTest;
  Pump;
  Check(F.Sched.OverloadCount > 0, 'limpar o nivelamento traz os conflitos de volta');
  { editar recurso pela planilha }
  F.ShowStep(3);
  for I := 0 to F.ResList.Items.Count - 1 do
    if Pos('Ana  -', F.ResList.Items[I]) > 0 then F.ResList.ItemIndex := I;
  F.ResList.OnClick(F.ResList);
  F.RUnits.Text := '300';
  F.ResApplyForTest;
  Check(Abs(F.Doc.FindResource('Ana').MaxUnits - 3) < 1E-6, 'unidades maximas editadas');
  Check(not F.Sched.ResourceOverallocated('Ana'), 'Ana com 300% sem conflito');
  F.RUnits.Text := 'muito';
  F.ResApplyForTest;
  Check(Pos('Unidades', F.StatusText) > 0, 'unidades invalidas recusadas');
  Shot('08_recursos');
  F.Doc.Undo;
  F.RefreshAll;
  F.ShowStep(1);
end;

procedure TestFile;
var FN: string;
begin
  FN := IncludeTrailingPathDelimiter(GetTempDir(False)) + 'multiproject_ui_test.mproj';
  F.SaveFile(FN);
  Check(FileExists(FN) and not F.Doc.Modified, 'salvar');
  F.NewProject;
  Check(F.Doc.Count = 0, 'novo projeto vazio');
  F.OpenFile(FN);
  Check((F.Doc.Count = 17) and (F.Doc.LinkCount = 17), 'abrir o arquivo salvo');
  DeleteFile(FN);
end;

procedure TestLayout;
begin
  F.SetBounds(0, 0, 1024, 768);
  Pump;
  Check(F.Width >= 1000, 'janela aceita 1024 x 768');
  Check((F.OpenToolButton.Left + F.OpenToolButton.Width <= F.FooterPanel.ClientWidth) and
    (F.ValidateButton.Left > F.StatusLabel.Left), 'botoes do rodape visiveis em 1024 x 768');
  Check(F.Pages.Width = 336, 'painel de propriedades com 336 px');
  Check(F.Gantt.Width > 300, Format('area central utilizavel: %d px', [F.Gantt.Width]));
  Shot('05_1024');
end;

var I: Integer;
begin
  Passed := 0; Failed := 0;
  ShotPrefix := '';
  for I := 1 to ParamCount - 1 do
    if ParamStr(I) = '--shot' then ShotPrefix := ParamStr(I + 1);
  Application.Initialize;
  Application.OnException := @TFailFast(nil).OnException;
  Application.CreateForm(TMultiProjectForm, F);
  F.SetBounds(0, 0, 1360, 860);
  F.Show;
  Pump;
  TestExample;
  TestSelectionAndTaskPage;
  TestGanttEditing;
  TestCommands;
  TestNetworkAndBoard;
  TestFilters;
  TestResources;
  TestFile;
  TestLayout;
  { fechar a janela principal encerra o aplicativo }
  F.Doc.Modified := False;
  F.Close;
  Pump;
  Check(Application.Terminated, 'fechar a janela encerra o aplicativo');
  if Failed = 0 then
    Writeln(Format('PASS: %d checks (Gantt, rede, quadro, equipe, recursos, nivelamento, pagina da tarefa, edicao, filtros, arquivo, 1024x768)', [Passed]))
  else
  begin
    Writeln(Format('FAIL: %d de %d checks', [Failed, Passed + Failed]));
    Halt(1);
  end;
end.
