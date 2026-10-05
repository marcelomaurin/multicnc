unit multicnc_simulator;

{ Transporte e protocolo de demonstracao, sem hardware. O transporte responde
  "ok" para cada linha recebida e um relatorio de estado para '?', como uma
  controladora GRBL, para que o envio com confirmacao funcione igual ao real. }

{$mode objfpc}{$H+}
{$interfaces corba}

interface

uses
  Classes, SysUtils, multisuite_numfmt, multicnc_types, multicnc_interfaces,
  multicnc_protocol_base;

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
    procedure Poll;
    procedure SetOnData(AEvent: TTransportDataEvent);
    procedure SetOnState(AEvent: TTransportStateEvent);
    function GetName: string;
  end;

  TSimulatorProtocol = class(TMultiCNCProtocolBase)
  protected
    procedure HandleLine(const ALine: string); override;
  public
    function GetName: string; override;
    function ReceiveBufferSize: Integer; override;
    function BuildHomeCommand(AFeed: Double = 0): string; override;
    function BuildSetHomeCommand: string; override;
    function BuildPhysicalHomingCommand: string; override;
    function BuildFeedRateCommand(AFeed: Double): string; override;
    function BuildZeroCommand: string; override;
    function BuildStatusCommand: string; override;
    function BuildUnlockCommand: string; override;
    function BuildPauseCommand: string; override;
    function BuildResumeCommand: string; override;
    function BuildStopCommand: string; override;
    function BuildJogCommand(AAxis: TAxis; ADistance, AFeed: Double): string; override;
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
var Lines: TStringList; I: Integer; Reply: string;
begin
  Result := FConnected;
  if not Result then Exit;
  Reply := '';
  if Pos('?', AData) > 0 then Reply := '<Idle|MPos:0.000,0.000,0.000|FS:0,0>' + LineEnding;
  if Pos(#24, AData) > 0 then Reply := Reply + 'Grbl 1.1h [''$'' for help]' + LineEnding;
  Lines := TStringList.Create;
  try
    Lines.Text := AData;
    { Somente linhas terminadas em quebra de linha sao confirmadas. }
    if (AData <> '') and (AData[Length(AData)] in [#10, #13]) then
      for I := 0 to Lines.Count - 1 do
        if Trim(Lines[I]) <> '' then
          Reply := Reply + 'SIM> ' + Trim(Lines[I]) + LineEnding + 'ok' + LineEnding;
  finally
    Lines.Free;
  end;
  if (Reply <> '') and Assigned(FOnData) then FOnData(Reply);
end;

procedure TSimulatorTransport.Poll;
begin
end;

procedure TSimulatorTransport.SetOnData(AEvent: TTransportDataEvent);
begin FOnData := AEvent; end;

procedure TSimulatorTransport.SetOnState(AEvent: TTransportStateEvent);
begin FOnState := AEvent; end;

function TSimulatorTransport.GetName: string;
begin Result := 'MultiCNC Simulator'; end;

procedure TSimulatorProtocol.HandleLine(const ALine: string);
begin
  if SameText(ALine, 'ok') then Inc(FAcks)
  else if SameText(Copy(ALine, 1, 6), 'error:') then
  begin
    Inc(FAcks); Inc(FErrors); SetMessage(ALine);
  end
  else if Copy(ALine, 1, 5) = 'Grbl ' then
  begin
    FResetDetected := True; SetState(msIdle);
  end
  else if (ALine[1] = '<') and (Pos('Idle', ALine) = 2) then
    SetState(msIdle);
end;

function TSimulatorProtocol.GetName: string;
begin Result := 'Simulator'; end;

function TSimulatorProtocol.ReceiveBufferSize: Integer;
begin Result := 127; end;

function TSimulatorProtocol.BuildSetHomeCommand: string;
begin
  Result := 'G28.1' + LineEnding;
end;

function TSimulatorProtocol.BuildHomeCommand(AFeed: Double = 0): string;
begin
  if AFeed > 0 then
    Result := Format('G28 F%.0f%s', [AFeed, LineEnding], InvariantFS)
  else
    Result := 'G28' + LineEnding;
end;

function TSimulatorProtocol.BuildPhysicalHomingCommand: string;
begin
  Result := '$H' + LineEnding;
end;

function TSimulatorProtocol.BuildFeedRateCommand(AFeed: Double): string;
begin
  Result := Format('G0 F%.0f%s', [AFeed, LineEnding], InvariantFS);
end;
function TSimulatorProtocol.BuildZeroCommand: string;
begin Result := 'G92 X0 Y0 Z0' + LineEnding; end;
function TSimulatorProtocol.BuildStatusCommand: string;
begin Result := '?' end;
function TSimulatorProtocol.BuildUnlockCommand: string;
begin Result := '$X' + LineEnding; end;
function TSimulatorProtocol.BuildPauseCommand: string;
begin Result := '!'; end;
function TSimulatorProtocol.BuildResumeCommand: string;
begin Result := '~'; end;
function TSimulatorProtocol.BuildStopCommand: string;
begin Result := #24; end;

function TSimulatorProtocol.BuildJogCommand(AAxis: TAxis; ADistance, AFeed: Double): string;
const
  AxisName: array[TAxis] of string = ('X','Y','Z','A','E');
begin
  Result := Format('$J=G91 %s%.3f F%.0f%s',
    [AxisName[AAxis], ADistance, AFeed, LineEnding], InvariantFS);
end;

end.
