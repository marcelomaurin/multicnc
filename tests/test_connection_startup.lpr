program test_connection_startup;
{$mode objfpc}{$H+}
{$interfaces corba}
uses Classes, SysUtils, multicnc_types, multicnc_interfaces, multicnc_session;
type
  TPort = class(TInterfacedObject, IMultiCNCTransport)
  public
    Opened, Reply, ReplyModal: Boolean;
    Sent: string;
    OnData: TTransportDataEvent;
    function Connect: Boolean;
    procedure Disconnect;
    function IsConnected: Boolean;
    function Send(const Data: string): Boolean;
    procedure Poll;
    procedure SetOnData(Event: TTransportDataEvent);
    procedure SetOnState(Event: TTransportStateEvent);
    function GetName: string;
  end;
  TLog = class
    Text: string;
    procedure Receive(const Data: string);
  end;
function TPort.Connect: Boolean; begin Opened := True; Result := True; end;
procedure TPort.Disconnect; begin Opened := False; end;
function TPort.IsConnected: Boolean; begin Result := Opened; end;
function TPort.Send(const Data: string): Boolean;
begin
  Sent := Sent + Data; Result := Opened;
  if ReplyModal and (Data='$$'+#10) and Assigned(OnData) then
    OnData('$13=0 (report inches, bool)'#13#10'ok'#13#10);
  if ReplyModal and (Data='$G'+#10) and Assigned(OnData) then
    OnData('[G0 G54 G17 G21 G90 G94 M5 M9 T0 F0.0 S0.0]'#13#10'ok'#13#10);
  if Reply and (Data='$I'+#10) and Assigned(OnData) then
    OnData('[VER:1.1h.20190825:]'#13#10'ok'#13#10);
  if Reply and (Data = '?') and Assigned(OnData) then
    OnData('<Idle|MPos:1.000,2.000,3.000|FS:0,0>'#13#10);
end;
procedure TPort.Poll; begin end;
procedure TPort.SetOnData(Event: TTransportDataEvent); begin OnData := Event; end;
procedure TPort.SetOnState(Event: TTransportStateEvent); begin end;
function TPort.GetName: string; begin Result := 'test port, no hardware'; end;
procedure TLog.Receive(const Data: string); begin Text := Text + Data; end;
procedure Check(Value: Boolean; const Msg: string);
begin if not Value then raise Exception.Create(Msg); end;
var S: TSimulationSession; P: TPort; L: TLog; HomePos: TMachinePosition;
begin
  S := TSimulationSession.Create; L := TLog.Create;
  try
    S.OnLog := @L.Receive;
    P := TPort.Create; P.Reply := True;
    Check(S.ConnectTransport(mtRouter, pkGRBL, P, P), 'Connect GRBL');
    Check(P.Sent = '', 'No movement or feed command on opening');
    S.Poll;
    Check(P.Sent = '?', 'Startup requests status without movement');
    Check(Pos('RX  <Idle', L.Text) > 0, 'First status reply visible in log');
    Check(Abs(S.Position.X - 1) < 0.001, 'GRBL position received');
    S.Disconnect;
    P := TPort.Create; P.Reply := True;
    Check(S.ConnectTransport(mtRouter, pkGRBL, P, P), 'Reconnect GRBL');
    S.Poll;
    Check(P.Sent = '?', 'Reconnect resets polling deadline');
    S.Disconnect;
    P := TPort.Create;
    Check(S.ConnectTransport(mtRouter, pkGRBL, P, P, True), 'Guarded serial startup');
    Check(P.Sent = #13#10#13#10, 'Wake sequence without reset or motion');
    Check(not S.ControllerReady, 'Port opening does not confirm firmware');
    Check(not S.Jog(axX, 1, 500), 'Block jog without reply');
    Check(not S.Home, 'Block return home without reply');
    Check(not S.PhysicalHoming, 'Block homing without reply');
    Check(not S.SetHome(HomePos), 'Block setting home without reply');
    Check(not S.Zero, 'Block zero without reply');
    Check(not S.SetFeedRate(500), 'Block feed command without reply');
    Check(not S.Unlock, 'Block unlock without reply');
    Check(not S.Send('G0 X1'), 'Block console motion without reply');
    Check(P.Sent = #13#10#13#10, 'Rejected commands never reach transport');
    P.OnData('ok'#13#10);
    Check(not S.ControllerReady, 'A bare ok does not identify GRBL');
    S.Poll;
    Check(P.Sent = #13#10#13#10, 'Wait for board boot before status');
    Sleep(2100); S.Poll;
    Check(P.Sent = #13#10#13#10'?', 'Status query after boot, without motion');
    Check(not S.ControllerReady, 'No response keeps motion blocked');
    P.Reply := True; Sleep(260); S.Poll;
    Check(S.ControllerReady, 'Recognized GRBL status releases controls');
    Check(Pos('Comunicacao com a controladora confirmada.', L.Text) > 0, 'Confirmation logged');
    S.PhysicalHomingAllowed := False;
    L.Text := P.Sent;
    Check(not S.PhysicalHoming, 'No-switch profile rejects physical homing');
    Check(not S.Send('$H'), 'Console homing rejected for no-switch profile');
    Check(not S.Home, 'No return to an undefined manual reference');
    Check(P.Sent = L.Text, 'Rejected homing commands never transmitted');
    S.PhysicalHomingAllowed := True;

    { Resposta exata da TTC3018: reconhecida, mas em alarme. }
    P.Reply := False;
    P.OnData('<Alarm|MPos:-22.000,9.000,-2.447|FS:0,1000|Pn:PXYZ>'#13#10);
    Check(S.ControllerReady, 'Alarme tambem confirma GRBL');
    Check(S.MachineState = msAlarm, 'Alarme nao e falha de conexao');
    Check(not S.Jog(axX, 1, 500), 'Movimento permanece bloqueado em alarme');
    Check(S.Unlock, 'Desbloqueio manual disponivel em alarme');
    Check(Pos('$X'#10, P.Sent) > 0, 'Desbloqueio usa $X');
    P.OnData('ok'#13#10'<Idle|MPos:-22.000,9.000,-2.447|FS:0,0>'#13#10);
    Check(S.ControllerReady and (S.MachineState = msIdle), 'Idle confirmado apos desbloqueio');
    Check(S.Stop, 'Parada solicitada pelo operador');
    Check(not S.ControllerReady, 'Reset pendente nao usa resposta antiga');
    P.OnData('ok'#13#10);
    Check(not S.ControllerReady, 'ok antigo nao libera reset');
    P.OnData('Grbl 1.1h'#13#10);
    Check(S.ControllerReady, 'Banner confirma reinicio');

    S.Disconnect;
    L.Text := ''; P := TPort.Create;
    Check(S.ConnectTransport(mtRouter, pkGRBL, P, P, True), 'Connect legacy GRBL');
    P.OnData('Grbl 0.9j [''$'' for help]'#13#10);
    P.OnData('<Idle,MPos:0.000,0.000,0.000,WPos:-3.056,-5.238,26.256>'#13#10);
    Check(S.ControllerReady and (S.MachineState=msIdle), 'Legacy controller ready');
    Check(Abs(S.Position.X+3.056)<0.001, 'Legacy X work coordinate');
    Check(Abs(S.Position.Y+5.238)<0.001, 'Legacy Y work coordinate');
    Check(Abs(S.Position.Z-26.256)<0.001, 'Legacy Z work coordinate');
    Check(Pos('RX  <Idle,MPos:',L.Text)>0,'First legacy status visible after banner');
    Check(Pos('0.9j',S.FirmwareDescription)>0,'Firmware version available in session');
    Check(Pos('Compatibilidade automatica:',L.Text)>0,'Automatic compatibility visible');
    L.Text := ''; P.ReplyModal:=True;
    Check(S.Jog(axX,1,500),'Legacy session queries modes and jogs');
    Check(Pos('$G'#10'G91 G21 G94 G1 X1.000 F500'#10'G21 G90 G94 G0 F0.0'#10,P.Sent)>0,
      'Legacy command sequence including restoration');
    P.OnData('ok'#13#10'ok'#13#10);
    P.ReplyModal:=False; P.OnData('<Idle,MPos:0,0,0,WPos:0,0,0>'#13#10);
    Check(not S.Jog(axX,1,500),'No legacy movement without fresh modal response');
    Check(Pos('nao enviado',S.LastError)>0,'Clear diagnostic for missing modal response');
    P.OnData('ok'#13#10);
    L.Text := '';
    P.OnData('<Run,MPos:1,2,3,WPos:4,5,6>'#13#10);
    Check(S.MachineState=msRunning,'Legacy Run');
    Check(Pos('RX  <Run',L.Text)=0,'Repeated status remains quiet');
    P.OnData('<Hold,MPos:1,2,3,WPos:4,5,6>'#13#10);
    Check(S.MachineState=msPaused,'Legacy Hold');
    P.OnData('<Alarm,MPos:1,2,3,WPos:4,5,6>'#13#10);
    Check(S.MachineState=msAlarm,'Legacy Alarm never interpreted as Idle');
    Check(not S.Jog(axX,1,500),'Legacy alarm blocks motion');

    S.Disconnect;
    L.Text := ''; P := TPort.Create;
    Check(S.ConnectTransport(mtRouter, pkMarlin, P, P), 'Connect CNC with Marlin');
    Sleep(7600); S.Poll;
    Check(P.Sent = '', 'CNC does not send printer handshake');
    Check(Pos('No printer handshake was sent.', L.Text) > 0, 'Correct CNC diagnostic');
    Check(Pos('5 s after M115', L.Text) = 0, 'Do not claim M115 was sent');
    WriteLn('Startup: OK (GRBL status, first reply, reconnect and CNC/Marlin diagnostics; no hardware)');
  finally S.Free; L.Free; end;
end.
