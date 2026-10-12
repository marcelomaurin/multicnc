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
  posicionamento 3D, suportes e previa 3D vem nas etapas seguintes; perfis de
  impressora e material estao em multislicer_printers/materials, Etapa 2). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls, Spin,
  Dialogs, Graphics, LCLType, multislicer_types, multislicer_mesh, multislicer_stl,
  multislicer_3mf, multislicer_profile, multislicer_pipeline, multislicer_view,
  multislicer_printers, multislicer_materials, multislicer_userdata,
  multisuite_controls, multisuite_icons;

const
  MS_STEP_COUNT = 7;
  MS_STEPS: array[0..MS_STEP_COUNT - 1] of string = ('1  Impressora', '2  Modelo',
    '3  Material', '4  Qualidade', '5  Suportes', '6  Previa', '7  Saida');

type
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
    FPrinters: TPrinterDefs;
    PrinterBox, FlavorChoice, ExtruderChoice: TComboBox;
    BedX, BedY, BedZ, Nozzle, FilamentDia: TFloatSpinEdit;
    HeatedBedBox: TCheckBox;
    StartMemo, EndMemo: TMemo;
    PrinterNote: TLabel;
    PrinterDeleteBtn: TSuiteButton;
    { material }
    FMaterials: TMaterialDefs;
    MaterialBox: TComboBox;
    HotendFirst, Hotend, BedFirst, BedTemp, FanPct, FanLayer: TSpinEdit;
    Density, Flow, RetractLen, RetractSpd, Cost: TFloatSpinEdit;
    MaterialNote, MaterialNotes: TLabel;
    MaterialDeleteBtn: TSuiteButton;
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
    procedure ExtruderChange(Sender: TObject);
    procedure MaterialChange(Sender: TObject);
    procedure SavePrinterClick(Sender: TObject);
    procedure DeletePrinterClick(Sender: TObject);
    procedure SaveMaterialClick(Sender: TObject);
    procedure DeleteMaterialClick(Sender: TObject);
    procedure ReloadPrinters(const SelectName: string);
    procedure ReloadMaterials(const SelectName: string);
    procedure ApplyPrinter(const P: TPrinterDef);
    procedure ApplyMaterial(const AMat: TMaterialDef);
    procedure RefreshProfileNotes;
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
    { perfil atual montado a partir dos campos da tela }
    function CurrentPrinter: TPrinterDef;
    function CurrentMaterial: TMaterialDef;
    procedure SelectPrinter(const AName: string);
    procedure SelectMaterial(const AName: string);
  end;

procedure MeshBounds(AMesh: TMesh; out AMin, AMax: TVec3);

implementation

uses multisuite_numfmt, multisuite_registry, multisuite_launcher, multisuite_types,
  multisuite_context;

const
  STEP_ICONS: array[0..MS_STEP_COUNT - 1] of TSuiteIconKind = (sikGear, sikMove,
    sikThermo, sikLayers, sikFlag, sikEye, sikExport);

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
  ReloadPrinters(ReadLastChoice('printer'));
  if PrinterBox.ItemIndex < 0 then PrinterBox.ItemIndex := 0;
  PrinterChange(nil);
  ReloadMaterials(ReadLastChoice('material'));
  if MaterialBox.ItemIndex < 0 then MaterialBox.ItemIndex := 0;
  MaterialChange(nil);
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
var K: TExtruderKind;
begin
  LabelAt(S, 'O volume da impressora define a mesa da vista e a validacao.',
    16, 48, 290, 40);
  PrinterBox := Combo(S, 'Perfil de impressora', 92);
  PrinterBox.OnChange := @PrinterChange;
  PrinterNote := LabelAt(S, '', 16, 146, 290, 20);
  Button(S, 'Salvar...', 16, 168, 140, sikSave, @SavePrinterClick);
  PrinterDeleteBtn := Button(S, 'Excluir', 166, 168, 140, sikTrash, @DeletePrinterClick);
  FlavorChoice := Combo(S, 'Firmware', 214);
  FlavorChoice.Items.Add('Marlin'); FlavorChoice.Items.Add('Klipper');
  FlavorChoice.ItemIndex := 0;
  FlavorChoice.OnChange := @SettingsChanged;
  ExtruderChoice := Combo(S, 'Extrusora', 272);
  for K := Low(TExtruderKind) to High(TExtruderKind) do ExtruderChoice.Items.Add(EXTRUDER_NAMES[K]);
  ExtruderChoice.ItemIndex := 0;
  ExtruderChoice.OnChange := @ExtruderChange;
  BedX := FloatField(S, 'Mesa X (mm)', 'BedX', 220, 10, 2000, 1, 1, 330);
  BedY := FloatField(S, 'Mesa Y (mm)', 'BedY', 220, 10, 2000, 1, 1, 386);
  BedZ := FloatField(S, 'Altura maxima Z (mm)', 'BedZ', 250, 10, 2000, 1, 1, 442);
  Nozzle := FloatField(S, 'Diametro do bico (mm)', 'Nozzle', 0.4, 0.1, 2, 0.05, 2, 498);
  FilamentDia := FloatField(S, 'Diametro do filamento (mm)', 'FilamentDiameter', 1.75, 1, 3.5, 0.05, 2, 554);
  HeatedBedBox := Check(S, 'Mesa aquecida', 612);
  HeatedBedBox.Checked := True;
  Section(S, 'G-CODE INICIAL', 650);
  StartMemo := TMemo.Create(Self);
  StartMemo.Parent := S; StartMemo.Name := 'StartGCode';
  StartMemo.SetBounds(16, 672, 290, 170);
  StartMemo.ScrollBars := ssAutoBoth; StartMemo.WordWrap := False;
  StartMemo.Font.Name := 'Courier New'; StartMemo.Font.Size := 9;
  StartMemo.Clear;
  StartMemo.OnChange := @SettingsChanged;
  Section(S, 'G-CODE FINAL', 852);
  EndMemo := TMemo.Create(Self);
  EndMemo.Parent := S; EndMemo.Name := 'EndGCode';
  EndMemo.SetBounds(16, 874, 290, 130);
  EndMemo.ScrollBars := ssAutoBoth; EndMemo.WordWrap := False;
  EndMemo.Font.Name := 'Courier New'; EndMemo.Font.Size := 9;
  EndMemo.Clear;
  EndMemo.OnChange := @SettingsChanged;
  LabelAt(S, 'Vazio = bloco padrao (aquece, G28, espera). Variaveis: {first_layer_bed_temp} {first_layer_hotend_temp} {bed_temp} {hotend_temp} {bed_x} {bed_y} {bed_z} {fan_speed}.',
    16, 1012, 290, 76);
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
  MaterialBox := Combo(S, 'Filamento', 52);
  MaterialBox.OnChange := @MaterialChange;
  MaterialNote := LabelAt(S, '', 16, 106, 290, 20);
  Button(S, 'Salvar...', 16, 128, 140, sikSave, @SaveMaterialClick);
  MaterialDeleteBtn := Button(S, 'Excluir', 166, 128, 140, sikTrash, @DeleteMaterialClick);
  MaterialNotes := LabelAt(S, '', 16, 170, 290, 58);
  Section(S, 'TEMPERATURAS', 234);
  HotendFirst := IntField(S, 'Bico na 1a camada (C)', 'HotendFirstLayer', 205, 0, 400, 256);
  Hotend := IntField(S, 'Bico nas demais camadas (C)', 'HotendTemperature', 200, 0, 400, 312);
  BedFirst := IntField(S, 'Mesa na 1a camada (C)', 'BedFirstLayer', 60, 0, 150, 368);
  BedTemp := IntField(S, 'Mesa nas demais camadas (C)', 'BedTemperature', 60, 0, 150, 424);
  Section(S, 'VENTOINHA', 490);
  FanPct := IntField(S, 'Ventoinha da peca (%)', 'FanPercent', 100, 0, 100, 512);
  FanLayer := IntField(S, 'Liga a partir da camada', 'FanFromLayer', 2, 1, 50, 568);
  Section(S, 'EXTRUSAO', 634);
  Flow := FloatField(S, 'Fluxo (%)', 'FlowPercent', 100, 50, 150, 1, 0, 656);
  RetractLen := FloatField(S, 'Retracao (mm)', 'RetractLength', 5, 0, 15, 0.1, 1, 712);
  RetractSpd := FloatField(S, 'Velocidade de retracao (mm/s)', 'RetractSpeed', 45, 5, 150, 1, 0, 768);
  Section(S, 'PESO E CUSTO', 834);
  Density := FloatField(S, 'Densidade (g/cm3)', 'FilamentDensity', 1.24, 0.5, 3, 0.01, 2, 856);
  Cost := FloatField(S, 'Preco do carretel (R$ por kg)', 'CostPerKg', 120, 0, 10000, 5, 2, 912);
  LabelAt(S, 'A retracao vem do material conforme a extrusora da impressora (Bowden ou direta). Confira a faixa de temperatura no carretel.',
    16, 974, 290, 60);
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

{ ---------------- perfis de impressora e material ---------------- }

function TMultiSlicerForm.CurrentPrinter: TPrinterDef;
begin
  Result.Name := '';
  if (PrinterBox.ItemIndex >= 0) and (PrinterBox.ItemIndex <= High(FPrinters)) then
    Result.Name := FPrinters[PrinterBox.ItemIndex].Name;
  Result.BedX := BedX.Value; Result.BedY := BedY.Value; Result.BedZ := BedZ.Value;
  Result.Nozzle := Nozzle.Value; Result.FilamentDiameter := FilamentDia.Value;
  Result.Flavor := TSlicerFlavor(Max(0, FlavorChoice.ItemIndex));
  Result.Extruder := TExtruderKind(Max(0, ExtruderChoice.ItemIndex));
  Result.HeatedBed := HeatedBedBox.Checked;
  Result.StartGCode := TrimRight(StartMemo.Text);
  Result.EndGCode := TrimRight(EndMemo.Text);
  Result.BuiltIn := False;
end;

function TMultiSlicerForm.CurrentMaterial: TMaterialDef;
var K: Integer;
begin
  K := MaterialBox.ItemIndex;
  if (K >= 0) and (K <= High(FMaterials)) then Result := FMaterials[K]
  else Result := BuiltinMaterials[0];
  Result.BuiltIn := False;
  Result.HotendFirst := HotendFirst.Value; Result.Hotend := Hotend.Value;
  Result.BedFirst := BedFirst.Value; Result.Bed := BedTemp.Value;
  Result.FanPercent := FanPct.Value; Result.FanFromLayer := FanLayer.Value;
  Result.Density := Density.Value; Result.FlowPercent := Flow.Value;
  if ExtruderChoice.ItemIndex = Ord(ekBowden) then Result.RetractBowden := RetractLen.Value
  else Result.RetractDirect := RetractLen.Value;
  Result.RetractSpeed := RetractSpd.Value;
  Result.CostPerKg := Cost.Value;
end;

procedure TMultiSlicerForm.ReloadPrinters(const SelectName: string);
var I, K: Integer;
begin
  FPrinters := LoadPrinters;
  FUpdating := True;
  try
    PrinterBox.Items.Clear;
    for I := 0 to High(FPrinters) do
      if FPrinters[I].BuiltIn then PrinterBox.Items.Add(FPrinters[I].Name)
      else PrinterBox.Items.Add(FPrinters[I].Name + '  (meu)');
    K := FindPrinter(FPrinters, SelectName);
    PrinterBox.ItemIndex := K;
  finally
    FUpdating := False;
  end;
end;

procedure TMultiSlicerForm.ReloadMaterials(const SelectName: string);
var I, K: Integer;
begin
  FMaterials := LoadMaterials;
  FUpdating := True;
  try
    MaterialBox.Items.Clear;
    for I := 0 to High(FMaterials) do
      if FMaterials[I].BuiltIn then MaterialBox.Items.Add(FMaterials[I].Name)
      else MaterialBox.Items.Add(FMaterials[I].Name + '  (meu)');
    K := FindMaterial(FMaterials, SelectName);
    MaterialBox.ItemIndex := K;
  finally
    FUpdating := False;
  end;
end;

procedure TMultiSlicerForm.SelectPrinter(const AName: string);
var K: Integer;
begin
  K := FindPrinter(FPrinters, AName);
  if K < 0 then raise Exception.Create('Perfil de impressora nao encontrado: ' + AName);
  PrinterBox.ItemIndex := K;
  PrinterChange(PrinterBox);
end;

procedure TMultiSlicerForm.SelectMaterial(const AName: string);
var K: Integer;
begin
  K := FindMaterial(FMaterials, AName);
  if K < 0 then raise Exception.Create('Material nao encontrado: ' + AName);
  MaterialBox.ItemIndex := K;
  MaterialChange(MaterialBox);
end;

procedure TMultiSlicerForm.ApplyPrinter(const P: TPrinterDef);
begin
  FUpdating := True;
  try
    BedX.Value := P.BedX; BedY.Value := P.BedY; BedZ.Value := P.BedZ;
    Nozzle.Value := P.Nozzle; FilamentDia.Value := P.FilamentDiameter;
    FlavorChoice.ItemIndex := Ord(P.Flavor);
    ExtruderChoice.ItemIndex := Ord(P.Extruder);
    HeatedBedBox.Checked := P.HeatedBed;
    StartMemo.Text := P.StartGCode;
    EndMemo.Text := P.EndGCode;
    BedFirst.Enabled := P.HeatedBed; BedTemp.Enabled := P.HeatedBed;
  finally
    FUpdating := False;
  end;
end;

procedure TMultiSlicerForm.ApplyMaterial(const AMat: TMaterialDef);
begin
  FUpdating := True;
  try
    HotendFirst.Value := AMat.HotendFirst; Hotend.Value := AMat.Hotend;
    BedFirst.Value := AMat.BedFirst; BedTemp.Value := AMat.Bed;
    FanPct.Value := AMat.FanPercent; FanLayer.Value := AMat.FanFromLayer;
    Density.Value := AMat.Density; Flow.Value := AMat.FlowPercent;
    if ExtruderChoice.ItemIndex = Ord(ekBowden) then RetractLen.Value := AMat.RetractBowden
    else RetractLen.Value := AMat.RetractDirect;
    RetractSpd.Value := AMat.RetractSpeed;
    Cost.Value := AMat.CostPerKg;
    MaterialNotes.Caption := AMat.Notes;
  finally
    FUpdating := False;
  end;
end;

procedure TMultiSlicerForm.RefreshProfileNotes;
var K: Integer; C: TMaterialDef; MatChanged: Boolean;
begin
  if PrinterNote = nil then Exit;
  K := PrinterBox.ItemIndex;
  if (K >= 0) and (K <= High(FPrinters)) and not SamePrinter(CurrentPrinter, FPrinters[K]) then
  begin
    PrinterNote.Caption := 'Perfil alterado: salve para manter.';
    PrinterNote.Font.Color := clSuiteWarning;
  end
  else
  begin
    PrinterNote.Caption := '';
    PrinterNote.Font.Color := clSuiteMuted;
  end;
  PrinterDeleteBtn.Enabled := (K >= 0) and (K <= High(FPrinters)) and not FPrinters[K].BuiltIn;
  K := MaterialBox.ItemIndex;
  if (K >= 0) and (K <= High(FMaterials)) then
  begin
    C := CurrentMaterial;
    MatChanged := (C.HotendFirst <> FMaterials[K].HotendFirst) or (C.Hotend <> FMaterials[K].Hotend) or
      (C.BedFirst <> FMaterials[K].BedFirst) or (C.Bed <> FMaterials[K].Bed) or
      (C.FanPercent <> FMaterials[K].FanPercent) or (C.FanFromLayer <> FMaterials[K].FanFromLayer) or
      not SameValue(C.Density, FMaterials[K].Density) or not SameValue(C.FlowPercent, FMaterials[K].FlowPercent) or
      not SameValue(C.RetractBowden, FMaterials[K].RetractBowden) or
      not SameValue(C.RetractDirect, FMaterials[K].RetractDirect) or
      not SameValue(C.RetractSpeed, FMaterials[K].RetractSpeed) or not SameValue(C.CostPerKg, FMaterials[K].CostPerKg);
    if MatChanged then
    begin
      MaterialNote.Caption := 'Material alterado: salve para manter.';
      MaterialNote.Font.Color := clSuiteWarning;
    end
    else MaterialNote.Caption := '';
    MaterialDeleteBtn.Enabled := not FMaterials[K].BuiltIn;
  end;
end;

procedure TMultiSlicerForm.PrinterChange(Sender: TObject);
var K: Integer;
begin
  if FUpdating then Exit;
  K := PrinterBox.ItemIndex;
  if (K < 0) or (K > High(FPrinters)) then Exit;
  ApplyPrinter(FPrinters[K]);
  { a retracao depende da extrusora: reaplica a do material atual }
  if (MaterialBox <> nil) and (MaterialBox.ItemIndex >= 0) and (MaterialBox.ItemIndex <= High(FMaterials)) then
    ExtruderChange(nil);
  if Sender <> nil then WriteLastChoice('printer', FPrinters[K].Name);
  SettingsChanged(nil);
end;

procedure TMultiSlicerForm.ExtruderChange(Sender: TObject);
var K: Integer;
begin
  if FUpdating then Exit;
  K := MaterialBox.ItemIndex;
  if (K >= 0) and (K <= High(FMaterials)) then
  begin
    FUpdating := True;
    try
      if ExtruderChoice.ItemIndex = Ord(ekBowden) then RetractLen.Value := FMaterials[K].RetractBowden
      else RetractLen.Value := FMaterials[K].RetractDirect;
    finally
      FUpdating := False;
    end;
  end;
  if Sender <> nil then SettingsChanged(Sender);
end;

procedure TMultiSlicerForm.MaterialChange(Sender: TObject);
var K: Integer;
begin
  if FUpdating then Exit;
  K := MaterialBox.ItemIndex;
  if (K < 0) or (K > High(FMaterials)) then Exit;
  ApplyMaterial(FMaterials[K]);
  if Sender <> nil then WriteLastChoice('material', FMaterials[K].Name);
  SettingsChanged(nil);
end;

procedure TMultiSlicerForm.SavePrinterClick(Sender: TObject);
var P: TPrinterDef; AName: string;
begin
  P := CurrentPrinter;
  AName := P.Name;
  if not InputQuery('Salvar perfil de impressora', 'Nome do perfil:', AName) then Exit;
  AName := Trim(AName);
  if AName = '' then Exit;
  P.Name := AName;
  try
    SavePrinter(P);
    ReloadPrinters(AName);
    WriteLastChoice('printer', AName);
    RefreshProfileNotes;
    Status.Caption := 'Perfil de impressora salvo: ' + AName;
  except
    on E: Exception do ShowError(E);
  end;
end;

procedure TMultiSlicerForm.DeletePrinterClick(Sender: TObject);
var K: Integer; AName: string;
begin
  K := PrinterBox.ItemIndex;
  if (K < 0) or (K > High(FPrinters)) or FPrinters[K].BuiltIn then Exit;
  AName := FPrinters[K].Name;
  if MessageDlg('Excluir perfil', 'Excluir o perfil de impressora "' + AName + '"?',
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes then Exit;
  DeletePrinter(AName);
  ReloadPrinters(AName);  { se havia perfil pronto com o mesmo nome, ele volta }
  if PrinterBox.ItemIndex < 0 then PrinterBox.ItemIndex := 0;
  PrinterChange(PrinterBox);
  Status.Caption := 'Perfil excluido: ' + AName;
end;

procedure TMultiSlicerForm.SaveMaterialClick(Sender: TObject);
var MD: TMaterialDef; AName: string;
begin
  MD := CurrentMaterial;
  AName := MD.Name;
  if not InputQuery('Salvar material', 'Nome do material:', AName) then Exit;
  AName := Trim(AName);
  if AName = '' then Exit;
  MD.Name := AName;
  try
    SaveMaterial(MD);
    ReloadMaterials(AName);
    WriteLastChoice('material', AName);
    RefreshProfileNotes;
    Status.Caption := 'Material salvo: ' + AName;
  except
    on E: Exception do ShowError(E);
  end;
end;

procedure TMultiSlicerForm.DeleteMaterialClick(Sender: TObject);
var K: Integer; AName: string;
begin
  K := MaterialBox.ItemIndex;
  if (K < 0) or (K > High(FMaterials)) or FMaterials[K].BuiltIn then Exit;
  AName := FMaterials[K].Name;
  if MessageDlg('Excluir material', 'Excluir o material "' + AName + '"?',
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes then Exit;
  DeleteMaterial(AName);
  ReloadMaterials(AName);
  if MaterialBox.ItemIndex < 0 then MaterialBox.ItemIndex := 0;
  MaterialChange(MaterialBox);
  Status.Caption := 'Material excluido: ' + AName;
end;

procedure TMultiSlicerForm.SettingsChanged(Sender: TObject);
begin
  if FUpdating then Exit;
  if Sender = HeatedBedBox then
  begin
    BedFirst.Enabled := HeatedBedBox.Checked;
    BedTemp.Enabled := HeatedBedBox.Checked;
  end;
  RefreshProfileNotes;
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
  Result.Printer.Name := CurrentPrinter.Name;
  Result.Printer.BedX := BedX.Value; Result.Printer.BedY := BedY.Value; Result.Printer.MaxZ := BedZ.Value;
  Result.Printer.Nozzle := Nozzle.Value;
  Result.Printer.FilamentDiameter := FilamentDia.Value;
  Result.Printer.HotendTemp := Hotend.Value;
  Result.FirstLayerHotendTemp := HotendFirst.Value;
  Result.HeatedBed := HeatedBedBox.Checked;
  if Result.HeatedBed then
  begin
    Result.Printer.BedTemp := BedTemp.Value;
    Result.FirstLayerBedTemp := BedFirst.Value;
  end
  else
  begin
    Result.Printer.BedTemp := 0;
    Result.FirstLayerBedTemp := 0;
  end;
  Result.FanPercent := FanPct.Value;
  Result.FlowPercent := Flow.Value;
  Result.RetractSpeed := RetractSpd.Value;
  Result.StartGCode := TrimRight(StartMemo.Text);
  Result.EndGCode := TrimRight(EndMemo.Text);
  if (MaterialBox.ItemIndex >= 0) and (MaterialBox.ItemIndex <= High(FMaterials)) then
    Result.MaterialName := FMaterials[MaterialBox.ItemIndex].Name;
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
    if Cost.Value > 0 then
      PreviewSummary.Caption := PreviewSummary.Caption + Format(#10'Custo do filamento: R$ %.2f',
        [R.FilamentGrams / 1000 * Cost.Value], InvariantFS);
    PreviewSummary.Caption := PreviewSummary.Caption + #10'Impressora: ' + CurrentPrinter.Name +
      #10'Material: ' + CurrentMaterial.Name + Format(' (bico %d C, mesa %d C)', [Hotend.Value, BedTemp.Value]);
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
