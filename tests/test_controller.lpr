program test_controller;
{$mode objfpc}{$H+}
{$interfaces corba}
{ Testa parser de status Grbl, overrides em tempo real, streaming com
  character-counting, protocolo Marlin com checksum/resend, analise de G-code
  com estimativa de tempo e transporte TCP contra um servidor local. }
uses
  {$ifdef unix}cthreads,{$endif}
  Classes, SysUtils, Math, ssockets, multicnc_types, multicnc_interfaces,
  multicnc_grbl_status, multicnc_realtime, multicnc_grbl, multicnc_marlin,
  multicnc_streamer, multicnc_gcode_analyzer, multicnc_tcp;

type
  TFakeTransport = class(TInterfacedObject, IMultiCNCTransport)
  public
    Sent: TStringList;
    Connected: Boolean;
    constructor Create;
    destructor Destroy; override;
    function Connect: Boolean;
    procedure Disconnect;
    function IsConnected: Boolean;
    function Send(const AData: string): Boolean;
    procedure SetOnData(AEvent: TTransportDataEvent);
    procedure SetOnState(AEvent: TTransportStateEvent);
    procedure Poll;
    function GetName: string;
  end;

  TEchoServer = class(TThread)
  public
    Server: TInetServer;
    Port: Word;
    procedure Execute; override;
    procedure OnConnect(Sender: TObject; Data: TSocketStream);
  end;

  TCollector = class
    Data: string;
    procedure OnData(const S: string);
  end;

constructor TFakeTransport.Create; begin inherited Create; Sent := TStringList.Create; Connected := True; end;
destructor TFakeTransport.Destroy; begin Sent.Free; inherited; end;
function TFakeTransport.Connect: Boolean; begin Connected := True; Result := True; end;
procedure TFakeTransport.Disconnect; begin Connected := False; end;
function TFakeTransport.IsConnected: Boolean; begin Result := Connected; end;
function TFakeTransport.Send(const AData: string): Boolean; begin Sent.Add(TrimRight(AData)); Result := Connected; end;
procedure TFakeTransport.SetOnData(AEvent: TTransportDataEvent); begin end;
procedure TFakeTransport.SetOnState(AEvent: TTransportStateEvent); begin end;
procedure TFakeTransport.Poll; begin end;
function TFakeTransport.GetName: string; begin Result := 'fake'; end;

procedure TEchoServer.OnConnect(Sender: TObject; Data: TSocketStream);
var Buf: array[0..255] of Char; N: Integer; Reply: string;
begin
  Reply := 'Grbl 3.7 [FluidNC v3.7.8 (wifi) ''$'' for help]'#13#10;
  Data.Write(Reply[1], Length(Reply));
  N := Data.Read(Buf, SizeOf(Buf));
  if N > 0 then begin
    Reply := '<Idle|MPos:1.000,2.000,3.000|FS:0,0>'#13#10'ok'#13#10;
    Data.Write(Reply[1], Length(Reply));
  end;
  Sleep(200);
  Data.Free;
  Server.StopAccepting(False);
end;

procedure TEchoServer.Execute;
begin
  Server.OnConnect := @OnConnect;
  Server.StartAccepting;
end;

procedure TCollector.OnData(const S: string); begin Data := Data + S; end;

procedure Check(Value: Boolean; const Msg: string);
begin
  if not Value then begin
    WriteLn('FALHOU: ', Msg);
    Halt(1);
  end;
end;

var
  Parser: TGrblStatusParser;
  R: TGrblResponse;
  Fake: TFakeTransport;
  S: TGCodeStreamer;
  Prog, Warn: TStringList;
  I: Integer;
  Rep: TGCodeReport;
  Env: TMachineEnvelope;
  Grbl: TGRBLProtocol;
  Marlin: TMarlinProtocol;
  Srv: TEchoServer;
  Tcp: TTCPTransport;
  Col: TCollector;
  Host: string;
  Port: Word;
begin
  { --- Parser de status --- }
  Parser := TGrblStatusParser.Create;
  try
    R := Parser.ParseLine('Grbl 1.1h [''$'' for help]');
    Check((R.Kind = grkWelcome) and (Parser.Firmware = gfGrbl) and (Parser.Version = '1.1h'), 'banner Grbl');
    R := Parser.ParseLine('GrblHAL 1.1f [''$'' or ''$HELP'' for help]');
    Check(Parser.Firmware = gfGrblHAL, 'banner grblHAL');
    R := Parser.ParseLine('Grbl 3.7 [FluidNC v3.7.8 (wifi) ''$'' for help]');
    Check((Parser.Firmware = gfFluidNC) and (Parser.Version = '3.7.8'), 'banner FluidNC');
    R := Parser.ParseLine('<Run|MPos:10.000,20.000,-1.500|Bf:15,96|FS:1200,8000|WCO:5.000,5.000,-2.000|Ov:120,100,90|A:SF|Pn:P>');
    Check(R.Kind = grkStatus, 'status');
    Check(Parser.Status.State = gsRun, 'estado Run');
    Check(Abs(Parser.Status.WPos.X - 5) < 1e-9, 'WPos = MPos - WCO');
    Check(Abs(Parser.Status.WPos.Z - 0.5) < 1e-9, 'WPos Z');
    Check((Parser.Status.PlannerFree = 15) and (Parser.Status.RxFree = 96), 'Bf');
    Check(Abs(Parser.Status.Spindle - 8000) < 1e-9, 'FS spindle');
    Check(Parser.Status.FeedOverride = 120, 'Ov feed');
    Check((Parser.Status.Accessories = 'SF') and (Parser.Status.Pins = 'P'), 'A/Pn');
    R := Parser.ParseLine('<Hold:1|WPos:1.000,2.000,3.000>');
    Check((Parser.Status.State = gsHold) and (Parser.Status.SubState = 1), 'Hold:1');
    Check(Abs(Parser.Status.MPos.X - 6) < 1e-9, 'MPos reconstruida com WCO anterior');
    R := Parser.ParseLine('error:22');
    Check((R.Kind = grkError) and (R.Code = 22) and (Pos('F', R.Text) > 0), 'error:22');
    R := Parser.ParseLine('ALARM:1');
    Check((R.Kind = grkAlarm) and (Parser.Status.State = gsAlarm), 'ALARM:1');
    Check(GrblStateToMachineState(gsAlarm) = msAlarm, 'mapa de estado');
  finally
    Parser.Free;
  end;

  { --- Overrides --- }
  Check(BuildFeedOverride(100, 100) = #$90, 'reset feed');
  Check(BuildFeedOverride(100, 125) = #$91#$91#$93#$93#$93#$93#$93, 'feed 125');
  Check(BuildFeedOverride(150, 95) = #$90#$94#$94#$94#$94#$94, 'feed 95 via reset');
  Check(BuildRapidOverride(50) = #$96, 'rapid 50');
  Check(RealtimeSupported(rtStatusReportAll, gfGrblHAL) and not RealtimeSupported(rtStatusReportAll, gfGrbl), 'extensoes grblHAL');

  { --- Protocolo Grbl com telemetria --- }
  Grbl := TGrblHALProtocol.Create;
  try
    Grbl.ProcessIncoming('<Idle|MPos:0.000,0.000,0.000|FS:0,0>'#13#10'<Jo');
    Check(Grbl.CurrentState = msIdle, 'protocolo: Idle');
    Grbl.ProcessIncoming('g|MPos:1.000,0.000,0.000>'#13#10);
    Check(Grbl.CurrentState = msRunning, 'protocolo: linha fragmentada');
    Check(Grbl.RxBufferSize = 1024, 'grblHAL RX 1024');
    Check(Grbl.RecommendedStreamMode = smCharacterCounting, 'modo grbl');
    Check(Pos('G21', Grbl.BuildJogCommand(axX, 1.5, 500)) > 0, 'jog em mm');
    Check(Grbl.BuildFeedOverride(110) = #$91, 'override pelo protocolo');
  finally
    Grbl.Free;
  end;

  { --- Streamer character-counting --- }
  Fake := TFakeTransport.Create;
  Prog := TStringList.Create;
  S := TGCodeStreamer.Create(Fake, smCharacterCounting, 32);
  try
    Prog.Text := 'G21 ; mm'#10'(cabecalho)'#10'G0 X10 Y10'#10'G1 X20 F500'#10'G1 Y20'#10'G1 X10'#10'G1 Y10'#10'M5';
    S.Load(Prog);
    Check(S.Total = 7, 'limpeza de comentarios');
    Check(S.Start, 'start');
    // 32 bytes: 'G21'(4) 'G0 X10 Y10'(11) 'G1 X20 F500'(12) = 27, proxima (7) nao cabe
    Check(Fake.Sent.Count = 3, Format('buffer cheio com 3 linhas (%d)', [Fake.Sent.Count]));
    Check(S.InFlightBytes = 27, 'bytes em transito');
    S.Feed('ok'#13#10);
    Check(Fake.Sent.Count = 4, 'ok libera espaco');
    S.Feed('<Run|MPos:0,0,0>'#13#10);
    Check(S.Acknowledged = 1, 'status nao conta como ok');
    S.Pause;
    S.Feed('ok'#10'ok'#10);
    Check(Fake.Sent.Count = 4, 'pausado nao envia');
    S.Resume;
    Check(Fake.Sent.Count = 7, 'retoma e completa buffer');
    for I := 1 to 4 do S.Feed('ok'#10);
    Check(S.State = stDone, 'concluido');
    Check(Abs(S.Progress - 100) < 1e-9, 'progresso 100%');
    // erro para o envio
    S.Load(Prog);
    S.Start;
    S.Feed('error:20'#10);
    Check((S.State = stError) and (S.Errors = 1), 'erro interrompe');
  finally
    S.Free;
    Prog.Free;
  end;

  { --- Marlin: checksum e resend --- }
  Check(TGCodeStreamer.MarlinChecksum('N0 M110') = (Ord('N') xor Ord('0') xor Ord(' ') xor Ord('M') xor Ord('1') xor Ord('1') xor Ord('0')), 'checksum');
  Fake.Sent.Clear;
  Prog := TStringList.Create;
  S := TGCodeStreamer.Create(Fake, smMarlinChecksum);
  try
    Prog.Text := 'G28'#10'G1 X10 F3000'#10'G1 Y10';
    S.Load(Prog);
    S.Start;
    Check((Fake.Sent.Count = 1) and (Copy(Fake.Sent[0], 1, 7) = 'N0 M110'), 'M110 inicial');
    S.Feed('ok'#10);
    Check(Copy(Fake.Sent[1], 1, 6) = 'N1 G28', 'linha numerada');
    S.Feed('ok'#10);
    Check(Copy(Fake.Sent[2], 1, 15) = 'N2 G1 X10 F3000', 'segunda linha');
    S.Feed('Error:checksum mismatch, Last Line: 1'#10'Resend: 2'#10'ok'#10);
    Check(Copy(Fake.Sent[3], 1, 15) = 'N2 G1 X10 F3000', 'retransmite linha 2');
    Check(S.Errors = 0, 'erro de transmissao nao conta como erro de programa');
    S.Feed('echo:busy: processing'#10'ok'#10'ok'#10);
    Check(S.State = stDone, 'Marlin concluido');
  finally
    S.Free;
    Prog.Free;
  end;
  Fake.Free;

  Marlin := TMarlinProtocol.Create;
  try
    Marlin.ProcessIncoming('ok T:205.3 /210.0 B:59.8 /60.0 @:64 B@:0'#10'X:10.00 Y:20.00 Z:0.30 E:1.20 Count X:800 Y:1600 Z:120'#10);
    Check(Marlin.Temperatures.Valid and (Abs(Marlin.Temperatures.HotendTarget - 210) < 1e-9), 'temperaturas Marlin');
    Check(Abs(Marlin.Temperatures.Bed - 59.8) < 1e-9, 'mesa Marlin');
    Check(Abs(Marlin.CurrentPosition.Y - 20) < 1e-9, 'M114 Marlin');
    Check(Marlin.BuildFeedOverride(150) = 'M220 S150' + LineEnding, 'M220');
  finally
    Marlin.Free;
  end;

  { --- Analise de G-code --- }
  Env := DefaultEnvelope(200, 200, 50);
  Env.Acceleration := 100;
  Env.AccelerationZ := 100;
  Prog := TStringList.Create;
  Warn := TStringList.Create;
  try
    Prog.Text := 'G21 G90'#10'M3 S10000'#10'G1 X100 F600';
    Rep := TGCodeAnalyzer.Analyze(Prog, Env, Warn);
    // 100 mm a 10 mm/s com a=100: 0.1 + 0.1 + 99/10 = 10.1 s
    Check(Abs(Rep.EstimatedSeconds - 10.1) < 1e-6, Format('tempo trapezoidal %.4f', [Rep.EstimatedSeconds]));
    Check(Warn.Count = 0, 'programa limpo sem avisos: ' + Warn.Text);
    // Duas retas colineares devem ser mais rapidas que uma esquina de 90 graus
    Prog.Text := 'M3'#10'G1 X50 F3000'#10'G1 X100';
    Rep := TGCodeAnalyzer.Analyze(Prog, Env, Warn);
    I := Round(Rep.EstimatedSeconds * 1000);
    Prog.Text := 'M3'#10'G1 X50 F3000'#10'G1 X50 Y50';
    Rep := TGCodeAnalyzer.Analyze(Prog, Env, Warn);
    Check(Rep.EstimatedSeconds * 1000 > I, 'esquina reduz velocidade (junction deviation)');
    // Arco completo de raio 10: comprimento 2*pi*10
    Prog.Text := 'G21'#10'M3'#10'G0 X60 Y50'#10'G2 X60 Y50 I-10 J0 F1000';
    Warn.Clear;
    Rep := TGCodeAnalyzer.Analyze(Prog, Env, Warn);
    Check(Abs(Rep.CutLength - 2 * Pi * 10) < 0.01, Format('arco completo %.4f', [Rep.CutLength]));
    Check((Abs(Rep.MinX) < 0.01) and (Abs(Rep.MaxY - 60) < 0.01), 'limites incluem origem e arco');
    // Arco por R e polegadas
    Prog.Text := 'G20'#10'M3'#10'G1 F10'#10'G3 X1 Y1 R1';
    Rep := TGCodeAnalyzer.Analyze(Prog, Env, Warn);
    Check(Rep.UsesInches and (Abs(Rep.CutLength - Pi * 25.4 / 2) < 0.01), 'arco R em polegadas');
    // Envelope, avanco ausente e spindle desligado
    Prog.Text := 'G0 X250'#10'G1 X10';
    Warn.Clear;
    Rep := TGCodeAnalyzer.Analyze(Prog, Env, Warn);
    Check(Rep.Errors >= 2, 'erros detectados');
    Check(Pos('envelope', Warn.Text) > 0, 'aviso de envelope');
    Check(Pos('error:22', Warn.Text) > 0, 'aviso de F ausente');
    Check(Pos('spindle', Warn.Text) > 0, 'aviso de spindle');
    Check(FormatDuration(3725) = '1:02:05', 'formato de duracao');
  finally
    Warn.Free;
    Prog.Free;
  end;

  { --- Transporte TCP --- }
  Check(ParseTCPAddress('tcp://fluidnc.local:2323', Host, Port) and (Host = 'fluidnc.local') and (Port = 2323), 'endereco tcp');
  Check(ParseTCPAddress('192.168.0.10', Host, Port) and (Port = 23), 'porta telnet padrao');
  Srv := TEchoServer.Create(True);
  Port := 39000 + (GetProcessID mod 2000);
  Srv.Server := TInetServer.Create('127.0.0.1', Port);
  Srv.Server.ReuseAddress := True;
  Srv.Server.Bind;
  Srv.Server.Listen;
  Srv.FreeOnTerminate := False;
  Srv.Start;
  Col := TCollector.Create;
  begin
    Tcp := TTCPTransport.Create('127.0.0.1', Port, 2000);
    try
      Tcp.SetOnData(@Col.OnData);
      Check(Tcp.Connect, 'conecta TCP: ' + Tcp.LastError);
      for I := 1 to 50 do begin Tcp.Poll(20); if Pos('FluidNC', Col.Data) > 0 then Break; end;
      Check(Pos('FluidNC', Col.Data) > 0, 'banner via TCP');
      Check(Tcp.Send('?'), 'envio TCP');
      for I := 1 to 50 do begin Tcp.Poll(20); if Pos('ok', Col.Data) > 0 then Break; end;
      Check(Pos('<Idle|MPos:1.000', Col.Data) > 0, 'status via TCP');
      Tcp.Disconnect;
      Check(not Tcp.IsConnected, 'desconecta TCP');
    finally
      Tcp.Free;
    end;
  end;
  Srv.WaitFor;
  Srv.Server.Free;
  Srv.Free;
  Col.Free;

  WriteLn('MultiCNC controlador: OK (status Grbl/grblHAL/FluidNC, overrides, streaming, Marlin resend, preflight, TCP)');
end.
