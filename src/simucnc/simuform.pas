unit simuform;
{$mode objfpc}{$H+}
interface
uses multisuite_numfmt, Math, aitcpserver, Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls, Dialogs,
  aimarlinserialdevice, aimarlinsimulator, aivirtualserialpair, multicnc_print3d_view, simu_table_config_form, Graphics, Spin,
  multisuite_icons, multisuite_controls;
type
  TMainForm = class(TForm)
  private
    DeviceEdit, PeerEdit, BaudEdit, SetupEdit: TEdit;
    ConnectButton, PairButton, ClearButton, ResetButton: TSuiteButton;
    ConfigButton: TSuiteButton;
    MachineButtons: array[0..2] of TSuiteButton;
    HeaderBar: TSuiteHeader;
    StateBadge: TSuiteBadge;
    FrameCheck:TCheckBox;
    RealPositionLabel, RefPositionLabel, RefIconLabel, HomeStatusLabel, LaserStatus:TLabel;
    TemperaturePanel: TPanel;
    LblSimHotend, LblSimBed, LblSimTempStatus: TLabel;
    SpSimHotendTarget, SpSimBedTarget: TSpinEdit;
    BtnSetSimHotend, BtnSetSimBed, BtnSimCooldown, BtnSimInstantHeat: TSuiteButton;
    CodeList:TListBox;
    CommandBuffer:string;
    LaserPower:Double;
    function GetActiveSimulator: TAIMarlinSimulator;
    procedure SetSimHotendClick(Sender: TObject);
    procedure SetSimBedClick(Sender: TObject);
    procedure SimCooldownClick(Sender: TObject);
    procedure SimInstantHeatClick(Sender: TObject);
    procedure CaptureCommands(const Data:string);
    procedure UpdateLaserPower(const Data:string);
    procedure UpdateLaserStatus;
    procedure ViewClick(Sender:TObject);
    procedure FrameChanged(Sender:TObject);
    procedure ConfigClick(Sender:TObject);
    function IsMarlin:Boolean;
    function FilterRealtime(const Data:string; Sim:TAIMarlinSimulator):string;
    procedure SerialReceive(Sender:TObject; const AText:string);
  private
    View: TPrint3DView; LogMemo: TMemo; Timer: TTimer; Status: TStatusBar;
    MachineCombo, ModeCombo, ProtocolCombo: TComboBox;
    SerialPanel, TCPPanel: TPanel;
    procedure ModeChanged(Sender: TObject);
    procedure MachineChanged(Sender: TObject);
    function SideLabel(AParent: TWinControl; const AText: string; X, Y, W: Integer): TLabel;
    function SideButton(AParent: TWinControl; const AText: string; X, Y, W, H: Integer;
      AStyle: TSuiteButtonStyle; AAccent: TColor; AIcon: TSuiteIconKind; AHandler: TNotifyEvent): TSuiteButton;
    function SectionTitle(AParent: TWinControl; const AText: string; AIcon: TSuiteIconKind; Y: Integer): TSuiteSectionTitle;
    procedure CardPaint(Sender: TObject);
    procedure HeaderResize(Sender: TObject);
    procedure DroResize(Sender: TObject);
    procedure MachineButtonClick(Sender: TObject);
    procedure ProtocolChanged(Sender: TObject);
    procedure UpdateMachineButtons;
    procedure UpdateStateBadge;
    procedure UpdateViewTitle;
    procedure ApplyMachineDefaults;
  private
    TCP: TAITCPServer;
    TCPMarlin: TAIMarlinSimulator;
    HostEdit, PortEdit: TEdit;
    TCPButton: TSuiteButton;
    LastTick: QWord;
    procedure TCPClick(Sender: TObject);
    procedure TCPData(Sender: TObject; const Data: string);
    procedure TCPResponse(Sender: TObject; const Data: string);
    procedure TCPConnected(Sender: TObject);
    procedure TCPDisconnected(Sender: TObject);
  private
    Device: TAIMarlinSerialDevice; PairManager: TAIVirtualSerialPair;
    procedure ConnectClick(Sender: TObject); procedure PairClick(Sender: TObject); procedure ClearClick(Sender: TObject);
    procedure ResetClick(Sender: TObject); procedure Tick(Sender: TObject);
    procedure Traffic(Sender: TObject; const AText: string);
    procedure Motion(Sender: TObject; const A, B: TAIMarlinPosition; Material: Double);
    procedure Log(const S: string);
  public constructor Create(AOwner: TComponent); override; destructor Destroy; override;
  end;
implementation
const
  SB_W = 284;      { largura das barras laterais }
  SB_X = 16;       { margem interna }
  SB_IW = 251;     { largura util }
  SB_HALF = 122;   { meia largura }
  SB_X2 = 145;     { segunda coluna }

function TMainForm.SideLabel(AParent: TWinControl; const AText: string; X, Y, W: Integer): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := AParent;
  Result.AutoSize := False;
  Result.SetBounds(X, Y, W, 18);
  Result.Caption := AText;
  Result.Font.Size := 9;
  Result.Font.Color := clSuiteMuted;
end;

function TMainForm.SideButton(AParent: TWinControl; const AText: string; X, Y, W, H: Integer;
  AStyle: TSuiteButtonStyle; AAccent: TColor; AIcon: TSuiteIconKind; AHandler: TNotifyEvent): TSuiteButton;
begin
  Result := TSuiteButton.Create(Self);
  Result.Parent := AParent;
  Result.SetBounds(X, Y, W, H);
  Result.Caption := AText;
  Result.SetLook(AStyle, AAccent, AIcon);
  Result.OnClick := AHandler;
  Result.ShowHint := True;
end;

function TMainForm.SectionTitle(AParent: TWinControl; const AText: string;
  AIcon: TSuiteIconKind; Y: Integer): TSuiteSectionTitle;
begin
  Result := TSuiteSectionTitle.CreateTitle(Self, AText, AIcon, clSuitePrimary);
  Result.Parent := AParent;
  Result.SetBounds(SB_X, Y, SB_IW, 22);
end;

procedure TMainForm.CardPaint(Sender: TObject);
var
  P: TPanel;
begin
  P := TPanel(Sender);
  P.Canvas.Pen.Color := clSuiteBorder;
  if P.Align = alLeft then
    P.Canvas.Line(P.Width - 1, 0, P.Width - 1, P.Height)
  else if P.Align = alRight then
    P.Canvas.Line(0, 0, 0, P.Height)
  else
    P.Canvas.Line(0, P.Height - 1, P.Width, P.Height - 1);
end;

procedure TMainForm.HeaderResize(Sender: TObject);
begin
  if (HeaderBar = nil) or (StateBadge = nil) then Exit;
  StateBadge.AnchorRight := HeaderBar.ClientWidth - 20;
  StateBadge.AutoFit;
end;

procedure TMainForm.MachineButtonClick(Sender: TObject);
begin
  if (Sender is TControl) and (MachineCombo.ItemIndex <> TControl(Sender).Tag) then
  begin
    MachineCombo.ItemIndex := TControl(Sender).Tag;
    MachineChanged(MachineCombo);
  end;
end;

procedure TMainForm.UpdateMachineButtons;
const
  Accents: array[0..2] of array[0..2] of Byte = ((234, 88, 12), (37, 99, 235), (124, 58, 237));
  Icons: array[0..2] of TSuiteIconKind = (sikSlicer, sikCAM, sikLaserPCB);
var
  I: Integer;
  C: TColor;
begin
  for I := 0 to 2 do
    if Assigned(MachineButtons[I]) then
    begin
      C := RGBToColor(Accents[I][0], Accents[I][1], Accents[I][2]);
      if MachineCombo.ItemIndex = I then
        MachineButtons[I].SetLook(sbsSolid, C, Icons[I])
      else
        MachineButtons[I].SetLook(sbsOutline, C, Icons[I]);
    end;
end;

procedure TMainForm.UpdateStateBadge;
begin
  if StateBadge = nil then Exit;
  if TCP.Active then
  begin
    if TCP.Connected then
    begin
      StateBadge.Caption := 'TCP: controladora conectada';
      StateBadge.DotColor := clSuiteSuccess;
    end
    else
    begin
      StateBadge.Caption := 'TCP: aguardando controladora';
      StateBadge.DotColor := clSuiteWarning;
    end;
  end
  else if Device.Serial.Active then
  begin
    StateBadge.Caption := 'Serial ativa em ' + Trim(DeviceEdit.Text);
    StateBadge.DotColor := clSuiteSuccess;
  end
  else
  begin
    StateBadge.Caption := 'Simulador desligado';
    StateBadge.DotColor := clSuiteNeutral;
  end;
end;

constructor TMainForm.Create(AOwner: TComponent);
var
  Header: TSuiteHeader;
  LeftBar, RightBar, Toolbar, Dro, Center, LogHead: TPanel;
  L: TLabel; B: TSuiteButton; I, Y: Integer;
begin
  inherited CreateNew(AOwner);
  Caption := 'SimuCNC - Simulador de equipamento CNC';
  Position := poScreenCenter;
  SetBounds(0, 0, 1300, 820);
  Constraints.MinWidth := 1200;
  Constraints.MinHeight := 700;
  Font.Name := 'Segoe UI';
  Font.Size := 10;
  Color := clSuiteSurface;
  ShowHint := True;

  { Cabecalho }
  Header := TSuiteHeader.Create(Self);
  Header.Parent := Self;
  Header.Align := alTop;
  Header.Height := 72;
  Header.Setup('SimuCNC', 'Simulador de equipamentos: impressora 3D, CNC router e CNC laser', sikCNC);
  Header.OnResize := @HeaderResize;
  HeaderBar := Header;
  StateBadge := TSuiteBadge.Create(Self);
  StateBadge.Parent := Header;
  StateBadge.SetBounds(900, 21, 200, 30);
  StateBadge.Caption := 'Simulador desligado';

  Status := TStatusBar.Create(Self); Status.Parent := Self; Status.Align := alBottom;
  Status.SimplePanel := True; Status.SimpleText := 'Porta virtual desligada';

  { ---------------- Barra esquerda: equipamento, conexao, temperatura }
  LeftBar := TPanel.Create(Self); LeftBar.Parent := Self; LeftBar.Align := alLeft;
  LeftBar.Width := SB_W; LeftBar.BevelOuter := bvNone; LeftBar.Color := clSuiteCard;
  LeftBar.ParentColor := False; LeftBar.OnPaint := @CardPaint;

  SectionTitle(LeftBar, 'EQUIPAMENTO', sikGear, 14);
  MachineCombo := TComboBox.Create(Self); MachineCombo.Parent := LeftBar; MachineCombo.Visible := False;
  MachineCombo.Style := csDropDownList; MachineCombo.Items.Add('Impressora 3D');
  MachineCombo.Items.Add('CNC Router'); MachineCombo.Items.Add('CNC Laser');
  MachineCombo.ItemIndex := 0; MachineCombo.OnChange := @MachineChanged;
  for I := 0 to 2 do
  begin
    MachineButtons[I] := SideButton(LeftBar, MachineCombo.Items[I], SB_X, 42 + I * 46, SB_IW, 40,
      sbsOutline, clSuitePrimary, sikCNC, @MachineButtonClick);
    MachineButtons[I].Tag := I;
  end;
  MachineButtons[0].Hint := 'Impressora 3D cartesiana (Marlin): mesa aquecida, hotend e filamento';
  MachineButtons[1].Hint := 'CNC Router (GRBL): portico, spindle e fresa entalhando madeira';
  MachineButtons[2].Hint := 'CNC Laser (GRBL): modulo laser gravando/cortando a chapa';

  Y := 190;
  SectionTitle(LeftBar, 'CONEXAO', sikPlug, Y);
  SideLabel(LeftBar, 'Comunicacao', SB_X, Y + 28, SB_HALF);
  ModeCombo := TComboBox.Create(Self); ModeCombo.Parent := LeftBar;
  ModeCombo.SetBounds(SB_X, Y + 48, SB_HALF, 28);
  ModeCombo.Items.Add('Serial'); ModeCombo.Items.Add('TCP'); ModeCombo.ItemIndex := 0;
  ModeCombo.Style := csDropDownList; ModeCombo.OnChange := @ModeChanged;
  ModeCombo.Hint := 'Interface de comunicacao (porta serial virtual ou rede TCP)';
  SideLabel(LeftBar, 'Protocolo', SB_X2, Y + 28, SB_HALF);
  ProtocolCombo := TComboBox.Create(Self); ProtocolCombo.Parent := LeftBar;
  ProtocolCombo.SetBounds(SB_X2, Y + 48, SB_HALF, 28);
  ProtocolCombo.Style := csDropDownList; ProtocolCombo.Items.Add('Marlin'); ProtocolCombo.Items.Add('GRBL');
  ProtocolCombo.ItemIndex := 0;
  ProtocolCombo.Hint := 'Dialeto do firmware (Marlin 3D ou GRBL router/laser)';
  ProtocolCombo.OnChange := @ProtocolChanged;

  SerialPanel := TPanel.Create(Self); SerialPanel.Parent := LeftBar; SerialPanel.BevelOuter := bvNone;
  SerialPanel.Color := clSuiteCard; SerialPanel.ParentColor := False;
  SerialPanel.SetBounds(0, Y + 86, SB_W - 1, 196);
  TCPPanel := TPanel.Create(Self); TCPPanel.Parent := LeftBar; TCPPanel.BevelOuter := bvNone;
  TCPPanel.Color := clSuiteCard; TCPPanel.ParentColor := False;
  TCPPanel.SetBounds(0, Y + 86, SB_W - 1, 196);

  SideLabel(SerialPanel, 'Porta serial', SB_X, 0, SB_HALF);
  DeviceEdit := TEdit.Create(Self); DeviceEdit.Parent := SerialPanel; DeviceEdit.SetBounds(SB_X, 20, SB_HALF, 28);
  DeviceEdit.Text := 'COM4'; DeviceEdit.Hint := 'Porta COM virtual aberta pelo SimuCNC (ex.: COM4)';
  SideLabel(SerialPanel, 'Baud', SB_X2, 0, SB_HALF);
  BaudEdit := TEdit.Create(Self); BaudEdit.Parent := SerialPanel; BaudEdit.SetBounds(SB_X2, 20, SB_HALF, 28);
  BaudEdit.Text := '115200'; BaudEdit.Hint := 'Velocidade da porta serial';
  SideLabel(SerialPanel, 'COM do MultiCNC (par virtual)', SB_X, 54, SB_IW);
  PeerEdit := TEdit.Create(Self); PeerEdit.Parent := SerialPanel; PeerEdit.SetBounds(SB_X, 74, SB_HALF, 28);
  PeerEdit.Text := 'COM3'; PeerEdit.Hint := 'Porta COM virtual usada pelo MultiCNC (ex.: COM3)';
  ConnectButton := SideButton(SerialPanel, 'Iniciar serial', SB_X2, 72, SB_HALF, 32,
    sbsSolid, clSuiteSuccess, sikPlay, @ConnectClick);
  ConnectButton.Hint := 'Abre ou fecha a porta serial virtual';
  SideLabel(SerialPanel, 'setupc.exe (com0com)', SB_X, 112, SB_IW);
  SetupEdit := TEdit.Create(Self); SetupEdit.Parent := SerialPanel; SetupEdit.SetBounds(SB_X, 132, SB_IW, 28);
  SetupEdit.Text := 'C:\Program Files (x86)\com0com\setupc.exe';
  SetupEdit.Hint := 'Caminho do setupc.exe do com0com';
  PairButton := SideButton(SerialPanel, 'Criar par virtual', SB_X, 164, SB_IW, 30,
    sbsOutline, clSuitePrimary, sikPlug, @PairClick);
  PairButton.Hint := 'Cria o par de portas COM virtuais com o com0com';

  SideLabel(TCPPanel, 'IP local', SB_X, 0, SB_HALF);
  HostEdit := TEdit.Create(Self); HostEdit.Parent := TCPPanel; HostEdit.SetBounds(SB_X, 20, SB_HALF, 28);
  HostEdit.Text := '0.0.0.0'; HostEdit.Hint := 'Endereco para escutar (0.0.0.0 = todas as interfaces)';
  SideLabel(TCPPanel, 'Porta TCP', SB_X2, 0, SB_HALF);
  PortEdit := TEdit.Create(Self); PortEdit.Parent := TCPPanel; PortEdit.SetBounds(SB_X2, 20, SB_HALF, 28);
  PortEdit.Text := '9000'; PortEdit.Hint := 'Porta TCP de escuta (ex.: 9000)';
  TCPButton := SideButton(TCPPanel, 'Iniciar TCP', SB_X, 58, SB_IW, 34,
    sbsSolid, clSuiteSuccess, sikPlay, @TCPClick);
  TCPButton.Hint := 'Inicia ou para o servidor TCP de G-code';
  L := SideLabel(TCPPanel, 'G-code via TCP. Use 0.0.0.0 para escutar em todas as interfaces e conecte o MultiCNC em 127.0.0.1.', SB_X, 100, SB_IW);
  L.Height := 54; L.WordWrap := True;

  Y := Y + 290;
  TemperaturePanel := TPanel.Create(Self); TemperaturePanel.Parent := LeftBar;
  TemperaturePanel.BevelOuter := bvNone; TemperaturePanel.Color := clSuiteCard;
  TemperaturePanel.ParentColor := False; TemperaturePanel.ShowHint := True;
  TemperaturePanel.SetBounds(0, Y, SB_W - 1, 196);
  with TSuiteSectionTitle.CreateTitle(Self, 'TEMPERATURA', sikThermo, clSuiteWarning) do
  begin
    Parent := TemperaturePanel; SetBounds(SB_X, 0, SB_IW, 22);
  end;
  LblSimHotend := SideLabel(TemperaturePanel, 'Bico: 25.0 °C / 0 °C', SB_X, 30, SB_IW);
  LblSimHotend.Font.Style := [fsBold]; LblSimHotend.Font.Color := clSuiteText;
  LblSimHotend.Hint := 'Temperatura atual e alvo do bico (°C)';
  SpSimHotendTarget := TSpinEdit.Create(Self); SpSimHotendTarget.Parent := TemperaturePanel;
  SpSimHotendTarget.SetBounds(SB_X, 50, SB_HALF, 28); SpSimHotendTarget.MinValue := 0;
  SpSimHotendTarget.MaxValue := 320; SpSimHotendTarget.Value := 200;
  SpSimHotendTarget.Hint := 'Temperatura alvo do bico (M104)';
  BtnSetSimHotend := SideButton(TemperaturePanel, 'Definir bico', SB_X2, 49, SB_HALF, 30,
    sbsSoft, clSuiteWarning, sikFlame, @SetSimHotendClick);
  BtnSetSimHotend.Hint := 'Aplica a temperatura alvo do bico';
  LblSimBed := SideLabel(TemperaturePanel, 'Mesa: 25.0 °C / 0 °C', SB_X, 86, SB_IW);
  LblSimBed.Font.Style := [fsBold]; LblSimBed.Font.Color := clSuiteText;
  LblSimBed.Hint := 'Temperatura atual e alvo da mesa aquecida (°C)';
  SpSimBedTarget := TSpinEdit.Create(Self); SpSimBedTarget.Parent := TemperaturePanel;
  SpSimBedTarget.SetBounds(SB_X, 106, SB_HALF, 28); SpSimBedTarget.MinValue := 0;
  SpSimBedTarget.MaxValue := 150; SpSimBedTarget.Value := 60;
  SpSimBedTarget.Hint := 'Temperatura alvo da mesa (M140)';
  BtnSetSimBed := SideButton(TemperaturePanel, 'Definir mesa', SB_X2, 105, SB_HALF, 30,
    sbsSoft, clSuiteWarning, sikFlame, @SetSimBedClick);
  BtnSetSimBed.Hint := 'Aplica a temperatura alvo da mesa';
  BtnSimCooldown := SideButton(TemperaturePanel, 'Desligar', SB_X, 144, SB_HALF, 30,
    sbsOutline, clSuiteInfo, sikSnow, @SimCooldownClick);
  BtnSimCooldown.Hint := 'Desliga bico e mesa (alvo 0 °C)';
  BtnSimInstantHeat := SideButton(TemperaturePanel, 'Aquecer ja', SB_X2, 144, SB_HALF, 30,
    sbsOutline, clSuiteDanger, sikFlame, @SimInstantHeatClick);
  BtnSimInstantHeat.Hint := 'Atinge a temperatura alvo instantaneamente (teste rapido)';
  LblSimTempStatus := SideLabel(TemperaturePanel, 'Aquecedores desligados', SB_X, 178, SB_IW);
  LblSimTempStatus.Font.Style := [fsBold];
  LblSimTempStatus.Hint := 'Estado do sistema termico simulado';

  { ---------------- Barra direita: G-code recebido e registro }
  RightBar := TPanel.Create(Self); RightBar.Parent := Self; RightBar.Align := alRight;
  RightBar.Width := SB_W; RightBar.BevelOuter := bvNone; RightBar.Color := clSuiteCard;
  RightBar.ParentColor := False; RightBar.OnPaint := @CardPaint;
  LogHead := TPanel.Create(Self); LogHead.Parent := RightBar; LogHead.Align := alTop; LogHead.Height := 40;
  LogHead.BevelOuter := bvNone; LogHead.Color := clSuiteCard; LogHead.ParentColor := False;
  SectionTitle(LogHead, 'G-CODE RECEBIDO', sikFile, 12);
  LogMemo := TMemo.Create(Self); LogMemo.Parent := RightBar; LogMemo.Align := alBottom; LogMemo.Height := 190;
  LogMemo.ReadOnly := True; LogMemo.ScrollBars := ssAutoBoth; LogMemo.Font.Name := 'Consolas'; LogMemo.Font.Size := 8;
  LogMemo.BorderSpacing.Left := 10; LogMemo.BorderSpacing.Right := 10; LogMemo.BorderSpacing.Bottom := 10;
  LogMemo.Hint := 'Registro de comunicacao e diagnostico';
  LogHead := TPanel.Create(Self); LogHead.Parent := RightBar; LogHead.Align := alBottom; LogHead.Height := 44;
  LogHead.BevelOuter := bvNone; LogHead.Color := clSuiteCard; LogHead.ParentColor := False;
  SectionTitle(LogHead, 'REGISTRO', sikTerminal, 14);
  ClearButton := SideButton(LogHead, 'Limpar', SB_W - 106, 8, 92, 28, sbsOutline, clSuiteDanger, sikTrash, @ClearClick);
  ClearButton.Hint := 'Limpa a janela de registro';
  CodeList := TListBox.Create(Self); CodeList.Name := 'ReceivedGCode'; CodeList.Parent := RightBar; CodeList.Align := alClient;
  CodeList.Font.Name := 'Consolas'; CodeList.Font.Size := 10;
  CodeList.BorderSpacing.Left := 10; CodeList.BorderSpacing.Right := 10;
  CodeList.Hint := 'Fluxo de G-code recebido (ultima linha destacada)';

  { ---------------- Centro: barra de vista, 3D e leitura de posicao }
  Center := TPanel.Create(Self); Center.Parent := Self; Center.Align := alClient;
  Center.BevelOuter := bvNone; Center.Color := clSuiteSurface; Center.ParentColor := False;

  Toolbar := TPanel.Create(Self); Toolbar.Parent := Center; Toolbar.Align := alTop; Toolbar.Height := 52;
  Toolbar.BevelOuter := bvNone; Toolbar.Color := clSuiteCard; Toolbar.ParentColor := False;
  Toolbar.OnPaint := @CardPaint;
  for I := 0 to 2 do
  begin
    case I of
      0: B := SideButton(Toolbar, 'Perspectiva', 12, 10, 114, 32, sbsOutline, clSuitePrimary, sikCAD, @ViewClick);
      1: B := SideButton(Toolbar, 'Topo', 132, 10, 78, 32, sbsOutline, clSuitePrimary, sikArrowDown, @ViewClick);
    else
      B := SideButton(Toolbar, 'Frente', 216, 10, 86, 32, sbsOutline, clSuitePrimary, sikFrame, @ViewClick);
    end;
    B.Tag := I;
    case I of
      0: B.Hint := 'Vista em perspectiva (isometrica)';
      1: B.Hint := 'Vista de topo (plano XY)';
      2: B.Hint := 'Vista frontal (plano XZ)';
    end;
  end;
  FrameCheck := TCheckBox.Create(Self); FrameCheck.Parent := Toolbar; FrameCheck.Caption := 'Volume';
  FrameCheck.SetBounds(314, 15, 80, 24); FrameCheck.OnChange := @FrameChanged;
  FrameCheck.Hint := 'Mostra ou oculta o contorno do volume de trabalho';
  ConfigButton := SideButton(Toolbar, 'Mesa', 398, 10, 80, 32, sbsOutline, clSuitePrimary, sikGear, @ConfigClick);
  ConfigButton.Hint := 'Dimensoes da mesa e limites de trabalho (X, Y, Z)';
  ResetButton := SideButton(Toolbar, 'Limpar peca', 484, 10, 120, 32, sbsOutline, clSuiteDanger, sikTrash, @ResetClick);
  ResetButton.Hint := 'Limpa a peca 3D, o historico de trajetoria e reinicia o simulador';

  Dro := TPanel.Create(Self); Dro.Parent := Center; Dro.Align := alBottom; Dro.Height := 66;
  Dro.BevelOuter := bvNone; Dro.Color := clSuiteNavy; Dro.ParentColor := False;
  RealPositionLabel := TLabel.Create(Self); RealPositionLabel.Parent := Dro; RealPositionLabel.SetBounds(16, 9, 560, 22);
  RealPositionLabel.Font.Size := 11; RealPositionLabel.Font.Name := 'Consolas'; RealPositionLabel.Font.Style := [fsBold];
  RealPositionLabel.Font.Color := RGBToColor(110, 231, 183);
  RealPositionLabel.Caption := 'MPos  X    0.000   Y    0.000   Z    0.000 mm';
  RealPositionLabel.Hint := 'Posicao real da maquina (MPos) - coordenadas fisicas absolutas';
  RefPositionLabel := TLabel.Create(Self); RefPositionLabel.Parent := Dro; RefPositionLabel.SetBounds(16, 35, 560, 22);
  RefPositionLabel.Font.Size := 11; RefPositionLabel.Font.Name := 'Consolas'; RefPositionLabel.Font.Style := [fsBold];
  RefPositionLabel.Font.Color := RGBToColor(252, 211, 77);
  RefPositionLabel.Caption := 'WPos  X    0.000   Y    0.000   Z    0.000 mm';
  RefPositionLabel.Hint := 'Posicao de trabalho (WPos) - deslocada pela origem G92';
  HomeStatusLabel := TLabel.Create(Self); HomeStatusLabel.Parent := Dro; HomeStatusLabel.SetBounds(560, 9, 260, 22);
  HomeStatusLabel.Font.Size := 9; HomeStatusLabel.Font.Style := [fsBold];
  HomeStatusLabel.Caption := 'HOME G28: nao definido'; HomeStatusLabel.Font.Color := clSuiteFaint;
  HomeStatusLabel.Hint := 'Referencia HOME armazenada (G28.1)';
  HomeStatusLabel.Anchors := [akTop, akRight];
  RefIconLabel := TLabel.Create(Self); RefIconLabel.Parent := Dro; RefIconLabel.SetBounds(560, 35, 260, 22);
  RefIconLabel.Font.Size := 9; RefIconLabel.Font.Style := [fsBold];
  RefIconLabel.Caption := 'Origem: zero fisico'; RefIconLabel.Font.Color := clSuiteFaint;
  RefIconLabel.Hint := 'Origem fisica da maquina ativa (sem deslocamento G92)';
  RefIconLabel.Anchors := [akTop, akRight];
  LaserStatus := TLabel.Create(Self); LaserStatus.Parent := Dro; LaserStatus.SetBounds(560, 22, 120, 22);
  LaserStatus.Visible := False;
  LaserStatus.Caption := 'Laser: 0'; LaserStatus.Hint := 'Potencia simulada do laser/spindle (S0..S1000)';
  Dro.OnResize := @DroResize;

  View := TPrint3DView.Create(Self); View.Name := 'PrinterView'; View.Parent := Center; View.Align := alClient;

  PairManager:=TAIVirtualSerialPair.Create(Self);
  Device:=TAIMarlinSerialDevice.Create(Self); Device.OnTraffic:=@Traffic; Device.Simulator.OnMotion:=@Motion;
  Device.Serial.OnRXReceive:=@SerialReceive; { trata os comandos de tempo real do GRBL }
  TCP:=TAITCPServer.Create(Self); TCP.OnData:=@TCPData;
  TCP.OnConnect:=@TCPConnected; TCP.OnDisconnect:=@TCPDisconnected;
  TCPMarlin:=TAIMarlinSimulator.Create(Self); TCPMarlin.OnMotion:=@Motion;
  TCPMarlin.OnResponse:=@TCPResponse;
  LastTick:=GetTickCount64;
  Timer:=TTimer.Create(Self); Timer.Interval:=33; Timer.OnTimer:=@Tick; Timer.Enabled:=True;
  ModeChanged(Self);
  MachineChanged(Self);
  if FindCmdLineSwitch('laser') then begin MachineCombo.ItemIndex:=2; MachineChanged(Self); end;
  if FindCmdLineSwitch('router') then begin MachineCombo.ItemIndex:=1; MachineChanged(Self); end;
  if FindCmdLineSwitch('grbl') then ProtocolCombo.ItemIndex:=ProtocolCombo.Items.IndexOf('GRBL');
  if FindCmdLineSwitch('tcp') then begin ModeCombo.ItemIndex:=1; ModeChanged(Self); TCPClick(Self); end;
  UpdateViewTitle;
  UpdateStateBadge;
  HeaderResize(nil);
end;

procedure TMainForm.DroResize(Sender: TObject);
var
  X: Integer;
begin
  X := Max(400, TPanel(Sender).ClientWidth - 270);
  HomeStatusLabel.Left := X;
  RefIconLabel.Left := X;
end;

{ Mesa padrao de cada equipamento (igual aos perfis do MultiCNC):
  impressora 220x220x250, router 3018 300x180x45, laser 400x400. }
procedure TMainForm.ApplyMachineDefaults;
var
  X, Y, Z: Double;
begin
  if not Assigned(View) then Exit;
  case MachineCombo.ItemIndex of
    1: begin X := 300; Y := 180; Z := 45; end;
    2: begin X := 400; Y := 400; Z := 10; end;
  else
    begin X := 220; Y := 220; Z := 250; end;
  end;
  View.SetBuildVolume(X, Y, Z);
  if Assigned(TCPMarlin) then TCPMarlin.SetBuildVolume(X, Y, Z);
  if Assigned(Device) then Device.Simulator.SetBuildVolume(X, Y, Z);
end;

procedure TMainForm.ProtocolChanged(Sender: TObject);
begin
  UpdateViewTitle;
end;

procedure TMainForm.UpdateViewTitle;
begin
  if Assigned(View) and (MachineCombo.ItemIndex >= 0) and (ProtocolCombo.ItemIndex >= 0) then
    View.InfoTitle := MachineCombo.Items[MachineCombo.ItemIndex] + '  |  ' +
      ProtocolCombo.Items[ProtocolCombo.ItemIndex];
end;
destructor TMainForm.Destroy; begin Timer.Enabled:=False; TCP.OnDisconnect:=nil; TCP.Stop; Device.Close; inherited Destroy; end;
procedure TMainForm.ViewClick(Sender:TObject);
begin case TControl(Sender).Tag of 0:View.ResetView;1:View.TopView;2:View.FrontView;end;end;
procedure TMainForm.FrameChanged(Sender:TObject);
begin View.ShowFrame:=FrameCheck.Checked;end;
procedure TMainForm.ConfigClick(Sender:TObject);
var X,Y,Z:Double;
begin
  X := View.VolumeX;
  Y := View.VolumeY;
  Z := View.VolumeZ;
  if not TTableConfigForm.Execute(X, Y, Z) then Exit;
  View.SetBuildVolume(X,Y,Z);
  TCPMarlin.SetBuildVolume(X,Y,Z);
  Device.Simulator.SetBuildVolume(X,Y,Z);
  Log(Format('Mesa configurada: X %.1f mm, Y %.1f mm, Z %.1f mm',[X,Y,Z],InvariantFS));
end;
procedure TMainForm.Log(const S:string); begin LogMemo.Lines.Add(FormatDateTime('hh:nn:ss',Now)+'  '+Trim(S)); while LogMemo.Lines.Count>1000 do LogMemo.Lines.Delete(0); end;
procedure TMainForm.CaptureCommands(const Data:string);
var I:Integer; Line:string;
begin
  for I:=1 to Length(Data) do begin
    if Data[I] in [#10,#13] then begin
      Line:=Trim(CommandBuffer);CommandBuffer:='';
      if Line<>'' then begin
        CodeList.Items.Add(Line);
        while CodeList.Items.Count>2000 do CodeList.Items.Delete(0);
        CodeList.ItemIndex:=CodeList.Items.Count-1;CodeList.TopIndex:=Max(0,CodeList.Items.Count-15);
        if (Pos('$J=',UpperCase(Line))=1) and IsMarlin then
          Log('Jog GRBL recebido com SimuCNC em Marlin; altere o protocolo para GRBL.');
      end;
    end else if Length(CommandBuffer)<4096 then CommandBuffer:=CommandBuffer+Data[I];
  end;
end;
procedure TMainForm.UpdateLaserStatus;
begin
  if Assigned(LaserStatus) then LaserStatus.Caption:=Format('Laser: %.0f',[LaserPower],InvariantFS);
end;
function TMainForm.IsMarlin:Boolean;
begin Result:=(ProtocolCombo.ItemIndex>=0) and (ProtocolCombo.Items[ProtocolCombo.ItemIndex]='Marlin'); end;
{ No GRBL, '?', '!', '~' e Ctrl-X (#24) sao comandos de tempo real, enviados
  sem quebra de linha e em qualquer ponto do fluxo. O simulador Marlin so
  entende linhas; sem este filtro, o '?' enviado periodicamente pelo MultiCNC
  seria grudado no proximo G-code ("?G1 X10") e causaria erro. }
function TMainForm.FilterRealtime(const Data:string; Sim:TAIMarlinSimulator):string;
var I:Integer;
begin
  if IsMarlin then Exit(Data);
  Result:='';
  for I:=1 to Length(Data) do
    case Data[I] of
      '?': Sim.SubmitLine('?');
      '!': Sim.Pause;
      '~': Sim.Resume;
      #24: begin Sim.Reset; LaserPower:=0; end;
    else Result:=Result+Data[I];
    end;
end;
procedure TMainForm.SerialReceive(Sender:TObject; const AText:string);
var Payload:string;
begin
  Payload:=FilterRealtime(AText,Device.Simulator);
  if Payload='' then Exit;
  Traffic(Device,'RX '+Payload);
  Device.Simulator.Receive(Payload);
end;
procedure TMainForm.Traffic(Sender:TObject; const AText:string);
begin
  if Copy(AText,1,4)='TX <' then Exit; { relatorio de estado periodico }
  Log(AText);
  if Copy(AText,1,3)='RX ' then begin
    UpdateLaserPower(Copy(AText,4,Length(AText)));
    CaptureCommands(Copy(AText,4,Length(AText)));
  end;
end;
procedure TMainForm.Motion(Sender:TObject; const A,B:TAIMarlinPosition; Material:Double);
var Power:Double;
begin
  { A potencia vem do simulador, no momento em que o movimento e executado.
    LaserPower reflete o ultimo comando recebido: com o envio antecipado
    (buffer do GRBL), o M5 do fim do programa chega antes dos G1 serem
    executados e zeraria a marcacao. }
  if Sender is TAIMarlinSimulator then begin
    Power:=TAIMarlinSimulator(Sender).State.LaserPower;
    { GRBL em modo laser ($32=1): movimento rapido (G0) nunca queima. }
    if TAIMarlinSimulator(Sender).RapidMove then Power:=0;
  end
  else Power:=LaserPower;
  case MachineCombo.ItemIndex of
    1: begin
         { Router: potencia do spindle, inclusive em G0 (a fresa continua girando) }
         if Sender is TAIMarlinSimulator then Power:=TAIMarlinSimulator(Sender).State.LaserPower;
         View.AddCutMotion(A,B,Power,(Sender is TAIMarlinSimulator) and TAIMarlinSimulator(Sender).RapidMove);
       end;
    2: if Power>0 then View.AddLaserMotion(A,B,Power) else View.AddMotion(Sender,A,B,0);
  else
    View.AddMotion(Sender,A,B,Material);
  end;
end;
procedure TMainForm.PairClick(Sender:TObject); begin
  PairManager.SetupExecutable:=Trim(SetupEdit.Text);
  if PairManager.CreatePair(Trim(DeviceEdit.Text),Trim(PeerEdit.Text)) then Log('Par virtual criado: '+DeviceEdit.Text+' <-> '+PeerEdit.Text)
  else Log('Falha ao criar par: '+PairManager.LastError+' '+PairManager.LastOutput);
end;

procedure TMainForm.ConnectClick(Sender:TObject); begin
  if TCP.Active then begin Log('Pare o servidor TCP antes de iniciar a serial.'); Exit; end;
  if Device.Serial.Active then begin Device.Close; ConnectButton.Caption:='Iniciar serial'; ConnectButton.SetLook(sbsSolid,clSuiteSuccess,sikPlay); Status.SimpleText:='Porta virtual desligada'; Log('Porta fechada.'); end
  else if Device.Open(Trim(DeviceEdit.Text),StrToIntDef(BaudEdit.Text,115200)) then begin ConnectButton.Caption:='Parar serial'; ConnectButton.SetLook(sbsSoft,clSuiteDanger,sikStop); Status.SimpleText:='Marlin virtual ativo em '+DeviceEdit.Text; Log('Marlin virtual pronto.'); end
  else Log('Falha ao abrir porta: '+Device.LastError);
  ModeCombo.Enabled:=not Device.Serial.Active;
  DeviceEdit.Enabled:=not Device.Serial.Active; BaudEdit.Enabled:=not Device.Serial.Active;
  PairButton.Enabled:=not Device.Serial.Active;
  UpdateStateBadge;
end;
function TMainForm.GetActiveSimulator: TAIMarlinSimulator;
begin
  if TCP.Active then Result := TCPMarlin else Result := Device.Simulator;
end;

procedure TMainForm.SetSimHotendClick(Sender: TObject);
var Sim: TAIMarlinSimulator;
begin
  Sim := GetActiveSimulator;
  if Assigned(Sim) then
  begin
    Sim.SetHotendTarget(SpSimHotendTarget.Value);
    Log(Format('Simulador: Temperatura alvo do bico alterada para %d °C', [SpSimHotendTarget.Value]));
  end;
end;

procedure TMainForm.SetSimBedClick(Sender: TObject);
var Sim: TAIMarlinSimulator;
begin
  Sim := GetActiveSimulator;
  if Assigned(Sim) then
  begin
    Sim.SetBedTarget(SpSimBedTarget.Value);
    Log(Format('Simulador: Temperatura alvo da cama alterada para %d °C', [SpSimBedTarget.Value]));
  end;
end;

procedure TMainForm.SimCooldownClick(Sender: TObject);
var Sim: TAIMarlinSimulator;
begin
  Sim := GetActiveSimulator;
  if Assigned(Sim) then
  begin
    Sim.SetHotendTarget(0);
    Sim.SetBedTarget(0);
    SpSimHotendTarget.Value := 0;
    SpSimBedTarget.Value := 0;
    Log('Simulador: Aquecedores desligados (resfriamento acionado).');
  end;
end;

procedure TMainForm.SimInstantHeatClick(Sender: TObject);
var Sim: TAIMarlinSimulator;
begin
  Sim := GetActiveSimulator;
  if Assigned(Sim) then
  begin
    if Sim.State.HotendTarget > 0 then
      Sim.SetHotendActual(Sim.State.HotendTarget)
    else if SpSimHotendTarget.Value > 0 then
    begin
      Sim.SetHotendTarget(SpSimHotendTarget.Value);
      Sim.SetHotendActual(SpSimHotendTarget.Value);
    end;

    if Sim.State.BedTarget > 0 then
      Sim.SetBedActual(Sim.State.BedTarget)
    else if SpSimBedTarget.Value > 0 then
    begin
      Sim.SetBedTarget(SpSimBedTarget.Value);
      Sim.SetBedActual(SpSimBedTarget.Value);
    end;

    Log(Format('Simulador: Aquecimento instantâneo acionado (Bico=%.1f °C, Cama=%.1f °C).',
      [Sim.State.Hotend, Sim.State.Bed], InvariantFS));
  end;
end;

procedure TMainForm.ResetClick(Sender:TObject);
begin
  LaserPower:=0; View.ClearPrint;
  if TCP.Active then TCPMarlin.Reset else Device.Simulator.Reset;
  if Assigned(SpSimHotendTarget) then SpSimHotendTarget.Value := 0;
  if Assigned(SpSimBedTarget) then SpSimBedTarget.Value := 0;
  Log('Simulador reiniciado.');
end;
procedure TMainForm.ClearClick(Sender:TObject); begin LogMemo.Clear; end;
procedure TMainForm.ModeChanged(Sender:TObject);
begin
  SerialPanel.Visible:=ModeCombo.ItemIndex=0;
  TCPPanel.Visible:=ModeCombo.ItemIndex=1;
end;
procedure TMainForm.MachineChanged(Sender:TObject);
begin
  ProtocolCombo.Items.BeginUpdate;
  try
    ProtocolCombo.Items.Clear;
    if MachineCombo.ItemIndex=0 then begin
      ProtocolCombo.Items.Add('Marlin'); ProtocolCombo.Items.Add('GRBL'); ProtocolCombo.ItemIndex:=0;
    end else begin
      ProtocolCombo.Items.Add('GRBL'); ProtocolCombo.ItemIndex:=0;
    end;
  finally ProtocolCombo.Items.EndUpdate; end;
  LaserPower:=0;
  if Assigned(TemperaturePanel) then TemperaturePanel.Visible := MachineCombo.ItemIndex = 0;
  if Assigned(View) then begin
    View.MachineKind:=TSimMachineKind(MachineCombo.ItemIndex); View.Invalidate;
    if Assigned(TCPMarlin) then TCPMarlin.AllowZ:=MachineCombo.ItemIndex<>2;
    if Assigned(Device) then Device.Simulator.AllowZ:=MachineCombo.ItemIndex<>2;
  end;
  ApplyMachineDefaults;
  UpdateMachineButtons;
  UpdateViewTitle;
  Log('Equipamento selecionado: '+MachineCombo.Items[MachineCombo.ItemIndex]+' / protocolo '+ProtocolCombo.Items[ProtocolCombo.ItemIndex]);
end;
procedure TMainForm.TCPClick(Sender:TObject);
begin
  if TCP.Active then TCP.Stop
  else begin
    if Device.Serial.Active then begin Log('Pare a serial antes de iniciar TCP.'); Exit; end;
    if not TCP.Start(Trim(HostEdit.Text),StrToIntDef(PortEdit.Text,0)) then begin
      Log('Falha TCP: '+TCP.LastError); Exit;
    end;
    Log('TCP escutando em '+HostEdit.Text+':'+PortEdit.Text);
  end;
  if TCP.Active then begin TCPButton.Caption:='Parar TCP'; TCPButton.SetLook(sbsSoft,clSuiteDanger,sikStop); TCPButton.Hint:='Para o servidor TCP e desconecta a controladora'; Status.SimpleText:='Servidor TCP escutando - aguardando controladora'; end
  else begin TCPButton.Caption:='Iniciar TCP'; TCPButton.SetLook(sbsSolid,clSuiteSuccess,sikPlay); TCPButton.Hint:='Inicia o servidor TCP de G-code'; Status.SimpleText:='Servidor TCP parado'; end;
  UpdateStateBadge;
  ModeCombo.Enabled:=not TCP.Active;
  HostEdit.Enabled:=not TCP.Active; PortEdit.Enabled:=not TCP.Active;
  ConnectButton.Enabled:=not TCP.Active; PairButton.Enabled:=not TCP.Active;
end;
procedure TMainForm.TCPData(Sender:TObject; const Data:string);
var Payload:string;
begin
  Payload:=FilterRealtime(Data,TCPMarlin);
  if Payload='' then Exit;
  UpdateLaserPower(Payload); CaptureCommands(Payload); Log('TCP RX '+Payload);
  if IsMarlin and (Pos('$J=',UpperCase(Trim(Payload)))=1) then begin
    Log('Comando GRBL ignorado: selecione o protocolo GRBL para simular este equipamento.');
    Exit;
  end;
  TCPMarlin.Receive(Payload);
end;
procedure TMainForm.UpdateLaserPower(const Data:string);
var Lines:TStringList; I,P,Q:Integer; U,Token:string; V:Double; FS:TFormatSettings;
begin
  if MachineCombo.ItemIndex<>2 then Exit;
  FS:=DefaultFormatSettings; FS.DecimalSeparator:='.';
  Lines:=TStringList.Create;
  try
    Lines.Text:=StringReplace(StringReplace(Data,#13#10,#10,[rfReplaceAll]),#13,#10,[rfReplaceAll]);
    for I:=0 to Lines.Count-1 do begin
      U:=UpperCase(Trim(Lines[I]));
      if Copy(U,1,2)='M5' then begin LaserPower:=0; Continue; end;
      P:=Pos('S',U);
      if P=0 then Continue;
      Q:=P+1; while (Q<=Length(U)) and (U[Q] in ['0'..'9','.',',','+','-']) do Inc(Q);
      Token:=StringReplace(Copy(U,P+1,Q-P-1),',','.',[rfReplaceAll]);
      if TryStrToFloat(Token,V,FS) then LaserPower:=EnsureRange(V,0,1000);
    end;
  finally Lines.Free; end;
end;
procedure TMainForm.TCPResponse(Sender:TObject; const Data:string);
begin
  if TCP.Connected then TCP.Send(Data);
  if Copy(Data,1,1)<>'<' then Log('TCP TX '+Data);
end;
procedure TMainForm.TCPConnected(Sender:TObject);
begin
  LaserPower:=0; Log('Controladora TCP conectada');
  Status.SimpleText:='TCP conectado';CommandBuffer:='';CodeList.Clear; View.ClearPrint; TCPMarlin.Reset;
  UpdateStateBadge;
end;
procedure TMainForm.TCPDisconnected(Sender:TObject);
begin
  LaserPower:=0; TCPMarlin.Pause;
  Log('Controladora TCP desconectada'); Status.SimpleText:='TCP aguardando controladora';
  UpdateStateBadge;
end;
procedure TMainForm.Tick(Sender:TObject);
var NowTick: QWord; Dt: Double; Sim: TAIMarlinSimulator; RealPos, RefPos: TAIMarlinPosition;
begin
  NowTick:=GetTickCount64; Dt:=(NowTick-LastTick)/1000; LastTick:=NowTick;
  if Dt<0 then Dt:=0 else if Dt>0.2 then Dt:=0.2;
  if TCP.Active then begin TCP.Poll; if TCP.Connected then TCPMarlin.Advance(Dt); end
  else Device.Poll(Dt);
  if TCP.Active then Sim := TCPMarlin else Sim := Device.Simulator;
  RealPos := Sim.State.Position;
  RefPos := Sim.WorkPosition;
  View.SetToolState(Sim.State.LaserPower, Sim.RapidMove);
  View.SetTemperatures(Sim.State.Hotend, Sim.State.HotendTarget, Sim.State.Bed, Sim.State.BedTarget);
  { Router: o zero de trabalho em Z (G92) marca a superficie do bloco }
  if (MachineCombo.ItemIndex = 1) and Sim.G92Active and ((RealPos.Z - RefPos.Z) > 0.5) then
    View.StockTop := (RealPos.Z - RefPos.Z)
  else
    View.StockTop := 0;
  View.SetPosition(RealPos);
  if TCP.Active and (StateBadge <> nil) and
     ((TCP.Connected and (StateBadge.DotColor <> clSuiteSuccess)) or
      ((not TCP.Connected) and (StateBadge.DotColor = clSuiteSuccess))) then
    UpdateStateBadge;
  RealPositionLabel.Caption := Format('MPos  X %8.3f   Y %8.3f   Z %8.3f mm',
    [RealPos.X, RealPos.Y, RealPos.Z], InvariantFS);
  RefPositionLabel.Caption := Format('WPos  X %8.3f   Y %8.3f   Z %8.3f mm',
    [RefPos.X, RefPos.Y, RefPos.Z], InvariantFS);
  if Sim.G28HomeSet then
  begin
    HomeStatusLabel.Caption := Format('HOME G28: %.1f, %.1f, %.1f',
      [Sim.G28Home.X, Sim.G28Home.Y, Sim.G28Home.Z], InvariantFS);
    HomeStatusLabel.Font.Color := RGBToColor(125, 211, 252);
    HomeStatusLabel.Hint := Format('Stored HOME reference point (G28.1): X=%.3f, Y=%.3f, Z=%.3f',
      [Sim.G28Home.X, Sim.G28Home.Y, Sim.G28Home.Z], InvariantFS);
  end
  else
  begin
    HomeStatusLabel.Caption := 'HOME G28: nao definido';
    HomeStatusLabel.Font.Color := clSuiteFaint;
    HomeStatusLabel.Hint := 'Stored HOME reference point not yet set with G28.1 (defaults to 0,0,0).';
  end;
  if Sim.G92Active then
  begin
    RefIconLabel.Caption := 'Origem: G92 ativa (zero da peca)';
    RefIconLabel.Font.Color := RGBToColor(74, 222, 128);
    RefIconLabel.Hint := 'Workpiece coordinate origin set (G92 active). Machine referenced to work zero.';
  end
  else
  begin
    RefIconLabel.Caption := 'Origem: zero fisico';
    RefIconLabel.Font.Color := clSuiteFaint;
    RefIconLabel.Hint := 'Standard machine physical origin active (no G92 work offset applied).';
  end;
  if Assigned(TemperaturePanel) and TemperaturePanel.Visible then
  begin
    LblSimHotend.Caption := Format('Bico: %.1f °C / %.0f °C',
      [Sim.State.Hotend, Sim.State.HotendTarget], InvariantFS);
    if Sim.State.HotendTarget > 0 then
    begin
      if Abs(Sim.State.Hotend - Sim.State.HotendTarget) <= 2 then
        LblSimHotend.Font.Color := $00008800
      else
        LblSimHotend.Font.Color := $000055CC;
    end
    else
      LblSimHotend.Font.Color := clSuiteText;

    LblSimBed.Caption := Format('Mesa: %.1f °C / %.0f °C',
      [Sim.State.Bed, Sim.State.BedTarget], InvariantFS);
    if Sim.State.BedTarget > 0 then
    begin
      if Abs(Sim.State.Bed - Sim.State.BedTarget) <= 2 then
        LblSimBed.Font.Color := $00008800
      else
        LblSimBed.Font.Color := $000055CC;
    end
    else
      LblSimBed.Font.Color := clSuiteText;

    if (not SpSimHotendTarget.Focused) and (Round(Sim.State.HotendTarget) <> SpSimHotendTarget.Value) then
      SpSimHotendTarget.Value := Round(Sim.State.HotendTarget);
    if (not SpSimBedTarget.Focused) and (Round(Sim.State.BedTarget) <> SpSimBedTarget.Value) then
      SpSimBedTarget.Value := Round(Sim.State.BedTarget);

    if (Sim.State.HotendTarget > 0) or (Sim.State.BedTarget > 0) then
    begin
      if ((Sim.State.HotendTarget = 0) or (Abs(Sim.State.Hotend - Sim.State.HotendTarget) <= 2)) and
         ((Sim.State.BedTarget = 0) or (Abs(Sim.State.Bed - Sim.State.BedTarget) <= 2)) then
      begin
        LblSimTempStatus.Caption := 'Temperatura estabilizada';
        LblSimTempStatus.Font.Color := $00008800;
      end
      else
      begin
        LblSimTempStatus.Caption := 'Aquecendo...';
        LblSimTempStatus.Font.Color := $000055CC;
      end;
    end
    else
    begin
      LblSimTempStatus.Caption := 'Aquecedores desligados';
      LblSimTempStatus.Font.Color := clSuiteMuted;
    end;
  end;
end;
end.
