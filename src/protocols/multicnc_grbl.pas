unit multicnc_grbl;

{ GRBL 1.1: envio por contagem de caracteres (buffer serial de 128 bytes),
  comandos de tempo real e leitura do relatorio de estado <...>. }

{$mode objfpc}{$H+}{$interfaces corba}

interface

uses
  SysUtils, multisuite_numfmt, multicnc_types, multicnc_interfaces,
  multicnc_protocol_base, multicnc_grbl_status, multicnc_realtime;

type
  TGRBLProtocol = class(TMultiCNCProtocolBase, IMultiCNCStreamingProtocol)
  private
    FParser: TGrblStatusParser;
    FWCO: TMachinePosition;
    FMPos: TMachinePosition;
    procedure ParseStatus(const S: string);
  protected
    procedure HandleLine(const ALine: string); override;
  public
    constructor Create;
    destructor Destroy; override;
    function RecommendedStreamMode: TStreamMode;
    function RxBufferSize: Integer; virtual;
    function BuildStatusQuery: string; virtual;
    function BuildFeedOverride(APercent: Integer): string;
    function BuildSpindleOverride(APercent: Integer): string;
    function CurrentState: TMachineState;
    function CurrentPosition: TMachinePosition;
    function BuildJogCancel: string;
    function BuildRealtime(ACmd: TRealtimeCommand): string;
    function BuildProbeCommand(ADistance, AFeed: Double): string;
    property Parser: TGrblStatusParser read FParser;
    function GetName: string; override;
    procedure Reset; override;
    function ReceiveBufferSize: Integer; override;
    function BuildHomeCommand(AFeed: Double = 0): string; override;
    function BuildSetHomeCommand: string; override;
    function BuildPhysicalHomingCommand: string; override;
    function BuildZeroCommand: string; override;
    function BuildStatusCommand: string; override;
    function BuildUnlockCommand: string; override;
    function BuildPauseCommand: string; override;
    function BuildResumeCommand: string; override;
    function BuildStopCommand: string; override;
    function BuildJogCommand(AAxis: TAxis; ADistance, AFeed: Double): string; override;
    function BuildFeedRateCommand(AFeed: Double): string; override;
    procedure ResetPositionToZero; override;
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

constructor TGRBLProtocol.Create;
begin inherited Create; FParser := TGrblStatusParser.Create; Reset; end;
destructor TGRBLProtocol.Destroy;
begin FParser.Free; inherited Destroy; end;

function TGRBLProtocol.RecommendedStreamMode: TStreamMode; begin Result := smCharacterCounting; end;
function TGRBLProtocol.RxBufferSize: Integer; begin Result := 128; end;
function TGRBLProtocol.BuildStatusQuery: string; begin Result := '?'; end;

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
  Result := Format('G38.2 G91 Z%.3f F%.0f%sG90%s', [-Abs(ADistance), AFeed, LineEnding, LineEnding], InvariantFS);
end;

function TGrblHALProtocol.GetName: string; begin Result := 'grblHAL'; end;
function TGrblHALProtocol.RxBufferSize: Integer; begin Result := 1024; end;
function TGrblHALProtocol.BuildStatusQuery: string; begin Result := '?'; end;

function TFluidNCProtocol.GetName: string; begin Result := 'FluidNC'; end;



function TGRBLProtocol.GetName: string;
begin
  Result := 'GRBL';
end;

procedure TGRBLProtocol.Reset;
begin
  inherited Reset;
  if Assigned(FParser) then FParser.Reset;
  FWCO := EmptyPosition;
  FMPos := EmptyPosition;
end;

{ <Idle|MPos:1.000,2.000,3.000|FS:0,0|WCO:0.000,0.000,0.000> }
procedure TGRBLProtocol.ParseStatus(const S: string);
var Body, Field, StateName: string; P, C: Integer; MPos, WPos, W: TMachinePosition;
  HasM, HasW: Boolean;
begin
  Body := Copy(S, 2, Length(S) - 2);
  HasM := False; HasW := False;
  P := Pos('|', Body);
  if P = 0 then begin StateName := Body; Body := ''; end
  else begin StateName := Copy(Body, 1, P - 1); Delete(Body, 1, P); end;
  C := Pos(':', StateName);
  if C > 0 then StateName := Copy(StateName, 1, C - 1);
  if SameText(StateName, 'Idle') then SetState(msIdle)
  else if SameText(StateName, 'Run') or SameText(StateName, 'Jog') or
    SameText(StateName, 'Home') then SetState(msRunning)
  else if SameText(StateName, 'Hold') or SameText(StateName, 'Door') then SetState(msPaused)
  else if SameText(StateName, 'Alarm') then SetState(msAlarm)
  else SetState(msIdle); { Check, Sleep }
  while Body <> '' do
  begin
    P := Pos('|', Body);
    if P = 0 then begin Field := Body; Body := ''; end
    else begin Field := Copy(Body, 1, P - 1); Delete(Body, 1, P); end;
    if Copy(Field, 1, 5) = 'MPos:' then
    begin
      HasM := ParseAxisList(Copy(Field, 6, MaxInt), MPos);
      if HasM then FMPos := MPos;
    end
    else if Copy(Field, 1, 5) = 'WPos:' then HasW := ParseAxisList(Copy(Field, 6, MaxInt), WPos)
    else if Copy(Field, 1, 4) = 'WCO:' then
    begin
      if ParseAxisList(Copy(Field, 5, MaxInt), W) then FWCO := W;
    end;
  end;
  if HasW then
  begin
    FPosition := WPos; FHasPosition := True;
  end
  else if HasM then
  begin
    FPosition.X := MPos.X - FWCO.X;
    FPosition.Y := MPos.Y - FWCO.Y;
    FPosition.Z := MPos.Z - FWCO.Z;
    FPosition.A := MPos.A - FWCO.A;
    FHasPosition := True;
  end;
end;

procedure TGRBLProtocol.HandleLine(const ALine: string);
var L: string;
begin
  FParser.ParseLine(ALine);
  L := LowerCase(ALine);
  if L = 'ok' then
    Inc(FAcks)
  else if Copy(L, 1, 6) = 'error:' then
  begin
    { No GRBL, "error:" substitui o "ok" da linha: libera o buffer e e erro. }
    Inc(FAcks);
    Inc(FErrors);
    SetMessage(ALine);
  end
  else if Copy(L, 1, 6) = 'alarm:' then
  begin
    SetState(msAlarm);
    SetMessage(ALine);
  end
  else if (ALine[1] = '<') and (ALine[Length(ALine)] = '>') then
    ParseStatus(ALine)
  else if (Copy(L, 1, 5) = 'grbl ') or (Copy(L, 1, 7) = 'grblhal') then
  begin
    { Reinicio (#24 ou reset fisico): a controladora descartou a fila. }
    FWCO := EmptyPosition;
    FHasPosition := False;
    FResetDetected := True;
    SetState(msIdle);
    SetMessage(ALine);
  end
  else if Copy(ALine, 1, 5) = '[MSG:' then
    SetMessage(ALine);
end;

function TGRBLProtocol.ReceiveBufferSize: Integer;
begin
  Result := 127; { RX_BUFFER_SIZE 128 do GRBL, menos uma margem }
end;

function TGRBLProtocol.BuildSetHomeCommand: string;
begin
  Result := 'G28.1' + LineEnding;
end;

function TGRBLProtocol.BuildHomeCommand(AFeed: Double = 0): string;
begin
  if AFeed > 0 then
    Result := Format('G28 F%.0f%s', [AFeed, LineEnding], InvariantFS)
  else
    Result := 'G28' + LineEnding;
end;

function TGRBLProtocol.BuildPhysicalHomingCommand: string;
begin
  Result := '$H' + LineEnding;
end;
function TGRBLProtocol.BuildZeroCommand: string; begin Result := 'G92 X0 Y0 Z0' + LineEnding; end;
function TGRBLProtocol.BuildStatusCommand: string; begin Result := '?'; end;
function TGRBLProtocol.BuildUnlockCommand: string; begin Result := '$X' + LineEnding; end;
function TGRBLProtocol.BuildPauseCommand: string; begin Result := '!'; end;
function TGRBLProtocol.BuildResumeCommand: string; begin Result := '~'; end;
{ Soft reset: para os motores imediatamente e desliga spindle, laser e
  refrigeracao. A controladora responde com "Grbl x.y". }
function TGRBLProtocol.BuildStopCommand: string; begin Result := #24; end;

function TGRBLProtocol.BuildJogCommand(AAxis: TAxis; ADistance, AFeed: Double): string;
const N: array[TAxis] of string = ('X', 'Y', 'Z', 'A', 'E');
begin
  Result := Format('$J=G91 G21 %s%.3f F%.0f%s', [N[AAxis], ADistance, AFeed, LineEnding], InvariantFS);
end;

function TGRBLProtocol.BuildFeedRateCommand(AFeed: Double): string;
begin
  Result := Format('G0 F%.0f%s', [AFeed, LineEnding], InvariantFS);
end;

procedure TGRBLProtocol.ResetPositionToZero;
begin
  inherited ResetPositionToZero;
  FWCO := FMPos;
end;

end.
