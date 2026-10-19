unit multiassembly_main;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls,
  Dialogs, Graphics, LCLType,
  multiassembly_types, multiassembly_project, multiassembly_solver, multiassembly_library,
  multiassembly_demo, multiassembly_engineering, multiassembly_physics_export,
  multiassembly_manual, multiassembly_mechanical_canvas, multiassembly_electrical_canvas,
  multisuite_controls, multisuite_icons, multisuite_context, multisuite_numfmt,
  multisuite_component_contract, fpjson, jsonparser, multisuite_types, multisuite_registry,
  multisuite_launcher;

const
  MA_STEPS: array[0..5] of string = (
    '1  Projeto', '2  Componentes', '3  Montagem',
    '4  Conexões', '5  Verificar', '6  Documentar'
  );

  STEP_ICONS: array[0..5] of TSuiteIconKind = (
    sikFile, sikLayers, sikAssembly, sikPlug, sikTests, sikExport
  );

type
  TMultiAssemblyForm = class(TForm)
  private
    P: TAssemblyProject;
    FSolver: TKinematicSolver;
    FSimTimer: TTimer;
    FUpdating: Boolean;
    FCurrentStep: Integer;

    // Layout principal
    Header: TSuiteHeader;
    Sidebar: TPanel;
    Work: TPanel;
    ViewBar: TPanel;
    Footer: TPanel;
    Pages: TPageControl;

    // Controles de navegacao lateral
    Nav: array[0..5] of TSuiteButton;
    CompList: TListBox;
    QuickSearch: TEdit;
    SidebarInfo: TLabel;

    // Vistas centrais
    MechView: TMechanicalAssemblyCanvas;
    ElecView: TElectricalAssemblyCanvas;
    ManualStepPanel: TPanel;
    ManualStepTitle: TLabel;
    ManualStepTools: TLabel;
    ManualStepInstr: TMemo;
    ManualStepChecks: TLabel;
    ManualStepComps: TLabel;
    BtnPrevStep, BtnNextStep: TSuiteButton;

    // Barra superior de vistas
    BtnViewIso, BtnViewTop, BtnViewFront, BtnViewSide, BtnViewElec, BtnViewManual: TSuiteButton;
    BtnFit, BtnZoomIn, BtnZoomOut, BtnMate: TSuiteButton;

    // Rodape
    StatusLabel, CoordsLabel: TLabel;
    StateBadge: TSuiteBadge;
    ValidateBtn, PhysicsBtn, DocBtn: TSuiteButton;

    // --- Parametros Aba 1: Projeto ---
    EdProjName, EdProjVer, EdProjAuthor: TEdit;
    CbProjUnits: TComboBox;
    LblProjStats: TLabel;

    // --- Parametros Aba 2: Componentes ---
    EdLibFolder: TEdit;
    CbCatSelect, CbItemSelect: TComboBox;
    EdCompID, EdCompName, EdCompModel, EdCompCategory, EdCompMat: TEdit;
    EdPosX, EdPosY, EdPosZ, EdSizeW, EdSizeH, EdSizeD: TEdit;
    CbCompKind: TComboBox;
    CbCompFixed: TCheckBox;

    // --- Parametros Aba 3: Montagem & Relacoes (SolidWorks) ---
    BtnFixFloat: TSuiteButton;
    CbRelKind: TComboBox;
    CbRelTarget: TComboBox;
    CbRelAxis: TComboBox;
    EdRelMin, EdRelMax: TEdit;
    EdRelRatio, EdRelPitch: TEdit;
    RelList: TListBox;
    LblSolverStatus: TLabel;

    // Move Component / Kinematic Testing
    CbActiveJoints: TComboBox;
    BtnJogMinusLarge, BtnJogMinusSmall, BtnJogPlusSmall, BtnJogPlusLarge: TSuiteButton;
    BtnResetHome, BtnSimulateMotion: TSuiteButton;
    LblCollisionStatus: TLabel;

    // --- Parametros Aba 4: Conexoes ---
    PortList: TListBox;
    EdPortName, EdPortVolt: TEdit;
    CbPortKind: TComboBox;
    CbFromPort, CbToComp, CbToPort: TComboBox;
    EdWireCaption: TEdit;
    WireList: TListBox;

    // --- Parametros Aba 5: Verificar ---
    LblErcSummary: TLabel;
    IssueList: TListBox;

    // --- Parametros Aba 6: Documentar ---
    LblBomSummary: TLabel;
    StepListBox: TListBox;
    EdStepTitle, EdStepTools: TEdit;
    MemStepInstr, MemStepChecks: TMemo;

    // Helpers de construcao da UI
    function CreateButton(AParent: TWinControl; const AText: string; X, Y, W, H: Integer;
      AIcon: TSuiteIconKind; Handler: TNotifyEvent): TSuiteButton;
    function CreateLabel(AParent: TWinControl; const AText: string; X, Y, W, H: Integer): TLabel;
    function CreateField(AParent: TWinControl; const AText, DefaultVal: string; Y: Integer): TEdit;
    function CreateCombo(AParent: TWinControl; const AText: string; Y: Integer): TComboBox;

    procedure BuildProjectPage(S: TScrollBox);
    procedure BuildComponentsPage(S: TScrollBox);
    procedure BuildAssemblyPage(S: TScrollBox);
    procedure BuildConnectionsPage(S: TScrollBox);
    procedure BuildVerifyPage(S: TScrollBox);
    procedure BuildDocumentPage(S: TScrollBox);

    // Eventos e Handlers
    procedure NavClick(Sender: TObject);
    procedure ShowStep(StepIndex: Integer);
    procedure NewProjectClick(Sender: TObject);
    procedure OpenProjectClick(Sender: TObject);
    procedure SaveProjectClick(Sender: TObject);
    procedure LoadDemoClick(Sender: TObject);

    procedure QuickSearchChange(Sender: TObject);
    procedure CompListClick(Sender: TObject);
    procedure OnCanvasSelect(Sender: TObject; const AID: string);

    procedure ViewModeClick(Sender: TObject);
    procedure FitViewClick(Sender: TObject);
    procedure ZoomInClick(Sender: TObject);
    procedure ZoomOutClick(Sender: TObject);
    procedure PrevStepClick(Sender: TObject);
    procedure NextStepClick(Sender: TObject);

    procedure ReloadLibrary;
    procedure BrowseLibFolderClick(Sender: TObject);
    procedure RefreshLibClick(Sender: TObject);
    procedure SaveCompToLibClick(Sender: TObject);
    procedure CategoryChange(Sender: TObject);
    procedure AddFromLibClick(Sender: TObject);
    procedure ApplyCompPropsClick(Sender: TObject);
    procedure DuplicateCompClick(Sender: TObject);
    procedure DeleteCompClick(Sender: TObject);

    procedure QuickNudgeClick(Sender: TObject);
    procedure ZeroPosClick(Sender: TObject);
    procedure AddRelationClick(Sender: TObject);
    procedure DeleteRelationClick(Sender: TObject);
    procedure ToggleFixFloatClick(Sender: TObject);
    procedure RelListClick(Sender: TObject);
    procedure ActiveJointChange(Sender: TObject);
    procedure JogJointClick(Sender: TObject);
    procedure ResetHomeClick(Sender: TObject);
    procedure SimulateMotionClick(Sender: TObject);
    procedure SimTimerTick(Sender: TObject);
    procedure OnCanvasKinematicMove(Sender: TObject; const ComponentID: string);
    procedure MateClick(Sender: TObject);
    procedure OnMateCreated(Sender: TObject);
    procedure OnMateStatus(Sender: TObject; const Msg: string);

    procedure AddPortClick(Sender: TObject);
    procedure FromCompChange;
    procedure ToCompChange(Sender: TObject);
    procedure ConnectWireClick(Sender: TObject);
    procedure DeleteWireClick(Sender: TObject);

    procedure RunAuditClick(Sender: TObject);
    procedure IssueListClick(Sender: TObject);

    procedure ExportBomCSVClick(Sender: TObject);
    procedure ExportBomJSONClick(Sender: TObject);
    procedure StepListClick(Sender: TObject);
    procedure AddStepClick(Sender: TObject);
    procedure SaveStepClick(Sender: TObject);
    procedure DeleteStepClick(Sender: TObject);
    procedure MoveStepUpClick(Sender: TObject);
    procedure MoveStepDownClick(Sender: TObject);
    procedure AssignCompToStepClick(Sender: TObject);
    procedure GenerateHTMLManualClick(Sender: TObject);
    procedure GenerateMarkdownManualClick(Sender: TObject);
    procedure ExportMultiPhysicsClick(Sender: TObject);

    procedure RefreshAll;
    procedure RefreshCompList;
    procedure RefreshSelectedProps;
    procedure RefreshRelations;
    procedure RefreshPortsAndWires;
    procedure RefreshSteps;
    procedure RefreshManualPreview;
    procedure UpdateStatus;
    procedure MarkModified;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

implementation

procedure SaveUnifiedToFile(U: TUnifiedMachine; const FileName: string);
var
  Root, CompObj, LinkObj: TJSONObject;
  CompsArr, LinksArr: TJSONArray;
  I, J: Integer;
  C: TUnifiedComponent;
  L: TUnifiedLink;
  SL: TStringList;
begin
  Root := TJSONObject.Create;
  SL := TStringList.Create;
  try
    CompsArr := TJSONArray.Create;
    for I := 0 to U.Count - 1 do
    begin
      C := U.Component(I);
      CompObj := TJSONObject.Create;
      CompObj.Add('id', C.ID);
      CompObj.Add('name', C.Name);
      CompObj.Add('model', C.Model);
      for J := 0 to C.Parameters.Count - 1 do
        CompObj.Add(C.Parameters.Names[J], C.Parameters.ValueFromIndex[J]);
      CompsArr.Add(CompObj);
    end;
    Root.Add('components', CompsArr);

    LinksArr := TJSONArray.Create;
    for I := 0 to U.LinkCount - 1 do
    begin
      L := U.GetLink(I);
      LinkObj := TJSONObject.Create;
      LinkObj.Add('from_id', L.FromID);
      LinkObj.Add('from_port', L.FromPort);
      LinkObj.Add('to_id', L.ToID);
      LinkObj.Add('to_port', L.ToPort);
      LinkObj.Add('kind', Ord(L.Kind));
      LinksArr.Add(LinkObj);
    end;
    Root.Add('links', LinksArr);

    SL.Text := Root.FormatJSON;
    SL.SaveToFile(FileName);
  finally
    SL.Free;
    Root.Free;
  end;
end;


constructor TMultiAssemblyForm.Create(AOwner: TComponent);
var
  I: Integer;
  Page: TTabSheet;
  Scroll: TScrollBox;
begin
  inherited CreateNew(AOwner, 1);
  Caption := 'MultiAssembly • MultiSuite';
  Width := 1280;
  Height := 860;
  Constraints.MinWidth := 1060;
  Constraints.MinHeight := 680;
  Position := poScreenCenter;
  Font.Name := SUITE_FONT;
  Font.Size := 10;
  Color := clSuiteSurface;

  // Carrega icone da aplicacao / janela
  if (Application.Icon <> nil) and not Application.Icon.Empty then
    Icon.Assign(Application.Icon)
  else if FileExists(ExtractFilePath(ParamStr(0)) + 'multiassembly.ico') then
    Icon.LoadFromFile(ExtractFilePath(ParamStr(0)) + 'multiassembly.ico')
  else if FileExists(ExtractFilePath(ParamStr(0)) + '..\multiassembly\src\app\multiassembly.ico') then
    Icon.LoadFromFile(ExtractFilePath(ParamStr(0)) + '..\multiassembly\src\app\multiassembly.ico')
  else if FileExists('multiassembly.ico') then
    Icon.LoadFromFile('multiassembly.ico');

  P := TAssemblyProject.Create;
  FSolver := TKinematicSolver.Create(P);
  FSimTimer := TTimer.Create(Self);
  FSimTimer.Interval := 35;
  FSimTimer.Enabled := False;
  FSimTimer.OnTimer := @SimTimerTick;
  FUpdating := True;
  FCurrentStep := 0;

  // 1. Cabecalho padrao MultiSuite
  Header := TSuiteHeader.Create(Self);
  Header.Parent := Self;
  Header.Align := alTop;
  Header.Height := 72;
  Header.Setup('MultiAssembly', 'Montagem Eletromecânica & Manual • MultiSuite', sikAssembly);

  // 2. Rodape
  Footer := TPanel.Create(Self);
  Footer.Parent := Self;
  Footer.Align := alBottom;
  Footer.Height := 66;
  Footer.BevelOuter := bvNone;
  Footer.Color := clSuiteCard;

  StatusLabel := CreateLabel(Footer, 'Pronto.', 18, 8, 450, 24);
  StatusLabel.Font.Color := clSuiteText;
  StatusLabel.Font.Style := [fsBold];

  CoordsLabel := CreateLabel(Footer, 'Selecione uma peça para ver propriedades.', 18, 34, 450, 22);
  CoordsLabel.Font.Color := clSuiteMuted;

  ValidateBtn := CreateButton(Footer, 'Validar ERC', 0, 15, 140, 36, sikTests, @RunAuditClick);
  PhysicsBtn := CreateButton(Footer, 'MultiPhysics', 0, 15, 150, 36, sikPhysics, @ExportMultiPhysicsClick);
  DocBtn := CreateButton(Footer, 'Gerar Manual & BOM', 0, 15, 190, 36, sikExport, @GenerateHTMLManualClick);
  DocBtn.SetLook(sbsSolid, clSuitePrimary, sikExport);

  // 3. Barra Lateral (Sidebar)
  Sidebar := TPanel.Create(Self);
  Sidebar.Parent := Self;
  Sidebar.Align := alLeft;
  Sidebar.Width := 214;
  Sidebar.BevelOuter := bvNone;
  Sidebar.Color := clSuiteCard;

  for I := 0 to 5 do
  begin
    Nav[I] := CreateButton(Sidebar, MA_STEPS[I], 12, 14 + I * 42, 190, 34, STEP_ICONS[I], @NavClick);
    Nav[I].Tag := I;
  end;

  CreateButton(Sidebar, 'Novo', 12, 276, 92, 32, sikNew, @NewProjectClick);
  CreateButton(Sidebar, 'Abrir', 110, 276, 92, 32, sikFolder, @OpenProjectClick);
  CreateButton(Sidebar, 'Salvar', 12, 314, 92, 32, sikSave, @SaveProjectClick);
  CreateButton(Sidebar, 'Demo', 110, 314, 92, 32, sikWand, @LoadDemoClick);

  CreateLabel(Sidebar, 'COMPONENTES', 16, 356, 180, 18).Font.Style := [fsBold];
  QuickSearch := TEdit.Create(Self);
  QuickSearch.Parent := Sidebar;
  QuickSearch.SetBounds(12, 376, 190, 26);
  QuickSearch.TextHint := 'Filtrar peças...';
  QuickSearch.OnChange := @QuickSearchChange;

  CompList := TListBox.Create(Self);
  CompList.Parent := Sidebar;
  CompList.SetBounds(12, 408, 190, 220);
  CompList.Anchors := [akLeft, akTop, akRight, akBottom];
  CompList.OnClick := @CompListClick;

  SidebarInfo := CreateLabel(Sidebar, '', 16, 640, 184, 80);
  SidebarInfo.Align := alBottom;
  SidebarInfo.BorderSpacing.Around := 12;

  // 4. Painel de Parametros a Direita
  Pages := TPageControl.Create(Self);
  Pages.Parent := Self;
  Pages.Align := alRight;
  Pages.Width := 336;
  Pages.ShowTabs := False;

  for I := 0 to 5 do
  begin
    Page := TTabSheet.Create(Self);
    Page.PageControl := Pages;
    Page.Caption := MA_STEPS[I];

    Scroll := TScrollBox.Create(Self);
    Scroll.Parent := Page;
    Scroll.Align := alClient;
    Scroll.BorderStyle := bsNone;
    Scroll.Color := clSuiteCard;
    Scroll.HorzScrollBar.Visible := False;

    CreateLabel(Scroll, MA_STEPS[I], 16, 16, 260, 28).Font.Style := [fsBold];

    case I of
      0: BuildProjectPage(Scroll);
      1: BuildComponentsPage(Scroll);
      2: BuildAssemblyPage(Scroll);
      3: BuildConnectionsPage(Scroll);
      4: BuildVerifyPage(Scroll);
      5: BuildDocumentPage(Scroll);
    end;
  end;

  // 5. Area Central (Workspace)
  Work := TPanel.Create(Self);
  Work.Parent := Self;
  Work.Align := alClient;
  Work.BevelOuter := bvNone;
  Work.Color := clSuiteSurface;

  ViewBar := TPanel.Create(Self);
  ViewBar.Parent := Work;
  ViewBar.Align := alTop;
  ViewBar.Height := 48;
  ViewBar.BevelOuter := bvNone;
  ViewBar.Color := clSuiteSurface;

  BtnViewIso := CreateButton(ViewBar, '3D Órbita', 12, 8, 96, 32, sikFit, @ViewModeClick);
  BtnViewIso.Tag := 0;
  BtnViewTop := CreateButton(ViewBar, 'Superior', 112, 8, 86, 32, sikLayers, @ViewModeClick);
  BtnViewTop.Tag := 1;
  BtnViewFront := CreateButton(ViewBar, 'Frontal', 202, 8, 86, 32, sikFrame, @ViewModeClick);
  BtnViewFront.Tag := 2;
  BtnViewSide := CreateButton(ViewBar, 'Lateral', 292, 8, 86, 32, sikRect, @ViewModeClick);
  BtnViewSide.Tag := 3;
  BtnViewElec := CreateButton(ViewBar, 'Elétrica', 382, 8, 86, 32, sikPlug, @ViewModeClick);
  BtnViewElec.Tag := 4;
  BtnViewManual := CreateButton(ViewBar, 'Manual', 472, 8, 86, 32, sikText, @ViewModeClick);
  BtnViewManual.Tag := 5;

  BtnFit := CreateButton(ViewBar, 'Ajustar 3D', 566, 8, 96, 32, sikFit, @FitViewClick);
  BtnZoomIn := CreateButton(ViewBar, '+', 666, 8, 38, 32, sikZoomIn, @ZoomInClick);
  BtnZoomOut := CreateButton(ViewBar, '-', 708, 8, 38, 32, sikZoomOut, @ZoomOutClick);
  BtnMate := CreateButton(ViewBar, 'Unir Peças', 754, 8, 112, 32, sikAssembly, @MateClick);

  // Painel de informacao do passo atual quando no modo manual
  ManualStepPanel := TPanel.Create(Self);
  ManualStepPanel.Parent := Work;
  ManualStepPanel.Align := alTop;
  ManualStepPanel.Height := 105;
  ManualStepPanel.Color := clSuiteCard;
  ManualStepPanel.BevelOuter := bvNone;
  ManualStepPanel.Visible := False;

  ManualStepTitle := CreateLabel(ManualStepPanel, '', 16, 8, 560, 22);
  ManualStepTitle.Font.Style := [fsBold];
  ManualStepTitle.Font.Color := clSuitePrimary;

  ManualStepTools := CreateLabel(ManualStepPanel, '', 16, 32, 560, 20);
  ManualStepTools.Font.Color := clSuiteWarning;

  ManualStepChecks := CreateLabel(ManualStepPanel, '', 16, 54, 560, 20);
  ManualStepChecks.Font.Color := clSuiteSuccess;

  ManualStepComps := CreateLabel(ManualStepPanel, '', 16, 76, 560, 20);
  ManualStepComps.Font.Color := clSuiteMuted;

  BtnPrevStep := CreateButton(ManualStepPanel, '< Passo Anterior', 590, 16, 130, 32, sikChevron, @PrevStepClick);
  BtnNextStep := CreateButton(ManualStepPanel, 'Próximo Passo >', 730, 16, 130, 32, sikArrowRight, @NextStepClick);

  // Vistas Mecanica e Eletrica
  MechView := TMechanicalAssemblyCanvas.Create(Self);
  MechView.Parent := Work;
  MechView.Align := alClient;
  MechView.Project := P;
  MechView.Solver := FSolver;
  MechView.OnSelectComponent := @OnCanvasSelect;
  MechView.OnKinematicMove := @OnCanvasKinematicMove;
  MechView.OnMateCreated := @OnMateCreated;
  MechView.OnMateStatus := @OnMateStatus;

  ElecView := TElectricalAssemblyCanvas.Create(Self);
  ElecView.Parent := Work;
  ElecView.Align := alClient;
  ElecView.Project := P;
  ElecView.Visible := False;
  ElecView.OnSelectComponent := @OnCanvasSelect;

  // Montagem inicia completamente em branco conforme padrao SolidWorks
  P.Clear;
  P.Name := 'Nova Montagem';
  P.Version := '1.0';
  P.Author := 'MultiAssembly';
  P.Units := 'mm';
  FSolver.Solve;

  FUpdating := False;
  RefreshAll;
  ShowStep(1); // Abre diretamente na etapa 2 (Componentes) para insercao
  StatusLabel.Caption := 'Montagem em branco. Insira o primeiro componente (base fixa).';
end;

destructor TMultiAssemblyForm.Destroy;
begin
  FSimTimer.Enabled := False;
  FSimTimer.Free;
  FSolver.Free;
  P.Free;
  inherited Destroy;
end;

function TMultiAssemblyForm.CreateButton(AParent: TWinControl; const AText: string; X, Y, W, H: Integer;
  AIcon: TSuiteIconKind; Handler: TNotifyEvent): TSuiteButton;
begin
  Result := TSuiteButton.Create(Self);
  Result.Parent := AParent;
  Result.SetBounds(X, Y, W, H);
  Result.Caption := AText;
  Result.SetLook(sbsSoft, clSuitePrimary, AIcon);
  Result.OnClick := Handler;
end;

function TMultiAssemblyForm.CreateLabel(AParent: TWinControl; const AText: string; X, Y, W, H: Integer): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := AParent;
  Result.AutoSize := False;
  Result.SetBounds(X, Y, W, H);
  Result.WordWrap := True;
  Result.Caption := AText;
  Result.Font.Color := clSuiteMuted;
end;

function TMultiAssemblyForm.CreateField(AParent: TWinControl; const AText, DefaultVal: string; Y: Integer): TEdit;
begin
  CreateLabel(AParent, AText, 16, Y, 290, 18);
  Result := TEdit.Create(Self);
  Result.Parent := AParent;
  Result.SetBounds(16, Y + 20, 290, 26);
  Result.Text := DefaultVal;
end;

function TMultiAssemblyForm.CreateCombo(AParent: TWinControl; const AText: string; Y: Integer): TComboBox;
begin
  CreateLabel(AParent, AText, 16, Y, 290, 18);
  Result := TComboBox.Create(Self);
  Result.Parent := AParent;
  Result.SetBounds(16, Y + 20, 290, 28);
  Result.Style := csDropDownList;
end;

procedure TMultiAssemblyForm.BuildProjectPage(S: TScrollBox);
begin
  EdProjName := CreateField(S, 'Nome do Projeto', P.Name, 48);
  EdProjVer := CreateField(S, 'Versão / Revisão', P.Version, 104);
  EdProjAuthor := CreateField(S, 'Autor / Responsável', P.Author, 160);
  CbProjUnits := CreateCombo(S, 'Unidades Geométricas', 216);
  CbProjUnits.Items.Add('Milímetros (mm)');
  CbProjUnits.Items.Add('Polegadas (in)');
  CbProjUnits.ItemIndex := 0;

  LblProjStats := CreateLabel(S, '', 16, 280, 290, 110);
  LblProjStats.Font.Color := clSuiteText;

  CreateButton(S, 'Salvar Projeto (.massembly)', 16, 400, 290, 34, sikSave, @SaveProjectClick);
  CreateButton(S, 'Exportar para MultiPhysics', 16, 442, 290, 34, sikPhysics, @ExportMultiPhysicsClick);
  CreateButton(S, 'Carregar CNC de Demonstração', 16, 484, 290, 34, sikWand, @LoadDemoClick);
end;

procedure TMultiAssemblyForm.BuildComponentsPage(S: TScrollBox);
begin
  CreateLabel(S, 'BIBLIOTECA DE MODELOS MECÂNICOS', 16, 44, 290, 18).Font.Style := [fsBold];
  CreateLabel(S, 'Pasta dos Modelos:', 16, 68, 290, 16);

  EdLibFolder := TEdit.Create(Self);
  EdLibFolder.Parent := S;
  EdLibFolder.SetBounds(16, 88, 212, 26);
  EdLibFolder.Text := TAssemblyLibrary.GetLibraryFolder;
  EdLibFolder.ReadOnly := True;
  EdLibFolder.Color := $242432;
  EdLibFolder.Font.Color := $E0E0E0;

  CreateButton(S, '📁', 232, 88, 34, 26, sikFolder, @BrowseLibFolderClick);
  CreateButton(S, '🔄', 270, 88, 36, 26, sikRedo, @RefreshLibClick);

  CbCatSelect := CreateCombo(S, 'Categoria / Pasta', 120);
  CbCatSelect.OnChange := @CategoryChange;

  CbItemSelect := CreateCombo(S, 'Modelo / Peça', 176);

  CreateButton(S, '+ Inserir Peça na Montagem', 16, 232, 290, 34, sikNew, @AddFromLibClick);

  CreateLabel(S, 'PROPRIEDADES DA OCORRÊNCIA', 16, 280, 290, 18).Font.Style := [fsBold];
  EdCompID := CreateField(S, 'Identificador Único (ID)', '', 302);
  EdCompName := CreateField(S, 'Nome Descritivo', '', 358);
  EdCompModel := CreateField(S, 'Modelo / Especificação', '', 414);
  EdCompMat := CreateField(S, 'Material', '', 470);

  CreateLabel(S, 'Posição (X, Y, Z mm)', 16, 526, 290, 18);
  EdPosX := TEdit.Create(Self); EdPosX.Parent := S; EdPosX.SetBounds(16, 546, 90, 26); EdPosX.Text := '0';
  EdPosY := TEdit.Create(Self); EdPosY.Parent := S; EdPosY.SetBounds(116, 546, 90, 26); EdPosY.Text := '0';
  EdPosZ := TEdit.Create(Self); EdPosZ.Parent := S; EdPosZ.SetBounds(216, 546, 90, 26); EdPosZ.Text := '0';

  CreateLabel(S, 'Dimensões (L, A, P mm)', 16, 580, 290, 18);
  EdSizeW := TEdit.Create(Self); EdSizeW.Parent := S; EdSizeW.SetBounds(16, 600, 90, 26); EdSizeW.Text := '20';
  EdSizeH := TEdit.Create(Self); EdSizeH.Parent := S; EdSizeH.SetBounds(116, 600, 90, 26); EdSizeH.Text := '20';
  EdSizeD := TEdit.Create(Self); EdSizeD.Parent := S; EdSizeD.SetBounds(216, 600, 90, 26); EdSizeD.Text := '20';

  CreateButton(S, 'Salvar Alterações', 16, 642, 140, 34, sikSave, @ApplyCompPropsClick);
  CreateButton(S, 'Duplicar', 166, 642, 140, 34, sikCopy, @DuplicateCompClick);
  CreateButton(S, 'Salvar Peça na Biblioteca...', 16, 684, 290, 32, sikSave, @SaveCompToLibClick);
  CreateButton(S, 'Excluir Componente', 16, 722, 290, 32, sikTrash, @DeleteCompClick).SetLook(sbsSoft, clSuiteDanger, sikTrash);

  ReloadLibrary;
end;

procedure TMultiAssemblyForm.BuildAssemblyPage(S: TScrollBox);
begin
  CreateLabel(S, 'POSICIONAMENTO RÁPIDO', 16, 48, 290, 18).Font.Style := [fsBold];
  CreateButton(S, 'Zerar Posição (0,0,0)', 16, 72, 290, 32, sikOrigin, @ZeroPosClick);
  CreateButton(S, '+10mm em X', 16, 110, 90, 28, sikArrowRight, @QuickNudgeClick).Tag := 1;
  CreateButton(S, '+10mm em Y', 116, 110, 90, 28, sikArrowUp, @QuickNudgeClick).Tag := 2;
  CreateButton(S, '+10mm em Z', 216, 110, 90, 28, sikPulse, @QuickNudgeClick).Tag := 3;

  CreateLabel(S, 'VÍNCULOS E RELAÇÕES (MATES)', 16, 154, 290, 18).Font.Style := [fsBold];
  
  CbRelKind := CreateCombo(S, 'Tipo de Relação', 176);
  CbRelKind.Items.Add('Eixo / Coaxial');
  CbRelKind.Items.Add('Fuso / Castanha (Linear)');
  CbRelKind.Items.Add('Correia / Polia');
  CbRelKind.Items.Add('Acoplado Rígido');
  CbRelKind.Items.Add('Fixo na Base');
  CbRelKind.ItemIndex := 0;

  CbRelTarget := CreateCombo(S, 'Vincular com Peça', 232);

  EdRelRatio := CreateField(S, 'Relação de Transmissão', '1.0', 288);
  EdRelPitch := CreateField(S, 'Passo do Fuso (mm/volta)', '2.0', 344);

  CreateButton(S, '+ Aplicar Relação Mecânica', 16, 400, 290, 34, sikAssembly, @AddRelationClick);

  CreateLabel(S, 'RELAÇÕES ATIVAS DA PEÇA', 16, 446, 290, 18).Font.Style := [fsBold];
  RelList := TListBox.Create(Self);
  RelList.Parent := S;
  RelList.SetBounds(16, 468, 290, 120);

  CreateButton(S, 'Remover Relação', 16, 596, 290, 30, sikTrash, @DeleteRelationClick);

  CreateButton(S, 'Unir peças por face / furo / eixo', 16, 634, 290, 32, sikTarget, @MateClick);

  LblSolverStatus := CreateLabel(S, 'Solver: Montagem consistente.', 16, 676, 290, 40);
  LblSolverStatus.Font.Color := clSuiteSuccess;
end;

procedure TMultiAssemblyForm.BuildConnectionsPage(S: TScrollBox);
begin
  CreateLabel(S, 'PORTAS / TERMINAIS DA PEÇA', 16, 48, 290, 18).Font.Style := [fsBold];
  PortList := TListBox.Create(Self);
  PortList.Parent := S;
  PortList.SetBounds(16, 70, 290, 110);

  EdPortName := CreateField(S, 'Nova Porta', 'PWR_IN', 188);
  CbPortKind := CreateCombo(S, 'Tipo do Sinal', 244);
  CbPortKind.Items.Add('Alimentação (Power)');
  CbPortKind.Items.Add('Terra (GND)');
  CbPortKind.Items.Add('Pulso de Passo (STEP)');
  CbPortKind.Items.Add('Direção (DIR)');
  CbPortKind.Items.Add('Habilitação (ENABLE)');
  CbPortKind.Items.Add('PWM / Velocidade');
  CbPortKind.Items.Add('Entrada Digital / Fim de Curso');
  CbPortKind.Items.Add('Comunicação (Serial/CAN)');
  CbPortKind.ItemIndex := 0;

  EdPortVolt := CreateField(S, 'Tensão Nominal (V)', '24.0', 300);
  CreateButton(S, '+ Adicionar Porta', 16, 356, 290, 30, sikNew, @AddPortClick);

  CreateLabel(S, 'LIGAÇÃO ELÉTRICA / CABO', 16, 400, 290, 18).Font.Style := [fsBold];
  CbFromPort := CreateCombo(S, 'Da Porta (Peça Selecionada)', 420);
  CbToComp := CreateCombo(S, 'Para o Componente', 476);
  CbToComp.OnChange := @ToCompChange;
  CbToPort := CreateCombo(S, 'Na Porta de Destino', 532);
  EdWireCaption := CreateField(S, 'Identificação do Cabo', 'Cabo Alimentacao', 588);

  CreateButton(S, 'Conectar Fio / Cabo', 16, 644, 290, 34, sikPlug, @ConnectWireClick);

  CreateLabel(S, 'CONEXÕES REGISTRADAS', 16, 690, 290, 18).Font.Style := [fsBold];
  WireList := TListBox.Create(Self);
  WireList.Parent := S;
  WireList.SetBounds(16, 712, 290, 120);
  CreateButton(S, 'Excluir Conexão', 16, 840, 290, 30, sikTrash, @DeleteWireClick);
end;

procedure TMultiAssemblyForm.BuildVerifyPage(S: TScrollBox);
begin
  CreateLabel(S, 'AUDITORIA DE ENGENHARIA', 16, 48, 290, 18).Font.Style := [fsBold];
  CreateButton(S, 'Executar Auditoria Completa', 16, 72, 290, 36, sikTests, @RunAuditClick).SetLook(sbsSolid, clSuitePrimary, sikTests);

  LblErcSummary := CreateLabel(S, 'Clique em Executar para auditar ERC, solver e interferências.', 16, 118, 290, 60);
  LblErcSummary.Font.Color := clSuiteText;

  CreateLabel(S, 'AVISOS E PENDÊNCIAS', 16, 184, 290, 18).Font.Style := [fsBold];
  IssueList := TListBox.Create(Self);
  IssueList.Parent := S;
  IssueList.SetBounds(16, 206, 290, 380);
  IssueList.OnClick := @IssueListClick;
end;

procedure TMultiAssemblyForm.BuildDocumentPage(S: TScrollBox);
begin
  CreateLabel(S, 'LISTA DE MATERIAIS (BOM)', 16, 48, 290, 18).Font.Style := [fsBold];
  LblBomSummary := CreateLabel(S, '', 16, 72, 290, 50);

  CreateButton(S, 'Exportar BOM em CSV', 16, 130, 140, 32, sikExport, @ExportBomCSVClick);
  CreateButton(S, 'Exportar BOM em JSON', 166, 130, 140, 32, sikFile, @ExportBomJSONClick);

  CreateLabel(S, 'ETAPAS DO MANUAL DE MONTAGEM', 16, 178, 290, 18).Font.Style := [fsBold];
  StepListBox := TListBox.Create(Self);
  StepListBox.Parent := S;
  StepListBox.SetBounds(16, 200, 290, 120);
  StepListBox.OnClick := @StepListClick;

  CreateButton(S, '+ Nova Etapa', 16, 326, 92, 28, sikNew, @AddStepClick);
  CreateButton(S, 'Subir', 112, 326, 92, 28, sikArrowUp, @MoveStepUpClick);
  CreateButton(S, 'Descer', 208, 326, 92, 28, sikArrowDown, @MoveStepDownClick);

  EdStepTitle := CreateField(S, 'Título da Etapa', '', 360);
  EdStepTools := CreateField(S, 'Ferramentas Necessárias', '', 416);

  CreateLabel(S, 'Instruções Passo a Passo', 16, 472, 290, 18);
  MemStepInstr := TMemo.Create(Self);
  MemStepInstr.Parent := S;
  MemStepInstr.SetBounds(16, 492, 290, 70);

  CreateLabel(S, 'Conferência de Qualidade / Segurança', 16, 568, 290, 18);
  MemStepChecks := TMemo.Create(Self);
  MemStepChecks.Parent := S;
  MemStepChecks.SetBounds(16, 588, 290, 50);

  CreateButton(S, 'Salvar Dados da Etapa', 16, 646, 140, 32, sikSave, @SaveStepClick);
  CreateButton(S, 'Atribuir Peça Selecionada', 166, 646, 140, 32, sikLayers, @AssignCompToStepClick);
  CreateButton(S, 'Excluir Etapa', 16, 684, 290, 28, sikTrash, @DeleteStepClick);

  CreateLabel(S, 'PUBLICAÇÃO DO MANUAL', 16, 726, 290, 18).Font.Style := [fsBold];
  CreateButton(S, 'Gerar Manual HTML (Imprimível)', 16, 748, 290, 36, sikExport, @GenerateHTMLManualClick).SetLook(sbsSolid, clSuitePrimary, sikExport);
  CreateButton(S, 'Gerar Manual Markdown (.md)', 16, 790, 290, 32, sikText, @GenerateMarkdownManualClick);
end;

procedure TMultiAssemblyForm.NavClick(Sender: TObject);
begin
  ShowStep((Sender as TSuiteButton).Tag);
end;

procedure TMultiAssemblyForm.ShowStep(StepIndex: Integer);
var
  I: Integer;
begin
  if (StepIndex < 0) or (StepIndex > 5) then Exit;
  FCurrentStep := StepIndex;
  for I := 0 to 5 do
  begin
    if I = StepIndex then
      Nav[I].SetLook(sbsSolid, clSuitePrimary, STEP_ICONS[I])
    else
      Nav[I].SetLook(sbsSoft, clSuitePrimary, STEP_ICONS[I]);
  end;
  Pages.ActivePageIndex := StepIndex;

  if StepIndex = 3 then // Conexoes
  begin
    MechView.Visible := False;
    ElecView.Visible := True;
    ManualStepPanel.Visible := False;
  end
  else if StepIndex = 5 then // Documentar
  begin
    MechView.Visible := True;
    ElecView.Visible := False;
    ManualStepPanel.Visible := True;
    RefreshManualPreview;
  end
  else
  begin
    MechView.Visible := True;
    ElecView.Visible := False;
    ManualStepPanel.Visible := False;
  end;

  UpdateStatus;
end;

procedure TMultiAssemblyForm.ViewModeClick(Sender: TObject);
begin
  case (Sender as TSuiteButton).Tag of
    0:
    begin
      MechView.SetViewMode(avm3DOrbit);
      MechView.Visible := True;
      ElecView.Visible := False;
      ManualStepPanel.Visible := False;
    end;
    1:
    begin
      MechView.SetViewMode(avmTop);
      MechView.Visible := True;
      ElecView.Visible := False;
      ManualStepPanel.Visible := False;
    end;
    2:
    begin
      MechView.SetViewMode(avmFront);
      MechView.Visible := True;
      ElecView.Visible := False;
      ManualStepPanel.Visible := False;
    end;
    3:
    begin
      MechView.SetViewMode(avmSide);
      MechView.Visible := True;
      ElecView.Visible := False;
      ManualStepPanel.Visible := False;
    end;
    4:
    begin
      MechView.Visible := False;
      ElecView.Visible := True;
      ManualStepPanel.Visible := False;
    end;
    5:
    begin
      MechView.SetViewMode(avm3DOrbit);
      MechView.Visible := True;
      ElecView.Visible := False;
      ManualStepPanel.Visible := True;
      RefreshManualPreview;
    end;
  end;
end;

procedure TMultiAssemblyForm.FitViewClick(Sender: TObject);
begin
  if MechView.Visible then MechView.FitToView;
  if ElecView.Visible then ElecView.FitToView;
end;

procedure TMultiAssemblyForm.ZoomInClick(Sender: TObject);
begin
  if MechView.Visible then MechView.ZoomIn;
  if ElecView.Visible then ElecView.ZoomIn;
end;

procedure TMultiAssemblyForm.ZoomOutClick(Sender: TObject);
begin
  if MechView.Visible then MechView.ZoomOut;
  if ElecView.Visible then ElecView.ZoomOut;
end;

procedure TMultiAssemblyForm.PrevStepClick(Sender: TObject);
begin
  if StepListBox.ItemIndex > 0 then
  begin
    StepListBox.ItemIndex := StepListBox.ItemIndex - 1;
    StepListClick(nil);
  end;
end;

procedure TMultiAssemblyForm.NextStepClick(Sender: TObject);
begin
  if StepListBox.ItemIndex < StepListBox.Count - 1 then
  begin
    StepListBox.ItemIndex := StepListBox.ItemIndex + 1;
    StepListClick(nil);
  end;
end;

procedure TMultiAssemblyForm.NewProjectClick(Sender: TObject);
begin
  if P.IsModified then
  begin
    if MessageDlg('MultiAssembly', 'Deseja descartar as alterações e criar um novo projeto?', mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
      Exit;
  end;
  P.Clear;
  P.Name := 'Nova Montagem';
  P.Version := '1.0';
  P.Author := 'MultiAssembly';
  P.Units := 'mm';
  if FSolver <> nil then
    FSolver.Solve;
  RefreshAll;
  MechView.FitToView;
  ShowStep(1); // Vai direto para insercao de componentes
  StatusLabel.Caption := 'Nova montagem criada. Insira o primeiro componente (base fixa).';
end;

procedure TMultiAssemblyForm.OpenProjectClick(Sender: TObject);
var
  OD: TOpenDialog;
begin
  OD := TOpenDialog.Create(Self);
  try
    OD.Filter := 'Montagem MultiAssembly (*.massembly)|*.massembly|Todos os arquivos (*.*)|*.*';
    if OD.Execute then
    begin
      P.LoadFromFile(OD.FileName);
      RefreshAll;
      ShowStep(0);
    end;
  finally
    OD.Free;
  end;
end;

procedure TMultiAssemblyForm.SaveProjectClick(Sender: TObject);
var
  SD: TSaveDialog;
begin
  if P.FileName = '' then
  begin
    SD := TSaveDialog.Create(Self);
    try
      SD.Filter := 'Montagem MultiAssembly (*.massembly)|*.massembly';
      SD.DefaultExt := 'massembly';
      if SD.Execute then
      begin
        P.Name := EdProjName.Text;
        P.Version := EdProjVer.Text;
        P.Author := EdProjAuthor.Text;
        P.SaveToFile(SD.FileName);
        Caption := 'MultiAssembly • ' + ExtractFileName(SD.FileName);
      end;
    finally
      SD.Free;
    end;
  end
  else
  begin
    P.Name := EdProjName.Text;
    P.Version := EdProjVer.Text;
    P.Author := EdProjAuthor.Text;
    P.SaveToFile(P.FileName);
  end;
  UpdateStatus;
end;

procedure TMultiAssemblyForm.LoadDemoClick(Sender: TObject);
begin
  TAssemblyDemo.BuildCNC(P);
  if FSolver <> nil then
    FSolver.Solve;
  RefreshAll;
  MechView.FitToView;
  ShowStep(2); // Direciona para Montagem para testar o movimento
  StatusLabel.Caption := 'Demonstração CNC carregada. Teste a movimentação na aba Montagem.';
end;

procedure TMultiAssemblyForm.QuickSearchChange(Sender: TObject);
var
  I: Integer;
  FilterStr, ItemStr: string;
begin
  FilterStr := UpperCase(Trim(QuickSearch.Text));
  CompList.Items.BeginUpdate;
  try
    CompList.Clear;
    for I := 0 to P.ComponentCount - 1 do
    begin
      ItemStr := P.Component(I).ID + ' - ' + P.Component(I).Name;
      if (FilterStr = '') or (Pos(FilterStr, UpperCase(ItemStr)) > 0) then
        CompList.Items.AddObject(ItemStr, TObject(PtrInt(I)));
    end;
  finally
    CompList.Items.EndUpdate;
  end;
end;

procedure TMultiAssemblyForm.CompListClick(Sender: TObject);
var
  Idx: Integer;
begin
  if CompList.ItemIndex < 0 then Exit;
  Idx := PtrInt(CompList.Items.Objects[CompList.ItemIndex]);
  MechView.SelectedID := P.Component(Idx).ID;
  ElecView.SelectedID := P.Component(Idx).ID;
  MechView.Invalidate;
  ElecView.Invalidate;
  RefreshSelectedProps;
  UpdateStatus;
end;

procedure TMultiAssemblyForm.OnCanvasSelect(Sender: TObject; const AID: string);
var
  I: Integer;
begin
  for I := 0 to CompList.Count - 1 do
  begin
    if SameText(P.Component(PtrInt(CompList.Items.Objects[I])).ID, AID) then
    begin
      CompList.ItemIndex := I;
      Break;
    end;
  end;
  MechView.SelectedID := AID;
  ElecView.SelectedID := AID;
  RefreshSelectedProps;
  UpdateStatus;
end;

procedure TMultiAssemblyForm.ReloadLibrary;
var
  Cats: TStringArray;
  I: Integer;
begin
  if CbCatSelect = nil then Exit;
  CbCatSelect.Items.Clear;
  Cats := TAssemblyLibrary.GetCategories;
  for I := 0 to High(Cats) do
    CbCatSelect.Items.Add(Cats[I]);
  if CbCatSelect.Items.Count > 0 then
    CbCatSelect.ItemIndex := 0;
  CategoryChange(nil);
end;

procedure TMultiAssemblyForm.BrowseLibFolderClick(Sender: TObject);
var
  Dlg: TSelectDirectoryDialog;
begin
  Dlg := TSelectDirectoryDialog.Create(Self);
  try
    Dlg.Title := 'Selecione a Pasta de Modelos Mecânicos';
    Dlg.InitialDir := TAssemblyLibrary.GetLibraryFolder;
    if Dlg.Execute then
    begin
      TAssemblyLibrary.SetLibraryFolder(Dlg.FileName);
      if EdLibFolder <> nil then
        EdLibFolder.Text := Dlg.FileName;
      ReloadLibrary;
      StatusLabel.Caption := 'Biblioteca apontada para: ' + Dlg.FileName;
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TMultiAssemblyForm.RefreshLibClick(Sender: TObject);
begin
  if EdLibFolder <> nil then
    TAssemblyLibrary.SetLibraryFolder(EdLibFolder.Text);
  ReloadLibrary;
  StatusLabel.Caption := 'Modelos recarregados da pasta da biblioteca.';
end;

procedure TMultiAssemblyForm.SaveCompToLibClick(Sender: TObject);
var
  Idx: Integer;
  C: TAssemblyComponent;
  TargetDir, TargetFile, SafeName: string;
begin
  Idx := P.FindComponent(MechView.SelectedID);
  if Idx < 0 then
  begin
    ShowMessage('Selecione um componente para salvar na biblioteca.');
    Exit;
  end;
  C := P.Component(Idx);
  if (CbCatSelect = nil) or (CbCatSelect.ItemIndex < 0) then Exit;

  SafeName := LowerCase(C.Name);
  SafeName := StringReplace(SafeName, ' ', '_', [rfReplaceAll]);
  SafeName := StringReplace(SafeName, '/', '_', [rfReplaceAll]);
  SafeName := StringReplace(SafeName, '', '_', [rfReplaceAll]);
  TargetDir := IncludeTrailingPathDelimiter(TAssemblyLibrary.GetLibraryFolder) + CbCatSelect.Text;
  TargetFile := IncludeTrailingPathDelimiter(TargetDir) + SafeName + '.json';

  TAssemblyLibrary.SaveComponentToFile(TargetFile, C);
  ReloadLibrary;
  StatusLabel.Caption := 'Modelo salvo com sucesso na biblioteca: ' + ExtractFileName(TargetFile);
  ShowMessage('Componente salvo na biblioteca mecânica com sucesso em:' + LineEnding + TargetFile);
end;

procedure TMultiAssemblyForm.CategoryChange(Sender: TObject);
var
  Items: TStringArray;
  I: Integer;
begin
  if CbCatSelect.ItemIndex < 0 then Exit;
  Items := TAssemblyLibrary.GetCatalogItems(CbCatSelect.Text);
  CbItemSelect.Items.Clear;
  for I := 0 to High(Items) do
    CbItemSelect.Items.Add(Items[I]);
  if CbItemSelect.Items.Count > 0 then
    CbItemSelect.ItemIndex := 0;
end;

procedure TMultiAssemblyForm.AddFromLibClick(Sender: TObject);
var
  NewID: string;
  C: TAssemblyComponent;
begin
  if CbItemSelect.ItemIndex < 0 then Exit;
  NewID := 'COMP_' + IntToStr(P.ComponentCount + 1);
  C := TAssemblyLibrary.CreateFromCatalog(CbCatSelect.Text, CbItemSelect.Text, NewID, 0, 0, 0);

  // Padrao SolidWorks: primeiro componente inserido e Fixo (f) na Origem
  if P.ComponentCount = 0 then
  begin
    C.Fixed := True;
    C.Position := Vec3(0, 0, 0);
  end
  else
  begin
    C.Fixed := False;
    // Coloca a nova peca flutuando no espaco 3D perto da area de montagem
    C.Position := Vec3(P.ComponentCount * 30.0, 20.0, 10.0);
  end;

  P.AddComponent(C);
  if FSolver <> nil then
    FSolver.Solve;
  RefreshAll;
  OnCanvasSelect(Self, NewID);
  MechView.FitToView;
  MarkModified;

  if C.Fixed then
    StatusLabel.Caption := Format('Peça %s inserida como Âncora Fixa (f) na Origem.', [C.Name])
  else
    StatusLabel.Caption := Format('Peça %s inserida com 6 GL livres (-). Vá para Montagem para aplicar Junções.', [C.Name]);
end;

procedure TMultiAssemblyForm.ApplyCompPropsClick(Sender: TObject);
var
  Idx: Integer;
  C: TAssemblyComponent;
begin
  Idx := P.FindComponent(MechView.SelectedID);
  if Idx < 0 then Exit;
  C := P.Component(Idx);
  C.Name := EdCompName.Text;
  C.Model := EdCompModel.Text;
  C.Material := EdCompMat.Text;
  C.Position.X := StrToFloatDef(EdPosX.Text, C.Position.X);
  C.Position.Y := StrToFloatDef(EdPosY.Text, C.Position.Y);
  C.Position.Z := StrToFloatDef(EdPosZ.Text, C.Position.Z);
  C.Size.X := Max(1.0, StrToFloatDef(EdSizeW.Text, C.Size.X));
  C.Size.Y := Max(1.0, StrToFloatDef(EdSizeH.Text, C.Size.Y));
  C.Size.Z := Max(1.0, StrToFloatDef(EdSizeD.Text, C.Size.Z));
  P.UpdateComponent(Idx, C);
  RefreshAll;
  MarkModified;
end;

procedure TMultiAssemblyForm.DuplicateCompClick(Sender: TObject);
var
  NewID: string;
begin
  if MechView.SelectedID = '' then Exit;
  NewID := MechView.SelectedID + '_COPIA';
  if P.DuplicateComponent(MechView.SelectedID, NewID) then
  begin
    RefreshAll;
    OnCanvasSelect(Self, NewID);
    MarkModified;
  end;
end;

procedure TMultiAssemblyForm.DeleteCompClick(Sender: TObject);
begin
  if MechView.SelectedID = '' then Exit;
  P.RemoveComponent(MechView.SelectedID);
  MechView.SelectedID := '';
  ElecView.SelectedID := '';
  RefreshAll;
  MarkModified;
end;

procedure TMultiAssemblyForm.QuickNudgeClick(Sender: TObject);
var
  Idx: Integer;
  C: TAssemblyComponent;
begin
  Idx := P.FindComponent(MechView.SelectedID);
  if Idx < 0 then Exit;
  C := P.Component(Idx);
  case (Sender as TSuiteButton).Tag of
    1: C.Position.X := C.Position.X + 10;
    2: C.Position.Y := C.Position.Y + 10;
    3: C.Position.Z := C.Position.Z + 10;
  end;
  P.UpdateComponent(Idx, C);
  RefreshSelectedProps;
  MechView.Invalidate;
  MarkModified;
end;

procedure TMultiAssemblyForm.ZeroPosClick(Sender: TObject);
var
  Idx: Integer;
  C: TAssemblyComponent;
begin
  Idx := P.FindComponent(MechView.SelectedID);
  if Idx < 0 then Exit;
  C := P.Component(Idx);
  C.Position := Vec3(0, 0, 0);
  P.UpdateComponent(Idx, C);
  RefreshSelectedProps;
  MechView.Invalidate;
  MarkModified;
end;

procedure TMultiAssemblyForm.AddRelationClick(Sender: TObject);
var
  R: TMechanicalRelation;
begin
  if (MechView.SelectedID = '') or (CbRelTarget.ItemIndex < 0) then Exit;
  R.A := MechView.SelectedID;
  R.B := CbRelTarget.Text;

  case CbRelKind.ItemIndex of
    0: R.Kind := mrCoincident;
    1: R.Kind := mrConcentric;
    2: R.Kind := mrSlider;
    3: R.Kind := mrHinge;
    4: R.Kind := mrLeadScrew;
    5: R.Kind := mrBelt;
    6: R.Kind := mrFixed;
    7: R.Kind := mrDistance;
  else
    R.Kind := mrSlider;
  end;

  case CbRelAxis.ItemIndex of
    0: R.Axis := Vec3(1, 0, 0);
    1: R.Axis := Vec3(0, 1, 0);
    2: R.Axis := Vec3(0, 0, 1);
  else
    R.Axis := Vec3(1, 0, 0);
  end;

  R.MinLimit := StrToFloatDef(EdRelMin.Text, 0.0);
  R.MaxLimit := StrToFloatDef(EdRelMax.Text, 250.0);
  R.CurrentValue := R.MinLimit;
  R.PitchMM := StrToFloatDef(EdRelPitch.Text, 4.0);
  R.Ratio := StrToFloatDef(EdRelRatio.Text, 1.0);
  R.Distance := 0;
  R.Offset := Vec3(0, 0, 0);
  R.Flipped := False;

  P.Relate(R);
  if FSolver <> nil then
    FSolver.Solve;
  RefreshAll;
  MechView.Invalidate;
  MarkModified;
end;

procedure TMultiAssemblyForm.DeleteRelationClick(Sender: TObject);
var
  Idx: Integer;
begin
  if RelList.ItemIndex < 0 then Exit;
  Idx := PtrInt(RelList.Items.Objects[RelList.ItemIndex]);
  if (Idx >= 0) and (Idx < P.RelationCount) then
    P.RemoveRelation(Idx);
  if FSolver <> nil then
    FSolver.Solve;
  RefreshAll;
  MechView.Invalidate;
  MarkModified;
end;

procedure TMultiAssemblyForm.ToggleFixFloatClick(Sender: TObject);
var
  Idx: Integer;
  C: TAssemblyComponent;
begin
  Idx := P.FindComponent(MechView.SelectedID);
  if Idx < 0 then Exit;
  C := P.Component(Idx);
  C.Fixed := not C.Fixed;
  P.UpdateComponent(Idx, C);
  if FSolver <> nil then
    FSolver.Solve;
  RefreshAll;
  MarkModified;
end;

procedure TMultiAssemblyForm.RelListClick(Sender: TObject);
begin
  // Pode destacar relacao selecionada
end;

procedure TMultiAssemblyForm.ActiveJointChange(Sender: TObject);
begin
  // Junta ativa alterada para teste de jog
end;

procedure TMultiAssemblyForm.JogJointClick(Sender: TObject);
var
  Delta: Double;
  JointIdx, RelIdx: Integer;
  Joints: array of TKinematicJointInfo;
  CurVal: Double;
begin
  if FSolver = nil then Exit;
  Joints := FSolver.GetActiveJoints;
  if Length(Joints) = 0 then Exit;
  JointIdx := CbActiveJoints.ItemIndex;
  if (JointIdx < 0) or (JointIdx >= Length(Joints)) then
    JointIdx := 0;

  Delta := (Sender as TSuiteButton).Tag * 1.0;
  RelIdx := Joints[JointIdx].RelationIndex;
  CurVal := Joints[JointIdx].CurrentValue + Delta;
  FSolver.SetJointValue(RelIdx, CurVal);
  RefreshRelations;
  MechView.Invalidate;
  UpdateStatus;
end;

procedure TMultiAssemblyForm.ResetHomeClick(Sender: TObject);
begin
  if FSolver = nil then Exit;
  FSolver.ResetToHome;
  RefreshRelations;
  MechView.Invalidate;
  UpdateStatus;
end;

procedure TMultiAssemblyForm.SimulateMotionClick(Sender: TObject);
begin
  if FSimTimer.Enabled then
  begin
    FSimTimer.Enabled := False;
    BtnSimulateMotion.Caption := '▶ Simular Movimento';
    BtnSimulateMotion.SetLook(sbsSoft, clSuitePrimary, sikPlay);
  end
  else
  begin
    FSimTimer.Enabled := True;
    BtnSimulateMotion.Caption := '⏹ Parar Simulação';
    BtnSimulateMotion.SetLook(sbsSolid, clSuiteWarning, sikPause);
  end;
end;

procedure TMultiAssemblyForm.SimTimerTick(Sender: TObject);
begin
  if FSolver = nil then Exit;
  FSolver.StepSimulation(0.035);
  MechView.Invalidate;
  UpdateStatus;
end;

procedure TMultiAssemblyForm.MateClick(Sender: TObject);
begin
  if MechView.MateMode <> mmNone then
  begin
    MechView.CancelMateMode;
    Exit;
  end;
  if P.ComponentCount < 2 then
  begin
    StatusLabel.Caption := 'Unir peças: insira ao menos duas peças na montagem.';
    Exit;
  end;
  if not MechView.Visible then
  begin
    BtnViewIso.Tag := 0;
    ViewModeClick(BtnViewIso);
  end;
  MechView.StartMateMode;
end;

procedure TMultiAssemblyForm.OnMateCreated(Sender: TObject);
begin
  RefreshAll;
end;

procedure TMultiAssemblyForm.OnMateStatus(Sender: TObject; const Msg: string);
begin
  StatusLabel.Caption := Msg;
end;

procedure TMultiAssemblyForm.OnCanvasKinematicMove(Sender: TObject; const ComponentID: string);
var
  Pos: TAssemblyVec3;
  DOF: TComponentDOF;
begin
  if FSolver = nil then Exit;
  Pos := FSolver.GetSolvedPosition(ComponentID);
  DOF := FSolver.GetDOF(ComponentID);
  CoordsLabel.Caption := Format('%s: X=%.1f  Y=%.1f  Z=%.1f  [%s]', [ComponentID, Pos.X, Pos.Y, Pos.Z, DOF.StatusText]);
  if FSolver.CollisionCount > 0 then
    StatusLabel.Caption := Format('⚠️ ALERTA: %d colisão(ões) detectada(s) durante o movimento!', [FSolver.CollisionCount])
  else
    StatusLabel.Caption := 'Movimentação cinemática consistente.';
  RefreshRelations;
end;

procedure TMultiAssemblyForm.AddPortClick(Sender: TObject);
var
  Idx: Integer;
  C: TAssemblyComponent;
begin
  Idx := P.FindComponent(MechView.SelectedID);
  if Idx < 0 then Exit;
  C := P.Component(Idx);
  TAssemblyLibrary.AddPort(C, EdPortName.Text, TAssemblyPortKind(CbPortKind.ItemIndex), StrToFloatDef(EdPortVolt.Text, 0));
  P.UpdateComponent(Idx, C);
  RefreshPortsAndWires;
  ElecView.Invalidate;
  MarkModified;
end;

procedure TMultiAssemblyForm.FromCompChange;
var
  Idx, I: Integer;
  C: TAssemblyComponent;
begin
  CbFromPort.Items.Clear;
  Idx := P.FindComponent(MechView.SelectedID);
  if Idx < 0 then Exit;
  C := P.Component(Idx);
  for I := 0 to High(C.Ports) do
    CbFromPort.Items.Add(C.Ports[I].Name);
  if CbFromPort.Items.Count > 0 then
    CbFromPort.ItemIndex := 0;
end;

procedure TMultiAssemblyForm.ToCompChange(Sender: TObject);
var
  Idx, I: Integer;
  C: TAssemblyComponent;
begin
  CbToPort.Items.Clear;
  Idx := P.FindComponent(CbToComp.Text);
  if Idx < 0 then Exit;
  C := P.Component(Idx);
  for I := 0 to High(C.Ports) do
    CbToPort.Items.Add(C.Ports[I].Name);
  if CbToPort.Items.Count > 0 then
    CbToPort.ItemIndex := 0;
end;

procedure TMultiAssemblyForm.ConnectWireClick(Sender: TObject);
var
  W: TElectricalConnection;
begin
  if (MechView.SelectedID = '') or (CbFromPort.Text = '') or (CbToComp.Text = '') or (CbToPort.Text = '') then
  begin
    ShowMessage('Selecione os componentes e portas de origem e destino.');
    Exit;
  end;
  W.FromComponent := MechView.SelectedID;
  W.FromPort := CbFromPort.Text;
  W.ToComponent := CbToComp.Text;
  W.ToPort := CbToPort.Text;
  W.Caption := EdWireCaption.Text;
  P.Connect(W);
  RefreshPortsAndWires;
  ElecView.Invalidate;
  MarkModified;
end;

procedure TMultiAssemblyForm.DeleteWireClick(Sender: TObject);
begin
  if WireList.ItemIndex < 0 then Exit;
  P.RemoveWire(WireList.ItemIndex);
  RefreshPortsAndWires;
  ElecView.Invalidate;
  MarkModified;
end;

procedure TMultiAssemblyForm.RunAuditClick(Sender: TObject);
var
  Issues: TAssemblyIssues;
  Interfs: TInterferencePairs;
  I: Integer;
  ErrCount, WarnCount: Integer;
  OutLines: TStringList;
begin
  IssueList.Items.BeginUpdate;
  OutLines := TStringList.Create;
  try
    IssueList.Clear;
    Issues := TAssemblyERC.Check(P);
    ErrCount := 0;
    WarnCount := 0;

    for I := 0 to High(Issues) do
    begin
      if Issues[I].Severity = isError then
      begin
        Inc(ErrCount);
        IssueList.Items.Add('[ERRO ERC] ' + Issues[I].ComponentID + ': ' + Issues[I].Message);
      end
      else if Issues[I].Severity = isWarning then
      begin
        Inc(WarnCount);
        IssueList.Items.Add('[AVISO ERC] ' + Issues[I].ComponentID + ': ' + Issues[I].Message);
      end
      else
        IssueList.Items.Add('[INFO] ' + Issues[I].ComponentID + ': ' + Issues[I].Message);
    end;

    // Verificacao de interferencias
    Interfs := TAssemblyInterference.Check(P);
    for I := 0 to High(Interfs) do
    begin
      Inc(WarnCount);
      IssueList.Items.Add(Format('[INTERFERÊNCIA] %s colide com %s (Vol: %.1f mm³)', [Interfs[I].IDA, Interfs[I].IDB, Interfs[I].OverlapVolume]));
    end;

    LblErcSummary.Caption := Format('Resultado da Auditoria: %d Erro(s) crítico(s), %d Aviso(s), %d Colisão(ões).', [ErrCount, WarnCount - Length(Interfs), Length(Interfs)]);
    if ErrCount > 0 then
      LblErcSummary.Font.Color := clSuiteDanger
    else if WarnCount > 0 then
      LblErcSummary.Font.Color := clSuiteWarning
    else
      LblErcSummary.Font.Color := clSuiteSuccess;

  finally
    OutLines.Free;
    IssueList.Items.EndUpdate;
  end;
end;

procedure TMultiAssemblyForm.IssueListClick(Sender: TObject);
var
  LineStr: string;
  I: Integer;
begin
  if IssueList.ItemIndex < 0 then Exit;
  LineStr := IssueList.Items[IssueList.ItemIndex];
  for I := 0 to P.ComponentCount - 1 do
  begin
    if Pos(P.Component(I).ID, LineStr) > 0 then
    begin
      OnCanvasSelect(Self, P.Component(I).ID);
      Break;
    end;
  end;
end;

procedure TMultiAssemblyForm.ExportBomCSVClick(Sender: TObject);
var
  SD: TSaveDialog;
  BOM: TBOMLines;
  OutList: TStringList;
begin
  SD := TSaveDialog.Create(Self);
  OutList := TStringList.Create;
  try
    SD.Filter := 'Arquivo CSV (*.csv)|*.csv';
    SD.FileName := 'BOM_' + P.Name + '.csv';
    if SD.Execute then
    begin
      BOM := TAssemblyBOM.Build(P);
      TAssemblyBOM.ToCSV(BOM, OutList);
      OutList.SaveToFile(SD.FileName);
      ShowMessage('Lista de Materiais salva com sucesso: ' + SD.FileName);
    end;
  finally
    OutList.Free;
    SD.Free;
  end;
end;

procedure TMultiAssemblyForm.ExportBomJSONClick(Sender: TObject);
var
  SD: TSaveDialog;
  BOM: TBOMLines;
  JSONStr: string;
  SL: TStringList;
begin
  SD := TSaveDialog.Create(Self);
  SL := TStringList.Create;
  try
    SD.Filter := 'Arquivo JSON (*.json)|*.json';
    SD.FileName := 'BOM_' + P.Name + '.json';
    if SD.Execute then
    begin
      BOM := TAssemblyBOM.Build(P);
      JSONStr := TAssemblyBOM.ToJSON(BOM);
      SL.Text := JSONStr;
      SL.SaveToFile(SD.FileName);
      ShowMessage('Lista de Materiais em JSON salva: ' + SD.FileName);
    end;
  finally
    SL.Free;
    SD.Free;
  end;
end;

procedure TMultiAssemblyForm.StepListClick(Sender: TObject);
var
  S: TManualStep;
begin
  if StepListBox.ItemIndex < 0 then Exit;
  S := P.Step(StepListBox.ItemIndex);
  EdStepTitle.Text := S.Title;
  EdStepTools.Text := S.Tools;
  MemStepInstr.Text := S.Instructions;
  MemStepChecks.Text := S.Checks;

  // Atualiza destaque na vista mecanica
  MechView.ActiveStep := StepListBox.ItemIndex;
  MechView.Invalidate;
  RefreshManualPreview;
end;

procedure TMultiAssemblyForm.AddStepClick(Sender: TObject);
var
  S: TManualStep;
begin
  S.ID := 'STEP_' + IntToStr(P.StepCount + 1);
  S.Order := P.StepCount + 1;
  S.Title := 'Nova Etapa de Montagem';
  S.Tools := '';
  S.Instructions := '';
  S.Checks := '';
  SetLength(S.ComponentIDs, 0);
  P.AddStep(S);
  RefreshSteps;
  StepListBox.ItemIndex := P.StepCount - 1;
  StepListClick(nil);
  MarkModified;
end;

procedure TMultiAssemblyForm.SaveStepClick(Sender: TObject);
var
  S: TManualStep;
begin
  if StepListBox.ItemIndex < 0 then Exit;
  S := P.Step(StepListBox.ItemIndex);
  S.Title := EdStepTitle.Text;
  S.Tools := EdStepTools.Text;
  S.Instructions := MemStepInstr.Text;
  S.Checks := MemStepChecks.Text;
  P.UpdateStep(StepListBox.ItemIndex, S);
  RefreshSteps;
  RefreshManualPreview;
  MarkModified;
end;

procedure TMultiAssemblyForm.DeleteStepClick(Sender: TObject);
begin
  if StepListBox.ItemIndex < 0 then Exit;
  P.RemoveStep(StepListBox.ItemIndex);
  RefreshSteps;
  RefreshManualPreview;
  MarkModified;
end;

procedure TMultiAssemblyForm.MoveStepUpClick(Sender: TObject);
var
  Idx: Integer;
begin
  Idx := StepListBox.ItemIndex;
  if Idx > 0 then
  begin
    P.MoveStepUp(Idx);
    RefreshSteps;
    StepListBox.ItemIndex := Idx - 1;
    StepListClick(nil);
    MarkModified;
  end;
end;

procedure TMultiAssemblyForm.MoveStepDownClick(Sender: TObject);
var
  Idx: Integer;
begin
  Idx := StepListBox.ItemIndex;
  if (Idx >= 0) and (Idx < P.StepCount - 1) then
  begin
    P.MoveStepDown(Idx);
    RefreshSteps;
    StepListBox.ItemIndex := Idx + 1;
    StepListClick(nil);
    MarkModified;
  end;
end;

procedure TMultiAssemblyForm.AssignCompToStepClick(Sender: TObject);
var
  S: TManualStep;
  I, N: Integer;
begin
  if (StepListBox.ItemIndex < 0) or (MechView.SelectedID = '') then Exit;
  S := P.Step(StepListBox.ItemIndex);
  for I := 0 to High(S.ComponentIDs) do
    if SameText(S.ComponentIDs[I], MechView.SelectedID) then Exit; // Ja atribuido

  N := Length(S.ComponentIDs);
  SetLength(S.ComponentIDs, N + 1);
  S.ComponentIDs[N] := MechView.SelectedID;
  P.UpdateStep(StepListBox.ItemIndex, S);
  RefreshManualPreview;
  ShowMessage('Componente ' + MechView.SelectedID + ' vinculado à Etapa ' + IntToStr(S.Order));
  MarkModified;
end;

procedure TMultiAssemblyForm.GenerateHTMLManualClick(Sender: TObject);
var
  SD: TSaveDialog;
  HTMLStr: string;
  SL: TStringList;
begin
  SD := TSaveDialog.Create(Self);
  SL := TStringList.Create;
  try
    SD.Filter := 'Manual HTML (*.html)|*.html';
    SD.FileName := 'Manual_' + P.Name + '.html';
    if SD.Execute then
    begin
      HTMLStr := TAssemblyManualGenerator.ToHTML(P);
      SL.Text := HTMLStr;
      SL.SaveToFile(SD.FileName);
      ShowMessage('Manual ilustrado HTML gerado com sucesso: ' + SD.FileName);
    end;
  finally
    SL.Free;
    SD.Free;
  end;
end;

procedure TMultiAssemblyForm.GenerateMarkdownManualClick(Sender: TObject);
var
  SD: TSaveDialog;
  MDStr: string;
  SL: TStringList;
begin
  SD := TSaveDialog.Create(Self);
  SL := TStringList.Create;
  try
    SD.Filter := 'Manual Markdown (*.md)|*.md';
    SD.FileName := 'Manual_' + P.Name + '.md';
    if SD.Execute then
    begin
      MDStr := TAssemblyManualGenerator.ToMarkdown(P);
      SL.Text := MDStr;
      SL.SaveToFile(SD.FileName);
      ShowMessage('Manual Markdown gerado com sucesso: ' + SD.FileName);
    end;
  finally
    SL.Free;
    SD.Free;
  end;
end;

{ salva a montagem e abre o MultiPhysics com ela (--file): o MultiPhysics
  importa pecas, geometria, posicoes, fixos e contatos }
procedure TMultiAssemblyForm.ExportMultiPhysicsClick(Sender: TObject);
var
  Reg: TSuiteRegistry;
  Idx: Integer;
  Err: string;
begin
  SaveProjectClick(nil);
  if P.FileName = '' then
  begin
    StatusLabel.Caption := 'Salve a montagem para simular no MultiPhysics.';
    Exit;
  end;
  Reg := TSuiteRegistry.Create;
  try
    Idx := Reg.Find(stiMultiPhysics);
    if (Idx < 0) or not TSuiteLauncher.LaunchArtifact(Reg.Tool(Idx), '', '', P.FileName, Err) then
      MessageDlg('MultiPhysics', 'Montagem salva em:' + LineEnding + P.FileName + LineEnding + LineEnding +
        'Nao foi possivel abrir o MultiPhysics: ' + Err, mtWarning, [mbOK], 0)
    else
      StatusLabel.Caption := 'Montagem aberta no MultiPhysics: ' + ExtractFileName(P.FileName);
  finally
    Reg.Free;
  end;
end;

procedure TMultiAssemblyForm.RefreshAll;
begin
  FUpdating := True;
  try
    EdProjName.Text := P.Name;
    EdProjVer.Text := P.Version;
    EdProjAuthor.Text := P.Author;

    RefreshCompList;
    RefreshSelectedProps;
    RefreshRelations;
    RefreshPortsAndWires;
    RefreshSteps;
    RefreshManualPreview;
    UpdateStatus;
    MechView.Invalidate;
    ElecView.Invalidate;
  finally
    FUpdating := False;
  end;
end;

procedure TMultiAssemblyForm.RefreshCompList;
var
  I, PrevIdx: Integer;
  DOF: TComponentDOF;
  Prefix: string;
begin
  PrevIdx := CompList.ItemIndex;
  CompList.Items.BeginUpdate;
  try
    CompList.Clear;
    CbRelTarget.Items.Clear;
    CbToComp.Items.Clear;
    if FSolver <> nil then
      FSolver.AnalyzeDOFs;
    for I := 0 to P.ComponentCount - 1 do
    begin
      if FSolver <> nil then
        DOF := FSolver.GetDOFByIndex(I)
      else
      begin
        if P.Component(I).Fixed then DOF.Status := adsFixed else DOF.Status := adsUnderdefined;
      end;
      case DOF.Status of
        adsFixed: Prefix := '(f) ';
        adsUnderdefined: Prefix := '(-) ';
        adsFullyDefined: Prefix := '( ) ';
        adsOverdefined: Prefix := '(+) ';
      end;
      CompList.Items.AddObject(Prefix + P.Component(I).ID + ' - ' + P.Component(I).Name, TObject(PtrInt(I)));
      CbRelTarget.Items.Add(P.Component(I).ID);
      CbToComp.Items.Add(P.Component(I).ID);
    end;
    if (PrevIdx >= 0) and (PrevIdx < CompList.Count) then
      CompList.ItemIndex := PrevIdx
    else if CompList.Count > 0 then
      CompList.ItemIndex := 0;
  finally
    CompList.Items.EndUpdate;
  end;
end;

procedure TMultiAssemblyForm.RefreshSelectedProps;
var
  Idx: Integer;
  C: TAssemblyComponent;
begin
  Idx := P.FindComponent(MechView.SelectedID);
  if Idx < 0 then
  begin
    EdCompID.Text := '';
    EdCompName.Text := '';
    EdCompModel.Text := '';
    EdCompMat.Text := '';
    Exit;
  end;
  C := P.Component(Idx);
  EdCompID.Text := C.ID;
  EdCompName.Text := C.Name;
  EdCompModel.Text := C.Model;
  EdCompMat.Text := C.Material;
  EdPosX.Text := FloatToStrF(C.Position.X, ffFixed, 8, 2);
  EdPosY.Text := FloatToStrF(C.Position.Y, ffFixed, 8, 2);
  EdPosZ.Text := FloatToStrF(C.Position.Z, ffFixed, 8, 2);
  EdSizeW.Text := FloatToStrF(C.Size.X, ffFixed, 8, 2);
  EdSizeH.Text := FloatToStrF(C.Size.Y, ffFixed, 8, 2);
  EdSizeD.Text := FloatToStrF(C.Size.Z, ffFixed, 8, 2);

  if (BtnFixFloat <> nil) and (Idx >= 0) then
  begin
    if C.Fixed then
    begin
      BtnFixFloat.Caption := 'Flutuar Peça (-)';
      BtnFixFloat.SetLook(sbsSoft, clSuiteWarning, sikLayers);
    end
    else
    begin
      BtnFixFloat.Caption := 'Fixar na Base (f)';
      BtnFixFloat.SetLook(sbsSoft, clSuitePrimary, sikOrigin);
    end;
  end;

  FromCompChange;
  RefreshRelations;
  RefreshPortsAndWires;
end;

procedure TMultiAssemblyForm.RefreshRelations;
var
  I: Integer;
  R: TMechanicalRelation;
  Desc: string;
  Joints: array of TKinematicJointInfo;
  PrevJointIdx: Integer;
begin
  RelList.Items.BeginUpdate;
  try
    RelList.Clear;
    for I := 0 to P.RelationCount - 1 do
    begin
      R := P.Relation(I);
      case R.Kind of
        mrFixed: Desc := Format('Fixo: %s <-> %s', [R.A, R.B]);
        mrCoincident: Desc := Format('Coincidente: %s <-> %s', [R.A, R.B]);
        mrConcentric: Desc := Format('Concêntrico: %s <-> %s', [R.A, R.B]);
        mrSlider: Desc := Format('Deslizador: %s <-> %s (%.1f..%.1f mm)', [R.A, R.B, R.MinLimit, R.MaxLimit]);
        mrHinge: Desc := Format('Articulação: %s <-> %s (%.1f..%.1f °)', [R.A, R.B, R.MinLimit, R.MaxLimit]);
        mrLeadScrew: Desc := Format('Fuso: %s <-> %s (Passo: %.1f mm)', [R.A, R.B, R.PitchMM]);
        mrBelt: Desc := Format('Correia: %s <-> %s (Ratio: %.2f)', [R.A, R.B, R.Ratio]);
        mrAxis: Desc := Format('Eixo: %s <-> %s', [R.A, R.B]);
        mrDistance: Desc := Format('Distância: %s <-> %s (%.1f mm)', [R.A, R.B, R.Distance]);
        mrInsert: Desc := Format('Inserir: %s -> %s', [R.A, R.B]);
        mrParallel: Desc := Format('Paralelo: %s <-> %s', [R.A, R.B]);
      else
        Desc := Format('%s <-> %s (Tipo %d)', [R.A, R.B, Ord(R.Kind)]);
      end;
      if R.HasRefs then Desc := Desc + ' • por referência';
      RelList.Items.AddObject(Desc, TObject(PtrInt(I)));
    end;
  finally
    RelList.Items.EndUpdate;
  end;

  if (CbActiveJoints <> nil) and (FSolver <> nil) then
  begin
    PrevJointIdx := CbActiveJoints.ItemIndex;
    CbActiveJoints.Items.BeginUpdate;
    try
      CbActiveJoints.Items.Clear;
      Joints := FSolver.GetActiveJoints;
      for I := 0 to High(Joints) do
        CbActiveJoints.Items.Add(Format('%s [%.1f %s]', [Joints[I].Name, Joints[I].CurrentValue, Joints[I].UnitStr]));

      if (PrevJointIdx >= 0) and (PrevJointIdx < CbActiveJoints.Items.Count) then
        CbActiveJoints.ItemIndex := PrevJointIdx
      else if CbActiveJoints.Items.Count > 0 then
        CbActiveJoints.ItemIndex := 0;
    finally
      CbActiveJoints.Items.EndUpdate;
    end;
  end;

  if (LblCollisionStatus <> nil) and (FSolver <> nil) then
  begin
    if FSolver.CollisionCount > 0 then
    begin
      LblCollisionStatus.Font.Color := $4040FF;
      LblCollisionStatus.Caption := Format('⚠️ Alerta: %d colisão(ões) detectada(s) entre peças!', [FSolver.CollisionCount]);
    end
    else
    begin
      LblCollisionStatus.Font.Color := clSuiteSuccess;
      LblCollisionStatus.Caption := '✅ Montagem consistente • Sem colisões detectadas.';
    end;
  end;
end;

procedure TMultiAssemblyForm.RefreshPortsAndWires;
var
  Idx, I: Integer;
  C: TAssemblyComponent;
  W: TElectricalConnection;
begin
  PortList.Items.BeginUpdate;
  WireList.Items.BeginUpdate;
  try
    PortList.Clear;
    Idx := P.FindComponent(MechView.SelectedID);
    if Idx >= 0 then
    begin
      C := P.Component(Idx);
      for I := 0 to High(C.Ports) do
        PortList.Items.Add(Format('%s (%s, %.1fV)', [C.Ports[I].Name, PortKindName(C.Ports[I].Kind), C.Ports[I].Voltage]));
    end;

    WireList.Clear;
    for I := 0 to P.WireCount - 1 do
    begin
      W := P.Wire(I);
      WireList.Items.Add(Format('%s.%s -> %s.%s (%s)', [W.FromComponent, W.FromPort, W.ToComponent, W.ToPort, W.Caption]));
    end;
  finally
    PortList.Items.EndUpdate;
    WireList.Items.EndUpdate;
  end;
end;

procedure TMultiAssemblyForm.RefreshSteps;
var
  I: Integer;
begin
  StepListBox.Items.BeginUpdate;
  try
    StepListBox.Clear;
    for I := 0 to P.StepCount - 1 do
      StepListBox.Items.Add(Format('%d. %s', [P.Step(I).Order, P.Step(I).Title]));
  finally
    StepListBox.Items.EndUpdate;
  end;
end;

procedure TMultiAssemblyForm.RefreshManualPreview;
var
  Idx, I: Integer;
  S: TManualStep;
  CompsStr: string;
begin
  if StepListBox.ItemIndex >= 0 then
    Idx := StepListBox.ItemIndex
  else
    Idx := 0;

  if (Idx >= 0) and (Idx < P.StepCount) then
  begin
    S := P.Step(Idx);
    ManualStepTitle.Caption := Format('ETAPA %d: %s', [S.Order, S.Title]);
    ManualStepTools.Caption := 'Ferramentas: ' + S.Tools;
    ManualStepChecks.Caption := 'Conferência: ' + S.Checks;
    CompsStr := '';
    for I := 0 to High(S.ComponentIDs) do
      CompsStr := CompsStr + S.ComponentIDs[I] + ' ';
    ManualStepComps.Caption := 'Peças montadas: ' + CompsStr;
  end
  else
  begin
    ManualStepTitle.Caption := 'Nenhuma etapa selecionada';
    ManualStepTools.Caption := '';
    ManualStepChecks.Caption := '';
    ManualStepComps.Caption := '';
  end;
end;

procedure TMultiAssemblyForm.UpdateStatus;
begin
  SidebarInfo.Caption := Format('%d Peças'#13#10'%d Ligações Elétricas'#13#10'%d Relações Mecânicas'#13#10'%d Etapas do Manual',
    [P.ComponentCount, P.WireCount, P.RelationCount, P.StepCount]);

  LblProjStats.Caption := Format('Resumo do Conjunto:'#13#10'• Total de Componentes: %d'#13#10'• Ligações Elétricas: %d'#13#10'• Vínculos Mecânicos: %d'#13#10'• Passos do Manual: %d',
    [P.ComponentCount, P.WireCount, P.RelationCount, P.StepCount]);

  LblBomSummary.Caption := Format('Total de %d itens agrupados na Lista de Materiais.', [Length(TAssemblyBOM.Build(P))]);

  if P.ComponentCount = 0 then
  begin
    StatusLabel.Caption := 'Montagem em branco (0 componentes).';
    CoordsLabel.Caption := 'Insira o primeiro componente (âncora fixa) pelo botão "+ Inserir Peça na Montagem".';
  end
  else if MechView.SelectedID <> '' then
  begin
    StatusLabel.Caption := 'Peça Selecionada: ' + MechView.SelectedID;
    CoordsLabel.Caption := Format('Dimensões: %s x %s x %s mm', [EdSizeW.Text, EdSizeH.Text, EdSizeD.Text]);
  end
  else
  begin
    StatusLabel.Caption := 'Projeto: ' + P.Name;
    CoordsLabel.Caption := 'Clique em uma peça para inspecionar e vincular.';
  end;
end;

procedure TMultiAssemblyForm.MarkModified;
begin
  P.IsModified := True;
  UpdateStatus;
end;

end.
