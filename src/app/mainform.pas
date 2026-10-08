unit mainform;

{$mode objfpc}{$H+}

interface

uses Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls,
  Dialogs, Graphics, Spin, Math, StrUtils, LazUTF8, LCLType, multisuite_numfmt,
  multicnc_types, multicnc_session, multicnc_gcode_analyzer, multicnc_laser_config,
  multicnc_printer_profiles, multicnc_router_profiles, ailistserialdevices, multisuite_icons,
  multisuite_controls;

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
      BtnHome, BtnSetHome, BtnPhysicalHome, BtnZero, BtnStatus, BtnUnlock, BtnSend: TSuiteButton;
      BtnGoTo: TSuiteButton;
    JogButtons: array[0..5] of TSuiteButton;
    StepSize: TFloatSpinEdit;
    FeedRate: TSpinEdit;
    ProgramMemo, MemoLog: TMemo;
    EditCommand, SearchEdit: TEdit;
    Pages: TPageControl;
    ProgramTab, ConfigTab, ConsoleTab: TTabSheet;
    SearchResult: TLabel;
    StateLabel: TSuiteBadge;
    FileLabel, ProgramInfoLabel, ProgressLabel, PositionLabel, HomeLabel: TLabel;
    HeaderBar: TSuiteHeader;
    ActionsBar, DroPanel: TPanel;
    TabImages: TImageList;
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
    GbRouterProfile: TGroupBox;
    RouterBrandCombo, RouterModelCombo: TComboBox;
    RouterSpecsLabel: TLabel;
    SpRouterX, SpRouterY, SpRouterZ: TFloatSpinEdit;
    SpConfigHotendTemp, SpConfigBedTemp: TSpinEdit;
    BtnApplyTemps, BtnCooldownTemps: TSuiteButton;
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
      X, Y, W: Integer; Handler: TNotifyEvent): TSuiteButton;
    procedure AddTabIcon(AKind: TSuiteIconKind; AColor: TColor);
    procedure HeaderResize(Sender: TObject);
    procedure ActionsResize(Sender: TObject);
    procedure FooterResize(Sender: TObject);
    procedure LayoutActions;
    procedure SidePaint(Sender: TObject);
    procedure ActionsPaint(Sender: TObject);
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
    function AskTargetPosition(var AX, AY, AZ: Double): Boolean;
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
    procedure RouterBrandChanged(Sender: TObject);
    procedure RouterModelChanged(Sender: TObject);
    procedure RouterTravelChanged(Sender: TObject);
    function NewTravelSpin(AParent: TWinControl; AIndex: Integer; const AHint: string): TFloatSpinEdit;
    procedure ApplyTempsClick(Sender: TObject);
    procedure CooldownTempsClick(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    procedure OpenProgramFile(const AFileName: string);
    destructor Destroy; override;
  end;

implementation

function TMainForm.Panel(ParentControl: TWinControl; Alignment: TAlign; Size: Integer): TPanel;
begin
  Result := TPanel.Create(Self);
  Result.Parent := ParentControl;
  Result.BevelOuter := bvNone;
  Result.Color := clSuiteSurface;
  Result.ParentColor := False;
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

procedure TMainForm.AddTabIcon(AKind: TSuiteIconKind; AColor: TColor);
var
  Bmp: TBitmap;
begin
  Bmp := RenderSuiteIcon(AKind, 16, AColor, sifNone, 2);
  try
    TabImages.Add(Bmp, nil);
  finally
    Bmp.Free;
  end;
end;

procedure TMainForm.HeaderResize(Sender: TObject);
begin
  if (HeaderBar = nil) or (BtnConnect = nil) then Exit;
  BtnConnect.Left := HeaderBar.ClientWidth - BtnConnect.Width - 20;
  if StateLabel <> nil then
  begin
    StateLabel.AnchorRight := BtnConnect.Left - 14;
    StateLabel.AutoFit;
  end;
end;

{ Distribui os botoes visiveis da barra de acoes; a parada de emergencia
  fica isolada a direita. }
procedure TMainForm.LayoutActions;
var
  X: Integer;

  procedure Place(B: TSuiteButton; AGapAfter: Integer);
  begin
    if (B = nil) or not B.Visible then Exit;
    B.Left := X;
    B.Top := 14;
    X := X + B.Width + AGapAfter;
  end;

begin
  if (ActionsBar = nil) or (BtnStop = nil) then Exit;
  X := 16;
  Place(BtnOpen, 8);
  Place(BtnFraming, 8);
  X := X + 12;
  Place(BtnStart, 8);
  Place(BtnPause, 8);
  Place(BtnResume, 8);
  BtnStop.Top := 14;
  BtnStop.Left := Max(X + 12, ActionsBar.ClientWidth - BtnStop.Width - 16);
end;

procedure TMainForm.FooterResize(Sender: TObject);
begin
  if Progress <> nil then
    Progress.Width := Max(50, TPanel(Sender).ClientWidth - 24);
end;

procedure TMainForm.ActionsResize(Sender: TObject);
begin
  LayoutActions;
end;

procedure TMainForm.SidePaint(Sender: TObject);
var
  P: TPanel;
begin
  P := TPanel(Sender);
  P.Canvas.Pen.Color := clSuiteBorder;
  P.Canvas.Line(P.Width - 1, 0, P.Width - 1, P.Height);
end;

procedure TMainForm.ActionsPaint(Sender: TObject);
var
  P: TPanel;
begin
  P := TPanel(Sender);
  P.Canvas.Pen.Color := clSuiteBorder;
  P.Canvas.Line(0, P.Height - 1, P.Width, P.Height - 1);
end;

function TMainForm.ButtonAt(ParentControl: TWinControl; const AText: string;
  X, Y, W: Integer; Handler: TNotifyEvent): TSuiteButton;
begin
  Result := TSuiteButton.Create(Self);
  Result.Parent := ParentControl;
  Result.Caption := AText;
  Result.SetBounds(X, Y, W, 34);
  Result.OnClick := Handler;
end;

const
  { Layout do painel lateral }
  SIDE_W  = 332;
  SIDE_X  = 20;
  COL_W   = 143;
  COL2_X  = 169;
  ROW1_Y  = 294;
  ROW2_Y  = 336;
  ROW3_Y  = 378;
  ROW_H   = 36;

constructor TMainForm.Create(AOwner: TComponent);
var
  Header: TSuiteHeader;
  Body, Side, Workspace, Actions, Footer, ConsoleBar, SearchBar, LogBar: TPanel;
  Title: TSuiteSectionTitle;
  L: TLabel; I: Integer;
  B: TSuiteButton;
const
  JogNames: array[0..5] of string = ('X-', 'X+', 'Y-', 'Y+', 'Z-', 'Z+');
  JogIcons: array[0..5] of TSuiteIconKind = (sikArrowLeft, sikArrowRight,
    sikArrowDown, sikArrowUp, sikArrowDown, sikArrowUp);
begin
  inherited CreateNew(AOwner);
  Caption := 'MultiCNC | Control Panel';
  Position := poScreenCenter;
  SetBounds(0, 0, 1180, 800);
  Constraints.MinWidth := 1180;
  Constraints.MinHeight := 700;
  Font.Name := 'Segoe UI';
  Font.Size := 10;
  Color := clSuiteSurface;
  OnCloseQuery := @Closing;
  KeyPreview := True;
  OnKeyDown := @Shortcut;
  AllowDropFiles := True;
  OnDropFiles := @DropFiles;
  Session := TSimulationSession.Create;
  Session.OnLog := @Log;

  { Top Header: faixa em degrade, estado e conexao }
  Header := TSuiteHeader.Create(Self);
  Header.Parent := Self;
  Header.Align := alTop;
  Header.Height := 76;
  Header.Setup('MultiCNC', 'CONTROL  /  Program execution with controller handshake', sikCNC);
  Header.OnResize := @HeaderResize;
  HeaderBar := Header;

  BtnConnect := ButtonAt(Header, 'Connect Device', 0, 19, 200, @ConnectClick);
  BtnConnect.Height := 38;
  BtnConnect.BackColor := clSuiteNavy2;
  BtnConnect.SetLook(sbsSolid, clSuitePrimary, sikPlug);

  StateLabel := TSuiteBadge.Create(Self);
  StateLabel.Parent := Header;
  StateLabel.SetBounds(600, 23, 160, 30);
  StateLabel.Caption := 'Disconnected';

  { Bottom Status Bar }
  Status := TStatusBar.Create(Self);
  Status.Parent := Self;
  Status.Align := alBottom;
  Status.SimplePanel := True;
  Status.SimpleText := 'Commands validated and sent with confirmation (ok). Keep physical emergency stop within reach.';

  { Main Body }
  Body := Panel(Self, alClient, 0);

  { Left Manual Jog & Indicator Panel }
  Side := Panel(Body, alLeft, SIDE_W);
  Side.Color := clSuiteCard;
  Side.OnPaint := @SidePaint;

  Title := TSuiteSectionTitle.CreateTitle(Self, 'MANUAL JOG', sikMove, clSuitePrimary);
  Title.Parent := Side;
  Title.SetBounds(SIDE_X, 14, 260, 22);

  L := LabelAt(Side, 'Step (mm)', SIDE_X, 42);
  L.AutoSize := False;
  L.Width := COL_W;
  L.Font.Size := 9;
  L.Font.Color := clSuiteMuted;
  StepSize := TFloatSpinEdit.Create(Self);
  StepSize.Parent := Side;
  StepSize.SetBounds(SIDE_X, 62, COL_W, 28);
  StepSize.MinValue := 0.01;
  StepSize.MaxValue := 100;
  StepSize.DecimalPlaces := 2;
  StepSize.Increment := 0.1;
  StepSize.Value := 1;

  L := LabelAt(Side, 'Feed rate (mm/min)', COL2_X, 42);
  L.AutoSize := False;
  L.Width := COL_W;
  L.Font.Size := 9;
  L.Font.Color := clSuiteMuted;
  FeedRate := TSpinEdit.Create(Self);
  FeedRate.Parent := Side;
  FeedRate.SetBounds(COL2_X, 62, COL_W, 28);
  FeedRate.MinValue := 1;
  FeedRate.MaxValue := 10000;
  FeedRate.Value := 500;
  FeedRate.OnChange := @FeedRateChanged;

  { Jog em cruz: XY a esquerda, Z a direita (X vermelho, Y verde, Z azul) }
  for I := 0 to 5 do begin
    JogButtons[I] := ButtonAt(Side, JogNames[I], 0, 0, 58, @JogClick);
    JogButtons[I].Tag := I;
    case I div 2 of
      0: JogButtons[I].SetLook(sbsSoft, clSuiteAxisX, JogIcons[I]);
      1: JogButtons[I].SetLook(sbsSoft, clSuiteAxisY, JogIcons[I]);
    else
      JogButtons[I].SetLook(sbsSoft, clSuiteAxisZ, JogIcons[I]);
    end;
  end;
  JogButtons[3].SetBounds(SIDE_X + 72, 104, 66, 44);   { Y+ }
  JogButtons[0].SetBounds(SIDE_X, 154, 66, 44);        { X- }
  JogButtons[1].SetBounds(SIDE_X + 144, 154, 66, 44);  { X+ }
  JogButtons[2].SetBounds(SIDE_X + 72, 204, 66, 44);   { Y- }
  JogButtons[5].SetBounds(SIDE_X + 222, 104, 70, 69);  { Z+ }
  JogButtons[4].SetBounds(SIDE_X + 222, 179, 70, 69);  { Z- }
  L := LabelAt(Side, 'XY', SIDE_X + 72, 154);
  L.AutoSize := False;
  L.SetBounds(SIDE_X + 72, 154, 66, 44);
  L.Alignment := taCenter;
  L.Layout := tlCenter;
  L.Font.Size := 9;
  L.Font.Style := [fsBold];
  L.Font.Color := clSuiteFaint;

  Title := TSuiteSectionTitle.CreateTitle(Self, 'MACHINE', sikGear, clSuitePrimary);
  Title.Parent := Side;
  Title.SetBounds(SIDE_X, 264, 260, 22);

  BtnHome := ButtonAt(Side, 'Go Home', SIDE_X, ROW1_Y, COL_W, @CommandClick);
  BtnHome.SetLook(sbsOutline, clSuitePrimary, sikHome);
  BtnHome.Hint := 'Return axes to recorded HOME position (G28).';
  BtnHome.ShowHint := True;
  BtnSetHome := ButtonAt(Side, 'Set Home Ref', COL2_X, ROW1_Y, COL_W, @CommandClick);
  BtnSetHome.SetLook(sbsOutline, clSuiteInfo, sikFlag);
  BtnSetHome.Hint := 'Record current axes position as application reference HOME (G28.1) without moving.';
  BtnSetHome.ShowHint := True;
  BtnGoTo := ButtonAt(Side, 'Go To Position', COL2_X, ROW1_Y, COL_W, @CommandClick);
  BtnGoTo.SetLook(sbsOutline, clSuiteInfo, sikPointer);
  BtnGoTo.Hint := 'Move the head to an absolute X/Y/Z position (G90 G0), checked against the machine travel.';
  BtnGoTo.ShowHint := True;
  BtnGoTo.Visible := False;

  BtnPhysicalHome := ButtonAt(Side, 'Physical Homing', SIDE_X, ROW2_Y, COL_W, @CommandClick);
  BtnPhysicalHome.SetLook(sbsOutline, clSuitePrimary, sikTarget);
  BtnPhysicalHome.Hint := 'Run physical homing cycle on endstop switches ($H in GRBL / G28 in Marlin 3D).';
  BtnPhysicalHome.ShowHint := True;
  BtnZero := ButtonAt(Side, 'Zero Workpiece', COL2_X, ROW2_Y, COL_W, @CommandClick);
  BtnZero.SetLook(sbsOutline, clSuiteSuccess, sikOrigin);
  BtnZero.Hint := 'Set current position as workpiece coordinate origin (G92 X0 Y0 Z0).';
  BtnZero.ShowHint := True;

  BtnStatus := ButtonAt(Side, 'Status / Pos', SIDE_X, ROW3_Y, COL_W, @CommandClick);
  BtnStatus.SetLook(sbsOutline, clSuiteInfo, sikPulse);
  BtnStatus.Hint := 'Query machine state and position (? in GRBL / M114 in Marlin).';
  BtnStatus.ShowHint := True;
  BtnUnlock := ButtonAt(Side, 'Unlock', COL2_X, ROW3_Y, COL_W, @CommandClick);
  BtnUnlock.SetLook(sbsOutline, clSuiteWarning, sikUnlock);
  BtnUnlock.Hint := 'Unlock machine from alarm state ($X in GRBL / M999 in Marlin).';
  BtnUnlock.ShowHint := True;

  { Leitura de posicao (DRO) }
  Title := TSuiteSectionTitle.CreateTitle(Self, 'POSITION', sikGauge, clSuitePrimary);
  Title.Parent := Side;
  Title.SetBounds(SIDE_X, 424, 260, 22);

  DroPanel := TPanel.Create(Self);
  DroPanel.Parent := Side;
  DroPanel.BevelOuter := bvNone;
  DroPanel.Color := clSuiteNavy;
  DroPanel.SetBounds(SIDE_X, 450, COL_W * 2 + 6, 104);

  PositionLabel := LabelAt(DroPanel, 'Position: -', 14, 8);
  PositionLabel.Name := 'PositionLabel';
  PositionLabel.Caption := 'Position: -';
  PositionLabel.AutoSize := False;
  PositionLabel.SetBounds(14, 8, COL_W * 2 - 22, 56);
  PositionLabel.WordWrap := True;
  PositionLabel.Font.Name := 'Consolas';
  PositionLabel.Font.Size := 10;
  PositionLabel.Font.Color := SuiteRGB(110, 231, 183);

  HomeLabel := LabelAt(DroPanel, 'HOME: -', 14, 64);
  HomeLabel.Name := 'HomeLabel';
  HomeLabel.Caption := 'HOME: -';
  HomeLabel.AutoSize := False;
  HomeLabel.SetBounds(14, 64, COL_W * 2 - 22, 36);
  HomeLabel.WordWrap := True;
  HomeLabel.Font.Name := 'Consolas';
  HomeLabel.Font.Size := 9;
  HomeLabel.Font.Color := SuiteRGB(252, 211, 77);

  { 3D Printer Temperature Indicator Group in Side Panel }
  GbSideTemperatures := TGroupBox.Create(Self);
  GbSideTemperatures.Parent := Side;
  GbSideTemperatures.Caption := '3D Printer Temperatures';
  GbSideTemperatures.SetBounds(SIDE_X - 4, 562, COL_W * 2 + 14, 128);
  GbSideTemperatures.Visible := False;

  LabelAt(GbSideTemperatures, 'Nozzle / Hotend:', 10, 2);
  LblNozzleTemp := TLabel.Create(Self);
  LblNozzleTemp.Parent := GbSideTemperatures;
  LblNozzleTemp.SetBounds(10, 23, 215, 20);
  LblNozzleTemp.Font.Name := 'Consolas';
  LblNozzleTemp.Font.Style := [fsBold];
  LblNozzleTemp.Font.Size := 9;
  LblNozzleTemp.Font.Color := clSuiteDanger;
  LblNozzleTemp.Caption := 'Real: - C  |  Config: 200 C';

  LabelAt(GbSideTemperatures, 'Heated Bed:', 10, 46);
  LblBedTemp := TLabel.Create(Self);
  LblBedTemp.Parent := GbSideTemperatures;
  LblBedTemp.SetBounds(10, 67, 215, 20);
  LblBedTemp.Font.Name := 'Consolas';
  LblBedTemp.Font.Style := [fsBold];
  LblBedTemp.Font.Size := 9;
  LblBedTemp.Font.Color := clSuiteWarning;
  LblBedTemp.Caption := 'Real: - C  |  Config: 60 C';

  LblHeaterStatus := TLabel.Create(Self);
  LblHeaterStatus.Parent := GbSideTemperatures;
  LblHeaterStatus.SetBounds(10, 93, 215, 18);
  LblHeaterStatus.Font.Size := 8;
  LblHeaterStatus.Font.Color := clSuiteMuted;
  LblHeaterStatus.Caption := 'Heaters Standby / Off';

  { Workspace (Center / Right) }
  Workspace := Panel(Body, alClient, 0);
  Actions := Panel(Workspace, alTop, 100);
  Actions.Color := clSuiteCard;
  Actions.OnPaint := @ActionsPaint;
  Actions.OnResize := @ActionsResize;
  ActionsBar := Actions;

  BtnOpen := ButtonAt(Actions, 'Open Program...', 16, 14, 158, @OpenClick);
  BtnOpen.Height := 38;
  BtnOpen.ShowHint := True;
  BtnOpen.SetLook(sbsOutline, clSuitePrimary, sikFolder);
  BtnFraming := ButtonAt(Actions, 'Frame (Test)', 0, 14, 128, @FramingClick);
  BtnFraming.Height := 38;
  BtnFraming.SetLook(sbsOutline, SuiteRGB(124, 58, 237), sikFrame);
  BtnStart := ButtonAt(Actions, 'Start', 0, 14, 100, @CommandClick);
  BtnStart.Height := 38;
  BtnStart.SetLook(sbsSolid, clSuiteSuccess, sikPlay);
  BtnPause := ButtonAt(Actions, 'Pause', 0, 14, 100, @CommandClick);
  BtnPause.Height := 38;
  BtnPause.SetLook(sbsSolid, clSuiteWarning, sikPause);
  BtnResume := ButtonAt(Actions, 'Resume', 0, 14, 110, @CommandClick);
  BtnResume.Height := 38;
  BtnResume.SetLook(sbsSoft, clSuitePrimary, sikPlay);
  BtnStop := ButtonAt(Actions, 'Emergency Stop', 0, 14, 168, @CommandClick);
  BtnStop.Height := 38;
  BtnStop.SetLook(sbsSolid, clSuiteDanger, sikStop);
  BtnStop.Hint := 'Stop the machine immediately.';
  BtnStop.ShowHint := True;

  FileLabel := LabelAt(Actions, 'No file opened', 16, 60);
  FileLabel.Font.Style := [fsBold];
  FileLabel.Font.Color := clSuiteText;
  ProgramInfoLabel := LabelAt(Actions, 'No program loaded', 16, 78);
  ProgramInfoLabel.Width := 800;
  ProgramInfoLabel.Font.Size := 9;
  ProgramInfoLabel.Font.Color := clSuiteMuted;
  ProgramInfoLabel.Anchors := [akLeft, akTop, akRight];
  ProgramInfoLabel.ShowHint := True;

  Footer := Panel(Workspace, alBottom, 62);
  ProgressLabel := LabelAt(Footer, '0 / 0 commands sent', 12, 6);
  ProgressLabel.Font.Color := clSuiteMuted;
  Progress := TProgressBar.Create(Self);
  Progress.Parent := Footer;
  Progress.SetBounds(12, 31, 610, 18);
  Footer.OnResize := @FooterResize;

  { Icones das abas }
  TabImages := TImageList.Create(Self);
  TabImages.Width := 16;
  TabImages.Height := 16;
  AddTabIcon(sikFile, clSuitePrimary);
  AddTabIcon(sikGear, clSuiteMuted);
  AddTabIcon(sikTerminal, clSuiteSuccess);

  Pages := TPageControl.Create(Self);
  Pages.Parent := Workspace;
  Pages.Align := alClient;
  Pages.BorderSpacing.Around := 8;
  Pages.Images := TabImages;

  { Tab 1: Program }
  ProgramTab := TTabSheet.Create(Self);
  ProgramTab.PageControl := Pages;
  ProgramTab.Caption := 'Program';
  ProgramTab.ImageIndex := 0;
  SearchBar := Panel(ProgramTab, alTop, 80);
  SearchBar.Color := clSuiteCard;
  L := LabelAt(SearchBar, 'Search in program (Ctrl+F)', 10, 4);
  L.Font.Size := 9;
  L.Font.Color := clSuiteMuted;
  SearchEdit := TEdit.Create(Self);
  SearchEdit.Name := 'ProgramSearch';
  SearchEdit.Parent := SearchBar;
  SearchEdit.SetBounds(10, 25, 300, 28);
  SearchEdit.Text := '';
  SearchEdit.TextHint := 'e.g.: G1, X10 or M3';
  SearchEdit.OnChange := @SearchChanged;
  B := ButtonAt(SearchBar, 'Next (F3)', 320, 22, 132, @SearchClick);
  B.Name := 'FindNext';
  B.Caption := 'Next (F3)';
  B.SetLook(sbsOutline, clSuitePrimary, sikSearch);
  SearchResult := LabelAt(SearchBar, 'Case-insensitive search.', 10, 58);
  SearchResult.Name := 'SearchResult';
  SearchResult.Caption := 'Case-insensitive search.';
  SearchResult.Font.Size := 9;
  SearchResult.Font.Color := clSuiteMuted;
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
  ConfigTab.ImageIndex := 1;

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

  { CNC Router Brand & Model Profile Group }
  GbRouterProfile := TGroupBox.Create(Self);
  GbRouterProfile.Parent := ConfigScrollBox;
  GbRouterProfile.Caption := 'CNC Router Brand && Model Profile';
  GbRouterProfile.SetBounds(15, 120, 715, 290);
  GbRouterProfile.Visible := False;

  LabelAt(GbRouterProfile, 'Brand:', 15, 8);
  RouterBrandCombo := TComboBox.Create(Self);
  RouterBrandCombo.Parent := GbRouterProfile;
  RouterBrandCombo.SetBounds(15, 30, 220, 30);
  RouterBrandCombo.Style := csDropDownList;
  RouterBrandCombo.OnChange := @RouterBrandChanged;

  LabelAt(GbRouterProfile, 'Model:', 250, 8);
  RouterModelCombo := TComboBox.Create(Self);
  RouterModelCombo.Parent := GbRouterProfile;
  RouterModelCombo.SetBounds(250, 30, 300, 30);
  RouterModelCombo.Style := csDropDownList;
  RouterModelCombo.OnChange := @RouterModelChanged;

  LabelAt(GbRouterProfile, 'Machine travel X / Y / Z (mm) - filled by the profile, adjust to your machine:', 15, 68);
  SpRouterX := NewTravelSpin(GbRouterProfile, 0, 'X travel (mm)');
  SpRouterY := NewTravelSpin(GbRouterProfile, 1, 'Y travel (mm)');
  SpRouterZ := NewTravelSpin(GbRouterProfile, 2, 'Z travel (mm)');

  LabelAt(GbRouterProfile, 'Standard Factory Specifications:', 15, 130);
  RouterSpecsLabel := TLabel.Create(Self);
  RouterSpecsLabel.Parent := GbRouterProfile;
  RouterSpecsLabel.SetBounds(15, 154, 680, 110);
  RouterSpecsLabel.AutoSize := False;
  RouterSpecsLabel.ShowAccelChar := False;
  RouterSpecsLabel.WordWrap := True;
  RouterSpecsLabel.Font.Name := 'Consolas';
  RouterSpecsLabel.Font.Size := 9;
  RouterSpecsLabel.Font.Color := $00442200;

  GetRouterBrands(RouterBrandCombo.Items);
  if RouterBrandCombo.Items.Count > 0 then
  begin
    RouterBrandCombo.ItemIndex := 0;
    GetRouterModels(RouterBrandCombo.Text, RouterModelCombo.Items);
    if RouterModelCombo.Items.Count > 0 then
      RouterModelCombo.ItemIndex := 0;
  end;

  { 3D Printer Profile & Specifications Group }
  GbPrinterProfile := TGroupBox.Create(Self);
  GbPrinterProfile.Parent := ConfigScrollBox;
  GbPrinterProfile.Caption := '3D Printer Brand && Model Profile';
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
  PrinterSpecsLabel.ShowAccelChar := False;
  PrinterSpecsLabel.WordWrap := True;
  PrinterSpecsLabel.Font.Name := 'Consolas';
  PrinterSpecsLabel.Font.Size := 9;
  PrinterSpecsLabel.Font.Color := $00442200;

  { 3D Printer Temperature Configuration Group in Config Tab }
  GbPrinterTemps := TGroupBox.Create(Self);
  GbPrinterTemps.Parent := ConfigScrollBox;
  GbPrinterTemps.Caption := '3D Printer Temperature Configuration && Targets';
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
  BtnApplyTemps.SetLook(sbsSolid, clSuiteWarning, sikFlame);
  BtnApplyTemps.Hint := 'Send target temperature commands to the 3D printer controller.';
  BtnApplyTemps.ShowHint := True;

  BtnCooldownTemps := ButtonAt(GbPrinterTemps, 'Cooldown Heaters', 525, 25, 175, @CooldownTempsClick);
  BtnCooldownTemps.SetLook(sbsSoft, clSuiteInfo, sikSnow);
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
  GbControl.Caption := 'Laser Control && Framing';
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
  ConsoleTab.ImageIndex := 2;
  LogBar := Panel(ConsoleTab, alTop, 50);
  LogBar.Color := clSuiteCard;
  ButtonAt(LogBar, 'Save Log...', 10, 8, 150, @SaveLogClick).SetLook(sbsOutline, clSuitePrimary, sikSave);
  B := ButtonAt(LogBar, 'Clear Console', 172, 8, 150, @ClearLogClick);
  B.Name := 'ClearConsole';
  B.Caption := 'Clear Console';
  B.SetLook(sbsOutline, clSuiteDanger, sikTrash);
  ConsoleBar := Panel(ConsoleTab, alBottom, 50);
  ConsoleBar.Color := clSuiteCard;
  BtnSend := ButtonAt(ConsoleBar, 'Send', 0, 8, 110, @CommandClick);
  BtnSend.SetLook(sbsSolid, clSuitePrimary, sikSend);
  BtnSend.Align := alRight;
  BtnSend.BorderSpacing.Around := 8;
  EditCommand := TEdit.Create(Self);
  EditCommand.Parent := ConsoleBar;
  EditCommand.Align := alClient;
  EditCommand.BorderSpacing.Left := 8;
  EditCommand.BorderSpacing.Top := 11;
  EditCommand.BorderSpacing.Bottom := 11;
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

  { Identifica o binario em execucao: ajuda a confirmar qual build o log mostra. }
  Log(Format('MultiCNC build %s %s (%s-%s, FPC %s). Serial: CHATGPT TAISerialModem (COM10+ supported).',
    [{$I %DATE%}, {$I %TIME%}, {$I %FPCTARGETCPU%}, {$I %FPCTARGETOS%}, {$I %FPCVERSION%}]));

  SyncLaserSettingsToUI;
  SelectionChanged(MachineType);
  UpdateMachineTypeLayout;
  UpdateControls;
  HeaderResize(nil);
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

function TMainForm.NewTravelSpin(AParent: TWinControl; AIndex: Integer;
  const AHint: string): TFloatSpinEdit;
begin
  Result := TFloatSpinEdit.Create(Self);
  Result.Parent := AParent;
  Result.SetBounds(15 + AIndex * 130, 92, 120, 28);
  Result.DecimalPlaces := 1;
  Result.Increment := 1;
  Result.MinValue := 1;
  Result.MaxValue := 3000;
  Result.Hint := AHint + ': useful travel that limits jog and moves.';
  Result.ShowHint := True;
  Result.OnChange := @RouterTravelChanged;
end;

procedure TMainForm.RouterBrandChanged(Sender: TObject);
begin
  GetRouterModels(RouterBrandCombo.Text, RouterModelCombo.Items);
  if RouterModelCombo.Items.Count > 0 then
  begin
    RouterModelCombo.ItemIndex := 0;
    RouterModelChanged(nil);
  end
  else
    RouterSpecsLabel.Caption := 'No models available for selected brand.';
end;

procedure TMainForm.RouterModelChanged(Sender: TObject);
var
  Prof: TRouterProfile;
begin
  if not FindRouterProfile(RouterBrandCombo.Text, RouterModelCombo.Text, Prof) then
  begin
    RouterSpecsLabel.Caption := 'Profile not found.';
    Exit;
  end;
  BaudCombo.Text := IntToStr(Prof.BaudRate);
  { Preenche o curso sem disparar tres atualizacoes parciais do envelope. }
  SpRouterX.OnChange := nil; SpRouterY.OnChange := nil; SpRouterZ.OnChange := nil;
  try
    SpRouterX.Value := Prof.WorkX;
    SpRouterY.Value := Prof.WorkY;
    SpRouterZ.Value := Prof.WorkZ;
  finally
    SpRouterX.OnChange := @RouterTravelChanged;
    SpRouterY.OnChange := @RouterTravelChanged;
    SpRouterZ.OnChange := @RouterTravelChanged;
  end;
  Session.SetWorkEnvelope(SpRouterX.Value, SpRouterY.Value, SpRouterZ.Value);
  RouterSpecsLabel.Caption := Format(
    'Brand & Model: %s %s' + LineEnding +
    'Work Area (X x Y x Z): %.1f x %.1f x %.1f mm' + LineEnding +
    'Default Baud: %d | Protocol / Firmware: %s' + LineEnding +
    'Spindle: %s' + LineEnding +
    'Notes: %s',
    [Prof.Brand, Prof.Model, Prof.WorkX, Prof.WorkY, Prof.WorkZ,
     Prof.BaudRate, Prof.Firmware, SpindleText(Prof), Prof.Notes], InvariantFS);
  Log(Format('CNC Router profile applied: %s %s (Table: %.1fx%.1fx%.1f mm, Baud: %d)',
    [Prof.Brand, Prof.Model, Prof.WorkX, Prof.WorkY, Prof.WorkZ, Prof.BaudRate], InvariantFS));
end;

procedure TMainForm.RouterTravelChanged(Sender: TObject);
begin
  if MachineType.ItemIndex <> 0 then Exit;
  Session.SetWorkEnvelope(SpRouterX.Value, SpRouterY.Value, SpRouterZ.Value);
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
var Parts: TStringList; Stamp: string; I: Integer;
begin
  { Cada linha recebe o horario: blocos RX/TX com varias linhas ficam legiveis. }
  Stamp := FormatDateTime('hh:nn:ss', Now) + '  ';
  Parts := TStringList.Create;
  MemoLog.Lines.BeginUpdate;
  try
    Parts.Text := AText;
    for I := 0 to Parts.Count - 1 do
      if Trim(Parts[I]) <> '' then
        MemoLog.Lines.Add(Stamp + Trim(Parts[I]));
    while MemoLog.Lines.Count > 1000 do MemoLog.Lines.Delete(0);
    MemoLog.SelStart := UTF8Length(MemoLog.Text);
  finally
    MemoLog.Lines.EndUpdate;
    Parts.Free;
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
  if Alarm or (Session.State = ssError) then
    StateLabel.DotColor := clSuiteDanger
  else if not Session.Connected then
    StateLabel.DotColor := clSuiteNeutral
  else if not Session.ControllerReady then
    StateLabel.DotColor := clSuiteWarning
  else
    case Session.State of
      ssRunning: StateLabel.DotColor := clSuitePrimary;
      ssPaused, ssStopped: StateLabel.DotColor := clSuiteWarning;
    else
      StateLabel.DotColor := clSuiteSuccess;
    end;
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
  if Assigned(RouterBrandCombo) then
  begin
    RouterBrandCombo.Enabled := not Session.Connected;
    RouterModelCombo.Enabled := not Session.Connected;
    SpRouterX.Enabled := not Session.Connected;
    SpRouterY.Enabled := not Session.Connected;
    SpRouterZ.Enabled := not Session.Connected;
  end;

  if Session.Connected then
  begin
    BtnConnect.Caption := 'Disconnect';
    BtnConnect.SetLook(sbsSoft, clSuiteDanger, sikPower);
  end
  else
  begin
    BtnConnect.Caption := 'Connect Device';
    BtnConnect.SetLook(sbsSolid, clSuitePrimary, sikPlug);
  end;
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
  BtnGoTo.Enabled := Manual and not Alarm and (MachineType.ItemIndex = 2);
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

{ Dialogo do "Go To Position": X/Y/Z absolutos, limitados ao curso do perfil. }
function TMainForm.AskTargetPosition(var AX, AY, AZ: Double): Boolean;
var
  Dlg: TForm;
  Edits: array[0..2] of TFloatSpinEdit;
  BtnOK, BtnCancel: TButton;
  Travel: array[0..2] of Double;
  Values: array[0..2] of Double;
  I: Integer;
  L: TLabel;
const
  Names: array[0..2] of string = ('X (mm)', 'Y (mm)', 'Z (mm)');
begin
  Result := False;
  Travel[0] := Session.EnvelopeX;
  Travel[1] := Session.EnvelopeY;
  Travel[2] := Session.EnvelopeZ;
  Values[0] := AX; Values[1] := AY; Values[2] := AZ;
  Dlg := TForm.CreateNew(nil);
  try
    Dlg.Caption := 'Go To Position';
    Dlg.BorderStyle := bsDialog;
    Dlg.Position := poOwnerFormCenter;
    Dlg.Font.Assign(Font);
    Dlg.Color := clSuiteSurface;
    Dlg.SetBounds(0, 0, 300, 210);
    for I := 0 to 2 do
    begin
      L := TLabel.Create(Dlg);
      L.Parent := Dlg;
      L.Caption := Names[I];
      L.SetBounds(20, 22 + I * 40, 70, 24);
      Edits[I] := TFloatSpinEdit.Create(Dlg);
      Edits[I].Parent := Dlg;
      Edits[I].SetBounds(100, 18 + I * 40, 170, 28);
      Edits[I].DecimalPlaces := 2;
      Edits[I].Increment := 1;
      Edits[I].MinValue := 0;
      if Travel[I] > 0 then Edits[I].MaxValue := Travel[I] else Edits[I].MaxValue := 1000;
      Edits[I].Value := EnsureRange(Values[I], Edits[I].MinValue, Edits[I].MaxValue);
      if Travel[I] > 0 then
        Edits[I].Hint := Format('0 to %.0f mm (machine travel)', [Travel[I]], InvariantFS);
      Edits[I].ShowHint := True;
    end;
    BtnOK := TButton.Create(Dlg);
    BtnOK.Parent := Dlg;
    BtnOK.Caption := 'Move';
    BtnOK.Default := True;
    BtnOK.ModalResult := mrOK;
    BtnOK.SetBounds(100, 140, 82, 32);
    BtnCancel := TButton.Create(Dlg);
    BtnCancel.Parent := Dlg;
    BtnCancel.Caption := 'Cancel';
    BtnCancel.Cancel := True;
    BtnCancel.ModalResult := mrCancel;
    BtnCancel.SetBounds(188, 140, 82, 32);
    if Dlg.ShowModal = mrOK then
    begin
      AX := Edits[0].Value;
      AY := Edits[1].Value;
      AZ := Edits[2].Value;
      Result := True;
    end;
  finally
    Dlg.Free;
  end;
end;

procedure TMainForm.UpdateMachineTypeLayout;
begin
  { Barra de acoes: o enquadramento (framing) so existe no laser }
  BtnFraming.Visible := MachineType.ItemIndex = 1;
  LaserContainer.Visible := MachineType.ItemIndex = 1;
  GbPrinterProfile.Visible := MachineType.ItemIndex = 2;
  GbRouterProfile.Visible := MachineType.ItemIndex = 0;
  GbPrinterTemps.Visible := MachineType.ItemIndex = 2;
  GbSideTemperatures.Visible := MachineType.ItemIndex = 2;

  if MachineType.ItemIndex = 2 then { 3D Printer }
  begin
    PrinterModelChanged(nil);
    BtnSetHome.Visible := False;
    BtnZero.Visible := False;
    BtnHome.SetBounds(SIDE_X, ROW1_Y, COL_W, ROW_H);
    BtnGoTo.SetBounds(COL2_X, ROW1_Y, COL_W, ROW_H);
    BtnGoTo.Visible := True;
    BtnPhysicalHome.SetBounds(SIDE_X, ROW2_Y, COL_W * 2 + 6, ROW_H);
    HomeLabel.Visible := False;
    DroPanel.Height := 68;
  end
  else { CNC Router / CNC Laser }
  begin
    BtnGoTo.Visible := False;
    BtnHome.SetBounds(SIDE_X, ROW1_Y, COL_W, ROW_H);
    BtnSetHome.SetBounds(COL2_X, ROW1_Y, COL_W, ROW_H);
    BtnSetHome.Visible := True;
    BtnPhysicalHome.SetBounds(SIDE_X, ROW2_Y, COL_W, ROW_H);
    BtnZero.SetBounds(COL2_X, ROW2_Y, COL_W, ROW_H);
    BtnZero.Visible := True;
    HomeLabel.Visible := True;
    DroPanel.Height := 104;
  end;
  GbSideTemperatures.Top := DroPanel.Top + DroPanel.Height + 10;
  BtnStatus.SetBounds(SIDE_X, ROW3_Y, COL_W, ROW_H);
  BtnUnlock.SetBounds(COL2_X, ROW3_Y, COL_W, ROW_H);
  LayoutActions;
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
        BtnOpen.Hint := 'Open CNC program (.nc, .tap, .cnc, .ngc, .gcode) - Ctrl+O';
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
        { Curso e baud vem do perfil de marca/modelo selecionado. }
        RouterModelChanged(nil);
      end;
      1: { CNC Laser }
      begin
        BtnOpen.Hint := 'Open CNC / Laser program (.nc, .tap, .cnc, .ngc, .gcode) - Ctrl+O';
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
        BtnOpen.Hint := 'Open 3D printer G-code (.gcode, .gco, .nc, .ngc) - Ctrl+O';
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
      if CommunicationMode.ItemIndex = 0 then
        Log(Format('Connecting to %s at %d baud (8N1) | Machine: %s | Protocol: %s ...',
          [Endpoint, Baud, MachineType.Text, ProtocolType.Text]))
      else
        Log(Format('Connecting to %s over TCP | Machine: %s | Protocol: %s ...',
          [Endpoint, MachineType.Text, ProtocolType.Text]));
      if (MachineType.ItemIndex = 2) and (ProtocolType.ItemIndex <> 1) then
        Log('Warning: 3D Printer selected with GRBL protocol. Creality/Prusa/Anycubic printers run Marlin.');
      if (MachineType.ItemIndex <> 2) and (ProtocolType.ItemIndex = 1) then
        Log('Warning: CNC machine selected with Marlin protocol. Printer handshake and temperatures only run for 3D Printer.');
      if Session.Connect(TMachineType(MachineType.ItemIndex),
        TProtocolKind(ProtocolType.ItemIndex), Endpoint, Baud) then
      begin
        Log('Connected: ' + MachineType.Text + ' / ' + ProtocolType.Text + ' at ' + Endpoint);
        if MachineType.ItemIndex = 2 then
          Log('Marlin conectado. Aguardando inicializacao da controladora antes do handshake M115/M105...')
        else
          Session.SetFeedRate(FeedRate.Value);
      end
      else
      begin
        Log('Failed to connect to ' + Endpoint + ': ' + Session.LastError);
        if CommunicationMode.ItemIndex = 0 then
          Log('Tip: close other programs that use the port, check Device Manager for the COM number, then click the COM list to refresh it.');
      end;
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

{ Abre um programa vindo da suite (LaserArt / LaserPCB via --file).
  O cabecalho define a maquina:
  - "; RouterPCB -> MultiCNC (CNC Router)": fresagem de PCB do RouterPCB -> CNC Router;
  - "; LaserPCB -> MultiCNC (CNC Router)": furacao do LaserPCB -> CNC Router;
  - "; LaserArt" ou "; LaserPCB": laser. A potencia (S) e as passadas ja
    estao no G-code, entao Pass count = 1 e override de velocidade desligado.
  Nada e enviado a maquina: o usuario conecta e inicia normalmente. }
procedure TMainForm.OpenProgramFile(const AFileName: string);
type
  TSuiteOrigin = (soNone, soLaser, soRouter);
var
  SL: TStringList;
  I: Integer;
  Origin: TSuiteOrigin;
begin
  if (AFileName = '') or not FileExists(AFileName) then Exit;
  Origin := soNone;
  SL := TStringList.Create;
  try
    try
      SL.LoadFromFile(AFileName);
      for I := 0 to Min(SL.Count, 40) - 1 do
        if (Pos('; RouterPCB -> MultiCNC (CNC Router)', SL[I]) = 1) or
           (Pos('; LaserPCB -> MultiCNC (CNC Router)', SL[I]) = 1) then
        begin
          Origin := soRouter;
          Break;
        end
        else if (Pos('; LaserArt', SL[I]) = 1) or (Pos('; LaserPCB', SL[I]) = 1) then
        begin
          Origin := soLaser;
          Break;
        end;
    except
      Origin := soNone;
    end;
  finally
    SL.Free;
  end;
  if (Origin <> soNone) and not Session.Connected then
  begin
    if Origin = soRouter then
    begin
      if MachineType.ItemIndex <> 0 then
      begin
        MachineType.ItemIndex := 0;
        SelectionChanged(MachineType);
      end;
      Log('Programa de PCB (RouterPCB/LaserPCB): maquina CNC Router. Zere X/Y no canto da placa e Z na superficie do cobre.');
    end
    else
    begin
      if MachineType.ItemIndex <> 1 then
      begin
        MachineType.ItemIndex := 1;
        SelectionChanged(MachineType);
      end;
      SpCutPasses.Value := 1;
      ChkOverrideSpeed.Checked := False;
      SyncLaserSettingsFromUI;
      Log('Arquivo de laser: maquina CNC Laser, Pass count = 1, override desligado (S e passadas vem do arquivo).');
    end;
  end;
  LoadProgram(AFileName);
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
var OK: Boolean; PosHome, Target: TMachinePosition;
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
  else if Sender = BtnGoTo then begin
    Target := Session.Position;
    if not AskTargetPosition(Target.X, Target.Y, Target.Z) then Exit;
    OK := Session.MoveTo(Target.X, Target.Y, Target.Z, FeedRate.Value);
    if OK then
      Log(Format('Go To: X %.3f Y %.3f Z %.3f at F%d',
        [Target.X, Target.Y, Target.Z, FeedRate.Value], InvariantFS));
  end
  else if Sender = BtnZero then begin OK := Session.Zero; if OK then UpdateControls; end
  else if Sender = BtnStatus then OK := Session.Status
  else if Sender = BtnUnlock then OK := Session.Unlock
  else if Sender = BtnSend then begin
    OK := Session.Send(EditCommand.Text);
    if OK then EditCommand.Clear;
  end;
  if OK then Log(TSuiteButton(Sender).Caption + ': OK')
  else Log('Action rejected: ' + Session.LastError);
  UpdateControls;
end;

procedure TMainForm.JogClick(Sender: TObject);
var Index: Integer; Distance: Double;
begin
  Index := TControl(Sender).Tag;
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
