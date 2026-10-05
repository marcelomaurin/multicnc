program test_grbl_regressions;
{ Nucleo do MultiCNC contra controladoras falsas (sem hardware, sem LCL):
  controle de fluxo GRBL/Marlin, erros, alarmes, leitura de estado/posicao,
  bloqueios de seguranca, parada e execucao de programa pela sessao. }
{$mode objfpc}{$H+}{$interfaces corba}
uses
  Classes, SysUtils, multisuite_numfmt, multicnc_types, multicnc_interfaces,
  multicnc_machine, multicnc_safety, multicnc_grbl, multicnc_marlin,
  multicnc_protocol_base;

type
  { Controladora falsa: guarda o que foi enviado e so responde quando o teste
    manda. Verifica o limite do buffer serial do GRBL (128 bytes) e o envio
    de uma linha por vez no Marlin. }
  TFakeController = class(TInterfacedObject, IMultiCNCTransport)
  public
    Connected: Boolean;
    OnData: TTransportDataEvent;
    Sent: TStringList;       { linhas recebidas (sem LF) }
    Realtime: string;        { bytes de tempo real recebidos }
    Pending: TStringList;    { linhas sem resposta }
    PendingBytes, MaxPendingBytes, MaxPendingLines: Integer;
    constructor Create;
    destructor Destroy; override;
    function Connect: Boolean;
    procedure Disconnect;
    function IsConnected: Boolean;
    function Send(const AData: string): Boolean;
    procedure Poll;
    procedure SetOnData(AEvent: TTransportDataEvent);
    procedure SetOnState(AEvent: TTransportStateEvent);
    function GetName: string;
    procedure Reply(const Text: string);
    { Responde "ok" para as N linhas mais antigas. }
    procedure Ack(N: Integer);
  end;

var
  Failures: Integer = 0;

procedure Check(Cond: Boolean; const Msg: string);
begin
  if not Cond then begin Writeln('FAIL: ', Msg); Inc(Failures); end;
end;

constructor TFakeController.Create;
begin
  inherited Create;
  Sent := TStringList.Create;
  Pending := TStringList.Create;
end;

destructor TFakeController.Destroy;
begin
  Sent.Free; Pending.Free;
  inherited Destroy;
end;

function TFakeController.Connect: Boolean; begin Connected := True; Result := True; end;
procedure TFakeController.Disconnect; begin Connected := False; end;
function TFakeController.IsConnected: Boolean; begin Result := Connected; end;
procedure TFakeController.Poll; begin end;
procedure TFakeController.SetOnData(AEvent: TTransportDataEvent); begin OnData := AEvent; end;
procedure TFakeController.SetOnState(AEvent: TTransportStateEvent); begin end;
function TFakeController.GetName: string; begin Result := 'fake'; end;

function TFakeController.Send(const AData: string): Boolean;
var L: string;
begin
  Result := Connected;
  if not Result then Exit;
  if (AData <> '') and (AData[Length(AData)] = #10) then
  begin
    L := Copy(AData, 1, Length(AData) - 1);
    Check(Pos(#10, L) = 0, 'uma linha por Send');
    Sent.Add(L);
    Pending.Add(L);
    Inc(PendingBytes, Length(AData));
    if PendingBytes > MaxPendingBytes then MaxPendingBytes := PendingBytes;
    if Pending.Count > MaxPendingLines then MaxPendingLines := Pending.Count;
  end
  else
    Realtime := Realtime + AData;
end;

procedure TFakeController.Reply(const Text: string);
begin
  if Assigned(OnData) then OnData(Text);
end;

procedure TFakeController.Ack(N: Integer);
begin
  while (N > 0) and (Pending.Count > 0) do
  begin
    Dec(PendingBytes, Length(Pending[0]) + 1);
    Pending.Delete(0);
    Reply('ok' + #13#10);
    Dec(N);
  end;
end;

function NewMachine(Kind: TMachineType; Marlin: Boolean; out F: TFakeController): TMultiCNCMachine;
var P: IMultiCNCProtocol;
begin
  F := TFakeController.Create;
  if Marlin then P := TMarlinProtocol.Create else P := TGRBLProtocol.Create;
  Result := TMultiCNCMachine.Create(Kind, F, P);
  Check(Result.Connect, 'conectar');
end;

procedure TestPauseAndReset;
var M: TMultiCNCMachine; F: TFakeController; I, N: Integer;
begin
  M := NewMachine(mtRouter, False, F);
  for I := 1 to 40 do Check(M.SendGCode('G1 X1 F500'), 'enqueue');
  Check(M.QueuedLines > 0, 'host queue populated');
  Check(M.Pause, 'pause'); N := F.Sent.Count;
  F.Ack(F.Pending.Count);
  F.Reply('<Hold:0|MPos:0,0,0>' + #10);
  Check(F.Sent.Count = N, 'acks and status cannot drain paused queue');
  Check(M.Resume, 'resume');
  while F.Pending.Count > 0 do F.Ack(1);
  Check(F.Sent.Count = 40, 'resume sends each line once');
  Check(F.MaxPendingBytes <= 127, 'RX capacity respected');
  Check(M.Stop, 'stop');
  Check(not M.SendGCode('G1 X2'), 'reject until reset banner');
  Check(not M.Resume, 'no resume during reset');
  F.Reply('ok' + #10);
  Check(not M.SendGCode('G1 X2'), 'old ack cannot complete reset');
  F.Reply('Grbl 1.1h' + #10);
  Check(M.SendGCode('G1 X2'), 'new command after reset banner');
  M.Free; F.Free;
end;

procedure TestLimitsAndRealtime;
var M: TMultiCNCMachine; F: TFakeController; L: string; N: Integer;
begin
  M := NewMachine(mtRouter, False, F);
  L := 'G1 X1 (' + StringOfChar('a', 71) + ')';
  Check(Length(L) = 79, 'boundary fixture');
  Check(M.SendGCode(L), '79 bytes accepted'); F.Ack(1); N := F.Sent.Count;
  Check(not M.SendGCode(L + 'a'), '80 bytes rejected');
  Check(not M.SendGCode('G1 X1 !'), 'embedded hold rejected');
  Check(not M.SendGCode('G1 X1 ?'), 'embedded status rejected');
  Check(not M.SendGCode('G1 X1 ~'), 'embedded resume rejected');
  Check(not M.SendGCode('G1 X1 ' + #$85), 'extended realtime rejected');
  Check(F.Sent.Count = N, 'rejected lines never sent');
  Check(M.Status and (Pos('?', F.Realtime) > 0), 'status uses realtime channel');
  M.Free; F.Free;
end;

procedure TestFragmentedErrorsAndResetPosition;
var M: TMultiCNCMachine; F: TFakeController; I, N: Integer;
begin
  M := NewMachine(mtRouter, False, F);
  for I := 1 to 40 do M.SendGCode('G1 X1 F500');
  N := F.Sent.Count;
  F.Reply('err'); F.Reply('or:22' + #13); F.Reply(#10);
  Check(M.ErrorCount = 1, 'fragmented error counted once');
  Check(M.QueuedLines = 0, 'error discards unsent lines');
  F.Ack(100);
  Check(F.Sent.Count = N, 'no new lines after error');
  F.Reply('<Idle|MPos:10,0,0|WCO:5,0,0>' + #10);
  Check(Abs(M.GetPosition.X - 5) < 1e-9, 'initial WCO');
  F.Reply('Grbl 1.1h' + #10);
  F.Reply('<Idle|MPos:10,0,0>' + #10);
  Check(Abs(M.GetPosition.X - 10) < 1e-9, 'reset invalidates old WCO');
  M.Free; F.Free;
end;

begin
  DefaultFormatSettings.DecimalSeparator := ',';
  TestPauseAndReset;
  TestLimitsAndRealtime;
  TestFragmentedErrorsAndResetPosition;
  if Failures > 0 then Halt(1);
  Writeln('PASS: GRBL pause, reset, limits, realtime, errors and position');
end.
