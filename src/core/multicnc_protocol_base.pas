unit multicnc_protocol_base;

{ Base comum dos protocolos: monta linhas a partir dos bytes recebidos e
  acumula confirmacoes, erros, estado e posicao informados pela controladora. }

{$mode objfpc}{$H+}
{$interfaces corba}

interface

uses
  SysUtils, multisuite_numfmt, multicnc_types, multicnc_interfaces;

const
  MaxIncomingLine = 4096;

type
  TMultiCNCProtocolBase = class(TInterfacedObject, IMultiCNCProtocol)
  protected
    FBuffer: string;
    FAcks, FErrors: Integer;
    FHasState, FHasPosition, FResetDetected: Boolean;
    FState: TMachineState;
    FPosition: TMachinePosition;
    FLastMessage: string;
    procedure HandleLine(const ALine: string); virtual; abstract;
    procedure SetState(AState: TMachineState);
    procedure SetMessage(const AText: string);
  public
    function GetName: string; virtual; abstract;
    procedure Reset; virtual;
    procedure ProcessIncoming(const AData: string);
    function TakeResponses(out Acks, Errors: Integer): Boolean;
    function ReportedState(out AState: TMachineState): Boolean;
    function ReportedPosition(out APosition: TMachinePosition): Boolean;
    function TakeResetDetected: Boolean;
    function LastMessage: string;
    function ReceiveBufferSize: Integer; virtual; abstract;
    function BuildHomeCommand: string; virtual; abstract;
    function BuildZeroCommand: string; virtual; abstract;
    function BuildStatusCommand: string; virtual; abstract;
    function BuildUnlockCommand: string; virtual; abstract;
    function BuildPauseCommand: string; virtual; abstract;
    function BuildResumeCommand: string; virtual; abstract;
    function BuildStopCommand: string; virtual; abstract;
    function BuildSafeOffCommands(AType: TMachineType): string; virtual;
    function BuildJogCommand(AAxis: TAxis; ADistance, AFeed: Double): string; virtual; abstract;
  end;

{ Le 'x,y,z[,a]' com ponto decimal. }
function ParseAxisList(const S: string; out P: TMachinePosition): Boolean;
{ Valor numerico depois de 'Key' (ex.: 'X:' em 'X:10.00 Y:...'). }
function ValueAfter(const S, Key: string; out V: Double): Boolean;

implementation

function ParseAxisList(const S: string; out P: TMachinePosition): Boolean;
var Parts: array[0..4] of Double; Rest, Item: string; N, C: Integer;
begin
  P := EmptyPosition;
  Rest := S; N := 0;
  while (Rest <> '') and (N <= High(Parts)) do
  begin
    C := Pos(',', Rest);
    if C = 0 then begin Item := Rest; Rest := ''; end
    else begin Item := Copy(Rest, 1, C - 1); Delete(Rest, 1, C); end;
    if not TryStrToFloat(Trim(Item), Parts[N], InvariantFS) then Exit(False);
    Inc(N);
  end;
  Result := N >= 3;
  if not Result then Exit;
  P.X := Parts[0]; P.Y := Parts[1]; P.Z := Parts[2];
  if N >= 4 then P.A := Parts[3];
end;

function ValueAfter(const S, Key: string; out V: Double): Boolean;
var I, J: Integer;
begin
  Result := False;
  V := 0;
  I := Pos(Key, S);
  if I = 0 then Exit;
  Inc(I, Length(Key));
  while (I <= Length(S)) and (S[I] = ' ') do Inc(I);
  J := I;
  while (J <= Length(S)) and (S[J] in ['0'..'9', '-', '+', '.']) do Inc(J);
  Result := (J > I) and TryStrToFloat(Copy(S, I, J - I), V, InvariantFS);
end;

procedure TMultiCNCProtocolBase.SetState(AState: TMachineState);
begin
  FState := AState;
  FHasState := True;
end;

procedure TMultiCNCProtocolBase.SetMessage(const AText: string);
begin
  FLastMessage := AText;
end;

procedure TMultiCNCProtocolBase.Reset;
begin
  FBuffer := '';
  FAcks := 0;
  FErrors := 0;
  FHasState := False;
  FHasPosition := False;
  FResetDetected := False;
  FPosition := EmptyPosition;
  FLastMessage := '';
end;

procedure TMultiCNCProtocolBase.ProcessIncoming(const AData: string);
var I: Integer; Line: string;
begin
  for I := 1 to Length(AData) do
    if AData[I] in [#10, #13] then
    begin
      Line := Trim(FBuffer);
      FBuffer := '';
      if Line <> '' then HandleLine(Line);
    end
    else if Length(FBuffer) < MaxIncomingLine then
      FBuffer := FBuffer + AData[I];
end;

function TMultiCNCProtocolBase.TakeResponses(out Acks, Errors: Integer): Boolean;
begin
  Acks := FAcks;
  Errors := FErrors;
  FAcks := 0;
  FErrors := 0;
  Result := (Acks > 0) or (Errors > 0);
end;

function TMultiCNCProtocolBase.ReportedState(out AState: TMachineState): Boolean;
begin
  AState := FState;
  Result := FHasState;
  FHasState := False; { cada relatorio e entregue uma vez }
end;

function TMultiCNCProtocolBase.ReportedPosition(out APosition: TMachinePosition): Boolean;
begin
  APosition := FPosition;
  Result := FHasPosition;
  FHasPosition := False;
end;

function TMultiCNCProtocolBase.TakeResetDetected: Boolean;
begin
  Result := FResetDetected;
  FResetDetected := False;
end;

function TMultiCNCProtocolBase.LastMessage: string;
begin
  Result := FLastMessage;
end;

function TMultiCNCProtocolBase.BuildSafeOffCommands(AType: TMachineType): string;
begin
  Result := '';
end;

end.
