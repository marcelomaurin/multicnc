unit multicnc_simulator;

{$mode objfpc}{$H+}
{$interfaces corba}

interface

uses
  Classes, SysUtils, multicnc_types, multicnc_interfaces;

type
  TSimulatorTransport = class(TInterfacedObject, IMultiCNCTransport)
  private
    FConnected: Boolean;
    FOnData: TTransportDataEvent;
    FOnState: TTransportStateEvent;
  public
    function Connect: Boolean;
    procedure Disconnect;
    function IsConnected: Boolean;
    function Send(const AData: string): Boolean;
    procedure SetOnData(AEvent: TTransportDataEvent);
    procedure SetOnState(AEvent: TTransportStateEvent);
    function GetName: string;
  end;

  TSimulatorProtocol = class(TInterfacedObject, IMultiCNCProtocol)
  public
    function GetName: string;
    procedure Reset;
    procedure ProcessIncoming(const AData: string);
    function BuildHomeCommand: string;
    function BuildZeroCommand: string;
    function BuildStatusCommand: string;
    function BuildUnlockCommand: string;
    function BuildPauseCommand: string;
    function BuildResumeCommand: string;
    function BuildStopCommand: string;
    function BuildJogCommand(AAxis: TAxis; ADistance, AFeed: Double): string;
  end;

implementation

function TSimulatorTransport.Connect: Boolean;
begin
  FConnected := True;
  if Assigned(FOnState) then FOnState(True);
  Result := True;
end;

procedure TSimulatorTransport.Disconnect;
begin
  if not FConnected then Exit;
  FConnected := False;
  if Assigned(FOnState) then FOnState(False);
end;

function TSimulatorTransport.IsConnected: Boolean;
begin Result := FConnected; end;

function TSimulatorTransport.Send(const AData: string): Boolean;
begin
  Result := FConnected;
  if Result and Assigned(FOnData) then
    FOnData('SIM> ' + Trim(AData) + LineEnding + 'ok' + LineEnding);
end;

procedure TSimulatorTransport.SetOnData(AEvent: TTransportDataEvent);
begin FOnData := AEvent; end;

procedure TSimulatorTransport.SetOnState(AEvent: TTransportStateEvent);
begin FOnState := AEvent; end;

function TSimulatorTransport.GetName: string;
begin Result := 'MultiCNC Simulator'; end;

function TSimulatorProtocol.GetName: string;
begin Result := 'Simulator'; end;

procedure TSimulatorProtocol.Reset;
begin end;

procedure TSimulatorProtocol.ProcessIncoming(const AData: string);
begin end;

function TSimulatorProtocol.BuildHomeCommand: string;
begin Result := '$H' + LineEnding; end;
function TSimulatorProtocol.BuildZeroCommand: string;
begin Result := 'G92 X0 Y0 Z0' + LineEnding; end;
function TSimulatorProtocol.BuildStatusCommand: string;
begin Result := '?' end;
function TSimulatorProtocol.BuildUnlockCommand: string;
begin Result := '$X' + LineEnding; end;

function TSimulatorProtocol.BuildPauseCommand: string;
begin Result := '!' + LineEnding; end;

function TSimulatorProtocol.BuildResumeCommand: string;
begin Result := '~' + LineEnding; end;

function TSimulatorProtocol.BuildStopCommand: string;
begin Result := #24; end;

function TSimulatorProtocol.BuildJogCommand(AAxis: TAxis; ADistance, AFeed: Double): string;
const
  AxisName: array[TAxis] of string = ('X','Y','Z','A','E');
begin
  Result := Format('$J=G91 %s%.3f F%.0f%s',
    [AxisName[AAxis], ADistance, AFeed, LineEnding]);
end;

end.
