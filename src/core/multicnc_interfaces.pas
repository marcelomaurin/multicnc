unit multicnc_interfaces;

{$mode objfpc}{$H+}
{$interfaces corba}

interface

uses
  Classes, multicnc_types;

type
  TTransportDataEvent = procedure(const AData: string) of object;
  TTransportStateEvent = procedure(AConnected: Boolean) of object;
  TMachineStateEvent = procedure(AState: TMachineState) of object;
  TMachinePositionEvent = procedure(const APosition: TMachinePosition) of object;

  IMultiCNCTransport = interface
    ['{A1B70C38-899D-45D6-9054-19F35A1AB101}']
    function Connect: Boolean;
    procedure Disconnect;
    function IsConnected: Boolean;
    function Send(const AData: string): Boolean;
    procedure SetOnData(AEvent: TTransportDataEvent);
    procedure SetOnState(AEvent: TTransportStateEvent);
    function GetName: string;
  end;

  IMultiCNCProtocol = interface
    ['{A1B70C38-899D-45D6-9054-19F35A1AB102}']
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

  IMultiCNCMachine = interface
    ['{A1B70C38-899D-45D6-9054-19F35A1AB103}']
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

end.
