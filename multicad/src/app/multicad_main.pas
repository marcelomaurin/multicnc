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
  Graphics, Dialogs, Menus, LCLType, fpjson, jsonparser, multisuite_controls,
  multisuite_icons, multicad_types, multicad_units, multicad_materials,
  multicad_document, multicad_feature, multicad_refgeom, multicad_sketch, multicad_mesh,
  multicad_solver, multicad_extrude, multicad_revolve, multicad_rebuild,
  multicad_camera, multicad_softrender, multicad_view3d, multicad_sketchtools,
  multicad_sketchedit, multicad_propman;

type
  TCadTab = (ctFeatures, ctSketch, ctEvaluate, ctView);

  TMainForm = class(TForm)
  private
    Doc: TCadDocument;
    RB: TCadRebuilder;
    Header: TSuiteHeader;
    TabBar, Ribbon, LeftPane: TPanel;
    TabButtons: array[TCadTab] of TSuiteButton;
    FileButtons: TPanel;
    Tree: TTreeView;
    TreeMenu: TPopupMenu;
    RelMenu: TPopupMenu;
    PM: TCadPropManager;
    View: TCadView3D;
    Status: TStatusBar;
    Splitter: TSplitter;
    FTab: TCadTab;
    FEditor: TCadSketchEditor;
    FSnapshot: TJSONObject;     { parametros antes de editar (Cancelar) }
    FSnapName: string;
    FPendingSketch: Boolean;    { esperando escolher plano/face para o esboco }
    FNormalFlip: Boolean;
    FToolButtons: array[TCadSketchToolKind] of TSuiteButton;
    FRefreshingTree: Boolean;
    procedure BuildUI;
    procedure ShowTab(T: TCadTab);
    function RibbonButton(const ACaption: string; AIcon: TSuiteIconKind;
      AHandler: TNotifyEvent; ATag: Integer = 0; AWidth: Integer = 0): TSuiteButton;
    procedure RibbonSep;
    procedure TabClick(Sender: TObject);
    { arquivo }
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
    { operacoes }
    procedure SketchClick(Sender: TObject);
    procedure StartSketch(const APlaneRef: string);
    procedure EditSketch(S: TCadSketch);
    procedure ExitSketch(Sender: TObject);
    procedure ToolClick(Sender: TObject);
    procedure RelationClick(Sender: TObject);
    procedure RelationMenuClick(Sender: TObject);
    procedure DeleteSketchClick(Sender: TObject);
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
    procedure SectionClick(Sender: TObject);
    procedure RebuildClick(Sender: TObject);
    procedure StyleClick(Sender: TObject);
    procedure ViewClick(Sender: TObject);
    procedure NormalToClick(Sender: TObject);
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
    procedure EditSketchById(AId: Integer);
    procedure EditFeatureById(AId: Integer);
    procedure CancelEdit;
    procedure ExitSketchMode;
  end;

implementation

const
  TAB_NAMES: array[TCadTab] of string = ('Operações', 'Esboço', 'Avaliar', 'Exibir');
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
  Color := clSuiteSurface;
  Font.Name := SUITE_FONT;
  Doc := TCadDocument.Create;
  Doc.NewPart;
  RB := TCadRebuilder.Create(Doc);
  BuildUI;
  RebuildModel;
  View.SetView(svIso);
  UpdateCaption;
end;

destructor TMainForm.Destroy;
begin
  FreeAndNil(FEditor);
  FSnapshot.Free;
  RB.Free;
  Doc.Free;
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
    Result := TSuiteButton.Create(Self);
    Result.Parent := FileButtons;
    Result.Align := alLeft;
    Result.BorderSpacing.Around := 3;
    Result.Width := 96;
    Result.Caption := S;
    Result.SetLook(sbsSoft, clSuitePrimary, AIcon);
    Result.OnClick := H;
  end;

  procedure AddMenu(const S: string; H: TNotifyEvent; ATag: Integer = 0);
  begin
    MI := TMenuItem.Create(TreeMenu);
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
  TabBar.Top := 100;
  TabBar.Height := 38;
  TabBar.BevelOuter := bvNone;
  TabBar.Color := clSuiteCard;
  for T := Low(TCadTab) to High(TCadTab) do
  begin
    B := TSuiteButton.Create(Self);
    B.Parent := TabBar;
    B.SetBounds(8 + Ord(T) * 118, 4, 112, 30);
    B.Caption := TAB_NAMES[T];
    B.Tag := Ord(T);
    B.OnClick := @TabClick;
    TabButtons[T] := B;
  end;
  FileButtons := TPanel.Create(Self);
  FileButtons.Parent := TabBar;
  FileButtons.Align := alRight;
  FileButtons.Width := 4 * 102 + 8;
  FileButtons.BevelOuter := bvNone;
  FileButtons.Color := clSuiteCard;
  FileBtn('Salvar como', sikSave, @SaveAsClick);
  FileBtn('Salvar', sikSave, @SaveClick);
  FileBtn('Abrir', sikFolder, @OpenClick);
  FileBtn('Novo', sikNew, @NewClick);

  Ribbon := TPanel.Create(Self);
  Ribbon.Parent := Self;
  Ribbon.Align := alTop;
  Ribbon.Top := 200;
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
  AddMenu('Normal a', @MenuNormalTo);

  RelMenu := TPopupMenu.Create(Self);
  for K := Low(TConstraintKind) to High(TConstraintKind) do
    if not IsDimensionKind(K) then
    begin
      MI := TMenuItem.Create(RelMenu);
      MI.Caption := CadConstraintName(K);
      MI.Tag := Ord(K);
      MI.OnClick := @RelationClick;
      RelMenu.Items.Add(MI);
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
var
  X, I: Integer;
begin
  X := 8;
  for I := 0 to Ribbon.ControlCount - 1 do
    X := Max(X, Ribbon.Controls[I].Left + Ribbon.Controls[I].Width + 6);
  Result := TSuiteButton.Create(Ribbon);
  Result.Parent := Ribbon;
  if AWidth = 0 then
    AWidth := Max(84, Round(Result.Canvas.TextWidth(ACaption) * 1.12) + 54);
  Result.SetBounds(X, 8, AWidth, 34);
  Result.Caption := ACaption;
  Result.Tag := ATag;
  Result.SetLook(sbsSoft, clSuitePrimary, AIcon);
  Result.OnClick := AHandler;
end;

procedure TMainForm.RibbonSep;
var
  X, I: Integer;
  B: TBevel;
begin
  X := 8;
  for I := 0 to Ribbon.ControlCount - 1 do
    X := Max(X, Ribbon.Controls[I].Left + Ribbon.Controls[I].Width + 6);
  B := TBevel.Create(Ribbon);
  B.Parent := Ribbon;
  B.Shape := bsLeftLine;
  B.SetBounds(X, 10, 4, 30);
end;

procedure TMainForm.ShowTab(T: TCadTab);
var
  I: Integer;
  TT: TCadTab;
  K: TCadSketchToolKind;
  InSketch: Boolean;
begin
  FTab := T;
  for TT := Low(TCadTab) to High(TCadTab) do
    if TT = T then
      TabButtons[TT].SetLook(sbsSolid, clSuitePrimary)
    else
      TabButtons[TT].SetLook(sbsSoft, clSuitePrimary);
  for I := Ribbon.ControlCount - 1 downto 0 do
    Ribbon.Controls[I].Free;
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
        FToolButtons[tkArc3P] := RibbonButton('Arco 3 pontos', sikRedo, @ToolClick, Ord(tkArc3P));
        FToolButtons[tkCenterline] := RibbonButton('Linha de centro', sikMirrorV, @ToolClick, Ord(tkCenterline));
        FToolButtons[tkPoint] := RibbonButton('Ponto', sikTarget, @ToolClick, Ord(tkPoint));
        RibbonSep;
        FToolButtons[tkDimension] := RibbonButton('Cota inteligente', sikGauge, @ToolClick, Ord(tkDimension));
        RibbonButton('Adicionar relação', sikLayers, @RelationMenuClick).Enabled := InSketch;
        RibbonButton('Apagar', sikTrash, @DeleteSketchClick, 0, 90).Enabled := InSketch;
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
      end;
  end;
end;

procedure TMainForm.TabClick(Sender: TObject);
begin
  ShowTab(TCadTab(TComponent(Sender).Tag));
end;

{ ---------- estado ---------- }

procedure TMainForm.SetStatus(I: Integer; const S: string);
begin
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
  View.ModelChanged;
  RefreshTree;
  UpdatePartStatus;
end;

procedure TMainForm.Modified;
begin
  Doc.Modified := True;
  UpdateCaption;
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
  if F = nil then
  begin
    View.HighlightPrefix := '';
    View.Redraw;
    Exit;
  end;
  View.HighlightPrefix := '';
  case F.Kind of
    cfPlane: View.Selected.Add('plane:' + IntToStr(F.Id));
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
  if F is TCadSketch then
    EditSketch(TCadSketch(F))
  else if (F is TCadExtrude) or (F is TCadRevolve) or
    ((F is TCadPlane) and (TCadPlane(F).PlaneType <> ptStandard)) then
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
    MessageDlg('Já existe uma operação chamada "' + S + '"', mtWarning, [mbOK], 0);
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
    MessageDlg('Não foi possível renomear: ' + Err, mtError, [mbOK], 0);
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
    ((F is TCadExtrude) or (F is TCadRevolve) or ((F is TCadPlane) and (TCadPlane(F).PlaneType <> ptStandard)));
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
  TreeMenu.Items[10].Enabled := Assigned(F) and ((F is TCadSketch) or (F is TCadPlane));
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
  if MessageDlg('Excluir "' + F.Name + '"?', mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
    Exit;
  if not Doc.DeleteFeature(F.Id, Err) then
  begin
    MessageDlg(Err, mtWarning, [mbOK], 0);
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
  F: TForm;
  L: TListBox;
  B: TButton;
  I: Integer;
  M: TCadMaterial;
begin
  F := TForm.CreateNew(Self);
  try
    F.Caption := 'Material';
    F.Position := poOwnerFormCenter;
    F.Width := 320;
    F.Height := 380;
    L := TListBox.Create(F);
    L.Parent := F;
    L.Align := alClient;
    for I := 0 to CadMaterialCount - 1 do
    begin
      M := CadMaterial(I);
      L.Items.Add(M.Name);
      if SameText(M.Name, Doc.Material) then
        L.ItemIndex := I;
    end;
    B := TButton.Create(F);
    B.Parent := F;
    B.Align := alBottom;
    B.Caption := 'Aplicar';
    B.ModalResult := mrOK;
    B.Default := True;
    if (F.ShowModal = mrOK) and (L.ItemIndex >= 0) then
    begin
      Doc.Material := L.Items[L.ItemIndex];
      Modified;
      RefreshTree;
      UpdatePartStatus;
    end;
  finally
    F.Free;
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
  case MessageDlg('Salvar as alterações em "' + Doc.Name + '"?', mtConfirmation,
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

procedure TMainForm.NewClick(Sender: TObject);
begin
  if not ConfirmDiscard then
    Exit;
  Doc.NewPart;
  RB.Invalidate;
  View.Selected.Clear;
  RebuildModel;
  View.SetView(svIso);
  UpdateCaption;
end;

function TMainForm.OpenFile(const AFile: string): Boolean;
var
  Err: string;
begin
  Result := Doc.LoadFromFile(AFile, Err);
  if not Result then
  begin
    MessageDlg('Não foi possível abrir "' + AFile + '":' + LineEnding + Err, mtError, [mbOK], 0);
    Exit;
  end;
  RB.Invalidate;
  View.Selected.Clear;
  RebuildModel;
  View.SetView(svIso);
  UpdateCaption;
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
  Result := Doc.SaveToFile(AFile, Err);
  if not Result then
    MessageDlg('Não foi possível salvar:' + LineEnding + Err, mtError, [mbOK], 0);
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
  CanClose := ConfirmDiscard;
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
  R := SelectedPlaneRef;
  if R <> '' then
  begin
    StartSketch(R);
    Exit;
  end;
  { como no SolidWorks: mostra os planos padrao e espera a escolha }
  FPendingSketch := True;
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
  FPendingSketch := False;
  View.ShowStdPlane(MCAD_ID_FRONTAL, False);
  View.ShowStdPlane(MCAD_ID_SUPERIOR, False);
  View.ShowStdPlane(MCAD_ID_LATERAL, False);
  if not RB.ResolvePlane(APlaneRef, Fr, Err) then
  begin
    MessageDlg('Não dá para esboçar em "' + APlaneRef + '": ' + Err, mtWarning, [mbOK], 0);
    Exit;
  end;
  S := Doc.AddSketch(APlaneRef);
  Modified;
  RebuildModel;
  EditSketch(S);
end;

procedure TMainForm.EditSketch(S: TCadSketch);
begin
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
end;

procedure TMainForm.ExitSketch(Sender: TObject);
begin
  if FEditor = nil then
    Exit;
  FreeAndNil(FEditor);
  SetStatus(0, '');
  RebuildModel;
  ShowTab(ctFeatures);
end;

procedure TMainForm.ToolClick(Sender: TObject);
begin
  if FEditor = nil then
    Exit;
  FEditor.SetTool(TCadSketchToolKind(TComponent(Sender).Tag));
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

procedure TMainForm.DeleteSketchClick(Sender: TObject);
begin
  if Assigned(FEditor) then
    FEditor.DeleteSelection;
end;

procedure TMainForm.EditorChanged(Sender: TObject);
begin
  Modified;
end;

procedure TMainForm.EditorStatus(Sender: TObject);
begin
  if Assigned(FEditor) then
  begin
    SetStatus(1, FEditor.StatusText);
    SetStatus(0, 'Ferramenta: ' + CAD_TOOL_NAMES[FEditor.Session.Tool]);
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
  F := SelectedFeature;
  if F is TCadSketch then
    Exit(TCadSketch(F));
  for I := 0 to View.Selected.Count - 1 do
    if Pos('sketch:', View.Selected[I]) = 1 then
    begin
      Id := StrToIntDef(Copy(View.Selected[I], 8, MaxInt), 0);
      F := Doc.FindById(Id);
      if F is TCadSketch then
        Exit(TCadSketch(F));
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
    Exit;
  IsCut := Sender = nil;
  S := FindSketchForFeature;
  if S = nil then
  begin
    MessageDlg('Selecione um esboço (ou crie um na aba Esboço).', mtInformation, [mbOK], 0);
    Exit;
  end;
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
    MessageDlg('Selecione um esboço com uma linha de centro.', mtInformation, [mbOK], 0);
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

procedure TMainForm.BeginEdit(F: TCadFeature; AIsNew: Boolean);
begin
  if Assigned(FEditor) then
    ExitSketch(nil);
  FreeAndNil(FSnapshot);
  FSnapshot := TJSONObject.Create;
  F.SaveParams(FSnapshot);
  FSnapName := F.Name;
  View.Selected.Clear;
  View.HighlightPrefix := F.Name + '/';
  Tree.Visible := False;
  PM.Visible := True;
  PM.Edit(Doc, F, AIsNew);
  RebuildModel;
  PMChange(nil);
end;

procedure TMainForm.EndEdit(Accept: Boolean);
var
  F: TCadFeature;
  Err: string;
begin
  F := PM.Feature;
  if (F <> nil) and not Accept then
  begin
    if PM.IsNew then
      Doc.DeleteFeature(F.Id, Err)
    else if Assigned(FSnapshot) then
      F.LoadParams(FSnapshot);
  end;
  FreeAndNil(FSnapshot);
  PM.Visible := False;
  Tree.Visible := True;
  View.HighlightPrefix := '';
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
    PM.ShowMessageText(V, True);
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
  RB.Rebuild;
  if F.State = fsError then
  begin
    { como no SolidWorks: aceita, mas fica marcada em vermelho na arvore }
    if MessageDlg(F.Message + LineEnding + 'Manter a operação com erro?', mtWarning,
      [mbYes, mbNo], 0) <> mrYes then
      Exit;
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
    MessageDlg('A peça ainda não tem corpos sólidos.', mtInformation, [mbOK], 0);
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
  MessageDlg('Propriedades de massa - ' + Doc.Name, S, mtInformation, [mbOK], 0);
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
  R, Err: string;
  Fr: TCadFrame;
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
  if (R = '') or not RB.ResolvePlane(R, Fr, Err) then
  begin
    SetStatus(1, 'Normal a: selecione um plano, face plana ou esboço');
    Exit;
  end;
  { repetir vira para o outro lado }
  FNormalFlip := VDist(View.Camera.Back, Fr.Normal) < 1E-6;
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
  if Tree.IsEditing then
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
    VK_1..VK_8, VK_F, VK_LEFT, VK_RIGHT, VK_UP, VK_DOWN:
      if not Tree.Focused or (ssCtrl in Shift) then
        View.HandleKey(Key, Shift);
  end;
end;

end.
