program test_router_spindle;
{$mode objfpc}{$H+}{$interfaces corba}
uses Classes, SysUtils, aijoystick, multicnc_joystick, multicnc_session,
  multicnc_types, multicnc_interfaces;
type
  TPort=class(TInterfacedObject,IMultiCNCTransport)
    Opened,FailCancel:Boolean; Sent:TStringList; OnData:TTransportDataEvent;
    constructor Create;
    destructor Destroy; override;
    function Connect:Boolean;
    procedure Disconnect;
    function IsConnected:Boolean;
    function Send(const Data:string):Boolean;
    procedure Poll;
    procedure SetOnData(Event:TTransportDataEvent);
    procedure SetOnState(Event:TTransportStateEvent);
    function GetName:string;
    procedure Reply(const Data:string);
  end;
  TSink=class
    OnCount,OffCount,JogCount,CancelCount,RPM:Integer;
    Reject:Boolean;
    function Spindle(Enabled:Boolean; Speed:Integer):Boolean;
    function Jog(X,Y,Z,Feed:Double):Boolean;
    procedure Cancel;
  end;
constructor TPort.Create;begin inherited Create;Sent:=TStringList.Create;end;
destructor TPort.Destroy;begin Sent.Free;inherited Destroy;end;
{ Sleep pode voltar antes do pedido em alguns ambientes (Wine, timers de
  baixa resolucao); o teste precisa de pelo menos Ms no relogio da sessao. }
procedure WaitTicks(Ms: QWord);
var T: QWord;
begin
  T := GetTickCount64;
  repeat Sleep(10) until GetTickCount64 - T >= Ms;
end;

function TPort.Connect:Boolean;begin Opened:=True;Result:=True;end;
procedure TPort.Disconnect;begin Opened:=False;end;
function TPort.IsConnected:Boolean;begin Result:=Opened;end;
function TPort.Send(const Data:string):Boolean;
begin Result:=Opened and not (FailCancel and (Pos(#$85,Data)>0));Sent.Add(Data);end;
procedure TPort.Poll;begin end;
procedure TPort.SetOnData(Event:TTransportDataEvent);begin OnData:=Event;end;
procedure TPort.SetOnState(Event:TTransportStateEvent);begin end;
function TPort.GetName:string;begin Result:='fake spindle controller, no hardware';end;
procedure TPort.Reply(const Data:string);begin if Assigned(OnData) then OnData(Data);end;
function TSink.Spindle(Enabled:Boolean;Speed:Integer):Boolean;
begin if Enabled then Inc(OnCount) else Inc(OffCount); RPM:=Speed;Result:=not Reject;end;
function TSink.Jog(X,Y,Z,Feed:Double):Boolean;begin Inc(JogCount);Result:=True;end;
procedure TSink.Cancel;begin Inc(CancelCount);end;
var Gate:TJoystickControl; Sink:TSink; Settings,Loaded:TJoystickSettings;
  Input:TAIJoystickState; S:TSimulationSession; Port:TPort; L:TStringList;
  Checks,N:Integer; FN:string;
procedure Check(Value:Boolean;const Msg:string);
begin Inc(Checks);if not Value then raise Exception.Create(Msg);end;
procedure Update(Active,Available,Ready,Router:Boolean);
begin Gate.Update(Input,Active,Available,Ready,True,1000,Router);end;
procedure Neutral;
begin Input.Axes[0]:=0;Input.Axes[1]:=0;FillChar(Input.Controls,SizeOf(Input.Controls),0);Update(True,True,True,True);end;
procedure Connect(Kind:TMachineType;Protocol:TProtocolKind=pkGRBL);
begin
  S.Disconnect;Port:=TPort.Create;Check(S.ConnectTransport(Kind,Protocol,Port,Port),'Fake connection');
end;
begin
  Gate:=TJoystickControl.Create;Sink:=TSink.Create;S:=TSimulationSession.Create;
  L:=TStringList.Create;FN:=GetTempFileName(GetTempDir,'spn');
  try
    try
      Settings:=DefaultJoystickSettings;
      Check((Settings.SpindleOnButton=0) and (Settings.SpindleOffButton=0),'Spindle shortcuts unassigned by default');
      Settings.SpindleOnButton:=ajX;Settings.SpindleOffButton:=ajB;Settings.SpindleRPM:=6000;
      Check(JoystickSpindleBindingsValid(Settings),'Independent spindle bindings accepted');
      SaveJoystickSettings(FN,Settings);Loaded:=LoadJoystickSettings(FN);
      Check((Loaded.SpindleOnButton=ajX) and (Loaded.SpindleOffButton=ajB) and (Loaded.SpindleRPM=6000),'Mapping and speed persist');
      Loaded.SpindleOnButton:=Loaded.ZPlus;Check(not JoystickSpindleBindingsValid(Loaded),'Z conflict rejected');
      Loaded:=Settings;Loaded.SpindleOffButton:=Loaded.SpindleOnButton;
      Check(not JoystickSpindleBindingsValid(Loaded),'Same button for on and off rejected');
      Gate.Settings:=Settings;Gate.OnSpindle:=@Sink.Spindle;Gate.OnJog:=@Sink.Jog;Gate.OnCancel:=@Sink.Cancel;
      Input:=Default(TAIJoystickState);Input.Connected:=True;Input.DeviceID:='fake';
      Input.Controls[ajX]:=True;Update(True,True,True,True);
      Check(Sink.OnCount=0,'Held on button at connection cannot start spindle');
      Neutral;Input.Controls[ajX]:=True;Update(True,True,True,True);
      Check((Sink.OnCount=1) and (Sink.RPM=6000),'Press sends selected RPM');
      Update(True,True,True,True);Update(True,True,True,True);
      Check(Sink.OnCount=1,'Holding button sends only one command');
      Neutral;Input.Controls[ajX]:=True;Update(True,True,True,True);
      Check(Sink.OnCount=2,'Release and new press sends next command');
      Neutral;Input.Controls[ajB]:=True;Update(True,True,True,True);
      Check(Sink.OffCount=1,'Selected off button works');
      Update(True,True,True,True);Check(Sink.OffCount=1,'Off also fires once per press');
      Neutral;Input.Controls[ajX]:=True;Input.Controls[ajB]:=True;Update(True,True,True,True);
      Check((Sink.OffCount=2) and (Sink.OnCount=2),'Off wins when both pressed');
      Neutral;Input.Controls[ajX]:=True;Update(True,True,True,False);
      Check(Sink.OnCount=2,'Laser and printer cannot start spindle');
      Neutral;Input.Controls[ajX]:=True;Update(False,True,True,True);
      Check(Sink.OnCount=2,'Window focus guard');
      Neutral;Input.Controls[ajX]:=True;Update(True,False,True,True);
      Check(Sink.OnCount=2,'Running program or disconnected controller blocks on');
      Neutral;Input.Controls[ajX]:=True;Update(True,True,False,True);
      Update(True,True,True,True);Check(Sink.OnCount=2,'Busy press never starts later while held');
      Neutral;Input.Axes[0]:=1;Input.Controls[ajX]:=True;Update(True,True,True,True);
      Check((Sink.OnCount=2) and (Sink.JogCount=0),'Start spindle requires centered stick');
      Neutral;Input.Axes[0]:=1;Update(True,True,True,True);Check(Sink.JogCount=1,'Jog owns one pulse');
      Input.Controls[ajB]:=True;Update(True,True,False,True);
      Check((Sink.CancelCount=1) and (Sink.OffCount=3),'Stop spindle cancels own jog even while stick displaced');
      Check(not Gate.Armed,'Stop requires neutral before further movements');
      Neutral;Input.Controls[ajX]:=True;Sink.Reject:=True;Update(True,True,True,True);
      Check(not Gate.Armed,'Rejected command cannot automatically repeat');
      N:=Sink.OnCount;Update(True,True,True,True);Check(Sink.OnCount=N,'Rejected press held never retries');
      Settings.SpindleOnButton:=Settings.ZPlus;Gate.Settings:=Settings;Neutral;
      Input.Controls[Settings.ZPlus]:=True;N:=Sink.JogCount;Update(True,True,True,True);
      Check((Sink.OnCount=3) and (Sink.JogCount=N),'Conflicting binding blocks all joystick commands');
      Check(not S.RouterSpindleOn(1000) and not S.RouterSpindleOff,'Disconnected API blocked');
      Connect(mtRouter);S.RouterSpindleMaxRPM:=10000;
      Check(not S.RouterSpindleOn(0) and not S.RouterSpindleOn(100001) and not S.RouterSpindleOn(12000),'RPM bounds and profile maximum enforced');
      Check(Port.Sent.Count=0,'Rejected spindle commands emit no bytes');
      Check(S.RouterSpindleOn(6000),'Router spindle on API');
      Check((Port.Sent.Count=1) and (Port.Sent[0]='M3 S6000'#10),'Correct one-line M3 command with terminator');
      Check(not S.RouterSpindleOn(6000),'Wait for spindle command acknowledgement');
      Port.Reply('ok'#10);Check(S.RouterSpindleOff,'Router spindle off API');
      Check(Port.Sent[1]='M5'#10,'Correct M5 with terminator');Port.Reply('ok'#10);
      Check(S.JoystickJog(0.5,0,0,500),'Start own bounded jog');
      Check(S.RouterSpindleOff,'Stop works during owned joystick movement');
      Check((Pos(#$85,Port.Sent.Text)>0) and (Pos('G4 P0',Port.Sent.Text)>0),'Jog cancellation before spindle stop');
      Check(Port.Sent[Port.Sent.Count-1]='M5'#10,'M5 follows cancel barrier');
      N:=Port.Sent.Count;S.CancelJoystick;Check(Port.Sent.Count=N,'No repeated cancel or barrier after spindle off');
      Port.Reply('ok'#10'ok'#10'ok'#10);WaitTicks(110);Port.Reply('<Idle|MPos:0,0,0>'#10);
      L.Text:='G1 X10 F500';L.SaveToFile(FN);S.LoadFile(FN);Check(S.Start,'Program starts after manual commands drain');
      N:=Port.Sent.Count;Check(not S.RouterSpindleOn(1000) and not S.RouterSpindleOff,'Both blocked during program');
      Check(Port.Sent.Count=N,'Program is not altered');Check(S.Pause,'Pause program');
      Check(not S.RouterSpindleOn(1000) and not S.RouterSpindleOff,'Paused program also protected');
      Connect(mtLaser);Check(not S.RouterSpindleOn(1000) and not S.RouterSpindleOff,'Laser cannot invoke router spindle API');
      Check(Port.Sent.Count=0,'No M3/M5 accidentally sent to laser');
      Connect(mtPrinter3D,pkMarlin);Check(not S.RouterSpindleOn(1000) and not S.RouterSpindleOff,'Printer cannot invoke router spindle API');
      Connect(mtRouter);Port.Reply('ALARM:1'#10);
      Check(not S.RouterSpindleOn(1000),'Alarm blocks energizing spindle');
      Check(S.RouterSpindleOff,'Alarm still permits M5');
      Connect(mtRouter);Port.Reply('Grbl 0.9j [help]'#10);
      Check(S.RouterSpindleOn(1000),'Manual spindle also supported on legacy GRBL');
      Connect(mtRouter);Check(S.JoystickJog(0.5,0,0,500),'Fake jog for cancellation failure');
      Port.FailCancel:=True;Check(not S.RouterSpindleOff,'Cancellation failure is reported');
      Check(Pos('M5',Port.Sent.Text)=0,'Failed cancellation never queues an unsynchronized M5');
      Port.FailCancel:=False;Check(S.RouterSpindleOff,'Explicit retry can cancel then stop');
      WriteLn('PASS: ',Checks,' router spindle mapping, debounce, guards and command checks');
    finally Gate.Free;Sink.Free;S.Free;L.Free;DeleteFile(FN);end;
  except on E:Exception do begin WriteLn('FAIL: ',E.Message);Halt(1);end;end;
end.
