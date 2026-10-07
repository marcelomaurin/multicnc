unit makepcb_main;

{ Tela principal do MakePCB, no padrao visual da suite (igual ao LaserPCB):
  cabecalho, etapas a esquerda, area de desenho no centro com barra de
  ferramentas, painel da etapa a direita e rodape com as acoes finais.

  Etapas: 1 Placa, 2 Componentes (galeria), 3 Ligacoes, 4 Trilhas
  (manual, autoroteamento e DRC), 5 Fabricar (lista de materiais,
  Gerber + Excellon para o LaserPCB). Vistas como as abas do PCB Wizard:
  Normal, Mundo real, Sem componentes e Arte final. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls, Grids,
  Dialogs, Graphics, LCLType, makepcb_model, makepcb_library, makepcb_render,
  makepcb_editor, makepcb_gallery, makepcb_select, makepcb_fpeditor, multisuite_controls, multisuite_icons;

type
  TMakePCBForm = class(TForm)
  private
    Doc: TMPDocument;
    Lib: TMPLibrary;
    Editor: TMPEditor;
    Gallery: TMPGallery;
    GalleryBox: TScrollBox;
    Pages: TPageControl;
    Nav: array[0..4] of TSuiteButton;
    Views: array[TMPViewMode] of TSuiteButton;
    Tools: array[TMPTool] of TSuiteButton;
    FooterPanel: TPanel;
    Status, Coords, Info, SelTitle, NetSummary, FabSummary: TLabel;
    State: TSuiteBadge;
    BoardName, BoardW, BoardH, TrackW, Clearance, CompRef, CompValue, CompX, CompY,
    SearchBox: TEdit;
    SidesBox, GridBox, CategoryBox, LayerBox, BarLayerBox: TComboBox;
    RouteLog: TMemo;
    BOMGrid: TStringGrid;
    OptSilk, OptMask, OptTop, MirrorBox: TCheckBox;
    CheckButton, ExportButton, OpenLaserButton: TSuiteButton;
    FFileName, FExportDir: string;
    FUpdating: Boolean;
    function Button(ParentControl: TWinControl; const AText: string; X, Y, W: Integer;
      AIcon: TSuiteIconKind; Handler: TNotifyEvent): TSuiteButton;
    function LabelAt(ParentControl: TWinControl; const AText: string; X, Y, W, H: Integer): TLabel;
    function Field(ParentControl: TWinControl; const AText, Value: string; Y: Integer): TEdit;
    function Combo(ParentControl: TWinControl; const AText: string; Y: Integer): TComboBox;
    function Num(E: TEdit; const What: string; MinV, MaxV: Double): Double;
    procedure BuildUI;
    procedure FocusPage(N: Integer);
    procedure NavClick(Sender: TObject);
    procedure ViewClick(Sender: TObject);
    procedure ToolClick(Sender: TObject);
    procedure SetViewMode(M: TMPViewMode);
    procedure SyncTools;
    procedure RefreshAll;
    procedure RefreshBoardFields;
    procedure RefreshSelection(Sender: TObject);
    procedure RefreshInfo;
    procedure RefreshBOM;
    procedure DocChanged(Sender: TObject);
    procedure EditorStatus(Sender: TObject; const S: string);
    procedure GalleryPick(Sender: TObject; FP: TMPFootprint);
    procedure CategoryChanged(Sender: TObject);
    procedure LayerChanged(Sender: TObject);
    procedure MirrorChanged(Sender: TObject);
    procedure ApplyBoardClick(Sender: TObject);
    procedure ApplyCompClick(Sender: TObject);
    procedure RotateClick(Sender: TObject);
    procedure FlipClick(Sender: TObject);
    procedure NewFootprintClick(Sender: TObject);
    procedure EditFootprintClick(Sender: TObject);
    procedure DeleteFootprintClick(Sender: TObject);
    procedure RunFootprintEditor(Template: TMPFootprint);
    procedure RefreshCategories;
    procedure CopyClick(Sender: TObject);
    procedure PasteClick(Sender: TObject);
    procedure DeleteClick(Sender: TObject);
    procedure UndoClick(Sender: TObject);
    procedure RedoClick(Sender: TObject);
    procedure FitClick(Sender: TObject);
    procedure ZoomInClick(Sender: TObject);
    procedure ZoomOutClick(Sender: TObject);
    procedure NewClick(Sender: TObject);
    procedure OpenClick(Sender: TObject);
    procedure SaveClick(Sender: TObject);
    procedure SaveAsClick(Sender: TObject);
    procedure ExampleClick(Sender: TObject);
    procedure RouteClick(Sender: TObject);
    procedure RipUpClick(Sender: TObject);
    procedure ClearWiresClick(Sender: TObject);
    procedure CheckClick(Sender: TObject);
    procedure ExportClick(Sender: TObject);
    procedure OpenLaserClick(Sender: TObject);
    procedure SaveBOMClick(Sender: TObject);
    procedure SaveArtworkClick(Sender: TObject);
    function ConfirmDiscard: Boolean;
    function BaseName: string;
    procedure ShowError(E: Exception);
    procedure ResizeUI(Sender: TObject);
    procedure FormKey(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure OpenFile(const FN: string);
    { exporta para Folder; devolve a lista de arquivos }
    procedure ExportTo(const Folder: string; Files: TStrings);
    { acoes usadas pelos testes e pela linha de comando }
    procedure LoadExample;
    procedure AutoRoute;
    procedure RunDRC;
    procedure ShowStep(N: Integer);
    procedure ShowView(M: TMPViewMode);
    property Document: TMPDocument read Doc;
    property EditorControl: TMPEditor read Editor;
  end;

implementation

uses makepcb_gerber, makepcb_route, makepcb_drc, makepcb_bom, multisuite_numfmt,
  multisuite_registry, multisuite_launcher, multisuite_types, multisuite_context;

function FmtNum(V: Double; D: Integer): string;
var
  FS: TFormatSettings;
begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := ',';
  FS.ThousandSeparator := #0;
  Result := FormatFloat('0.' + StringOfChar('#', Max(1, D)), V, FS);
end;

function SidesText(Double_: Boolean): string;
begin
  if Double_ then Result := 'dupla face' else Result := 'face simples';
end;

const
  STEP_NAMES: array[0..4] of string = ('1  Placa', '2  Componentes', '3  Ligacoes', '4  Trilhas', '5  Fabricar');
  STEP_ICONS: array[0..4] of TSuiteIconKind = (sikFrame, sikLayers, sikPlug, sikPen, sikExport);
  VIEW_ICONS: array[TMPViewMode] of TSuiteIconKind = (sikPCB, sikEye, sikRect, sikImage);
  TOOL_ICONS: array[TMPTool] of TSuiteIconKind = (sikPointer, sikImport, sikPen, sikPlug, sikText, sikPolygon);
  GRID_MM: array[0..4] of Double = (1.27, 2.54, 0.635, 1.0, 0.5);

{ ---------------- auxiliares de layout ---------------- }

function TMakePCBForm.Button(ParentControl: TWinControl; const AText: string;
  X, Y, W: Integer; AIcon: TSuiteIconKind; Handler: TNotifyEvent): TSuiteButton;
begin
  Result := TSuiteButton.Create(Self);
  Result.Parent := ParentControl;
  Result.SetBounds(X, Y, W, 34);
  Result.Caption := AText;
  Result.SetLook(sbsSoft, clSuitePrimary, AIcon);
  Result.OnClick := Handler;
end;

function TMakePCBForm.LabelAt(ParentControl: TWinControl; const AText: string;
  X, Y, W, H: Integer): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := ParentControl;
  Result.AutoSize := False;
  Result.SetBounds(X, Y, W, H);
  Result.WordWrap := True;
  Result.Caption := AText;
  Result.Font.Color := clSuiteMuted;
end;

function TMakePCBForm.Field(ParentControl: TWinControl; const AText, Value: string; Y: Integer): TEdit;
begin
  LabelAt(ParentControl, AText, 16, Y, 290, 18);
  Result := TEdit.Create(Self);
  Result.Parent := ParentControl;
  Result.SetBounds(16, Y + 20, 290, 28);
  Result.Text := Value;
end;

function TMakePCBForm.Combo(ParentControl: TWinControl; const AText: string; Y: Integer): TComboBox;
begin
  LabelAt(ParentControl, AText, 16, Y, 290, 18);
  Result := TComboBox.Create(Self);
  Result.Parent := ParentControl;
  Result.SetBounds(16, Y + 20, 290, 30);
  Result.Style := csDropDownList;
end;

function TMakePCBForm.Num(E: TEdit; const What: string; MinV, MaxV: Double): Double;
begin
  if not TryParseFloat(E.Text, Result) or (Result < MinV) or (Result > MaxV) then
  begin
    E.SetFocus;
    raise Exception.CreateFmt('%s: informe um numero entre %s e %s.',
      [What, FmtNum(MinV, 2), FmtNum(MaxV, 2)]);
  end;
end;

{ ---------------- construcao ---------------- }

constructor TMakePCBForm.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner, 1);
  Caption := 'MakePCB • MultiSuite';
  Width := 1320; Height := 880;
  Constraints.MinWidth := 1080; Constraints.MinHeight := 700;
  Position := poScreenCenter;
  Font.Name := SUITE_FONT; Font.Size := 10;
  Color := clSuiteSurface;
  KeyPreview := True;
  Lib := MakePCBLibrary;
  try
    if Lib.UserCount = 0 then Lib.LoadUserFile(MPUserLibraryFile);
  except
    { biblioteca pessoal corrompida nao impede abrir o programa }
  end;
  Doc := TMPDocument.Create;
  FUpdating := True;
  BuildUI;
  Editor.Doc := Doc;
  FUpdating := False;
  RefreshAll;
  OnResize := @ResizeUI;
  OnKeyDown := @FormKey;
  OnCloseQuery := @FormCloseQuery;
end;

destructor TMakePCBForm.Destroy;
begin
  if Editor <> nil then Editor.Doc := nil;
  Doc.Free;
  inherited Destroy;
end;

procedure TMakePCBForm.BuildUI;
var
  Header: TSuiteHeader;
  Sidebar, Work, Bar, Footer: TPanel;
  Page: TTabSheet;
  Scroll: TScrollBox;
  I, X: Integer;
  M: TMPViewMode;
  T: TMPTool;
  B: TSuiteButton;
begin
  Header := TSuiteHeader.Create(Self);
  Header.Parent := Self; Header.Align := alTop; Header.Height := 72;
  Header.Setup('MakePCB', 'Projeto de placas do zero  /  MultiSuite', sikPCB);

  { rodape }
  Footer := TPanel.Create(Self);
  Footer.Parent := Self; Footer.Align := alBottom; Footer.Height := 66;
  Footer.BevelOuter := bvNone; Footer.Color := clSuiteCard;
  FooterPanel := Footer;
  Status := LabelAt(Footer, 'Comece pela placa ou abra o exemplo do 555.', 18, 10, 420, 24);
  Status.Font.Color := clSuiteText;
  Coords := LabelAt(Footer, '', 18, 36, 420, 20);
  CheckButton := Button(Footer, 'Verificar (DRC)', 0, 15, 160, sikTests, @CheckClick);
  ExportButton := Button(Footer, 'Exportar Gerber', 0, 15, 180, sikExport, @ExportClick);
  ExportButton.SetLook(sbsSolid, clSuitePrimary, sikExport);
  OpenLaserButton := Button(Footer, 'Abrir no LaserPCB', 0, 15, 200, sikLaserPCB, @OpenLaserClick);
  OpenLaserButton.Enabled := False;

  { etapas e vistas }
  Sidebar := TPanel.Create(Self);
  Sidebar.Parent := Self; Sidebar.Align := alLeft; Sidebar.Width := 214;
  Sidebar.BevelOuter := bvNone; Sidebar.Color := clSuiteCard;
  for I := 0 to 4 do
  begin
    Nav[I] := Button(Sidebar, STEP_NAMES[I], 12, 16 + I * 44, 190, STEP_ICONS[I], @NavClick);
    Nav[I].Tag := I;
  end;
  Button(Sidebar, 'Novo', 12, 252, 92, sikNew, @NewClick);
  Button(Sidebar, 'Abrir', 110, 252, 92, sikFolder, @OpenClick);
  Button(Sidebar, 'Salvar', 12, 292, 92, sikSave, @SaveClick);
  Button(Sidebar, '555', 110, 292, 92, sikWand, @ExampleClick).Hint := 'Pisca-pisca com 555 (astavel)';
  LabelAt(Sidebar, 'VISTAS', 16, 344, 180, 20).Font.Style := [fsBold];
  I := 0;
  for M := Low(TMPViewMode) to High(TMPViewMode) do
  begin
    Views[M] := Button(Sidebar, ViewModeName(M), 12, 368 + I * 40, 190, VIEW_ICONS[M], @ViewClick);
    Views[M].Tag := Ord(M);
    Inc(I);
  end;
  Info := LabelAt(Sidebar, '', 16, 0, 184, 96);
  Info.Align := alBottom; Info.BorderSpacing.Around := 12;
  Info.WordWrap := False;   { linhas explicitas; o word wrap do GTK2 trava com #10 }

  { painel da etapa }
  Pages := TPageControl.Create(Self);
  Pages.Parent := Self; Pages.Align := alRight; Pages.Width := 336; Pages.ShowTabs := False;
  for I := 0 to 4 do
  begin
    Page := TTabSheet.Create(Self);
    Page.PageControl := Pages;
    Page.Caption := STEP_NAMES[I];
    Scroll := TScrollBox.Create(Self);
    Scroll.Parent := Page; Scroll.Align := alClient;
    Scroll.BorderStyle := bsNone; Scroll.Color := clSuiteCard;
    Scroll.HorzScrollBar.Visible := False;
    LabelAt(Scroll, STEP_NAMES[I], 16, 16, 260, 30).Font.Style := [fsBold];
    case I of
      0:
        begin
          BoardName := Field(Scroll, 'Nome da placa', '', 56);
          BoardW := Field(Scroll, 'Largura (mm)', '', 112);
          BoardH := Field(Scroll, 'Altura (mm)', '', 168);
          SidesBox := Combo(Scroll, 'Faces de cobre', 224);
          SidesBox.Items.Add('Face simples (cobre embaixo)');
          SidesBox.Items.Add('Dupla face');
          TrackW := Field(Scroll, 'Largura padrao da trilha (mm)', '', 282);
          Clearance := Field(Scroll, 'Folga minima entre cobres (mm)', '', 338);
          GridBox := Combo(Scroll, 'Grade', 394);
          GridBox.Items.Add('0,05 pol (1,27 mm)');
          GridBox.Items.Add('0,1 pol (2,54 mm)');
          GridBox.Items.Add('0,025 pol (0,635 mm)');
          GridBox.Items.Add('1 mm');
          GridBox.Items.Add('0,5 mm');
          Button(Scroll, 'Aplicar', 16, 456, 290, sikTarget, @ApplyBoardClick).SetLook(sbsSolid, clSuitePrimary, sikTarget);
          LabelAt(Scroll, 'Para o LaserPCB, prefira trilhas de 0,6 a 1,0 mm e folga de 0,4 mm ou mais: a isolacao a laser precisa de espaco entre os cobres.',
            16, 504, 290, 72);
          LabelAt(Scroll, 'Na face simples o cobre fica embaixo (lado da solda) e os componentes em cima, como no PCB Wizard.',
            16, 580, 290, 56);
        end;
      1:
        begin
          CategoryBox := Combo(Scroll, 'Galeria de componentes', 52);
          CategoryBox.Items.Add('Todos');
          for X := 0 to Lib.Categories.Count - 1 do CategoryBox.Items.Add(Lib.Categories[X]);
          CategoryBox.ItemIndex := 0;
          CategoryBox.OnChange := @CategoryChanged;
          SearchBox := TEdit.Create(Self);
          SearchBox.Parent := Scroll; SearchBox.SetBounds(16, 112, 290, 28);
          SearchBox.TextHint := 'Buscar (ex.: DIL, LED, 555, borne)';
          SearchBox.OnChange := @CategoryChanged;
          GalleryBox := TScrollBox.Create(Self);
          GalleryBox.Parent := Scroll; GalleryBox.SetBounds(12, 148, 298, 400);
          GalleryBox.BorderStyle := bsNone; GalleryBox.Color := clSuiteCard;
          GalleryBox.HorzScrollBar.Visible := False;
          GalleryBox.VertScrollBar.Increment := 40;
          Gallery := TMPGallery.Create(Self);
          Gallery.Parent := GalleryBox; Gallery.Left := 0; Gallery.Top := 0;
          Gallery.Width := 280;
          Gallery.Lib := Lib;
          Gallery.OnPick := @GalleryPick;
          Gallery.ShowHint := True;
          B := Button(Scroll, 'Novo', 16, 554, 92, sikNew, @NewFootprintClick);
          B.Hint := 'Criar um componente (editor de componentes)'; B.ShowHint := True;
          B := Button(Scroll, 'Editar', 115, 554, 92, sikPen, @EditFootprintClick);
          B.Hint := 'Editar o componente escolhido na galeria (os da biblioteca viram uma copia sua)'; B.ShowHint := True;
          B := Button(Scroll, 'Apagar', 214, 554, 92, sikTrash, @DeleteFootprintClick);
          B.Hint := 'Apagar um componente de "Meus componentes"'; B.ShowHint := True;
          SelTitle := LabelAt(Scroll, 'COMPONENTE SELECIONADO', 16, 604, 290, 18);
          SelTitle.Font.Style := [fsBold];
          CompRef := Field(Scroll, 'Referencia', '', 626);
          CompValue := Field(Scroll, 'Valor', '', 682);
          CompX := Field(Scroll, 'X (mm)', '', 738);
          CompY := Field(Scroll, 'Y (mm)', '', 794);
          Button(Scroll, 'Aplicar', 16, 854, 290, sikTarget, @ApplyCompClick);
          Button(Scroll, 'Girar', 16, 896, 92, sikMove, @RotateClick).Hint := 'Girar 90 graus (R)';
          B := Button(Scroll, 'Virar', 115, 896, 92, sikMirrorH, @FlipClick);
          B.Hint := 'Montar embaixo/em cima (F) - SMD em face simples vai embaixo'; B.ShowHint := True;
          Button(Scroll, 'Excluir', 214, 896, 92, sikTrash, @DeleteClick);
        end;
      2:
        begin
          LabelAt(Scroll, 'Ligue os pads que devem ficar no mesmo circuito (como as linhas do esquema). As ligacoes aparecem tracejadas ate virarem trilhas.',
            16, 52, 290, 74);
          Button(Scroll, 'Ferramenta Ligacao', 16, 130, 290, sikPlug, @ToolClick).Tag := Ord(etWire);
          Button(Scroll, 'Apagar todas as ligacoes', 16, 172, 290, sikTrash, @ClearWiresClick);
          LabelAt(Scroll, 'RESUMO', 16, 224, 290, 18).Font.Style := [fsBold];
          NetSummary := LabelAt(Scroll, '', 16, 246, 290, 120);
          NetSummary.WordWrap := False;
          LabelAt(Scroll, 'Dica: clique num pad, depois no outro. Esc cancela. Uma trilha desenhada que liga dois pads tambem forma o circuito.',
            16, 372, 290, 74);
        end;
      3:
        begin
          LayerBox := Combo(Scroll, 'Face ativa', 52);
          LayerBox.Items.Add('Bottom (lado da solda)');
          LayerBox.Items.Add('Top (lado dos componentes)');
          LayerBox.Items.Add('Serigrafia (texto)');
          LayerBox.ItemIndex := 0;
          LayerBox.OnChange := @LayerChanged;
          Button(Scroll, 'Trilha', 16, 112, 140, sikPen, @ToolClick).Tag := Ord(etTrack);
          Button(Scroll, 'Area de cobre', 166, 112, 140, sikPolygon, @ToolClick).Tag := Ord(etArea);
          Button(Scroll, 'Texto', 16, 152, 140, sikText, @ToolClick).Tag := Ord(etText);
          Button(Scroll, 'Selecionar', 166, 152, 140, sikPointer, @ToolClick).Tag := Ord(etSelect);
          LabelAt(Scroll, 'ROTEAMENTO AUTOMATICO', 16, 204, 290, 18).Font.Style := [fsBold];
          B := Button(Scroll, 'Rotear automaticamente', 16, 228, 290, sikWand, @RouteClick);
          B.SetLook(sbsSolid, clSuitePrimary, sikWand);
          Button(Scroll, 'Apagar trilhas (rip-up)', 16, 270, 290, sikTrash, @RipUpClick);
          Button(Scroll, 'Verificar (DRC)', 16, 312, 290, sikTests, @CheckClick);
          State := TSuiteBadge.Create(Self);
          State.Parent := Scroll; State.SetBounds(16, 360, 290, 32);
          State.Caption := 'Nao verificado'; State.DotColor := clSuiteWarning;
          RouteLog := TMemo.Create(Self);
          RouteLog.Parent := Scroll; RouteLog.SetBounds(16, 400, 290, 220);
          RouteLog.ReadOnly := True; RouteLog.ScrollBars := ssAutoVertical;
          LabelAt(Scroll, 'O roteador usa a grade, curvas de 45 graus e, em dupla face, vias. Mantem as trilhas ja desenhadas.',
            16, 628, 290, 56);
        end;
      4:
        begin
          LabelAt(Scroll, 'LISTA DE MATERIAIS', 16, 52, 290, 18).Font.Style := [fsBold];
          BOMGrid := TStringGrid.Create(Self);
          BOMGrid.Parent := Scroll; BOMGrid.SetBounds(12, 74, 298, 220);
          BOMGrid.ColCount := 3; BOMGrid.FixedCols := 0; BOMGrid.RowCount := 1;
          BOMGrid.Cells[0, 0] := 'Qtd'; BOMGrid.Cells[1, 0] := 'Valor'; BOMGrid.Cells[2, 0] := 'Referencias';
          BOMGrid.ColWidths[0] := 40; BOMGrid.ColWidths[1] := 92; BOMGrid.ColWidths[2] := 150;
          BOMGrid.Options := BOMGrid.Options - [goEditing, goRangeSelect] + [goRowSelect];
          BOMGrid.ScrollBars := ssAutoVertical;
          Button(Scroll, 'Salvar lista (CSV)', 16, 302, 290, sikSave, @SaveBOMClick);
          LabelAt(Scroll, 'ARQUIVOS PARA O LASERPCB', 16, 352, 290, 18).Font.Style := [fsBold];
          OptSilk := TCheckBox.Create(Self); OptSilk.Parent := Scroll;
          OptSilk.SetBounds(16, 376, 290, 24); OptSilk.Caption := 'Serigrafia (F_Silkscreen)'; OptSilk.Checked := True;
          OptMask := TCheckBox.Create(Self); OptMask.Parent := Scroll;
          OptMask.SetBounds(16, 402, 290, 24); OptMask.Caption := 'Mascara de solda (F/B_Mask)'; OptMask.Checked := True;
          OptTop := TCheckBox.Create(Self); OptTop.Parent := Scroll;
          OptTop.SetBounds(16, 428, 290, 24); OptTop.Caption := 'Cobre superior mesmo em face simples';
          LabelAt(Scroll, 'Gerber RS-274X (X2) + Excellon (PTH/NPTH), nomes no padrao KiCad: o LaserPCB reconhece cada camada sozinho.',
            16, 458, 290, 56);
          B := Button(Scroll, 'Exportar Gerber + Excellon', 16, 518, 290, sikExport, @ExportClick);
          B.SetLook(sbsSolid, clSuitePrimary, sikExport);
          Button(Scroll, 'Abrir no LaserPCB', 16, 560, 290, sikLaserPCB, @OpenLaserClick);
          Button(Scroll, 'Salvar arte final (PNG 600 dpi)', 16, 602, 290, sikImage, @SaveArtworkClick);
          FabSummary := LabelAt(Scroll, '', 16, 646, 290, 140);
          FabSummary.WordWrap := False;
        end;
    end;
  end;

  { area de desenho }
  Work := TPanel.Create(Self);
  Work.Parent := Self; Work.Align := alClient; Work.BevelOuter := bvNone; Work.Color := clSuiteSurface;
  Bar := TPanel.Create(Self);
  Bar.Parent := Work; Bar.Align := alTop; Bar.Height := 52; Bar.BevelOuter := bvNone; Bar.Color := clSuiteSurface;
  X := 10;
  for T := Low(TMPTool) to High(TMPTool) do
  begin
    if T = etPlace then Continue;
    Tools[T] := Button(Bar, '', X, 9, 36, TOOL_ICONS[T], @ToolClick);
    Tools[T].Tag := Ord(T);
    Tools[T].Hint := ToolName(T);
    Tools[T].ShowHint := True;
    Inc(X, 40);
  end;
  Inc(X, 8);
  BarLayerBox := TComboBox.Create(Self);
  BarLayerBox.Parent := Bar; BarLayerBox.SetBounds(X, 12, 104, 30);
  BarLayerBox.Style := csDropDownList;
  BarLayerBox.Items.Add('Bottom'); BarLayerBox.Items.Add('Top'); BarLayerBox.Items.Add('Serigrafia');
  BarLayerBox.ItemIndex := 0; BarLayerBox.OnChange := @LayerChanged;
  BarLayerBox.Hint := 'Face ativa (trilhas, areas e textos)'; BarLayerBox.ShowHint := True;
  Inc(X, 112);
  B := Button(Bar, '', X, 9, 36, sikUndo, @UndoClick); B.Hint := 'Desfazer (Ctrl+Z)'; B.ShowHint := True; Inc(X, 40);
  B := Button(Bar, '', X, 9, 36, sikRedo, @RedoClick); B.Hint := 'Refazer (Ctrl+Y)'; B.ShowHint := True; Inc(X, 48);
  B := Button(Bar, '', X, 9, 36, sikCopy, @CopyClick); B.Hint := 'Copiar (Ctrl+C)'; B.ShowHint := True; Inc(X, 40);
  B := Button(Bar, '', X, 9, 36, sikImport, @PasteClick); B.Hint := 'Colar (Ctrl+V)'; B.ShowHint := True; Inc(X, 40);
  B := Button(Bar, '', X, 9, 36, sikMove, @RotateClick); B.Hint := 'Girar 90 graus (R)'; B.ShowHint := True; Inc(X, 40);
  B := Button(Bar, '', X, 9, 36, sikTrash, @DeleteClick); B.Hint := 'Excluir (Del)'; B.ShowHint := True; Inc(X, 48);
  B := Button(Bar, '', X, 9, 36, sikFit, @FitClick); B.Hint := 'Ver a placa inteira'; B.ShowHint := True; Inc(X, 40);
  B := Button(Bar, '', X, 9, 36, sikZoomIn, @ZoomInClick); B.Hint := 'Ampliar'; B.ShowHint := True; Inc(X, 40);
  B := Button(Bar, '', X, 9, 36, sikZoomOut, @ZoomOutClick); B.Hint := 'Reduzir'; B.ShowHint := True;
  MirrorBox := TCheckBox.Create(Self);
  MirrorBox.Parent := Sidebar; MirrorBox.SetBounds(16, 532, 186, 24);
  MirrorBox.Caption := 'Espelhar a arte final';
  MirrorBox.Hint := 'Arte final espelhada (transferencia termica da face de cima)';
  MirrorBox.ShowHint := True;
  MirrorBox.OnChange := @MirrorChanged;
  Editor := TMPEditor.Create(Self);
  Editor.Parent := Work; Editor.Align := alClient;
  Editor.Lib := Lib;
  Editor.OnChange := @DocChanged;
  Editor.OnSelect := @RefreshSelection;
  Editor.OnStatus := @EditorStatus;
  Pages.ActivePageIndex := 0;
  FocusPage(0);
  SetViewMode(vmNormal);
  SyncTools;
  ResizeUI(nil);
end;

procedure TMakePCBForm.ResizeUI(Sender: TObject);
begin
  if FooterPanel = nil then Exit;
  OpenLaserButton.Left := FooterPanel.ClientWidth - OpenLaserButton.Width - 18;
  ExportButton.Left := OpenLaserButton.Left - ExportButton.Width - 10;
  CheckButton.Left := ExportButton.Left - CheckButton.Width - 10;
  Status.Width := Max(120, CheckButton.Left - 30);
  Coords.Width := Status.Width;
  if (Gallery <> nil) and (GalleryBox <> nil) then
    Gallery.Width := GalleryBox.ClientWidth;
end;

{ ---------------- etapas, vistas e ferramentas ---------------- }

procedure TMakePCBForm.FocusPage(N: Integer);
var
  I: Integer;
begin
  Pages.ActivePageIndex := N;
  for I := 0 to 4 do
    if I = N then Nav[I].SetLook(sbsSolid, clSuitePrimary, STEP_ICONS[I])
    else Nav[I].SetLook(sbsSoft, clSuitePrimary, STEP_ICONS[I]);
  case N of
    1: if Editor.ViewMode = vmArtwork then SetViewMode(vmNormal);
    2: Editor.Tool := etWire;
    4: RefreshBOM;
  end;
  if N <> 2 then
    if Editor.Tool = etWire then Editor.Tool := etSelect;
  SyncTools;
end;

procedure TMakePCBForm.NavClick(Sender: TObject);
begin
  FocusPage(TComponent(Sender).Tag);
end;

procedure TMakePCBForm.SetViewMode(M: TMPViewMode);
var
  V: TMPViewMode;
begin
  Editor.ViewMode := M;
  for V := Low(TMPViewMode) to High(TMPViewMode) do
    if V = M then Views[V].SetLook(sbsSolid, clSuiteNavy, VIEW_ICONS[V])
    else Views[V].SetLook(sbsOutline, clSuiteNavy, VIEW_ICONS[V]);
  MirrorBox.Enabled := M = vmArtwork;
  if M = vmArtwork then
  begin
    if Doc.DoubleSided and (Editor.ActiveLayer = mlTopCopper) then Editor.Renderer.ArtworkLayer := mlTopCopper
    else Editor.Renderer.ArtworkLayer := mlBottomCopper;
    Status.Caption := 'Arte final: ' + LayerName(Editor.Renderer.ArtworkLayer) + ', vista de cima.';
  end;
end;

procedure TMakePCBForm.ViewClick(Sender: TObject);
begin
  SetViewMode(TMPViewMode(TComponent(Sender).Tag));
end;

procedure TMakePCBForm.ToolClick(Sender: TObject);
var
  T: TMPTool;
begin
  T := TMPTool(TComponent(Sender).Tag);
  if Editor.ViewMode <> vmNormal then SetViewMode(vmNormal);
  Editor.Tool := T;
  if T <> etPlace then Gallery.ClearSelection;
  SyncTools;
  Editor.SetFocus;
end;

procedure TMakePCBForm.SyncTools;
var
  T: TMPTool;
begin
  for T := Low(TMPTool) to High(TMPTool) do
    if Tools[T] <> nil then
      if T = Editor.Tool then Tools[T].SetLook(sbsSolid, clSuitePrimary, TOOL_ICONS[T])
      else Tools[T].SetLook(sbsSoft, clSuitePrimary, TOOL_ICONS[T]);
end;

procedure TMakePCBForm.LayerChanged(Sender: TObject);
var
  I: Integer;
begin
  if FUpdating then Exit;
  I := TComboBox(Sender).ItemIndex;
  FUpdating := True;
  try
    LayerBox.ItemIndex := I;
    BarLayerBox.ItemIndex := I;
  finally
    FUpdating := False;
  end;
  case I of
    1: Editor.ActiveLayer := mlTopCopper;
    2: Editor.ActiveLayer := mlTopSilk;
  else Editor.ActiveLayer := mlBottomCopper;
  end;
  if (Editor.ActiveLayer = mlTopCopper) and not Doc.DoubleSided then
    Status.Caption := 'Placa de face simples: trilhas em Top so valem em dupla face (etapa 1).';
  if Editor.ViewMode = vmArtwork then SetViewMode(vmArtwork);
  Editor.Invalidate;
end;

procedure TMakePCBForm.MirrorChanged(Sender: TObject);
begin
  Editor.Renderer.ArtworkMirror := MirrorBox.Checked;
  Editor.Invalidate;
end;

{ ---------------- atualizacao ---------------- }

procedure TMakePCBForm.RefreshAll;
begin
  RefreshBoardFields;
  RefreshSelection(nil);
  RefreshInfo;
  Editor.Invalidate;
end;

procedure TMakePCBForm.RefreshBoardFields;
var
  I: Integer;
begin
  FUpdating := True;
  try
    BoardName.Text := Doc.Name;
    BoardW.Text := FmtNum(Doc.BoardW, 2);
    BoardH.Text := FmtNum(Doc.BoardH, 2);
    SidesBox.ItemIndex := Ord(Doc.DoubleSided);
    TrackW.Text := FmtNum(Doc.TrackWidth, 2);
    Clearance.Text := FmtNum(Doc.Clearance, 2);
    GridBox.ItemIndex := 0;
    for I := 0 to High(GRID_MM) do
      if Abs(GRID_MM[I] - Doc.Grid) < 1e-6 then GridBox.ItemIndex := I;
  finally
    FUpdating := False;
  end;
end;

procedure TMakePCBForm.RefreshSelection(Sender: TObject);
var
  C: TMPComponent;
  On_: Boolean;
begin
  On_ := (Editor.SelKind = selComponent) and (Editor.SelIndex >= 0) and (Editor.SelIndex < Doc.ComponentCount);
  CompRef.Enabled := On_; CompValue.Enabled := On_; CompX.Enabled := On_; CompY.Enabled := On_;
  FUpdating := True;
  try
    if On_ then
    begin
      C := Doc.Component(Editor.SelIndex);
      SelTitle.Caption := 'SELECIONADO: ' + UpperCase(C.Footprint.Name);
      CompRef.Text := C.Ref;
      CompValue.Text := C.Value;
      CompX.Text := FmtNum(C.X, 3);
      CompY.Text := FmtNum(C.Y, 3);
    end
    else if Editor.Selection.Count > 1 then
    begin
      SelTitle.Caption := Format('%d ITENS SELECIONADOS', [Editor.Selection.Count]);
      CompRef.Text := ''; CompValue.Text := ''; CompX.Text := ''; CompY.Text := '';
      Status.Caption := Format('%d itens selecionados (%d componentes). Arraste, R gira, Del apaga, Ctrl+C copia, Ctrl+D duplica.',
        [Editor.Selection.Count, Editor.Selection.CountOf(ikComponent)]);
    end
    else
    begin
      SelTitle.Caption := 'COMPONENTE SELECIONADO';
      CompRef.Text := ''; CompValue.Text := ''; CompX.Text := ''; CompY.Text := '';
    end;
  finally
    FUpdating := False;
  end;
  case Editor.SelKind of
    selTrack: Status.Caption := Format('Trilha %s, %s mm de largura, %s mm de comprimento.',
      [LayerName(Doc.Track(Editor.SelIndex).Layer), FmtNum(Doc.Track(Editor.SelIndex).Width, 2),
       FmtNum(Doc.Track(Editor.SelIndex).Length, 1)]);
    selArea: Status.Caption := 'Area de cobre ' + LayerName(Doc.Area(Editor.SelIndex).Layer) + '.';
    selText: Status.Caption := 'Texto "' + Doc.Text(Editor.SelIndex).Text + '" em ' + LayerName(Doc.Text(Editor.SelIndex).Layer) + '.';
  end;
end;

procedure TMakePCBForm.RefreshInfo;
var
  Pend: TMPConnections;
begin
  Pend := MPPendingConnections(Doc);
  Info.Caption := Format('%s'#10'%s x %s mm, %s'#10'%d componentes, %d trilhas'#10'%d ligacoes pendentes',
    [Doc.Name, FmtNum(Doc.BoardW, 1), FmtNum(Doc.BoardH, 1),
     SidesText(Doc.DoubleSided),
     Doc.ComponentCount, Doc.TrackCount, Length(Pend)]);
  Doc.ComputeNets;
  NetSummary.Caption := Format('%d ligacoes desenhadas'#10'%d circuitos (redes)'#10'%d ligacoes ainda sem trilha',
    [Doc.WireCount, Doc.NetCount, Length(Pend)]);
  if FFileName <> '' then Caption := 'MakePCB • ' + ExtractFileName(FFileName)
  else Caption := 'MakePCB • MultiSuite';
  if Editor.Modified then Caption := Caption + ' *';
end;

procedure TMakePCBForm.RefreshBOM;
var
  B: TMPBOM;
  I, N: Integer;
begin
  B := MPBuildBOM(Doc);
  BOMGrid.RowCount := Length(B) + 1;
  N := 0;
  for I := 0 to High(B) do
  begin
    BOMGrid.Cells[0, I + 1] := IntToStr(B[I].Quantity);
    BOMGrid.Cells[1, I + 1] := B[I].Value;
    BOMGrid.Cells[2, I + 1] := B[I].Refs;
    Inc(N, B[I].Quantity);
  end;
  FabSummary.Caption := Format('%d itens, %d componentes.', [Length(B), N]);
  if FExportDir <> '' then
    FabSummary.Caption := FabSummary.Caption + #10'Ultima exportacao:'#10 + FExportDir;
end;

procedure TMakePCBForm.DocChanged(Sender: TObject);
begin
  Editor.SetIssues(nil);
  State.Caption := 'Nao verificado'; State.DotColor := clSuiteWarning;
  RefreshSelection(nil);
  RefreshInfo;
  if Pages.ActivePageIndex = 4 then RefreshBOM;
end;

procedure TMakePCBForm.EditorStatus(Sender: TObject; const S: string);
begin
  if Pos('X ', S) = 1 then Coords.Caption := S
  else Status.Caption := S;
end;

procedure TMakePCBForm.ShowError(E: Exception);
begin
  Status.Caption := E.Message;
  MessageDlg('MakePCB', E.Message, mtError, [mbOK], 0);
end;

{ ---------------- galeria e componentes ---------------- }

procedure TMakePCBForm.CategoryChanged(Sender: TObject);
begin
  if CategoryBox.ItemIndex <= 0 then Gallery.Category := ''
  else Gallery.Category := CategoryBox.Items[CategoryBox.ItemIndex];
  Gallery.Filter := SearchBox.Text;
  GalleryBox.VertScrollBar.Position := 0;
end;

procedure TMakePCBForm.GalleryPick(Sender: TObject; FP: TMPFootprint);
begin
  if Editor.ViewMode in [vmArtwork, vmUnpopulated] then SetViewMode(vmNormal);
  Editor.SetPlaceFootprint(FP);
  SyncTools;
  Editor.SetFocus;
end;

procedure TMakePCBForm.ApplyCompClick(Sender: TObject);
var
  C: TMPComponent;
  X, Y: Double;
begin
  if (Editor.SelKind <> selComponent) or (Editor.SelIndex < 0) then Exit;
  try
    C := Doc.Component(Editor.SelIndex);
    X := Num(CompX, 'X', -1000, 1000);
    Y := Num(CompY, 'Y', -1000, 1000);
    if (Trim(CompRef.Text) <> C.Ref) and (Doc.FindComponent(Trim(CompRef.Text)) <> nil) then
      raise Exception.Create('Ja existe um componente ' + Trim(CompRef.Text) + '.');
    Editor.Snapshot;
    C.Ref := Trim(CompRef.Text);
    C.Value := Trim(CompValue.Text);
    C.X := X; C.Y := Y;
    Editor.Changed;
  except
    on E: Exception do ShowError(E);
  end;
end;

procedure TMakePCBForm.RotateClick(Sender: TObject);
begin
  Editor.RotateSelection;
end;

procedure TMakePCBForm.FlipClick(Sender: TObject);
begin
  Editor.FlipSelection;
end;

procedure TMakePCBForm.RefreshCategories;
var
  Cur: string;
  I: Integer;
begin
  Cur := CategoryBox.Text;
  CategoryBox.Items.Clear;
  CategoryBox.Items.Add('Todos');
  for I := 0 to Lib.Categories.Count - 1 do CategoryBox.Items.Add(Lib.Categories[I]);
  CategoryBox.ItemIndex := Max(0, CategoryBox.Items.IndexOf(Cur));
end;

procedure TMakePCBForm.RunFootprintEditor(Template: TMPFootprint);
var
  Ed: TMPFootprintEditor;
  FP: TMPFootprint;
  Name_: string;
begin
  Ed := TMPFootprintEditor.CreateFor(Self, Template);
  try
    FP := Ed.Execute;
  finally
    Ed.Free;
  end;
  if FP = nil then Exit;
  try
    Name_ := FP.Name;
    Lib.AddUser(FP);   { substitui no lugar se ja existir }
    Lib.SaveUserFile(MPUserLibraryFile);
    RefreshCategories;
    CategoryBox.ItemIndex := Max(0, CategoryBox.Items.IndexOf(MP_USER_CATEGORY));
    CategoryChanged(nil);
    Gallery.Reload;
    Editor.Invalidate;
    Status.Caption := '"' + Name_ + '" salvo em Meus componentes. Clique nele na galeria para colocar.';
  except
    on E: Exception do ShowError(E);
  end;
end;

procedure TMakePCBForm.NewFootprintClick(Sender: TObject);
begin
  RunFootprintEditor(nil);
end;

procedure TMakePCBForm.EditFootprintClick(Sender: TObject);
begin
  if Gallery.SelectedFootprint = nil then
  begin
    Status.Caption := 'Escolha um componente na galeria para editar (ou use Novo).';
    Exit;
  end;
  RunFootprintEditor(Gallery.SelectedFootprint);
end;

procedure TMakePCBForm.DeleteFootprintClick(Sender: TObject);
var
  FP: TMPFootprint;
  I: Integer;
begin
  FP := Gallery.SelectedFootprint;
  if (FP = nil) or not FP.UserDefined then
  begin
    Status.Caption := 'So componentes de "Meus componentes" podem ser apagados.';
    Exit;
  end;
  for I := 0 to Doc.ComponentCount - 1 do
    if Doc.Component(I).Footprint = FP then
    begin
      Status.Caption := '"' + FP.Name + '" esta em uso na placa (' + Doc.Component(I).Ref + '). Apague da placa primeiro.';
      Exit;
    end;
  if MessageDlg('MakePCB', 'Apagar "' + FP.Name + '" de Meus componentes?', mtConfirmation, [mbYes, mbNo], 0) <> mrYes then Exit;
  Editor.SetPlaceFootprint(nil);
  Editor.Tool := etSelect;
  Lib.RemoveUser(FP.Name);
  Lib.SaveUserFile(MPUserLibraryFile);
  Gallery.Reload;
  SyncTools;
end;

procedure TMakePCBForm.CopyClick(Sender: TObject);
begin
  Editor.CopySelection;
end;

procedure TMakePCBForm.PasteClick(Sender: TObject);
begin
  if Editor.ViewMode <> vmNormal then SetViewMode(vmNormal);
  Editor.Tool := etSelect;
  SyncTools;
  Editor.PasteClipboard;
end;

procedure TMakePCBForm.DeleteClick(Sender: TObject);
begin
  Editor.DeleteSelection;
end;

procedure TMakePCBForm.UndoClick(Sender: TObject);
begin
  Editor.Undo;
  RefreshBoardFields;
end;

procedure TMakePCBForm.RedoClick(Sender: TObject);
begin
  Editor.Redo;
  RefreshBoardFields;
end;

procedure TMakePCBForm.FitClick(Sender: TObject);
begin
  Editor.ZoomToBoard;
end;

procedure TMakePCBForm.ZoomInClick(Sender: TObject);
begin
  Editor.ZoomBy(1.25);
end;

procedure TMakePCBForm.ZoomOutClick(Sender: TObject);
begin
  Editor.ZoomBy(0.8);
end;

{ ---------------- placa ---------------- }

procedure TMakePCBForm.ApplyBoardClick(Sender: TObject);
var
  W, H, TW, CL: Double;
  B: TMPRect;
begin
  try
    W := Num(BoardW, 'Largura', 5, 500);
    H := Num(BoardH, 'Altura', 5, 500);
    TW := Num(TrackW, 'Largura da trilha', 0.15, 5);
    CL := Num(Clearance, 'Folga', 0.1, 5);
    B := Doc.Bounds;
    if B.Valid and (Doc.ComponentCount > 0) and ((B.MaxX > W + 1e-6) or (B.MaxY > H + 1e-6)) then
      if MessageDlg('MakePCB', 'Ha componentes ou trilhas fora da nova placa. Aplicar assim mesmo?',
        mtConfirmation, [mbYes, mbNo], 0) <> mrYes then Exit;
    Editor.Snapshot;
    Doc.Name := Trim(BoardName.Text);
    if Doc.Name = '' then Doc.Name := 'Nova placa';
    Doc.BoardW := W; Doc.BoardH := H;
    Doc.DoubleSided := SidesBox.ItemIndex = 1;
    Doc.TrackWidth := TW; Doc.Clearance := CL;
    if GridBox.ItemIndex >= 0 then Doc.Grid := GRID_MM[GridBox.ItemIndex];
    Editor.Changed;
    Editor.ZoomToBoard;
    Status.Caption := 'Placa atualizada.';
  except
    on E: Exception do ShowError(E);
  end;
end;

{ ---------------- arquivo ---------------- }

function TMakePCBForm.ConfirmDiscard: Boolean;
var
  R: Integer;
begin
  Result := True;
  if not Editor.Modified then Exit;
  R := MessageDlg('MakePCB', 'Salvar as alteracoes de "' + Doc.Name + '"?', mtConfirmation,
    [mbYes, mbNo, mbCancel], 0);
  if R = mrCancel then Exit(False);
  if R = mrYes then
  begin
    SaveClick(nil);
    Result := not Editor.Modified;
  end;
end;

procedure TMakePCBForm.NewClick(Sender: TObject);
begin
  if not ConfirmDiscard then Exit;
  Doc.Clear;
  FFileName := ''; FExportDir := '';
  OpenLaserButton.Enabled := False;
  Editor.ClearHistory;
  Editor.Select(selNone, -1);
  Editor.Modified := False;
  Editor.ZoomToBoard;
  RefreshAll;
  FocusPage(0);
  Status.Caption := 'Nova placa. Ajuste o tamanho e passe para os componentes.';
end;

procedure TMakePCBForm.ExampleClick(Sender: TObject);
begin
  if not ConfirmDiscard then Exit;
  MPAstableExample(Doc, Lib);
  FFileName := ''; FExportDir := '';
  OpenLaserButton.Enabled := False;
  Editor.ClearHistory;
  Editor.Select(selNone, -1);
  Editor.Modified := True;
  Editor.ZoomToBoard;
  RefreshAll;
  FocusPage(3);
  Status.Caption := 'Exemplo 555 carregado com as ligacoes. Clique em "Rotear automaticamente".';
end;

procedure TMakePCBForm.OpenFile(const FN: string);
begin
  try
    Doc.LoadFromFile(FN, @Lib.Resolve);
    FFileName := FN; FExportDir := '';
    OpenLaserButton.Enabled := False;
    Editor.ClearHistory;
    Editor.Select(selNone, -1);
    Editor.Modified := False;
    Editor.Doc := Doc;
    Editor.ZoomToBoard;
    RefreshAll;
    Status.Caption := 'Aberto: ' + FN;
  except
    on E: Exception do ShowError(E);
  end;
end;

procedure TMakePCBForm.OpenClick(Sender: TObject);
var
  D: TOpenDialog;
begin
  if not ConfirmDiscard then Exit;
  D := TOpenDialog.Create(Self);
  try
    D.Filter := 'Placa MakePCB (*.mpcb)|*.mpcb|Todos os arquivos|*';
    D.Options := D.Options + [ofFileMustExist];
    if D.Execute then OpenFile(D.FileName);
  finally
    D.Free;
  end;
end;

procedure TMakePCBForm.SaveAsClick(Sender: TObject);
var
  D: TSaveDialog;
begin
  D := TSaveDialog.Create(Self);
  try
    D.Filter := 'Placa MakePCB (*.mpcb)|*.mpcb';
    D.DefaultExt := 'mpcb';
    D.FileName := BaseName + '.mpcb';
    D.Options := D.Options + [ofOverwritePrompt];
    if D.Execute then
    begin
      FFileName := D.FileName;
      SaveClick(nil);
    end;
  finally
    D.Free;
  end;
end;

procedure TMakePCBForm.SaveClick(Sender: TObject);
begin
  if FFileName = '' then
  begin
    SaveAsClick(nil);
    Exit;
  end;
  try
    Doc.SaveToFile(FFileName);
    Editor.Modified := False;
    RefreshInfo;
    Status.Caption := 'Salvo: ' + FFileName;
  except
    on E: Exception do ShowError(E);
  end;
end;

function TMakePCBForm.BaseName: string;
var
  I: Integer;
begin
  Result := Trim(Doc.Name);
  for I := 1 to Length(Result) do
    if not (Result[I] in ['A'..'Z', 'a'..'z', '0'..'9', '-', '_']) then Result[I] := '_';
  if Result = '' then Result := 'placa';
end;

{ ---------------- trilhas ---------------- }

procedure TMakePCBForm.RouteClick(Sender: TObject);
var
  R: TMPRouter;
  Res: TMPRouteResult;
  Failed: TStringList;
begin
  if Length(MPPendingConnections(Doc)) = 0 then
  begin
    Status.Caption := 'Nao ha ligacoes pendentes para rotear.';
    Exit;
  end;
  Screen.Cursor := crHourGlass;
  Failed := TStringList.Create;
  R := TMPRouter.Create(Doc, Doc.TrackWidth, Doc.Clearance);
  try
    Editor.Snapshot;
    Res := R.RouteAll(-1, Failed);
    RouteLog.Lines.Clear;
    RouteLog.Lines.Add(Format('Roteadas: %d   Falhas: %d', [Res.Routed, Res.Failed]));
    RouteLog.Lines.Add(Format('Trilhas novas: %d   Vias: %d', [Res.Tracks, Res.Vias]));
    if Failed.Count > 0 then
    begin
      RouteLog.Lines.Add('Sem caminho:');
      RouteLog.Lines.AddStrings(Failed);
      RouteLog.Lines.Add('Afaste os componentes, use dupla face ou desenhe essas trilhas a mao.');
    end;
    Editor.Changed;
    if Res.Failed = 0 then Status.Caption := 'Roteamento completo. Rode o DRC antes de exportar.'
    else Status.Caption := Format('%d ligacoes ficaram sem trilha.', [Res.Failed]);
  finally
    R.Free;
    Failed.Free;
    Screen.Cursor := crDefault;
  end;
end;

procedure TMakePCBForm.RipUpClick(Sender: TObject);
begin
  if Doc.TrackCount = 0 then Exit;
  if MessageDlg('MakePCB', 'Apagar todas as trilhas e vias? As ligacoes continuam.',
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes then Exit;
  Editor.Snapshot;
  MPRipUp(Doc);
  Editor.Select(selNone, -1);
  Editor.Changed;
  Status.Caption := 'Trilhas apagadas.';
end;

procedure TMakePCBForm.ClearWiresClick(Sender: TObject);
begin
  if Doc.WireCount = 0 then Exit;
  if MessageDlg('MakePCB', 'Apagar todas as ligacoes (ratsnest)?', mtConfirmation, [mbYes, mbNo], 0) <> mrYes then Exit;
  Editor.Snapshot;
  SetLength(Doc.Wires, 0);
  Editor.Changed;
end;

procedure TMakePCBForm.CheckClick(Sender: TObject);
var
  Issues: TMPDrcIssues;
  Errors: TStringList;
  I: Integer;
  Ok: Boolean;
const
  KIND_NAMES: array[TMPDrcKind] of string = ('Folga', 'Curto', 'Sem trilha', 'Placa', 'Largura');
begin
  Errors := TStringList.Create;
  try
    Ok := Doc.ValidateBoard(Errors);
    Issues := MPCheckDesign(Doc);
    Editor.SetIssues(Issues);
    RouteLog.Lines.Clear;
    RouteLog.Lines.AddStrings(Errors);
    for I := 0 to High(Issues) do
      RouteLog.Lines.Add(KIND_NAMES[Issues[I].Kind] + ': ' + Issues[I].Text);
    if Ok and (Length(Issues) = 0) then
    begin
      State.Caption := 'DRC sem problemas'; State.DotColor := clSuiteSuccess;
      RouteLog.Lines.Add('Nenhum problema encontrado.');
      Status.Caption := 'DRC sem problemas: pronto para exportar.';
    end
    else
    begin
      State.Caption := Format('%d problemas', [Length(Issues) + Errors.Count]); State.DotColor := clSuiteDanger;
      Status.Caption := Format('DRC: %d problemas (marcados em vermelho na placa).', [Length(Issues) + Errors.Count]);
    end;
    if Pages.ActivePageIndex <> 3 then FocusPage(3);
    if Editor.ViewMode <> vmNormal then SetViewMode(vmNormal);
  finally
    Errors.Free;
  end;
end;

{ ---------------- fabricacao ---------------- }

procedure TMakePCBForm.ExportTo(const Folder: string; Files: TStrings);
var
  O: TMPFabOptions;
begin
  O := MPDefaultFabOptions(Folder, BaseName);
  O.Silkscreen := OptSilk.Checked;
  O.SolderMask := OptMask.Checked;
  O.TopCopper := OptTop.Checked;
  ForceDirectories(Folder);
  MPExportFabrication(Doc, O, Files);
  FExportDir := Folder;
end;

procedure TMakePCBForm.ExportClick(Sender: TObject);
var
  Folder: string;
  Files: TStringList;
  Pend: Integer;
  D: TSelectDirectoryDialog;
begin
  try
    Pend := Length(MPPendingConnections(Doc));
    if Pend > 0 then
      if MessageDlg('MakePCB', Format('Ainda ha %d ligacoes sem trilha. Exportar assim mesmo?', [Pend]),
        mtWarning, [mbYes, mbNo], 0) <> mrYes then Exit;
    if FFileName <> '' then
      Folder := ExtractFilePath(FFileName) + BaseName + '_gerber'
    else
    begin
      D := TSelectDirectoryDialog.Create(Self);
      try
        D.Title := 'Pasta para os arquivos Gerber/Excellon';
        if not D.Execute then Exit;
        Folder := IncludeTrailingPathDelimiter(D.FileName) + BaseName + '_gerber';
      finally
        D.Free;
      end;
    end;
    Files := TStringList.Create;
    try
      ExportTo(Folder, Files);
      OpenLaserButton.Enabled := True;
      Status.Caption := Format('%d arquivos em %s', [Files.Count, Folder]);
      RefreshBOM;
      FabSummary.Caption := FabSummary.Caption + #10#10 + ExtractFileName(Files[0]);
      if Files.Count > 1 then
        FabSummary.Caption := FabSummary.Caption + #10'... e mais ' + IntToStr(Files.Count - 1);
    finally
      Files.Free;
    end;
  except
    on E: Exception do ShowError(E);
  end;
end;

procedure TMakePCBForm.OpenLaserClick(Sender: TObject);
var
  Registry: TSuiteRegistry;
  Root, Err, Candidate: string;
  C: TSuiteContext;
  I: Integer;
begin
  if (FExportDir = '') or not DirectoryExists(FExportDir) then
  begin
    ExportClick(nil);
    if (FExportDir = '') or not DirectoryExists(FExportDir) then Exit;
  end;
  Registry := TSuiteRegistry.Create;
  try
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
      if not TSuiteLauncher.LaunchArtifact(Registry.Tool(Registry.Find(stiLaserPCB)), Root,
        C.ProjectRoot, FExportDir, Err) then
        raise Exception.Create(Err);
      Status.Caption := 'Placa aberta no LaserPCB.';
    except
      on E: Exception do ShowError(E);
    end;
  finally
    Registry.Free;
  end;
end;

procedure TMakePCBForm.SaveBOMClick(Sender: TObject);
var
  D: TSaveDialog;
  S: TStringList;
begin
  D := TSaveDialog.Create(Self);
  S := TStringList.Create;
  try
    D.Filter := 'CSV (*.csv)|*.csv';
    D.DefaultExt := 'csv';
    D.FileName := BaseName + '-BOM.csv';
    D.Options := D.Options + [ofOverwritePrompt];
    if D.Execute then
    begin
      S.Text := MPBOMToCSV(MPBuildBOM(Doc));
      S.SaveToFile(D.FileName);
      Status.Caption := 'Lista de materiais salva.';
    end;
  finally
    S.Free;
    D.Free;
  end;
end;

procedure TMakePCBForm.SaveArtworkClick(Sender: TObject);
const
  DPI = 600;
var
  D: TSaveDialog;
  Bmp: TBitmap;
  Png: TPortableNetworkGraphic;
  R: TMPRenderer;
  V: TMPViewport;
  M: Integer;
begin
  D := TSaveDialog.Create(Self);
  try
    D.Filter := 'PNG (*.png)|*.png';
    D.DefaultExt := 'png';
    D.FileName := BaseName + '-arte.png';
    D.Options := D.Options + [ofOverwritePrompt];
    if not D.Execute then Exit;
    Bmp := TBitmap.Create;
    Png := TPortableNetworkGraphic.Create;
    R := TMPRenderer.Create;
    try
      R.Doc := Doc;
      R.Mode := vmArtwork;
      R.ArtworkLayer := Editor.Renderer.ArtworkLayer;
      R.ArtworkMirror := MirrorBox.Checked;
      V.Scale := DPI / MP_INCH;
      M := Round(2 * V.Scale);   { 2 mm de margem }
      Bmp.SetSize(Round(Doc.BoardW * V.Scale) + 2 * M, Round(Doc.BoardH * V.Scale) + 2 * M);
      V.OX := M; V.OY := Bmp.Height - M;
      R.Paint(Bmp.Canvas, V, Rect(0, 0, Bmp.Width, Bmp.Height));
      Png.Assign(Bmp);
      Png.SaveToFile(D.FileName);
      Status.Caption := Format('Arte final salva (%d dpi, escala 1:1): %s', [DPI, D.FileName]);
    finally
      R.Free;
      Png.Free;
      Bmp.Free;
    end;
  finally
    D.Free;
  end;
end;

procedure TMakePCBForm.LoadExample;
begin
  Editor.Modified := False;
  ExampleClick(nil);
end;

procedure TMakePCBForm.AutoRoute;
begin
  RouteClick(nil);
end;

procedure TMakePCBForm.RunDRC;
begin
  CheckClick(nil);
end;

procedure TMakePCBForm.ShowStep(N: Integer);
begin
  FocusPage(N);
end;

procedure TMakePCBForm.ShowView(M: TMPViewMode);
begin
  SetViewMode(M);
end;

{ ---------------- teclado / fechar ---------------- }

procedure TMakePCBForm.FormKey(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  { copiar/colar so quando o foco esta na placa (nos campos e texto normal) }
  if (ssCtrl in Shift) and (ActiveControl = Editor) then
    case Key of
      VK_C: begin Editor.CopySelection; Key := 0; Exit; end;
      VK_X: begin Editor.CutSelection; Key := 0; Exit; end;
      VK_V: begin PasteClick(nil); Key := 0; Exit; end;
      VK_D: begin Editor.DuplicateSelection; Key := 0; Exit; end;
      VK_A: begin Editor.SelectAll; Key := 0; Exit; end;
    end;
  if ssCtrl in Shift then
    case Key of
      VK_Z: begin UndoClick(nil); Key := 0; end;
      VK_Y: begin RedoClick(nil); Key := 0; end;
      VK_S: begin SaveClick(nil); Key := 0; end;
      VK_O: begin OpenClick(nil); Key := 0; end;
      VK_N: begin NewClick(nil); Key := 0; end;
    end;
end;

procedure TMakePCBForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  CanClose := ConfirmDiscard;
end;

end.
