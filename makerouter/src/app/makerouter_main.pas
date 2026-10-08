unit makerouter_main;

{ Tela principal do MakeRouter, no padrao visual da suite (igual ao LaserPCB,
  MakePCB e RouterPCB): cabecalho, etapas na lateral, parametros a direita,
  vista ao centro e rodape com Validar / Gerar G-code / Abrir no MultiCNC.

  Etapas: 1 Material (tamanho e zero virtual), 2 Desenho (formas), 3 Relevo
  (fase 6), 4 Percursos (ferramentas e lista de percursos), 5 Simular
  (remocao de material), 6 Saida (programas para o MultiCNC). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls, CheckLst,
  Dialogs, Graphics, LCLType, laserpcb_geom, makerouter_types, makerouter_project,
  makerouter_cam, makerouter_sim, makerouter_gcode, makerouter_view,
  multisuite_controls, multisuite_icons;

type
  TMakeRouterForm = class(TForm)
  private
    P: TMRProject;
    View: TMRView;
    Pages: TPageControl;
    Nav: array[0..5] of TSuiteButton;
    ShapeList: TListBox;
    PathList: TCheckListBox;
    Info, Status, Coords, StepInfo: TLabel;
    State: TSuiteBadge;
    FooterPanel: TPanel;
    ValidateButton, ExportButton, SendButton: TSuiteButton;
    DesignButton, SimButton: TSuiteButton;
    ShowPathsBox, ShowRapidsBox: TCheckBox;
    { material }
    MatW, MatH, MatT, MatSafe, MatTravel, MatSpin: TEdit;
    DatumButtons: array[TMRDatumXY] of TSuiteButton;
    DatumZBox, WoodBox: TComboBox;
    { forma }
    ShName, ShX, ShY, ShW, ShH, ShRad, ShCorner, ShSides, ShInner, ShRot, ShText, ShTextH: TEdit;
    ShTitle: TLabel;
    { percurso }
    TpName, TpDepth, TpStart, TpTabs, TpTabW, TpTabH, TpAllow, TpPeck: TEdit;
    TpTool, TpSide, TpDir: TComboBox;
    TpRamp: TCheckBox;
    TpTitle: TLabel;
    { ferramenta }
    TlName, TlDia, TlAngle, TlStepDown, TlStepOver, TlFeed, TlPlunge, TlRPM: TEdit;
    TlKind: TComboBox;
    { simulacao e saida }
    SimSummary, OutSummary: TLabel;
    SingleFile: TCheckBox;
    Log: TMemo;
    FUpdating: Boolean;
    FExportedFile: string;
    FStock: TMRStock;
    function Button(AParent: TWinControl; const AText: string; X, Y, W: Integer;
      AIcon: TSuiteIconKind; Handler: TNotifyEvent): TSuiteButton;
    function LabelAt(AParent: TWinControl; const AText: string; X, Y, W, H: Integer): TLabel;
    function Field(AParent: TWinControl; const AText, Value: string; Y: Integer): TEdit;
    function Combo(AParent: TWinControl; const AText: string; Y: Integer): TComboBox;
    function Num(E: TEdit; const What: string): Double;
    function IntOf(E: TEdit; const What: string; Lo, Hi: Integer): Integer;
    procedure BuildMaterialPage(S: TScrollBox);
    procedure BuildDesignPage(S: TScrollBox);
    procedure BuildReliefPage(S: TScrollBox);
    procedure BuildPathsPage(S: TScrollBox);
    procedure BuildSimPage(S: TScrollBox);
    procedure BuildOutputPage(S: TScrollBox);
    procedure NavClick(Sender: TObject);
    procedure DatumClick(Sender: TObject);
    procedure MaterialApply(Sender: TObject);
    procedure AddShapeClick(Sender: TObject);
    procedure DuplicateClick(Sender: TObject);
    procedure DeleteShapesClick(Sender: TObject);
    procedure ShapeApply(Sender: TObject);
    procedure CenterShapeClick(Sender: TObject);
    procedure ShapeListClick(Sender: TObject);
    procedure ViewSelect(Sender: TObject);
    procedure ViewMoveShapes(Sender: TObject; DX, DY: Double);
    procedure ViewCursor(Sender: TObject; X, Y: Double);
    procedure AddPathClick(Sender: TObject);
    procedure DeletePathClick(Sender: TObject);
    procedure PathUpClick(Sender: TObject);
    procedure PathDownClick(Sender: TObject);
    procedure PathListClick(Sender: TObject);
    procedure PathCheck(Sender: TObject; Index: Integer);
    procedure PathApply(Sender: TObject);
    procedure UseSelectionClick(Sender: TObject);
    procedure CalculateClick(Sender: TObject);
    procedure ToolBoxChange(Sender: TObject);
    procedure ToolSaveClick(Sender: TObject);
    procedure ToolNewClick(Sender: TObject);
    procedure SimAllClick(Sender: TObject);
    procedure SimOneClick(Sender: TObject);
    procedure DesignViewClick(Sender: TObject);
    procedure ViewOptionsChanged(Sender: TObject);
    procedure FitClick(Sender: TObject);
    procedure ZoomInClick(Sender: TObject);
    procedure ZoomOutClick(Sender: TObject);
    procedure NewClick(Sender: TObject);
    procedure OpenClick(Sender: TObject);
    procedure SaveClick(Sender: TObject);
    procedure ExampleClick(Sender: TObject);
    procedure ValidateClick(Sender: TObject);
    procedure ExportClick(Sender: TObject);
    procedure SendClick(Sender: TObject);
    procedure FormKey(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ResizeUI(Sender: TObject);
    procedure ShowUI(Sender: TObject);
    procedure LoadMaterialEditor;
    procedure LoadShapeEditor;
    procedure LoadPathEditor;
    procedure LoadToolEditor;
    procedure RefreshShapeList;
    procedure RefreshPathList;
    procedure RefreshToolBox;
    procedure RefreshInfo;
    procedure Changed(const Msg: string);
    procedure ShowError(E: Exception);
    function SelectedShape: TMRShape;
    function SelectedPath: TMRToolpath;
    procedure RunSimulation(OnlyIndex: Integer);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { uso pela linha de comando e pelos testes }
    procedure OpenFile(const FN: string);
    procedure LoadExample;
    procedure ShowStep(N: Integer);
    procedure SelectShape(AId: Integer);
    function CalculateAll: Integer;
    function Simulate: Double;
    function ValidateJob: Boolean;
    function ExportTo(const Folder: string): TStringList;
    property Project: TMRProject read P;
    property ViewControl: TMRView read View;
    property Stock: TMRStock read FStock;
  end;

const
  MR_STEPS: array[0..5] of string = ('1  Material', '2  Desenho', '3  Relevo',
    '4  Percursos', '5  Simular', '6  Saida');

implementation

uses multisuite_numfmt, multisuite_registry, multisuite_launcher, multisuite_types,
  multisuite_context;

const
  STEP_ICONS: array[0..5] of TSuiteIconKind = (sikRect, sikPen, sikLayers, sikMakeRouter,
    sikPlay, sikExport);

function FmtN(V: Double): string;
begin
  Result := FormatFloat('0.###', V, InvariantFS);
end;

{ ---------------- construcao ---------------- }

function TMakeRouterForm.Button(AParent: TWinControl; const AText: string; X, Y, W: Integer;
  AIcon: TSuiteIconKind; Handler: TNotifyEvent): TSuiteButton;
begin
  Result := TSuiteButton.Create(Self);
  Result.Parent := AParent;
  Result.SetBounds(X, Y, W, 34);
  Result.Caption := AText;
  Result.SetLook(sbsSoft, clSuitePrimary, AIcon);
  Result.OnClick := Handler;
end;

function TMakeRouterForm.LabelAt(AParent: TWinControl; const AText: string; X, Y, W, H: Integer): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := AParent;
  Result.AutoSize := False;
  Result.SetBounds(X, Y, W, H);
  Result.WordWrap := True;
  Result.Caption := AText;
  Result.Font.Color := clSuiteMuted;
end;

function TMakeRouterForm.Field(AParent: TWinControl; const AText, Value: string; Y: Integer): TEdit;
begin
  LabelAt(AParent, AText, 16, Y, 290, 18);
  Result := TEdit.Create(Self);
  Result.Parent := AParent;
  Result.SetBounds(16, Y + 20, 290, 28);
  Result.Text := Value;
end;

function TMakeRouterForm.Combo(AParent: TWinControl; const AText: string; Y: Integer): TComboBox;
begin
  LabelAt(AParent, AText, 16, Y, 290, 18);
  Result := TComboBox.Create(Self);
  Result.Parent := AParent;
  Result.SetBounds(16, Y + 20, 290, 30);
  Result.Style := csDropDownList;
end;

constructor TMakeRouterForm.Create(AOwner: TComponent);
var
  Header: TSuiteHeader;
  Sidebar, Work, Bar, Footer: TPanel;
  Page: TTabSheet;
  Scroll: TScrollBox;
  I: Integer;
begin
  inherited CreateNew(AOwner, 1);
  Caption := 'MakeRouter • MultiSuite';
  Width := 1280; Height := 860;
  Constraints.MinWidth := 1060; Constraints.MinHeight := 680;
  Position := poScreenCenter;
  Font.Name := SUITE_FONT; Font.Size := 10;
  Color := clSuiteSurface;
  KeyPreview := True;
  OnKeyDown := @FormKey;
  P := TMRProject.Create;
  FStock := TMRStock.Create;
  FUpdating := True;

  Header := TSuiteHeader.Create(Self);
  Header.Parent := Self; Header.Align := alTop; Header.Height := 72;
  Header.Setup('MakeRouter', 'Projeto e usinagem de madeira  /  MultiSuite', sikMakeRouter);

  Footer := TPanel.Create(Self);
  Footer.Parent := Self; Footer.Align := alBottom; Footer.Height := 66;
  Footer.BevelOuter := bvNone; Footer.Color := clSuiteCard;
  FooterPanel := Footer;
  Status := LabelAt(Footer, 'Desenhe a peca ou abra o exemplo.', 18, 8, 420, 26);
  Coords := LabelAt(Footer, '', 18, 36, 420, 22);
  ValidateButton := Button(Footer, 'Validar', 0, 15, 130, sikTests, @ValidateClick);
  ExportButton := Button(Footer, 'Gerar G-code', 0, 15, 160, sikExport, @ExportClick);
  ExportButton.SetLook(sbsSolid, clSuitePrimary, sikExport);
  SendButton := Button(Footer, 'Abrir no MultiCNC', 0, 15, 222, sikSend, @SendClick);
  SendButton.Enabled := False;

  Sidebar := TPanel.Create(Self);
  Sidebar.Parent := Self; Sidebar.Align := alLeft; Sidebar.Width := 214;
  Sidebar.BevelOuter := bvNone; Sidebar.Color := clSuiteCard;
  for I := 0 to 5 do
  begin
    Nav[I] := Button(Sidebar, MR_STEPS[I], 12, 16 + I * 44, 190, STEP_ICONS[I], @NavClick);
    Nav[I].Tag := I;
  end;
  Button(Sidebar, 'Novo', 12, 290, 92, sikNew, @NewClick);
  Button(Sidebar, 'Abrir', 110, 290, 92, sikFolder, @OpenClick);
  Button(Sidebar, 'Salvar', 12, 330, 92, sikSave, @SaveClick);
  Button(Sidebar, 'Demo', 110, 330, 92, sikWand, @ExampleClick).Hint := 'Abrir a placa de exemplo';
  LabelAt(Sidebar, 'FORMAS', 16, 380, 180, 20).Font.Style := [fsBold];
  ShapeList := TListBox.Create(Self);
  ShapeList.Parent := Sidebar;
  ShapeList.SetBounds(12, 404, 190, 200);
  ShapeList.Anchors := [akLeft, akTop, akRight, akBottom];
  ShapeList.MultiSelect := True;
  ShapeList.OnClick := @ShapeListClick;
  Info := LabelAt(Sidebar, '', 16, 600, 184, 90);
  Info.Align := alBottom;
  Info.BorderSpacing.Around := 12;

  Pages := TPageControl.Create(Self);
  Pages.Parent := Self; Pages.Align := alRight; Pages.Width := 336;
  Pages.ShowTabs := False;
  for I := 0 to 5 do
  begin
    Page := TTabSheet.Create(Self);
    Page.PageControl := Pages;
    Page.Caption := MR_STEPS[I];
    Scroll := TScrollBox.Create(Self);
    Scroll.Parent := Page; Scroll.Align := alClient;
    Scroll.BorderStyle := bsNone; Scroll.Color := clSuiteCard;
    Scroll.HorzScrollBar.Visible := False;
    LabelAt(Scroll, MR_STEPS[I], 16, 16, 260, 30).Font.Style := [fsBold];
    case I of
      0: BuildMaterialPage(Scroll);
      1: BuildDesignPage(Scroll);
      2: BuildReliefPage(Scroll);
      3: BuildPathsPage(Scroll);
      4: BuildSimPage(Scroll);
      5: BuildOutputPage(Scroll);
    end;
  end;

  Work := TPanel.Create(Self);
  Work.Parent := Self; Work.Align := alClient;
  Work.BevelOuter := bvNone; Work.Color := clSuiteSurface;
  Bar := TPanel.Create(Self);
  Bar.Parent := Work; Bar.Align := alTop; Bar.Height := 52;
  Bar.BevelOuter := bvNone; Bar.Color := clSuiteSurface;
  DesignButton := Button(Bar, 'Desenho', 12, 9, 112, sikPen, @DesignViewClick);
  SimButton := Button(Bar, 'Simulacao', 130, 9, 124, sikPlay, @SimAllClick);
  Button(Bar, 'Ajustar', 262, 9, 96, sikFit, @FitClick);
  Button(Bar, '', 364, 9, 42, sikZoomIn, @ZoomInClick).Hint := 'Ampliar';
  Button(Bar, '', 412, 9, 42, sikZoomOut, @ZoomOutClick).Hint := 'Reduzir';
  ShowPathsBox := TCheckBox.Create(Self);
  ShowPathsBox.Parent := Bar; ShowPathsBox.SetBounds(468, 14, 110, 24);
  ShowPathsBox.Caption := 'Percursos'; ShowPathsBox.Checked := True;
  ShowPathsBox.OnChange := @ViewOptionsChanged;
  ShowRapidsBox := TCheckBox.Create(Self);
  ShowRapidsBox.Parent := Bar; ShowRapidsBox.SetBounds(580, 14, 140, 24);
  ShowRapidsBox.Caption := 'Deslocamentos'; ShowRapidsBox.Checked := False;
  ShowRapidsBox.OnChange := @ViewOptionsChanged;
  View := TMRView.Create(Self);
  View.Parent := Work; View.Align := alClient;
  View.Project := P;
  View.OnSelect := @ViewSelect;
  View.OnMoveShapes := @ViewMoveShapes;
  View.OnCursor := @ViewCursor;

  FUpdating := False;
  OnResize := @ResizeUI;
  OnShow := @ShowUI;
  LoadMaterialEditor;
  RefreshToolBox;
  RefreshShapeList;
  RefreshPathList;
  LoadToolEditor;
  ShowStep(0);
end;

destructor TMakeRouterForm.Destroy;
begin
  View.Project := nil;
  FStock.Free;
  P.Free;
  inherited Destroy;
end;

procedure TMakeRouterForm.BuildMaterialPage(S: TScrollBox);
var D: TMRDatumXY; C, R, I: Integer;
begin
  LabelAt(S, 'Tamanho da chapa ou tabua presa na mesa. O desenho comeca no canto inferior esquerdo do material.',
    16, 48, 290, 40);
  MatW := Field(S, 'Largura X (mm)', '300', 92);
  MatH := Field(S, 'Altura Y (mm)', '200', 148);
  MatT := Field(S, 'Espessura (mm)', '18', 204);
  LabelAt(S, 'PONTO DE ZERO XY', 16, 266, 290, 18).Font.Style := [fsBold];
  for D := Low(TMRDatumXY) to High(TMRDatumXY) do
  begin
    C := Ord(D) mod 3; R := 2 - Ord(D) div 3;
    DatumButtons[D] := Button(S, MR_DATUM_CODES[D], 16 + C * 100, 290 + R * 40, 92, sikTarget, @DatumClick);
    DatumButtons[D].Tag := Ord(D);
    DatumButtons[D].Hint := MR_DATUM_NAMES[D];
    DatumButtons[D].ShowHint := True;
  end;
  DatumZBox := Combo(S, 'Zero Z', 414);
  DatumZBox.Items.Add(MR_DATUMZ_NAMES[dzTop]);
  DatumZBox.Items.Add(MR_DATUMZ_NAMES[dzTable]);
  DatumZBox.ItemIndex := 0;
  MatSafe := Field(S, 'Z seguro acima do topo (mm)', '10', 472);
  MatTravel := Field(S, 'Z de deslocamento acima do topo (mm)', '5', 528);
  MatSpin := Field(S, 'Espera do spindle (s)', '3', 584);
  WoodBox := Combo(S, 'Madeira da previa', 640);
  for I := 0 to High(MR_WOODS) do WoodBox.Items.Add(MR_WOODS[I]);
  WoodBox.ItemIndex := 0;
  Button(S, 'Aplicar', 16, 702, 290, sikTarget, @MaterialApply).SetLook(sbsSolid, clSuitePrimary, sikTarget);
  LabelAt(S, 'O G-code sai relativo ao ponto de zero. No MultiCNC leve a fresa a esse ponto da peca presa na mesa, use Zero Workpiece e confira com Frame (Test).',
    16, 748, 290, 92);
end;

procedure TMakeRouterForm.BuildDesignPage(S: TScrollBox);
var B: TSuiteButton;
begin
  B := Button(S, 'Retangulo', 16, 56, 140, sikRect, @AddShapeClick); B.Tag := Ord(skRect);
  B := Button(S, 'Circulo', 166, 56, 140, sikCircle, @AddShapeClick); B.Tag := Ord(skCircle);
  B := Button(S, 'Elipse', 16, 98, 140, sikCircle, @AddShapeClick); B.Tag := Ord(skEllipse);
  B := Button(S, 'Poligono', 166, 98, 140, sikPolygon, @AddShapeClick); B.Tag := Ord(skPolygon);
  B := Button(S, 'Estrela', 16, 140, 140, sikWand, @AddShapeClick); B.Tag := Ord(skStar);
  B := Button(S, 'Texto', 166, 140, 140, sikText, @AddShapeClick); B.Tag := Ord(skText);
  Button(S, 'Duplicar', 16, 190, 140, sikCopy, @DuplicateClick);
  Button(S, 'Excluir', 166, 190, 140, sikTrash, @DeleteShapesClick);
  ShTitle := LabelAt(S, 'FORMA SELECIONADA', 16, 240, 290, 18);
  ShTitle.Font.Style := [fsBold];
  ShName := Field(S, 'Nome', '', 262);
  ShX := Field(S, 'Centro X (texto: inicio) (mm)', '0', 318);
  ShY := Field(S, 'Centro Y (texto: base) (mm)', '0', 374);
  ShW := Field(S, 'Largura (mm)', '0', 430);
  ShH := Field(S, 'Altura (mm)', '0', 486);
  ShRad := Field(S, 'Raio (mm)', '0', 542);
  ShCorner := Field(S, 'Raio dos cantos (mm)', '0', 598);
  ShSides := Field(S, 'Lados / pontas', '6', 654);
  ShInner := Field(S, 'Raio interno da estrela (%)', '50', 710);
  ShRot := Field(S, 'Rotacao (graus)', '0', 766);
  ShText := Field(S, 'Texto', '', 822);
  ShTextH := Field(S, 'Altura do texto (mm)', '20', 878);
  Button(S, 'Aplicar', 16, 940, 290, sikTarget, @ShapeApply).SetLook(sbsSolid, clSuitePrimary, sikTarget);
  Button(S, 'Centralizar no material', 16, 982, 290, sikFit, @CenterShapeClick);
  LabelAt(S, 'Clique na forma para selecionar (Shift soma), arraste para mover (passo de 1 mm; Alt = livre). Delete exclui. O texto usa fonte de traco, para gravacao na linha.',
    16, 1030, 290, 90);
end;

procedure TMakeRouterForm.BuildReliefPage(S: TScrollBox);
begin
  LabelAt(S, 'Relevo 3D (mapa de alturas: domo, rampa, extrusao, revolucao, imagem e STL) com desbaste e acabamento 3D entra na fase 6 do MakeRouter.',
    16, 56, 290, 90);
  LabelAt(S, 'Nesta versao: perfil, bolsao, furacao e gravacao (2,5D). O plano esta em makerouter/docs/TAREFA.md.',
    16, 156, 290, 70);
end;

procedure TMakeRouterForm.BuildPathsPage(S: TScrollBox);
var B: TSuiteButton; K: TMRToolKind; Sd: TMRProfileSide; Dr: TMRCutDirection;
begin
  PathList := TCheckListBox.Create(Self);
  PathList.Parent := S;
  PathList.SetBounds(16, 52, 290, 150);
  PathList.OnClick := @PathListClick;
  PathList.OnClickCheck := @PathListClick;
  PathList.OnItemClick := @PathCheck;
  B := Button(S, 'Perfil', 16, 210, 140, sikRect, @AddPathClick); B.Tag := Ord(tpProfile);
  B := Button(S, 'Bolsao', 166, 210, 140, sikLayers, @AddPathClick); B.Tag := Ord(tpPocket);
  B := Button(S, 'Furacao', 16, 252, 140, sikTarget, @AddPathClick); B.Tag := Ord(tpDrill);
  B := Button(S, 'Gravacao', 166, 252, 140, sikPen, @AddPathClick); B.Tag := Ord(tpEngrave);
  Button(S, 'Excluir', 16, 294, 92, sikTrash, @DeletePathClick);
  Button(S, 'Subir', 114, 294, 92, sikArrowUp, @PathUpClick);
  Button(S, 'Descer', 212, 294, 94, sikArrowDown, @PathDownClick);
  TpTitle := LabelAt(S, 'PERCURSO SELECIONADO', 16, 344, 290, 18);
  TpTitle.Font.Style := [fsBold];
  TpName := Field(S, 'Nome', '', 366);
  TpTool := Combo(S, 'Ferramenta', 422);
  TpDepth := Field(S, 'Profundidade final (mm)', '3', 480);
  TpStart := Field(S, 'Comeca abaixo do topo (mm)', '0', 536);
  TpSide := Combo(S, 'Lado do perfil', 592);
  for Sd := Low(TMRProfileSide) to High(TMRProfileSide) do TpSide.Items.Add(MR_SIDE_NAMES[Sd]);
  TpDir := Combo(S, 'Sentido de corte', 650);
  for Dr := Low(TMRCutDirection) to High(TMRCutDirection) do TpDir.Items.Add(MR_DIR_NAMES[Dr]);
  TpTabs := Field(S, 'Pontes por contorno (0 = sem)', '0', 708);
  TpTabW := Field(S, 'Largura da ponte (mm)', '6', 764);
  TpTabH := Field(S, 'Altura da ponte (mm)', '2', 820);
  TpRamp := TCheckBox.Create(Self);
  TpRamp.Parent := S; TpRamp.SetBounds(16, 880, 290, 24);
  TpRamp.Caption := 'Entrada em rampa'; TpRamp.Checked := True;
  TpAllow := Field(S, 'Sobremetal (mm)', '0', 908);
  TpPeck := Field(S, 'Bicada da furacao (mm, 0 = direto)', '0', 964);
  Button(S, 'Usar as formas selecionadas', 16, 1026, 290, sikPointer, @UseSelectionClick);
  Button(S, 'Aplicar', 16, 1068, 140, sikTarget, @PathApply);
  Button(S, 'Calcular', 166, 1068, 140, sikFlame, @CalculateClick).SetLook(sbsSolid, clSuitePrimary, sikFlame);
  LabelAt(S, 'FERRAMENTA (da lista acima)', 16, 1122, 290, 18).Font.Style := [fsBold];
  TpTool.OnChange := @ToolBoxChange;
  TlName := Field(S, 'Nome', '', 1146);
  TlKind := Combo(S, 'Tipo', 1202);
  for K := Low(TMRToolKind) to High(TMRToolKind) do TlKind.Items.Add(MR_TOOLKIND_NAMES[K]);
  TlDia := Field(S, 'Diametro (mm)', '6', 1260);
  TlAngle := Field(S, 'Angulo (V e gravacao, graus)', '60', 1316);
  TlStepDown := Field(S, 'Profundidade por passada (mm)', '3', 1372);
  TlStepOver := Field(S, 'Passo lateral do bolsao (%)', '40', 1428);
  TlFeed := Field(S, 'Avanco (mm/min)', '1500', 1484);
  TlPlunge := Field(S, 'Mergulho (mm/min)', '400', 1540);
  TlRPM := Field(S, 'Rotacao (RPM)', '18000', 1596);
  Button(S, 'Salvar ferramenta', 16, 1658, 140, sikSave, @ToolSaveClick);
  Button(S, 'Nova ferramenta', 166, 1658, 140, sikNew, @ToolNewClick);
  LabelAt(S, 'Os valores padrao sao exemplos. Avanco, mergulho e rotacao dependem da maquina, da fresa e da madeira: teste num retalho.',
    16, 1704, 290, 70);
end;

procedure TMakeRouterForm.BuildSimPage(S: TScrollBox);
begin
  Button(S, 'Simular todos', 16, 56, 290, sikPlay, @SimAllClick).SetLook(sbsSolid, clSuitePrimary, sikPlay);
  Button(S, 'Simular percurso selecionado', 16, 98, 290, sikPlay, @SimOneClick);
  Button(S, 'Voltar ao desenho', 16, 140, 290, sikPen, @DesignViewClick);
  SimSummary := LabelAt(S, 'Simule para ver a remocao do material.', 16, 190, 290, 220);
end;

procedure TMakeRouterForm.BuildOutputPage(S: TScrollBox);
begin
  State := TSuiteBadge.Create(Self);
  State.Parent := S; State.SetBounds(16, 56, 260, 32);
  State.Caption := 'Aguardando validacao'; State.DotColor := clSuiteWarning;
  SingleFile := TCheckBox.Create(Self);
  SingleFile.Parent := S; SingleFile.SetBounds(16, 100, 290, 24);
  SingleFile.Caption := 'Arquivo unico (pausa M0 na troca)';
  SingleFile.OnChange := @ViewOptionsChanged;
  OutSummary := LabelAt(S, 'Valide para ver os programas.', 16, 132, 290, 170);
  Log := TMemo.Create(Self);
  Log.Parent := S; Log.SetBounds(16, 310, 290, 170);
  Log.ReadOnly := True; Log.ScrollBars := ssAutoVertical;
  Button(S, 'Validar agora', 16, 492, 290, sikTests, @ValidateClick);
  Button(S, 'Gerar G-code...', 16, 534, 290, sikExport, @ExportClick).SetLook(sbsSolid, clSuitePrimary, sikExport);
  LabelAt(S, 'Um arquivo por ferramenta, na ordem da lista. Cabecalho com o ponto de zero, o material e a caixa do trabalho; o MultiCNC abre em CNC Router.',
    16, 582, 290, 80);
end;

{ ---------------- utilitarios ---------------- }

function TMakeRouterForm.Num(E: TEdit; const What: string): Double;
begin
  if not TryParseFloat(E.Text, Result) or IsNan(Result) or IsInfinite(Result) or (Abs(Result) > 1e7) then
    raise Exception.Create(What + ': informe um numero valido');
end;

function TMakeRouterForm.IntOf(E: TEdit; const What: string; Lo, Hi: Integer): Integer;
begin
  if not TryStrToInt(Trim(E.Text), Result) or (Result < Lo) or (Result > Hi) then
    raise Exception.Create(Format('%s: use %d a %d', [What, Lo, Hi]));
end;

procedure TMakeRouterForm.ShowError(E: Exception);
begin
  Status.Caption := E.Message;
  Log.Lines.Add(E.Message);
  State.Caption := 'Verifique o trabalho';
  State.DotColor := clSuiteDanger;
end;

procedure TMakeRouterForm.Changed(const Msg: string);
begin
  FExportedFile := '';
  SendButton.Enabled := False;
  State.Caption := 'Alteracoes pendentes';
  State.DotColor := clSuiteWarning;
  if Msg <> '' then Status.Caption := Msg;
  if View.Mode = vmSim then View.Mode := vmDesign;
  RefreshInfo;
  View.Invalidate;
end;

procedure TMakeRouterForm.ResizeUI(Sender: TObject);
begin
  if FooterPanel = nil then Exit;
  SendButton.Left := FooterPanel.ClientWidth - SendButton.Width - 18;
  ExportButton.Left := SendButton.Left - ExportButton.Width - 10;
  ValidateButton.Left := ExportButton.Left - ValidateButton.Width - 10;
  Status.Width := Max(120, ValidateButton.Left - 30);
  Coords.Width := Status.Width;
end;

procedure TMakeRouterForm.ShowUI(Sender: TObject);
begin
  ResizeUI(Sender);
  View.FitMaterial;
end;

procedure TMakeRouterForm.ShowStep(N: Integer);
var I: Integer;
begin
  N := EnsureRange(N, 0, 5);
  Pages.ActivePageIndex := N;
  for I := 0 to 5 do
    if I = N then Nav[I].SetLook(sbsSolid, clSuitePrimary)
    else Nav[I].SetLook(sbsSoft, clSuitePrimary);
end;

procedure TMakeRouterForm.SelectShape(AId: Integer);
begin
  View.SelectOnly(AId);
  RefreshShapeList;
end;

procedure TMakeRouterForm.NavClick(Sender: TObject);
begin
  ShowStep(TSuiteButton(Sender).Tag);
end;

procedure TMakeRouterForm.RefreshInfo;
var Cut, Rapid, C, R: Double; I: Integer;
begin
  Cut := 0;
  for I := 0 to P.ToolpathCount - 1 do
    if P.Toolpaths[I].Enabled then
    begin
      MRMovesLength(P.Toolpaths[I].Moves, C, R);
      Cut := Cut + C;
    end;
  Info.Caption := Format('%s' + LineEnding + 'Material %s x %s x %s mm' + LineEnding +
    '%d formas, %d percursos' + LineEnding + 'Corte calculado %.0f mm',
    [P.Name, FmtN(P.Material.Width), FmtN(P.Material.Height), FmtN(P.Material.Thickness),
     P.ShapeCount, P.ToolpathCount, Cut]);
  if Rapid = 0 then;
end;

{ ---------------- material ---------------- }

procedure TMakeRouterForm.LoadMaterialEditor;
var D: TMRDatumXY;
begin
  FUpdating := True;
  try
    MatW.Text := FmtN(P.Material.Width);
    MatH.Text := FmtN(P.Material.Height);
    MatT.Text := FmtN(P.Material.Thickness);
    MatSafe.Text := FmtN(P.Material.SafeZ);
    MatTravel.Text := FmtN(P.Material.TravelZ);
    MatSpin.Text := FmtN(P.Material.SpinUpSeconds);
    DatumZBox.ItemIndex := Ord(P.Material.DatumZ);
    WoodBox.ItemIndex := P.Material.Visual;
    for D := Low(TMRDatumXY) to High(TMRDatumXY) do
      if D = P.Material.DatumXY then DatumButtons[D].SetLook(sbsSolid, clSuitePrimary, sikTarget)
      else DatumButtons[D].SetLook(sbsSoft, clSuitePrimary, sikTarget);
  finally
    FUpdating := False;
  end;
end;

procedure TMakeRouterForm.DatumClick(Sender: TObject);
begin
  P.Material.DatumXY := TMRDatumXY(TSuiteButton(Sender).Tag);
  P.Modified := True;
  LoadMaterialEditor;
  Changed('Ponto de zero: ' + MR_DATUM_NAMES[P.Material.DatumXY] + '.');
end;

procedure TMakeRouterForm.MaterialApply(Sender: TObject);
var M: TMRMaterial; Errors: TStringList;
begin
  Errors := TStringList.Create;
  try
    try
      M := P.Material;
      M.Width := Num(MatW, 'Largura'); M.Height := Num(MatH, 'Altura');
      M.Thickness := Num(MatT, 'Espessura');
      M.SafeZ := Num(MatSafe, 'Z seguro'); M.TravelZ := Num(MatTravel, 'Z de deslocamento');
      M.SpinUpSeconds := Num(MatSpin, 'Espera do spindle');
      M.DatumZ := TMRDatumZ(Max(0, DatumZBox.ItemIndex));
      M.Visual := Max(0, WoodBox.ItemIndex);
      if not MRValidateMaterial(M, Errors) then raise Exception.Create(Errors[0]);
      P.Material := M;
      P.MarkAllDirty;
      P.Modified := True;
      View.FitMaterial;
      Changed('Material aplicado. Recalcule os percursos.');
      RefreshPathList;
    except
      on E: Exception do ShowError(E);
    end;
  finally
    Errors.Free;
  end;
end;

{ ---------------- formas ---------------- }

function TMakeRouterForm.SelectedShape: TMRShape;
var Ids: TMRIds;
begin
  Ids := View.SelectedIds;
  if Length(Ids) = 1 then Result := P.ShapeById(Ids[0]) else Result := nil;
end;

procedure TMakeRouterForm.RefreshShapeList;
var I: Integer;
begin
  FUpdating := True;
  try
    ShapeList.Items.BeginUpdate;
    ShapeList.Items.Clear;
    for I := 0 to P.ShapeCount - 1 do
    begin
      ShapeList.Items.Add(P.Shapes[I].Caption);
      ShapeList.Selected[I] := View.IsSelected(P.Shapes[I].Id);
    end;
    ShapeList.Items.EndUpdate;
  finally
    FUpdating := False;
  end;
  LoadShapeEditor;
  RefreshInfo;
end;

procedure TMakeRouterForm.LoadShapeEditor;
var S: TMRShape;
  procedure En(E: TEdit; On: Boolean);
  begin
    E.Enabled := On;
  end;
begin
  S := SelectedShape;
  FUpdating := True;
  try
    if S = nil then
    begin
      if View.SelectedCount > 1 then
        ShTitle.Caption := Format('%d FORMAS SELECIONADAS', [View.SelectedCount])
      else ShTitle.Caption := 'FORMA SELECIONADA (nenhuma)';
      Exit;
    end;
    ShTitle.Caption := 'FORMA: ' + UpperCase(S.KindName);
    ShName.Text := S.Name;
    ShX.Text := FmtN(S.X); ShY.Text := FmtN(S.Y);
    ShW.Text := FmtN(S.W); ShH.Text := FmtN(S.H);
    ShRad.Text := FmtN(S.Radius); ShCorner.Text := FmtN(S.Corner);
    ShSides.Text := IntToStr(S.Sides); ShInner.Text := FmtN(S.Inner * 100);
    ShRot.Text := FmtN(S.Rotation);
    ShText.Text := S.Text; ShTextH.Text := FmtN(S.TextHeight);
    En(ShW, S.Kind in [skRect, skEllipse]); En(ShH, S.Kind in [skRect, skEllipse]);
    En(ShRad, S.Kind in [skCircle, skPolygon, skStar]);
    En(ShCorner, S.Kind = skRect);
    En(ShSides, S.Kind in [skPolygon, skStar]);
    En(ShInner, S.Kind = skStar);
    En(ShText, S.Kind = skText); En(ShTextH, S.Kind = skText);
    En(ShRot, S.Kind <> skPolyline);
  finally
    FUpdating := False;
  end;
end;

procedure TMakeRouterForm.AddShapeClick(Sender: TObject);
var S: TMRShape;
begin
  S := TMRShape.Create(TMRShapeKind(TSuiteButton(Sender).Tag));
  S.X := P.Material.Width / 2;
  S.Y := P.Material.Height / 2;
  S.W := Min(100, P.Material.Width / 2); S.H := Min(60, P.Material.Height / 2);
  S.Radius := Min(30, Min(P.Material.Width, P.Material.Height) / 4);
  if S.Kind = skStar then S.Sides := 5;
  if S.Kind = skText then
  begin
    S.Text := 'TEXTO';
    S.TextHeight := Max(5, Min(30, P.Material.Height / 6));
    S.X := P.Material.Width / 4;
  end;
  P.AddShape(S);
  View.SelectOnly(S.Id);
  RefreshShapeList;
  Changed(S.KindName + ' adicionado. Edite as medidas ou arraste na vista.');
end;

procedure TMakeRouterForm.DuplicateClick(Sender: TObject);
var Ids: TMRIds; I: Integer; S, N: TMRShape; NewIds: TMRIds;
begin
  Ids := View.SelectedIds;
  NewIds := nil;
  for I := 0 to High(Ids) do
  begin
    S := P.ShapeById(Ids[I]);
    if S = nil then Continue;
    N := TMRShape.Create(S.Kind);
    N.Assign(S);
    if N.Name <> '' then N.Name := N.Name + ' (copia)';
    N.MoveBy(10, -10);
    P.AddShape(N);
    SetLength(NewIds, Length(NewIds) + 1);
    NewIds[High(NewIds)] := N.Id;
  end;
  View.ClearSelection;
  for I := 0 to High(NewIds) do
    if I = 0 then View.SelectOnly(NewIds[I]);
  RefreshShapeList;
  Changed(Format('%d forma(s) duplicada(s).', [Length(NewIds)]));
end;

procedure TMakeRouterForm.DeleteShapesClick(Sender: TObject);
var Ids: TMRIds; I: Integer;
begin
  Ids := View.SelectedIds;
  if Length(Ids) = 0 then Exit;
  for I := 0 to High(Ids) do P.DeleteShape(Ids[I]);
  View.ClearSelection;
  RefreshShapeList;
  RefreshPathList;
  Changed(Format('%d forma(s) excluida(s).', [Length(Ids)]));
end;

procedure TMakeRouterForm.ShapeApply(Sender: TObject);
var S: TMRShape; T: TMRShape;
begin
  S := SelectedShape;
  if S = nil then begin Status.Caption := 'Selecione uma forma.'; Exit; end;
  T := TMRShape.Create(S.Kind);
  try
    try
      T.Assign(S);
      T.Name := Trim(ShName.Text);
      T.X := Num(ShX, 'X'); T.Y := Num(ShY, 'Y');
      if ShW.Enabled then T.W := Num(ShW, 'Largura');
      if ShH.Enabled then T.H := Num(ShH, 'Altura');
      if ShRad.Enabled then T.Radius := Num(ShRad, 'Raio');
      if ShCorner.Enabled then T.Corner := Num(ShCorner, 'Raio dos cantos');
      if ShSides.Enabled then T.Sides := IntOf(ShSides, 'Lados', 3, 200);
      if ShInner.Enabled then T.Inner := Num(ShInner, 'Raio interno') / 100;
      if ShRot.Enabled then T.Rotation := Num(ShRot, 'Rotacao');
      if ShText.Enabled then T.Text := ShText.Text;
      if ShTextH.Enabled then T.TextHeight := Num(ShTextH, 'Altura do texto');
      if (T.Kind in [skRect, skEllipse]) and ((T.W <= 0) or (T.H <= 0)) then
        raise Exception.Create('Largura e altura devem ser positivas');
      if (T.Kind in [skCircle, skPolygon, skStar]) and (T.Radius <= 0) then
        raise Exception.Create('Raio deve ser positivo');
      if (T.Kind = skText) and ((Trim(T.Text) = '') or (T.TextHeight <= 0)) then
        raise Exception.Create('Informe o texto e uma altura positiva');
      if (T.Kind = skStar) and ((T.Inner <= 0) or (T.Inner >= 1)) then
        raise Exception.Create('Raio interno da estrela entre 1 e 99 %');
      if T.Corner < 0 then raise Exception.Create('Raio dos cantos >= 0');
      S.Assign(T);
      P.ShapeChanged(S.Id);
      RefreshShapeList;
      RefreshPathList;
      Changed('Forma alterada. Percursos que a usam precisam ser recalculados.');
    except
      on E: Exception do ShowError(E);
    end;
  finally
    T.Free;
  end;
end;

procedure TMakeRouterForm.CenterShapeClick(Sender: TObject);
var Ids: TMRIds; I: Integer; B, R: TLPRect; S: TMRShape;
begin
  Ids := View.SelectedIds;
  if Length(Ids) = 0 then Exit;
  B := LPEmptyRect;
  for I := 0 to High(Ids) do
  begin
    S := P.ShapeById(Ids[I]);
    if S <> nil then begin R := S.Bounds; LPRectIncludeRect(B, R); end;
  end;
  if not B.Valid then Exit;
  ViewMoveShapes(nil, P.Material.Width / 2 - (B.MinX + B.MaxX) / 2,
    P.Material.Height / 2 - (B.MinY + B.MaxY) / 2);
end;

procedure TMakeRouterForm.ShapeListClick(Sender: TObject);
var I: Integer; First: Boolean;
begin
  if FUpdating then Exit;
  View.ClearSelection;
  First := True;
  for I := 0 to ShapeList.Items.Count - 1 do
    if ShapeList.Selected[I] and (I < P.ShapeCount) then
    begin
      if First then View.SelectOnly(P.Shapes[I].Id)
      else
      begin
        { soma a selecao: usa o mesmo caminho do Shift-clique }
        View.SelectOnly(P.Shapes[I].Id);
      end;
      First := False;
    end;
  LoadShapeEditor;
  if Pages.ActivePageIndex <> 3 then ShowStep(1);
end;

procedure TMakeRouterForm.ViewSelect(Sender: TObject);
begin
  RefreshShapeList;
end;

procedure TMakeRouterForm.ViewMoveShapes(Sender: TObject; DX, DY: Double);
var Ids: TMRIds; I: Integer; S: TMRShape;
begin
  Ids := View.SelectedIds;
  for I := 0 to High(Ids) do
  begin
    S := P.ShapeById(Ids[I]);
    if S = nil then Continue;
    S.MoveBy(DX, DY);
    P.ShapeChanged(S.Id);
  end;
  LoadShapeEditor;
  RefreshPathList;
  Changed(Format('Movido %s; %s mm.', [FmtN(DX), FmtN(DY)]));
end;

procedure TMakeRouterForm.ViewCursor(Sender: TObject; X, Y: Double);
var D: TLPPoint;
begin
  D := P.DatumPoint;
  Coords.Caption := Format('X %.1f  Y %.1f mm (no G-code: X %.1f  Y %.1f)', [X, Y, X - D.X, Y - D.Y], InvariantFS);
end;

{ ---------------- ferramentas ---------------- }

procedure TMakeRouterForm.RefreshToolBox;
var I, Keep: Integer;
begin
  Keep := TpTool.ItemIndex;
  FUpdating := True;
  try
    TpTool.Items.Clear;
    for I := 0 to High(P.Tools) do
      TpTool.Items.Add(Format('T%d  %s', [I + 1, P.Tools[I].Name]));
    if (Keep >= 0) and (Keep < TpTool.Items.Count) then TpTool.ItemIndex := Keep
    else if TpTool.Items.Count > 0 then TpTool.ItemIndex := 0;
  finally
    FUpdating := False;
  end;
end;

procedure TMakeRouterForm.LoadToolEditor;
var T: TMRTool;
begin
  if (TpTool.ItemIndex < 0) or (TpTool.ItemIndex > High(P.Tools)) then Exit;
  T := P.Tools[TpTool.ItemIndex];
  FUpdating := True;
  try
    TlName.Text := T.Name; TlKind.ItemIndex := Ord(T.Kind);
    TlDia.Text := FmtN(T.Diameter); TlAngle.Text := FmtN(T.Angle);
    TlStepDown.Text := FmtN(T.StepDown); TlStepOver.Text := FmtN(T.StepOver);
    TlFeed.Text := FmtN(T.Feed); TlPlunge.Text := FmtN(T.Plunge); TlRPM.Text := FmtN(T.RPM);
  finally
    FUpdating := False;
  end;
end;

procedure TMakeRouterForm.ToolBoxChange(Sender: TObject);
begin
  if FUpdating then Exit;
  LoadToolEditor;
end;

procedure TMakeRouterForm.ToolSaveClick(Sender: TObject);
var T: TMRTool; Errors: TStringList; I: Integer;
begin
  I := TpTool.ItemIndex;
  if (I < 0) or (I > High(P.Tools)) then Exit;
  Errors := TStringList.Create;
  try
    try
      T := P.Tools[I];
      T.Name := Trim(TlName.Text);
      T.Kind := TMRToolKind(Max(0, TlKind.ItemIndex));
      T.Diameter := Num(TlDia, 'Diametro'); T.Angle := Num(TlAngle, 'Angulo');
      T.StepDown := Num(TlStepDown, 'Profundidade por passada');
      T.StepOver := Num(TlStepOver, 'Passo lateral');
      T.Feed := Num(TlFeed, 'Avanco'); T.Plunge := Num(TlPlunge, 'Mergulho');
      T.RPM := Num(TlRPM, 'Rotacao');
      if not MRValidateTool(T, Errors) then raise Exception.Create(Errors[0]);
      P.Tools[I] := T;
      for I := 0 to P.ToolpathCount - 1 do
        if P.Toolpaths[I].Tool = TpTool.ItemIndex then P.Toolpaths[I].Dirty := True;
      P.Modified := True;
      RefreshToolBox;
      RefreshPathList;
      Changed('Ferramenta salva. Percursos com ela precisam ser recalculados.');
    except
      on E: Exception do ShowError(E);
    end;
  finally
    Errors.Free;
  end;
end;

procedure TMakeRouterForm.ToolNewClick(Sender: TObject);
begin
  SetLength(P.Tools, Length(P.Tools) + 1);
  P.Tools[High(P.Tools)] := MRDefaultTool(tkEndMill);
  P.Tools[High(P.Tools)].Name := 'Nova fresa ' + IntToStr(Length(P.Tools));
  RefreshToolBox;
  TpTool.ItemIndex := High(P.Tools);
  LoadToolEditor;
  Status.Caption := 'Ferramenta criada: ajuste e salve.';
end;

{ ---------------- percursos ---------------- }

function TMakeRouterForm.SelectedPath: TMRToolpath;
begin
  if (PathList.ItemIndex >= 0) and (PathList.ItemIndex < P.ToolpathCount) then
    Result := P.Toolpaths[PathList.ItemIndex]
  else Result := nil;
end;

procedure TMakeRouterForm.RefreshPathList;
var I, Keep: Integer; T: TMRToolpath; S: string;
begin
  Keep := PathList.ItemIndex;
  FUpdating := True;
  try
    PathList.Items.BeginUpdate;
    PathList.Items.Clear;
    for I := 0 to P.ToolpathCount - 1 do
    begin
      T := P.Toolpaths[I];
      S := Format('%s  [T%d, %s mm]', [T.Caption, T.Tool + 1, FmtN(T.Depth)]);
      PathList.Items.Add(S);
      PathList.Checked[I] := T.Enabled;
    end;
    PathList.Items.EndUpdate;
    if (Keep >= 0) and (Keep < PathList.Items.Count) then PathList.ItemIndex := Keep
    else if PathList.Items.Count > 0 then PathList.ItemIndex := 0;
  finally
    FUpdating := False;
  end;
  View.ActiveToolpath := PathList.ItemIndex;
  LoadPathEditor;
  RefreshInfo;
end;

procedure TMakeRouterForm.LoadPathEditor;
var T: TMRToolpath;
begin
  T := SelectedPath;
  FUpdating := True;
  try
    if T = nil then begin TpTitle.Caption := 'PERCURSO SELECIONADO (nenhum)'; Exit; end;
    TpTitle.Caption := Format('PERCURSO: %s (%d formas)', [UpperCase(MR_TOOLPATH_NAMES[T.Kind]), Length(T.ShapeIds)]);
    TpName.Text := T.Name;
    if T.Tool < TpTool.Items.Count then TpTool.ItemIndex := T.Tool;
    TpDepth.Text := FmtN(T.Depth); TpStart.Text := FmtN(T.StartDepth);
    TpSide.ItemIndex := Ord(T.Side); TpDir.ItemIndex := Ord(T.Direction);
    TpTabs.Text := IntToStr(T.Tabs); TpTabW.Text := FmtN(T.TabWidth); TpTabH.Text := FmtN(T.TabHeight);
    TpRamp.Checked := T.Ramp; TpAllow.Text := FmtN(T.Allowance); TpPeck.Text := FmtN(T.PeckDepth);
    TpSide.Enabled := T.Kind = tpProfile; TpTabs.Enabled := T.Kind = tpProfile;
    TpTabW.Enabled := T.Kind = tpProfile; TpTabH.Enabled := T.Kind = tpProfile;
    TpDir.Enabled := T.Kind in [tpProfile, tpPocket];
    TpRamp.Enabled := T.Kind in [tpProfile, tpPocket];
    TpAllow.Enabled := T.Kind in [tpProfile, tpPocket];
    TpPeck.Enabled := T.Kind = tpDrill;
  finally
    FUpdating := False;
  end;
  LoadToolEditor;
end;

procedure TMakeRouterForm.AddPathClick(Sender: TObject);
var T: TMRToolpath; Ids: TMRIds; I: Integer; K: TMRToolpathKind;
begin
  K := TMRToolpathKind(TSuiteButton(Sender).Tag);
  Ids := View.SelectedIds;
  if Length(Ids) = 0 then
  begin
    Status.Caption := 'Selecione as formas na vista (Shift soma) e depois crie o percurso.';
    Exit;
  end;
  T := TMRToolpath.Create(K);
  T.Name := MR_TOOLPATH_NAMES[K] + ' ' + IntToStr(P.ToolpathCount + 1);
  SetLength(T.ShapeIds, Length(Ids));
  for I := 0 to High(Ids) do T.ShapeIds[I] := Ids[I];
  case K of
    tpProfile:
      begin
        T.Tool := 0; T.Depth := P.Material.Thickness + 0.5; T.Tabs := 4;
        T.TabWidth := 8; T.TabHeight := Min(3, P.Material.Thickness / 3);
      end;
    tpPocket: begin T.Tool := 0; T.Depth := Min(6, P.Material.Thickness / 2); end;
    tpDrill:
      begin
        T.Tool := Max(0, P.ToolIndexByName('Broca 5 mm'));
        T.Depth := P.Material.Thickness + 0.5; T.PeckDepth := 6;
      end;
    tpEngrave:
      begin
        T.Tool := Max(0, P.ToolIndexByName('Gravador 30 graus'));
        T.Depth := 1;
      end;
  end;
  P.AddToolpath(T);
  RefreshPathList;
  PathList.ItemIndex := P.ToolpathCount - 1;
  View.ActiveToolpath := PathList.ItemIndex;
  LoadPathEditor;
  ShowStep(3);
  Changed(T.Name + ' criado com ' + IntToStr(Length(Ids)) + ' forma(s). Ajuste e calcule.');
end;

procedure TMakeRouterForm.DeletePathClick(Sender: TObject);
var I: Integer;
begin
  I := PathList.ItemIndex;
  if I < 0 then Exit;
  P.DeleteToolpath(I);
  RefreshPathList;
  Changed('Percurso excluido.');
end;

procedure TMakeRouterForm.PathUpClick(Sender: TObject);
var I: Integer;
begin
  I := PathList.ItemIndex;
  if I <= 0 then Exit;
  P.MoveToolpath(I, -1);
  RefreshPathList;
  PathList.ItemIndex := I - 1;
  LoadPathEditor;
  Changed('Ordem dos percursos alterada.');
end;

procedure TMakeRouterForm.PathDownClick(Sender: TObject);
var I: Integer;
begin
  I := PathList.ItemIndex;
  if (I < 0) or (I >= P.ToolpathCount - 1) then Exit;
  P.MoveToolpath(I, 1);
  RefreshPathList;
  PathList.ItemIndex := I + 1;
  LoadPathEditor;
  Changed('Ordem dos percursos alterada.');
end;

procedure TMakeRouterForm.PathListClick(Sender: TObject);
var I: Integer;
begin
  if FUpdating then Exit;
  for I := 0 to Min(PathList.Items.Count, P.ToolpathCount) - 1 do
    P.Toolpaths[I].Enabled := PathList.Checked[I];
  View.ActiveToolpath := PathList.ItemIndex;
  LoadPathEditor;
  View.Invalidate;
end;

procedure TMakeRouterForm.PathCheck(Sender: TObject; Index: Integer);
begin
  PathListClick(Sender);
end;

procedure TMakeRouterForm.PathApply(Sender: TObject);
var T: TMRToolpath; Depth, Start, TW, TH, Al, Pk: Double; Tabs: Integer;
begin
  T := SelectedPath;
  if T = nil then Exit;
  try
    Depth := Num(TpDepth, 'Profundidade'); Start := Num(TpStart, 'Inicio');
    Tabs := IntOf(TpTabs, 'Pontes', 0, 100);
    TW := Num(TpTabW, 'Largura da ponte'); TH := Num(TpTabH, 'Altura da ponte');
    Al := Num(TpAllow, 'Sobremetal'); Pk := Num(TpPeck, 'Bicada');
    if Depth <= 0 then raise Exception.Create('Profundidade deve ser positiva');
    if (Start < 0) or (Start >= Depth) then raise Exception.Create('Inicio entre 0 e a profundidade');
    if (Al < 0) or (Pk < 0) or (TW < 0) or (TH < 0) then raise Exception.Create('Valores negativos nao sao aceitos');
    T.Name := Trim(TpName.Text);
    if T.Name = '' then T.Name := MR_TOOLPATH_NAMES[T.Kind];
    T.Tool := Max(0, TpTool.ItemIndex);
    T.Depth := Depth; T.StartDepth := Start;
    T.Side := TMRProfileSide(Max(0, TpSide.ItemIndex));
    T.Direction := TMRCutDirection(Max(0, TpDir.ItemIndex));
    T.Tabs := Tabs; T.TabWidth := TW; T.TabHeight := TH;
    T.Ramp := TpRamp.Checked; T.Allowance := Al; T.PeckDepth := Pk;
    T.Dirty := True;
    P.Modified := True;
    RefreshPathList;
    Changed(T.Name + ' alterado. Calcule de novo.');
  except
    on E: Exception do ShowError(E);
  end;
end;

procedure TMakeRouterForm.UseSelectionClick(Sender: TObject);
var T: TMRToolpath; Ids: TMRIds; I: Integer;
begin
  T := SelectedPath;
  Ids := View.SelectedIds;
  if (T = nil) or (Length(Ids) = 0) then
  begin
    Status.Caption := 'Selecione um percurso e as formas na vista.';
    Exit;
  end;
  SetLength(T.ShapeIds, Length(Ids));
  for I := 0 to High(Ids) do T.ShapeIds[I] := Ids[I];
  T.Dirty := True;
  RefreshPathList;
  Changed(Format('%s agora usa %d forma(s).', [T.Name, Length(Ids)]));
end;

function TMakeRouterForm.CalculateAll: Integer;
var Errors: TStringList;
begin
  Errors := TStringList.Create;
  try
    Result := MRGenerateAll(P, Errors);
    Log.Lines.AddStrings(Errors);
    RefreshPathList;
    if Result > 0 then
    begin
      Status.Caption := Errors[0];
      State.Caption := 'Corrigir percursos'; State.DotColor := clSuiteDanger;
    end
    else
    begin
      Status.Caption := 'Percursos calculados. Confira na vista e simule.';
      State.Caption := 'Percursos calculados'; State.DotColor := clSuiteInfo;
    end;
    View.Mode := vmDesign;
    View.Invalidate;
  finally
    Errors.Free;
  end;
end;

procedure TMakeRouterForm.CalculateClick(Sender: TObject);
begin
  CalculateAll;
end;

{ ---------------- simulacao ---------------- }

procedure TMakeRouterForm.RunSimulation(OnlyIndex: Integer);
var I, PW, PH: Integer; T: TMRToolpath; Errors: TStringList; Px: TMRPixels; Scale: Double;
  BaseNote: string;
begin
  Errors := TStringList.Create;
  try
    if MRGenerateAll(P, Errors) > 0 then raise Exception.Create(Errors[0]);
    FStock.Init(P.Material);
    for I := 0 to P.ToolpathCount - 1 do
    begin
      T := P.Toolpaths[I];
      if not T.Enabled or (Length(T.Moves) = 0) then Continue;
      if (OnlyIndex >= 0) and (I <> OnlyIndex) then Continue;
      FStock.Apply(T.Moves, P.Tools[T.Tool]);
    end;
    Scale := Min(1400 / Max(1, P.Material.Width), 1000 / Max(1, P.Material.Height));
    PW := Max(10, Round(P.Material.Width * Scale));
    PH := Max(10, Round(P.Material.Height * Scale));
    Px := FStock.Render(PW, PH, P.Material.Visual);
    View.SetSimPixels(Px, PW, PH);
    if FStock.BelowBase > 0 then
      BaseNote := 'Corte passa da base do material (normal no recorte: base de sacrificio).'
    else BaseNote := 'Nenhum corte abaixo da base.';
    View.Mode := vmSim;
    View.Invalidate;
    SimSummary.Caption := Format('Volume removido %.1f cm3' + LineEnding +
      'Grade %d x %d (%.2f mm)' + LineEnding + '%s',
      [FStock.RemovedVolume / 1000, FStock.Cols, FStock.Rows, FStock.Cell,
       BaseNote], InvariantFS);
    Status.Caption := 'Simulacao pronta. Vermelho = abaixo da base do material.';
  finally
    Errors.Free;
  end;
end;

function TMakeRouterForm.Simulate: Double;
begin
  RunSimulation(-1);
  Result := FStock.RemovedVolume;
end;

procedure TMakeRouterForm.SimAllClick(Sender: TObject);
begin
  try
    ShowStep(4);
    RunSimulation(-1);
  except
    on E: Exception do ShowError(E);
  end;
end;

procedure TMakeRouterForm.SimOneClick(Sender: TObject);
begin
  try
    if PathList.ItemIndex < 0 then raise Exception.Create('Selecione um percurso na etapa 4');
    RunSimulation(PathList.ItemIndex);
  except
    on E: Exception do ShowError(E);
  end;
end;

procedure TMakeRouterForm.DesignViewClick(Sender: TObject);
begin
  View.Mode := vmDesign;
  View.Invalidate;
end;

procedure TMakeRouterForm.ViewOptionsChanged(Sender: TObject);
begin
  View.ShowPaths := ShowPathsBox.Checked;
  View.ShowRapids := ShowRapidsBox.Checked;
  View.Invalidate;
  if Sender = SingleFile then Changed('');
end;

procedure TMakeRouterForm.FitClick(Sender: TObject);
begin
  View.FitMaterial;
end;

procedure TMakeRouterForm.ZoomInClick(Sender: TObject);
begin
  View.ZoomBy(1.25);
end;

procedure TMakeRouterForm.ZoomOutClick(Sender: TObject);
begin
  View.ZoomBy(1 / 1.25);
end;

{ ---------------- arquivos ---------------- }

procedure TMakeRouterForm.NewClick(Sender: TObject);
begin
  P.Clear;
  View.ClearSelection;
  LoadMaterialEditor;
  RefreshToolBox;
  RefreshShapeList;
  RefreshPathList;
  LoadToolEditor;
  View.FitMaterial;
  Log.Clear;
  ShowStep(0);
  Changed('Novo projeto. Defina o material e o ponto de zero.');
end;

procedure TMakeRouterForm.LoadExample;
begin
  MRLoadExample(P);
  View.ClearSelection;
  LoadMaterialEditor;
  RefreshToolBox;
  RefreshShapeList;
  RefreshPathList;
  LoadToolEditor;
  View.FitMaterial;
  Changed('Exemplo: placa com texto gravado, bolsao, 4 furos e recorte com pontes. Calcule e simule.');
end;

procedure TMakeRouterForm.ExampleClick(Sender: TObject);
begin
  LoadExample;
  CalculateAll;
end;

procedure TMakeRouterForm.OpenFile(const FN: string);
begin
  try
    P.LoadFromFile(FN);
    View.ClearSelection;
    LoadMaterialEditor;
    RefreshToolBox;
    RefreshShapeList;
    RefreshPathList;
    LoadToolEditor;
    View.FitMaterial;
    Changed('Aberto: ' + ExtractFileName(FN));
  except
    on E: Exception do ShowError(E);
  end;
end;

procedure TMakeRouterForm.OpenClick(Sender: TObject);
var D: TOpenDialog;
begin
  D := TOpenDialog.Create(Self);
  try
    D.Filter := 'Projeto MakeRouter|*.mrouter|Todos os arquivos|*';
    if D.Execute then OpenFile(D.FileName);
  finally
    D.Free;
  end;
end;

procedure TMakeRouterForm.SaveClick(Sender: TObject);
var D: TSaveDialog;
begin
  D := TSaveDialog.Create(Self);
  try
    D.Filter := 'Projeto MakeRouter|*.mrouter';
    D.DefaultExt := 'mrouter';
    D.Options := D.Options + [ofOverwritePrompt];
    if P.FileName <> '' then D.FileName := P.FileName
    else D.FileName := MRSafeFileName(P.Name) + '.mrouter';
    if D.Execute then
    begin
      P.SaveToFile(D.FileName);
      Status.Caption := 'Salvo: ' + ExtractFileName(D.FileName);
    end;
  finally
    D.Free;
  end;
end;

{ ---------------- validacao e saida ---------------- }

function TMakeRouterForm.ValidateJob: Boolean;
var Progs: TMRPrograms; I: Integer; S: string; Pr: TMRProgram;
begin
  Result := False;
  Log.Clear;
  try
    Progs := MRBuildPrograms(P, SingleFile.Checked);
    try
      S := Format('%d programa(s), tempo estimado %s', [Progs.Count, MRFormatTime(Progs.TotalSeconds)]);
      for I := 0 to Progs.Count - 1 do
      begin
        Pr := Progs.Item(I);
        S := S + LineEnding + Format('%d) %s: %s (%s)', [I + 1, P.Tools[Pr.ToolIndex].Name,
          Pr.Title, MRFormatTime(Pr.Seconds)]);
      end;
      OutSummary.Caption := S;
      for I := 0 to P.ToolpathCount - 1 do
        if P.Toolpaths[I].Enabled and (P.Toolpaths[I].Warnings <> '') then
          Log.Lines.Add(P.Toolpaths[I].Name + ': ' + P.Toolpaths[I].Warnings);
      Log.Lines.Add('Pronto para gerar o G-code.');
      State.Caption := 'Trabalho valido'; State.DotColor := clSuiteSuccess;
      Status.Caption := 'Validado: ' + Format('%d programa(s), %s.', [Progs.Count, MRFormatTime(Progs.TotalSeconds)]);
      RefreshPathList;
      Result := True;
    finally
      Progs.Free;
    end;
  except
    on E: Exception do
    begin
      ShowError(E);
      State.Caption := 'Corrigir antes de gerar';
    end;
  end;
end;

procedure TMakeRouterForm.ValidateClick(Sender: TObject);
begin
  ShowStep(5);
  ValidateJob;
end;

function TMakeRouterForm.ExportTo(const Folder: string): TStringList;
var Progs: TMRPrograms;
begin
  Progs := MRBuildPrograms(P, SingleFile.Checked);
  try
    Result := MRSavePrograms(Progs, Folder, P.Name);
  finally
    Progs.Free;
  end;
  if Result.Count > 0 then
  begin
    FExportedFile := ExpandFileName(Result[0]);
    SendButton.Enabled := True;
    State.Caption := 'G-code gerado'; State.DotColor := clSuiteSuccess;
    Status.Caption := Format('%d arquivo(s) em %s. Abra o primeiro no MultiCNC.', [Result.Count, Folder]);
    Log.Lines.AddStrings(Result);
  end;
end;

procedure TMakeRouterForm.ExportClick(Sender: TObject);
var D: TSelectDirectoryDialog; Files: TStringList;
begin
  ShowStep(5);
  if not ValidateJob then Exit;
  D := TSelectDirectoryDialog.Create(Self);
  try
    D.Title := 'Pasta para os programas G-code';
    if P.FileName <> '' then D.InitialDir := ExtractFilePath(P.FileName);
    if not D.Execute then Exit;
    try
      Files := ExportTo(D.FileName);
      Files.Free;
    except
      on E: Exception do ShowError(E);
    end;
  finally
    D.Free;
  end;
end;

procedure TMakeRouterForm.SendClick(Sender: TObject);
var Registry: TSuiteRegistry; Root, Err, Candidate: string; C: TSuiteContext; I: Integer;
begin
  if (FExportedFile = '') or not FileExists(FExportedFile) then Exit;
  Registry := TSuiteRegistry.Create;
  try
    try
      C := ReadSuiteContext;
      Root := ExtractFilePath(ParamStr(0)); Candidate := Root;
      for I := 0 to 5 do
      begin
        if DirectoryExists(IncludeTrailingPathDelimiter(Candidate) + 'multisuite') then
        begin
          Root := Candidate; Break;
        end;
        Candidate := ExtractFileDir(ExcludeTrailingPathDelimiter(Candidate));
      end;
      if not TSuiteLauncher.LaunchArtifact(Registry.Tool(Registry.Find(stiMultiCNC)), Root,
        C.ProjectRoot, FExportedFile, Err) then
        raise Exception.Create(Err);
      Status.Caption := 'Programa aberto no MultiCNC (CNC Router). Faca o zero no ponto indicado.';
    except
      on E: Exception do ShowError(E);
    end;
  finally
    Registry.Free;
  end;
end;

procedure TMakeRouterForm.FormKey(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_DELETE) and (ActiveControl = View) then
  begin
    DeleteShapesClick(Sender);
    Key := 0;
  end;
end;

end.
