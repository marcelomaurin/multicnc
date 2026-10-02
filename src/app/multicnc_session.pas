unit multicnc_session;

{$mode objfpc}{$H+}

interface

uses Classes, SysUtils, multicnc_types, multicnc_interfaces, multicnc_machine,
  multicnc_simulator, multicnc_grbl, multicnc_marlin;

type
  TSessionState = (ssDisconnected, ssIdle, ssRunning, ssPaused, ssDone, ssStopped, ssError);
  TProtocolKind = (pkGRBL, pkMarlin);

  { This runner deliberately owns only a simulator transport. Real hardware needs
    acknowledgement-driven streaming and controller state reconciliation. }
  TSimulationSession = class
  private
    FTransport: TSimulatorTransport;
    FProtocol: TInterfacedObject;
    FMachine: TMultiCNCMachine;
    FLines, FSource: TStringList;
    FIndex: Integer;
    FState: TSessionState;
    FFileName: string;
    FOnLog: TTransportDataEvent;
    procedure Receive(const Data: string);
    procedure ReleaseConnection;
    function GetConnected: Boolean;
    function GetCount: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    function Connect(Kind: TMachineType; ProtocolKind: TProtocolKind): Boolean;
    procedure Disconnect;
    procedure LoadFile(const FileName: string);
    function Start: Boolean;
    procedure Tick;
    function Pause: Boolean;
    function Resume: Boolean;
    function Stop: Boolean;
    function Home: Boolean;
    function Jog(Axis: TAxis; Distance, Feed: Double): Boolean;
    function Send(const Line: string): Boolean;
    function SupportsAxis(Axis: TAxis): Boolean;
    function ProgramText: string;
    property Connected: Boolean read GetConnected;
    property State: TSessionState read FState;
    property Completed: Integer read FIndex;
    property Count: Integer read GetCount;
    property FileName: string read FFileName;
    property OnLog: TTransportDataEvent read FOnLog write FOnLog;
  end;

implementation

constructor TSimulationSession.Create;
begin
  inherited Create;
  FLines := TStringList.Create;
  FSource := TStringList.Create;
  FState := ssDisconnected;
end;

destructor TSimulationSession.Destroy;
begin
  ReleaseConnection;
  FLines.Free;
  FSource.Free;
  inherited Destroy;
end;

procedure TSimulationSession.Receive(const Data: string);
begin
  if Assigned(FOnLog) then FOnLog(Data);
end;

procedure TSimulationSession.ReleaseConnection;
begin
  if Assigned(FTransport) then FTransport.SetOnData(nil);
  if Assigned(FMachine) then FMachine.Disconnect;
  FreeAndNil(FMachine);
  FreeAndNil(FProtocol);
  FreeAndNil(FTransport);
end;

function TSimulationSession.Connect(Kind: TMachineType; ProtocolKind: TProtocolKind): Boolean;
var Protocol: IMultiCNCProtocol;
begin
  Result := False;
  if Connected then Exit;
  ReleaseConnection;
  FTransport := TSimulatorTransport.Create;
  if ProtocolKind = pkMarlin then begin
    FProtocol := TMarlinProtocol.Create;
    Protocol := TMarlinProtocol(FProtocol);
  end else begin
    FProtocol := TGRBLProtocol.Create;
    Protocol := TGRBLProtocol(FProtocol);
  end;
  FMachine := TMultiCNCMachine.Create(Kind, FTransport, Protocol);
  FTransport.SetOnData(@Receive);
  Result := FMachine.Connect;
  if Result then FState := ssIdle else FState := ssError;
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

procedure TSimulationSession.LoadFile(const FileName: string);
var Source, Commands: TStringList; Stream: TFileStream; I: Integer; Line: string;
begin
  if FState in [ssRunning, ssPaused] then
    raise Exception.Create('Pare a simulacao antes de abrir outro arquivo.');
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
    FLines.Assign(Commands);
    FSource.Assign(Source);
    FFileName := ExpandFileName(FileName);
    FIndex := 0;
    if Connected then FState := ssIdle else FState := ssDisconnected;
  finally
    Source.Free;
    Commands.Free;
  end;
end;

function TSimulationSession.Start: Boolean;
begin
  Result := Connected and (Count > 0) and not (FState in [ssRunning, ssPaused]);
  if Result then begin FIndex := 0; FState := ssRunning; end;
end;

procedure TSimulationSession.Tick;
begin
  if FState <> ssRunning then Exit;
  if not Connected then begin FState := ssError; Exit; end;
  if not FMachine.SendGCode(FLines[FIndex]) then begin FState := ssError; Exit; end;
  Inc(FIndex);
  if FIndex = Count then FState := ssDone;
end;

function TSimulationSession.Pause: Boolean;
begin
  Result := Connected and (FState = ssRunning);
  if Result then begin Result := FMachine.Pause; if Result then FState := ssPaused; end;
end;

function TSimulationSession.Resume: Boolean;
begin
  Result := Connected and (FState = ssPaused);
  if Result then begin Result := FMachine.Resume; if Result then FState := ssRunning; end;
end;

function TSimulationSession.Stop: Boolean;
begin
  Result := Connected;
  if Result then begin
    Result := FMachine.Stop;
    if Result then FState := ssStopped else FState := ssError;
  end;
end;

function TSimulationSession.Home: Boolean;
begin
  Result := Connected and not (FState in [ssRunning, ssPaused, ssError]);
  if Result then Result := FMachine.Home;
end;

function TSimulationSession.SupportsAxis(Axis: TAxis): Boolean;
begin
  Result := Connected;
  if Result then Result := Axis in FMachine.GetCapabilities.Axes;
end;

function TSimulationSession.Jog(Axis: TAxis; Distance, Feed: Double): Boolean;
begin
  Result := SupportsAxis(Axis) and not (FState in [ssRunning, ssPaused, ssError]) and
    (Abs(Distance) > 0) and (Abs(Distance) <= 100) and (Feed >= 1) and (Feed <= 10000);
  if Result then Result := FMachine.Jog(Axis, Distance, Feed);
end;

function TSimulationSession.Send(const Line: string): Boolean;
begin
  Result := Connected and not (FState in [ssRunning, ssPaused, ssError]) and
    (Trim(Line) <> '') and (Pos(#10, Line) = 0) and (Pos(#13, Line) = 0);
  if Result then Result := FMachine.SendGCode(Line);
end;

function TSimulationSession.ProgramText: string;
begin
  Result := FSource.Text;
end;

end.
