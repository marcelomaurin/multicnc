unit multicnc_streamer;

{$mode objfpc}{$H+}
{$interfaces corba}

{ Envio confiavel de programas G-code para o controlador.

  Modos:
  - smCharacterCounting: protocolo recomendado pelo Grbl 1.1/grblHAL/FluidNC.
    Mantem o buffer serial do controlador cheio (sem estourar), contando os
    bytes de cada linha ainda nao confirmada. Cada 'ok' ou 'error:' libera a
    linha mais antiga. Muito mais rapido que enviar-e-esperar em trajetorias
    com muitos segmentos curtos (gravacao laser, PCB, 3D).
  - smSendResponse: uma linha por vez, aguardando 'ok' (modo seguro).
  - smMarlinChecksum: linhas numeradas com checksum XOR (N12 G1 X5*71) e
    tratamento de 'Resend:' - protocolo confiavel do Marlin/RepRap.

  O streamer nao acessa a UI: recebe o texto do transporte por Feed() e
  envia por IMultiCNCTransport. Erros do controlador param o envio
  (StopOnError) - a camada de seguranca decide o que fazer. }

interface

uses
  Classes, SysUtils, multicnc_types, multicnc_interfaces;

type
  TStreamState = (stIdle, stRunning, stPaused, stDone, stError, stAborted);

  TStreamErrorEvent = procedure(LineIndex: Integer; const Line, Response: string) of object;

  TGCodeStreamer = class
  private
    FTransport: IMultiCNCTransport;
    FMode: TStreamMode;
    FRxBufferSize: Integer;
    FLines: TStringList;
    FNext: Integer;               // proxima linha a enviar
    FAcked: Integer;              // linhas confirmadas
    FInFlight: array of Integer;  // tamanhos (bytes) das linhas em transito
    FInFlightIdx: array of Integer;
    FInFlightBytes: Integer;
    FState: TStreamState;
    FStopOnError: Boolean;
    FErrors: Integer;
    FLastResponse: string;
    FPartial: string;
    FMarlinLineNo: Integer;       // numero N da proxima linha Marlin
    FMarlinBase: Integer;         // N da linha de indice 0
    FIgnoreNextOk: Boolean;
    FOnError: TStreamErrorEvent;
    procedure PushInFlight(Index, Bytes: Integer);
    function PopInFlight(out Index: Integer): Boolean;
    function FormatLine(Index: Integer): string;
    procedure HandleResponse(const Line: string);
    function GetTotal: Integer;
  public
    constructor Create(const ATransport: IMultiCNCTransport; AMode: TStreamMode;
      ARxBufferSize: Integer = 128);
    destructor Destroy; override;
    class function CleanLine(const S: string): string;
    class function MarlinChecksum(const S: string): Byte;
    procedure Load(Source: TStrings);
    function Start: Boolean;
    procedure Pause;
    procedure Resume;
    procedure Abort;
    procedure Pump;
    procedure Feed(const Data: string);
    function Progress: Double;
    property Mode: TStreamMode read FMode;
    property State: TStreamState read FState;
    property Total: Integer read GetTotal;
    property Sent: Integer read FNext;
    property Acknowledged: Integer read FAcked;
    property InFlightBytes: Integer read FInFlightBytes;
    property RxBufferSize: Integer read FRxBufferSize write FRxBufferSize;
    property StopOnError: Boolean read FStopOnError write FStopOnError;
    property Errors: Integer read FErrors;
    property LastResponse: string read FLastResponse;
    property OnError: TStreamErrorEvent read FOnError write FOnError;
  end;

implementation

constructor TGCodeStreamer.Create(const ATransport: IMultiCNCTransport;
  AMode: TStreamMode; ARxBufferSize: Integer);
begin
  inherited Create;
  FTransport := ATransport;
  FMode := AMode;
  if ARxBufferSize < 16 then ARxBufferSize := 16;
  FRxBufferSize := ARxBufferSize;
  FLines := TStringList.Create;
  FStopOnError := True;
  FState := stIdle;
end;

destructor TGCodeStreamer.Destroy;
begin
  FLines.Free;
  inherited Destroy;
end;

function TGCodeStreamer.GetTotal: Integer;
begin
  Result := FLines.Count;
end;

class function TGCodeStreamer.CleanLine(const S: string): string;
var I: Integer; InParen: Boolean; C: Char;
begin
  // Remove comentarios ';' e '( )', espacos nas pontas e caracteres de controle.
  Result := '';
  InParen := False;
  for I := 1 to Length(S) do begin
    C := S[I];
    if InParen then begin
      if C = ')' then InParen := False;
      Continue;
    end;
    if C = '(' then begin InParen := True; Continue; end;
    if C = ';' then Break;
    if C < ' ' then Continue;
    Result := Result + C;
  end;
  Result := Trim(Result);
  if Result = '%' then Result := '';
end;

class function TGCodeStreamer.MarlinChecksum(const S: string): Byte;
var I: Integer;
begin
  Result := 0;
  for I := 1 to Length(S) do Result := Result xor Ord(S[I]);
end;

procedure TGCodeStreamer.Load(Source: TStrings);
var I: Integer; L: string;
begin
  if FState in [stRunning, stPaused] then
    raise Exception.Create('Interrompa o envio antes de carregar outro programa.');
  FLines.Clear;
  for I := 0 to Source.Count - 1 do begin
    L := CleanLine(Source[I]);
    if L <> '' then FLines.Add(L);
  end;
  FState := stIdle;
  FNext := 0;
  FAcked := 0;
end;

function TGCodeStreamer.Start: Boolean;
begin
  Result := (FLines.Count > 0) and Assigned(FTransport) and FTransport.IsConnected and
    not (FState in [stRunning, stPaused]);
  if not Result then Exit;
  FNext := 0;
  FAcked := 0;
  FErrors := 0;
  SetLength(FInFlight, 0);
  SetLength(FInFlightIdx, 0);
  FInFlightBytes := 0;
  FPartial := '';
  FIgnoreNextOk := False;
  FState := stRunning;
  if FMode = smMarlinChecksum then begin
    // Zera o contador de linhas do firmware: N0 M110*cs
    FTransport.Send(Format('N0 M110*%d', [MarlinChecksum('N0 M110')]) + #10);
    FMarlinBase := 1;
    FMarlinLineNo := 1;
    FIgnoreNextOk := True; // 'ok' do M110
  end;
  Pump;
end;

procedure TGCodeStreamer.Pause;
begin
  if FState = stRunning then FState := stPaused;
end;

procedure TGCodeStreamer.Resume;
begin
  if FState = stPaused then begin
    FState := stRunning;
    Pump;
  end;
end;

procedure TGCodeStreamer.Abort;
begin
  if FState in [stRunning, stPaused] then FState := stAborted;
  SetLength(FInFlight, 0);
  SetLength(FInFlightIdx, 0);
  FInFlightBytes := 0;
end;

procedure TGCodeStreamer.PushInFlight(Index, Bytes: Integer);
var N: Integer;
begin
  N := Length(FInFlight);
  SetLength(FInFlight, N + 1);
  SetLength(FInFlightIdx, N + 1);
  FInFlight[N] := Bytes;
  FInFlightIdx[N] := Index;
  Inc(FInFlightBytes, Bytes);
end;

function TGCodeStreamer.PopInFlight(out Index: Integer): Boolean;
var I: Integer;
begin
  Result := Length(FInFlight) > 0;
  Index := -1;
  if not Result then Exit;
  Index := FInFlightIdx[0];
  Dec(FInFlightBytes, FInFlight[0]);
  for I := 1 to High(FInFlight) do begin
    FInFlight[I - 1] := FInFlight[I];
    FInFlightIdx[I - 1] := FInFlightIdx[I];
  end;
  SetLength(FInFlight, Length(FInFlight) - 1);
  SetLength(FInFlightIdx, Length(FInFlightIdx) - 1);
end;

function TGCodeStreamer.FormatLine(Index: Integer): string;
var Body: string;
begin
  if FMode = smMarlinChecksum then begin
    Body := Format('N%d %s', [FMarlinBase + Index, FLines[Index]]);
    Result := Format('%s*%d', [Body, MarlinChecksum(Body)]);
  end else
    Result := FLines[Index];
end;

procedure TGCodeStreamer.Pump;
var Line: string; Bytes: Integer;
begin
  while (FState = stRunning) and (FNext < FLines.Count) do begin
    if not FTransport.IsConnected then begin
      FState := stError;
      FLastResponse := 'Transporte desconectado';
      Exit;
    end;
    Line := FormatLine(FNext);
    Bytes := Length(Line) + 1; // + #10
    case FMode of
      smCharacterCounting:
        // Linha maior que o buffer so pode ir com o buffer vazio.
        if (Length(FInFlight) > 0) and (FInFlightBytes + Bytes > FRxBufferSize) then Exit;
      smSendResponse, smMarlinChecksum:
        if (Length(FInFlight) > 0) or FIgnoreNextOk then Exit;
    end;
    if not FTransport.Send(Line + #10) then begin
      FState := stError;
      FLastResponse := 'Falha de envio';
      Exit;
    end;
    PushInFlight(FNext, Bytes);
    Inc(FNext);
  end;
end;

procedure TGCodeStreamer.HandleResponse(const Line: string);
var L, Low: string; Index, N, P: Integer;
begin
  L := Trim(Line);
  if L = '' then Exit;
  Low := LowerCase(L);
  if (Low = 'ok') or (Copy(Low, 1, 3) = 'ok ') then begin
    FLastResponse := L;
    if FIgnoreNextOk then begin
      FIgnoreNextOk := False;
      Pump;
      Exit;
    end;
    if PopInFlight(Index) then Inc(FAcked);
    if (FAcked >= FLines.Count) and (FState in [stRunning, stPaused]) then
      FState := stDone
    else
      Pump;
  end else if (Copy(Low, 1, 7) = 'resend:') or (Copy(Low, 1, 3) = 'rs ') then begin
    // Marlin: retransmitir a partir da linha N
    if Copy(Low, 1, 7) = 'resend:' then P := 8 else P := 4;
    N := StrToIntDef(Trim(Copy(L, P, MaxInt)), -1);
    if (FMode = smMarlinChecksum) and (N >= FMarlinBase) then begin
      Index := N - FMarlinBase;
      if Index < FLines.Count then FNext := Index;
      FAcked := Index;
      SetLength(FInFlight, 0);
      SetLength(FInFlightIdx, 0);
      FInFlightBytes := 0;
      FIgnoreNextOk := True; // o 'ok' que acompanha o pedido de resend
    end;
  end else if (Copy(Low, 1, 6) = 'error:') and (FMode = smMarlinChecksum) and
    ((Pos('checksum', Low) > 0) or (Pos('line number', Low) > 0) or
     (Pos('no line number', Low) > 0)) then begin
    // Erro de transmissao do Marlin: sera seguido de Resend:, nao conta.
    FLastResponse := L;
  end else if (Copy(Low, 1, 6) = 'error:') or (Copy(Low, 1, 6) = 'alarm:') then begin
    FLastResponse := L;
    Inc(FErrors);
    Index := -1;
    if Copy(Low, 1, 6) = 'error:' then begin
      if PopInFlight(Index) then Inc(FAcked);
    end;
    if Assigned(FOnError) then
      if Index >= 0 then FOnError(Index, FLines[Index], L) else FOnError(-1, '', L);
    if FStopOnError or (Copy(Low, 1, 6) = 'alarm:') then
      FState := stError
    else if FAcked >= FLines.Count then
      FState := stDone
    else
      Pump;
  end;
  // Outras linhas (status <...>, [MSG:], echo:busy, wait) nao afetam o fluxo.
end;

procedure TGCodeStreamer.Feed(const Data: string);
var I: Integer; C: Char;
begin
  for I := 1 to Length(Data) do begin
    C := Data[I];
    if (C = #10) or (C = #13) then begin
      if FPartial <> '' then HandleResponse(FPartial);
      FPartial := '';
    end else
      FPartial := FPartial + C;
  end;
end;

function TGCodeStreamer.Progress: Double;
begin
  if FLines.Count = 0 then Exit(0);
  Result := 100.0 * FAcked / FLines.Count;
end;

end.
