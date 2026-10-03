unit multicnc_machine;

{$mode objfpc}{$H+}

interface

uses
  SysUtils, multicnc_types, multicnc_interfaces;

type
  TMultiCNCMachine = class(TInterfacedObject, IMultiCNCMachine)
  private
    FMachineType: TMachineType;
    FState: TMachineState;
    FPosition: TMachinePosition;
    FCapabilities: TMachineCapabilities;
    FTransport: IMultiCNCTransport;
    FProtocol: IMultiCNCProtocol;
    function SendProtocolCommand(const ACommand: string): Boolean;
  public
    constructor Create(AType: TMachineType;
      const ATransport: IMultiCNCTransport; const AProtocol: IMultiCNCProtocol);
    function GetMachineType: TMachineType;
    function GetState: TMachineState;
    function GetPosition: TMachinePosition;
    function GetCapabilities: TMachineCapabilities;
    function Connect: Boolean;
    procedure Disconnect;
    function Home: Boolean;
    function Zero: Boolean;
    function Status: Boolean;
    function Unlock: Boolean;
    function Pause: Boolean;
    function Resume: Boolean;
    function Stop: Boolean;
    function Jog(AAxis: TAxis; ADistance, AFeed: Double): Boolean;
    function SendGCode(const ALine: string): Boolean;
  end;

implementation

constructor TMultiCNCMachine.Create(AType: TMachineType;
  const ATransport: IMultiCNCTransport; const AProtocol: IMultiCNCProtocol);
begin
  inherited Create;
  FMachineType := AType;
  FTransport := ATransport;
  FProtocol := AProtocol;
  FState := msDisconnected;
  FPosition := EmptyPosition;
  FCapabilities := DefaultCapabilities(AType);
end;

function TMultiCNCMachine.Connect: Boolean;
begin
  Result := False;
  if not Assigned(FTransport) then Exit;
  FState := msConnecting;
  Result := FTransport.Connect;
  if Result then FState := msIdle else FState := msError;
end;

procedure TMultiCNCMachine.Disconnect;
begin
  if Assigned(FTransport) then FTransport.Disconnect;
  FState := msDisconnected;
end;

function TMultiCNCMachine.SendProtocolCommand(const ACommand: string): Boolean;
begin
  Result := Assigned(FTransport) and FTransport.IsConnected and
    (ACommand <> '') and FTransport.Send(ACommand);
end;

function TMultiCNCMachine.Home: Boolean;
begin
  Result := Assigned(FProtocol) and SendProtocolCommand(FProtocol.BuildHomeCommand);
end;
function TMultiCNCMachine.Zero: Boolean;
begin Result := Assigned(FProtocol) and SendProtocolCommand(FProtocol.BuildZeroCommand); end;
function TMultiCNCMachine.Status: Boolean;
begin Result := Assigned(FProtocol) and SendProtocolCommand(FProtocol.BuildStatusCommand); end;
function TMultiCNCMachine.Unlock: Boolean;
begin Result := Assigned(FProtocol) and SendProtocolCommand(FProtocol.BuildUnlockCommand); end;

function TMultiCNCMachine.Pause: Boolean;
begin
  Result := Assigned(FProtocol) and SendProtocolCommand(FProtocol.BuildPauseCommand);
end;

function TMultiCNCMachine.Resume: Boolean;
begin
  Result := Assigned(FProtocol) and SendProtocolCommand(FProtocol.BuildResumeCommand);
end;

function TMultiCNCMachine.Stop: Boolean;
begin
  Result := Assigned(FProtocol) and SendProtocolCommand(FProtocol.BuildStopCommand);
end;

function TMultiCNCMachine.Jog(AAxis: TAxis; ADistance, AFeed: Double): Boolean;
begin
  Result := (AAxis in FCapabilities.Axes) and Assigned(FProtocol) and
    SendProtocolCommand(FProtocol.BuildJogCommand(AAxis, ADistance, AFeed));
end;

function TMultiCNCMachine.SendGCode(const ALine: string): Boolean;
begin
  Result := SendProtocolCommand(Trim(ALine) + #10);
end;

function TMultiCNCMachine.GetMachineType: TMachineType;
begin Result := FMachineType; end;
function TMultiCNCMachine.GetState: TMachineState;
begin Result := FState; end;
function TMultiCNCMachine.GetPosition: TMachinePosition;
begin Result := FPosition; end;
function TMultiCNCMachine.GetCapabilities: TMachineCapabilities;
begin Result := FCapabilities; end;

end.
