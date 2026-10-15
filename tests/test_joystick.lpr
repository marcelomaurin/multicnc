program test_joystick;
{$mode objfpc}{$H+}{$interfaces corba}
uses Classes, SysUtils, Math, aijoystick, multicnc_joystick, multicnc_session,
  multicnc_types, multicnc_interfaces;

type
  TFakeJoystick = class(TAIJoystick)
    public
    Online1, Online2: Boolean;
    protected
    function ReadDevice(const ID: string; out S: TAIJoystickState): Boolean; override;
    procedure ScanDevices; override;
  end;
  TPort = class(TInterfacedObject,IMultiCNCTransport)
    Opened: Boolean; Sent: TStringList; OnData: TTransportDataEvent;
    constructor Create;
    destructor Destroy; override;
    function Connect: Boolean;
    procedure Disconnect;
    function IsConnected: Boolean;
    function Send(const Data: string): Boolean;
    procedure Poll;
    procedure SetOnData(Event: TTransportDataEvent);
    procedure SetOnState(Event: TTransportStateEvent);
    function GetName: string;
    procedure Reply(const Data: string);
  end;
  TSink = class
    Jogs,Cancels: Integer;
    X,Y,Z,Feed: Double;
    Reject: Boolean;
    function Jog(AX,AY,AZ,AFeed: Double): Boolean;
    procedure Cancel;
  end;

function TFakeJoystick.ReadDevice(const ID: string; out S: TAIJoystickState): Boolean;
begin
  S:=Default(TAIJoystickState);
  Result:=((ID='one') and Online1) or ((ID='two') and Online2);
  if Result then begin S.Connected:=True; S.DeviceID:=ID; S.DeviceName:='Fake '+ID; end;
end;
procedure TFakeJoystick.ScanDevices;
begin
  SetLength(FDevices,2); FDevices[0].ID:='one'; FDevices[1].ID:='two';
end;
constructor TPort.Create;begin inherited Create; Sent:=TStringList.Create;end;
destructor TPort.Destroy;begin Sent.Free; inherited Destroy;end;
function TPort.Connect:Boolean;begin Opened:=True; Result:=True;end;
procedure TPort.Disconnect;begin Opened:=False;end;
function TPort.IsConnected:Boolean;begin Result:=Opened;end;
function TPort.Send(const Data:string):Boolean;begin Result:=Opened; Sent.Add(Data);end;
procedure TPort.Poll;begin end;
procedure TPort.SetOnData(Event:TTransportDataEvent);begin OnData:=Event;end;
procedure TPort.SetOnState(Event:TTransportStateEvent);begin end;
function TPort.GetName:string;begin Result:='fake, no hardware';end;
procedure TPort.Reply(const Data:string);begin if Assigned(OnData) then OnData(Data);end;
function TSink.Jog(AX,AY,AZ,AFeed:Double):Boolean;
begin Inc(Jogs); X:=AX; Y:=AY; Z:=AZ; Feed:=AFeed; Result:=not Reject;end;
procedure TSink.Cancel;begin Inc(Cancels);end;

var Checks,N: Integer; Driver: TFakeJoystick; Gate:TJoystickControl; Sink:TSink;
  Input:TAIJoystickState; Settings,Loaded:TJoystickSettings; FN:string;
  S:TSimulationSession; Port:TPort; L:TStringList;
procedure Check(OK:Boolean;const Text:string);
begin Inc(Checks); if not OK then raise Exception.Create(Text);end;
procedure Update(Active,Available,Ready,Z:Boolean; NowMS:QWord);
begin Gate.Update(Input,Active,Available,Ready,Z,NowMS);end;
procedure Neutral(NowMS:QWord);
begin Input.Axes[0]:=0; Input.Axes[1]:=0; FillChar(Input.Controls,SizeOf(Input.Controls),0); Update(True,True,True,True,NowMS);end;
procedure Connect(Kind:TMachineType; Protocol:TProtocolKind);
begin
  S.Disconnect; Port:=TPort.Create;
  Check(S.ConnectTransport(Kind,Protocol,Port,Port),'Fake machine connected');
  if Protocol=pkMarlin then Sleep(2600);
end;
begin
  Driver:=TFakeJoystick.Create(nil); Gate:=TJoystickControl.Create; Sink:=TSink.Create;
  S:=TSimulationSession.Create; L:=TStringList.Create; FN:=GetTempFileName(GetTempDir,'joy');
  try
    try
      Check(TAIJoystick.NormalizeAxis(0,0,65535)=-1,'Minimum normalization');
      Check(TAIJoystick.NormalizeAxis(65535,0,65535)=1,'Maximum normalization');
      Check(Abs(TAIJoystick.NormalizeAxis(32767,0,65535))<0.001,'Center normalization');
      Check(TAIJoystick.NormalizeAxis(4,10,10)=0,'Missing generic axis stays neutral');
      Driver.Online2:=True; Check(Driver.Poll and (Driver.State.DeviceID='two'),'Auto finds connected device');
      Driver.Online1:=True; Check(Driver.Poll and (Driver.State.DeviceID='two'),'New controller cannot steal active device');
      Driver.Online2:=False; Check(Driver.Poll and (Driver.State.DeviceID='one'),'Hot-unplug selects replacement');
      Driver.DeviceID:='two'; Check(not Driver.Poll and not Driver.State.Connected,'Manual selection never falls back silently');
      Driver.Online2:=True; Check(Driver.Poll,'Manual controller reconnects');
      Driver.Online2:=False; Driver.Online1:=False; Driver.DeviceID:=''; Check(not Driver.Poll,'All disconnected clears state');
      Settings:=DefaultJoystickSettings;
      Check((Settings.ZPlus=ajRB) and (Settings.ZMinus=ajRT),'Upper/lower right shoulder defaults');
      Settings.ZPlus:=ajLB; Settings.ZMinus:=ajLT; Settings.InvertX:=True; Settings.DeviceID:='two';
      SaveJoystickSettings(FN,Settings); Loaded:=LoadJoystickSettings(FN);
      Check((Loaded.ZPlus=ajLB) and (Loaded.ZMinus=ajLT) and Loaded.InvertX and (Loaded.DeviceID='two'),'Persistent custom model mapping');
      Settings.XAxis:=-7; Settings.ZPlus:=900; Settings.DeadZone:=1; Settings.Feed:=Infinity;
      ValidateJoystickSettings(Settings);
      Check((Settings.XAxis=0) and (Settings.ZPlus=34) and (Abs(Settings.DeadZone-0.8)<1e-12) and (Settings.Feed=500),'Corrupt settings bounded');
      Gate.OnJog:=@Sink.Jog; Gate.OnCancel:=@Sink.Cancel;
      Input:=Default(TAIJoystickState); Input.Connected:=True; Input.DeviceID:='one'; Input.Axes[0]:=1;
      Update(True,True,True,True,1000); Check(Sink.Jogs=0,'Held input at startup never moves');
      Neutral(1100); Check(Gate.Armed,'Neutral enables control');
      Input.Axes[0]:=0.19; Update(True,True,True,True,1200); Check(Sink.Jogs=0,'Dead zone ignores drift');
      Input.Axes[0]:=1; Input.Axes[1]:=-1; Update(True,True,True,True,1300);
      Check((Sink.Jogs=1) and (Sink.X>0) and (Sink.Y<0) and (Sink.Z=0),'XY diagonal preserves axis directions');
      Check(Sqrt(Sqr(Sink.X)+Sqr(Sink.Y))<=1,'Diagonal pulse length bounded');
      Update(True,True,True,True,1350); Check(Sink.Jogs=1,'Minimum pulse interval enforced');
      Update(True,True,False,True,1400); Check(Sink.Jogs=1,'Busy controller cannot accumulate pulses');
      N:=Sink.Cancels; Neutral(1500); Check(Sink.Cancels=N+1,'Release cancels only owned motion');
      Neutral(1550); Check(Sink.Cancels=N+1,'No repeated cancel when already neutral');
      Input.Controls[ajRB]:=True; Update(True,True,True,True,1600);
      Check(Sink.Z>0,'Upper shoulder is Z+');
      Neutral(1700); Input.Controls[ajRT]:=True; Update(True,True,True,True,1800);
      Check(Sink.Z<0,'Lower trigger is Z-');
      N:=Sink.Jogs; Input.Controls[ajRB]:=True; Update(True,True,True,True,1900);
      Check((Sink.Jogs=N) and not Gate.OwnMotion,'Opposite Z controls together stop');
      Neutral(2000); Input.Controls[ajRB]:=True; Update(True,True,True,False,2100);
      Check(Sink.Jogs=N,'No Z commands for a laser without Z');
      Neutral(2200); Input.Axes[0]:=1; Update(True,True,True,True,2300);
      N:=Sink.Cancels; Update(False,True,True,True,2400);
      Check((Sink.Cancels=N+1) and not Gate.Armed,'Focus loss cancels and disarms');
      N:=Sink.Jogs; Update(True,True,True,True,2500); Check(Sink.Jogs=N,'Focus regain while held cannot resume');
      Neutral(2600); Input.Axes[0]:=1; Update(True,True,True,True,2700);
      Input.Connected:=False; N:=Sink.Cancels; Update(True,True,True,True,2800);
      Check((Sink.Cancels=N+1) and not Gate.Armed,'Unplug cancels and disarms');
      Input.Connected:=True; N:=Sink.Jogs; Update(True,True,True,True,2900); Check(Sink.Jogs=N,'Reconnect while held cannot move');
      Neutral(3000); Input.Axes[0]:=1; Update(True,True,True,True,3100);
      N:=Sink.Cancels; Update(True,False,False,True,3200);
      Check((Sink.Cancels=N+1) and not Gate.Armed,'Program start or alarm suspends control');
      N:=Sink.Jogs; Update(True,True,True,True,3300); Check(Sink.Jogs=N,'Program end requires neutral again');
      Neutral(3400); Input.DeviceID:='two'; Input.Axes[0]:=1; Update(True,True,True,True,3500);
      Check(Sink.Jogs=N,'Replacement controller requires neutral');
      Neutral(3600); Settings:=DefaultJoystickSettings; Settings.InvertX:=True; Gate.Settings:=Settings;
      Neutral(3700); Input.Axes[0]:=1; Update(True,True,True,True,3800); Check(Sink.X<0,'Axis inversion');
      Settings.Enabled:=False; N:=Sink.Cancels; Gate.Settings:=Settings;
      Check(Sink.Cancels=N+1,'Disabling cancels immediately');
      N:=Sink.Jogs; Update(True,True,True,True,3900); Check(Sink.Jogs=N,'Disabled control never moves');
      Settings:=DefaultJoystickSettings; Gate.Settings:=Settings; Neutral(4000);
      Sink.Reject:=True; Input.Axes[0]:=1; Update(True,True,True,True,4100); Check(not Gate.Armed,'Rejected motion disarms');
      Connect(mtRouter,pkGRBL); Check(S.JoystickReady,'Router ready');
      Check(S.JoystickJog(0.5,-0.25,0.1,500),'GRBL combined XYZ');
      Check((Pos('$J=G91 G21 X0.500 Y-0.250 Z0.100 F500',Port.Sent.Text)>0),'Correct GRBL vector bytes');
      N:=Port.Sent.Count; Check(not S.JoystickJog(0.5,0,0,500),'No second pulse before completion');
      Check(Port.Sent.Count=N,'No backlog');
      Check(not S.Jog(axY,1,500) and not S.Send('G0 X10'),'Manual jog and console cannot interleave');
      Check(not S.Home and not S.Zero,'Home and zero cannot interleave');
      Port.Reply('ok'#10); Check(not S.JoystickReady,'A parsed ok alone does not mean movement complete');
      S.CancelJoystick; Check(Pos(#$85,Port.Sent.Text)>0,'GRBL realtime cancel');
      Check(Pos('G4 P0',Port.Sent.Text)>0,'Cancel completion barrier');
      Port.Reply('ok'#10); Sleep(110); Port.Reply('<Idle|MPos:0,0,0>'#10);
      Check(S.JoystickReady,'Fresh idle unlocks next pulse');
      N:=Port.Sent.Count; S.CancelJoystick; Check(Port.Sent.Count=N,'No cancel when session no longer owns jog');
      Check(not S.JoystickJog(3,0,0,500),'Oversized pulse rejected');
      Check(not S.JoystickJog(NaN,0,0,500),'NaN rejected'); Check(not S.JoystickJog(1,0,0,4000),'Overspeed rejected');
      L.Text:='G1 X10 F500'; L.SaveToFile(FN); S.LoadFile(FN); Check(S.Start,'Valid program starts');
      N:=Port.Sent.Count; Check(not S.JoystickAvailable and not S.JoystickJog(1,0,0,500),'Running program blocks joystick');
      S.CancelJoystick; Check(Port.Sent.Count=N,'Joystick release never cancels a program');
      Connect(mtLaser,pkGRBL); N:=Port.Sent.Count;
      Check(not S.JoystickJog(0,0,0.1,500),'Laser Z capability enforced');
      Check(Port.Sent.Count=N,'Unsupported Z emits nothing');
      Check(S.JoystickJog(0.1,0.1,0,500),'Laser XY works');
      Port.Reply('error:20'#10); Sleep(110); Port.Reply('<Idle|MPos:0,0,0>'#10);
      Check(not S.JoystickAvailable,'Firmware rejection latches until reconnect');
      Connect(mtRouter,pkGRBL);
      Port.Reply('Grbl 0.9j [help]'#10);
      Check(not S.JoystickAvailable,'Legacy GRBL cannot use unsafe continuous joystick');
      Connect(mtPrinter3D,pkMarlin); Check(S.JoystickJog(0.1,0.1,-0.1,500),'Printer XYZ works');
      Check(Port.Sent.Count=1,'Marlin first line obeys normal ack flow control');
      for N:=1 to 4 do Port.Reply('ok'#10);
      Check(Pos('M400',Port.Sent.Text)>0,'Marlin waits for actual movement completion');
      Check(not S.JoystickReady,'Marlin cannot accumulate while M400 pending');
      S.CancelJoystick; Check((Pos('M410',Port.Sent.Text)=0) and (Pos(#$85,Port.Sent.Text)=0),'Marlin retains bounded movement and modal restore');
      Port.Reply('ok'#10); Check(Pos('M114',Port.Sent.Text)>0,'Printer position refreshed after completion');
      Port.Reply('ok'#10); Check(S.JoystickReady,'Printer ready after all completion acknowledgements');
      S.Disconnect; Check(not S.JoystickAvailable,'Disconnected machine blocked');
      WriteLn('PASS: ',Checks,' joystick driver, mapping, input gate and machine integration checks');
    finally Driver.Free; Gate.Free; Sink.Free; S.Free; L.Free; DeleteFile(FN); end;
  except on E:Exception do begin WriteLn('FAIL: ',E.Message); Halt(1); end; end;
end.
