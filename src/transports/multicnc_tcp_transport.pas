unit multicnc_tcp_transport;
{$mode objfpc}{$H+}
{$ifdef windows}{$define HAS_WINDOWS}{$endif}
interface
uses Classes, SysUtils, Sockets, multicnc_interfaces;
type
  TTCPTransport = class(TInterfacedObject, IMultiCNCTransport)
  private FSocket: LongInt; FHost: string; FPort: Word; FOnData: TTransportDataEvent; FOnState: TTransportStateEvent;
  public
    constructor Create(const Endpoint: string);
    destructor Destroy; override;
    function Connect: Boolean; procedure Disconnect; function IsConnected: Boolean; function Send(const AData: string): Boolean;
    procedure SetOnData(AEvent: TTransportDataEvent); procedure SetOnState(AEvent: TTransportStateEvent); function GetName: string; procedure Poll;
  end;
implementation
constructor TTCPTransport.Create(const Endpoint: string);
var P: Integer;
begin inherited Create; FSocket := -1; P := LastDelimiter(':', Endpoint); if P > 0 then begin FHost := Copy(Endpoint,1,P-1); FPort := StrToIntDef(Copy(Endpoint,P+1,20),23); end else begin FHost := Endpoint; FPort := 23; end; end;
destructor TTCPTransport.Destroy; begin Disconnect; inherited Destroy; end;
function TTCPTransport.Connect: Boolean;
var A: TSockAddr; H: in_addr;
begin Result := False; if IsConnected then Exit; H := StrToHostAddr(FHost); if H.s_addr=0 then Exit; FSocket := fpSocket(AF_INET,SOCK_STREAM,0); if FSocket < 0 then Exit; FillChar(A,SizeOf(A),0); A.sin_family:=AF_INET; A.sin_port:=htons(FPort); A.sin_addr:=H; if fpConnect(FSocket,@A,SizeOf(A))<>0 then begin CloseSocket(FSocket); FSocket:=-1; Exit; end; Result:=True; if Assigned(FOnState) then FOnState(True); end;
procedure TTCPTransport.Disconnect; begin if IsConnected then begin fpShutdown(FSocket,2); CloseSocket(FSocket); FSocket:=-1; if Assigned(FOnState) then FOnState(False); end; end;
function TTCPTransport.IsConnected: Boolean; begin Result:=FSocket>=0; end;
function TTCPTransport.Send(const AData: string): Boolean; begin Result:=IsConnected and (fpSend(FSocket,@AData[1],Length(AData),0)=Length(AData)); end;
procedure TTCPTransport.SetOnData(AEvent:TTransportDataEvent); begin FOnData:=AEvent; end;
procedure TTCPTransport.SetOnState(AEvent:TTransportStateEvent); begin FOnState:=AEvent; end;
function TTCPTransport.GetName:string; begin Result:='TCP '+FHost+':'+IntToStr(FPort); end;
procedure TTCPTransport.Poll;
begin
  { TCP polling is intentionally passive here; command writes are immediate. }
end;
end.

