program test_gcode_compat;
{$mode objfpc}{$H+}{$interfaces corba}
uses Classes, SysUtils, multicnc_types, multicnc_interfaces, multicnc_session,
  multicnc_machine, multicnc_grbl, multicnc_gcode_compat;
type TPort=class(TInterfacedObject,IMultiCNCTransport)
  Opened, RejectNow: Boolean;
  Sent: TStringList;
  OnData: TTransportDataEvent;
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
constructor TPort.Create;begin inherited Create;Sent:=TStringList.Create;end;
destructor TPort.Destroy;begin Sent.Free;inherited Destroy;end;
function TPort.Connect:Boolean;begin Opened:=True;Result:=True;end;
procedure TPort.Disconnect;begin Opened:=False;end;
function TPort.IsConnected:Boolean;begin Result:=Opened;end;
function TPort.Send(const Data:string):Boolean;
begin Result:=Opened;Sent.Add(Data);if RejectNow then Reply('error:20'#10);end;
procedure TPort.Poll;begin end;
procedure TPort.SetOnData(Event:TTransportDataEvent);begin OnData:=Event;end;
procedure TPort.SetOnState(Event:TTransportStateEvent);begin end;
function TPort.GetName:string;begin Result:='Fake controller, no hardware';end;
procedure TPort.Reply(const Data:string);begin if Assigned(OnData) then OnData(Data);end;
const BadCommands: array[0..12] of string = ('M82','m83','M104 S200','M109 S200','M140 S60','M190 S60','M84',
  'G92 E0','G1X50Y20E1.12253F1800','N10 M0104.0 S200','M 82','G1 E-0.5','N1 G21*18');
  GoodCommands: array[0..19] of string = ('G21','G90','G28','G92 X0 Y0 Z0','G1X50Y20F1800',
    'M3 S12000','M4 S100','M5','G2 X10 Y10 I5 J0 F600','M8','M9','M30',
    '; M104 S200 E1','(M82) G1 X10 (E1) F500','G1 Y10 ; E1 M109',
    '$I','$$','$X','$J=G91 G21 X1 F500','$SSID=HOME');
var S:TSimulationSession;Port:TPort;P:TGRBLProtocol;M:TMultiCNCMachine;
  L:TStringList;Reason,FN,Sample,Cmd:string;Acks,Errors,Checks:Integer;
procedure Check(OK:Boolean;const Msg:string);
begin Inc(Checks);if not OK then raise Exception.Create(Msg);end;
procedure Block(const Command:string);
begin
  Check(not CheckGCodeCompatibility(Command,'GRBL',Reason),'GRBL must reject '+Command);
  Check(Reason<>'','Actionable reason');
  Check(CheckGCodeCompatibility(Command,'Marlin',Reason),'Marlin remains available '+Command);
end;
procedure Save(const Text:string);begin L.Text:=Text;L.SaveToFile(FN);end;
begin
  S:=nil;L:=TStringList.Create;FN:=GetTempFileName(GetTempDir,'gcd');
  try
    try
      for Cmd in BadCommands do Block(Cmd);
      for Cmd in GoodCommands do
        Check(CheckGCodeCompatibility(Cmd,'GRBL',Reason),'Valid GRBL preserved '+Cmd);
      Check(not CheckGCodeCompatibility('M104 S200','FluidNC',Reason),'FluidNC rejects printer temperatures');
      Sample:=ExpandFileName(ExtractFilePath(ParamStr(0))+'../models/printer3d/cantoneira_30mm_marlin.gcode');
      L.LoadFromFile(Sample);Check(not CheckProgramCompatibility(L,'GRBL',Reason),'Actual reported file rejected');
      Check((Pos('Linha 7:',Reason)>0) and (Pos('M82',Reason)>0),'Physical source line reported');
      S:=TSimulationSession.Create;Port:=TPort.Create;
      Check(S.ConnectTransport(mtRouter,pkGRBL,Port,Port),'Connect fake GRBL');
      S.LoadFile(Sample);Check(not S.Start,'Start blocked');
      Check(Port.Sent.Count=0,'NO bytes sent, including initial G21/G90/G28');
      Check(Pos('Linha 7:',S.LastError)>0,'Block explained to UI');
      Save('; misleading .nc filename'+LineEnding+'G21'+LineEnding+'G1 X10 F500'+LineEnding+'M104 S200');
      S.LoadFile(FN);Check(not S.Start,'Late heater command blocks renamed file');
      Check(Port.Sent.Count=0,'Late command preflight prevents earlier movement');
      Check(not S.Send('G1X10E1F500'),'Console rejects extrusion');Check(Port.Sent.Count=0,'Console sends nothing');
      L.Text:='G1 X10 F500'+LineEnding+'M82';
      Check(not S.RunFraming(L),'Framing API also guarded');Check(Port.Sent.Count=0,'No partial framing');
      Save('G21'+LineEnding+'G90'+LineEnding+'G1 X10 F500');S.LoadFile(FN);
      Check(S.Start,'Valid router program accepted');Check(Port.Sent.Count=3,'Valid lines transmitted');
      Port.Reply('error:20'#10);Port.Reply('error:26'#10'error:36'#10);S.Tick;
      Check(S.State=ssError,'Firmware errors abort');
      Check(Pos('error:20',S.LastError)>0,'First error survives later receive packets');
      Save('G1 X10 F500'+LineEnding+'G1 Y10 F500');S.LoadFile(FN);Port.Sent.Clear;Port.RejectNow:=True;
      Check(not S.Start,'Synchronous error prevents successful start');
      Check(Port.Sent.Count=1,'Stop feeding immediately after synchronous rejection');
      S.Disconnect;Port:=TPort.Create;Check(S.ConnectTransport(mtPrinter3D,pkMarlin,Port,Port),'Reconnect Marlin');
      Sleep(2600);
      S.LoadFile(Sample);Check(S.Start,'Same source accepted for Marlin');
      Check(Port.Sent.Count=1,'Marlin keeps one-line flow control');
      FreeAndNil(S);
      P:=TGRBLProtocol.Create;
      try
        P.ProcessIncoming('error:20'#10'ok'#10'error:36'#10);
        Check(P.TakeResponses(Acks,Errors) and (Acks=1) and (Errors=2),'Error never double-counted as OK');
        Check(P.LastMessage='error:20','First error preserved inside one packet');
      finally P.Free;end;
      Port:=TPort.Create;P:=TGRBLProtocol.Create;M:=TMultiCNCMachine.Create(mtRouter,Port,P);
      try
        Check(M.Connect,'Machine fake connected');
        Check(M.SendGCode('G21'+LineEnding+'G90'+LineEnding+'G1 X10 F500'),'Three in-flight lines');
        Port.Reply('error:20'#10);Check(M.InFlightLines=2,'One error releases exactly one line');
      finally M.Free;P.Free;Port.Free;end;
      WriteLn('PASS: ',Checks,' G-code compatibility and error-handling checks');
    finally S.Free;L.Free;DeleteFile(FN);end;
  except on E:Exception do begin WriteLn('FAIL: ',E.Message);Halt(1);end;end;
end.
