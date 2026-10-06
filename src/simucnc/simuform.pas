unit simuform;
{$mode objfpc}{$H+}
interface
uses multisuite_numfmt, Math, aitcpserver, Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls, Dialogs,
  aimarlinserialdevice, aimarlinsimulator, aivirtualserialpair, multicnc_print3d_view, simu_table_config_form, Graphics, Spin;
type
  TMainForm = class(TForm)
  private
    DeviceEdit, PeerEdit, BaudEdit, SetupEdit: TEdit;
    ConnectButton, PairButton, ClearButton, ResetButton: TButton;
    ConfigButton: TButton;
    FrameCheck:TCheckBox;
    RealPositionLabel, RefPositionLabel, RefIconLabel, HomeStatusLabel, LaserStatus:TLabel;
    TemperaturePanel: TPanel;
    LblSimHotend, LblSimBed, LblSimTempStatus: TLabel;
    SpSimHotendTarget, SpSimBedTarget: TSpinEdit;
    BtnSetSimHotend, BtnSetSimBed, BtnSimCooldown, BtnSimInstantHeat: TButton;
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
  private
    TCP: TAITCPServer;
    TCPMarlin: TAIMarlinSimulator;
    HostEdit, PortEdit: TEdit;
    TCPButton: TButton;
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
constructor TMainForm.Create(AOwner: TComponent);
var P,BottomBar,RightPanel,PositionPanel:TPanel; L:TLabel; B:TButton; I:Integer;
begin
  inherited CreateNew(AOwner); Caption:='SimuCNC - Simulador de equipamento CNC'; Position:=poScreenCenter; SetBounds(0,0,1100,760); ShowHint:=True;
  P:=TPanel.Create(Self); P.Parent:=Self; P.Align:=alTop; P.Height:=112; P.BevelOuter:=bvNone;
  L:=TLabel.Create(Self); L.Parent:=P; L.Caption:='Equipamento'; L.SetBounds(12,8,110,20);
  MachineCombo:=TComboBox.Create(Self); MachineCombo.Parent:=P; MachineCombo.SetBounds(12,32,115,28);
  MachineCombo.Style:=csDropDownList; MachineCombo.Items.Add('Impressora 3D');
  MachineCombo.Items.Add('CNC Router'); MachineCombo.Items.Add('CNC Laser');
  MachineCombo.ItemIndex:=0; MachineCombo.OnChange:=@MachineChanged;
  MachineCombo.Hint:='Select simulated CNC machine type'; MachineCombo.ShowHint:=True;
  L:=TLabel.Create(Self); L.Parent:=P; L.Caption:='Comunicação'; L.SetBounds(140,8,110,20);
  ModeCombo:=TComboBox.Create(Self); ModeCombo.Parent:=P; ModeCombo.SetBounds(140,32,115,28);
  ModeCombo.Items.Add('Serial'); ModeCombo.Items.Add('TCP'); ModeCombo.ItemIndex:=0;
  ModeCombo.Style:=csDropDownList; ModeCombo.OnChange:=@ModeChanged;
  ModeCombo.Hint:='Select communication interface (Virtual Serial port or TCP network)'; ModeCombo.ShowHint:=True;
  L:=TLabel.Create(Self); L.Parent:=P; L.Caption:='Protocolo'; L.SetBounds(268,8,110,20);
  ProtocolCombo:=TComboBox.Create(Self); ProtocolCombo.Parent:=P; ProtocolCombo.SetBounds(268,32,115,28);
  ProtocolCombo.Style:=csDropDownList; ProtocolCombo.Items.Add('Marlin'); ProtocolCombo.Items.Add('GRBL');
  ProtocolCombo.ItemIndex:=0;
  ProtocolCombo.Hint:='Select firmware dialect (Marlin 3D/CNC or GRBL Router/Laser)'; ProtocolCombo.ShowHint:=True;
  SerialPanel:=TPanel.Create(Self); SerialPanel.Parent:=P;
  SerialPanel.SetBounds(400,0,680,112); SerialPanel.BevelOuter:=bvNone;
  TCPPanel:=TPanel.Create(Self); TCPPanel.Parent:=P;
  TCPPanel.SetBounds(400,0,680,112); TCPPanel.BevelOuter:=bvNone;
  L:=TLabel.Create(Self); L.Parent:=SerialPanel; L.Caption:='Porta serial'; L.SetBounds(12,8,130,22);
  DeviceEdit:=TEdit.Create(Self); DeviceEdit.Parent:=SerialPanel; DeviceEdit.SetBounds(12,32,130,28); DeviceEdit.Text:='COM4';
  DeviceEdit.Hint:='Virtual COM port opened by SimuCNC (e.g. COM4)'; DeviceEdit.ShowHint:=True;
  L:=TLabel.Create(Self); L.Parent:=SerialPanel; L.Caption:='Baud'; L.SetBounds(155,8,70,22);
  BaudEdit:=TEdit.Create(Self); BaudEdit.Parent:=SerialPanel; BaudEdit.SetBounds(155,32,90,28); BaudEdit.Text:='115200';
  BaudEdit.Hint:='Serial communication baud rate'; BaudEdit.ShowHint:=True;
  L:=TLabel.Create(Self); L.Parent:=SerialPanel; L.Caption:='COM do MultiCNC (par virtual)'; L.SetBounds(260,8,240,22);
  PeerEdit:=TEdit.Create(Self); PeerEdit.Parent:=SerialPanel; PeerEdit.SetBounds(260,32,120,28); PeerEdit.Text:='COM3';
  PeerEdit.Hint:='Virtual COM port used by MultiCNC (e.g. COM3)'; PeerEdit.ShowHint:=True;
  ConnectButton:=TButton.Create(Self); ConnectButton.Parent:=SerialPanel; ConnectButton.Caption:='🔌 Start Serial'; ConnectButton.SetBounds(520,28,130,34); ConnectButton.OnClick:=@ConnectClick;
  ConnectButton.Hint:='Open or close virtual serial communication port'; ConnectButton.ShowHint:=True;
  L:=TLabel.Create(Self); L.Parent:=SerialPanel; L.Caption:='setupc.exe'; L.SetBounds(12,78,70,22);
  SetupEdit:=TEdit.Create(Self); SetupEdit.Parent:=SerialPanel; SetupEdit.SetBounds(85,75,430,28); SetupEdit.Text:='C:\Program Files (x86)\com0com\setupc.exe';
  SetupEdit.Hint:='Path to com0com setupc.exe command line tool'; SetupEdit.ShowHint:=True;
  PairButton:=TButton.Create(Self); PairButton.Parent:=SerialPanel; PairButton.Caption:='🔗 Create Pair'; PairButton.SetBounds(520,73,130,34); PairButton.OnClick:=@PairClick;
  PairButton.Hint:='Create virtual COM port pair using com0com'; PairButton.ShowHint:=True;
  L:=TLabel.Create(Self); L.Parent:=TCPPanel; L.Caption:='IP local TCP'; L.SetBounds(12,8,120,20);
  HostEdit:=TEdit.Create(Self); HostEdit.Parent:=TCPPanel; HostEdit.SetBounds(12,32,180,28); HostEdit.Text:='0.0.0.0';
  HostEdit.Hint:='TCP IP address to bind (0.0.0.0 listens on all interfaces)'; HostEdit.ShowHint:=True;
  L:=TLabel.Create(Self); L.Parent:=TCPPanel; L.Caption:='Porta TCP'; L.SetBounds(210,8,80,20);
  PortEdit:=TEdit.Create(Self); PortEdit.Parent:=TCPPanel; PortEdit.SetBounds(210,32,100,28); PortEdit.Text:='9000';
  PortEdit.Hint:='TCP port number to listen on (e.g. 9000)'; PortEdit.ShowHint:=True;
  TCPButton:=TButton.Create(Self); TCPButton.Parent:=TCPPanel; TCPButton.SetBounds(330,28,130,34);
  TCPButton.Caption:='🌐 Start TCP'; TCPButton.OnClick:=@TCPClick;
  TCPButton.Hint:='Start or stop TCP server for incoming G-code connections'; TCPButton.ShowHint:=True;
  L:=TLabel.Create(Self); L.Parent:=TCPPanel; L.Caption:='G-code via TCP; use 0.0.0.0 para escutar em todas as interfaces.'; L.SetBounds(12,78,650,20);
  BottomBar:=TPanel.Create(Self);BottomBar.Parent:=Self;BottomBar.Align:=alBottom;BottomBar.Height:=52;
  ResetButton:=TButton.Create(Self); ResetButton.Parent:=BottomBar; ResetButton.Caption:='🗑 Clear Model'; ResetButton.SetBounds(12,8,114,34); ResetButton.OnClick:=@ResetClick;
  ResetButton.Hint:='Clear 3D workpiece model and toolpath history'; ResetButton.ShowHint:=True;
  ClearButton:=TButton.Create(Self); ClearButton.Parent:=BottomBar; ClearButton.Caption:='🧹 Clear Log'; ClearButton.SetBounds(132,8,110,34); ClearButton.OnClick:=@ClearClick;
  ClearButton.Hint:='Clear received G-code log window'; ClearButton.ShowHint:=True;
  for I:=0 to 2 do begin
    B:=TButton.Create(Self); B.Parent:=BottomBar; B.SetBounds(248+I*106,8,102,34); B.Tag:=I;
    case I of
      0: begin B.Caption:='📐 Perspective'; B.Hint:='Switch 3D camera to perspective isometric view'; end;
      1: begin B.Caption:='🔝 Top View'; B.Hint:='Switch 3D camera to top-down view (XY plane)'; end;
      2: begin B.Caption:='⏹ Front View'; B.Hint:='Switch 3D camera to front view (XZ plane)'; end;
    end;
    B.ShowHint:=True;
    B.OnClick:=@ViewClick;
  end;
  FrameCheck:=TCheckBox.Create(Self);FrameCheck.Parent:=BottomBar;FrameCheck.Caption:='🔲 Build Frame';
  FrameCheck.SetBounds(572,12,110,26);FrameCheck.OnChange:=@FrameChanged;
  FrameCheck.Hint:='Show or hide build volume boundary wireframe box'; FrameCheck.ShowHint:=True;
  ConfigButton:=TButton.Create(Self);ConfigButton.Parent:=BottomBar;ConfigButton.Caption:='⚙ Table Size';
  ConfigButton.SetBounds(688,8,124,34);ConfigButton.OnClick:=@ConfigClick;
  ConfigButton.Hint:='Configure machine table dimensions and build limits (X, Y, Z)'; ConfigButton.ShowHint:=True;
  LaserStatus:=TLabel.Create(Self); LaserStatus.Parent:=BottomBar;
  LaserStatus.SetBounds(822,16,160,24); LaserStatus.Font.Name:='Segoe UI'; LaserStatus.Font.Style:=[fsBold];
  LaserStatus.Caption:='⚡ Laser: 0'; LaserStatus.Hint:='Current simulated laser/spindle power (S0..S1000)';
  LaserStatus.ShowHint:=True;
  PositionPanel:=TPanel.Create(Self);PositionPanel.Parent:=Self;PositionPanel.Align:=alTop;
  PositionPanel.Top:=112;PositionPanel.Height:=72;PositionPanel.BevelOuter:=bvNone;
  PositionPanel.Color:=$00F7F7F7;
  RealPositionLabel:=TLabel.Create(Self);RealPositionLabel.Parent:=PositionPanel;RealPositionLabel.SetBounds(16,10,720,24);
  RealPositionLabel.Font.Size:=13;RealPositionLabel.Font.Name:='Consolas';RealPositionLabel.Font.Style:=[fsBold];
  RealPositionLabel.Caption:='⚙ Real (MPos): X:    0.000   Y:    0.000   Z:    0.000 mm';
  RealPositionLabel.Hint:='Real Machine Position (MPos) - Absolute physical coordinates of the machine axes';
  RealPositionLabel.ShowHint:=True;
  RefPositionLabel:=TLabel.Create(Self);RefPositionLabel.Parent:=PositionPanel;RefPositionLabel.SetBounds(16,38,720,24);
  RefPositionLabel.Font.Size:=13;RefPositionLabel.Font.Name:='Consolas';RefPositionLabel.Font.Style:=[fsBold];
  RefPositionLabel.Caption:='🎯 Ref  (WPos): X:    0.000   Y:    0.000   Z:    0.000 mm';
  RefPositionLabel.Hint:='Reference Work Position (WPos) - Workpiece coordinates offset by G92 origin';
  RefPositionLabel.ShowHint:=True;
  HomeStatusLabel:=TLabel.Create(Self);HomeStatusLabel.Parent:=PositionPanel;HomeStatusLabel.SetBounds(740,10,240,24);
  HomeStatusLabel.Font.Size:=10;HomeStatusLabel.Font.Name:='Segoe UI';HomeStatusLabel.Font.Style:=[fsBold];
  HomeStatusLabel.Caption:='🏠 [G28: NOT SET]';HomeStatusLabel.Font.Color:=clGrayText;
  HomeStatusLabel.Hint:='Application stored HOME reference position (G28.1).';
  HomeStatusLabel.ShowHint:=True;
  RefIconLabel:=TLabel.Create(Self);RefIconLabel.Parent:=PositionPanel;RefIconLabel.SetBounds(740,38,240,24);
  RefIconLabel.Font.Size:=10;RefIconLabel.Font.Name:='Segoe UI';RefIconLabel.Font.Style:=[fsBold];
  RefIconLabel.Caption:='⌖ [PHYSICAL ZERO]';RefIconLabel.Font.Color:=clGrayText;
  RefIconLabel.Hint:='Standard machine physical origin active (no G92 work offset applied).';
  RefIconLabel.ShowHint:=True;
  TemperaturePanel:=TPanel.Create(Self);TemperaturePanel.Parent:=Self;TemperaturePanel.Align:=alTop;
  TemperaturePanel.Top:=185;TemperaturePanel.Height:=46;TemperaturePanel.BevelOuter:=bvNone;
  TemperaturePanel.Color:=$00F2F4F8;TemperaturePanel.ShowHint:=True;

  LblSimHotend:=TLabel.Create(Self);LblSimHotend.Parent:=TemperaturePanel;
  LblSimHotend.SetBounds(16,12,175,22);LblSimHotend.Font.Size:=10;
  LblSimHotend.Font.Name:='Segoe UI';LblSimHotend.Font.Style:=[fsBold];
  LblSimHotend.Caption:='♨ Bico: 25.0 °C / 0 °C';
  LblSimHotend.Hint:='Temperatura atual e configurada do bico extrusor (ºC)';

  SpSimHotendTarget:=TSpinEdit.Create(Self);SpSimHotendTarget.Parent:=TemperaturePanel;
  SpSimHotendTarget.SetBounds(195,9,65,26);SpSimHotendTarget.MinValue:=0;
  SpSimHotendTarget.MaxValue:=320;SpSimHotendTarget.Value:=200;
  SpSimHotendTarget.Hint:='Temperatura alvo para aquecer o bico (M104)';

  BtnSetSimHotend:=TButton.Create(Self);BtnSetSimHotend.Parent:=TemperaturePanel;
  BtnSetSimHotend.SetBounds(265,9,60,26);BtnSetSimHotend.Caption:='Definir';
  BtnSetSimHotend.Hint:='Aplica temperatura alvo do bico';
  BtnSetSimHotend.OnClick:=@SetSimHotendClick;

  LblSimBed:=TLabel.Create(Self);LblSimBed.Parent:=TemperaturePanel;
  LblSimBed.SetBounds(345,12,175,22);LblSimBed.Font.Size:=10;
  LblSimBed.Font.Name:='Segoe UI';LblSimBed.Font.Style:=[fsBold];
  LblSimBed.Caption:='🛏 Cama: 25.0 °C / 0 °C';
  LblSimBed.Hint:='Temperatura atual e configurada da mesa/cama aquecida (ºC)';

  SpSimBedTarget:=TSpinEdit.Create(Self);SpSimBedTarget.Parent:=TemperaturePanel;
  SpSimBedTarget.SetBounds(525,9,65,26);SpSimBedTarget.MinValue:=0;
  SpSimBedTarget.MaxValue:=150;SpSimBedTarget.Value:=60;
  SpSimBedTarget.Hint:='Temperatura alvo para aquecer a cama/mesa (M140)';

  BtnSetSimBed:=TButton.Create(Self);BtnSetSimBed.Parent:=TemperaturePanel;
  BtnSetSimBed.SetBounds(595,9,60,26);BtnSetSimBed.Caption:='Definir';
  BtnSetSimBed.Hint:='Aplica temperatura alvo da cama/mesa';
  BtnSetSimBed.OnClick:=@SetSimBedClick;

  BtnSimCooldown:=TButton.Create(Self);BtnSimCooldown.Parent:=TemperaturePanel;
  BtnSimCooldown.SetBounds(670,9,85,26);BtnSimCooldown.Caption:='❄ Desligar';
  BtnSimCooldown.Hint:='Desliga bico e cama (define temperatura alvo para 0 ºC)';
  BtnSimCooldown.OnClick:=@SimCooldownClick;

  BtnSimInstantHeat:=TButton.Create(Self);BtnSimInstantHeat.Parent:=TemperaturePanel;
  BtnSimInstantHeat.SetBounds(760,9,95,26);BtnSimInstantHeat.Caption:='⚡ Aquecer Já';
  BtnSimInstantHeat.Hint:='Atinge a temperatura alvo instantaneamente para teste rápido';
  BtnSimInstantHeat.OnClick:=@SimInstantHeatClick;

  LblSimTempStatus:=TLabel.Create(Self);LblSimTempStatus.Parent:=TemperaturePanel;
  LblSimTempStatus.SetBounds(870,12,210,22);LblSimTempStatus.Font.Size:=9;
  LblSimTempStatus.Font.Name:='Segoe UI';LblSimTempStatus.Font.Style:=[fsBold];
  LblSimTempStatus.Font.Color:=clGrayText;
  LblSimTempStatus.Caption:='❄ [AQUECEDORES DESLIGADOS]';
  LblSimTempStatus.Hint:='Status do sistema térmico simulado';
  RightPanel:=TPanel.Create(Self);RightPanel.Parent:=Self;RightPanel.Align:=alRight;RightPanel.Width:=300;
  L:=TLabel.Create(Self);L.Parent:=RightPanel;L.Align:=alTop;L.Caption:='G-CODE RECEBIDO (última linha destacada)';
  LogMemo:=TMemo.Create(Self); LogMemo.Parent:=RightPanel;LogMemo.Align:=alBottom;LogMemo.Height:=180;
  LogMemo.ReadOnly:=True;LogMemo.ScrollBars:=ssAutoBoth;
  LogMemo.Hint:='Communication diagnostic and activity log'; LogMemo.ShowHint:=True;
  CodeList:=TListBox.Create(Self);CodeList.Name:='ReceivedGCode';CodeList.Parent:=RightPanel;CodeList.Align:=alClient;
  CodeList.Font.Name:='Consolas';CodeList.Font.Size:=10;
  CodeList.Hint:='Received G-code command stream (last executed line highlighted)'; CodeList.ShowHint:=True;
  View:=TPrint3DView.Create(Self);View.Name:='PrinterView'; View.Parent:=Self; View.Align:=alClient;
  Status:=TStatusBar.Create(Self); Status.Parent:=Self; Status.Align:=alBottom; Status.SimplePanel:=True; Status.SimpleText:='Porta virtual desligada';
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
  if FindCmdLineSwitch('grbl') then ProtocolCombo.ItemIndex:=ProtocolCombo.Items.IndexOf('GRBL');
  if FindCmdLineSwitch('tcp') then begin ModeCombo.ItemIndex:=1; ModeChanged(Self); TCPClick(Self); end;
end;
destructor TMainForm.Destroy; begin Timer.Enabled:=False; TCP.OnDisconnect:=nil; TCP.Stop; Device.Close; inherited Destroy; end;
procedure TMainForm.ViewClick(Sender:TObject);
begin case TButton(Sender).Tag of 0:View.ResetView;1:View.TopView;2:View.FrontView;end;end;
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
  if (MachineCombo.ItemIndex=2) and (Power>0) then View.AddLaserMotion(A,B,Power)
  else View.AddMotion(Sender,A,B,Material);
end;
procedure TMainForm.PairClick(Sender:TObject); begin
  PairManager.SetupExecutable:=Trim(SetupEdit.Text);
  if PairManager.CreatePair(Trim(DeviceEdit.Text),Trim(PeerEdit.Text)) then Log('Par virtual criado: '+DeviceEdit.Text+' <-> '+PeerEdit.Text)
  else Log('Falha ao criar par: '+PairManager.LastError+' '+PairManager.LastOutput);
end;

procedure TMainForm.ConnectClick(Sender:TObject); begin
  if TCP.Active then begin Log('Pare o servidor TCP antes de iniciar a serial.'); Exit; end;
  if Device.Serial.Active then begin Device.Close; ConnectButton.Caption:='🔌 Start Serial'; Status.SimpleText:='Porta virtual desligada'; Log('Porta fechada.'); end
  else if Device.Open(Trim(DeviceEdit.Text),StrToIntDef(BaudEdit.Text,115200)) then begin ConnectButton.Caption:='⏹ Stop Serial'; Status.SimpleText:='Marlin virtual ativo em '+DeviceEdit.Text; Log('Marlin virtual pronto.'); end
  else Log('Falha ao abrir porta: '+Device.LastError);
  ModeCombo.Enabled:=not Device.Serial.Active;
  DeviceEdit.Enabled:=not Device.Serial.Active; BaudEdit.Enabled:=not Device.Serial.Active;
  PairButton.Enabled:=not Device.Serial.Active;
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
    View.LaserMode:=MachineCombo.ItemIndex=2; View.Invalidate;
    if Assigned(TCPMarlin) then TCPMarlin.AllowZ:=MachineCombo.ItemIndex<>2;
    if Assigned(Device) then Device.Simulator.AllowZ:=MachineCombo.ItemIndex<>2;
  end;
  Log('Equipamento selecionado: '+MachineCombo.Text+' / protocolo '+ProtocolCombo.Text);
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
  if TCP.Active then begin TCPButton.Caption:='⏹ Stop TCP'; TCPButton.Hint:='Stop TCP server and disconnect clients'; Status.SimpleText:='TCP server listening - waiting for controller'; end
  else begin TCPButton.Caption:='🌐 Start TCP'; TCPButton.Hint:='Start TCP server for network G-code connections'; Status.SimpleText:='TCP server stopped'; end;
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
end;
procedure TMainForm.TCPDisconnected(Sender:TObject);
begin
  LaserPower:=0; TCPMarlin.Pause;
  Log('Controladora TCP desconectada'); Status.SimpleText:='TCP aguardando controladora';
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
  View.SetPosition(RealPos);
  RealPositionLabel.Caption := Format('⚙ Real (MPos): X: %8.3f   Y: %8.3f   Z: %8.3f mm',
    [RealPos.X, RealPos.Y, RealPos.Z], InvariantFS);
  RefPositionLabel.Caption := Format('🎯 Ref  (WPos): X: %8.3f   Y: %8.3f   Z: %8.3f mm',
    [RefPos.X, RefPos.Y, RefPos.Z], InvariantFS);
  if Sim.G28HomeSet then
  begin
    HomeStatusLabel.Caption := Format('🏠 [G28: %.1f, %.1f, %.1f]',
      [Sim.G28Home.X, Sim.G28Home.Y, Sim.G28Home.Z], InvariantFS);
    HomeStatusLabel.Font.Color := $00AA5500;
    HomeStatusLabel.Hint := Format('Stored HOME reference point (G28.1): X=%.3f, Y=%.3f, Z=%.3f',
      [Sim.G28Home.X, Sim.G28Home.Y, Sim.G28Home.Z], InvariantFS);
  end
  else
  begin
    HomeStatusLabel.Caption := '🏠 [G28: NOT SET]';
    HomeStatusLabel.Font.Color := clGrayText;
    HomeStatusLabel.Hint := 'Stored HOME reference point not yet set with G28.1 (defaults to 0,0,0).';
  end;
  if Sim.G92Active then
  begin
    RefIconLabel.Caption := '🎯 [G92 REF ACTIVE]';
    RefIconLabel.Font.Color := $00008800;
    RefIconLabel.Hint := 'Workpiece coordinate origin set (G92 active). Machine referenced to work zero.';
  end
  else
  begin
    RefIconLabel.Caption := '⌖ [PHYSICAL ZERO]';
    RefIconLabel.Font.Color := clGrayText;
    RefIconLabel.Hint := 'Standard machine physical origin active (no G92 work offset applied).';
  end;
  if Assigned(TemperaturePanel) and TemperaturePanel.Visible then
  begin
    LblSimHotend.Caption := Format('♨ Bico: %.1f °C / %.0f °C',
      [Sim.State.Hotend, Sim.State.HotendTarget], InvariantFS);
    if Sim.State.HotendTarget > 0 then
    begin
      if Abs(Sim.State.Hotend - Sim.State.HotendTarget) <= 2 then
        LblSimHotend.Font.Color := $00008800
      else
        LblSimHotend.Font.Color := $000055CC;
    end
    else
      LblSimHotend.Font.Color := clWindowText;

    LblSimBed.Caption := Format('🛏 Cama: %.1f °C / %.0f °C',
      [Sim.State.Bed, Sim.State.BedTarget], InvariantFS);
    if Sim.State.BedTarget > 0 then
    begin
      if Abs(Sim.State.Bed - Sim.State.BedTarget) <= 2 then
        LblSimBed.Font.Color := $00008800
      else
        LblSimBed.Font.Color := $000055CC;
    end
    else
      LblSimBed.Font.Color := clWindowText;

    if (not SpSimHotendTarget.Focused) and (Round(Sim.State.HotendTarget) <> SpSimHotendTarget.Value) then
      SpSimHotendTarget.Value := Round(Sim.State.HotendTarget);
    if (not SpSimBedTarget.Focused) and (Round(Sim.State.BedTarget) <> SpSimBedTarget.Value) then
      SpSimBedTarget.Value := Round(Sim.State.BedTarget);

    if (Sim.State.HotendTarget > 0) or (Sim.State.BedTarget > 0) then
    begin
      if ((Sim.State.HotendTarget = 0) or (Abs(Sim.State.Hotend - Sim.State.HotendTarget) <= 2)) and
         ((Sim.State.BedTarget = 0) or (Abs(Sim.State.Bed - Sim.State.BedTarget) <= 2)) then
      begin
        LblSimTempStatus.Caption := '✅ [TEMPERATURA ESTABILIZADA]';
        LblSimTempStatus.Font.Color := $00008800;
      end
      else
      begin
        LblSimTempStatus.Caption := '♨ [AQUECENDO...]';
        LblSimTempStatus.Font.Color := $000055CC;
      end;
    end
    else
    begin
      LblSimTempStatus.Caption := '❄ [AQUECEDORES DESLIGADOS]';
      LblSimTempStatus.Font.Color := clGrayText;
    end;
  end;
end;
end.
