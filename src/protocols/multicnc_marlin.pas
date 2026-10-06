unit multicnc_marlin;

{ Marlin com envio pelo host: uma linha por vez, aguardando "ok".
  M25/M24/M524 so atuam em impressao pelo cartao SD; com envio pelo host a
  pausa e feita parando o envio, e a parada usa M410 (quickstop), que limpa o
  planejador de movimentos. Como so ha uma linha pendente, o M410 entra na fila
  logo em seguida. Com EMERGENCY_PARSER ativo no firmware ele e imediato. }

{$mode objfpc}{$H+}
{$interfaces corba}

interface

uses
  SysUtils, multisuite_numfmt, multicnc_types, multicnc_interfaces,
  multicnc_protocol_base;

type
  TMarlinProtocol = class(TMultiCNCProtocolBase)
  private
    procedure ParsePosition(const S: string);
  protected
    procedure HandleLine(const ALine: string); override;
  public
    function GetName: string; override;
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
    function BuildSafeOffCommands(AType: TMachineType): string; override;
    function BuildJogCommand(AAxis: TAxis; ADistance, AFeed: Double): string; override;
    function BuildFeedRateCommand(AFeed: Double): string; override;
    function BuildQueryTemperaturesCommand: string; override;
    function BuildSetHotendTemperatureCommand(ATemp: Double): string; override;
    function BuildSetBedTemperatureCommand(ATemp: Double): string; override;
  end;

implementation

function TMarlinProtocol.GetName: string;
begin
  Result := 'Marlin';
end;

{ X:10.00 Y:20.00 Z:0.00 E:0.00 Count X:800 Y:1600 Z:0 }
procedure TMarlinProtocol.ParsePosition(const S: string);
var Head: string; C: Integer; X, Y, Z, E: Double;
begin
  Head := S;
  C := Pos('Count', Head);
  if C > 0 then Head := Copy(Head, 1, C - 1);
  if ValueAfter(Head, 'X:', X) and ValueAfter(Head, 'Y:', Y) and ValueAfter(Head, 'Z:', Z) then
  begin
    FPosition.X := X; FPosition.Y := Y; FPosition.Z := Z;
    if ValueAfter(Head, 'E:', E) then FPosition.E := E;
    FHasPosition := True;
  end;
end;

procedure TMarlinProtocol.HandleLine(const ALine: string);
var L: string;
begin
  L := LowerCase(ALine);
  if Copy(L, 1, 2) = 'ok' then
  begin
    Inc(FAcks);
    { "ok" pode trazer temperaturas: "ok T:200.0 /200.0 B:60.0 /60.0" }
    if (Pos('t:', L) > 0) or (Pos('b:', L) > 0) then
      if ParseMarlinTemperatures(ALine, FTemperatures) then
        FHasTemperatures := True;
  end
  else if (Pos('t:', L) > 0) and ((Pos('/', L) > 0) or (Pos('b:', L) > 0)) then
  begin
    if ParseMarlinTemperatures(ALine, FTemperatures) then
      FHasTemperatures := True;
  end
  else if L = 'start' then
  begin
    FResetDetected := True;
    SetState(msIdle);
    SetMessage(ALine);
  end
  else if (Copy(L, 1, 6) = 'error:') or (L = '!!') then
  begin
    Inc(FErrors);
    SetMessage(ALine);
    if (Pos('halted', L) > 0) or (Pos('kill', L) > 0) or (Pos('stopped', L) > 0) or
      (Pos('thermal', L) > 0) or (L = '!!') then
      SetState(msAlarm);
  end
  else if Copy(L, 1, 7) = 'resend:' then
  begin
    Inc(FErrors);
    SetMessage(ALine);
  end
  else if (Copy(L, 1, 2) = 'x:') and (Pos('y:', L) > 0) and (Pos('z:', L) > 0) then
    ParsePosition(ALine)
  else if Copy(L, 1, 5) = 'echo:' then
  begin
    if Pos('busy', L) = 0 then SetMessage(ALine);
  end;
end;

function TMarlinProtocol.ReceiveBufferSize: Integer;
begin
  Result := 0; { uma linha por vez }
end;

function TMarlinProtocol.BuildSetHomeCommand: string;
begin
  Result := 'G28.1' + LineEnding;
end;

function TMarlinProtocol.BuildHomeCommand(AFeed: Double = 0): string;
begin
  if AFeed > 0 then
    Result := Format('G28 F%.0f%s', [AFeed, LineEnding], InvariantFS)
  else
    Result := 'G28' + LineEnding;
end;

function TMarlinProtocol.BuildPhysicalHomingCommand: string;
begin
  Result := 'G28' + LineEnding;
end;

function TMarlinProtocol.BuildZeroCommand: string;
begin
  Result := 'G92 X0 Y0 Z0' + LineEnding;
end;

function TMarlinProtocol.BuildStatusCommand: string;
begin
  Result := 'M114' + LineEnding;
end;

function TMarlinProtocol.BuildUnlockCommand: string;
begin
  Result := 'M999' + LineEnding;
end;

function TMarlinProtocol.BuildPauseCommand: string;
begin
  Result := '';
end;

function TMarlinProtocol.BuildResumeCommand: string;
begin
  Result := '';
end;

function TMarlinProtocol.BuildStopCommand: string;
begin
  Result := 'M410' + LineEnding;
end;

function TMarlinProtocol.BuildSafeOffCommands(AType: TMachineType): string;
begin
  case AType of
    mtPrinter3D: Result := 'M104 S0' + LineEnding + 'M140 S0' + LineEnding + 'M107' + LineEnding;
  else
    Result := 'M5' + LineEnding;
  end;
end;

function TMarlinProtocol.BuildJogCommand(AAxis: TAxis; ADistance, AFeed: Double): string;
const N: array[TAxis] of string = ('X', 'Y', 'Z', 'A', 'E');
begin
  Result := Format('G91%sG0 %s%.3f F%.0f%sG90%s',
    [LineEnding, N[AAxis], ADistance, AFeed, LineEnding, LineEnding], InvariantFS);
end;

function TMarlinProtocol.BuildFeedRateCommand(AFeed: Double): string;
begin
  Result := Format('G0 F%.0f%s', [AFeed, LineEnding], InvariantFS);
end;

function TMarlinProtocol.BuildQueryTemperaturesCommand: string;
begin
  Result := 'M105' + LineEnding;
end;

function TMarlinProtocol.BuildSetHotendTemperatureCommand(ATemp: Double): string;
begin
  Result := Format('M104 S%.0f%s', [ATemp, LineEnding], InvariantFS);
end;

function TMarlinProtocol.BuildSetBedTemperatureCommand(ATemp: Double): string;
begin
  Result := Format('M140 S%.0f%s', [ATemp, LineEnding], InvariantFS);
end;

end.
