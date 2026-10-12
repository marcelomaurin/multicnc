unit multislicer_main;

{ Tela principal do MultiSlicer, no padrao visual da suite (igual ao
  MakeRouter, LaserPCB, MakePCB e RouterPCB): cabecalho, etapas na lateral,
  parametros a direita, vista ao centro e rodape com
  Validar / Fatiar / Gerar G-code / Abrir no MultiCNC.

  Etapas: 1 Impressora, 2 Modelo, 3 Material, 4 Qualidade, 5 Suportes,
  6 Previa, 7 Saida. Referencia funcional: UltiMaker Cura.

  O fatiamento e a previa usam o mesmo TModernSlicer. Qualquer alteracao de
  modelo ou configuracao invalida o G-code anterior. O MultiSlicer prepara o
  programa; o MultiCNC conecta e imprime.

  Plano completo em multislicer/docs/PLANO_TAREFAS.md (esta e a Etapa 1:
  posicionamento 3D, perfis salvos, materiais, suportes e previa 3D vem nas
  etapas seguintes). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls, Spin,
  Dialogs, Graphics, LCLType, multislicer_types, multislicer_mesh, multislicer_stl,
  multislicer_3mf, multislicer_profile, multislicer_pipeline, multislicer_view,
  multisuite_controls, multisuite_icons;

const
  MS_STEP_COUNT = 7;
  MS_STEPS: array[0..MS_STEP_COUNT - 1] of string = ('1  Impressora', '2  Modelo',
    '3  Material', '4  Qualidade', '5  Suportes', '6  Previa', '7  Saida');

type
  TPrinterPreset = record
    Name: string;
    BedX, BedY, BedZ, Nozzle, Filament, Retract: Double;
    Flavor: TSlicerFlavor;
  end;

  TPrinterPresets = array of TPrinterPreset;

  TMultiSlicerForm = class(TForm)
  private
    M: TMesh;
    Engine: TModernSlicer;
    Code: TStringList;
    Report: TSliceReport;
    Ready: Boolean;
    FUpdating: Boolean;
    SourceFile: string;
    FExportedFile: string;
    { estrutura }
    Pages: TPageControl;
    Nav: array[0..MS_STEP_COUNT - 1] of TSuiteButton;
    View: TSlicerView;
    FooterPanel, ViewBar: TPanel;
    Status, Coords, ModelInfo, PreviewSummary, OutSummary: TLabel;
    State: TSuiteBadge;
    ValidateButton, SliceBtn, ExportBtn, SendButton: TSuiteButton;
    BedButton, LayersButton: TSuiteButton;
    LayerTrack: TTrackBar;
    LayerLabel: TLabel;
    Log: TMemo;
    { impressora }
    PrinterBox, FlavorChoice: TComboBox;
    BedX, BedY, BedZ, Nozzle, FilamentDia, RetractLen: TFloatSpinEdit;
    { material }
    Hotend, BedTemp, FanLayer: TSpinEdit;
    Density: TFloatSpinEdit;
    { qualidade }
    LayerHeight, Speed: TFloatSpinEdit;
    Walls, TopLayers, BottomLayers, InfillDensity: TSpinEdit;
    PatternChoice: TComboBox;
    Adaptive, ArcFit: TCheckBox;
    { suportes e aderencia }
    SkirtLoops: TSpinEdit;
    SkirtDist: TFloatSpinEdit;
    { previa }
    LayerChoice: TSpinEdit;
    function Button(AParent: TWinControl; const AText: string; X, Y, W: Integer;
      AIcon: TSuiteIconKind; Handler: TNotifyEvent): TSuiteButton;
    function LabelAt(AParent: TWinControl; const AText: string; X, Y, W, H: Integer): TLabel;
    function Section(AParent: TWinControl; const AText: string; Y: Integer): TLabel;
    function FloatField(AParent: TWinControl; const AText, AName: string;
      Value, MinValue, MaxValue, Step: Double; Decimals, Y: Integer): TFloatSpinEdit;
    function IntField(AParent: TWinControl; const AText, AName: string;
      Value, MinValue, MaxValue, Y: Integer): TSpinEdit;
    function Combo(AParent: TWinControl; const AText: string; Y: Integer): TComboBox;
    function Check(AParent: TWinControl; const AText: string; Y: Integer): TCheckBox;
    procedure BuildPrinterPage(S: TScrollBox);
    procedure BuildModelPage(S: TScrollBox);
    procedure BuildMaterialPage(S: TScrollBox);
    procedure BuildQualityPage(S: TScrollBox);
    procedure BuildSupportPage(S: TScrollBox);
    procedure BuildPreviewPage(S: TScrollBox);
    procedure BuildOutputPage(S: TScrollBox);
    procedure NavClick(Sender: TObject);
    procedure OpenClick(Sender: TObject);
    procedure CenterClick(Sender: TObject);
    procedure PrinterChange(Sender: TObject);
    procedure SliceClick(Sender: TObject);
    procedure ValidateClick(Sender: TObject);
    procedure ExportClick(Sender: TObject);
    procedure SendClick(Sender: TObject);
    procedure BedViewClick(Sender: TObject);
    procedure LayersViewClick(Sender: TObject);
    procedure FitClick(Sender: TObject);
    procedure ZoomInClick(Sender: TObject);
    procedure ZoomOutClick(Sender: TObject);
    procedure SettingsChanged(Sender: TObject);
    procedure LayerChanged(Sender: TObject);
    procedure TrackChanged(Sender: TObject);
    procedure ResizeUI(Sender: TObject);
    procedure ApplyPreset(const P: TPrinterPreset);
    procedure SetState(const ACaption: string; AColor: TColor);
    procedure ShowError(E: Exception);
    procedure ShowViewMode(AMode: TSlicerViewMode);
    procedure RefreshModelInfo;
    function Settings: TSliceSettings;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { uso pela linha de comando e pelos testes }
    procedure OpenFile(const FN: string);
    procedure CenterModel;
    procedure ShowStep(N: Integer);
    function ValidateJob: Boolean;
    procedure GenerateProgram;
    procedure ExportProgram(const FN: string);
    property SliceReport: TSliceReport read Report;
    property ProgramReady: Boolean read Ready;
    property Mesh: TMesh read M;
    property ExportedFile: string read FExportedFile;
  end;

function PrinterPresets: TPrinterPresets;
procedure MeshBounds(AMesh: TMesh; out AMin, AMax: TVec3);

implementation

uses multisuite_numfmt, multisuite_registry, multisuite_launcher, multisuite_types,
  multisuite_context;

const
  STEP_ICONS: array[0..MS_STEP_COUNT - 1] of TSuiteIconKind = (sikGear, sikMove,
    sikThermo, sikLayers, sikFlag, sikEye, sikExport);

function Preset(const AName: string; X, Y, Z, ANozzle, AFil, ARetract: Double;
  AFlavor: TSlicerFlavor): TPrinterPreset;
begin
  Result.Name := AName;
  Result.BedX := X; Result.BedY := Y; Result.BedZ := Z;
  Result.Nozzle := ANozzle; Result.Filament := AFil; Result.Retract := ARetract;
  Result.Flavor := AFlavor;
end;

function PrinterPresets: TPrinterPresets;
begin
  { Perfis fixos ate a Etapa 2 (perfis em JSON). Ender-3 original: extrusora
    Bowden, por isso retracao bem maior que a de extrusora direta. }
  SetLength(Result, 2);
  Result[0] := Preset('Creality Ender-3', 220, 220, 250, 0.4, 1.75, 5.0, sfMarlin);
  Result[1] := Preset('Generic Marlin', 220, 220, 250, 0.4, 1.75, 0.8, sfMarlin);
end;

procedure MeshBounds(AMesh: TMesh; out AMin, AMax: TVec3);
var I: Integer; T: TTriangle;
  procedure Take(const V: TVec3);
  begin
    AMin.X := Min(AMin.X, V.X); AMin.Y := Min(AMin.Y, V.Y); AMin.Z := Min(AMin.Z, V.Z);
    AMax.X := Max(AMax.X, V.X); AMax.Y := Max(AMax.Y, V.Y); AMax.Z := Max(AMax.Z, V.Z);
  end;
begin
  AMin.X := 0; AMin.Y := 0; AMin.Z := 0; AMax := AMin;
  if (AMesh = nil) or (AMesh.Count = 0) then Exit;
  AMin.X := MaxDouble; AMin.Y := MaxDouble; AMin.Z := MaxDouble;
  AMax.X := -MaxDouble; AMax.Y := -MaxDouble; AMax.Z := -MaxDouble;
  for I := 0 to AMesh.Count - 1 do
  begin
    T := AMesh.Triangle(I);
    Take(T.A); Take(T.B); Take(T.C);
  end;
end;

{ ---------------- construcao ---------------- }

function TMultiSlicerForm.Button(AParent: TWinControl; const AText: string; X, Y, W: Integer;
  AIcon: TSuiteIconKind; Handler: TNotifyEvent): TSuiteButton;
begin
  Result := TSuiteButton.Create(Self);
  Result.Parent := AParent;
  Result.SetBounds(X, Y, W, 34);
  Result.Caption := AText;
  Result.SetLook(sbsSoft, clSuitePrimary, AIcon);
  Result.OnClick := Handler;
end;

function TMultiSlicerForm.LabelAt(AParent: TWinControl; const AText: string; X, Y, W, H: Integer): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := AParent;
  Result.AutoSize := False;
  Result.SetBounds(X, Y, W, H);
  Result.WordWrap := True;
  Result.Caption := AText;
  Result.Font.Color := clSuiteMuted;
end;

function TMultiSlicerForm.Section(AParent: TWinControl; const AText: string; Y: Integer): TLabel;
begin
  Result := LabelAt(AParent, AText, 16, Y, 290, 18);
  Result.Font.Style := [fsBold];
end;

function TMultiSlicerForm.FloatField(AParent: TWinControl; const AText, AName: string;
  Value, MinValue, MaxValue, Step: Double; Decimals, Y: Integer): TFloatSpinEdit;
begin
  LabelAt(AParent, AText, 16, Y, 290, 18);
  Result := TFloatSpinEdit.Create(Self);
  Result.Parent := AParent;
  Result.Name := AName;
  Result.SetBounds(16, Y + 20, 290, 28);
  Result.DecimalPlaces := Decimals;
  Result.MinValue := MinValue;
  Result.MaxValue := MaxValue;
  Result.Increment := Step;
  Result.Value := Value;
  Result.OnChange := @SettingsChanged;
end;

function TMultiSlicerForm.IntField(AParent: TWinControl; const AText, AName: string;
  Value, MinValue, MaxValue, Y: Integer): TSpinEdit;
begin
  LabelAt(AParent, AText, 16, Y, 290, 18);
  Result := TSpinEdit.Create(Self);
  Result.Parent := AParent;
  Result.Name := AName;
  Result.SetBounds(16, Y + 20, 290, 28);
  Result.MinValue := MinValue;
  Result.MaxValue := MaxValue;
  Result.Value := Value;
  Result.OnChange := @SettingsChanged;
end;

function TMultiSlicerForm.Combo(AParent: TWinControl; const AText: string; Y: Integer): TComboBox;
begin
  LabelAt(AParent, AText, 16, Y, 290, 18);
  Result := TComboBox.Create(Self);
  Result.Parent := AParent;
  Result.SetBounds(16, Y + 20, 290, 30);
  Result.Style := csDropDownList;
end;

function TMultiSlicerForm.Check(AParent: TWinControl; const AText: string; Y: Integer): TCheckBox;
begin
  Result := TCheckBox.Create(Self);
  Result.Parent := AParent;
  Result.SetBounds(16, Y, 290, 24);
  Result.Caption := AText;
  Result.OnChange := @SettingsChanged;
end;

constructor TMultiSlicerForm.Create(AOwner: TComponent);
var
  Header: TSuiteHeader;
  Sidebar, Work: TPanel;
  Page: TTabSheet;
  Scroll: TScrollBox;
  I: Integer;
begin
  inherited CreateNew(AOwner, 1);
  Caption := 'MultiSlicer • MultiSuite';
  Width := 1280; Height := 860;
  Constraints.MinWidth := 1060; Constraints.MinHeight := 680;
  Position := poScreenCenter;
  Font.Name := SUITE_FONT; Font.Size := 10;
  Color := clSuiteSurface;
  M := TMesh.Create;
  Engine := TModernSlicer.Create;
  Code := TStringList.Create;
  FUpdating := True;

  Header := TSuiteHeader.Create(Self);
  Header.Parent := Self; Header.Align := alTop; Header.Height := 72;
  Header.Setup('MultiSlicer', 'Preparacao para impressao 3D  /  MultiSuite', sikSlicer);

  FooterPanel := TPanel.Create(Self);
  FooterPanel.Parent := Self; FooterPanel.Align := alBottom; FooterPanel.Height := 66;
  FooterPanel.BevelOuter := bvNone; FooterPanel.Color := clSuiteCard;
  Status := LabelAt(FooterPanel, 'Abra um modelo STL ou 3MF.', 18, 8, 420, 26);
  Coords := LabelAt(FooterPanel, '', 18, 36, 420, 22);
  ValidateButton := Button(FooterPanel, 'Validar', 0, 15, 116, sikTests, @ValidateClick);
  SliceBtn := Button(FooterPanel, 'Fatiar', 0, 15, 116, sikLayers, @SliceClick);
  SliceBtn.Name := 'Slice';
  ExportBtn := Button(FooterPanel, 'Gerar G-code', 0, 15, 150, sikExport, @ExportClick);
  ExportBtn.Name := 'Export';
  ExportBtn.SetLook(sbsSolid, clSuitePrimary, sikExport);
  SendButton := Button(FooterPanel, 'Abrir no MultiCNC', 0, 15, 200, sikSend, @SendClick);
  SliceBtn.Enabled := False; ExportBtn.Enabled := False; SendButton.Enabled := False;

  Sidebar := TPanel.Create(Self);
  Sidebar.Parent := Self; Sidebar.Align := alLeft; Sidebar.Width := 214;
  Sidebar.BevelOuter := bvNone; Sidebar.Color := clSuiteCard;
  for I := 0 to MS_STEP_COUNT - 1 do
  begin
    Nav[I] := Button(Sidebar, MS_STEPS[I], 12, 16 + I * 44, 190, STEP_ICONS[I], @NavClick);
    Nav[I].Tag := I;
  end;
  Button(Sidebar, 'Abrir', 12, 16 + MS_STEP_COUNT * 44 + 8, 92, sikFolder, @OpenClick).Hint :=
    'Abrir modelo STL ou 3MF';
  Button(Sidebar, 'Centro', 110, 16 + MS_STEP_COUNT * 44 + 8, 92, sikFit, @CenterClick).Hint :=
    'Centralizar a peca na mesa e assentar em Z = 0';
  ModelInfo := LabelAt(Sidebar, '', 16, 16 + MS_STEP_COUNT * 44 + 56, 184, 150);
  ModelInfo.Align := alBottom;
  ModelInfo.BorderSpacing.Around := 12;

  Pages := TPageControl.Create(Self);
  Pages.Parent := Self; Pages.Align := alRight; Pages.Width := 336;
  Pages.ShowTabs := False;
  for I := 0 to MS_STEP_COUNT - 1 do
  begin
    Page := TTabSheet.Create(Self);
    Page.PageControl := Pages;
    Page.Caption := MS_STEPS[I];
    Scroll := TScrollBox.Create(Self);
    Scroll.Parent := Page; Scroll.Align := alClient;
    Scroll.BorderStyle := bsNone; Scroll.Color := clSuiteCard;
    Scroll.HorzScrollBar.Visible := False;
    LabelAt(Scroll, MS_STEPS[I], 16, 16, 260, 30).Font.Style := [fsBold];
    case I of
      0: BuildPrinterPage(Scroll);
      1: BuildModelPage(Scroll);
      2: BuildMaterialPage(Scroll);
      3: BuildQualityPage(Scroll);
      4: BuildSupportPage(Scroll);
      5: BuildPreviewPage(Scroll);
      6: BuildOutputPage(Scroll);
    end;
  end;

  Work := TPanel.Create(Self);
  Work.Parent := Self; Work.Align := alClient;
  Work.BevelOuter := bvNone; Work.Color := clSuiteSurface;
  ViewBar := TPanel.Create(Self);
  ViewBar.Parent := Work; ViewBar.Align := alTop; ViewBar.Height := 52;
  ViewBar.BevelOuter := bvNone; ViewBar.Color := clSuiteSurface;
  BedButton := Button(ViewBar, 'Mesa', 12, 9, 100, sikFrame, @BedViewClick);
  LayersButton := Button(ViewBar, 'Camadas', 118, 9, 118, sikLayers, @LayersViewClick);
  Button(ViewBar, 'Ajustar', 248, 9, 96, sikFit, @FitClick).Hint := 'Mostrar a mesa inteira';
  Button(ViewBar, '', 350, 9, 42, sikZoomIn, @ZoomInClick).Hint := 'Ampliar (roda do mouse)';
  Button(ViewBar, '', 398, 9, 42, sikZoomOut, @ZoomOutClick).Hint := 'Reduzir (roda do mouse)';
  LayerLabel := LabelAt(ViewBar, 'Camada', 456, 17, 64, 20);
  LayerTrack := TTrackBar.Create(Self);
  LayerTrack.Parent := ViewBar;
  LayerTrack.SetBounds(522, 10, 300, 32);
  LayerTrack.Min := 1; LayerTrack.Max := 1; LayerTrack.Position := 1;
  LayerTrack.TickStyle := tsNone;
  LayerTrack.OnChange := @TrackChanged;
  View := TSlicerView.Create(Self);
  View.Parent := Work; View.Align := alClient;
  View.SetMesh(M);

  FUpdating := False;
  OnResize := @ResizeUI;
  PrinterBox.ItemIndex := 0;
  PrinterChange(nil);
  ShowViewMode(svMesa);
  ShowStep(1);
  SetState('Aguardando modelo', clSuiteWarning);
  RefreshModelInfo;
end;

destructor TMultiSlicerForm.Destroy;
begin
  if View <> nil then View.SetMesh(nil);
  Code.Free;
  Engine.Free;
  M.Free;
  inherited Destroy;
end;

procedure TMultiSlicerForm.BuildPrinterPage(S: TScrollBox);
var I: Integer; P: TPrinterPresets;
begin
  LabelAt(S, 'Escolha a impressora onde a peca sera impressa. O volume define a mesa da vista e a validacao.',
    16, 48, 290, 40);
  PrinterBox := Combo(S, 'Impressora', 92);
  P := PrinterPresets;
  for I := 0 to High(P) do PrinterBox.Items.Add(P[I].Name);
  PrinterBox.Items.Add('Personalizada');
  PrinterBox.OnChange := @PrinterChange;
  FlavorChoice := Combo(S, 'Firmware', 150);
  FlavorChoice.Items.Add('Marlin'); FlavorChoice.Items.Add('Klipper');
  FlavorChoice.ItemIndex := 0;
  FlavorChoice.OnChange := @SettingsChanged;
  BedX := FloatField(S, 'Mesa X (mm)', 'BedX', 220, 10, 2000, 1, 1, 208);
  BedY := FloatField(S, 'Mesa Y (mm)', 'BedY', 220, 10, 2000, 1, 1, 264);
  BedZ := FloatField(S, 'Altura maxima Z (mm)', 'BedZ', 250, 10, 2000, 1, 1, 320);
  Nozzle := FloatField(S, 'Diametro do bico (mm)', 'Nozzle', 0.4, 0.1, 2, 0.05, 2, 376);
  FilamentDia := FloatField(S, 'Diametro do filamento (mm)', 'FilamentDiameter', 1.75, 1, 3.5, 0.05, 2, 432);
  RetractLen := FloatField(S, 'Retracao (mm)', 'RetractLength', 5, 0, 15, 0.1, 1, 488);
  LabelAt(S, 'Ender-3 original usa extrusora Bowden (retracao maior). Perfis salvos e G-code inicial/final editavel entram na proxima etapa.',
    16, 550, 290, 70);
end;

procedure TMultiSlicerForm.BuildModelPage(S: TScrollBox);
begin
  Button(S, 'Abrir modelo...', 16, 52, 290, sikFolder, @OpenClick).SetLook(sbsSolid, clSuitePrimary, sikFolder);
  Button(S, 'Centralizar na mesa', 16, 94, 290, sikFit, @CenterClick);
  LabelAt(S, 'Ao abrir, a peca e centralizada na mesa e assentada em Z = 0, como no Cura. Parte vermelha na vista = fora da mesa. Roda do mouse amplia; arraste para deslocar.',
    16, 142, 290, 80);
  Section(S, 'POSICIONAMENTO', 234);
  LabelAt(S, 'Mover, girar, escalar, espelhar, deitar face na mesa, varias pecas e a vista 3D entram nas etapas 3 e 4 do plano.',
    16, 256, 290, 60);
end;

procedure TMultiSlicerForm.BuildMaterialPage(S: TScrollBox);
begin
  LabelAt(S, 'Temperaturas e ventoinha do filamento. A biblioteca de materiais (PLA, PETG, ABS, ASA, TPU) entra na proxima etapa.',
    16, 48, 290, 56);
  Hotend := IntField(S, 'Temperatura do bico (C)', 'HotendTemperature', 200, 0, 400, 108);
  BedTemp := IntField(S, 'Temperatura da mesa (C)', 'BedTemperature', 60, 0, 150, 164);
  FanLayer := IntField(S, 'Ventoinha a partir da camada', 'FanFromLayer', 2, 1, 50, 220);
  Density := FloatField(S, 'Densidade do filamento (g/cm3)', 'FilamentDensity', 1.24, 0.5, 3, 0.01, 2, 276);
  LabelAt(S, 'PLA: bico 190 a 220 C, mesa 50 a 60 C, densidade 1,24. Confira os valores do fabricante do filamento.',
    16, 338, 290, 56);
end;

procedure TMultiSlicerForm.BuildQualityPage(S: TScrollBox);
begin
  LayerHeight := FloatField(S, 'Altura de camada (mm)', 'LayerHeight', 0.2, 0.04, 1, 0.02, 2, 52);
  Walls := IntField(S, 'Numero de paredes', 'Walls', 2, 1, 20, 108);
  TopLayers := IntField(S, 'Camadas de topo', 'TopLayers', 4, 0, 50, 164);
  BottomLayers := IntField(S, 'Camadas de fundo', 'BottomLayers', 3, 0, 50, 220);
  InfillDensity := IntField(S, 'Preenchimento (%)', 'InfillDensity', 20, 0, 100, 276);
  PatternChoice := Combo(S, 'Padrao de preenchimento', 332);
  PatternChoice.Items.Add('Gyroid'); PatternChoice.Items.Add('Retilineo');
  PatternChoice.ItemIndex := 0;
  PatternChoice.OnChange := @SettingsChanged;
  Speed := FloatField(S, 'Velocidade de impressao (mm/s)', 'PrintSpeed', 50, 5, 500, 5, 0, 390);
  Adaptive := Check(S, 'Altura de camada adaptativa', 452);
  ArcFit := Check(S, 'Arcos G2/G3 nos perimetros', 480);
  ArcFit.Checked := True;
  LabelAt(S, 'Altura de camada ate 80% do bico. Parede externa sai a 60% da velocidade.', 16, 514, 290, 40);
end;

procedure TMultiSlicerForm.BuildSupportPage(S: TScrollBox);
begin
  Section(S, 'SUPORTES (HASTES DE APOIO)', 52);
  LabelAt(S, 'Deteccao de saliencias, hastes manuais por clique e bloqueadores entram na etapa 6 do plano. Ate la a peca e fatiada sem suporte.',
    16, 74, 290, 60);
  Section(S, 'ADERENCIA', 146);
  SkirtLoops := IntField(S, 'Voltas de saia (0 = sem)', 'SkirtLoops', 1, 0, 20, 168);
  SkirtDist := FloatField(S, 'Distancia da saia (mm)', 'SkirtDistance', 3, 0.5, 50, 0.5, 1, 224);
  LabelAt(S, 'Aba (brim) e jangada (raft) entram na etapa 6.', 16, 286, 290, 40);
end;

procedure TMultiSlicerForm.BuildPreviewPage(S: TScrollBox);
begin
  Button(S, 'Fatiar e visualizar', 16, 52, 290, sikLayers, @SliceClick).SetLook(sbsSolid, clSuitePrimary, sikLayers);
  LayerChoice := IntField(S, 'Camada', 'LayerChoice', 1, 1, 1, 100);
  LayerChoice.OnChange := @LayerChanged;
  PreviewSummary := LabelAt(S, 'Fatie para ver tempo, filamento e camadas.', 16, 164, 290, 160);
end;

procedure TMultiSlicerForm.BuildOutputPage(S: TScrollBox);
begin
  State := TSuiteBadge.Create(Self);
  State.Parent := S; State.SetBounds(16, 56, 260, 32);
  OutSummary := LabelAt(S, 'Fatie e gere o G-code para salvar e enviar ao MultiCNC.', 16, 100, 290, 80);
  Log := TMemo.Create(Self);
  Log.Name := 'SliceOutput';
  Log.Parent := S; Log.SetBounds(16, 186, 290, 260);
  Log.ReadOnly := True; Log.WordWrap := False; Log.ScrollBars := ssAutoBoth;
  Log.Clear;
  Button(S, 'Validar agora', 16, 458, 290, sikTests, @ValidateClick);
  Button(S, 'Gerar G-code...', 16, 500, 290, sikExport, @ExportClick).SetLook(sbsSolid, clSuitePrimary, sikExport);
  Button(S, 'Abrir no MultiCNC', 16, 542, 290, sikSend, @SendClick);
  LabelAt(S, 'O G-code fica salvo no arquivo escolhido. Abrir no MultiCNC carrega o programa para imprimir; a conexao com a impressora e feita la.',
    16, 590, 290, 80);
end;

{ ---------------- estado e utilitarios ---------------- }

procedure TMultiSlicerForm.SetState(const ACaption: string; AColor: TColor);
begin
  if State = nil then Exit;
  State.Caption := ACaption;
  State.DotColor := AColor;
end;

procedure TMultiSlicerForm.ShowError(E: Exception);
begin
  Status.Caption := E.Message;
  if Log <> nil then Log.Lines.Add('Erro: ' + E.Message);
  SetState('Verifique o trabalho', clSuiteDanger);
end;

procedure TMultiSlicerForm.ResizeUI(Sender: TObject);
begin
  if FooterPanel = nil then Exit;
  SendButton.Left := FooterPanel.ClientWidth - SendButton.Width - 18;
  ExportBtn.Left := SendButton.Left - ExportBtn.Width - 10;
  SliceBtn.Left := ExportBtn.Left - SliceBtn.Width - 10;
  ValidateButton.Left := SliceBtn.Left - ValidateButton.Width - 10;
  Status.Width := Max(120, ValidateButton.Left - 30);
  Coords.Width := Status.Width;
  if ViewBar <> nil then
    LayerTrack.Width := Max(120, ViewBar.ClientWidth - LayerTrack.Left - 16);
end;

procedure TMultiSlicerForm.ShowStep(N: Integer);
var I: Integer;
begin
  N := EnsureRange(N, 0, MS_STEP_COUNT - 1);
  Pages.ActivePageIndex := N;
  for I := 0 to MS_STEP_COUNT - 1 do
    if I = N then Nav[I].SetLook(sbsSolid, clSuitePrimary)
    else Nav[I].SetLook(sbsSoft, clSuitePrimary);
  if N = 5 then ShowViewMode(svCamadas)
  else if N <= 2 then ShowViewMode(svMesa);
end;

procedure TMultiSlicerForm.NavClick(Sender: TObject);
begin
  ShowStep(TSuiteButton(Sender).Tag);
end;

procedure TMultiSlicerForm.ShowViewMode(AMode: TSlicerViewMode);
begin
  View.Mode := AMode;
  if AMode = svMesa then
  begin
    BedButton.SetLook(sbsSolid, clSuitePrimary);
    LayersButton.SetLook(sbsSoft, clSuitePrimary);
  end
  else
  begin
    BedButton.SetLook(sbsSoft, clSuitePrimary);
    LayersButton.SetLook(sbsSolid, clSuitePrimary);
  end;
  LayerTrack.Visible := (AMode = svCamadas) and Ready;
  LayerLabel.Visible := LayerTrack.Visible;
end;

procedure TMultiSlicerForm.BedViewClick(Sender: TObject);
begin
  ShowViewMode(svMesa);
end;

procedure TMultiSlicerForm.LayersViewClick(Sender: TObject);
begin
  ShowViewMode(svCamadas);
end;

procedure TMultiSlicerForm.FitClick(Sender: TObject);
begin
  View.FitView;
end;

procedure TMultiSlicerForm.ZoomInClick(Sender: TObject);
begin
  View.ZoomIn;
end;

procedure TMultiSlicerForm.ZoomOutClick(Sender: TObject);
begin
  View.ZoomOut;
end;

procedure TMultiSlicerForm.RefreshModelInfo;
var A, B: TVec3;
begin
  if M.Count = 0 then
  begin
    ModelInfo.Caption := 'Nenhum modelo aberto.';
    Coords.Caption := '';
    Exit;
  end;
  MeshBounds(M, A, B);
  ModelInfo.Caption := Format('%s'#10'%d triangulos'#10'%.1f x %.1f x %.1f mm'#10'X %.1f..%.1f  Y %.1f..%.1f',
    [ExtractFileName(SourceFile), M.Count, B.X - A.X, B.Y - A.Y, B.Z - A.Z, A.X, B.X, A.Y, B.Y],
    InvariantFS);
  Coords.Caption := Format('Peca %.1f x %.1f x %.1f mm  |  mesa %.0f x %.0f x %.0f mm',
    [B.X - A.X, B.Y - A.Y, B.Z - A.Z, BedX.Value, BedY.Value, BedZ.Value], InvariantFS);
end;

procedure TMultiSlicerForm.ApplyPreset(const P: TPrinterPreset);
begin
  FUpdating := True;
  try
    BedX.Value := P.BedX; BedY.Value := P.BedY; BedZ.Value := P.BedZ;
    Nozzle.Value := P.Nozzle; FilamentDia.Value := P.Filament;
    RetractLen.Value := P.Retract;
    FlavorChoice.ItemIndex := Ord(P.Flavor);
  finally
    FUpdating := False;
  end;
  SettingsChanged(nil);
end;

procedure TMultiSlicerForm.PrinterChange(Sender: TObject);
var P: TPrinterPresets;
begin
  P := PrinterPresets;
  if (PrinterBox.ItemIndex >= 0) and (PrinterBox.ItemIndex <= High(P)) then
    ApplyPreset(P[PrinterBox.ItemIndex]);
end;

procedure TMultiSlicerForm.SettingsChanged(Sender: TObject);
var P: TPrinterPresets; I: Integer;
begin
  if FUpdating then Exit;
  { campo da impressora alterado a mao: perfil passa a "Personalizada" }
  if (Sender = BedX) or (Sender = BedY) or (Sender = BedZ) or (Sender = Nozzle) or
    (Sender = FilamentDia) or (Sender = RetractLen) or (Sender = FlavorChoice) then
  begin
    P := PrinterPresets;
    I := PrinterBox.ItemIndex;
    if (I >= 0) and (I <= High(P)) and not (SameValue(BedX.Value, P[I].BedX) and
      SameValue(BedY.Value, P[I].BedY) and SameValue(BedZ.Value, P[I].BedZ) and
      SameValue(Nozzle.Value, P[I].Nozzle) and SameValue(FilamentDia.Value, P[I].Filament) and
      SameValue(RetractLen.Value, P[I].Retract) and (FlavorChoice.ItemIndex = Ord(P[I].Flavor))) then
    begin
      FUpdating := True;
      PrinterBox.ItemIndex := PrinterBox.Items.Count - 1;
      FUpdating := False;
    end;
  end;
  Ready := False;
  FExportedFile := '';
  if Assigned(Code) then Code.Clear;
  if Assigned(View) then
  begin
    View.SetBed(BedX.Value, BedY.Value);
    View.SetSlice(nil, -1);
    ShowViewMode(View.Mode);
  end;
  if Assigned(SendButton) then SendButton.Enabled := False;
  if Assigned(ModelInfo) then RefreshModelInfo;
  if M.Count > 0 then
  begin
    SetState('Alteracoes pendentes', clSuiteWarning);
    if Assigned(Status) then Status.Caption := 'Configuracao alterada. Fatie novamente para atualizar a previa.';
    if Assigned(PreviewSummary) then PreviewSummary.Caption := 'Fatie para ver tempo, filamento e camadas.';
  end;
end;

{ ---------------- modelo ---------------- }

procedure TMultiSlicerForm.OpenFile(const FN: string);
var Candidate: TMesh; OK: Boolean;
begin
  if not FileExists(FN) then raise EInOutError.Create('Arquivo nao encontrado: ' + FN);
  Candidate := TMesh.Create;
  try
    try
      if SameText(ExtractFileExt(FN), '.3mf') then OK := T3MFImporter.Load(FN, Candidate)
      else OK := TSTLImporter.Load(FN, Candidate);
    except
      OK := False;
    end;
    if not OK or (Candidate.Count = 0) then
      raise Exception.Create('Modelo invalido ou sem triangulos: ' + FN);
    View.SetMesh(nil);
    M.Free; M := Candidate; Candidate := nil;
    SourceFile := ExpandFileName(FN);
    CenterModel;
    SliceBtn.Enabled := True; ExportBtn.Enabled := True;
    Status.Caption := Format('Aberto: %s (%d triangulos). Peca centralizada na mesa.',
      [ExtractFileName(FN), M.Count]);
    if Log <> nil then Log.Lines.Add('Aberto: ' + SourceFile);
  finally
    Candidate.Free;
  end;
end;

procedure TMultiSlicerForm.CenterModel;
var A, B: TVec3; DX, DY, DZ: Double; I: Integer; T: TTriangle; N: TMesh;
begin
  if M.Count = 0 then Exit;
  MeshBounds(M, A, B);
  DX := BedX.Value / 2 - (A.X + B.X) / 2;
  DY := BedY.Value / 2 - (A.Y + B.Y) / 2;
  DZ := -A.Z;
  N := TMesh.Create;
  for I := 0 to M.Count - 1 do
  begin
    T := M.Triangle(I);
    T.A.X := T.A.X + DX; T.A.Y := T.A.Y + DY; T.A.Z := T.A.Z + DZ;
    T.B.X := T.B.X + DX; T.B.Y := T.B.Y + DY; T.B.Z := T.B.Z + DZ;
    T.C.X := T.C.X + DX; T.C.Y := T.C.Y + DY; T.C.Z := T.C.Z + DZ;
    N.Add(T);
  end;
  View.SetMesh(nil);
  M.Free; M := N;
  View.SetMesh(M);
  SettingsChanged(nil);
end;

procedure TMultiSlicerForm.OpenClick(Sender: TObject);
var D: TOpenDialog;
begin
  D := TOpenDialog.Create(Self);
  try
    D.Filter := 'Modelos 3D (*.stl;*.3mf)|*.stl;*.3mf|STL|*.stl|3MF|*.3mf';
    D.Options := [ofFileMustExist, ofEnableSizing];
    if D.Execute then
    try
      OpenFile(D.FileName);
      ShowStep(1);
    except
      on E: Exception do ShowError(E);
    end;
  finally
    D.Free;
  end;
end;

procedure TMultiSlicerForm.CenterClick(Sender: TObject);
begin
  if M.Count = 0 then Exit;
  CenterModel;
  Status.Caption := 'Peca centralizada na mesa e assentada em Z = 0.';
end;

{ ---------------- fatiamento ---------------- }

function TMultiSlicerForm.Settings: TSliceSettings;
begin
  Result := DefaultSliceSettings;
  Result.Printer := DefaultPrinterProfile;
  if PrinterBox.ItemIndex >= 0 then Result.Printer.Name := PrinterBox.Text;
  Result.Printer.BedX := BedX.Value; Result.Printer.BedY := BedY.Value; Result.Printer.MaxZ := BedZ.Value;
  Result.Printer.Nozzle := Nozzle.Value;
  Result.Printer.FilamentDiameter := FilamentDia.Value;
  Result.Printer.HotendTemp := Hotend.Value; Result.Printer.BedTemp := BedTemp.Value;
  Result.Flavor := TSlicerFlavor(FlavorChoice.ItemIndex);
  Result.LayerHeight := LayerHeight.Value; Result.Printer.LayerHeight := Result.LayerHeight;
  Result.FirstLayerHeight := Result.LayerHeight;
  if Result.LayerHeight > Result.Printer.Nozzle * 0.8 + 1e-9 then
    raise Exception.Create('A altura de camada deve ser no maximo 80% do diametro do bico.');
  Result.LineWidth := Result.Printer.Nozzle * 1.125;
  Result.Walls := Walls.Value;
  Result.TopLayers := TopLayers.Value; Result.BottomLayers := BottomLayers.Value;
  Result.InfillDensity := InfillDensity.Value / 100;
  Result.InfillPattern := TInfillPattern(PatternChoice.ItemIndex);
  Result.WallSpeed := Speed.Value; Result.OuterWallSpeed := Speed.Value * 0.6; Result.InfillSpeed := Speed.Value;
  Result.RetractLength := RetractLen.Value;
  Result.ArcFitting := ArcFit.Checked;
  Result.SkirtLoops := SkirtLoops.Value; Result.SkirtDistance := SkirtDist.Value;
  Result.FanFromLayer := FanLayer.Value;
  Result.FilamentDensity := Density.Value;
  Result.Adaptive := Adaptive.Checked;
  Result.AdaptiveMin := Min(0.08, Result.LayerHeight);
  Result.AdaptiveMax := Min(Result.LayerHeight, Result.Printer.Nozzle * 0.8);
  Result.ObjectName := ChangeFileExt(ExtractFileName(SourceFile), '');
  if Result.ObjectName = '' then Result.ObjectName := 'objeto';
end;

function TMultiSlicerForm.ValidateJob: Boolean;
var A, B: TVec3; Errors: TStringList; S: TSliceSettings; I: Integer;
begin
  Errors := TStringList.Create;
  try
    if M.Count = 0 then Errors.Add('Abra um modelo STL ou 3MF.')
    else
    begin
      MeshBounds(M, A, B);
      if (A.X < -1e-6) or (A.Y < -1e-6) or (B.X > BedX.Value + 1e-6) or (B.Y > BedY.Value + 1e-6) then
        Errors.Add(Format('A peca sai da mesa (X %.1f..%.1f, Y %.1f..%.1f; mesa %.0f x %.0f mm). Use Centralizar.',
          [A.X, B.X, A.Y, B.Y, BedX.Value, BedY.Value], InvariantFS));
      if B.Z - A.Z > BedZ.Value + 1e-6 then
        Errors.Add(Format('A peca tem %.1f mm de altura; a impressora vai ate %.0f mm.',
          [B.Z - A.Z, BedZ.Value], InvariantFS));
      if Abs(A.Z) > 1e-3 then
        Errors.Add('A peca nao esta assentada na mesa (Z minimo diferente de 0). Use Centralizar.');
    end;
    try
      S := Settings;
      if S.InfillDensity < 0 then Errors.Add('Preenchimento invalido.');
    except
      on E: Exception do Errors.Add(E.Message);
    end;
    Result := Errors.Count = 0;
    Log.Lines.Add('--- Validacao ---');
    if Result then
    begin
      Log.Lines.Add('Trabalho valido.');
      Status.Caption := 'Trabalho valido. Fatie para gerar o G-code.';
      if not Ready then SetState('Trabalho valido', clSuiteInfo);
    end
    else
    begin
      for I := 0 to Errors.Count - 1 do Log.Lines.Add(Errors[I]);
      Status.Caption := Errors[0];
      SetState('Corrigir o trabalho', clSuiteDanger);
    end;
  finally
    Errors.Free;
  end;
end;

procedure TMultiSlicerForm.GenerateProgram;
var Candidate: TModernSlicer; G: TStringList; R: TSliceReport;
begin
  if M.Count = 0 then raise Exception.Create('Abra um modelo STL ou 3MF primeiro.');
  Candidate := TModernSlicer.Create;
  G := TStringList.Create;
  Screen.Cursor := crHourGlass;
  try
    R := Candidate.Slice(M, Settings, G);
    if (R.Layers = 0) or (G.Count = 0) then raise Exception.Create('O modelo nao gerou camadas imprimiveis.');
    View.SetSlice(nil, -1);
    Engine.Free; Engine := Candidate; Candidate := nil;
    Code.Assign(G); Report := R; Ready := True; FExportedFile := '';
    FUpdating := True;
    try
      LayerChoice.MaxValue := R.Layers; LayerChoice.Value := 1;
      LayerTrack.Max := R.Layers; LayerTrack.Position := 1;
    finally
      FUpdating := False;
    end;
    View.SetSlice(Engine, 0);
    PreviewSummary.Caption := Format('%d camadas'#10'Tempo estimado: %d h %.2d min'#10 +
      'Filamento: %.2f m  /  %.1f g'#10'Retracoes: %d', [R.Layers, Trunc(R.EstimatedSeconds / 3600),
      Trunc(R.EstimatedSeconds / 60) mod 60, R.FilamentMM / 1000, R.FilamentGrams, R.Retractions],
      InvariantFS);
    if R.Warnings <> '' then PreviewSummary.Caption := PreviewSummary.Caption + #10'Avisos: ' + R.Warnings;
    OutSummary.Caption := Format('%d linhas de G-code (%s). Gere o arquivo para salvar e enviar ao MultiCNC.',
      [Code.Count, FlavorChoice.Text]);
    Log.Lines.Add(Format('Fatiado: %d camadas | %.2f g | %.1f min | %d retracoes',
      [R.Layers, R.FilamentGrams, R.EstimatedSeconds / 60, R.Retractions], InvariantFS));
    if R.Warnings <> '' then Log.Lines.Add('Avisos: ' + R.Warnings);
    Status.Caption := Format('Fatiado: %d camadas, %d min, %.1f g de filamento.',
      [R.Layers, Round(R.EstimatedSeconds / 60), R.FilamentGrams], InvariantFS);
    SetState('Fatiado', clSuiteInfo);
    SendButton.Enabled := False;
    ShowViewMode(svCamadas);
  finally
    Screen.Cursor := crDefault;
    G.Free;
    Candidate.Free;
  end;
end;

procedure TMultiSlicerForm.ExportProgram(const FN: string);
begin
  if not Ready then GenerateProgram;
  Code.SaveToFile(FN);
  FExportedFile := ExpandFileName(FN);
  SendButton.Enabled := True;
  SetState('G-code gerado', clSuiteSuccess);
  Status.Caption := 'G-code salvo em ' + FExportedFile + '. Abra no MultiCNC para imprimir.';
  Log.Lines.Add('Salvo: ' + FExportedFile);
end;

procedure TMultiSlicerForm.LayerChanged(Sender: TObject);
begin
  if FUpdating or not Ready then Exit;
  FUpdating := True;
  try
    LayerTrack.Position := LayerChoice.Value;
  finally
    FUpdating := False;
  end;
  View.SetSlice(Engine, LayerChoice.Value - 1);
  if View.Mode <> svCamadas then ShowViewMode(svCamadas);
end;

procedure TMultiSlicerForm.TrackChanged(Sender: TObject);
begin
  if FUpdating or not Ready then Exit;
  FUpdating := True;
  try
    LayerChoice.Value := LayerTrack.Position;
  finally
    FUpdating := False;
  end;
  View.SetSlice(Engine, LayerTrack.Position - 1);
end;

procedure TMultiSlicerForm.SliceClick(Sender: TObject);
begin
  try
    if not ValidateJob then Exit;
    GenerateProgram;
    ShowStep(5);
  except
    on E: Exception do ShowError(E);
  end;
end;

procedure TMultiSlicerForm.ValidateClick(Sender: TObject);
begin
  try
    ValidateJob;
  except
    on E: Exception do ShowError(E);
  end;
end;

procedure TMultiSlicerForm.ExportClick(Sender: TObject);
var D: TSaveDialog;
begin
  try
    if not ValidateJob then Exit;
  except
    on E: Exception do begin ShowError(E); Exit; end;
  end;
  D := TSaveDialog.Create(Self);
  try
    D.Filter := 'G-code|*.gcode';
    D.DefaultExt := 'gcode';
    D.FileName := ChangeFileExt(ExtractFileName(SourceFile), '.gcode');
    if SourceFile <> '' then D.InitialDir := ExtractFilePath(SourceFile);
    D.Options := [ofOverwritePrompt, ofPathMustExist, ofEnableSizing];
    if D.Execute then
    try
      ExportProgram(D.FileName);
      ShowStep(6);
    except
      on E: Exception do ShowError(E);
    end;
  finally
    D.Free;
  end;
end;

procedure TMultiSlicerForm.SendClick(Sender: TObject);
var Registry: TSuiteRegistry; Root, Err, Candidate: string; C: TSuiteContext; I: Integer;
begin
  if (FExportedFile = '') or not FileExists(FExportedFile) then
  begin
    Status.Caption := 'Gere o G-code antes de abrir no MultiCNC.';
    Exit;
  end;
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
      Status.Caption := 'Programa aberto no MultiCNC. Selecione a impressora 3D, conecte e imprima.';
      Log.Lines.Add('Enviado ao MultiCNC: ' + FExportedFile);
    except
      on E: Exception do ShowError(E);
    end;
  finally
    Registry.Free;
  end;
end;

end.
