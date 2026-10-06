unit laserart_main;

{ LaserArt - editor de arte para laser da suite MultiSuite.

  Layout inspirado no LightBurn (area de trabalho com reguas, ferramentas a
  esquerda, paleta de camadas no rodape, painel "Cortes / Camadas" e painel
  de saida a direita) e na tabela de camadas do RDWorks (cor, modo,
  velocidade/potencia, saida, setas de ordem), no visual da suite.

  O LaserArt prepara o trabalho e gera G-code; quem controla a maquina e o
  MultiCNC ("Enviar ao MultiCNC" abre o arquivo no MultiCNC). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, StrUtils, Forms, Controls, Graphics, Dialogs, StdCtrls,
  ExtCtrls, ComCtrls, Spin, LCLType, LCLIntf, multisuite_numfmt,
  multisuite_icons, multisuite_controls, multisuite_types, multisuite_registry,
  multisuite_launcher, laserart_model, laserart_geom, laserart_imaging,
  laserart_svgimport, laserart_output, laserart_materials, laserart_editor,
  laserart_widgets, laserart_calibrationform;

type
  TLaserArtForm = class(TForm)
  private
    Doc: TLADocument;
    Editor: TLAEditor;
    Materials: TLAMaterialLibrary;
    FUndo, FRedo: TStringList;
    FUndoTag: string;
    FModified: Boolean;
    FUpdating: Boolean;
    FInternal: Boolean;   { alteracao feita pelo proprio formulario (desfazer ja registrado) }
    FProjectRoot: string;

    Header: TSuiteHeader;
    Badge: TSuiteBadge;
    ToolButtons: array[TLATool] of TSuiteButton;
    BtnPreview, BtnSaveGCode, BtnSend: TSuiteButton;

    { barra de propriedades }
    EdX, EdY, EdW, EdH, EdRot: TFloatSpinEdit;
    BtnLock: TSuiteButton;
    LblSel: TLabel;

    { camadas }
    LayerList: TLALayerList;
    LblLayer: TLabel;
    CbMode: TComboBox;
    EdSpeed, EdPMax, EdPMin, EdInterval: TFloatSpinEdit;
    EdPasses: TSpinEdit;
    ChkAir: TCheckBox;
    LayerEditor: TPanel;

    { objeto }
    PnlText, PnlImage, PnlShape, PnlNoSel: TPanel;
    MemoText: TMemo;
    CbFont: TComboBox;
    ChkBold, ChkItalic: TCheckBox;
    CbDither: TComboBox;
    TbBright, TbContrast: TTrackBar;
    ChkInvert: TCheckBox;
    LblImage: TLabel;
    EdSides: TSpinEdit;
    EdCorner: TFloatSpinEdit;
    ChkLocked: TCheckBox;
    TextTimer: TTimer;

    { materiais }
    LbMaterials: TListBox;
    LblMaterial: TLabel;

    { saida }
    CbStart: TComboBox;
    Origin: TLAOriginPicker;
    ChkOptimize, ChkSelOnly: TCheckBox;
    LblEstimate, LblWarn: TLabel;

    Palette: TLAPalette;
    Status: TStatusBar;
    Pages: TPageControl;

    { construcao da tela }
    function NewPanel(AParent: TWinControl; AAlign: TAlign; ASize: Integer; AColor: TColor): TPanel;
    function NewButton(AParent: TWinControl; const ACaption, AHint: string; X, Y, W, H: Integer;
      AStyle: TSuiteButtonStyle; AAccent: TColor; AIcon: TSuiteIconKind; AHandler: TNotifyEvent): TSuiteButton;
    function NewLabel(AParent: TWinControl; const AText: string; X, Y: Integer; AW: Integer = 0): TLabel;
    function NewFloat(AParent: TWinControl; X, Y, W: Integer; AMin, AMax: Double; ADec: Integer;
      AHandler: TNotifyEvent): TFloatSpinEdit;
    procedure BuildHeader;
    procedure BuildToolbar;
    procedure BuildPropBar;
    procedure BuildTools;
    procedure BuildRightPanel;
    procedure BuildLayersTab(AParent: TWinControl);
    procedure BuildObjectTab(AParent: TWinControl);
    procedure BuildMaterialsTab(AParent: TWinControl);
    procedure BuildOutputPanel(AParent: TWinControl);
    procedure BuildBottom;
    procedure CardPaint(Sender: TObject);
    procedure HeaderResize(Sender: TObject);

    { estado }
    procedure PushUndo(const ATag: string = '');
    procedure RestoreSnapshot(const S: string);
    procedure SetModified(V: Boolean);
    procedure UpdateTitle;
    procedure RefreshAll;
    procedure RefreshLayerEditor;
    procedure RefreshObjectPanel;
    procedure RefreshPropBar;
    procedure RefreshOutput;
    procedure RefreshMaterials;
    procedure RefreshTools;
    function SelectedLayer: Integer;
    function ConfirmDiscard: Boolean;
    function DocumentsDir: string;
    function FindSuiteRoot: string;
    function ImageLayer: Integer;
    procedure SetStatus(const S: string);

    { eventos }
    procedure EditorBeforeChange(Sender: TObject);
    procedure EditorChange(Sender: TObject);
    procedure EditorSelection(Sender: TObject);
    procedure EditorCursor(Sender: TObject; X, Y: Double);
    procedure ToolClick(Sender: TObject);
    procedure NewClick(Sender: TObject);
    procedure OpenClick(Sender: TObject);
    procedure SaveClick(Sender: TObject);
    procedure SaveAsClick(Sender: TObject);
    procedure ImportClick(Sender: TObject);
    procedure UndoClick(Sender: TObject);
    procedure RedoClick(Sender: TObject);
    procedure DuplicateClick(Sender: TObject);
    procedure DeleteClick(Sender: TObject);
    procedure MirrorHClick(Sender: TObject);
    procedure MirrorVClick(Sender: TObject);
    procedure TraceClick(Sender: TObject);
    procedure ZoomInClick(Sender: TObject);
    procedure ZoomOutClick(Sender: TObject);
    procedure ZoomFitClick(Sender: TObject);
    procedure CalibrationClick(Sender: TObject);
    procedure BedClick(Sender: TObject);
    procedure LockClick(Sender: TObject);
    procedure PropChange(Sender: TObject);
    procedure LayerSelect(Sender: TObject; L: Integer);
    procedure LayerToggle(Sender: TObject; L: Integer);
    procedure LayerParamChange(Sender: TObject);
    procedure LayerUpClick(Sender: TObject);
    procedure LayerDownClick(Sender: TObject);
    procedure PalettePick(Sender: TObject; L: Integer);
    procedure TextChange(Sender: TObject);
    procedure TextTimerFire(Sender: TObject);
    procedure ObjectParamChange(Sender: TObject);
    procedure MaterialSelect(Sender: TObject);
    procedure MaterialApplyClick(Sender: TObject);
    procedure MaterialSaveClick(Sender: TObject);
    procedure MaterialDeleteClick(Sender: TObject);
    procedure OutputParamChange(Sender: TObject);
    procedure PreviewClick(Sender: TObject);
    procedure SaveGCodeClick(Sender: TObject);
    procedure SendClick(Sender: TObject);
    procedure FormKey(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure FormDropFiles(Sender: TObject; const FileNames: array of string);
    function BuildJobChecked(out Job: TLAJob): Boolean;
    function WriteGCode(const FN: string; out Job: TLAJob): Boolean;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure OpenFile(const FN: string);
    procedure ImportFile(const FN: string);
    property ProjectRoot: string read FProjectRoot write FProjectRoot;
  end;

implementation

const
  RP_W = 384;          { largura do painel direito }
  ACCENT_ART: array[0..2] of Byte = (219, 39, 119);

function ArtAccent: TColor;
begin
  Result := RGBToColor(ACCENT_ART[0], ACCENT_ART[1], ACCENT_ART[2]);
end;

{ ---------------------------------------------------------------------------- }
{ Construcao                                                                   }

function TLaserArtForm.NewPanel(AParent: TWinControl; AAlign: TAlign; ASize: Integer;
  AColor: TColor): TPanel;
begin
  Result := TPanel.Create(Self);
  Result.Parent := AParent;
  Result.BevelOuter := bvNone;
  Result.Align := AAlign;
  if AAlign = alTop then Result.Top := 100000;
  if AAlign = alBottom then Result.Top := 0;
  if AAlign in [alLeft, alRight] then Result.Width := ASize
  else if AAlign in [alTop, alBottom] then Result.Height := ASize;
  Result.Color := AColor;
  Result.ParentColor := False;
end;

function TLaserArtForm.NewButton(AParent: TWinControl; const ACaption, AHint: string;
  X, Y, W, H: Integer; AStyle: TSuiteButtonStyle; AAccent: TColor; AIcon: TSuiteIconKind;
  AHandler: TNotifyEvent): TSuiteButton;
begin
  Result := TSuiteButton.Create(Self);
  Result.Parent := AParent;
  Result.SetBounds(X, Y, W, H);
  Result.Caption := ACaption;
  Result.Hint := AHint;
  Result.ShowHint := AHint <> '';
  Result.SetLook(AStyle, AAccent, AIcon);
  Result.OnClick := AHandler;
end;

function TLaserArtForm.NewLabel(AParent: TWinControl; const AText: string; X, Y: Integer;
  AW: Integer): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := AParent;
  Result.Caption := AText;
  Result.Left := X;
  Result.Top := Y;
  Result.Font.Size := 9;
  Result.Font.Color := clSuiteMuted;
  if AW > 0 then
  begin
    Result.AutoSize := False;
    Result.Width := AW;
    Result.Height := 18;
  end;
end;

function TLaserArtForm.NewFloat(AParent: TWinControl; X, Y, W: Integer; AMin, AMax: Double;
  ADec: Integer; AHandler: TNotifyEvent): TFloatSpinEdit;
begin
  Result := TFloatSpinEdit.Create(Self);
  Result.Parent := AParent;
  Result.SetBounds(X, Y, W, 26);
  Result.MinValue := AMin;
  Result.MaxValue := AMax;
  Result.DecimalPlaces := ADec;
  if ADec = 0 then Result.Increment := 1 else Result.Increment := Power(10, -Min(ADec, 1));
  Result.OnChange := AHandler;
end;

procedure TLaserArtForm.CardPaint(Sender: TObject);
var
  P: TPanel;
begin
  P := TPanel(Sender);
  P.Canvas.Pen.Color := clSuiteBorder;
  case P.Align of
    alLeft: P.Canvas.Line(P.Width - 1, 0, P.Width - 1, P.Height);
    alRight: P.Canvas.Line(0, 0, 0, P.Height);
    alBottom: P.Canvas.Line(0, 0, P.Width, 0);
  else
    P.Canvas.Line(0, P.Height - 1, P.Width, P.Height - 1);
  end;
end;

procedure TLaserArtForm.HeaderResize(Sender: TObject);
begin
  if Badge = nil then Exit;
  Badge.AnchorRight := Header.ClientWidth - 20;
  Badge.AutoFit;
end;

procedure TLaserArtForm.BuildHeader;
begin
  Header := TSuiteHeader.Create(Self);
  Header.Parent := Self;
  Header.Align := alTop;
  Header.Top := 0;
  Header.Height := 64;
  Header.Setup('LaserArt', 'Logos, textos, vetores e imagens para gravacao e corte a laser', sikLaserArt);
  Header.OnResize := @HeaderResize;
  Badge := TSuiteBadge.Create(Self);
  Badge.Parent := Header;
  Badge.SetBounds(900, 17, 200, 30);
  Badge.Caption := 'Nova arte';
end;

procedure TLaserArtForm.BuildToolbar;
var
  P: TPanel;
  X: Integer;

  function Btn(const C, H: string; W: Integer; Icon: TSuiteIconKind; Handler: TNotifyEvent;
    Gap: Integer = 4): TSuiteButton;
  begin
    Result := NewButton(P, C, H, X, 8, W, 32, sbsOutline, clSuitePrimary, Icon, Handler);
    X := X + W + Gap;
  end;

begin
  P := NewPanel(Self, alTop, 48, clSuiteCard);
  P.Top := Header.Top + Header.Height;
  P.OnPaint := @CardPaint;
  X := 10;
  Btn('', 'Novo (Ctrl+N)', 36, sikNew, @NewClick);
  Btn('', 'Abrir .lart (Ctrl+O)', 36, sikFolder, @OpenClick);
  Btn('', 'Salvar (Ctrl+S)', 36, sikSave, @SaveClick, 10);
  Btn('Importar', 'Importar SVG ou imagem (Ctrl+I)', 104, sikImport, @ImportClick, 14);
  Btn('', 'Desfazer (Ctrl+Z)', 36, sikUndo, @UndoClick);
  Btn('', 'Refazer (Ctrl+Y)', 36, sikRedo, @RedoClick, 14);
  Btn('', 'Duplicar (Ctrl+D)', 36, sikCopy, @DuplicateClick);
  Btn('', 'Excluir (Delete)', 36, sikTrash, @DeleteClick);
  Btn('', 'Espelhar na horizontal', 36, sikMirrorH, @MirrorHClick);
  Btn('', 'Espelhar na vertical', 36, sikMirrorV, @MirrorVClick, 14);
  Btn('Vetorizar', 'Vetorizar imagem selecionada (gera contornos)', 104, sikWand, @TraceClick, 14);
  Btn('Mesa', 'Tamanho da mesa e S maximo', 82, sikGear, @BedClick);
  Btn('Teste de material', 'Gerar matriz de potencia x velocidade', 176, sikGauge, @CalibrationClick);
end;

procedure TLaserArtForm.BuildPropBar;
var
  P: TPanel;
begin
  P := NewPanel(Self, alTop, 42, RGBToColor(248, 250, 252));
  P.Top := Header.Top + Header.Height + 48 + 1;
  P.OnPaint := @CardPaint;
  NewLabel(P, 'X', 14, 12);
  EdX := NewFloat(P, 30, 8, 92, -10000, 10000, 2, @PropChange);
  NewLabel(P, 'Y', 132, 12);
  EdY := NewFloat(P, 148, 8, 92, -10000, 10000, 2, @PropChange);
  NewLabel(P, 'Largura', 258, 12);
  EdW := NewFloat(P, 312, 8, 92, 0.01, 10000, 2, @PropChange);
  BtnLock := NewButton(P, '', 'Travar proporcao', 410, 7, 30, 28, sbsSoft, clSuitePrimary, sikUnlock, @LockClick);
  NewLabel(P, 'Altura', 448, 12);
  EdH := NewFloat(P, 492, 8, 92, 0.01, 10000, 2, @PropChange);
  NewLabel(P, 'Rotacao', 602, 12);
  EdRot := NewFloat(P, 658, 8, 80, -360, 360, 1, @PropChange);
  NewLabel(P, 'mm  |  graus', 746, 12);
  LblSel := NewLabel(P, '', 850, 12, 400);
  LblSel.Font.Color := clSuiteText;
end;

procedure TLaserArtForm.BuildTools;
var
  P: TPanel;
  T: TLATool;
  Y: Integer;
const
  Icons: array[TLATool] of TSuiteIconKind = (sikPointer, sikRect, sikCircle, sikPolygon, sikPen, sikText);
  Hints: array[TLATool] of string = ('Selecionar e mover (V)', 'Retangulo (R)', 'Elipse (E)',
    'Poligono (P)', 'Linha / polilinha: clique os pontos; duplo clique termina (L)', 'Texto (T)');
begin
  P := NewPanel(Self, alLeft, 54, clSuiteCard);
  P.OnPaint := @CardPaint;
  Y := 10;
  for T := Low(TLATool) to High(TLATool) do
  begin
    ToolButtons[T] := NewButton(P, '', Hints[T], 8, Y, 38, 38, sbsOutline, ArtAccent, Icons[T], @ToolClick);
    ToolButtons[T].Tag := Ord(T);
    Inc(Y, 44);
  end;
  Inc(Y, 6);
  NewButton(P, '', 'Importar imagem', 8, Y, 38, 38, sbsOutline, ArtAccent, sikImage, @ImportClick);
  Inc(Y, 56);
  NewButton(P, '', 'Aproximar', 8, Y, 38, 34, sbsOutline, clSuiteMuted, sikZoomIn, @ZoomInClick);
  Inc(Y, 40);
  NewButton(P, '', 'Afastar', 8, Y, 38, 34, sbsOutline, clSuiteMuted, sikZoomOut, @ZoomOutClick);
  Inc(Y, 40);
  NewButton(P, '', 'Mostrar a mesa inteira', 8, Y, 38, 34, sbsOutline, clSuiteMuted, sikFit, @ZoomFitClick);
end;

procedure TLaserArtForm.BuildLayersTab(AParent: TWinControl);
var
  TopP: TPanel;
  X, Y: Integer;
begin
  TopP := NewPanel(AParent, alTop, 40, clSuiteCard);
  NewButton(TopP, '', 'Executar esta camada antes', 6, 4, 40, 30, sbsSoft, clSuitePrimary, sikArrowUp, @LayerUpClick);
  NewButton(TopP, '', 'Executar esta camada depois', 50, 4, 40, 30, sbsSoft, clSuitePrimary, sikArrowDown, @LayerDownClick);
  LblLayer := NewLabel(TopP, 'Selecione uma camada', 100, 10, 260);
  LblLayer.Font.Style := [fsBold];
  LblLayer.Font.Color := clSuiteText;
  TopP := NewPanel(AParent, alTop, 156, clSuiteCard);
  LayerList := TLALayerList.Create(Self);
  LayerList.Parent := TopP;
  LayerList.Align := alClient;
  LayerList.BorderSpacing.Around := 6;
  LayerList.Document := Doc;
  LayerList.OnSelectLayer := @LayerSelect;
  LayerList.OnToggle := @LayerToggle;

  LayerEditor := NewPanel(AParent, alClient, 0, clSuiteCard);
  X := 10; Y := 2;
  NewLabel(LayerEditor, 'Modo', X, Y);
  CbMode := TComboBox.Create(Self);
  CbMode.Parent := LayerEditor;
  CbMode.Style := csDropDownList;
  CbMode.Items.Add('Linha (corte)');
  CbMode.Items.Add('Preencher');
  CbMode.Items.Add('Imagem');
  CbMode.SetBounds(X, Y + 18, 168, 26);
  CbMode.OnChange := @LayerParamChange;
  NewLabel(LayerEditor, 'Velocidade (mm/min)', 188, Y);
  EdSpeed := NewFloat(LayerEditor, 188, Y + 18, 168, 0, 100000, 0, @LayerParamChange);
  Y := Y + 48;
  NewLabel(LayerEditor, 'Potencia max (%)', X, Y);
  EdPMax := NewFloat(LayerEditor, X, Y + 18, 110, 0, 100, 1, @LayerParamChange);
  NewLabel(LayerEditor, 'Potencia min (%)', 128, Y);
  EdPMin := NewFloat(LayerEditor, 128, Y + 18, 110, 0, 100, 1, @LayerParamChange);
  NewLabel(LayerEditor, 'Passadas', 246, Y);
  EdPasses := TSpinEdit.Create(Self);
  EdPasses.Parent := LayerEditor;
  EdPasses.SetBounds(246, Y + 18, 110, 26);
  EdPasses.MinValue := 1;
  EdPasses.MaxValue := 50;
  EdPasses.OnChange := @LayerParamChange;
  Y := Y + 48;
  NewLabel(LayerEditor, 'Intervalo (mm)', X, Y);
  EdInterval := NewFloat(LayerEditor, X, Y + 18, 110, 0.01, 5, 3, @LayerParamChange);
  EdInterval.Increment := 0.01;
  ChkAir := TCheckBox.Create(Self);
  ChkAir.Parent := LayerEditor;
  ChkAir.Caption := 'Ar comprimido (M8/M9)';
  ChkAir.SetBounds(128, Y + 20, 200, 24);
  ChkAir.OnChange := @LayerParamChange;
  Y := Y + 48;
  with NewLabel(LayerEditor, 'Velocidade e potencia dependem da maquina e do material: use o Teste de material e salve o resultado na aba Materiais.', X, Y, 346) do
  begin
    Height := 34;
    WordWrap := True;
    Font.Size := 8;
  end;
end;

procedure TLaserArtForm.BuildObjectTab(AParent: TWinControl);
var
  Y: Integer;
  Lb: TLabel;
begin
  PnlNoSel := NewPanel(AParent, alClient, 0, clSuiteCard);
  with NewLabel(PnlNoSel, 'Selecione um objeto na area de trabalho para editar texto, imagem ou forma.', 12, 14, 340) do
  begin
    Height := 40;
    WordWrap := True;
  end;

  { texto }
  PnlText := NewPanel(AParent, alTop, 230, clSuiteCard);
  with TSuiteSectionTitle.CreateTitle(Self, 'TEXTO', sikText, ArtAccent) do
  begin
    Parent := PnlText; SetBounds(12, 8, 300, 22);
  end;
  MemoText := TMemo.Create(Self);
  MemoText.Parent := PnlText;
  MemoText.SetBounds(12, 34, 344, 80);
  MemoText.ScrollBars := ssAutoVertical;
  MemoText.OnChange := @TextChange;
  NewLabel(PnlText, 'Fonte', 12, 122);
  CbFont := TComboBox.Create(Self);
  CbFont.Parent := PnlText;
  CbFont.SetBounds(12, 140, 344, 26);
  CbFont.Style := csDropDownList;
  CbFont.Items.Assign(Screen.Fonts);
  CbFont.Sorted := True;
  CbFont.OnChange := @ObjectParamChange;
  ChkBold := TCheckBox.Create(Self);
  ChkBold.Parent := PnlText; ChkBold.Caption := 'Negrito'; ChkBold.SetBounds(12, 174, 100, 24);
  ChkBold.OnChange := @ObjectParamChange;
  ChkItalic := TCheckBox.Create(Self);
  ChkItalic.Parent := PnlText; ChkItalic.Caption := 'Italico'; ChkItalic.SetBounds(120, 174, 100, 24);
  ChkItalic.OnChange := @ObjectParamChange;
  Lb := NewLabel(PnlText, 'Altura do texto = campo "Altura" na barra superior.', 12, 202, 344);
  Lb.Font.Size := 8;

  { imagem }
  PnlImage := NewPanel(AParent, alTop, 244, clSuiteCard);
  with TSuiteSectionTitle.CreateTitle(Self, 'IMAGEM', sikImage, ArtAccent) do
  begin
    Parent := PnlImage; SetBounds(12, 8, 300, 22);
  end;
  LblImage := NewLabel(PnlImage, '', 12, 30, 344);
  Y := 50;
  NewLabel(PnlImage, 'Conversao (dithering)', 12, Y);
  CbDither := TComboBox.Create(Self);
  CbDither.Parent := PnlImage;
  CbDither.Style := csDropDownList;
  CbDither.Items.Add('Limiar (preto e branco)');
  CbDither.Items.Add('Floyd-Steinberg');
  CbDither.Items.Add('Jarvis');
  CbDither.Items.Add('Tons de cinza (potencia variavel)');
  CbDither.SetBounds(12, Y + 18, 344, 26);
  CbDither.OnChange := @ObjectParamChange;
  Y := Y + 52;
  NewLabel(PnlImage, 'Brilho', 12, Y);
  TbBright := TTrackBar.Create(Self);
  TbBright.Parent := PnlImage;
  TbBright.SetBounds(70, Y - 4, 286, 30);
  TbBright.Min := -100; TbBright.Max := 100; TbBright.Frequency := 25;
  TbBright.OnChange := @ObjectParamChange;
  Y := Y + 32;
  NewLabel(PnlImage, 'Contraste', 12, Y);
  TbContrast := TTrackBar.Create(Self);
  TbContrast.Parent := PnlImage;
  TbContrast.SetBounds(70, Y - 4, 286, 30);
  TbContrast.Min := -100; TbContrast.Max := 100; TbContrast.Frequency := 25;
  TbContrast.OnChange := @ObjectParamChange;
  Y := Y + 32;
  ChkInvert := TCheckBox.Create(Self);
  ChkInvert.Parent := PnlImage; ChkInvert.Caption := 'Inverter (negativo)';
  ChkInvert.SetBounds(12, Y, 200, 24);
  ChkInvert.OnChange := @ObjectParamChange;
  NewButton(PnlImage, 'Vetorizar imagem', 'Gera contornos a partir das areas escuras', 12, Y + 28, 344, 30,
    sbsSoft, ArtAccent, sikWand, @TraceClick);

  { forma }
  PnlShape := NewPanel(AParent, alTop, 104, clSuiteCard);
  with TSuiteSectionTitle.CreateTitle(Self, 'FORMA', sikPolygon, ArtAccent) do
  begin
    Parent := PnlShape; SetBounds(12, 6, 300, 22);
  end;
  NewLabel(PnlShape, 'Lados (poligono)', 12, 28);
  EdSides := TSpinEdit.Create(Self);
  EdSides.Parent := PnlShape;
  EdSides.SetBounds(12, 46, 110, 26);
  EdSides.MinValue := 3; EdSides.MaxValue := 64;
  EdSides.OnChange := @ObjectParamChange;
  NewLabel(PnlShape, 'Cantos (mm)', 140, 28);
  EdCorner := NewFloat(PnlShape, 140, 46, 110, 0, 1000, 2, @ObjectParamChange);
  ChkLocked := TCheckBox.Create(Self);
  ChkLocked.Parent := PnlShape;
  ChkLocked.Caption := 'Travar posicao';
  ChkLocked.Hint := 'Nao move nem redimensiona';
  ChkLocked.SetBounds(12, 76, 340, 24);
  ChkLocked.OnChange := @ObjectParamChange;

  { ordem de cima para baixo: texto, imagem, forma }
  PnlText.Top := 0;
  PnlImage.Top := PnlText.Top + PnlText.Height + 1;
  PnlShape.Top := PnlImage.Top + PnlImage.Height + 1;

  TextTimer := TTimer.Create(Self);
  TextTimer.Enabled := False;
  TextTimer.Interval := 350;
  TextTimer.OnTimer := @TextTimerFire;
end;

procedure TLaserArtForm.BuildMaterialsTab(AParent: TWinControl);
var
  P: TPanel;
begin
  P := NewPanel(AParent, alBottom, 140, clSuiteCard);
  LblMaterial := NewLabel(P, '', 12, 6, 344);
  LblMaterial.Height := 34;
  LblMaterial.WordWrap := True;
  NewButton(P, 'Aplicar na camada selecionada', '', 12, 44, 344, 30, sbsSolid, clSuitePrimary, sikArrowLeft, @MaterialApplyClick);
  NewButton(P, 'Salvar camada', 'Salva os parametros da camada selecionada como material', 12, 80, 170, 30,
    sbsOutline, clSuitePrimary, sikSave, @MaterialSaveClick);
  NewButton(P, 'Excluir', '', 188, 80, 168, 30, sbsOutline, clSuiteDanger, sikTrash, @MaterialDeleteClick);
  LbMaterials := TListBox.Create(Self);
  LbMaterials.Parent := AParent;
  LbMaterials.Align := alClient;
  LbMaterials.BorderSpacing.Around := 8;
  LbMaterials.OnSelectionChange := nil;
  LbMaterials.OnClick := @MaterialSelect;
end;

procedure TLaserArtForm.BuildOutputPanel(AParent: TWinControl);
var
  P: TPanel;
begin
  P := NewPanel(AParent, alBottom, 262, clSuiteCard);
  P.OnPaint := @CardPaint;
  with TSuiteSectionTitle.CreateTitle(Self, 'SAIDA', sikExport, clSuitePrimary) do
  begin
    Parent := P; SetBounds(12, 10, 300, 22);
  end;
  BtnPreview := NewButton(P, 'Previa', 'Mostra o percurso do laser e o enquadramento', 12, 38, 110, 34,
    sbsOutline, clSuitePrimary, sikEye, @PreviewClick);
  BtnSaveGCode := NewButton(P, 'Salvar G-code', 'Salva o arquivo G-code', 126, 38, 150, 34, sbsOutline, clSuitePrimary, sikSave, @SaveGCodeClick);
  BtnSend := NewButton(P, 'Enviar ao MultiCNC', 'Gera o G-code e abre no MultiCNC (CNC Laser)', 12, 78, 264, 38,
    sbsSolid, clSuiteSuccess, sikCNC, @SendClick);
  NewLabel(P, 'Iniciar de', 12, 124);
  CbStart := TComboBox.Create(Self);
  CbStart.Parent := P;
  CbStart.Style := csDropDownList;
  CbStart.Items.Add(StartFromName(sfAbsolute));
  CbStart.Items.Add(StartFromName(sfUserOrigin));
  CbStart.Items.Add(StartFromName(sfWorkZero));
  CbStart.SetBounds(12, 142, 264, 26);
  CbStart.OnChange := @OutputParamChange;
  NewLabel(P, 'Origem', 292, 38);
  Origin := TLAOriginPicker.Create(Self);
  Origin.Parent := P;
  Origin.SetBounds(290, 56, 76, 62);
  Origin.Color := clSuiteCard;
  Origin.Hint := 'Ponto do trabalho que fica no zero da peca (Zero Workpiece no MultiCNC)';
  Origin.ShowHint := True;
  Origin.OnChange := @OutputParamChange;
  ChkOptimize := TCheckBox.Create(Self);
  ChkOptimize.Parent := P; ChkOptimize.Caption := 'Otimizar percurso';
  ChkOptimize.SetBounds(12, 174, 150, 24);
  ChkOptimize.OnChange := @OutputParamChange;
  ChkSelOnly := TCheckBox.Create(Self);
  ChkSelOnly.Parent := P; ChkSelOnly.Caption := 'So a selecao';
  ChkSelOnly.SetBounds(170, 174, 150, 24);
  ChkSelOnly.OnChange := @OutputParamChange;
  LblEstimate := NewLabel(P, '', 12, 202, 356);
  LblEstimate.Font.Color := clSuiteText;
  LblEstimate.Font.Style := [fsBold];
  LblWarn := NewLabel(P, '', 12, 222, 356);
  LblWarn.Height := 34;
  LblWarn.WordWrap := True;
  LblWarn.Font.Size := 8;
end;

procedure TLaserArtForm.BuildRightPanel;
var
  RP: TPanel;
  T: TTabSheet;
begin
  RP := NewPanel(Self, alRight, RP_W, clSuiteCard);
  RP.OnPaint := @CardPaint;
  BuildOutputPanel(RP);
  Pages := TPageControl.Create(Self);
  Pages.Parent := RP;
  Pages.Align := alClient;
  Pages.BorderSpacing.Around := 6;
  T := TTabSheet.Create(Self); T.PageControl := Pages; T.Caption := 'Cortes / Camadas';
  BuildLayersTab(T);
  T := TTabSheet.Create(Self); T.PageControl := Pages; T.Caption := 'Objeto';
  BuildObjectTab(T);
  T := TTabSheet.Create(Self); T.PageControl := Pages; T.Caption := 'Materiais';
  BuildMaterialsTab(T);
  Pages.ActivePageIndex := 0;
end;

procedure TLaserArtForm.BuildBottom;
var
  P: TPanel;
begin
  Status := TStatusBar.Create(Self);
  Status.Parent := Self;
  Status.Align := alBottom;
  Status.SimplePanel := False;
  with Status.Panels.Add do Width := 180;
  with Status.Panels.Add do Width := 240;
  Status.Panels.Add;
  P := NewPanel(Self, alBottom, 36, RGBToColor(248, 250, 252));
  P.Top := Status.Top - 40;
  P.OnPaint := @CardPaint;
  Palette := TLAPalette.Create(Self);
  Palette.Parent := P;
  Palette.Align := alClient;
  Palette.Color := RGBToColor(248, 250, 252);
  Palette.Hint := 'Clique: camada para novos objetos e para os objetos selecionados';
  Palette.ShowHint := True;
  Palette.OnPick := @PalettePick;
end;

constructor TLaserArtForm.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner);
  Caption := 'LaserArt';
  Position := poScreenCenter;
  SetBounds(0, 0, 1440, 900);
  Constraints.MinWidth := 1180;
  Constraints.MinHeight := 760;
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  Color := clSuiteSurface;
  KeyPreview := True;
  OnKeyDown := @FormKey;
  OnCloseQuery := @FormCloseQuery;
  AllowDropFiles := True;
  OnDropFiles := @FormDropFiles;
  ShowHint := True;

  Doc := TLADocument.Create;
  Materials := TLAMaterialLibrary.Create;
  try
    Materials.Load;
  except
    on E: Exception do ;
  end;
  FUndo := TStringList.Create;
  FRedo := TStringList.Create;

  BuildHeader;
  BuildToolbar;
  BuildPropBar;
  BuildBottom;
  BuildTools;
  BuildRightPanel;

  Editor := TLAEditor.Create(Self);
  Editor.Parent := Self;
  Editor.Align := alClient;
  Editor.Document := Doc;
  Editor.OnBeforeChange := @EditorBeforeChange;
  Editor.OnChange := @EditorChange;
  Editor.OnSelectionChange := @EditorSelection;
  Editor.OnCursor := @EditorCursor;
  Editor.CurrentLayer := 0;

  RefreshAll;
  HeaderResize(nil);
  SetStatus('Pronto. Desenhe, digite um texto ou importe SVG/imagem (arraste o arquivo para a janela).');
end;

destructor TLaserArtForm.Destroy;
begin
  Editor.Document := nil;
  Doc.Free;
  Materials.Free;
  FUndo.Free;
  FRedo.Free;
  inherited Destroy;
end;

{ ---------------------------------------------------------------------------- }
{ Estado                                                                       }

procedure TLaserArtForm.SetStatus(const S: string);
begin
  Status.Panels[2].Text := S;
end;

procedure TLaserArtForm.PushUndo(const ATag: string);
begin
  if (ATag <> '') and (ATag = FUndoTag) then Exit;
  FUndoTag := ATag;
  FUndo.Add(Doc.ToJSON);
  while FUndo.Count > 50 do FUndo.Delete(0);
  FRedo.Clear;
  SetModified(True);
end;

procedure TLaserArtForm.RestoreSnapshot(const S: string);
var
  FN, N: string;
begin
  FN := Doc.FileName;
  N := Doc.Name;
  Doc.FromJSON(S);
  Doc.FileName := FN;
  Doc.Name := N;
  FUndoTag := '';
  Editor.DocumentReplaced;
  RefreshAll;
end;

procedure TLaserArtForm.SetModified(V: Boolean);
begin
  FModified := V;
  UpdateTitle;
end;

procedure TLaserArtForm.UpdateTitle;
var
  N: string;
begin
  if Doc.FileName <> '' then N := ExtractFileName(Doc.FileName) else N := Doc.Name;
  Caption := 'LaserArt - ' + N + IfThen(FModified, ' *', '');
  Badge.Caption := N + IfThen(FModified, '  (alterado)', '');
  if FModified then Badge.DotColor := clSuiteWarning else Badge.DotColor := clSuiteSuccess;
  HeaderResize(nil);
end;

function TLaserArtForm.SelectedLayer: Integer;
begin
  Result := LayerList.SelectedLayer;
end;

procedure TLaserArtForm.RefreshTools;
var
  T: TLATool;
begin
  for T := Low(TLATool) to High(TLATool) do
    if Editor.Tool = T then
      ToolButtons[T].SetLook(sbsSolid, ArtAccent)
    else
      ToolButtons[T].SetLook(sbsOutline, ArtAccent);
end;

procedure TLaserArtForm.RefreshAll;
begin
  Doc.SyncLayerOrder;
  if (LayerList.SelectedLayer < 0) and (Length(Doc.LayerOrder) > 0) then
    LayerList.SelectedLayer := Doc.LayerOrder[0];
  LayerList.Invalidate;
  Palette.Current := Editor.CurrentLayer;
  Palette.Invalidate;
  RefreshTools;
  RefreshLayerEditor;
  RefreshObjectPanel;
  RefreshPropBar;
  RefreshOutput;
  RefreshMaterials;
  UpdateTitle;
  Editor.Invalidate;
end;

procedure TLaserArtForm.RefreshLayerEditor;
var
  L: TLALayer;
  En: Boolean;
begin
  FUpdating := True;
  try
    En := SelectedLayer >= 0;
    LayerEditor.Enabled := En;
    if not En then
    begin
      LblLayer.Caption := 'Selecione uma camada';
      Exit;
    end;
    L := Doc.Layers[SelectedLayer];
    LblLayer.Caption := Format('Camada %s  -  %s', [L.Caption, IfThen(Doc.LayerUsed(L.Index),
      'em uso', 'sem objetos')]);
    CbMode.ItemIndex := Ord(L.Mode);
    EdSpeed.Value := L.Speed;
    EdPMax.Value := L.PowerMax;
    EdPMin.Value := L.PowerMin;
    EdPasses.Value := L.Passes;
    EdInterval.Value := L.Interval;
    EdInterval.Enabled := L.Mode <> lmLine;
    EdPMin.Enabled := L.Mode = lmImage;
    ChkAir.Checked := L.AirAssist;
  finally
    FUpdating := False;
  end;
end;

procedure TLaserArtForm.RefreshObjectPanel;
var
  Sel: TList;
  S: TLAShape;
begin
  FUpdating := True;
  try
    Sel := Editor.Selection;
    if Sel.Count = 1 then S := TLAShape(Sel[0]) else S := nil;
    PnlText.Visible := (S <> nil) and (S.Kind = skText);
    PnlImage.Visible := (S <> nil) and (S.Kind = skImage);
    PnlShape.Visible := (S <> nil);
    PnlNoSel.Visible := S = nil;
    if S = nil then Exit;
    if S.Kind = skText then
    begin
      if MemoText.Text <> S.Text then MemoText.Text := S.Text;
      CbFont.ItemIndex := CbFont.Items.IndexOf(S.FontName);
      ChkBold.Checked := S.Bold;
      ChkItalic.Checked := S.Italic;
    end;
    if S.Kind = skImage then
    begin
      LblImage.Caption := ExtractFileName(S.ImageFile);
      CbDither.ItemIndex := Ord(S.Dither);
      TbBright.Position := S.Brightness;
      TbContrast.Position := S.Contrast;
      ChkInvert.Checked := S.Invert;
    end;
    EdSides.Enabled := S.Kind = skPolygon;
    EdSides.Value := S.Sides;
    EdCorner.Enabled := S.Kind = skRect;
    EdCorner.Value := S.CornerRadius;
    ChkLocked.Checked := S.Locked;
  finally
    FUpdating := False;
  end;
end;

procedure TLaserArtForm.RefreshPropBar;
var
  B: TLABox;
  Sel: TList;
  En: Boolean;
  S: string;
begin
  FUpdating := True;
  try
    Sel := Editor.Selection;
    En := Sel.Count > 0;
    EdX.Enabled := En; EdY.Enabled := En; EdW.Enabled := En; EdH.Enabled := En;
    EdRot.Enabled := En;
    if not En then
    begin
      LblSel.Caption := 'Nada selecionado';
      Status.Panels[1].Text := '';
      Exit;
    end;
    B := Editor.SelectionBox;
    EdX.Value := B.X1;
    EdY.Value := B.Y1;
    EdW.Value := Max(0.01, B.X2 - B.X1);
    EdH.Value := Max(0.01, B.Y2 - B.Y1);
    if Sel.Count = 1 then
    begin
      EdRot.Value := TLAShape(Sel[0]).Angle;
      S := TLAShape(Sel[0]).KindName + Format('  -  camada C%.2d', [TLAShape(Sel[0]).Layer]);
    end
    else
      S := Format('%d objetos', [Sel.Count]);
    LblSel.Caption := S;
    Status.Panels[1].Text := Format('Selecao: %.2f x %.2f mm', [B.X2 - B.X1, B.Y2 - B.Y1], InvariantFS);
  finally
    FUpdating := False;
  end;
end;

procedure TLaserArtForm.RefreshOutput;
begin
  FUpdating := True;
  try
    CbStart.ItemIndex := Ord(Doc.StartFrom);
    Origin.Value := Doc.JobOrigin;
    Origin.Enabled := Doc.StartFrom = sfWorkZero;
    ChkOptimize.Checked := Doc.Optimize;
    if Editor.ShowPreview then
      BtnPreview.SetLook(sbsSolid, clSuitePrimary, sikEye)
    else
      BtnPreview.SetLook(sbsOutline, clSuitePrimary, sikEye);
  finally
    FUpdating := False;
  end;
end;

procedure TLaserArtForm.RefreshMaterials;
var
  I, Old: Integer;
begin
  Old := LbMaterials.ItemIndex;
  LbMaterials.Items.BeginUpdate;
  try
    LbMaterials.Items.Clear;
    for I := 0 to Materials.Count - 1 do
      LbMaterials.Items.Add(Materials.Item(I).Name + '  -  ' + Materials.Item(I).Summary);
  finally
    LbMaterials.Items.EndUpdate;
  end;
  if (Old >= 0) and (Old < LbMaterials.Items.Count) then LbMaterials.ItemIndex := Old;
  if Materials.Count = 0 then
    LblMaterial.Caption := 'Nenhum material salvo. Ajuste uma camada com valores testados e clique em "Salvar camada".'
  else
    LblMaterial.Caption := 'Selecione um material e aplique na camada selecionada.';
end;

{ ---------------------------------------------------------------------------- }
{ Eventos do editor                                                            }

procedure TLaserArtForm.EditorBeforeChange(Sender: TObject);
begin
  if not FInternal then
    PushUndo;
end;

procedure TLaserArtForm.EditorChange(Sender: TObject);
begin
  Doc.SyncLayerOrder;
  SetModified(True);
  LayerList.Invalidate;
  if Editor.ShowPreview then
  begin
    Editor.ShowPreview := False;
    RefreshOutput;
  end;
end;

procedure TLaserArtForm.EditorSelection(Sender: TObject);
var
  Sel: TList;
begin
  Sel := Editor.Selection;
  if not FInternal then
    FUndoTag := '';
  if Sel.Count > 0 then
  begin
    LayerList.SelectedLayer := TLAShape(Sel[0]).Layer;
    LayerList.EnsureVisible(TLAShape(Sel[0]).Layer);
    RefreshLayerEditor;
  end;
  RefreshPropBar;
  RefreshObjectPanel;
  { texto recem-criado: abre a aba Objeto para digitar }
  if (Editor.Tool = ltText) and (Sel.Count = 1) and (TLAShape(Sel[0]).Kind = skText) then
  begin
    Editor.Tool := ltSelect;
    Pages.ActivePageIndex := 1;
    if MemoText.CanFocus then
    begin
      MemoText.SetFocus;
      MemoText.SelectAll;
    end;
    SetStatus('Digite o texto na aba Objeto; a altura fica no campo "Altura".');
  end;
  RefreshTools;
end;

procedure TLaserArtForm.EditorCursor(Sender: TObject; X, Y: Double);
begin
  Status.Panels[0].Text := Format('X %.2f   Y %.2f mm', [X, Y], InvariantFS);
end;

procedure TLaserArtForm.ToolClick(Sender: TObject);
begin
  Editor.Tool := TLATool(TControl(Sender).Tag);
  RefreshTools;
  case Editor.Tool of
    ltLine: SetStatus('Linha: clique os pontos. Clique no primeiro ponto para fechar; duplo clique ou Enter termina; Esc cancela.');
    ltText: SetStatus('Texto: clique onde o texto deve comecar e edite na aba Objeto.');
    ltSelect: SetStatus('Selecionar: clique ou arraste. Shift adiciona a selecao; setas movem 1 mm (Shift: 10 mm).');
  else
    SetStatus('Arraste para desenhar. Shift mantem a proporcao.');
  end;
  if Editor.CanFocus then Editor.SetFocus;
end;

{ ---------------------------------------------------------------------------- }
{ Arquivo                                                                      }

function TLaserArtForm.ConfirmDiscard: Boolean;
begin
  Result := True;
  if not FModified then Exit;
  case MessageDlg('LaserArt', 'Salvar as alteracoes em "' + Doc.Name + '"?',
    mtConfirmation, [mbYes, mbNo, mbCancel], 0) of
    mrYes:
      begin
        SaveClick(nil);
        Result := not FModified;
      end;
    mrNo: Result := True;
  else
    Result := False;
  end;
end;

procedure TLaserArtForm.NewClick(Sender: TObject);
begin
  if not ConfirmDiscard then Exit;
  Doc.Clear;
  FUndo.Clear;
  FRedo.Clear;
  FUndoTag := '';
  LayerList.SelectedLayer := -1;
  Editor.DocumentReplaced;
  Editor.ZoomFit;
  SetModified(False);
  RefreshAll;
end;

procedure TLaserArtForm.OpenFile(const FN: string);
var
  Ext: string;
begin
  Ext := LowerCase(ExtractFileExt(FN));
  if Ext = LA_FILE_EXT then
  begin
    try
      Doc.LoadFromFile(FN);
      Doc.Name := ChangeFileExt(ExtractFileName(FN), '');
    except
      on E: Exception do
      begin
        MessageDlg('Nao foi possivel abrir', E.Message, mtError, [mbOK], 0);
        Exit;
      end;
    end;
    FUndo.Clear;
    FRedo.Clear;
    FUndoTag := '';
    LayerList.SelectedLayer := -1;
    Editor.DocumentReplaced;
    Editor.ZoomFit;
    SetModified(False);
    RefreshAll;
    SetStatus('Aberto: ' + FN);
  end
  else
    ImportFile(FN);
end;

procedure TLaserArtForm.OpenClick(Sender: TObject);
var
  D: TOpenDialog;
begin
  if not ConfirmDiscard then Exit;
  D := TOpenDialog.Create(Self);
  try
    D.Title := 'Abrir arte LaserArt';
    D.Filter := 'LaserArt (*.lart)|*.lart|Todos os arquivos|*.*';
    D.Options := [ofFileMustExist, ofEnableSizing];
    if D.Execute then OpenFile(D.FileName);
  finally
    D.Free;
  end;
end;

procedure TLaserArtForm.SaveAsClick(Sender: TObject);
var
  D: TSaveDialog;
begin
  D := TSaveDialog.Create(Self);
  try
    D.Title := 'Salvar arte LaserArt';
    D.Filter := 'LaserArt (*.lart)|*.lart';
    D.DefaultExt := 'lart';
    D.FileName := Doc.Name + LA_FILE_EXT;
    D.Options := [ofOverwritePrompt, ofPathMustExist, ofEnableSizing];
    if not D.Execute then Exit;
    Doc.Name := ChangeFileExt(ExtractFileName(D.FileName), '');
    Doc.SaveToFile(D.FileName);
    SetModified(False);
    SetStatus('Salvo: ' + D.FileName);
  finally
    D.Free;
  end;
end;

procedure TLaserArtForm.SaveClick(Sender: TObject);
begin
  if Doc.FileName = '' then
  begin
    SaveAsClick(Sender);
    Exit;
  end;
  try
    Doc.SaveToFile(Doc.FileName);
    SetModified(False);
    SetStatus('Salvo: ' + Doc.FileName);
  except
    on E: Exception do MessageDlg('Nao foi possivel salvar', E.Message, mtError, [mbOK], 0);
  end;
end;

function TLaserArtForm.ImageLayer: Integer;
var
  I: Integer;
begin
  { usa a camada atual se for de imagem ou estiver livre; senao a 1a livre }
  Result := Editor.CurrentLayer;
  if (Doc.Layers[Result].Mode = lmImage) or not Doc.LayerUsed(Result) then Exit;
  for I := 0 to LA_LAYER_COUNT - 1 do
    if Doc.Layers[I].Mode = lmImage then Exit(I);
  for I := 0 to LA_LAYER_COUNT - 1 do
    if not Doc.LayerUsed(I) then Exit(I);
end;

procedure TLaserArtForm.ImportFile(const FN: string);
var
  Ext: string;
  R: TLASvgResult;
  Added: TList;
  S: TLAShape;
  G: TLAGray;
  W, H, F: Double;
  L, I: Integer;
begin
  Ext := LowerCase(ExtractFileExt(FN));
  Added := TList.Create;
  try
    if Ext = '.svg' then
    begin
      PushUndo;
      try
        R := ImportSVGFile(Doc, FN, Editor.CurrentLayer, Added);
      except
        on E: Exception do
        begin
          MessageDlg('SVG', 'Nao foi possivel importar: ' + E.Message, mtError, [mbOK], 0);
          Exit;
        end;
      end;
      if R.Shapes = 0 then
      begin
        MessageDlg('SVG', 'Nenhum vetor encontrado no arquivo.', mtInformation, [mbOK], 0);
        Exit;
      end;
      SetStatus(Format('SVG importado: %d objeto(s), %d caminho(s)%s', [R.Shapes, R.Paths,
        IfThen(R.Skipped > 0, Format('; ignorados: %s', [R.SkippedKinds]), '')]));
    end
    else if (Ext = '.png') or (Ext = '.jpg') or (Ext = '.jpeg') or (Ext = '.bmp') then
    begin
      G := LoadGray(FN);
      if G.W = 0 then
      begin
        MessageDlg('Imagem', 'Nao foi possivel ler a imagem.', mtError, [mbOK], 0);
        Exit;
      end;
      PushUndo;
      L := ImageLayer;
      if not Doc.LayerUsed(L) then
      begin
        Doc.Layers[L].Mode := lmImage;
        if Doc.Layers[L].Interval <= 0 then Doc.Layers[L].Interval := 0.1;
      end;
      S := TLAShape.Create(skImage);
      S.Layer := L;
      S.Name := ExtractFileName(FN);
      S.ImageFile := FN;
      S.Dither := ldFloyd;
      { 0,1 mm por pixel, limitado a 80% da mesa }
      W := G.W * 0.1; H := G.H * 0.1;
      F := Min(1, Min(Doc.BedW * 0.8 / W, Doc.BedH * 0.8 / H));
      S.W := W * F; S.H := H * F;
      S.X := 10; S.Y := Doc.BedH - 10 - S.H;
      Doc.Add(S);
      Added.Add(S);
      SetStatus(Format('Imagem importada: %d x %d px na camada C%.2d (%s)', [G.W, G.H, L, LayerModeName(Doc.Layers[L].Mode)]));
    end
    else if Ext = LA_FILE_EXT then
    begin
      OpenFile(FN);
      Exit;
    end
    else
    begin
      MessageDlg('Importar', 'Formato nao suportado: ' + Ext, mtWarning, [mbOK], 0);
      Exit;
    end;
    Doc.SyncLayerOrder;
    Editor.Selection.Clear;
    for I := 0 to Added.Count - 1 do
      Editor.Selection.Add(Added[I]);
    if Added.Count > 0 then
      LayerList.SelectedLayer := TLAShape(Added[0]).Layer;
    Editor.Tool := ltSelect;
    EditorChange(nil);
    EditorSelection(nil);
    RefreshAll;
  finally
    Added.Free;
  end;
end;

procedure TLaserArtForm.ImportClick(Sender: TObject);
var
  D: TOpenDialog;
  I: Integer;
begin
  D := TOpenDialog.Create(Self);
  try
    D.Title := 'Importar';
    D.Filter := 'Vetores e imagens|*.svg;*.png;*.jpg;*.jpeg;*.bmp|SVG|*.svg|Imagens|*.png;*.jpg;*.jpeg;*.bmp';
    D.Options := [ofFileMustExist, ofEnableSizing, ofAllowMultiSelect];
    if D.Execute then
      for I := 0 to D.Files.Count - 1 do
        ImportFile(D.Files[I]);
  finally
    D.Free;
  end;
end;

procedure TLaserArtForm.FormDropFiles(Sender: TObject; const FileNames: array of string);
var
  I: Integer;
begin
  for I := 0 to High(FileNames) do
    ImportFile(FileNames[I]);
end;

{ ---------------------------------------------------------------------------- }
{ Edicao                                                                       }

procedure TLaserArtForm.UndoClick(Sender: TObject);
begin
  if FUndo.Count = 0 then Exit;
  FRedo.Add(Doc.ToJSON);
  RestoreSnapshot(FUndo[FUndo.Count - 1]);
  FUndo.Delete(FUndo.Count - 1);
  SetModified(True);
end;

procedure TLaserArtForm.RedoClick(Sender: TObject);
begin
  if FRedo.Count = 0 then Exit;
  FUndo.Add(Doc.ToJSON);
  RestoreSnapshot(FRedo[FRedo.Count - 1]);
  FRedo.Delete(FRedo.Count - 1);
  SetModified(True);
end;

procedure TLaserArtForm.DuplicateClick(Sender: TObject);
begin
  Editor.DuplicateSelection;
end;

procedure TLaserArtForm.DeleteClick(Sender: TObject);
begin
  Editor.DeleteSelection;
  RefreshAll;
end;

procedure TLaserArtForm.MirrorHClick(Sender: TObject);
begin
  Editor.MirrorSelection(True);
end;

procedure TLaserArtForm.MirrorVClick(Sender: TObject);
begin
  Editor.MirrorSelection(False);
end;

procedure TLaserArtForm.TraceClick(Sender: TObject);
var
  Img, S: TLAShape;
  W, H: Double;
  P: TLAPaths;
begin
  if (Editor.Selection.Count <> 1) or (TLAShape(Editor.Selection[0]).Kind <> skImage) then
  begin
    MessageDlg('Vetorizar', 'Selecione uma imagem para vetorizar.', mtInformation, [mbOK], 0);
    Exit;
  end;
  Img := TLAShape(Editor.Selection[0]);
  Screen.Cursor := crHourGlass;
  try
    P := ImageToPaths(Img.ImageFile, Img.Brightness, Img.Contrast, Img.Invert, W, H);
  finally
    Screen.Cursor := crDefault;
  end;
  if Length(P) = 0 then
  begin
    MessageDlg('Vetorizar', 'Nenhum contorno encontrado (ajuste brilho/contraste).', mtInformation, [mbOK], 0);
    Exit;
  end;
  PushUndo;
  S := TLAShape.Create(skPath);
  S.Name := 'Vetor de ' + Img.Name;
  S.Local := P;
  S.LocalW := W;
  S.LocalH := H;
  S.X := Img.X; S.Y := Img.Y; S.W := Img.W; S.H := Img.H;
  S.MirrorX := Img.MirrorX; S.MirrorY := Img.MirrorY;
  S.Angle := Img.Angle;
  if Doc.Layers[Editor.CurrentLayer].Mode <> lmImage then
    S.Layer := Editor.CurrentLayer
  else
    S.Layer := IfThen(Img.Layer = 0, 1, 0);
  Doc.Add(S);
  Editor.SelectShape(S);
  EditorChange(nil);
  RefreshAll;
  SetStatus(Format('Vetorizado: %d contornos na camada C%.2d.', [Length(P), S.Layer]));
end;

procedure TLaserArtForm.ZoomInClick(Sender: TObject);
begin
  Editor.ZoomBy(1.25);
end;

procedure TLaserArtForm.ZoomOutClick(Sender: TObject);
begin
  Editor.ZoomBy(1 / 1.25);
end;

procedure TLaserArtForm.ZoomFitClick(Sender: TObject);
begin
  Editor.ZoomFit;
end;

procedure TLaserArtForm.LockClick(Sender: TObject);
begin
  Editor.LockRatio := not Editor.LockRatio;
  if Editor.LockRatio then
    BtnLock.SetLook(sbsSolid, clSuitePrimary, sikUnlock)
  else
    BtnLock.SetLook(sbsSoft, clSuitePrimary, sikUnlock);
end;

procedure TLaserArtForm.PropChange(Sender: TObject);
var
  B: TLABox;
  W, H: Double;
begin
  if FUpdating or (Editor.Selection.Count = 0) then Exit;
  B := Editor.SelectionBox;
  W := EdW.Value;
  H := EdH.Value;
  if (Editor.LockRatio or ((Editor.Selection.Count = 1) and (TLAShape(Editor.Selection[0]).Kind = skText)))
     and (B.X2 - B.X1 > 0) and (B.Y2 - B.Y1 > 0) then
  begin
    if Sender = EdW then H := W * (B.Y2 - B.Y1) / (B.X2 - B.X1)
    else if Sender = EdH then W := H * (B.X2 - B.X1) / (B.Y2 - B.Y1);
  end;
  PushUndo('prop');
  FInternal := True;
  try
    if Sender = EdRot then
      Editor.SetSelectionAngle(EdRot.Value)
    else
      Editor.SetSelectionBounds(EdX.Value, EdY.Value, W, H);
  finally
    FInternal := False;
  end;
  RefreshPropBar;
end;

procedure TLaserArtForm.BedClick(Sender: TObject);
var
  S: string;
  V: Double;
  Parts: TStringList;
begin
  S := Format('%.0f x %.0f; %.0f', [Doc.BedW, Doc.BedH, Doc.SMax], InvariantFS);
  if not InputQuery('Mesa', 'Area da mesa (L x A em mm) e S maximo do GRBL ($30):', S) then Exit;
  Parts := TStringList.Create;
  try
    Parts.Text := StringReplace(StringReplace(StringReplace(S, 'x', #10, [rfReplaceAll, rfIgnoreCase]),
      ';', #10, [rfReplaceAll]), ',', '.', [rfReplaceAll]);
    if Parts.Count < 2 then Exit;
    PushUndo;
    if TryParseFloat(Trim(Parts[0]), V) and (V > 0) then Doc.BedW := V;
    if TryParseFloat(Trim(Parts[1]), V) and (V > 0) then Doc.BedH := V;
    if (Parts.Count > 2) and TryParseFloat(Trim(Parts[2]), V) and (V > 0) then Doc.SMax := V;
  finally
    Parts.Free;
  end;
  Editor.ZoomFit;
  SetStatus(Format('Mesa %.0f x %.0f mm, S maximo %.0f', [Doc.BedW, Doc.BedH, Doc.SMax], InvariantFS));
end;

procedure TLaserArtForm.CalibrationClick(Sender: TObject);
var
  F: TLaserCalibrationForm;
begin
  F := TLaserCalibrationForm.Create(Self);
  try
    F.ShowModal;
  finally
    F.Free;
  end;
end;

{ ---------------------------------------------------------------------------- }
{ Camadas e paleta                                                             }

procedure TLaserArtForm.LayerSelect(Sender: TObject; L: Integer);
begin
  Editor.CurrentLayer := L;
  Palette.Current := L;
  Palette.Invalidate;
  RefreshLayerEditor;
end;

procedure TLaserArtForm.LayerToggle(Sender: TObject; L: Integer);
begin
  SetModified(True);
  Editor.PreviewJob := nil;
  Editor.Invalidate;
end;

procedure TLaserArtForm.LayerParamChange(Sender: TObject);
var
  L: TLALayer;
begin
  if FUpdating or (SelectedLayer < 0) then Exit;
  PushUndo('layer' + IntToStr(SelectedLayer));
  L := Doc.Layers[SelectedLayer];
  L.Mode := TLALayerMode(Max(0, CbMode.ItemIndex));
  L.Speed := EdSpeed.Value;
  L.PowerMax := EdPMax.Value;
  L.PowerMin := Min(EdPMin.Value, EdPMax.Value);
  L.Passes := EdPasses.Value;
  L.Interval := EdInterval.Value;
  L.AirAssist := ChkAir.Checked;
  EdInterval.Enabled := L.Mode <> lmLine;
  EdPMin.Enabled := L.Mode = lmImage;
  LayerList.Invalidate;
  Editor.PreviewJob := nil;
  if Sender = EdInterval then Editor.InvalidatePreviews;
  SetModified(True);
end;

procedure TLaserArtForm.LayerUpClick(Sender: TObject);
begin
  if SelectedLayer < 0 then Exit;
  PushUndo;
  Doc.MoveLayer(SelectedLayer, -1);
  LayerList.Invalidate;
  Editor.PreviewJob := nil;
end;

procedure TLaserArtForm.LayerDownClick(Sender: TObject);
begin
  if SelectedLayer < 0 then Exit;
  PushUndo;
  Doc.MoveLayer(SelectedLayer, 1);
  LayerList.Invalidate;
  Editor.PreviewJob := nil;
end;

procedure TLaserArtForm.PalettePick(Sender: TObject; L: Integer);
begin
  Editor.CurrentLayer := L;
  if Editor.Selection.Count > 0 then
    Editor.SetSelectionLayer(L);
  LayerList.SelectedLayer := L;
  RefreshAll;
  SetStatus(Format('Camada atual: C%.2d', [L]));
end;

{ ---------------------------------------------------------------------------- }
{ Objeto                                                                       }

procedure TLaserArtForm.TextChange(Sender: TObject);
begin
  if FUpdating then Exit;
  TextTimer.Enabled := False;
  TextTimer.Enabled := True;
end;

procedure TLaserArtForm.TextTimerFire(Sender: TObject);
var
  S: TLAShape;
begin
  TextTimer.Enabled := False;
  if (Editor.Selection.Count <> 1) then Exit;
  S := TLAShape(Editor.Selection[0]);
  if S.Kind <> skText then Exit;
  PushUndo('text');
  S.Text := MemoText.Text;
  RebuildTextShape(S);
  EditorChange(nil);
  RefreshPropBar;
  Editor.Invalidate;
end;

procedure TLaserArtForm.ObjectParamChange(Sender: TObject);
var
  S: TLAShape;
begin
  if FUpdating or (Editor.Selection.Count <> 1) then Exit;
  S := TLAShape(Editor.Selection[0]);
  PushUndo('obj' + TComponent(Sender).Name + IntToStr(PtrInt(Sender)));
  if (Sender = CbFont) or (Sender = ChkBold) or (Sender = ChkItalic) then
  begin
    if CbFont.ItemIndex >= 0 then S.FontName := CbFont.Text;
    S.Bold := ChkBold.Checked;
    S.Italic := ChkItalic.Checked;
    RebuildTextShape(S);
  end
  else if (Sender = CbDither) or (Sender = TbBright) or (Sender = TbContrast) or (Sender = ChkInvert) then
  begin
    S.Dither := TLADither(Max(0, CbDither.ItemIndex));
    S.Brightness := TbBright.Position;
    S.Contrast := TbContrast.Position;
    S.Invert := ChkInvert.Checked;
    S.InvalidatePreview;
  end
  else if Sender = EdSides then
    S.Sides := EdSides.Value
  else if Sender = EdCorner then
    S.CornerRadius := EdCorner.Value
  else if Sender = ChkLocked then
    S.Locked := ChkLocked.Checked;
  EditorChange(nil);
  RefreshPropBar;
  Editor.Invalidate;
end;

{ ---------------------------------------------------------------------------- }
{ Materiais                                                                    }

procedure TLaserArtForm.MaterialSelect(Sender: TObject);
var
  M: TLAMaterial;
begin
  if (LbMaterials.ItemIndex < 0) or (LbMaterials.ItemIndex >= Materials.Count) then Exit;
  M := Materials.Item(LbMaterials.ItemIndex);
  LblMaterial.Caption := M.Name + ': ' + M.Summary + IfThen(M.Notes <> '', ' - ' + M.Notes, '');
end;

procedure TLaserArtForm.MaterialApplyClick(Sender: TObject);
begin
  if (LbMaterials.ItemIndex < 0) or (SelectedLayer < 0) then
  begin
    MessageDlg('Materiais', 'Selecione um material e uma camada.', mtInformation, [mbOK], 0);
    Exit;
  end;
  PushUndo;
  Materials.Item(LbMaterials.ItemIndex).ToLayer(Doc.Layers[SelectedLayer]);
  RefreshLayerEditor;
  LayerList.Invalidate;
  Editor.PreviewJob := nil;
  Editor.InvalidatePreviews;
  SetStatus('Material aplicado na camada ' + Doc.Layers[SelectedLayer].Caption);
end;

procedure TLaserArtForm.MaterialSaveClick(Sender: TObject);
var
  N: string;
  M: TLAMaterial;
begin
  if SelectedLayer < 0 then Exit;
  if not Doc.Layers[SelectedLayer].Calibrated then
  begin
    MessageDlg('Materiais', 'Informe velocidade e potencia testadas antes de salvar o material.', mtWarning, [mbOK], 0);
    Exit;
  end;
  N := '';
  if not InputQuery('Salvar material', 'Nome (ex.: MDF 3 mm - corte):', N) or (Trim(N) = '') then Exit;
  M := Materials.Add(Trim(N));
  M.FromLayer(Doc.Layers[SelectedLayer]);
  try
    Materials.Save;
  except
    on E: Exception do MessageDlg('Materiais', 'Nao foi possivel salvar: ' + E.Message, mtError, [mbOK], 0);
  end;
  RefreshMaterials;
  LbMaterials.ItemIndex := Materials.Count - 1;
  Pages.ActivePageIndex := 2;
end;

procedure TLaserArtForm.MaterialDeleteClick(Sender: TObject);
begin
  if LbMaterials.ItemIndex < 0 then Exit;
  if MessageDlg('Materiais', 'Excluir "' + Materials.Item(LbMaterials.ItemIndex).Name + '"?',
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes then Exit;
  Materials.Delete(LbMaterials.ItemIndex);
  Materials.Save;
  RefreshMaterials;
end;

{ ---------------------------------------------------------------------------- }
{ Saida                                                                        }

procedure TLaserArtForm.OutputParamChange(Sender: TObject);
begin
  if FUpdating then Exit;
  Doc.StartFrom := TLAStartFrom(Max(0, CbStart.ItemIndex));
  Doc.JobOrigin := Origin.Value;
  Doc.Optimize := ChkOptimize.Checked;
  Origin.Enabled := Doc.StartFrom = sfWorkZero;
  if (Doc.StartFrom = sfUserOrigin) and (Sender = CbStart) then
    SetStatus('Origem do usuario: use o comando "Mesa" e o campo X/Y da selecao para posicionar; ' +
      'o trabalho sera gerado relativo a (0,0) da origem definida.');
  SetModified(True);
  Editor.PreviewJob := nil;
  if Editor.ShowPreview then PreviewClick(nil);
  Editor.Invalidate;
end;

function TLaserArtForm.BuildJobChecked(out Job: TLAJob): Boolean;
var
  Sel: TList;
begin
  if ChkSelOnly.Checked then Sel := Editor.Selection else Sel := nil;
  Screen.Cursor := crHourGlass;
  try
    Job := BuildJob(Doc, Sel);
  finally
    Screen.Cursor := crDefault;
  end;
  Result := Job.Ok;
  if Job.Box.Valid then
    LblEstimate.Caption := Format('Tempo %s  |  Area %.1f x %.1f mm',
      [FormatDuration(Job.EstSeconds), Job.Box.X2 - Job.Box.X1, Job.Box.Y2 - Job.Box.Y1], InvariantFS)
  else
    LblEstimate.Caption := '';
  if Job.Errors.Count > 0 then
  begin
    LblWarn.Font.Color := clSuiteDanger;
    LblWarn.Caption := Job.Errors[0];
  end
  else if Job.Warnings.Count > 0 then
  begin
    LblWarn.Font.Color := clSuiteWarning;
    LblWarn.Caption := Job.Warnings[0];
  end
  else
  begin
    LblWarn.Font.Color := clSuiteMuted;
    LblWarn.Caption := Format('%d movimentos  |  corte %.0f mm  |  deslocamento %.0f mm',
      [Job.Count, Job.CutLength, Job.TravelLength], InvariantFS);
  end;
end;

procedure TLaserArtForm.PreviewClick(Sender: TObject);
var
  Job: TLAJob;
begin
  if Editor.ShowPreview and (Sender <> nil) then
  begin
    Editor.ShowPreview := False;
    RefreshOutput;
    Exit;
  end;
  if not BuildJobChecked(Job) then
  begin
    Editor.ShowPreview := False;
    RefreshOutput;
    if Job.Errors.Count > 0 then
      MessageDlg('Previa', Job.Errors.Text, mtWarning, [mbOK], 0);
    Job.Free;
    Exit;
  end;
  Editor.PreviewJob := Job;
  Editor.ShowPreview := True;
  RefreshOutput;
  SetStatus('Previa: vermelho tracejado = deslocamento; azul = enquadramento e origem do trabalho.');
end;

function TLaserArtForm.WriteGCode(const FN: string; out Job: TLAJob): Boolean;
var
  G: TStringList;
begin
  Result := False;
  if not BuildJobChecked(Job) then
  begin
    MessageDlg('G-code', 'Nao foi possivel gerar o trabalho:' + LineEnding + LineEnding + Job.Errors.Text,
      mtWarning, [mbOK], 0);
    Exit;
  end;
  G := JobToGCode(Doc, Job);
  try
    G.SaveToFile(FN);
  finally
    G.Free;
  end;
  Result := True;
end;

procedure TLaserArtForm.SaveGCodeClick(Sender: TObject);
var
  D: TSaveDialog;
  Job: TLAJob;
begin
  D := TSaveDialog.Create(Self);
  Job := nil;
  try
    D.Title := 'Salvar G-code';
    D.Filter := 'G-code (*.gcode;*.nc)|*.gcode;*.nc';
    D.DefaultExt := 'gcode';
    if Doc.FileName <> '' then
      D.FileName := ChangeFileExt(Doc.FileName, '.gcode')
    else
      D.FileName := Doc.Name + '.gcode';
    D.Options := [ofOverwritePrompt, ofPathMustExist, ofEnableSizing];
    if not D.Execute then Exit;
    if WriteGCode(D.FileName, Job) then
      SetStatus(Format('G-code salvo: %s (%s)', [D.FileName, FormatDuration(Job.EstSeconds)]));
  finally
    Job.Free;
    D.Free;
  end;
end;

function TLaserArtForm.DocumentsDir: string;
begin
  {$IFDEF WINDOWS}
  Result := IncludeTrailingPathDelimiter(GetUserDir) + 'Documents' + PathDelim;
  {$ELSE}
  Result := IncludeTrailingPathDelimiter(GetUserDir);
  {$ENDIF}
  Result := Result + 'MultiSuite Projects' + PathDelim + 'LaserArt' + PathDelim;
end;

function TLaserArtForm.FindSuiteRoot: string;
var
  Dir, ParentDir, Marker: string;
  I: Integer;
begin
  Dir := ExcludeTrailingPathDelimiter(ExtractFilePath(ExpandFileName(ParamStr(0))));
  Marker := 'multisuite' + PathDelim + 'src' + PathDelim + 'app' + PathDelim + 'multisuite.lpi';
  for I := 0 to 6 do
  begin
    if FileExists(IncludeTrailingPathDelimiter(Dir) + Marker) then
      Exit(IncludeTrailingPathDelimiter(Dir));
    ParentDir := ExcludeTrailingPathDelimiter(ExtractFilePath(Dir));
    if (ParentDir = '') or (ParentDir = Dir) then Break;
    Dir := ParentDir;
  end;
  Result := IncludeTrailingPathDelimiter(ExtractFilePath(ExpandFileName(ParamStr(0))));
end;

procedure TLaserArtForm.SendClick(Sender: TObject);
var
  FN, Err: string;
  Job: TLAJob;
  Reg: TSuiteRegistry;
  Idx: Integer;
  Size: Int64;
  SR: TSearchRec;
begin
  if Doc.FileName <> '' then
    FN := ChangeFileExt(Doc.FileName, '.gcode')
  else
  begin
    FN := DocumentsDir;
    ForceDirectories(FN);
    FN := FN + Doc.Name + '.gcode';
  end;
  Job := nil;
  try
    if not WriteGCode(FN, Job) then Exit;
    Size := 0;
    if FindFirst(FN, faAnyFile, SR) = 0 then
    begin
      Size := SR.Size;
      FindClose(SR);
    end;
    if Size > LA_MULTICNC_MAX_BYTES then
    begin
      MessageDlg('Enviar ao MultiCNC', Format('O G-code tem %.1f MB; o MultiCNC aceita ate %d MB. ' +
        'Aumente o intervalo da camada de imagem ou reduza o tamanho. Arquivo salvo em:' + LineEnding + '%s',
        [Size / 1048576, LA_MULTICNC_MAX_BYTES div 1048576, FN], InvariantFS), mtWarning, [mbOK], 0);
      Exit;
    end;
    Reg := TSuiteRegistry.Create;
    try
      Idx := Reg.Find(stiMultiCNC);
      if (Idx < 0) or not TSuiteLauncher.LaunchArtifact(Reg.Tool(Idx), FindSuiteRoot, FProjectRoot, FN, Err) then
      begin
        MessageDlg('Enviar ao MultiCNC', 'G-code salvo em:' + LineEnding + FN + LineEnding + LineEnding +
          'Nao foi possivel abrir o MultiCNC: ' + Err, mtWarning, [mbOK], 0);
        Exit;
      end;
    finally
      Reg.Free;
    end;
    SetStatus(Format('Enviado ao MultiCNC: %s (%s). Confira a area com Frame antes de iniciar.',
      [ExtractFileName(FN), FormatDuration(Job.EstSeconds)]));
  finally
    Job.Free;
  end;
end;

{ ---------------------------------------------------------------------------- }
{ Teclado e fechamento                                                         }

procedure TLaserArtForm.FormKey(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  InEditor: Boolean;
  Step: Double;
begin
  InEditor := ActiveControl = Editor;
  if ssCtrl in Shift then
  begin
    case Key of
      VK_Z: if ssShift in Shift then RedoClick(nil) else UndoClick(nil);
      VK_Y: RedoClick(nil);
      VK_S: if ssShift in Shift then SaveAsClick(nil) else SaveClick(nil);
      VK_O: OpenClick(nil);
      VK_N: NewClick(nil);
      VK_I: ImportClick(nil);
      VK_D: if InEditor then DuplicateClick(nil) else Exit;
      VK_A: if InEditor then Editor.SelectAll else Exit;
    else
      Exit;
    end;
    Key := 0;
    Exit;
  end;
  if not InEditor then Exit;
  if ssShift in Shift then Step := 10 else Step := 1;
  case Key of
    VK_DELETE, VK_BACK: DeleteClick(nil);
    VK_ESCAPE: Editor.CancelTool;
    VK_RETURN: Editor.FinishPolyline(False);
    VK_LEFT: Editor.MoveSelection(-Step, 0);
    VK_RIGHT: Editor.MoveSelection(Step, 0);
    VK_UP: Editor.MoveSelection(0, Step);
    VK_DOWN: Editor.MoveSelection(0, -Step);
    VK_V: Editor.Tool := ltSelect;
    VK_R: Editor.Tool := ltRect;
    VK_E: Editor.Tool := ltEllipse;
    VK_P: Editor.Tool := ltPolygon;
    VK_L: Editor.Tool := ltLine;
    VK_T: Editor.Tool := ltText;
  else
    Exit;
  end;
  RefreshTools;
  RefreshPropBar;
  Key := 0;
end;

procedure TLaserArtForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  CanClose := ConfirmDiscard;
end;

end.
