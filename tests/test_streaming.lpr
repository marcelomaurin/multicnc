program test_streaming;
{ Nucleo do MultiCNC contra controladoras falsas (sem hardware, sem LCL):
  controle de fluxo GRBL/Marlin, erros, alarmes, leitura de estado/posicao,
  bloqueios de seguranca, parada e execucao de programa pela sessao. }
{$mode objfpc}{$H+}{$interfaces corba}
uses
  Classes, SysUtils, multisuite_numfmt, multicnc_types, multicnc_interfaces,
  multicnc_machine, multicnc_safety, multicnc_grbl, multicnc_marlin,
  multicnc_session, multicnc_laser_config;

type
  { Controladora falsa: guarda o que foi enviado e so responde quando o teste
    manda. Verifica o limite do buffer serial do GRBL (128 bytes) e o envio
    de uma linha por vez no Marlin. }
  TFakeController = class(TInterfacedObject, IMultiCNCTransport)
  public
    Connected: Boolean;
    OnData: TTransportDataEvent;
    Sent: TStringList;       { linhas recebidas (sem LF) }
    Realtime: string;        { bytes de tempo real recebidos }
    FailedLine: string;      { simula falha de transporte no encerramento }
    Pending: TStringList;    { linhas sem resposta }
    PendingBytes, MaxPendingBytes, MaxPendingLines: Integer;
    constructor Create;
    destructor Destroy; override;
    function Connect: Boolean;
    procedure Disconnect;
    function IsConnected: Boolean;
    function Send(const AData: string): Boolean;
    procedure Poll;
    procedure SetOnData(AEvent: TTransportDataEvent);
    procedure SetOnState(AEvent: TTransportStateEvent);
    function GetName: string;
    procedure Reply(const Text: string);
    { Responde "ok" para as N linhas mais antigas. }
    procedure Ack(N: Integer);
  end;

var
  Failures: Integer = 0;

procedure Check(Cond: Boolean; const Msg: string);
begin
  if not Cond then begin Writeln('FAIL: ', Msg); Inc(Failures); end;
end;

constructor TFakeController.Create;
begin
  inherited Create;
  Sent := TStringList.Create;
  Pending := TStringList.Create;
end;

destructor TFakeController.Destroy;
begin
  Sent.Free; Pending.Free;
  inherited Destroy;
end;

function TFakeController.Connect: Boolean; begin Connected := True; Result := True; end;
procedure TFakeController.Disconnect; begin Connected := False; end;
function TFakeController.IsConnected: Boolean; begin Result := Connected; end;
procedure TFakeController.Poll; begin end;
procedure TFakeController.SetOnData(AEvent: TTransportDataEvent); begin OnData := AEvent; end;
procedure TFakeController.SetOnState(AEvent: TTransportStateEvent); begin end;
function TFakeController.GetName: string; begin Result := 'fake'; end;

function TFakeController.Send(const AData: string): Boolean;
var L: string;
begin
  Result := Connected;
  if not Result then Exit;
  if (AData <> '') and (AData[Length(AData)] = #10) then
  begin
    L := Copy(AData, 1, Length(AData) - 1);
    Check(Pos(#10, L) = 0, 'uma linha por Send');
    if (FailedLine <> '') and (L = FailedLine) then Exit(False);
    Sent.Add(L);
    Pending.Add(L);
    Inc(PendingBytes, Length(AData));
    if PendingBytes > MaxPendingBytes then MaxPendingBytes := PendingBytes;
    if Pending.Count > MaxPendingLines then MaxPendingLines := Pending.Count;
  end
  else
    Realtime := Realtime + AData;
end;

procedure TFakeController.Reply(const Text: string);
begin
  if Assigned(OnData) then OnData(Text);
end;

procedure TFakeController.Ack(N: Integer);
begin
  while (N > 0) and (Pending.Count > 0) do
  begin
    Dec(PendingBytes, Length(Pending[0]) + 1);
    Pending.Delete(0);
    Reply('ok' + #13#10);
    Dec(N);
  end;
end;

function NewMachine(Kind: TMachineType; Marlin: Boolean; out F: TFakeController): TMultiCNCMachine;
var P: IMultiCNCProtocol;
begin
  F := TFakeController.Create;
  if Marlin then P := TMarlinProtocol.Create else P := TGRBLProtocol.Create;
  Result := TMultiCNCMachine.Create(Kind, F, P);
  Check(Result.Connect, 'conectar');
end;

procedure TestGRBLCharacterCounting;
var M: TMultiCNCMachine; F: TFakeController; I: Integer;
begin
  M := NewMachine(mtRouter, False, F);
  for I := 1 to 60 do
    Check(M.SendGCode(Format('G1 X%d.125 Y%d.250 F1200', [I, I])), 'enfileirar linha ' + IntToStr(I));
  Check(F.PendingBytes <= 127, 'GRBL: nao excede buffer de 127 bytes (enviados ' + IntToStr(F.PendingBytes) + ')');
  Check(F.Sent.Count < 60, 'GRBL: segura linhas ate receber ok');
  Check(M.GetState = msRunning, 'linhas pendentes = executando');
  while F.Pending.Count > 0 do F.Ack(1);
  Check(F.Sent.Count = 60, 'GRBL: todas as linhas enviadas apos os ok (' + IntToStr(F.Sent.Count) + ')');
  Check(F.MaxPendingBytes <= 127, 'GRBL: buffer nunca excedido (max ' + IntToStr(F.MaxPendingBytes) + ')');
  Check(F.MaxPendingLines > 1, 'GRBL: usa o buffer para mais de uma linha');
  Check(F.Sent[0] = 'G1 X1.125 Y1.250 F1200', 'ordem e conteudo preservados');
  Check(F.Sent[59] = 'G1 X60.125 Y60.250 F1200', 'ultima linha');
  Check(M.PendingLines = 0, 'fila vazia');
  Check(M.GetState = msIdle, 'ocioso apos confirmar tudo');
  M.Free; F.Free;
end;

procedure TestGRBLErrorStopsQueue;
var M: TMultiCNCMachine; F: TFakeController; I, SentBefore: Integer;
begin
  M := NewMachine(mtRouter, False, F);
  for I := 1 to 30 do M.SendGCode(Format('G1 X%d Y1 F500', [I]));
  SentBefore := F.Sent.Count;
  F.Pending.Delete(0); F.PendingBytes := 0;
  F.Reply('error:22' + #10);
  Check(M.ErrorCount = 1, 'erro contado');
  Check(Pos('error:22', M.LastError) > 0, 'mensagem do erro');
  Check(M.QueuedLines = 0, 'fila descartada apos erro');
  while F.Pending.Count > 0 do F.Ack(1);
  Check(F.Sent.Count = SentBefore, 'nada mais enviado apos erro');
  M.Free; F.Free;
end;

procedure TestGRBLAlarmAndStatus;
var M: TMultiCNCMachine; F: TFakeController; P: TMachinePosition;
begin
  M := NewMachine(mtRouter, False, F);
  F.Reply('<Idle|MPos:10.000,20.000,-5.000|FS:0,0|WCO:1.000,2.000,-1.000>' + #13#10);
  P := M.GetPosition;
  Check((Abs(P.X - 9) < 1e-9) and (Abs(P.Y - 18) < 1e-9) and (Abs(P.Z + 4) < 1e-9),
    'posicao de trabalho = MPos - WCO');
  F.Reply('<Run|WPos:3.500,4.000,0.000|FS:500,0>' + #10);
  Check(Abs(M.GetPosition.X - 3.5) < 1e-9, 'WPos direto');
  Check(M.GetState = msRunning, 'estado Run');
  F.Reply('ALARM:2' + #10);
  Check(M.GetState = msAlarm, 'alarme reconhecido');
  Check(M.AlarmCount = 1, 'alarme contado');
  Check(not M.SendGCode('G0 X10'), 'movimento bloqueado em alarme');
  Check(not M.Jog(axX, 1, 500), 'jog bloqueado em alarme');
  Check(M.SendGCode('$$'), 'consulta de configuracao permitida em alarme');
  Check(M.Unlock, 'desbloqueio ($X) permitido');
  Check(F.Sent[F.Sent.Count - 1] = '$X', '$X enviado');
  Check(M.GetState <> msAlarm, 'sai do alarme apos $X');
  F.Ack(10);
  Check(M.SendGCode('G0 X10'), 'movimento liberado apos desbloqueio');
  M.Free; F.Free;
end;

procedure TestSafetyValidation;
var M: TMultiCNCMachine; F: TFakeController; R: string;
begin
  M := NewMachine(mtLaser, False, F);
  Check(not M.SendGCode('G1 X10,5 Y2'), 'rejeita virgula decimal');
  Check(Pos('virgula', M.LastError) > 0, 'motivo informado');
  Check(M.SendGCode('G1 X10 (ponto, virgula no comentario) Y2'), 'virgula em comentario e permitida');
  Check(not M.SendGCode(StringOfChar('G', 200)), 'rejeita linha longa');
  Check(not M.SendGCode('G1'#7'X1'), 'rejeita caractere de controle');
  Check(not M.Jog(axZ, 1, 500), 'laser nao tem Z');
  M.SetWorkEnvelope(300, 200, 0);
  Check(not M.Jog(axY, 250, 500), 'jog maior que o curso');
  Check(M.Jog(axY, 150, 500), 'jog dentro do curso');
  Check(TSafetyValidator.CheckCommand(msIdle, 'G0 X1.5', R), 'validador aceita linha normal');
  M.Free; F.Free;
end;

procedure TestGRBLStopIsImmediate;
var M: TMultiCNCMachine; F: TFakeController; I, SentBefore: Integer;
begin
  M := NewMachine(mtRouter, False, F);
  for I := 1 to 40 do M.SendGCode(Format('G1 X%d Y2 F800', [I]));
  SentBefore := F.Sent.Count;
  Check(M.Stop, 'parar');
  Check(Pos(#24, F.Realtime) > 0, 'GRBL: soft reset (#24) enviado imediatamente');
  Check(M.QueuedLines = 0, 'fila descartada');
  F.Pending.Clear; F.PendingBytes := 0;
  F.Reply('Grbl 1.1h [''$'' for help]' + #13#10);
  Check(M.PendingLines = 0, 'reinicio da controladora limpa pendencias');
  Check(F.Sent.Count = SentBefore, 'nenhuma linha enviada depois da parada');
  Check(M.Pause and (Pos('!', F.Realtime) > 0), 'pausa = feed hold (!)');
  Check(M.Resume and (Pos('~', F.Realtime) > 0), 'retomada = cycle start (~)');
  M.Free; F.Free;
end;

procedure TestMarlin;
var M: TMultiCNCMachine; F: TFakeController; I, N: Integer;
begin
  M := NewMachine(mtPrinter3D, True, F);
  for I := 1 to 10 do M.SendGCode(Format('G1 X%d E%d.5 F1500', [I, I]));
  Check(F.Sent.Count = 1, 'Marlin: uma linha por vez');
  while F.Pending.Count > 0 do F.Ack(1);
  Check((F.Sent.Count = 10) and (F.MaxPendingLines = 1), 'Marlin: todas enviadas, nunca duas pendentes');
  F.Reply('X:10.00 Y:20.50 Z:5.00 E:3.00 Count X:800 Y:1640 Z:2000' + #10);
  Check((Abs(M.GetPosition.Y - 20.5) < 1e-9) and (Abs(M.GetPosition.E - 3) < 1e-9), 'Marlin: M114 lido');
  F.Reply('ok T:200.0 /200.0 B:60.0 /60.0' + #10);
  { pausa no host: nada enviado }
  N := F.Sent.Count;
  Check(M.Pause and (F.Realtime = '') and (F.Sent.Count = N), 'Marlin: pausa no host, sem M25');
  for I := 1 to 5 do M.SendGCode('G1 X1 F100');
  Check(M.Stop, 'parar Marlin');
  Check(F.Sent.IndexOf('M410') >= 0, 'Marlin: M410 (quickstop) enviado');
  Check(F.Sent.IndexOf('M524') < 0, 'Marlin: nao usa M524');
  Check(M.QueuedLines > 0, 'desligamentos aguardam o ok do M410');
  while F.Pending.Count > 0 do F.Ack(1);
  Check((F.Sent.IndexOf('M104 S0') > 0) and (F.Sent.IndexOf('M140 S0') > 0) and (F.Sent.IndexOf('M107') > 0),
    'Marlin impressora: aquecedores e ventilador desligados apos parada');
  N := 0;
  for I := 0 to F.Sent.Count - 1 do if F.Sent[I] = 'G1 X1 F100' then Inc(N);
  Check(N = 1, 'so a linha que ja estava na controladora foi enviada; as da fila nao');
  F.Reply('Error:Printer halted. kill() called!' + #10);
  Check(M.GetState = msAlarm, 'Marlin: halted = alarme');
  Check(not M.SendGCode('G28'), 'Marlin: bloqueia movimento apos halted');
  Check(M.Unlock, 'M999 permitido');
  M.Free; F.Free;
end;

procedure TestJogUsesDecimalPoint;
var M: TMultiCNCMachine; F: TFakeController;
begin
  M := NewMachine(mtRouter, False, F);
  Check(M.Jog(axX, 10.5, 600), 'jog');
  Check(F.Sent[F.Sent.Count - 1] = '$J=G91 G21 X10.500 F600', 'jog com ponto decimal: ' + F.Sent[F.Sent.Count - 1]);
  M.Free; F.Free;
  M := NewMachine(mtPrinter3D, True, F);
  Check(M.Jog(axZ, -0.25, 300), 'jog Marlin');
  while F.Pending.Count > 0 do F.Ack(1);
  Check((F.Sent.Count = 3) and (F.Sent[1] = 'G0 Z-0.250 F300') and (F.Sent[2] = 'G90'), 'jog Marlin G91/G0/G90');
  M.Free; F.Free;
end;

procedure TestMoveTo;
var M: TMultiCNCMachine; F: TFakeController; S: TSimulationSession;
begin
  { Movimento absoluto da impressora: G90 explicito e ponto decimal. }
  M := NewMachine(mtPrinter3D, True, F);
  M.SetWorkEnvelope(220, 220, 250);
  Check(M.MoveTo(110.5, 20, 5, 1500), 'MoveTo Marlin: ' + M.LastError);
  while F.Pending.Count > 0 do F.Ack(1);
  Check((F.Sent.Count = 2) and (F.Sent[0] = 'G90') and
    (F.Sent[1] = 'G0 X110.500 Y20.000 Z5.000 F1500'), 'MoveTo Marlin G90/G0');
  Check(not M.MoveTo(221, 0, 0, 1500), 'MoveTo: X alem do curso recusado');
  Check(not M.MoveTo(0, -1, 0, 1500), 'MoveTo: Y negativo recusado');
  Check(not M.MoveTo(0, 0, 251, 1500), 'MoveTo: Z alem do curso recusado');
  Check(not M.MoveTo(10, 10, 10, 0), 'MoveTo: avanco zero recusado');
  M.Free; F.Free;

  { Laser nao tem Z: alvo Z diferente de zero e recusado. }
  M := NewMachine(mtLaser, False, F);
  Check(not M.MoveTo(10, 10, 5, 1000), 'MoveTo: Z em laser recusado');
  Check(M.MoveTo(10, 10, 0, 1000), 'MoveTo laser XY');
  M.Free; F.Free;

  { Sessao Marlin: apos jog e MoveTo pede M114 para atualizar o DRO. }
  S := TSimulationSession.Create;
  try
    F := TFakeController.Create;
    Check(S.ConnectTransport(mtPrinter3D, pkMarlin, F, F), 'conectar sessao Marlin');
    S.SetWorkEnvelope(220, 220, 250);
    Sleep(2600); { janela de boot do Marlin }
    Check(S.Jog(axX, 10, 1200), 'jog sessao Marlin: ' + S.LastError);
    while F.Pending.Count > 0 do F.Ack(1);
    Check(F.Sent[F.Sent.Count - 1] = 'M114', 'jog Marlin seguido de M114');
    Check(S.MoveTo(50, 60, 10, 1200), 'MoveTo sessao: ' + S.LastError);
    while F.Pending.Count > 0 do F.Ack(1);
    Check(F.Sent[F.Sent.Count - 1] = 'M114', 'MoveTo Marlin seguido de M114');
  finally
    S.Free;
  end;
end;

type
  TLogSink = class
    Lines: TStringList;
    constructor Create;
    destructor Destroy; override;
    procedure Add(const AText: string);
    function Has(const ASub: string): Boolean;
  end;

constructor TLogSink.Create; begin inherited Create; Lines := TStringList.Create; end;
destructor TLogSink.Destroy; begin Lines.Free; inherited Destroy; end;
procedure TLogSink.Add(const AText: string); begin Lines.Add(AText); end;
function TLogSink.Has(const ASub: string): Boolean;
var I: Integer;
begin
  for I := 0 to Lines.Count - 1 do
    if Pos(ASub, Lines[I]) > 0 then Exit(True);
  Result := False;
end;

procedure TestConsoleLog;
var S: TSimulationSession; F: TFakeController; Sink: TLogSink;
begin
  Sink := TLogSink.Create;
  S := TSimulationSession.Create;
  try
    S.OnLog := @Sink.Add;
    F := TFakeController.Create;
    Check(S.ConnectTransport(mtRouter, pkGRBL, F, F), 'conectar GRBL para log');
    { Controladora muda por 5 s: aviso de silencio, uma unica vez. }
    Sleep(5200);
    S.Poll;
    Check(Sink.Has('[MultiCNC] No recognized GRBL reply'), 'aviso de controladora sem resposta');
    Sink.Lines.Clear;
    S.Poll;
    Check(not Sink.Has('No recognized GRBL reply'), 'aviso de silencio nao se repete');
    { Linhas recebidas com prefixo RX; relatorio de temperatura filtrado. }
    F.Reply('Grbl 1.1h [''$'' for help]' + #10);
    Check(Sink.Has('RX  Grbl 1.1h'), 'linha recebida com prefixo RX');
    Sink.Lines.Clear;
    F.Reply('ok T:200.0 /200.0 B:60.0 /60.0' + #10);
    Check(not Sink.Has('T:200'), 'resposta de M105 nao polui o console');
    F.Reply('error:22' + #10);
    Check(Sink.Has('RX  error:22'), 'erro da controladora aparece no console');
  finally
    S.Free; Sink.Free;
  end;
end;

procedure TestSessionJob;
var S: TSimulationSession; F: TFakeController; L: TStringList; FN: string; I, Guard: Integer;
begin
  FN := GetTempFileName(GetTempDir, 'job');
  L := TStringList.Create;
  S := TSimulationSession.Create;
  try
    L.Add('; programa'); L.Add('G21'); L.Add('G90');
    for I := 1 to 40 do L.Add(Format('G1 X%d.5 Y%d F900', [I, I]));
    L.SaveToFile(FN);
    S.LoadFile(FN);
    Check(S.Count = 42, 'programa carregado');
    F := TFakeController.Create;
    Check(S.ConnectTransport(mtRouter, pkGRBL, F, F), 'conectar sessao');
    Check(S.Start, 'iniciar');
    Check(F.MaxPendingBytes <= 127, 'sessao respeita o buffer');
    Check(S.Completed = 0, 'nada confirmado ainda');
    S.Tick;
    Check(S.State = ssRunning, 'nao conclui sem os ok');
    { Pausa: feed hold e nenhuma linha nova. }
    Check(S.Pause, 'pausar');
    I := F.Sent.Count;
    F.Ack(F.Pending.Count);
    S.Tick;
    Check(Pos('!', F.Realtime) > 0, 'feed hold enviado');
    Check(F.Sent.Count = I, 'nenhuma linha nova durante pausa');
    Check(S.Completed > 0, 'linhas confirmadas contam no progresso');
    Check(S.Resume, 'retomar');
    Guard := 0;
    while (S.State = ssRunning) and (Guard < 1000) do
    begin
      F.Ack(1);
      S.Tick;
      Inc(Guard);
    end;
    Check(S.State = ssDone, 'programa concluido apos todos os ok');
    Check(S.Completed = 42, 'progresso = linhas confirmadas');
    Check(F.Sent.Count = 43, 'programa e desligamento enviados uma vez');
    Check(F.Sent[42] = 'M5', 'router termina com spindle desligado');
    Check(F.MaxPendingBytes <= 127, 'buffer nunca excedido');
    { Erro no meio do programa interrompe o envio. }
    Check(S.Start, 'reiniciar programa');
    I := F.Sent.Count;
    F.Pending.Delete(0); F.PendingBytes := 0;
    F.Reply('error:33' + #10);
    S.Tick;
    Check(S.State = ssError, 'erro do firmware interrompe o programa');
    Check(Pos('error:33', S.LastError) > 0, 'motivo exibido');
    Check(Pos(#24, F.Realtime) = 0, 'erro nao reinicia automaticamente a controladora');
    F.Ack(100);
    S.Tick;
    Check(F.Sent.Count - I < 42, 'linhas restantes nao enviadas');
    Check(not S.Start or (S.State = ssRunning), 'pode reiniciar apos erro');
    S.Stop;
    { Alarme durante o programa }
    F.Reply('Grbl 1.1h' + #10);
    F.Pending.Clear; F.PendingBytes := 0;
    Check(S.Start, 'iniciar novamente');
    F.Reply('ALARM:1' + #10);
    S.Tick;
    Check(S.State = ssError, 'alarme interrompe o programa');
    Check(not S.Jog(axX, 1, 500), 'jog bloqueado em alarme');
    Check(S.Unlock, 'desbloquear');
    S.Disconnect;
    Check(not S.Connected, 'desconectado');
  finally
    S.Free;
    L.Free;
    DeleteFile(FN);
  end;
end;

procedure TestSessionEndCommands(Kind: TMachineType; FirmwareError, SendFailure: Boolean);
var S: TSimulationSession; F: TFakeController; L: TStringList; FN: string;
    Settings: TLaserSettings; N: Integer;
begin
  FN := GetTempFileName(GetTempDir, 'end');
  L := TStringList.Create;
  S := TSimulationSession.Create;
  try
    if Kind <> mtPrinter3D then L.Add('M3 S8000');
    L.Add('G90'); L.Add('G1 X20 F900');
    L.SaveToFile(FN);
    S.LoadFile(FN);
    F := TFakeController.Create;
    Check(S.ConnectTransport(Kind, pkGRBL, F, F), 'conectar para encerramento');
    if Kind = mtLaser then
    begin
      Settings := S.LaserSettings;
      Settings.AirAssist := True;
      Settings.AirAssistOnCmd := 'M8';
      Settings.AirAssistOffCmd := 'M9';
      S.LaserSettings := Settings;
    end;
    Check(S.Start, 'iniciar programa sem M5');
    Check(S.State = ssRunning, 'aguarda confirmacoes do programa');
    Check(F.Sent.IndexOf('M5') < 0, 'nao desliga antes das linhas do programa');
    F.Ack(100);
    if SendFailure then F.FailedLine := 'M5';
    S.Tick;
    if Kind = mtPrinter3D then
    begin
      Check(S.State = ssDone, 'impressora conclui sem desligamento de spindle');
      Check(F.Sent.IndexOf('M5') < 0, 'impressora nao recebe M5 automatico');
      Exit;
    end;
    if SendFailure then
    begin
      Check(S.State = ssError, 'falha no envio de M5 nao conclui o programa');
      Check(S.LastError <> '', 'falha de desligamento informada');
      Exit;
    end;
    Check(F.Sent.IndexOf('M5') >= 0, 'M5 automatico apos o programa');
    Check(S.State = ssRunning, 'aguarda confirmacao do desligamento');
    Check(S.Completed = S.Count, 'desligamento nao reduz progresso do programa');
    N := F.Sent.Count;
    S.Tick;
    Check(F.Sent.Count = N, 'M5 enviado uma unica vez enquanto aguarda resposta');
    if FirmwareError then
    begin
      F.Reply('error:20' + #10);
      S.Tick;
      Check(S.State = ssError, 'M5 recusado nao aparece como concluido');
      Check(Pos('error:20', S.LastError) > 0, 'erro do desligamento informado');
      Check(Pos(#24, F.Realtime) = 0, 'M5 recusado nao dispara reset automatico');
      Exit;
    end;
    if Kind = mtLaser then
    begin
      Check(F.Sent[N - 2] = 'M5', 'laser desliga antes do ar');
      Check(F.Sent[N - 1] = 'M9', 'desliga ar assistido ao terminar');
      F.Ack(1); S.Tick;
      Check(S.State = ssRunning, 'aguarda tambem confirmacao do ar assistido');
    end;
    F.Ack(100); S.Tick;
    Check(S.State = ssDone, 'conclui apos confirmar desligamento');
    Check(S.Completed = S.Count, 'progresso final preservado');
    S.Tick;
    Check(F.Sent.Count = N, 'nao repete desligamento depois de concluir');
  finally
    S.Free; L.Free; DeleteFile(FN);
  end;
end;

procedure TestNoHomingProfileProgram;
var S: TSimulationSession; F: TFakeController; L: TStringList; FN: string;
begin
  FN := GetTempFileName(GetTempDir, 'hom');
  L := TStringList.Create;
  S := TSimulationSession.Create;
  try
    L.Add('; MultiCNC public test model - CC0-1.0');
    L.Add('M3 S8000');
    L.Add('$H ; home');
    L.Add('G1 X20 F900');
    L.SaveToFile(FN);
    S.LoadFile(FN);
    Check(S.Count = 3, 'comentario de cabecalho nao e comando');
    F := TFakeController.Create;
    Check(S.ConnectTransport(mtRouter, pkGRBL, F, F), 'conectar perfil TTC3018');
    S.PhysicalHomingAllowed := False;
    Check(not S.Start, 'perfil sem homing rejeita arquivo com $H');
    Check(Pos('Comando 2 ($H)', S.LastError) > 0, 'identifica comando real sem contar comentario');
    Check(F.Sent.Count = 0, 'nenhum spindle ou movimento enviado antes da validacao');
    Check(Pos(#24, F.Realtime) = 0, 'validacao nao reinicia a maquina');
  finally
    S.Free; L.Free; DeleteFile(FN);
  end;
end;

procedure TestSessionRejectsBadProgram;
var S: TSimulationSession; F: TFakeController; L: TStringList; FN: string;
begin
  FN := GetTempFileName(GetTempDir, 'job');
  L := TStringList.Create;
  S := TSimulationSession.Create;
  try
    L.Add('G1 X1 F100'); L.Add('G1 X10,5 F100'); L.Add('G1 X3 F100');
    L.SaveToFile(FN);
    S.LoadFile(FN);
    F := TFakeController.Create;
    S.ConnectTransport(mtRouter, pkGRBL, F, F);
    S.Start;
    Check(S.State = ssError, 'linha com virgula decimal interrompe o programa');
    Check(Pos('Linha 2', S.LastError) > 0, 'numero da linha informado: ' + S.LastError);
    Check(F.Sent.IndexOf('G1 X3 F100') < 0, 'linhas posteriores nao enviadas');
  finally
    S.Free; L.Free; DeleteFile(FN);
  end;
end;

begin
  DefaultFormatSettings.DecimalSeparator := ','; { Windows pt-BR }
  TestGRBLCharacterCounting;
  TestGRBLErrorStopsQueue;
  TestGRBLAlarmAndStatus;
  TestSafetyValidation;
  TestGRBLStopIsImmediate;
  TestMarlin;
  TestJogUsesDecimalPoint;
  TestMoveTo;
  TestConsoleLog;
  TestSessionJob;
  TestSessionEndCommands(mtRouter, False, False);
  TestSessionEndCommands(mtRouter, True, False);
  TestSessionEndCommands(mtRouter, False, True);
  TestSessionEndCommands(mtLaser, False, False);
  TestSessionEndCommands(mtPrinter3D, False, False);
  TestNoHomingProfileProgram;
  TestSessionRejectsBadProgram;
  if Failures > 0 then begin Writeln(Failures, ' falha(s)'); Halt(1); end;
  Writeln('PASS: controle de fluxo, erros, alarmes, estado, seguranca e parada');
end.
