unit multicnc_tcp;

{$mode objfpc}{$H+}
{$interfaces corba}

{ Transporte TCP/IP para controladores em rede:
  - FluidNC (ESP32) via Wi-Fi/telnet, porta padrao 23;
  - grblHAL com Ethernet/Wi-Fi (telnet, porta 23);
  - pontes serial<->TCP (ser2net, ESP-Link, ESP3D).

  Leitura nao bloqueante: a aplicacao chama Poll periodicamente (mesmo modelo
  do TChatGPTSerialTransport), e os dados chegam por OnData. Nenhuma UI e
  acessada daqui. }

interface

uses
  Classes, SysUtils, ssockets, multicnc_interfaces;

type
  TTCPTransport = class(TInterfacedObject, IMultiCNCTransport)
  private
    FHost: string;
    FPort: Word;
    FConnectTimeoutMS: Integer;
    FSocket: TInetSocket;
    FOnData: TTransportDataEvent;
    FOnState: TTransportStateEvent;
    FLastError: string;
    procedure DropConnection;
  public
    constructor Create(const AHost: string; APort: Word = 23; AConnectTimeoutMS: Integer = 3000);
    destructor Destroy; override;
    function Connect: Boolean;
    procedure Disconnect;
    function IsConnected: Boolean;
    function Send(const AData: string): Boolean;
    procedure SetOnData(AEvent: TTransportDataEvent);
    procedure SetOnState(AEvent: TTransportStateEvent);
    function GetName: string;
    { Le o que estiver disponivel (ate AMaxWaitMS) e dispara OnData. Retorna
      a quantidade de bytes recebidos. }
    function Poll(AMaxWaitMS: Integer = 1): Integer;
    property Host: string read FHost;
    property Port: Word read FPort;
    property LastError: string read FLastError;
  end;

{ Interpreta 'host', 'host:porta' ou 'tcp://host:porta'. }
function ParseTCPAddress(const S: string; out Host: string; out Port: Word): Boolean;

implementation

function ParseTCPAddress(const S: string; out Host: string; out Port: Word): Boolean;
var T: string; P, V: Integer;
begin
  T := Trim(S);
  if LowerCase(Copy(T, 1, 6)) = 'tcp://' then Delete(T, 1, 6);
  if LowerCase(Copy(T, 1, 9)) = 'telnet://' then Delete(T, 1, 9);
  P := LastDelimiter(':', T);
  Port := 23;
  if P > 0 then begin
    V := StrToIntDef(Copy(T, P + 1, MaxInt), -1);
    if (V <= 0) or (V > 65535) then Exit(False);
    Port := V;
    T := Copy(T, 1, P - 1);
  end;
  Host := T;
  Result := Host <> '';
end;

constructor TTCPTransport.Create(const AHost: string; APort: Word; AConnectTimeoutMS: Integer);
begin
  inherited Create;
  FHost := AHost;
  FPort := APort;
  FConnectTimeoutMS := AConnectTimeoutMS;
end;

destructor TTCPTransport.Destroy;
begin
  Disconnect;
  inherited Destroy;
end;

function TTCPTransport.Connect: Boolean;
begin
  Result := IsConnected;
  if Result then Exit;
  FLastError := '';
  try
    FSocket := TInetSocket.Create(FHost, FPort, FConnectTimeoutMS);
    FSocket.IOTimeout := 1;
    Result := True;
  except
    on E: Exception do begin
      FLastError := E.Message;
      FreeAndNil(FSocket);
      Result := False;
    end;
  end;
  if Result and Assigned(FOnState) then FOnState(True);
end;

procedure TTCPTransport.DropConnection;
begin
  if FSocket = nil then Exit;
  FreeAndNil(FSocket);
  if Assigned(FOnState) then FOnState(False);
end;

procedure TTCPTransport.Disconnect;
begin
  DropConnection;
end;

function TTCPTransport.IsConnected: Boolean;
begin
  Result := FSocket <> nil;
end;

function TTCPTransport.Send(const AData: string): Boolean;
var Done, N: Integer;
begin
  Result := IsConnected and (AData <> '');
  if not Result then Exit;
  Done := 0;
  try
    while Done < Length(AData) do begin
      N := FSocket.Write(AData[Done + 1], Length(AData) - Done);
      if N <= 0 then begin
        FLastError := 'Falha de escrita no socket';
        DropConnection;
        Exit(False);
      end;
      Inc(Done, N);
    end;
  except
    on E: Exception do begin
      FLastError := E.Message;
      DropConnection;
      Result := False;
    end;
  end;
end;

function TTCPTransport.Poll(AMaxWaitMS: Integer): Integer;
var Buf: array[0..4095] of Char; N: Integer; S: string;
begin
  Result := 0;
  if not IsConnected then Exit;
  try
    if AMaxWaitMS < 1 then AMaxWaitMS := 1;
    FSocket.IOTimeout := AMaxWaitMS;
    repeat
      N := FSocket.Read(Buf, SizeOf(Buf));
      if N > 0 then begin
        SetString(S, PChar(@Buf[0]), N);
        Inc(Result, N);
        if Assigned(FOnData) then FOnData(S);
      end else if N = 0 then begin
        // conexao encerrada pelo controlador
        FLastError := 'Conexao encerrada pelo controlador';
        DropConnection;
        Exit;
      end;
      FSocket.IOTimeout := 1;
    until N <= 0;
  except
    on E: ESocketError do
      ; // timeout de leitura: sem dados no momento
    on E: Exception do begin
      FLastError := E.Message;
      DropConnection;
    end;
  end;
end;

procedure TTCPTransport.SetOnData(AEvent: TTransportDataEvent);
begin
  FOnData := AEvent;
end;

procedure TTCPTransport.SetOnState(AEvent: TTransportStateEvent);
begin
  FOnState := AEvent;
end;

function TTCPTransport.GetName: string;
begin
  Result := Format('TCP %s:%d', [FHost, FPort]);
end;

end.
