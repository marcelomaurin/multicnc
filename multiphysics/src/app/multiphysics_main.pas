unit multiphysics_main;

{ MultiPhysics - simulacao fisica da montagem, no padrao visual da suite
  (MultiAssembly / MakeRouter): cabecalho, etapas a esquerda, painel de
  propriedades a direita, vista 3D ou grafico no centro e log embaixo.

  Etapas: Montagem, Materiais, Cargas e fixacoes, Malha, Resolver,
  Resultados (FEM proprio, ver multiphysics_analysis) e Sistema, Maquina
  CNC, Circuito, Ambiente (modelos reduzidos, sempre ESTIMATIVA). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, StrUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  ComCtrls, Spin, LCLType, multisuite_numfmt, multisuite_controls, multisuite_icons,
  multisuite_context, multiphysics_types, multiphysics_materials, multiphysics_vector,
  multiphysics_geometry, multiphysics_mesh, multiphysics_project, multiphysics_analysis,
  multiphysics_scenario, multiphysics_environment, multiphysics_rigidbody,
  multiphysics_buoyancy, multiphysics_runtime, multiphysics_runtime_types,
  multiphysics_graph, multiphysics_graph_runtime, multiphysics_machine_runtime,
  multiphysics_machine_faults, multiphysics_netlist, multiphysics_units,
  multiphysics_view3d, multiphysics_chart;

const
  STEP_COUNT = 10;

type
  TMultiPhysicsForm = class(TForm)
  private
    P: TPhysicsProject;
    Run: TAnalysisRun;
    HasResult: Boolean;
    FUpdating: Boolean;
    FStep: Integer;
    { estrutura }
    Header: TSuiteHeader;
    Badge: TSuiteBadge;
    Footer, Sidebar, Work, ViewBar: TPanel;
    StatusLabel, InfoLabel: TLabel;
    Nav: array[0..STEP_COUNT - 1] of TSuiteButton;
    Tree: TTreeView;
    Pages: TPageControl;
    View: TPhysicsView3D;
    Chart: TPhysicsChart;
    Log: TMemo;
    { 1 montagem }
    EdProjectName: TEdit;
    CbPrimKind, CbAxis: TComboBox;
    EdPartID: TEdit;
    EdDim: array[0..3] of TFloatSpinEdit;
    LbDim: array[0..3] of TLabel;
    LbParts: TListBox;
    EdPos, EdRot: array[0..2] of TFloatSpinEdit;
    CkSuppressed: TCheckBox;
    { 2 materiais }
    LbMatParts: TListBox;
    CbMaterial: TComboBox;
    EdE, EdNu, EdRho, EdK, EdAlpha, EdYield: TFloatSpinEdit;
    { 3 cargas }
    LbBCs: TListBox;
    EdBCName: TEdit;
    CbBCKind, CbBCPart, CbBCFace: TComboBox;
    EdVec: array[0..2] of TFloatSpinEdit;
    EdVal1, EdVal2: TFloatSpinEdit;
    LbVecUnit, LbVal1, LbVal2: TLabel;
    CkDof: array[0..2] of TCheckBox;
    { 4 malha }
    EdMeshSize: TFloatSpinEdit;
    CkQuadratic, CkConvergence: TCheckBox;
    LbMeshInfo: TLabel;
    { 5 resolver }
    CbAnalysis: TComboBox;
    EdModes: TSpinEdit;
    { 6 resultados }
    CbField: TComboBox;
    EdScale: TFloatSpinEdit;
    CkAnimate, CkDeformed: TCheckBox;
    LbSummary: TLabel;
    { 7 sistema }
    Graph: TSimulationGraph;
    GraphRuntime: TGraphRuntime;
    Runtime: TSimulationRuntime;
    RuntimeTimer: TTimer;
    LbRuntime: TLabel;
    { 8 maquina }
    Machine: TMachineRuntime;
    EdTarget: array[0..2] of TFloatSpinEdit;
    EdFeed: TFloatSpinEdit;
    CbFault, CbFaultAxis: TComboBox;
    LbMachine: TLabel;
    { 9 circuito }
    MmNetlist: TMemo;
    { 10 ambiente }
    Scenario: TSimulationScenario;
    CbEnv: TComboBox;
    EdFlow, EdArea, EdVolume, EdCd, EdMass: TFloatSpinEdit;

    function Btn(AParent: TWinControl; const AText: string; X, Y, W, H: Integer;
      AIcon: TSuiteIconKind; Handler: TNotifyEvent): TSuiteButton;
    function Lbl(AParent: TWinControl; const AText: string; X, Y, W, H: Integer): TLabel;
    function Num(AParent: TWinControl; const ACaption: string; X, Y, W: Integer;
      AMin, AMax, AValue: Double; ADec: Integer): TFloatSpinEdit;
    function Combo(AParent: TWinControl; const ACaption: string; X, Y, W: Integer): TComboBox;
    procedure BuildPages;
    procedure BuildAssemblyPage(S: TScrollBox);
    procedure BuildMaterialsPage(S: TScrollBox);
    procedure BuildLoadsPage(S: TScrollBox);
    procedure BuildMeshPage(S: TScrollBox);
    procedure BuildSolvePage(S: TScrollBox);
    procedure BuildResultsPage(S: TScrollBox);
    procedure BuildSystemPage(S: TScrollBox);
    procedure BuildMachinePage(S: TScrollBox);
    procedure BuildCircuitPage(S: TScrollBox);
    procedure BuildEnvironmentPage(S: TScrollBox);
    procedure ShowStep(I: Integer);
    procedure SetStatus(const S: string);
    procedure RefreshAll;
    procedure RefreshTree;
    procedure RefreshPartLists;
    procedure RefreshBCList;
    procedure RefreshFaceCombo;
    procedure UpdateBCUnits;
    procedure UpdatePrimLabels;
    procedure ShowMarks;
    procedure ShowResultField;
    procedure ApplySettingsFromUI;
    function SelectedPart: TPhysicsPart;
    function BCFromUI(out B: TBoundaryCondition): Boolean;
    procedure LoadProjectFile(const FN: string);
    { eventos }
    procedure NavClick(Sender: TObject);
    procedure NewClick(Sender: TObject);
    procedure OpenClick(Sender: TObject);
    procedure SaveClick(Sender: TObject);
    procedure DemoClick(Sender: TObject);
    procedure ProjectNameChange(Sender: TObject);
    procedure PrimKindChange(Sender: TObject);
    procedure AddPartClick(Sender: TObject);
    procedure PartListClick(Sender: TObject);
    procedure ApplyPartClick(Sender: TObject);
    procedure DeletePartClick(Sender: TObject);
    procedure MatPartListClick(Sender: TObject);
    procedure MaterialChange(Sender: TObject);
    procedure ApplyMaterialClick(Sender: TObject);
    procedure ApplyMaterialAllClick(Sender: TObject);
    procedure BCKindChange(Sender: TObject);
    procedure BCPartChange(Sender: TObject);
    procedure BCListClick(Sender: TObject);
    procedure AddBCClick(Sender: TObject);
    procedure UpdateBCClick(Sender: TObject);
    procedure DeleteBCClick(Sender: TObject);
    procedure ViewPickFace(Sender: TObject; FaceTag: Integer; const TagName: string);
    procedure MeshClick(Sender: TObject);
    procedure SolveClick(Sender: TObject);
    procedure FieldChange(Sender: TObject);
    procedure ExportCSVClick(Sender: TObject);
    procedure ReportClick(Sender: TObject);
    procedure ViewFitClick(Sender: TObject);
    procedure ViewDirClick(Sender: TObject);
    procedure LoadMachineClick(Sender: TObject);
    procedure RuntimeStartClick(Sender: TObject);
    procedure RuntimePauseClick(Sender: TObject);
    procedure RuntimeStopClick(Sender: TObject);
    procedure RuntimeTick(Sender: TObject);
    procedure ChartCSVClick(Sender: TObject);
    procedure MachineCreateClick(Sender: TObject);
    procedure MachineMoveClick(Sender: TObject);
    procedure MachineFaultClick(Sender: TObject);
    procedure CircuitSolveClick(Sender: TObject);
    procedure EnvChange(Sender: TObject);
    procedure EstimateClick(Sender: TObject);
    procedure FloatTestClick(Sender: TObject);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure CaptureTick(Sender: TObject);
    procedure HeaderResize(Sender: TObject);
    procedure SetBadge(const ACaption: string; AColor: TColor);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

implementation

const
  STEP_NAMES: array[0..STEP_COUNT - 1] of string = (
    '1  Montagem', '2  Materiais', '3  Cargas e fixacoes', '4  Malha', '5  Resolver',
    '6  Resultados', '7  Sistema', '8  Maquina CNC', '9  Circuito', '10 Ambiente');
  BC_KINDS: array[0..8] of TBoundaryKind = (bkFixed, bkDisplacement, bkForce, bkPressure,
    bkGravity, bkTemperature, bkHeatFlux, bkConvection, bkHeatPower);
  DEMO_NETLIST =
    '* Filtro RC com degrau de 10 V'#13#10 +
    'V1 in 0 10'#13#10 +
    'R1 in out 1k'#13#10 +
    'C1 out 0 1u'#13#10 +
    '.tran 10u 5m'#13#10 +
    '.probe in out'#13#10;

function StepIcon(I: Integer): TSuiteIconKind;
begin
  case I of
    0: Result := sikAssembly;
    1: Result := sikLayers;
    2: Result := sikTarget;
    3: Result := sikPolygon;
    4: Result := sikPlay;
    5: Result := sikEye;
    6: Result := sikPulse;
    7: Result := sikCNC;
    8: Result := sikPlug;
    else Result := sikThermo;
  end;
end;

function BCKindIndex(K: TBoundaryKind): Integer;
var
  I: Integer;
begin
  for I := 0 to High(BC_KINDS) do
    if BC_KINDS[I] = K then Exit(I);
  Result := 0;
end;

{ ---------------- construcao ---------------- }

function TMultiPhysicsForm.Btn(AParent: TWinControl; const AText: string; X, Y, W, H: Integer;
  AIcon: TSuiteIconKind; Handler: TNotifyEvent): TSuiteButton;
begin
  Result := TSuiteButton.Create(Self);
  Result.Parent := AParent;
  Result.SetBounds(X, Y, W, H);
  Result.Caption := AText;
  Result.SetLook(sbsSoft, clSuitePrimary, AIcon);
  Result.OnClick := Handler;
end;

function TMultiPhysicsForm.Lbl(AParent: TWinControl; const AText: string; X, Y, W, H: Integer): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := AParent;
  Result.AutoSize := False;
  Result.WordWrap := True;
  Result.SetBounds(X, Y, W, H);
  Result.Caption := AText;
  Result.Font.Color := clSuiteMuted;
end;

function TMultiPhysicsForm.Num(AParent: TWinControl; const ACaption: string; X, Y, W: Integer;
  AMin, AMax, AValue: Double; ADec: Integer): TFloatSpinEdit;
begin
  if ACaption <> '' then Lbl(AParent, ACaption, X, Y, Max(W + 40, 306 - X), 18).BringToFront;
  Result := TFloatSpinEdit.Create(Self);
  Result.Parent := AParent;
  Result.SetBounds(X, Y + 19, W, 26);
  Result.MinValue := AMin;
  Result.MaxValue := AMax;
  Result.DecimalPlaces := ADec;
  Result.Value := AValue;
end;

function TMultiPhysicsForm.Combo(AParent: TWinControl; const ACaption: string; X, Y, W: Integer): TComboBox;
begin
  if ACaption <> '' then Lbl(AParent, ACaption, X, Y, W, 18);
  Result := TComboBox.Create(Self);
  Result.Parent := AParent;
  Result.SetBounds(X, Y + 19, W, 26);
  Result.Style := csDropDownList;
end;

constructor TMultiPhysicsForm.Create(AOwner: TComponent);
var
  I: Integer;
  B: TSuiteButton;
  Split: TSplitter;
  Ctx: TSuiteContext;
begin
  inherited CreateNew(AOwner, 1);
  Caption := 'MultiPhysics • MultiSuite';
  Width := 1360; Height := 880;
  Constraints.MinWidth := 1100; Constraints.MinHeight := 700;
  Position := poScreenCenter;
  Font.Name := SUITE_FONT; Font.Size := 10;
  Color := clSuiteSurface;
  KeyPreview := True;
  OnCloseQuery := @FormCloseQuery;
  if FileExists(ExtractFilePath(ParamStr(0)) + 'multiphysics.ico') then
    Icon.LoadFromFile(ExtractFilePath(ParamStr(0)) + 'multiphysics.ico');

  P := TPhysicsProject.Create;
  Run := TAnalysisRun.Create(P);
  Runtime := TSimulationRuntime.Create;
  Machine := TMachineRuntime.Create;
  Scenario := MarineScenario;
  RuntimeTimer := TTimer.Create(Self);
  RuntimeTimer.Enabled := False;
  RuntimeTimer.Interval := 30;
  RuntimeTimer.OnTimer := @RuntimeTick;
  FUpdating := True;

  Header := TSuiteHeader.Create(Self);
  Header.Parent := Self;
  Header.Align := alTop;
  Header.Height := 72;
  Header.Setup('MultiPhysics', 'Simulacao fisica da montagem: estrutural, termica, modal, sistema e circuitos', sikPhysics);
  Badge := TSuiteBadge.Create(Self);
  Badge.Parent := Header;
  Badge.SetBounds(Header.ClientWidth - 330, 22, 300, 28);
  Header.OnResize := @HeaderResize;
  SetBadge('Sem resultado', clSuiteFaint);

  Footer := TPanel.Create(Self);
  Footer.Parent := Self;
  Footer.Align := alBottom;
  Footer.Height := 58;
  Footer.BevelOuter := bvNone;
  Footer.Color := clSuiteCard;
  StatusLabel := Lbl(Footer, 'Pronto.', 18, 8, 760, 22);
  StatusLabel.Font.Color := clSuiteText;
  StatusLabel.Font.Style := [fsBold];
  InfoLabel := Lbl(Footer, 'Projeto novo. Adicione pecas ou abra a demonstracao.', 18, 30, 760, 22);
  B := Btn(Footer, 'Resolver', 0, 11, 140, 36, sikPlay, @SolveClick);
  B.Anchors := [akTop, akRight];
  B.Left := Footer.ClientWidth - 156;
  B.SetLook(sbsSolid, clSuitePrimary, sikPlay);

  Sidebar := TPanel.Create(Self);
  Sidebar.Parent := Self;
  Sidebar.Align := alLeft;
  Sidebar.Width := 214;
  Sidebar.BevelOuter := bvNone;
  Sidebar.Color := clSuiteCard;
  for I := 0 to STEP_COUNT - 1 do
  begin
    Nav[I] := Btn(Sidebar, STEP_NAMES[I], 12, 12 + I * 37, 190, 32, StepIcon(I), @NavClick);
    Nav[I].Tag := I;
  end;
  Btn(Sidebar, 'Novo', 12, 390, 92, 30, sikNew, @NewClick);
  Btn(Sidebar, 'Abrir', 110, 390, 92, 30, sikFolder, @OpenClick);
  Btn(Sidebar, 'Salvar', 12, 424, 92, 30, sikSave, @SaveClick);
  Btn(Sidebar, 'Demo', 110, 424, 92, 30, sikWand, @DemoClick);
  Lbl(Sidebar, 'PROJETO', 16, 464, 180, 18).Font.Style := [fsBold];
  Tree := TTreeView.Create(Self);
  Tree.Parent := Sidebar;
  Tree.SetBounds(12, 484, 190, 200);
  Tree.Anchors := [akLeft, akTop, akRight, akBottom];
  Tree.ReadOnly := True;
  Tree.BorderStyle := bsNone;
  Tree.Color := SuiteRGB(248, 250, 252);

  Pages := TPageControl.Create(Self);
  Pages.Parent := Self;
  Pages.Align := alRight;
  Pages.Width := 340;
  Pages.ShowTabs := False;
  BuildPages;

  Work := TPanel.Create(Self);
  Work.Parent := Self;
  Work.Align := alClient;
  Work.BevelOuter := bvNone;
  Work.Color := clSuiteSurface;
  ViewBar := TPanel.Create(Self);
  ViewBar.Parent := Work;
  ViewBar.Align := alTop;
  ViewBar.Height := 46;
  ViewBar.BevelOuter := bvNone;
  ViewBar.Color := clSuiteSurface;
  Btn(ViewBar, 'Ajustar', 10, 7, 92, 32, sikFit, @ViewFitClick);
  B := Btn(ViewBar, 'Iso', 106, 7, 64, 32, sikFrame, @ViewDirClick); B.Tag := 0;
  B := Btn(ViewBar, 'Frente', 174, 7, 76, 32, sikRect, @ViewDirClick); B.Tag := 1;
  B := Btn(ViewBar, 'Topo', 254, 7, 70, 32, sikLayers, @ViewDirClick); B.Tag := 2;
  B := Btn(ViewBar, 'Lado', 328, 7, 70, 32, sikRect, @ViewDirClick); B.Tag := 3;
  Lbl(ViewBar, 'Arraste para girar, botao direito desloca, roda aproxima, clique seleciona a face.', 410, 14, 520, 20);

  Log := TMemo.Create(Self);
  Log.Parent := Work;
  Log.Align := alBottom;
  Log.Height := 150;
  Log.ScrollBars := ssAutoVertical;
  Log.ReadOnly := True;
  Log.Font.Name := 'Consolas';
  Log.Font.Size := 9;
  Log.BorderStyle := bsNone;
  Split := TSplitter.Create(Self);
  Split.Parent := Work;
  Split.Align := alBottom;
  Split.Height := 5;

  View := TPhysicsView3D.Create(Self);
  View.Parent := Work;
  View.Align := alClient;
  View.OnPickFace := @ViewPickFace;
  Chart := TPhysicsChart.Create(Self);
  Chart.Parent := Work;
  Chart.Align := alClient;
  Chart.Visible := False;

  Log.Lines.Add('MultiPhysics 0.2: FEM proprio (TET4/TET10) estatico, termico, termomecanico e modal;');
  Log.Lines.Add('sistema eletromecanico, CNC virtual e circuitos com modelos reduzidos (ESTIMATIVA).');
  FUpdating := False;
  RefreshAll;
  ShowStep(0);

  { multiphysics.exe --capture=static|thermal|modal|system arquivo.png:
    carrega a demonstracao, resolve, salva a imagem da janela e sai }
  if Application.HasOption('capture') then
    with TTimer.Create(Self) do
    begin
      Interval := 400;
      OnTimer := @CaptureTick;
      Enabled := True;
    end;

  Ctx := ReadSuiteContext;
  if (Ctx.FileName <> '') and SameText(ExtractFileExt(Ctx.FileName), MPHYS_EXT) and FileExists(Ctx.FileName) then
    LoadProjectFile(Ctx.FileName);
end;

destructor TMultiPhysicsForm.Destroy;
begin
  RuntimeTimer.Enabled := False;
  GraphRuntime.Free;
  Graph.Free;
  Machine.Free;
  Runtime.Free;
  Run.Free;
  P.Free;
  inherited Destroy;
end;

procedure TMultiPhysicsForm.BuildPages;
var
  I: Integer;
  Page: TTabSheet;
  S: TScrollBox;
  T: TLabel;
begin
  for I := 0 to STEP_COUNT - 1 do
  begin
    Page := TTabSheet.Create(Self);
    Page.PageControl := Pages;
    S := TScrollBox.Create(Self);
    S.Parent := Page;
    S.Align := alClient;
    S.BorderStyle := bsNone;
    S.Color := clSuiteCard;
    S.HorzScrollBar.Visible := False;
    T := Lbl(S, Copy(STEP_NAMES[I], 4, MaxInt), 16, 12, 290, 26);
    T.Font.Style := [fsBold];
    T.Font.Color := clSuiteText;
    T.Font.Size := 12;
    case I of
      0: BuildAssemblyPage(S);
      1: BuildMaterialsPage(S);
      2: BuildLoadsPage(S);
      3: BuildMeshPage(S);
      4: BuildSolvePage(S);
      5: BuildResultsPage(S);
      6: BuildSystemPage(S);
      7: BuildMachinePage(S);
      8: BuildCircuitPage(S);
      9: BuildEnvironmentPage(S);
    end;
  end;
end;

procedure TMultiPhysicsForm.BuildAssemblyPage(S: TScrollBox);
var
  I: Integer;
begin
  Lbl(S, 'Nome do projeto', 16, 44, 290, 18);
  EdProjectName := TEdit.Create(Self);
  EdProjectName.Parent := S;
  EdProjectName.SetBounds(16, 63, 290, 26);
  EdProjectName.OnChange := @ProjectNameChange;
  Lbl(S, 'NOVA PECA', 16, 100, 290, 18).Font.Style := [fsBold];
  CbPrimKind := Combo(S, 'Forma', 16, 120, 180);
  CbPrimKind.Items.CommaText := '"Caixa","Cilindro","Tubo","Perfil L"';
  CbPrimKind.ItemIndex := 0;
  CbPrimKind.OnChange := @PrimKindChange;
  CbAxis := Combo(S, 'Eixo', 206, 120, 100);
  CbAxis.Items.CommaText := 'x,y,z';
  CbAxis.ItemIndex := 2;
  for I := 0 to 3 do
  begin
    EdDim[I] := Num(S, '', 16 + (I mod 2) * 150, 186 + (I div 2) * 50, 140, 0.01, 100000, 10, 2);
    LbDim[I] := Lbl(S, '', 16 + (I mod 2) * 150, 167 + (I div 2) * 50, 140, 18);
  end;
  Lbl(S, 'ID da peca', 16, 270, 140, 18);
  EdPartID := TEdit.Create(Self);
  EdPartID.Parent := S;
  EdPartID.SetBounds(16, 289, 140, 26);
  Btn(S, 'Adicionar peca', 166, 286, 140, 32, sikNew, @AddPartClick);
  Lbl(S, 'PECAS', 16, 330, 290, 18).Font.Style := [fsBold];
  LbParts := TListBox.Create(Self);
  LbParts.Parent := S;
  LbParts.SetBounds(16, 350, 290, 110);
  LbParts.OnClick := @PartListClick;
  for I := 0 to 2 do
  begin
    EdPos[I] := Num(S, 'Posicao ' + Chr(Ord('X') + I) + ' (mm)', 16 + I * 98, 468, 90, -1e6, 1e6, 0, 2);
    EdRot[I] := Num(S, 'Rot. ' + Chr(Ord('X') + I) + ' (graus)', 16 + I * 98, 518, 90, -360, 360, 0, 1);
  end;
  CkSuppressed := TCheckBox.Create(Self);
  CkSuppressed.Parent := S;
  CkSuppressed.SetBounds(16, 572, 290, 22);
  CkSuppressed.Caption := 'Suprimida (fora da analise)';
  Btn(S, 'Aplicar', 16, 600, 140, 32, sikSave, @ApplyPartClick);
  Btn(S, 'Excluir peca', 166, 600, 140, 32, sikTrash, @DeletePartClick);
  Lbl(S, 'Pecas da montagem do MultiAssembly entram por "Importar" (em breve nesta etapa). ' +
    'Pecas sao malhadas separadamente: cada uma precisa da sua fixacao ate a amarracao de contatos (MP-3.3).',
    16, 642, 290, 70);
  UpdatePrimLabels;
end;

procedure TMultiPhysicsForm.BuildMaterialsPage(S: TScrollBox);
var
  I: Integer;
begin
  Lbl(S, 'Peca', 16, 44, 290, 18);
  LbMatParts := TListBox.Create(Self);
  LbMatParts.Parent := S;
  LbMatParts.SetBounds(16, 63, 290, 110);
  LbMatParts.OnClick := @MatPartListClick;
  CbMaterial := Combo(S, 'Material da biblioteca', 16, 182, 290);
  for I := 0 to MaterialCount - 1 do CbMaterial.Items.Add(MaterialByIndex(I).Name);
  CbMaterial.OnChange := @MaterialChange;
  EdE := Num(S, 'E (GPa)', 16, 234, 140, 0.0001, 2000, 200, 3);
  EdNu := Num(S, 'Poisson', 166, 234, 140, 0, 0.4999, 0.3, 3);
  EdRho := Num(S, 'Densidade (kg/m3)', 16, 284, 140, 0.001, 100000, 7850, 1);
  EdK := Num(S, 'Condutividade (W/m K)', 166, 284, 140, 0.0001, 10000, 50, 3);
  EdAlpha := Num(S, 'Dilatacao (1e-6/K)', 16, 334, 140, 0, 1000, 12, 2);
  EdYield := Num(S, 'Escoamento (MPa)', 166, 334, 140, 0, 100000, 250, 1);
  Btn(S, 'Aplicar a peca', 16, 392, 140, 32, sikSave, @ApplyMaterialClick);
  Btn(S, 'Aplicar a todas', 166, 392, 140, 32, sikCopy, @ApplyMaterialAllClick);
  Lbl(S, 'Os valores podem ser ajustados depois de escolher o material; o projeto guarda as propriedades da peca.',
    16, 436, 290, 50);
end;

procedure TMultiPhysicsForm.BuildLoadsPage(S: TScrollBox);
var
  I: Integer;
begin
  LbBCs := TListBox.Create(Self);
  LbBCs.Parent := S;
  LbBCs.SetBounds(16, 44, 290, 120);
  LbBCs.OnClick := @BCListClick;
  Lbl(S, 'Nome', 16, 172, 290, 18);
  EdBCName := TEdit.Create(Self);
  EdBCName.Parent := S;
  EdBCName.SetBounds(16, 191, 290, 26);
  CbBCKind := Combo(S, 'Tipo', 16, 222, 290);
  for I := 0 to High(BC_KINDS) do CbBCKind.Items.Add(BoundaryKindName(BC_KINDS[I]));
  CbBCKind.ItemIndex := 0;
  CbBCKind.OnChange := @BCKindChange;
  CbBCPart := Combo(S, 'Peca', 16, 272, 140);
  CbBCPart.OnChange := @BCPartChange;
  CbBCFace := Combo(S, 'Face (ou clique na vista)', 166, 272, 140);
  LbVecUnit := Lbl(S, 'Vetor', 16, 322, 290, 18);
  for I := 0 to 2 do
  begin
    EdVec[I] := Num(S, '', 16 + I * 98, 322, 90, -1e9, 1e9, 0, 3);
    Lbl(S, Chr(Ord('X') + I), 16 + I * 98 + 92, 345, 10, 18);
  end;
  LbVal1 := Lbl(S, 'Valor', 16, 372, 140, 18);
  EdVal1 := Num(S, '', 16, 372, 140, -1e12, 1e12, 0, 3);
  LbVal2 := Lbl(S, 'Valor 2', 166, 372, 140, 18);
  EdVal2 := Num(S, '', 166, 372, 140, -1e12, 1e12, 0, 3);
  Lbl(S, 'Graus fixos', 16, 422, 290, 18);
  for I := 0 to 2 do
  begin
    CkDof[I] := TCheckBox.Create(Self);
    CkDof[I].Parent := S;
    CkDof[I].SetBounds(16 + I * 70, 440, 60, 22);
    CkDof[I].Caption := Chr(Ord('X') + I);
    CkDof[I].Checked := True;
  end;
  Btn(S, 'Incluir', 16, 472, 92, 32, sikNew, @AddBCClick);
  Btn(S, 'Atualizar', 115, 472, 92, 32, sikSave, @UpdateBCClick);
  Btn(S, 'Excluir', 214, 472, 92, 32, sikTrash, @DeleteBCClick);
  Lbl(S, 'Forca: total em N, repartida pela area da face. Pressao em MPa (positiva empurra para dentro). ' +
    'Deslocamento em mm. Temperatura em C, fluxo em W/m2, conveccao h em W/m2K e ambiente em C, potencia em W na peca inteira.',
    16, 512, 290, 96);
  UpdateBCUnits;
end;

procedure TMultiPhysicsForm.BuildMeshPage(S: TScrollBox);
begin
  EdMeshSize := Num(S, 'Tamanho dos elementos (mm)', 16, 44, 140, 0.05, 1000, 5, 2);
  CkQuadratic := TCheckBox.Create(Self);
  CkQuadratic.Parent := S;
  CkQuadratic.SetBounds(16, 100, 290, 22);
  CkQuadratic.Caption := 'Elementos quadraticos TET10 (recomendado)';
  CkQuadratic.Checked := True;
  CkConvergence := TCheckBox.Create(Self);
  CkConvergence.Parent := S;
  CkConvergence.SetBounds(16, 126, 290, 22);
  CkConvergence.Caption := 'Estudo de convergencia (para ENGENHARIA)';
  CkConvergence.Checked := True;
  Btn(S, 'Gerar malha', 16, 160, 140, 32, sikPolygon, @MeshClick);
  LbMeshInfo := Lbl(S, '', 16, 204, 290, 140);
  LbMeshInfo.Font.Color := clSuiteText;
  Lbl(S, 'Cada forma vira uma secao triangulada extrudada em camadas. TET4 e rigido demais em flexao; ' +
    'use TET10 para estrutural e modal. A convergencia resolve de novo com elementos 1,5x maiores e compara.',
    16, 350, 290, 90);
end;

procedure TMultiPhysicsForm.BuildSolvePage(S: TScrollBox);
var
  B: TSuiteButton;
begin
  CbAnalysis := Combo(S, 'Analise', 16, 44, 290);
  CbAnalysis.Items.CommaText := '"Estatica linear","Termica permanente","Termomecanica","Modal (frequencias naturais)"';
  CbAnalysis.ItemIndex := 0;
  Lbl(S, 'Modos (modal)', 16, 96, 140, 18);
  EdModes := TSpinEdit.Create(Self);
  EdModes.Parent := S;
  EdModes.SetBounds(16, 115, 140, 26);
  EdModes.MinValue := 1; EdModes.MaxValue := 30; EdModes.Value := 6;
  B := Btn(S, 'Resolver', 16, 156, 290, 36, sikPlay, @SolveClick);
  B.SetLook(sbsSolid, clSuitePrimary, sikPlay);
  Lbl(S, 'Solver: FEM proprio (Cholesky em perfil ou gradiente conjugado). A comparacao com CalculiX ' +
    '(ccx) entra na Fase 5 do plano. Resultado sem convergencia verificada sai como ESTIMATIVA.',
    16, 204, 290, 90);
end;

procedure TMultiPhysicsForm.BuildResultsPage(S: TScrollBox);
begin
  CbField := Combo(S, 'Campo', 16, 44, 290);
  CbField.OnChange := @FieldChange;
  CkDeformed := TCheckBox.Create(Self);
  CkDeformed.Parent := S;
  CkDeformed.SetBounds(16, 96, 140, 22);
  CkDeformed.Caption := 'Deformada';
  CkDeformed.Checked := True;
  CkDeformed.OnClick := @FieldChange;
  CkAnimate := TCheckBox.Create(Self);
  CkAnimate.Parent := S;
  CkAnimate.SetBounds(166, 96, 140, 22);
  CkAnimate.Caption := 'Animar';
  CkAnimate.OnClick := @FieldChange;
  EdScale := Num(S, 'Escala da deformada (0 = automatica)', 16, 122, 140, 0, 1e9, 0, 1);
  EdScale.OnChange := @FieldChange;
  LbSummary := Lbl(S, 'Resolva uma analise para ver os resultados.', 16, 180, 290, 260);
  LbSummary.Font.Color := clSuiteText;
  Btn(S, 'Exportar CSV', 16, 450, 140, 32, sikExport, @ExportCSVClick);
  Btn(S, 'Relatorio HTML', 166, 450, 140, 32, sikFile, @ReportClick);
end;

procedure TMultiPhysicsForm.BuildSystemPage(S: TScrollBox);
begin
  Btn(S, 'Carregar maquina demonstracao', 16, 44, 290, 32, sikWand, @LoadMachineClick);
  Btn(S, 'Ligar', 16, 84, 92, 32, sikPlay, @RuntimeStartClick);
  Btn(S, 'Pausar', 115, 84, 92, 32, sikPause, @RuntimePauseClick);
  Btn(S, 'Desligar', 214, 84, 92, 32, sikStop, @RuntimeStopClick);
  Btn(S, 'Exportar CSV', 16, 124, 140, 32, sikExport, @ChartCSVClick);
  LbRuntime := Lbl(S, '', 16, 168, 290, 120);
  LbRuntime.Font.Color := clSuiteText;
  Lbl(S, 'Fonte -> driver PWM -> motor DC -> carga -> sensor -> controlador, em passos de tempo. ' +
    'Modelo reduzido e deterministico: ESTIMATIVA (ver docs/RUNTIME.md).', 16, 296, 290, 80);
end;

procedure TMultiPhysicsForm.BuildMachinePage(S: TScrollBox);
var
  I: Integer;
begin
  Btn(S, 'Criar CNC XYZ + spindle', 16, 44, 290, 32, sikCNC, @MachineCreateClick);
  for I := 0 to 2 do
    EdTarget[I] := Num(S, 'Alvo ' + Chr(Ord('X') + I) + ' (mm)', 16 + I * 98, 86, 90, -1000, 10000, 0, 2);
  EdTarget[0].Value := 100; EdTarget[1].Value := 50; EdTarget[2].Value := 20;
  EdFeed := Num(S, 'Velocidade (mm/s)', 16, 136, 140, 0.1, 1000, 40, 1);
  Btn(S, 'Executar movimento', 166, 152, 140, 32, sikPlay, @MachineMoveClick);
  CbFaultAxis := Combo(S, 'Eixo', 16, 196, 90);
  CbFaultAxis.Items.CommaText := 'X,Y,Z';
  CbFaultAxis.ItemIndex := 0;
  CbFault := Combo(S, 'Falha', 116, 196, 190);
  CbFault.Items.CommaText := '"Circuito aberto","Curto-circuito","Eixo travado","Sensor falhou","Fim de curso preso","Corrosao","Oxidacao","Sobrecorrente"';
  CbFault.ItemIndex := 2;
  Btn(S, 'Injetar falha', 16, 248, 140, 32, sikFlame, @MachineFaultClick);
  LbMachine := Lbl(S, '', 16, 290, 290, 140);
  LbMachine.Font.Color := clSuiteText;
end;

procedure TMultiPhysicsForm.BuildCircuitPage(S: TScrollBox);
begin
  Lbl(S, 'Netlist (estilo SPICE): R, C, L, V (DC ou SIN), I, D, M (NMOS), .tran passo fim, .probe nos', 16, 44, 290, 36);
  MmNetlist := TMemo.Create(Self);
  MmNetlist.Parent := S;
  MmNetlist.SetBounds(16, 84, 290, 260);
  MmNetlist.Font.Name := 'Consolas';
  MmNetlist.ScrollBars := ssAutoBoth;
  MmNetlist.Text := DEMO_NETLIST;
  Btn(S, 'Resolver circuito', 16, 352, 290, 32, sikPlay, @CircuitSolveClick);
  Lbl(S, 'MNA com Newton-Raphson (diodo, NMOS) e transitorio trapezoidal. O transitorio parte de capacitores descarregados.',
    16, 394, 290, 60);
end;

procedure TMultiPhysicsForm.BuildEnvironmentPage(S: TScrollBox);
begin
  CbEnv := Combo(S, 'Ambiente', 16, 44, 290);
  CbEnv.Items.CommaText := 'Ar,Agua,Vacuo';
  CbEnv.ItemIndex := 1;
  CbEnv.OnChange := @EnvChange;
  EdFlow := Num(S, 'Velocidade do fluido (m/s)', 16, 96, 140, -1e4, 1e4, 2, 3);
  EdArea := Num(S, 'Area de referencia (m2)', 166, 96, 140, 0, 1e6, 1, 4);
  EdVolume := Num(S, 'Volume deslocado (m3)', 16, 146, 140, 0, 1e6, 0.1, 4);
  EdCd := Num(S, 'Coeficiente de arrasto', 166, 146, 140, 0, 10, 0.8, 3);
  EdMass := Num(S, 'Massa do corpo (kg)', 16, 196, 140, 0, 1e9, 100, 2);
  Btn(S, 'Estimar arrasto e empuxo', 16, 252, 290, 32, sikPulse, @EstimateClick);
  Btn(S, 'Teste de flutuacao', 16, 292, 290, 32, sikTarget, @FloatTestClick);
  Lbl(S, 'Formulas reduzidas (pressao dinamica, arrasto Cd, empuxo hidrostatico): ESTIMATIVA, nao e CFD. ' +
    'Acima de Mach 0,3 a hipotese incompressivel nao vale.', 16, 336, 290, 70);
end;

{ ---------------- utilidades ---------------- }

procedure TMultiPhysicsForm.SetStatus(const S: string);
begin
  StatusLabel.Caption := S;
end;

procedure TMultiPhysicsForm.ShowStep(I: Integer);
var
  K: Integer;
begin
  FStep := I;
  for K := 0 to STEP_COUNT - 1 do
    if K = I then Nav[K].SetLook(sbsSolid, clSuitePrimary, StepIcon(K))
    else Nav[K].SetLook(sbsSoft, clSuitePrimary, StepIcon(K));
  Pages.ActivePageIndex := I;
  Chart.Visible := I in [6, 7, 8];
  View.Visible := not Chart.Visible;
  ViewBar.Visible := View.Visible;
  if I = 2 then ShowMarks;
  if I = 5 then ShowResultField;
end;

procedure TMultiPhysicsForm.NavClick(Sender: TObject);
begin
  ShowStep(TComponent(Sender).Tag);
end;

function TMultiPhysicsForm.SelectedPart: TPhysicsPart;
begin
  Result := nil;
  if (LbParts.ItemIndex >= 0) and (LbParts.ItemIndex < P.PartCount) then Result := P.Part(LbParts.ItemIndex);
end;

procedure TMultiPhysicsForm.RefreshAll;
begin
  FUpdating := True;
  try
    EdProjectName.Text := P.Name;
    EdMeshSize.Value := MToMm(P.Settings.MeshSize);
    CkQuadratic.Checked := P.Settings.Quadratic;
    CkConvergence.Checked := P.Settings.CheckConvergence;
    EdModes.Value := Max(1, P.Settings.Modes);
  finally
    FUpdating := False;
  end;
  RefreshPartLists;
  RefreshBCList;
  RefreshTree;
end;

procedure TMultiPhysicsForm.RefreshTree;
var
  R, N: TTreeNode;
  I: Integer;
  B: TBoundaryCondition;
begin
  Tree.Items.BeginUpdate;
  try
    Tree.Items.Clear;
    R := Tree.Items.Add(nil, P.Name);
    N := Tree.Items.AddChild(R, Format('Pecas (%d)', [P.PartCount]));
    for I := 0 to P.PartCount - 1 do
      Tree.Items.AddChild(N, P.Part(I).ID + ' - ' + P.Part(I).Material.Name);
    N := Tree.Items.AddChild(R, Format('Condicoes (%d)', [P.BCCount]));
    for I := 0 to P.BCCount - 1 do
    begin
      B := P.BC(I);
      Tree.Items.AddChild(N, B.Name + ' (' + BoundaryKindName(B.Kind) + ')');
    end;
    N := Tree.Items.AddChild(R, Format('Contatos (%d)', [P.ContactCount]));
    for I := 0 to P.ContactCount - 1 do Tree.Items.AddChild(N, P.Contact(I).Name);
    if HasResult then
      Tree.Items.AddChild(R, 'Resultado: ' + AnalysisKindName(Run.Kind) + ' - ' + FidelityName(Run.Fidelity));
    R.Expand(True);
  finally
    Tree.Items.EndUpdate;
  end;
  if P.FileName <> '' then InfoLabel.Caption := P.FileName + IfThen(P.Modified, ' (alterado)', '')
  else InfoLabel.Caption := IfThen(P.Modified, 'Projeto nao salvo (alterado)', 'Projeto nao salvo');
end;

procedure TMultiPhysicsForm.RefreshPartLists;
var
  I, Sel, MSel: Integer;
  Txt: string;
begin
  Sel := LbParts.ItemIndex; MSel := LbMatParts.ItemIndex;
  LbParts.Items.BeginUpdate; LbMatParts.Items.BeginUpdate;
  try
    LbParts.Items.Clear; LbMatParts.Items.Clear;
    CbBCPart.Items.Clear;
    for I := 0 to P.PartCount - 1 do
    begin
      Txt := Format('%s  (%s, %.3f kg)', [P.Part(I).ID, P.Part(I).Material.Name, P.Part(I).Mass]);
      if P.Part(I).Suppressed then Txt := Txt + ' [suprimida]';
      LbParts.Items.Add(Txt);
      LbMatParts.Items.Add(P.Part(I).ID + ' - ' + P.Part(I).Material.Name);
      CbBCPart.Items.Add(P.Part(I).ID);
    end;
  finally
    LbParts.Items.EndUpdate; LbMatParts.Items.EndUpdate;
  end;
  if (Sel >= 0) and (Sel < LbParts.Count) then LbParts.ItemIndex := Sel;
  if (MSel >= 0) and (MSel < LbMatParts.Count) then LbMatParts.ItemIndex := MSel;
  if (CbBCPart.ItemIndex < 0) and (CbBCPart.Items.Count > 0) then CbBCPart.ItemIndex := 0;
  RefreshFaceCombo;
  if EdPartID.Text = '' then EdPartID.Text := 'PECA' + IntToStr(P.PartCount + 1);
end;

procedure TMultiPhysicsForm.RefreshBCList;
var
  I, Sel: Integer;
  B: TBoundaryCondition;
begin
  Sel := LbBCs.ItemIndex;
  LbBCs.Items.BeginUpdate;
  try
    LbBCs.Items.Clear;
    for I := 0 to P.BCCount - 1 do
    begin
      B := P.BC(I);
      LbBCs.Items.Add(Format('%s: %s em %s/%s', [B.Name, BoundaryKindName(B.Kind), B.TargetID,
        IfThen(B.TargetFace = '', '(todas)', B.TargetFace)]));
    end;
  finally
    LbBCs.Items.EndUpdate;
  end;
  if (Sel >= 0) and (Sel < LbBCs.Count) then LbBCs.ItemIndex := Sel;
end;

procedure TMultiPhysicsForm.RefreshFaceCombo;
var
  Part: TPhysicsPart;
  I, J: Integer;
  Names: TStringList;
  Seen: TStringList;
begin
  CbBCFace.Items.Clear;
  CbBCFace.Items.Add('(todas as faces)');
  if (CbBCPart.ItemIndex >= 0) and (CbBCPart.ItemIndex < P.PartCount) then
  begin
    Part := P.Part(CbBCPart.ItemIndex);
    Names := TStringList.Create; Seen := TStringList.Create;
    try
      for I := 0 to High(Part.Primitives) do
      begin
        Names.CommaText := PrimFaceNames(Part.Primitives[I]);
        for J := 0 to Names.Count - 1 do
        begin
          { nome curto (vale em todas as primitivas) e nome completo }
          if Seen.IndexOf(Names[J]) < 0 then Seen.Add(Names[J]);
          if Length(Part.Primitives) > 1 then
            CbBCFace.Items.Add(Part.ID + '/' + Part.Primitives[I].ID + '/' + Names[J]);
        end;
      end;
      for J := 0 to Seen.Count - 1 do CbBCFace.Items.Insert(1 + J, Seen[J]);
    finally
      Seen.Free; Names.Free;
    end;
  end;
  CbBCFace.ItemIndex := 0;
end;

procedure TMultiPhysicsForm.UpdatePrimLabels;
const
  CAP: array[0..3, 0..3] of string = (
    ('Comprimento X (mm)', 'Largura Y (mm)', 'Altura Z (mm)', ''),
    ('Raio (mm)', 'Altura (mm)', '', ''),
    ('Raio externo (mm)', 'Raio interno (mm)', 'Altura (mm)', ''),
    ('Aba U (mm)', 'Aba V (mm)', 'Espessura (mm)', 'Comprimento (mm)'));
  DEF: array[0..3, 0..3] of Double = ((200, 10, 20, 0), (10, 100, 0, 0), (20, 16, 100, 0), (40, 30, 5, 200));
var
  K, I: Integer;
begin
  K := Max(0, CbPrimKind.ItemIndex);
  for I := 0 to 3 do
  begin
    LbDim[I].Caption := CAP[K, I];
    EdDim[I].Visible := CAP[K, I] <> '';
    if EdDim[I].Visible then EdDim[I].Value := DEF[K, I];
  end;
  CbAxis.Enabled := K > 0;
end;

procedure TMultiPhysicsForm.UpdateBCUnits;
var
  K: TBoundaryKind;
  I: Integer;
begin
  K := BC_KINDS[Max(0, CbBCKind.ItemIndex)];
  for I := 0 to 2 do EdVec[I].Enabled := K in [bkDisplacement, bkForce, bkGravity];
  for I := 0 to 2 do CkDof[I].Enabled := K in [bkFixed, bkDisplacement];
  EdVal1.Enabled := K in [bkPressure, bkTemperature, bkHeatFlux, bkConvection, bkHeatPower];
  EdVal2.Enabled := K = bkConvection;
  CbBCFace.Enabled := not (K in [bkGravity, bkHeatPower]);
  CbBCPart.Enabled := K <> bkGravity;
  case K of
    bkDisplacement: LbVecUnit.Caption := 'Deslocamento (mm)';
    bkForce: LbVecUnit.Caption := 'Forca total (N)';
    bkGravity: LbVecUnit.Caption := 'Aceleracao da gravidade (m/s2)';
    else LbVecUnit.Caption := 'Vetor (nao usado)';
  end;
  case K of
    bkPressure: LbVal1.Caption := 'Pressao (MPa)';
    bkTemperature: LbVal1.Caption := 'Temperatura (C)';
    bkHeatFlux: LbVal1.Caption := 'Fluxo (W/m2)';
    bkConvection: LbVal1.Caption := 'h (W/m2 K)';
    bkHeatPower: LbVal1.Caption := 'Potencia (W)';
    else LbVal1.Caption := 'Valor (nao usado)';
  end;
  if K = bkConvection then LbVal2.Caption := 'T ambiente (C)' else LbVal2.Caption := 'Valor 2 (nao usado)';
end;

function TMultiPhysicsForm.BCFromUI(out B: TBoundaryCondition): Boolean;
var
  K: TBoundaryKind;
  Face: string;
begin
  Result := False;
  K := BC_KINDS[Max(0, CbBCKind.ItemIndex)];
  if (K <> bkGravity) and (CbBCPart.ItemIndex < 0) then
  begin
    SetStatus('Escolha a peca da condicao.');
    Exit;
  end;
  Face := '';
  if (CbBCFace.ItemIndex > 0) and CbBCFace.Enabled then Face := CbBCFace.Text;
  B := NewBC(Trim(EdBCName.Text), '', Face, K);
  if K <> bkGravity then B.TargetID := CbBCPart.Text;
  if B.Name = '' then B.Name := BoundaryKindName(K) + ' ' + IntToStr(P.BCCount + 1);
  case K of
    bkDisplacement: begin B.X := MmToM(EdVec[0].Value); B.Y := MmToM(EdVec[1].Value); B.Z := MmToM(EdVec[2].Value); end;
    bkForce, bkGravity: begin B.X := EdVec[0].Value; B.Y := EdVec[1].Value; B.Z := EdVec[2].Value; end;
  end;
  case K of
    bkPressure: B.Value := MPaToPa(EdVal1.Value);
    bkTemperature, bkHeatFlux, bkConvection, bkHeatPower: B.Value := EdVal1.Value;
  end;
  if K = bkConvection then B.Value2 := EdVal2.Value;
  if K in [bkFixed, bkDisplacement] then
  begin
    B.DofMask := Ord(CkDof[0].Checked) or (Ord(CkDof[1].Checked) shl 1) or (Ord(CkDof[2].Checked) shl 2);
    if B.DofMask = 7 then B.DofMask := 0;
    if (B.DofMask = 0) and not (CkDof[0].Checked or CkDof[1].Checked or CkDof[2].Checked) then
    begin
      SetStatus('Marque ao menos um grau fixo.');
      Exit;
    end;
  end;
  Result := True;
end;

procedure TMultiPhysicsForm.ShowMarks;
var
  I, J: Integer;
  B: TBoundaryCondition;
  Clr: TColor;
  Arrow: TVector3;
  FaceName, Prefix: string;
  Hit: Boolean;
begin
  View.ClearMarks;
  if View = nil then Exit;
  for I := 0 to P.BCCount - 1 do
  begin
    B := P.BC(I);
    case B.Kind of
      bkFixed, bkDisplacement: Clr := SuiteRGB(80, 120, 220);
      bkForce, bkPressure: Clr := SuiteRGB(230, 120, 90);
      bkTemperature, bkHeatFlux: Clr := SuiteRGB(240, 170, 60);
      bkConvection: Clr := SuiteRGB(90, 190, 200);
      else Continue;
    end;
    if B.Kind = bkForce then Arrow := V3(B.X, B.Y, B.Z) else Arrow := V3(0, 0, 0);
    Prefix := B.TargetID + '/';
    for J := 0 to Run.Mesh.FaceNames.Count - 1 do
    begin
      FaceName := Run.Mesh.FaceNames[J];
      if not SameText(Copy(FaceName, 1, Length(Prefix)), Prefix) then Continue;
      if B.TargetFace = '' then Hit := True
      else if Pos('/', B.TargetFace) > 0 then Hit := SameText(FaceName, B.TargetFace)
      else Hit := SameText(Copy(FaceName, LastDelimiter('/', FaceName) + 1, MaxInt), B.TargetFace);
      if Hit then View.AddMark(J, Clr, Arrow);
    end;
  end;
end;

procedure TMultiPhysicsForm.ApplySettingsFromUI;
begin
  P.Settings.MeshSize := MmToM(EdMeshSize.Value);
  P.Settings.Quadratic := CkQuadratic.Checked;
  P.Settings.CheckConvergence := CkConvergence.Checked;
  P.Settings.Modes := EdModes.Value;
  case CbAnalysis.ItemIndex of
    1: P.Settings.Physics := [pkThermal];
    2: P.Settings.Physics := [pkStructural, pkThermal];
    3: P.Settings.Physics := [pkModal];
    else P.Settings.Physics := [pkStructural];
  end;
end;

{ ---------------- arquivo ---------------- }

procedure TMultiPhysicsForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  CanClose := True;
  if P.Modified then
    CanClose := MessageDlg('MultiPhysics', 'O projeto foi alterado e nao foi salvo. Sair mesmo assim?',
      mtConfirmation, [mbYes, mbNo], 0) = mrYes;
end;

procedure TMultiPhysicsForm.CaptureTick(Sender: TObject);
var
  Mode, FN: string;
  Bmp: TBitmap;
  Png: TPortableNetworkGraphic;
  I: Integer;
begin
  TTimer(Sender).Enabled := False;
  Mode := LowerCase(Application.GetOptionValue('capture'));
  FN := ParamStr(ParamCount);
  DemoClick(nil);
  if Mode = 'system' then
  begin
    ShowStep(6);
    LoadMachineClick(nil);
    GraphRuntime.Start;
    for I := 1 to 300 do RuntimeTick(nil);
  end
  else if Mode = 'circuit' then
  begin
    ShowStep(8);
    CircuitSolveClick(nil);
  end
  else if Mode = 'loads' then
    ShowStep(2)
  else
  begin
    if Mode = 'thermal' then CbAnalysis.ItemIndex := 1
    else if Mode = 'thermomech' then CbAnalysis.ItemIndex := 2
    else if Mode = 'modal' then CbAnalysis.ItemIndex := 3
    else CbAnalysis.ItemIndex := 0;
    SolveClick(nil);
    if Mode = 'modal' then CkAnimate.Checked := False;
    if Mode = 'static' then begin CbField.ItemIndex := 1; ShowResultField; end;
  end;
  Application.ProcessMessages;
  Repaint;
  Application.ProcessMessages;
  Bmp := GetFormImage;
  Png := TPortableNetworkGraphic.Create;
  try
    Png.Assign(Bmp);
    Png.SaveToFile(FN);
  finally
    Png.Free;
    Bmp.Free;
  end;
  P.Modified := False;
  Application.Terminate;
end;

procedure TMultiPhysicsForm.SetBadge(const ACaption: string; AColor: TColor);
begin
  Badge.Caption := ACaption;
  Badge.DotColor := AColor;
  HeaderResize(nil);
end;

procedure TMultiPhysicsForm.HeaderResize(Sender: TObject);
begin
  Badge.Left := Max(400, Header.ClientWidth - Badge.Width - 24);
end;

procedure TMultiPhysicsForm.NewClick(Sender: TObject);
begin
  if P.Modified and (MessageDlg('Novo projeto', 'Descartar as alteracoes do projeto atual?',
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes) then Exit;
  P.Clear;
  Run.Mesh.Clear;
  HasResult := False;
  View.SetMesh(nil);
  SetBadge('Sem resultado', clSuiteFaint);
  EdPartID.Text := '';
  RefreshAll;
  SetStatus('Projeto novo.');
  ShowStep(0);
end;

procedure TMultiPhysicsForm.LoadProjectFile(const FN: string);
begin
  try
    P.LoadFromFile(FN);
    HasResult := False;
    Run.Mesh.Clear;
    View.SetMesh(nil);
    SetBadge('Sem resultado', clSuiteFaint);
    RefreshAll;
    SetStatus('Projeto aberto: ' + ExtractFileName(FN));
    Log.Lines.Add('Aberto ' + FN);
    MeshClick(nil);
  except
    on E: Exception do MessageDlg('Nao foi possivel abrir', E.Message, mtError, [mbOK], 0);
  end;
end;

procedure TMultiPhysicsForm.OpenClick(Sender: TObject);
var
  D: TOpenDialog;
begin
  D := TOpenDialog.Create(Self);
  try
    D.Filter := 'Projeto MultiPhysics (*.mphys)|*.mphys|Todos os arquivos|*.*';
    if D.Execute then LoadProjectFile(D.FileName);
  finally
    D.Free;
  end;
end;

procedure TMultiPhysicsForm.SaveClick(Sender: TObject);
var
  D: TSaveDialog;
  FN: string;
begin
  ApplySettingsFromUI;
  FN := P.FileName;
  if FN = '' then
  begin
    D := TSaveDialog.Create(Self);
    try
      D.Filter := 'Projeto MultiPhysics (*.mphys)|*.mphys';
      D.DefaultExt := 'mphys';
      D.FileName := P.Name + MPHYS_EXT;
      D.Options := D.Options + [ofOverwritePrompt];
      if not D.Execute then Exit;
      FN := D.FileName;
    finally
      D.Free;
    end;
  end;
  try
    P.SaveToFile(FN);
    RefreshTree;
    SetStatus('Salvo em ' + FN);
  except
    on E: Exception do MessageDlg('Nao foi possivel salvar', E.Message, mtError, [mbOK], 0);
  end;
end;

{ demonstracao: suporte em L engastado com carga na ponta }
procedure TMultiPhysicsForm.DemoClick(Sender: TObject);
var
  Part: TPhysicsPart;
  B: TBoundaryCondition;
begin
  if P.Modified and (MessageDlg('Demonstracao', 'Descartar as alteracoes do projeto atual?',
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes) then Exit;
  P.Clear;
  P.Name := 'Demo - viga em balanco';
  Part := TPhysicsPart.Create;
  Part.ID := 'VIGA'; Part.Name := 'Viga de aco 200 x 10 x 20 mm';
  Part.Material := MaterialByIndex(FindMaterial('Aco carbono'));
  Part.AddPrimitive(BoxPrim('b', V3(0, 0, 0), V3(0.2, 0.01, 0.02)));
  P.AddPart(Part);
  P.AddBC(NewBC('Engaste', 'VIGA', 'xmin', bkFixed));
  B := NewBC('Carga na ponta', 'VIGA', 'xmax', bkForce);
  B.Z := -100;
  P.AddBC(B);
  B := NewBC('Base quente', 'VIGA', 'xmin', bkTemperature);
  B.Value := 80;
  P.AddBC(B);
  B := NewBC('Ar ambiente', 'VIGA', '', bkConvection);
  B.Value := 15; B.Value2 := 20;
  P.AddBC(B);
  P.Settings.MeshSize := 0.005;
  P.Modified := False;
  HasResult := False;
  RefreshAll;
  MeshClick(nil);
  ShowStep(2);
  SetStatus('Demonstracao: viga engastada, 100 N na ponta. Va em Resolver.');
end;

procedure TMultiPhysicsForm.ProjectNameChange(Sender: TObject);
begin
  if FUpdating then Exit;
  P.Name := EdProjectName.Text;
  P.Modified := True;
  RefreshTree;
end;

{ ---------------- 1 montagem ---------------- }

procedure TMultiPhysicsForm.PrimKindChange(Sender: TObject);
begin
  UpdatePrimLabels;
end;

procedure TMultiPhysicsForm.AddPartClick(Sender: TObject);
var
  Part: TPhysicsPart;
  ID: string;
  Ax: Char;
  D: array[0..3] of Double;
  I: Integer;
begin
  ID := UpperCase(Trim(EdPartID.Text));
  if (ID = '') or (Pos('/', ID) > 0) then begin SetStatus('Informe um ID sem barra.'); Exit; end;
  if P.FindPart(ID) >= 0 then begin SetStatus('Ja existe uma peca ' + ID + '.'); Exit; end;
  for I := 0 to 3 do D[I] := MmToM(EdDim[I].Value);
  Ax := CbAxis.Text[1];
  Part := TPhysicsPart.Create;
  Part.ID := ID; Part.Name := ID;
  Part.Material := MaterialByIndex(FindMaterial('Aco carbono'));
  case CbPrimKind.ItemIndex of
    1: Part.AddPrimitive(CylPrim('c', Ax, V3(0, 0, 0), D[0], D[1]));
    2:
      begin
        if D[1] >= D[0] then begin Part.Free; SetStatus('Raio interno deve ser menor que o externo.'); Exit; end;
        Part.AddPrimitive(CylPrim('t', Ax, V3(0, 0, 0), D[0], D[2], D[1]));
      end;
    3:
      begin
        if (D[2] >= D[0]) or (D[2] >= D[1]) then begin Part.Free; SetStatus('Espessura deve ser menor que as abas.'); Exit; end;
        Part.AddPrimitive(PrismPrim('l', Ax, V3(0, 0, 0), D[3],
          [V2(0, 0), V2(D[0], 0), V2(D[0], D[2]), V2(D[2], D[2]), V2(D[2], D[1]), V2(0, D[1])]));
      end;
    else Part.AddPrimitive(BoxPrim('b', V3(0, 0, 0), V3(D[0], D[1], D[2])));
  end;
  P.AddPart(Part);
  EdPartID.Text := '';
  RefreshPartLists;
  LbParts.ItemIndex := P.PartCount - 1;
  PartListClick(nil);
  RefreshTree;
  MeshClick(nil);
  SetStatus('Peca ' + ID + ' adicionada (aco carbono). Ajuste o material na etapa 2.');
end;

procedure TMultiPhysicsForm.PartListClick(Sender: TObject);
var
  Part: TPhysicsPart;
begin
  Part := SelectedPart;
  if Part = nil then Exit;
  EdPos[0].Value := MToMm(Part.Position.X);
  EdPos[1].Value := MToMm(Part.Position.Y);
  EdPos[2].Value := MToMm(Part.Position.Z);
  EdRot[0].Value := Part.RotX; EdRot[1].Value := Part.RotY; EdRot[2].Value := Part.RotZ;
  CkSuppressed.Checked := Part.Suppressed;
end;

procedure TMultiPhysicsForm.ApplyPartClick(Sender: TObject);
var
  Part: TPhysicsPart;
begin
  Part := SelectedPart;
  if Part = nil then begin SetStatus('Selecione uma peca na lista.'); Exit; end;
  Part.Position := V3(MmToM(EdPos[0].Value), MmToM(EdPos[1].Value), MmToM(EdPos[2].Value));
  Part.RotX := EdRot[0].Value; Part.RotY := EdRot[1].Value; Part.RotZ := EdRot[2].Value;
  Part.Suppressed := CkSuppressed.Checked;
  P.Modified := True;
  RefreshPartLists;
  RefreshTree;
  MeshClick(nil);
end;

procedure TMultiPhysicsForm.DeletePartClick(Sender: TObject);
begin
  if SelectedPart = nil then Exit;
  P.DeletePart(LbParts.ItemIndex);
  RefreshAll;
  MeshClick(nil);
end;

{ ---------------- 2 materiais ---------------- }

procedure TMultiPhysicsForm.MatPartListClick(Sender: TObject);
var
  M: TMaterial;
begin
  if (LbMatParts.ItemIndex < 0) or (LbMatParts.ItemIndex >= P.PartCount) then Exit;
  M := P.Part(LbMatParts.ItemIndex).Material;
  FUpdating := True;
  try
    CbMaterial.ItemIndex := FindMaterial(M.Name);
    EdE.Value := M.YoungModulus / 1e9;
    EdNu.Value := M.Poisson;
    EdRho.Value := M.Density;
    EdK.Value := M.ThermalConductivity;
    EdAlpha.Value := M.ThermalExpansion * 1e6;
    EdYield.Value := M.YieldStrength / 1e6;
  finally
    FUpdating := False;
  end;
end;

procedure TMultiPhysicsForm.MaterialChange(Sender: TObject);
var
  M: TMaterial;
begin
  if FUpdating or (CbMaterial.ItemIndex < 0) then Exit;
  M := MaterialByIndex(CbMaterial.ItemIndex);
  EdE.Value := M.YoungModulus / 1e9;
  EdNu.Value := M.Poisson;
  EdRho.Value := M.Density;
  EdK.Value := M.ThermalConductivity;
  EdAlpha.Value := M.ThermalExpansion * 1e6;
  EdYield.Value := M.YieldStrength / 1e6;
end;

procedure TMultiPhysicsForm.ApplyMaterialClick(Sender: TObject);
var
  M: TMaterial;
  Part: TPhysicsPart;
begin
  if (LbMatParts.ItemIndex < 0) or (LbMatParts.ItemIndex >= P.PartCount) then
  begin
    SetStatus('Selecione a peca.');
    Exit;
  end;
  Part := P.Part(LbMatParts.ItemIndex);
  if CbMaterial.ItemIndex >= 0 then M := MaterialByIndex(CbMaterial.ItemIndex) else M := Part.Material;
  M.YoungModulus := EdE.Value * 1e9;
  M.Poisson := EdNu.Value;
  M.Density := EdRho.Value;
  M.ThermalConductivity := EdK.Value;
  M.ThermalExpansion := EdAlpha.Value * 1e-6;
  M.YieldStrength := EdYield.Value * 1e6;
  Part.Material := M;
  P.Modified := True;
  RefreshPartLists;
  RefreshTree;
  SetStatus(Format('Material de %s: %s', [Part.ID, M.Name]));
end;

procedure TMultiPhysicsForm.ApplyMaterialAllClick(Sender: TObject);
var
  I: Integer;
begin
  for I := 0 to P.PartCount - 1 do
  begin
    LbMatParts.ItemIndex := I;
    ApplyMaterialClick(nil);
  end;
end;

{ ---------------- 3 cargas ---------------- }

procedure TMultiPhysicsForm.BCKindChange(Sender: TObject);
begin
  UpdateBCUnits;
end;

procedure TMultiPhysicsForm.BCPartChange(Sender: TObject);
begin
  RefreshFaceCombo;
end;

procedure TMultiPhysicsForm.BCListClick(Sender: TObject);
var
  B: TBoundaryCondition;
  I: Integer;
begin
  if (LbBCs.ItemIndex < 0) or (LbBCs.ItemIndex >= P.BCCount) then Exit;
  B := P.BC(LbBCs.ItemIndex);
  EdBCName.Text := B.Name;
  CbBCKind.ItemIndex := BCKindIndex(B.Kind);
  UpdateBCUnits;
  CbBCPart.ItemIndex := P.FindPart(B.TargetID);
  RefreshFaceCombo;
  I := CbBCFace.Items.IndexOf(B.TargetFace);
  if I >= 0 then CbBCFace.ItemIndex := I else CbBCFace.ItemIndex := 0;
  case B.Kind of
    bkDisplacement: begin EdVec[0].Value := MToMm(B.X); EdVec[1].Value := MToMm(B.Y); EdVec[2].Value := MToMm(B.Z); end;
    bkForce, bkGravity: begin EdVec[0].Value := B.X; EdVec[1].Value := B.Y; EdVec[2].Value := B.Z; end;
  end;
  if B.Kind = bkPressure then EdVal1.Value := PaToMPa(B.Value) else EdVal1.Value := B.Value;
  EdVal2.Value := B.Value2;
  for I := 0 to 2 do CkDof[I].Checked := (B.DofMask = 0) or ((B.DofMask and (1 shl I)) <> 0);
end;

procedure TMultiPhysicsForm.AddBCClick(Sender: TObject);
var
  B: TBoundaryCondition;
begin
  if not BCFromUI(B) then Exit;
  P.AddBC(B);
  RefreshBCList;
  LbBCs.ItemIndex := P.BCCount - 1;
  RefreshTree;
  ShowMarks;
  SetStatus('Condicao "' + B.Name + '" adicionada.');
end;

procedure TMultiPhysicsForm.UpdateBCClick(Sender: TObject);
var
  B: TBoundaryCondition;
begin
  if (LbBCs.ItemIndex < 0) or (LbBCs.ItemIndex >= P.BCCount) then
  begin
    SetStatus('Selecione a condicao na lista.');
    Exit;
  end;
  if not BCFromUI(B) then Exit;
  P.SetBC(LbBCs.ItemIndex, B);
  RefreshBCList;
  RefreshTree;
  ShowMarks;
end;

procedure TMultiPhysicsForm.DeleteBCClick(Sender: TObject);
begin
  if (LbBCs.ItemIndex < 0) or (LbBCs.ItemIndex >= P.BCCount) then Exit;
  P.DeleteBC(LbBCs.ItemIndex);
  RefreshBCList;
  RefreshTree;
  ShowMarks;
end;

procedure TMultiPhysicsForm.ViewPickFace(Sender: TObject; FaceTag: Integer; const TagName: string);
var
  Parts: TStringList;
  I: Integer;
begin
  SetStatus('Face: ' + TagName);
  if FStep <> 2 then Exit;
  Parts := TStringList.Create;
  try
    Parts.Delimiter := '/';
    Parts.StrictDelimiter := True;
    Parts.DelimitedText := TagName;
    if Parts.Count < 3 then Exit;
    CbBCPart.ItemIndex := P.FindPart(Parts[0]);
    RefreshFaceCombo;
    I := CbBCFace.Items.IndexOf(TagName);
    if I < 0 then I := CbBCFace.Items.IndexOf(Parts[2]);
    if I >= 0 then CbBCFace.ItemIndex := I;
  finally
    Parts.Free;
  end;
end;

{ ---------------- 4 malha / 5 resolver ---------------- }

procedure TMultiPhysicsForm.MeshClick(Sender: TObject);
var
  Q: TMeshQuality;
begin
  ApplySettingsFromUI;
  Screen.Cursor := crHourGlass;
  try
    if not Run.MeshOnly(Q) then
    begin
      View.SetMesh(nil);
      LbMeshInfo.Caption := 'Nenhuma peca com geometria.';
      Exit;
    end;
  finally
    Screen.Cursor := crDefault;
  end;
  HasResult := False;
  View.SetMesh(Run.Mesh);
  View.Message := '';
  ShowMarks;
  LbMeshInfo.Caption := Format('%d nos, %d elementos TET%d'#13#10'%d faces de contorno'#13#10 +
    'Forma minima %.2f, media %.2f'#13#10'Elementos ruins (< 0,1): %d'#13#10'Invertidos: %d'#13#10'Volume %.4g cm3',
    [Run.Mesh.NodeCount, Run.Mesh.ElemCount, Run.Mesh.NodesPerElement, Run.Mesh.FaceCount,
     Q.MinShape, Q.MeanShape, Q.Poor, Q.Inverted, Run.Mesh.Volume * 1e6]);
  if Sender <> nil then SetStatus('Malha gerada.');
end;

procedure TMultiPhysicsForm.SolveClick(Sender: TObject);
var
  K: TAnalysisKind;
  I: Integer;
begin
  ApplySettingsFromUI;
  case CbAnalysis.ItemIndex of
    1: K := akThermal;
    2: K := akThermoMechanical;
    3: K := akModal;
    else K := akStatic;
  end;
  SetStatus('Resolvendo ' + AnalysisKindName(K) + '...');
  Application.ProcessMessages;
  Screen.Cursor := crHourGlass;
  try
    HasResult := Run.Run(K);
  finally
    Screen.Cursor := crDefault;
  end;
  Log.Lines.Add('--- ' + AnalysisKindName(K) + ' ---');
  for I := 0 to Run.Log.Count - 1 do Log.Lines.Add(Run.Log[I]);
  if not HasResult then
  begin
    SetStatus('Nao resolvido: ' + Run.Message);
    SetBadge('Nao resolvido', clSuiteDanger);
    RefreshTree;
    Exit;
  end;
  if Run.Fidelity = flEngineering then
  begin
    SetBadge(AnalysisKindName(K) + ': ENGENHARIA', clSuiteSuccess);
  end
  else
  begin
    SetBadge(AnalysisKindName(K) + ': ESTIMATIVA', clSuiteWarning);
  end;
  SetStatus(Format('%s resolvida em %d ms (%s).', [AnalysisKindName(K), Run.ElapsedMs, FidelityName(Run.Fidelity)]));
  View.SetMesh(Run.Mesh);
  CbField.Items.Clear;
  case K of
    akStatic: CbField.Items.CommaText := '"Deslocamento","Tensao de von Mises","Fator de seguranca"';
    akThermal: CbField.Items.CommaText := '"Temperatura"';
    akThermoMechanical: CbField.Items.CommaText := '"Deslocamento","Tensao de von Mises","Fator de seguranca","Temperatura"';
    akModal:
      for I := 0 to High(Run.ModalRes.Freq) do
        CbField.Items.Add(Format('Modo %d: %.2f Hz', [I + 1, Run.ModalRes.Freq[I]]));
  end;
  CbField.ItemIndex := 0;
  CkAnimate.Checked := K = akModal;
  RefreshTree;
  ShowStep(5);
end;

{ ---------------- 6 resultados ---------------- }

procedure TMultiPhysicsForm.ShowResultField;
var
  V: array of Double;
  I, NN, Mode: Integer;
  S, Yield: Double;
  Txt: string;
begin
  if not HasResult then
  begin
    View.ClearScalar;
    View.ClearDisplacement;
    Exit;
  end;
  NN := Run.Mesh.NodeCount;
  View.ClearMarks;
  View.Animate := False;
  V := nil;
  Txt := CbField.Text;
  if Run.Kind = akModal then
  begin
    Mode := Max(0, CbField.ItemIndex);
    if Mode <= High(Run.ModalRes.Shapes) then
    begin
      SetLength(V, NN);
      for I := 0 to NN - 1 do
        V[I] := Sqrt(Sqr(Run.ModalRes.Shapes[Mode][3 * I]) + Sqr(Run.ModalRes.Shapes[Mode][3 * I + 1]) + Sqr(Run.ModalRes.Shapes[Mode][3 * I + 2]));
      View.SetScalar(V, 'Forma modal', 'rel.');
      S := EdScale.Value;
      if S = 0 then S := View.AutoScale(Run.ModalRes.Shapes[Mode]);
      View.SetDisplacement(Run.ModalRes.Shapes[Mode], S);
      View.Animate := CkAnimate.Checked;
    end;
  end
  else
  begin
    SetLength(V, NN);
    if Pos('Temperatura', Txt) = 1 then
    begin
      for I := 0 to NN - 1 do V[I] := Run.ThermalRes.T[I];
      View.SetScalar(V, 'Temperatura', 'C');
    end
    else if Pos('Tensao', Txt) = 1 then
    begin
      for I := 0 to NN - 1 do V[I] := Run.StaticRes.VonMises[I] / 1e6;
      View.SetScalar(V, 'von Mises', 'MPa');
    end
    else if Pos('Fator', Txt) = 1 then
    begin
      Yield := 0;
      if P.PartCount > 0 then Yield := P.Part(0).Material.YieldStrength;
      for I := 0 to NN - 1 do V[I] := Min(10, Yield / Max(Run.StaticRes.VonMises[I], 1));
      View.SetScalar(V, 'Fator de seguranca (max 10)', '-');
    end
    else if Length(Run.StaticRes.U) = 3 * NN then
    begin
      for I := 0 to NN - 1 do
        V[I] := 1000 * Sqrt(Sqr(Run.StaticRes.U[3 * I]) + Sqr(Run.StaticRes.U[3 * I + 1]) + Sqr(Run.StaticRes.U[3 * I + 2]));
      View.SetScalar(V, 'Deslocamento', 'mm');
    end;
    if CkDeformed.Checked and (Length(Run.StaticRes.U) = 3 * NN) then
    begin
      S := EdScale.Value;
      if S = 0 then S := View.AutoScale(Run.StaticRes.U);
      View.SetDisplacement(Run.StaticRes.U, S);
      View.Animate := CkAnimate.Checked;
    end
    else
      View.ClearDisplacement;
  end;
  { resumo }
  Txt := AnalysisKindName(Run.Kind) + #13#10 + 'Fidelidade: ' + FidelityName(Run.Fidelity);
  if Run.Fidelity <> flEngineering then Txt := Txt + #13#10 + '(' + Run.FidelityReason + ')';
  if Run.Convergence >= 0 then Txt := Txt + Format(#13#10'Variacao entre malhas: %.2f%%', [Run.Convergence * 100]);
  Txt := Txt + Format(#13#10'Malha: %d nos, %d elementos', [Run.Mesh.NodeCount, Run.Mesh.ElemCount]);
  case Run.Kind of
    akStatic, akThermoMechanical:
      begin
        Txt := Txt + #13#10#13#10'Deslocamento maximo: ' + FormatLength(Run.StaticRes.MaxDisp);
        Txt := Txt + #13#10'von Mises maximo: ' + FormatStress(Run.StaticRes.MaxVonMises);
        if Run.StaticRes.MinSafety < 1e30 then Txt := Txt + Format(#13#10'Fator de seguranca minimo: %.2f', [Run.StaticRes.MinSafety]);
        Txt := Txt + Format(#13#10'Reacao: (%s, %s, %s)', [FormatForce(Run.StaticRes.Reaction.X),
          FormatForce(Run.StaticRes.Reaction.Y), FormatForce(Run.StaticRes.Reaction.Z)]);
        if Run.Kind = akThermoMechanical then
          Txt := Txt + Format(#13#10'Temperatura: %.1f a %.1f C', [Run.ThermalRes.MinT, Run.ThermalRes.MaxT]);
      end;
    akThermal:
      Txt := Txt + Format(#13#10#13#10'Temperatura: %.2f a %.2f C'#13#10'Calor pelas faces fixas: %.3f W',
        [Run.ThermalRes.MinT, Run.ThermalRes.MaxT, Run.ThermalRes.HeatIn]);
    akModal:
      begin
        Txt := Txt + #13#10;
        for I := 0 to High(Run.ModalRes.Freq) do Txt := Txt + Format(#13#10'Modo %d: %.2f Hz', [I + 1, Run.ModalRes.Freq[I]]);
      end;
  end;
  LbSummary.Caption := Txt;
  View.Message := AnalysisKindName(Run.Kind) + ' - ' + FidelityName(Run.Fidelity);
end;

procedure TMultiPhysicsForm.FieldChange(Sender: TObject);
begin
  if FStep = 5 then ShowResultField;
end;

procedure TMultiPhysicsForm.ExportCSVClick(Sender: TObject);
var
  D: TSaveDialog;
  L: TStringList;
  I: Integer;
  Line: string;
  M: TFEMMesh;

  function F(V: Double): string;
  begin
    Result := FloatToStr(V, InvariantFS);
  end;

begin
  if not HasResult then begin SetStatus('Resolva uma analise antes.'); Exit; end;
  D := TSaveDialog.Create(Self);
  L := TStringList.Create;
  try
    D.Filter := 'CSV (*.csv)|*.csv';
    D.DefaultExt := 'csv';
    D.FileName := P.Name + '_resultado.csv';
    if not D.Execute then Exit;
    M := Run.Mesh;
    L.Add('# MultiPhysics - ' + AnalysisKindName(Run.Kind) + ' - fidelidade ' + FidelityName(Run.Fidelity));
    Line := 'no;x_m;y_m;z_m';
    if Length(Run.StaticRes.U) = 3 * M.NodeCount then Line := Line + ';ux_m;uy_m;uz_m;von_mises_pa';
    if Length(Run.ThermalRes.T) = M.NodeCount then Line := Line + ';temperatura_c';
    L.Add(Line);
    for I := 0 to M.NodeCount - 1 do
    begin
      Line := IntToStr(I) + ';' + F(M.Nodes[I].X) + ';' + F(M.Nodes[I].Y) + ';' + F(M.Nodes[I].Z);
      if Length(Run.StaticRes.U) = 3 * M.NodeCount then
        Line := Line + ';' + F(Run.StaticRes.U[3 * I]) + ';' + F(Run.StaticRes.U[3 * I + 1]) + ';' +
          F(Run.StaticRes.U[3 * I + 2]) + ';' + F(Run.StaticRes.VonMises[I]);
      if Length(Run.ThermalRes.T) = M.NodeCount then Line := Line + ';' + F(Run.ThermalRes.T[I]);
      L.Add(Line);
    end;
    if Run.Kind = akModal then
      for I := 0 to High(Run.ModalRes.Freq) do L.Add(Format('# modo %d: %s Hz', [I + 1, F(Run.ModalRes.Freq[I])]));
    L.SaveToFile(D.FileName);
    SetStatus('CSV salvo em ' + D.FileName);
  finally
    L.Free;
    D.Free;
  end;
end;

procedure TMultiPhysicsForm.ReportClick(Sender: TObject);
var
  D: TSaveDialog;
  H: TStringList;
  Bmp: TBitmap;
  Png: TPortableNetworkGraphic;
  ImgName: string;
  I: Integer;

  function Esc(const S: string): string;
  begin
    Result := StringReplace(StringReplace(StringReplace(S, '&', '&amp;', [rfReplaceAll]), '<', '&lt;', [rfReplaceAll]), '>', '&gt;', [rfReplaceAll]);
  end;

begin
  if not HasResult then begin SetStatus('Resolva uma analise antes.'); Exit; end;
  D := TSaveDialog.Create(Self);
  H := TStringList.Create;
  try
    D.Filter := 'HTML (*.html)|*.html';
    D.DefaultExt := 'html';
    D.FileName := P.Name + '_relatorio.html';
    if not D.Execute then Exit;
    ImgName := ChangeFileExt(ExtractFileName(D.FileName), '.png');
    Bmp := TBitmap.Create; Png := TPortableNetworkGraphic.Create;
    try
      Bmp.SetSize(View.ClientWidth, View.ClientHeight);
      View.PaintTo(Bmp.Canvas, 0, 0);
      Png.Assign(Bmp);
      Png.SaveToFile(ChangeFileExt(D.FileName, '.png'));
    finally
      Png.Free; Bmp.Free;
    end;
    H.Add('<!doctype html><html><head><meta charset="utf-8"><title>' + Esc(P.Name) + ' - MultiPhysics</title>');
    H.Add('<style>body{font-family:Segoe UI,Arial,sans-serif;margin:32px;color:#0f172a}td,th{border:1px solid #e2e8f0;padding:4px 10px;text-align:left}' +
      'table{border-collapse:collapse}.fid{display:inline-block;padding:4px 10px;border-radius:6px;background:#f1f5f9;font-weight:600}pre{background:#f8fafc;padding:12px}</style></head><body>');
    H.Add('<h1>' + Esc(P.Name) + '</h1>');
    H.Add('<p>' + Esc(AnalysisKindName(Run.Kind)) + ' &middot; <span class="fid">' + FidelityName(Run.Fidelity) + '</span> ' +
      Esc(Run.FidelityReason) + '</p>');
    H.Add('<img src="' + Esc(ImgName) + '" style="max-width:100%;border:1px solid #e2e8f0">');
    H.Add('<h2>Resumo</h2><pre>' + Esc(LbSummary.Caption) + '</pre>');
    H.Add('<h2>Pecas</h2><table><tr><th>ID</th><th>Material</th><th>Massa</th></tr>');
    for I := 0 to P.PartCount - 1 do
      H.Add(Format('<tr><td>%s</td><td>%s</td><td>%.4f kg</td></tr>', [Esc(P.Part(I).ID), Esc(P.Part(I).Material.Name), P.Part(I).Mass]));
    H.Add('</table><h2>Condicoes de contorno</h2><table><tr><th>Nome</th><th>Tipo</th><th>Peca/face</th></tr>');
    for I := 0 to P.BCCount - 1 do
      H.Add(Format('<tr><td>%s</td><td>%s</td><td>%s/%s</td></tr>', [Esc(P.BC(I).Name), Esc(BoundaryKindName(P.BC(I).Kind)),
        Esc(P.BC(I).TargetID), Esc(P.BC(I).TargetFace)]));
    H.Add('</table><h2>Registro do solver</h2><pre>' + Esc(Run.Log.Text) + '</pre>');
    H.Add('<p style="color:#64748b">Gerado pelo MultiPhysics em ' + DateTimeToStr(Now) +
      '. ENGENHARIA = FEM com malha verificada e convergencia &lt; 5%; ESTIMATIVA = sem essa verificacao. ' +
      'Nenhum resultado e VALIDADO sem comparacao com ensaio ou referencia.</p></body></html>');
    H.SaveToFile(D.FileName);
    SetStatus('Relatorio salvo em ' + D.FileName);
  finally
    H.Free;
    D.Free;
  end;
end;

procedure TMultiPhysicsForm.ViewFitClick(Sender: TObject);
begin
  View.FitView;
end;

procedure TMultiPhysicsForm.ViewDirClick(Sender: TObject);
begin
  case TComponent(Sender).Tag of
    1: View.SetView(0, 0);
    2: View.SetView(0, 89);
    3: View.SetView(-90, 0);
    else View.SetView(-35, 25);
  end;
end;

{ ---------------- 7 sistema ---------------- }

procedure TMultiPhysicsForm.LoadMachineClick(Sender: TObject);
var
  I: Integer;
begin
  RuntimeTimer.Enabled := False;
  FreeAndNil(GraphRuntime);
  FreeAndNil(Graph);
  Graph := BuildDemoMachine;
  GraphRuntime := TGraphRuntime.Create(Graph, Log.Lines);
  Log.Lines.Add('--- Maquina executavel ---');
  for I := 0 to Graph.ComponentCount - 1 do
    Log.Lines.Add('  ' + Graph.ComponentAt(I).ID + ' - ' + Graph.ComponentAt(I).Name);
  Log.Lines.Add(Format('  %d conexoes', [Graph.ConnectionCount]));
  if GraphRuntime.Prepare then SetStatus('Maquina pronta. Clique em Ligar.');
  Chart.Clear;
  Chart.Title := 'Sistema eletromecanico (ESTIMATIVA)';
  Chart.AddSeries('V barramento', 'V', clDefault);
  Chart.AddSeries('Corrente', 'A', clDefault);
  Chart.AddSeries('Velocidade', 'rad/s', clDefault);
  Chart.AddSeries('Temperatura', 'C', clDefault);
  Chart.AddSeries('PWM', '%', clDefault);
end;

procedure TMultiPhysicsForm.RuntimeStartClick(Sender: TObject);
begin
  if GraphRuntime = nil then LoadMachineClick(nil);
  if not GraphRuntime.Prepare then Exit;
  GraphRuntime.Start;
  RuntimeTimer.Enabled := True;
  SetStatus('Simulacao ligada.');
end;

procedure TMultiPhysicsForm.RuntimePauseClick(Sender: TObject);
begin
  if GraphRuntime <> nil then GraphRuntime.Pause;
  RuntimeTimer.Enabled := False;
  SetStatus('Simulacao pausada.');
end;

procedure TMultiPhysicsForm.RuntimeStopClick(Sender: TObject);
begin
  RuntimeTimer.Enabled := False;
  if GraphRuntime <> nil then GraphRuntime.Stop;
  SetStatus('Simulacao desligada.');
end;

procedure TMultiPhysicsForm.RuntimeTick(Sender: TObject);
var
  S: TSimulationSnapshot;
  I: Integer;
begin
  if GraphRuntime = nil then Exit;
  for I := 1 to 5 do GraphRuntime.Step;
  S := GraphRuntime.Snapshot;
  Chart.AddSample(S.Clock.Time, [S.Electrical.BusVoltage, S.Electrical.TotalCurrent, S.Mechanical.Velocity,
    S.Thermal.Temperature, S.Control.PWM * 100]);
  LbRuntime.Caption := Format('t = %.2f s'#13#10'Barramento %.2f V, %.2f A'#13#10'Velocidade %.2f rad/s'#13#10 +
    'Torque %.3f N m'#13#10'Temperatura %.1f C'#13#10'PWM %.0f%%',
    [S.Clock.Time, S.Electrical.BusVoltage, S.Electrical.TotalCurrent, S.Mechanical.Velocity,
     S.Mechanical.Torque, S.Thermal.Temperature, S.Control.PWM * 100]);
  if Chart.SampleCount > 4000 then RuntimeTimer.Enabled := False;
end;

procedure TMultiPhysicsForm.ChartCSVClick(Sender: TObject);
var
  D: TSaveDialog;
begin
  if Chart.SampleCount = 0 then begin SetStatus('Sem dados no grafico.'); Exit; end;
  D := TSaveDialog.Create(Self);
  try
    D.Filter := 'CSV (*.csv)|*.csv';
    D.DefaultExt := 'csv';
    D.FileName := 'serie_temporal.csv';
    if D.Execute then
    begin
      Chart.SaveCSV(D.FileName);
      SetStatus('CSV salvo em ' + D.FileName);
    end;
  finally
    D.Free;
  end;
end;

{ ---------------- 8 maquina ---------------- }

procedure TMultiPhysicsForm.MachineCreateClick(Sender: TObject);
begin
  Machine.Clear;
  Machine.AddAxis('X', 0, 300, 80, 1.2);
  Machine.AddAxis('Y', 0, 200, 80, 1.2);
  Machine.AddAxis('Z', 0, 100, 400, 1.5);
  Machine.SetSpindle(12000);
  Machine.Start;
  Chart.Clear;
  Chart.Title := 'CNC virtual XYZ (ESTIMATIVA)';
  Chart.AddSeries('X', 'mm', clSuiteAxisX);
  Chart.AddSeries('Y', 'mm', clSuiteAxisY);
  Chart.AddSeries('Z', 'mm', clSuiteAxisZ);
  Chart.AddSeries('Spindle', 'rpm', clDefault);
  LbMachine.Caption := 'CNC energizada: X 0-300, Y 0-200, Z 0-100 mm, spindle alvo 12000 rpm.';
  SetStatus('CNC virtual criada.');
end;

procedure TMultiPhysicsForm.MachineMoveClick(Sender: TObject);
var
  I, K: Integer;
  T: Double;
  Txt: string;
begin
  if Machine.AxisCount = 0 then MachineCreateClick(nil);
  for K := 0 to 2 do Machine.CommandAxis(Chr(Ord('X') + K), EdTarget[K].Value, EdFeed.Value);
  T := 0;
  for I := 1 to 6000 do
  begin
    Machine.Step;
    T := T + 0.001;
    if I mod 20 = 0 then
      Chart.AddSample(T, [Machine.Axis(0).State.PositionMM, Machine.Axis(1).State.PositionMM,
        Machine.Axis(2).State.PositionMM, Machine.SpindleRPM]);
    if Machine.TripReason <> '' then Break;
  end;
  Txt := '';
  for K := 0 to Machine.AxisCount - 1 do
    with Machine.Axis(K) do
      Txt := Txt + Format('%s = %.3f mm, passos perdidos %d%s'#13#10, [Name, State.PositionMM, State.LostSteps,
        IfThen(State.AtMin or State.AtMax, ' (fim de curso)', '')]);
  Txt := Txt + Format('Spindle %.0f rpm', [Machine.SpindleRPM]);
  if Machine.TripReason <> '' then Txt := Txt + #13#10'DESARME: ' + Machine.TripReason;
  LbMachine.Caption := Txt;
  Log.Lines.Add('--- CNC ---');
  Log.Lines.Add(StringReplace(Txt, #13#10, ' | ', [rfReplaceAll]));
end;

procedure TMultiPhysicsForm.MachineFaultClick(Sender: TObject);
begin
  if Machine.AxisCount = 0 then MachineCreateClick(nil);
  InjectAxisFault(Machine.Axis(CbFaultAxis.ItemIndex), TMachineFault(CbFault.ItemIndex + 1));
  Log.Lines.Add(Format('Falha injetada no eixo %s: %s', [CbFaultAxis.Text, CbFault.Text]));
  SetStatus('Falha injetada. Execute um movimento para ver o efeito.');
end;

{ ---------------- 9 circuito ---------------- }

procedure TMultiPhysicsForm.CircuitSolveClick(Sender: TObject);
var
  R: TNetlistResult;
  I, K, Stride: Integer;
begin
  R := RunNetlist(MmNetlist.Text);
  try
    Log.Lines.Add('--- Circuito ---');
    if not R.Ok then
    begin
      Log.Lines.Add('Erro: ' + R.Message);
      SetStatus('Circuito: ' + R.Message);
      Exit;
    end;
    Log.Lines.Add('Ponto DC:');
    for I := 0 to R.DCNodes.Count - 1 do Log.Lines.Add('  V(' + R.DCNodes.Names[I] + ') = ' + R.DCNodes.ValueFromIndex[I] + ' V');
    Chart.Clear;
    Chart.Title := 'Transitorio do circuito';
    if R.HasTran then
    begin
      for I := 0 to R.Probes.Count - 1 do Chart.AddSeries('V(' + R.Probes[I] + ')', 'V', clDefault);
      Stride := Max(1, Length(R.Times) div 2000);
      K := 0;
      while K <= High(R.Times) do
      begin
        Chart.AddSample(R.Times[K], R.Values[K]);
        Inc(K, Stride);
      end;
    end;
    SetStatus('Circuito resolvido: ' + R.Message);
  finally
    FreeNetlistResult(R);
  end;
end;

{ ---------------- 10 ambiente ---------------- }

procedure TMultiPhysicsForm.EnvChange(Sender: TObject);
begin
  case CbEnv.ItemIndex of
    0: Scenario.Environment := AirEnvironment;
    2: Scenario.Environment := VacuumEnvironment;
    else Scenario.Environment := WaterEnvironment;
  end;
  Log.Lines.Add('Ambiente: ' + Scenario.Environment.Name);
end;

procedure TMultiPhysicsForm.EstimateClick(Sender: TObject);
var
  R: TFluidEstimate;
begin
  EnvChange(nil);
  Scenario.Environment.FlowX := EdFlow.Value;
  R := EstimateFluidLoads(Scenario.Environment, EdArea.Value, EdCd.Value, EdVolume.Value);
  Log.Lines.Add('--- ESTIMATIVA, NAO E CFD ---');
  Log.Lines.Add(Format('Velocidade %.3f m/s, pressao dinamica %.2f Pa', [R.Speed, R.DynamicPressure]));
  Log.Lines.Add(Format('Arrasto estimado %.2f N, empuxo %.2f N', [R.DragForce, R.BuoyancyForce]));
  if (CbEnv.ItemIndex = 0) and (Abs(EdFlow.Value) > 0.3 * 343) then
    Log.Lines.Add('Aviso: acima de Mach 0,3 a hipotese incompressivel nao vale.');
  SetStatus(Format('Arrasto %.2f N, empuxo %.2f N (ESTIMATIVA)', [R.DragForce, R.BuoyancyForce]));
end;

procedure TMultiPhysicsForm.FloatTestClick(Sender: TObject);
var
  Body: TRigidBodyState;
  R: TBuoyancyResult;
begin
  EnvChange(nil);
  FillChar(Body, SizeOf(Body), 0);
  Body.Mass := EdMass.Value;
  Body.CenterOfMass := V3(0, 0, 0.2);
  Body.Inertia := V3(20, 50, 50);
  R := EvaluateBuoyancy(Body, Scenario.Environment, EdVolume.Value, V3(0, 0, 0));
  Log.Lines.Add('--- FLUTUACAO (ESTIMATIVA) ---');
  Log.Lines.Add(Format('Peso %.2f N, empuxo %.2f N, forca liquida %.2f N: %s',
    [R.Weight, R.Buoyancy, R.NetVerticalForce, FloatStateName(R.State)]));
  Log.Lines.Add('Ainda nao inclui superficie livre nem metacentro.');
  SetStatus('Flutuacao: ' + FloatStateName(R.State));
end;

end.
