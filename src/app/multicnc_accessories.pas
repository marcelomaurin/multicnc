unit multicnc_accessories;

{$mode objfpc}{$H+}

interface

uses Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, Spin,
  aijoystick, multicnc_joystick, multicnc_session, multicnc_types, multisuite_controls;

type
  TAccessoriesFrame = class(TPanel)
  private
    FSession: TSimulationSession;
    FJoystick: TAIJoystick;
    FControl: TJoystickControl;
    FTimer: TTimer;
    FFileName, FLastDevice, FLastMessage: string;
    FLoading: Boolean;
    FDeviceIDs: TStringList;
    FEnabled, FInvertX, FInvertY: TCheckBox;
    FDevice, FXAxis, FYAxis, FZPlus, FZMinus: TComboBox;
    FSpindleOn, FSpindleOff: TComboBox;
    FSpindleRPM: TSpinEdit;
    BtnSpindleOn, BtnSpindleOff: TSuiteButton;
    FDeadZone, FFeed: TSpinEdit;
    FStep: TFloatSpinEdit;
    FStatus, FLive, FModel: TLabel;
    procedure Tick(Sender: TObject);
    procedure Apply(Sender: TObject);
    procedure Refresh(Sender: TObject);
    procedure Defaults(Sender: TObject);
    procedure Changed(Sender: TObject);
    procedure RebuildDevices;
    procedure ShowSettings;
    function DoJog(X,Y,Z,Feed: Double): Boolean;
    procedure DoCancel;
    function DoSpindle(AEnabled: Boolean; RPM: Integer): Boolean;
    procedure SpindleClick(Sender: TObject);
    function SettingsFromUI: TJoystickSettings;
  public
    constructor CreateForSession(AOwner: TComponent; ASession: TSimulationSession;
      const AFileName: string);
    destructor Destroy; override;
    procedure Suspend;
  end;

implementation

constructor TAccessoriesFrame.CreateForSession(AOwner: TComponent;
  ASession: TSimulationSession; const AFileName: string);
var Scroll: TScrollBox; G: TGroupBox; L: TLabel; B: TSuiteButton; I: Integer;
  procedure LabelAt(const Text: string; X,Y: Integer);
  begin
    L:=TLabel.Create(Self); L.Parent:=G; L.Caption:=Text; L.SetBounds(X,Y,250,22);
  end;
  function Combo(const AName: string; X,Y,W: Integer): TComboBox;
  begin
    Result:=TComboBox.Create(Self); Result.Parent:=G; Result.Name:=AName;
    Result.Style:=csDropDownList; Result.SetBounds(X,Y,W,30); Result.OnChange:=@Changed;
  end;
  function Check(const AName,Caption: string; X,Y: Integer): TCheckBox;
  begin
    Result:=TCheckBox.Create(Self); Result.Parent:=G; Result.Name:=AName;
    Result.Caption:=Caption; Result.SetBounds(X,Y,230,28); Result.OnChange:=@Changed;
  end;
  procedure Button(const Caption: string; X,Y,W: Integer; Handler: TNotifyEvent);
  begin
    B:=TSuiteButton.Create(Self); B.Parent:=G; B.Caption:=Caption;
    B.SetBounds(X,Y,W,32); B.OnClick:=Handler;
  end;
begin
  inherited Create(AOwner);
  BevelOuter:=bvNone;
  FSession:=ASession; FFileName:=AFileName;
  FDeviceIDs:=TStringList.Create;
  FJoystick:=TAIJoystick.Create(Self);
  FControl:=TJoystickControl.Create;
  FControl.OnJog:=@DoJog; FControl.OnCancel:=@DoCancel;
  FControl.OnSpindle:=@DoSpindle;
  try FControl.Settings:=LoadJoystickSettings(FFileName);
  except on E: Exception do begin
    FControl.Settings:=DefaultJoystickSettings;
    if Assigned(FSession.OnLog) then FSession.OnLog('Joystick: falha ao ler configuracao: '+E.Message);
  end; end;
  Color:=clSuiteSurface;
  Scroll:=TScrollBox.Create(Self); Scroll.Parent:=Self; Scroll.Align:=alClient;
  Scroll.BorderStyle:=bsNone; Scroll.Color:=clSuiteSurface;
  G:=TGroupBox.Create(Self); G.Parent:=Scroll; G.Caption:='Joystick'; G.SetBounds(15,12,735,590);
  FEnabled:=Check('JoystickEnabled','Ativar controle por joystick',15,10);
  LabelAt('Controle',15,50);
  FDevice:=Combo('JoystickDevice',15,74,560);
  Button('Detectar',590,74,130,@Refresh);
  FModel:=TLabel.Create(Self); FModel.Parent:=G; FModel.SetBounds(15,112,780,26);
  FStatus:=TLabel.Create(Self); FStatus.Name:='JoystickStatus'; FStatus.Parent:=G;
  FStatus.SetBounds(15,142,780,26);
  FLive:=TLabel.Create(Self); FLive.Name:='JoystickInput'; FLive.Parent:=G;
  FLive.SetBounds(15,172,780,45); FLive.AutoSize:=False; FLive.WordWrap:=True;
  LabelAt('Eixo X',15,225); LabelAt('Eixo Y',280,225);
  FXAxis:=Combo('JoystickXAxis',15,250,230); FYAxis:=Combo('JoystickYAxis',280,250,230);
  for I:=0 to AIJoystickAxes-1 do
  begin FXAxis.Items.Add('Eixo '+IntToStr(I+1)); FYAxis.Items.Add('Eixo '+IntToStr(I+1)); end;
  FInvertX:=Check('JoystickInvertX','Inverter X',15,285);
  FInvertY:=Check('JoystickInvertY','Inverter Y',280,285);
  LabelAt('Z+ (botao superior)',15,325); LabelAt('Z- (botao inferior)',280,325);
  FZPlus:=Combo('JoystickZPlus',15,350,230); FZMinus:=Combo('JoystickZMinus',280,350,230);
  for I:=1 to AIJoystickControls do
  begin
    FZPlus.Items.Add('Botao '+IntToStr(I));
  end;
  FZPlus.Items[ajA-1]:='1 - A / botao 1'; FZPlus.Items[ajB-1]:='2 - B / botao 2';
  FZPlus.Items[ajX-1]:='3 - X / botao 3'; FZPlus.Items[ajY-1]:='4 - Y / botao 4';
  FZPlus.Items[ajLB-1]:='5 - LB (superior esquerdo)';
  FZPlus.Items[ajRB-1]:='6 - RB (superior direito)';
  FZPlus.Items[ajLT-1]:='33 - LT (gatilho esquerdo)';
  FZPlus.Items[ajRT-1]:='34 - RT (gatilho direito)';
  FZMinus.Items.Assign(FZPlus.Items);
  LabelAt('Zona morta (%)',15,400); LabelAt('Velocidade (mm/min)',250,400); LabelAt('Passo maximo (mm)',485,400);
  FDeadZone:=TSpinEdit.Create(Self); FDeadZone.Parent:=G; FDeadZone.Name:='JoystickDeadZone';
  FDeadZone.SetBounds(15,425,210,30); FDeadZone.MinValue:=5; FDeadZone.MaxValue:=80; FDeadZone.OnChange:=@Changed;
  FFeed:=TSpinEdit.Create(Self); FFeed.Parent:=G; FFeed.Name:='JoystickFeed';
  FFeed.SetBounds(250,425,210,30); FFeed.MinValue:=1; FFeed.MaxValue:=3000; FFeed.OnChange:=@Changed;
  FStep:=TFloatSpinEdit.Create(Self); FStep.Parent:=G; FStep.Name:='JoystickMaxStep';
  FStep.SetBounds(485,425,210,30); FStep.MinValue:=0.01; FStep.MaxValue:=2; FStep.DecimalPlaces:=2;
  FStep.Increment:=0.1; FStep.OnChange:=@Changed;
  Button('Salvar configuracao',15,490,210,@Apply);
  Button('Padrao Xbox 360',245,490,210,@Defaults);
  LabelAt('Analogico esquerdo: X/Y. Solte tudo para liberar apos conectar ou trocar de janela.',15,540);
  L.AutoSize:=False; L.Width:=700; L.Height:=36; L.WordWrap:=True;
  G:=TGroupBox.Create(Self); G.Parent:=Scroll; G.Caption:='Router - spindle'; G.SetBounds(15,625,735,235);
  LabelAt('Botao para ligar spindle',15,15); LabelAt('Botao para desligar spindle',280,15);
  FSpindleOn:=Combo('JoystickSpindleOnButton',15,40,230);
  FSpindleOff:=Combo('JoystickSpindleOffButton',280,40,230);
  FSpindleOn.Items.Add('Sem atalho'); FSpindleOn.Items.AddStrings(FZPlus.Items);
  FSpindleOff.Items.Assign(FSpindleOn.Items);
  LabelAt('Rotacao / valor S (RPM)',15,85);
  FSpindleRPM:=TSpinEdit.Create(Self); FSpindleRPM.Name:='JoystickSpindleRPM'; FSpindleRPM.Parent:=G;
  FSpindleRPM.SetBounds(15,110,210,30); FSpindleRPM.MinValue:=1; FSpindleRPM.MaxValue:=100000;
  FSpindleRPM.OnChange:=@Changed;
  Button('Ligar spindle',280,110,190,@SpindleClick); BtnSpindleOn:=B;
  B.Name:='RouterSpindleOn'; B.Enabled:=False;
  Button('Desligar spindle',490,110,210,@SpindleClick); BtnSpindleOff:=B;
  B.Name:='RouterSpindleOff'; B.Enabled:=False;
  Button('Salvar configuracao',15,160,210,@Apply); B.Name:='SaveSpindleSettings';
  LabelAt('Escolha botoes diferentes dos usados para Z. Salvar conserva os atalhos.',245,160);
  L.AutoSize:=False; L.SetBounds(245,160,455,50); L.WordWrap:=True;
  L:=TLabel.Create(Self); L.Parent:=Scroll; L.SetBounds(30,885,710,75); L.AutoSize:=False; L.WordWrap:=True;
  L.Caption:='Deteccao automatica. A velocidade acompanha o analogico. Z depende dos eixos do equipamento. '+
    'Ao soltar, GRBL cancela o jog; Marlin conclui apenas o passo curto atual. '+
    'Durante programas, dialogos e edicao de campos o joystick fica suspenso.';
  L:=TLabel.Create(Self); L.Parent:=Scroll; L.SetBounds(30,970,710,40); L.AutoSize:=False; L.WordWrap:=True;
  L.Caption:='Configuracao: '+FFileName;
  FJoystick.RefreshDevices; RebuildDevices; ShowSettings;
  FTimer:=TTimer.Create(Self); FTimer.Enabled:=False; FTimer.Interval:=50; FTimer.OnTimer:=@Tick;
  FTimer.Enabled:=True;
end;

destructor TAccessoriesFrame.Destroy;
begin
  if Assigned(FTimer) then FTimer.Enabled:=False;
  Suspend;
  FreeAndNil(FControl); FDeviceIDs.Free;
  inherited Destroy;
end;

procedure TAccessoriesFrame.Suspend;
begin if Assigned(FControl) then FControl.Suspend; end;

function TAccessoriesFrame.DoJog(X,Y,Z,Feed: Double): Boolean;
begin
  Result:=FSession.JoystickJog(X,Y,Z,Feed);
  if not Result and Assigned(FSession.OnLog) then FSession.OnLog('Joystick: '+FSession.LastError);
end;

procedure TAccessoriesFrame.DoCancel;
begin FSession.CancelJoystick; end;

function TAccessoriesFrame.DoSpindle(AEnabled: Boolean; RPM: Integer): Boolean;
var ActionName: string;
begin
  if AEnabled then begin ActionName:='ligar'; Result:=FSession.RouterSpindleOn(RPM); end
  else begin ActionName:='desligar'; Result:=FSession.RouterSpindleOff; end;
  if Assigned(FSession.OnLog) then
  begin
    if Result then FSession.OnLog('Spindle: solicitado '+ActionName+'; aguardando resposta da controladora')
    else FSession.OnLog('Spindle: comando recusado: '+FSession.LastError);
  end;
end;

procedure TAccessoriesFrame.SpindleClick(Sender: TObject);
begin
  Suspend;
  DoSpindle(Sender=BtnSpindleOn,FSpindleRPM.Value);
end;

procedure TAccessoriesFrame.RebuildDevices;
var I: Integer; ID: string; D: TAIJoystickDevices;
begin
  ID:=FControl.Settings.DeviceID;
  FLoading:=True;
  try
    FDevice.Items.Clear; FDeviceIDs.Clear;
    FDevice.Items.Add('Automatico (Xbox 360 / XInput preferencial)'); FDeviceIDs.Add('');
    D:=FJoystick.Devices;
    for I:=0 to High(D) do begin FDevice.Items.Add(D[I].Name); FDeviceIDs.Add(D[I].ID); end;
    if (ID<>'') and (FDeviceIDs.IndexOf(ID)<0) then
    begin FDevice.Items.Add(ID+' (desconectado)'); FDeviceIDs.Add(ID); end;
    FDevice.ItemIndex:=FDeviceIDs.IndexOf(ID);
  finally FLoading:=False; end;
end;

procedure TAccessoriesFrame.ShowSettings;
var S: TJoystickSettings;
begin
  FLoading:=True;
  try
    S:=FControl.Settings; FEnabled.Checked:=S.Enabled;
    FDevice.ItemIndex:=FDeviceIDs.IndexOf(S.DeviceID);
    FXAxis.ItemIndex:=S.XAxis; FYAxis.ItemIndex:=S.YAxis;
    FInvertX.Checked:=S.InvertX; FInvertY.Checked:=S.InvertY;
    FZPlus.ItemIndex:=S.ZPlus-1; FZMinus.ItemIndex:=S.ZMinus-1;
    FSpindleOn.ItemIndex:=S.SpindleOnButton; FSpindleOff.ItemIndex:=S.SpindleOffButton;
    FSpindleRPM.Value:=S.SpindleRPM;
    FDeadZone.Value:=Round(S.DeadZone*100); FFeed.Value:=Round(S.Feed); FStep.Value:=S.MaxStep;
    FJoystick.DeviceID:=S.DeviceID;
  finally FLoading:=False; end;
end;

function TAccessoriesFrame.SettingsFromUI: TJoystickSettings;
begin
  Result:=FControl.Settings; Result.Enabled:=FEnabled.Checked;
  if (FDevice.ItemIndex>=0) and (FDevice.ItemIndex<FDeviceIDs.Count) then
    Result.DeviceID:=FDeviceIDs[FDevice.ItemIndex];
  Result.XAxis:=FXAxis.ItemIndex; Result.YAxis:=FYAxis.ItemIndex;
  Result.InvertX:=FInvertX.Checked; Result.InvertY:=FInvertY.Checked;
  Result.ZPlus:=FZPlus.ItemIndex+1; Result.ZMinus:=FZMinus.ItemIndex+1;
  Result.SpindleOnButton:=FSpindleOn.ItemIndex; Result.SpindleOffButton:=FSpindleOff.ItemIndex;
  Result.SpindleRPM:=FSpindleRPM.Value;
  Result.DeadZone:=FDeadZone.Value/100.0; Result.Feed:=FFeed.Value; Result.MaxStep:=FStep.Value;
  ValidateJoystickSettings(Result);
end;

procedure TAccessoriesFrame.Changed(Sender: TObject);
begin
  if FLoading then Exit;
  FControl.Settings:=SettingsFromUI; FJoystick.DeviceID:=FControl.Settings.DeviceID;
end;

procedure TAccessoriesFrame.Apply(Sender: TObject);
begin
  Changed(Sender);
  if not JoystickSpindleBindingsValid(FControl.Settings) then
  begin
    FStatus.Caption:='Escolha botoes diferentes para Z e para ligar/desligar spindle';
    if Assigned(FSession.OnLog) then FSession.OnLog(FStatus.Caption);
    Exit;
  end;
  try
    SaveJoystickSettings(FFileName,FControl.Settings);
    if Assigned(FSession.OnLog) then FSession.OnLog('Joystick: configuracao salva em '+FFileName);
  except on E: Exception do
    if Assigned(FSession.OnLog) then FSession.OnLog('Joystick: erro ao salvar: '+E.Message);
  end;
end;

procedure TAccessoriesFrame.Defaults(Sender: TObject);
begin FControl.Settings:=DefaultJoystickSettings; RebuildDevices; ShowSettings; end;

procedure TAccessoriesFrame.Refresh(Sender: TObject);
begin Suspend; FJoystick.RefreshDevices; RebuildDevices; end;

procedure TAccessoriesFrame.Tick(Sender: TObject);
var Input: TAIJoystickState; Active,Ready,Available: Boolean; I: Integer; Buttons,MessageText: string;
  Main: TCustomForm;
begin
  try
    FJoystick.Poll; Input:=FJoystick.State;
    Main:=GetParentForm(Self);
    Active:=Assigned(Main) and Main.Visible and Application.Active and
      (Screen.ActiveCustomForm=Main) and (Application.ModalLevel=0);
    if Active and (Main.ActiveControl is TCustomEdit) then
      Active:=TCustomEdit(Main.ActiveControl).ReadOnly;
    if Active and (Main.ActiveControl is TCustomComboBox) then Active:=False;
    Ready:=FSession.JoystickReady; Available:=FSession.JoystickAvailable;
    FControl.Update(Input,Active,Available,Ready,FSession.SupportsAxis(axZ),GetTickCount64,
      FSession.Connected and (FSession.MachineType=mtRouter));
    BtnSpindleOn.Enabled:=FSession.RouterSpindleReady(True);
    BtnSpindleOff.Enabled:=FSession.RouterSpindleReady(False);
    FStatus.Caption:=FControl.Status;
    if Input.Connected then FModel.Caption:=Input.DeviceName else FModel.Caption:='Nenhum joystick conectado';
    Buttons:='';
    for I:=1 to AIJoystickControls do if Input.Controls[I] then Buttons:=Buttons+IntToStr(I)+' ';
    FLive.Caption:=Format('X: %.2f   Y: %.2f   Botoes: %s',
      [Input.Axes[FControl.Settings.XAxis],Input.Axes[FControl.Settings.YAxis],Buttons]);
    MessageText:=Input.DeviceID+' '+FControl.Status;
    if (MessageText<>FLastMessage) and Assigned(FSession.OnLog) then
      FSession.OnLog('Joystick: '+Input.DeviceName+' - '+FControl.Status);
    FLastMessage:=MessageText;
    if Input.DeviceID<>FLastDevice then begin FLastDevice:=Input.DeviceID; RebuildDevices; end;
  except on E: Exception do begin
    Suspend; FStatus.Caption:='Erro no joystick: '+E.Message;
    FTimer.Enabled:=False;
    if Assigned(FSession.OnLog) then FSession.OnLog(FStatus.Caption);
  end; end;
end;

end.
