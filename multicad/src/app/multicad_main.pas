unit multicad_main;

{ MultiCAD - janela principal (fase 3B), no padrao visual da MultiSuite e
  com a organizacao do SolidWorks:

  - cabecalho da suite e CommandManager com abas Operações, Esboço,
    Avaliar e Exibir (Novo / Abrir / Salvar a direita);
  - a esquerda a arvore de operacoes (FeatureManager): esbocos aninhados
    na operacao que os usa, cores de estado (vermelho = erro, laranja =
    aviso, cinza = suprimida ou abaixo da barra de retrocesso), menu de
    contexto (editar, editar esboco, suprimir, ocultar, renomear, excluir,
    retroceder) e a barra de retrocesso;
  - no mesmo lugar o PropertyManager quando uma operacao esta em edicao
    (previa ao vivo: a peca e reconstruida a cada mudanca e as faces da
    operacao aparecem em amarelo);
  - no centro a vista 3D; embaixo a barra de estado (selecao, estado do
    esboco ou massa, unidades MMGS). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls,
  Graphics, Dialogs, Menus, LCLType, LCLIntf, multicad_log, multicad_diagnostics, multicad_commandmanager, fpjson, jsonparser, multisuite_controls,
  multisuite_icons, multicad_types, multicad_units, multicad_materials,
  multicad_document, multicad_feature, multicad_refgeom, multicad_sketch, multicad_mesh,
  multicad_solver, multicad_extrude, multicad_revolve, multicad_rebuild,
  multicad_camera, multicad_softrender, multicad_view3d, multicad_sketchtools, multicad_extrudeedit,
  multicad_sketchedit, multicad_propman, multicad_undo, multicad_hole, multicad_pattern, multicad_blend, multicad_occt, multicad_import, multicad_materialdlg, multicad_textures, multicad_export, multicad_measure,
  multisuite_types, multisuite_registry, multisuite_launcher, multisuite_context,
  multicad_sketchpattern, multicad_sketchpatterndlg, multicad_sketchtext,
  multicad_sketchtextdlg;

type
  TCadTab = (ctFeatures, ctSketch, ctEvaluate, ctView, ctExport, ctAbout);

  TMainForm = class(TForm)
  private
    Doc: TCadDocument;
    RB: TCadRebuilder;
    Header: TSuiteHeader;
    TabBar, Ribbon, LeftPane: TPanel;
    TabButtons: array[TCadTab] of TSuiteButton;
    FileButtons: TPanel;
    MainMenuBar: TMainMenu;
    Tree: TTreeView;
    TreeMenu, MatMenu, PartMenu: TPopupMenu;
    RelMenu: TPopupMenu;
    PM: TCadPropManager;
    View: TCadView3D;
    Status: TStatusBar;
    Splitter: TSplitter;
    FTab: TCadTab;
    FEditor: TCadSketchEditor;
    FExtrudeEditor: TCadExtrudeEditor;
    FSnapshot: TJSONObject;     { parametros antes de editar (Cancelar) }
    FSnapName: string;
    FPendingSketch: Boolean;    { esperando escolher plano/face para o esboco }
    FLastSketchId: Integer;     { ultimo esboco finalizado; prioridade para a proxima operacao }
    FNormalFlip: Boolean;
    FToolButtons: array[TCadSketchToolKind] of TSuiteButton;
    FRibX, FRibY: Integer;
    FGridBtn, FGridSnapBtn, FWheelBtn: TSuiteButton;
    SketchPanel: TPanel;
    SketchTitle, SketchSel, SketchHint: TLabel;
    LineKind: TRadioGroup;
    FUpdatingPanel: Boolean;
    FUndo: TCadUndoStack;
    FAutoSketchId: Integer;   { esboco criado pelo comando Furo (Cancelar apaga) }
    FBlendEdit: Boolean;      { editando filete/chanfro: modelo antes dele + previa }
    FSavedRollback: Integer;
    FBlendPreview: TCadMesh;
    FRefreshingTree: Boolean;
    procedure UpdateSketchPanel;
    procedure ResetUndo;
    procedure RestoreState(const AState: string);
    procedure UndoClick(Sender: TObject);
    procedure RedoClick(Sender: TObject);
    procedure HoleClick(Sender: TObject);
    procedure LinearPatternClick(Sender: TObject);
    procedure CircularPatternClick(Sender: TObject);
    procedure SketchPatternClick(Sender: TObject);
    procedure SketchTextClick(Sender: TObject);
    procedure MirrorClick(Sender: TObject);
    procedure BlendClick(Sender: TObject);
    procedure StopBlendEdit;
    procedure UpdateBlendPreview;
    function PatternSeeds: TCadIdArray;
    function SelectedFaceRef: string;
    procedure LineKindClick(Sender: TObject);
    procedure BuildUI;
    procedure ShowTab(T: TCadTab);
    function RibbonButton(const ACaption: string; AIcon: TSuiteIconKind;
      AHandler: TNotifyEvent; ATag: Integer = 0; AWidth: Integer = 0): TSuiteButton;
    procedure RibbonSep;
    procedure TabClick(Sender: TObject);
    procedure LayoutCommandManager(Sender: TObject);
    procedure BuildMainMenu;
    procedure CloseClick(Sender: TObject);
    { arquivo }
    procedure AboutClick(Sender: TObject);
    procedure LogClick(Sender: TObject);
    procedure ApplicationError(Sender: TObject; E: Exception);
    procedure NewClick(Sender: TObject);
    procedure OpenClick(Sender: TObject);
    procedure SaveClick(Sender: TObject);
    procedure SaveAsClick(Sender: TObject);
    function ConfirmDiscard: Boolean;
    function SaveTo(const AFile: string): Boolean;
    procedure UpdateCaption;
    { modelo }
    procedure RebuildModel;
    procedure Modified;
    procedure RefreshTree;
    function NodeFeature(N: TTreeNode): TCadFeature;
    function SelectedFeature: TCadFeature;
    function FindSketchForFeature: TCadSketch;
    function SelectedPlaneRef: string;
    procedure SyncSelectionFromTree;
    { arvore }
    procedure TreeSelect(Sender: TObject; Node: TTreeNode);
    procedure TreeDblClick(Sender: TObject);
    procedure TreeCustomDraw(Sender: TCustomTreeView; Node: TTreeNode;
      State: TCustomDrawState; var DefaultDraw: Boolean);
    procedure TreeEditing(Sender: TObject; Node: TTreeNode; var AllowEdit: Boolean);
    procedure TreeEdited(Sender: TObject; Node: TTreeNode; var S: string);
    procedure TreeMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure MenuPopup(Sender: TObject);
    procedure MenuEdit(Sender: TObject);
    procedure MenuEditSketch(Sender: TObject);
    procedure MenuSuppress(Sender: TObject);
    procedure MenuHide(Sender: TObject);
    procedure MenuRename(Sender: TObject);
    procedure MenuDelete(Sender: TObject);
    procedure MenuRollHere(Sender: TObject);
    procedure MenuRollEnd(Sender: TObject);
    procedure MenuNormalTo(Sender: TObject);
    procedure RenameFeature(F: TCadFeature; const ANew: string);
    procedure ChooseMaterial;
    procedure MaterialMenuEdit(Sender: TObject);
    procedure MaterialMenuDefault(Sender: TObject);
    procedure PartMenuRename(Sender: TObject);
    procedure MenuSketchOnPlane(Sender: TObject);
    procedure TreeContextPopup(Sender: TObject; MousePos: TPoint; var Handled: Boolean);
    procedure ChoosePlaneForSketch;
    { operacoes }
    procedure SketchClick(Sender: TObject);
    procedure StartSketch(const APlaneRef: string);
    procedure EditSketch(S: TCadSketch);
    procedure ExitSketch(Sender: TObject);
    procedure ToolClick(Sender: TObject);
    procedure RelationClick(Sender: TObject);
    procedure RelationMenuClick(Sender: TObject);
    procedure DeleteSketchClick(Sender: TObject);
    procedure GridClick(Sender: TObject);
    procedure GridSnapClick(Sender: TObject);
    procedure PrevViewClick(Sender: TObject);
    procedure WheelClick(Sender: TObject);
    procedure FormKeyPress(Sender: TObject; var Key: Char);
    procedure LoadSettings;
    procedure SaveSettings;
    procedure EditorChanged(Sender: TObject);
    procedure EditorStatus(Sender: TObject);
    procedure ExtrudeClick(Sender: TObject);
    procedure CutClick(Sender: TObject);
    procedure RevolveClick(Sender: TObject);
    procedure RevolveCutClick(Sender: TObject);
    procedure PlaneClick(Sender: TObject);
    procedure BeginEdit(F: TCadFeature; AIsNew: Boolean);
    procedure EndEdit(Accept: Boolean);
    procedure PMChange(Sender: TObject);
    procedure PMOK(Sender: TObject);
    procedure PMCancel(Sender: TObject);
    { avaliar / exibir }
    procedure MassClick(Sender: TObject);
    procedure MeasureClick(Sender: TObject);
    procedure ExportSTLClick(Sender: TObject);
    procedure ExportDXFClick(Sender: TObject);
    procedure ExportSTEPClick(Sender: TObject);
    procedure ImportSTEPClick(Sender: TObject);
    function KernelText: string;
    procedure KernelClick(Sender: TObject);
    procedure OpenSlicerClick(Sender: TObject);
    function AskStlOptions(out ABinary: Boolean; out AOrient: TCadStlOrient): Boolean;
    function ExportSTLTo(const AFile: string; ABinary: Boolean; AOrient: TCadStlOrient): Boolean;
    function SelectedFaceNormal(out N: TCadVec3): Boolean;
    procedure SectionClick(Sender: TObject);
    procedure RebuildClick(Sender: TObject);
    procedure StyleClick(Sender: TObject);
    procedure ViewClick(Sender: TObject);
    procedure NormalToClick(Sender: TObject);
    procedure NormalToRef(const ARef: string);
    procedure PerspectiveClick(Sender: TObject);
    procedure PlanesClick(Sender: TObject);
    { vista }
    procedure ViewPick(Sender: TObject; const ARef: string; Shift: TShiftState);
    procedure ViewHover(Sender: TObject);
    procedure ViewNormalTo(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure SetStatus(I: Integer; const S: string);
    procedure UpdatePartStatus;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function OpenFile(const AFile: string): Boolean;
    { acesso para o teste de interface }
    property Document: TCadDocument read Doc;
    property Rebuilder: TCadRebuilder read RB;
    property View3D: TCadView3D read View;
    property FeatureTree: TTreeView read Tree;
    property CommandRibbon: TPanel read Ribbon;
    property CommandTabs: TPanel read TabBar;
    property SketchEditor: TCadSketchEditor read FEditor;
    property ExtrudeEditor: TCadExtrudeEditor read FExtrudeEditor;
    procedure EditSketchById(AId: Integer);
    procedure EditFeatureById(AId: Integer);
    procedure CancelEdit;
    procedure ExitSketchMode;
    procedure ApplyMaterial(const AName: string; AColor: Integer);
    { para o teste de interface }
    procedure RefreshModel;
    procedure MarkModified;
    procedure DoUndo;
    procedure DoRedo;
    { filete (0), chanfro (1) ou casca (2) com a selecao atual }
    procedure StartBlend(AKind: Integer);
    procedure AcceptEdit;
    procedure PreviewChanged;
    property PropManager: TCadPropManager read PM;
  end;

implementation

const
  TAB_NAMES: array[TCadTab] of string = ('Operações', 'Esboço', 'Avaliar', 'Exibir', 'Exportar', 'Sobre');
  NODE_PART = -100;
  NODE_MATERIAL = -101;
  NODE_ROLLBACK = -102;

{ ---------- criacao ---------- }

constructor TMainForm.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner, 0);
  Caption := 'MultiCAD';
  Width := 1360;
  Height := 860;
  Position := poScreenCenter;
  KeyPreview := True;
  OnKeyDown := @FormKeyDown;
  OnCloseQuery := @FormCloseQuery;
  OnKeyPress := @FormKeyPress;
  Color := clSuiteSurface;
  Font.Name := SUITE_FONT;
  Doc := TCadDocument.Create;
  Doc.NewPart;
  RB := TCadRebuilder.Create(Doc);
  FUndo := TCadUndoStack.Create(100);
  BuildUI;
  BuildMainMenu;
  OnResize:=@LayoutCommandManager;
  LoadSettings;
  Application.AddOnExceptionHandler(@ApplicationError);
  CadLog('WINDOW.OPEN','version='+CadExecutableVersion);
  RebuildModel;
  View.SetView(svIso);
  UpdateCaption;
  ResetUndo;
end;

destructor TMainForm.Destroy;
begin
  Application.RemoveOnExceptionHandler(@ApplicationError);
  CadLog('WINDOW.CLOSE',Caption);
  FreeAndNil(FExtrudeEditor);
  FreeAndNil(FEditor);
  FSnapshot.Free;
  View.SetPreview(nil, False);
  FBlendPreview.Free;
  RB.Free;
  Doc.Free;
  FUndo.Free;
  inherited Destroy;
end;

procedure TMainForm.BuildUI;
var
  T: TCadTab;
  B: TSuiteButton;
  MI: TMenuItem;
  K: TConstraintKind;

  function FileBtn(const S: string; AIcon: TSuiteIconKind; H: TNotifyEvent): TSuiteButton;
  begin
    Result := TCadLoggedButton.Create(Self);
    Result.Parent := FileButtons;
    Result.Align := alLeft;
    Result.BorderSpacing.Around := 3;
    Result.Width := 108;
    Result.Caption := S;
    Result.SetLook(sbsSoft, clSuitePrimary, AIcon);
    Result.OnClick := H;
  end;

  procedure AddMenu(const S: string; H: TNotifyEvent; ATag: Integer = 0);
  begin
    MI := TCadLoggedMenuItem.Create(TreeMenu);
    MI.Caption := S;
    MI.OnClick := H;
    MI.Tag := ATag;
    TreeMenu.Items.Add(MI);
  end;

begin
  Header := TSuiteHeader.Create(Self);
  Header.Parent := Self;
  Header.Align := alTop;
  Header.Height := 60;
  Header.Setup('MultiCAD', 'Modelagem paramétrica de peças  /  MultiSuite', sikCAD);

  TabBar := TPanel.Create(Self);
  TabBar.Parent := Self;
  TabBar.Align := alTop;
  TabBar.Top := 200;
  TabBar.Height := 30;
  TabBar.BevelOuter := bvNone;
  TabBar.Color := clSuiteCard;
  for T := Low(TCadTab) to High(TCadTab) do
  begin
    B := TCadCommandTab.Create(Self);
    B.Parent := TabBar;
    B.SetBounds(8 + Ord(T) * 112, 0, 112, 30);
    B.Caption := TAB_NAMES[T];
    B.Tag := Ord(T);
    B.OnClick := @TabClick;
    TabButtons[T] := B;
  end;
  FileButtons := TPanel.Create(Self);
  FileButtons.Parent := Header;
  FileButtons.Align := alRight;
  FileButtons.BorderSpacing.Top:=12;
  FileButtons.BorderSpacing.Bottom:=12;
  FileButtons.Width := 6 * 114 + 28;
  FileButtons.BevelOuter := bvNone;
  FileButtons.Color := clSuiteCard;
  FileBtn('Salvar como', sikSave, @SaveAsClick).Width:=128;
  FileBtn('Salvar', sikSave, @SaveClick);
  FileBtn('Abrir', sikFolder, @OpenClick);
  FileBtn('Novo', sikNew, @NewClick);
  FileBtn('Refazer', sikRedo, @RedoClick).Hint := 'Refazer (Ctrl+Y)';
  FileBtn('Desfazer', sikUndo, @UndoClick).Hint := 'Desfazer (Ctrl+Z)';

  Ribbon := TPanel.Create(Self);
  Ribbon.Parent := Self;
  Ribbon.Align := alTop;
  Ribbon.Top := 100;
  Ribbon.Height := 50;
  Ribbon.BevelOuter := bvNone;
  Ribbon.Color := clSuiteSurface;
  Ribbon.BorderSpacing.Bottom := 2;

  Status := TStatusBar.Create(Self);
  Status.Parent := Self;
  Status.SimplePanel := False;
  with Status.Panels.Add do Width := 420;
  with Status.Panels.Add do Width := 520;
  with Status.Panels.Add do Width := 120;
  Status.Panels[2].Text := 'MMGS (mm, g, s)';

  LeftPane := TPanel.Create(Self);
  LeftPane.Parent := Self;
  LeftPane.Align := alLeft;
  LeftPane.Width := 270;
  LeftPane.BevelOuter := bvNone;
  LeftPane.Color := clSuiteSurface;

  Splitter := TSplitter.Create(Self);
  Splitter.Parent := Self;
  Splitter.Align := alLeft;
  Splitter.Left := 300;

  TreeMenu := TPopupMenu.Create(Self);
  TreeMenu.OnPopup := @MenuPopup;
  AddMenu('Editar operação', @MenuEdit);
  AddMenu('Editar esboço', @MenuEditSketch);
  AddMenu('-', nil);
  AddMenu('Suprimir', @MenuSuppress);
  AddMenu('Ocultar', @MenuHide);
  AddMenu('Renomear', @MenuRename);
  AddMenu('Excluir', @MenuDelete);
  AddMenu('-', nil);
  AddMenu('Retroceder até aqui', @MenuRollHere);
  AddMenu('Retroceder até o fim', @MenuRollEnd);
  AddMenu('Vista (normal ao plano)', @MenuNormalTo);
  AddMenu('-', nil);
  AddMenu('Novo esboço neste plano', @MenuSketchOnPlane);
  MatMenu := TPopupMenu.Create(Self);
  MI := TCadLoggedMenuItem.Create(MatMenu);
  MI.Caption := 'Editar material...';
  MI.OnClick := @MaterialMenuEdit;
  MatMenu.Items.Add(MI);
  MI := TCadLoggedMenuItem.Create(MatMenu);
  MI.Caption := 'Material padrão (' + CAD_DEFAULT_MATERIAL + ')';
  MI.OnClick := @MaterialMenuDefault;
  MatMenu.Items.Add(MI);
  PartMenu := TPopupMenu.Create(Self);
  MI := TCadLoggedMenuItem.Create(PartMenu);
  MI.Caption := 'Renomear';
  MI.OnClick := @PartMenuRename;
  PartMenu.Items.Add(MI);

  RelMenu := TPopupMenu.Create(Self);
  for K := Low(TConstraintKind) to High(TConstraintKind) do
    if not IsDimensionKind(K) then
    begin
      MI := TCadLoggedMenuItem.Create(RelMenu);
      MI.Caption := CadConstraintName(K);
      MI.Tag := Ord(K);
      MI.OnClick := @RelationClick;
      RelMenu.Items.Add(MI);
    end;

  { painel do esboco: o que esta selecionado e linha normal / de apoio }
  SketchPanel := TPanel.Create(Self);
  SketchPanel.Parent := LeftPane;
  SketchPanel.Align := alTop;
  SketchPanel.Height := 182;
  SketchPanel.BevelOuter := bvNone;
  SketchPanel.Color := clSuiteCard;
  SketchPanel.Visible := False;
  SketchTitle := TLabel.Create(Self);
  SketchTitle.Parent := SketchPanel;
  SketchTitle.SetBounds(10, 6, 250, 18);
  SketchTitle.Font.Style := [fsBold];
  SketchSel := TLabel.Create(Self);
  SketchSel.Name := 'SketchToolSummary';
  SketchSel.Parent := SketchPanel;
  SketchSel.SetBounds(10, 28, Max(1, SketchPanel.ClientWidth-20), 34);
  SketchSel.WordWrap := True;
  SketchSel.AutoSize := False;
  SketchSel.Anchors := [akLeft, akTop, akRight];
  LineKind := TRadioGroup.Create(Self);
  LineKind.Name := 'SketchLineKind';
  LineKind.Parent := SketchPanel;
  LineKind.SetBounds(8, 66, Max(1, SketchPanel.ClientWidth-16), 70);
  LineKind.Caption := 'Tipo de linha';
  LineKind.Anchors := [akLeft, akTop, akRight];
  LineKind.Items.Add('Linha normal (contorno da peça)');
  LineKind.Items.Add('Linha de apoio (tracejada)');
  LineKind.ItemIndex := 0;
  LineKind.OnClick := @LineKindClick;
  SketchHint := TLabel.Create(Self);
  SketchHint.Name := 'SketchToolHint';
  with SketchHint do
  begin
    Parent := SketchPanel;
    SetBounds(10, 140, 250, 36);
    AutoSize := False;
    WordWrap := True;
    BorderSpacing.Left := 10;
    BorderSpacing.Right := 10;
    BorderSpacing.Bottom := 6;
    Align := alBottom;
    Font.Color := clSuiteMuted;
    Caption := 'Sem seleção, a escolha vale para as próximas linhas.';
  end;

  Tree := TTreeView.Create(Self);
  Tree.Parent := LeftPane;
  Tree.Align := alClient;
  Tree.ReadOnly := False;
  Tree.HideSelection := False;
  Tree.RightClickSelect := True;
  Tree.PopupMenu := TreeMenu;
  Tree.OnChange := @TreeSelect;
  Tree.OnDblClick := @TreeDblClick;
  Tree.OnCustomDrawItem := @TreeCustomDraw;
  Tree.OnEditing := @TreeEditing;
  Tree.OnEdited := @TreeEdited;
  Tree.OnMouseDown := @TreeMouseDown;
  Tree.OnContextPopup := @TreeContextPopup;
  Tree.BorderStyle := bsNone;

  PM := TCadPropManager.Create(Self);
  PM.Parent := LeftPane;
  PM.Align := alClient;
  PM.Visible := False;
  PM.OnChange := @PMChange;
  PM.OnOK := @PMOK;
  PM.OnCancel := @PMCancel;

  View := TCadView3D.Create(Self);
  View.Parent := Self;
  View.Align := alClient;
  View.SetModel(Doc, RB);
  View.OnPick := @ViewPick;
  View.OnHoverChange := @ViewHover;
  View.OnNormalTo := @ViewNormalTo;

  ShowTab(ctFeatures);
end;

function TMainForm.RibbonButton(const ACaption: string; AIcon: TSuiteIconKind;
  AHandler: TNotifyEvent; ATag: Integer; AWidth: Integer): TSuiteButton;
begin
  Result := TCadCommandButton.Create(Ribbon);
  Result.Parent := Ribbon;
  if AWidth = 0 then
    AWidth := EnsureRange(Round(Result.Canvas.TextWidth(ACaption) * 0.65) + 14, 78, 124);
  { quebra de linha quando nao cabe (aba Esboco tem duas linhas) }
  if (FRibX > 8) and (FRibX + AWidth > Max(Ribbon.ClientWidth, ClientWidth) - 8) then
  begin
    FRibX := 8;
    Inc(FRibY, 86);
  end;
  Result.SetBounds(FRibX, FRibY, AWidth, 80);
  Inc(FRibX, AWidth + 6);
  Result.Caption := ACaption;
  Result.Tag := ATag;
  Result.SetLook(sbsSoft, clSuitePrimary, AIcon);
  TCadCommandButton(Result).SetCommandIcon(AIcon);
  Result.Hint:=ACaption;Result.ShowHint:=True;
  Result.OnClick := AHandler;
end;

procedure TMainForm.RibbonSep;
var
  B: TBevel;
begin
  if FRibX <= 8 then
    Exit;
  B := TBevel.Create(Ribbon);
  B.Parent := Ribbon;
  B.Shape := bsLeftLine;
  B.SetBounds(FRibX, FRibY + 2, 4, 76);
  Inc(FRibX, 8);
end;

procedure TMainForm.ShowTab(T: TCadTab);
var
  I: Integer;
  TT: TCadTab;
  K: TCadSketchToolKind;
  InSketch: Boolean;
begin
  CadLog('TAB',TAB_NAMES[T]);
  FTab := T;
  for TT := Low(TCadTab) to High(TCadTab) do
    if TT = T then
      TabButtons[TT].SetLook(sbsSolid, clSuitePrimary)
    else
      TabButtons[TT].SetLook(sbsSoft, clSuitePrimary);
  for I := Ribbon.ControlCount - 1 downto 0 do
  begin
    { Click is called before WMLButtonUp finishes using the control.
      Hide now, release after dispatch so switching tools/tabs is safe. }
    Ribbon.Controls[I].Visible:=False;
    Application.ReleaseComponent(Ribbon.Controls[I]);
  end;
  FRibX := 8;
  FRibY := 8;
  FGridBtn := nil;
  FGridSnapBtn := nil;
  FWheelBtn := nil;
  for K := Low(TCadSketchToolKind) to High(TCadSketchToolKind) do
    FToolButtons[K] := nil;
  InSketch := Assigned(FEditor);
  case T of
    ctFeatures:
      begin
        RibbonButton('Ressalto extrudado', sikMove, @ExtrudeClick);
        RibbonButton('Ressalto revolucionado', sikRedo, @RevolveClick);
        RibbonSep;
        RibbonButton('Corte extrudado', sikTrash, @CutClick);
        RibbonButton('Corte revolucionado', sikUndo, @RevolveCutClick);
        RibbonSep;
        RibbonButton('Plano', sikLayers, @PlaneClick);
        RibbonSep;
        RibbonButton('Furo', sikTarget, @HoleClick);
        RibbonButton('Padrão linear', sikCopy, @LinearPatternClick);
        RibbonButton('Padrão circular', sikRedo, @CircularPatternClick);
        RibbonButton('Espelhar', sikMirrorH, @MirrorClick);
        RibbonSep;
        RibbonButton('Filete', sikCircle, @BlendClick, 0);
        RibbonButton('Chanfro', sikRect, @BlendClick, 1);
        RibbonButton('Casca', sikFrame, @BlendClick, 2);
      end;
    ctSketch:
      begin
        if InSketch then
          RibbonButton('Sair do esboço', sikFlag, @ExitSketch).SetLook(sbsSolid, clSuiteSuccess, sikFlag)
        else
          RibbonButton('Esboço', sikPen, @SketchClick).SetLook(sbsSolid, clSuitePrimary, sikPen);
        RibbonSep;
        FToolButtons[tkSelect] := RibbonButton('Selecionar', sikPointer, @ToolClick, Ord(tkSelect));
        FToolButtons[tkLine] := RibbonButton('Linha', sikPen, @ToolClick, Ord(tkLine));
        FToolButtons[tkRectangle] := RibbonButton('Retângulo', sikRect, @ToolClick, Ord(tkRectangle));
        FToolButtons[tkCircle] := RibbonButton('Círculo', sikCircle, @ToolClick, Ord(tkCircle));
        FToolButtons[tkArcCenter] := RibbonButton('Arco pelo centro', sikRedo, @ToolClick, Ord(tkArcCenter));
        FToolButtons[tkArcTangent] := RibbonButton('Arco tangente', sikRedo, @ToolClick, Ord(tkArcTangent));
        FToolButtons[tkArc3P] := RibbonButton('Arco 3 pontos', sikRedo, @ToolClick, Ord(tkArc3P));
        FToolButtons[tkCenterline] := RibbonButton('Linha de centro', sikMirrorV, @ToolClick, Ord(tkCenterline));
        FToolButtons[tkPoint] := RibbonButton('Ponto', sikTarget, @ToolClick, Ord(tkPoint));
        RibbonButton('Texto', sikText, @SketchTextClick).Enabled := InSketch;
        RibbonSep;
        FToolButtons[tkTrim] := RibbonButton('Aparar (Trim)', sikTrim, @ToolClick, Ord(tkTrim));
        FToolButtons[tkChamfer] := RibbonButton('Chanfro', sikRect, @ToolClick, Ord(tkChamfer));
        RibbonSep;
        FToolButtons[tkDimension] := RibbonButton('Cota inteligente', sikGauge, @ToolClick, Ord(tkDimension));
        RibbonButton('Adicionar relação', sikLayers, @RelationMenuClick).Enabled := InSketch;
        RibbonButton('Apagar', sikTrash, @DeleteSketchClick, 0, 90).Enabled := InSketch;
        RibbonButton('Padrão linear', sikCopy, @SketchPatternClick, Ord(skpLinear)).Enabled := InSketch;
        RibbonButton('Padrão circular', sikRedo, @SketchPatternClick, Ord(skpCircular)).Enabled := InSketch;
        RibbonSep;
        FGridBtn := RibbonButton('Grade', sikFrame, @GridClick, 0);
        FGridSnapBtn := RibbonButton('Capturar na grade', sikTarget, @GridSnapClick, 0);
        FGridBtn.Enabled := InSketch;
        FGridSnapBtn.Enabled := InSketch;
        if InSketch and FEditor.Grid then
          FGridBtn.SetLook(sbsSolid, clSuitePrimary, sikFrame);
        if InSketch and FEditor.Session.GridSnap then
          FGridSnapBtn.SetLook(sbsSolid, clSuitePrimary, sikTarget);
        for K := Low(TCadSketchToolKind) to High(TCadSketchToolKind) do
          if Assigned(FToolButtons[K]) then
          begin
            FToolButtons[K].Enabled := InSketch;
            if InSketch and (FEditor.Session.Tool = K) then
              FToolButtons[K].SetLook(sbsSolid, clSuitePrimary);
          end;
      end;
    ctEvaluate:
      begin
        RibbonButton('Propriedades de massa', sikGauge, @MassClick);
        RibbonButton('Medir', sikTarget, @MeasureClick);
        RibbonButton('Vista de seção', sikLayers, @SectionClick);
        RibbonButton('Reconstruir (Ctrl+B)', sikPulse, @RebuildClick);
      end;
    ctView:
      begin
        RibbonButton('Sombreado com arestas', sikFrame, @StyleClick, Ord(dsShadedEdges));
        RibbonButton('Sombreado', sikFrame, @StyleClick, Ord(dsShaded));
        RibbonButton('Linhas ocultas removidas', sikFrame, @StyleClick, Ord(dsHiddenRemoved));
        RibbonButton('Linhas ocultas visíveis', sikFrame, @StyleClick, Ord(dsHiddenVisible));
        RibbonButton('Arame', sikFrame, @StyleClick, Ord(dsWireframe));
        RibbonSep;
        RibbonButton('Frontal', sikEye, @ViewClick, Ord(svFront), 80);
        RibbonButton('Superior', sikEye, @ViewClick, Ord(svTop), 84);
        RibbonButton('Direita', sikEye, @ViewClick, Ord(svRight), 80);
        RibbonButton('Isométrica', sikEye, @ViewClick, Ord(svIso), 96);
        RibbonButton('Normal a', sikTarget, @NormalToClick, 0, 88);
        RibbonButton('Enquadrar (F)', sikFit, @ViewClick, -1, 110);
        RibbonSep;
        RibbonButton('Perspectiva', sikEye, @PerspectiveClick);
        RibbonButton('Planos padrão', sikLayers, @PlanesClick);
        RibbonButton('Vista anterior', sikUndo, @PrevViewClick);
        FWheelBtn := RibbonButton('Inverter zoom da roda', sikZoomIn, @WheelClick);
        if View.ReverseWheel then
          FWheelBtn.SetLook(sbsSolid, clSuitePrimary, sikZoomIn);
      end;
    ctAbout:
      begin
        RibbonButton('Sobre o MultiCAD', sikHome, @AboutClick);
        RibbonButton('Abrir log', sikFolder, @LogClick);
      end;
    ctExport:
      begin
        RibbonButton('STL para impressão 3D...', sikExport, @ExportSTLClick);
        RibbonButton('DXF do esboço ou face...', sikExport, @ExportDXFClick);
        RibbonButton('STEP (outros CADs)...', sikExport, @ExportSTEPClick);
        RibbonButton('Importar STEP...', sikImport, @ImportSTEPClick);
        RibbonSep;
        RibbonButton('Abrir no MultiSlicer', sikSlicer, @OpenSlicerClick).SetLook(sbsSolid,
          clSuitePrimary, sikSlicer);
      end;
  end;
  Ribbon.Height := FRibY + 80 + 8;
end;

procedure TMainForm.LayoutCommandManager(Sender: TObject);
begin
  if Assigned(Ribbon) and Assigned(TabButtons[ctFeatures]) then ShowTab(FTab);
end;

procedure TMainForm.CloseClick(Sender: TObject);
begin Close;end;

procedure TMainForm.BuildMainMenu;
var Root,Item:TMenuItem;
  function Category(const Caption:string):TMenuItem;
  begin
    Result:=TCadLoggedMenuItem.Create(MainMenuBar);Result.Caption:=Caption;
    MainMenuBar.Items.Add(Result);
  end;
  procedure Command(const Caption:string;Handler:TNotifyEvent;Tag:Integer=0);
  begin
    Item:=TCadLoggedMenuItem.Create(MainMenuBar);Item.Caption:=Caption;
    Item.Tag:=Tag;Item.OnClick:=Handler;Root.Add(Item);
  end;
begin
  MainMenuBar:=TMainMenu.Create(Self);Menu:=MainMenuBar;
  Root:=Category('Arquivo');
  Command('Novo',@NewClick);Command('Abrir...',@OpenClick);
  Command('Salvar',@SaveClick);Command('Salvar como...',@SaveAsClick);
  Command('-',nil);Command('Sair',@CloseClick);
  Root:=Category('Editar');
  Command('Editar operação',@MenuEdit);Command('Editar esboço',@MenuEditSketch);
  Command('Renomear',@MenuRename);Command('Excluir',@MenuDelete);
  Root:=Category('Exibir');
  Command('Frontal',@ViewClick,Ord(svFront));Command('Superior',@ViewClick,Ord(svTop));
  Command('Direita',@ViewClick,Ord(svRight));Command('Isométrica',@ViewClick,Ord(svIso));
  Command('Normal a',@NormalToClick);Command('Enquadrar',@ViewClick,-1);
  Command('Perspectiva',@PerspectiveClick);Command('Planos padrão',@PlanesClick);
  Root:=Category('Inserir');
  Command('Esboço',@SketchClick);Command('Plano',@PlaneClick);
  Command('-',nil);Command('Ressalto extrudado',@ExtrudeClick);Command('Corte extrudado',@CutClick);
  Command('Ressalto revolucionado',@RevolveClick);Command('Corte revolucionado',@RevolveCutClick);
  Root:=Category('Ferramentas');
  Command('Reconstruir',@RebuildClick);Command('Propriedades de massa',@MassClick);
  Command('Medir',@MeasureClick);Command('Exportar STL...',@ExportSTLClick);
  Command('Exportar DXF...',@ExportDXFClick);
  Command('Exportar STEP...',@ExportSTEPClick);Command('Importar STEP...',@ImportSTEPClick);
  Command('Núcleo OpenCascade / Pascal',@KernelClick);
  Root:=Category('Sobre');
  Command('Sobre o MultiCAD',@AboutClick);Command('Abrir log',@LogClick);
end;

procedure TMainForm.TabClick(Sender: TObject);
begin
  ShowTab(TCadTab(TComponent(Sender).Tag));
end;

{ ---------- estado ---------- }

procedure TMainForm.SetStatus(I: Integer; const S: string);
begin
  { so repinta a barra de status quando o texto muda de fato }
  if Status.Panels[I].Text <> S then
    Status.Panels[I].Text := S;
end;

procedure TMainForm.UpdatePartStatus;
var
  M: TCadMaterial;
begin
  if Assigned(FEditor) then
    SetStatus(1, FEditor.StatusText)
  else if RB.BodyCount > 0 then
  begin
    if not CadFindMaterial(Doc.Material, M) then
      M := CadMaterial(0);
    SetStatus(1, Format('%d corpo(s)  |  volume %s mm³  |  %s: %s kg',
      [RB.BodyCount, CadFmt(RB.TotalVolume, 1), M.Name, CadFmt(RB.MassKg, 3)]));
  end
  else
    SetStatus(1, 'Peça vazia: comece por um esboço (aba Esboço)');
end;

procedure TMainForm.UpdateCaption;
var
  N: string;
begin
  if Doc.FileName <> '' then
    N := ExtractFileName(Doc.FileName)
  else
    N := Doc.Name;
  if Doc.Modified then
    N := N + ' *';
  Caption := 'MultiCAD - ' + N;
end;

procedure TMainForm.RebuildModel;
begin
  RB.Rebuild;
  View.SetAppearance(Doc.AppearanceColor, CadTextureIndex(Doc.MaterialData.Texture));
  View.ModelChanged;
  RefreshTree;
  UpdatePartStatus;
end;

procedure TMainForm.Modified;
begin
  Doc.Modified := True;
  UpdateCaption;
  { historia para desfazer (estado depois da alteracao) }
  if Assigned(FUndo) and not PM.Visible then
    FUndo.Push(Doc.ToJSON);
end;

procedure TMainForm.ResetUndo;
begin
  FUndo.Reset(Doc.ToJSON);
end;

procedure TMainForm.RestoreState(const AState: string);
var
  SketchId, I: Integer;
  T: TCadSketchToolKind;
  Err, Fn: string;
  F: TCadFeature;
begin
  if AState = '' then
    Exit;
  SketchId := 0;
  T := tkSelect;
  if Assigned(FEditor) then
  begin
    SketchId := FEditor.Sketch.Id;
    T := FEditor.Session.Tool;
    FreeAndNil(FEditor);
  end;
  Fn := Doc.FileName;
  if not Doc.LoadFromJSON(AState, Err) then
  begin
    MessageDlg('Não foi possível desfazer: ' + Err, mtError, [mbOK], 0);
    Exit;
  end;
  Doc.FileName := Fn;
  Doc.Modified := True;
  View.Selected.Clear;
  View.HighlightPrefix := '';
  RebuildModel;
  UpdateCaption;
  if SketchId > 0 then
  begin
    F := Doc.FindById(SketchId);
    if F is TCadSketch then
    begin
      FEditor := TCadSketchEditor.Create(View, Doc, RB, TCadSketch(F));
      FEditor.OnChanged := @EditorChanged;
      FEditor.OnStatus := @EditorStatus;
      FEditor.SetTool(T);
      ShowTab(ctSketch);
      EditorStatus(nil);
    end
    else
      ShowTab(ctFeatures);
    UpdateSketchPanel;
  end;
  I := 0;
  if I = 0 then;
end;

procedure TMainForm.UndoClick(Sender: TObject);
begin
  if PM.Visible then
  begin
    SetStatus(1, 'Termine (OK) ou cancele a operação antes de desfazer');
    Exit;
  end;
  if FUndo.CanUndo then
  begin
    RestoreState(FUndo.Undo);
    SetStatus(0, 'Desfeito');
  end
  else
    SetStatus(0, 'Nada para desfazer');
end;

procedure TMainForm.RedoClick(Sender: TObject);
begin
  if PM.Visible then
    Exit;
  if FUndo.CanRedo then
  begin
    RestoreState(FUndo.Redo);
    SetStatus(0, 'Refeito');
  end
  else
    SetStatus(0, 'Nada para refazer');
end;

{ ---------- arvore ---------- }

function ConsumerIndex(D: TCadDocument; SketchId: Integer): Integer;
var
  I, K: Integer;
  Deps: TCadIdArray;
begin
  Result := -1;
  for I := 0 to D.Count - 1 do
  begin
    if D.Feature(I).Kind in [cfSketch, cfPlane, cfAxis, cfOrigin] then
      Continue;
    Deps := D.Feature(I).Dependencies;
    for K := 0 to High(Deps) do
      if Deps[K] = SketchId then
        Exit(I);
  end;
end;

procedure TMainForm.RefreshTree;
var
  Root, N, Sub: TTreeNode;
  I, K, Sel, Roll: Integer;
  F, G: TCadFeature;
  Deps: TCadIdArray;
  RollAdded: Boolean;

  procedure AddRollback;
  begin
    if RollAdded then
      Exit;
    RollAdded := True;
    Tree.Items.AddChildObject(Root, '── Barra de retrocesso ──', Pointer(PtrInt(NODE_ROLLBACK)));
  end;

begin
  FRefreshingTree := True;
  Tree.Items.BeginUpdate;
  try
    Sel := 0;
    F := SelectedFeature;
    if Assigned(F) then
      Sel := F.Id;
    Tree.Items.Clear;
    Root := Tree.Items.AddObject(nil, Doc.Name, Pointer(PtrInt(NODE_PART)));
    if Doc.Material <> '' then
      Tree.Items.AddChildObject(Root, 'Material <' + Doc.Material + '>', Pointer(PtrInt(NODE_MATERIAL)))
    else
      Tree.Items.AddChildObject(Root, 'Material <não especificado>', Pointer(PtrInt(NODE_MATERIAL)));
    Roll := Doc.RollbackIndex;
    RollAdded := False;
    for I := 0 to Doc.Count - 1 do
    begin
      if (Roll >= 0) and (I = Roll) then
        AddRollback;
      F := Doc.Feature(I);
      { esboco usado por uma operacao aparece dentro dela }
      if (F is TCadSketch) and (ConsumerIndex(Doc, F.Id) > I) then
        Continue;
      N := Tree.Items.AddChildObject(Root, F.Name, Pointer(PtrInt(F.Id)));
      if not (F.Kind in [cfSketch, cfPlane, cfAxis, cfOrigin]) then
      begin
        Deps := F.Dependencies;
        for K := 0 to High(Deps) do
        begin
          G := Doc.FindById(Deps[K]);
          if (G is TCadSketch) and (ConsumerIndex(Doc, G.Id) = I) then
          begin
            Sub := Tree.Items.AddChildObject(N, G.Name, Pointer(PtrInt(G.Id)));
            if G.Id = Sel then
              Sub.Selected := True;
          end;
        end;
      end;
      if F.Id = Sel then
        N.Selected := True;
    end;
    AddRollback;
    Root.Expand(False);
  finally
    Tree.Items.EndUpdate;
    FRefreshingTree := False;
  end;
end;

function TMainForm.NodeFeature(N: TTreeNode): TCadFeature;
var
  V: PtrInt;
begin
  Result := nil;
  if N = nil then
    Exit;
  V := PtrInt(N.Data);
  if V > 0 then
    Result := Doc.FindById(V);
end;

function TMainForm.SelectedFeature: TCadFeature;
begin
  Result := NodeFeature(Tree.Selected);
end;

procedure TMainForm.TreeCustomDraw(Sender: TCustomTreeView; Node: TTreeNode;
  State: TCustomDrawState; var DefaultDraw: Boolean);
var
  F: TCadFeature;
  I: Integer;
begin
  DefaultDraw := True;
  if PtrInt(Node.Data) = NODE_ROLLBACK then
  begin
    Sender.Canvas.Font.Color := clSuitePrimary;
    Sender.Canvas.Font.Style := [fsBold];
    Exit;
  end;
  Sender.Canvas.Font.Style := [];
  F := NodeFeature(Node);
  if F = nil then
    Exit;
  I := Doc.IndexOfId(F.Id);
  if F.Suppressed or ((Doc.RollbackIndex >= 0) and (I >= Doc.RollbackIndex)) then
    Sender.Canvas.Font.Color := clSuiteFaint
  else if F.State = fsError then
    Sender.Canvas.Font.Color := clSuiteDanger
  else if F.State = fsWarning then
    Sender.Canvas.Font.Color := clSuiteWarning
  else if (F is TCadSketch) and View.IsHidden(F.Id) then
    Sender.Canvas.Font.Color := clSuiteMuted;
end;

procedure TMainForm.SyncSelectionFromTree;
var
  F: TCadFeature;
begin
  View.Selected.Clear;
  F := SelectedFeature;
  CadLogFeature('SELECT.TREE',F);
  if F = nil then
  begin
    View.HighlightPrefix := '';
    View.Redraw;
    Exit;
  end;
  View.HighlightPrefix := '';
  case F.Kind of
    cfPlane:
      begin
        View.Selected.Add('plane:' + IntToStr(F.Id));
        { Plano selecionado deve ficar visivel na vista 3D, inclusive os
          planos padrao que normalmente ficam ocultos. }
        if (F is TCadPlane) and (TCadPlane(F).PlaneType = ptStandard) then
          View.ShowStdPlane(F.Id, True)
        else
          View.SetHidden(F.Id, False);
      end;
    cfAxis: View.Selected.Add('axis:' + IntToStr(F.Id));
    cfSketch: View.Selected.Add('sketch:' + IntToStr(F.Id));
    cfOrigin: View.Selected.Add('origin');
  else
    View.HighlightPrefix := F.Name + '/';
  end;
  View.Redraw;
  if F.Message <> '' then
    SetStatus(0, F.Name + ': ' + F.Message)
  else
    SetStatus(0, F.Name);
end;

procedure TMainForm.TreeSelect(Sender: TObject; Node: TTreeNode);
begin
  if FRefreshingTree or PM.Visible then
    Exit;
  SyncSelectionFromTree;
end;

procedure TMainForm.TreeDblClick(Sender: TObject);
var
  F: TCadFeature;
begin
  if Tree.Selected = nil then
    Exit;
  if PtrInt(Tree.Selected.Data) = NODE_MATERIAL then
  begin
    ChooseMaterial;
    Exit;
  end;
  F := SelectedFeature;
  if F = nil then
    Exit;
  if F is TCadPlane then
  begin
    { Duplo clique em qualquer plano orienta a camera normal a ele. A edicao
      de plano criado continua disponivel pelo menu "Editar operacao". }
    View.Selected.Clear;
    View.Selected.Add('plane:' + IntToStr(F.Id));
    if TCadPlane(F).PlaneType = ptStandard then
      View.ShowStdPlane(F.Id, True)
    else
      View.SetHidden(F.Id, False);
    NormalToRef('plane:' + IntToStr(F.Id));
  end
  else if F is TCadSketch then
    EditSketch(TCadSketch(F))
  else if (F is TCadExtrude) or (F is TCadRevolve) or (F is TCadHole) or
    (F is TCadPatternBase) then
    BeginEdit(F, False);
end;

procedure TMainForm.TreeEditing(Sender: TObject; Node: TTreeNode; var AllowEdit: Boolean);
var
  F: TCadFeature;
begin
  F := NodeFeature(Node);
  AllowEdit := Assigned(F) and (F.Kind <> cfOrigin) and not PM.Visible and not Assigned(FEditor);
  if PtrInt(Node.Data) = NODE_PART then
    AllowEdit := True;
end;

procedure TMainForm.TreeEdited(Sender: TObject; Node: TTreeNode; var S: string);
var
  F: TCadFeature;
begin
  S := Trim(S);
  if PtrInt(Node.Data) = NODE_PART then
  begin
    if S <> '' then
    begin
      Doc.Name := S;
      Modified;
    end;
    Exit;
  end;
  F := NodeFeature(Node);
  if (F = nil) or (S = '') or (S = F.Name) then
  begin
    if Assigned(F) then
      S := F.Name;
    Exit;
  end;
  if Doc.FindByName(S) <> nil then
  begin
    CadMessageDlg('Já existe uma operação chamada "' + S + '"', mtWarning, [mbOK], 0);
    S := F.Name;
    Exit;
  end;
  RenameFeature(F, S);
  S := F.Name;
end;

procedure TMainForm.RenameFeature(F: TCadFeature; const ANew: string);
var
  Old, J, Err, OldJ, NewJ: string;
  Id: Integer;
begin
  { nomes de faces ("Extrude1/fim") e cotas ("D1@Esboço1") usam o nome:
    atualiza todas as referencias do documento }
  Old := F.Name;
  Id := F.Id;
  J := Doc.ToJSON;
  OldJ := StringToJSONString(Old);
  NewJ := StringToJSONString(ANew);
  J := StringReplace(J, '"' + OldJ + '"', '"' + NewJ + '"', [rfReplaceAll]);
  J := StringReplace(J, 'face:' + OldJ + '/', 'face:' + NewJ + '/', [rfReplaceAll]);
  J := StringReplace(J, '@' + OldJ, '@' + NewJ, [rfReplaceAll]);
  if Doc.LoadFromJSON(J, Err) then
  begin
    RB.Invalidate;
    Modified;
    RebuildModel;
    F := Doc.FindById(Id);
  end
  else
    CadMessageDlg('Não foi possível renomear: ' + Err, mtError, [mbOK], 0);
end;

procedure TMainForm.TreeMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  N: TTreeNode;
begin
  if Button = mbRight then
  begin
    N := Tree.GetNodeAt(X, Y);
    if Assigned(N) then
      N.Selected := True;
  end;
end;

procedure TMainForm.MenuPopup(Sender: TObject);
var
  F: TCadFeature;
  I: Integer;
  IsRoll: Boolean;
begin
  F := SelectedFeature;
  IsRoll := Assigned(Tree.Selected) and (PtrInt(Tree.Selected.Data) = NODE_ROLLBACK);
  for I := 0 to TreeMenu.Items.Count - 1 do
    TreeMenu.Items[I].Enabled := Assigned(F) and not PM.Visible and not Assigned(FEditor);
  TreeMenu.Items[0].Enabled := TreeMenu.Items[0].Enabled and
    ((F is TCadExtrude) or (F is TCadRevolve) or (F is TCadHole) or (F is TCadPatternBase) or
    ((F is TCadPlane) and (TCadPlane(F).PlaneType <> ptStandard)));
  TreeMenu.Items[1].Enabled := TreeMenu.Items[1].Enabled and (F is TCadSketch);
  if Assigned(F) and F.Suppressed then
    TreeMenu.Items[3].Caption := 'Cancelar supressão'
  else
    TreeMenu.Items[3].Caption := 'Suprimir';
  if Assigned(F) and View.IsHidden(F.Id) then
    TreeMenu.Items[4].Caption := 'Mostrar'
  else
    TreeMenu.Items[4].Caption := 'Ocultar';
  TreeMenu.Items[4].Enabled := TreeMenu.Items[4].Enabled and ((F is TCadSketch) or (F is TCadPlane));
  TreeMenu.Items[3].Enabled := TreeMenu.Items[3].Enabled and not (F.Kind in [cfOrigin]) and
    not ((F is TCadPlane) and (TCadPlane(F).PlaneType = ptStandard));
  TreeMenu.Items[9].Enabled := (Doc.RollbackIndex >= 0) or IsRoll;
  TreeMenu.Items[10].Enabled := Assigned(F) and ((F is TCadSketch) or (F is TCadPlane)) and
    not Assigned(FEditor);
  TreeMenu.Items[12].Enabled := (F is TCadPlane) and not PM.Visible and not Assigned(FEditor);
end;

procedure TMainForm.MenuEdit(Sender: TObject);
var
  F: TCadFeature;
begin
  F := SelectedFeature;
  if Assigned(F) then
    BeginEdit(F, False);
end;

procedure TMainForm.MenuEditSketch(Sender: TObject);
var
  F: TCadFeature;
begin
  F := SelectedFeature;
  if F is TCadSketch then
    EditSketch(TCadSketch(F));
end;

procedure TMainForm.MenuSuppress(Sender: TObject);
var
  F: TCadFeature;
begin
  F := SelectedFeature;
  if F = nil then
    Exit;
  F.Suppressed := not F.Suppressed;
  Modified;
  RebuildModel;
end;

procedure TMainForm.MenuHide(Sender: TObject);
var
  F: TCadFeature;
begin
  F := SelectedFeature;
  if F = nil then
    Exit;
  View.SetHidden(F.Id, not View.IsHidden(F.Id));
  if (F is TCadPlane) and (TCadPlane(F).PlaneType = ptStandard) then
    View.ShowStdPlane(F.Id, View.IsHidden(F.Id) = False);
  Tree.Invalidate;
end;

procedure TMainForm.MenuRename(Sender: TObject);
begin
  if Assigned(Tree.Selected) then
    Tree.Selected.EditText;
end;

procedure TMainForm.MenuDelete(Sender: TObject);
var
  F: TCadFeature;
  Err: string;
begin
  F := SelectedFeature;
  if F = nil then
    Exit;
  if CadMessageDlg('Excluir "' + F.Name + '"?', mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
    Exit;
  if not Doc.DeleteFeature(F.Id, Err) then
  begin
    CadMessageDlg(Err, mtWarning, [mbOK], 0);
    Exit;
  end;
  View.Selected.Clear;
  View.HighlightPrefix := '';
  Modified;
  RebuildModel;
end;

procedure TMainForm.MenuRollHere(Sender: TObject);
var
  F: TCadFeature;
begin
  F := SelectedFeature;
  if F = nil then
    Exit;
  Doc.RollbackIndex := Doc.IndexOfId(F.Id);
  Modified;
  RebuildModel;
end;

procedure TMainForm.MenuRollEnd(Sender: TObject);
begin
  Doc.RollbackIndex := -1;
  Modified;
  RebuildModel;
end;

procedure TMainForm.MenuNormalTo(Sender: TObject);
begin
  SyncSelectionFromTree;
  NormalToClick(nil);
end;

procedure TMainForm.ChooseMaterial;
var
  M: string;
  C: Integer;
begin
  M := Doc.Material;
  C := Doc.MaterialColor;
  if not CadChooseMaterial(Self, M, C) then
    Exit;
  Doc.Material := M;
  Doc.MaterialColor := C;
  Modified;
  View.SetAppearance(Doc.AppearanceColor, CadTextureIndex(Doc.MaterialData.Texture));
  RefreshTree;
  UpdatePartStatus;
end;

procedure TMainForm.RefreshModel;
begin
  RebuildModel;
end;

procedure TMainForm.MarkModified;
begin
  Modified;
end;

procedure TMainForm.DoUndo;
begin
  UndoClick(nil);
end;

procedure TMainForm.DoRedo;
begin
  RedoClick(nil);
end;

procedure TMainForm.ApplyMaterial(const AName: string; AColor: Integer);
begin
  Doc.Material := AName;
  Doc.MaterialColor := AColor;
  Modified;
  View.SetAppearance(Doc.AppearanceColor, CadTextureIndex(Doc.MaterialData.Texture));
  RefreshTree;
  UpdatePartStatus;
end;

procedure TMainForm.MaterialMenuEdit(Sender: TObject);
begin
  ChooseMaterial;
end;

procedure TMainForm.MaterialMenuDefault(Sender: TObject);
begin
  Doc.Material := CAD_DEFAULT_MATERIAL;
  Doc.MaterialColor := -1;
  Modified;
  View.SetAppearance(Doc.AppearanceColor, CadTextureIndex(Doc.MaterialData.Texture));
  RefreshTree;
  UpdatePartStatus;
end;

procedure TMainForm.PartMenuRename(Sender: TObject);
begin
  if Assigned(Tree.Items.GetFirstNode) then
    Tree.Items.GetFirstNode.EditText;
end;

procedure TMainForm.MenuSketchOnPlane(Sender: TObject);
var
  F: TCadFeature;
begin
  F := SelectedFeature;
  if F is TCadPlane then
    StartSketch('plane:' + IntToStr(F.Id));
end;

procedure TMainForm.TreeContextPopup(Sender: TObject; MousePos: TPoint; var Handled: Boolean);
var
  N: TTreeNode;
  P: TPoint;
begin
  N := Tree.GetNodeAt(MousePos.X, MousePos.Y);
  if N = nil then
    Exit;
  N.Selected := True;
  P := Tree.ClientToScreen(MousePos);
  case PtrInt(N.Data) of
    NODE_MATERIAL:
      begin
        MatMenu.PopUp(P.X, P.Y);
        Handled := True;
      end;
    NODE_PART:
      begin
        PartMenu.PopUp(P.X, P.Y);
        Handled := True;
      end;
  end;
end;

{ ---------- arquivo ---------- }

function TMainForm.ConfirmDiscard: Boolean;
begin
  if Assigned(FEditor) then
    ExitSketch(nil);
  if PM.Visible then
    EndEdit(False);
  Result := True;
  if not Doc.Modified then
    Exit;
  case CadMessageDlg('Salvar as alterações em "' + Doc.Name + '"?', mtConfirmation,
    [mbYes, mbNo, mbCancel], 0) of
    mrYes:
      begin
        SaveClick(nil);
        Result := not Doc.Modified;
      end;
    mrNo: Result := True;
  else
    Result := False;
  end;
end;

procedure TMainForm.ApplicationError(Sender: TObject; E: Exception);
begin
  CadLogException('Application',E);
  Application.ShowException(E);
end;

procedure TMainForm.AboutClick(Sender: TObject);
var S: string;
begin
  S:='MultiCAD - Maurinsoft / MultiSuite'+LineEnding+
    'Modelagem paramétrica de peças: esboços, extrusões, cortes e revoluções.'+LineEnding+LineEnding+
    'Versão do executável: '+CadExecutableVersion+LineEnding+
    'Compilação: '+{$I %DATE%}+' '+{$I %TIME%}+LineEnding+
    'Executável: '+ParamStr(0)+LineEnding+'Log: '+CadLogPath+LineEnding+
    'Núcleo geométrico: '+KernelText;
  if CadLogError<>'' then S:=S+LineEnding+'Falha no log: '+CadLogError;
  CadMessageDlg('Sobre o MultiCAD',S,mtInformation,[mbOK],0);
end;

procedure TMainForm.LogClick(Sender: TObject);
begin
  if (CadLogPath='') or not FileExists(CadLogPath) then
    CadMessageDlg('Log indisponivel: '+CadLogError,mtWarning,[mbOK],0)
  else if not OpenDocument(CadLogPath) then
    CadMessageDlg('Nao foi possivel abrir o log: '+CadLogPath,mtWarning,[mbOK],0);
end;

procedure TMainForm.NewClick(Sender: TObject);
begin
  if not ConfirmDiscard then
    Exit;
  CadLog('DOCUMENT.NEW','nova peca');
  FLastSketchId:=0;FPendingSketch:=False;
  Tree.Selected:=nil;
  Doc.NewPart;
  RB.Invalidate;
  View.Selected.Clear;
  RebuildModel;
  View.SetView(svIso);
  UpdateCaption;
  ResetUndo;
end;

function TMainForm.OpenFile(const AFile: string): Boolean;
var
  Err: string;
begin
  if PM.Visible then EndEdit(False);
  if Assigned(FEditor) then ExitSketch(nil);
  CadLog('DOCUMENT.OPEN',AFile);
  Result := Doc.LoadFromFile(AFile, Err);
  if not Result then
  begin
    CadLog('ERROR.FILE',AFile+': '+Err);
    CadMessageDlg('Não foi possível abrir "' + AFile + '":' + LineEnding + Err, mtError, [mbOK], 0);
    Exit;
  end;
  FLastSketchId:=0;FPendingSketch:=False;
  Tree.Selected:=nil;
  RB.Invalidate;
  View.Selected.Clear;
  RebuildModel;
  View.SetView(svIso);
  UpdateCaption;
  ResetUndo;
end;

procedure TMainForm.OpenClick(Sender: TObject);
var
  D: TOpenDialog;
begin
  if not ConfirmDiscard then
    Exit;
  D := TOpenDialog.Create(Self);
  try
    D.Filter := 'Peça MultiCAD (*.mcad)|*.mcad|Todos os arquivos|*.*';
    if D.Execute then
      OpenFile(D.FileName);
  finally
    D.Free;
  end;
end;

function TMainForm.SaveTo(const AFile: string): Boolean;
var
  Err: string;
begin
  CadLog('DOCUMENT.SAVE',AFile);
  Result := Doc.SaveToFile(AFile, Err);
  if not Result then
  begin
    CadLog('ERROR.FILE',AFile+': '+Err);
    CadMessageDlg('Não foi possível salvar:' + LineEnding + Err, mtError, [mbOK], 0);
  end;
  UpdateCaption;
end;

procedure TMainForm.SaveClick(Sender: TObject);
begin
  if Doc.FileName = '' then
    SaveAsClick(Sender)
  else
    SaveTo(Doc.FileName);
end;

procedure TMainForm.SaveAsClick(Sender: TObject);
var
  D: TSaveDialog;
begin
  D := TSaveDialog.Create(Self);
  try
    D.Filter := 'Peça MultiCAD (*.mcad)|*.mcad';
    D.DefaultExt := 'mcad';
    D.FileName := Doc.Name + MCAD_EXT;
    D.Options := D.Options + [ofOverwritePrompt];
    if D.Execute then
      SaveTo(D.FileName);
  finally
    D.Free;
  end;
end;

procedure TMainForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  CadLog('WINDOW.CLOSE_REQUEST',Caption);
  CanClose := ConfirmDiscard;
  CadLog('WINDOW.CLOSE_ALLOWED',BoolToStr(CanClose,True));
end;

{ ---------- esboco ---------- }

function TMainForm.SelectedPlaneRef: string;
var
  I: Integer;
  S: string;
begin
  Result := '';
  for I := 0 to View.Selected.Count - 1 do
  begin
    S := View.Selected[I];
    if (Pos('plane:', S) = 1) or (Pos('face:', S) = 1) then
      Exit(S);
  end;
end;

procedure TMainForm.SketchClick(Sender: TObject);
var
  R: string;
begin
  if Assigned(FEditor) or PM.Visible then
    Exit;
  { o plano marcado (na arvore ou na vista) e o plano do esboco }
  R := SelectedPlaneRef;
  if (R = '') and (SelectedFeature is TCadPlane) then
    R := 'plane:' + IntToStr(SelectedFeature.Id);
  if R <> '' then
  begin
    StartSketch(R);
    Exit;
  end;
  ChoosePlaneForSketch;
end;

procedure TMainForm.ChoosePlaneForSketch;
var
  F: TForm;
  L: TListBox;
  B: TButton;
  Lb: TLabel;
  I: Integer;
  Ids: array of Integer;
  R: TModalResult;
begin
  { nada marcado: escolher o plano (ou clicar numa face plana na vista) }
  F := TForm.CreateNew(Self);
  try
    F.Caption := 'Plano do esboço';
    F.BorderStyle := bsDialog;
    F.Position := poOwnerFormCenter;
    F.Width := 340;
    F.Height := 320;
    Lb := TLabel.Create(F);
    Lb.Parent := F;
    Lb.SetBounds(12, 10, 316, 18);
    Lb.Caption := 'Escolha o plano onde desenhar:';
    L := TListBox.Create(F);
    L.Parent := F;
    L.SetBounds(12, 32, 316, 190);
    SetLength(Ids, 0);
    for I := 0 to Doc.Count - 1 do
      if (Doc.Feature(I) is TCadPlane) and not Doc.Feature(I).Suppressed then
      begin
        L.Items.Add(Doc.Feature(I).Name);
        SetLength(Ids, Length(Ids) + 1);
        Ids[High(Ids)] := Doc.Feature(I).Id;
      end;
    L.ItemIndex := 0;
    B := TButton.Create(F);
    B.Parent := F;
    B.SetBounds(12, 234, 316, 30);
    B.Caption := 'Clicar numa face plana da peça...';
    B.ModalResult := mrRetry;
    B := TButton.Create(F);
    B.Parent := F;
    B.SetBounds(150, 270, 86, 30);
    B.Caption := 'Esboçar';
    B.Default := True;
    B.ModalResult := mrOK;
    B := TButton.Create(F);
    B.Parent := F;
    B.SetBounds(242, 270, 86, 30);
    B.Caption := 'Cancelar';
    B.Cancel := True;
    B.ModalResult := mrCancel;
    L.OnDblClick := nil;
    R := F.ShowModal;
    if (R = mrOK) and (L.ItemIndex >= 0) then
    begin
      StartSketch('plane:' + IntToStr(Ids[L.ItemIndex]));
      Exit;
    end;
    if R <> mrRetry then
      Exit;
  finally
    F.Free;
  end;
  { escolher na vista: mostra os planos padrao e espera o clique }
  FPendingSketch := True;
  View.PickEdges := False;
  View.ShowStdPlane(MCAD_ID_FRONTAL, True);
  View.ShowStdPlane(MCAD_ID_SUPERIOR, True);
  View.ShowStdPlane(MCAD_ID_LATERAL, True);
  View.Selected.Clear;
  SetStatus(1, 'Selecione um plano ou uma face plana para o esboço (Esc cancela)');
end;

procedure TMainForm.StartSketch(const APlaneRef: string);
var
  S: TCadSketch;
  Fr: TCadFrame;
  Err: string;
begin
  CadLog('SKETCH.CREATE',APlaneRef);
  FPendingSketch := False;
  View.PickEdges := True;
  View.ShowStdPlane(MCAD_ID_FRONTAL, False);
  View.ShowStdPlane(MCAD_ID_SUPERIOR, False);
  View.ShowStdPlane(MCAD_ID_LATERAL, False);
  if not RB.ResolvePlane(APlaneRef, Fr, Err) then
  begin
    CadMessageDlg('Não dá para esboçar em "' + APlaneRef + '": ' + Err, mtWarning, [mbOK], 0);
    Exit;
  end;
  S := Doc.AddSketch(APlaneRef);
  Modified;
  RebuildModel;
  EditSketch(S);
end;

procedure TMainForm.EditSketch(S: TCadSketch);
begin
  CadLogFeature('SKETCH.EDIT',S);
  if PM.Visible then
    EndEdit(False);
  FreeAndNil(FEditor);
  View.Selected.Clear;
  View.HighlightPrefix := '';
  FEditor := TCadSketchEditor.Create(View, Doc, RB, S);
  FEditor.OnChanged := @EditorChanged;
  FEditor.OnStatus := @EditorStatus;
  FEditor.NormalTo;
  FEditor.SetTool(tkLine);
  ShowTab(ctSketch);
  EditorStatus(nil);
  UpdateSketchPanel;
end;

procedure TMainForm.ExitSketch(Sender: TObject);
var
  S: TCadSketch;
  I: Integer;
begin
  if FEditor = nil then
    Exit;
  S := FEditor.Sketch;
  CadLogFeature('SKETCH.EXIT',S);
  if Assigned(S) then
    FLastSketchId := S.Id;
  FreeAndNil(FEditor);
  View.Selected.Clear;
  if FLastSketchId > 0 then
    View.Selected.Add('sketch:' + IntToStr(FLastSketchId));
  SetStatus(0, '');
  UpdateSketchPanel;
  RebuildModel;
  { The tree and viewport must point to the sketch just completed. }
  for I:=0 to Tree.Items.Count-1 do
    if PtrInt(Tree.Items[I].Data)=FLastSketchId then
    begin Tree.Selected:=Tree.Items[I];Tree.Items[I].MakeVisible;Break;end;
  ShowTab(ctFeatures);
end;

procedure TMainForm.ToolClick(Sender: TObject);
var
  T: TCadSketchToolKind;
  P: TCadVec2;
  Txt, Err: string;
  D1, D2: Double;
  K: Integer;
begin
  if FEditor = nil then
    Exit;
  T := TCadSketchToolKind(TComponent(Sender).Tag);
  { chanfro com duas linhas (ou o ponto do canto) ja selecionadas:
    aplica direto, como no SolidWorks }
  if (T = tkChamfer) and FEditor.Session.CornerFromSelection(P) then
  begin
    Txt := FormatFloat('0.###', FEditor.Session.ChamferD1);
    if InputQuery('Chanfro', 'Distância ou "d1 x d2" (mm):', Txt) then
    begin
      Txt := StringReplace(LowerCase(Trim(Txt)), '×', 'x', [rfReplaceAll]);
      K := Pos('x', Txt);
      if K > 0 then
      begin
        if Doc.Eval(Copy(Txt, 1, K - 1), D1, Err) and Doc.Eval(Copy(Txt, K + 1, MaxInt), D2, Err) then
          FEditor.Session.ChamferCorner(P, D1, D2);
      end
      else if Doc.Eval(Txt, D1, Err) then
        FEditor.Session.ChamferCorner(P, D1, D1);
    end;
    FEditor.Session.ClearSelection;
    FEditor.View3DChanged;
  end;
  FEditor.SetTool(T);
  ShowTab(ctSketch);
end;

procedure TMainForm.RelationClick(Sender: TObject);
begin
  if FEditor = nil then
    Exit;
  FEditor.AddRelation(TConstraintKind(TComponent(Sender).Tag));
end;

procedure TMainForm.RelationMenuClick(Sender: TObject);
var
  P: TPoint;
begin
  if FEditor = nil then
    Exit;
  P := TControl(Sender).ClientToScreen(Point(0, TControl(Sender).Height));
  RelMenu.PopUp(P.X, P.Y);
end;

procedure TMainForm.GridClick(Sender: TObject);
begin
  if Assigned(FEditor) then
  begin
    FEditor.SetGrid(not FEditor.Grid, FEditor.Session.GridSnap);
    ShowTab(ctSketch);
  end;
end;

procedure TMainForm.GridSnapClick(Sender: TObject);
begin
  if Assigned(FEditor) then
  begin
    FEditor.SetGrid(True, not FEditor.Session.GridSnap);
    ShowTab(ctSketch);
  end;
end;

procedure TMainForm.PrevViewClick(Sender: TObject);
begin
  View.PreviousView;
end;

procedure TMainForm.WheelClick(Sender: TObject);
begin
  View.ReverseWheel := not View.ReverseWheel;
  SaveSettings;
  ShowTab(ctView);
end;

function SettingsFile: string;
begin
  Result := IncludeTrailingPathDelimiter(GetAppConfigDir(False)) + 'multicad.ini';
end;

procedure TMainForm.LoadSettings;
var
  L: TStringList;
begin
  if not FileExists(SettingsFile) then
    Exit;
  L := TStringList.Create;
  try
    try
      L.LoadFromFile(SettingsFile);
      View.ReverseWheel := L.Values['reverse_wheel'] = '1';
      RB.UseOcct := L.Values['kernel'] <> 'pascal';
    except
      on E:Exception do CadLogException('ler configuracao '+SettingsFile,E);
    end;
  finally
    L.Free;
  end;
end;

procedure TMainForm.SaveSettings;
var
  L: TStringList;
begin
  L := TStringList.Create;
  try
    try
      ForceDirectories(ExtractFilePath(SettingsFile));
      if View.ReverseWheel then
        L.Values['reverse_wheel'] := '1'
      else
        L.Values['reverse_wheel'] := '0';
      if RB.UseOcct then
        L.Values['kernel'] := 'occt'
      else
        L.Values['kernel'] := 'pascal';
      L.SaveToFile(SettingsFile);
    except
      on E:Exception do CadLogException('salvar configuracao '+SettingsFile,E);
    end;
  finally
    L.Free;
  end;
end;

procedure TMainForm.FormKeyPress(Sender: TObject; var Key: Char);
begin
  { com a ferramenta no meio (1 clique), digitar um numero abre a caixa da
    medida, como no SolidWorks }
  if Assigned(FEditor) and not FEditor.Typing and not (ActiveControl is TCustomEdit) and
    (Key in ['0'..'9', '.', ',']) and FEditor.Session.CanType then
  begin
    if FEditor.BeginTyping(Key) then
      Key := #0;
  end;
end;

procedure TMainForm.DeleteSketchClick(Sender: TObject);
begin
  if Assigned(FEditor) then
    FEditor.DeleteSelection;
end;

procedure TMainForm.EditorChanged(Sender: TObject);
begin
  if FEditor<>nil then CadLogFeature('SKETCH.CHANGE',FEditor.Sketch);
  Modified;
  UpdateSketchPanel;
end;

procedure TMainForm.UpdateSketchPanel;
var
  St: Integer;
  T, HintText: string;
  Tool, K: TCadSketchToolKind;
  DrawGeometry: Boolean;
begin
  SketchPanel.Visible := Assigned(FEditor);
  if FEditor = nil then
    Exit;
  FUpdatingPanel := True;
  try
    SketchTitle.Caption := 'Esboço: ' + FEditor.Sketch.Name;
    Tool := FEditor.Session.Tool;
    T := FEditor.Session.SelectionText;
    St := FEditor.Session.SelectionConstructionState;
    if T = '' then T := 'Nada selecionado.';
    SketchSel.Caption := CAD_TOOL_NAMES[Tool] + LineEnding + T;
    DrawGeometry := Tool in [tkLine, tkRectangle, tkCircle, tkArc3P,
      tkCenterline, tkPoint, tkArcCenter, tkArcTangent];
    LineKind.Visible := DrawGeometry or ((Tool=tkSelect) and (St<>0));
    if Tool in [tkLine, tkCenterline] then begin
      LineKind.Caption := 'Tipo de linha';
      if LineKind.Items[0]<>'Linha normal (contorno da peça)' then begin
        LineKind.Items[0] := 'Linha normal (contorno da peça)';
        LineKind.Items[1] := 'Linha de apoio (tracejada)';
      end;
    end else begin
      LineKind.Caption := 'Tipo de geometria';
      if LineKind.Items[0]<>'Contorno da peça' then begin
        LineKind.Items[0] := 'Contorno da peça';
        LineKind.Items[1] := 'Geometria de apoio (tracejada)';
      end;
    end;
    if LineKind.Visible then begin
      SketchHint.Height := 36;
      if (Tool=tkSelect) and (St<>0) then
        HintText := 'A escolha altera a geometria selecionada.'
      else HintText := 'A escolha vale para a próxima geometria desenhada.';
    end else begin
      SketchHint.Height := 110;
      case Tool of
        tkDimension: HintText := 'Selecione uma reta, círculo ou dois pontos. Mova o mouse para escolher X, Y ou comprimento real e clique para confirmar. Também aceita pontos de esboços anteriores visíveis.';
        tkTrim: HintText := 'Clique no trecho de reta que deseja remover, entre as interseções mais próximas. Sem interseções, remove a reta inteira. Esc termina; Ctrl+Z desfaz.';
        tkChamfer: HintText := 'Clique perto do encontro de duas retas para aplicar o chanfro. Digite as distâncias durante a operação.';
      else
        HintText := 'Clique na geometria para selecioná-la. Selecione uma linha ou curva para consultar suas propriedades e trocar o tipo.';
      end;
    end;
    SketchHint.Caption := HintText;
    for K := Low(TCadSketchToolKind) to High(TCadSketchToolKind) do
      if Assigned(FToolButtons[K]) then
        if K=Tool then FToolButtons[K].SetLook(sbsSolid, clSuitePrimary)
        else FToolButtons[K].SetLook(sbsSoft, clSuitePrimary);
    case St of
      1: LineKind.ItemIndex := 0;
      2: LineKind.ItemIndex := 1;
      3: LineKind.ItemIndex := -1;
    else
      if FEditor.Session.ConstructionMode then
        LineKind.ItemIndex := 1
      else
        LineKind.ItemIndex := 0;
    end;
  finally
    FUpdatingPanel := False;
  end;
end;

procedure TMainForm.LineKindClick(Sender: TObject);
begin
  if FUpdatingPanel or (FEditor = nil) or (LineKind.ItemIndex < 0) then
    Exit;
  if FEditor.Session.SelectionConstructionState <> 0 then
    FEditor.Session.SetSelectionConstruction(LineKind.ItemIndex = 1)
  else
    FEditor.Session.ConstructionMode := LineKind.ItemIndex = 1;
  FEditor.View3DChanged;
  Modified;
  UpdateSketchPanel;
end;

procedure TMainForm.EditorStatus(Sender: TObject);
begin
  if Assigned(FEditor) then
  begin
    SetStatus(1, FEditor.StatusText);
    SetStatus(0, CAD_TOOL_NAMES[FEditor.Session.Tool] + '   |   ' + FEditor.CursorText);
  end;
end;

{ ---------- operacoes ---------- }

function TMainForm.FindSketchForFeature: TCadSketch;
var
  I, Id: Integer;
  F: TCadFeature;
begin
  Result := nil;
  if Assigned(FEditor) then
  begin
    Result := FEditor.Sketch;
    ExitSketch(nil);
    Exit;
  end;
  for I := 0 to View.Selected.Count - 1 do
    if Pos('sketch:', View.Selected[I]) = 1 then
    begin
      Id := StrToIntDef(Copy(View.Selected[I], 8, MaxInt), 0);
      F := Doc.FindById(Id);
      if F is TCadSketch then Exit(TCadSketch(F));
    end;
  F := SelectedFeature;
  if F is TCadSketch then Exit(TCadSketch(F));
  if FLastSketchId > 0 then
  begin
    F := Doc.FindById(FLastSketchId);
    if (F is TCadSketch) and (ConsumerIndex(Doc, FLastSketchId) < 0) and
      (TCadSketch(F).EntityCount > 0) then Exit(TCadSketch(F));
    FLastSketchId := 0;
  end;
  { o ultimo esboco ainda nao usado }
  for I := Doc.Count - 1 downto 0 do
    if (Doc.Feature(I) is TCadSketch) and (ConsumerIndex(Doc, Doc.Feature(I).Id) < 0) and
      (TCadSketch(Doc.Feature(I)).EntityCount > 0) then
      Exit(TCadSketch(Doc.Feature(I)));
end;

procedure TMainForm.ExtrudeClick(Sender: TObject);
var
  S: TCadSketch;
  X: TCadExtrude;
  IsCut: Boolean;
begin
  if PM.Visible then
  begin
    CadLog('COMMAND.BLOCKED','extrusao: confirme ou cancele a operacao aberta');
    SetStatus(0,'Confirme (OK) ou cancele a operação aberta antes de criar outro corte ou ressalto.');
    Exit;
  end;
  IsCut := Sender = nil;
  S := FindSketchForFeature;
  if S = nil then
  begin
    CadLog('ERROR.SELECTION','extrusao: nenhum esboco disponivel; view='+View.Selected.CommaText);
    CadMessageDlg('Selecione um esboço (ou crie um na aba Esboço).', mtInformation, [mbOK], 0);
    Exit;
  end;
  CadLogFeature('EXTRUDE.SKETCH cut='+BoolToStr(IsCut,True),S);
  X := Doc.AddExtrude(S.Id, 10, IsCut);
  BeginEdit(X, True);
end;

procedure TMainForm.CutClick(Sender: TObject);
begin
  ExtrudeClick(nil);
end;

procedure TMainForm.RevolveClick(Sender: TObject);
var
  S: TCadSketch;
  R: TCadRevolve;
begin
  if PM.Visible then
    Exit;
  S := FindSketchForFeature;
  if S = nil then
  begin
    CadMessageDlg('Selecione um esboço com uma linha de centro.', mtInformation, [mbOK], 0);
    Exit;
  end;
  R := Doc.AddRevolve(S.Id, 360, Sender = nil);
  BeginEdit(R, True);
end;

procedure TMainForm.RevolveCutClick(Sender: TObject);
begin
  RevolveClick(nil);
end;

procedure TMainForm.PlaneClick(Sender: TObject);
var
  R: string;
  P: TCadPlane;
begin
  if PM.Visible or Assigned(FEditor) then
    Exit;
  R := SelectedPlaneRef;
  if R = '' then
    R := 'plane:' + IntToStr(MCAD_ID_FRONTAL);
  P := Doc.AddPlane(ptOffset, [R], 10);
  BeginEdit(P, True);
end;

function TMainForm.SelectedFaceRef: string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to View.Selected.Count - 1 do
    if Pos('face:', View.Selected[I]) = 1 then
      Exit(View.Selected[I]);
end;

function FaceCentroid(M: TCadMesh; AFace: Integer): TCadVec3;
var
  I: Integer;
  T: TCadTri;
  A, W: Double;
  C: TCadVec3;
begin
  C := V3(0, 0, 0);
  W := 0;
  for I := 0 to M.TriCount - 1 do
  begin
    T := M.Tris[I];
    if T.Face <> AFace then
      Continue;
    A := M.TriArea(I);
    C := VAdd(C, VScale(VAdd(VAdd(M.Verts[T.A], M.Verts[T.B]), M.Verts[T.C]), A / 3));
    W := W + A;
  end;
  if W > 0 then
    Result := VScale(C, 1 / W)
  else
    Result := C;
end;

procedure TMainForm.HoleClick(Sender: TObject);
var
  S: TCadSketch;
  F: TCadFeature;
  R, Err: string;
  B: TCadBody;
  Fi, I, NPts: Integer;
  Fr: TCadFrame;
  P: TCadVec2;
  H: TCadHole;
begin
  if PM.Visible then
    Exit;
  S := nil;
  { esboco com pontos selecionado (ou em edicao) }
  if Assigned(FEditor) then
  begin
    S := FEditor.Sketch;
    ExitSketch(nil);
  end
  else
  begin
    F := SelectedFeature;
    if F is TCadSketch then
      S := TCadSketch(F);
  end;
  if Assigned(S) then
  begin
    NPts := 0;
    for I := 0 to S.EntityCount - 1 do
      if S.Entity(I).Kind in [sePoint, seCircle] then
        Inc(NPts);
    if NPts = 0 then
      S := nil;
  end;
  if S = nil then
  begin
    { face plana selecionada: esboco nela com um ponto no centro da face }
    R := SelectedFaceRef;
    if (R = '') or not RB.ResolvePlane(R, Fr, Err) then
    begin
      MessageDlg('Selecione a face plana onde vai o furo (ou um esboço com pontos).',
        mtInformation, [mbOK], 0);
      Exit;
    end;
    S := Doc.AddSketch(R);
    if RB.FindFace(Copy(R, 6, MaxInt), B, Fi) then
      P := FrameToLocal(Fr, FaceCentroid(B.Mesh, Fi))
    else
      P := V2(0, 0);
    S.AddPoint(P.X, P.Y);
    NPts := S.Id;
  end
  else
    NPts := 0;
  H := TCadHole.Create;
  H.SketchId := S.Id;
  Doc.AddFeature(H);
  BeginEdit(H, True);
  FAutoSketchId := NPts;
  SetStatus(1, 'Furo: para mudar a posição, edite o esboço ' + S.Name + ' (cotas no ponto)');
end;

function TMainForm.PatternSeeds: TCadIdArray;
var
  F: TCadFeature;
  I: Integer;
begin
  Result := nil;
  F := SelectedFeature;
  if Assigned(F) and not (F.Kind in [cfSketch, cfPlane, cfAxis, cfOrigin]) then
  begin
    SetLength(Result, 1);
    Result[0] := F.Id;
    Exit;
  end;
  { ultima operacao de solido }
  for I := Doc.Count - 1 downto 0 do
    if not (Doc.Feature(I).Kind in [cfSketch, cfPlane, cfAxis, cfOrigin]) and
      not Doc.Feature(I).Suppressed then
    begin
      SetLength(Result, 1);
      Result[0] := Doc.Feature(I).Id;
      Exit;
    end;
end;

procedure TMainForm.SketchTextClick(Sender: TObject);
var D:TCadSketchTextDialog;Ids:TCadIdArray;Error:string;I:Integer;
begin
  if not Assigned(FEditor) or PM.Visible then Exit;
  D:=TCadSketchTextDialog.CreateText(Self,Doc,FEditor.Session.Cursor.P);
  try
    if D.ShowModal<>mrOK then Exit;
    if not CadInsertSketchText(FEditor.Sketch,D.Contours,Ids,Error) then begin
      CadMessageDlg(Error,mtWarning,[mbOK],0);Exit;
    end;
    FEditor.SetTool(tkSelect);FEditor.Session.ClearSelection;
    SetLength(FEditor.Session.Selection,Length(Ids));
    for I:=0 to High(Ids) do FEditor.Session.Selection[I]:=PickItem(Ids[I],0);
    FEditor.Session.Solve;
    FEditor.View3DChanged;ShowTab(ctSketch);
    SetStatus(1,'Texto convertido em contornos vetoriais. Saia do esboço para criar uma extrusão ou corte. Ctrl+Z desfaz a inserção.');
    CadLog('SKETCH.TEXT',Format('font=%s height=%g segments=%d',[D.Settings.FontName,D.Settings.Height,Length(Ids)]));
  finally D.Free;end;
end;

procedure TMainForm.SketchPatternClick(Sender: TObject);
var D: TCadSketchPatternDialog; Kind: TCadSketchPatternKind;
begin
  if not Assigned(FEditor) or PM.Visible then Exit;
  if Length(FEditor.Session.Selection)=0 then begin
    FEditor.SetTool(tkSelect);ShowTab(ctSketch);
    SetStatus(1,'Selecione as entidades a repetir (Ctrl para somar) e clique no padrão.');
    Exit;
  end;
  Kind:=TCadSketchPatternKind(TComponent(Sender).Tag);
  D:=TCadSketchPatternDialog.CreatePattern(Self,Doc,Kind,Length(FEditor.Session.Selection));
  try
    if D.ShowModal<>mrOK then begin CadLog('SKETCH.PATTERN.CANCEL',D.Caption);Exit;end;
    if not FEditor.Session.ApplyPattern(D.Settings) then begin
      CadLog('SKETCH.PATTERN.ERROR',FEditor.Session.LastMessage);
      CadMessageDlg(FEditor.Session.LastMessage,mtWarning,[mbOK],0);Exit;
    end;
    CadLog('SKETCH.PATTERN',Format('kind=%d countX=%d countY=%d spacingX=%g spacingY=%g centerX=%g centerY=%g angle=%g',
      [Ord(Kind),D.Settings.CountX,D.Settings.CountY,D.Settings.SpacingX,D.Settings.SpacingY,
       D.Settings.Center.X,D.Settings.Center.Y,D.Settings.Angle]));
    FEditor.View3DChanged;ShowTab(ctSketch);
  finally D.Free;end;
end;

procedure TMainForm.LinearPatternClick(Sender: TObject);
var
  P: TCadLinearPattern;
begin
  if PM.Visible or Assigned(FEditor) then
    Exit;
  P := TCadLinearPattern.Create;
  P.Seeds := PatternSeeds;
  Doc.AddFeature(P);
  BeginEdit(P, True);
end;

procedure TMainForm.CircularPatternClick(Sender: TObject);
var
  P: TCadCircularPattern;
begin
  if PM.Visible or Assigned(FEditor) then
    Exit;
  P := TCadCircularPattern.Create;
  P.Seeds := PatternSeeds;
  Doc.AddFeature(P);
  BeginEdit(P, True);
end;

procedure TMainForm.MirrorClick(Sender: TObject);
var
  P: TCadMirror;
  R: string;
begin
  if PM.Visible or Assigned(FEditor) then
    Exit;
  P := TCadMirror.Create;
  P.Seeds := PatternSeeds;
  R := SelectedPlaneRef;
  if R <> '' then
    P.PlaneRef := R;
  Doc.AddFeature(P);
  BeginEdit(P, True);
end;

procedure TMainForm.BlendClick(Sender: TObject);
var
  F: TCadFeature;
  Refs: TCadStrArray;
  I: Integer;
  R: string;
begin
  if PM.Visible or Assigned(FEditor) then
    Exit;
  { o que ja estava selecionado entra na lista, como no SolidWorks }
  Refs := nil;
  for I := 0 to View.Selected.Count - 1 do
  begin
    R := View.Selected[I];
    if (Pos('face:', R) = 1) or ((Pos('edge:', R) = 1) and (TComponent(Sender).Tag <> 2)) then
    begin
      SetLength(Refs, Length(Refs) + 1);
      Refs[High(Refs)] := R;
    end;
  end;
  case TComponent(Sender).Tag of
    0:
      begin
        F := TCadFillet3D.Create;
        TCadFillet3D(F).Edges := Refs;
      end;
    1:
      begin
        F := TCadChamfer3D.Create;
        TCadChamfer3D(F).Edges := Refs;
      end;
  else
    begin
      F := TCadShell.Create;
      TCadShell(F).Faces := Refs;
    end;
  end;
  Doc.AddFeature(F);
  BeginEdit(F, True);
  if TComponent(Sender).Tag = 2 then
    SetStatus(1, 'Casca: clique nas faces que ficam abertas')
  else
    SetStatus(1, CAD_FEATURE_NAMES[F.Kind] + ': clique nas arestas (ou faces) da peça');
end;

procedure TMainForm.StartBlend(AKind: Integer);
var
  C: TComponent;
begin
  C := TComponent.Create(nil);
  try
    C.Tag := AKind;
    BlendClick(C);
  finally
    C.Free;
  end;
end;

procedure TMainForm.AcceptEdit;
begin
  PMOK(nil);
end;

procedure TMainForm.PreviewChanged;
begin
  PMChange(nil);
end;

procedure TMainForm.StopBlendEdit;
begin
  if FBlendEdit then
  begin
    Doc.RollbackIndex := FSavedRollback;
    FBlendEdit := False;
  end;
  View.SetPreview(nil, False);
  FreeAndNil(FBlendPreview);
end;

procedure TMainForm.UpdateBlendPreview;
var
  F: TCadFeature;
  Cut: Boolean;
  Err: string;
  I: Integer;
  Refs: TCadStrArray;
begin
  F := PM.Feature;
  View.SetPreview(nil, False);
  FreeAndNil(FBlendPreview);
  Refs := PM.ItemRefs;
  View.Selected.Clear;
  for I := 0 to High(Refs) do
    View.Selected.Add(Refs[I]);
  if not (F is TCadBlendBase) or (Length(Refs) = 0) then
  begin
    PM.ShowMessageText('Selecione arestas ou faces na vista', False);
    Exit;
  end;
  if F.Validate <> '' then
  begin
    PM.ShowMessageText(F.Validate, True);
    Exit;
  end;
  FBlendPreview := RB.BlendPreview(TCadBlendBase(F), Cut, Err);
  if Assigned(FBlendPreview) then
  begin
    View.SetPreview(FBlendPreview, Cut);
    if Err <> '' then
      PM.ShowMessageText('Ignorada: ' + Err, False)
    else
      PM.ShowMessageText('', False);
  end
  else
    PM.ShowMessageText(Err, True);
end;

procedure TMainForm.BeginEdit(F: TCadFeature; AIsNew: Boolean);
begin
  if Assigned(FEditor) then
    ExitSketch(nil);
  if PM.Visible then begin if PM.Feature=F then Exit;EndEdit(False);end;
  CadLogFeature('FEATURE.EDIT new='+BoolToStr(AIsNew,True),F);
  FreeAndNil(FSnapshot);
  FSnapshot := TJSONObject.Create;
  F.SaveParams(FSnapshot);
  FSnapName := F.Name;
  View.Selected.Clear;
  View.HighlightPrefix := F.Name + '/';
  if F is TCadExtrude then
    View.OperationSketchId:=TCadExtrude(F).SketchId
  else if F is TCadRevolve then
    View.OperationSketchId:=TCadRevolve(F).SketchId
  else
    View.OperationSketchId:=0;
  Tree.Visible := False;
  PM.Visible := True;
  PM.Edit(Doc, F, AIsNew);
  View.PickEdges := F is TCadBlendBase;
  if F is TCadBlendBase then
  begin
    { como no SolidWorks: o modelo fica como antes da operacao (as arestas
      continuam clicaveis) e a previa mostra o material tirado/acrescentado }
    FSavedRollback := Doc.RollbackIndex;
    Doc.RollbackIndex := Doc.IndexOfId(F.Id);
    FBlendEdit := True;
    View.HighlightPrefix := '';
  end;
  RebuildModel;
  PMChange(nil);
  if F is TCadExtrude then
    FExtrudeEditor:=TCadExtrudeEditor.Create(View,RB,PM,TCadExtrude(F));
end;

procedure TMainForm.EndEdit(Accept: Boolean);
var
  F: TCadFeature;
  Err: string;
begin
  FreeAndNil(FExtrudeEditor);
  F := PM.Feature;
  View.OperationSketchId:=0;
  CadLogFeature('FEATURE.END accept='+BoolToStr(Accept,True),F);
  if (F <> nil) and not Accept then
  begin
    if PM.IsNew then
    begin
      Doc.DeleteFeature(F.Id, Err);
      { furo novo em face: apaga o esboco de posicao criado junto }
      if FAutoSketchId > 0 then
        Doc.DeleteFeature(FAutoSketchId, Err);
    end
    else if Assigned(FSnapshot) then
      F.LoadParams(FSnapshot);
  end;
  FreeAndNil(FSnapshot);
  FAutoSketchId := 0;
  StopBlendEdit;
  View.PickEdges := True;
  View.Selected.Clear;
  PM.Visible := False;
  Tree.Visible := True;
  View.HighlightPrefix := '';
  SetStatus(0,'');
  if Accept then
    Modified;
  RebuildModel;
end;

procedure TMainForm.PMChange(Sender: TObject);
var
  F: TCadFeature;
  V: string;
begin
  F := PM.Feature;
  if F = nil then
    Exit;
  CadLogFeature('FEATURE.PARAMETERS',F);
  if FBlendEdit then
  begin
    RB.Rebuild;
    View.ModelChanged;
    UpdateBlendPreview;
    Exit;
  end;
  V := F.Validate;
  if V = '' then
  begin
    RB.Rebuild;
    View.ModelChanged;
    UpdatePartStatus;
    if F.State = fsError then
      PM.ShowMessageText(F.Message, True)
    else if F.Message <> '' then
      PM.ShowMessageText(F.Message, False)
    else
      PM.ShowMessageText('', False);
  end
  else
  begin
    CadLog('ERROR.VALIDATION',F.Name+': '+V);
    PM.ShowMessageText(V, True);
  end;
end;

procedure TMainForm.PMOK(Sender: TObject);
var
  F: TCadFeature;
  V: string;
begin
  F := PM.Feature;
  if F = nil then
    Exit;
  V := F.Validate;
  if V <> '' then
  begin
    PM.ShowMessageText(V, True);
    Exit;
  end;
  StopBlendEdit;
  Screen.Cursor := crHourGlass;
  try
    RB.Rebuild;
  finally
    Screen.Cursor := crDefault;
  end;
  { Refresh borrowed meshes before the error dialog dispatches WM_PAINT. }
  View.ModelChanged;
  UpdatePartStatus;
  if F.State = fsError then
  begin
    { como no SolidWorks: aceita, mas fica marcada em vermelho na arvore }
    if CadMessageDlg(F.Message + LineEnding + 'Manter a operação com erro?', mtWarning,
      [mbYes, mbNo], 0) <> mrYes then
    begin
      if F is TCadBlendBase then
      begin
        FSavedRollback := Doc.RollbackIndex;
        Doc.RollbackIndex := Doc.IndexOfId(F.Id);
        FBlendEdit := True;
        PMChange(nil);
      end;
      Exit;
    end;
  end;
  EndEdit(True);
end;

procedure TMainForm.PMCancel(Sender: TObject);
begin
  EndEdit(False);
end;

{ ---------- avaliar / exibir ---------- }

procedure TMainForm.MassClick(Sender: TObject);
var
  I: Integer;
  MP: TCadMassProps;
  Vol, Area: Double;
  C: TCadVec3;
  M: TCadMaterial;
  S: string;
begin
  if RB.BodyCount = 0 then
  begin
    CadMessageDlg('A peça ainda não tem corpos sólidos.', mtInformation, [mbOK], 0);
    Exit;
  end;
  Vol := 0;
  Area := 0;
  C := V3(0, 0, 0);
  for I := 0 to RB.BodyCount - 1 do
  begin
    MP := RB.Body(I).Mesh.MassProps;
    Vol := Vol + MP.Volume;
    Area := Area + MP.Area;
    C := VAdd(C, VScale(MP.Centroid, MP.Volume));
  end;
  if Vol > 0 then
    C := VScale(C, 1 / Vol);
  if not CadFindMaterial(Doc.Material, M) then
    M := CadMaterial(0);
  S := Format('Material: %s (%s kg/m³)' + LineEnding +
    'Volume: %s mm³' + LineEnding + 'Área de superfície: %s mm²' + LineEnding +
    'Massa: %s g' + LineEnding + 'Centro de massa (mm): X = %s  Y = %s  Z = %s' + LineEnding +
    'Corpos: %d',
    [M.Name, CadFmt(M.Density, 0), CadFmt(Vol, 2), CadFmt(Area, 2),
     CadFmt(CadMassKg(M, Vol) * 1000, 2), CadFmt(C.X, 3), CadFmt(C.Y, 3), CadFmt(C.Z, 3),
     RB.BodyCount]);
  CadMessageDlg('Propriedades de massa - ' + Doc.Name, S, mtInformation, [mbOK], 0);
end;

procedure TMainForm.MeasureClick(Sender: TObject);
var
  R: TCadMeasureResult;
begin
  R := CadMeasure(RB, View.Selected);
  try
    CadMessageDlg('Medir', R.Lines.Text, mtInformation, [mbOK], 0);
  finally
    R.Lines.Free;
  end;
end;

function TMainForm.SelectedFaceNormal(out N: TCadVec3): Boolean;
var
  I, F: Integer;
  B: TCadBody;
begin
  Result := False;
  N := V3(0, 0, 0);
  for I := 0 to View.Selected.Count - 1 do
    if (Pos('face:', View.Selected[I]) = 1) and
      RB.FindFace(Copy(View.Selected[I], 6, MaxInt), B, F) and
      (B.Mesh.Faces[F].Surf = skPlane) then
    begin
      N := B.Mesh.Faces[F].Axis;
      Exit(True);
    end;
end;

function TMainForm.AskStlOptions(out ABinary: Boolean; out AOrient: TCadStlOrient): Boolean;
var
  F: TForm;
  RO, RF: TRadioGroup;
  O: TCadStlOrient;
  B: TButton;
  N: TCadVec3;
begin
  ABinary := True;
  AOrient := soYToZ;
  F := TForm.CreateNew(Self);
  try
    F.Caption := 'Exportar STL';
    F.Position := poOwnerFormCenter;
    F.BorderStyle := bsDialog;
    F.Width := 380;
    F.Height := 270;
    RO := TRadioGroup.Create(F);
    RO.Parent := F;
    RO.SetBounds(10, 8, 360, 110);
    RO.Caption := 'Orientação (o MultiSlicer usa Z para cima)';
    for O := Low(TCadStlOrient) to High(TCadStlOrient) do
      RO.Items.Add(CAD_STL_ORIENT_NAMES[O]);
    RO.ItemIndex := 0;
    if SelectedFaceNormal(N) then
      RO.ItemIndex := Ord(soFaceDown);
    RF := TRadioGroup.Create(F);
    RF.Parent := F;
    RF.SetBounds(10, 124, 360, 76);
    RF.Caption := 'Formato';
    RF.Items.Add('Binário (menor, recomendado)');
    RF.Items.Add('Texto (ASCII)');
    RF.ItemIndex := 0;
    B := TButton.Create(F);
    B.Parent := F;
    B.SetBounds(196, 210, 84, 30);
    B.Caption := 'Exportar';
    B.Default := True;
    B.ModalResult := mrOK;
    B := TButton.Create(F);
    B.Parent := F;
    B.SetBounds(286, 210, 84, 30);
    B.Caption := 'Cancelar';
    B.Cancel := True;
    B.ModalResult := mrCancel;
    Result := F.ShowModal = mrOK;
    if Result then
    begin
      AOrient := TCadStlOrient(RO.ItemIndex);
      ABinary := RF.ItemIndex = 0;
      if (AOrient = soFaceDown) and not SelectedFaceNormal(N) then
      begin
        CadMessageDlg('Selecione na vista a face plana que vai apoiada na mesa.', mtInformation, [mbOK], 0);
        Result := False;
      end;
    end;
  finally
    F.Free;
  end;
end;

function TMainForm.ExportSTLTo(const AFile: string; ABinary: Boolean; AOrient: TCadStlOrient): Boolean;
var
  Meshes: array of TCadMesh;
  I: Integer;
  N: TCadVec3;
  Err: string;
begin
  Result := False;
  if RB.BodyCount = 0 then
  begin
    CadMessageDlg('A peça ainda não tem corpos sólidos.', mtInformation, [mbOK], 0);
    Exit;
  end;
  SetLength(Meshes, RB.BodyCount);
  for I := 0 to RB.BodyCount - 1 do
    Meshes[I] := RB.Body(I).Mesh;
  SelectedFaceNormal(N);
  Result := CadExportSTL(Meshes, AFile, ABinary, AOrient, N, Doc.Name, Err);
  if Result then
    SetStatus(0, 'STL gravado: ' + AFile)
  else
    CadMessageDlg('Não foi possível exportar o STL:' + LineEnding + Err, mtError, [mbOK], 0);
end;

procedure TMainForm.ExportSTLClick(Sender: TObject);
var
  D: TSaveDialog;
  Bin: Boolean;
  O: TCadStlOrient;
begin
  if not AskStlOptions(Bin, O) then
    Exit;
  D := TSaveDialog.Create(Self);
  try
    D.Filter := 'STL (*.stl)|*.stl';
    D.DefaultExt := 'stl';
    D.FileName := Doc.Name + '.stl';
    if Doc.FileName <> '' then
      D.InitialDir := ExtractFilePath(Doc.FileName);
    D.Options := D.Options + [ofOverwritePrompt];
    if D.Execute then
      ExportSTLTo(D.FileName, Bin, O);
  finally
    D.Free;
  end;
end;

function TMainForm.KernelText: string;
begin
  if OcctAvailable then
  begin
    Result := 'OpenCascade ' + OcctVersion;
    if not RB.UseOcct then
      Result := Result + ' (desligado: usando o núcleo Pascal)';
  end
  else
    Result := 'Pascal (malha) — OpenCascade indisponível: ' + OcctLoadError;
end;

procedure TMainForm.KernelClick(Sender: TObject);
begin
  if PM.Visible or Assigned(FEditor) then
    Exit;
  if not OcctAvailable then
  begin
    CadMessageDlg('Núcleo geométrico: ' + KernelText, mtInformation, [mbOK], 0);
    Exit;
  end;
  RB.UseOcct := not RB.UseOcct;
  SaveSettings;
  RebuildModel;
  SetStatus(0, 'Núcleo geométrico: ' + KernelText);
end;

procedure TMainForm.ExportSTEPClick(Sender: TObject);
var
  D: TSaveDialog;
  Shapes: array of TOcctShape;
  I: Integer;
  Err: string;
begin
  if not RB.OcctActive then
  begin
    CadMessageDlg('STEP precisa do núcleo OpenCascade.' + LineEnding + KernelText, mtWarning, [mbOK], 0);
    Exit;
  end;
  Shapes := nil;
  for I := 0 to RB.BodyCount - 1 do
    if RB.BodyShape(I) <> nil then
    begin
      SetLength(Shapes, Length(Shapes) + 1);
      Shapes[High(Shapes)] := RB.BodyShape(I);
    end;
  if Length(Shapes) = 0 then
  begin
    CadMessageDlg('A peça não tem sólido para exportar.', mtInformation, [mbOK], 0);
    Exit;
  end;
  D := TSaveDialog.Create(Self);
  try
    D.Filter := 'STEP AP214 (*.step;*.stp)|*.step;*.stp';
    D.DefaultExt := 'step';
    D.FileName := Doc.Name + '.step';
    if Doc.FileName <> '' then
      D.InitialDir := ExtractFilePath(Doc.FileName);
    D.Options := D.Options + [ofOverwritePrompt];
    if not D.Execute then
      Exit;
    if OcctStepWrite(Shapes, D.FileName, Err) then
      SetStatus(0, 'STEP gravado: ' + D.FileName)
    else
      CadMessageDlg('Não foi possível gravar o STEP: ' + Err, mtError, [mbOK], 0);
  finally
    D.Free;
  end;
end;

procedure TMainForm.ImportSTEPClick(Sender: TObject);
var
  D: TOpenDialog;
  F: TCadImportStep;
  Fn: string;
begin
  if PM.Visible or Assigned(FEditor) then
    Exit;
  if not RB.OcctActive then
  begin
    CadMessageDlg('Importar STEP precisa do núcleo OpenCascade.' + LineEnding + KernelText,
      mtWarning, [mbOK], 0);
    Exit;
  end;
  D := TOpenDialog.Create(Self);
  try
    D.Filter := 'STEP (*.step;*.stp)|*.step;*.stp;*.STEP;*.STP';
    if Doc.FileName <> '' then
      D.InitialDir := ExtractFilePath(Doc.FileName);
    if not D.Execute then
      Exit;
    Fn := D.FileName;
  finally
    D.Free;
  end;
  F := TCadImportStep.Create;
  if Doc.FileName <> '' then
    F.FileName := ExtractRelativePath(ExtractFilePath(Doc.FileName), Fn)
  else
    F.FileName := Fn;
  Doc.AddFeature(F);
  RebuildModel;
  Modified;
  if F.State = fsError then
    CadMessageDlg(F.Message, mtWarning, [mbOK], 0)
  else
    SetStatus(0, 'Importado: ' + Fn);
end;

procedure TMainForm.ExportDXFClick(Sender: TObject);
var
  D: TSaveDialog;
  S: TCadSketch;
  F: TCadFeature;
  I, Face, Loops: Integer;
  B: TCadBody;
  Err, FaceRef, Base: string;
  Ok: Boolean;
begin
  { face plana selecionada na vista, ou o esboco selecionado/em edicao }
  FaceRef := '';
  for I := 0 to View.Selected.Count - 1 do
    if Pos('face:', View.Selected[I]) = 1 then
    begin
      FaceRef := Copy(View.Selected[I], 6, MaxInt);
      Break;
    end;
  S := nil;
  if FaceRef = '' then
  begin
    if Assigned(FEditor) then
      S := FEditor.Sketch
    else
    begin
      F := SelectedFeature;
      if F is TCadSketch then
        S := TCadSketch(F);
      for I := 0 to View.Selected.Count - 1 do
        if Pos('sketch:', View.Selected[I]) = 1 then
        begin
          F := Doc.FindById(StrToIntDef(Copy(View.Selected[I], 8, MaxInt), 0));
          if F is TCadSketch then
            S := TCadSketch(F);
        end;
    end;
    if S = nil then
    begin
      CadMessageDlg('Selecione uma face plana na vista ou um esboço na árvore.', mtInformation, [mbOK], 0);
      Exit;
    end;
    Base := S.Name;
  end
  else
    Base := StringReplace(StringReplace(FaceRef, '/', '-', [rfReplaceAll]), ':', '', [rfReplaceAll]);
  D := TSaveDialog.Create(Self);
  try
    D.Filter := 'DXF (*.dxf)|*.dxf';
    D.DefaultExt := 'dxf';
    D.FileName := Doc.Name + '-' + Base + '.dxf';
    if Doc.FileName <> '' then
      D.InitialDir := ExtractFilePath(Doc.FileName);
    D.Options := D.Options + [ofOverwritePrompt];
    if not D.Execute then
      Exit;
    if FaceRef <> '' then
    begin
      Ok := RB.FindFace(FaceRef, B, Face) and
        CadExportFaceDXF(B.Mesh, Face, D.FileName, Loops, Err);
      if Ok then
        SetStatus(0, Format('DXF gravado (%d contorno(s)): %s', [Loops, D.FileName]));
    end
    else
    begin
      Ok := CadExportSketchDXF(S, D.FileName, Err);
      if Ok then
        SetStatus(0, 'DXF gravado: ' + D.FileName);
    end;
    if not Ok then
      CadMessageDlg('Não foi possível exportar o DXF:' + LineEnding + Err, mtError, [mbOK], 0);
  finally
    D.Free;
  end;
end;

procedure TMainForm.OpenSlicerClick(Sender: TObject);
var
  Registry: TSuiteRegistry;
  Root, Candidate, Err, Fn: string;
  C: TSuiteContext;
  I: Integer;
begin
  { STL em pe ao lado do .mcad (ou na pasta temporaria) e abre o MultiSlicer,
    como o "Abrir no ..." do MakePCB }
  if Doc.FileName <> '' then
    Fn := ChangeFileExt(Doc.FileName, '.stl')
  else
    Fn := GetTempDir + Doc.Name + '.stl';
  if not ExportSTLTo(Fn, True, soYToZ) then
    Exit;
  Registry := TSuiteRegistry.Create;
  try
    C := ReadSuiteContext;
    Root := ExtractFilePath(ParamStr(0));
    Candidate := Root;
    for I := 0 to 5 do
    begin
      if DirectoryExists(IncludeTrailingPathDelimiter(Candidate) + 'multisuite') then
      begin
        Root := Candidate;
        Break;
      end;
      Candidate := ExtractFileDir(ExcludeTrailingPathDelimiter(Candidate));
    end;
    if TSuiteLauncher.LaunchArtifact(Registry.Tool(Registry.Find(stiMultiSlicer)), Root,
      C.ProjectRoot, Fn, Err) then
      SetStatus(0, 'Peça aberta no MultiSlicer: ' + Fn)
    else
      CadMessageDlg('Não foi possível abrir o MultiSlicer:' + LineEnding + Err + LineEnding +
        'O STL foi gravado em ' + Fn, mtWarning, [mbOK], 0);
  finally
    Registry.Free;
  end;
end;

procedure TMainForm.SectionClick(Sender: TObject);
var
  R, Err: string;
  Fr: TCadFrame;
  B: TCadBox3;
begin
  if View.SectionOn then
  begin
    View.SetSection(False, Fr);
    Exit;
  end;
  R := SelectedPlaneRef;
  if (R = '') or not RB.ResolvePlane(R, Fr, Err) then
  begin
    Fr := StdFrame(spFrontal);
    B := View.ModelBox;
    if not B.Empty then
      Fr.Origin := V3(0, 0, (B.Min.Z + B.Max.Z) / 2);
  end;
  View.SetSection(True, Fr);
end;

procedure TMainForm.RebuildClick(Sender: TObject);
begin
  RB.Invalidate;
  RebuildModel;
end;

procedure TMainForm.StyleClick(Sender: TObject);
begin
  View.Style := TCadDisplayStyle(TComponent(Sender).Tag);
end;

procedure TMainForm.ViewClick(Sender: TObject);
begin
  if TComponent(Sender).Tag < 0 then
    View.FitAll
  else
    View.SetView(TCadStdView(TComponent(Sender).Tag));
end;

procedure TMainForm.NormalToClick(Sender: TObject);
var
  R: string;
  F: TCadFeature;
begin
  if Assigned(FEditor) then
  begin
    FEditor.NormalTo;
    Exit;
  end;
  R := SelectedPlaneRef;
  if R = '' then
  begin
    F := SelectedFeature;
    if F is TCadSketch then
      R := TCadSketch(F).PlaneRef;
  end;
  NormalToRef(R);
end;

procedure TMainForm.NormalToRef(const ARef: string);
var
  Fr: TCadFrame;
  Err: string;
begin
  if (ARef = '') or not RB.ResolvePlane(ARef, Fr, Err) then
  begin
    SetStatus(1, 'Normal a: selecione um plano, face plana ou esboço');
    Exit;
  end;
  { repetir vira para o outro lado }
  FNormalFlip := VDist(View.Camera.Back, Fr.Normal) < 1E-6;
  View.PushView;
  View.Camera.NormalTo(Fr, FNormalFlip);
  View.FitAll;
end;

procedure TMainForm.PerspectiveClick(Sender: TObject);
begin
  View.Camera.Perspective := not View.Camera.Perspective;
  View.Redraw;
end;

procedure TMainForm.PlanesClick(Sender: TObject);
var
  ShowIt: Boolean;
begin
  ShowIt := not View.IsHidden(-1);
  View.SetHidden(-1, ShowIt);
  View.ShowStdPlane(MCAD_ID_FRONTAL, ShowIt);
  View.ShowStdPlane(MCAD_ID_SUPERIOR, ShowIt);
  View.ShowStdPlane(MCAD_ID_LATERAL, ShowIt);
end;

procedure TMainForm.EditSketchById(AId: Integer);
begin
  if Doc.FindById(AId) is TCadSketch then
    EditSketch(TCadSketch(Doc.FindById(AId)));
end;

procedure TMainForm.EditFeatureById(AId: Integer);
begin
  if Assigned(Doc.FindById(AId)) then
    BeginEdit(Doc.FindById(AId), False);
end;

procedure TMainForm.CancelEdit;
begin
  if PM.Visible then
    EndEdit(False);
end;

procedure TMainForm.ExitSketchMode;
begin
  ExitSketch(nil);
end;

{ ---------- vista ---------- }

procedure TMainForm.ViewPick(Sender: TObject; const ARef: string; Shift: TShiftState);
var
  I, Id: Integer;
  N: TTreeNode;
begin
  CadLog('SELECT.VIEW',ARef+' ctrl='+BoolToStr(ssCtrl in Shift,True));
  if PM.Visible then
  begin
    if PM.SetPickedRef(ARef) then
      SetStatus(0, 'Referência: ' + ARef);
    Exit;
  end;
  if FPendingSketch then
  begin
    if (Pos('plane:', ARef) = 1) or (Pos('face:', ARef) = 1) then
      StartSketch(ARef);
    Exit;
  end;
  if not (ssCtrl in Shift) then
    View.Selected.Clear;
  View.HighlightPrefix := '';
  if ARef <> '' then
  begin
    I := View.Selected.IndexOf(ARef);
    if I >= 0 then
      View.Selected.Delete(I)
    else
      View.Selected.Add(ARef);
  end;
  { espelha na arvore }
  Id := 0;
  if (Pos('plane:', ARef) = 1) or (Pos('sketch:', ARef) = 1) or (Pos('axis:', ARef) = 1) then
    Id := StrToIntDef(Copy(ARef, Pos(':', ARef) + 1, MaxInt), 0);
  FRefreshingTree := True;
  try
    Tree.Selected := nil;
    if Id > 0 then
      for I := 0 to Tree.Items.Count - 1 do
      begin
        N := Tree.Items[I];
        if PtrInt(N.Data) = Id then
        begin
          N.Selected := True;
          Break;
        end;
      end;
  finally
    FRefreshingTree := False;
  end;
  if ARef <> '' then
    SetStatus(0, 'Selecionado: ' + ARef)
  else
    SetStatus(0, '');
  View.Redraw;
end;

procedure TMainForm.ViewHover(Sender: TObject);
begin
  if View.Hover <> '' then
    SetStatus(0, View.Hover)
  else if not Assigned(FEditor) then
    SetStatus(0, '');
end;

procedure TMainForm.ViewNormalTo(Sender: TObject);
begin
  NormalToClick(nil);
end;

procedure TMainForm.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key=VK_ESCAPE) and Assigned(FExtrudeEditor) and FExtrudeEditor.CancelDrag then
  begin Key:=0;Exit;end;
  if Tree.IsEditing or (Assigned(FEditor) and FEditor.Typing) then
    Exit;
  if (ActiveControl is TCustomEdit) or (ActiveControl is TCustomComboBox) then
  begin
    if Key = VK_ESCAPE then
    begin
      if PM.Visible then
        EndEdit(False);
      Key := 0;
    end;
    Exit;
  end;
  case Key of
    VK_ESCAPE:
      begin
        if FPendingSketch then
        begin
          FPendingSketch := False;
          View.PickEdges := True;
          View.ShowStdPlane(MCAD_ID_FRONTAL, False);
          View.ShowStdPlane(MCAD_ID_SUPERIOR, False);
          View.ShowStdPlane(MCAD_ID_LATERAL, False);
          UpdatePartStatus;
        end
        else if Assigned(FEditor) then
          FEditor.Escape
        else if PM.Visible then
          EndEdit(False)
        else
        begin
          View.Selected.Clear;
          View.HighlightPrefix := '';
          View.Redraw;
        end;
        Key := 0;
      end;
    VK_DELETE:
      begin
        if Assigned(FEditor) then
          FEditor.DeleteSelection
        else if Tree.Focused then
          MenuDelete(nil);
        Key := 0;
      end;
    VK_RETURN:
      if PM.Visible then
      begin
        PMOK(nil);
        Key := 0;
      end;
    VK_S:
      if ssCtrl in Shift then
      begin
        SaveClick(nil);
        Key := 0;
      end;
    VK_N:
      if ssCtrl in Shift then
      begin
        NewClick(nil);
        Key := 0;
      end;
    VK_O:
      if ssCtrl in Shift then
      begin
        OpenClick(nil);
        Key := 0;
      end;
    VK_B:
      if ssCtrl in Shift then
      begin
        RebuildClick(nil);
        Key := 0;
      end;
    VK_Z:
      if (ssCtrl in Shift) and not (ssShift in Shift) then
      begin
        UndoClick(nil);
        Key := 0;
      end
      else
        View.HandleKey(Key, Shift);
    VK_Y:
      if ssCtrl in Shift then
      begin
        RedoClick(nil);
        Key := 0;
      end;
    VK_1..VK_8, VK_F, VK_LEFT, VK_RIGHT, VK_UP, VK_DOWN:
      if not Tree.Focused or (ssCtrl in Shift) then
        View.HandleKey(Key, Shift);
  end;
end;

end.
