unit mainform;

{$mode objfpc}{$H+}

interface

uses Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls,
  Dialogs, Graphics, Spin, StrUtils, LazUTF8, LCLType, multisuite_numfmt,
  multicnc_types, multicnc_session, multicnc_gcode_analyzer, multicnc_laser_config,
  multicnc_printer_profiles, ailistserialdevices;

type
  TMainForm = class(TForm)
  private
    Session: TSimulationSession;
    MachineType, ProtocolType: TComboBox;
    DeviceEdit, BaudCombo: TComboBox;
    HostEdit, PortEdit: TEdit;
    SerialDeviceList: TAIListSerialDevices;
    CommunicationMode: TComboBox;
    SerialPanel, TCPPanel: TPanel;
    BtnConnect, BtnOpen, BtnFraming, BtnStart, BtnPause, BtnResume, BtnStop,
      BtnHome, BtnSetHome, BtnPhysicalHome, BtnZero, BtnStatus, BtnUnlock, BtnSend: TButton;
    JogButtons: array[0..5] of TButton;
    StepSize: TFloatSpinEdit;
    FeedRate: TSpinEdit;
    ProgramMemo, MemoLog: TMemo;
    EditCommand, SearchEdit: TEdit;
    Pages: TPageControl;
    ProgramTab, ConfigTab, ConsoleTab: TTabSheet;
    SearchResult: TLabel;
    StateLabel, FileLabel, ProgramInfoLabel, ProgressLabel, PositionLabel, HomeLabel: TLabel;
    LastState: TSessionState;
    Progress: TProgressBar;
    Timer: TTimer;
    Status: TStatusBar;

    { Config UI controls }
    ConfigScrollBox: TScrollBox;
    GbConnection: TGroupBox;

    { 3D Printer Profile & Temperature UI controls }
    GbPrinterProfile: TGroupBox;
    PrinterBrandCombo, PrinterModelCombo: TComboBox;
    PrinterSpecsLabel: TLabel;
    GbPrinterTemps: TGroupBox;
    SpConfigHotendTemp, SpConfigBedTemp: TSpinEdit;
    BtnApplyTemps, BtnCooldownTemps: TButton;
    LblConfigRealTemps: TLabel;

    { Main View Side Panel Temperature Indicators }
    GbSideTemperatures: TGroupBox;
    LblNozzleTemp, LblBedTemp, LblHeaterStatus: TLabel;

    { Laser UI controls }
    LaserContainer: TPanel;
    GbWork, GbPower, GbSpeed, GbCut, GbDot, GbAir, GbControl: TGroupBox;
    RbModeCut, RbModeEngrave, RbModePerforate: TRadioButton;
    SpLaserPower, SpLaserMinPower, SpLaserMaxPower, SpLaserMaxS: TSpinEdit;
    SpSpeedEngrave, SpSpeedCut, SpSpeedTravel: TSpinEdit;
    ChkOverrideSpeed: TCheckBox;
    SpCutPasses, SpCutPassPower, SpCutPassFeed, SpCutPassDelay: TSpinEdit;
    SpCutPassZStep: TFloatSpinEdit;
    SpDotLengthOn, SpDotLengthOff: TFloatSpinEdit;
    SpDotPower, SpDotFeed: TSpinEdit;
    ChkAirAssist: TCheckBox;
    EditAirAssistOn, EditAirAssistOff: TEdit;
    RbLaserM4, RbLaserM3: TRadioButton;
    ChkFramingLaser: TCheckBox;
    SpFramingPower, SpFramingFeed: TSpinEdit;
    SpPreFireDelay, SpPostFireDelay: TSpinEdit;
    SpKerf: TFloatSpinEdit;
    ChkFrameBeforeStart: TCheckBox;

    function Panel(ParentControl: TWinControl; Alignment: TAlign; Size: Integer): TPanel;
    function LabelAt(ParentControl: TWinControl; const AText: string; X, Y: Integer): TLabel;
    function ButtonAt(ParentControl: TWinControl; const AText: string;
      X, Y, W: Integer; Handler: TNotifyEvent): TButton;
    procedure SearchClick(Sender: TObject);
    procedure SearchChanged(Sender: TObject);
    procedure SaveLogClick(Sender: TObject);
    procedure ClearLogClick(Sender: TObject);
    procedure Shortcut(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure DropFiles(Sender: TObject; const FileNames: array of string);
    procedure LoadProgram(const AFileName: string);
    procedure CommunicationChanged(Sender: TObject);
    procedure SelectionChanged(Sender: TObject);
    procedure ConnectClick(Sender: TObject);
    procedure OpenClick(Sender: TObject);
    procedure CommandClick(Sender: TObject);
    procedure FramingClick(Sender: TObject);
    procedure JogClick(Sender: TObject);
    procedure Tick(Sender: TObject);
    procedure Log(const AText: string);
    procedure UpdateControls;
    procedure UpdateMachineTypeLayout;
    procedure FeedRateChanged(Sender: TObject);
    procedure Closing(Sender: TObject; var CanClose: Boolean);
    procedure LaserParamChanged(Sender: TObject);
    procedure SyncLaserSettingsToUI;
    procedure SyncLaserSettingsFromUI;
    procedure RefreshSerialPorts;
    procedure DeviceComboDropDown(Sender: TObject);
    procedure PrinterBrandChanged(Sender: TObject);
    procedure PrinterModelChanged(Sender: TObject);
    procedure TempConfigChanged(Sender: TObject);
    procedure ApplyTempsClick(Sender: TObject);
    procedure CooldownTempsClick(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

implementation

function TMainForm.Panel(ParentControl: TWinControl; Alignment: TAlign; Size: Integer): TPanel;
begin
  Result := TPanel.Create(Self);
  Result.Parent := ParentControl;
  Result.BevelOuter := bvNone;
  Result.Align := Alignment;
  if Alignment in [alLeft, alRight] then Result.Width := Size else Result.Height := Size;
end;

function TMainForm.LabelAt(ParentControl: TWinControl; const AText: string; X, Y: Integer): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := ParentControl;
  Result.Caption := AText;
  Result.SetBounds(X, Y, 200, 24);
end;

function TMainForm.ButtonAt(ParentControl: TWinControl; const AText: string;
  X, Y, W: Integer; Handler: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := ParentControl;
  Result.Caption := AText;
  Result.SetBounds(X, Y, W, 34);
  Result.OnClick := Handler;
end;

constructor TMainForm.Create(AOwner: TComponent);
var
  Header, Body, Side, Workspace, Actions, Footer, ConsoleBar, SearchBar, LogBar: TPanel;
  L: TLabel; I: Integer;
const JogNames: array[0..5] of string = ('X -', 'X +', 'Y -', 'Y +', 'Z -', 'Z +');
begin
  inherited CreateNew(AOwner);
  Caption := 'MultiCNC | Control Panel';
  Position := poScreenCenter;
  SetBounds(0, 0, 1140, 780);
  Constraints.MinWidth := 1020;
  Constraints.MinHeight := 700;
  Font.Name := 'Segoe UI';
  Font.Size := 10;
  Color := clBtnFace;
  OnCloseQuery := @Closing;
  KeyPreview := True;
  OnKeyDown := @Shortcut;
  AllowDropFiles := True;
  OnDropFiles := @DropFiles;
  Session := TSimulationSession.Create;
  Session.OnLog := @Log;

  { Top Header }
  Header := Panel(Self, alTop, 75);
  L := LabelAt(Header, 'MultiCNC', 20, 10);
  L.Font.Size := 20;
  L.Font.Style := [fsBold];
  LabelAt(Header, 'CONTROL  /  Program execution with controller handshake', 22, 46);
  StateLabel := LabelAt(Header, 'Disconnected', 620, 25);
  StateLabel.Font.Style := [fsBold];
  StateLabel.Font.Size := 11;
  BtnConnect := ButtonAt(Header, 'Connect Device', 840, 18, 200, @ConnectClick);

  { Bottom Status Bar }
  Status := TStatusBar.Create(Self);
  Status.Parent := Self;
  Status.Align := alBottom;
  Status.SimplePanel := True;
  Status.SimpleText := 'Commands validated and sent with confirmation (ok). Keep physical emergency stop within reach.';

  { Main Body }
  Body := Panel(Self, alClient, 0);

  { Left Manual Jog & Indicator Panel }
  Side := Panel(Body, alLeft, 268);
  L := LabelAt(Side, 'Manual Jog', 20, 14);
  L.Font.Style := [fsBold];
  LabelAt(Side, 'Step (mm)', 20, 51);
  StepSize := TFloatSpinEdit.Create(Self);
  StepSize.Parent := Side;
  StepSize.SetBounds(20, 75, 220, 30);
  StepSize.MinValue := 0.01;
  StepSize.MaxValue := 100;
  StepSize.DecimalPlaces := 2;
  StepSize.Increment := 0.1;
  StepSize.Value := 1;

  LabelAt(Side, 'Feed rate (mm/min)', 20, 119);
  FeedRate := TSpinEdit.Create(Self);
  FeedRate.Parent := Side;
  FeedRate.SetBounds(20, 143, 220, 30);
  FeedRate.MinValue := 1;
  FeedRate.MaxValue := 10000;
  FeedRate.Value := 500;
  FeedRate.OnChange := @FeedRateChanged;

  for I := 0 to 5 do begin
    JogButtons[I] := ButtonAt(Side, JogNames[I], 20 + (I mod 2) * 114,
      194 + (I div 2) * 44, 106, @JogClick);
    JogButtons[I].Tag := I;
  end;

  BtnHome := ButtonAt(Side, 'Go Home', 20, 328, 108, @CommandClick);
  BtnHome.Hint := 'Return axes to recorded HOME position (G28).';
  BtnHome.ShowHint := True;
  BtnSetHome := ButtonAt(Side, 'Set Home Ref', 132, 328, 116, @CommandClick);
  BtnSetHome.Hint := 'Record current axes position as application reference HOME (G28.1) without moving.';
  BtnSetHome.ShowHint := True;

  BtnPhysicalHome := ButtonAt(Side, 'Physical Homing', 20, 368, 108, @CommandClick);
  BtnPhysicalHome.Hint := 'Run physical homing cycle on endstop switches ($H in GRBL / G28 in Marlin 3D).';
  BtnPhysicalHome.ShowHint := True;
  BtnZero := ButtonAt(Side, 'Zero Workpiece', 132, 368, 116, @CommandClick);
  BtnZero.Hint := 'Set current position as workpiece coordinate origin (G92 X0 Y0 Z0).';
  BtnZero.ShowHint := True;

  BtnStatus := ButtonAt(Side, 'Status / Pos', 20, 408, 108, @CommandClick);
  BtnStatus.Hint := 'Query machine state and position (? in GRBL / M114 in Marlin).';
  BtnStatus.ShowHint := True;
  BtnUnlock := ButtonAt(Side, 'Unlock', 132, 408, 116, @CommandClick);
  BtnUnlock.Hint := 'Unlock machine from alarm state ($X in GRBL / M999 in Marlin).';
  BtnUnlock.ShowHint := True;

  PositionLabel := LabelAt(Side, 'Position: -', 20, 452);
  PositionLabel.Name := 'PositionLabel';
  PositionLabel.AutoSize := False;
  PositionLabel.SetBounds(20, 452, 228, 55);
  PositionLabel.WordWrap := True;
  PositionLabel.Font.Name := 'Consolas';

  HomeLabel := LabelAt(Side, 'HOME: -', 20, 512);
  HomeLabel.Name := 'HomeLabel';
  HomeLabel.AutoSize := False;
  HomeLabel.SetBounds(20, 512, 228, 45);
  HomeLabel.WordWrap := True;
  HomeLabel.Font.Name := 'Consolas';
  HomeLabel.Font.Color := $00994400;

  { 3D Printer Temperature Indicator Group in Side Panel }
  GbSideTemperatures := TGroupBox.Create(Self);
  GbSideTemperatures.Parent := Side;
  GbSideTemperatures.Caption := '3D Printer Temperatures';
  GbSideTemperatures.SetBounds(15, 510, 235, 130);
  GbSideTemperatures.Visible := False;

  LabelAt(GbSideTemperatures, 'Nozzle / Hotend:', 10, 2);
  LblNozzleTemp := TLabel.Create(Self);
  LblNozzleTemp.Parent := GbSideTemperatures;
  LblNozzleTemp.SetBounds(10, 23, 215, 20);
  LblNozzleTemp.Font.Name := 'Consolas';
  LblNozzleTemp.Font.Style := [fsBold];
  LblNozzleTemp.Font.Size := 9;
  LblNozzleTemp.Font.Color := $000033AA;
  LblNozzleTemp.Caption := 'Real: - C  |  Config: 200 C';

  LabelAt(GbSideTemperatures, 'Heated Bed:', 10, 46);
  LblBedTemp := TLabel.Create(Self);
  LblBedTemp.Parent := GbSideTemperatures;
  LblBedTemp.SetBounds(10, 67, 215, 20);
  LblBedTemp.Font.Name := 'Consolas';
  LblBedTemp.Font.Style := [fsBold];
  LblBedTemp.Font.Size := 9;
  LblBedTemp.Font.Color := $00773300;
  LblBedTemp.Caption := 'Real: - C  |  Config: 60 C';

  LblHeaterStatus := TLabel.Create(Self);
  LblHeaterStatus.Parent := GbSideTemperatures;
  LblHeaterStatus.SetBounds(10, 93, 215, 18);
  LblHeaterStatus.Font.Size := 8;
  LblHeaterStatus.Font.Color := clGray;
  LblHeaterStatus.Caption := 'Heaters Standby / Off';

  { Workspace (Center / Right) }
  Workspace := Panel(Body, alClient, 0);
  Actions := Panel(Workspace, alTop, 82);

  BtnOpen := ButtonAt(Actions, 'Open Program...', 12, 10, 160, @OpenClick);
  BtnFraming := ButtonAt(Actions, 'Frame (Test)', 178, 10, 110, @FramingClick);
  BtnStart := ButtonAt(Actions, 'Start', 294, 10, 95, @CommandClick);
  BtnPause := ButtonAt(Actions, 'Pause', 395, 10, 95, @CommandClick);
  BtnResume := ButtonAt(Actions, 'Resume', 496, 10, 95, @CommandClick);
  BtnStop := ButtonAt(Actions, 'Emergency Stop', 597, 10, 130, @CommandClick);

  FileLabel := LabelAt(Actions, 'No file opened', 12, 48);
  FileLabel.Font.Style := [fsBold];
  ProgramInfoLabel := LabelAt(Actions, 'No program loaded', 12, 64);
  ProgramInfoLabel.Width := 800;
  ProgramInfoLabel.Font.Size := 9;
  ProgramInfoLabel.Font.Color := $00664400;
  ProgramInfoLabel.Anchors := [akLeft, akTop, akRight];
  ProgramInfoLabel.ShowHint := True;

  Footer := Panel(Workspace, alBottom, 62);
  ProgressLabel := LabelAt(Footer, '0 / 0 commands sent', 12, 6);
  Progress := TProgressBar.Create(Self);
  Progress.Parent := Footer;
  Progress.SetBounds(12, 31, 610, 18);
  Progress.Anchors := [akLeft, akRight, akTop];

  Pages := TPageControl.Create(Self);
  Pages.Parent := Workspace;
  Pages.Align := alClient;

  { Tab 1: Program }
  ProgramTab := TTabSheet.Create(Self);
  ProgramTab.PageControl := Pages;
  ProgramTab.Caption := 'Program';
  SearchBar := Panel(ProgramTab, alTop, 80);
  LabelAt(SearchBar, 'Search in program (Ctrl+F)', 10, 4);
  SearchEdit := TEdit.Create(Self);
  SearchEdit.Name := 'ProgramSearch';
  SearchEdit.Parent := SearchBar;
  SearchEdit.SetBounds(10, 25, 300, 28);
  SearchEdit.TextHint := 'e.g.: G1, X10 or M3';
  SearchEdit.OnChange := @SearchChanged;
  ButtonAt(SearchBar, 'Next (F3)', 324, 22, 132, @SearchClick).Name := 'FindNext';
  SearchResult := LabelAt(SearchBar, 'Case-insensitive search.', 10, 58);
  SearchResult.Name := 'SearchResult';
  ProgramMemo := TMemo.Create(Self);
  ProgramMemo.Name := 'ProgramText';
  ProgramMemo.Parent := ProgramTab;
  ProgramMemo.Align := alClient;
  ProgramMemo.ReadOnly := True;
  ProgramMemo.WordWrap := False;
  ProgramMemo.ScrollBars := ssAutoBoth;
  ProgramMemo.Font.Name := 'Consolas';
  ProgramMemo.Text := 'Open a .nc, .gcode or .tap file to inspect and run.';

  { Tab 2: Config }
  ConfigTab := TTabSheet.Create(Self);
  ConfigTab.PageControl := Pages;
  ConfigTab.Caption := 'Config';

  ConfigScrollBox := TScrollBox.Create(Self);
  ConfigScrollBox.Parent := ConfigTab;
  ConfigScrollBox.Align := alClient;
  ConfigScrollBox.BorderStyle := bsNone;
  ConfigScrollBox.HorzScrollBar.Tracking := True;
  ConfigScrollBox.VertScrollBar.Tracking := True;

  { Connection Settings Group inside Config }
  GbConnection := TGroupBox.Create(Self);
  GbConnection.Parent := ConfigScrollBox;
  GbConnection.Caption := 'Connection Settings';
  GbConnection.SetBounds(15, 10, 715, 100);

  LabelAt(GbConnection, 'Machine', 15, 5);
  MachineType := TComboBox.Create(Self);
  MachineType.Parent := GbConnection;
  MachineType.SetBounds(15, 29, 140, 30);
  MachineType.Style := csDropDownList;
  MachineType.Items.Add('CNC Router');
  MachineType.Items.Add('CNC Laser');
  MachineType.Items.Add('3D Printer');
  MachineType.ItemIndex := 0;
  MachineType.OnChange := @SelectionChanged;

  LabelAt(GbConnection, 'Protocol', 165, 5);
  ProtocolType := TComboBox.Create(Self);
  ProtocolType.Parent := GbConnection;
  ProtocolType.SetBounds(165, 29, 115, 30);
  ProtocolType.Style := csDropDownList;
  ProtocolType.Items.Add('GRBL');
  ProtocolType.Items.Add('Marlin');
  ProtocolType.ItemIndex := 0;
  ProtocolType.OnChange := @SelectionChanged;

  LabelAt(GbConnection, 'Interface', 290, 5);
  CommunicationMode := TComboBox.Create(Self);
  CommunicationMode.Parent := GbConnection;
  CommunicationMode.SetBounds(290, 29, 90, 28);
  CommunicationMode.Items.Add('Serial');
  CommunicationMode.Items.Add('TCP');
  CommunicationMode.ItemIndex := 0;
  CommunicationMode.Style := csDropDownList;
  CommunicationMode.OnChange := @CommunicationChanged;

  SerialPanel := TPanel.Create(Self);
  SerialPanel.Parent := GbConnection;
  SerialPanel.SetBounds(390, 0, 315, 75);
  SerialPanel.BevelOuter := bvNone;

  TCPPanel := TPanel.Create(Self);
  TCPPanel.Parent := GbConnection;
  TCPPanel.SetBounds(390, 0, 315, 75);
  TCPPanel.BevelOuter := bvNone;

  SerialDeviceList := TAIListSerialDevices.Create(Self);
  SerialDeviceList.IncludeSystemPorts := True;
  SerialDeviceList.IncludeUSBSerial := True;
  SerialDeviceList.IncludeBluetooth := True;

  LabelAt(SerialPanel, 'COM Port', 0, 5);
  DeviceEdit := TComboBox.Create(Self);
  DeviceEdit.Parent := SerialPanel;
  DeviceEdit.SetBounds(0, 29, 140, 30);
  DeviceEdit.Style := csDropDownList;
  DeviceEdit.Hint := 'Serial COM ports detected in the system. Click to refresh.';
  DeviceEdit.ShowHint := True;
  DeviceEdit.OnDropDown := @DeviceComboDropDown;
  RefreshSerialPorts;

  LabelAt(SerialPanel, 'Baud Rate', 150, 5);
  BaudCombo := TComboBox.Create(Self);
  BaudCombo.Parent := SerialPanel;
  BaudCombo.SetBounds(150, 29, 130, 30);
  BaudCombo.Style := csDropDown;
  BaudCombo.Items.Add('115200');
  BaudCombo.Items.Add('250000');
  BaudCombo.Items.Add('57600');
  BaudCombo.Items.Add('38400');
  BaudCombo.Items.Add('19200');
  BaudCombo.Items.Add('9600');
  BaudCombo.Text := '115200';
  BaudCombo.Hint := 'Connection baud rate speed (bps).';
  BaudCombo.ShowHint := True;

  LabelAt(TCPPanel, 'Device IP Address', 0, 5);
  HostEdit := TEdit.Create(Self);
  HostEdit.Parent := TCPPanel;
  HostEdit.SetBounds(0, 29, 160, 30);
  HostEdit.Text := '127.0.0.1';

  LabelAt(TCPPanel, 'TCP Port', 170, 5);
  PortEdit := TEdit.Create(Self);
  PortEdit.Parent := TCPPanel;
  PortEdit.SetBounds(170, 29, 90, 30);
  PortEdit.Text := '9000';

  CommunicationChanged(Self);

  { 3D Printer Profile & Specifications Group }
  GbPrinterProfile := TGroupBox.Create(Self);
  GbPrinterProfile.Parent := ConfigScrollBox;
  GbPrinterProfile.Caption := '3D Printer Brand & Model Profile';
  GbPrinterProfile.SetBounds(15, 120, 715, 230);
  GbPrinterProfile.Visible := False;

  LabelAt(GbPrinterProfile, 'Brand:', 15, 8);
  PrinterBrandCombo := TComboBox.Create(Self);
  PrinterBrandCombo.Parent := GbPrinterProfile;
  PrinterBrandCombo.SetBounds(15, 30, 220, 30);
  PrinterBrandCombo.Style := csDropDownList;
  PrinterBrandCombo.OnChange := @PrinterBrandChanged;

  LabelAt(GbPrinterProfile, 'Model:', 250, 8);
  PrinterModelCombo := TComboBox.Create(Self);
  PrinterModelCombo.Parent := GbPrinterProfile;
  PrinterModelCombo.SetBounds(250, 30, 260, 30);
  PrinterModelCombo.Style := csDropDownList;
  PrinterModelCombo.OnChange := @PrinterModelChanged;

  LabelAt(GbPrinterProfile, 'Standard Factory Specifications:', 15, 68);
  PrinterSpecsLabel := TLabel.Create(Self);
  PrinterSpecsLabel.Parent := GbPrinterProfile;
  PrinterSpecsLabel.SetBounds(15, 92, 680, 125);
  PrinterSpecsLabel.AutoSize := False;
  PrinterSpecsLabel.WordWrap := True;
  PrinterSpecsLabel.Font.Name := 'Consolas';
  PrinterSpecsLabel.Font.Size := 9;
  PrinterSpecsLabel.Font.Color := $00442200;

  { 3D Printer Temperature Configuration Group in Config Tab }
  GbPrinterTemps := TGroupBox.Create(Self);
  GbPrinterTemps.Parent := ConfigScrollBox;
  GbPrinterTemps.Caption := '3D Printer Temperature Configuration & Targets';
  GbPrinterTemps.SetBounds(15, 360, 715, 135);
  GbPrinterTemps.Visible := False;

  LabelAt(GbPrinterTemps, 'Nozzle Target (C):', 15, 6);
  SpConfigHotendTemp := TSpinEdit.Create(Self);
  SpConfigHotendTemp.Parent := GbPrinterTemps;
  SpConfigHotendTemp.SetBounds(15, 28, 120, 28);
  SpConfigHotendTemp.MinValue := 0;
  SpConfigHotendTemp.MaxValue := 300;
  SpConfigHotendTemp.Value := 200;
  SpConfigHotendTemp.Increment := 5;
  SpConfigHotendTemp.OnChange := @TempConfigChanged;

  LabelAt(GbPrinterTemps, 'Bed Target (C):', 155, 6);
  SpConfigBedTemp := TSpinEdit.Create(Self);
  SpConfigBedTemp.Parent := GbPrinterTemps;
  SpConfigBedTemp.SetBounds(155, 28, 120, 28);
  SpConfigBedTemp.MinValue := 0;
  SpConfigBedTemp.MaxValue := 130;
  SpConfigBedTemp.Value := 60;
  SpConfigBedTemp.Increment := 5;
  SpConfigBedTemp.OnChange := @TempConfigChanged;

  BtnApplyTemps := ButtonAt(GbPrinterTemps, 'Set Targets (M104/M140)', 295, 25, 220, @ApplyTempsClick);
  BtnApplyTemps.Hint := 'Send target temperature commands to the 3D printer controller.';
  BtnApplyTemps.ShowHint := True;

  BtnCooldownTemps := ButtonAt(GbPrinterTemps, 'Cooldown Heaters', 525, 25, 175, @CooldownTempsClick);
  BtnCooldownTemps.Hint := 'Turn off nozzle and bed heaters (set targets to 0 C).';
  BtnCooldownTemps.ShowHint := True;

  LblConfigRealTemps := LabelAt(GbPrinterTemps, 'Live Equipment Readings: Nozzle: - C | Bed: - C', 15, 75);
  LblConfigRealTemps.SetBounds(15, 75, 680, 45);
  LblConfigRealTemps.AutoSize := False;
  LblConfigRealTemps.WordWrap := True;
  LblConfigRealTemps.Font.Name := 'Consolas';
  LblConfigRealTemps.Font.Size := 9;
  LblConfigRealTemps.Font.Color := $00442200;
  LblConfigRealTemps.Font.Style := [fsBold];

  { Initialize brands and models }
  GetPrinterBrands(PrinterBrandCombo.Items);
  if PrinterBrandCombo.Items.Count > 0 then
  begin
    PrinterBrandCombo.ItemIndex := 0;
    GetPrinterModels(PrinterBrandCombo.Text, PrinterModelCombo.Items);
    if PrinterModelCombo.Items.Count > 0 then
      PrinterModelCombo.ItemIndex := 0;
  end;

  { Laser Container inside Config }
  LaserContainer := TPanel.Create(Self);
  LaserContainer.Parent := ConfigScrollBox;
  LaserContainer.SetBounds(0, 115, 740, 750);
  LaserContainer.BevelOuter := bvNone;
  LaserContainer.Visible := False;

  { Laser Group 1: Work Mode }
  GbWork := TGroupBox.Create(Self);
  GbWork.Parent := LaserContainer;
  GbWork.Caption := 'Work Mode';
  GbWork.SetBounds(15, 5, 320, 125);
  RbModeCut := TRadioButton.Create(Self);
  RbModeCut.Parent := GbWork;
  RbModeCut.Caption := 'Cutting';
  RbModeCut.SetBounds(15, 10, 120, 24);
  RbModeCut.Checked := True;
  RbModeCut.OnClick := @LaserParamChanged;
  RbModeEngrave := TRadioButton.Create(Self);
  RbModeEngrave.Parent := GbWork;
  RbModeEngrave.Caption := 'Engraving';
  RbModeEngrave.SetBounds(15, 40, 120, 24);
  RbModeEngrave.OnClick := @LaserParamChanged;
  RbModePerforate := TRadioButton.Create(Self);
  RbModePerforate.Parent := GbWork;
  RbModePerforate.Caption := 'Perforation / Dot';
  RbModePerforate.SetBounds(15, 70, 160, 24);
  RbModePerforate.OnClick := @LaserParamChanged;

  { Laser Group 2: Power }
  GbPower := TGroupBox.Create(Self);
  GbPower.Parent := LaserContainer;
  GbPower.Caption := 'Laser Power';
  GbPower.SetBounds(350, 5, 340, 185);
  LabelAt(GbPower, 'Laser power (%):', 15, 10);
  SpLaserPower := TSpinEdit.Create(Self);
  SpLaserPower.Parent := GbPower;
  SpLaserPower.SetBounds(210, 6, 110, 26);
  SpLaserPower.MinValue := 0; SpLaserPower.MaxValue := 100; SpLaserPower.Value := 70;
  SpLaserPower.OnChange := @LaserParamChanged;

  LabelAt(GbPower, 'Minimum power (%):', 15, 45);
  SpLaserMinPower := TSpinEdit.Create(Self);
  SpLaserMinPower.Parent := GbPower;
  SpLaserMinPower.SetBounds(210, 41, 110, 26);
  SpLaserMinPower.MinValue := 0; SpLaserMinPower.MaxValue := 100; SpLaserMinPower.Value := 0;
  SpLaserMinPower.OnChange := @LaserParamChanged;

  LabelAt(GbPower, 'Maximum power (%):', 15, 80);
  SpLaserMaxPower := TSpinEdit.Create(Self);
  SpLaserMaxPower.Parent := GbPower;
  SpLaserMaxPower.SetBounds(210, 76, 110, 26);
  SpLaserMaxPower.MinValue := 0; SpLaserMaxPower.MaxValue := 100; SpLaserMaxPower.Value := 100;
  SpLaserMaxPower.OnChange := @LaserParamChanged;

  LabelAt(GbPower, 'Max S value ($30):', 15, 115);
  SpLaserMaxS := TSpinEdit.Create(Self);
  SpLaserMaxS.Parent := GbPower;
  SpLaserMaxS.SetBounds(210, 111, 110, 26);
  SpLaserMaxS.MinValue := 1; SpLaserMaxS.MaxValue := 65535; SpLaserMaxS.Value := 1000;
  SpLaserMaxS.OnChange := @LaserParamChanged;

  { Laser Group 3: Speed }
  GbSpeed := TGroupBox.Create(Self);
  GbSpeed.Parent := LaserContainer;
  GbSpeed.Caption := 'Feed Rates (mm/min)';
  GbSpeed.SetBounds(15, 140, 320, 185);
  LabelAt(GbSpeed, 'Engraving:', 15, 10);
  SpSpeedEngrave := TSpinEdit.Create(Self);
  SpSpeedEngrave.Parent := GbSpeed;
  SpSpeedEngrave.SetBounds(190, 6, 115, 26);
  SpSpeedEngrave.MinValue := 1; SpSpeedEngrave.MaxValue := 50000; SpSpeedEngrave.Value := 3000;
  SpSpeedEngrave.OnChange := @LaserParamChanged;

  LabelAt(GbSpeed, 'Cutting:', 15, 45);
  SpSpeedCut := TSpinEdit.Create(Self);
  SpSpeedCut.Parent := GbSpeed;
  SpSpeedCut.SetBounds(190, 41, 115, 26);
  SpSpeedCut.MinValue := 1; SpSpeedCut.MaxValue := 20000; SpSpeedCut.Value := 800;
  SpSpeedCut.OnChange := @LaserParamChanged;

  LabelAt(GbSpeed, 'Rapid travel (G0):', 15, 80);
  SpSpeedTravel := TSpinEdit.Create(Self);
  SpSpeedTravel.Parent := GbSpeed;
  SpSpeedTravel.SetBounds(190, 76, 115, 26);
  SpSpeedTravel.MinValue := 1; SpSpeedTravel.MaxValue := 50000; SpSpeedTravel.Value := 5000;
  SpSpeedTravel.OnChange := @LaserParamChanged;

  ChkOverrideSpeed := TCheckBox.Create(Self);
  ChkOverrideSpeed.Parent := GbSpeed;
  ChkOverrideSpeed.Caption := 'Override file feed rates';
  ChkOverrideSpeed.SetBounds(15, 118, 280, 24);
  ChkOverrideSpeed.OnClick := @LaserParamChanged;

  { Laser Group 4: Cutting Passes }
  GbCut := TGroupBox.Create(Self);
  GbCut.Parent := LaserContainer;
  GbCut.Caption := 'Cutting Multi-Pass';
  GbCut.SetBounds(350, 200, 340, 215);
  LabelAt(GbCut, 'Pass count:', 15, 10);
  SpCutPasses := TSpinEdit.Create(Self);
  SpCutPasses.Parent := GbCut;
  SpCutPasses.SetBounds(210, 6, 110, 26);
  SpCutPasses.MinValue := 1; SpCutPasses.MaxValue := 100; SpCutPasses.Value := 1;
  SpCutPasses.OnChange := @LaserParamChanged;

  LabelAt(GbCut, 'Power per pass (%):', 15, 45);
  SpCutPassPower := TSpinEdit.Create(Self);
  SpCutPassPower.Parent := GbCut;
  SpCutPassPower.SetBounds(210, 41, 110, 26);
  SpCutPassPower.MinValue := 0; SpCutPassPower.MaxValue := 100; SpCutPassPower.Value := 100;
  SpCutPassPower.OnChange := @LaserParamChanged;

  LabelAt(GbCut, 'Feed rate per pass:', 15, 80);
  SpCutPassFeed := TSpinEdit.Create(Self);
  SpCutPassFeed.Parent := GbCut;
  SpCutPassFeed.SetBounds(210, 76, 110, 26);
  SpCutPassFeed.MinValue := 1; SpCutPassFeed.MaxValue := 20000; SpCutPassFeed.Value := 800;
  SpCutPassFeed.OnChange := @LaserParamChanged;

  LabelAt(GbCut, 'Pause per pass (ms):', 15, 115);
  SpCutPassDelay := TSpinEdit.Create(Self);
  SpCutPassDelay.Parent := GbCut;
  SpCutPassDelay.SetBounds(210, 111, 110, 26);
  SpCutPassDelay.MinValue := 0; SpCutPassDelay.MaxValue := 60000; SpCutPassDelay.Value := 0;
  SpCutPassDelay.OnChange := @LaserParamChanged;

  LabelAt(GbCut, 'Z step per pass (mm):', 15, 150);
  SpCutPassZStep := TFloatSpinEdit.Create(Self);
  SpCutPassZStep.Parent := GbCut;
  SpCutPassZStep.SetBounds(210, 146, 110, 26);
  SpCutPassZStep.MinValue := 0.0; SpCutPassZStep.MaxValue := 50.0; SpCutPassZStep.Value := 0.0;
  SpCutPassZStep.DecimalPlaces := 3; SpCutPassZStep.Increment := 0.1;
  SpCutPassZStep.OnChange := @LaserParamChanged;

  { Laser Group 5: Perforation / Dot }
  GbDot := TGroupBox.Create(Self);
  GbDot.Parent := LaserContainer;
  GbDot.Caption := 'Perforation / Dot Mode';
  GbDot.SetBounds(15, 335, 320, 185);
  LabelAt(GbDot, 'Length on (mm):', 15, 10);
  SpDotLengthOn := TFloatSpinEdit.Create(Self);
  SpDotLengthOn.Parent := GbDot;
  SpDotLengthOn.SetBounds(190, 6, 115, 26);
  SpDotLengthOn.MinValue := 0.1; SpDotLengthOn.MaxValue := 1000; SpDotLengthOn.Value := 5.0;
  SpDotLengthOn.DecimalPlaces := 1; SpDotLengthOn.Increment := 0.5;
  SpDotLengthOn.OnChange := @LaserParamChanged;

  LabelAt(GbDot, 'Length off (mm):', 15, 45);
  SpDotLengthOff := TFloatSpinEdit.Create(Self);
  SpDotLengthOff.Parent := GbDot;
  SpDotLengthOff.SetBounds(190, 41, 115, 26);
  SpDotLengthOff.MinValue := 0.1; SpDotLengthOff.MaxValue := 1000; SpDotLengthOff.Value := 2.0;
  SpDotLengthOff.DecimalPlaces := 1; SpDotLengthOff.Increment := 0.5;
  SpDotLengthOff.OnChange := @LaserParamChanged;

  LabelAt(GbDot, 'Power (%):', 15, 80);
  SpDotPower := TSpinEdit.Create(Self);
  SpDotPower.Parent := GbDot;
  SpDotPower.SetBounds(190, 76, 115, 26);
  SpDotPower.MinValue := 0; SpDotPower.MaxValue := 100; SpDotPower.Value := 70;
  SpDotPower.OnChange := @LaserParamChanged;

  LabelAt(GbDot, 'Feed rate (mm/min):', 15, 115);
  SpDotFeed := TSpinEdit.Create(Self);
  SpDotFeed.Parent := GbDot;
  SpDotFeed.SetBounds(190, 111, 115, 26);
  SpDotFeed.MinValue := 1; SpDotFeed.MaxValue := 20000; SpDotFeed.Value := 1000;
  SpDotFeed.OnChange := @LaserParamChanged;

  { Laser Group 6: Air Assist }
  GbAir := TGroupBox.Create(Self);
  GbAir.Parent := LaserContainer;
  GbAir.Caption := 'Air Assist';
  GbAir.SetBounds(350, 425, 340, 140);
  ChkAirAssist := TCheckBox.Create(Self);
  ChkAirAssist.Parent := GbAir;
  ChkAirAssist.Caption := 'Air assist enabled';
  ChkAirAssist.SetBounds(15, 10, 280, 24);
  ChkAirAssist.Checked := True;
  ChkAirAssist.OnClick := @LaserParamChanged;

  LabelAt(GbAir, 'Turn on command:', 15, 45);
  EditAirAssistOn := TEdit.Create(Self);
  EditAirAssistOn.Parent := GbAir;
  EditAirAssistOn.SetBounds(210, 41, 110, 26);
  EditAirAssistOn.Text := 'M8';
  EditAirAssistOn.OnChange := @LaserParamChanged;

  LabelAt(GbAir, 'Turn off command:', 15, 80);
  EditAirAssistOff := TEdit.Create(Self);
  EditAirAssistOff.Parent := GbAir;
  EditAirAssistOff.SetBounds(210, 76, 110, 26);
  EditAirAssistOff.Text := 'M9';
  EditAirAssistOff.OnChange := @LaserParamChanged;

  { Laser Group 7: Control & Framing }
  GbControl := TGroupBox.Create(Self);
  GbControl.Parent := LaserContainer;
  GbControl.Caption := 'Laser Control & Framing';
  GbControl.SetBounds(15, 530, 675, 205);

  RbLaserM4 := TRadioButton.Create(Self);
  RbLaserM4.Parent := GbControl;
  RbLaserM4.Caption := 'M4 - Dynamic power (Recommended GRBL)';
  RbLaserM4.SetBounds(15, 8, 300, 24);
  RbLaserM4.Checked := True;
  RbLaserM4.OnClick := @LaserParamChanged;

  RbLaserM3 := TRadioButton.Create(Self);
  RbLaserM3.Parent := GbControl;
  RbLaserM3.Caption := 'M3 - Constant power';
  RbLaserM3.SetBounds(340, 8, 280, 24);
  RbLaserM3.OnClick := @LaserParamChanged;

  ChkFramingLaser := TCheckBox.Create(Self);
  ChkFramingLaser.Parent := GbControl;
  ChkFramingLaser.Caption := 'Use framing laser (DISABLED by default)';
  ChkFramingLaser.SetBounds(15, 40, 400, 24);
  ChkFramingLaser.Checked := False;
  ChkFramingLaser.OnClick := @LaserParamChanged;

  LabelAt(GbControl, 'Framing power (%):', 15, 75);
  SpFramingPower := TSpinEdit.Create(Self);
  SpFramingPower.Parent := GbControl;
  SpFramingPower.SetBounds(210, 71, 90, 26);
  SpFramingPower.MinValue := 0; SpFramingPower.MaxValue := 10; SpFramingPower.Value := 1;
  SpFramingPower.OnChange := @LaserParamChanged;

  LabelAt(GbControl, 'Framing feed (mm/min):', 340, 75);
  SpFramingFeed := TSpinEdit.Create(Self);
  SpFramingFeed.Parent := GbControl;
  SpFramingFeed.SetBounds(550, 71, 100, 26);
  SpFramingFeed.MinValue := 1; SpFramingFeed.MaxValue := 20000; SpFramingFeed.Value := 3000;
  SpFramingFeed.OnChange := @LaserParamChanged;

  LabelAt(GbControl, 'Kerf / cut width (mm):', 15, 110);
  SpKerf := TFloatSpinEdit.Create(Self);
  SpKerf.Parent := GbControl;
  SpKerf.SetBounds(210, 106, 90, 26);
  SpKerf.MinValue := 0.0; SpKerf.MaxValue := 10.0; SpKerf.Value := 0.10;
  SpKerf.DecimalPlaces := 2; SpKerf.Increment := 0.05;
  SpKerf.OnChange := @LaserParamChanged;

  LabelAt(GbControl, 'Pre-fire delay (ms):', 340, 110);
  SpPreFireDelay := TSpinEdit.Create(Self);
  SpPreFireDelay.Parent := GbControl;
  SpPreFireDelay.SetBounds(440, 106, 70, 26);
  SpPreFireDelay.MinValue := 0; SpPreFireDelay.MaxValue := 5000; SpPreFireDelay.Value := 0;
  SpPreFireDelay.OnChange := @LaserParamChanged;

  LabelAt(GbControl, 'Post-fire delay (ms):', 525, 110);
  SpPostFireDelay := TSpinEdit.Create(Self);
  SpPostFireDelay.Parent := GbControl;
  SpPostFireDelay.SetBounds(620, 106, 70, 26);
  SpPostFireDelay.MinValue := 0; SpPostFireDelay.MaxValue := 5000; SpPostFireDelay.Value := 0;
  SpPostFireDelay.OnChange := @LaserParamChanged;

  ChkFrameBeforeStart := TCheckBox.Create(Self);
  ChkFrameBeforeStart.Parent := GbControl;
  ChkFrameBeforeStart.Caption := 'Execute framing before job start (prompts for confirmation)';
  ChkFrameBeforeStart.SetBounds(15, 145, 550, 24);
  ChkFrameBeforeStart.Checked := False;
  ChkFrameBeforeStart.OnClick := @LaserParamChanged;

  { Tab 3: Console }
  ConsoleTab := TTabSheet.Create(Self);
  ConsoleTab.PageControl := Pages;
  ConsoleTab.Caption := 'Console';
  LogBar := Panel(ConsoleTab, alTop, 50);
  ButtonAt(LogBar, 'Save Log...', 10, 8, 150, @SaveLogClick);
  ButtonAt(LogBar, 'Clear Console', 172, 8, 150, @ClearLogClick).Name := 'ClearConsole';
  ConsoleBar := Panel(ConsoleTab, alBottom, 50);
  BtnSend := ButtonAt(ConsoleBar, 'Send', 0, 8, 100, @CommandClick);
  BtnSend.Align := alRight;
  EditCommand := TEdit.Create(Self);
  EditCommand.Parent := ConsoleBar;
  EditCommand.Align := alClient;
  EditCommand.TextHint := 'Manual G-code command';
  MemoLog := TMemo.Create(Self);
  MemoLog.Name := 'ConsoleLog';
  MemoLog.Parent := ConsoleTab;
  MemoLog.Align := alClient;
  MemoLog.ReadOnly := True;
  MemoLog.ScrollBars := ssAutoBoth;
  MemoLog.WordWrap := False;
  MemoLog.Font.Name := 'Consolas';

  Pages.ActivePage := ProgramTab;
  Timer := TTimer.Create(Self);
  Timer.Enabled := False;
  Timer.Interval := 100;
  Timer.OnTimer := @Tick;

  SyncLaserSettingsToUI;
  SelectionChanged(MachineType);
  UpdateMachineTypeLayout;
  UpdateControls;
end;

destructor TMainForm.Destroy;
begin
  if Assigned(Timer) then Timer.Enabled := False;
  Session.Free;
  SerialDeviceList.Free;
  inherited Destroy;
end;

procedure TMainForm.RefreshSerialPorts;
var
  CurrentPort: string;
  Ports: TStringList;
  I: Integer;
begin
  if not Assigned(SerialDeviceList) or not Assigned(DeviceEdit) then Exit;
  CurrentPort := Trim(DeviceEdit.Text);
  Ports := TStringList.Create;
  try
    SerialDeviceList.Refresh;
    SerialDeviceList.GetDeviceNames(Ports);
    DeviceEdit.Items.BeginUpdate;
    try
      DeviceEdit.Items.Clear;
      for I := 0 to Ports.Count - 1 do
        DeviceEdit.Items.Add(Ports[I]);
    finally
      DeviceEdit.Items.EndUpdate;
    end;

    if CurrentPort <> '' then
      DeviceEdit.ItemIndex := DeviceEdit.Items.IndexOf(CurrentPort);

    if (DeviceEdit.ItemIndex < 0) and (DeviceEdit.Items.Count > 0) then
      DeviceEdit.ItemIndex := 0;
  finally
    Ports.Free;
  end;
end;

procedure TMainForm.DeviceComboDropDown(Sender: TObject);
begin
  RefreshSerialPorts;
end;

procedure TMainForm.PrinterBrandChanged(Sender: TObject);
begin
  GetPrinterModels(PrinterBrandCombo.Text, PrinterModelCombo.Items);
  if PrinterModelCombo.Items.Count > 0 then
  begin
    PrinterModelCombo.ItemIndex := 0;
    PrinterModelChanged(nil);
  end
  else
    PrinterSpecsLabel.Caption := 'No models available for selected brand.';
end;

procedure TMainForm.PrinterModelChanged(Sender: TObject);
var
  Prof: TPrinterProfile;
  BedStr: string;
begin
  if FindPrinterProfile(PrinterBrandCombo.Text, PrinterModelCombo.Text, Prof) then
  begin
    BaudCombo.Text := IntToStr(Prof.BaudRate);
    Session.SetWorkEnvelope(Prof.VolumeX, Prof.VolumeY, Prof.VolumeZ);
    Session.SetThermalLimits(Prof.MaxHotendTemp, Prof.MaxBedTemp);

    SpConfigHotendTemp.MaxValue := Prof.MaxHotendTemp;
    if SpConfigHotendTemp.Value > Prof.MaxHotendTemp then
      SpConfigHotendTemp.Value := Prof.MaxHotendTemp;

    SpConfigBedTemp.MaxValue := Prof.MaxBedTemp;
    if SpConfigBedTemp.Value > Prof.MaxBedTemp then
      SpConfigBedTemp.Value := Prof.MaxBedTemp;

    if Prof.HasHeatedBed then
    begin
      BedStr := 'Yes';
      SpConfigBedTemp.Enabled := True;
      if SpConfigBedTemp.Value = 0 then SpConfigBedTemp.Value := 60;
    end
    else
    begin
      BedStr := 'No';
      SpConfigBedTemp.Value := 0;
      SpConfigBedTemp.Enabled := False;
    end;

    PrinterSpecsLabel.Caption := Format(
      'Brand & Model: %s %s' + LineEnding +
      'Build Volume (X x Y x Z): %.0f x %.0f x %.0f mm' + LineEnding +
      'Default Baud: %d | Protocol / Firmware: %s' + LineEnding +
      'Max Safe Hotend Temp: %d C | Max Safe Bed Temp: %d C (Heated: %s)' + LineEnding +
      'Filament Diameter: %.2f mm' + LineEnding +
      'Notes: %s',
      [Prof.Brand, Prof.Model,
       Prof.VolumeX, Prof.VolumeY, Prof.VolumeZ,
       Prof.BaudRate, Prof.Firmware,
       Prof.MaxHotendTemp, Prof.MaxBedTemp, BedStr,
       Prof.FilamentDiameter, Prof.Notes]);
    Log(Format('3D Printer profile applied: %s %s (Table: %.0fx%.0fx%.0f mm, Baud: %d, MaxHotend: %d C, MaxBed: %d C)',
      [Prof.Brand, Prof.Model, Prof.VolumeX, Prof.VolumeY, Prof.VolumeZ, Prof.BaudRate, Prof.MaxHotendTemp, Prof.MaxBedTemp]));
  end
  else
    PrinterSpecsLabel.Caption := 'Profile not found.';
end;

procedure TMainForm.TempConfigChanged(Sender: TObject);
var
  Prof: TPrinterProfile;
  MaxHotend, MaxBed: Integer;
begin
  MaxHotend := DEFAULT_MAX_HOTEND_TEMP;
  MaxBed := DEFAULT_MAX_BED_TEMP;
  if FindPrinterProfile(PrinterBrandCombo.Text, PrinterModelCombo.Text, Prof) then
  begin
    MaxHotend := Prof.MaxHotendTemp;
    MaxBed := Prof.MaxBedTemp;
  end;

  if SpConfigHotendTemp.Value > MaxHotend then
  begin
    SpConfigHotendTemp.Value := MaxHotend;
    Log(Format('AVISO DE SEGURANÇA: Temperatura do bico limitada a %d C conforme especificações do fabricante.', [MaxHotend]));
  end;

  if SpConfigBedTemp.Value > MaxBed then
  begin
    SpConfigBedTemp.Value := MaxBed;
    Log(Format('AVISO DE SEGURANÇA: Temperatura da cama limitada a %d C conforme especificações do fabricante.', [MaxBed]));
  end;

  UpdateControls;
end;

procedure TMainForm.ApplyTempsClick(Sender: TObject);
var
  Prof: TPrinterProfile;
  MaxHotend, MaxBed: Integer;
begin
  if not Session.Connected then
  begin
    Log('Connect to 3D printer before setting temperatures.');
    Exit;
  end;

  MaxHotend := DEFAULT_MAX_HOTEND_TEMP;
  MaxBed := DEFAULT_MAX_BED_TEMP;
  if FindPrinterProfile(PrinterBrandCombo.Text, PrinterModelCombo.Text, Prof) then
  begin
    MaxHotend := Prof.MaxHotendTemp;
    MaxBed := Prof.MaxBedTemp;
  end;

  if SpConfigHotendTemp.Value > MaxHotend then
  begin
    MessageDlg('Bloqueio de Segurança Térmica',
      Format('A temperatura solicitada para o bico (%d C) ultrapassa o limite seguro do fabricante (%d C).' + LineEnding +
             'O valor foi corrigido para evitar superaquecimento e queima do bico/extrusor.',
             [SpConfigHotendTemp.Value, MaxHotend]), mtWarning, [mbOK], 0);
    SpConfigHotendTemp.Value := MaxHotend;
  end;

  if SpConfigBedTemp.Enabled and (SpConfigBedTemp.Value > MaxBed) then
  begin
    MessageDlg('Bloqueio de Segurança Térmica',
      Format('A temperatura solicitada para a cama (%d C) ultrapassa o limite seguro do fabricante (%d C).' + LineEnding +
             'O valor foi corrigido para evitar danos à cama aquecida.',
             [SpConfigBedTemp.Value, MaxBed]), mtWarning, [mbOK], 0);
    SpConfigBedTemp.Value := MaxBed;
  end;

  Session.SetHotendTemperature(SpConfigHotendTemp.Value);
  if SpConfigBedTemp.Enabled and (SpConfigBedTemp.Value > 0) then
    Session.SetBedTemperature(SpConfigBedTemp.Value);
  Log(Format('Sent Temperature Targets: Nozzle = %.0f C (Max: %d C), Bed = %.0f C (Max: %d C) (M104/M140)',
    [Double(SpConfigHotendTemp.Value), MaxHotend, Double(SpConfigBedTemp.Value), MaxBed], InvariantFS));
  UpdateControls;
end;

procedure TMainForm.CooldownTempsClick(Sender: TObject);
begin
  if not Session.Connected then
  begin
    Log('Connect to 3D printer before cooling down.');
    Exit;
  end;
  Session.SetHotendTemperature(0);
  Session.SetBedTemperature(0);
  Log('Cooldown heaters: Nozzle and Bed target set to 0 C (M104 S0, M140 S0)');
  UpdateControls;
end;

procedure TMainForm.SyncLaserSettingsToUI;
var S: TLaserSettings;
begin
  S := Session.LaserSettings;
  RbModeCut.Checked := S.WorkMode = lwmCut;
  RbModeEngrave.Checked := S.WorkMode = lwmEngrave;
  RbModePerforate.Checked := S.WorkMode = lwmPerforate;
  SpLaserPower.Value := Round(S.LaserPower);
  SpLaserMinPower.Value := Round(S.MinPower);
  SpLaserMaxPower.Value := Round(S.MaxPower);
  SpLaserMaxS.Value := S.MaxS;
  SpSpeedEngrave.Value := Round(S.EngraveFeed);
  SpSpeedCut.Value := Round(S.CutFeed);
  SpSpeedTravel.Value := Round(S.RapidFeed);
  ChkOverrideSpeed.Checked := S.OverrideSpeeds;
  SpCutPasses.Value := S.PassCount;
  SpCutPassPower.Value := Round(S.PassPower);
  SpCutPassFeed.Value := Round(S.PassFeed);
  SpCutPassDelay.Value := S.PassPauseMS;
  SpCutPassZStep.Value := S.PassZStep;
  SpDotLengthOn.Value := S.PerforateOnLength;
  SpDotLengthOff.Value := S.PerforateOffLength;
  SpDotPower.Value := Round(S.PerforatePower);
  SpDotFeed.Value := Round(S.PerforateFeed);
  ChkAirAssist.Checked := S.AirAssist;
  EditAirAssistOn.Text := S.AirAssistOnCmd;
  EditAirAssistOff.Text := S.AirAssistOffCmd;
  RbLaserM4.Checked := S.ControlMode = lcmM4Dynamic;
  RbLaserM3.Checked := S.ControlMode = lcmM3Constant;
  ChkFramingLaser.Checked := S.FramingLaser;
  SpFramingPower.Value := Round(S.FramingPower);
  SpFramingFeed.Value := Round(S.FramingFeed);
  SpPreFireDelay.Value := S.PreFireMS;
  SpPostFireDelay.Value := S.PostFireMS;
  SpKerf.Value := S.Kerf;
  ChkFrameBeforeStart.Checked := S.FrameBeforeStart;
end;

procedure TMainForm.SyncLaserSettingsFromUI;
var S: TLaserSettings;
begin
  S := Session.LaserSettings;
  if RbModeEngrave.Checked then S.WorkMode := lwmEngrave
  else if RbModePerforate.Checked then S.WorkMode := lwmPerforate
  else S.WorkMode := lwmCut;

  S.LaserPower := SpLaserPower.Value;
  S.MinPower := SpLaserMinPower.Value;
  S.MaxPower := SpLaserMaxPower.Value;
  S.MaxS := SpLaserMaxS.Value;
  S.EngraveFeed := SpSpeedEngrave.Value;
  S.CutFeed := SpSpeedCut.Value;
  S.RapidFeed := SpSpeedTravel.Value;
  S.OverrideSpeeds := ChkOverrideSpeed.Checked;
  S.PassCount := SpCutPasses.Value;
  S.PassPower := SpCutPassPower.Value;
  S.PassFeed := SpCutPassFeed.Value;
  S.PassPauseMS := SpCutPassDelay.Value;
  S.PassZStep := SpCutPassZStep.Value;
  S.PerforateOnLength := SpDotLengthOn.Value;
  S.PerforateOffLength := SpDotLengthOff.Value;
  S.PerforatePower := SpDotPower.Value;
  S.PerforateFeed := SpDotFeed.Value;
  S.AirAssist := ChkAirAssist.Checked;
  S.AirAssistOnCmd := Trim(EditAirAssistOn.Text);
  S.AirAssistOffCmd := Trim(EditAirAssistOff.Text);
  if RbLaserM3.Checked then S.ControlMode := lcmM3Constant
  else S.ControlMode := lcmM4Dynamic;
  S.FramingLaser := ChkFramingLaser.Checked;
  S.FramingPower := SpFramingPower.Value;
  S.FramingFeed := SpFramingFeed.Value;
  S.PreFireMS := SpPreFireDelay.Value;
  S.PostFireMS := SpPostFireDelay.Value;
  SpKerf.Value := S.Kerf;
  S.FrameBeforeStart := ChkFrameBeforeStart.Checked;

  Session.LaserSettings := S;
end;

procedure TMainForm.LaserParamChanged(Sender: TObject);
begin
  SyncLaserSettingsFromUI;
  UpdateControls;
end;

procedure TMainForm.Log(const AText: string);
begin
  MemoLog.Lines.BeginUpdate;
  try
    MemoLog.Lines.Add(FormatDateTime('hh:nn:ss', Now) + '  ' + Trim(AText));
    while MemoLog.Lines.Count > 1000 do MemoLog.Lines.Delete(0);
    MemoLog.SelStart := UTF8Length(MemoLog.Text);
  finally
    MemoLog.Lines.EndUpdate;
  end;
end;

procedure TMainForm.UpdateControls;
const StateNames: array[TSessionState] of string = ('Disconnected', 'Ready',
  'Running', 'Paused', 'Program completed', 'Stopped', 'Error');
var
  Busy, Manual, Alarm: Boolean; I: Integer; P, H: TMachinePosition; Info: string;
  T: TPrinterTemperatures; HRealStr, BRealStr, HStat: string;
begin
  Busy := Session.State in [ssRunning, ssPaused];
  Manual := Session.Connected and Session.ControllerReady and not Busy;
  Alarm := Session.MachineState = msAlarm;
  StateLabel.Caption := StateNames[Session.State];
  if Session.Connected and not Session.ControllerReady then
    StateLabel.Caption := 'Initializing Marlin...';
  if Alarm then StateLabel.Caption := StateLabel.Caption + ' | ALARM';
  if Session.Connected then
  begin
    P := Session.Position;
    PositionLabel.Caption := Format('Machine: %s' + LineEnding + 'X %9.3f  Y %9.3f' + LineEnding + 'Z %9.3f',
      [MachineStateToString(Session.MachineState), P.X, P.Y, P.Z], InvariantFS);
    if Session.HomePositionSet then
    begin
      H := Session.HomePosition;
      HomeLabel.Caption := Format('HOME ref: X %.3f' + LineEnding + 'Y %.3f  Z %.3f (G28.1)', [H.X, H.Y, H.Z], InvariantFS);
    end
    else
      HomeLabel.Caption := 'HOME: [Not referenced]';
  end
  else
  begin
    PositionLabel.Caption := 'Position: -';
    HomeLabel.Caption := 'HOME: -';
  end;

  { 3D Printer Temperature Indicator Updates }
  if MachineType.ItemIndex = 2 then
  begin
    T := Session.Temperatures;
    if Session.Connected and T.HasReadings then
    begin
      HRealStr := Format('%.1f C', [T.HotendActual], InvariantFS);
      BRealStr := Format('%.1f C', [T.BedActual], InvariantFS);

      if (T.HotendTarget > 0) or (T.BedTarget > 0) then
        HStat := Format('Target active: Nozzle %.0f C | Bed %.0f C', [T.HotendTarget, T.BedTarget], InvariantFS)
      else
        HStat := 'Heaters Standby / Off';

      LblNozzleTemp.Caption := Format('Real: %s  |  Config: %.0f C', [HRealStr, 1.0 * SpConfigHotendTemp.Value], InvariantFS);
      LblBedTemp.Caption := Format('Real: %s  |  Config: %.0f C', [BRealStr, 1.0 * SpConfigBedTemp.Value], InvariantFS);
      LblHeaterStatus.Caption := HStat;

      LblConfigRealTemps.Caption := Format('Live Equipment Readings: Nozzle: %s (Target: %.0f C) | Bed: %s (Target: %.0f C)',
        [HRealStr, T.HotendTarget, BRealStr, T.BedTarget], InvariantFS);
    end
    else
    begin
      LblNozzleTemp.Caption := Format('Real: - C  |  Config: %.0f C', [1.0 * SpConfigHotendTemp.Value], InvariantFS);
      LblBedTemp.Caption := Format('Real: - C  |  Config: %.0f C', [1.0 * SpConfigBedTemp.Value], InvariantFS);
      if Session.Connected and not Session.ControllerReady then
        LblHeaterStatus.Caption := 'Initializing Marlin...'
      else if Session.Connected then
        LblHeaterStatus.Caption := 'Reading temperatures...'
      else
        LblHeaterStatus.Caption := 'Heaters Disconnected';
      LblConfigRealTemps.Caption := 'Live Equipment Readings: [Not connected or no reading yet]';
    end;
  end;

  MachineType.Enabled := not Session.Connected;
  ProtocolType.Enabled := not Session.Connected;
  CommunicationMode.Enabled := not Session.Connected;
  HostEdit.Enabled := not Session.Connected;
  PortEdit.Enabled := not Session.Connected;
  DeviceEdit.Enabled := not Session.Connected;
  BaudCombo.Enabled := not Session.Connected;
  if Assigned(PrinterBrandCombo) then PrinterBrandCombo.Enabled := not Session.Connected;
  if Assigned(PrinterModelCombo) then PrinterModelCombo.Enabled := not Session.Connected;

  if Session.Connected then BtnConnect.Caption := 'Disconnect' else BtnConnect.Caption := 'Connect Device';
  BtnConnect.Enabled := not Busy;
  BtnOpen.Enabled := not Busy;
  BtnFraming.Enabled := Session.Connected and not Busy and (Session.Count > 0);
  BtnStart.Enabled := Session.Connected and Session.ControllerReady and not Busy and (Session.Count > 0);
  BtnPause.Enabled := Session.State = ssRunning;
  BtnResume.Enabled := Session.State = ssPaused;
  BtnStop.Enabled := Session.Connected;
  BtnHome.Enabled := Manual and not Alarm;
  BtnSetHome.Visible := MachineType.ItemIndex <> 2;
  BtnSetHome.Enabled := Manual and not Alarm and (MachineType.ItemIndex <> 2);
  BtnPhysicalHome.Enabled := Manual;
  BtnZero.Visible := MachineType.ItemIndex <> 2;
  BtnZero.Enabled := Manual and not Alarm and (MachineType.ItemIndex <> 2);
  BtnStatus.Enabled := Session.Connected;
  BtnUnlock.Enabled := Manual;
  BtnSend.Enabled := Manual;
  EditCommand.Enabled := Manual;
  StepSize.Enabled := Manual and not Alarm;
  FeedRate.Enabled := Manual and not Alarm;
  for I := 0 to 5 do JogButtons[I].Enabled := Manual and not Alarm and Session.SupportsAxis(TAxis(I div 2));
  Progress.Max := Session.Count;
  if Progress.Max = 0 then Progress.Max := 1;
  Progress.Position := Session.Completed;
  ProgressLabel.Caption := Format('%d / %d commands confirmed', [Session.Completed, Session.Count]);

  { Program and Work Area Info }
  if Session.Count > 0 then
  begin
    FileLabel.Caption := ExtractFileName(Session.FileName);
    FileLabel.Hint := Session.FileName;
    if Session.Bounds.HasMotion then
      Info := Format('Bounds: %.2f x %.2f mm | X: %.2f -> %.2f mm | Y: %.2f -> %.2f mm',
        [BoundsWidth(Session.Bounds), BoundsHeight(Session.Bounds),
         Session.Bounds.MinX, Session.Bounds.MaxX,
         Session.Bounds.MinY, Session.Bounds.MaxY], InvariantFS)
    else
      Info := 'Bounds: non-dimensional motion path';

    if MachineType.ItemIndex = 1 then { CNC Laser }
      Info := Info + ' | ' + LaserSummaryString(Session.LaserSettings);

    ProgramInfoLabel.Caption := Info;
    ProgramInfoLabel.Hint := Info;
  end
  else
  begin
    FileLabel.Caption := 'No file opened';
    FileLabel.Hint := '';
    ProgramInfoLabel.Caption := 'No program loaded';
    ProgramInfoLabel.Hint := '';
  end;

  Timer.Enabled := Session.Connected;
end;

procedure TMainForm.UpdateMachineTypeLayout;
begin
  if MachineType.ItemIndex = 1 then { CNC Laser }
  begin
    BtnFraming.Visible := True;
    BtnOpen.SetBounds(12, 10, 160, 34);
    BtnFraming.SetBounds(178, 10, 110, 34);
    BtnStart.SetBounds(294, 10, 95, 34);
    BtnPause.SetBounds(395, 10, 95, 34);
    BtnResume.SetBounds(496, 10, 95, 34);
    BtnStop.SetBounds(597, 10, 130, 34);

    LaserContainer.Visible := True;
    GbPrinterProfile.Visible := False;
    GbPrinterTemps.Visible := False;
    GbSideTemperatures.Visible := False;

    BtnHome.SetBounds(20, 328, 108, 34);
    BtnSetHome.SetBounds(132, 328, 116, 34);
    BtnSetHome.Visible := True;
    BtnPhysicalHome.SetBounds(20, 368, 108, 34);
    BtnZero.SetBounds(132, 368, 116, 34);
    BtnZero.Visible := True;
    BtnStatus.SetBounds(20, 408, 108, 34);
    BtnUnlock.SetBounds(132, 408, 116, 34);
    PositionLabel.Top := 452;
    HomeLabel.Visible := True;
    HomeLabel.Top := 512;
  end
  else if MachineType.ItemIndex = 2 then { 3D Printer }
  begin
    BtnFraming.Visible := False;
    BtnOpen.SetBounds(12, 10, 170, 34);
    BtnStart.SetBounds(188, 10, 100, 34);
    BtnPause.SetBounds(294, 10, 100, 34);
    BtnResume.SetBounds(400, 10, 100, 34);
    BtnStop.SetBounds(506, 10, 132, 34);

    LaserContainer.Visible := False;
    GbPrinterProfile.Visible := True;
    GbPrinterTemps.Visible := True;
    GbSideTemperatures.Visible := True;
    PrinterModelChanged(nil);

    BtnSetHome.Visible := False;
    BtnZero.Visible := False;
    BtnHome.SetBounds(20, 328, 228, 34);
    BtnPhysicalHome.SetBounds(20, 368, 228, 34);
    BtnStatus.SetBounds(20, 408, 108, 34);
    BtnUnlock.SetBounds(132, 408, 116, 34);
    PositionLabel.Top := 452;
    HomeLabel.Visible := False;
  end
  else { CNC Router }
  begin
    BtnFraming.Visible := False;
    BtnOpen.SetBounds(12, 10, 170, 34);
    BtnStart.SetBounds(188, 10, 100, 34);
    BtnPause.SetBounds(294, 10, 100, 34);
    BtnResume.SetBounds(400, 10, 100, 34);
    BtnStop.SetBounds(506, 10, 132, 34);

    LaserContainer.Visible := False;
    GbPrinterProfile.Visible := False;
    GbPrinterTemps.Visible := False;
    GbSideTemperatures.Visible := False;

    BtnHome.SetBounds(20, 328, 108, 34);
    BtnSetHome.SetBounds(132, 328, 116, 34);
    BtnSetHome.Visible := True;
    BtnPhysicalHome.SetBounds(20, 368, 108, 34);
    BtnZero.SetBounds(132, 368, 116, 34);
    BtnZero.Visible := True;
    BtnStatus.SetBounds(20, 408, 108, 34);
    BtnUnlock.SetBounds(132, 408, 116, 34);
    PositionLabel.Top := 452;
    HomeLabel.Visible := True;
    HomeLabel.Top := 512;
  end;
end;

procedure TMainForm.SelectionChanged(Sender: TObject);
var
  SavedBaud: string;
begin
  SavedBaud := Trim(BaudCombo.Text);
  BaudCombo.Items.BeginUpdate;
  try
    BaudCombo.Items.Clear;
    case MachineType.ItemIndex of
      0: { CNC Router }
      begin
        BtnOpen.Caption := 'Open CNC Program...';
        if Sender = MachineType then ProtocolType.ItemIndex := 0;
        { Standard CNC Router baud rates (GRBL) }
        BaudCombo.Items.Add('115200'); { Standard for GRBL 1.1 / 3018-PRO }
        BaudCombo.Items.Add('250000'); { High-speed 32-bit controllers }
        BaudCombo.Items.Add('57600');
        BaudCombo.Items.Add('38400');
        BaudCombo.Items.Add('19200');
        BaudCombo.Items.Add('9600');   { Legacy GRBL 0.8/0.9 }
        if (SavedBaud <> '') and (BaudCombo.Items.IndexOf(SavedBaud) >= 0) then
          BaudCombo.Text := SavedBaud
        else
          BaudCombo.Text := '115200';
        Session.SetWorkEnvelope(300.0, 180.0, 45.0); { Standard CNC Router 3018 work volume }
        Log('Configuração CNC Router: Baud rate padrão 115200, mesa padrão 300x180x45 mm.');
      end;
      1: { CNC Laser }
      begin
        BtnOpen.Caption := 'Open CNC / Laser Program...';
        if Sender = MachineType then ProtocolType.ItemIndex := 0;
        { Standard CNC Laser baud rates (GRBL Laser Mode) }
        BaudCombo.Items.Add('115200'); { Standard for GRBL 1.1f Laser Mode (LaserGRBL/LightBurn) }
        BaudCombo.Items.Add('230400'); { Standard for 32-bit laser engravers (Sculpfun, Atomstack, xTool) }
        BaudCombo.Items.Add('250000'); { High-speed 32-bit boards }
        BaudCombo.Items.Add('57600');
        BaudCombo.Items.Add('38400');
        BaudCombo.Items.Add('19200');
        BaudCombo.Items.Add('9600');   { Legacy diode lasers }
        if (SavedBaud <> '') and (BaudCombo.Items.IndexOf(SavedBaud) >= 0) then
          BaudCombo.Text := SavedBaud
        else
          BaudCombo.Text := '115200';
        Session.SetWorkEnvelope(400.0, 400.0, 0.0); { Standard desktop laser 400x400 mm }
        Log('Configuração CNC Laser: Baud rate padrão 115200 (suporte a 230400), área de trabalho padrão 400x400 mm.');
      end;
      2: { 3D Printer }
      begin
        BtnOpen.Caption := 'Open G-code...';
        if Sender = MachineType then ProtocolType.ItemIndex := 1;
        { Standard 3D Printer baud rates (Marlin) }
        BaudCombo.Items.Add('115200'); { Creality, Prusa, Elegoo }
        BaudCombo.Items.Add('250000'); { Anycubic, Artillery, RAMPS }
        BaudCombo.Items.Add('57600');
        BaudCombo.Items.Add('38400');
        BaudCombo.Items.Add('19200');
        BaudCombo.Items.Add('9600');
        PrinterModelChanged(nil);
      end;
    end;
  finally
    BaudCombo.Items.EndUpdate;
  end;
  UpdateMachineTypeLayout;
  UpdateControls;
end;

procedure TMainForm.CommunicationChanged(Sender: TObject);
begin
  SerialPanel.Visible := CommunicationMode.ItemIndex = 0;
  TCPPanel.Visible := CommunicationMode.ItemIndex = 1;
  if SerialPanel.Visible and Assigned(SerialDeviceList) then
    RefreshSerialPorts;
end;

procedure TMainForm.ConnectClick(Sender: TObject);
var Endpoint: string; Baud, PortNumber: Integer;
begin
  if Session.Connected then begin
    Session.Disconnect;
    Log('Device disconnected.');
  end else begin
    Baud := 115200;
    if CommunicationMode.ItemIndex = 0 then begin
      Endpoint := Trim(DeviceEdit.Text);
      if (Endpoint = '') or (Pos(':', Endpoint) > 0) then begin
        Log('No serial port selected. Connect device and select port.'); Exit;
      end;
      if not TryStrToInt(Trim(BaudCombo.Text), Baud) or (Baud <= 0) then begin
        Log('Please enter a valid positive baud rate.'); Exit;
      end;
    end else begin
      if (Trim(HostEdit.Text) = '') or (Pos(':', HostEdit.Text) > 0) then begin
        Log('Enter device IPv4 address in IP field.'); Exit;
      end;
      if not TryStrToInt(Trim(PortEdit.Text), PortNumber) or
         (PortNumber < 1) or (PortNumber > 65535) then begin
        Log('TCP port must be between 1 and 65535.'); Exit;
      end;
      Endpoint := Trim(HostEdit.Text) + ':' + IntToStr(PortNumber);
    end;
    try
      SyncLaserSettingsFromUI;
      if Session.Connect(TMachineType(MachineType.ItemIndex),
        TProtocolKind(ProtocolType.ItemIndex), Endpoint, Baud) then
      begin
        Log('Connected: ' + MachineType.Text + ' / ' + ProtocolType.Text + ' at ' + Endpoint);
        if MachineType.ItemIndex = 2 then
          Log('Marlin conectado. Aguardando inicializacao da controladora antes do handshake M115/M105...')
        else
          Session.SetFeedRate(FeedRate.Value);
      end
      else Log('Failed to connect to ' + Endpoint + '. Check port and device.');
    except
      on E: Exception do Log('Connection failure: ' + E.Message);
    end;
  end;
  UpdateControls;
end;

procedure TMainForm.OpenClick(Sender: TObject);
var D: TOpenDialog;
begin
  D := TOpenDialog.Create(Self);
  try
    D.Title := 'Open Program';
    if MachineType.ItemIndex = 2 then begin
      D.Title := 'Open 3D Printer G-code';
      D.Filter := 'G-code files|*.gcode;*.gco;*.nc;*.ngc|All files|*.*';
    end else begin
      D.Title := 'Open CNC / Laser Program';
      D.Filter := 'CNC programs|*.nc;*.tap;*.cnc;*.ngc;*.gcode|All files|*.*';
    end;
    D.Options := [ofFileMustExist, ofEnableSizing];
    if not D.Execute then Exit;
    LoadProgram(D.FileName);
  finally
    D.Free;
    UpdateControls;
  end;
end;

procedure TMainForm.LoadProgram(const AFileName: string);
begin
  try
    Session.LoadFile(AFileName);
    ProgramMemo.Text := Session.ProgramText;
    ProgramMemo.SelStart := 0;
    SearchEdit.Clear;
    FileLabel.Caption := ExtractFileName(Session.FileName);
    FileLabel.Hint := Session.FileName;
    Pages.ActivePage := ProgramTab;
    Log('Program loaded: ' + Session.FileName);
    if Session.Bounds.HasMotion then
      Log(Format('Workpiece dimensions: %.2f x %.2f mm (X: %.2f..%.2f, Y: %.2f..%.2f)',
        [BoundsWidth(Session.Bounds), BoundsHeight(Session.Bounds),
         Session.Bounds.MinX, Session.Bounds.MaxX,
         Session.Bounds.MinY, Session.Bounds.MaxY], InvariantFS));
  except
    on E: Exception do MessageDlg('Could not open file', E.Message, mtError, [mbOK], 0);
  end;
  UpdateControls;
end;

procedure TMainForm.DropFiles(Sender: TObject; const FileNames: array of string);
begin
  if Length(FileNames) <> 1 then begin
    Status.SimpleText := 'Only drop one G-code file at a time.';
    Exit;
  end;
  if Session.State in [ssRunning, ssPaused] then begin
    Status.SimpleText := 'Stop the program before opening another file.';
    Exit;
  end;
  LoadProgram(FileNames[0]);
end;

procedure TMainForm.SearchChanged(Sender: TObject);
begin
  ProgramMemo.SelStart := 0;
  ProgramMemo.SelLength := 0;
  SearchResult.Caption := 'Press Enter or F3 to search. Search wraps to start.';
end;

procedure TMainForm.SearchClick(Sender: TObject);
var Source, Query: string; Offset, FoundAt, LineNo, I: Integer; Wrapped: Boolean;
begin
  Query := UpperCase(SearchEdit.Text);
  if Query = '' then begin SearchResult.Caption := 'Please enter text to search.'; Exit; end;
  Source := UpperCase(ProgramMemo.Text);
  Offset := Length(UTF8Copy(Source, 1, ProgramMemo.SelStart + ProgramMemo.SelLength)) + 1;
  FoundAt := PosEx(Query, Source, Offset);
  Wrapped := (FoundAt = 0) and (Offset > 1);
  if Wrapped then FoundAt := PosEx(Query, Source, 1);
  if FoundAt = 0 then begin SearchResult.Caption := 'Text not found.'; Exit; end;
  Pages.ActivePage := ProgramTab;
  ProgramMemo.SelStart := UTF8Length(Copy(Source, 1, FoundAt - 1));
  ProgramMemo.SelLength := UTF8Length(Query);
  LineNo := 1;
  for I := 1 to FoundAt - 1 do if Source[I] = #10 then Inc(LineNo);
  SearchResult.Caption := Format('Command %d in loaded program', [LineNo]);
  if Wrapped then SearchResult.Caption := SearchResult.Caption + ' (wrapped to beginning)';
  ProgramMemo.HideSelection := False;
end;

procedure TMainForm.Shortcut(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Shift = [ssCtrl]) and (Key = Ord('O')) then begin
    if BtnOpen.Enabled then OpenClick(Sender);
    Key := 0;
  end else if (Shift = [ssCtrl]) and (Key = Ord('F')) then begin
    Pages.ActivePage := ProgramTab;
    SearchEdit.SetFocus;
    SearchEdit.SelectAll;
    Key := 0;
  end else if ((Shift = []) and (Key = VK_F3)) or
    ((Shift = []) and (Key = VK_RETURN) and (ActiveControl = SearchEdit)) then begin
    SearchClick(Sender);
    Key := 0;
  end;
end;

procedure TMainForm.SaveLogClick(Sender: TObject);
var D: TSaveDialog;
begin
  D := TSaveDialog.Create(Self);
  try
    D.Title := 'Save Console Log';
    D.Filter := 'Text file|*.txt';
    D.DefaultExt := 'txt';
    D.FileName := 'multicnc-' + FormatDateTime('yyyymmdd-hhnnss', Now) + '.txt';
    D.Options := [ofOverwritePrompt, ofPathMustExist, ofEnableSizing];
    if D.Execute then
      try
        MemoLog.Lines.SaveToFile(D.FileName);
        Status.SimpleText := 'Log saved: ' + D.FileName;
      except
        on E: Exception do MessageDlg('Failed to save log', E.Message, mtError, [mbOK], 0);
      end;
  finally
    D.Free;
  end;
end;

procedure TMainForm.ClearLogClick(Sender: TObject);
begin
  MemoLog.Clear;
  Status.SimpleText := 'Console cleared. Machine remains in current state.';
end;

procedure TMainForm.FramingClick(Sender: TObject);
var FramingGCode: TStringList; PowerS: Integer;
begin
  if not Session.Connected then
  begin
    Log('Connect the equipment before framing.');
    Exit;
  end;
  if Session.Count = 0 then
  begin
    Log('No program loaded for framing.');
    Exit;
  end;
  if not Session.Bounds.HasMotion then
  begin
    Log('Could not determine program bounds for framing.');
    Exit;
  end;
  SyncLaserSettingsFromUI;
  if Session.LaserSettings.FramingLaser then
    PowerS := LaserCalcPowerS(Session.LaserSettings, Session.LaserSettings.FramingPower)
  else
    PowerS := 0;

  FramingGCode := TGCodeAnalyzer.BuildFramingGCode(Session.Bounds,
    Session.LaserSettings.FramingFeed, Session.LaserSettings.FramingLaser, PowerS);
  try
    Log(Format('Framing: X(%.2f..%.2f) Y(%.2f..%.2f) at %.0f mm/min | Laser: %s',
      [Session.Bounds.MinX, Session.Bounds.MaxX, Session.Bounds.MinY, Session.Bounds.MaxY,
       Session.LaserSettings.FramingFeed,
       IfThen(Session.LaserSettings.FramingLaser, Format('ON in test mode (%.0f%% = S%d)', [Session.LaserSettings.FramingPower, PowerS]), 'OFF')],
      InvariantFS));
    if not Session.RunFraming(FramingGCode) then
      Log('Failed to start framing: ' + Session.LastError);
  finally
    FramingGCode.Free;
  end;
  UpdateControls;
end;

procedure TMainForm.CommandClick(Sender: TObject);
var OK: Boolean; PosHome: TMachinePosition;
begin
  OK := False;
  if Sender = BtnStart then
  begin
    if not Session.Connected then
    begin
      Log('Machine disconnected.');
      Exit;
    end;
    if Session.Count = 0 then
    begin
      Log('No program loaded.');
      Exit;
    end;
    if Session.MachineState in [msAlarm, msError] then
    begin
      Log('Machine in alarm or error: unlock or home before starting.');
      Exit;
    end;

    { Envelope limit check }
    if Session.Bounds.HasMotion then
    begin
      if (Session.EnvelopeX > 0) and (Session.Bounds.MaxX > Session.EnvelopeX) then
      begin
        MessageDlg('WARNING: Limit Exceeded',
          Format('The job exceeds the machine X axis limit.' + LineEnding +
                 'Required size: %.2f mm' + LineEnding +
                 'Available limit: %.2f mm' + LineEnding + LineEnding +
                 'Start aborted.',
                 [Session.Bounds.MaxX, Session.EnvelopeX], InvariantFS),
          mtWarning, [mbOK], 0);
        Log('Start aborted: exceeds machine X axis limit.');
        Exit;
      end;
      if (Session.EnvelopeY > 0) and (Session.Bounds.MaxY > Session.EnvelopeY) then
      begin
        MessageDlg('WARNING: Limit Exceeded',
          Format('The job exceeds the machine Y axis limit.' + LineEnding +
                 'Required size: %.2f mm' + LineEnding +
                 'Available limit: %.2f mm' + LineEnding + LineEnding +
                 'Start aborted.',
                 [Session.Bounds.MaxY, Session.EnvelopeY], InvariantFS),
          mtWarning, [mbOK], 0);
        Log('Start aborted: exceeds machine Y axis limit.');
        Exit;
      end;
    end;

    SyncLaserSettingsFromUI;

    { Execute framing before start in laser mode if enabled }
    if (MachineType.ItemIndex = 1) and Session.LaserSettings.FrameBeforeStart and Session.Bounds.HasMotion then
    begin
      FramingClick(Sender);
      if MessageDlg('Positioning Confirmation',
        'Framing path has been executed.' + LineEnding + LineEnding +
        'Is the workpiece positioned correctly on the bed to start the job?',
        mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
      begin
        Log('Job start aborted by operator after framing.');
        Exit;
      end;
    end;

    OK := Session.Start;
  end
  else if Sender = BtnPause then OK := Session.Pause
  else if Sender = BtnResume then OK := Session.Resume
  else if Sender = BtnStop then OK := Session.Stop
  else if Sender = BtnHome then OK := Session.Home(FeedRate.Value)
  else if Sender = BtnSetHome then begin
    OK := Session.SetHome(PosHome);
    if OK then begin
      Log(Format('Set Home Ref: position recorded as HOME at X: %.3f, Y: %.3f, Z: %.3f (G28.1 stored, no motion)',
        [PosHome.X, PosHome.Y, PosHome.Z], InvariantFS));
      UpdateControls;
      Exit;
    end;
  end
  else if Sender = BtnPhysicalHome then OK := Session.PhysicalHoming
  else if Sender = BtnZero then begin OK := Session.Zero; if OK then UpdateControls; end
  else if Sender = BtnStatus then OK := Session.Status
  else if Sender = BtnUnlock then OK := Session.Unlock
  else if Sender = BtnSend then begin
    OK := Session.Send(EditCommand.Text);
    if OK then EditCommand.Clear;
  end;
  if OK then Log(TButton(Sender).Caption + ': OK')
  else Log('Action rejected: ' + Session.LastError);
  UpdateControls;
end;

procedure TMainForm.JogClick(Sender: TObject);
var Index: Integer; Distance: Double;
begin
  Index := TButton(Sender).Tag;
  Distance := StepSize.Value;
  if Index mod 2 = 0 then Distance := -Distance;
  if not Session.Jog(TAxis(Index div 2), Distance, FeedRate.Value) then
    Log('Motion rejected: ' + Session.LastError);
  UpdateControls;
end;

procedure TMainForm.Tick(Sender: TObject);
begin
  try
    Session.Poll;
    Session.Tick;
  except
    on E: Exception do begin Session.Stop; Log('Execution failure: ' + E.Message); end;
  end;
  if Session.State <> LastState then
  begin
    case Session.State of
      ssDone: Log('Program completed: all lines confirmed by controller.');
      ssError: Log('Program aborted: ' + Session.LastError);
    end;
    LastState := Session.State;
  end;
  UpdateControls;
end;

procedure TMainForm.FeedRateChanged(Sender: TObject);
begin
  if Session.Connected and (Session.State = ssIdle) and (FeedRate.Value > 0) then
    Session.SetFeedRate(FeedRate.Value);
end;

procedure TMainForm.Closing(Sender: TObject; var CanClose: Boolean);
begin
  CanClose := True;
  if Session.State in [ssRunning, ssPaused] then begin
    CanClose := MessageDlg('Program in Progress',
      'Stop the machine and close application?', mtConfirmation, [mbYes, mbNo], 0) = mrYes;
    if CanClose then Session.Stop;
  end;
end;

end.
