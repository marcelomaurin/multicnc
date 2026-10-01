unit multicnc_marlin;
{$mode objfpc}{$H+}{$interfaces corba}

{ Driver Marlin (impressoras 3D e lasers/routers com firmware Marlin 2.x).

  Envio confiavel: linhas numeradas com checksum e Resend (smMarlinChecksum).
  Telemetria: interpreta respostas de M114 (posicao) e M105 (temperaturas,
  inclusive o auto-report de M155). Overrides via M220/M221. }

interface
uses SysUtils, multicnc_types, multicnc_interfaces;

type
  TMarlinTemperatures = record
    Hotend, HotendTarget, Bed, BedTarget: Double;
    Valid: Boolean;
  end;

  TMarlinProtocol = class(TInterfacedObject, IMultiCNCProtocol, IMultiCNCStreamingProtocol)
  private
    FPartial: string;
    FPosition: TMachinePosition;
    FTemps: TMarlinTemperatures;
    FState: TMachineState;
    FFeedPercent: Integer;
    procedure ParseLine(const L: string);
  public
    constructor Create;
    function GetName: string;
    procedure Reset;
    procedure ProcessIncoming(const AData: string);
    function BuildHomeCommand: string;
    function BuildPauseCommand: string;
    function BuildResumeCommand: string;
    function BuildStopCommand: string;
    function BuildJogCommand(AAxis: TAxis; ADistance, AFeed: Double): string;
    { IMultiCNCStreamingProtocol }
    function RecommendedStreamMode: TStreamMode;
    function RxBufferSize: Integer;
    function BuildStatusQuery: string;
    function BuildUnlockCommand: string;
    function BuildFeedOverride(APercent: Integer): string;
    function BuildSpindleOverride(APercent: Integer): string;
    function CurrentState: TMachineState;
    function CurrentPosition: TMachinePosition;
    function BuildTemperatureAutoReport(AIntervalSeconds: Integer): string;
    property Temperatures: TMarlinTemperatures read FTemps;
  end;

implementation

function InvariantFmt(const F: string; const Args: array of const): string;
var FS: TFormatSettings;
begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  Result := Format(F, Args, FS);
end;

function InvFloat(const S: string; Default: Double): Double;
var FS: TFormatSettings;
begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := '.';
  if not TryStrToFloat(S, Result, FS) then Result := Default;
end;

{ Valor numerico apos "Key" (ex.: 'X:' em 'X:10.00 Y:5.00'). }
function ValueAfter(const S, Key: string; out V: Double): Boolean;
var P, Q: Integer;
begin
  P := Pos(Key, S);
  Result := P > 0;
  if not Result then Exit;
  Inc(P, Length(Key));
  Q := P;
  while (Q <= Length(S)) and (S[Q] in ['0'..'9', '.', '-', '+']) do Inc(Q);
  Result := Q > P;
  if Result then V := InvFloat(Copy(S, P, Q - P), 0);
end;

constructor TMarlinProtocol.Create;
begin
  inherited Create;
  Reset;
end;

function TMarlinProtocol.GetName: string; begin Result := 'Marlin'; end;

procedure TMarlinProtocol.Reset;
begin
  FPartial := '';
  FPosition := EmptyPosition;
  FillChar(FTemps, SizeOf(FTemps), 0);
  FState := msIdle;
  FFeedPercent := 100;
end;

procedure TMarlinProtocol.ParseLine(const L: string);
var V, T: Double; Low, Head: string; P: Integer;
begin
  Low := LowerCase(L);
  if (Pos('t:', Low) > 0) and ((Pos('b:', Low) > 0) or (Copy(Low, 1, 2) = 't:') or
    (Copy(Low, 1, 5) = 'ok t:')) then begin
    // ok T:200.0 /200.0 B:60.0 /60.0 @:0 B@:0
    if ValueAfter(L, 'T:', V) then begin
      FTemps.Hotend := V;
      P := Pos('T:', L);
      Head := Copy(L, P, MaxInt);
      if ValueAfter(Head, '/', T) then FTemps.HotendTarget := T;
      FTemps.Valid := True;
    end;
    if ValueAfter(L, 'B:', V) then begin
      FTemps.Bed := V;
      P := Pos('B:', L);
      Head := Copy(L, P, MaxInt);
      if ValueAfter(Head, '/', T) then FTemps.BedTarget := T;
    end;
  end else if (Copy(L, 1, 2) = 'X:') then begin
    // X:10.00 Y:20.00 Z:5.00 E:0.00 Count X:...
    P := Pos(' Count', L);
    if P > 0 then Head := Copy(L, 1, P - 1) else Head := L;
    if ValueAfter(Head, 'X:', V) then FPosition.X := V;
    if ValueAfter(Head, 'Y:', V) then FPosition.Y := V;
    if ValueAfter(Head, 'Z:', V) then FPosition.Z := V;
    if ValueAfter(Head, 'E:', V) then FPosition.E := V;
  end else if (Copy(Low, 1, 5) = 'error') and (Pos('printer halted', Low) > 0) then
    FState := msAlarm
  else if (Copy(Low, 1, 5) = 'error') and (Pos('checksum', Low) = 0) and
    (Pos('line number', Low) = 0) then
    FState := msError
  else if Pos('busy:', Low) > 0 then
    FState := msRunning;
end;

procedure TMarlinProtocol.ProcessIncoming(const AData: string);
var I: Integer; C: Char;
begin
  for I := 1 to Length(AData) do begin
    C := AData[I];
    if (C = #10) or (C = #13) then begin
      if FPartial <> '' then ParseLine(Trim(FPartial));
      FPartial := '';
    end else
      FPartial := FPartial + C;
  end;
end;

function TMarlinProtocol.BuildHomeCommand: string; begin Result := 'G28' + LineEnding; end;
function TMarlinProtocol.BuildPauseCommand: string; begin Result := 'M25' + LineEnding; end;
function TMarlinProtocol.BuildResumeCommand: string; begin Result := 'M24' + LineEnding; end;
function TMarlinProtocol.BuildStopCommand: string; begin Result := 'M524' + LineEnding; end;

function TMarlinProtocol.BuildJogCommand(AAxis: TAxis; ADistance, AFeed: Double): string;
const N: array[TAxis] of string = ('X','Y','Z','A','E');
begin
  Result := InvariantFmt('G91%sG0 %s%.3f F%.0f%sG90%s',
    [LineEnding, N[AAxis], ADistance, AFeed, LineEnding, LineEnding]);
end;

function TMarlinProtocol.RecommendedStreamMode: TStreamMode; begin Result := smMarlinChecksum; end;
function TMarlinProtocol.RxBufferSize: Integer; begin Result := 0; end;
function TMarlinProtocol.BuildStatusQuery: string; begin Result := 'M114' + LineEnding; end;
function TMarlinProtocol.BuildUnlockCommand: string; begin Result := 'M999' + LineEnding; end;

function TMarlinProtocol.BuildFeedOverride(APercent: Integer): string;
begin
  if APercent < 10 then APercent := 10;
  if APercent > 999 then APercent := 999;
  FFeedPercent := APercent;
  Result := Format('M220 S%d', [APercent]) + LineEnding;
end;

function TMarlinProtocol.BuildSpindleOverride(APercent: Integer): string;
begin
  // Em impressoras o equivalente e o fluxo do extrusor (M221).
  if APercent < 10 then APercent := 10;
  if APercent > 999 then APercent := 999;
  Result := Format('M221 S%d', [APercent]) + LineEnding;
end;

function TMarlinProtocol.CurrentState: TMachineState; begin Result := FState; end;
function TMarlinProtocol.CurrentPosition: TMachinePosition; begin Result := FPosition; end;

function TMarlinProtocol.BuildTemperatureAutoReport(AIntervalSeconds: Integer): string;
begin
  Result := Format('M155 S%d', [AIntervalSeconds]) + LineEnding;
end;

end.
