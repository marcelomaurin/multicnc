unit routerpcb_main;

{ Tela principal do RouterPCB, no padrao visual da suite (igual ao LaserPCB e
  ao MakePCB): cabecalho TSuiteHeader, etapas na barra lateral, parametros a
  direita, previa no centro e rodape com Validar / Gerar G-code / Abrir no
  MultiCNC.

  Etapas: 1 Importar, 2 Isolacao, 3 Furacao, 4 Recorte, 5 Nivelamento,
  6 Saida. Os parametros so viram geometria em "Atualizar trajetorias"
  (Generate leva ~1 s numa placa media); qualquer alteracao marca o trabalho
  como pendente e desliga "Abrir no MultiCNC" ate gerar de novo. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls,
  Dialogs, Graphics, laserpcb_geom, laserpcb_drill, laserpcb_roles,
  routerpcb_types, routerpcb_project, routerpcb_heightmap, routerpcb_gcode,
  routerpcb_preview, routerpcb_cutout, multisuite_controls, multisuite_icons;

const
  RP_STEPS = 6;

type
  TRouterPCBForm = class(TForm)
  private
    P: TRouterPCBProject;
    HM: TRPHeightMap;
    View: TRPPreview;
    Pages: TPageControl;
    Nav: array[0..RP_STEPS - 1] of TSuiteButton;
    State: TSuiteBadge;
    Status, Info, Summary, DrillSummary, CutSummary, LevelSummary, IsoWidth: TLabel;
    LogMemo: TMemo;
    LayerList: TListBox;
    FooterPanel: TPanel;
    ValidateButton, ExportButton, SendButton: TSuiteButton;
    { importar }
    SideBox, RoleBox: TComboBox;
    ResEdit: TEdit;
    { isolacao }
    IsoOn: TCheckBox;
    IsoKind, IsoDir: TComboBox;
    IsoAngle, IsoTip, IsoDia, IsoDepth, IsoPasses, IsoOverlap, IsoFeed, IsoPlunge, IsoRPM: TEdit;
    { furacao }
    DrlOn, DrlPTH, DrlNPTH, DrlMill, DrlPerTool, DrlPause: TCheckBox;
    DrlBits, DrlTol, DrlDepth, DrlPeck, DrlPlunge, DrlSlot, DrlRPM: TEdit;
    { recorte }
    CutOn: TCheckBox;
    CutDir: TComboBox;
    CutDia, CutThick, CutExtra, CutStep, CutFeed, CutPlunge, CutRPM, CutTabs, CutTabW, CutTabH: TEdit;
    { nivelamento }
    LvlOn, LvlDrill, LvlCut: TCheckBox;
    LvlCols, LvlRows, LvlMargin, LvlDepth, LvlFeed, LvlSeg, LvlMax: TEdit;
    { maquina }
    MSafe, MTravel, MSpin, MRapid: TEdit;
    { vistas }
    VCopper, VIso, VDrill, VCut, VLevel: TCheckBox;
    FUpdating: Boolean;
    FExportedFile: string;
    FSourceDir: string;
    FGridKey: string;
    function Button(AParent: TWinControl; const AText: string; X, Y, W: Integer;
      AIcon: TSuiteIconKind; Handler: TNotifyEvent): TSuiteButton;
    function LabelAt(AParent: TWinControl; const AText: string; X, Y, W, H: Integer): TLabel;
    function Title(AParent: TWinControl; const AText: string; Y: Integer): TLabel;
    function Field(AParent: TWinControl; const AText, Value: string; Y: Integer): TEdit;
    function HalfField(AParent: TWinControl; const AText, Value: string; X, Y: Integer): TEdit;
    function Check(AParent: TWinControl; const AText: string; Y: Integer; Value: Boolean): TCheckBox;
    function Combo(AParent: TWinControl; const AText: string; const Items: array of string;
      Y: Integer): TComboBox;
    function Num(E: TEdit; const What: string): Double;
    function Int(E: TEdit; const What: string): Integer;
    procedure BuildPage(Index: Integer; S: TScrollBox);
    procedure LoadSettings;
    procedure ReadSettings;
    procedure SettingsChanged(Sender: TObject);
    procedure ViewsChanged(Sender: TObject);
    procedure NavClick(Sender: TObject);
    procedure OpenFolderClick(Sender: TObject);
    procedure OpenFilesClick(Sender: TObject);
    procedure NewClick(Sender: TObject);
    procedure LayerClick(Sender: TObject);
    procedure RoleChanged(Sender: TObject);
    procedure GenerateClick(Sender: TObject);
    procedure ValidateClick(Sender: TObject);
    procedure ExportClick(Sender: TObject);
    procedure SendClick(Sender: TObject);
    procedure ProbeExportClick(Sender: TObject);
    procedure ProbeImportClick(Sender: TObject);
    procedure FitClick(Sender: TObject);
    procedure ZoomInClick(Sender: TObject);
    procedure ZoomOutClick(Sender: TObject);
    procedure ResizeUI(Sender: TObject);
    procedure ShowUI(Sender: TObject);
    procedure RefreshLayers;
    procedure RefreshSummaries;
    procedure SyncHeightMap;
    procedure SetState(const ACaption: string; AColor: TColor);
    procedure ShowError(E: Exception);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure OpenFile(const FN: string);
    { gera, valida e devolve True se pronto (usado pelos testes) }
    function Prepare: Boolean;
    { grava os programas na pasta; devolve os arquivos (o chamador libera) }
    function ExportTo(const Folder: string): TStringList;
    procedure FocusPage(N: Integer);
    property Project: TRouterPCBProject read P;
    property HeightMap: TRPHeightMap read HM;
    property Preview: TRPPreview read View;
    property Log: TMemo read LogMemo;
  end;

implementation

uses
  multisuite_numfmt, multisuite_registry, multisuite_launcher, multisuite_types,
  multisuite_context;

const
  STEP_NAMES: array[0..RP_STEPS - 1] of string =
    ('1  Importar', '2  Isolacao', '3  Furacao', '4  Recorte', '5  Nivelamento', '6  Saida');
  STEP_ICONS: array[0..RP_STEPS - 1] of TSuiteIconKind =
    (sikImport, sikRouterPCB, sikTarget, sikCAM, sikGauge, sikExport);

function FS(V: Double): string;
begin
  Result := FormatFloat('0.###', V, InvariantFS);
end;

{ ---------------- construcao ---------------- }

function TRouterPCBForm.Button(AParent: TWinControl; const AText: string; X, Y, W: Integer;
  AIcon: TSuiteIconKind; Handler: TNotifyEvent): TSuiteButton;
begin
  Result := TSuiteButton.Create(Self);
  Result.Parent := AParent;
  Result.SetBounds(X, Y, W, 34);
  Result.Caption := AText;
  Result.SetLook(sbsSoft, clSuitePrimary, AIcon);
  Result.OnClick := Handler;
end;

function TRouterPCBForm.LabelAt(AParent: TWinControl; const AText: string; X, Y, W, H: Integer): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := AParent;
  Result.AutoSize := False;
  Result.SetBounds(X, Y, W, H);
  Result.WordWrap := True;
  Result.Caption := AText;
  Result.Font.Color := clSuiteMuted;
end;

function TRouterPCBForm.Title(AParent: TWinControl; const AText: string; Y: Integer): TLabel;
begin
  Result := LabelAt(AParent, AText, 16, Y, 280, 20);
  Result.WordWrap := False;
  Result.Font.Style := [fsBold];
end;

function TRouterPCBForm.Field(AParent: TWinControl; const AText, Value: string; Y: Integer): TEdit;
begin
  LabelAt(AParent, AText, 16, Y, 290, 18).WordWrap := False;
  Result := TEdit.Create(Self);
  Result.Parent := AParent;
  Result.SetBounds(16, Y + 20, 290, 28);
  Result.Text := Value;
  Result.OnChange := @SettingsChanged;
end;

function TRouterPCBForm.HalfField(AParent: TWinControl; const AText, Value: string; X, Y: Integer): TEdit;
begin
  LabelAt(AParent, AText, X, Y, 140, 18).WordWrap := False;
  Result := TEdit.Create(Self);
  Result.Parent := AParent;
  Result.SetBounds(X, Y + 20, 140, 28);
  Result.Text := Value;
  Result.OnChange := @SettingsChanged;
end;

function TRouterPCBForm.Check(AParent: TWinControl; const AText: string; Y: Integer; Value: Boolean): TCheckBox;
begin
  Result := TCheckBox.Create(Self);
  Result.Parent := AParent;
  Result.SetBounds(16, Y, 290, 24);
  Result.Caption := AText;
  Result.Checked := Value;
  Result.OnChange := @SettingsChanged;
end;

function TRouterPCBForm.Combo(AParent: TWinControl; const AText: string; const Items: array of string;
  Y: Integer): TComboBox;
var I: Integer;
begin
  LabelAt(AParent, AText, 16, Y, 290, 18).WordWrap := False;
  Result := TComboBox.Create(Self);
  Result.Parent := AParent;
  Result.SetBounds(16, Y + 20, 290, 30);
  Result.Style := csDropDownList;
  for I := 0 to High(Items) do Result.Items.Add(Items[I]);
  Result.ItemIndex := 0;
  Result.OnChange := @SettingsChanged;
end;

procedure TRouterPCBForm.BuildPage(Index: Integer; S: TScrollBox);
const
  DIRS: array[0..1] of string = ('Concordante (climb)', 'Discordante (convencional)');
var Y: Integer; Role: TLPLayerRole;
begin
  Title(S, STEP_NAMES[Index], 16).Font.Size := 11;
  Y := 52;
  case Index of
    0:
    begin
      LabelAt(S, 'Abra a pasta <nome>_gerber exportada pelo MakePCB (ou Gerber + Excellon de outro programa). ' +
        'Cobre, contorno e furos sao reconhecidos pelo nome e pelo atributo X2.', 16, Y, 290, 96);
      Button(S, 'Abrir pasta do MakePCB...', 16, Y + 100, 290, sikFolder, @OpenFolderClick)
        .SetLook(sbsSolid, clSuitePrimary, sikFolder);
      Button(S, 'Abrir arquivos...', 16, Y + 142, 290, sikImport, @OpenFilesClick);
      SideBox := Combo(S, 'Lado a fresar', ['Top (cobre de cima)', 'Bottom (espelhado)'], Y + 192);
      LabelAt(S, 'Placa de face simples do MakePCB tem o cobre embaixo: abre em Bottom e a saida ' +
        'ja sai espelhada. Vire a placa na mesa com o cobre para cima.', 16, Y + 248, 290, 96);
      LabelAt(S, 'Funcao da camada selecionada', 16, Y + 350, 290, 18).WordWrap := False;
      RoleBox := TComboBox.Create(Self);
      RoleBox.Parent := S;
      RoleBox.SetBounds(16, Y + 370, 290, 30);
      RoleBox.Style := csDropDownList;
      for Role := Low(TLPLayerRole) to High(TLPLayerRole) do RoleBox.Items.Add(LayerRoleName(Role));
      RoleBox.ItemIndex := 0;
      RoleBox.OnChange := @RoleChanged;
      ResEdit := Field(S, 'Resolucao do calculo (mm/pixel, 0 = auto)', '0', Y + 414);
    end;
    1:
    begin
      IsoOn := Check(S, 'Isolar o cobre', Y, True);
      IsoKind := Combo(S, 'Ferramenta', ['Fresa em V (gravacao)', 'Fresa de topo'], Y + 32);
      IsoAngle := HalfField(S, 'Angulo (graus)', '30', 16, Y + 88);
      IsoTip := HalfField(S, 'Ponta (mm)', '0.1', 166, Y + 88);
      IsoDia := HalfField(S, 'Diametro topo (mm)', '0.8', 16, Y + 144);
      IsoDepth := HalfField(S, 'Profundidade (mm)', '-0.08', 166, Y + 144);
      IsoWidth := LabelAt(S, '', 16, Y + 200, 290, 20);
      IsoWidth.Font.Style := [fsBold];
      IsoWidth.Font.Color := clSuitePrimary;
      IsoPasses := HalfField(S, 'Passadas', '2', 16, Y + 226);
      IsoOverlap := HalfField(S, 'Sobreposicao (%)', '30', 166, Y + 226);
      IsoDir := Combo(S, 'Sentido de corte (spindle M3)', DIRS, Y + 282);
      IsoFeed := HalfField(S, 'Avanco (mm/min)', '150', 16, Y + 338);
      IsoPlunge := HalfField(S, 'Mergulho (mm/min)', '50', 166, Y + 338);
      IsoRPM := Field(S, 'Rotacao do spindle (RPM)', '12000', Y + 394);
      LabelAt(S, 'A largura do corte da fresa V cresce com a profundidade. Se aparecer um circulo vermelho ' +
        'na previa, a fresa nao passa entre dois cobres: reduza a profundidade ou use ponta menor.',
        16, Y + 452, 290, 96);
      Button(S, 'Atualizar trajetorias', 16, Y + 554, 290, sikFlame, @GenerateClick);
    end;
    2:
    begin
      DrlOn := Check(S, 'Furar', Y, True);
      DrlBits := Field(S, 'Brocas disponiveis (mm)', '0.6; 0.8; 1.0; 1.2; 1.5; 2.0; 3.0', Y + 30);
      DrlTol := HalfField(S, 'Tolerancia (mm)', '0.1', 16, Y + 86);
      DrlDepth := HalfField(S, 'Profundidade (mm)', '-1.8', 166, Y + 86);
      DrlPeck := HalfField(S, 'Bicada (mm, 0 = direto)', '0', 16, Y + 142);
      DrlPlunge := HalfField(S, 'Mergulho (mm/min)', '60', 166, Y + 142);
      DrlSlot := HalfField(S, 'Avanco rasgos', '100', 16, Y + 198);
      DrlRPM := HalfField(S, 'Rotacao (RPM)', '12000', 166, Y + 198);
      DrlPTH := Check(S, 'Furos metalizados (PTH)', Y + 258, True);
      DrlNPTH := Check(S, 'Furos de fixacao (NPTH)', Y + 284, True);
      DrlMill := Check(S, 'Fresar furos maiores que a maior broca', Y + 310, True);
      DrlPerTool := Check(S, 'Um arquivo por broca (recomendado)', Y + 336, True);
      DrlPause := Check(S, 'Arquivo unico: pausar na troca (M0)', Y + 362, True);
      Button(S, 'Atualizar trajetorias', 16, Y + 398, 290, sikFlame, @GenerateClick);
      DrillSummary := LabelAt(S, 'Importe a placa e atualize as trajetorias.', 16, Y + 442, 290, 130);
    end;
    3:
    begin
      CutOn := Check(S, 'Recortar a placa', Y, True);
      CutDia := HalfField(S, 'Fresa de topo (mm)', '2', 16, Y + 30);
      CutThick := HalfField(S, 'Espessura (mm)', '1.6', 166, Y + 30);
      CutExtra := HalfField(S, 'Extra no fundo (mm)', '0.1', 16, Y + 86);
      CutStep := HalfField(S, 'Passo (mm)', '0.6', 166, Y + 86);
      CutFeed := HalfField(S, 'Avanco (mm/min)', '200', 16, Y + 142);
      CutPlunge := HalfField(S, 'Mergulho (mm/min)', '60', 166, Y + 142);
      CutRPM := Field(S, 'Rotacao (RPM)', '12000', Y + 198);
      Title(S, 'PONTES (TABS)', Y + 258);
      CutTabs := Field(S, 'Quantidade (0 = sem pontes)', '4', Y + 282);
      CutTabW := HalfField(S, 'Largura (mm)', '3', 16, Y + 338);
      CutTabH := HalfField(S, 'Altura (mm)', '0.6', 166, Y + 338);
      CutDir := Combo(S, 'Sentido de corte', DIRS, Y + 394);
      Button(S, 'Atualizar trajetorias', 16, Y + 452, 290, sikFlame, @GenerateClick);
      CutSummary := LabelAt(S, 'O recorte vai por ultimo: recortes internos primeiro, depois o contorno.',
        16, Y + 496, 290, 90);
    end;
    4:
    begin
      LvlOn := Check(S, 'Nivelar pela sondagem (autolevel)', Y, False);
      LvlCols := HalfField(S, 'Colunas', '5', 16, Y + 30);
      LvlRows := HalfField(S, 'Linhas', '4', 166, Y + 30);
      LvlMargin := HalfField(S, 'Margem (mm)', '0', 16, Y + 86);
      LvlDepth := HalfField(S, 'Limite sonda (mm)', '-2', 166, Y + 86);
      LvlFeed := HalfField(S, 'Avanco sonda', '50', 16, Y + 142);
      LvlSeg := HalfField(S, 'Segmento max (mm)', '1', 166, Y + 142);
      LvlMax := Field(S, 'Correcao maxima (mm)', '0.5', Y + 198);
      LvlDrill := Check(S, 'Corrigir tambem a furacao', Y + 256, False);
      LvlCut := Check(S, 'Corrigir tambem o recorte', Y + 282, False);
      Button(S, '1. Gerar sondagem...', 16, Y + 318, 290, sikGauge, @ProbeExportClick);
      LabelAt(S, '2. No MultiCNC: ligue a garra na fresa e o fio no cobre, rode a sondagem e use ' +
        '"Save Log...".', 16, Y + 360, 290, 56);
      Button(S, '3. Importar log ou CSV...', 16, Y + 420, 290, sikImport, @ProbeImportClick);
      LevelSummary := LabelAt(S, 'Sem mapa de alturas.', 16, Y + 464, 290, 90);
    end;
    5:
    begin
      State := TSuiteBadge.Create(Self);
      State.Parent := S;
      State.SetBounds(16, Y, 260, 32);
      State.Caption := 'Aguardando a placa';
      State.DotColor := clSuiteWarning;
      Title(S, 'MAQUINA', Y + 44);
      MSafe := HalfField(S, 'Z seguro (mm)', '5', 16, Y + 68);
      MTravel := HalfField(S, 'Z entre cortes (mm)', '2', 166, Y + 68);
      MSpin := HalfField(S, 'Espera spindle (s)', '2', 16, Y + 124);
      MRapid := HalfField(S, 'Desloc. (mm/min)', '1500', 166, Y + 124);
      Title(S, 'PROGRAMAS', Y + 184);
      Summary := LabelAt(S, 'Atualize as trajetorias para ver os programas.', 16, Y + 208, 290, 150);
      LogMemo := TMemo.Create(Self);
      LogMemo.Parent := S;
      LogMemo.SetBounds(16, Y + 364, 290, 150);
      LogMemo.ReadOnly := True;
      LogMemo.ScrollBars := ssAutoVertical;
      LabelAt(S, 'Zere X/Y no canto inferior esquerdo da placa e Z na superficie do cobre. ' +
        'Troque a ferramenta entre os programas sem mexer no zero X/Y.', 16, Y + 522, 290, 78);
      Button(S, 'Validar agora', 16, Y + 606, 290, sikTests, @ValidateClick);
      Button(S, 'Gerar G-code...', 16, Y + 648, 290, sikSave, @ExportClick);
    end;
  end;
end;

constructor TRouterPCBForm.Create(AOwner: TComponent);
var Header: TSuiteHeader; Sidebar, Work, Bar, Footer: TPanel; Page: TTabSheet; S: TScrollBox;
  I: Integer;

  function ViewCheck(const AText: string; X, W: Integer): TCheckBox;
  begin
    Result := TCheckBox.Create(Self);
    Result.Parent := Bar;
    Result.SetBounds(X, 52, W, 24);
    Result.Caption := AText;
    Result.Checked := True;
    Result.OnChange := @ViewsChanged;
  end;

begin
  inherited CreateNew(AOwner, 1);
  Caption := 'RouterPCB • MultiSuite';
  Width := 1240; Height := 850;
  Constraints.MinWidth := 1040; Constraints.MinHeight := 680;
  Position := poScreenCenter;
  Font.Name := SUITE_FONT; Font.Size := 10;
  Color := clSuiteSurface;
  P := TRouterPCBProject.Create;
  HM := TRPHeightMap.Create;
  FUpdating := True;
  Header := TSuiteHeader.Create(Self);
  Header.Parent := Self; Header.Align := alTop; Header.Height := 72;
  Header.Setup('RouterPCB', 'Fresagem de placas na CNC Router  /  MultiSuite', sikRouterPCB);
  { rodape }
  Footer := TPanel.Create(Self);
  Footer.Parent := Self; Footer.Align := alBottom; Footer.Height := 66;
  Footer.BevelOuter := bvNone; Footer.Color := clSuiteCard;
  FooterPanel := Footer;
  Status := LabelAt(Footer, 'Abra a pasta Gerber + Excellon exportada pelo MakePCB.', 18, 12, 380, 44);
  ValidateButton := Button(Footer, 'Validar', 0, 15, 130, sikTests, @ValidateClick);
  ExportButton := Button(Footer, 'Gerar G-code', 0, 15, 160, sikExport, @ExportClick);
  ExportButton.SetLook(sbsSolid, clSuitePrimary, sikExport);
  SendButton := Button(Footer, 'Abrir no MultiCNC', 0, 15, 222, sikSend, @SendClick);
  SendButton.Enabled := False;
  { barra lateral }
  Sidebar := TPanel.Create(Self);
  Sidebar.Parent := Self; Sidebar.Align := alLeft; Sidebar.Width := 214;
  Sidebar.BevelOuter := bvNone; Sidebar.Color := clSuiteCard;
  for I := 0 to RP_STEPS - 1 do
  begin
    Nav[I] := Button(Sidebar, STEP_NAMES[I], 12, 16 + I * 44, 190, STEP_ICONS[I], @NavClick);
    Nav[I].Tag := I;
  end;
  Button(Sidebar, 'Abrir pasta...', 12, 16 + RP_STEPS * 44 + 8, 190, sikFolder, @OpenFolderClick);
  Button(Sidebar, 'Novo trabalho', 12, 16 + RP_STEPS * 44 + 50, 190, sikNew, @NewClick);
  LabelAt(Sidebar, 'CAMADAS E FUROS', 16, 16 + RP_STEPS * 44 + 100, 180, 20).WordWrap := False;
  LayerList := TListBox.Create(Self);
  LayerList.Parent := Sidebar;
  LayerList.SetBounds(12, 16 + RP_STEPS * 44 + 124, 190, 160);
  LayerList.OnClick := @LayerClick;
  Info := LabelAt(Sidebar, 'Nenhuma placa importada', 16, Sidebar.Height - 132, 184, 100);
  Info.Align := alBottom; Info.BorderSpacing.Around := 12;
  { paginas }
  Pages := TPageControl.Create(Self);
  Pages.Parent := Self; Pages.Align := alRight; Pages.Width := 336; Pages.ShowTabs := False;
  for I := 0 to RP_STEPS - 1 do
  begin
    Page := TTabSheet.Create(Self);
    Page.PageControl := Pages;
    Page.Caption := STEP_NAMES[I];
    S := TScrollBox.Create(Self);
    S.Parent := Page; S.Align := alClient; S.BorderStyle := bsNone;
    S.Color := clSuiteCard; S.HorzScrollBar.Visible := False;
    BuildPage(I, S);
  end;
  { area de trabalho }
  Work := TPanel.Create(Self);
  Work.Parent := Self; Work.Align := alClient; Work.BevelOuter := bvNone; Work.Color := clSuiteSurface;
  Bar := TPanel.Create(Self);
  Bar.Parent := Work; Bar.Align := alTop; Bar.Height := 84; Bar.BevelOuter := bvNone;
  Button(Bar, 'Placa', 12, 12, 100, sikFit, @FitClick);
  Button(Bar, '', 120, 12, 42, sikZoomIn, @ZoomInClick).Hint := 'Ampliar';
  Button(Bar, '', 168, 12, 42, sikZoomOut, @ZoomOutClick).Hint := 'Reduzir';
  LabelAt(Bar, 'Roda do mouse: zoom   Arrastar: mover   Duplo clique: ajustar', 222, 20, 420, 20).WordWrap := False;
  VCopper := ViewCheck('Cobre', 12, 80);
  VIso := ViewCheck('Isolacao', 96, 100);
  VDrill := ViewCheck('Furos', 200, 80);
  VCut := ViewCheck('Recorte', 284, 90);
  VLevel := ViewCheck('Sondagem', 378, 110);
  View := TRPPreview.Create(Self);
  View.Parent := Work; View.Align := alClient;
  View.Project := P; View.HeightMap := HM;
  Pages.ActivePageIndex := 0;
  FocusPage(0);
  LoadSettings;
  FUpdating := False;
  OnResize := @ResizeUI;
  OnShow := @ShowUI;
end;

destructor TRouterPCBForm.Destroy;
begin
  if View <> nil then
  begin
    View.Project := nil;
    View.HeightMap := nil;
  end;
  HM.Free;
  P.Free;
  inherited Destroy;
end;

procedure TRouterPCBForm.ResizeUI(Sender: TObject);
begin
  if FooterPanel = nil then Exit;
  SendButton.Left := FooterPanel.ClientWidth - SendButton.Width - 18;
  ExportButton.Left := SendButton.Left - ExportButton.Width - 10;
  ValidateButton.Left := ExportButton.Left - ValidateButton.Width - 10;
  Status.Width := Max(120, ValidateButton.Left - 30);
  LayerList.Height := Max(60, LayerList.Parent.ClientHeight - LayerList.Top - 130);
end;

procedure TRouterPCBForm.ShowUI(Sender: TObject);
begin
  ResizeUI(Sender);
  View.FitBoard;
end;

procedure TRouterPCBForm.FocusPage(N: Integer);
var I: Integer;
begin
  Pages.ActivePageIndex := N;
  for I := 0 to RP_STEPS - 1 do
    if I = N then Nav[I].SetLook(sbsSolid, clSuitePrimary)
    else Nav[I].SetLook(sbsSoft, clSuitePrimary);
end;

procedure TRouterPCBForm.NavClick(Sender: TObject);
begin
  FocusPage(TSuiteButton(Sender).Tag);
end;

procedure TRouterPCBForm.SetState(const ACaption: string; AColor: TColor);
begin
  State.Caption := ACaption;
  State.DotColor := AColor;
end;

procedure TRouterPCBForm.ShowError(E: Exception);
begin
  Status.Caption := E.Message;
  LogMemo.Lines.Add(E.Message);
  SetState('Verifique o trabalho', clSuiteDanger);
end;

{ ---------------- parametros ---------------- }

function TRouterPCBForm.Num(E: TEdit; const What: string): Double;
begin
  if not TryParseFloat(Trim(E.Text), Result) or not RPFinite(Result) then
    raise Exception.Create(What + ': informe um numero');
end;

function TRouterPCBForm.Int(E: TEdit; const What: string): Integer;
begin
  if not TryStrToInt(Trim(E.Text), Result) then
    raise Exception.Create(What + ': informe um numero inteiro');
end;

procedure TRouterPCBForm.LoadSettings;
var Old: Boolean;
begin
  Old := FUpdating;
  FUpdating := True;
  try
    SideBox.ItemIndex := Ord(P.Side);
    if P.Resolution > 0 then ResEdit.Text := FS(P.Resolution) else ResEdit.Text := '0';
    with P.Isolation do
    begin
      IsoOn.Checked := Enabled; IsoKind.ItemIndex := Ord(Kind); IsoDir.ItemIndex := Ord(Direction);
      IsoAngle.Text := FS(Angle); IsoTip.Text := FS(TipWidth); IsoDia.Text := FS(Diameter);
      IsoDepth.Text := FS(Depth); IsoPasses.Text := IntToStr(Passes);
      IsoOverlap.Text := FS(Overlap * 100); IsoFeed.Text := FS(Feed); IsoPlunge.Text := FS(PlungeFeed);
      IsoRPM.Text := FS(RPM);
    end;
    with P.Drilling do
    begin
      DrlOn.Checked := Enabled; DrlBits.Text := RPBitsToText(Bits); DrlTol.Text := FS(Tolerance);
      DrlDepth.Text := FS(Depth); DrlPeck.Text := FS(Peck); DrlPlunge.Text := FS(PlungeFeed);
      DrlSlot.Text := FS(SlotFeed); DrlRPM.Text := FS(RPM); DrlPTH.Checked := IncludePlated;
      DrlNPTH.Checked := IncludeNonPlated; DrlMill.Checked := MillLarge;
    end;
    DrlPerTool.Checked := P.Machine.OneFilePerTool;
    DrlPause.Checked := P.Machine.ToolChange = rtcPause;
    with P.Cutout do
    begin
      CutOn.Checked := Enabled; CutDia.Text := FS(ToolDiameter); CutThick.Text := FS(Thickness);
      CutExtra.Text := FS(ExtraDepth); CutStep.Text := FS(StepDown); CutFeed.Text := FS(Feed);
      CutPlunge.Text := FS(PlungeFeed); CutRPM.Text := FS(RPM); CutTabs.Text := IntToStr(Tabs);
      CutTabW.Text := FS(TabWidth); CutTabH.Text := FS(TabHeight); CutDir.ItemIndex := Ord(Direction);
    end;
    with P.Level do
    begin
      LvlOn.Checked := Enabled; LvlCols.Text := IntToStr(Cols); LvlRows.Text := IntToStr(Rows);
      LvlMargin.Text := FS(Margin); LvlDepth.Text := FS(ProbeDepth); LvlFeed.Text := FS(ProbeFeed);
      LvlSeg.Text := FS(MaxSegment); LvlMax.Text := FS(MaxCorrection);
      LvlDrill.Checked := ApplyDrill; LvlCut.Checked := ApplyCutout;
    end;
    MSafe.Text := FS(P.Machine.SafeZ); MTravel.Text := FS(P.Machine.TravelZ);
    MSpin.Text := FS(P.Machine.SpinUpSeconds); MRapid.Text := FS(P.Machine.RapidFeed);
    IsoWidth.Caption := Format('Largura do corte: %.3f mm', [P.IsolationWidth], InvariantFS);
  finally
    FUpdating := Old;
  end;
end;

procedure TRouterPCBForm.ReadSettings;
var I: TRPIsolationOptions; D: TRPDrillOptions; C: TRPCutoutOptions; L: TRPLevelOptions;
  M: TRPMachineOptions; Bits: TRPDoubles; R: Double;
begin
  { le tudo antes de mexer no projeto: um campo invalido nao deixa o projeto pela metade }
  R := Num(ResEdit, 'Resolucao');
  if (R < 0) or (R > 0.5) or ((R > 0) and (R < 0.005)) then
    raise Exception.Create('Resolucao: 0 (auto) ou entre 0,005 e 0,5 mm');
  I := P.Isolation;
  I.Enabled := IsoOn.Checked; I.Kind := TRPToolKind(Max(0, IsoKind.ItemIndex));
  I.Direction := TRPCutDir(Max(0, IsoDir.ItemIndex));
  I.Angle := Num(IsoAngle, 'Angulo da fresa'); I.TipWidth := Num(IsoTip, 'Ponta da fresa');
  I.Diameter := Num(IsoDia, 'Diametro da fresa'); I.Depth := Num(IsoDepth, 'Profundidade da isolacao');
  I.Passes := Int(IsoPasses, 'Passadas'); I.Overlap := Num(IsoOverlap, 'Sobreposicao') / 100;
  I.Feed := Num(IsoFeed, 'Avanco da isolacao'); I.PlungeFeed := Num(IsoPlunge, 'Mergulho da isolacao');
  I.RPM := Num(IsoRPM, 'Rotacao da isolacao');
  D := P.Drilling;
  if not RPParseBits(DrlBits.Text, Bits) then raise Exception.Create('Brocas: use numeros separados por ;');
  D.Enabled := DrlOn.Checked; D.Bits := Bits; D.Tolerance := Num(DrlTol, 'Tolerancia das brocas');
  D.Depth := Num(DrlDepth, 'Profundidade da furacao'); D.Peck := Num(DrlPeck, 'Bicada');
  D.PlungeFeed := Num(DrlPlunge, 'Mergulho da furacao'); D.SlotFeed := Num(DrlSlot, 'Avanco nos rasgos');
  D.RPM := Num(DrlRPM, 'Rotacao da furacao'); D.IncludePlated := DrlPTH.Checked;
  D.IncludeNonPlated := DrlNPTH.Checked; D.MillLarge := DrlMill.Checked;
  C := P.Cutout;
  C.Enabled := CutOn.Checked; C.ToolDiameter := Num(CutDia, 'Fresa do recorte');
  C.Thickness := Num(CutThick, 'Espessura'); C.ExtraDepth := Num(CutExtra, 'Passar do fundo');
  C.StepDown := Num(CutStep, 'Passo'); C.Feed := Num(CutFeed, 'Avanco do recorte');
  C.PlungeFeed := Num(CutPlunge, 'Mergulho do recorte'); C.RPM := Num(CutRPM, 'Rotacao do recorte');
  C.Tabs := Int(CutTabs, 'Pontes'); C.TabWidth := Num(CutTabW, 'Largura da ponte');
  C.TabHeight := Num(CutTabH, 'Altura da ponte'); C.Direction := TRPCutDir(Max(0, CutDir.ItemIndex));
  L := P.Level;
  L.Enabled := LvlOn.Checked; L.Cols := Int(LvlCols, 'Colunas'); L.Rows := Int(LvlRows, 'Linhas');
  L.Margin := Num(LvlMargin, 'Margem'); L.ProbeDepth := Num(LvlDepth, 'Limite da sonda');
  L.ProbeFeed := Num(LvlFeed, 'Avanco da sonda'); L.MaxSegment := Num(LvlSeg, 'Segmento maximo');
  L.MaxCorrection := Num(LvlMax, 'Correcao maxima'); L.ApplyDrill := LvlDrill.Checked;
  L.ApplyCutout := LvlCut.Checked;
  M := P.Machine;
  M.SafeZ := Num(MSafe, 'Z seguro'); M.TravelZ := Num(MTravel, 'Z entre cortes');
  M.SpinUpSeconds := Num(MSpin, 'Espera do spindle'); M.RapidFeed := Num(MRapid, 'Deslocamento');
  M.OneFilePerTool := DrlPerTool.Checked;
  if DrlPause.Checked then M.ToolChange := rtcPause else M.ToolChange := rtcNone;
  { aplica }
  P.Resolution := R;
  P.Isolation := I; P.Drilling := D; P.Cutout := C; P.Level := L; P.Machine := M;
  if SideBox.ItemIndex >= 0 then P.Side := TRPSide(SideBox.ItemIndex);
  IsoWidth.Caption := Format('Largura do corte: %.3f mm', [P.IsolationWidth], InvariantFS);
  SyncHeightMap;
end;

procedure TRouterPCBForm.SyncHeightMap;
var R: TLPRect; Key: string;
begin
  { a grade segue a placa e os parametros; muda-los descarta o mapa medido }
  if (P.BoardWidth <= 0) or not P.Level.Enabled then Exit;
  Key := Format('%d|%d|%s|%s|%s|%d', [P.Level.Cols, P.Level.Rows, FS(P.Level.Margin),
    FS(P.BoardWidth), FS(P.BoardHeight), Ord(P.Side)]);
  if (Key = FGridKey) and HM.Ready then Exit;
  R := LPEmptyRect;
  LPRectInclude(R, 0, 0);
  LPRectInclude(R, P.BoardWidth, P.BoardHeight);
  try
    HM.Setup(R, P.Level.Margin, P.Level.Cols, P.Level.Rows);
    FGridKey := Key;
    LevelSummary.Caption := Format('Grade %d x %d (%d pontos). Gere a sondagem, rode no MultiCNC e importe o log.',
      [HM.Cols, HM.Rows, HM.Count]);
  except
    on E: Exception do
    begin
      HM.Clear;
      FGridKey := '';
      LevelSummary.Caption := E.Message;
    end;
  end;
end;

procedure TRouterPCBForm.SettingsChanged(Sender: TObject);
var V: Double;
begin
  if FUpdating then Exit;
  FExportedFile := '';
  SendButton.Enabled := False;
  SetState('Alteracoes pendentes', clSuiteWarning);
  Status.Caption := 'Atualize as trajetorias e valide.';
  { largura da fresa ao vivo }
  if (IsoWidth <> nil) and TryParseFloat(IsoDepth.Text, V) then
    try
      ReadSettings;
    except
      on E: Exception do Status.Caption := E.Message;
    end;
  if (Sender = SideBox) and (P.LayerCount > 0) then
  begin
    try
      P.InvalidateCAM;
      P.RebuildMasks;
    except
      on E: Exception do Status.Caption := E.Message;
    end;
    View.InvalidateCache;
    View.FitBoard;
  end;
end;

procedure TRouterPCBForm.ViewsChanged(Sender: TObject);
begin
  View.ShowCopper := VCopper.Checked;
  View.ShowIsolation := VIso.Checked;
  View.ShowDrills := VDrill.Checked;
  View.ShowCutout := VCut.Checked;
  View.ShowLevel := VLevel.Checked;
  View.Invalidate;
end;

{ ---------------- importacao ---------------- }

procedure TRouterPCBForm.RefreshLayers;
var I: Integer;
begin
  LayerList.Items.BeginUpdate;
  try
    LayerList.Items.Clear;
    for I := 0 to P.LayerCount - 1 do
      LayerList.Items.Add(LayerRoleName(P.Layer(I).Role) + ' | ' + ExtractFileName(P.Layer(I).FileName));
    for I := 0 to P.DrillFiles.Count - 1 do
      LayerList.Items.Add('Furos | ' + ExtractFileName(P.DrillFiles[I]));
  finally
    LayerList.Items.EndUpdate;
  end;
  if P.LayerCount > 0 then
    Info.Caption := Format('%s' + LineEnding + 'Placa %.2f x %.2f mm' + LineEnding + 'Lado %s  •  %d furos',
      [P.Name, P.BoardWidth, P.BoardHeight, RPSideName(P.Side), P.Drills.HoleCount], InvariantFS)
  else Info.Caption := 'Nenhuma placa importada';
end;

procedure TRouterPCBForm.OpenFile(const FN: string);
var N: Integer;
begin
  try
    if DirectoryExists(FN) then
    begin
      N := P.ImportFolder(FN);
      FSourceDir := ExcludeTrailingPathDelimiter(ExpandFileName(FN));
      Status.Caption := Format('Pasta importada: %d arquivos (%d camadas, %d de furos).',
        [N, P.LayerCount, P.DrillFiles.Count]);
    end
    else
    begin
      P.ImportFile(FN);
      if FSourceDir = '' then FSourceDir := ExtractFileDir(ExpandFileName(FN));
      Status.Caption := 'Importado: ' + ExtractFileName(FN);
    end;
    FUpdating := True;
    try
      SideBox.ItemIndex := Ord(P.Side);
    finally
      FUpdating := False;
    end;
    FGridKey := '';
    HM.Clear;
    RefreshLayers;
    LogMemo.Lines.Assign(P.Warnings);
    FExportedFile := '';
    SendButton.Enabled := False;
    if P.HasOutline then
    begin
      try
        ReadSettings;
        P.RebuildMasks;
      except
        on E: Exception do Status.Caption := E.Message;
      end;
      SetState('Placa importada', clSuiteInfo);
    end
    else SetState('Defina o contorno da placa', clSuiteWarning);
    View.InvalidateCache;
    View.FitBoard;
  except
    on E: Exception do ShowError(E);
  end;
end;

procedure TRouterPCBForm.OpenFolderClick(Sender: TObject);
var D: TSelectDirectoryDialog;
begin
  D := TSelectDirectoryDialog.Create(Self);
  try
    D.Title := 'Pasta Gerber + Excellon (MakePCB: <nome>_gerber)';
    if FSourceDir <> '' then D.InitialDir := ExtractFileDir(FSourceDir);
    if D.Execute then OpenFile(D.FileName);
  finally
    D.Free;
  end;
end;

procedure TRouterPCBForm.OpenFilesClick(Sender: TObject);
var D: TOpenDialog; I: Integer;
begin
  D := TOpenDialog.Create(Self);
  try
    D.Options := D.Options + [ofAllowMultiSelect, ofFileMustExist];
    D.Filter := 'Gerber e Excellon|*.gbr;*.ger;*.gtl;*.gbl;*.gts;*.gbs;*.gto;*.gbo;*.gm1;*.gko;*.gml;*.drl;*.xln;*.exc|Todos|*';
    if D.Execute then
      for I := 0 to D.Files.Count - 1 do OpenFile(D.Files[I]);
  finally
    D.Free;
  end;
end;

procedure TRouterPCBForm.NewClick(Sender: TObject);
begin
  P.Clear;
  HM.Clear;
  FGridKey := '';
  FSourceDir := '';
  FExportedFile := '';
  SendButton.Enabled := False;
  RefreshLayers;
  LogMemo.Clear;
  RefreshSummaries;
  View.InvalidateCache;
  View.FitBoard;
  SetState('Aguardando a placa', clSuiteWarning);
  Status.Caption := 'Novo trabalho. Abra a pasta da placa.';
  FocusPage(0);
end;

procedure TRouterPCBForm.LayerClick(Sender: TObject);
begin
  if (LayerList.ItemIndex < 0) or (LayerList.ItemIndex >= P.LayerCount) then Exit;
  FUpdating := True;
  try
    RoleBox.ItemIndex := Ord(P.Layer(LayerList.ItemIndex).Role);
  finally
    FUpdating := False;
  end;
end;

procedure TRouterPCBForm.RoleChanged(Sender: TObject);
var K: Integer;
begin
  if FUpdating then Exit;
  K := LayerList.ItemIndex;
  if (K < 0) or (K >= P.LayerCount) then
  begin
    Status.Caption := 'Selecione uma camada na lista a esquerda.';
    Exit;
  end;
  try
    P.SetLayerRole(K, TLPLayerRole(RoleBox.ItemIndex));
    RefreshLayers;
    LayerList.ItemIndex := K;
    if P.HasOutline then P.RebuildMasks;
    View.InvalidateCache;
    View.FitBoard;
    SettingsChanged(Sender);
  except
    on E: Exception do ShowError(E);
  end;
end;

{ ---------------- geracao e saida ---------------- }

procedure TRouterPCBForm.RefreshSummaries;
var S: string; I: Integer; G: TLPDrillGroup; MinH, MaxH, Secs: Double; Progs: TRPPrograms;
  Errs: TStringList;
begin
  if not P.Generated then
  begin
    DrillSummary.Caption := 'Atualize as trajetorias.';
    Summary.Caption := 'Atualize as trajetorias para ver os programas.';
    Exit;
  end;
  { furacao }
  S := Format('%d furos em %d broca(s)', [P.DrillPlan.HoleCount, P.DrillPlan.GroupCount]);
  for I := 0 to Min(P.DrillPlan.GroupCount, 6) - 1 do
  begin
    G := P.DrillPlan.Group(I);
    S := S + LineEnding + Format('T%d  %.2f mm  x%d', [I + 1, G.Diameter, Length(G.Holes)], InvariantFS);
  end;
  if Length(P.MilledHoles) > 0 then
    S := S + LineEnding + Format('%d furo(s) fresado(s) no recorte', [Length(P.MilledHoles)]);
  DrillSummary.Caption := S;
  { recorte }
  if Length(P.Cutouts) > 0 then
    CutSummary.Caption := Format('%d contorno(s), %d ponte(s), %d passada(s) ate %.2f mm',
      [Length(P.Cutouts), Length(P.Cutouts[High(P.Cutouts)].Tabs),
       Length(RPDepthLevels(P.Cutout.Thickness + P.Cutout.ExtraDepth, P.Cutout.StepDown)),
       P.Cutout.Thickness + P.Cutout.ExtraDepth], InvariantFS)
  else CutSummary.Caption := 'Recorte desligado ou sem contorno.';
  { nivelamento }
  if P.Level.Enabled and HM.Complete then
  begin
    HM.Range(MinH, MaxH);
    LevelSummary.Caption := Format('Mapa medido: %d pontos. Altura de %.3f a %.3f mm (desnivel %.3f mm).',
      [HM.Count, MinH, MaxH, MaxH - MinH], InvariantFS);
  end;
  { programas }
  Errs := TStringList.Create;
  try
    if P.Validate(Errs, True) then
    begin
      Progs := RPBuildPrograms(P, HM);
      try
        S := '';
        for I := 0 to Progs.Count - 1 do
          S := S + Format('%s  ~%d min', [Progs.Item(I).Suffix, Ceil(Progs.Item(I).Seconds / 60)],
            InvariantFS) + LineEnding;
        Secs := Progs.TotalSeconds;
        if Progs.NeedsProbe then S := S + 'Rode a sondagem e importe o log para gerar os demais.'
        else S := S + Format('Total ~%d min', [Ceil(Secs / 60)]);
        Summary.Caption := S;
      finally
        Progs.Free;
      end;
    end
    else Summary.Caption := Errs[0];
  finally
    Errs.Free;
  end;
end;

function TRouterPCBForm.Prepare: Boolean;
var I: Integer;
begin
  Result := False;
  LogMemo.Clear;
  ReadSettings;
  Screen.Cursor := crHourGlass;
  try
    P.Generate;
  finally
    Screen.Cursor := crDefault;
  end;
  View.InvalidateCache;
  for I := 0 to P.Notes.Count - 1 do LogMemo.Lines.Add('Aviso: ' + P.Notes[I]);
  Result := P.Validate(LogMemo.Lines, True);
  if Result and P.Level.Enabled and not HM.Complete then
    LogMemo.Lines.Add('Nivelamento ligado e sem mapa: so a sondagem sera gerada.');
  RefreshSummaries;
end;

procedure TRouterPCBForm.GenerateClick(Sender: TObject);
begin
  try
    if Prepare then
    begin
      SetState('Trajetorias atualizadas', clSuiteInfo);
      Status.Caption := Format('Isolacao %d caminhos, %d furos, %d contorno(s). Confira a previa e valide.',
        [Length(P.IsolationPaths), P.DrillPlan.HoleCount + Length(P.MilledHoles), Length(P.Cutouts)]);
    end
    else
    begin
      SetState('Corrigir antes de exportar', clSuiteDanger);
      if LogMemo.Lines.Count > 0 then Status.Caption := LogMemo.Lines[LogMemo.Lines.Count - 1];
    end;
  except
    on E: Exception do ShowError(E);
  end;
end;

procedure TRouterPCBForm.ValidateClick(Sender: TObject);
begin
  FocusPage(5);
  try
    if Prepare then
    begin
      LogMemo.Lines.Add('Pronto para gerar o G-code.');
      SetState('Trabalho valido', clSuiteSuccess);
      Status.Caption := 'Geometria e parametros validados.';
    end
    else
    begin
      SetState('Corrigir antes de exportar', clSuiteDanger);
      Status.Caption := LogMemo.Lines[LogMemo.Lines.Count - 1];
    end;
  except
    on E: Exception do ShowError(E);
  end;
end;

function TRouterPCBForm.ExportTo(const Folder: string): TStringList;
var Progs: TRPPrograms;
begin
  if not Prepare then raise Exception.Create(Trim(LogMemo.Lines.Text));
  Progs := RPBuildPrograms(P, HM);
  try
    Result := RPSavePrograms(Progs, Folder, P.Name);
    if Progs.NeedsProbe then
      LogMemo.Lines.Add('Gerada so a sondagem: rode no MultiCNC, salve o log e importe na etapa 5.');
  finally
    Progs.Free;
  end;
end;

procedure TRouterPCBForm.ExportClick(Sender: TObject);
var D: TSelectDirectoryDialog; Files: TStringList; Folder: string;
begin
  try
    if not Prepare then
    begin
      FocusPage(5);
      raise Exception.Create(LogMemo.Lines[LogMemo.Lines.Count - 1]);
    end;
    D := TSelectDirectoryDialog.Create(Self);
    try
      D.Title := 'Pasta para os programas da router';
      if FSourceDir <> '' then D.InitialDir := ExtractFileDir(FSourceDir);
      if not D.Execute then Exit;
      Folder := D.FileName;
    finally
      D.Free;
    end;
    Files := ExportTo(Folder);
    try
      FExportedFile := Files[0];
      SendButton.Enabled := True;
      SetState('G-code gerado', clSuiteSuccess);
      Status.Caption := Format('%d programa(s) em %s. Abra o primeiro no MultiCNC.', [Files.Count, Folder]);
      LogMemo.Lines.AddStrings(Files);
    finally
      Files.Free;
    end;
  except
    on E: Exception do ShowError(E);
  end;
end;

procedure TRouterPCBForm.SendClick(Sender: TObject);
var Registry: TSuiteRegistry; Root, Err, Candidate: string; C: TSuiteContext; I: Integer;
begin
  if (FExportedFile = '') or not FileExists(FExportedFile) then Exit;
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
      if not TSuiteLauncher.LaunchArtifact(Registry.Tool(Registry.Find(stiMultiCNC)), Root, C.ProjectRoot,
        FExportedFile, Err) then raise Exception.Create(Err);
      Status.Caption := 'Programa aberto no MultiCNC (CNC Router): ' + ExtractFileName(FExportedFile);
    except
      on E: Exception do ShowError(E);
    end;
  finally
    Registry.Free;
  end;
end;

procedure TRouterPCBForm.ProbeExportClick(Sender: TObject);
var D: TSaveDialog; G: TStringList; Errs: TStringList;
begin
  try
    ReadSettings;
    if not P.Level.Enabled then
    begin
      FUpdating := True;
      try LvlOn.Checked := True; finally FUpdating := False; end;
      ReadSettings;
    end;
    Errs := TStringList.Create;
    try
      if not RPValidateLevel(P.Level, Errs) or not RPValidateMachine(P.Machine, Errs) then
        raise Exception.Create(Errs[0]);
    finally
      Errs.Free;
    end;
    if not HM.Ready then raise Exception.Create('Importe a placa antes de gerar a sondagem');
    D := TSaveDialog.Create(Self);
    try
      D.Filter := 'G-code|*.gcode';
      D.DefaultExt := 'gcode';
      D.FileName := P.Name + '_0_sondagem.gcode';
      D.Options := D.Options + [ofOverwritePrompt];
      if not D.Execute then Exit;
      G := HM.ProbeProgram(P.Level, P.Machine, P.Name + ' - sondagem');
      try
        G.SaveToFile(D.FileName);
      finally
        G.Free;
      end;
      FExportedFile := D.FileName;
      SendButton.Enabled := True;
      Status.Caption := 'Sondagem gerada. Rode no MultiCNC e depois importe o log salvo.';
      View.Invalidate;
    finally
      D.Free;
    end;
  except
    on E: Exception do ShowError(E);
  end;
end;

procedure TRouterPCBForm.ProbeImportClick(Sender: TObject);
var D: TOpenDialog; L, Errs: TStringList; N: Integer;
begin
  try
    ReadSettings;
    if not HM.Ready then raise Exception.Create('Ligue o nivelamento e importe a placa antes');
    D := TOpenDialog.Create(Self);
    L := TStringList.Create;
    Errs := TStringList.Create;
    try
      D.Filter := 'Log do MultiCNC ou CSV|*.txt;*.log;*.csv|Todos|*';
      if not D.Execute then Exit;
      L.LoadFromFile(D.FileName);
      if Pos('[PRB:', L.Text) > 0 then N := HM.LoadProbeLog(L, Errs)
      else N := HM.LoadCSV(L, Errs);
      LogMemo.Lines.AddStrings(Errs);
      if HM.Complete then
      begin
        Status.Caption := Format('Mapa de alturas: %d pontos lidos. Atualize as trajetorias e gere o G-code.', [N]);
        SettingsChanged(Sender);
        RefreshSummaries;
      end
      else
      begin
        if Errs.Count > 0 then Status.Caption := Errs[0]
        else Status.Caption := 'Mapa incompleto.';
        LevelSummary.Caption := Status.Caption;
      end;
      View.Invalidate;
    finally
      Errs.Free;
      L.Free;
      D.Free;
    end;
  except
    on E: Exception do ShowError(E);
  end;
end;

procedure TRouterPCBForm.FitClick(Sender: TObject);
begin
  View.FitBoard;
end;

procedure TRouterPCBForm.ZoomInClick(Sender: TObject);
begin
  View.ZoomIn;
end;

procedure TRouterPCBForm.ZoomOutClick(Sender: TObject);
begin
  View.ZoomOut;
end;

end.
