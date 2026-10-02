unit multicnc_grbl;
{$mode objfpc}{$H+}{$interfaces corba}

{ Drivers da familia GRBL.

  TGRBLProtocol   - Grbl 1.1 (Arduino/ATmega328P), RX de 128 bytes.
  TGrblHALProtocol - grblHAL (STM32, RP2040, ESP32, Teensy...), RX de 1024
                     bytes e comandos de tempo real estendidos.
  TFluidNCProtocol - FluidNC (ESP32, configuracao YAML, Wi-Fi/telnet).

  ProcessIncoming interpreta status, alarmes e erros (multicnc_grbl_status)
  e mantem estado/posicao da maquina atualizados para a UI e para o
  streamer. }

interface
uses SysUtils, multicnc_types, multicnc_interfaces, multicnc_grbl_status,
  multicnc_realtime;

type
  TGrblResponseEvent = procedure(const AResponse: TGrblResponse) of object;

  TGRBLProtocol = class(TInterfacedObject, IMultiCNCProtocol, IMultiCNCStreamingProtocol)
  private
    FParser: TGrblStatusParser;
    FPartial: string;
    FOnResponse: TGrblResponseEvent;
  public
    constructor Create; virtual;
    destructor Destroy; override;
    function GetName: string; virtual;
    procedure Reset;
    procedure ProcessIncoming(const AData: string);
    function BuildHomeCommand: string;
    function BuildPauseCommand: string;
    function BuildResumeCommand: string;
    function BuildStopCommand: string;
    function BuildJogCommand(AAxis: TAxis; ADistance, AFeed: Double): string;
    { IMultiCNCStreamingProtocol }
    function RecommendedStreamMode: TStreamMode;
    function RxBufferSize: Integer; virtual;
    function BuildStatusQuery: string; virtual;
    function BuildUnlockCommand: string;
    function BuildFeedOverride(APercent: Integer): string;
    function BuildSpindleOverride(APercent: Integer): string;
    function CurrentState: TMachineState;
    function CurrentPosition: TMachinePosition;
    { extras }
    function BuildJogCancel: string;
    function BuildRealtime(ACmd: TRealtimeCommand): string;
    function BuildProbeCommand(ADistance, AFeed: Double): string;
    property Parser: TGrblStatusParser read FParser;
    property OnResponse: TGrblResponseEvent read FOnResponse write FOnResponse;
  end;

  TGrblHALProtocol = class(TGRBLProtocol)
  public
    function GetName: string; override;
    function RxBufferSize: Integer; override;
    function BuildStatusQuery: string; override;
  end;

  TFluidNCProtocol = class(TGRBLProtocol)
  public
    function GetName: string; override;
  end;

implementation

const AxisNames: array[TAxis] of string = ('X','Y','Z','A','E');

function InvariantFmt(const F: string; const Args: array of const): string;
var FS: TFormatSettings;
begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  Result := Format(F, Args, FS);
end;

constructor TGRBLProtocol.Create;
begin
  inherited Create;
  FParser := TGrblStatusParser.Create;
end;

destructor TGRBLProtocol.Destroy;
begin
  FParser.Free;
  inherited Destroy;
end;

function TGRBLProtocol.GetName: string; begin Result := 'GRBL'; end;

procedure TGRBLProtocol.Reset;
begin
  FParser.Reset;
  FPartial := '';
end;

procedure TGRBLProtocol.ProcessIncoming(const AData: string);
var I: Integer; C: Char; R: TGrblResponse;
begin
  for I := 1 to Length(AData) do begin
    C := AData[I];
    if (C = #10) or (C = #13) then begin
      if FPartial <> '' then begin
        R := FParser.ParseLine(FPartial);
        if (R.Kind <> grkNone) and Assigned(FOnResponse) then FOnResponse(R);
      end;
      FPartial := '';
    end else
      FPartial := FPartial + C;
  end;
end;

function TGRBLProtocol.BuildHomeCommand: string; begin Result := '$H' + LineEnding; end;
function TGRBLProtocol.BuildPauseCommand: string; begin Result := '!'; end;
function TGRBLProtocol.BuildResumeCommand: string; begin Result := '~'; end;
function TGRBLProtocol.BuildStopCommand: string; begin Result := #24; end;

function TGRBLProtocol.BuildJogCommand(AAxis: TAxis; ADistance, AFeed: Double): string;
begin
  Result := InvariantFmt('$J=G91 G21 %s%.3f F%.0f%s', [AxisNames[AAxis], ADistance, AFeed, LineEnding]);
end;

function TGRBLProtocol.RecommendedStreamMode: TStreamMode; begin Result := smCharacterCounting; end;
function TGRBLProtocol.RxBufferSize: Integer; begin Result := 128; end;
function TGRBLProtocol.BuildStatusQuery: string; begin Result := '?'; end;
function TGRBLProtocol.BuildUnlockCommand: string; begin Result := '$X' + LineEnding; end;

function TGRBLProtocol.BuildFeedOverride(APercent: Integer): string;
begin
  Result := multicnc_realtime.BuildFeedOverride(FParser.Status.FeedOverride, APercent);
end;

function TGRBLProtocol.BuildSpindleOverride(APercent: Integer): string;
begin
  Result := multicnc_realtime.BuildSpindleOverride(FParser.Status.SpindleOverride, APercent);
end;

function TGRBLProtocol.CurrentState: TMachineState;
begin
  if FParser.Status.State = gsUnknown then Result := msConnecting
  else Result := GrblStateToMachineState(FParser.Status.State);
end;

function TGRBLProtocol.CurrentPosition: TMachinePosition;
begin
  Result := FParser.Status.WPos;
end;

function TGRBLProtocol.BuildJogCancel: string;
begin
  Result := RealtimeByte(rtJogCancel);
end;

function TGRBLProtocol.BuildRealtime(ACmd: TRealtimeCommand): string;
begin
  if RealtimeSupported(ACmd, FParser.Firmware) or
    ((FParser.Firmware = gfUnknown) and (Self is TGrblHALProtocol)) then
    Result := RealtimeByte(ACmd)
  else
    Result := '';
end;

function TGRBLProtocol.BuildProbeCommand(ADistance, AFeed: Double): string;
begin
  // G38.2: sonda ate tocar; erro se nao houver contato (ALARM:5)
  Result := InvariantFmt('G38.2 G91 Z%.3f F%.0f%sG90%s', [-Abs(ADistance), AFeed, LineEnding, LineEnding]);
end;

function TGrblHALProtocol.GetName: string; begin Result := 'grblHAL'; end;
function TGrblHALProtocol.RxBufferSize: Integer; begin Result := 1024; end;
function TGrblHALProtocol.BuildStatusQuery: string; begin Result := '?'; end;

function TFluidNCProtocol.GetName: string; begin Result := 'FluidNC'; end;

end.
