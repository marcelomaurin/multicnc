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
    { Le dados pendentes e dispara OnData. Transportes orientados a evento
      podem deixar vazio. }
    procedure Poll;
    procedure SetOnData(AEvent: TTransportDataEvent);
    procedure SetOnState(AEvent: TTransportStateEvent);
    function GetName: string;
  end;

  { Protocolo de firmware. Comandos que terminam em LineEnding sao linhas de
    G-code e geram uma confirmacao ("ok"/"error"); comandos sem quebra de linha
    sao de tempo real (ex.: '?', '!', '~', #24 no GRBL) e nao geram "ok".
    String vazia significa que a acao e feita no host (ex.: pausa no Marlin). }
  IMultiCNCProtocol = interface
    ['{A1B70C38-899D-45D6-9054-19F35A1AB102}']
    function GetName: string;
    procedure Reset;
    procedure ProcessIncoming(const AData: string);
    { Confirmacoes recebidas desde a ultima chamada. Cada "ok" ou "error:" do
      GRBL libera uma linha enviada; Errors conta as respostas de erro. }
    function TakeResponses(out Acks, Errors: Integer): Boolean;
    { Estado/posicao informados desde a ultima consulta (True uma vez por
      relatorio recebido). }
    function ReportedState(out AState: TMachineState): Boolean;
    function ReportedPosition(out APosition: TMachinePosition): Boolean;
    function ReportedTemperatures(out ATemps: TPrinterTemperatures): Boolean;
    { True uma vez apos a controladora reiniciar (perde a fila de comandos). }
    function TakeResetDetected: Boolean;
    function LastMessage: string;
    { Bytes que a controladora aceita em buffer; 0 = uma linha por vez. }
    function ReceiveBufferSize: Integer;
    function BuildHomeCommand(AFeed: Double = 0): string;
    function BuildSetHomeCommand: string;
    function BuildPhysicalHomingCommand: string;
    function BuildZeroCommand: string;
    function BuildStatusCommand: string;
    function BuildUnlockCommand: string;
    function BuildPauseCommand: string;
    function BuildResumeCommand: string;
    function BuildStopCommand: string;
    { Linhas enviadas apos a parada para desligar spindle/laser/aquecedores. }
    function BuildSafeOffCommands(AType: TMachineType): string;
    function BuildJogCommand(AAxis: TAxis; ADistance, AFeed: Double): string;
    { Movimento absoluto ate X/Y/Z (coordenadas de trabalho, mm). }
    function BuildMoveToCommand(AX, AY, AZ, AFeed: Double): string;
    function BuildFeedRateCommand(AFeed: Double): string;
    function BuildQueryTemperaturesCommand: string;
    function BuildSetHotendTemperatureCommand(ATemp: Double): string;
    function BuildSetBedTemperatureCommand(ATemp: Double): string;
    procedure ResetPositionToZero;
  end;

  IMultiCNCMachine = interface
    ['{A1B70C38-899D-45D6-9054-19F35A1AB103}']
    function GetMachineType: TMachineType;
    function GetState: TMachineState;
    function GetPosition: TMachinePosition;
    function GetCapabilities: TMachineCapabilities;
    function GetTemperatures: TPrinterTemperatures;
    function QueryTemperatures: Boolean;
    function SetHotendTemperature(ATemp: Double): Boolean;
    function SetBedTemperature(ATemp: Double): Boolean;
    function Connect: Boolean;
    procedure Disconnect;
    function Home(AFeed: Double = 0): Boolean;
    function SetHome(out AHomePos: TMachinePosition): Boolean;
    function PhysicalHoming: Boolean;
    function Zero: Boolean;
    function Status: Boolean;
    function Unlock: Boolean;
    function Pause: Boolean;
    function Resume: Boolean;
    function Stop: Boolean;
    function Jog(AAxis: TAxis; ADistance, AFeed: Double): Boolean;
    function SendGCode(const ALine: string): Boolean;
    function SetFeedRate(AFeed: Double): Boolean;
    function GetHomePosition: TMachinePosition;
    function IsHomePositionSet: Boolean;
  end;

implementation

end.
