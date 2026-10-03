unit multicnc_tcp_transport;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Winsock2, multicnc_interfaces;
type
  TTCPTransport = class(TInterfacedObject, IMultiCNCTransport)
  private
    FSocket: TSocket;
    FStarted: Boolean;
    FHost, FOutput: string;
    FPort: Integer;
    FOnData: TTransportDataEvent;
    FOnState: TTransportStateEvent;
    procedure Flush;
  public
    constructor Create(const Endpoint: string);
    destructor Destroy; override;
    function Connect: Boolean;
    procedure Disconnect;
    function IsConnected: Boolean;
    function Send(const AData: string): Boolean;
    procedure SetOnData(AEvent: TTransportDataEvent);
    procedure SetOnState(AEvent: TTransportStateEvent);
    function GetName: string;
    procedure Poll;
  end;
implementation
constructor TTCPTransport.Create(const Endpoint: string);
var P: Integer; W: TWSAData;
begin
  inherited Create;
  FSocket := INVALID_SOCKET;
  FStarted := WSAStartup($0202, W) = 0;
  P := LastDelimiter(':', Endpoint);
  if P > 0 then begin
    FHost := Copy(Endpoint, 1, P-1);
    FPort := StrToIntDef(Copy(Endpoint, P+1, 20), 0);
  end else begin FHost := Endpoint; FPort := 23; end;
end;
destructor TTCPTransport.Destroy;
begin
  Disconnect;
  if FStarted then WSACleanup;
  inherited Destroy;
end;
function TTCPTransport.Connect: Boolean;
var A: TSockAddrIn; Mode: u_long; Ready, Failed: TFDSet;
  Timeout: TTimeVal; ErrorCode, ErrorSize: Integer;
begin
  Result := IsConnected;
  if Result then Exit;
  if not FStarted or (FPort < 1) or (FPort > 65535) then Exit;
  FillChar(A, SizeOf(A), 0);
  A.sin_family := AF_INET;
  A.sin_port := htons(FPort);
  if SameText(FHost, 'localhost') then A.sin_addr.s_addr := inet_addr('127.0.0.1')
  else A.sin_addr.s_addr := inet_addr(PChar(FHost));
  if A.sin_addr.s_addr = INADDR_NONE then Exit;
  FSocket := socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  if FSocket = INVALID_SOCKET then Exit;
  Mode := 1;
  if ioctlsocket(FSocket, LongInt(FIONBIO), Mode) = SOCKET_ERROR then begin Disconnect; Exit; end;
  if Winsock2.connect(FSocket, A, SizeOf(A)) = SOCKET_ERROR then begin
    if WSAGetLastError <> WSAEWOULDBLOCK then begin Disconnect; Exit; end;
    FD_ZERO(Ready); FD_SET(FSocket, Ready);
    FD_ZERO(Failed); FD_SET(FSocket, Failed);
    Timeout.tv_sec := 3; Timeout.tv_usec := 0;
    if select(0, nil, @Ready, @Failed, @Timeout) <= 0 then begin Disconnect; Exit; end;
    ErrorCode := 0; ErrorSize := SizeOf(ErrorCode);
    if (getsockopt(FSocket, SOL_SOCKET, SO_ERROR, @ErrorCode, ErrorSize) <> 0) or
       (ErrorCode <> 0) or not FD_ISSET(FSocket, Ready) then begin Disconnect; Exit; end;
  end;
  Result := True;
  if Assigned(FOnState) then FOnState(True);
end;
procedure TTCPTransport.Disconnect;
begin
  if IsConnected then begin
    closesocket(FSocket); FSocket := INVALID_SOCKET; FOutput := '';
    if Assigned(FOnState) then FOnState(False);
  end;
end;
function TTCPTransport.IsConnected: Boolean;
begin Result := FSocket <> INVALID_SOCKET; end;
procedure TTCPTransport.Flush;
var N: Integer;
begin
  if not IsConnected or (FOutput = '') then Exit;
  N := Winsock2.send(FSocket, FOutput[1], Length(FOutput), 0);
  if N > 0 then Delete(FOutput, 1, N)
  else if (N = 0) or (WSAGetLastError <> WSAEWOULDBLOCK) then Disconnect;
end;
function TTCPTransport.Send(const AData: string): Boolean;
begin
  Result := False;
  if not IsConnected then Exit;
  if Length(FOutput)+Length(AData) > 1048576 then begin Disconnect; Exit; end;
  FOutput := FOutput + AData;
  Flush;
  Result := IsConnected;
end;
procedure TTCPTransport.Poll;
var B: array[0..4095] of Char; N, I: Integer; S: string;
begin
  Flush;
  for I := 1 to 8 do begin
    if not IsConnected then Exit;
    N := recv(FSocket, B, SizeOf(B), 0);
    if N > 0 then begin
      SetString(S, PChar(@B[0]), N);
      if Assigned(FOnData) then FOnData(S);
    end else begin
      if (N = 0) or (WSAGetLastError <> WSAEWOULDBLOCK) then Disconnect;
      Break;
    end;
  end;
end;
procedure TTCPTransport.SetOnData(AEvent: TTransportDataEvent);
begin FOnData := AEvent; end;
procedure TTCPTransport.SetOnState(AEvent: TTransportStateEvent);
begin FOnState := AEvent; end;
function TTCPTransport.GetName: string;
begin Result := 'TCP '+FHost+':'+IntToStr(FPort); end;
end.
