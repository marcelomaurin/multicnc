unit multicnc_machine;

{ Maquina conectada: valida comandos no nucleo de seguranca, envia com
  controle de fluxo (aguarda "ok" da controladora) e mantem estado e posicao
  a partir das respostas do firmware.

  Controle de fluxo:
  - GRBL: contagem de caracteres. Envia enquanto a soma das linhas pendentes
    couber no buffer serial (127 bytes); cada "ok"/"error:" libera a mais
    antiga.
  - Marlin: uma linha por vez.
  Comandos de tempo real (sem quebra de linha) nao entram na fila. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, multicnc_types, multicnc_interfaces, multicnc_safety, multicnc_printer_profiles,
  multicnc_gcode_compat;

const
  MaxQueuedLines = 10000;

type
  TMultiCNCMachine = class(TInterfacedObject, IMultiCNCMachine)
  private
    FMachineType: TMachineType;
    FState: TMachineState;
    FPosition: TMachinePosition;
    FTemperatures: TPrinterTemperatures;
    FMaxHotendTemp, FMaxBedTemp: Integer;
    FHomePosition: TMachinePosition;
    FHomePositionSet: Boolean;
    FCapabilities: TMachineCapabilities;
    FEnvelope: TWorkEnvelope;
    FTransport: IMultiCNCTransport;
    FProtocol: IMultiCNCProtocol;
    FQueue: TStringList;      { linhas aguardando espaco no buffer }
    FInFlight: TList;         { tamanho (bytes) de cada linha sem "ok" }
    FInFlightBytes: Integer;
    FLastActivity: QWord;
    FPumping: Boolean;
    FFeedPaused, FWaitingReset: Boolean;
    FHasControllerReply: Boolean;
    FErrorCount: Integer;
    FAlarmCount: Integer;
    FLastError: string;
    FFirstControllerError: string;
    FOnData: TTransportDataEvent;
    FOnSend, FOnReceive: TTransportDataEvent;
    procedure TransportData(const AData: string);
    procedure TransportState(AConnected: Boolean);
    procedure ReleaseInFlight(ACount: Integer);
    procedure ClearPending;
    function Reject(const AReason: string): Boolean;
    function SendRealtime(const ACommand: string): Boolean;
    function EnqueueLines(const AText: string; AValidate: Boolean): Boolean;
    function SendProtocolCommand(const ACommand: string; AValidate: Boolean): Boolean;
    procedure Pump;
  public
    constructor Create(AType: TMachineType;
      const ATransport: IMultiCNCTransport; const AProtocol: IMultiCNCProtocol);
    destructor Destroy; override;
    function GetMachineType: TMachineType;
    function GetState: TMachineState;
    function GetPosition: TMachinePosition;
    function GetCapabilities: TMachineCapabilities;
    function GetTemperatures: TPrinterTemperatures;
    function QueryTemperatures: Boolean;
    function MoveTo(AX, AY, AZ, AFeed: Double): Boolean;
    function SetHotendTemperature(ATemp: Double): Boolean;
    function SetBedTemperature(ATemp: Double): Boolean;
    function Connect: Boolean;
    procedure Disconnect;
    function Home(AFeed: Double = 0): Boolean;
    function SetHome(out AHomePos: TMachinePosition): Boolean;
    function PhysicalHoming: Boolean;
    function Zero: Boolean;
    function GetHomePosition: TMachinePosition;
    function IsHomePositionSet: Boolean;
    function Status: Boolean;
    function Unlock: Boolean;
    function Pause: Boolean;
    function Resume: Boolean;
    function Stop: Boolean;
    function SetFeedRate(AFeed: Double): Boolean;
    function Jog(AAxis: TAxis; ADistance, AFeed: Double): Boolean;
    function JogVector(X,Y,Z,Feed: Double; AMarlin: Boolean): Boolean;
    function CancelJoystickJog: Boolean;
    { Valida e coloca a linha na fila; o envio acontece conforme o firmware
      confirma as anteriores. }
    function SendGCode(const ALine: string): Boolean;
    procedure SetWorkEnvelope(AX, AY, AZ: Double);
    procedure SetThermalLimits(AMaxHotend, AMaxBed: Integer);
    { Descarta o que ainda nao foi enviado (o que ja esta na controladora
      continua sendo executado). }
    procedure ClearQueue;
    procedure CheckCommunicationTimeout(ANow: QWord);
    procedure ResetControllerError;
    function QueuedLines: Integer;
    function InFlightLines: Integer;
    function PendingLines: Integer;
    property ErrorCount: Integer read FErrorCount;
    property HasControllerReply: Boolean read FHasControllerReply;
    property AlarmCount: Integer read FAlarmCount;
    property HomePosition: TMachinePosition read FHomePosition;
    property HomePositionSet: Boolean read FHomePositionSet;
    property LastError: string read FLastError;
    property FirstControllerError: string read FFirstControllerError;
    property OnData: TTransportDataEvent read FOnData write FOnData;
    property OnSend: TTransportDataEvent read FOnSend write FOnSend;
    property OnReceive: TTransportDataEvent read FOnReceive write FOnReceive;
  end;

implementation

uses Math, multisuite_numfmt;

constructor TMultiCNCMachine.Create(AType: TMachineType;
  const ATransport: IMultiCNCTransport; const AProtocol: IMultiCNCProtocol);
begin
  inherited Create;
  FMachineType := AType;
  FTransport := ATransport;
  FProtocol := AProtocol;
  FState := msDisconnected;
  FPosition := EmptyPosition;
  FHomePosition := EmptyPosition;
  FHomePositionSet := False;
  FTemperatures := EmptyTemperatures;
  FMaxHotendTemp := DEFAULT_MAX_HOTEND_TEMP;
  FMaxBedTemp := DEFAULT_MAX_BED_TEMP;
  FCapabilities := DefaultCapabilities(AType);
  FillChar(FEnvelope, SizeOf(FEnvelope), 0);
  FQueue := TStringList.Create;
  FInFlight := TList.Create;
  if Assigned(FTransport) then
  begin
    FTransport.SetOnData(@TransportData);
    FTransport.SetOnState(@TransportState);
  end;
end;

destructor TMultiCNCMachine.Destroy;
begin
  if Assigned(FTransport) then
  begin
    FTransport.SetOnData(nil);
    FTransport.SetOnState(nil);
  end;
  FQueue.Free;
  FInFlight.Free;
  inherited Destroy;
end;

function TMultiCNCMachine.Reject(const AReason: string): Boolean;
begin
  FLastError := AReason;
  Result := False;
end;

procedure TMultiCNCMachine.ClearPending;
begin
  FQueue.Clear;
  FInFlight.Clear;
  FInFlightBytes := 0;
end;

procedure TMultiCNCMachine.ReleaseInFlight(ACount: Integer);
begin
  while (ACount > 0) and (FInFlight.Count > 0) do
  begin
    Dec(FInFlightBytes, PtrInt(FInFlight[0]));
    FInFlight.Delete(0);
    Dec(ACount);
  end;
  if FInFlightBytes < 0 then FInFlightBytes := 0;
end;

procedure TMultiCNCMachine.TransportData(const AData: string);
var Acks, Errors: Integer; S: TMachineState; P: TMachinePosition; Temps: TPrinterTemperatures;
begin
  if Assigned(FOnReceive) then FOnReceive(AData);
  if Assigned(FProtocol) then
  begin
    if AData <> '' then FLastActivity := GetTickCount64;
    FProtocol.ProcessIncoming(AData);
    if FProtocol.TakeResetDetected then
    begin
      if (FQueue.Count > 0) or (FInFlight.Count > 0) then begin
        Inc(FErrorCount);
        FLastError := 'Controladora reiniciou com comandos pendentes; trabalho interrompido';
        FFirstControllerError := FLastError;
      end;
      ClearPending; { a controladora descartou tudo o que estava pendente }
      FWaitingReset := False;
      FFeedPaused := False;
    end;
    if FProtocol.TakeResponses(Acks, Errors) then
    begin
      { Tanto 'ok' quanto 'error:' encerram a resposta de uma linha enviada. }
      ReleaseInFlight(Acks + Errors);
      if Errors > 0 then
      begin
        Inc(FErrorCount, Errors);
        FLastError := FProtocol.LastMessage;
        if FFirstControllerError='' then FFirstControllerError:=FLastError;
        { Nao continua um programa depois de um erro do firmware. }
        FQueue.Clear;
      end;
    end;
    if FProtocol.ReportedState(S) then
    begin
      FHasControllerReply := True;
      if (S = msAlarm) and (FState <> msAlarm) then
      begin
        Inc(FAlarmCount);
        FLastError := FProtocol.LastMessage;
        FQueue.Clear;
      end;
      if SameText(FProtocol.GetName, 'GRBL') and (S = msPaused) then
        FFeedPaused := True;
      if FState <> msDisconnected then FState := S;
    end;
    if FProtocol.ReportedPosition(P) then FPosition := P;
    if FProtocol.ReportedTemperatures(Temps) then FTemperatures := Temps;
  end;
  if not FPumping then Pump;
  if Assigned(FOnData) then FOnData(AData);
end;

procedure TMultiCNCMachine.CheckCommunicationTimeout(ANow: QWord);
begin
  { busy/temperature reports keep a heating command alive. Do not replay
    an unacknowledged motion after a silent controller or connection loss. }
  if not SameText(FProtocol.GetName, 'Marlin') or (FInFlight.Count = 0) then Exit;
  if (ANow >= FLastActivity) and (ANow - FLastActivity >= 120000) then begin
    Inc(FErrorCount);
    FLastError := 'Marlin sem resposta por 120 s; trabalho interrompido, verifique a maquina';
    FFirstControllerError := FLastError;
    ClearPending;
    FFeedPaused := True;
    FState := msError;
  end;
end;

procedure TMultiCNCMachine.TransportState(AConnected: Boolean);
begin
  if not AConnected then
  begin
    ClearPending;
    FState := msDisconnected;
  end;
end;

procedure TMultiCNCMachine.Pump;
var Line: string; Len, Limit: Integer;
begin
  if FPumping or not Assigned(FTransport) or not Assigned(FProtocol) then Exit;
  FPumping := True;
  try
    Limit := FProtocol.ReceiveBufferSize;
    while (FQueue.Count > 0) and FTransport.IsConnected and
      not FFeedPaused and not FWaitingReset do
    begin
      Line := FQueue[0];
      Len := Length(Line) + 1; { + LF }
      if Limit > 0 then
      begin
        if FInFlightBytes + Len > Limit then Break;
      end
      else if FInFlight.Count > 0 then
        Break;
      FQueue.Delete(0);
      { Registra antes de enviar: o "ok" pode chegar durante o Send. }
      FInFlight.Add(Pointer(PtrInt(Len)));
      Inc(FInFlightBytes, Len);
      FLastActivity := GetTickCount64;
      if Assigned(FOnSend) then FOnSend(Line + #10);
      if not FTransport.Send(Line + #10) then
      begin
        ClearPending;
        FState := msError;
        FLastError := 'Failed to send command to controller';
        Break;
      end;
    end;
  finally
    FPumping := False;
  end;
end;

function TMultiCNCMachine.EnqueueLines(const AText: string; AValidate: Boolean): Boolean;
var Lines: TStringList; I, J: Integer; Reason, L: string;
begin
  Result := False;
  if not (Assigned(FTransport) and FTransport.IsConnected) then
    Exit(Reject('Machine disconnected'));
  if FWaitingReset then Exit(Reject('Aguarde o reinicio do GRBL'));
  Lines := TStringList.Create;
  try
    Lines.Text := AText;
    for I := Lines.Count - 1 downto 0 do
      if Trim(Lines[I]) = '' then Lines.Delete(I) else Lines[I] := Trim(Lines[I]);
    if Lines.Count = 0 then Exit(Reject('Comando vazio'));
    { Valida todas as linhas antes de enfileirar qualquer uma. }
    for I := 0 to Lines.Count - 1 do
    begin
      L := Lines[I];
      { GRBL padrao: 80 bytes no buffer de linha, incluindo terminador.
        Limite conservador sobre a linha bruta, mesmo com comentarios. }
      if SameText(FProtocol.GetName, 'GRBL') then
      begin
        if Length(L) > 79 then Exit(Reject('Linha GRBL com mais de 79 caracteres'));
        if (Pos('!', L) > 0) or (Pos('~', L) > 0) or (Pos('?', L) > 0) then
          Exit(Reject('Comando de tempo real dentro de linha GRBL'));
        for J := 1 to Length(L) do
          if Ord(L[J]) > 126 then Exit(Reject('Linha GRBL deve usar caracteres ASCII'));
      end;
      if AValidate then
      begin
        if not CheckGCodeCompatibility(L,FProtocol.GetName,Reason) then Exit(Reject(Reason));
        if not TSafetyValidator.CheckCommand(GetState, L, Reason) then Exit(Reject(Reason));
      end
      else if Length(L) > MaxCommandLength then
        Exit(Reject('Comando muito longo'));
    end;
    if FQueue.Count + Lines.Count > MaxQueuedLines then Exit(Reject('Fila de envio cheia'));
    FQueue.AddStrings(Lines);
  finally
    Lines.Free;
  end;
  Pump;
  Result := FState <> msError;
end;

function TMultiCNCMachine.SendRealtime(const ACommand: string): Boolean;
begin
  if Assigned(FOnSend) then FOnSend(ACommand);
  Result := Assigned(FTransport) and FTransport.IsConnected and (ACommand <> '') and
    FTransport.Send(ACommand);
  if not Result then FLastError := 'Failed to send real-time command';
end;

function TMultiCNCMachine.SendProtocolCommand(const ACommand: string; AValidate: Boolean): Boolean;
begin
  if ACommand = '' then Exit(Reject('Command not supported by protocol'));
  if ACommand[Length(ACommand)] in [#10, #13] then
    Result := EnqueueLines(ACommand, AValidate)
  else
    Result := SendRealtime(ACommand);
end;

function TMultiCNCMachine.Connect: Boolean;
begin
  Result := False;
  if not Assigned(FTransport) then Exit;
  ClearPending;
  if Assigned(FProtocol) then FProtocol.Reset;
  FErrorCount := 0;
  FAlarmCount := 0;
  FLastError := '';
  ResetControllerError;
  FFeedPaused := False;
  FWaitingReset := False;
  FHomePosition := EmptyPosition;
  FHomePositionSet := False;
  FTemperatures := EmptyTemperatures;
  FHasControllerReply := False;
  FState := msConnecting;
  Result := FTransport.Connect;
  if Result then FState := msIdle else FState := msError;
end;

procedure TMultiCNCMachine.ResetControllerError;
begin FFirstControllerError:='';end;

procedure TMultiCNCMachine.Disconnect;
begin
  ClearPending;
  if Assigned(FTransport) then FTransport.Disconnect;
  FState := msDisconnected;
end;

function TMultiCNCMachine.GetHomePosition: TMachinePosition;
begin
  Result := FHomePosition;
end;

function TMultiCNCMachine.IsHomePositionSet: Boolean;
begin
  Result := FHomePositionSet;
end;

function TMultiCNCMachine.SetHome(out AHomePos: TMachinePosition): Boolean;
begin
  AHomePos := EmptyPosition;
  if not Assigned(FProtocol) then Exit(Reject('Sem protocolo'));
  if FState in [msRunning, msPaused] then Exit(Reject('Machine is running'));
  FHomePosition := FPosition;
  FHomePositionSet := True;
  AHomePos := FHomePosition;
  Result := SendProtocolCommand(FProtocol.BuildSetHomeCommand, False);
end;

function TMultiCNCMachine.PhysicalHoming: Boolean;
begin
  if not Assigned(FProtocol) then Exit(Reject('Sem protocolo'));
  if FState in [msRunning, msPaused] then Exit(Reject('Machine is running'));
  Result := SendProtocolCommand(FProtocol.BuildPhysicalHomingCommand, False);
end;

function TMultiCNCMachine.Home(AFeed: Double = 0): Boolean;
begin
  if not Assigned(FProtocol) then Exit(Reject('Sem protocolo'));
  if FState in [msRunning, msPaused] then Exit(Reject('Machine is running'));
  { Permitido em alarme: e a forma de sair dele. }
  Result := SendProtocolCommand(FProtocol.BuildHomeCommand(AFeed), False);
end;

function TMultiCNCMachine.SetFeedRate(AFeed: Double): Boolean;
var
  Cmd: string;
begin
  if not Assigned(FProtocol) then Exit(Reject('Sem protocolo'));
  if AFeed <= 0 then Exit(Reject('Invalid feed rate'));
  Cmd := FProtocol.BuildFeedRateCommand(AFeed);
  if Cmd = '' then Exit(False);
  Result := SendProtocolCommand(Cmd, True);
end;

function TMultiCNCMachine.Zero: Boolean;
begin
  if not Assigned(FProtocol) then Exit(Reject('Sem protocolo'));
  if FMachineType = mtPrinter3D then
    Exit(Reject('Zero reference is not applicable to 3D printers'));
  Result := SendProtocolCommand(FProtocol.BuildZeroCommand, True);
  if Result then
  begin
    FPosition.X := 0;
    FPosition.Y := 0;
    FPosition.Z := 0;
    if Assigned(FProtocol) then
    begin
      FProtocol.ResetPositionToZero;
      Status;
    end;
  end;
end;

function TMultiCNCMachine.Status: Boolean;
begin
  if not Assigned(FProtocol) then Exit(Reject('Sem protocolo'));
  Result := SendProtocolCommand(FProtocol.BuildStatusCommand, False);
end;

function TMultiCNCMachine.Unlock: Boolean;
begin
  if not Assigned(FProtocol) then Exit(Reject('Sem protocolo'));
  Result := SendProtocolCommand(FProtocol.BuildUnlockCommand, False);
  if Result and (FState = msAlarm) then FState := msIdle;
end;

function TMultiCNCMachine.Pause: Boolean;
var C: string;
begin
  if not Assigned(FProtocol) then Exit(Reject('Sem protocolo'));
  C := FProtocol.BuildPauseCommand;
  { Vazio: pausa no host (o chamador para de enviar linhas). }
  FFeedPaused := True;
  { Stop the host queue for every protocol, including Marlin lookahead.
    Already accepted planner moves may finish; this is not emergency stop. }
  if C = '' then Result := Assigned(FTransport) and FTransport.IsConnected
  else Result := SendRealtime(C);
  if not Result then FFeedPaused := False;
end;

function TMultiCNCMachine.Resume: Boolean;
var C: string;
begin
  if not Assigned(FProtocol) then Exit(Reject('Sem protocolo'));
  if FWaitingReset then Exit(Reject('Aguarde o reinicio do GRBL'));
  if FState in [msAlarm, msError] then Exit(Reject('Machine in alarm/error'));
  C := FProtocol.BuildResumeCommand;
  if C = '' then Result := Assigned(FTransport) and FTransport.IsConnected
  else Result := SendRealtime(C);
  if Result then
  begin
    FFeedPaused := False;
    Pump;
  end;
end;

function TMultiCNCMachine.Stop: Boolean;
var C, Off: string;
begin
  if not Assigned(FProtocol) then Exit(Reject('Sem protocolo'));
  if not (Assigned(FTransport) and FTransport.IsConnected) then Exit(Reject('Machine disconnected'));
  { Nada mais da fila sera enviado. }
  ClearPending;
  FFeedPaused := False;
  FWaitingReset := SameText(FProtocol.GetName, 'GRBL');
  C := FProtocol.BuildStopCommand;
  if C = '' then Exit(Reject('Protocolo sem comando de parada'));
  { A parada nunca espera a fila: vai direto ao transporte. }
  if C[Length(C)] in [#10, #13] then
  begin
    FInFlight.Add(Pointer(PtrInt(Length(Trim(C)) + 1)));
    Inc(FInFlightBytes, Length(Trim(C)) + 1);
    if Assigned(FOnSend) then FOnSend(Trim(C) + #10);
    Result := FTransport.Send(Trim(C) + #10);
  end
  else begin
    if Assigned(FOnSend) then FOnSend(C);
    Result := FTransport.Send(C);
  end;
  if not Result then Exit(Reject('Failed to send stop command'));
  Off := FProtocol.BuildSafeOffCommands(FMachineType);
  if Off <> '' then EnqueueLines(Off, False);
end;

function TMultiCNCMachine.Jog(AAxis: TAxis; ADistance, AFeed: Double): Boolean;
var Reason: string;
begin
  if not Assigned(FProtocol) then Exit(Reject('Sem protocolo'));
  if not TSafetyValidator.CheckJog(GetState, AAxis, ADistance, AFeed, FCapabilities,
    FEnvelope, Reason) then Exit(Reject(Reason));
  Result := SendProtocolCommand(FProtocol.BuildJogCommand(AAxis, ADistance, AFeed), True);
end;

function TMultiCNCMachine.JogVector(X,Y,Z,Feed: Double; AMarlin: Boolean): Boolean;
var Reason, AxesText, Command: string;
  function AddAxis(Axis: TAxis; const Name: string; Value: Double): Boolean;
  begin
    Result:=True;
    if Abs(Value)<0.0005 then Exit;
    Result:=TSafetyValidator.CheckJog(GetState,Axis,Value,Feed,FCapabilities,FEnvelope,Reason);
    if Result then AxesText:=AxesText+Format(' %s%.3f',[Name,Value],InvariantFS);
  end;
begin
  if not Assigned(FProtocol) then Exit(Reject('Sem protocolo'));
  if IsNan(X) or IsNan(Y) or IsNan(Z) or IsNan(Feed) or
     IsInfinite(X) or IsInfinite(Y) or IsInfinite(Z) or IsInfinite(Feed) then
    Exit(Reject('Vetor invalido'));
  if (GetState<>msIdle) or (PendingLines<>0) then Exit(Reject('Aguarde a controladora ociosa'));
  if (Feed<1) or (Feed>3000) or (Sqrt(Sqr(X)+Sqr(Y)+Sqr(Z))>2.001) then
    Exit(Reject('Passo ou velocidade do joystick fora dos limites'));
  AxesText:='';
  if not AddAxis(axX,'X',X) or not AddAxis(axY,'Y',Y) or not AddAxis(axZ,'Z',Z) then
    Exit(Reject(Reason));
  if AxesText='' then Exit(Reject('Vetor sem deslocamento'));
  if AMarlin then
    { M400's acknowledgement means physical completion, unlike G1's ok. }
    Command:='G21'+LineEnding+'G91'+LineEnding+Format('G1%s F%.0f',[AxesText,Feed],InvariantFS)+
      LineEnding+'G90'+LineEnding+'M400'+LineEnding+'M114'
  else Command:='$J=G91 G21'+AxesText+Format(' F%.0f',[Feed],InvariantFS);
  Result:=EnqueueLines(Command,True);
end;

function TMultiCNCMachine.CancelJoystickJog: Boolean;
begin
  { Caller owns this jog; preserve accounting for lines already transmitted. }
  FQueue.Clear;
  Result:=SendRealtime(#$85);
  if Result then Result:=EnqueueLines('G4 P0',True);
end;

function TMultiCNCMachine.MoveTo(AX, AY, AZ, AFeed: Double): Boolean;
var Reason: string;
begin
  if not Assigned(FProtocol) then Exit(Reject('Sem protocolo'));
  if not TSafetyValidator.CheckMoveTo(GetState, AX, AY, AZ, AFeed, FCapabilities,
    FEnvelope, Reason) then Exit(Reject(Reason));
  Result := SendProtocolCommand(FProtocol.BuildMoveToCommand(AX, AY, AZ, AFeed), True);
end;

function TMultiCNCMachine.SendGCode(const ALine: string): Boolean;
begin
  Result := EnqueueLines(ALine, True);
end;

procedure TMultiCNCMachine.SetWorkEnvelope(AX, AY, AZ: Double);
begin
  FEnvelope.X := AX;
  FEnvelope.Y := AY;
  FEnvelope.Z := AZ;
end;

procedure TMultiCNCMachine.SetThermalLimits(AMaxHotend, AMaxBed: Integer);
begin
  if (AMaxHotend > 0) and (AMaxHotend <= ABSOLUTE_MAX_HOTEND_TEMP) then
    FMaxHotendTemp := AMaxHotend
  else
    FMaxHotendTemp := ABSOLUTE_MAX_HOTEND_TEMP;

  if (AMaxBed > 0) and (AMaxBed <= ABSOLUTE_MAX_BED_TEMP) then
    FMaxBedTemp := AMaxBed
  else
    FMaxBedTemp := ABSOLUTE_MAX_BED_TEMP;
end;

procedure TMultiCNCMachine.ClearQueue;
begin
  FQueue.Clear;
end;

function TMultiCNCMachine.QueuedLines: Integer;
begin Result := FQueue.Count; end;

function TMultiCNCMachine.InFlightLines: Integer;
begin Result := FInFlight.Count; end;

function TMultiCNCMachine.PendingLines: Integer;
begin Result := FQueue.Count + FInFlight.Count; end;

function TMultiCNCMachine.GetMachineType: TMachineType;
begin Result := FMachineType; end;

function TMultiCNCMachine.GetState: TMachineState;
begin
  Result := FState;
  if not (Assigned(FTransport) and FTransport.IsConnected) then
    Exit(msDisconnected);
  if FWaitingReset then Exit(msConnecting);
  if FFeedPaused and not (Result in [msAlarm, msError]) then Exit(msPaused);
  { Controladora ociosa mas com linhas pendentes = em execucao. }
  if (Result = msIdle) and (PendingLines > 0) then Result := msRunning;
end;

function TMultiCNCMachine.GetPosition: TMachinePosition;
begin Result := FPosition; end;

function TMultiCNCMachine.GetCapabilities: TMachineCapabilities;
begin Result := FCapabilities; end;

function TMultiCNCMachine.GetTemperatures: TPrinterTemperatures;
begin
  Result := FTemperatures;
end;

function TMultiCNCMachine.QueryTemperatures: Boolean;
begin
  if not Assigned(FProtocol) then Exit(Reject('No protocol'));
  if FMachineType <> mtPrinter3D then Exit(False);
  Result := SendProtocolCommand(FProtocol.BuildQueryTemperaturesCommand, False);
end;

function TMultiCNCMachine.SetHotendTemperature(ATemp: Double): Boolean;
var
  Reason: string;
begin
  if not Assigned(FProtocol) then Exit(Reject('No protocol'));
  if FMachineType <> mtPrinter3D then Exit(False);
  if not ValidateHotendTemperature(ATemp, FMaxHotendTemp, Reason) then
  begin
    Reject(Reason);
    Exit(False);
  end;
  Result := SendProtocolCommand(FProtocol.BuildSetHotendTemperatureCommand(ATemp), False);
end;

function TMultiCNCMachine.SetBedTemperature(ATemp: Double): Boolean;
var
  Reason: string;
begin
  if not Assigned(FProtocol) then Exit(Reject('No protocol'));
  if FMachineType <> mtPrinter3D then Exit(False);
  if not ValidateBedTemperature(ATemp, FMaxBedTemp, Reason) then
  begin
    Reject(Reason);
    Exit(False);
  end;
  Result := SendProtocolCommand(FProtocol.BuildSetBedTemperatureCommand(ATemp), False);
end;

end.
