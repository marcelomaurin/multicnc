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
    FEnvelopeX, FEnvelopeY, FEnvelopeZ: Double;
    procedure Receive(const Data: string);
    procedure ReleaseConnection;
    procedure CheckFirmwareFaults;
    procedure FeedJob;
    function GetConnected: Boolean;
    function GetCount: Integer;
    function GetCompleted: Integer;
    function GetMachineState: TMachineState;
    function GetPosition: TMachinePosition;
    function GetHomePosition: TMachinePosition;
    function GetHomePositionSet: Boolean;
    function Fail(const Reason: string): Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    function Connect(Kind: TMachineType; ProtocolKind: TProtocolKind; const Device: string; BaudRate: Integer): Boolean;
    { Conecta usando um transporte ja criado (testes, simuladores). A sessao
      passa a ser dona de ATransportObject. }
    function ConnectTransport(Kind: TMachineType; ProtocolKind: TProtocolKind;
      ATransportObject: TObject; const ATransport: IMultiCNCTransport): Boolean;
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
    function Send(const Line: string): Boolean;
    function SupportsAxis(Axis: TAxis): Boolean;
    function ProgramText: string;
    { Curso util por eixo (mm), aplicado ao jog; 0 = desconhecido. }
    procedure SetWorkEnvelope(X, Y, Z: Double);
    property Connected: Boolean read GetConnected;
    property State: TSessionState read FState;
    { Linhas do programa confirmadas pela controladora. }
    property Completed: Integer read GetCompleted;
    property Count: Integer read GetCount;
    property FileName: string read FFileName;
    property MachineState: TMachineState read GetMachineState;
    property Position: TMachinePosition read GetPosition;
    property Bounds: TGCodeBounds read FBounds;
    property LaserSettings: TLaserSettings read FLaserSettings write FLaserSettings;
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
  FState := ssDisconnected;
end;

destructor TSimulationSession.Destroy;
begin
  ReleaseConnection;
  FLines.Free;
  FLoadedLines.Free;
  FOriginalLines.Free;
  inherited Destroy;
end;

function TSimulationSession.Fail(const Reason: string): Boolean;
begin
  FLastError := Reason;
  Result := False;
end;

procedure TSimulationSession.Receive(const Data: string);
var Lines: TStringList; I: Integer; Shown: string;
begin
  if not Assigned(FOnLog) then Exit;
  { Relatorios de estado periodicos do GRBL nao poluem o console. }
  Lines := TStringList.Create;
  try
    Lines.Text := Data;
    Shown := '';
    for I := 0 to Lines.Count - 1 do
      if (Trim(Lines[I]) <> '') and (Copy(Trim(Lines[I]), 1, 1) <> '<') then
        Shown := Shown + Trim(Lines[I]) + LineEnding;
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
    Result := ConnectTransport(Kind, ProtocolKind, Serial, Serial);
  end;
end;

function TSimulationSession.ConnectTransport(Kind: TMachineType; ProtocolKind: TProtocolKind;
  ATransportObject: TObject; const ATransport: IMultiCNCTransport): Boolean;
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
  Result := FMachine.Connect;
  if Result then FState := ssIdle
  else
  begin
    FState := ssError;
    FLastError := 'Falha ao abrir a conexao';
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

function TSimulationSession.GetCount: Integer;
begin
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

procedure TSimulationSession.LoadFile(const FileName: string);
var Source, Commands: TStringList; Stream: TFileStream; I: Integer; Line: string;
begin
  if FState in [ssRunning, ssPaused] then
    raise Exception.Create('Pare o programa antes de abrir outro arquivo.');
  Source := TStringList.Create;
  Commands := TStringList.Create;
  try
    Stream := TFileStream.Create(FileName, fmOpenRead or fmShareDenyWrite);
    try
      if Stream.Size > 5 * 1024 * 1024 then
        raise Exception.Create('O arquivo excede o limite de 5 MB.');
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
    if Commands.Count = 0 then raise Exception.Create('O arquivo nao contem comandos.');
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
  if not Connected then Exit(Fail('Maquina desconectada'));
  if (AFramingLines = nil) or (AFramingLines.Count = 0) then Exit(Fail('Nenhum percurso de contorno disponivel'));
  if FState in [ssRunning, ssPaused] then Exit(Fail('Maquina ocupada com outro programa'));
  if FMachine.GetState in [msAlarm, msError] then
    Exit(Fail('Maquina em alarme: desbloqueie ou referencie antes de iniciar'));
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
  if not Connected then Exit(Fail('Maquina desconectada'));
  if FLoadedLines.Count = 0 then Exit(Fail('Nenhum programa carregado'));
  if FState in [ssRunning, ssPaused] then Exit(Fail('Programa ja em execucao'));
  if FMachine.GetState in [msAlarm, msError] then
    Exit(Fail('Maquina em alarme: desbloqueie ou referencie antes de iniciar'));
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
  { GRBL: '?' e de tempo real e nao ocupa o buffer. }
  if (FProtocolKind = pkGRBL) and Connected then
  begin
    Now64 := GetTickCount64;
    if Now64 - FLastPoll >= StatusPollMS then
    begin
      FLastPoll := Now64;
      FMachine.Status;
    end;
  end;
end;

procedure TSimulationSession.Tick;
begin
  if not (FState in [ssRunning, ssPaused]) then Exit;
  if not Connected then
  begin
    FState := ssError;
    FLastError := 'Conexao perdida durante o programa';
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
  if not (Connected and (FState = ssPaused)) then Exit(Fail('Programa nao esta pausado'));
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
  if not Connected then Exit(Fail('Maquina desconectada'));
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
  if not Connected or (FState in [ssRunning, ssPaused]) then Exit(Fail('Indisponivel durante o programa'));
  Result := FMachine.SetHome(AHomePos);
  if not Result then FLastError := FMachine.LastError;
end;

function TSimulationSession.PhysicalHoming: Boolean;
begin
  if not Connected or (FState in [ssRunning, ssPaused]) then Exit(Fail('Indisponivel durante o programa'));
  Result := FMachine.PhysicalHoming;
  if not Result then FLastError := FMachine.LastError;
end;

function TSimulationSession.Home(AFeed: Double = 0): Boolean;
begin
  if not Connected or (FState in [ssRunning, ssPaused]) then Exit(Fail('Indisponivel durante o programa'));
  Result := FMachine.Home(AFeed);
  if not Result then FLastError := FMachine.LastError;
end;

function TSimulationSession.SetFeedRate(AFeed: Double): Boolean;
begin
  if not Connected or (FState in [ssRunning, ssPaused]) then Exit(Fail('Indisponivel durante o programa'));
  Result := FMachine.SetFeedRate(AFeed);
  if not Result then FLastError := FMachine.LastError;
end;

function TSimulationSession.Zero: Boolean;
begin
  if not Connected or (FState in [ssRunning, ssPaused]) then Exit(Fail('Indisponivel durante o programa'));
  if Assigned(FMachine) and (FMachine.GetMachineType = mtPrinter3D) then
    Exit(Fail('Referenciamento de zero indisponivel para impressora 3D'));
  Result := FMachine.Zero;
  if not Result then FLastError := FMachine.LastError;
end;

function TSimulationSession.Status: Boolean;
begin
  Result := Connected and FMachine.Status;
  if not Result then FLastError := 'Falha ao consultar estado';
end;

function TSimulationSession.Unlock: Boolean;
begin
  if not Connected or (FState in [ssRunning, ssPaused]) then Exit(Fail('Indisponivel durante o programa'));
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
  if not SupportsAxis(Axis) then Exit(Fail('Eixo indisponivel'));
  if FState in [ssRunning, ssPaused] then Exit(Fail('Indisponivel durante o programa'));
  if not ((Abs(Distance) > 0) and (Abs(Distance) <= 100) and (Feed >= 1) and (Feed <= 10000)) then
    Exit(Fail('Passo ou avanco fora dos limites (0-100 mm, 1-10000 mm/min)'));
  Result := FMachine.Jog(Axis, Distance, Feed);
  if not Result then FLastError := FMachine.LastError;
end;

function TSimulationSession.Send(const Line: string): Boolean;
begin
  if not Connected or (FState in [ssRunning, ssPaused]) then Exit(Fail('Indisponivel durante o programa'));
  if (Trim(Line) = '') or (Pos(#10, Line) > 0) or (Pos(#13, Line) > 0) then
    Exit(Fail('Informe um unico comando'));
  Result := FMachine.SendGCode(Line);
  if not Result then FLastError := FMachine.LastError;
end;

function TSimulationSession.ProgramText: string;
begin
  Result := FLines.Text;
end;

end.
