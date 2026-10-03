unit simuform;
{$mode objfpc}{$H+}
interface
uses multisuite_numfmt, Math, aitcpserver, Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls, Dialogs,
  aimarlinserialdevice, aimarlinsimulator, aivirtualserialpair, multicnc_print3d_view;
type
  TMainForm = class(TForm)
  private
    DeviceEdit, PeerEdit, BaudEdit, SetupEdit: TEdit;
    ConnectButton, PairButton, ClearButton, ResetButton: TButton;
    ConfigButton: TButton;
    FrameCheck:TCheckBox;
    PositionLabel, LaserStatus:TLabel;
    CodeList:TListBox;
    CommandBuffer:string;
    LaserPower:Double;
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
  inherited CreateNew(AOwner); Caption:='SimuCNC - Simulador de equipamento CNC'; Position:=poScreenCenter; SetBounds(0,0,1100,760);
  P:=TPanel.Create(Self); P.Parent:=Self; P.Align:=alTop; P.Height:=112; P.BevelOuter:=bvNone;
  L:=TLabel.Create(Self); L.Parent:=P; L.Caption:='Equipamento'; L.SetBounds(12,8,110,20);
  MachineCombo:=TComboBox.Create(Self); MachineCombo.Parent:=P; MachineCombo.SetBounds(12,32,115,28);
  MachineCombo.Style:=csDropDownList; MachineCombo.Items.Add('Impressora 3D');
  MachineCombo.Items.Add('CNC Router'); MachineCombo.Items.Add('CNC Laser');
  MachineCombo.ItemIndex:=0; MachineCombo.OnChange:=@MachineChanged;
  L:=TLabel.Create(Self); L.Parent:=P; L.Caption:='Comunicação'; L.SetBounds(140,8,110,20);
  ModeCombo:=TComboBox.Create(Self); ModeCombo.Parent:=P; ModeCombo.SetBounds(140,32,115,28);
  ModeCombo.Items.Add('Serial'); ModeCombo.Items.Add('TCP'); ModeCombo.ItemIndex:=0;
  ModeCombo.Style:=csDropDownList; ModeCombo.OnChange:=@ModeChanged;
  L:=TLabel.Create(Self); L.Parent:=P; L.Caption:='Protocolo'; L.SetBounds(268,8,110,20);
  ProtocolCombo:=TComboBox.Create(Self); ProtocolCombo.Parent:=P; ProtocolCombo.SetBounds(268,32,115,28);
  ProtocolCombo.Style:=csDropDownList; ProtocolCombo.Items.Add('Marlin'); ProtocolCombo.Items.Add('GRBL');
  ProtocolCombo.ItemIndex:=0;
  SerialPanel:=TPanel.Create(Self); SerialPanel.Parent:=P;
  SerialPanel.SetBounds(400,0,680,112); SerialPanel.BevelOuter:=bvNone;
  TCPPanel:=TPanel.Create(Self); TCPPanel.Parent:=P;
  TCPPanel.SetBounds(400,0,680,112); TCPPanel.BevelOuter:=bvNone;
  L:=TLabel.Create(Self); L.Parent:=SerialPanel; L.Caption:='Porta serial'; L.SetBounds(12,8,130,22);
  DeviceEdit:=TEdit.Create(Self); DeviceEdit.Parent:=SerialPanel; DeviceEdit.SetBounds(12,32,130,28); DeviceEdit.Text:='COM4';
  L:=TLabel.Create(Self); L.Parent:=SerialPanel; L.Caption:='Baud'; L.SetBounds(155,8,70,22);
  BaudEdit:=TEdit.Create(Self); BaudEdit.Parent:=SerialPanel; BaudEdit.SetBounds(155,32,90,28); BaudEdit.Text:='115200';
  L:=TLabel.Create(Self); L.Parent:=SerialPanel; L.Caption:='COM do MultiCNC (par virtual)'; L.SetBounds(260,8,240,22);
  PeerEdit:=TEdit.Create(Self); PeerEdit.Parent:=SerialPanel; PeerEdit.SetBounds(260,32,120,28); PeerEdit.Text:='COM3';
  ConnectButton:=TButton.Create(Self); ConnectButton.Parent:=SerialPanel; ConnectButton.Caption:='Iniciar serial'; ConnectButton.SetBounds(520,28,130,34); ConnectButton.OnClick:=@ConnectClick;
  L:=TLabel.Create(Self); L.Parent:=SerialPanel; L.Caption:='setupc.exe'; L.SetBounds(12,78,70,22);
  SetupEdit:=TEdit.Create(Self); SetupEdit.Parent:=SerialPanel; SetupEdit.SetBounds(85,75,430,28); SetupEdit.Text:='C:\Program Files (x86)\com0com\setupc.exe';
  PairButton:=TButton.Create(Self); PairButton.Parent:=SerialPanel; PairButton.Caption:='Criar par virtual'; PairButton.SetBounds(520,73,130,34); PairButton.OnClick:=@PairClick;
  L:=TLabel.Create(Self); L.Parent:=TCPPanel; L.Caption:='IP local TCP'; L.SetBounds(12,8,120,20);
  HostEdit:=TEdit.Create(Self); HostEdit.Parent:=TCPPanel; HostEdit.SetBounds(12,32,180,28); HostEdit.Text:='0.0.0.0';
  L:=TLabel.Create(Self); L.Parent:=TCPPanel; L.Caption:='Porta TCP'; L.SetBounds(210,8,80,20);
  PortEdit:=TEdit.Create(Self); PortEdit.Parent:=TCPPanel; PortEdit.SetBounds(210,32,100,28); PortEdit.Text:='9000';
  TCPButton:=TButton.Create(Self); TCPButton.Parent:=TCPPanel; TCPButton.SetBounds(330,28,130,34);
  TCPButton.Caption:='Iniciar TCP'; TCPButton.OnClick:=@TCPClick;
  L:=TLabel.Create(Self); L.Parent:=TCPPanel; L.Caption:='G-code via TCP; use 0.0.0.0 para escutar em todas as interfaces.'; L.SetBounds(12,78,650,20);
  BottomBar:=TPanel.Create(Self);BottomBar.Parent:=Self;BottomBar.Align:=alBottom;BottomBar.Height:=52;
  ResetButton:=TButton.Create(Self); ResetButton.Parent:=BottomBar; ResetButton.Caption:='Limpar peça'; ResetButton.SetBounds(12,8,110,34); ResetButton.OnClick:=@ResetClick;
  ClearButton:=TButton.Create(Self); ClearButton.Parent:=BottomBar; ClearButton.Caption:='Limpar log'; ClearButton.SetBounds(130,8,110,34); ClearButton.OnClick:=@ClearClick;
  for I:=0 to 2 do begin
    B:=TButton.Create(Self); B.Parent:=BottomBar; B.SetBounds(252+I*100,8,94,34); B.Tag:=I;
    case I of 0:B.Caption:='Perspectiva';1:B.Caption:='Superior';2:B.Caption:='Frontal';end;
    B.OnClick:=@ViewClick;
  end;
  FrameCheck:=TCheckBox.Create(Self);FrameCheck.Parent:=BottomBar;FrameCheck.Caption:='Estrutura';
  FrameCheck.SetBounds(564,12,100,26);FrameCheck.OnChange:=@FrameChanged;
  ConfigButton:=TButton.Create(Self);ConfigButton.Parent:=BottomBar;ConfigButton.Caption:='Configurar mesa';
  ConfigButton.SetBounds(680,8,130,34);ConfigButton.OnClick:=@ConfigClick;
  PositionPanel:=TPanel.Create(Self);PositionPanel.Parent:=Self;PositionPanel.Align:=alTop;
  PositionPanel.Top:=112;PositionPanel.Height:=54;PositionPanel.BevelOuter:=bvNone;
  PositionLabel:=TLabel.Create(Self);PositionLabel.Parent:=PositionPanel;PositionLabel.SetBounds(16,12,950,32);
  PositionLabel.Font.Size:=18;PositionLabel.Font.Name:='Consolas';PositionLabel.Caption:='X: 0.000   Y: 0.000   Z: 0.000 mm';
  RightPanel:=TPanel.Create(Self);RightPanel.Parent:=Self;RightPanel.Align:=alRight;RightPanel.Width:=300;
  L:=TLabel.Create(Self);L.Parent:=RightPanel;L.Align:=alTop;L.Caption:='G-CODE RECEBIDO (última linha destacada)';
  LogMemo:=TMemo.Create(Self); LogMemo.Parent:=RightPanel;LogMemo.Align:=alBottom;LogMemo.Height:=180;
  LogMemo.ReadOnly:=True;LogMemo.ScrollBars:=ssAutoBoth;
  CodeList:=TListBox.Create(Self);CodeList.Name:='ReceivedGCode';CodeList.Parent:=RightPanel;CodeList.Align:=alClient;
  CodeList.Font.Name:='Consolas';CodeList.Font.Size:=10;
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
var SX,SY,SZ:string; X,Y,Z:Double; FS:TFormatSettings;
begin
  SX:=FloatToStr(View.VolumeX,InvariantFS); SY:=FloatToStr(View.VolumeY,InvariantFS); SZ:=FloatToStr(View.VolumeZ,InvariantFS);
  if not InputQuery('Dimensões da mesa', 'Tamanho X (mm):', SX) then Exit;
  if not InputQuery('Dimensões da mesa', 'Tamanho Y (mm):', SY) then Exit;
  if not InputQuery('Dimensões da mesa', 'Altura Z (mm):', SZ) then Exit;
  FS:=DefaultFormatSettings; FS.DecimalSeparator:='.';
  SX:=StringReplace(SX,',','.',[rfReplaceAll]);SY:=StringReplace(SY,',','.',[rfReplaceAll]);SZ:=StringReplace(SZ,',','.',[rfReplaceAll]);
  if not TryStrToFloat(SX,X,FS) or not TryStrToFloat(SY,Y,FS) or not TryStrToFloat(SZ,Z,FS) or
     (X<10) or (Y<10) or (Z<10) or (X>2000) or (Y>2000) or (Z>2000) then begin
    MessageDlg('Dimensões inválidas','Informe valores entre 10 e 2000 mm.',mtError,[mbOK],0); Exit;
  end;
  View.SetBuildVolume(X,Y,Z); TCPMarlin.SetBuildVolume(X,Y,Z); Device.Simulator.SetBuildVolume(X,Y,Z);
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
  if Device.Serial.Active then begin Device.Close; ConnectButton.Caption:='Iniciar porta'; Status.SimpleText:='Porta virtual desligada'; Log('Porta fechada.'); end
  else if Device.Open(Trim(DeviceEdit.Text),StrToIntDef(BaudEdit.Text,115200)) then begin ConnectButton.Caption:='Parar porta'; Status.SimpleText:='Marlin virtual ativo em '+DeviceEdit.Text; Log('Marlin virtual pronto.'); end
  else Log('Falha ao abrir porta: '+Device.LastError);
  ModeCombo.Enabled:=not Device.Serial.Active;
  DeviceEdit.Enabled:=not Device.Serial.Active; BaudEdit.Enabled:=not Device.Serial.Active;
  PairButton.Enabled:=not Device.Serial.Active;
end;
procedure TMainForm.ResetClick(Sender:TObject); begin LaserPower:=0; View.ClearPrint; if TCP.Active then TCPMarlin.Reset else Device.Simulator.Reset; Log('Simulador reiniciado.'); end;
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
  if TCP.Active then begin TCPButton.Caption:='Parar TCP'; Status.SimpleText:='TCP aguardando controladora'; end
  else begin TCPButton.Caption:='Iniciar TCP'; Status.SimpleText:='TCP desligado'; end;
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
var NowTick: QWord; Dt: Double;
begin
  NowTick:=GetTickCount64; Dt:=(NowTick-LastTick)/1000; LastTick:=NowTick;
  if Dt>0.5 then Dt:=0.5;
  if TCP.Active then begin TCP.Poll; if TCP.Connected then TCPMarlin.Advance(Dt); end
  else Device.Poll(Dt);
  if TCP.Active then View.SetPosition(TCPMarlin.State.Position)
  else View.SetPosition(Device.Simulator.State.Position);
  with View.CurrentPosition do PositionLabel.Caption:=Format('X: %.3f   Y: %.3f   Z: %.3f mm',[X,Y,Z],InvariantFS);
end;
end.
