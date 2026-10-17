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
  multislicer_scene, multislicer_view3d, multislicer_toolpath3d, multicad_camera, multislicer_quality, multislicer_support,
  multisuite_controls, multisuite_icons, multislicer_machines, multicnc_types, multicnc_equipment, fpjson, multislicer_project, multislicer_meshcheck, multislicer_filaments;

const
  { manter igual ao VersionInfo do multislicer.lpi (revisao = etapa do PLANO_TAREFAS) }
  MS_VERSION = '0.1.0.1';
  MS_STEP_COUNT = 7;
  MS_STEPS: array[0..MS_STEP_COUNT - 1] of string = ('1  Impressora', '2  Modelo',
    '3  Material', '4  Qualidade', '5  Suportes', '6  Previa', '7  Saida');

type
  { fatia fora da thread da tela; a malha e uma copia (a cena pode mudar) }
  TSliceThread = class(TThread)
  public
    Engine: TModernSlicer;
    Mesh: TMesh;
    Settings: TSliceSettings;
    Output: TStringList;
    Report: TSliceReport;
    ErrorText: string;
    Canceled: Boolean;
    procedure Execute; override;
  end;

  TMultiSlicerForm = class(TForm)
  private
    FScene: TSliceScene;
    FMerged: TMesh;
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
    View: TSlicerView;          { previa de camadas (2D) }
    View3D: TSlicerView3D;      { mesa em 3D }
    ObjectList: TListBox;
    { modelo: transformacao da peca selecionada }
    PosX, PosY, RotXEd, RotYEd, RotZEd, ScaleXP, ScaleYP, ScaleZP, SizeX, SizeY, SizeZ: TFloatSpinEdit;
    CopiesEd: TSpinEdit;
    UniformBox, LockBox: TCheckBox;
    TransformNote: TLabel;
    UndoBtn, RedoBtn: TSuiteButton;
    FUndoKey: string;
    ViewButtons: array[0..2] of TSuiteButton;
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
    PrinterBrandBox, PrinterModelBox: TComboBox;
    CreatePrinterProfileBtn: TSuiteButton;
    PrinterBox, FlavorChoice, ExtruderChoice: TComboBox;
    BedX, BedY, BedZ, PrintStartZ, Nozzle, FilamentDia: TFloatSpinEdit;
    HeatedBedBox: TCheckBox;
    StartMemo, EndMemo: TMemo;
    PrinterNote: TLabel;
    OnlyLayerBox, TravelsBox, Preview2DBox: TCheckBox;
    { fatiamento em andamento }
    FSlicing, FCloseRequested: Boolean;
    FRunning: TModernSlicer;
    SliceProgress: TProgressBar;
    CancelBtn: TSuiteButton;
    { projeto .mslice }
    FProjectFile: string;
    FDirty, FLoadingProject: Boolean;
    FAskSave: Boolean;
    FLastMeshReport: TMeshReport;
    { equipamento do MultiCNC (combo no topo) }
    FHeader: TSuiteHeader;
    EquipmentBox: TComboBox;
    EquipmentNote: TLabel;
    FEquipment: TEquipmentProfiles;
    FEquipPrinter: TPrinterDef;     { perfil montado do equipamento escolhido }
    FHasEquipPrinter: Boolean;
    FMachine: TMachineSpec;         { catalogo de marca/modelo }
    FHasMachine: Boolean;
    PrinterDeleteBtn: TSuiteButton;
    { material }
    FMaterials: TMaterialDefs;
    FilamentKindBox, FilamentBrandBox, FilamentModelBox: TComboBox;
    MaterialBox: TComboBox;
    HotendFirst, Hotend, BedFirst, BedTemp, FanPct, FanLayer: TSpinEdit;
    Density, Flow, RetractLen, RetractSpd, Cost: TFloatSpinEdit;
    MaterialNote, MaterialNotes: TLabel;
    MaterialDeleteBtn: TSuiteButton;
    { qualidade }
    FQualities: TQualityDefs;
    QualityBox: TComboBox;
    QualityNote, QualityHint, InfillLabel: TLabel;
    QualityDeleteBtn: TSuiteButton;
    ModeBtn: array[0..1] of TSuiteButton;
    QualityBtn: array[0..2] of TSuiteButton;
    RecPanel, CustomPanel: TPanel;
    InfillTrack: TTrackBar;
    SupportBox, AdhesionBox: TCheckBox;
    LayerHeight, FirstLayerH, LineWidthP: TFloatSpinEdit;
    WallSpd, OuterSpd, InfillSpd, FirstSpd, TravelSpd, ZHopEd, PAEd: TFloatSpinEdit;
    Walls, TopLayers, BottomLayers, InfillDensity: TSpinEdit;
    PatternChoice: TComboBox;
    Adaptive, ArcFit: TCheckBox;
    { suportes e aderencia }
    SkirtLoops: TSpinEdit;
    SkirtDist: TFloatSpinEdit;
    SupportModeBox, SupportWhereBox, AdhesionTypeBox, BlockerBox: TComboBox;
    SupportAngle, SupportXY, SupportZ, SupportSpd, PillarDia, BrimWidthEd, RaftMarginEd, RaftGapEd: TFloatSpinEdit;
    BlkX, BlkY, BlkW, BlkD, BlkH: TFloatSpinEdit;
    SupportDens, SupportIfc: TSpinEdit;
    ShowOverhangsBox: TCheckBox;
    PillarInfo: TLabel;
    FPickPillar: Boolean;
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
    procedure PrinterBrandChange(Sender: TObject);
    procedure PrinterModelChange(Sender: TObject);
    procedure CreatePrinterProfileClick(Sender: TObject);
    procedure FilamentKindChange(Sender: TObject);
    procedure FilamentBrandChange(Sender: TObject);
    procedure FilamentModelChange(Sender: TObject);
    procedure PrinterChange(Sender: TObject);
    procedure ExtruderChange(Sender: TObject);
    procedure MaterialChange(Sender: TObject);
    procedure SavePrinterClick(Sender: TObject);
    procedure DeletePrinterClick(Sender: TObject);
    procedure SaveMaterialClick(Sender: TObject);
    procedure DeleteMaterialClick(Sender: TObject);
    procedure ReloadPrinters(const SelectName: string);
    procedure ReloadEquipment;
    procedure PreviewOptionChange(Sender: TObject);
    procedure CancelSliceClick(Sender: TObject);
    procedure NewProjectClick(Sender: TObject);
    procedure InchClick(Sender: TObject);
    procedure FormDropFiles(Sender: TObject; const FileNames: array of string);
    procedure OpenProjectClick(Sender: TObject);
    procedure SaveProjectClick(Sender: TObject);
    procedure SaveProjectAsClick(Sender: TObject);
    function ProjectSettingsJSON: TJSONObject;
    procedure ApplyProjectSettings(O: TJSONObject);
    function ConfirmDiscard: Boolean;
    procedure UpdateTitle;
    procedure SetBusy(ABusy: Boolean);
    procedure FormCloseQuery(Sender: TObject; var CanClose: Boolean);
    procedure EquipmentChange(Sender: TObject);
    procedure HeaderResize(Sender: TObject);
    procedure MachineChecks(Errors, Warnings: TStrings);
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
    procedure RefreshObjectList;
    procedure SceneChanged(const Msg: string);
    procedure DuplicateClick(Sender: TObject);
    procedure RemoveClick(Sender: TObject);
    procedure ClearClick(Sender: TObject);
    procedure ObjectListClick(Sender: TObject);
    procedure View3DSelect(Sender: TObject);
    procedure View3DMoved(Sender: TObject);
    procedure View3DDelete(Sender: TObject);
    procedure StdViewClick(Sender: TObject);
    procedure LoadTransformEditor;
    procedure ModeClick(Sender: TObject);
    procedure QualityCardClick(Sender: TObject);
    procedure QualityChange(Sender: TObject);
    procedure SaveQualityClick(Sender: TObject);
    procedure DeleteQualityClick(Sender: TObject);
    procedure InfillTrackChange(Sender: TObject);
    procedure AdhesionClick(Sender: TObject);
    procedure ReloadQualities(const SelectName: string);
    procedure ApplyQuality(const Q: TQualityDef);
    procedure ShowQualityMode(Custom: Boolean);
    procedure SyncRecommended;
    procedure TransformChange(Sender: TObject);
    procedure Rotate90Click(Sender: TObject);
    procedure MirrorClick(Sender: TObject);
    procedure LayFlatClick(Sender: TObject);
    procedure PickFaceClick(Sender: TObject);
    procedure FacePicked(Sender: TObject; ObjIndex, TriIndex: Integer; const Hit: TVec3);
    procedure SupportSettingsChanged(Sender: TObject);
    procedure AddPillarClick(Sender: TObject);
    procedure ClearPillarsClick(Sender: TObject);
    procedure AddBlockerClick(Sender: TObject);
    procedure RemoveBlockerClick(Sender: TObject);
    procedure BlockerSelect(Sender: TObject);
    procedure BlockerFieldChange(Sender: TObject);
    procedure SupportBoxClick(Sender: TObject);
    procedure RefreshSupportAids;
    procedure ArrangeClick(Sender: TObject);
    procedure LockClick(Sender: TObject);
    procedure UndoClick(Sender: TObject);
    procedure RedoClick(Sender: TObject);
    procedure BeforeMove(Sender: TObject);
    procedure FormKey(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure PushUndo(const Key: string);
    function TargetObject: TSliceObject;
    function TransformField(AParent: TWinControl; const AText, AName: string; X, Y, W: Integer;
      MinV, MaxV, Step: Double; Decimals: Integer): TFloatSpinEdit;
    function GetMergedMesh: TMesh;
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
    property Mesh: TMesh read GetMergedMesh;   { todas as pecas, ja na mesa }
    property Scene: TSliceScene read FScene;
    property ViewControl3D: TSlicerView3D read View3D;
    procedure RemoveSelected;
    procedure DoUndo;
    procedure DoRedo;
    property ExportedFile: string read FExportedFile;
    { perfil atual montado a partir dos campos da tela }
    function CurrentPrinter: TPrinterDef;
    function CurrentMaterial: TMaterialDef;
    procedure SelectPrinter(const AName: string);
    procedure SelectMaterial(const AName: string);
    function CurrentQuality: TQualityDef;
    procedure SelectQuality(const AName: string);
    { equipamento do MultiCNC; '' = ajuste manual }
    procedure SelectEquipment(const AName: string);
    { pede para parar o fatiamento em andamento }
    procedure CancelSlicing;
    property Slicing: Boolean read FSlicing;
    { projeto .mslice }
    procedure NewProject;
    { arquivos arrastados para a janela: modelos entram na mesa, .mslice abre }
    procedure DropFiles(const FileNames: array of string);
    { converte as pecas selecionadas de polegadas para mm }
    procedure ConvertInches;
    property LastMeshReport: TMeshReport read FLastMeshReport;
    procedure OpenProject(const FN: string);
    procedure SaveProjectAs(const FN: string);
    property ProjectFile: string read FProjectFile;
    property ProjectDirty: Boolean read FDirty;
    { False: nao pergunta se salva antes de descartar (testes) }
    property AskSave: Boolean read FAskSave write FAskSave;
    property Equipment: TComboBox read EquipmentBox;
    property Machine: TMachineSpec read FMachine;
    property HasMachine: Boolean read FHasMachine;
  end;

procedure MeshBounds(AMesh: TMesh; out AMin, AMax: TVec3);

var
  { testes: outro cadastro de equipamentos ('' = o do MultiCNC) }
  EquipmentFileOverride: string = '';

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
  LastBrand, LastModel, LastKind, InfillStr: string;
begin
  inherited CreateNew(AOwner, 1);
  Caption := 'MultiSlicer ' + MS_VERSION + ' • MultiSuite';
  Width := 1280; Height := 860;
  Constraints.MinWidth := 1060; Constraints.MinHeight := 680;
  Position := poScreenCenter;
  Font.Name := SUITE_FONT; Font.Size := 10;
  Color := clSuiteSurface;
  FScene := TSliceScene.Create;
  FMerged := TMesh.Create;
  Engine := TModernSlicer.Create;
  Code := TStringList.Create;
  FUpdating := True;

  Header := TSuiteHeader.Create(Self);
  Header.Parent := Self; Header.Align := alTop; Header.Height := 72;
  Header.Setup('MultiSlicer', 'Preparacao para impressao 3D  /  MultiSuite  /  versao ' + MS_VERSION, sikSlicer);
  FHeader := Header;
  { mesmo combo dos outros programas: os equipamentos cadastrados no MultiCNC }
  EquipmentBox := TComboBox.Create(Self);
  EquipmentBox.Name := 'SavedEquipment';
  EquipmentBox.Parent := Header;
  EquipmentBox.SetBounds(0, 22, 280, 28);
  EquipmentBox.Style := csDropDownList;
  EquipmentBox.Hint := 'Impressoras 3D cadastradas no MultiCNC. Marca e modelo completam a configuracao.';
  EquipmentBox.ShowHint := True;
  EquipmentBox.OnChange := @EquipmentChange;
  Header.OnResize := @HeaderResize;

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
  SliceProgress := TProgressBar.Create(Self);
  SliceProgress.Parent := FooterPanel;
  SliceProgress.SetBounds(18, 38, 300, 18);
  SliceProgress.Min := 0; SliceProgress.Max := 1000;
  SliceProgress.Visible := False;
  CancelBtn := Button(FooterPanel, 'Cancelar', 0, 15, 116, sikClose, @CancelSliceClick);
  CancelBtn.Name := 'CancelSlice';
  CancelBtn.SetLook(sbsSolid, clSuiteDanger, sikClose);
  CancelBtn.Hint := 'Parar o fatiamento (Esc)';
  CancelBtn.Visible := False;
  OnCloseQuery := @FormCloseQuery;
  AllowDropFiles := True;
  OnDropFiles := @FormDropFiles;

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
  ModelInfo := LabelAt(Sidebar, '', 16, 16 + MS_STEP_COUNT * 44 + 56, 184, 96);
  ModelInfo.Align := alBottom;
  ModelInfo.BorderSpacing.Around := 12;
  Section(Sidebar, 'PECAS NA MESA', 16 + MS_STEP_COUNT * 44 + 56).Width := 190;
  ObjectList := TListBox.Create(Self);
  ObjectList.Parent := Sidebar;
  ObjectList.SetBounds(12, 16 + MS_STEP_COUNT * 44 + 80, 190, 160);
  ObjectList.Anchors := [akLeft, akTop, akRight, akBottom];
  ObjectList.MultiSelect := True;
  ObjectList.OnClick := @ObjectListClick;

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
  ViewButtons[0] := Button(ViewBar, 'Frente', 456, 9, 84, sikFrame, @StdViewClick);
  ViewButtons[0].Tag := Ord(svFront);
  ViewButtons[1] := Button(ViewBar, 'Topo', 546, 9, 76, sikLayers, @StdViewClick);
  ViewButtons[1].Tag := Ord(svTop);
  ViewButtons[2] := Button(ViewBar, 'Iso', 628, 9, 66, sikCAD, @StdViewClick);
  ViewButtons[2].Tag := Ord(svIso);
  LayerLabel := LabelAt(ViewBar, 'Camada', 14, 58, 64, 20);
  LayerTrack := TTrackBar.Create(Self);
  LayerTrack.Parent := ViewBar;
  LayerTrack.SetBounds(80, 52, 300, 32);
  LayerTrack.Min := 1; LayerTrack.Max := 1; LayerTrack.Position := 1;
  LayerTrack.TickStyle := tsNone;
  LayerTrack.OnChange := @TrackChanged;
  View := TSlicerView.Create(Self);
  View.Parent := Work; View.Align := alClient;
  View.Mode := svCamadas;
  View3D := TSlicerView3D.Create(Self);
  View3D.Parent := Work; View3D.Align := alClient;
  View3D.Scene := FScene;
  View3D.OnSelect := @View3DSelect;
  View3D.OnMoved := @View3DMoved;
  View3D.OnDelete := @View3DDelete;
  View3D.OnFacePicked := @FacePicked;
  View3D.OnBeforeMove := @BeforeMove;
  KeyPreview := True;
  OnKeyDown := @FormKey;

  FUpdating := False;
  OnResize := @ResizeUI;
  ReloadPrinters(ReadLastChoice('printer'));
  if PrinterBox.ItemIndex < 0 then PrinterBox.ItemIndex := 0;
  PrinterChange(nil);
  ReloadMaterials(ReadLastChoice('material'));
  if MaterialBox.ItemIndex < 0 then MaterialBox.ItemIndex := 0;
  MaterialChange(nil);

  { Inicializa marcas e modelos de impressora }
  if PrinterBrandBox <> nil then
  begin
    GetMachineBrands(PrinterBrandBox.Items);
    LastBrand := ReadLastChoice('printer_brand');
    LastModel := ReadLastChoice('printer_model');
    if (LastBrand <> '') and (PrinterBrandBox.Items.IndexOf(LastBrand) >= 0) then
      PrinterBrandBox.ItemIndex := PrinterBrandBox.Items.IndexOf(LastBrand)
    else if PrinterBrandBox.Items.Count > 0 then
      PrinterBrandBox.ItemIndex := 0;

    if PrinterBrandBox.ItemIndex >= 0 then
    begin
      GetMachineModels(PrinterBrandBox.Text, PrinterModelBox.Items);
      if (LastModel <> '') and (PrinterModelBox.Items.IndexOf(LastModel) >= 0) then
        PrinterModelBox.ItemIndex := PrinterModelBox.Items.IndexOf(LastModel)
      else if PrinterModelBox.Items.Count > 0 then
        PrinterModelBox.ItemIndex := 0;
    end;
  end;

  { Inicializa tipos, marcas e modelos de filamento }
  if FilamentKindBox <> nil then
  begin
    GetFilamentKinds(FilamentKindBox.Items);
    LastKind := ReadLastChoice('filament_kind');
    LastBrand := ReadLastChoice('filament_brand');
    LastModel := ReadLastChoice('filament_model');
    if (LastKind <> '') and (FilamentKindBox.Items.IndexOf(LastKind) >= 0) then
      FilamentKindBox.ItemIndex := FilamentKindBox.Items.IndexOf(LastKind)
    else if FilamentKindBox.Items.Count > 0 then
      FilamentKindBox.ItemIndex := 0;

    if FilamentKindBox.ItemIndex >= 0 then
    begin
      GetFilamentBrands(FilamentKindBox.Text, FilamentBrandBox.Items);
      if (LastBrand <> '') and (FilamentBrandBox.Items.IndexOf(LastBrand) >= 0) then
        FilamentBrandBox.ItemIndex := FilamentBrandBox.Items.IndexOf(LastBrand)
      else if FilamentBrandBox.Items.Count > 0 then
        FilamentBrandBox.ItemIndex := 0;

      if FilamentBrandBox.ItemIndex >= 0 then
      begin
        GetFilamentModels(FilamentKindBox.Text, FilamentBrandBox.Text, FilamentModelBox.Items);
        if (LastModel <> '') and (FilamentModelBox.Items.IndexOf(LastModel) >= 0) then
          FilamentModelBox.ItemIndex := FilamentModelBox.Items.IndexOf(LastModel)
        else if FilamentModelBox.Items.Count > 0 then
          FilamentModelBox.ItemIndex := 0;
      end;
    end;
  end;
  ReloadEquipment;
  SelectEquipment(ReadLastChoice('equipment'));
  ReloadQualities(ReadLastChoice('quality'));
  if QualityBox.ItemIndex < 0 then QualityBox.ItemIndex := FindQuality(FQualities, 'Normal');
  QualityChange(nil);
  ShowQualityMode(ReadLastChoice('quality_mode') = 'custom');
  FUpdating := True;
  try
    SupportModeBox.ItemIndex := EnsureRange(StrToIntDef(ReadLastChoice('support_mode'), 0), 0, 2);
    AdhesionTypeBox.ItemIndex := EnsureRange(StrToIntDef(ReadLastChoice('adhesion_type'), 1), 0, 3);
  finally
    FUpdating := False;
  end;
  InfillStr := ReadLastChoice('infill_percent');
  if InfillStr <> '' then
  begin
    InfillDensity.Value := EnsureRange(StrToIntDef(InfillStr, 20), 0, 100);
    InfillTrack.Position := InfillDensity.Value;
    InfillLabel.Caption := IntToStr(InfillDensity.Value) + '%';
  end;
  SyncRecommended;
  RefreshSupportAids;
  ShowViewMode(svMesa);
  ShowStep(1);
  SetState('Aguardando modelo', clSuiteWarning);
  RefreshModelInfo;
  FAskSave := True;
  FDirty := False;
  UpdateTitle;
end;

destructor TMultiSlicerForm.Destroy;
begin
  if View3D <> nil then View3D.Scene := nil;
  if View <> nil then View.SetSlice(nil, -1);
  Code.Free;
  Engine.Free;
  FMerged.Free;
  FScene.Free;
  inherited Destroy;
end;

procedure TMultiSlicerForm.BuildPrinterPage(S: TScrollBox);
var K: TExtruderKind;
begin
  EquipmentNote := LabelAt(S, 'O volume da impressora define a mesa da vista e a validacao.',
    16, 48, 290, 40);
  EquipmentNote.ShowHint := True;
  EquipmentNote.Name := 'EquipmentNote';

  Section(S, 'MARCA E MODELO', 92);
  PrinterBrandBox := Combo(S, 'Marca da impressora', 114);
  PrinterBrandBox.Name := 'PrinterBrandBox';
  PrinterBrandBox.OnChange := @PrinterBrandChange;
  PrinterModelBox := Combo(S, 'Modelo', 170);
  PrinterModelBox.Name := 'PrinterModelBox';
  PrinterModelBox.OnChange := @PrinterModelChange;
  CreatePrinterProfileBtn := Button(S, 'Criar perfil a partir do modelo...', 16, 226, 290, sikNew, @CreatePrinterProfileClick);
  CreatePrinterProfileBtn.Name := 'CreatePrinterProfileBtn';

  Section(S, 'PERFIL DE IMPRESSORA', 270);
  PrinterBox := Combo(S, 'Perfil cadastrado', 292);
  PrinterBox.OnChange := @PrinterChange;
  PrinterNote := LabelAt(S, '', 16, 346, 290, 20);
  Button(S, 'Salvar...', 16, 368, 140, sikSave, @SavePrinterClick);
  PrinterDeleteBtn := Button(S, 'Excluir', 166, 368, 140, sikTrash, @DeletePrinterClick);
  FlavorChoice := Combo(S, 'Firmware', 414);
  FlavorChoice.Items.Add('Marlin'); FlavorChoice.Items.Add('Klipper');
  FlavorChoice.ItemIndex := 0;
  FlavorChoice.OnChange := @SettingsChanged;
  ExtruderChoice := Combo(S, 'Extrusora', 472);
  for K := Low(TExtruderKind) to High(TExtruderKind) do ExtruderChoice.Items.Add(EXTRUDER_NAMES[K]);
  ExtruderChoice.ItemIndex := 0;
  ExtruderChoice.Name := 'Extruder';
  ExtruderChoice.OnChange := @ExtruderChange;
  BedX := FloatField(S, 'Mesa X (mm)', 'BedX', 220, 10, 2000, 1, 1, 530);
  BedY := FloatField(S, 'Mesa Y (mm)', 'BedY', 220, 10, 2000, 1, 1, 586);
  BedZ := FloatField(S, 'Altura maxima Z (mm)', 'BedZ', 250, 10, 2000, 1, 1, 642);
  Nozzle := FloatField(S, 'Diametro do bico (mm)', 'Nozzle', 0.4, 0.1, 2, 0.05, 2, 698);
  FilamentDia := FloatField(S, 'Diametro do filamento (mm)', 'FilamentDiameter', 1.75, 1, 3.5, 0.05, 2, 754);
  PrintStartZ := FloatField(S, 'Degrau inicial Z (mm)', 'PrintStartZ', 0, 0, 100, 0.1, 2, 810);
  HeatedBedBox := Check(S, 'Mesa aquecida', 868);
  HeatedBedBox.Checked := True;
  Section(S, 'G-CODE INICIAL', 906);
  StartMemo := TMemo.Create(Self);
  StartMemo.Parent := S; StartMemo.Name := 'StartGCode';
  StartMemo.SetBounds(16, 928, 290, 170);
  StartMemo.ScrollBars := ssAutoBoth; StartMemo.WordWrap := False;
  StartMemo.Font.Name := 'Courier New'; StartMemo.Font.Size := 9;
  StartMemo.Clear;
  StartMemo.OnChange := @SettingsChanged;
  Section(S, 'G-CODE FINAL', 1108);
  EndMemo := TMemo.Create(Self);
  EndMemo.Parent := S; EndMemo.Name := 'EndGCode';
  EndMemo.SetBounds(16, 1130, 290, 130);
  EndMemo.ScrollBars := ssAutoBoth; EndMemo.WordWrap := False;
  EndMemo.Font.Name := 'Courier New'; EndMemo.Font.Size := 9;
  EndMemo.Clear;
  EndMemo.OnChange := @SettingsChanged;
  LabelAt(S, 'Vazio = bloco padrao (aquece, G28, espera). Variaveis: {first_layer_bed_temp} {first_layer_hotend_temp} {bed_temp} {hotend_temp} {bed_x} {bed_y} {bed_z} {fan_speed}.',
    16, 1268, 290, 76);
end;

function TMultiSlicerForm.TransformField(AParent: TWinControl; const AText, AName: string;
  X, Y, W: Integer; MinV, MaxV, Step: Double; Decimals: Integer): TFloatSpinEdit;
begin
  LabelAt(AParent, AText, X, Y, W, 18);
  Result := TFloatSpinEdit.Create(Self);
  Result.Parent := AParent;
  Result.Name := AName;
  Result.SetBounds(X, Y + 20, W, 28);
  Result.DecimalPlaces := Decimals;
  Result.MinValue := MinV; Result.MaxValue := MaxV;
  Result.Increment := Step;
  Result.OnChange := @TransformChange;
end;

procedure TMultiSlicerForm.BuildModelPage(S: TScrollBox);
var B: TSuiteButton;
begin
  Button(S, 'Abrir modelo...', 16, 52, 290, sikFolder, @OpenClick).SetLook(sbsSolid, clSuitePrimary, sikFolder);
  LabelAt(S, 'Cada modelo entra num lugar livre da mesa, apoiado em Z = 0. Clique na peca (Ctrl soma) e arraste para mover.',
    16, 94, 290, 42);
  Section(S, 'PECAS', 146);
  Button(S, 'Duplicar', 16, 168, 140, sikCopy, @DuplicateClick);
  Button(S, 'Remover', 166, 168, 140, sikTrash, @RemoveClick);
  Button(S, 'Centralizar', 16, 210, 140, sikFit, @CenterClick);
  Button(S, 'Limpar mesa', 166, 210, 140, sikClose, @ClearClick);
  LabelAt(S, 'Copias ao duplicar', 16, 254, 140, 18);
  CopiesEd := TSpinEdit.Create(Self);
  CopiesEd.Parent := S; CopiesEd.Name := 'Copies';
  CopiesEd.SetBounds(16, 274, 140, 28);
  CopiesEd.MinValue := 1; CopiesEd.MaxValue := 100; CopiesEd.Value := 1;
  LockBox := TCheckBox.Create(Self);
  LockBox.Parent := S; LockBox.Name := 'LockPart';
  LockBox.SetBounds(166, 278, 140, 24);
  LockBox.Caption := 'Travar peca';
  LockBox.OnChange := @LockClick;
  Button(S, 'Organizar mesa', 16, 314, 290, sikWand, @ArrangeClick).Hint := 'Distribui as pecas destravadas a partir do centro';
  UndoBtn := Button(S, 'Desfazer', 16, 356, 140, sikUndo, @UndoClick);
  UndoBtn.Hint := 'Ctrl+Z';
  RedoBtn := Button(S, 'Refazer', 166, 356, 140, sikRedo, @RedoClick);
  RedoBtn.Hint := 'Ctrl+Y';
  TransformNote := LabelAt(S, '', 16, 400, 290, 20);
  TransformNote.Font.Style := [fsBold];

  Section(S, 'MOVER (CENTRO DA PECA)', 428);
  PosX := TransformField(S, 'X (mm)', 'PosX', 16, 450, 140, -5000, 5000, 1, 2);
  PosY := TransformField(S, 'Y (mm)', 'PosY', 166, 450, 140, -5000, 5000, 1, 2);

  Section(S, 'GIRAR (GRAUS)', 514);
  RotXEd := TransformField(S, 'X', 'RotX', 16, 536, 92, -360, 360, 15, 1);
  RotYEd := TransformField(S, 'Y', 'RotY', 115, 536, 92, -360, 360, 15, 1);
  RotZEd := TransformField(S, 'Z', 'RotZ', 214, 536, 92, -360, 360, 15, 1);
  B := Button(S, 'X +90', 16, 592, 92, sikRedo, @Rotate90Click); B.Tag := 0;
  B := Button(S, 'Y +90', 115, 592, 92, sikRedo, @Rotate90Click); B.Tag := 1;
  B := Button(S, 'Z +90', 214, 592, 92, sikRedo, @Rotate90Click); B.Tag := 2;
  Button(S, 'Deitar (auto)', 16, 634, 140, sikArrowDown, @LayFlatClick).Hint :=
    'Gira a peca para a maior face plana ficar apoiada na mesa';
  Button(S, 'Escolher face', 166, 634, 140, sikPointer, @PickFaceClick).Hint :=
    'Clique depois na face da peca que deve ficar apoiada na mesa';

  Section(S, 'ESCALAR', 686);
  UniformBox := TCheckBox.Create(Self);
  UniformBox.Parent := S; UniformBox.Name := 'UniformScale';
  UniformBox.SetBounds(16, 706, 290, 24);
  UniformBox.Caption := 'Uniforme (mantem a proporcao)';
  UniformBox.Checked := True;
  ScaleXP := TransformField(S, 'X (%)', 'ScaleXP', 16, 734, 140, 1, 10000, 5, 1);
  SizeX := TransformField(S, 'X (mm)', 'SizeX', 166, 734, 140, 0.01, 5000, 1, 2);
  ScaleYP := TransformField(S, 'Y (%)', 'ScaleYP', 16, 790, 140, 1, 10000, 5, 1);
  SizeY := TransformField(S, 'Y (mm)', 'SizeY', 166, 790, 140, 0.01, 5000, 1, 2);
  ScaleZP := TransformField(S, 'Z (%)', 'ScaleZP', 16, 846, 140, 1, 10000, 5, 1);
  SizeZ := TransformField(S, 'Z (mm)', 'SizeZ', 166, 846, 140, 0.01, 5000, 1, 2);

  B := Button(S, 'Polegadas para mm (x 25,4)', 16, 902, 290, sikGauge, @InchClick);
  B.Name := 'InchToMM';
  B.Hint := 'Para STL exportado em polegadas: multiplica a escala das pecas selecionadas por 25,4';

  Section(S, 'ESPELHAR', 952);
  B := Button(S, 'X', 16, 974, 92, sikMirrorH, @MirrorClick); B.Tag := 0;
  B := Button(S, 'Y', 115, 974, 92, sikMirrorV, @MirrorClick); B.Tag := 1;
  B := Button(S, 'Z', 214, 974, 92, sikMirrorV, @MirrorClick); B.Tag := 2;
  LabelAt(S, 'Os campos valem para a peca selecionada; girar 90, espelhar e deitar valem para todas as selecionadas. Desfazer vale para posicao, rotacao, escala e espelho.',
    16, 1020, 290, 76);
end;

procedure TMultiSlicerForm.BuildMaterialPage(S: TScrollBox);
begin
  Section(S, 'FILAMENTO POR MARCA E MODELO', 44);
  FilamentKindBox := Combo(S, 'Tipo (Polimero)', 66);
  FilamentKindBox.Name := 'FilamentKindBox';
  FilamentKindBox.OnChange := @FilamentKindChange;
  FilamentBrandBox := Combo(S, 'Marca do filamento', 124);
  FilamentBrandBox.Name := 'FilamentBrandBox';
  FilamentBrandBox.OnChange := @FilamentBrandChange;
  FilamentModelBox := Combo(S, 'Modelo comercial', 182);
  FilamentModelBox.Name := 'FilamentModelBox';
  FilamentModelBox.OnChange := @FilamentModelChange;

  Section(S, 'PERFIL DE MATERIAL', 240);
  MaterialBox := Combo(S, 'Perfil salvo', 262);
  MaterialBox.OnChange := @MaterialChange;
  MaterialNote := LabelAt(S, '', 16, 316, 290, 20);
  Button(S, 'Salvar...', 16, 338, 140, sikSave, @SaveMaterialClick);
  MaterialDeleteBtn := Button(S, 'Excluir', 166, 338, 140, sikTrash, @DeleteMaterialClick);
  MaterialNotes := LabelAt(S, '', 16, 380, 290, 58);
  Section(S, 'TEMPERATURAS', 446);
  HotendFirst := IntField(S, 'Bico na 1a camada (C)', 'HotendFirstLayer', 205, 0, 400, 468);
  Hotend := IntField(S, 'Bico nas demais camadas (C)', 'HotendTemperature', 200, 0, 400, 524);
  BedFirst := IntField(S, 'Mesa na 1a camada (C)', 'BedFirstLayer', 60, 0, 150, 580);
  BedTemp := IntField(S, 'Mesa nas demais camadas (C)', 'BedTemperature', 60, 0, 150, 636);
  Section(S, 'VENTOINHA', 702);
  FanPct := IntField(S, 'Ventoinha da peca (%)', 'FanPercent', 100, 0, 100, 724);
  FanLayer := IntField(S, 'Liga a partir da camada', 'FanFromLayer', 2, 1, 50, 780);
  Section(S, 'EXTRUSAO', 846);
  Flow := FloatField(S, 'Fluxo (%)', 'FlowPercent', 100, 50, 150, 1, 0, 868);
  RetractLen := FloatField(S, 'Retracao (mm)', 'RetractLength', 5, 0, 15, 0.1, 1, 924);
  RetractSpd := FloatField(S, 'Velocidade de retracao (mm/s)', 'RetractSpeed', 45, 5, 150, 1, 0, 980);
  Section(S, 'PESO E CUSTO', 1046);
  Density := FloatField(S, 'Densidade (g/cm3)', 'FilamentDensity', 1.24, 0.5, 3, 0.01, 2, 1068);
  Cost := FloatField(S, 'Preco do carretel (R$ por kg)', 'CostPerKg', 120, 0, 10000, 5, 2, 1124);
  LabelAt(S, 'A retracao vem do material conforme a extrusora da impressora (Bowden ou direta). Confira a faixa de temperatura no carretel.',
    16, 1186, 290, 60);
end;

procedure TMultiSlicerForm.BuildQualityPage(S: TScrollBox);
var Q: TQualityDefs; I: Integer;

  function Panel(H: Integer): TPanel;
  begin
    Result := TPanel.Create(Self);
    Result.Parent := S;
    Result.SetBounds(0, 96, 320, H);
    Result.BevelOuter := bvNone;
    Result.Color := clSuiteCard;
    Result.ParentColor := False;
  end;

begin
  ModeBtn[0] := Button(S, 'Recomendado', 16, 52, 140, sikWand, @ModeClick);
  ModeBtn[0].Tag := 0;
  ModeBtn[1] := Button(S, 'Personalizado', 166, 52, 140, sikGear, @ModeClick);
  ModeBtn[1].Tag := 1;

  { ---- modo recomendado (como no Cura) ---- }
  RecPanel := Panel(330);
  Section(RecPanel, 'QUALIDADE', 4);
  Q := BuiltinQualities;
  for I := 0 to 2 do
  begin
    QualityBtn[I] := Button(RecPanel, Q[I].Name, 16 + I * 99, 26, 92, sikLayers, @QualityCardClick);
    QualityBtn[I].Tag := I;
    QualityBtn[I].ClearIcon;   { sem icone o nome cabe no cartao }
    LabelAt(RecPanel, FormatFloat('0.0#', Q[I].LayerHeight, InvariantFS) + ' mm', 16 + I * 99, 64, 92, 18).Alignment := taCenter;
  end;
  QualityHint := LabelAt(RecPanel, '', 16, 88, 290, 40);
  Section(RecPanel, 'PREENCHIMENTO', 138);
  InfillTrack := TTrackBar.Create(Self);
  InfillTrack.Parent := RecPanel;
  InfillTrack.SetBounds(12, 160, 236, 36);
  InfillTrack.Min := 0; InfillTrack.Max := 100; InfillTrack.Frequency := 10;
  InfillTrack.Position := 20;
  InfillTrack.OnChange := @InfillTrackChange;
  InfillLabel := LabelAt(RecPanel, '20%', 254, 168, 52, 20);
  InfillLabel.Font.Style := [fsBold];
  SupportBox := TCheckBox.Create(Self);
  SupportBox.Parent := RecPanel;
  SupportBox.SetBounds(16, 206, 290, 24);
  SupportBox.Caption := 'Gerar suporte (hastes de apoio)';
  SupportBox.Name := 'SupportAuto';
  SupportBox.Hint := 'Suporte automatico sob as saliencias; detalhes na pagina Suportes';
  SupportBox.ShowHint := True;
  SupportBox.OnChange := @SupportBoxClick;
  AdhesionBox := TCheckBox.Create(Self);
  AdhesionBox.Parent := RecPanel; AdhesionBox.Name := 'Adhesion';
  AdhesionBox.SetBounds(16, 234, 290, 24);
  AdhesionBox.Caption := 'Aderencia a mesa (saia, aba ou jangada)';
  AdhesionBox.Checked := True;
  AdhesionBox.OnChange := @AdhesionClick;
  LabelAt(RecPanel, 'Escolha a qualidade e o preenchimento; o resto vem do perfil. Para ajustar cada valor use Personalizado.',
    16, 268, 290, 56);

  { ---- modo personalizado ---- }
  CustomPanel := Panel(1180);
  QualityBox := Combo(CustomPanel, 'Perfil de qualidade', 4);
  QualityBox.OnChange := @QualityChange;
  QualityNote := LabelAt(CustomPanel, '', 16, 58, 290, 20);
  Button(CustomPanel, 'Salvar...', 16, 80, 140, sikSave, @SaveQualityClick);
  QualityDeleteBtn := Button(CustomPanel, 'Excluir', 166, 80, 140, sikTrash, @DeleteQualityClick);
  Section(CustomPanel, 'CAMADAS', 128);
  LayerHeight := FloatField(CustomPanel, 'Altura de camada (mm)', 'LayerHeight', 0.2, 0.02, 1, 0.02, 2, 150);
  FirstLayerH := FloatField(CustomPanel, 'Altura da 1a camada (mm)', 'FirstLayerHeight', 0.2, 0.02, 1, 0.02, 2, 206);
  LineWidthP := FloatField(CustomPanel, 'Largura de linha (% do bico)', 'LineWidthPercent', 112.5, 60, 200, 2.5, 1, 262);
  Adaptive := Check(CustomPanel, 'Altura de camada adaptativa', 322);
  Section(CustomPanel, 'PAREDES E PREENCHIMENTO', 356);
  Walls := IntField(CustomPanel, 'Numero de paredes', 'Walls', 3, 1, 20, 378);
  TopLayers := IntField(CustomPanel, 'Camadas de topo', 'TopLayers', 4, 0, 50, 434);
  BottomLayers := IntField(CustomPanel, 'Camadas de fundo', 'BottomLayers', 3, 0, 50, 490);
  InfillDensity := IntField(CustomPanel, 'Preenchimento (%)', 'InfillDensity', 20, 0, 100, 546);
  PatternChoice := Combo(CustomPanel, 'Padrao de preenchimento', 602);
  PatternChoice.Items.Add('Gyroid'); PatternChoice.Items.Add('Retilineo');
  PatternChoice.ItemIndex := 0;
  PatternChoice.OnChange := @SettingsChanged;
  Section(CustomPanel, 'VELOCIDADES (MM/S)', 666);
  WallSpd := FloatField(CustomPanel, 'Paredes internas', 'WallSpeed', 50, 1, 1000, 5, 0, 688);
  OuterSpd := FloatField(CustomPanel, 'Parede externa', 'OuterWallSpeed', 30, 1, 1000, 5, 0, 744);
  InfillSpd := FloatField(CustomPanel, 'Preenchimento e topo/fundo', 'InfillSpeed', 70, 1, 1000, 5, 0, 800);
  FirstSpd := FloatField(CustomPanel, '1a camada', 'FirstLayerSpeed', 20, 1, 1000, 1, 0, 856);
  TravelSpd := FloatField(CustomPanel, 'Deslocamento', 'TravelSpeed', 150, 1, 1000, 10, 0, 912);
  Section(CustomPanel, 'AVANCADO', 976);
  ArcFit := Check(CustomPanel, 'Arcos G2/G3 nos perimetros', 998);
  ArcFit.Checked := True;
  ZHopEd := FloatField(CustomPanel, 'Z-hop na retracao (mm, 0 = sem)', 'ZHop', 0, 0, 10, 0.1, 2, 1026);
  PAEd := FloatField(CustomPanel, 'Pressure/linear advance (0 = sem)', 'PressureAdvance', 0, 0, 2, 0.01, 3, 1082);
  LabelAt(CustomPanel, 'A Ender-3 original (Marlin) costuma vir sem linear advance; deixe 0 se nao calibrou.',
    16, 1140, 290, 40);
end;

procedure TMultiSlicerForm.BuildSupportPage(S: TScrollBox);

  function BlkField(const AText, AName: string; X, Y: Integer; MinV: Double): TFloatSpinEdit;
  begin
    LabelAt(S, AText, X, Y, 92, 18);
    Result := TFloatSpinEdit.Create(Self);
    Result.Parent := S; Result.Name := AName;
    Result.SetBounds(X, Y + 20, 92, 28);
    Result.DecimalPlaces := 1; Result.MinValue := MinV; Result.MaxValue := 2000; Result.Increment := 1;
    Result.OnChange := @BlockerFieldChange;
  end;

begin
  Section(S, 'SUPORTES (HASTES DE APOIO)', 52);
  SupportModeBox := Combo(S, 'Suporte', 74);
  SupportModeBox.Name := 'SupportMode';
  SupportModeBox.Items.Add('Desligado');
  SupportModeBox.Items.Add('Automatico (saliencias + hastes)');
  SupportModeBox.Items.Add('Somente hastes manuais');
  SupportModeBox.ItemIndex := 0;
  SupportModeBox.OnChange := @SupportSettingsChanged;
  SupportWhereBox := Combo(S, 'Onde apoiar', 132);
  SupportWhereBox.Name := 'SupportWhere';
  SupportWhereBox.Items.Add('Somente tocando a mesa');
  SupportWhereBox.Items.Add('Em toda parte (tambem sobre a peca)');
  SupportWhereBox.ItemIndex := 0;
  SupportWhereBox.OnChange := @SupportSettingsChanged;
  SupportAngle := FloatField(S, 'Angulo de saliencia (graus da vertical)', 'SupportAngle', 50, 0, 89, 5, 0, 190);
  SupportAngle.OnChange := @SupportSettingsChanged;
  ShowOverhangsBox := Check(S, 'Mostrar saliencias em vermelho na vista', 248);
  ShowOverhangsBox.Name := 'ShowOverhangs';
  ShowOverhangsBox.Checked := True;
  ShowOverhangsBox.OnChange := @SupportSettingsChanged;
  SupportDens := IntField(S, 'Densidade do suporte (%)', 'SupportDensity', 15, 3, 100, 280);
  SupportXY := FloatField(S, 'Distancia XY da peca (mm)', 'SupportXYGap', 0.7, 0, 5, 0.1, 2, 336);
  SupportZ := FloatField(S, 'Distancia Z da peca (mm)', 'SupportZGap', 0.2, 0, 2, 0.05, 2, 392);
  SupportIfc := IntField(S, 'Camadas de interface (densas)', 'SupportInterface', 2, 0, 10, 448);
  SupportSpd := FloatField(S, 'Velocidade do suporte (mm/s)', 'SupportSpeed', 50, 5, 300, 5, 0, 504);

  Section(S, 'HASTES MANUAIS', 570);
  PillarDia := FloatField(S, 'Diametro da haste (mm)', 'PillarDiameter', 3, 1, 20, 0.5, 1, 592);
  Button(S, 'Adicionar hastes', 16, 652, 140, sikPointer, @AddPillarClick).Hint :=
    'Clique na vista sob as partes salientes da peca; Esc termina';
  Button(S, 'Limpar hastes', 166, 652, 140, sikTrash, @ClearPillarsClick);
  PillarInfo := LabelAt(S, 'Nenhuma haste.', 16, 692, 290, 36);

  Section(S, 'BLOQUEADORES DE SUPORTE', 736);
  BlockerBox := Combo(S, 'Caixas onde o suporte automatico nao e gerado', 758);
  BlockerBox.OnChange := @BlockerSelect;
  Button(S, 'Adicionar', 16, 816, 140, sikRect, @AddBlockerClick).Hint := 'Na peca selecionada (ou no centro da mesa)';
  Button(S, 'Remover', 166, 816, 140, sikTrash, @RemoveBlockerClick);
  BlkX := BlkField('Centro X', 'BlockerX', 16, 858, -2000);
  BlkY := BlkField('Centro Y', 'BlockerY', 115, 858, -2000);
  BlkH := BlkField('Altura', 'BlockerH', 214, 858, 0.1);
  BlkW := BlkField('Largura X', 'BlockerW', 16, 914, 0.1);
  BlkD := BlkField('Profund. Y', 'BlockerD', 115, 914, 0.1);

  Section(S, 'ADERENCIA A MESA', 984);
  AdhesionTypeBox := Combo(S, 'Tipo', 1006);
  AdhesionTypeBox.Name := 'AdhesionType';
  AdhesionTypeBox.Items.Add('Nenhuma');
  AdhesionTypeBox.Items.Add('Saia (contorno afastado)');
  AdhesionTypeBox.Items.Add('Aba / brim (abas grudadas na peca)');
  AdhesionTypeBox.Items.Add('Jangada / raft (base embaixo da peca)');
  AdhesionTypeBox.ItemIndex := 1;
  AdhesionTypeBox.OnChange := @SupportSettingsChanged;
  SkirtLoops := IntField(S, 'Voltas de saia', 'SkirtLoops', 1, 0, 20, 1064);
  SkirtDist := FloatField(S, 'Distancia da saia (mm)', 'SkirtDistance', 3, 0.5, 50, 0.5, 1, 1120);
  BrimWidthEd := FloatField(S, 'Largura da aba (mm)', 'BrimWidth', 8, 1, 50, 1, 1, 1176);
  RaftMarginEd := FloatField(S, 'Margem da jangada (mm)', 'RaftMargin', 3, 1, 30, 0.5, 1, 1232);
  RaftGapEd := FloatField(S, 'Folga entre jangada e peca (mm)', 'RaftAirGap', 0.2, 0, 1, 0.05, 2, 1288);
  LabelAt(S, 'Ender-3 com mesa limpa: saia basta. Pecas altas e finas ou com cantos que levantam: aba. Mesa irregular: jangada.',
    16, 1348, 290, 56);
end;

procedure TMultiSlicerForm.BuildPreviewPage(S: TScrollBox);
begin
  Button(S, 'Fatiar e visualizar', 16, 52, 290, sikLayers, @SliceClick).SetLook(sbsSolid, clSuitePrimary, sikLayers);
  LayerChoice := IntField(S, 'Camada', 'LayerChoice', 1, 1, 1, 100);
  LayerChoice.OnChange := @LayerChanged;
  OnlyLayerBox := Check(S, 'So a camada escolhida', 160);
  OnlyLayerBox.Name := 'OnlyLayer';
  OnlyLayerBox.OnChange := @PreviewOptionChange;
  TravelsBox := Check(S, 'Mostrar deslocamentos da camada', 186);
  TravelsBox.Name := 'ShowTravels';
  TravelsBox.OnChange := @PreviewOptionChange;
  Preview2DBox := Check(S, 'Vista 2D (camada vista de cima)', 212);
  Preview2DBox.Name := 'Preview2D';
  Preview2DBox.OnChange := @PreviewOptionChange;
  PreviewSummary := LabelAt(S, 'Fatie para ver tempo, filamento e camadas.', 16, 248, 290, 300);
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
  Section(S, 'PROJETO (.MSLICE)', 680);
  Button(S, 'Novo', 16, 702, 140, sikNew, @NewProjectClick).Hint := 'Limpa a mesa e comeca um projeto novo';
  Button(S, 'Abrir...', 166, 702, 140, sikFolder, @OpenProjectClick).Hint := 'Abrir projeto .mslice (Ctrl+O tambem abre)';
  Button(S, 'Salvar', 16, 744, 140, sikSave, @SaveProjectClick).Hint := 'Salvar o projeto (Ctrl+S)';
  Button(S, 'Salvar como...', 166, 744, 140, sikSave, @SaveProjectAsClick);
  LabelAt(S, 'O projeto guarda as pecas (aponta para os STL/3MF) com a posicao, as hastes, os bloqueadores, impressora, material, qualidade, suporte e aderencia.',
    16, 790, 290, 80);
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
  if E is EAbort then Exit;   { cancelado: a mensagem ja foi dada }
  Status.Caption := E.Message;
  if Log <> nil then Log.Lines.Add('Erro: ' + E.Message);
  SetState('Verifique o trabalho', clSuiteDanger);
end;

{ ---------------- projeto .mslice ---------------- }

procedure TMultiSlicerForm.UpdateTitle;
var Base: string; K: Integer;
begin
  Base := Caption;
  K := Pos(' - ', Base);
  if K > 0 then Base := Copy(Base, 1, K - 1);
  if FProjectFile <> '' then
  begin
    Caption := Base + ' - ' + ChangeFileExt(ExtractFileName(FProjectFile), '');
    if FDirty then Caption := Caption + ' *';
  end
  else if FDirty and (FScene.Count > 0) then
    Caption := Base + ' - sem nome *'
  else
    Caption := Base;
end;

function TMultiSlicerForm.ConfirmDiscard: Boolean;
begin
  Result := True;
  if not FAskSave or not FDirty or (FScene.Count = 0) then Exit;
  case MessageDlg('MultiSlicer', 'O projeto tem alteracoes nao salvas. Salvar antes?',
    mtConfirmation, [mbYes, mbNo, mbCancel], 0) of
    mrYes:
      begin
        SaveProjectClick(nil);
        Result := not FDirty;    { cancelou o dialogo de salvar }
      end;
    mrNo: Result := True;
  else
    Result := False;
  end;
end;

function TMultiSlicerForm.ProjectSettingsJSON: TJSONObject;
var P, M, Q, Sup, Adh: TJSONObject;
begin
  Result := TJSONObject.Create;
  if EquipmentBox.ItemIndex > 0 then Result.Add('equipment', EquipmentBox.Text)
  else Result.Add('equipment', '');
  P := PrinterToJSON(CurrentPrinter);
  if (PrinterBox.ItemIndex >= 0) and (PrinterBox.ItemIndex <= High(FPrinters)) then
    P.Add('profile', FPrinters[PrinterBox.ItemIndex].Name);
  Result.Add('printer', P);
  M := MaterialToJSON(CurrentMaterial);
  if (MaterialBox.ItemIndex >= 0) and (MaterialBox.ItemIndex <= High(FMaterials)) then
    M.Add('profile', FMaterials[MaterialBox.ItemIndex].Name);
  Result.Add('material', M);
  Q := QualityToJSON(CurrentQuality);
  if (QualityBox.ItemIndex >= 0) and (QualityBox.ItemIndex <= High(FQualities)) then
    Q.Add('profile', FQualities[QualityBox.ItemIndex].Name);
  Q.Add('custom_mode', CustomPanel.Visible);
  Result.Add('quality', Q);
  Sup := TJSONObject.Create;
  Sup.Add('mode', SupportModeBox.ItemIndex);
  Sup.Add('where', SupportWhereBox.ItemIndex);
  Sup.Add('angle', SupportAngle.Value);
  Sup.Add('density', SupportDens.Value);
  Sup.Add('xy_gap', SupportXY.Value);
  Sup.Add('z_gap', SupportZ.Value);
  Sup.Add('interface_layers', SupportIfc.Value);
  Sup.Add('speed', SupportSpd.Value);
  Sup.Add('pillar_diameter', PillarDia.Value);
  Sup.Add('show_overhangs', ShowOverhangsBox.Checked);
  Result.Add('support', Sup);
  Adh := TJSONObject.Create;
  Adh.Add('type', AdhesionTypeBox.ItemIndex);
  Adh.Add('skirt_loops', SkirtLoops.Value);
  Adh.Add('skirt_distance', SkirtDist.Value);
  Adh.Add('brim_width', BrimWidthEd.Value);
  Adh.Add('raft_margin', RaftMarginEd.Value);
  Adh.Add('raft_gap', RaftGapEd.Value);
  Result.Add('adhesion', Adh);
end;

procedure TMultiSlicerForm.ApplyProjectSettings(O: TJSONObject);
var E: TJSONObject; K: Integer;
  function Sub(const Key: string): TJSONObject;
  begin
    if O.Find(Key) is TJSONObject then Result := TJSONObject(O.Find(Key)) else Result := nil;
  end;
begin
  { equipamento primeiro (troca o perfil de impressora), depois os valores
    gravados no projeto, que prevalecem }
  SelectEquipment(JStr(O, 'equipment', ''));
  E := Sub('printer');
  if E <> nil then
  begin
    if EquipmentBox.ItemIndex <= 0 then
    begin
      K := FindPrinter(FPrinters, JStr(E, 'profile', ''));
      if K >= 0 then begin PrinterBox.ItemIndex := K; PrinterChange(nil); end;
    end;
    ApplyPrinter(PrinterFromJSON(E));
  end;
  E := Sub('material');
  if E <> nil then
  begin
    K := FindMaterial(FMaterials, JStr(E, 'profile', ''));
    if K >= 0 then begin MaterialBox.ItemIndex := K; MaterialChange(nil); end;
    ApplyMaterial(MaterialFromJSON(E));
  end;
  E := Sub('quality');
  if E <> nil then
  begin
    K := FindQuality(FQualities, JStr(E, 'profile', ''));
    if K >= 0 then begin QualityBox.ItemIndex := K; QualityChange(nil); end;
    ApplyQuality(QualityFromJSON(E));
    ShowQualityMode(JBool(E, 'custom_mode', False));
  end;
  FUpdating := True;
  try
    E := Sub('support');
    if E <> nil then
    begin
      SupportModeBox.ItemIndex := EnsureRange(JInt(E, 'mode', 0), 0, 2);
      SupportWhereBox.ItemIndex := EnsureRange(JInt(E, 'where', 0), 0, 1);
      SupportAngle.Value := JFloat(E, 'angle', 50);
      SupportDens.Value := JInt(E, 'density', 15);
      SupportXY.Value := JFloat(E, 'xy_gap', 0.7);
      SupportZ.Value := JFloat(E, 'z_gap', 0.2);
      SupportIfc.Value := JInt(E, 'interface_layers', 2);
      SupportSpd.Value := JFloat(E, 'speed', 50);
      PillarDia.Value := JFloat(E, 'pillar_diameter', 3);
      ShowOverhangsBox.Checked := JBool(E, 'show_overhangs', False);
    end;
    E := Sub('adhesion');
    if E <> nil then
    begin
      AdhesionTypeBox.ItemIndex := EnsureRange(JInt(E, 'type', 1), 0, 3);
      SkirtLoops.Value := JInt(E, 'skirt_loops', 1);
      SkirtDist.Value := JFloat(E, 'skirt_distance', 3);
      BrimWidthEd.Value := JFloat(E, 'brim_width', 8);
      RaftMarginEd.Value := JFloat(E, 'raft_margin', 3);
      RaftGapEd.Value := JFloat(E, 'raft_gap', 0.2);
    end;
  finally
    FUpdating := False;
  end;
  SyncRecommended;
  RefreshSupportAids;
end;

procedure TMultiSlicerForm.NewProject;
begin
  if FSlicing then Exit;
  FScene.Clear;
  FScene.ClearHistory;
  FProjectFile := '';
  SourceFile := '';
  SceneChanged('Projeto novo: abra um modelo STL ou 3MF.');
  FDirty := False;
  UpdateTitle;
  RefreshModelInfo;
  SetState('Aguardando modelo', clSuiteWarning);
end;

procedure TMultiSlicerForm.OpenProject(const FN: string);
var Missing: TStringList; Sets: TJSONObject; Msg: string;
begin
  if FSlicing then Exit;
  Missing := TStringList.Create;
  FLoadingProject := True;
  try
    Sets := LoadProject(FN, FScene, Missing);
    try
      ApplyProjectSettings(Sets);
    finally
      Sets.Free;
    end;
    FProjectFile := ExpandFileName(FN);
    if FScene.Count > 0 then SourceFile := FScene[0].SourceFile else SourceFile := '';
    Msg := Format('Projeto aberto: %s (%d pecas).', [ExtractFileName(FN), FScene.Count]);
    if Missing.Count > 0 then
      Msg := Msg + ' Modelos nao encontrados: ' + StringReplace(Trim(Missing.Text), LineEnding, ', ', [rfReplaceAll]);
    FScene.BedX := BedX.Value; FScene.BedY := BedY.Value; FScene.BedZ := BedZ.Value;
    SceneChanged(Msg);
    View3D.FitBed;
    Log.Lines.Add(Msg);
  finally
    FLoadingProject := False;
    Missing.Free;
  end;
  FDirty := False;
  UpdateTitle;
  RefreshModelInfo;
end;

procedure TMultiSlicerForm.SaveProjectAs(const FN: string);
var Sets: TJSONObject; PName: string;
begin
  PName := FN;
  if ExtractFileExt(PName) = '' then PName := PName + MSLICE_EXT;
  Sets := ProjectSettingsJSON;
  try
    SaveProject(PName, FScene, Sets);
  finally
    Sets.Free;
  end;
  FProjectFile := ExpandFileName(PName);
  FDirty := False;
  UpdateTitle;
  Status.Caption := 'Projeto salvo: ' + FProjectFile;
  Log.Lines.Add('Projeto salvo: ' + FProjectFile);
end;

procedure TMultiSlicerForm.ConvertInches;
var I, N: Integer; O: TSliceObject;
begin
  N := 0;
  FScene.PushUndo; FUndoKey := '';
  for I := 0 to FScene.Count - 1 do
    if FScene[I].Selected or ((FScene.SelectedCount = 0) and (FScene.Count = 1)) then
    begin
      O := FScene[I];
      O.ScaleX := O.ScaleX * INCH_TO_MM;
      O.ScaleY := O.ScaleY * INCH_TO_MM;
      O.ScaleZ := O.ScaleZ * INCH_TO_MM;
      if not FScene.Inside(I) then FScene.CenterObject(I);
      Inc(N);
    end;
  if N = 0 then begin Status.Caption := 'Selecione a peca a converter.'; Exit; end;
  FScene.Touch;
  LoadTransformEditor;
  SceneChanged(Format('%d peca(s) convertida(s) de polegadas para mm (x 25,4).', [N]));
end;

procedure TMultiSlicerForm.InchClick(Sender: TObject);
begin
  ConvertInches;
end;

procedure TMultiSlicerForm.DropFiles(const FileNames: array of string);
var I, N: Integer; Ext: string;
begin
  if FSlicing then Exit;
  N := 0;
  for I := 0 to High(FileNames) do
  begin
    Ext := LowerCase(ExtractFileExt(FileNames[I]));
    try
      if Ext = MSLICE_EXT then
      begin
        if ConfirmDiscard then OpenProject(FileNames[I]);
        Exit;   { um projeto substitui a mesa inteira }
      end
      else if (Ext = '.stl') or (Ext = '.3mf') then
      begin
        OpenFile(FileNames[I]);
        Inc(N);
      end
      else
        Log.Lines.Add('Ignorado (nao e STL, 3MF nem .mslice): ' + FileNames[I]);
    except
      on E: Exception do ShowError(E);
    end;
  end;
  if N > 0 then ShowStep(1);
end;

procedure TMultiSlicerForm.FormDropFiles(Sender: TObject; const FileNames: array of string);
begin
  DropFiles(FileNames);
end;

procedure TMultiSlicerForm.NewProjectClick(Sender: TObject);
begin
  if ConfirmDiscard then NewProject;
end;

procedure TMultiSlicerForm.OpenProjectClick(Sender: TObject);
var D: TOpenDialog;
begin
  if not ConfirmDiscard then Exit;
  D := TOpenDialog.Create(Self);
  try
    D.Filter := 'Projeto MultiSlicer (*.mslice)|*.mslice';
    D.Options := [ofFileMustExist, ofEnableSizing];
    if FProjectFile <> '' then D.InitialDir := ExtractFilePath(FProjectFile);
    if D.Execute then
    try
      OpenProject(D.FileName);
      ShowStep(1);
    except
      on E: Exception do ShowError(E);
    end;
  finally
    D.Free;
  end;
end;

procedure TMultiSlicerForm.SaveProjectClick(Sender: TObject);
begin
  if FProjectFile = '' then SaveProjectAsClick(Sender)
  else
    try
      SaveProjectAs(FProjectFile);
    except
      on E: Exception do ShowError(E);
    end;
end;

procedure TMultiSlicerForm.SaveProjectAsClick(Sender: TObject);
var D: TSaveDialog;
begin
  D := TSaveDialog.Create(Self);
  try
    D.Filter := 'Projeto MultiSlicer (*.mslice)|*.mslice';
    D.DefaultExt := 'mslice';
    if FProjectFile <> '' then
    begin
      D.FileName := ExtractFileName(FProjectFile);
      D.InitialDir := ExtractFilePath(FProjectFile);
    end
    else if SourceFile <> '' then
    begin
      D.FileName := ChangeFileExt(ExtractFileName(SourceFile), MSLICE_EXT);
      D.InitialDir := ExtractFilePath(SourceFile);
    end;
    D.Options := [ofOverwritePrompt, ofPathMustExist, ofEnableSizing];
    if D.Execute then
    try
      SaveProjectAs(D.FileName);
    except
      on E: Exception do ShowError(E);
    end;
  finally
    D.Free;
  end;
end;

procedure TMultiSlicerForm.HeaderResize(Sender: TObject);
begin
  if (EquipmentBox <> nil) and (FHeader <> nil) then
    EquipmentBox.Left := FHeader.ClientWidth - EquipmentBox.Width - 18;
end;

procedure TMultiSlicerForm.ReloadEquipment;
var
  Store: TEquipmentStore;
  I: Integer;
  E: TEquipmentProfile;
begin
  FEquipment := nil;
  if EquipmentFileOverride <> '' then Store := TEquipmentStore.Create(EquipmentFileOverride)
  else Store := TEquipmentStore.Create(EquipmentFileName);
  try
    try
      Store.Load;
      for I := 0 to Store.Count - 1 do
      begin
        E := Store.Item(I);
        if E.MachineType <> mtPrinter3D then Continue;
        SetLength(FEquipment, Length(FEquipment) + 1);
        FEquipment[High(FEquipment)] := E;
      end;
    except
      { cadastro ausente ou ilegivel: so o ajuste manual }
      FEquipment := nil;
    end;
  finally
    Store.Free;
  end;
  FUpdating := True;
  try
    EquipmentBox.Items.Clear;
    EquipmentBox.Items.Add('Ajuste manual');
    for I := 0 to High(FEquipment) do EquipmentBox.Items.Add(FEquipment[I].Name);
    EquipmentBox.ItemIndex := 0;
  finally
    FUpdating := False;
  end;
end;

procedure TMultiSlicerForm.SelectEquipment(const AName: string);
var I: Integer;
begin
  I := 0;
  if AName <> '' then
    I := EquipmentBox.Items.IndexOf(AName);
  if I < 0 then I := 0;
  EquipmentBox.ItemIndex := I;
  EquipmentChange(nil);
end;

procedure TMultiSlicerForm.EquipmentChange(Sender: TObject);
var
  K, M: Integer;
  E: TEquipmentProfile;
  P: TPrinterDef;
  Port, Info: string;
begin
  if FUpdating then Exit;
  K := EquipmentBox.ItemIndex - 1;
  if (K < 0) or (K > High(FEquipment)) then
  begin
    { ajuste manual: volta ao ultimo perfil escolhido a mao }
    FHasMachine := False;
    FHasEquipPrinter := False;
    ReloadPrinters(ReadLastChoice('printer'));
    if PrinterBox.ItemIndex < 0 then PrinterBox.ItemIndex := 0;
    PrinterChange(nil);
    EquipmentNote.Caption := 'O volume da impressora define a mesa da vista e a validacao.';
    EquipmentNote.Hint := '';
    EquipmentNote.Font.Color := clSuiteMuted;
    if Sender <> nil then WriteLastChoice('equipment', '');
    Exit;
  end;
  E := FEquipment[K];
  M := FindMachine(E.Brand, E.Model);
  FHasMachine := M >= 0;
  if FHasMachine then
  begin
    FMachine := MachineCatalog[M];
    P := MachinePrinterDef(FMachine, E.Name, E.WorkX, E.WorkY, E.WorkZ);
  end
  else
  begin
    { modelo fora do catalogo: usa o perfil atual e so troca nome e mesa }
    P := CurrentPrinter;
    P.Name := E.Name;
    if E.WorkX > 0 then P.BedX := E.WorkX;
    if E.WorkY > 0 then P.BedY := E.WorkY;
    if E.WorkZ > 0 then P.BedZ := E.WorkZ;
    P.BuiltIn := True;
  end;
  FEquipPrinter := P;
  FHasEquipPrinter := True;
  ReloadPrinters(P.Name);
  PrinterChange(nil);
  { retracao propria do modelo (Cura), quando ele define }
  if FHasMachine and (FMachine.RetractLen > 0) then
  begin
    FUpdating := True;
    try
      RetractLen.Value := FMachine.RetractLen;
      RetractSpd.Value := FMachine.RetractSpeed;
    finally
      FUpdating := False;
    end;
  end;
  { a porta e do MultiCNC: aqui so se gera o arquivo }
  if E.SerialPort <> '' then Port := 'porta ' + E.SerialPort
  else if E.Host <> '' then Port := E.Host + ':' + IntToStr(E.TCPPort)
  else Port := 'sem porta';
  Info := Trim(E.Brand + ' ' + E.Model);
  if Info = '' then Info := 'Marca/modelo nao informados';
  EquipmentNote.Caption := Info + LineEnding + Port + ' (usada pelo MultiCNC)';
  if FHasMachine then
  begin
    EquipmentNote.Font.Color := clSuiteSuccess;
    EquipmentNote.Hint := Format('%s %s%s' +
      'Area %.0f x %.0f x %.0f mm, bico %.2f, filamento %.2f, extrusora %s%s' +
      'Bico ate %.0f C, mesa ate %.0f C, nivelamento: %s%s' +
      'Velocidade recomendada %.0f mm/s, maxima %.0f mm/s%s' +
      'Fonte: %s',
      [FMachine.Brand, FMachine.Model, LineEnding,
       P.BedX, P.BedY, P.BedZ, P.Nozzle, P.FilamentDiameter, EXTRUDER_NAMES[P.Extruder], LineEnding,
       FMachine.MaxHotend, FMachine.MaxBed, FMachine.LevelingName, LineEnding,
       FMachine.PrintSpeed, FMachine.MaxSpeed, LineEnding, FMachine.Source]);
    Log.Lines.Add('Equipamento: ' + E.Name + ' = ' + FMachine.Brand + ' ' + FMachine.Model +
      ' (' + FMachine.Source + ')');
  end
  else
  begin
    EquipmentNote.Font.Color := clSuiteWarning;
    EquipmentNote.Hint := 'Modelo fora do catalogo: confira bico, extrusora e G-code.';
    EquipmentNote.Caption := EquipmentNote.Caption + ' - fora do catalogo';
  end;
  if Sender <> nil then WriteLastChoice('equipment', E.Name);
  SettingsChanged(nil);
end;

procedure TMultiSlicerForm.MachineChecks(Errors, Warnings: TStrings);
var Fastest: Double;
begin
  if not FHasMachine then Exit;
  if Max(HotendFirst.Value, Hotend.Value) > FMachine.MaxHotend then
    Errors.Add(Format('Temperatura do bico acima do limite da %s (%.0f C).', [FMachine.Model, FMachine.MaxHotend]));
  if HeatedBedBox.Checked and (Max(BedFirst.Value, BedTemp.Value) > FMachine.MaxBed) then
    Errors.Add(Format('Temperatura da mesa acima do limite da %s (%.0f C).', [FMachine.Model, FMachine.MaxBed]));
  Fastest := Max(Max(WallSpd.Value, OuterSpd.Value), InfillSpd.Value);
  if (FMachine.MaxSpeed > 0) and (Fastest > FMachine.MaxSpeed) then
    Warnings.Add(Format('Velocidade de %.0f mm/s acima da maxima da %s (%.0f mm/s).',
      [Fastest, FMachine.Model, FMachine.MaxSpeed]));
end;

procedure TMultiSlicerForm.ResizeUI(Sender: TObject);
begin
  if FooterPanel = nil then Exit;
  SendButton.Left := FooterPanel.ClientWidth - SendButton.Width - 18;
  ExportBtn.Left := SendButton.Left - ExportBtn.Width - 10;
  SliceBtn.Left := ExportBtn.Left - SliceBtn.Width - 10;
  ValidateButton.Left := SliceBtn.Left - ValidateButton.Width - 10;
  CancelBtn.Left := SliceBtn.Left;
  Status.Width := Max(120, ValidateButton.Left - 30);
  SliceProgress.Width := Status.Width;
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
var I: Integer; Use2D: Boolean;
begin
  View.Mode := svCamadas;
  { camadas: previa 3D (como no Cura); a 2D continua como opcao }
  Use2D := (AMode = svCamadas) and (Preview2DBox <> nil) and Preview2DBox.Checked;
  View3D.PreviewMode := AMode = svCamadas;
  View3D.Visible := not Use2D;
  View.Visible := Use2D;
  for I := 0 to High(ViewButtons) do ViewButtons[I].Visible := not Use2D;
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
  { mantem o modo para quem consulta View.Mode }
  if AMode = svMesa then View.Tag := 0 else View.Tag := 1;
  LayerLabel.Visible := LayerTrack.Visible;
  { deslizante de camada numa segunda linha da barra }
  if LayerTrack.Visible then ViewBar.Height := 90 else ViewBar.Height := 52;
end;

procedure TMultiSlicerForm.PreviewOptionChange(Sender: TObject);
begin
  View3D.OnlyLayer := OnlyLayerBox.Checked;
  View3D.ShowTravels := TravelsBox.Checked;
  if View.Tag = 1 then ShowViewMode(svCamadas);
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
  if View3D.Visible then View3D.FitBed else View.FitView;
end;

procedure TMultiSlicerForm.ZoomInClick(Sender: TObject);
begin
  if View3D.Visible then View3D.ZoomBy(1.25) else View.ZoomIn;
end;

procedure TMultiSlicerForm.ZoomOutClick(Sender: TObject);
begin
  if View3D.Visible then View3D.ZoomBy(1 / 1.25) else View.ZoomOut;
end;

procedure TMultiSlicerForm.RefreshModelInfo;
var B: TBox3; Sz: TVec3; K: Integer;
begin
  if FScene.Count = 0 then
  begin
    ModelInfo.Caption := 'Nenhum modelo na mesa.';
    Coords.Caption := '';
    Exit;
  end;
  K := FScene.FirstSelected;
  if (K >= 0) and (FScene.SelectedCount = 1) then
  begin
    Sz := FScene[K].Size;
    B := FScene[K].WorldBox;
    ModelInfo.Caption := Format('%s'#10'%d triangulos'#10'%.1f x %.1f x %.1f mm'#10'centro X %.1f  Y %.1f',
      [FScene[K].Name, FScene[K].Source.Count, Sz.X, Sz.Y, Sz.Z, (B.Min.X + B.Max.X) / 2,
       (B.Min.Y + B.Max.Y) / 2], InvariantFS);
  end
  else
    ModelInfo.Caption := Format('%d peca(s), %d selecionada(s)'#10'%d triangulos',
      [FScene.Count, FScene.SelectedCount, FScene.TriangleCount]);
  B := FScene.Bounds;
  Coords.Caption := Format('%d peca(s)  |  conjunto %.1f x %.1f x %.1f mm  |  mesa %.0f x %.0f x %.0f mm',
    [FScene.Count, B.Max.X - B.Min.X, B.Max.Y - B.Min.Y, B.Max.Z - B.Min.Z, BedX.Value, BedY.Value,
     BedZ.Value], InvariantFS);
end;

procedure TMultiSlicerForm.RefreshObjectList;
var I: Integer;
begin
  if ObjectList = nil then Exit;
  FUpdating := True;
  try
    ObjectList.Items.BeginUpdate;
    try
      ObjectList.Items.Clear;
      for I := 0 to FScene.Count - 1 do
        ObjectList.Items.Add(FScene[I].Name);
    finally
      ObjectList.Items.EndUpdate;
    end;
    { a selecao so vale depois do EndUpdate (GTK2) }
    for I := 0 to FScene.Count - 1 do
      ObjectList.Selected[I] := FScene[I].Selected;
  finally
    FUpdating := False;
  end;
end;

procedure TMultiSlicerForm.SceneChanged(const Msg: string);
begin
  RefreshObjectList;
  if (PillarInfo <> nil) and not FUpdating then RefreshSupportAids;
  if not FUpdating then LoadTransformEditor;
  SettingsChanged(nil);
  View3D.Redraw;
  if Msg <> '' then Status.Caption := Msg;
  SliceBtn.Enabled := FScene.Count > 0;
  ExportBtn.Enabled := FScene.Count > 0;
end;

function TMultiSlicerForm.GetMergedMesh: TMesh;
begin
  FScene.MergedMesh(FMerged);
  Result := FMerged;
end;

procedure TMultiSlicerForm.ObjectListClick(Sender: TObject);
var I: Integer;
begin
  if FUpdating then Exit;
  for I := 0 to FScene.Count - 1 do
    FScene[I].Selected := (I < ObjectList.Items.Count) and ObjectList.Selected[I];
  FScene.Touch;
  View3D.Redraw;
  RefreshModelInfo;
  LoadTransformEditor;
end;

procedure TMultiSlicerForm.View3DSelect(Sender: TObject);
begin
  RefreshObjectList;
  RefreshModelInfo;
  LoadTransformEditor;
end;

procedure TMultiSlicerForm.View3DMoved(Sender: TObject);
begin
  FUndoKey := '';
  SceneChanged('Peca movida na mesa.');
end;

procedure TMultiSlicerForm.View3DDelete(Sender: TObject);
begin
  RemoveSelected;
end;

procedure TMultiSlicerForm.RemoveSelected;
var N: Integer;
begin
  N := FScene.SelectedCount;
  if N = 0 then Exit;
  FScene.DeleteSelected;
  SceneChanged(Format('%d peca(s) removida(s) da mesa.', [N]));
end;

procedure TMultiSlicerForm.DuplicateClick(Sender: TObject);
var I, N, Want, Got: Integer; Sel: array of Integer;
begin
  N := FScene.Count;
  Want := 1;
  if CopiesEd <> nil then Want := CopiesEd.Value;
  SetLength(Sel, 0);
  for I := 0 to N - 1 do
    if FScene[I].Selected then
    begin
      SetLength(Sel, Length(Sel) + 1);
      Sel[High(Sel)] := I;
    end;
  if Length(Sel) = 0 then
  begin
    Status.Caption := 'Selecione a peca a duplicar (clique nela na vista ou na lista).';
    Exit;
  end;
  Got := 0;
  for I := 0 to High(Sel) do Inc(Got, FScene.DuplicateN(Sel[I], Want));
  if Got < Want * Length(Sel) then
    SceneChanged(Format('%d copia(s) colocada(s); as demais nao couberam na mesa.', [Got]))
  else
    SceneChanged(Format('%d copia(s) colocada(s) na mesa.', [Got]));
end;

procedure TMultiSlicerForm.RemoveClick(Sender: TObject);
begin
  if FScene.SelectedCount = 0 then
    Status.Caption := 'Selecione a peca a remover (clique nela na vista ou na lista).'
  else
    RemoveSelected;
end;

procedure TMultiSlicerForm.ClearClick(Sender: TObject);
begin
  if FScene.Count = 0 then Exit;
  FScene.Clear;
  SceneChanged('Mesa limpa.');
end;

function TMultiSlicerForm.TargetObject: TSliceObject;
var K: Integer;
begin
  Result := nil;
  K := FScene.FirstSelected;
  if (K < 0) and (FScene.Count = 1) then K := 0;
  if K >= 0 then Result := FScene[K];
end;

procedure TMultiSlicerForm.LoadTransformEditor;
var O: TSliceObject; Sz: TVec3; On: Boolean; I: Integer; C: TControl;
begin
  if PosX = nil then Exit;
  O := TargetObject;
  On := O <> nil;
  FUpdating := True;
  try
    for I := 0 to PosX.Parent.ControlCount - 1 do
    begin
      C := PosX.Parent.Controls[I];
      if (C is TFloatSpinEdit) or (C = LockBox) then C.Enabled := On;
    end;
    if not On then
    begin
      TransformNote.Caption := 'Selecione uma peca na vista ou na lista.';
      Exit;
    end;
    if FScene.SelectedCount > 1 then
      TransformNote.Caption := Format('%d pecas selecionadas; campos mostram: %s', [FScene.SelectedCount, O.Name])
    else
      TransformNote.Caption := 'Peca: ' + O.Name;
    PosX.Value := O.X; PosY.Value := O.Y;
    RotXEd.Value := O.RotX; RotYEd.Value := O.RotY; RotZEd.Value := O.RotZ;
    ScaleXP.Value := O.ScaleX * 100; ScaleYP.Value := O.ScaleY * 100; ScaleZP.Value := O.ScaleZ * 100;
    Sz := O.Size;
    SizeX.Value := Sz.X; SizeY.Value := Sz.Y; SizeZ.Value := Sz.Z;
    LockBox.Checked := O.Locked;
    PosX.Enabled := not O.Locked; PosY.Enabled := not O.Locked;
  finally
    FUpdating := False;
  end;
  if UndoBtn <> nil then
  begin
    UndoBtn.Enabled := FScene.CanUndo;
    RedoBtn.Enabled := FScene.CanRedo;
  end;
end;

procedure TMultiSlicerForm.PushUndo(const Key: string);
begin
  { varias mudancas seguidas no mesmo campo e na mesma peca viram um passo so }
  if (Key <> '') and (Key = FUndoKey) then Exit;
  FScene.PushUndo;
  FUndoKey := Key;
end;

procedure TMultiSlicerForm.TransformChange(Sender: TObject);
var O: TSliceObject; Sz: TVec3; F: Double;

  procedure Uniform(Factor: Double);
  begin
    O.SetScaleUniform(Factor);
  end;

begin
  if FUpdating then Exit;
  O := TargetObject;
  if O = nil then Exit;
  PushUndo(TComponent(Sender).Name + ':' + IntToStr(O.Id));
  if (Sender = PosX) or (Sender = PosY) then
  begin
    if O.Locked then Exit;
    O.X := PosX.Value; O.Y := PosY.Value;
  end
  else if (Sender = RotXEd) or (Sender = RotYEd) or (Sender = RotZEd) then
    O.SetRotation(RotXEd.Value, RotYEd.Value, RotZEd.Value)
  else if (Sender = ScaleXP) or (Sender = ScaleYP) or (Sender = ScaleZP) then
  begin
    if UniformBox.Checked then Uniform(TFloatSpinEdit(Sender).Value / 100)
    else
    begin
      O.ScaleX := ScaleXP.Value / 100; O.ScaleY := ScaleYP.Value / 100; O.ScaleZ := ScaleZP.Value / 100;
    end;
  end
  else if (Sender = SizeX) or (Sender = SizeY) or (Sender = SizeZ) then
  begin
    { tamanho em mm: fator sobre o tamanho atual nesse eixo da mesa }
    Sz := O.Size;
    if Sender = SizeX then F := SizeX.Value / Max(1e-6, Sz.X)
    else if Sender = SizeY then F := SizeY.Value / Max(1e-6, Sz.Y)
    else F := SizeZ.Value / Max(1e-6, Sz.Z);
    if UniformBox.Checked then Uniform(O.ScaleX * F)
    else if Sender = SizeX then O.ScaleX := O.ScaleX * F
    else if Sender = SizeY then O.ScaleY := O.ScaleY * F
    else O.ScaleZ := O.ScaleZ * F;
  end;
  FScene.Touch;
  LoadTransformEditor;
  SceneChanged('');
end;

procedure TMultiSlicerForm.Rotate90Click(Sender: TObject);
var I, N: Integer;
begin
  N := 0;
  FScene.PushUndo; FUndoKey := '';
  for I := 0 to FScene.Count - 1 do
    if FScene[I].Selected or ((FScene.SelectedCount = 0) and (FScene.Count = 1)) then
    begin
      FScene[I].RotateWorld(TSuiteButton(Sender).Tag, 90);
      Inc(N);
    end;
  if N = 0 then begin Status.Caption := 'Selecione a peca a girar.'; Exit; end;
  FScene.Touch;
  LoadTransformEditor;
  SceneChanged(Format('%d peca(s) girada(s) 90 graus em %s.', [N, Copy('XYZ', TSuiteButton(Sender).Tag + 1, 1)]));
end;

procedure TMultiSlicerForm.MirrorClick(Sender: TObject);
var I, N: Integer; O: TSliceObject;
begin
  N := 0;
  FScene.PushUndo; FUndoKey := '';
  for I := 0 to FScene.Count - 1 do
    if FScene[I].Selected or ((FScene.SelectedCount = 0) and (FScene.Count = 1)) then
    begin
      O := FScene[I];
      case TSuiteButton(Sender).Tag of
        0: O.MirrorX := not O.MirrorX;
        1: O.MirrorY := not O.MirrorY;
      else
        O.MirrorZ := not O.MirrorZ;
      end;
      Inc(N);
    end;
  if N = 0 then begin Status.Caption := 'Selecione a peca a espelhar.'; Exit; end;
  FScene.Touch;
  LoadTransformEditor;
  SceneChanged(Format('%d peca(s) espelhada(s) em %s.', [N, Copy('XYZ', TSuiteButton(Sender).Tag + 1, 1)]));
end;

procedure TMultiSlicerForm.LayFlatClick(Sender: TObject);
var I, N, NChanged: Integer;
begin
  N := 0; NChanged := 0;
  FScene.PushUndo; FUndoKey := '';
  for I := 0 to FScene.Count - 1 do
    if FScene[I].Selected or ((FScene.SelectedCount = 0) and (FScene.Count = 1)) then
    begin
      Inc(N);
      if FScene[I].LayFlatAuto then Inc(NChanged);
    end;
  if N = 0 then begin Status.Caption := 'Selecione a peca a deitar na mesa.'; Exit; end;
  FScene.Touch;
  LoadTransformEditor;
  if NChanged = 0 then SceneChanged('A peca ja esta apoiada pela maior face plana.')
  else SceneChanged(Format('%d peca(s) deitada(s) pela maior face plana.', [NChanged]));
end;

procedure TMultiSlicerForm.PickFaceClick(Sender: TObject);
begin
  if FScene.Count = 0 then Exit;
  FPickPillar := False;
  View3D.KeepPickMode := False;
  ShowViewMode(svMesa);
  View3D.PickFaceMode := True;
  View3D.Redraw;
  Status.Caption := 'Clique na face da peca que deve ficar apoiada na mesa (Esc cancela).';
end;

procedure TMultiSlicerForm.FacePicked(Sender: TObject; ObjIndex, TriIndex: Integer; const Hit: TVec3);
begin
  if FPickPillar then
  begin
    { haste da mesa ate o ponto clicado (a folga Z e descontada no fatiamento) }
    if SupportModeBox.ItemIndex = 0 then SupportModeBox.ItemIndex := 2;
    FScene.AddPillar(FScene[ObjIndex], Hit.X, Hit.Y, Hit.Z, PillarDia.Value);
    RefreshSupportAids;
    SceneChanged(Format('Haste em X %.1f Y %.1f ate Z %.1f mm. Clique em outro ponto ou Esc para terminar.',
      [Hit.X, Hit.Y, Hit.Z], InvariantFS));
    Exit;
  end;
  FScene.PushUndo; FUndoKey := '';
  FScene[ObjIndex].LayFlatTriangle(TriIndex);
  FScene.SelectOnly(ObjIndex);
  LoadTransformEditor;
  SceneChanged('Face escolhida apoiada na mesa.');
end;

procedure TMultiSlicerForm.RefreshSupportAids;
var I, N: Integer; X, Y, Z, D: Double; B: TSceneBlocker; Keep: Integer;
begin
  if PillarInfo = nil then Exit;
  N := FScene.RemoveInvalidPillars;
  if N > 0 then
    Status.Caption := Format('%d haste(s) removida(s): a peca foi girada, escalada ou removida.', [N]);
  N := 0;
  for I := 0 to FScene.PillarCount - 1 do
    if FScene.PillarAbs(I, X, Y, Z, D) then Inc(N);
  if N = 0 then PillarInfo.Caption := 'Nenhuma haste.'
  else PillarInfo.Caption := Format('%d haste(s). Elas acompanham a peca ao arrastar.', [N]);
  Keep := BlockerBox.ItemIndex;
  FUpdating := True;
  try
    BlockerBox.Items.Clear;
    for I := 0 to FScene.BlockerCount - 1 do
    begin
      B := FScene.Blocker(I);
      BlockerBox.Items.Add(Format('Bloqueador %d  (%.0f x %.0f x %.0f mm)', [I + 1, B.W, B.D, B.H], InvariantFS));
    end;
    if Keep >= BlockerBox.Items.Count then Keep := BlockerBox.Items.Count - 1;
    BlockerBox.ItemIndex := Keep;
  finally
    FUpdating := False;
  end;
  BlockerSelect(nil);
  View3D.ShowOverhangs := ShowOverhangsBox.Checked and (SupportModeBox.ItemIndex = 1);
  View3D.OverhangAngle := SupportAngle.Value;
  View3D.Redraw;
end;

procedure TMultiSlicerForm.SupportSettingsChanged(Sender: TObject);
begin
  if FUpdating then Exit;
  { o modo de suporte e o tipo de aderencia ficam lembrados (como o perfil no Cura) }
  if Sender = SupportModeBox then WriteLastChoice('support_mode', IntToStr(SupportModeBox.ItemIndex));
  if Sender = AdhesionTypeBox then WriteLastChoice('adhesion_type', IntToStr(AdhesionTypeBox.ItemIndex));
  RefreshSupportAids;
  SettingsChanged(Sender);
end;

procedure TMultiSlicerForm.AddPillarClick(Sender: TObject);
begin
  if FScene.Count = 0 then Exit;
  ShowViewMode(svMesa);
  FPickPillar := True;
  View3D.KeepPickMode := True;
  View3D.PickFaceMode := True;
  View3D.Redraw;
  Status.Caption := 'Clique sob as partes salientes da peca para colocar hastes (Esc termina).';
end;

procedure TMultiSlicerForm.ClearPillarsClick(Sender: TObject);
begin
  if FScene.PillarCount = 0 then Exit;
  FScene.ClearPillars;
  RefreshSupportAids;
  SceneChanged('Hastes removidas.');
end;

procedure TMultiSlicerForm.AddBlockerClick(Sender: TObject);
var B: TSceneBlocker; O: TSliceObject; Bx: TBox3;
begin
  O := TargetObject;
  if O <> nil then
  begin
    Bx := O.WorldBox;
    B.CX := (Bx.Min.X + Bx.Max.X) / 2; B.CY := (Bx.Min.Y + Bx.Max.Y) / 2;
    B.W := Max(5, (Bx.Max.X - Bx.Min.X) / 2); B.D := Max(5, (Bx.Max.Y - Bx.Min.Y) / 2);
    B.H := Bx.Max.Z + 1;
  end
  else
  begin
    B.CX := BedX.Value / 2; B.CY := BedY.Value / 2; B.W := 30; B.D := 30; B.H := 30;
  end;
  FScene.AddBlocker(B);
  RefreshSupportAids;
  BlockerBox.ItemIndex := FScene.BlockerCount - 1;
  BlockerSelect(nil);
  SceneChanged('Bloqueador adicionado: ajuste o centro e o tamanho nos campos.');
end;

procedure TMultiSlicerForm.RemoveBlockerClick(Sender: TObject);
begin
  if BlockerBox.ItemIndex < 0 then Exit;
  FScene.DeleteBlocker(BlockerBox.ItemIndex);
  RefreshSupportAids;
  SceneChanged('Bloqueador removido.');
end;

procedure TMultiSlicerForm.BlockerSelect(Sender: TObject);
var B: TSceneBlocker; On: Boolean;
begin
  if BlkX = nil then Exit;
  On := (BlockerBox.ItemIndex >= 0) and (BlockerBox.ItemIndex < FScene.BlockerCount);
  BlkX.Enabled := On; BlkY.Enabled := On; BlkW.Enabled := On; BlkD.Enabled := On; BlkH.Enabled := On;
  if not On then Exit;
  B := FScene.Blocker(BlockerBox.ItemIndex);
  FUpdating := True;
  try
    BlkX.Value := B.CX; BlkY.Value := B.CY; BlkW.Value := B.W; BlkD.Value := B.D; BlkH.Value := B.H;
  finally
    FUpdating := False;
  end;
end;

procedure TMultiSlicerForm.BlockerFieldChange(Sender: TObject);
var B: TSceneBlocker; K: Integer;
begin
  if FUpdating then Exit;
  K := BlockerBox.ItemIndex;
  if (K < 0) or (K >= FScene.BlockerCount) then Exit;
  B.CX := BlkX.Value; B.CY := BlkY.Value; B.W := BlkW.Value; B.D := BlkD.Value; B.H := BlkH.Value;
  FScene.SetBlocker(K, B);
  FUpdating := True;
  try
    BlockerBox.Items[K] := Format('Bloqueador %d  (%.0f x %.0f x %.0f mm)', [K + 1, B.W, B.D, B.H], InvariantFS);
    BlockerBox.ItemIndex := K;
  finally
    FUpdating := False;
  end;
  View3D.Redraw;
  SettingsChanged(nil);
end;

procedure TMultiSlicerForm.SupportBoxClick(Sender: TObject);
begin
  if FUpdating then Exit;
  if SupportBox.Checked then SupportModeBox.ItemIndex := 1 else SupportModeBox.ItemIndex := 0;
  SupportSettingsChanged(SupportModeBox);
end;

procedure TMultiSlicerForm.ArrangeClick(Sender: TObject);
begin
  if FScene.Count = 0 then Exit;
  FScene.PushUndo; FUndoKey := '';
  if FScene.Arrange then SceneChanged('Pecas organizadas na mesa.')
  else SceneChanged('Nem todas as pecas couberam na mesa: remova alguma ou diminua a escala.');
  LoadTransformEditor;
end;

procedure TMultiSlicerForm.LockClick(Sender: TObject);
var I: Integer;
begin
  if FUpdating then Exit;
  FScene.PushUndo; FUndoKey := '';
  for I := 0 to FScene.Count - 1 do
    if FScene[I].Selected or ((FScene.SelectedCount = 0) and (FScene.Count = 1)) then
      FScene[I].Locked := LockBox.Checked;
  LoadTransformEditor;
  View3D.Redraw;
end;

procedure TMultiSlicerForm.DoUndo;
begin
  if FScene.Undo then
  begin
    FUndoKey := '';
    LoadTransformEditor;
    SceneChanged('Desfeito.');
  end;
end;

procedure TMultiSlicerForm.DoRedo;
begin
  if FScene.Redo then
  begin
    FUndoKey := '';
    LoadTransformEditor;
    SceneChanged('Refeito.');
  end;
end;

procedure TMultiSlicerForm.UndoClick(Sender: TObject);
begin
  DoUndo;
end;

procedure TMultiSlicerForm.RedoClick(Sender: TObject);
begin
  DoRedo;
end;

procedure TMultiSlicerForm.BeforeMove(Sender: TObject);
begin
  FScene.PushUndo;
  FUndoKey := '';
end;

procedure TMultiSlicerForm.FormKey(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (ssCtrl in Shift) and not FSlicing then
  begin
    if Key = VK_S then
    begin
      if ssShift in Shift then SaveProjectAsClick(nil) else SaveProjectClick(nil);
      Key := 0; Exit;
    end;
    if Key = VK_O then begin OpenClick(nil); Key := 0; Exit; end;
  end;
  if FSlicing and (Key = VK_ESCAPE) then
  begin
    CancelSlicing;
    Key := 0;
    Exit;
  end;
  { Ctrl+Z / Ctrl+Y so fora dos campos de texto (la eles desfazem o texto) }
  if (ssCtrl in Shift) and ((ActiveControl = View3D) or (ActiveControl = ObjectList) or (ActiveControl = nil) or
    (ActiveControl is TSuiteButton)) then
  begin
    if Key = VK_Z then begin DoUndo; Key := 0; end
    else if Key = VK_Y then begin DoRedo; Key := 0; end;
  end;
end;

{ ---------------- qualidade ---------------- }

function TMultiSlicerForm.CurrentQuality: TQualityDef;
var K: Integer;
begin
  K := QualityBox.ItemIndex;
  if (K >= 0) and (K <= High(FQualities)) then Result := FQualities[K]
  else Result := BuiltinQualities[1];
  Result.BuiltIn := False;
  Result.LayerHeight := LayerHeight.Value; Result.FirstLayerHeight := FirstLayerH.Value;
  Result.LineWidthPct := LineWidthP.Value;
  Result.Walls := Walls.Value; Result.TopLayers := TopLayers.Value; Result.BottomLayers := BottomLayers.Value;
  Result.InfillPercent := InfillDensity.Value;
  Result.Pattern := TInfillPattern(Max(0, PatternChoice.ItemIndex));
  Result.WallSpeed := WallSpd.Value; Result.OuterWallSpeed := OuterSpd.Value;
  Result.InfillSpeed := InfillSpd.Value; Result.FirstLayerSpeed := FirstSpd.Value;
  Result.TravelSpeed := TravelSpd.Value;
  Result.Adaptive := Adaptive.Checked; Result.ArcFitting := ArcFit.Checked;
  Result.ZHop := ZHopEd.Value; Result.PressureAdvance := PAEd.Value;
end;

procedure TMultiSlicerForm.ReloadQualities(const SelectName: string);
var I: Integer;
begin
  FQualities := LoadQualities;
  FUpdating := True;
  try
    QualityBox.Items.Clear;
    for I := 0 to High(FQualities) do
      if FQualities[I].BuiltIn then QualityBox.Items.Add(FQualities[I].Name)
      else QualityBox.Items.Add(FQualities[I].Name + '  (meu)');
    QualityBox.ItemIndex := FindQuality(FQualities, SelectName);
  finally
    FUpdating := False;
  end;
end;

procedure TMultiSlicerForm.ApplyQuality(const Q: TQualityDef);
begin
  FUpdating := True;
  try
    LayerHeight.Value := Q.LayerHeight; FirstLayerH.Value := Q.FirstLayerHeight;
    LineWidthP.Value := Q.LineWidthPct;
    Walls.Value := Q.Walls; TopLayers.Value := Q.TopLayers; BottomLayers.Value := Q.BottomLayers;
    InfillDensity.Value := Q.InfillPercent;
    PatternChoice.ItemIndex := Ord(Q.Pattern);
    WallSpd.Value := Q.WallSpeed; OuterSpd.Value := Q.OuterWallSpeed; InfillSpd.Value := Q.InfillSpeed;
    FirstSpd.Value := Q.FirstLayerSpeed; TravelSpd.Value := Q.TravelSpeed;
    Adaptive.Checked := Q.Adaptive; ArcFit.Checked := Q.ArcFitting;
    ZHopEd.Value := Q.ZHop; PAEd.Value := Q.PressureAdvance;
  finally
    FUpdating := False;
  end;
end;

procedure TMultiSlicerForm.SelectQuality(const AName: string);
var K: Integer;
begin
  K := FindQuality(FQualities, AName);
  if K < 0 then raise Exception.Create('Perfil de qualidade nao encontrado: ' + AName);
  QualityBox.ItemIndex := K;
  QualityChange(QualityBox);
end;

procedure TMultiSlicerForm.QualityChange(Sender: TObject);
var K: Integer;
begin
  if FUpdating then Exit;
  K := QualityBox.ItemIndex;
  if (K < 0) or (K > High(FQualities)) then Exit;
  ApplyQuality(FQualities[K]);
  if Sender <> nil then WriteLastChoice('quality', FQualities[K].Name);
  SettingsChanged(nil);
end;

procedure TMultiSlicerForm.QualityCardClick(Sender: TObject);
var Keep: Integer;
begin
  { no modo recomendado o preenchimento escolhido na barra continua valendo }
  Keep := InfillTrack.Position;
  SelectQuality(BuiltinQualities[TSuiteButton(Sender).Tag].Name);
  InfillDensity.Value := Keep;
  SyncRecommended;
end;

procedure TMultiSlicerForm.SyncRecommended;
var I, K: Integer; Q: TQualityDefs;
begin
  if InfillTrack = nil then Exit;
  Q := BuiltinQualities;
  K := -1;
  if (QualityBox.ItemIndex >= 0) and (QualityBox.ItemIndex <= High(FQualities)) then
    for I := 0 to 2 do
      if SameText(FQualities[QualityBox.ItemIndex].Name, Q[I].Name) then K := I;
  for I := 0 to 2 do
    if I = K then QualityBtn[I].SetLook(sbsSolid, clSuitePrimary)
    else QualityBtn[I].SetLook(sbsSoft, clSuitePrimary);
  if (QualityBox.ItemIndex >= 0) and (QualityBox.ItemIndex <= High(FQualities)) then
    QualityHint.Caption := FQualities[QualityBox.ItemIndex].Notes
  else
    QualityHint.Caption := '';
  if K < 0 then QualityHint.Caption := 'Perfil personalizado em uso: ' + CurrentQuality.Name + '.';
  FUpdating := True;
  try
    InfillTrack.Position := InfillDensity.Value;
    InfillLabel.Caption := IntToStr(InfillDensity.Value) + '%';
    if AdhesionTypeBox <> nil then
      AdhesionBox.Checked := (AdhesionTypeBox.ItemIndex > 1) or ((AdhesionTypeBox.ItemIndex = 1) and (SkirtLoops.Value > 0));
    if SupportModeBox <> nil then SupportBox.Checked := SupportModeBox.ItemIndex = 1;
  finally
    FUpdating := False;
  end;
end;

procedure TMultiSlicerForm.InfillTrackChange(Sender: TObject);
begin
  if FUpdating then Exit;
  InfillLabel.Caption := IntToStr(InfillTrack.Position) + '%';
  InfillDensity.Value := InfillTrack.Position;
  WriteLastChoice('infill_percent', IntToStr(InfillTrack.Position));
end;

procedure TMultiSlicerForm.AdhesionClick(Sender: TObject);
begin
  if FUpdating then Exit;
  if AdhesionBox.Checked then
  begin
    if AdhesionTypeBox.ItemIndex = 0 then AdhesionTypeBox.ItemIndex := 1;
    if (AdhesionTypeBox.ItemIndex = 1) and (SkirtLoops.Value = 0) then SkirtLoops.Value := 1;
  end
  else AdhesionTypeBox.ItemIndex := 0;
  WriteLastChoice('adhesion_type', IntToStr(AdhesionTypeBox.ItemIndex));
  SettingsChanged(AdhesionTypeBox);
end;

procedure TMultiSlicerForm.ShowQualityMode(Custom: Boolean);
begin
  RecPanel.Visible := not Custom;
  CustomPanel.Visible := Custom;
  if Custom then
  begin
    ModeBtn[0].SetLook(sbsSoft, clSuitePrimary);
    ModeBtn[1].SetLook(sbsSolid, clSuitePrimary);
  end
  else
  begin
    ModeBtn[0].SetLook(sbsSolid, clSuitePrimary);
    ModeBtn[1].SetLook(sbsSoft, clSuitePrimary);
  end;
  SyncRecommended;
end;

procedure TMultiSlicerForm.ModeClick(Sender: TObject);
begin
  ShowQualityMode(TSuiteButton(Sender).Tag = 1);
  if TSuiteButton(Sender).Tag = 1 then WriteLastChoice('quality_mode', 'custom')
  else WriteLastChoice('quality_mode', 'recommended');
end;

procedure TMultiSlicerForm.SaveQualityClick(Sender: TObject);
var QD: TQualityDef; AName, Err: string;
begin
  QD := CurrentQuality;
  Err := CheckQuality(QD, Nozzle.Value);
  if Err <> '' then begin ShowError(Exception.Create(Err)); Exit; end;
  AName := QD.Name;
  if not InputQuery('Salvar perfil de qualidade', 'Nome do perfil:', AName) then Exit;
  AName := Trim(AName);
  if AName = '' then Exit;
  QD.Name := AName;
  try
    SaveQuality(QD);
    ReloadQualities(AName);
    WriteLastChoice('quality', AName);
    RefreshProfileNotes;
    SyncRecommended;
    Status.Caption := 'Perfil de qualidade salvo: ' + AName;
  except
    on E: Exception do ShowError(E);
  end;
end;

procedure TMultiSlicerForm.DeleteQualityClick(Sender: TObject);
var K: Integer; AName: string;
begin
  K := QualityBox.ItemIndex;
  if (K < 0) or (K > High(FQualities)) or FQualities[K].BuiltIn then Exit;
  AName := FQualities[K].Name;
  if MessageDlg('Excluir perfil', 'Excluir o perfil de qualidade "' + AName + '"?',
    mtConfirmation, [mbYes, mbNo], 0) <> mrYes then Exit;
  DeleteQuality(AName);
  ReloadQualities(AName);
  if QualityBox.ItemIndex < 0 then QualityBox.ItemIndex := FindQuality(FQualities, 'Normal');
  QualityChange(QualityBox);
  Status.Caption := 'Perfil excluido: ' + AName;
end;

procedure TMultiSlicerForm.StdViewClick(Sender: TObject);
begin
  View3D.StdView(TCadStdView(TSuiteButton(Sender).Tag));
end;

{ ---------------- perfis de impressora e material ---------------- }

function TMultiSlicerForm.CurrentPrinter: TPrinterDef;
begin
  Result.Name := '';
  if (PrinterBox.ItemIndex >= 0) and (PrinterBox.ItemIndex <= High(FPrinters)) then
    Result.Name := FPrinters[PrinterBox.ItemIndex].Name;
  Result.BedX := BedX.Value; Result.BedY := BedY.Value; Result.BedZ := BedZ.Value;
  Result.PrintStartZ := PrintStartZ.Value;
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
  if FHasEquipPrinter then
  begin
    K := FindPrinter(FPrinters, FEquipPrinter.Name);
    if K < 0 then
    begin
      SetLength(FPrinters, Length(FPrinters) + 1);
      K := High(FPrinters);
    end;
    FPrinters[K] := FEquipPrinter;
  end;
  FUpdating := True;
  try
    PrinterBox.Items.Clear;
    for I := 0 to High(FPrinters) do
      if FHasEquipPrinter and (I = FindPrinter(FPrinters, FEquipPrinter.Name)) then
        PrinterBox.Items.Add(FPrinters[I].Name + '  (equipamento)')
      else if FPrinters[I].BuiltIn then PrinterBox.Items.Add(FPrinters[I].Name)
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
    PrintStartZ.Value := P.PrintStartZ;
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
  if QualityNote <> nil then
  begin
    K := QualityBox.ItemIndex;
    if (K >= 0) and (K <= High(FQualities)) and not SameQuality(CurrentQuality, FQualities[K]) then
    begin
      QualityNote.Caption := 'Perfil alterado: salve para manter.';
      QualityNote.Font.Color := clSuiteWarning;
    end
    else QualityNote.Caption := '';
    QualityDeleteBtn.Enabled := (K >= 0) and (K <= High(FQualities)) and not FQualities[K].BuiltIn;
  end;
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

procedure TMultiSlicerForm.PrinterBrandChange(Sender: TObject);
var
  Brand: string;
begin
  if FUpdating or (PrinterBrandBox = nil) or (PrinterModelBox = nil) then Exit;
  Brand := PrinterBrandBox.Text;
  FUpdating := True;
  try
    GetMachineModels(Brand, PrinterModelBox.Items);
    if PrinterModelBox.Items.Count > 0 then
      PrinterModelBox.ItemIndex := 0
    else
      PrinterModelBox.ItemIndex := -1;
  finally
    FUpdating := False;
  end;
  if PrinterModelBox.ItemIndex >= 0 then
    PrinterModelChange(Sender);
end;

procedure TMultiSlicerForm.PrinterModelChange(Sender: TObject);
var
  Brand, Model: string;
  Idx: Integer;
  Spec: TMachineSpec;
  P: TPrinterDef;
begin
  if FUpdating or (PrinterBrandBox = nil) or (PrinterModelBox = nil) then Exit;
  Brand := PrinterBrandBox.Text;
  Model := PrinterModelBox.Text;
  if Model = '' then Exit;

  Idx := FindMachine(Brand, Model);
  if Idx >= 0 then
  begin
    Spec := MachineCatalog[Idx];
    P := MachinePrinterDef(Spec, Spec.Brand + ' ' + Spec.Model, 0, 0, 0);
    ApplyPrinter(P);
    if Sender <> nil then
    begin
      WriteLastChoice('printer_brand', Brand);
      WriteLastChoice('printer_model', Model);
    end;
    Idx := FindPrinter(FPrinters, P.Name);
    if Idx >= 0 then
    begin
      FUpdating := True;
      try
        PrinterBox.ItemIndex := Idx;
      finally
        FUpdating := False;
      end;
    end;
    SettingsChanged(Sender);
  end;
end;

procedure TMultiSlicerForm.CreatePrinterProfileClick(Sender: TObject);
var
  P: TPrinterDef;
  AName: string;
begin
  P := CurrentPrinter;
  if (PrinterBrandBox <> nil) and (PrinterModelBox <> nil) and
     (PrinterBrandBox.Text <> '') and (PrinterModelBox.Text <> '') then
    AName := PrinterBrandBox.Text + ' ' + PrinterModelBox.Text
  else
    AName := P.Name;

  if not InputQuery('Criar perfil de impressora', 'Nome do perfil:', AName) then Exit;
  AName := Trim(AName);
  if AName = '' then Exit;
  P.Name := AName;
  try
    SavePrinter(P);
    ReloadPrinters(AName);
    WriteLastChoice('printer', AName);
    if (PrinterBrandBox <> nil) and (PrinterBrandBox.Text <> '') then
      WriteLastChoice('printer_brand', PrinterBrandBox.Text);
    if (PrinterModelBox <> nil) and (PrinterModelBox.Text <> '') then
      WriteLastChoice('printer_model', PrinterModelBox.Text);
    RefreshProfileNotes;
    Status.Caption := 'Perfil criado a partir do modelo: ' + AName;
  except
    on E: Exception do ShowError(E);
  end;
end;

procedure TMultiSlicerForm.FilamentKindChange(Sender: TObject);
var
  Kind, CurBrand: string;
begin
  if FUpdating or (FilamentKindBox = nil) or (FilamentBrandBox = nil) then Exit;
  Kind := FilamentKindBox.Text;
  CurBrand := FilamentBrandBox.Text;
  FUpdating := True;
  try
    GetFilamentBrands(Kind, FilamentBrandBox.Items);
    if (CurBrand <> '') and (FilamentBrandBox.Items.IndexOf(CurBrand) >= 0) then
      FilamentBrandBox.ItemIndex := FilamentBrandBox.Items.IndexOf(CurBrand)
    else if FilamentBrandBox.Items.Count > 0 then
      FilamentBrandBox.ItemIndex := 0
    else
      FilamentBrandBox.ItemIndex := -1;
  finally
    FUpdating := False;
  end;
  if FilamentBrandBox.ItemIndex >= 0 then
    FilamentBrandChange(Sender);
end;

procedure TMultiSlicerForm.FilamentBrandChange(Sender: TObject);
var
  Kind, Brand, CurModel: string;
begin
  if FUpdating or (FilamentKindBox = nil) or (FilamentBrandBox = nil) or (FilamentModelBox = nil) then Exit;
  Kind := FilamentKindBox.Text;
  Brand := FilamentBrandBox.Text;
  CurModel := FilamentModelBox.Text;
  FUpdating := True;
  try
    GetFilamentModels(Kind, Brand, FilamentModelBox.Items);
    if (CurModel <> '') and (FilamentModelBox.Items.IndexOf(CurModel) >= 0) then
      FilamentModelBox.ItemIndex := FilamentModelBox.Items.IndexOf(CurModel)
    else if FilamentModelBox.Items.Count > 0 then
      FilamentModelBox.ItemIndex := 0
    else
      FilamentModelBox.ItemIndex := -1;
  finally
    FUpdating := False;
  end;
  if FilamentModelBox.ItemIndex >= 0 then
    FilamentModelChange(Sender);
end;

procedure TMultiSlicerForm.FilamentModelChange(Sender: TObject);
var
  Kind, Brand, Model: string;
  Spec: TFilamentSpec;
begin
  if FUpdating or (FilamentKindBox = nil) or (FilamentBrandBox = nil) or (FilamentModelBox = nil) then Exit;
  Kind := FilamentKindBox.Text;
  Brand := FilamentBrandBox.Text;
  Model := FilamentModelBox.Text;
  if (Model = '') or not FindFilament(Kind, Brand, Model, Spec) then Exit;

  FUpdating := True;
  try
    HotendFirst.Value := Spec.HotendFirst;
    Hotend.Value := Spec.Hotend;
    BedFirst.Value := Spec.BedFirst;
    BedTemp.Value := Spec.Bed;
    FanPct.Value := Spec.FanPercent;
    FanLayer.Value := Spec.FanFromLayer;
    Density.Value := Spec.Density;
    Flow.Value := Spec.FlowPercent;
    if (ExtruderChoice <> nil) and (ExtruderChoice.ItemIndex = Ord(ekDirect)) then
      RetractLen.Value := Spec.RetractDirect
    else
      RetractLen.Value := Spec.RetractBowden;
    RetractSpd.Value := Spec.RetractSpeed;
    if Spec.CostPerKg > 0 then Cost.Value := Spec.CostPerKg;
    MaterialNotes.Caption := Spec.Notes;
  finally
    FUpdating := False;
  end;

  if Sender <> nil then
  begin
    WriteLastChoice('filament_kind', Kind);
    WriteLastChoice('filament_brand', Brand);
    WriteLastChoice('filament_model', Model);
  end;

  SettingsChanged(Sender);
end;

procedure TMultiSlicerForm.PrinterChange(Sender: TObject);
var K, M: Integer;
begin
  if FUpdating then Exit;
  K := PrinterBox.ItemIndex;
  if (K < 0) or (K > High(FPrinters)) then Exit;
  ApplyPrinter(FPrinters[K]);
  { Atualiza Marca e Modelo se corresponder a uma maquina do catalogo }
  M := FindMachine('', FPrinters[K].Name);
  if (M >= 0) and (PrinterBrandBox <> nil) and (PrinterModelBox <> nil) then
  begin
    FUpdating := True;
    try
      PrinterBrandBox.ItemIndex := PrinterBrandBox.Items.IndexOf(MachineCatalog[M].Brand);
      if PrinterBrandBox.ItemIndex >= 0 then
      begin
        GetMachineModels(MachineCatalog[M].Brand, PrinterModelBox.Items);
        PrinterModelBox.ItemIndex := PrinterModelBox.Items.IndexOf(MachineCatalog[M].Model);
      end;
    finally
      FUpdating := False;
    end;
  end;
  { a retracao depende da extrusora: reaplica a do material atual }
  if (MaterialBox <> nil) and (MaterialBox.ItemIndex >= 0) and (MaterialBox.ItemIndex <= High(FMaterials)) then
    ExtruderChange(nil);
  if (Sender <> nil) and not (FHasEquipPrinter and SameText(FPrinters[K].Name, FEquipPrinter.Name)) then
    WriteLastChoice('printer', FPrinters[K].Name);
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
  if not FLoadingProject and not FDirty then
  begin
    FDirty := True;
    UpdateTitle;
  end;
  if (InfillTrack <> nil) and ((Sender = InfillDensity) or (Sender = SkirtLoops) or (Sender = nil) or
    (Sender = AdhesionTypeBox) or (Sender = SupportModeBox)) then
  begin
    SyncRecommended;
    if Sender = InfillDensity then
      WriteLastChoice('infill_percent', IntToStr(InfillDensity.Value));
  end;
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
    View3D.SetToolpaths(nil);
    if (FScene.BedX <> BedX.Value) or (FScene.BedY <> BedY.Value) or (FScene.BedZ <> BedZ.Value) then
    begin
      FScene.BedX := BedX.Value; FScene.BedY := BedY.Value; FScene.BedZ := BedZ.Value;
      FScene.Touch;
      View3D.FitBed;
    end;
    View3D.Redraw;
    if View.Tag = 1 then ShowViewMode(svCamadas) else ShowViewMode(svMesa);
  end;
  if Assigned(SendButton) then SendButton.Enabled := False;
  if Assigned(ModelInfo) then RefreshModelInfo;
  if FScene.Count > 0 then
  begin
    SetState('Alteracoes pendentes', clSuiteWarning);
    if Assigned(Status) then Status.Caption := 'Configuracao alterada. Fatie novamente para atualizar a previa.';
    if Assigned(PreviewSummary) then PreviewSummary.Caption := 'Fatie para ver tempo, filamento e camadas.';
  end;
end;

{ ---------------- modelo ---------------- }

procedure TMultiSlicerForm.OpenFile(const FN: string);
var Candidate: TMesh; OK, Fixed: Boolean; O: TSliceObject; Warn: string;
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
    { confere a malha: normais para dentro sao desviradas; casca aberta e
      escala estranha viram aviso }
    FLastMeshReport := CheckMesh(Candidate);
    Fixed := NormalsInverted(FLastMeshReport);
    if Fixed then FlipNormals(Candidate);
    Warn := MeshReportText(FLastMeshReport);
    O := FScene.Add(Candidate, ChangeFileExt(ExtractFileName(FN), ''), ExpandFileName(FN));
    Candidate := nil;
    FScene.SelectOnly(FScene.IndexOf(O));
    SourceFile := ExpandFileName(FN);
    if Log <> nil then
    begin
      Log.Lines.Add('Aberto: ' + SourceFile);
      if Fixed then Log.Lines.Add('Normais invertidas (faces viradas para dentro): corrigidas.');
      if Warn <> '' then Log.Lines.Add('Aviso: ' + Warn);
    end;
    if Warn <> '' then
      SceneChanged(Format('Aberto: %s. %s', [ExtractFileName(FN), Warn]))
    else
      SceneChanged(Format('Aberto: %s (%d triangulos). Peca colocada na mesa.',
        [ExtractFileName(FN), O.Source.Count]));
    if Warn <> '' then SetState('Confira a peca', clSuiteWarning);
  finally
    Candidate.Free;
  end;
end;

procedure TMultiSlicerForm.CenterModel;
var I, N: Integer;
begin
  if FScene.Count = 0 then Exit;
  FScene.PushUndo; FUndoKey := '';
  N := 0;
  for I := 0 to FScene.Count - 1 do
    if FScene[I].Selected then
    begin
      FScene.CenterObject(I);
      Inc(N);
    end;
  if (N = 0) and (FScene.Count = 1) then FScene.CenterObject(0);
  SceneChanged('');
end;

procedure TMultiSlicerForm.OpenClick(Sender: TObject);
var D: TOpenDialog;
begin
  D := TOpenDialog.Create(Self);
  try
    D.Filter := 'Modelos e projetos (*.stl;*.3mf;*.mslice)|*.stl;*.3mf;*.mslice|STL|*.stl|3MF|*.3mf|Projeto MultiSlicer|*.mslice';
    D.Options := [ofFileMustExist, ofEnableSizing];
    if D.Execute then
    try
      if SameText(ExtractFileExt(D.FileName), MSLICE_EXT) then
      begin
        if ConfirmDiscard then OpenProject(D.FileName);
      end
      else OpenFile(D.FileName);
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
  if FScene.Count = 0 then Exit;
  if (FScene.SelectedCount = 0) and (FScene.Count > 1) then
  begin
    Status.Caption := 'Selecione a peca a centralizar.';
    Exit;
  end;
  CenterModel;
  Status.Caption := 'Peca centralizada na mesa.';
end;

{ ---------------- fatiamento ---------------- }

function TMultiSlicerForm.Settings: TSliceSettings;
var I: Integer; B: TBox3; Err: string; PX, PY, PZ, PD: Double;
begin
  Result := DefaultSliceSettings;
  Result.Printer := DefaultPrinterProfile;
  Result.Printer.Name := CurrentPrinter.Name;
  Result.Printer.BedX := BedX.Value; Result.Printer.BedY := BedY.Value; Result.Printer.MaxZ := BedZ.Value;
  Result.PrintStartZ := PrintStartZ.Value;
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
  Err := CheckQuality(CurrentQuality, Result.Printer.Nozzle);
  if Err <> '' then raise Exception.Create(Err);
  Result.LayerHeight := LayerHeight.Value; Result.Printer.LayerHeight := Result.LayerHeight;
  Result.FirstLayerHeight := FirstLayerH.Value;
  Result.LineWidth := Result.Printer.Nozzle * LineWidthP.Value / 100;
  Result.Walls := Walls.Value;
  Result.TopLayers := TopLayers.Value; Result.BottomLayers := BottomLayers.Value;
  Result.InfillDensity := InfillDensity.Value / 100;
  Result.InfillPattern := TInfillPattern(PatternChoice.ItemIndex);
  Result.WallSpeed := WallSpd.Value; Result.OuterWallSpeed := OuterSpd.Value; Result.InfillSpeed := InfillSpd.Value;
  Result.FirstLayerSpeed := FirstSpd.Value; Result.TravelSpeed := TravelSpd.Value;
  Result.ZHop := ZHopEd.Value; Result.PressureAdvance := PAEd.Value;
  Result.RetractLength := RetractLen.Value;
  Result.ArcFitting := ArcFit.Checked;
  Result.SkirtLoops := SkirtLoops.Value; Result.SkirtDistance := SkirtDist.Value;
  Result.FanFromLayer := FanLayer.Value;
  Result.FilamentDensity := Density.Value;
  Result.Adaptive := Adaptive.Checked;
  Result.AdaptiveMin := Min(0.08, Result.LayerHeight);
  Result.AdaptiveMax := Min(Result.LayerHeight, Result.Printer.Nozzle * 0.8);
  { suportes }
  Result.Support := DefaultSupportParams;
  Result.Support.Mode := TSupportMode(Max(0, SupportModeBox.ItemIndex));
  Result.Support.Everywhere := SupportWhereBox.ItemIndex = 1;
  Result.Support.AngleDeg := SupportAngle.Value;
  Result.Support.Density := SupportDens.Value / 100;
  Result.Support.XYGap := SupportXY.Value;
  Result.Support.ZGap := SupportZ.Value;
  Result.Support.InterfaceLayers := SupportIfc.Value;
  Result.Support.Speed := SupportSpd.Value;
  SetLength(Result.Support.Pillars, 0);
  for I := 0 to FScene.PillarCount - 1 do
    if FScene.PillarAbs(I, PX, PY, PZ, PD) then
    begin
      SetLength(Result.Support.Pillars, Length(Result.Support.Pillars) + 1);
      with Result.Support.Pillars[High(Result.Support.Pillars)] do
      begin
        X := PX; Y := PY; ZTop := PZ; Diameter := PD;
      end;
    end;
  SetLength(Result.Support.Blockers, FScene.BlockerCount);
  for I := 0 to FScene.BlockerCount - 1 do
    with FScene.Blocker(I) do
    begin
      Result.Support.Blockers[I].MinX := CX - W / 2; Result.Support.Blockers[I].MaxX := CX + W / 2;
      Result.Support.Blockers[I].MinY := CY - D / 2; Result.Support.Blockers[I].MaxY := CY + D / 2;
      Result.Support.Blockers[I].MinZ := 0; Result.Support.Blockers[I].MaxZ := H;
    end;
  { aderencia }
  Result.Adhesion := TAdhesionType(Max(0, AdhesionTypeBox.ItemIndex));
  Result.BrimWidth := BrimWidthEd.Value;
  Result.RaftMargin := RaftMarginEd.Value;
  Result.RaftAirGap := RaftGapEd.Value;
  if FScene.Count = 1 then Result.ObjectName := FScene[0].Name
  else Result.ObjectName := 'pecas';
  { cada peca com rotulo proprio no G-code (cancelar uma peca na impressora) }
  SetLength(Result.Objects, FScene.Count);
  for I := 0 to FScene.Count - 1 do
  begin
    B := FScene[I].WorldBox;
    Result.Objects[I].Name := FScene[I].Name;
    Result.Objects[I].MinX := B.Min.X; Result.Objects[I].MinY := B.Min.Y;
    Result.Objects[I].MaxX := B.Max.X; Result.Objects[I].MaxY := B.Max.Y;
  end;
  if Result.ObjectName = '' then Result.ObjectName := 'objeto';
end;

function TMultiSlicerForm.ValidateJob: Boolean;
var Errors, Warnings: TStringList; S: TSliceSettings; I: Integer;
begin
  Errors := TStringList.Create;
  Warnings := TStringList.Create;
  try
    MachineChecks(Errors, Warnings);
    FScene.BedX := BedX.Value; FScene.BedY := BedY.Value; FScene.BedZ := BedZ.Value;
    FScene.Validate(Errors);
    try
      S := Settings;
      if S.InfillDensity < 0 then Errors.Add('Preenchimento invalido.');
      if PrintStartZ.Value >= BedZ.Value then Errors.Add('Degrau inicial Z maior que altura maxima da impressora.');
    except
      on E: Exception do Errors.Add(E.Message);
    end;
    Result := Errors.Count = 0;
    Log.Lines.Add('--- Validacao ---');
    for I := 0 to Warnings.Count - 1 do Log.Lines.Add('Aviso: ' + Warnings[I]);
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
    Warnings.Free;
    Errors.Free;
  end;
end;

procedure TMultiSlicerForm.GenerateProgram;
var Candidate: TModernSlicer; G: TStringList; R: TSliceReport; Th: TSliceThread; Err: string; WasCanceled: Boolean;
begin
  if FSlicing then Exit;
  if FScene.Count = 0 then raise Exception.Create('Abra um modelo STL ou 3MF primeiro.');
  FScene.MergedMesh(FMerged);
  Candidate := TModernSlicer.Create;
  G := TStringList.Create;
  try
    { a tela continua viva: barra de andamento e Cancelar (Esc) }
    Th := TSliceThread.Create(True);
    try
      Th.Engine := Candidate;
      Th.Mesh := TMesh.Create;
      FScene.MergedMesh(Th.Mesh);
      Th.Settings := Settings;
      Th.Output := G;
      Th.FreeOnTerminate := False;
      FRunning := Candidate;
      SetBusy(True);
      try
        Th.Start;
        while not Th.Finished do
        begin
          SliceProgress.Position := Round(Candidate.Progress * 1000);
          Status.Caption := Format('%s... %d%%  (Esc cancela)',
            [SLICE_STAGE_NAMES[EnsureRange(Candidate.Stage, 0, 3)], Round(Candidate.Progress * 100)]);
          Application.ProcessMessages;
          Sleep(15);
        end;
        Th.WaitFor;
      finally
        FRunning := nil;
        SetBusy(False);
      end;
      if FCloseRequested then
      begin
        Close;
        Abort;
      end;
      R := Th.Report;
      Err := Th.ErrorText;
      WasCanceled := Th.Canceled;
    finally
      Th.Mesh.Free;
      Th.Free;
    end;
    if WasCanceled then
    begin
      Status.Caption := 'Fatiamento cancelado. A previa anterior foi mantida.';
      Log.Lines.Add('Fatiamento cancelado.');
      SetState('Cancelado', clSuiteWarning);
      Abort;
    end;
    if Err <> '' then raise Exception.Create(Err);
    if (R.Layers = 0) or (G.Count = 0) then raise Exception.Create('O modelo nao gerou camadas imprimiveis.');
    View.SetSlice(nil, -1);
    View3D.SetToolpaths(nil);
    Engine.Free; Engine := Candidate; Candidate := nil;
    Code.Assign(G); Report := R; Ready := True; FExportedFile := '';
    FUpdating := True;
    try
      { como no Cura: abre mostrando a peca inteira (ultima camada) }
      LayerChoice.MaxValue := R.Layers; LayerChoice.Value := R.Layers;
      LayerTrack.Max := R.Layers; LayerTrack.Position := R.Layers;
    finally
      FUpdating := False;
    end;
    View.SetSlice(Engine, R.Layers - 1);
    View3D.SetToolpaths(TToolpathPreview.Create(Engine.Layers, CurrentPrinter.Nozzle * LineWidthP.Value / 100));
    View3D.ShowLayer := R.Layers - 1;
    PreviewSummary.Caption := Format('%d camadas'#10'Tempo estimado: %d h %.2d min'#10 +
      'Filamento: %.2f m  /  %.1f g'#10'Retracoes: %d', [R.Layers, Trunc(R.EstimatedSeconds / 3600),
      Trunc(R.EstimatedSeconds / 60) mod 60, R.FilamentMM / 1000, R.FilamentGrams, R.Retractions],
      InvariantFS);
    if Cost.Value > 0 then
      PreviewSummary.Caption := PreviewSummary.Caption + Format(#10'Custo do filamento: R$ %.2f',
        [R.FilamentGrams / 1000 * Cost.Value], InvariantFS);
    PreviewSummary.Caption := PreviewSummary.Caption + #10'Qualidade: ' + CurrentQuality.Name +
      Format(' (camada %s mm, preenchimento %d%%)', [FormatFloat('0.0#', LayerHeight.Value, InvariantFS), InfillDensity.Value]);
    PreviewSummary.Caption := PreviewSummary.Caption + #10'Impressora: ' + CurrentPrinter.Name +
      #10'Material: ' + CurrentMaterial.Name + Format(' (bico %d C, mesa %d C)', [Hotend.Value, BedTemp.Value]);
    if R.SupportPaths > 0 then
      PreviewSummary.Caption := PreviewSummary.Caption + Format(#10'Suporte: %d trajetorias', [R.SupportPaths]);
    if R.RaftLayers > 0 then
      PreviewSummary.Caption := PreviewSummary.Caption + Format(#10'Jangada: %d camadas', [R.RaftLayers]);
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
    G.Free;
    Candidate.Free;
  end;
end;

procedure TSliceThread.Execute;
begin
  try
    Report := Engine.Slice(Mesh, Settings, Output);
  except
    on ESliceCanceled do Canceled := True;
    on E: Exception do ErrorText := E.Message;
  end;
end;

procedure TMultiSlicerForm.CancelSlicing;
begin
  if FRunning <> nil then FRunning.CancelRequested := True;
end;

procedure TMultiSlicerForm.CancelSliceClick(Sender: TObject);
begin
  CancelSlicing;
end;

procedure TMultiSlicerForm.SetBusy(ABusy: Boolean);
var I: Integer;
begin
  FSlicing := ABusy;
  Pages.Enabled := not ABusy;
  for I := 0 to High(Nav) do Nav[I].Enabled := not ABusy;
  ObjectList.Enabled := not ABusy;
  EquipmentBox.Enabled := not ABusy;
  ViewBar.Enabled := not ABusy;
  ValidateButton.Visible := not ABusy;
  SliceBtn.Visible := not ABusy;
  ExportBtn.Enabled := not ABusy and (FScene.Count > 0);
  SendButton.Enabled := not ABusy and (FExportedFile <> '');
  CancelBtn.Visible := ABusy;
  SliceProgress.Position := 0;
  SliceProgress.Visible := ABusy;
  Coords.Visible := not ABusy;
  if ABusy then
  begin
    SetState('Fatiando...', clSuiteInfo);
  end;
end;

procedure TMultiSlicerForm.FormCloseQuery(Sender: TObject; var CanClose: Boolean);
begin
  if not FSlicing then
  begin
    CanClose := ConfirmDiscard;
    Exit;
  end;
  { fechando no meio do fatiamento: cancela e fecha quando a thread parar }
  CanClose := not FSlicing;
  if FSlicing then
  begin
    CancelSlicing;
    FCloseRequested := True;
    Status.Caption := 'Cancelando o fatiamento para fechar...';
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
  View3D.ShowLayer := LayerChoice.Value - 1;
  if View.Tag <> 1 then ShowViewMode(svCamadas);
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
  View3D.ShowLayer := LayerTrack.Position - 1;
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
    { nome sugerido: o do projeto; sem projeto, o do modelo }
    if FProjectFile <> '' then
    begin
      D.FileName := ChangeFileExt(ExtractFileName(FProjectFile), '.gcode');
      D.InitialDir := ExtractFilePath(FProjectFile);
    end
    else
    begin
      D.FileName := ChangeFileExt(ExtractFileName(SourceFile), '.gcode');
      if SourceFile <> '' then D.InitialDir := ExtractFilePath(SourceFile);
    end;
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
  { sem arquivo gerado (ou desatualizado): gera antes, como o MakeRouter }
  if (FExportedFile = '') or not FileExists(FExportedFile) or not Ready then
  begin
    ExportClick(nil);
    if (FExportedFile = '') or not FileExists(FExportedFile) then
    begin
      Status.Caption := 'Gere o G-code antes de abrir no MultiCNC.';
      Exit;
    end;
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
