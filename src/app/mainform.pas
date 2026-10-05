unit mainform;

{$mode objfpc}{$H+}

interface

uses Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls,
  Dialogs, Graphics, Spin, StrUtils, LazUTF8, LCLType, multisuite_numfmt,
  multicnc_types, multicnc_session, multicnc_gcode_analyzer, multicnc_laser_config;

type
  TMainForm = class(TForm)
  private
    Session: TSimulationSession;
    MachineType, ProtocolType: TComboBox;
    DeviceEdit, BaudEdit, HostEdit, PortEdit: TEdit;
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
    ProgramTab, LaserTab, ConsoleTab: TTabSheet;
    SearchResult: TLabel;
    StateLabel, FileLabel, ProgramInfoLabel, ProgressLabel, PositionLabel, HomeLabel: TLabel;
    LastState: TSessionState;
    Progress: TProgressBar;
    Timer: TTimer;
    Status: TStatusBar;

    { Laser UI controls }
    LaserScrollBox: TScrollBox;
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
  Header, Connection, Body, Side, Workspace, Actions, Footer, ConsoleBar, SearchBar, LogBar: TPanel;
  GbWork, GbPower, GbSpeed, GbCut, GbDot, GbAir, GbControl: TGroupBox;
  L: TLabel; I: Integer;
const JogNames: array[0..5] of string = ('X -', 'X +', 'Y -', 'Y +', 'Z -', 'Z +');
begin
  inherited CreateNew(AOwner);
  Caption := 'MultiCNC | Painel de operacao';
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

  Header := Panel(Self, alTop, 82);
  L := LabelAt(Header, 'MultiCNC', 20, 12);
  L.Font.Size := 20;
  L.Font.Style := [fsBold];
  LabelAt(Header, 'CONTROLE  /  Envio de programas com confirmacao da controladora', 22, 51);
  StateLabel := LabelAt(Header, 'Desconectado', 620, 25);
  StateLabel.Font.Style := [fsBold];

  Connection := Panel(Self, alTop, 105);
  Connection.Top := 90;
  LabelAt(Connection, 'Maquina', 20, 5);
  MachineType := TComboBox.Create(Self);
  MachineType.Parent := Connection;
  MachineType.SetBounds(20, 29, 150, 30);
  MachineType.Style := csDropDownList;
  MachineType.Items.Add('CNC Router');
  MachineType.Items.Add('CNC Laser');
  MachineType.Items.Add('Impressora 3D');
  MachineType.ItemIndex := 0;
  MachineType.OnChange := @SelectionChanged;

  LabelAt(Connection, 'Protocolo', 185, 5);
  ProtocolType := TComboBox.Create(Self);
  ProtocolType.Parent := Connection;
  ProtocolType.SetBounds(185, 29, 125, 30);
  ProtocolType.Style := csDropDownList;
  ProtocolType.Items.Add('GRBL');
  ProtocolType.Items.Add('Marlin');
  ProtocolType.ItemIndex := 0;
  ProtocolType.OnChange := @SelectionChanged;

  LabelAt(Connection, 'Comunicacao', 325, 5);
  CommunicationMode := TComboBox.Create(Self);
  CommunicationMode.Parent := Connection;
  CommunicationMode.SetBounds(325, 29, 100, 28);
  CommunicationMode.Items.Add('Serial');
  CommunicationMode.Items.Add('TCP');
  CommunicationMode.ItemIndex := 0;
  CommunicationMode.Style := csDropDownList;
  CommunicationMode.OnChange := @CommunicationChanged;

  SerialPanel := TPanel.Create(Self);
  SerialPanel.Parent := Connection;
  SerialPanel.SetBounds(440, 0, 260, 90);
  SerialPanel.BevelOuter := bvNone;
  TCPPanel := TPanel.Create(Self);
  TCPPanel.Parent := Connection;
  TCPPanel.SetBounds(440, 0, 260, 90);
  TCPPanel.BevelOuter := bvNone;

  LabelAt(SerialPanel, 'Porta COM', 0, 5);
  DeviceEdit := TEdit.Create(Self);
  DeviceEdit.Parent := SerialPanel;
  DeviceEdit.SetBounds(0, 29, 120, 30);
  DeviceEdit.Text := 'COM3';
  LabelAt(SerialPanel, 'Baud', 135, 5);
  BaudEdit := TEdit.Create(Self);
  BaudEdit.Parent := SerialPanel;
  BaudEdit.SetBounds(135, 29, 110, 30);
  BaudEdit.Text := '115200';

  LabelAt(TCPPanel, 'IP do equipamento', 0, 5);
  HostEdit := TEdit.Create(Self);
  HostEdit.Parent := TCPPanel;
  HostEdit.SetBounds(0, 29, 155, 30);
  HostEdit.Text := '127.0.0.1';
  LabelAt(TCPPanel, 'Porta TCP', 165, 5);
  PortEdit := TEdit.Create(Self);
  PortEdit.Parent := TCPPanel;
  PortEdit.SetBounds(165, 29, 80, 30);
  PortEdit.Text := '9000';
  BtnConnect := ButtonAt(Connection, 'Conectar equipamento', 715, 26, 205, @ConnectClick);
  CommunicationChanged(Self);

  Status := TStatusBar.Create(Self);
  Status.Parent := Self;
  Status.Align := alBottom;
  Status.SimplePanel := True;
  Status.SimpleText := 'Comandos validados e enviados com confirmacao (ok). Mantenha a parada de emergencia fisica ao alcance.';

  Body := Panel(Self, alClient, 0);
  Side := Panel(Body, alLeft, 268);
  L := LabelAt(Side, 'Movimento manual', 20, 14);
  L.Font.Style := [fsBold];
  LabelAt(Side, 'Passo (mm)', 20, 51);
  StepSize := TFloatSpinEdit.Create(Self);
  StepSize.Parent := Side;
  StepSize.SetBounds(20, 75, 220, 30);
  StepSize.MinValue := 0.01;
  StepSize.MaxValue := 100;
  StepSize.DecimalPlaces := 2;
  StepSize.Increment := 0.1;
  StepSize.Value := 1;

  LabelAt(Side, 'Avanco (mm/min)', 20, 119);
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

  BtnHome := ButtonAt(Side, 'Ir para Home', 20, 328, 108, @CommandClick);
  BtnHome.Hint := 'Retorna os eixos para a posicao HOME gravada (G28).';
  BtnHome.ShowHint := True;
  BtnSetHome := ButtonAt(Side, 'Referenciar Home', 132, 328, 116, @CommandClick);
  BtnSetHome.Hint := 'Grava a posicao atual dos eixos como HOME de referencia da aplicacao (G28.1), sem movimentar a maquina.';
  BtnSetHome.ShowHint := True;

  BtnPhysicalHome := ButtonAt(Side, 'Homing fisico', 20, 368, 108, @CommandClick);
  BtnPhysicalHome.Hint := 'Executa o ciclo fisico de homing nos sensores/fins de curso ($H no GRBL / G28 no Marlin 3D).';
  BtnPhysicalHome.ShowHint := True;
  BtnZero := ButtonAt(Side, 'Zerar peca', 132, 368, 116, @CommandClick);
  BtnZero.Hint := 'Define a posicao atual como origem das coordenadas de trabalho da peca (G92 X0 Y0 Z0).';
  BtnZero.ShowHint := True;

  BtnStatus := ButtonAt(Side, 'Status / Pos', 20, 408, 108, @CommandClick);
  BtnStatus.Hint := 'Consulta a posicao e estado da maquina (? no GRBL / M114 no Marlin).';
  BtnStatus.ShowHint := True;
  BtnUnlock := ButtonAt(Side, 'Desbloquear', 132, 408, 116, @CommandClick);
  BtnUnlock.Hint := 'Desbloqueia a maquina em estado de alarme ($X no GRBL / M999 no Marlin).';
  BtnUnlock.ShowHint := True;

  PositionLabel := LabelAt(Side, 'Posicao: -', 20, 452);
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

  Workspace := Panel(Body, alClient, 0);
  Actions := Panel(Workspace, alTop, 115);

  BtnOpen := ButtonAt(Actions, 'Abrir programa CNC...', 12, 10, 160, @OpenClick);
  BtnFraming := ButtonAt(Actions, 'CONTORNAR', 178, 10, 110, @FramingClick);
  BtnFraming.Font.Style := [fsBold];
  BtnFraming.Hint := 'Percorre o perimetro retangular do trabalho para inspecao fisica da area com laser desligado.';
  BtnFraming.ShowHint := True;
  BtnFraming.Visible := False;

  BtnStart := ButtonAt(Actions, 'Iniciar', 294, 10, 95, @CommandClick);
  BtnPause := ButtonAt(Actions, 'Pausar', 395, 10, 95, @CommandClick);
  BtnResume := ButtonAt(Actions, 'Retomar', 496, 10, 95, @CommandClick);
  BtnStop := ButtonAt(Actions, 'PARAR', 597, 10, 110, @CommandClick);
  BtnStop.Font.Style := [fsBold];
  BtnStop.Hint := 'Para a maquina (GRBL: soft reset; Marlin: M410 e desliga spindle/laser/aquecimento).';
  BtnStop.ShowHint := True;

  FileLabel := LabelAt(Actions, 'Nenhum arquivo aberto', 14, 52);
  FileLabel.AutoSize := False;
  FileLabel.Width := 800;
  FileLabel.Font.Style := [fsBold];
  FileLabel.Anchors := [akLeft, akTop, akRight];
  FileLabel.ShowHint := True;

  ProgramInfoLabel := LabelAt(Actions, 'Nenhum programa carregado', 14, 78);
  ProgramInfoLabel.AutoSize := False;
  ProgramInfoLabel.Width := 800;
  ProgramInfoLabel.Font.Size := 9;
  ProgramInfoLabel.Font.Color := $00664400;
  ProgramInfoLabel.Anchors := [akLeft, akTop, akRight];
  ProgramInfoLabel.ShowHint := True;

  Footer := Panel(Workspace, alBottom, 62);
  ProgressLabel := LabelAt(Footer, '0 / 0 comandos enviados', 12, 6);
  Progress := TProgressBar.Create(Self);
  Progress.Parent := Footer;
  Progress.SetBounds(12, 31, 610, 18);
  Progress.Anchors := [akLeft, akRight, akTop];

  Pages := TPageControl.Create(Self);
  Pages.Parent := Workspace;
  Pages.Align := alClient;

  { Aba 1: Programa }
  ProgramTab := TTabSheet.Create(Self);
  ProgramTab.PageControl := Pages;
  ProgramTab.Caption := 'Programa';
  SearchBar := Panel(ProgramTab, alTop, 80);
  LabelAt(SearchBar, 'Buscar no programa (Ctrl+F)', 10, 4);
  SearchEdit := TEdit.Create(Self);
  SearchEdit.Name := 'ProgramSearch';
  SearchEdit.Parent := SearchBar;
  SearchEdit.SetBounds(10, 25, 300, 28);
  SearchEdit.TextHint := 'Ex.: G1, X10 ou M3';
  SearchEdit.OnChange := @SearchChanged;
  ButtonAt(SearchBar, 'Proximo (F3)', 324, 22, 132, @SearchClick).Name := 'FindNext';
  SearchResult := LabelAt(SearchBar, 'Busca sem diferenciar maiusculas e minusculas.', 10, 58);
  SearchResult.Name := 'SearchResult';
  ProgramMemo := TMemo.Create(Self);
  ProgramMemo.Name := 'ProgramText';
  ProgramMemo.Parent := ProgramTab;
  ProgramMemo.Align := alClient;
  ProgramMemo.ReadOnly := True;
  ProgramMemo.WordWrap := False;
  ProgramMemo.ScrollBars := ssAutoBoth;
  ProgramMemo.Font.Name := 'Consolas';
  ProgramMemo.Text := 'Abra um arquivo .nc, .gcode ou .tap para inspecionar e executar.';

  { Aba 2: Configuracoes Laser }
  LaserTab := TTabSheet.Create(Self);
  LaserTab.PageControl := Pages;
  LaserTab.Caption := 'Configuracoes Laser';
  LaserTab.TabVisible := False;

  LaserScrollBox := TScrollBox.Create(Self);
  LaserScrollBox.Parent := LaserTab;
  LaserScrollBox.Align := alClient;
  LaserScrollBox.BorderStyle := bsNone;

  { Grupo 1: Trabalho }
  GbWork := TGroupBox.Create(Self);
  GbWork.Parent := LaserScrollBox;
  GbWork.Caption := 'Trabalho';
  GbWork.SetBounds(15, 10, 320, 125);
  RbModeCut := TRadioButton.Create(Self);
  RbModeCut.Parent := GbWork;
  RbModeCut.Caption := 'Corte';
  RbModeCut.SetBounds(15, 10, 120, 24);
  RbModeCut.Checked := True;
  RbModeCut.OnClick := @LaserParamChanged;
  RbModeEngrave := TRadioButton.Create(Self);
  RbModeEngrave.Parent := GbWork;
  RbModeEngrave.Caption := 'Gravacao';
  RbModeEngrave.SetBounds(15, 40, 120, 24);
  RbModeEngrave.OnClick := @LaserParamChanged;
  RbModePerforate := TRadioButton.Create(Self);
  RbModePerforate.Parent := GbWork;
  RbModePerforate.Caption := 'Picote';
  RbModePerforate.SetBounds(15, 70, 120, 24);
  RbModePerforate.OnClick := @LaserParamChanged;

  { Grupo 2: Potencia }
  GbPower := TGroupBox.Create(Self);
  GbPower.Parent := LaserScrollBox;
  GbPower.Caption := 'Potencia';
  GbPower.SetBounds(350, 10, 340, 185);
  LabelAt(GbPower, 'Potencia do laser (%):', 15, 10);
  SpLaserPower := TSpinEdit.Create(Self);
  SpLaserPower.Parent := GbPower;
  SpLaserPower.SetBounds(210, 6, 110, 26);
  SpLaserPower.MinValue := 0; SpLaserPower.MaxValue := 100; SpLaserPower.Value := 70;
  SpLaserPower.OnChange := @LaserParamChanged;

  LabelAt(GbPower, 'Potencia minima (%):', 15, 45);
  SpLaserMinPower := TSpinEdit.Create(Self);
  SpLaserMinPower.Parent := GbPower;
  SpLaserMinPower.SetBounds(210, 41, 110, 26);
  SpLaserMinPower.MinValue := 0; SpLaserMinPower.MaxValue := 100; SpLaserMinPower.Value := 0;
  SpLaserMinPower.OnChange := @LaserParamChanged;

  LabelAt(GbPower, 'Potencia maxima (%):', 15, 80);
  SpLaserMaxPower := TSpinEdit.Create(Self);
  SpLaserMaxPower.Parent := GbPower;
  SpLaserMaxPower.SetBounds(210, 76, 110, 26);
  SpLaserMaxPower.MinValue := 0; SpLaserMaxPower.MaxValue := 100; SpLaserMaxPower.Value := 100;
  SpLaserMaxPower.OnChange := @LaserParamChanged;

  LabelAt(GbPower, 'Valor S maximo ($30):', 15, 115);
  SpLaserMaxS := TSpinEdit.Create(Self);
  SpLaserMaxS.Parent := GbPower;
  SpLaserMaxS.SetBounds(210, 111, 110, 26);
  SpLaserMaxS.MinValue := 1; SpLaserMaxS.MaxValue := 65535; SpLaserMaxS.Value := 1000;
  SpLaserMaxS.OnChange := @LaserParamChanged;

  { Grupo 3: Velocidade }
  GbSpeed := TGroupBox.Create(Self);
  GbSpeed.Parent := LaserScrollBox;
  GbSpeed.Caption := 'Velocidade (mm/min)';
  GbSpeed.SetBounds(15, 145, 320, 185);
  LabelAt(GbSpeed, 'Gravacao:', 15, 10);
  SpSpeedEngrave := TSpinEdit.Create(Self);
  SpSpeedEngrave.Parent := GbSpeed;
  SpSpeedEngrave.SetBounds(190, 6, 115, 26);
  SpSpeedEngrave.MinValue := 1; SpSpeedEngrave.MaxValue := 50000; SpSpeedEngrave.Value := 3000;
  SpSpeedEngrave.OnChange := @LaserParamChanged;

  LabelAt(GbSpeed, 'Corte:', 15, 45);
  SpSpeedCut := TSpinEdit.Create(Self);
  SpSpeedCut.Parent := GbSpeed;
  SpSpeedCut.SetBounds(190, 41, 115, 26);
  SpSpeedCut.MinValue := 1; SpSpeedCut.MaxValue := 20000; SpSpeedCut.Value := 800;
  SpSpeedCut.OnChange := @LaserParamChanged;

  LabelAt(GbSpeed, 'Posicionamento (G0):', 15, 80);
  SpSpeedTravel := TSpinEdit.Create(Self);
  SpSpeedTravel.Parent := GbSpeed;
  SpSpeedTravel.SetBounds(190, 76, 115, 26);
  SpSpeedTravel.MinValue := 1; SpSpeedTravel.MaxValue := 50000; SpSpeedTravel.Value := 5000;
  SpSpeedTravel.OnChange := @LaserParamChanged;

  ChkOverrideSpeed := TCheckBox.Create(Self);
  ChkOverrideSpeed.Parent := GbSpeed;
  ChkOverrideSpeed.Caption := 'Substituir velocidades do arquivo';
  ChkOverrideSpeed.SetBounds(15, 118, 280, 24);
  ChkOverrideSpeed.OnClick := @LaserParamChanged;

  { Grupo 4: Corte }
  GbCut := TGroupBox.Create(Self);
  GbCut.Parent := LaserScrollBox;
  GbCut.Caption := 'Corte';
  GbCut.SetBounds(350, 205, 340, 215);
  LabelAt(GbCut, 'Numero de passadas:', 15, 10);
  SpCutPasses := TSpinEdit.Create(Self);
  SpCutPasses.Parent := GbCut;
  SpCutPasses.SetBounds(210, 6, 110, 26);
  SpCutPasses.MinValue := 1; SpCutPasses.MaxValue := 100; SpCutPasses.Value := 1;
  SpCutPasses.OnChange := @LaserParamChanged;

  LabelAt(GbCut, 'Potencia por passada (%):', 15, 45);
  SpCutPassPower := TSpinEdit.Create(Self);
  SpCutPassPower.Parent := GbCut;
  SpCutPassPower.SetBounds(210, 41, 110, 26);
  SpCutPassPower.MinValue := 0; SpCutPassPower.MaxValue := 100; SpCutPassPower.Value := 100;
  SpCutPassPower.OnChange := @LaserParamChanged;

  LabelAt(GbCut, 'Velocidade por passada:', 15, 80);
  SpCutPassFeed := TSpinEdit.Create(Self);
  SpCutPassFeed.Parent := GbCut;
  SpCutPassFeed.SetBounds(210, 76, 110, 26);
  SpCutPassFeed.MinValue := 1; SpCutPassFeed.MaxValue := 20000; SpCutPassFeed.Value := 800;
  SpCutPassFeed.OnChange := @LaserParamChanged;

  LabelAt(GbCut, 'Pausa entre passadas (ms):', 15, 115);
  SpCutPassDelay := TSpinEdit.Create(Self);
  SpCutPassDelay.Parent := GbCut;
  SpCutPassDelay.SetBounds(210, 111, 110, 26);
  SpCutPassDelay.MinValue := 0; SpCutPassDelay.MaxValue := 60000; SpCutPassDelay.Value := 0;
  SpCutPassDelay.OnChange := @LaserParamChanged;

  LabelAt(GbCut, 'Alteracao Z por passada (mm):', 15, 150);
  SpCutPassZStep := TFloatSpinEdit.Create(Self);
  SpCutPassZStep.Parent := GbCut;
  SpCutPassZStep.SetBounds(210, 146, 110, 26);
  SpCutPassZStep.MinValue := -50; SpCutPassZStep.MaxValue := 50; SpCutPassZStep.Value := 0.00;
  SpCutPassZStep.DecimalPlaces := 2; SpCutPassZStep.Increment := 0.1;
  SpCutPassZStep.OnChange := @LaserParamChanged;

  { Grupo 5: Picote }
  GbDot := TGroupBox.Create(Self);
  GbDot.Parent := LaserScrollBox;
  GbDot.Caption := 'Picote';
  GbDot.SetBounds(15, 340, 320, 185);
  LabelAt(GbDot, 'Comprimento ligado (mm):', 15, 10);
  SpDotLengthOn := TFloatSpinEdit.Create(Self);
  SpDotLengthOn.Parent := GbDot;
  SpDotLengthOn.SetBounds(190, 6, 115, 26);
  SpDotLengthOn.MinValue := 0.1; SpDotLengthOn.MaxValue := 1000; SpDotLengthOn.Value := 5.0;
  SpDotLengthOn.DecimalPlaces := 1; SpDotLengthOn.Increment := 0.5;
  SpDotLengthOn.OnChange := @LaserParamChanged;

  LabelAt(GbDot, 'Comprimento desligado (mm):', 15, 45);
  SpDotLengthOff := TFloatSpinEdit.Create(Self);
  SpDotLengthOff.Parent := GbDot;
  SpDotLengthOff.SetBounds(190, 41, 115, 26);
  SpDotLengthOff.MinValue := 0.1; SpDotLengthOff.MaxValue := 1000; SpDotLengthOff.Value := 2.0;
  SpDotLengthOff.DecimalPlaces := 1; SpDotLengthOff.Increment := 0.5;
  SpDotLengthOff.OnChange := @LaserParamChanged;

  LabelAt(GbDot, 'Potencia (%):', 15, 80);
  SpDotPower := TSpinEdit.Create(Self);
  SpDotPower.Parent := GbDot;
  SpDotPower.SetBounds(190, 76, 115, 26);
  SpDotPower.MinValue := 0; SpDotPower.MaxValue := 100; SpDotPower.Value := 70;
  SpDotPower.OnChange := @LaserParamChanged;

  LabelAt(GbDot, 'Velocidade (mm/min):', 15, 115);
  SpDotFeed := TSpinEdit.Create(Self);
  SpDotFeed.Parent := GbDot;
  SpDotFeed.SetBounds(190, 111, 115, 26);
  SpDotFeed.MinValue := 1; SpDotFeed.MaxValue := 20000; SpDotFeed.Value := 1000;
  SpDotFeed.OnChange := @LaserParamChanged;

  { Grupo 6: Assistencia de Ar }
  GbAir := TGroupBox.Create(Self);
  GbAir.Parent := LaserScrollBox;
  GbAir.Caption := 'Assistencia de ar';
  GbAir.SetBounds(350, 430, 340, 140);
  ChkAirAssist := TCheckBox.Create(Self);
  ChkAirAssist.Parent := GbAir;
  ChkAirAssist.Caption := 'Assistencia de ar ativa';
  ChkAirAssist.SetBounds(15, 10, 280, 24);
  ChkAirAssist.Checked := True;
  ChkAirAssist.OnClick := @LaserParamChanged;

  LabelAt(GbAir, 'Comando ligar:', 15, 45);
  EditAirAssistOn := TEdit.Create(Self);
  EditAirAssistOn.Parent := GbAir;
  EditAirAssistOn.SetBounds(210, 41, 110, 26);
  EditAirAssistOn.Text := 'M8';
  EditAirAssistOn.OnChange := @LaserParamChanged;

  LabelAt(GbAir, 'Comando desligar:', 15, 80);
  EditAirAssistOff := TEdit.Create(Self);
  EditAirAssistOff.Parent := GbAir;
  EditAirAssistOff.SetBounds(210, 76, 110, 26);
  EditAirAssistOff.Text := 'M9';
  EditAirAssistOff.OnChange := @LaserParamChanged;

  { Grupo 7: Controle do Laser & Parametros Adicionais }
  GbControl := TGroupBox.Create(Self);
  GbControl.Parent := LaserScrollBox;
  GbControl.Caption := 'Controle do laser e Enquadramento';
  GbControl.SetBounds(15, 535, 675, 205);

  RbLaserM4 := TRadioButton.Create(Self);
  RbLaserM4.Parent := GbControl;
  RbLaserM4.Caption := 'M4 - Potencia dinamica (Recomendado GRBL)';
  RbLaserM4.SetBounds(15, 8, 300, 24);
  RbLaserM4.Checked := True;
  RbLaserM4.OnClick := @LaserParamChanged;

  RbLaserM3 := TRadioButton.Create(Self);
  RbLaserM3.Parent := GbControl;
  RbLaserM3.Caption := 'M3 - Potencia constante';
  RbLaserM3.SetBounds(340, 8, 280, 24);
  RbLaserM3.OnClick := @LaserParamChanged;

  ChkFramingLaser := TCheckBox.Create(Self);
  ChkFramingLaser.Parent := GbControl;
  ChkFramingLaser.Caption := 'Usar laser de enquadramento (DESATIVADO por padrao)';
  ChkFramingLaser.SetBounds(15, 40, 400, 24);
  ChkFramingLaser.Checked := False;
  ChkFramingLaser.OnClick := @LaserParamChanged;

  LabelAt(GbControl, 'Potencia enquadramento (%):', 15, 75);
  SpFramingPower := TSpinEdit.Create(Self);
  SpFramingPower.Parent := GbControl;
  SpFramingPower.SetBounds(210, 71, 90, 26);
  SpFramingPower.MinValue := 0; SpFramingPower.MaxValue := 10; SpFramingPower.Value := 1;
  SpFramingPower.OnChange := @LaserParamChanged;

  LabelAt(GbControl, 'Velocidade contorno (mm/min):', 340, 75);
  SpFramingFeed := TSpinEdit.Create(Self);
  SpFramingFeed.Parent := GbControl;
  SpFramingFeed.SetBounds(550, 71, 100, 26);
  SpFramingFeed.MinValue := 1; SpFramingFeed.MaxValue := 20000; SpFramingFeed.Value := 3000;
  SpFramingFeed.OnChange := @LaserParamChanged;

  LabelAt(GbControl, 'Kerf / largura corte (mm):', 15, 110);
  SpKerf := TFloatSpinEdit.Create(Self);
  SpKerf.Parent := GbControl;
  SpKerf.SetBounds(210, 106, 90, 26);
  SpKerf.MinValue := 0.0; SpKerf.MaxValue := 10.0; SpKerf.Value := 0.10;
  SpKerf.DecimalPlaces := 2; SpKerf.Increment := 0.05;
  SpKerf.OnChange := @LaserParamChanged;

  LabelAt(GbControl, 'Pre-disparo (ms):', 340, 110);
  SpPreFireDelay := TSpinEdit.Create(Self);
  SpPreFireDelay.Parent := GbControl;
  SpPreFireDelay.SetBounds(440, 106, 70, 26);
  SpPreFireDelay.MinValue := 0; SpPreFireDelay.MaxValue := 5000; SpPreFireDelay.Value := 0;
  SpPreFireDelay.OnChange := @LaserParamChanged;

  LabelAt(GbControl, 'Pos-disparo (ms):', 525, 110);
  SpPostFireDelay := TSpinEdit.Create(Self);
  SpPostFireDelay.Parent := GbControl;
  SpPostFireDelay.SetBounds(620, 106, 70, 26);
  SpPostFireDelay.MinValue := 0; SpPostFireDelay.MaxValue := 5000; SpPostFireDelay.Value := 0;
  SpPostFireDelay.OnChange := @LaserParamChanged;

  ChkFrameBeforeStart := TCheckBox.Create(Self);
  ChkFrameBeforeStart.Parent := GbControl;
  ChkFrameBeforeStart.Caption := 'Executar contorno antes de iniciar (solicita confirmacao da posicao)';
  ChkFrameBeforeStart.SetBounds(15, 145, 550, 24);
  ChkFrameBeforeStart.Checked := False;
  ChkFrameBeforeStart.OnClick := @LaserParamChanged;

  { Aba 3: Console }
  ConsoleTab := TTabSheet.Create(Self);
  ConsoleTab.PageControl := Pages;
  ConsoleTab.Caption := 'Console';
  LogBar := Panel(ConsoleTab, alTop, 50);
  ButtonAt(LogBar, 'Salvar registro...', 10, 8, 150, @SaveLogClick);
  ButtonAt(LogBar, 'Limpar console', 172, 8, 150, @ClearLogClick).Name := 'ClearConsole';
  ConsoleBar := Panel(ConsoleTab, alBottom, 50);
  BtnSend := ButtonAt(ConsoleBar, 'Enviar', 0, 8, 100, @CommandClick);
  BtnSend.Align := alRight;
  EditCommand := TEdit.Create(Self);
  EditCommand.Parent := ConsoleBar;
  EditCommand.Align := alClient;
  EditCommand.TextHint := 'Comando G-code manual';
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
  UpdateMachineTypeLayout;
  UpdateControls;
end;

destructor TMainForm.Destroy;
begin
  if Assigned(Timer) then Timer.Enabled := False;
  Session.Free;
  inherited Destroy;
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
  S.Kerf := SpKerf.Value;
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
const StateNames: array[TSessionState] of string = ('Desconectado', 'Pronto',
  'Executando', 'Pausado', 'Programa concluido', 'Interrompido', 'Erro');
var Busy, Manual, Alarm: Boolean; I: Integer; P, H: TMachinePosition; Info: string;
begin
  Busy := Session.State in [ssRunning, ssPaused];
  Manual := Session.Connected and not Busy;
  Alarm := Session.MachineState = msAlarm;
  StateLabel.Caption := StateNames[Session.State];
  if Alarm then StateLabel.Caption := StateLabel.Caption + ' | ALARME';
  if Session.Connected then
  begin
    P := Session.Position;
    PositionLabel.Caption := Format('Maquina: %s' + LineEnding + 'X %9.3f  Y %9.3f' + LineEnding + 'Z %9.3f',
      [MachineStateToString(Session.MachineState), P.X, P.Y, P.Z], InvariantFS);
    if Session.HomePositionSet then
    begin
      H := Session.HomePosition;
      HomeLabel.Caption := Format('HOME ref: X %.3f' + LineEnding + 'Y %.3f  Z %.3f (G28.1)', [H.X, H.Y, H.Z], InvariantFS);
    end
    else
      HomeLabel.Caption := 'HOME: [Nao referenciado]';
  end
  else
  begin
    PositionLabel.Caption := 'Posicao: -';
    HomeLabel.Caption := 'HOME: -';
  end;

  MachineType.Enabled := not Session.Connected;
  ProtocolType.Enabled := not Session.Connected;
  CommunicationMode.Enabled := not Session.Connected;
  HostEdit.Enabled := not Session.Connected;
  PortEdit.Enabled := not Session.Connected;
  DeviceEdit.Enabled := not Session.Connected;
  BaudEdit.Enabled := not Session.Connected;
  if Session.Connected then BtnConnect.Caption := 'Desconectar' else BtnConnect.Caption := 'Conectar equipamento';
  BtnConnect.Enabled := not Busy;
  BtnOpen.Enabled := not Busy;
  BtnFraming.Enabled := Session.Connected and not Busy and (Session.Count > 0);
  BtnStart.Enabled := Session.Connected and not Busy and (Session.Count > 0);
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
  ProgressLabel.Caption := Format('%d / %d comandos confirmados', [Session.Completed, Session.Count]);

  { Informacoes do Programa e Area do Trabalho }
  if Session.Count > 0 then
  begin
    FileLabel.Caption := ExtractFileName(Session.FileName);
    FileLabel.Hint := Session.FileName;
    if Session.Bounds.HasMotion then
      Info := Format('Area: %.2f x %.2f mm | X: %.2f -> %.2f mm | Y: %.2f -> %.2f mm',
        [BoundsWidth(Session.Bounds), BoundsHeight(Session.Bounds),
         Session.Bounds.MinX, Session.Bounds.MaxX,
         Session.Bounds.MinY, Session.Bounds.MaxY], InvariantFS)
    else
      Info := 'Area: percurso nao dimensionalizado';

    if MachineType.ItemIndex = 1 then { CNC Laser }
      Info := Info + ' | ' + LaserSummaryString(Session.LaserSettings);

    ProgramInfoLabel.Caption := Info;
    ProgramInfoLabel.Hint := Info;
  end
  else
  begin
    FileLabel.Caption := 'Nenhum arquivo aberto';
    FileLabel.Hint := '';
    ProgramInfoLabel.Caption := 'Nenhum programa carregado';
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
    BtnStop.SetBounds(597, 10, 110, 34);

    LaserTab.TabVisible := True;

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
  else if MachineType.ItemIndex = 2 then { Impressora 3D }
  begin
    BtnFraming.Visible := False;
    BtnOpen.SetBounds(12, 10, 170, 34);
    BtnStart.SetBounds(188, 10, 100, 34);
    BtnPause.SetBounds(294, 10, 100, 34);
    BtnResume.SetBounds(400, 10, 100, 34);
    BtnStop.SetBounds(506, 10, 132, 34);

    LaserTab.TabVisible := False;
    if Pages.ActivePage = LaserTab then Pages.ActivePage := ProgramTab;

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

    LaserTab.TabVisible := False;
    if Pages.ActivePage = LaserTab then Pages.ActivePage := ProgramTab;

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
begin
  if MachineType.ItemIndex = 2 then begin
    BtnOpen.Caption := 'Abrir G-code...';
    if Sender = MachineType then ProtocolType.ItemIndex := 1;
  end else begin
    BtnOpen.Caption := 'Abrir programa CNC...';
    if Sender = MachineType then ProtocolType.ItemIndex := 0;
  end;
  UpdateMachineTypeLayout;
  UpdateControls;
end;

procedure TMainForm.CommunicationChanged(Sender: TObject);
begin
  SerialPanel.Visible := CommunicationMode.ItemIndex = 0;
  TCPPanel.Visible := CommunicationMode.ItemIndex = 1;
end;

procedure TMainForm.ConnectClick(Sender: TObject);
var Endpoint: string; Baud, PortNumber: Integer;
begin
  if Session.Connected then begin
    Session.Disconnect;
    Log('Equipamento desconectado.');
  end else begin
    Baud := 115200;
    if CommunicationMode.ItemIndex = 0 then begin
      Endpoint := Trim(DeviceEdit.Text);
      if (Endpoint = '') or (Pos(':', Endpoint) > 0) then begin
        Log('Informe uma porta serial valida, por exemplo COM3.'); Exit;
      end;
      if not TryStrToInt(Trim(BaudEdit.Text), Baud) or (Baud <= 0) then begin
        Log('Informe um baud rate positivo.'); Exit;
      end;
    end else begin
      if (Trim(HostEdit.Text) = '') or (Pos(':', HostEdit.Text) > 0) then begin
        Log('Informe o IPv4 do equipamento no campo IP.'); Exit;
      end;
      if not TryStrToInt(Trim(PortEdit.Text), PortNumber) or
         (PortNumber < 1) or (PortNumber > 65535) then begin
        Log('A porta TCP deve estar entre 1 e 65535.'); Exit;
      end;
      Endpoint := Trim(HostEdit.Text) + ':' + IntToStr(PortNumber);
    end;
    try
      SyncLaserSettingsFromUI;
      if Session.Connect(TMachineType(MachineType.ItemIndex),
        TProtocolKind(ProtocolType.ItemIndex), Endpoint, Baud) then
      begin
        Log('Conectado: ' + MachineType.Text + ' / ' + ProtocolType.Text + ' em ' + Endpoint);
        Session.SetFeedRate(FeedRate.Value);
      end
      else Log('Falha ao conectar em ' + Endpoint + '. Confira a porta e o equipamento.');
    except
      on E: Exception do Log('Falha na conexao: ' + E.Message);
    end;
  end;
  UpdateControls;
end;

procedure TMainForm.OpenClick(Sender: TObject);
var D: TOpenDialog;
begin
  D := TOpenDialog.Create(Self);
  try
    D.Title := 'Abrir programa';
    if MachineType.ItemIndex = 2 then begin
      D.Title := 'Abrir G-code da impressora 3D';
      D.Filter := 'G-code|*.gcode;*.gco;*.nc;*.ngc|Todos os arquivos|*.*';
    end else begin
      D.Title := 'Abrir programa CNC / Laser';
      D.Filter := 'Programas CNC|*.nc;*.tap;*.cnc;*.ngc;*.gcode|Todos os arquivos|*.*';
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
    Log('Programa carregado: ' + Session.FileName);
    if Session.Bounds.HasMotion then
      Log(Format('Dimensoes da peca: %.2f x %.2f mm (X: %.2f..%.2f, Y: %.2f..%.2f)',
        [BoundsWidth(Session.Bounds), BoundsHeight(Session.Bounds),
         Session.Bounds.MinX, Session.Bounds.MaxX,
         Session.Bounds.MinY, Session.Bounds.MaxY], InvariantFS));
  except
    on E: Exception do MessageDlg('Nao foi possivel abrir', E.Message, mtError, [mbOK], 0);
  end;
  UpdateControls;
end;

procedure TMainForm.DropFiles(Sender: TObject; const FileNames: array of string);
begin
  if Length(FileNames) <> 1 then begin
    Status.SimpleText := 'Arraste apenas um arquivo de G-code por vez.';
    Exit;
  end;
  if Session.State in [ssRunning, ssPaused] then begin
    Status.SimpleText := 'Pare o programa antes de abrir outro arquivo.';
    Exit;
  end;
  LoadProgram(FileNames[0]);
end;

procedure TMainForm.SearchChanged(Sender: TObject);
begin
  ProgramMemo.SelStart := 0;
  ProgramMemo.SelLength := 0;
  SearchResult.Caption := 'Enter ou F3 para buscar. A busca retorna ao inicio.';
end;

procedure TMainForm.SearchClick(Sender: TObject);
var Source, Query: string; Offset, FoundAt, LineNo, I: Integer; Wrapped: Boolean;
begin
  Query := UpperCase(SearchEdit.Text);
  if Query = '' then begin SearchResult.Caption := 'Digite um texto para buscar.'; Exit; end;
  Source := UpperCase(ProgramMemo.Text);
  Offset := Length(UTF8Copy(Source, 1, ProgramMemo.SelStart + ProgramMemo.SelLength)) + 1;
  FoundAt := PosEx(Query, Source, Offset);
  Wrapped := (FoundAt = 0) and (Offset > 1);
  if Wrapped then FoundAt := PosEx(Query, Source, 1);
  if FoundAt = 0 then begin SearchResult.Caption := 'Texto nao encontrado.'; Exit; end;
  Pages.ActivePage := ProgramTab;
  ProgramMemo.SelStart := UTF8Length(Copy(Source, 1, FoundAt - 1));
  ProgramMemo.SelLength := UTF8Length(Query);
  LineNo := 1;
  for I := 1 to FoundAt - 1 do if Source[I] = #10 then Inc(LineNo);
  SearchResult.Caption := Format('Comando %d da lista carregada', [LineNo]);
  if Wrapped then SearchResult.Caption := SearchResult.Caption + ' (voltou ao inicio)';
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
    D.Title := 'Salvar registro do console';
    D.Filter := 'Arquivo de texto|*.txt';
    D.DefaultExt := 'txt';
    D.FileName := 'multicnc-' + FormatDateTime('yyyymmdd-hhnnss', Now) + '.txt';
    D.Options := [ofOverwritePrompt, ofPathMustExist, ofEnableSizing];
    if D.Execute then
      try
        MemoLog.Lines.SaveToFile(D.FileName);
        Status.SimpleText := 'Registro salvo: ' + D.FileName;
      except
        on E: Exception do MessageDlg('Falha ao salvar registro', E.Message, mtError, [mbOK], 0);
      end;
  finally
    D.Free;
  end;
end;

procedure TMainForm.ClearLogClick(Sender: TObject);
begin
  MemoLog.Clear;
  Status.SimpleText := 'Console limpo. A maquina permanece no estado atual.';
end;

procedure TMainForm.FramingClick(Sender: TObject);
var FramingGCode: TStringList; PowerS: Integer;
begin
  if not Session.Connected then
  begin
    Log('Conecte o equipamento antes de contornar.');
    Exit;
  end;
  if Session.Count = 0 then
  begin
    Log('Nenhum programa carregado para contornar.');
    Exit;
  end;
  if not Session.Bounds.HasMotion then
  begin
    Log('Nao foi possivel determinar a area do programa para contorno.');
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
    Log(Format('Contornar: X(%.2f..%.2f) Y(%.2f..%.2f) a %.0f mm/min | Laser: %s',
      [Session.Bounds.MinX, Session.Bounds.MaxX, Session.Bounds.MinY, Session.Bounds.MaxY,
       Session.LaserSettings.FramingFeed,
       IfThen(Session.LaserSettings.FramingLaser, Format('LIGADO em teste (%.0f%% = S%d)', [Session.LaserSettings.FramingPower, PowerS]), 'DESLIGADO')],
      InvariantFS));
    if not Session.RunFraming(FramingGCode) then
      Log('Falha ao iniciar contorno: ' + Session.LastError);
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
      Log('Maquina desconectada.');
      Exit;
    end;
    if Session.Count = 0 then
    begin
      Log('Nenhum programa carregado.');
      Exit;
    end;
    if Session.MachineState in [msAlarm, msError] then
    begin
      Log('Maquina em alarme ou erro: desbloqueie ou referencie antes de iniciar.');
      Exit;
    end;

    { Pre-validacao de limites da maquina (envelope) }
    if Session.Bounds.HasMotion then
    begin
      if (Session.EnvelopeX > 0) and (Session.Bounds.MaxX > Session.EnvelopeX) then
      begin
        MessageDlg('ATENCAO: Limite Ultrapassado',
          Format('O trabalho ultrapassa o limite X da maquina.' + LineEnding +
                 'Area necessaria: %.2f mm' + LineEnding +
                 'Area disponivel: %.2f mm' + LineEnding + LineEnding +
                 'Inicio cancelado.',
                 [Session.Bounds.MaxX, Session.EnvelopeX], InvariantFS),
          mtWarning, [mbOK], 0);
        Log('Inicio cancelado: ultrapassa o limite X da maquina.');
        Exit;
      end;
      if (Session.EnvelopeY > 0) and (Session.Bounds.MaxY > Session.EnvelopeY) then
      begin
        MessageDlg('ATENCAO: Limite Ultrapassado',
          Format('O trabalho ultrapassa o limite Y da maquina.' + LineEnding +
                 'Area necessaria: %.2f mm' + LineEnding +
                 'Area disponivel: %.2f mm' + LineEnding + LineEnding +
                 'Inicio cancelado.',
                 [Session.Bounds.MaxY, Session.EnvelopeY], InvariantFS),
          mtWarning, [mbOK], 0);
        Log('Inicio cancelado: ultrapassa o limite Y da maquina.');
        Exit;
      end;
    end;

    SyncLaserSettingsFromUI;

    { Se configurado para executar contorno antes de iniciar no modo Laser }
    if (MachineType.ItemIndex = 1) and Session.LaserSettings.FrameBeforeStart and Session.Bounds.HasMotion then
    begin
      FramingClick(Sender);
      if MessageDlg('Confirmacao de Posicionamento',
        'O percurso de contorno foi executado.' + LineEnding + LineEnding +
        'A posicao da peca na mesa esta correta para iniciar o trabalho?',
        mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
      begin
        Log('Inicio de trabalho cancelado pelo operador apos o contorno.');
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
      Log(Format('Referenciar Home: posicao registrada como HOME em X: %.3f, Y: %.3f, Z: %.3f (G28.1 gravado, sem movimento)',
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
  else Log('Acao recusada: ' + Session.LastError);
  UpdateControls;
end;

procedure TMainForm.JogClick(Sender: TObject);
var Index: Integer; Distance: Double;
begin
  Index := TButton(Sender).Tag;
  Distance := StepSize.Value;
  if Index mod 2 = 0 then Distance := -Distance;
  if not Session.Jog(TAxis(Index div 2), Distance, FeedRate.Value) then
    Log('Movimento recusado: ' + Session.LastError);
  UpdateControls;
end;

procedure TMainForm.Tick(Sender: TObject);
begin
  try
    Session.Poll;
    Session.Tick;
  except
    on E: Exception do begin Session.Stop; Log('Falha durante a execucao: ' + E.Message); end;
  end;
  if Session.State <> LastState then
  begin
    case Session.State of
      ssDone: Log('Programa concluido: todas as linhas confirmadas pela controladora.');
      ssError: Log('Programa interrompido: ' + Session.LastError);
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
    CanClose := MessageDlg('Programa em andamento',
      'Parar a maquina e fechar?', mtConfirmation, [mbYes, mbNo], 0) = mrYes;
    if CanClose then Session.Stop;
  end;
end;

end.
