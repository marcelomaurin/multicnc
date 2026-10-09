unit multicnc_session;

{ Sessao de operacao: conecta a maquina (serial, TCP ou transporte injetado),
  executa o programa carregado com controle de fluxo e acompanha erros e
  alarmes do firmware. O envio do programa respeita a confirmacao ("ok") de
  cada linha; qualquer "error:" ou alarme interrompe o programa. }

{$mode objfpc}{$H+}

interface

uses Classes, SysUtils, multicnc_types, multicnc_interfaces, multicnc_machine,
  multicnc_gcode_analyzer, multicnc_laser_config,
  multicnc_simulator, multicnc_chatgpt_serial, multicnc_tcp_transport,
  multicnc_grbl, multicnc_marlin;

const
  { Linhas mantidas na fila do host alem das que estao na controladora. }
  JobLookahead = 8;
  StatusPollMS = 250;

type
  TSessionState = (ssDisconnected, ssIdle, ssRunning, ssPaused, ssDone, ssStopped, ssError);
  TProtocolKind = (pkGRBL, pkMarlin);

  { Nome mantido por compatibilidade: a sessao opera maquinas reais. }
  TSimulationSession = class
  private
    FTransport: IMultiCNCTransport;
    FTransportObject: TObject;
    FProtocol: TObject;
    FProtocolKind: TProtocolKind;
    FMachine: TMultiCNCMachine;
    FLines, FLoadedLines, FOriginalLines: TStringList;
    FBounds: TGCodeBounds;
    FLaserSettings: TLaserSettings;
    FMachineKind: TMachineType;
    FFramingActive: Boolean;
    FIndex: Integer;          { proxima linha do programa a enfileirar }
    FState: TSessionState;
    FFileName: string;
    FOnLog: TTransportDataEvent;
    FLastError: string;
    FErrorBase, FAlarmBase: Integer;
    FLastPoll: QWord;
    FLastTempQuery: QWord;
    FConnectedAt, FLastRxAt: QWord;
    FSilenceWarned: Boolean;
    FPhysicalHomingAllowed: Boolean;
    FRequireGrblReply, FGrblProbeLogged, FGrblConfirmedLogged: Boolean;
    FMarlinReadyAt: QWord;
    FMarlinHandshakeSent: Boolean;
    FEnvelopeX, FEnvelopeY, FEnvelopeZ: Double;
    procedure SerialTX(Sender: TObject; const AData: string);
    procedure CheckControllerSilence(ANow: QWord);
    procedure Diag(const AText: string);
    procedure Receive(const Data: string);
    procedure ReleaseConnection;
    procedure CheckFirmwareFaults;
    procedure FeedJob;
    function GetConnected: Boolean;
    function GetCount: Integer;
    function GetCompleted: Integer;
    function GetMachineState: TMachineState;
    function GetPosition: TMachinePosition;
    function GetTemperatures: TPrinterTemperatures;
    function GetHomePosition: TMachinePosition;
    function GetHomePositionSet: Boolean;
    function GetControllerReady: Boolean;
    function Fail(const Reason: string): Boolean;
    procedure RequestPositionAfterMotion;
  public
    constructor Create;
    destructor Destroy; override;
    function Connect(Kind: TMachineType; ProtocolKind: TProtocolKind; const Device: string; BaudRate: Integer): Boolean;
    { Conecta usando um transporte ja criado (testes, simuladores). A sessao
      passa a ser dona de ATransportObject. }
    function ConnectTransport(Kind: TMachineType; ProtocolKind: TProtocolKind;
      ATransportObject: TObject; const ATransport: IMultiCNCTransport;
      RequireGrblReply: Boolean = False): Boolean;
    procedure Disconnect;
    procedure LoadFile(const FileName: string);
    function Start: Boolean;
    function RunFraming(const AFramingLines: TStrings): Boolean;
    procedure Tick;
    procedure Poll;
    function Pause: Boolean;
    function Resume: Boolean;
    function Stop: Boolean;
    function Home(AFeed: Double = 0): Boolean;
    function SetHome(out AHomePos: TMachinePosition): Boolean;
    function PhysicalHoming: Boolean;
    function SetFeedRate(AFeed: Double): Boolean;
    function Zero: Boolean;
    function Status: Boolean;
    function Unlock: Boolean;
    function Jog(Axis: TAxis; Distance, Feed: Double): Boolean;
    { Movimento absoluto ate X/Y/Z (mm), validado contra o curso da maquina. }
    function MoveTo(X, Y, Z, Feed: Double): Boolean;
    function Send(const Line: string): Boolean;
    function SupportsAxis(Axis: TAxis): Boolean;
    function ProgramText: string;
    { Curso util por eixo (mm), aplicado ao jog; 0 = desconhecido. }
    procedure SetWorkEnvelope(X, Y, Z: Double);
    procedure SetThermalLimits(AMaxHotend, AMaxBed: Integer);
    property Connected: Boolean read GetConnected;
    property ControllerReady: Boolean read GetControllerReady;
    property State: TSessionState read FState;
    { Linhas do programa confirmadas pela controladora. }
    property Completed: Integer read GetCompleted;
    property Count: Integer read GetCount;
    property FileName: string read FFileName;
    property MachineState: TMachineState read GetMachineState;
    property Position: TMachinePosition read GetPosition;
    property Bounds: TGCodeBounds read FBounds;
    property LaserSettings: TLaserSettings read FLaserSettings write FLaserSettings;
    property Temperatures: TPrinterTemperatures read GetTemperatures;
    function QueryTemperatures: Boolean;
    function SetHotendTemperature(ATemp: Double): Boolean;
    function SetBedTemperature(ATemp: Double): Boolean;
    property PhysicalHomingAllowed: Boolean read FPhysicalHomingAllowed write FPhysicalHomingAllowed;
    property EnvelopeX: Double read FEnvelopeX;
    property EnvelopeY: Double read FEnvelopeY;
    property EnvelopeZ: Double read FEnvelopeZ;
    property FramingActive: Boolean read FFramingActive;
    property MachineType: TMachineType read FMachineKind;
    property HomePosition: TMachinePosition read GetHomePosition;
    property HomePositionSet: Boolean read GetHomePositionSet;
    property LastError: string read FLastError;
    property OnLog: TTransportDataEvent read FOnLog write FOnLog;
  end;

implementation

constructor TSimulationSession.Create;
begin
  inherited Create;
  FLines := TStringList.Create;
  FLoadedLines := TStringList.Create;
  FOriginalLines := TStringList.Create;
  FBounds := TGCodeAnalyzer.EmptyBounds;
  FLaserSettings := DefaultLaserSettings;
  FFramingActive := False;
  FMarlinReadyAt := 0;
  FMarlinHandshakeSent := False;
  FState := ssDisconnected;
  FPhysicalHomingAllowed := True;
end;

destructor TSimulationSession.Destroy;
begin
  ReleaseConnection;
  FLines.Free;
  FLoadedLines.Free;
  FOriginalLines.Free;
  inherited Destroy;
end;

{ Marlin nao envia posicao sozinho: depois de cada movimento manual pede um
  M114 (enfileirado, sai apos o "ok" do movimento) para atualizar o DRO. }
procedure TSimulationSession.RequestPositionAfterMotion;
begin
  if (FProtocolKind = pkMarlin) and Assigned(FMachine) then
    FMachine.Status;
end;

function TSimulationSession.Fail(const Reason: string): Boolean;
begin
  FLastError := Reason;
  Result := False;
end;

{ Resposta ao M105 periodico ("ok T:200.0 /200.0 B:60.0 /60.0"): o valor ja
  aparece no painel de temperaturas, nao precisa repetir no console. }
function IsTemperatureReport(const ALine: string): Boolean;
var L: string;
begin
  L := LowerCase(ALine);
  if Copy(L, 1, 3) = 'ok ' then L := TrimLeft(Copy(L, 4, MaxInt));
  Result := (Copy(L, 1, 2) = 't:') and ((Pos('b:', L) > 0) or (Pos('/', L) > 0));
end;

procedure TSimulationSession.Diag(const AText: string);
begin
  if Assigned(FOnLog) then FOnLog('[MultiCNC] ' + AText);
end;

{ Linhas enviadas a controladora aparecem no console como "TX". As consultas
  periodicas (status GRBL e temperatura Marlin) ficam de fora para nao poluir. }
procedure TSimulationSession.SerialTX(Sender: TObject; const AData: string);
var Lines: TStringList; I: Integer; L, Shown: string;
begin
  if not Assigned(FOnLog) then Exit;
  Lines := TStringList.Create;
  try
    Lines.Text := AData;
    Shown := '';
    for I := 0 to Lines.Count - 1 do
    begin
      L := Trim(Lines[I]);
      if (L = '') or (L = '?') or SameText(L, 'M105') then Continue;
      if (Length(L) = 1) and (Ord(L[1]) < 32) then L := Format('<0x%.2x>', [Ord(L[1])]);
      Shown := Shown + 'TX  ' + L + LineEnding;
    end;
  finally
    Lines.Free;
  end;
  if Shown <> '' then FOnLog(Shown);
end;

procedure TSimulationSession.CheckControllerSilence(ANow: QWord);
var StartAt: QWord;
begin
  if FSilenceWarned or not Connected then Exit;
  if (FLastRxAt <> 0) and (not FRequireGrblReply or FMachine.HasControllerReply) then Exit;
  if FProtocolKind = pkMarlin then
  begin
    if FMarlinReadyAt = 0 then Exit;
    if (FMachineKind = mtPrinter3D) and not FMarlinHandshakeSent then Exit;
    StartAt := FMarlinReadyAt;
  end
  else begin
    StartAt := FConnectedAt;
    if FRequireGrblReply then Inc(StartAt, 2000);
  end;
  if ANow < StartAt + 5000 then Exit;
  FSilenceWarned := True;
  if (FProtocolKind = pkMarlin) and (FMachineKind <> mtPrinter3D) then
    Diag('No reply from the CNC controller after connecting. Marlin is selected; ' +
      'for a GRBL router select GRBL. No printer handshake was sent.')
  else if FProtocolKind = pkMarlin then
    Diag('No reply from the controller 5 s after M115. Port opened, but nothing came back: ' +
      'check the baud rate (Creality/Ender stock firmware: 115200; some boards use 250000), ' +
      'that this COM port is the printer, and that Protocol is Marlin.')
  else
    Diag('No recognized GRBL reply after status queries (no GRBL banner or status). ' +
      'Check the baud rate (GRBL 1.1: 115200), that this COM port is the machine, ' +
      'and that Protocol is GRBL.');
end;

procedure TSimulationSession.Receive(const Data: string);
var Lines: TStringList; I: Integer; Shown: string; FirstReply: Boolean;
begin
  FirstReply := FLastRxAt = 0;
  if FRequireGrblReply and FMachine.HasControllerReply and not FGrblConfirmedLogged then begin
    FGrblConfirmedLogged := True;
    FirstReply := True;
    Diag('Resposta GRBL reconhecida. Comunicacao com a controladora confirmada.');
  end;
  FLastRxAt := GetTickCount64;
  if not Assigned(FOnLog) then Exit;
  { Relatorios de estado periodicos do GRBL nao poluem o console. }
  Lines := TStringList.Create;
  try
    Lines.Text := Data;
    Shown := '';
    for I := 0 to Lines.Count - 1 do
      if (Trim(Lines[I]) <> '') and (FirstReply or
         ((Copy(Trim(Lines[I]), 1, 1) <> '<') and not IsTemperatureReport(Trim(Lines[I])))) then
        Shown := Shown + 'RX  ' + Trim(Lines[I]) + LineEnding;
  finally
    Lines.Free;
  end;
  if Shown <> '' then FOnLog(Shown);
end;

procedure TSimulationSession.ReleaseConnection;
begin
  if Assigned(FMachine) then
  begin
    FMachine.OnData := nil;
    FMachine.Disconnect;
  end;
  FreeAndNil(FMachine);
  FreeAndNil(FProtocol);
  FTransport := nil;
  FreeAndNil(FTransportObject);
end;

function TSimulationSession.Connect(Kind: TMachineType; ProtocolKind: TProtocolKind; const Device: string; BaudRate: Integer): Boolean;
var Serial: TChatGPTSerialTransport; TCP: TTCPTransport;
begin
  if Connected then Exit(Fail('Ja conectado'));
  if Pos(':', Device) > 0 then
  begin
    TCP := TTCPTransport.Create(Device);
    Result := ConnectTransport(Kind, ProtocolKind, TCP, TCP);
  end
  else
  begin
    Serial := TChatGPTSerialTransport.Create(Device, BaudRate);
    Serial.Serial.OnTXSend := @SerialTX;
    Result := ConnectTransport(Kind, ProtocolKind, Serial, Serial, ProtocolKind = pkGRBL);
    { O transporte continua vivo ate a proxima conexao: traz o motivo real. }
    if not Result and (Serial.LastError <> '') then
      FLastError := Serial.LastError;
  end;
end;

function TSimulationSession.ConnectTransport(Kind: TMachineType; ProtocolKind: TProtocolKind;
  ATransportObject: TObject; const ATransport: IMultiCNCTransport;
  RequireGrblReply: Boolean): Boolean;
var Protocol: IMultiCNCProtocol;
begin
  Result := False;
  if Connected then
  begin
    ATransportObject.Free;
    Exit(Fail('Ja conectado'));
  end;
  ReleaseConnection;
  FTransportObject := ATransportObject;
  FTransport := ATransport;
  FProtocolKind := ProtocolKind;
  FRequireGrblReply := RequireGrblReply and (ProtocolKind = pkGRBL);
  FGrblProbeLogged := False;
  FGrblConfirmedLogged := False;
  FMachineKind := Kind;
  if ProtocolKind = pkMarlin then
  begin
    FProtocol := TMarlinProtocol.Create;
    Protocol := TMarlinProtocol(FProtocol);
  end
  else
  begin
    FProtocol := TGRBLProtocol.Create;
    Protocol := TGRBLProtocol(FProtocol);
  end;
  FMachine := TMultiCNCMachine.Create(Kind, FTransport, Protocol);
  FMachine.SetWorkEnvelope(FEnvelopeX, FEnvelopeY, FEnvelopeZ);
  FMachine.OnData := @Receive;
  FErrorBase := 0;
  FAlarmBase := 0;
  FLastError := '';
  FLastTempQuery := 0;
  FLastPoll := 0;
  FConnectedAt := GetTickCount64;
  FLastRxAt := 0;
  FSilenceWarned := False;
  FMarlinHandshakeSent := False;
  FMarlinReadyAt := 0;
  Result := FMachine.Connect;
  if Result then
  begin
    FState := ssIdle;
    { Muitas placas Marlin reiniciam ao abrir a serial. Aguarda o boot antes
      de enviar o primeiro comando; GRBL continua imediato. }
    if ProtocolKind = pkMarlin then
      FMarlinReadyAt := GetTickCount64 + 2500;
    if FRequireGrblReply then begin
      if not FTransport.Send(#13#10#13#10) then
        Diag('Falha ao enviar a inicializacao GRBL.');
      Diag('GRBL: inicializacao enviada (CR/LF). Aguardando boot e resposta de estado.');
    end;
  end
  else
  begin
    FState := ssError;
    FLastError := 'Failed to open connection';
  end;
end;

procedure TSimulationSession.Disconnect;
begin
  if FState in [ssRunning, ssPaused] then Stop;
  ReleaseConnection;
  FState := ssDisconnected;
end;

function TSimulationSession.GetConnected: Boolean;
begin
  Result := Assigned(FTransport) and FTransport.IsConnected;
end;

function TSimulationSession.GetControllerReady: Boolean;
begin
  Result := Connected;
  if Result and FRequireGrblReply then Result := FMachine.HasControllerReply;
  if Result and (FProtocolKind = pkMarlin) then
    Result := (FMarlinReadyAt = 0) or (GetTickCount64 >= FMarlinReadyAt);
end;

function TSimulationSession.GetCount: Integer;
begin
  if FLoadedLines.Count > 0 then
    Result := FLoadedLines.Count
  else
    Result := FLines.Count;
end;

function TSimulationSession.GetCompleted: Integer;
begin
  Result := FIndex;
  if (FState in [ssRunning, ssPaused]) and Assigned(FMachine) then
    Dec(Result, FMachine.PendingLines);
  if Result < 0 then Result := 0;
end;

function TSimulationSession.GetMachineState: TMachineState;
begin
  if Assigned(FMachine) then Result := FMachine.GetState else Result := msDisconnected;
end;

function TSimulationSession.GetPosition: TMachinePosition;
begin
  if Assigned(FMachine) then Result := FMachine.GetPosition else Result := EmptyPosition;
end;

procedure TSimulationSession.SetWorkEnvelope(X, Y, Z: Double);
begin
  FEnvelopeX := X; FEnvelopeY := Y; FEnvelopeZ := Z;
  if Assigned(FMachine) then FMachine.SetWorkEnvelope(X, Y, Z);
end;

procedure TSimulationSession.SetThermalLimits(AMaxHotend, AMaxBed: Integer);
begin
  if Assigned(FMachine) then FMachine.SetThermalLimits(AMaxHotend, AMaxBed);
end;

procedure TSimulationSession.LoadFile(const FileName: string);
var Source, Commands: TStringList; Stream: TFileStream; I: Integer; Line: string;
begin
  if FState in [ssRunning, ssPaused] then
    raise Exception.Create('Stop program before opening another file.');
  Source := TStringList.Create;
  Commands := TStringList.Create;
  try
    Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
    try
      if Stream.Size > 5 * 1024 * 1024 then
        raise Exception.Create('The file exceeds the 5 MB limit.');
      Source.LoadFromStream(Stream);
    finally
      Stream.Free;
    end;
    for I := 0 to Source.Count - 1 do begin
      Line := Trim(Source[I]);
      if (Line = '') or (Line[1] = ';') or (Line = '%') then Continue;
      if (Line[1] = '(') and (Line[Length(Line)] = ')') then Continue;
      Commands.Add(Line);
    end;
    if Commands.Count = 0 then raise Exception.Create('The file contains no commands.');
    FOriginalLines.Assign(Source);
    FLoadedLines.Assign(Commands);
    FLines.Assign(Commands);
    TGCodeAnalyzer.Analyze(Commands, FBounds);
    FFileName := FileName;
    FIndex := 0;
    FFramingActive := False;
    if Connected then FState := ssIdle else FState := ssDisconnected;
  finally
    Source.Free;
    Commands.Free;
  end;
end;

function TSimulationSession.RunFraming(const AFramingLines: TStrings): Boolean;
begin
  if FRequireGrblReply and not ControllerReady then
    Exit(Fail('Aguarde a resposta GRBL antes de enviar comandos.'));
  if not Connected then Exit(Fail('Machine disconnected'));
  if (AFramingLines = nil) or (AFramingLines.Count = 0) then Exit(Fail('No framing path available'));
  if FState in [ssRunning, ssPaused] then Exit(Fail('Machine is busy with another program'));
  if FMachine.GetState in [msAlarm, msError] then
    Exit(Fail('Machine in alarm: unlock or home before starting'));
  if FMachine.PendingLines > 0 then
    Exit(Fail('Aguarde a controladora concluir os comandos pendentes'));

  FFramingActive := True;
  FLines.Assign(AFramingLines);
  FIndex := 0;
  FErrorBase := FMachine.ErrorCount;
  FAlarmBase := FMachine.AlarmCount;
  FLastError := '';
  FState := ssRunning;
  if Assigned(FOnLog) then FOnLog('Iniciando contorno (framing)...');
  FeedJob;
  Result := FState in [ssRunning, ssIdle, ssDone];
end;

function TSimulationSession.Start: Boolean;
var Transformed: TStringList;
begin
  if not Connected then Exit(Fail('Machine disconnected'));
  if not ControllerReady then Exit(Fail('Aguarde a resposta e inicializacao da controladora'));
  if FLoadedLines.Count = 0 then Exit(Fail('No program loaded'));
  if FState in [ssRunning, ssPaused] then Exit(Fail('Program is already running'));
  if FMachine.GetState in [msAlarm, msError] then
    Exit(Fail('Machine in alarm: unlock or home before starting'));
  if FMachine.PendingLines > 0 then
    Exit(Fail('Aguarde a controladora concluir os comandos pendentes'));

  FFramingActive := False;
  if FMachineKind = mtLaser then
  begin
    Transformed := TransformGCodeForLaser(FLoadedLines, FLaserSettings);
    try
      FLines.Assign(Transformed);
    finally
      Transformed.Free;
    end;
    if FLaserSettings.AirAssist and (Trim(FLaserSettings.AirAssistOnCmd) <> '') then
      FMachine.SendGCode(Trim(FLaserSettings.AirAssistOnCmd));
  end
  else
    FLines.Assign(FLoadedLines);

  FIndex := 0;
  FErrorBase := FMachine.ErrorCount;
  FAlarmBase := FMachine.AlarmCount;
  FLastError := '';
  FState := ssRunning;
  FeedJob;
  Result := FState in [ssRunning, ssDone];
end;

procedure TSimulationSession.CheckFirmwareFaults;
begin
  if not (FState in [ssRunning, ssPaused]) or not Assigned(FMachine) then Exit;
  if FMachine.AlarmCount <> FAlarmBase then
  begin
    FMachine.ClearQueue;
    FState := ssError;
    FLastError := 'Alarme da controladora: ' + FMachine.LastError;
  end
  else if FMachine.ErrorCount <> FErrorBase then
  begin
    FMachine.ClearQueue;
    FState := ssError;
    FLastError := 'Erro da controladora: ' + FMachine.LastError;
  end;
end;

procedure TSimulationSession.FeedJob;
begin
  CheckFirmwareFaults;
  if FState <> ssRunning then Exit;
  while (FIndex < Count) and (FMachine.QueuedLines < JobLookahead) do
  begin
    if not FMachine.SendGCode(FLines[FIndex]) then
    begin
      FMachine.ClearQueue;
      FState := ssError;
      FLastError := Format('Linha %d recusada: %s', [FIndex + 1, FMachine.LastError]);
      Exit;
    end;
    Inc(FIndex);
  end;
  CheckFirmwareFaults;
  if (FState = ssRunning) and (FIndex >= Count) and (FMachine.PendingLines = 0) then
  begin
        if FFramingActive then
    begin
      FLines.Assign(FLoadedLines);
      FIndex := 0;
      FFramingActive := False;
      FState := ssIdle;
      if Assigned(FOnLog) then FOnLog('Contorno (framing) concluido.');
    end
    else
    begin
      if (FMachineKind = mtLaser) and Assigned(FMachine) then
      begin
        FMachine.SendGCode('M5');
        if FLaserSettings.AirAssist and (Trim(FLaserSettings.AirAssistOffCmd) <> '') then
          FMachine.SendGCode(Trim(FLaserSettings.AirAssistOffCmd));
      end;
      FState := ssDone;
    end;
  end;
end;

procedure TSimulationSession.Poll;
var Now64: QWord;
begin
  if not Assigned(FTransport) then Exit;
  FTransport.Poll;
  if not FTransport.IsConnected then begin
    if FTransportObject is TChatGPTSerialTransport then begin
      FLastError := TChatGPTSerialTransport(FTransportObject).LastError;
      if FLastError <> '' then Diag(FLastError);
    end;
    FState := ssError; Exit;
  end;
  CheckControllerSilence(GetTickCount64);
  { GRBL: '?' e de tempo real e nao ocupa o buffer. }
  if (FProtocolKind = pkGRBL) and Connected then
  begin
    Now64 := GetTickCount64;
    if FRequireGrblReply and (Now64 < FConnectedAt + 2000) then Exit;
    if FRequireGrblReply and not FGrblProbeLogged then begin
      FGrblProbeLogged := True;
      Diag('GRBL TX ? (consulta de estado, sem movimento).');
    end;
    if Now64 - FLastPoll >= StatusPollMS then
    begin
      FLastPoll := Now64;
      FMachine.Status;
    end;
  end;

  { Marlin: diversas placas Arduino/RAMPS/Creality reiniciam quando a porta
    serial e aberta. Nao envie G-code durante esse boot. Depois da janela de
    inicializacao, faz uma identificacao M115 fora da fila e passa a consultar
    temperaturas somente quando nao ha outro comando pendente. }
  if (FMachineKind = mtPrinter3D) and (FProtocolKind = pkMarlin) and
     Connected and Assigned(FMachine) then
  begin
    Now64 := GetTickCount64;
    if not ControllerReady then Exit;

    if not FMarlinHandshakeSent then
    begin
      FMarlinHandshakeSent := FTransport.Send('M115' + #10);
      FLastTempQuery := Now64;
      Exit;
    end;

    if (Now64 - FLastTempQuery >= 1000) and (FMachine.PendingLines = 0) then
    begin
      FLastTempQuery := Now64;
      FMachine.QueryTemperatures;
    end;
  end;
end;

procedure TSimulationSession.Tick;
begin
  if not (FState in [ssRunning, ssPaused]) then Exit;
  if not Connected then
  begin
    FState := ssError;
    FLastError := 'Connection lost while program was running';
    Exit;
  end;
  if FState = ssRunning then FeedJob else CheckFirmwareFaults;
end;

function TSimulationSession.Pause: Boolean;
begin
  if not (Connected and (FState = ssRunning)) then Exit(Fail('Nada em execucao'));
  Result := FMachine.Pause;
  if Result then
  begin
    FState := ssPaused;
    if (FMachineKind = mtLaser) and Assigned(FMachine) then
    begin
      FMachine.SendGCode('M5');
      if FLaserSettings.AirAssist and (Trim(FLaserSettings.AirAssistOffCmd) <> '') then
        FMachine.SendGCode(Trim(FLaserSettings.AirAssistOffCmd));
    end;
  end
  else FLastError := FMachine.LastError;
end;

function TSimulationSession.Resume: Boolean;
begin
  if not (Connected and (FState = ssPaused)) then Exit(Fail('Program is not paused'));
  Result := FMachine.Resume;
  if Result then
  begin
    if (FMachineKind = mtLaser) and Assigned(FMachine) then
    begin
      if FLaserSettings.AirAssist and (Trim(FLaserSettings.AirAssistOnCmd) <> '') then
        FMachine.SendGCode(Trim(FLaserSettings.AirAssistOnCmd));
    end;
    FState := ssRunning;
  end
  else FLastError := FMachine.LastError;
end;

function TSimulationSession.Stop: Boolean;
begin
  if not Connected then Exit(Fail('Machine disconnected'));
  Result := FMachine.Stop;
  if FFramingActive then
  begin
    FLines.Assign(FLoadedLines);
    FIndex := 0;
    FFramingActive := False;
  end;
  if (FMachineKind = mtLaser) and Assigned(FMachine) then
  begin
    FMachine.SendGCode('M5');
    if FLaserSettings.AirAssist and (Trim(FLaserSettings.AirAssistOffCmd) <> '') then
      FMachine.SendGCode(Trim(FLaserSettings.AirAssistOffCmd));
  end;
  if Result then FState := ssStopped
  else
  begin
    FState := ssError;
    FLastError := FMachine.LastError;
  end;
end;

function TSimulationSession.GetHomePosition: TMachinePosition;
begin
  if Assigned(FMachine) then Result := FMachine.GetHomePosition else Result := EmptyPosition;
end;

function TSimulationSession.GetHomePositionSet: Boolean;
begin
  if Assigned(FMachine) then Result := FMachine.IsHomePositionSet else Result := False;
end;

function TSimulationSession.SetHome(out AHomePos: TMachinePosition): Boolean;
begin
  AHomePos := EmptyPosition;
  if FRequireGrblReply and not ControllerReady then
    Exit(Fail('Aguarde a resposta GRBL antes de enviar comandos.'));
  if not Connected or (FState in [ssRunning, ssPaused]) then Exit(Fail('Unavailable while program is running'));
  Result := FMachine.SetHome(AHomePos);
  if not Result then FLastError := FMachine.LastError;
end;

function TSimulationSession.PhysicalHoming: Boolean;
begin
  if not FPhysicalHomingAllowed then
    Exit(Fail('Este perfil nao possui homing fisico. Defina a origem manualmente.'));
  if FRequireGrblReply and not ControllerReady then
    Exit(Fail('Aguarde a resposta GRBL antes de enviar comandos.'));
  if not Connected or (FState in [ssRunning, ssPaused]) then Exit(Fail('Unavailable while program is running'));
  Result := FMachine.PhysicalHoming;
  if Result then RequestPositionAfterMotion
  else FLastError := FMachine.LastError;
end;

function TSimulationSession.Home(AFeed: Double = 0): Boolean;
begin
  if not FPhysicalHomingAllowed and not HomePositionSet then
    Exit(Fail('Defina uma referencia manual antes de retornar a ela.'));
  if FRequireGrblReply and not ControllerReady then
    Exit(Fail('Aguarde a resposta GRBL antes de enviar comandos.'));
  if not Connected or (FState in [ssRunning, ssPaused]) then Exit(Fail('Unavailable while program is running'));
  Result := FMachine.Home(AFeed);
  if Result then RequestPositionAfterMotion
  else FLastError := FMachine.LastError;
end;

function TSimulationSession.SetFeedRate(AFeed: Double): Boolean;
begin
  if FRequireGrblReply and not ControllerReady then
    Exit(Fail('Aguarde a resposta GRBL antes de enviar comandos.'));
  if not Connected or (FState in [ssRunning, ssPaused]) then Exit(Fail('Unavailable while program is running'));
  Result := FMachine.SetFeedRate(AFeed);
  if not Result then FLastError := FMachine.LastError;
end;

function TSimulationSession.Zero: Boolean;
begin
  if FRequireGrblReply and not ControllerReady then
    Exit(Fail('Aguarde a resposta GRBL antes de enviar comandos.'));
  if not Connected or (FState in [ssRunning, ssPaused]) then Exit(Fail('Unavailable while program is running'));
  if Assigned(FMachine) and (FMachine.GetMachineType = mtPrinter3D) then
    Exit(Fail('Referenciamento de zero indisponivel para impressora 3D'));
  Result := FMachine.Zero;
  if not Result then FLastError := FMachine.LastError;
end;

function TSimulationSession.Status: Boolean;
begin
  Result := Connected and FMachine.Status;
  if not Result then FLastError := 'Failed to query machine state';
end;

function TSimulationSession.Unlock: Boolean;
begin
  if FRequireGrblReply and not ControllerReady then
    Exit(Fail('Aguarde a resposta GRBL antes de enviar comandos.'));
  if not Connected or (FState in [ssRunning, ssPaused]) then Exit(Fail('Unavailable while program is running'));
  Result := FMachine.Unlock;
  if Result then
  begin
    if FState = ssError then FState := ssIdle;
  end
  else FLastError := FMachine.LastError;
end;

function TSimulationSession.SupportsAxis(Axis: TAxis): Boolean;
begin
  Result := Connected;
  if Result then Result := Axis in FMachine.GetCapabilities.Axes;
end;

function TSimulationSession.Jog(Axis: TAxis; Distance, Feed: Double): Boolean;
begin
  if not ControllerReady then Exit(Fail('Aguarde a resposta e inicializacao da controladora'));
  if not SupportsAxis(Axis) then Exit(Fail('Eixo indisponivel'));
  if FState in [ssRunning, ssPaused] then Exit(Fail('Unavailable while program is running'));
  if not ((Abs(Distance) > 0) and (Abs(Distance) <= 100) and (Feed >= 1) and (Feed <= 10000)) then
    Exit(Fail('Passo ou avanco fora dos limites (0-100 mm, 1-10000 mm/min)'));
  Result := FMachine.Jog(Axis, Distance, Feed);
  if Result then RequestPositionAfterMotion
  else FLastError := FMachine.LastError;
end;

function TSimulationSession.MoveTo(X, Y, Z, Feed: Double): Boolean;
begin
  if not Connected then Exit(Fail('Maquina desconectada'));
  if not ControllerReady then Exit(Fail('Aguarde a resposta e inicializacao da controladora'));
  if FState in [ssRunning, ssPaused] then Exit(Fail('Unavailable while program is running'));
  if not ((Feed >= 1) and (Feed <= 10000)) then
    Exit(Fail('Avanco fora dos limites (1-10000 mm/min)'));
  Result := FMachine.MoveTo(X, Y, Z, Feed);
  if Result then RequestPositionAfterMotion
  else FLastError := FMachine.LastError;
end;

function TSimulationSession.Send(const Line: string): Boolean;
begin
  if not FPhysicalHomingAllowed and SameText(Trim(Line), '$H') then
    Exit(Fail('Este perfil nao possui homing fisico.'));
  if not Connected or (FState in [ssRunning, ssPaused]) then Exit(Fail('Unavailable while program is running'));
  if not ControllerReady then Exit(Fail('Aguarde a resposta e inicializacao da controladora'));
  if (Trim(Line) = '') or (Pos(#10, Line) > 0) or (Pos(#13, Line) > 0) then
    Exit(Fail('Informe um unico comando'));
  Result := FMachine.SendGCode(Line);
  if not Result then FLastError := FMachine.LastError;
end;

function TSimulationSession.ProgramText: string;
begin
  Result := FOriginalLines.Text;
end;

function TSimulationSession.GetTemperatures: TPrinterTemperatures;
begin
  if Assigned(FMachine) then Result := FMachine.GetTemperatures
  else Result := EmptyTemperatures;
end;

function TSimulationSession.QueryTemperatures: Boolean;
begin
  if not ControllerReady then Exit(False);
  if Assigned(FMachine) then Result := FMachine.QueryTemperatures
  else Result := False;
end;

function TSimulationSession.SetHotendTemperature(ATemp: Double): Boolean;
begin
  if not ControllerReady then Exit(Fail('Aguarde a resposta e inicializacao da controladora'));
  if Assigned(FMachine) then Result := FMachine.SetHotendTemperature(ATemp)
  else Result := False;
end;

function TSimulationSession.SetBedTemperature(ATemp: Double): Boolean;
begin
  if not ControllerReady then Exit(Fail('Aguarde a resposta e inicializacao da controladora'));
  if Assigned(FMachine) then Result := FMachine.SetBedTemperature(ATemp)
  else Result := False;
end;

end.
