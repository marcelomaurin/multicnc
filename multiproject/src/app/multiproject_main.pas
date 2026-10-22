unit multiproject_main;

{ Tela do MultiProject no padrao da MultiSuite (multiproject/docs/LAYOUT.md):
  cabecalho, lateral com 7 etapas, barra da vista, vista central (Gantt, Rede,
  Quadro), painel de propriedades de 336 px e rodape com Validar / Gerar
  tarefas / Abrir na ferramenta.

  As vistas sao componentes genericos do CHATGPT (aiganttview, ainetworkview,
  aiboardview, airesourceview); o calculo e do nucleo (multiproject_*). Esta
  unit so liga eventos, campos e comandos. Fases futuras aparecem
  desabilitadas com a fase em que entram (Gerar tarefas: 6;
  acompanhamento e relatorios: 8).

  Recursos (fase 7): etapa 4 com a planilha de pessoas, maquinas e materiais
  e a importacao das maquinas do MultiCNC; secao 8 da pagina da tarefa com as
  atribuicoes; coluna Recursos no Gantt; vista Equipe com a superalocacao e
  arraste para reatribuir; nivelar e limpar o nivelamento na etapa 5. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, StrUtils, Math, DateUtils, Forms, Controls, Graphics, StdCtrls,
  ExtCtrls, ComCtrls, Grids, Dialogs, LCLType,
  multisuite_controls, multisuite_icons,
  aiprojectduration, aitaskgraph, aiworkcalendar, aicpmscheduler,
  airesourceload, aiganttview, ainetworkview, aiboardview, airesourceview,
  multiproject_types, multiproject_document, multiproject_json, multiproject_graph,
  multiproject_schedule, multiproject_states, multiproject_examples, multiproject_views,
  multiproject_resources, multiproject_kinds, multiproject_artifacts,
  multiproject_taskctx, multiproject_rules, multiproject_templates, multiproject_lathe, multisuite_types, multisuite_registry, multisuite_launcher, multisuite_paths;

const
  PJ_APP_VERSION = '0.2.0.0';
  PJ_STEPS: array[0..6] of string = ('1  Objetivo', '2  Tarefas', '3  Relacoes',
    '4  Recursos', '5  Cronograma', '6  Acompanhar', '7  Relatorios');
  PAGE_TASK = 7;
  VIEW_GANTT = 0; VIEW_NETWORK = 1; VIEW_BOARD = 2; VIEW_TEAM = 3;

type
  TMultiProjectForm = class(TForm)
  private
    FUpdating: Boolean;
    ArtifactTimer: TTimer;
    ArtifactPathEdit: TEdit;
    OpenCNCButton: TSuiteButton;
    LatheButton: TSuiteButton;
    SidebarBody: TPanel;
    ChainTitleLabel: TLabel;
    FCheckingArtifacts: Boolean;
    FSelectedId: string;
    FIcons: array[TPJTaskKind] of TBitmap;
    FRefreshQueued: Boolean;
    Header: TSuiteHeader;
    WorkPanel, BarPanel: TPanel;
    procedure CheckArtifacts(Sender: TObject);
    procedure OpenToolClick(Sender: TObject);
    procedure LinkArtifactClick(Sender: TObject);
    procedure OpenCNCClick(Sender: TObject);
    procedure GenerateClick(Sender: TObject);
    procedure RefreshSuggestions;
    procedure SuggestionOpen(Sender: TObject);
    procedure AcceptSuggestions(Sender: TObject);
    procedure RejectSuggestions(Sender: TObject);
    procedure DecideSuggestions(Accept: Boolean);
    procedure TemplateClick(Sender: TObject);
    procedure LatheSheetClick(Sender: TObject);
    procedure BuildSidebar(S: TPanel);
    procedure BuildBar;
    procedure BuildFooter;
    procedure BuildPages;
    procedure BuildObjectivePage(S: TScrollBox);
    procedure BuildTasksPage(S: TScrollBox);
    procedure BuildRelationsPage(S: TScrollBox);
    procedure BuildResourcesPage(S: TScrollBox);
    procedure BuildSchedulePage(S: TScrollBox);
    procedure BuildTrackPage(S: TScrollBox);
    procedure BuildReportsPage(S: TScrollBox);
    procedure BuildTaskPage(S: TScrollBox);
    function Btn(AParent: TWinControl; const AText: string; X, Y, W: Integer;
      AIcon: TSuiteIconKind; AHandler: TNotifyEvent): TSuiteButton;
    function Lbl(AParent: TWinControl; const AText: string; X, Y, W, H: Integer): TLabel;
    function Section(AParent: TWinControl; const AText: string; Y: Integer): TLabel;
    function Edit(AParent: TWinControl; const ACaption: string; Y: Integer): TEdit;
    function Combo(AParent: TWinControl; const ACaption: string; Y: Integer): TComboBox;
    function Memo(AParent: TWinControl; const ACaption: string; Y, H: Integer): TMemo;
    procedure FormKey(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormResizeUI(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure NavClick(Sender: TObject);
    procedure ViewClick(Sender: TObject);
    procedure FitClick(Sender: TObject);
    procedure ZoomInClick(Sender: TObject);
    procedure ZoomOutClick(Sender: TObject);
    procedure FilterChange(Sender: TObject);
    procedure NewClick(Sender: TObject);
    procedure OpenClick(Sender: TObject);
    procedure SaveClick(Sender: TObject);
    procedure DemoClick(Sender: TObject);
    procedure ValidateClick(Sender: TObject);
    procedure ChainClick(Sender: TObject);
    procedure GanttSelect(Sender: TObject; ARow: Integer);
    procedure GanttDblClick(Sender: TObject; ARow: Integer);
    procedure GanttEdited(Sender: TObject; ARow, ACol: Integer; var AText: string; var Accept: Boolean);
    function GanttWorkingDay(Sender: TObject; ADay: TDateTime): Boolean;
    procedure GanttIcon(Sender: TObject; ACanvas: TCanvas; ARow: Integer; const ARect: TRect);
    procedure NetSelect(Sender: TObject; ANode: Integer);
    procedure NetDblClick(Sender: TObject; ANode: Integer);
    procedure NetLink(Sender: TObject; AFromNode, AToNode: Integer; AAlt: Boolean);
    procedure BoardSelect(Sender: TObject; ACard: Integer);
    procedure BoardDblClick(Sender: TObject; ACard: Integer);
    procedure BoardMove(Sender: TObject; ACard, ANewColumn: Integer; var Accept: Boolean; var Reason: string);
    procedure TeamSelect(Sender: TObject; ABar: Integer);
    procedure TeamDblClick(Sender: TObject; ABar: Integer);
    procedure TeamReassign(Sender: TObject; ABar, ANewRow: Integer; var Accept: Boolean; var Reason: string);
    { objetivo }
    procedure ObjectiveApply(Sender: TObject);
    procedure LoadObjectivePage;
    { tarefas }
    procedure InsertClick(Sender: TObject);
    procedure InsertSummaryClick(Sender: TObject);
    procedure InsertMilestoneClick(Sender: TObject);
    procedure IndentClick(Sender: TObject);
    procedure OutdentClick(Sender: TObject);
    procedure UpClick(Sender: TObject);
    procedure DownClick(Sender: TObject);
    procedure DeleteClick(Sender: TObject);
    procedure UndoClick(Sender: TObject);
    procedure RedoClick(Sender: TObject);
    procedure TaskPageClick(Sender: TObject);
    { relacoes }
    procedure LoadRelationsPage;
    procedure RelPredApply(Sender: TObject);
    procedure RelAddClick(Sender: TObject);
    procedure RelRemoveClick(Sender: TObject);
    procedure LinkNextClick(Sender: TObject);
    { recursos / calendarios }
    procedure LoadResourcesPage;
    procedure CalSelect(Sender: TObject);
    procedure CalAddExceptionClick(Sender: TObject);
    procedure CalRemoveExceptionClick(Sender: TObject);
    procedure CalNewClick(Sender: TObject);
    procedure ResSelect(Sender: TObject);
    procedure ResApply(Sender: TObject);
    procedure ResNewPerson(Sender: TObject);
    procedure ResNewMachine(Sender: TObject);
    procedure ResNewMaterial(Sender: TObject);
    procedure ResNew(AType: TPJResourceType; const ABase: string);
    procedure ResDelete(Sender: TObject);
    procedure ResImport(Sender: TObject);
    function SelectedResource: TPJResource;
    { cronograma }
    procedure LoadSchedulePage;
    procedure RecalcClick(Sender: TObject);
    procedure CritSlackApply(Sender: TObject);
    procedure IssueClick(Sender: TObject);
    procedure LevelClick(Sender: TObject);
    procedure ClearLevelClick(Sender: TObject);
    { acompanhar }
    procedure StatusDateApply(Sender: TObject);
    { tarefa }
    procedure LoadTaskPage;
    procedure TaskApply(Sender: TObject);
    procedure TaskBack(Sender: TObject);
    procedure TaskResApply(Sender: TObject);
    procedure TaskResAdd(Sender: TObject);
    procedure AsyncRefresh(Data: PtrInt);
    procedure QueueRefresh;
    procedure SetStatus(const AText: string; AKind: Integer = 0);
    procedure UpdateHeader;
    procedure UpdateFooter;
    procedure RefreshChains;
    function CurrentTaskIndex: Integer;
    function InsertAt: Integer;
    procedure AfterCommand(const AId: string = '');
  public
    Doc: TPJProject;
    Sched: TPJSchedule;
    Options: TPJViewOptions;
    FileName: string;
    CurrentView, CurrentStep: Integer;
    Pages: TPageControl;
    Nav: array[0..6] of TSuiteButton;
    ViewButtons: array[0..5] of TSuiteButton;
    Gantt: TAIGanttView;
    Network: TAINetworkView;
    Board: TAIBoardView;
    Team: TAIResourceView;
    FooterPanel: TPanel;
    StatusLabel, InfoLabel: TLabel;
    ValidateButton, GenerateButton, OpenToolButton: TSuiteButton;
    AcceptSuggestionButton, RejectSuggestionButton: TSuiteButton;
    GateBox: TCheckBox;
    ChainList, SuggestList: TListBox;
    FilterCombo, GroupCombo: TComboBox;
    CriticalBox: TCheckBox;
    { objetivo }
    OName, OShort, OStart, ORevision, OAuthor: TEdit;
    OLong, OScope, OSuccess: TMemo;
    OCalendar: TComboBox;
    { tarefas }
    KindCombo: TComboBox;
    { relacoes }
    RelTaskLabel: TLabel;
    RelPredEdit, RelLagEdit: TEdit;
    RelTarget, RelType: TComboBox;
    RelArtifact: TCheckBox;
    RelList: TListBox;
    { recursos }
    ResList: TListBox;
    RName, RRole, REmail, RUnits, RGroup: TEdit;
    RType, RMachine, RCalendar: TComboBox;
    ResInfo: TLabel;
    CalList, CalExcList: TListBox;
    CalDateEdit, CalNameEdit: TEdit;
    { cronograma }
    SchedInfo: TLabel;
    IssueList: TListBox;
    CritSlackEdit: TEdit;
    LevelSlackBox: TCheckBox;
    { acompanhar }
    StatusDateEdit: TEdit;
    { tarefa }
    TName, TShort, TDuration, TConstraintDate, TDeadline, TTechText: TEdit;
    TResEdit, TResUnits, TPriority: TEdit;
    TResCombo: TComboBox;
    TResInfo: TLabel;
    TLong, TNotes: TMemo;
    TIdLabel, TDatesLabel, TToolLabel, TPredLabel, TOriginLabel: TLabel;
    TKind, TProcess, TState, TMode, TConstraint, TCalendar: TComboBox;
    TTechGrid, TFuncGrid: TStringGrid;
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure NewProject;
    procedure LoadExample;
    procedure OpenFile(const AFileName: string);
    procedure CreateFromTemplateFile(const AFileName: string);
    procedure SaveFile(const AFileName: string);
    procedure RefreshAll;
    procedure ShowStep(N: Integer);
    procedure ShowView(V: Integer);
    procedure SelectTask(const AId: string);
    function SelectedTask: TPJTask;
    function StatusText: string;
    { comandos da tela para o teste de interface (mesmo caminho dos botoes) }
    procedure TaskApplyForTest;
    procedure InsertClickForTest;
    procedure IndentClickForTest;
    procedure UndoClickForTest;
    procedure LevelForTest(AWithinSlack: Boolean);
    procedure ClearLevelForTest;
    procedure ResApplyForTest;
    procedure TaskResApplyForTest;
  end;

var
  MultiProjectForm: TMultiProjectForm;

function TryParseBRDateTime(const S: string; out D: TDateTime): Boolean;
function FormatBRDateTime(D: TDateTime): string;

implementation

const
  STEP_ICONS: array[0..6] of TSuiteIconKind = (sikTarget, sikLayers, sikArrowRight,
    sikGear, sikPulse, sikGauge, sikExport);
  VIEW_CAPTIONS: array[0..5] of string = ('Gantt', 'Rede', 'Quadro', 'Equipe', 'Calendario', 'Linha do tempo');
  PROCESS_CAPTIONS: array[TPJProcess] of string = ('nenhum', 'impressao 3D', 'usinagem CNC Router',
    'corte laser', 'usinagem de torno');
  LINK_CAPTIONS: array[TAITaskLinkType] of string = ('TI - termino-inicio', 'II - inicio-inicio',
    'TT - termino-termino', 'IT - inicio-termino');
  VIEW_WIDTHS: array[0..3] of Integer = (80, 70, 86, 84);
  VIEW_ICONS: array[0..5] of TSuiteIconKind = (sikLayers, sikArrowRight, sikRect, sikGear, sikFrame, sikPulse);
  CRIT_NAMES: array[TPJCriterionState] of string = ('pendente', 'aprovado', 'reprovado', 'dispensado');

{ ---------------- datas no formato brasileiro ---------------- }

function TryParseBRDateTime(const S: string; out D: TDateTime): Boolean;
var T: string; Dd, Mm, Yy, Hh, Nn: Integer; DP, TP: TDateTime;
begin
  D := 0;
  T := Trim(S);
  if T = '' then Exit(True);
  Result := False;
  Hh := 0; Nn := 0;
  if (Length(T) < 10) or (T[3] <> '/') or (T[6] <> '/') then Exit;
  Dd := StrToIntDef(Copy(T, 1, 2), -1);
  Mm := StrToIntDef(Copy(T, 4, 2), -1);
  Yy := StrToIntDef(Copy(T, 7, 4), -1);
  if Length(T) > 10 then
  begin
    T := Trim(Copy(T, 11, MaxInt));
    if (Length(T) <> 5) or (T[3] <> ':') then Exit;
    Hh := StrToIntDef(Copy(T, 1, 2), -1);
    Nn := StrToIntDef(Copy(T, 4, 2), -1);
  end;
  if not TryEncodeDate(Yy, Mm, Dd, DP) or not TryEncodeTime(Hh, Nn, 0, 0, TP) then Exit;
  D := DP + TP;
  Result := True;
end;

function FormatBRDateTime(D: TDateTime): string;
begin
  if D = 0 then Exit('');
  Result := FormatDateTime('dd"/"mm"/"yyyy hh":"nn', D);
end;

{ ---------------- construcao ---------------- }

function TMultiProjectForm.Btn(AParent: TWinControl; const AText: string; X, Y, W: Integer;
  AIcon: TSuiteIconKind; AHandler: TNotifyEvent): TSuiteButton;
begin
  Result := TSuiteButton.Create(Self);
  Result.Parent := AParent;
  Result.SetBounds(X, Y, W, 34);
  Result.Caption := AText;
  Result.SetLook(sbsSoft, clSuitePrimary, AIcon);
  Result.OnClick := AHandler;
end;

function TMultiProjectForm.Lbl(AParent: TWinControl; const AText: string; X, Y, W, H: Integer): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := AParent;
  Result.AutoSize := False;
  Result.SetBounds(X, Y, W, H);
  Result.WordWrap := True;
  Result.Caption := AText;
  Result.Font.Color := clSuiteMuted;
end;

function TMultiProjectForm.Section(AParent: TWinControl; const AText: string; Y: Integer): TLabel;
begin
  Result := Lbl(AParent, AText, 16, Y, 290, 22);
  Result.Font.Style := [fsBold];
  Result.Font.Color := clSuiteText;
end;

function TMultiProjectForm.Edit(AParent: TWinControl; const ACaption: string; Y: Integer): TEdit;
begin
  Lbl(AParent, ACaption, 16, Y, 290, 18);
  Result := TEdit.Create(Self);
  Result.Parent := AParent;
  Result.SetBounds(16, Y + 20, 290, 28);
end;

function TMultiProjectForm.Combo(AParent: TWinControl; const ACaption: string; Y: Integer): TComboBox;
begin
  Lbl(AParent, ACaption, 16, Y, 290, 18);
  Result := TComboBox.Create(Self);
  Result.Parent := AParent;
  Result.SetBounds(16, Y + 20, 290, 30);
  Result.Style := csDropDownList;
end;

function TMultiProjectForm.Memo(AParent: TWinControl; const ACaption: string; Y, H: Integer): TMemo;
begin
  Lbl(AParent, ACaption, 16, Y, 290, 18);
  Result := TMemo.Create(Self);
  Result.Parent := AParent;
  Result.SetBounds(16, Y + 20, 290, H);
  Result.ScrollBars := ssAutoVertical;
  Result.WordWrap := True;
end;

constructor TMultiProjectForm.Create(AOwner: TComponent);
var Sidebar: TPanel; K: TPJTaskKind;
begin
  inherited CreateNew(AOwner, 1);
  Caption := 'MultiProject • MultiSuite';
  Width := 1360; Height := 880;
  Constraints.MinWidth := 1000; Constraints.MinHeight := 680;
  Position := poScreenCenter;
  Font.Name := SUITE_FONT; Font.Size := 10;
  Color := clSuiteSurface;
  KeyPreview := True;
  OnKeyDown := @FormKey;
  OnCloseQuery := @FormCloseQuery;
  OnActivate := @CheckArtifacts;
  ArtifactTimer := TTimer.Create(Self);
  ArtifactTimer.Interval := 2000;
  ArtifactTimer.OnTimer := @CheckArtifacts;
  Doc := TPJProject.Create;
  Sched := TPJSchedule.Create(Doc);
  Options := DefaultViewOptions;
  for K := Low(K) to High(K) do
    FIcons[K] := RenderSuiteIcon(KindIcon(K), 16, KindColor(K));
  FUpdating := True;

  Header := TSuiteHeader.Create(Self);
  Header.Parent := Self; Header.Align := alTop; Header.Height := 72;
  Header.Setup('MultiProject', 'Gestao de projetos mecanicos e eletronicos  /  MultiSuite', sikProject);

  BuildFooter;

  Sidebar := TPanel.Create(Self);
  Sidebar.Parent := Self; Sidebar.Align := alLeft; Sidebar.Width := 214;
  Sidebar.BevelOuter := bvNone; Sidebar.Color := clSuiteCard;
  BuildSidebar(Sidebar);

  BuildPages;

  WorkPanel := TPanel.Create(Self);
  WorkPanel.Parent := Self; WorkPanel.Align := alClient;
  WorkPanel.BevelOuter := bvNone; WorkPanel.Color := clSuiteSurface;
  BuildBar;

  Gantt := TAIGanttView.Create(Self);
  Gantt.Parent := WorkPanel; Gantt.Align := alClient;
  StyleGantt(Gantt);
  Gantt.OnSelectRow := @GanttSelect;
  Gantt.OnRowDblClick := @GanttDblClick;
  Gantt.OnCellEdited := @GanttEdited;
  Gantt.OnIsWorkingDay := @GanttWorkingDay;
  Gantt.OnCellIcon := @GanttIcon;

  Network := TAINetworkView.Create(Self);
  Network.Parent := WorkPanel; Network.Align := alClient;
  StyleNetwork(Network);
  Network.OnSelect := @NetSelect;
  Network.OnNodeDblClick := @NetDblClick;
  Network.OnCreateLink := @NetLink;
  Network.Visible := False;

  Board := TAIBoardView.Create(Self);
  Board.Parent := WorkPanel; Board.Align := alClient;
  StyleBoard(Board);
  Board.OnSelect := @BoardSelect;
  Board.OnCardDblClick := @BoardDblClick;
  Board.OnCardMove := @BoardMove;
  Board.Visible := False;

  Team := TAIResourceView.Create(Self);
  Team.Parent := WorkPanel; Team.Align := alClient;
  StyleTeam(Team);
  Team.OnSelectBar := @TeamSelect;
  Team.OnBarDblClick := @TeamDblClick;
  Team.OnReassign := @TeamReassign;
  Team.OnIsWorkingDay := @GanttWorkingDay;
  Team.Visible := False;

  OnResize := @FormResizeUI;
  FUpdating := False;
  NewProject;
  ShowStep(1);
  ShowView(VIEW_GANTT);
end;

destructor TMultiProjectForm.Destroy;
var K: TPJTaskKind;
begin
  ArtifactTimer.Enabled := False;
  OnActivate := nil;
  Application.RemoveAsyncCalls(Self);
  for K := Low(K) to High(K) do FIcons[K].Free;
  Sched.Free;
  Doc.Free;
  inherited Destroy;
end;

procedure TMultiProjectForm.BuildFooter;
begin
  FooterPanel := TPanel.Create(Self);
  FooterPanel.Parent := Self; FooterPanel.Align := alBottom; FooterPanel.Height := 66;
  FooterPanel.BevelOuter := bvNone; FooterPanel.Color := clSuiteCard;
  StatusLabel := Lbl(FooterPanel, '', 18, 8, 600, 24);
  StatusLabel.Font.Color := clSuiteText;
  InfoLabel := Lbl(FooterPanel, '', 18, 36, 600, 22);
  ValidateButton := Btn(FooterPanel, 'Validar', 0, 15, 120, sikTests, @ValidateClick);
  GenerateButton := Btn(FooterPanel, 'Gerar tarefas', 0, 15, 150, sikWand, @GenerateClick);
  GenerateButton.Hint := 'Propor tarefas pelas especificacoes, estados e regras do projeto';
  GenerateButton.ShowHint := True;
  OpenToolButton := Btn(FooterPanel, 'Abrir na ferramenta', 0, 15, 230, sikSend, @OpenToolClick);
  OpenToolButton.SetLook(sbsSolid, clSuitePrimary, sikSend);
  OpenToolButton.Enabled := False;
  OpenToolButton.Hint := 'Abrir o artefato selecionado na ferramenta da suite';
  OpenToolButton.ShowHint := True;
end;

procedure TMultiProjectForm.BuildSidebar(S: TPanel);
var I: Integer; Body, Actions: TPanel; Title: TLabel;
begin
  for I := 0 to 6 do
  begin
    Nav[I] := Btn(S, PJ_STEPS[I], 12, 16 + I * 44, 190, STEP_ICONS[I], @NavClick);
    Nav[I].Tag := I;
  end;
  Btn(S, 'Novo', 12, 332, 92, sikNew, @NewClick).Hint := 'Novo projeto (Ctrl+N)';
  Btn(S, 'Abrir', 110, 332, 92, sikFolder, @OpenClick).Hint := 'Abrir .mproj (Ctrl+O)';
  Btn(S, 'Salvar', 12, 372, 92, sikSave, @SaveClick).Hint := 'Salvar (Ctrl+S)';
  Btn(S, 'Demo', 110, 372, 92, sikWand, @DemoClick).Hint := 'Abrir o exemplo do motor DC';
  Body := TPanel.Create(Self); SidebarBody:=Body; Body.Parent := S; Body.BevelOuter := bvNone; Body.Color := S.Color;
  Body.SetBounds(12, 416, 190, Max(120,S.ClientHeight-428));
  Body.Anchors := [akLeft,akTop,akRight,akBottom];
  Title := Lbl(Body,'CADEIAS',0,0,190,20); ChainTitleLabel:=Title; Title.Align := alTop; Title.Font.Style := [fsBold];
  ChainList := TListBox.Create(Self); ChainList.Parent := Body; ChainList.Top:=20;
  ChainList.Align := alTop; ChainList.Height := 40; ChainList.OnClick := @ChainClick;
  Title := Lbl(Body,'SUGESTOES',0,60,190,20); Title.Align := alTop; Title.Font.Style := [fsBold];
  Actions := TPanel.Create(Self); Actions.Parent := Body; Actions.Align := alBottom;
  Actions.Height:=38; Actions.BevelOuter:=bvNone; Actions.Color:=S.Color;
  AcceptSuggestionButton := Btn(Actions,'Aceitar',0,2,92,sikSave,@AcceptSuggestions);
  RejectSuggestionButton := Btn(Actions,'Recusar',98,2,92,sikTrash,@RejectSuggestions);
  SuggestList := TListBox.Create(Self); SuggestList.Parent := Body; SuggestList.Align := alClient;
  SuggestList.MultiSelect:=True; SuggestList.ExtendedSelect:=True; SuggestList.OnDblClick:=@SuggestionOpen;
  SuggestList.Hint:='Selecione uma ou varias sugestoes. Sem selecao, Aceitar/Recusar vale para todas.';
  SuggestList.ShowHint:=True;
end;

procedure TMultiProjectForm.BuildBar;
var I, X: Integer;
begin
  { duas linhas: vistas e zoom em cima (52 px), filtro/agrupamento embaixo (36 px),
    para caber na largura de 1024 x 768 }
  BarPanel := TPanel.Create(Self);
  BarPanel.Parent := WorkPanel; BarPanel.Align := alTop; BarPanel.Height := 88;
  BarPanel.BevelOuter := bvNone; BarPanel.Color := clSuiteSurface;
  X := 12;
  for I := 0 to 5 do
  begin
    if I < 4 then
      ViewButtons[I] := Btn(BarPanel, VIEW_CAPTIONS[I], X, 9, VIEW_WIDTHS[I], VIEW_ICONS[I], @ViewClick)
    else
    begin
      { vistas da fase 8 (Calendario e Linha do tempo): criadas ocultas,
        aparecem quando a fase entrar }
      ViewButtons[I] := Btn(BarPanel, VIEW_CAPTIONS[I], X, 9, 40, VIEW_ICONS[I], @ViewClick);
      ViewButtons[I].Enabled := False;
      ViewButtons[I].Visible := False;
    end;
    ViewButtons[I].Tag := I;
    if ViewButtons[I].Visible then Inc(X, ViewButtons[I].Width + 6);
  end;
  ViewButtons[3].Hint := 'Equipe: pessoas e maquinas no tempo, com os conflitos';
  ViewButtons[3].ShowHint := True;
  ViewButtons[4].Hint := 'Calendario: fase 8';
  ViewButtons[5].Hint := 'Linha do tempo: fase 8';
  Inc(X, 4);
  with Btn(BarPanel, '', X, 9, 34, sikFit, @FitClick) do begin Hint := 'Ajustar a vista'; ShowHint := True; end;
  Inc(X, 38);
  with Btn(BarPanel, '', X, 9, 34, sikZoomIn, @ZoomInClick) do begin Hint := 'Ampliar (Ctrl+roda)'; ShowHint := True; end;
  Inc(X, 38);
  with Btn(BarPanel, '', X, 9, 34, sikZoomOut, @ZoomOutClick) do begin Hint := 'Reduzir'; ShowHint := True; end;
  X := 12;
  FilterCombo := TComboBox.Create(Self);
  FilterCombo.Parent := BarPanel;
  FilterCombo.SetBounds(X, 54, 150, 28);
  FilterCombo.Style := csDropDownList;
  FilterCombo.Items.CommaText := '"Todas as tarefas",Criticas,Atrasadas,Sugeridas,"Cadeia selecionada","Geradas por regra"';
  FilterCombo.ItemIndex := 0;
  FilterCombo.OnChange := @FilterChange;
  Inc(X, 158);
  GroupCombo := TComboBox.Create(Self);
  GroupCombo.Parent := BarPanel;
  GroupCombo.SetBounds(X, 54, 130, 28);
  GroupCombo.Style := csDropDownList;
  GroupCombo.Items.CommaText := '"Agrupar: EAP","Agrupar: tipo","Agrupar: estado"';
  GroupCombo.ItemIndex := 0;
  GroupCombo.OnChange := @FilterChange;
  Inc(X, 138);
  CriticalBox := TCheckBox.Create(Self);
  CriticalBox.Parent := BarPanel;
  CriticalBox.SetBounds(X, 56, 140, 24);
  CriticalBox.Caption := 'Realcar criticas';
  CriticalBox.Checked := True;
  CriticalBox.OnChange := @FilterChange;
end;

procedure TMultiProjectForm.BuildPages;
var I: Integer; Page: TTabSheet; Scroll: TScrollBox;
begin
  Pages := TPageControl.Create(Self);
  Pages.Parent := Self; Pages.Align := alRight; Pages.Width := 336;
  Pages.ShowTabs := False;
  for I := 0 to PAGE_TASK do
  begin
    Page := TTabSheet.Create(Self);
    Page.PageControl := Pages;
    Scroll := TScrollBox.Create(Self);
    Scroll.Parent := Page; Scroll.Align := alClient;
    Scroll.BorderStyle := bsNone; Scroll.Color := clSuiteCard;
    Scroll.HorzScrollBar.Visible := False;
    Scroll.VertScrollBar.Tracking := True;
    if I < PAGE_TASK then
    begin
      Page.Caption := PJ_STEPS[I];
      Lbl(Scroll, PJ_STEPS[I], 16, 16, 280, 30).Font.Style := [fsBold];
    end
    else
      Page.Caption := 'Tarefa';
    case I of
      0: BuildObjectivePage(Scroll);
      1: BuildTasksPage(Scroll);
      2: BuildRelationsPage(Scroll);
      3: BuildResourcesPage(Scroll);
      4: BuildSchedulePage(Scroll);
      5: BuildTrackPage(Scroll);
      6: BuildReportsPage(Scroll);
      7: BuildTaskPage(Scroll);
    end;
  end;
end;

procedure TMultiProjectForm.BuildObjectivePage(S: TScrollBox);
begin
  OName := Edit(S, 'Nome do projeto', 52);
  OShort := Edit(S, 'Objetivo (descricao curta)', 104);
  OLong := Memo(S, 'Descricao longa', 156, 80);
  OScope := Memo(S, 'Escopo', 260, 56);
  OSuccess := Memo(S, 'Criterios de sucesso (um por linha)', 340, 64);
  OStart := Edit(S, 'Inicio (dd/mm/aaaa hh:mm)', 428);
  OCalendar := Combo(S, 'Calendario do projeto', 480);
  ORevision := Edit(S, 'Revisao', 534);
  OAuthor := Edit(S, 'Autor', 586);
  GateBox:=TCheckBox.Create(Self); GateBox.Parent:=S; GateBox.SetBounds(16,688,290,24);
  GateBox.Caption:='Exigir liberacao antes de fabricar'; GateBox.Checked:=True;
  Btn(S,'Novo a partir de modelo...',16,724,290,sikFolder,@TemplateClick);
  Btn(S, 'Aplicar', 16, 644, 140, sikSave, @ObjectiveApply).SetLook(sbsSolid, clSuitePrimary, sikSave);
  with Btn(S, 'Decompor com IA', 166, 644, 140, sikWand, nil) do
  begin
    Enabled := False;
    Hint := 'Decomposicao do objetivo pela IA: fase 9';
    ShowHint := True;
  end;
end;

procedure TMultiProjectForm.BuildTasksPage(S: TScrollBox);
var K: TPJTaskKind;
begin
  KindCombo := Combo(S, 'Tipo da nova tarefa', 52);
  for K := Low(K) to High(K) do
    if not (K in [tkSummary, tkMilestone]) then KindCombo.Items.AddObject(KindCaption(K), TObject(PtrInt(Ord(K))));
  KindCombo.ItemIndex := KindCombo.Items.IndexOf(KindCaption(tkPart));
  Btn(S, 'Inserir tarefa (Insert)', 16, 108, 290, sikNew, @InsertClick).SetLook(sbsSolid, clSuitePrimary, sikNew);
  Btn(S, 'Resumo', 16, 148, 142, sikLayers, @InsertSummaryClick);
  Btn(S, 'Marco', 164, 148, 142, sikFlag, @InsertMilestoneClick);
  Section(S, 'ESTRUTURA', 196);
  Btn(S, 'Recuar', 16, 222, 142, sikArrowRight, @IndentClick).Hint := 'Alt+Shift+Seta direita';
  Btn(S, 'Avancar', 164, 222, 142, sikArrowLeft, @OutdentClick).Hint := 'Alt+Shift+Seta esquerda';
  Btn(S, 'Subir', 16, 262, 142, sikArrowUp, @UpClick);
  Btn(S, 'Descer', 164, 262, 142, sikArrowDown, @DownClick);
  Btn(S, 'Excluir', 16, 302, 142, sikTrash, @DeleteClick).SetLook(sbsSoft, clSuiteDanger, sikTrash);
  Btn(S, 'Detalhes', 164, 302, 142, sikEye, @TaskPageClick).Hint := 'Pagina da tarefa (Shift+F2)';
  Section(S, 'EDICAO', 350);
  Btn(S, 'Desfazer', 16, 376, 142, sikUndo, @UndoClick).Hint := 'Ctrl+Z';
  Btn(S, 'Refazer', 164, 376, 142, sikRedo, @RedoClick).Hint := 'Ctrl+Y';
  Lbl(S, 'Na tabela: duplo clique (ou F2) edita nome, duracao e predecessoras. ' +
    'Duracao: 30min, 4h, 2d, 1sem; decorrida 14eh; estimada 4h?. ' +
    'Predecessoras: T-0003;T-0004II+2h;T-0005TT-10%.', 16, 424, 290, 110);
end;

procedure TMultiProjectForm.BuildRelationsPage(S: TScrollBox);
var L: TAITaskLinkType;
begin
  RelTaskLabel := Section(S, 'Selecione uma tarefa', 52);
  RelPredEdit := Edit(S, 'Predecessoras (coluna do Project)', 80);
  Btn(S, 'Aplicar predecessoras', 16, 136, 290, sikSave, @RelPredApply);
  Section(S, 'NOVO VINCULO', 184);
  RelTarget := Combo(S, 'Sucessora', 208);
  RelType := Combo(S, 'Tipo', 262);
  for L := Low(L) to High(L) do RelType.Items.Add(LINK_CAPTIONS[L]);
  RelType.ItemIndex := 0;
  RelLagEdit := Edit(S, 'Latencia (+2h, -1d, +24eh, -10%)', 316);
  RelArtifact := TCheckBox.Create(Self);
  RelArtifact.Parent := S;
  RelArtifact.SetBounds(16, 372, 290, 24);
  RelArtifact.Caption := 'A sucessora usa o arquivo desta tarefa';
  Btn(S, 'Vincular', 16, 402, 142, sikPlug, @RelAddClick).SetLook(sbsSolid, clSuitePrimary, sikPlug);
  Btn(S, 'Vincular a proxima', 164, 402, 142, sikArrowDown, @LinkNextClick).Hint := 'Ctrl+F2';
  Section(S, 'VINCULOS DA TAREFA', 450);
  RelList := TListBox.Create(Self);
  RelList.Parent := S;
  RelList.SetBounds(16, 474, 290, 150);
  Btn(S, 'Remover vinculo', 16, 632, 290, sikTrash, @RelRemoveClick).SetLook(sbsSoft, clSuiteDanger, sikTrash);
end;

procedure TMultiProjectForm.BuildResourcesPage(S: TScrollBox);
var RT: TPJResourceType; MT: TPJMachineType;
begin
  Lbl(S, 'Pessoas (usuarios), maquinas e materiais. Atribua na pagina da tarefa, ' +
    'na coluna Recursos ou arrastando na vista Equipe.', 16, 50, 290, 52);
  Section(S, 'RECURSOS', 104);
  ResList := TListBox.Create(Self);
  ResList.Parent := S;
  ResList.SetBounds(16, 128, 290, 150);
  ResList.OnClick := @ResSelect;
  Btn(S, 'Nova pessoa', 16, 286, 142, sikNew, @ResNewPerson).Hint := 'Pessoa (usuario) da equipe';
  Btn(S, 'Nova maquina', 164, 286, 142, sikGear, @ResNewMachine).Hint := 'Maquina da oficina';
  Btn(S, 'Novo material', 16, 326, 142, sikLayers, @ResNewMaterial).Hint := 'Consumivel (kg, m2, un)';
  with Btn(S, 'Do MultiCNC', 164, 326, 142, sikImport, @ResImport) do
  begin
    Hint := 'Importar as maquinas do cadastro do MultiCNC (somente leitura)';
    ShowHint := True;
  end;
  Section(S, 'RECURSO SELECIONADO', 374);
  RName := Edit(S, 'Nome', 398);
  RType := Combo(S, 'Tipo', 450);
  for RT := Low(RT) to High(RT) do RType.Items.Add(ResourceTypeCaption(RT));
  RRole := Edit(S, 'Funcao (pessoa)', 504);
  REmail := Edit(S, 'E-mail', 556);
  RMachine := Combo(S, 'Tipo de maquina', 608);
  for MT := Low(MT) to High(MT) do RMachine.Items.Add(MachineTypeCaption(MT));
  RUnits := Edit(S, 'Unidades maximas (%): 100 = uma pessoa ou maquina', 662);
  RCalendar := Combo(S, 'Calendario', 714);
  RGroup := Edit(S, 'Grupo (equipe, oficina)', 768);
  ResInfo := Lbl(S, '', 16, 822, 290, 40);
  ResInfo.Font.Color := clSuiteText;
  Btn(S, 'Aplicar', 16, 866, 142, sikSave, @ResApply).SetLook(sbsSolid, clSuitePrimary, sikSave);
  Btn(S, 'Excluir', 164, 866, 142, sikTrash, @ResDelete).SetLook(sbsSoft, clSuiteDanger, sikTrash);
  Section(S, 'CALENDARIOS', 918);
  CalList := TListBox.Create(Self);
  CalList.Parent := S;
  CalList.SetBounds(16, 942, 290, 70);
  CalList.OnClick := @CalSelect;
  Btn(S, 'Novo calendario (copia do padrao)', 16, 1020, 290, sikNew, @CalNewClick);
  Section(S, 'EXCECOES (FERIADOS E FOLGAS)', 1066);
  CalExcList := TListBox.Create(Self);
  CalExcList.Parent := S;
  CalExcList.SetBounds(16, 1090, 290, 180);
  CalDateEdit := Edit(S, 'Data (dd/mm/aaaa)', 1278);
  CalNameEdit := Edit(S, 'Nome (folga sem expediente)', 1330);
  Btn(S, 'Adicionar folga', 16, 1388, 142, sikNew, @CalAddExceptionClick);
  Btn(S, 'Remover', 164, 1388, 142, sikTrash, @CalRemoveExceptionClick).SetLook(sbsSoft, clSuiteDanger, sikTrash);
end;

procedure TMultiProjectForm.BuildSchedulePage(S: TScrollBox);
begin
  SchedInfo := Lbl(S, '', 16, 50, 290, 70);
  SchedInfo.Font.Color := clSuiteText;
  Btn(S, 'Recalcular (F9)', 16, 124, 290, sikPulse, @RecalcClick).SetLook(sbsSolid, clSuitePrimary, sikPulse);
  CritSlackEdit := Edit(S, 'Critica com margem ate (ex.: 0h, 4h, 1d)', 170);
  Btn(S, 'Aplicar limiar', 16, 226, 290, sikSave, @CritSlackApply);
  Section(S, 'AVISOS E VALIDACAO', 274);
  IssueList := TListBox.Create(Self);
  IssueList.Parent := S;
  IssueList.SetBounds(16, 298, 290, 260);
  IssueList.OnClick := @IssueClick;
  Section(S, 'RECURSOS', 568);
  LevelSlackBox := TCheckBox.Create(Self);
  LevelSlackBox.Parent := S;
  LevelSlackBox.SetBounds(16, 592, 290, 24);
  LevelSlackBox.Caption := 'So dentro da margem (nao atrasa o termino)';
  Btn(S, 'Nivelar recursos', 16, 622, 290, sikPulse, @LevelClick).SetLook(sbsSolid, clSuitePrimary, sikPulse);
  Btn(S, 'Limpar nivelamento', 16, 662, 290, sikUndo, @ClearLevelClick);
  Lbl(S, 'Nivelar atrasa tarefas pela prioridade e pela margem ate cada pessoa ou maquina ' +
    'fazer uma coisa por vez. Linhas de base: fase 8.', 16, 706, 290, 56);
end;

procedure TMultiProjectForm.BuildTrackPage(S: TScrollBox);
begin
  StatusDateEdit := Edit(S, 'Data de status (dd/mm/aaaa)', 52);
  Btn(S, 'Aplicar data de status', 16, 110, 290, sikSave, @StatusDateApply);
  Lbl(S, 'O estado das tarefas muda no Quadro (arraste o cartao). ' +
    'Linha de base, % concluido, valor agregado e verificacao de artefatos entram nas fases 5 e 8.',
    16, 160, 290, 90);
end;

procedure TMultiProjectForm.BuildReportsPage(S: TScrollBox);
begin
  Lbl(S, 'Relatorio HTML, dossie de artefatos, impressao e PDF do Gantt e da rede: fase 8. ' +
    'Exportacao para o XML do Microsoft Project e CSV: fase 10. ' +
    'O projeto ja e salvo em .mproj (JSON) pelo botao Salvar.', 16, 50, 290, 120);
end;

procedure TMultiProjectForm.BuildTaskPage(S: TScrollBox);
var Y: Integer; K: TPJTaskKind; Pr: TPJProcess; St: TPJTaskState; C: TAIConstraintType;
begin
  Btn(S, 'Voltar', 16, 12, 90, sikArrowLeft, @TaskBack).Hint := 'Esc';
  Btn(S, 'Aplicar', 116, 12, 190, sikSave, @TaskApply).SetLook(sbsSolid, clSuitePrimary, sikSave);
  Y := 56;
  Section(S, '1  IDENTIFICACAO', Y); Inc(Y, 26);
  TIdLabel := Lbl(S, '', 16, Y, 290, 20); Inc(Y, 22);
  TName := Edit(S, 'Nome', Y); Inc(Y, 52);
  TKind := Combo(S, 'Tipo', Y); Inc(Y, 54);
  for K := Low(K) to High(K) do TKind.Items.Add(KindCaption(K));
  TProcess := Combo(S, 'Processo de fabricacao (peca)', Y); Inc(Y, 54);
  for Pr := Low(Pr) to High(Pr) do TProcess.Items.Add(PROCESS_CAPTIONS[Pr]);
  TState := Combo(S, 'Estado', Y); Inc(Y, 54);
  for St := Low(St) to High(St) do TState.Items.Add(StateCaption(St));
  TMode := Combo(S, 'Agendamento', Y); Inc(Y, 60);
  TMode.Items.CommaText := 'Automatico,Manual';
  Section(S, '2  DESCRICOES', Y); Inc(Y, 26);
  TShort := Edit(S, 'Descricao curta', Y); Inc(Y, 52);
  TLong := Memo(S, 'Descricao longa', Y, 100); Inc(Y, 130);
  Section(S, '3  ESPECIFICACAO TECNICA', Y); Inc(Y, 26);
  TTechGrid := TStringGrid.Create(Self);
  TTechGrid.Parent := S;
  TTechGrid.SetBounds(16, Y, 290, 130);
  TTechGrid.ColCount := 3; TTechGrid.FixedCols := 0; TTechGrid.RowCount := 9; TTechGrid.FixedRows := 1;
  TTechGrid.Cells[0, 0] := 'Chave'; TTechGrid.Cells[1, 0] := 'Valor'; TTechGrid.Cells[2, 0] := 'Unid.';
  TTechGrid.ColWidths[0] := 120; TTechGrid.ColWidths[1] := 110; TTechGrid.ColWidths[2] := 50;
  TTechGrid.Options := TTechGrid.Options + [goEditing, goTabs];
  Inc(Y, 136);
  TTechText := Edit(S, 'Observacoes tecnicas', Y); Inc(Y, 60);
  Section(S, '4  ESPECIFICACAO FUNCIONAL', Y); Inc(Y, 26);
  TFuncGrid := TStringGrid.Create(Self);
  TFuncGrid.Parent := S;
  TFuncGrid.SetBounds(16, Y, 290, 130);
  TFuncGrid.ColCount := 2; TFuncGrid.FixedCols := 0; TFuncGrid.RowCount := 7; TFuncGrid.FixedRows := 1;
  TFuncGrid.Cells[0, 0] := 'Criterio de aceite'; TFuncGrid.Cells[1, 0] := 'Estado';
  TFuncGrid.ColWidths[0] := 200; TFuncGrid.ColWidths[1] := 82;
  TFuncGrid.Options := TFuncGrid.Options + [goEditing, goTabs];
  Inc(Y, 134);
  Lbl(S, 'Estado: pendente, aprovado, reprovado ou dispensado.', 16, Y, 290, 20); Inc(Y, 28);
  Section(S, '5  DATAS', Y); Inc(Y, 26);
  TDuration := Edit(S, 'Duracao (4h, 2d, 14eh, 1sem, 4h?)', Y); Inc(Y, 52);
  TDatesLabel := Lbl(S, '', 16, Y, 290, 40); Inc(Y, 44);
  TConstraint := Combo(S, 'Restricao', Y); Inc(Y, 54);
  for C := Low(C) to High(C) do TConstraint.Items.Add(AIConstraintCode(C));
  TConstraintDate := Edit(S, 'Data da restricao (dd/mm/aaaa hh:mm)', Y); Inc(Y, 52);
  TDeadline := Edit(S, 'Data limite (dd/mm/aaaa hh:mm)', Y); Inc(Y, 52);
  TCalendar := Combo(S, 'Calendario da tarefa', Y); Inc(Y, 60);
  Section(S, '6  VINCULO COM A FERRAMENTA', Y); Inc(Y, 26);
  TToolLabel := Lbl(S, '', 16, Y, 290, 44); Inc(Y, 50);
  ArtifactPathEdit := Edit(S, 'Arquivo (caminho copiavel)', Y);
  ArtifactPathEdit.ReadOnly := True; Inc(Y, 54);
  Btn(S, 'Vincular arquivo...', 16, Y, 290, sikImport, @LinkArtifactClick); Inc(Y, 42);
  Btn(S, 'Verificar arquivo', 16, Y, 290, sikTests, @CheckArtifacts); Inc(Y, 42);
  OpenCNCButton := Btn(S, 'Abrir no MultiCNC', 16, Y, 290, sikSend, @OpenCNCClick); Inc(Y, 42);
  LatheButton:=Btn(S,'Gerar folha de torno...',16,Y,290,sikExport,@LatheSheetClick); Inc(Y,42);
  Section(S, '7  PREDECESSORAS E SUCESSORAS', Y); Inc(Y, 26);
  TPredLabel := Lbl(S, '', 16, Y, 290, 60); Inc(Y, 66);
  Section(S, '8  RECURSOS', Y); Inc(Y, 26);
  TResEdit := Edit(S, 'Recursos (ex.: Ana; Ender-3; Bruno[50%])', Y); Inc(Y, 54);
  Btn(S, 'Aplicar recursos', 16, Y, 290, sikSave, @TaskResApply); Inc(Y, 42);
  TResCombo := Combo(S, 'Adicionar recurso compativel', Y); Inc(Y, 54);
  TResUnits := Edit(S, 'Unidades (%) ou quantidade do material', Y); Inc(Y, 54);
  Btn(S, 'Adicionar', 16, Y, 290, sikNew, @TaskResAdd); Inc(Y, 42);
  TResInfo := Lbl(S, '', 16, Y, 290, 52); Inc(Y, 56);
  TPriority := Edit(S, 'Prioridade no nivelamento (0 a 1000)', Y); Inc(Y, 60);
  Section(S, '9  ORIGEM E ANOTACOES', Y); Inc(Y, 26);
  TOriginLabel := Lbl(S, 'Criada pelo usuario', 16, Y, 290, 20); Inc(Y, 24);
  TNotes := Memo(S, 'Anotacoes', Y, 80); Inc(Y, 110);
  Btn(S, 'Aplicar', 16, Y, 290, sikSave, @TaskApply).SetLook(sbsSolid, clSuitePrimary, sikSave);
end;

{ ---------------- layout ---------------- }

procedure TMultiProjectForm.FormResizeUI(Sender: TObject);
begin
  if FooterPanel = nil then Exit;
  if SidebarBody<>nil then
  begin
    SidebarBody.SetBounds(12,416,190,Max(64,SidebarBody.Parent.ClientHeight-428));
    ChainList.Visible:=SidebarBody.Height>=180; ChainTitleLabel.Visible:=ChainList.Visible;
  end;
  OpenToolButton.Left := FooterPanel.ClientWidth - OpenToolButton.Width - 18;
  GenerateButton.Left := OpenToolButton.Left - GenerateButton.Width - 10;
  ValidateButton.Left := GenerateButton.Left - ValidateButton.Width - 10;
  StatusLabel.Width := Max(120, ValidateButton.Left - 30);
  InfoLabel.Width := StatusLabel.Width;
  { a tabela do Gantt cede espaco ao grafico em janelas estreitas }
  if Gantt <> nil then
    Gantt.TableWidth := Min(498, Max(220, Gantt.ClientWidth - 280));
end;

procedure TMultiProjectForm.ShowStep(N: Integer);
var I: Integer;
begin
  N := EnsureRange(N, 0, PAGE_TASK);
  CurrentStep := N;
  Pages.ActivePageIndex := N;
  for I := 0 to 6 do
    if I = N then Nav[I].SetLook(sbsSolid, clSuitePrimary)
    else Nav[I].SetLook(sbsSoft, clSuitePrimary);
  case N of
    0: LoadObjectivePage;
    2: LoadRelationsPage;
    3: LoadResourcesPage;
    4: LoadSchedulePage;
    5: StatusDateEdit.Text := FormatBRDateTime(Doc.StatusDate);
    PAGE_TASK: LoadTaskPage;
  end;
  { cada etapa sugere uma vista, como no LAYOUT }
  case N of
    1, 4: ShowView(VIEW_GANTT);
    2: ShowView(VIEW_NETWORK);
    3: ShowView(VIEW_TEAM);
    5: ShowView(VIEW_BOARD);
  end;
end;

procedure TMultiProjectForm.ShowView(V: Integer);
var I: Integer;
begin
  if not (V in [VIEW_GANTT, VIEW_NETWORK, VIEW_BOARD, VIEW_TEAM]) then Exit;
  CurrentView := V;
  Gantt.Visible := V = VIEW_GANTT;
  Network.Visible := V = VIEW_NETWORK;
  Board.Visible := V = VIEW_BOARD;
  Team.Visible := V = VIEW_TEAM;
  for I := 0 to 3 do
    if I = V then ViewButtons[I].SetLook(sbsSolid, clSuitePrimary)
    else ViewButtons[I].SetLook(sbsSoft, clSuitePrimary);
  if FSelectedId <> '' then SelectTask(FSelectedId);
end;

{ ---------------- documento ---------------- }

procedure TMultiProjectForm.NewProject;
var D: TDateTime;
begin
  Doc.Clear;
  Doc.Name := 'Novo projeto';
  D := Date + 1;
  while DayOfWeek(D) in [1, 7] do D := D + 1;
  Doc.StartDate := D + EncodeTime(8, 0, 0, 0);
  Doc.ResetCalendars;
  Doc.ClearHistory;
  Doc.Modified := False;
  FileName := '';
  FSelectedId := '';
  RefreshAll;
  SetStatus('Defina o objetivo (etapa 1) e insira as tarefas (etapa 2), ou abra o exemplo (Demo).');
end;

procedure TMultiProjectForm.LoadExample;
begin
  BuildMotorExample(Doc);
  FileName := '';
  FSelectedId := '';
  RefreshAll;
  Gantt.FitToRows;
  Network.FitAll;
  Team.FitToBars;
  SetStatus(Format('Exemplo do motor DC: 17 tarefas, %d recursos e conflitos para nivelar (vista Equipe).',
    [Doc.ResourceCount]), 1);
end;

procedure TMultiProjectForm.OpenFile(const AFileName: string);
begin
  try
    LoadProjectFile(Doc, AFileName);
  except
    on E: Exception do
    begin
      SetStatus('Nao foi possivel abrir ' + ExtractFileName(AFileName) + ': ' + E.Message, 3);
      Exit;
    end;
  end;
  FileName := AFileName;
  FSelectedId := '';
  RefreshAll;
  Gantt.FitToRows;
  Team.FitToBars;
  SetStatus('Aberto: ' + AFileName, 1);
end;

procedure TMultiProjectForm.SaveFile(const AFileName: string);
begin
  try
    SaveProjectFile(Doc, AFileName);
  except
    on E: Exception do
    begin
      SetStatus('Nao foi possivel salvar: ' + E.Message, 3);
      Exit;
    end;
  end;
  FileName := AFileName;
  UpdateHeader;
  SetStatus('Salvo: ' + AFileName, 1);
end;

function TMultiProjectForm.StatusText: string;
begin
  Result := StatusLabel.Caption;
end;

procedure TMultiProjectForm.SetStatus(const AText: string; AKind: Integer);
begin
  { 0 normal, 1 sucesso, 2 aviso, 3 erro }
  StatusLabel.Caption := AText;
  case AKind of
    1: StatusLabel.Font.Color := clSuiteSuccess;
    2: StatusLabel.Font.Color := clSuiteWarning;
    3: StatusLabel.Font.Color := clSuiteDanger;
  else
    StatusLabel.Font.Color := clSuiteText;
  end;
end;

procedure TMultiProjectForm.UpdateHeader;
var S: string;
begin
  S := Doc.Name;
  if S = '' then S := 'Sem nome';
  S := S + '  •  rev. ' + Doc.Revision;
  if Doc.Modified then S := S + '  •  alterado';
  Header.Setup('MultiProject', S + '  /  MultiSuite', sikProject);
  Header.Invalidate;
  Caption := 'MultiProject • MultiSuite';
  if FileName <> '' then Caption := Caption + ' - ' + ExtractFileName(FileName);
end;

procedure TMultiProjectForm.UpdateFooter;
var
  L: TPJIssues;
  N, I, Pre, Suc, Leaves: Integer;
  G: TAITaskGraph;
  Err, S: string;
  T: TPJTask;
begin
  L := Doc.Validate;
  N := Length(L) + Length(Sched.Issues);
  if not Sched.Valid then
    InfoLabel.Caption := 'Cronograma nao calculado: ' + Sched.Error
  else
  begin
    InfoLabel.Caption := Format('%d avisos  •  Termino previsto %s  •  Criticas: %d', [N,
      FormatBRDateTime(Sched.ProjectFinish), Sched.CriticalCount]);
    if Sched.OverloadCount > 0 then
      InfoLabel.Caption := InfoLabel.Caption + Format('  •  Superalocacao: %d', [Sched.OverloadCount]);
  end;
  if not Sched.Valid or (Sched.OverloadCount > 0) then InfoLabel.Font.Color := clSuiteDanger
  else if N > 0 then InfoLabel.Font.Color := clSuiteWarning
  else InfoLabel.Font.Color := clSuiteMuted;
  T := SelectedTask;
  if (T <> nil) and Sched.Valid and not Doc.HasChildren(Doc.IndexOfId(T.Id)) then
  begin
    G := BuildTaskGraph(Doc, Err);
    if G <> nil then
      try
        I := Doc.IndexOfId(T.Id);
        Pre := Length(G.AllPredecessors(I));
        Suc := Length(G.AllSuccessors(I));
        Leaves := 0;
        for N := 0 to Doc.Count - 1 do
          if not Doc.HasChildren(N) then Inc(Leaves);
        S := Format('%s  •  em cadeia com %d (antes %d, depois %d)  •  em paralelo com %d',
          [T.Id, Pre + Suc, Pre, Suc, Max(0, Leaves - 1 - Pre - Suc)]);
        if Sched[I].Critical then S := S + '  •  critica';
        InfoLabel.Caption := InfoLabel.Caption + '     |     ' + S;
      finally
        G.Free;
      end;
  end;
  OpenToolButton.Enabled := (T <> nil);
  if T <> nil then OpenToolButton.Enabled := PJKindInfo(T.Kind).HasTool;
  OpenToolButton.Caption := 'Abrir na ferramenta';
  if (T <> nil) and (KindToolName(T.Kind) <> '') then OpenToolButton.Caption := 'Abrir no ' + KindToolName(T.Kind);
  if (T<>nil) and (T.Kind=tkPCBFab) and SameText(T.TechValue('ferramenta_sugerida'),'RouterPCB') then OpenToolButton.Caption:='Abrir no RouterPCB';
  if (T <> nil) and PJKindInfo(T.Kind).Fabrication and PJIsGCode(T.Artifact.Path) and
    FileExists(PJArtifactFile(T, FileName)) then OpenToolButton.Caption := 'Abrir no MultiCNC';
end;

procedure TMultiProjectForm.RefreshChains;
var C: TPJChains; I: Integer;
begin
  ChainList.Items.BeginUpdate;
  try
    ChainList.Items.Clear;
    try
      C := TaskChains(Doc);
    except
      C := nil;
    end;
    for I := 0 to High(C) do
      ChainList.Items.Add(Format('Cadeia %d  (%d tarefas)', [I + 1, Length(C[I])]));
  finally
    ChainList.Items.EndUpdate;
  end;
end;

procedure TMultiProjectForm.RefreshAll;
begin
  if FUpdating then Exit;
  FUpdating := True;
  try
    Sched.Compute;
    Options.HighlightCritical := CriticalBox.Checked;
    FillGantt(Gantt, Doc, Sched, Options);
    FillNetwork(Network, Doc, Sched);
    FillBoard(Board, Doc, Sched);
    FillTeam(Team, Doc, Sched, CriticalBox.Checked);
    RefreshChains;
    RefreshSuggestions;
    UpdateHeader;
    if FSelectedId <> '' then SelectTask(FSelectedId);
    UpdateFooter;
    case CurrentStep of
      2: LoadRelationsPage;
      3: LoadResourcesPage;
      4: LoadSchedulePage;
      PAGE_TASK: LoadTaskPage;
    end;
  finally
    FUpdating := False;
  end;
end;

procedure TMultiProjectForm.AsyncRefresh(Data: PtrInt);
begin
  FRefreshQueued := False;
  RefreshAll;
end;

procedure TMultiProjectForm.QueueRefresh;
begin
  if FRefreshQueued then Exit;
  FRefreshQueued := True;
  Application.QueueAsyncCall(@AsyncRefresh, 0);
end;

procedure TMultiProjectForm.AfterCommand(const AId: string);
begin
  if AId <> '' then FSelectedId := AId;
  RefreshAll;
end;

{ ---------------- selecao ---------------- }

function TMultiProjectForm.SelectedTask: TPJTask;
begin
  if FSelectedId = '' then Result := nil else Result := Doc.FindTask(FSelectedId);
end;

function TMultiProjectForm.CurrentTaskIndex: Integer;
begin
  if FSelectedId = '' then Result := -1 else Result := Doc.IndexOfId(FSelectedId);
end;

procedure TMultiProjectForm.SelectTask(const AId: string);
var Keep: Boolean;
begin
  Keep := FUpdating;
  FUpdating := True;
  try
    FSelectedId := AId;
    Gantt.SelectId(AId);
    Network.Selected := Network.IndexOfId(AId);
    Board.Selected := Board.IndexOfId(AId);
    Team.SelectId(AId);
  finally
    FUpdating := Keep;
  end;
  if not FUpdating then
  begin
    UpdateFooter;
    case CurrentStep of
      2: LoadRelationsPage;
      PAGE_TASK: LoadTaskPage;
    end;
  end;
end;

procedure TMultiProjectForm.GanttSelect(Sender: TObject; ARow: Integer);
begin
  if FUpdating or (ARow < 0) or (Gantt.Row(ARow).Id = '') then Exit;
  SelectTask(Gantt.Row(ARow).Id);
end;

procedure TMultiProjectForm.GanttDblClick(Sender: TObject; ARow: Integer);
begin
  if (ARow >= 0) and (Gantt.Row(ARow).Id <> '') then
  begin
    SelectTask(Gantt.Row(ARow).Id);
    ShowStep(PAGE_TASK);
  end;
end;

procedure TMultiProjectForm.GanttEdited(Sender: TObject; ARow, ACol: Integer; var AText: string;
  var Accept: Boolean);
var T: TPJTask; Err: string;
begin
  T := Doc.FindTask(Gantt.Row(ARow).Id);
  if T = nil then begin Accept := False; Exit; end;
  Err := '';
  case ACol of
    GC_NAME:
      if Trim(AText) = '' then Err := 'a tarefa precisa de um nome'
      else if AText <> T.Name then
      begin
        Doc.BeginChange('Renomear tarefa');
        T.Name := Trim(AText);
        Doc.EndChange;
      end;
    GC_DUR:
      if Doc.SetDurationText(T.Id, AText, Err) then AText := Doc.FormatDur(T.Duration);
    GC_PRED:
      if Doc.SetPredecessorsText(T.Id, AText, Err) then AText := Doc.PredecessorsText(T.Id);
    GC_RES:
      begin
        AText := Trim(StringReplace(AText, Trim(PJ_OVERLOAD_MARK), '', [rfReplaceAll]));
        if Doc.SetResourcesText(T.Id, AText, Err) then AText := Doc.ResourcesText(T.Id);
      end;
  end;
  Accept := Err = '';
  if Accept then
  begin
    FSelectedId := T.Id;
    SetStatus('');
    QueueRefresh;
  end
  else
    SetStatus(T.Id + ': ' + Err, 3);
end;

function TMultiProjectForm.GanttWorkingDay(Sender: TObject; ADay: TDateTime): Boolean;
begin
  try
    Result := Doc.ProjectCalendar.IsWorkingDay(ADay);
  except
    Result := not (DayOfWeek(ADay) in [1, 7]);
  end;
end;

procedure TMultiProjectForm.GanttIcon(Sender: TObject; ACanvas: TCanvas; ARow: Integer; const ARect: TRect);
var I: Integer; K: TPJTaskKind;
begin
  I := Gantt.Row(ARow).Tag;
  if (I < 0) or (I >= Doc.Count) then Exit;
  if Doc.HasChildren(I) then K := tkSummary else K := Doc[I].Kind;
  ACanvas.Draw(ARect.Left, ARect.Top, FIcons[K]);
end;

procedure TMultiProjectForm.NetSelect(Sender: TObject; ANode: Integer);
begin
  if FUpdating or (ANode < 0) then Exit;
  SelectTask(Network.Node(ANode).Id);
end;

procedure TMultiProjectForm.NetDblClick(Sender: TObject; ANode: Integer);
begin
  if ANode < 0 then Exit;
  SelectTask(Network.Node(ANode).Id);
  ShowStep(PAGE_TASK);
end;

procedure TMultiProjectForm.NetLink(Sender: TObject; AFromNode, AToNode: Integer; AAlt: Boolean);
var A, B, Err: string; LT: TAITaskLinkType;
begin
  A := Network.Node(AFromNode).Id;
  B := Network.Node(AToNode).Id;
  if AAlt then LT := atlSS else LT := atlFS;
  if Doc.AddLink(A, B, LT, AINoLag, False, Err) then
  begin
    SetStatus(Format('Vinculo %s -> %s (%s) criado.', [A, B, AILinkTypeCode(LT)]), 1);
    FSelectedId := B;
    QueueRefresh;
  end
  else
    SetStatus(Err, 3);
end;

procedure TMultiProjectForm.BoardSelect(Sender: TObject; ACard: Integer);
begin
  if FUpdating or (ACard < 0) then Exit;
  SelectTask(Board.Card(ACard).Id);
end;

procedure TMultiProjectForm.BoardDblClick(Sender: TObject; ACard: Integer);
begin
  if ACard < 0 then Exit;
  SelectTask(Board.Card(ACard).Id);
  ShowStep(PAGE_TASK);
end;

procedure TMultiProjectForm.BoardMove(Sender: TObject; ACard, ANewColumn: Integer; var Accept: Boolean;
  var Reason: string);
var Id: string;
begin
  Id := Board.Card(ACard).Id;
  CheckArtifacts(nil);
  Accept := SetTaskState(Doc, Id, BOARD_STATES[ANewColumn], Reason);
  if Accept then
  begin
    SetStatus(Format('%s: %s', [Id, StateCaption(BOARD_STATES[ANewColumn])]), 1);
    FSelectedId := Id;
    QueueRefresh;
  end
  else
    SetStatus(Reason, 3);
end;

{ ---------------- barra e lateral ---------------- }

procedure TMultiProjectForm.NavClick(Sender: TObject);
begin
  ShowStep(TSuiteButton(Sender).Tag);
end;

procedure TMultiProjectForm.ViewClick(Sender: TObject);
begin
  ShowView(TSuiteButton(Sender).Tag);
end;

procedure TMultiProjectForm.FitClick(Sender: TObject);
begin
  case CurrentView of
    VIEW_GANTT: Gantt.FitToRows;
    VIEW_NETWORK: Network.FitAll;
    VIEW_TEAM: Team.FitToBars;
  end;
end;

procedure TMultiProjectForm.ZoomInClick(Sender: TObject);
begin
  case CurrentView of
    VIEW_GANTT: Gantt.ZoomBy(1.4);
    VIEW_NETWORK: Network.Zoom(1.2);
    VIEW_TEAM: Team.ZoomBy(1.4);
  end;
end;

procedure TMultiProjectForm.ZoomOutClick(Sender: TObject);
begin
  case CurrentView of
    VIEW_GANTT: Gantt.ZoomBy(1 / 1.4);
    VIEW_NETWORK: Network.Zoom(1 / 1.2);
    VIEW_TEAM: Team.ZoomBy(1 / 1.4);
  end;
end;

procedure TMultiProjectForm.FilterChange(Sender: TObject);
begin
  if FUpdating then Exit;
  case FilterCombo.ItemIndex of
    1: Options.Filter := pfCritical;
    2: Options.Filter := pfLate;
    3: Options.Filter := pfSuggested;
    4: begin Options.Filter := pfChain; Options.FilterChain := Max(0, ChainList.ItemIndex); end;
    5: Options.Filter := pfRules;
  else
    Options.Filter := pfAll;
  end;
  Options.GroupBy := TPJGroupBy(EnsureRange(GroupCombo.ItemIndex, 0, Ord(High(TPJGroupBy))));
  RefreshAll;
end;

procedure TMultiProjectForm.ChainClick(Sender: TObject);
begin
  if FilterCombo.ItemIndex = 4 then FilterChange(Sender);
end;

procedure TMultiProjectForm.NewClick(Sender: TObject);
begin
  if Doc.Modified and (MessageDlg('MultiProject', 'Descartar as alteracoes do projeto atual?',
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes) then Exit;
  NewProject;
end;

procedure TMultiProjectForm.OpenClick(Sender: TObject);
var D: TOpenDialog;
begin
  if Doc.Modified and (MessageDlg('MultiProject', 'Descartar as alteracoes do projeto atual?',
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes) then Exit;
  D := TOpenDialog.Create(Self);
  try
    D.Filter := 'MultiProject (*.mproj)|*.mproj|Todos os arquivos|*.*';
    if D.Execute then OpenFile(D.FileName);
  finally
    D.Free;
  end;
end;

procedure TMultiProjectForm.SaveClick(Sender: TObject);
var D: TSaveDialog;
begin
  if FileName <> '' then
  begin
    SaveFile(FileName);
    Exit;
  end;
  D := TSaveDialog.Create(Self);
  try
    D.Filter := 'MultiProject (*.mproj)|*.mproj';
    D.DefaultExt := 'mproj';
    D.Options := D.Options + [ofOverwritePrompt];
    D.FileName := StringReplace(Trim(Doc.Name), ' ', '_', [rfReplaceAll]) + '.mproj';
    if D.Execute then SaveFile(D.FileName);
  finally
    D.Free;
  end;
end;

procedure TMultiProjectForm.DemoClick(Sender: TObject);
begin
  if Doc.Modified and (MessageDlg('MultiProject', 'Descartar as alteracoes do projeto atual?',
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes) then Exit;
  LoadExample;
end;

procedure TMultiProjectForm.ValidateClick(Sender: TObject);
var L: TPJIssues;
begin
  RefreshAll;
  ShowStep(4);
  L := Doc.Validate;
  if not Sched.Valid then SetStatus('Cronograma nao calculado: ' + Sched.Error, 3)
  else if ErrorCount(L) > 0 then SetStatus(Format('%d erros na validacao. Veja a lista na etapa 5.', [ErrorCount(L)]), 3)
  else if Length(L) + Length(Sched.Issues) > 0 then
    SetStatus(Format('Plano valido com %d avisos.', [Length(L) + Length(Sched.Issues)]), 2)
  else
    SetStatus('Plano valido, sem avisos.', 1);
end;

procedure TMultiProjectForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  CanClose := True;
  if Doc.Modified then
    CanClose := MessageDlg('MultiProject', 'Sair sem salvar as alteracoes?', mtConfirmation,
      [mbYes, mbNo], 0) = mrYes;
end;

procedure TMultiProjectForm.FormKey(Sender: TObject; var Key: Word; Shift: TShiftState);
var InText: Boolean;
begin
  { nos campos de texto do painel, so os atalhos com Ctrl/F valem }
  InText := (ActiveControl is TCustomEdit) or (ActiveControl is TCustomGrid) or Gantt.Editing;
  if (ssCtrl in Shift) and not (ssShift in Shift) then
    case Key of
      VK_N: begin NewClick(nil); Key := 0; end;
      VK_O: begin OpenClick(nil); Key := 0; end;
      VK_S: begin SaveClick(nil); Key := 0; end;
      VK_Z: if not InText then begin UndoClick(nil); Key := 0; end;
      VK_Y: if not InText then begin RedoClick(nil); Key := 0; end;
      VK_F2: begin LinkNextClick(nil); Key := 0; end;
    end
  else if (ssCtrl in Shift) and (ssShift in Shift) and (Key = VK_F2) then
  begin
    if SelectedTask <> nil then
    begin
      RelPredEdit.Text := '';
      RelPredApply(nil);
    end;
    Key := 0;
  end
  else if (Shift = [ssShift]) and (Key = VK_F2) then
  begin
    ShowStep(PAGE_TASK);
    Key := 0;
  end
  else if (Shift = [ssAlt, ssShift]) and (Key = VK_RIGHT) then begin IndentClick(nil); Key := 0; end
  else if (Shift = [ssAlt, ssShift]) and (Key = VK_LEFT) then begin OutdentClick(nil); Key := 0; end
  else if (Shift = []) and not InText then
    case Key of
      VK_INSERT: begin InsertClick(nil); Key := 0; end;
      VK_DELETE: begin DeleteClick(nil); Key := 0; end;
      VK_F9: begin RecalcClick(nil); Key := 0; end;
      VK_ESCAPE: if CurrentStep = PAGE_TASK then begin TaskBack(nil); Key := 0; end;
    end
  else if (Shift = []) and (Key = VK_F9) then
  begin
    RecalcClick(nil);
    Key := 0;
  end;
end;

{ ---------------- etapa 1: objetivo ---------------- }

procedure TMultiProjectForm.LoadObjectivePage;
var I: Integer;
begin
  OName.Text := Doc.Name;
  OShort.Text := Doc.ObjectiveShort;
  OLong.Text := Doc.ObjectiveLong;
  OScope.Text := Doc.ObjectiveScope;
  OSuccess.Lines.Clear;
  for I := 0 to High(Doc.ObjectiveSuccess) do OSuccess.Lines.Add(Doc.ObjectiveSuccess[I].Text);
  OStart.Text := FormatBRDateTime(Doc.StartDate);
  OCalendar.Items.Clear;
  for I := 0 to Doc.CalendarCount - 1 do OCalendar.Items.Add(Doc.Calendars[I].Name);
  OCalendar.ItemIndex := Doc.IndexOfCalendar(Doc.ProjectCalendarName);
  ORevision.Text := Doc.Revision;
  OAuthor.Text := Doc.Author;
  GateBox.Checked := Doc.FabricationGate;
end;

procedure TMultiProjectForm.ObjectiveApply(Sender: TObject);
var D: TDateTime; I, N: Integer; Old: TPJCriteria; Err: string;
begin
  if not TryParseBRDateTime(OStart.Text, D) or (D = 0) then
  begin
    SetStatus('Inicio invalido: use dd/mm/aaaa hh:mm', 3);
    Exit;
  end;
  Old := Doc.ObjectiveSuccess;
  Doc.BeginChange('Editar objetivo');
  try
    Doc.Name := Trim(OName.Text);
    Doc.ObjectiveShort := Trim(OShort.Text);
    Doc.ObjectiveLong := OLong.Text;
    Doc.ObjectiveScope := OScope.Text;
    N := 0;
    Doc.ObjectiveSuccess := nil;
    for I := 0 to OSuccess.Lines.Count - 1 do
      if Trim(OSuccess.Lines[I]) <> '' then
      begin
        SetLength(Doc.ObjectiveSuccess, N + 1);
        Doc.ObjectiveSuccess[N].Id := Format('OK-%d', [N + 1]);
        Doc.ObjectiveSuccess[N].Text := Trim(OSuccess.Lines[I]);
        { mantem estado e evidencia de criterio que ja existia com o mesmo texto }
        Doc.ObjectiveSuccess[N].State := csPending;
        Doc.ObjectiveSuccess[N].Evidence := '';
        if (N <= High(Old)) and (Old[N].Text = Doc.ObjectiveSuccess[N].Text) then
          Doc.ObjectiveSuccess[N] := Old[N];
        Inc(N);
      end;
    Doc.StartDate := D;
    if OCalendar.ItemIndex >= 0 then Doc.ProjectCalendarName := OCalendar.Items[OCalendar.ItemIndex];
    Doc.Revision := Trim(ORevision.Text);
    Doc.Author := Trim(OAuthor.Text);
    if not PJSetFabricationGate(Doc,GateBox.Checked,Err) then SetStatus(Err,3);
  finally
    Doc.EndChange;
  end;
  RefreshAll;
  SetStatus('Objetivo atualizado.', 1);
end;

{ ---------------- etapa 2: tarefas ---------------- }

function TMultiProjectForm.InsertAt: Integer;
var I: Integer;
begin
  { como no Project: a nova tarefa entra abaixo da selecionada (ou no fim) }
  I := CurrentTaskIndex;
  if I < 0 then Result := Doc.Count else Result := Doc.SubtreeEnd(I) + 1;
end;

procedure TMultiProjectForm.InsertClick(Sender: TObject);
var K: TPJTaskKind; T: TPJTask; At, Sel: Integer;
begin
  K := tkPart;
  if KindCombo.ItemIndex >= 0 then K := TPJTaskKind(PtrInt(KindCombo.Items.Objects[KindCombo.ItemIndex]));
  At := InsertAt;
  Sel := CurrentTaskIndex;
  T := Doc.InsertTask(At, K, 'Nova ' + LowerCase(KindCaption(K)), 'Descreva a tarefa');
  if (Sel >= 0) and (At < Doc.Count) then T.Level := Doc[Sel].Level;
  if K = tkPart then T.Process := prPrint3D;
  AfterCommand(T.Id);
  SetStatus(T.Id + ' inserida. Edite o nome na tabela ou em Detalhes.', 1);
end;

procedure TMultiProjectForm.InsertSummaryClick(Sender: TObject);
var T: TPJTask; Sel: Integer;
begin
  Sel := CurrentTaskIndex;
  T := Doc.InsertTask(InsertAt, tkSummary, 'Novo subsistema', 'Agrupa tarefas');
  if Sel >= 0 then T.Level := Doc[Sel].Level;
  AfterCommand(T.Id);
end;

procedure TMultiProjectForm.InsertMilestoneClick(Sender: TObject);
var T: TPJTask; Sel: Integer;
begin
  Sel := CurrentTaskIndex;
  T := Doc.InsertTask(InsertAt, tkMilestone, 'Novo marco', 'Ponto de controle');
  if Sel >= 0 then T.Level := Doc[Sel].Level;
  AfterCommand(T.Id);
end;

procedure TMultiProjectForm.IndentClick(Sender: TObject);
begin
  if FSelectedId = '' then Exit;
  if Doc.Indent(FSelectedId) then AfterCommand
  else if Doc.LastError <> '' then SetStatus(Doc.LastError, 3)
  else SetStatus('Recuar: a tarefa precisa de uma irma acima no mesmo nivel.', 2);
end;

procedure TMultiProjectForm.OutdentClick(Sender: TObject);
begin
  if FSelectedId = '' then Exit;
  if Doc.Outdent(FSelectedId) then AfterCommand
  else if Doc.LastError <> '' then SetStatus(Doc.LastError, 3)
  else SetStatus('A tarefa ja esta no primeiro nivel.', 2);
end;

procedure TMultiProjectForm.UpClick(Sender: TObject);
begin
  if (FSelectedId <> '') and Doc.MoveUp(FSelectedId) then AfterCommand;
end;

procedure TMultiProjectForm.DownClick(Sender: TObject);
begin
  if (FSelectedId <> '') and Doc.MoveDown(FSelectedId) then AfterCommand;
end;

procedure TMultiProjectForm.DeleteClick(Sender: TObject);
var Id, NextId: string; I: Integer;
begin
  if FSelectedId = '' then Exit;
  Id := FSelectedId;
  I := Doc.IndexOfId(Id);
  NextId := '';
  if (I >= 0) and (Doc.SubtreeEnd(I) + 1 < Doc.Count) then NextId := Doc[Doc.SubtreeEnd(I) + 1].Id
  else if I > 0 then NextId := Doc[I - 1].Id;
  if Doc.DeleteTask(Id) then
  begin
    FSelectedId := NextId;
    AfterCommand;
    SetStatus(Id + ' excluida (Ctrl+Z desfaz).', 1);
  end;
end;

procedure TMultiProjectForm.UndoClick(Sender: TObject);
var D: string;
begin
  D := Doc.UndoDescription;
  if Doc.Undo then
  begin
    AfterCommand;
    SetStatus('Desfeito: ' + D, 1);
  end;
end;

procedure TMultiProjectForm.RedoClick(Sender: TObject);
var D: string;
begin
  D := Doc.RedoDescription;
  if Doc.Redo then
  begin
    AfterCommand;
    SetStatus('Refeito: ' + D, 1);
  end;
end;

procedure TMultiProjectForm.TaskPageClick(Sender: TObject);
begin
  if SelectedTask <> nil then ShowStep(PAGE_TASK)
  else SetStatus('Selecione uma tarefa.', 2);
end;

{ ---------------- etapa 3: relacoes ---------------- }

procedure TMultiProjectForm.LoadRelationsPage;
var T: TPJTask; I: Integer; L: TPJLink; S: string; Item: TAIPredecessorItem;
begin
  T := SelectedTask;
  RelList.Items.Clear;
  RelTarget.Items.Clear;
  if T = nil then
  begin
    RelTaskLabel.Caption := 'Selecione uma tarefa';
    RelPredEdit.Text := '';
    Exit;
  end;
  RelTaskLabel.Caption := T.Id + '  ' + T.Name;
  RelPredEdit.Text := Doc.PredecessorsText(T.Id);
  for I := 0 to Doc.Count - 1 do
    if Doc[I].Id <> T.Id then RelTarget.Items.Add(Doc[I].Id + '  ' + Doc[I].Name);
  if RelTarget.Items.Count > 0 then RelTarget.ItemIndex := 0;
  for I := 0 to Doc.LinkCount - 1 do
  begin
    L := Doc.Links[I];
    if not SameText(L.FromId, T.Id) and not SameText(L.ToId, T.Id) then Continue;
    Item.Id := ''; Item.LinkType := L.LinkType; Item.Lag := L.Lag;
    S := AIFormatPredecessor(Item, Doc.MinutesPerDay, Doc.MinutesPerWeek);
    if S = '' then S := 'TI';
    if L.Artifact then S := S + '  [arquivo]';
    RelList.Items.AddObject(Format('%s -> %s   %s', [L.FromId, L.ToId, S]), TObject(PtrInt(I)));
  end;
end;

procedure TMultiProjectForm.RelPredApply(Sender: TObject);
var T: TPJTask; Err: string;
begin
  T := SelectedTask;
  if T = nil then Exit;
  if Doc.SetPredecessorsText(T.Id, RelPredEdit.Text, Err) then
  begin
    AfterCommand(T.Id);
    SetStatus(T.Id + ': predecessoras atualizadas.', 1);
  end
  else
    SetStatus(Err, 3);
end;

procedure TMultiProjectForm.RelAddClick(Sender: TObject);
var T: TPJTask; Target, Err: string; L: TAITaskLag;
begin
  T := SelectedTask;
  if (T = nil) or (RelTarget.ItemIndex < 0) then Exit;
  Target := Copy(RelTarget.Items[RelTarget.ItemIndex], 1, Pos(' ', RelTarget.Items[RelTarget.ItemIndex]) - 1);
  if not AITryParseLag(RelLagEdit.Text, Doc.MinutesPerDay, Doc.MinutesPerWeek, L, Err) then
  begin
    SetStatus(Err, 3);
    Exit;
  end;
  if Doc.AddLink(T.Id, Target, TAITaskLinkType(Max(0, RelType.ItemIndex)), L, RelArtifact.Checked, Err) then
  begin
    AfterCommand(T.Id);
    SetStatus(Format('Vinculo %s -> %s criado.', [T.Id, Target]), 1);
  end
  else
    SetStatus(Err, 3);
end;

procedure TMultiProjectForm.RelRemoveClick(Sender: TObject);
var I: Integer; L: TPJLink;
begin
  if RelList.ItemIndex < 0 then Exit;
  I := PtrInt(RelList.Items.Objects[RelList.ItemIndex]);
  if (I < 0) or (I >= Doc.LinkCount) then Exit;
  L := Doc.Links[I];
  if Doc.RemoveLink(L.FromId, L.ToId) then AfterCommand;
end;

procedure TMultiProjectForm.LinkNextClick(Sender: TObject);
var I, J: Integer; Err: string;
begin
  { Ctrl+F2 com selecao unica: vincula a selecionada a proxima tarefa (nao resumo) }
  I := CurrentTaskIndex;
  if I < 0 then Exit;
  J := I + 1;
  while (J < Doc.Count) and Doc.HasChildren(J) do Inc(J);
  if J >= Doc.Count then
  begin
    SetStatus('Nao ha tarefa abaixo para vincular.', 2);
    Exit;
  end;
  if Doc.LinkChain([Doc[I].Id, Doc[J].Id], Err) then
  begin
    AfterCommand(Doc[J].Id);
    SetStatus(Format('Vinculo %s -> %s (TI) criado.', [Doc[I].Id, Doc[J].Id]), 1);
  end
  else
    SetStatus(Err, 3);
end;

{ ---------------- etapa 4: calendarios ---------------- }

function TMultiProjectForm.SelectedResource: TPJResource;
var I: Integer;
begin
  Result := nil;
  if (ResList = nil) or (ResList.ItemIndex < 0) then Exit;
  I := PtrInt(ResList.Items.Objects[ResList.ItemIndex]);
  if (I >= 0) and (I < Doc.ResourceCount) then Result := Doc.Resources[I];
end;

procedure TMultiProjectForm.LoadResourcesPage;
var I, K: Integer; Res: TPJResource; S, KeepId: string;
begin
  { planilha de recursos }
  if SelectedResource <> nil then KeepId := SelectedResource.Id else KeepId := '';
  ResList.Items.BeginUpdate;
  try
    ResList.Items.Clear;
    for I := 0 to Doc.ResourceCount - 1 do
    begin
      Res := Doc.Resources[I];
      S := Res.Name + '  -  ' + ResourceCaption(Res);
      if Sched.Valid and Sched.ResourceOverallocated(Res.Id) then S := '(!) ' + S;
      ResList.Items.AddObject(S, TObject(PtrInt(I)));
    end;
  finally
    ResList.Items.EndUpdate;
  end;
  K := -1;
  for I := 0 to ResList.Items.Count - 1 do
    if (KeepId <> '') and SameText(Doc.Resources[PtrInt(ResList.Items.Objects[I])].Id, KeepId) then K := I;
  if (K < 0) and (ResList.Items.Count > 0) then K := 0;
  ResList.ItemIndex := K;
  RCalendar.Items.Clear;
  RCalendar.Items.Add('(calendario do projeto)');
  for I := 0 to Doc.CalendarCount - 1 do RCalendar.Items.Add(Doc.Calendars[I].Name);
  ResSelect(nil);
  { calendarios }
  K := CalList.ItemIndex;
  CalList.Items.Clear;
  for I := 0 to Doc.CalendarCount - 1 do
    CalList.Items.Add(Doc.Calendars[I].Name + IfThen(SameText(Doc.Calendars[I].Name, Doc.ProjectCalendarName), '  (projeto)', ''));
  if (K < 0) or (K >= CalList.Items.Count) then K := Max(0, Doc.IndexOfCalendar(Doc.ProjectCalendarName));
  if CalList.Items.Count > 0 then CalList.ItemIndex := K;
  CalSelect(nil);
end;

procedure TMultiProjectForm.CalSelect(Sender: TObject);
var C: TAIWorkCalendar; I: Integer; E: TAICalendarException;
begin
  CalExcList.Items.Clear;
  if (CalList.ItemIndex < 0) or (CalList.ItemIndex >= Doc.CalendarCount) then Exit;
  C := Doc.Calendars[CalList.ItemIndex];
  for I := 0 to C.ExceptionCount - 1 do
  begin
    E := C.ExceptionAt(I);
    CalExcList.Items.Add(FormatDateTime('dd"/"mm"/"yyyy ddd', E.Day) + '  ' + E.Name +
      IfThen(Length(E.Intervals) > 0, '  (expediente especial)', ''));
  end;
end;

procedure TMultiProjectForm.CalAddExceptionClick(Sender: TObject);
var D: TDateTime; C: TAIWorkCalendar;
begin
  if (CalList.ItemIndex < 0) or not TryParseBRDateTime(CalDateEdit.Text, D) or (D = 0) then
  begin
    SetStatus('Data invalida: use dd/mm/aaaa', 3);
    Exit;
  end;
  C := Doc.Calendars[CalList.ItemIndex];
  Doc.BeginChange('Adicionar folga');
  try
    C.AddHoliday(D, Trim(CalNameEdit.Text));
  finally
    Doc.EndChange;
  end;
  RefreshAll;
  LoadResourcesPage;
  SetStatus('Folga adicionada em ' + C.Name + '.', 1);
end;

procedure TMultiProjectForm.CalRemoveExceptionClick(Sender: TObject);
var C: TAIWorkCalendar; E: TAICalendarException;
begin
  if (CalList.ItemIndex < 0) or (CalExcList.ItemIndex < 0) then Exit;
  C := Doc.Calendars[CalList.ItemIndex];
  E := C.ExceptionAt(CalExcList.ItemIndex);
  Doc.BeginChange('Remover folga');
  try
    C.RemoveException(E.Day);
  finally
    Doc.EndChange;
  end;
  RefreshAll;
  LoadResourcesPage;
end;

procedure TMultiProjectForm.CalNewClick(Sender: TObject);
var N: string; K: Integer;
begin
  K := 1;
  repeat
    N := 'calendario' + IntToStr(K);
    Inc(K);
  until Doc.IndexOfCalendar(N) < 0;
  Doc.AddCalendar(N, Doc.ProjectCalendar);
  RefreshAll;
  LoadResourcesPage;
  CalList.ItemIndex := Doc.IndexOfCalendar(N);
  CalSelect(nil);
  SetStatus('Calendario "' + N + '" criado a partir do calendario do projeto.', 1);
end;

procedure TMultiProjectForm.ResSelect(Sender: TObject);
var Res: TPJResource; Peak: Double; W: Int64;
begin
  Res := SelectedResource;
  RName.Text := ''; RRole.Text := ''; REmail.Text := ''; RUnits.Text := ''; RGroup.Text := '';
  RType.ItemIndex := -1; RMachine.ItemIndex := -1; RCalendar.ItemIndex := 0;
  ResInfo.Caption := IfThen(Doc.ResourceCount = 0, 'Nenhum recurso. Crie pessoas e maquinas acima.', '');
  if Res = nil then Exit;
  RName.Text := Res.Name;
  RType.ItemIndex := Ord(Res.RType);
  RRole.Text := Res.Role;
  REmail.Text := Res.Email;
  RMachine.ItemIndex := Ord(Res.MachineType);
  RMachine.Enabled := Res.RType = rtMachine;
  if Res.RType = rtMaterial then RUnits.Text := Res.MaterialUnit
  else RUnits.Text := IntToStr(Round(Res.MaxUnits * 100));
  RCalendar.ItemIndex := Max(0, Doc.IndexOfCalendar(Res.CalendarName) + 1);
  if Res.CalendarName = '' then RCalendar.ItemIndex := 0;
  RGroup.Text := Res.Group;
  if Sched.Valid then
  begin
    W := Sched.ResourceWork(Res.Id);
    Peak := Sched.ResourcePeak(Res.Id);
    ResInfo.Caption := Format('%s  •  %d tarefa(s)  •  trabalho %s  •  pico %d%%',
      [Res.Id, Length(Doc.AssignmentsOfResource(Res.Id)), Doc.FormatDur(AIMakeDuration(W, aduHour)), Round(Peak * 100)]);
    if Sched.ResourceOverallocated(Res.Id) then
    begin
      ResInfo.Caption := ResInfo.Caption + LineEnding + 'Superalocado: veja a vista Equipe ou nivele na etapa 5.';
      ResInfo.Font.Color := clSuiteDanger;
    end
    else
      ResInfo.Font.Color := clSuiteText;
  end;
end;

procedure TMultiProjectForm.ResApply(Sender: TObject);
var Res, Other: TPJResource; U: Integer; Id: string;
begin
  Res := SelectedResource;
  if Res = nil then Exit;
  if Trim(RName.Text) = '' then begin SetStatus('O recurso precisa de um nome.', 3); Exit; end;
  Other := Doc.FindResource(Trim(RName.Text));
  if (Other <> nil) and (Other <> Res) then
  begin
    SetStatus('Ja existe um recurso chamado "' + Trim(RName.Text) + '".', 3);
    Exit;
  end;
  U := 0;
  if (RType.ItemIndex <> Ord(rtMaterial)) and (RType.ItemIndex <> Ord(rtCost)) then
    if not TryStrToInt(Trim(StringReplace(RUnits.Text, '%', '', [])), U) or (U < 0) or (U > 10000) then
    begin
      SetStatus('Unidades maximas: um numero em %, por exemplo 100 ou 200.', 3);
      Exit;
    end;
  Id := Res.Id;
  Doc.BeginChange('Editar recurso');
  try
    Res.Name := Trim(RName.Text);
    Res.RType := TPJResourceType(Max(0, RType.ItemIndex));
    Res.Role := Trim(RRole.Text);
    Res.Email := Trim(REmail.Text);
    if Res.RType = rtMachine then Res.MachineType := TPJMachineType(Max(0, RMachine.ItemIndex))
    else Res.MachineType := pmNone;
    if Res.RType = rtMaterial then
    begin
      Res.MaterialUnit := Trim(RUnits.Text);
      Res.MaxUnits := 0;
    end
    else if Res.RType = rtCost then Res.MaxUnits := 0
    else Res.MaxUnits := U / 100;
    if RCalendar.ItemIndex <= 0 then Res.CalendarName := ''
    else Res.CalendarName := RCalendar.Items[RCalendar.ItemIndex];
    Res.Group := Trim(RGroup.Text);
  finally
    Doc.EndChange;
  end;
  RefreshAll;
  SetStatus(Res.Name + ' atualizado.', 1);
end;

procedure TMultiProjectForm.ResNew(AType: TPJResourceType; const ABase: string);
var N: string; K, I: Integer; Res: TPJResource;
begin
  K := 1;
  N := ABase;
  while Doc.IndexOfResource(N) >= 0 do
  begin
    Inc(K);
    N := ABase + ' ' + IntToStr(K);
  end;
  Res := Doc.AddResource(N, AType);
  if AType = rtMachine then Res.Group := 'Oficina'
  else if AType = rtPerson then Res.Group := 'Equipe';
  if AType = rtMaterial then Res.MaterialUnit := 'kg';
  RefreshAll;
  LoadResourcesPage;
  for I := 0 to ResList.Items.Count - 1 do
    if Doc.Resources[PtrInt(ResList.Items.Objects[I])] = Res then ResList.ItemIndex := I;
  ResSelect(nil);
  if RName.CanFocus then RName.SetFocus;
  SetStatus(Res.Id + ' criado: ajuste o nome e clique Aplicar.', 1);
end;

procedure TMultiProjectForm.ResNewPerson(Sender: TObject);
begin
  ResNew(rtPerson, 'Nova pessoa');
end;

procedure TMultiProjectForm.ResNewMachine(Sender: TObject);
begin
  ResNew(rtMachine, 'Nova maquina');
end;

procedure TMultiProjectForm.ResNewMaterial(Sender: TObject);
begin
  ResNew(rtMaterial, 'Novo material');
end;

procedure TMultiProjectForm.ResDelete(Sender: TObject);
var Res: TPJResource; N, Id: string;
begin
  Res := SelectedResource;
  if Res = nil then Exit;
  N := Res.Name;
  Id := Res.Id;
  if Doc.DeleteResource(Id) then
  begin
    RefreshAll;
    SetStatus(N + ' excluido, com as atribuicoes (Ctrl+Z desfaz).', 1);
  end;
end;

procedure TMultiProjectForm.ResImport(Sender: TObject);
var NAdd, NUpd: Integer; Err: string;
begin
  if ImportMachines(Doc, '', NAdd, NUpd, Err) then
  begin
    RefreshAll;
    SetStatus(Format('Maquinas do MultiCNC: %d nova(s), %d atualizada(s).', [NAdd, NUpd]), 1);
  end
  else
    SetStatus(Err, 3);
end;

procedure TMultiProjectForm.LevelClick(Sender: TObject);
var R: TPJLevelResult;
begin
  R := LevelProject(Doc, LevelSlackBox.Checked);
  try
    AfterCommand;
    if R.Error <> '' then SetStatus(LevelSummary(R), 3)
    else if R.Unresolved.Count > 0 then SetStatus(LevelSummary(R), 2)
    else SetStatus(LevelSummary(R), 1);
  finally
    R.Unresolved.Free;
  end;
end;

procedure TMultiProjectForm.ClearLevelClick(Sender: TObject);
begin
  if ClearLeveling(Doc) then
  begin
    AfterCommand;
    SetStatus('Nivelamento limpo: as datas voltaram ao cronograma original.', 1);
  end
  else
    SetStatus('O projeto nao esta nivelado.', 2);
end;

{ ---------------- vista Equipe ---------------- }

procedure TMultiProjectForm.TeamSelect(Sender: TObject; ABar: Integer);
begin
  if FUpdating or (ABar < 0) then Exit;
  SelectTask(Team.Bar(ABar).Id);
end;

procedure TMultiProjectForm.TeamDblClick(Sender: TObject; ABar: Integer);
begin
  if ABar < 0 then Exit;
  SelectTask(Team.Bar(ABar).Id);
  ShowStep(PAGE_TASK);
end;

procedure TMultiProjectForm.TeamReassign(Sender: TObject; ABar, ANewRow: Integer; var Accept: Boolean;
  var Reason: string);
var
  TaskId, NewId, OldId, Err: string;
  T: TPJTask;
  Res: TPJResource;
  A: Integer;
  U: Double;
  Need: TPJMachineTypes;
begin
  Accept := False;
  TaskId := Team.Bar(ABar).Id;
  T := Doc.FindTask(TaskId);
  if T = nil then Exit;
  A := Team.Bar(ABar).Tag;
  NewId := Team.Row(ANewRow).Id;
  OldId := '';
  U := 1;
  if (A >= 0) and (A < Doc.AssignmentCount) then
  begin
    OldId := Doc.Assignments[A].ResourceId;
    U := Doc.Assignments[A].Units;
  end;
  if NewId = PJ_TEAM_UNASSIGNED then
  begin
    if OldId = '' then Exit;
    Accept := True;
    Doc.Unassign(TaskId, OldId);
    SetStatus(Format('%s: %s removido da tarefa.', [TaskId, Doc.FindResource(OldId).Name]), 1);
    FSelectedId := TaskId;
    QueueRefresh;
    Exit;
  end;
  Res := Doc.FindResource(NewId);
  if Res = nil then Exit;
  if Doc.IndexOfAssignment(TaskId, Res.Id) >= 0 then
  begin
    Reason := Format('%s ja esta com %s', [TaskId, Res.Name]);
    SetStatus(Reason, 3);
    Exit;
  end;
  Need := MachineTypesFor(T.Kind);
  if Res.RType = rtMachine then
  begin
    if Need = [] then Reason := Format('%s (%s) nao usa maquina', [TaskId, KindCaption(T.Kind)])
    else if not (Res.MachineType in Need) then
      Reason := Format('%s (%s) precisa de %s; %s e %s', [TaskId, KindCaption(T.Kind),
        MachineTypesCaption(Need), Res.Name, MachineTypeCaption(Res.MachineType)]);
    if Reason <> '' then
    begin
      SetStatus(Reason, 3);
      Exit;
    end;
  end;
  Doc.BeginChange('Reatribuir recurso');
  try
    if OldId <> '' then Doc.Unassign(TaskId, OldId);
    Accept := Doc.Assign(TaskId, Res.Id, U, Err);
  finally
    Doc.EndChange;
  end;
  if not Accept then
  begin
    Doc.Undo;
    Reason := Err;
    SetStatus(Err, 3);
    Exit;
  end;
  if OldId <> '' then
    SetStatus(Format('%s: %s -> %s.', [TaskId, Doc.FindResource(OldId).Name, Res.Name]), 1)
  else
    SetStatus(Format('%s atribuida a %s.', [TaskId, Res.Name]), 1);
  FSelectedId := TaskId;
  QueueRefresh;
end;

{ ---------------- etapa 5: cronograma ---------------- }

procedure TMultiProjectForm.LoadSchedulePage;
var L: TPJIssues; I: Integer; S: string;
begin
  if Sched.Valid then
    SchedInfo.Caption := Format('Inicio %s' + LineEnding + 'Termino previsto %s' + LineEnding + 'Tarefas criticas: %d',
      [FormatBRDateTime(Sched.ProjectStart), FormatBRDateTime(Sched.ProjectFinish), Sched.CriticalCount])
  else
    SchedInfo.Caption := 'Cronograma nao calculado: ' + Sched.Error;
  CritSlackEdit.Text := Doc.FormatDur(AIMakeDuration(Doc.CriticalSlack, aduHour));
  IssueList.Items.BeginUpdate;
  try
    IssueList.Items.Clear;
    L := Doc.Validate;
    for I := 0 to High(L) do
    begin
      if L[I].Severity = svError then S := 'ERRO  ' else S := 'Aviso  ';
      IssueList.Items.AddObject(S + L[I].Message, TObject(PtrInt(Doc.IndexOfId(L[I].TaskId))));
    end;
    for I := 0 to High(Sched.Issues) do
      IssueList.Items.AddObject('Cronograma  ' + Sched.Issues[I].Message,
        TObject(PtrInt(Doc.IndexOfId(Sched.Issues[I].TaskId))));
    if IssueList.Items.Count = 0 then IssueList.Items.AddObject('Nenhum aviso.', TObject(PtrInt(-1)));
  finally
    IssueList.Items.EndUpdate;
  end;
end;

procedure TMultiProjectForm.RecalcClick(Sender: TObject);
begin
  RefreshAll;
  if Sched.Valid then SetStatus('Cronograma recalculado: termino ' + FormatBRDateTime(Sched.ProjectFinish), 1)
  else SetStatus('Cronograma nao calculado: ' + Sched.Error, 3);
end;

procedure TMultiProjectForm.CritSlackApply(Sender: TObject);
var D: TAIDuration; Err: string;
begin
  if not Doc.ParseDur(CritSlackEdit.Text, D, Err) then
  begin
    SetStatus(Err, 3);
    Exit;
  end;
  Doc.BeginChange('Limiar de critica');
  Doc.CriticalSlack := D.Minutes;
  Doc.EndChange;
  RefreshAll;
end;

procedure TMultiProjectForm.IssueClick(Sender: TObject);
var I: Integer;
begin
  if IssueList.ItemIndex < 0 then Exit;
  I := PtrInt(IssueList.Items.Objects[IssueList.ItemIndex]);
  if (I >= 0) and (I < Doc.Count) then SelectTask(Doc[I].Id);
end;

{ ---------------- etapa 6: acompanhar ---------------- }

procedure TMultiProjectForm.StatusDateApply(Sender: TObject);
var D: TDateTime;
begin
  if not TryParseBRDateTime(StatusDateEdit.Text, D) then
  begin
    SetStatus('Data invalida: use dd/mm/aaaa', 3);
    Exit;
  end;
  Doc.BeginChange('Data de status');
  Doc.StatusDate := D;
  Doc.EndChange;
  RefreshAll;
end;

procedure TMultiProjectForm.GenerateClick(Sender: TObject);
var N: Integer; Why: string;
begin
  CheckArtifacts(nil); N:=PJGenerateSuggestions(Doc,Why,FileName); RefreshAll;
  if N<0 then SetStatus(Why,3)
  else if Why<>'' then SetStatus(Format('%d sugestoes. %s',[N,Why]),2)
  else SetStatus(Format('%d novas sugestoes. Confira e aceite ou recuse na lateral.',[N]),1);
end;
procedure TMultiProjectForm.RefreshSuggestions;
var I: Integer;
begin
  SuggestList.Items.BeginUpdate;
  try
    SuggestList.Items.Clear;
    for I:=0 to Doc.Count-1 do if Doc[I].State=tsSuggested then
      SuggestList.Items.AddObject(Doc[I].Id+' ['+Doc[I].Origin.Rule+'] '+Doc[I].Name,TObject(PtrInt(I)));
  finally SuggestList.Items.EndUpdate; end;
  SuggestList.Enabled:=SuggestList.Items.Count>0;
  AcceptSuggestionButton.Enabled:=SuggestList.Enabled; RejectSuggestionButton.Enabled:=SuggestList.Enabled;
end;
procedure TMultiProjectForm.SuggestionOpen(Sender: TObject);
begin
  if SuggestList.ItemIndex<0 then Exit;
  SelectTask(Doc[PtrInt(SuggestList.Items.Objects[SuggestList.ItemIndex])].Id); ShowStep(PAGE_TASK);
end;
procedure TMultiProjectForm.DecideSuggestions(Accept: Boolean);
var IDs: TPJStrings; I: Integer; Why: string;
begin
  IDs:=nil;
  for I:=0 to SuggestList.Items.Count-1 do if SuggestList.Selected[I] then
  begin
    SetLength(IDs,Length(IDs)+1); IDs[High(IDs)]:=Doc[PtrInt(SuggestList.Items.Objects[I])].Id;
  end;
  if PJDecideSuggestions(Doc,IDs,Accept,Why) then
  begin RefreshAll; SetStatus('Sugestoes atualizadas. Ctrl+Z desfaz a decisao.',1); end
  else SetStatus(Why,2);
end;
procedure TMultiProjectForm.AcceptSuggestions(Sender: TObject);
begin DecideSuggestions(True); end;
procedure TMultiProjectForm.RejectSuggestions(Sender: TObject);
begin DecideSuggestions(False); end;
procedure TMultiProjectForm.CreateFromTemplateFile(const AFileName: string);
var Model: TPJProject;
begin
  Model:=TPJProject.Create;
  try
    LoadProjectFile(Model,AFileName); PJCreateFromTemplate(Doc,Model);
    FileName:=''; FSelectedId:=''; RefreshAll; ShowStep(0);
    SetStatus('Novo projeto criado do modelo. Salve em sua pasta de trabalho.',1);
  finally Model.Free; end;
end;
procedure TMultiProjectForm.TemplateClick(Sender: TObject);
var D: TOpenDialog; Root: string;
begin
  if Doc.Modified and (MessageDlg('MultiProject','Descartar as alteracoes do projeto atual?',mtConfirmation,[mbYes,mbNo],0)<>mrYes) then Exit;
  D:=TOpenDialog.Create(Self);
  try
    Root:=IncludeTrailingPathDelimiter(SuiteRootForExecutable(ParamStr(0)));
    D.InitialDir:=Root+'models'+DirectorySeparator+'multiproject';
    if not DirectoryExists(D.InitialDir) then D.InitialDir:=Root+'documentation'+DirectorySeparator+'models'+DirectorySeparator+'multiproject';
    D.Filter:='Modelos MultiProject|*.mproj;*.mpt';
    if D.Execute then
      try CreateFromTemplateFile(D.FileName); except on E: Exception do SetStatus(E.Message,3); end;
  finally D.Free; end;
end;
procedure TMultiProjectForm.LatheSheetClick(Sender: TObject);
var T: TPJTask; D: TSaveDialog; FN: string;
begin
  T:=SelectedTask; if (T=nil) or (T.Kind<>tkLathe) then Exit;
  if FileName='' then SaveClick(nil);
  if FileName='' then Exit;
  FN:=ExtractFilePath(ExpandFileName(FileName))+PJDefaultArtifact(T.Kind,T.Id,T.Name);
  D:=TSaveDialog.Create(Self);
  try
    D.FileName:=FN; D.DefaultExt:='md'; D.Filter:='Folha de processo Markdown|*.md'; D.Options:=D.Options+[ofOverwritePrompt];
    if D.Execute then
    try
      PJSaveLatheSheet(Doc,T,D.FileName,True); PJLinkArtifact(Doc,T,FileName,D.FileName);
      CheckArtifacts(nil); RefreshAll; SetStatus('Folha de torno salva: '+D.FileName,1);
    except on E: Exception do SetStatus(E.Message,3); end;
  finally D.Free; end;
end;

procedure TMultiProjectForm.CheckArtifacts(Sender: TObject);
var W: string;
begin
  if FUpdating or FCheckingArtifacts or (FileName = '') or (Doc = nil) then Exit;
  if (Sender = ArtifactTimer) and not Active then Exit;
  FCheckingArtifacts := True;
  try
    if PJRefreshArtifacts(Doc, FileName, Sender <> ArtifactTimer, W) then
    begin
      UpdateHeader; UpdateFooter; QueueRefresh;
    end;
    if W <> '' then SetStatus(W, 2);
  finally FCheckingArtifacts := False; end;
end;

procedure TMultiProjectForm.LinkArtifactClick(Sender: TObject);
var D: TOpenDialog; T: TPJTask;
begin
  T := SelectedTask; if T = nil then Exit;
  if FileName = '' then SaveClick(nil);
  if FileName = '' then Exit;
  D := TOpenDialog.Create(Self);
  try
    D.InitialDir := ExtractFilePath(FileName); D.Options := D.Options + [ofFileMustExist];
    if D.Execute then
    begin
      PJLinkArtifact(Doc, T, FileName, D.FileName); CheckArtifacts(nil); RefreshAll;
    end;
  finally D.Free; end;
end;

procedure TMultiProjectForm.OpenToolClick(Sender: TObject);
var T: TPJTask; Info: TPJKindInfo; FN, Err, Root: string; R: TSuiteRegistry; N: Integer; OK: Boolean;
begin
  T := SelectedTask; if T = nil then Exit;
  Info := PJKindInfo(T.Kind); if not Info.HasTool then Exit;
  if (T.Kind=tkPCBFab) and SameText(T.TechValue('ferramenta_sugerida'),'RouterPCB') then Info.Tool:=stiRouterPCB;
  if FileName = '' then SaveClick(nil);
  if FileName = '' then Exit;
  Root := ExtractFilePath(ExpandFileName(FileName)); FN := PJArtifactFile(T, FileName);
  if Info.Fabrication and PJIsGCode(FN) and FileExists(FN) then
  begin OpenCNCClick(Sender); Exit; end;
  if FN = '' then FN := Root + PJDefaultArtifact(T.Kind, T.Id, T.Name);
  try
    if not ForceDirectories(ExtractFilePath(FN)) then raise Exception.Create('Nao foi possivel criar a pasta');
    PJWriteTaskContext(Doc, T, FileName, FN);
    R := TSuiteRegistry.Create;
    try
      N := R.Find(Info.Tool); if N < 0 then raise Exception.Create('Ferramenta nao cadastrada');
      if FileExists(FN) then OK := TSuiteLauncher.LaunchArtifact(R.Tool(N), SuiteRootForExecutable(ParamStr(0)), Root, FN, Err, FN + '.task.json')
      else OK := TSuiteLauncher.LaunchNew(R.Tool(N), SuiteRootForExecutable(ParamStr(0)), Root, FN, FN + '.task.json', Err);
    finally R.Free; end;
    if not OK then begin SetStatus(Err, 3); Exit; end;
    if T.Artifact.Path = '' then PJLinkArtifact(Doc, T, FileName, FN);
    SetStatus('Ferramenta aberta. Salve como: ' + FN, 1); RefreshAll;
  except on E: Exception do SetStatus(E.Message, 3); end;
end;

procedure TMultiProjectForm.OpenCNCClick(Sender: TObject);
var T: TPJTask; FN, Err: string; R: TSuiteRegistry; N: Integer;
begin
  T := SelectedTask; if T = nil then Exit;
  FN := PJArtifactFile(T, FileName);
  if not PJKindInfo(T.Kind).Fabrication or not PJIsGCode(FN) or not FileExists(FN) then
  begin SetStatus('Vincule o G-code existente da tarefa de fabricacao', 2); Exit; end;
  R := TSuiteRegistry.Create;
  try
    N := R.Find(stiMultiCNC);
    if (N >= 0) and not TSuiteLauncher.LaunchArtifact(R.Tool(N), SuiteRootForExecutable(ParamStr(0)),
      ExtractFilePath(ExpandFileName(FileName)), FN, Err) then SetStatus(Err, 3);
  finally R.Free; end;
end;

{ ---------------- pagina da tarefa ---------------- }

procedure TMultiProjectForm.LoadTaskPage;
var T: TPJTask; I, Idx: Integer; R: TAICPMResult; Tool, Succ: string;
begin
  T := SelectedTask;
  if T = nil then
  begin
    TIdLabel.Caption := 'Nenhuma tarefa selecionada';
    Exit;
  end;
  Idx := Doc.IndexOfId(T.Id);
  TIdLabel.Caption := Format('ID %s   •   EAP %s', [T.Id, Doc.WBS(Idx)]);
  TName.Text := T.Name;
  TKind.ItemIndex := Ord(T.Kind);
  TProcess.ItemIndex := Ord(T.Process);
  TProcess.Enabled := T.Kind = tkPart;
  TState.ItemIndex := Ord(T.State);
  TMode.ItemIndex := Ord(T.Mode);
  TShort.Text := T.ShortDesc;
  TLong.Text := T.LongDesc;
  for I := 1 to TTechGrid.RowCount - 1 do
  begin
    TTechGrid.Cells[0, I] := ''; TTechGrid.Cells[1, I] := ''; TTechGrid.Cells[2, I] := '';
  end;
  if Length(T.TechItems) + 1 > TTechGrid.RowCount then TTechGrid.RowCount := Length(T.TechItems) + 3;
  for I := 0 to High(T.TechItems) do
  begin
    TTechGrid.Cells[0, I + 1] := T.TechItems[I].Key;
    TTechGrid.Cells[1, I + 1] := T.TechItems[I].Value;
    TTechGrid.Cells[2, I + 1] := T.TechItems[I].UnitName;
  end;
  TTechText.Text := T.TechText;
  for I := 1 to TFuncGrid.RowCount - 1 do
  begin
    TFuncGrid.Cells[0, I] := ''; TFuncGrid.Cells[1, I] := '';
  end;
  if Length(T.FuncSpec) + 1 > TFuncGrid.RowCount then TFuncGrid.RowCount := Length(T.FuncSpec) + 3;
  for I := 0 to High(T.FuncSpec) do
  begin
    TFuncGrid.Cells[0, I + 1] := T.FuncSpec[I].Text;
    TFuncGrid.Cells[1, I + 1] := CRIT_NAMES[T.FuncSpec[I].State];
  end;
  TDuration.Text := Doc.FormatDur(T.Duration);
  TDuration.Enabled := not Doc.HasChildren(Idx);
  if Sched.Valid then
  begin
    R := Sched[Idx];
    TDatesLabel.Caption := Format('Inicio %s   Termino %s' + LineEnding + 'Margem total %s   livre %s%s',
      [FormatBRDateTime(R.Start), FormatBRDateTime(R.Finish),
       Doc.FormatDur(AIMakeDuration(Abs(R.TotalSlack), aduHour)) + IfThen(R.TotalSlack < 0, ' (negativa)', ''),
       Doc.FormatDur(AIMakeDuration(R.FreeSlack, aduHour)), IfThen(R.Critical, '   •   CRITICA', '')]);
  end
  else
    TDatesLabel.Caption := 'Cronograma nao calculado';
  TConstraint.ItemIndex := Ord(T.Constraint);
  TConstraintDate.Text := FormatBRDateTime(T.ConstraintDate);
  TDeadline.Text := FormatBRDateTime(T.Deadline);
  TCalendar.Items.Clear;
  TCalendar.Items.Add('(calendario do projeto)');
  for I := 0 to Doc.CalendarCount - 1 do TCalendar.Items.Add(Doc.Calendars[I].Name);
  TCalendar.ItemIndex := Max(0, Doc.IndexOfCalendar(T.CalendarName) + 1);
  if T.CalendarName = '' then TCalendar.ItemIndex := 0;
  Tool := KindToolName(T.Kind);
  if Tool = '' then TToolLabel.Caption := 'Este tipo de tarefa nao usa ferramenta da suite.'
  else TToolLabel.Caption := Tool + ': ' + T.Artifact.Path + LineEnding + T.Artifact.Status + ' - ' + T.Artifact.CheckMessage;
  TToolLabel.Hint := TToolLabel.Caption; TToolLabel.ShowHint := True;
  ArtifactPathEdit.Text := PJArtifactFile(T, FileName);
  LatheButton.Enabled := T.Kind=tkLathe;
  OpenCNCButton.Enabled := PJKindInfo(T.Kind).Fabrication and
    PJIsGCode(T.Artifact.Path) and FileExists(ArtifactPathEdit.Text);
  Succ := Doc.SuccessorsText(T.Id);
  TPredLabel.Caption := 'Predecessoras: ' + IfThen(Doc.PredecessorsText(T.Id) = '', '(nenhuma)', Doc.PredecessorsText(T.Id)) +
    LineEnding + 'Sucessoras: ' + IfThen(Succ = '', '(nenhuma)', Succ);
  { recursos da tarefa }
  TResEdit.Text := Doc.ResourcesText(T.Id);
  TResCombo.Items.Clear;
  for I in CompatibleResources(Doc, T.Id) do
    TResCombo.Items.AddObject(Doc.Resources[I].Name + '  -  ' + ResourceCaption(Doc.Resources[I]),
      TObject(PtrInt(I)));
  if TResCombo.Items.Count > 0 then TResCombo.ItemIndex := 0;
  TResUnits.Text := '100';
  TResInfo.Caption := '';
  TResInfo.Font.Color := clSuiteMuted;
  if MachineTypesFor(T.Kind) <> [] then
    TResInfo.Caption := 'Precisa de ' + MachineTypesCaption(MachineTypesFor(T.Kind)) + '.';
  if Sched.Valid and Sched.TaskOverallocated(T.Id) then
  begin
    TResInfo.Caption := TResInfo.Caption + IfThen(TResInfo.Caption <> '', LineEnding, '') +
      'Conflito: um recurso desta tarefa esta em outra ao mesmo tempo (vista Equipe).';
    TResInfo.Font.Color := clSuiteDanger;
  end;
  TPriority.Text := IntToStr(T.Priority);
  TOriginLabel.Caption := 'Criada pelo usuario';
  if T.Origin.By='rule' then
  begin
    TOriginLabel.Caption:='Regra '+T.Origin.Rule+':';
    for I:=0 to High(T.Origin.Sources) do TOriginLabel.Caption:=TOriginLabel.Caption+' '+T.Origin.Sources[I];
  end;
  TOriginLabel.Hint:=TOriginLabel.Caption; TOriginLabel.ShowHint:=True;
  TNotes.Text := T.Notes;
end;

procedure TMultiProjectForm.TaskResApply(Sender: TObject);
var T: TPJTask; Err: string;
begin
  T := SelectedTask;
  if T = nil then Exit;
  if Doc.SetResourcesText(T.Id, TResEdit.Text, Err) then
  begin
    AfterCommand(T.Id);
    SetStatus(T.Id + ': recursos atualizados.', 1);
  end
  else
    SetStatus(T.Id + ': ' + Err, 3);
end;

procedure TMultiProjectForm.TaskResAdd(Sender: TObject);
var T: TPJTask; Res: TPJResource; Err: string; U: Double; FS: TFormatSettings;
begin
  T := SelectedTask;
  if (T = nil) or (TResCombo.ItemIndex < 0) then Exit;
  Res := Doc.Resources[PtrInt(TResCombo.Items.Objects[TResCombo.ItemIndex])];
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  if not TryStrToFloat(StringReplace(Trim(StringReplace(TResUnits.Text, '%', '', [])), ',', '.', []), U, FS) then
  begin
    SetStatus('Unidades invalidas: use 100 (%) ou a quantidade do material.', 3);
    Exit;
  end;
  if Res.RType <> rtMaterial then U := U / 100;
  if Doc.Assign(T.Id, Res.Id, U, Err) then
  begin
    AfterCommand(T.Id);
    SetStatus(Format('%s: %s atribuido.', [T.Id, Res.Name]), 1);
  end
  else
    SetStatus(Err, 3);
end;

function CriterionFromName(const S: string): TPJCriterionState;
var C: TPJCriterionState;
begin
  for C := Low(C) to High(C) do
    if SameText(Trim(S), CRIT_NAMES[C]) or SameText(Trim(S), CriterionStateName(C)) then Exit(C);
  Result := csPending;
end;

procedure TMultiProjectForm.TaskApply(Sender: TObject);
var
  T: TPJTask;
  D: TAIDuration;
  CD, DL: TDateTime;
  Err: string;
  I, N, Prio: Integer;
begin
  T := SelectedTask;
  if T = nil then Exit;
  if Trim(TName.Text) = '' then begin SetStatus('A tarefa precisa de um nome.', 3); Exit; end;
  if Trim(TShort.Text) = '' then begin SetStatus('A tarefa precisa de uma descricao curta.', 3); Exit; end;
  if not Doc.ParseDur(TDuration.Text, D, Err) then begin SetStatus('Duracao: ' + Err, 3); Exit; end;
  if (TKind.ItemIndex = Ord(tkMilestone)) and (D.Minutes <> 0) then
  begin
    SetStatus('Marco tem duracao zero.', 3);
    Exit;
  end;
  if not TryParseBRDateTime(TConstraintDate.Text, CD) then begin SetStatus('Data da restricao invalida.', 3); Exit; end;
  if not TryParseBRDateTime(TDeadline.Text, DL) then begin SetStatus('Data limite invalida.', 3); Exit; end;
  if (TConstraint.ItemIndex > Ord(actALAP)) and (CD = 0) then
  begin
    SetStatus('A restricao ' + TConstraint.Text + ' precisa de data.', 3);
    Exit;
  end;
  if not TryStrToInt(Trim(TPriority.Text), Prio) or (Prio < 0) or (Prio > 1000) then
  begin
    SetStatus('Prioridade: um numero de 0 a 1000 (padrao 500).', 3);
    Exit;
  end;
  CheckArtifacts(nil);
  Doc.BeginChange('Editar tarefa');
  try
    T.Name := Trim(TName.Text);
    if T.Kind <> TPJTaskKind(Max(0, TKind.ItemIndex)) then T.Artifact.Status := 'created';
    T.Kind := TPJTaskKind(Max(0, TKind.ItemIndex));
    T.Process := TPJProcess(Max(0, TProcess.ItemIndex));

    T.Mode := TPJScheduleMode(Max(0, TMode.ItemIndex));
    if (T.Mode = smManual) and (T.ManualStart = 0) and Sched.Valid then
      T.ManualStart := Sched[Doc.IndexOfId(T.Id)].Start;
    T.ShortDesc := Trim(TShort.Text);
    T.LongDesc := TLong.Text;
    T.TechItems := nil;
    for I := 1 to TTechGrid.RowCount - 1 do
      if Trim(TTechGrid.Cells[0, I]) <> '' then
        T.AddTechItem(Trim(TTechGrid.Cells[0, I]), Trim(TTechGrid.Cells[1, I]), Trim(TTechGrid.Cells[2, I]));
    T.TechText := TTechText.Text;
    N := 0;
    T.FuncSpec := nil;
    for I := 1 to TFuncGrid.RowCount - 1 do
      if Trim(TFuncGrid.Cells[0, I]) <> '' then
      begin
        Inc(N);
        T.AddCriterion(Format('F-%d', [N]), Trim(TFuncGrid.Cells[0, I]));
        T.FuncSpec[High(T.FuncSpec)].State := CriterionFromName(TFuncGrid.Cells[1, I]);
      end;
    if not Doc.HasChildren(Doc.IndexOfId(T.Id)) then T.Duration := D;
    T.Constraint := TAIConstraintType(Max(0, TConstraint.ItemIndex));
    T.ConstraintDate := CD;
    T.Deadline := DL;
    if TCalendar.ItemIndex <= 0 then T.CalendarName := ''
    else T.CalendarName := TCalendar.Items[TCalendar.ItemIndex];
    T.Notes := TNotes.Text;
    T.Priority := Prio;
    if CanSetState(Doc, T.Id, TPJTaskState(Max(0, TState.ItemIndex)), Err) then
      T.State := TPJTaskState(Max(0, TState.ItemIndex));
  finally
    Doc.EndChange;
  end;
  AfterCommand(T.Id);
  if Err <> '' then SetStatus(Err, 3) else SetStatus(T.Id + ' atualizada.', 1);
end;

procedure TMultiProjectForm.TaskApplyForTest;
begin
  TaskApply(nil);
end;

procedure TMultiProjectForm.InsertClickForTest;
begin
  InsertClick(nil);
end;

procedure TMultiProjectForm.IndentClickForTest;
begin
  IndentClick(nil);
end;

procedure TMultiProjectForm.UndoClickForTest;
begin
  UndoClick(nil);
end;

procedure TMultiProjectForm.LevelForTest(AWithinSlack: Boolean);
begin
  LevelSlackBox.Checked := AWithinSlack;
  LevelClick(nil);
end;

procedure TMultiProjectForm.ClearLevelForTest;
begin
  ClearLevelClick(nil);
end;

procedure TMultiProjectForm.ResApplyForTest;
begin
  ResApply(nil);
end;

procedure TMultiProjectForm.TaskResApplyForTest;
begin
  TaskResApply(nil);
end;

procedure TMultiProjectForm.TaskBack(Sender: TObject);
begin
  ShowStep(1);
end;

end.
