unit multicnc_chatgpt_serial;

{$mode objfpc}{$H+}
{$interfaces corba}

interface

uses
  Classes, SysUtils, aiserial, multicnc_interfaces;

type
  { Adapter do componente TAISerialModem da suíte marcelomaurin/CHATGPT.
    O restante do MultiCNC depende apenas de IMultiCNCTransport. }
  TChatGPTSerialTransport = class(TInterfacedObject, IMultiCNCTransport)
  private
    FSerial: TAISerialModem;
    FOnData: TTransportDataEvent;
    FOnState: TTransportStateEvent;
    procedure SerialConnect(Sender: TObject);
    procedure SerialDisconnect(Sender: TObject);
    procedure SerialReceive(Sender: TObject; const AData: string);
  public
    constructor Create(const ADevice: string; ABaudRate: Integer);
    destructor Destroy; override;
    function Connect: Boolean;
    procedure Disconnect;
    function IsConnected: Boolean;
    function Send(const AData: string): Boolean;
    procedure SetOnData(AEvent: TTransportDataEvent);
    procedure SetOnState(AEvent: TTransportStateEvent);
    function GetName: string;
    procedure Poll;
    property Serial: TAISerialModem read FSerial;
  end;

implementation

constructor TChatGPTSerialTransport.Create(const ADevice: string; ABaudRate: Integer);
begin
  inherited Create;
  FSerial := TAISerialModem.Create(nil);
  FSerial.DeviceName := ADevice;
  FSerial.BaudRate := ABaudRate;
  FSerial.DataBits := 8;
  FSerial.StopBits := 1;
  FSerial.Parity := 'N';
  FSerial.OnConnect := @SerialConnect;
  FSerial.OnDisconnect := @SerialDisconnect;
  FSerial.OnRXReceive := @SerialReceive;
end;

destructor TChatGPTSerialTransport.Destroy;
begin
  FSerial.Free;
  inherited Destroy;
end;

procedure TChatGPTSerialTransport.SerialConnect(Sender: TObject);
begin
  if Assigned(FOnState) then FOnState(True);
end;

procedure TChatGPTSerialTransport.SerialDisconnect(Sender: TObject);
begin
  if Assigned(FOnState) then FOnState(False);
end;

procedure TChatGPTSerialTransport.SerialReceive(Sender: TObject; const AData: string);
begin
  if Assigned(FOnData) then FOnData(AData);
end;

function TChatGPTSerialTransport.Connect: Boolean;
begin
  Result := FSerial.OpenPort;
end;

procedure TChatGPTSerialTransport.Disconnect;
begin
  FSerial.ClosePort;
end;

function TChatGPTSerialTransport.IsConnected: Boolean;
begin
  Result := FSerial.Active;
end;

function TChatGPTSerialTransport.Send(const AData: string): Boolean;
begin
  Result := FSerial.WriteText(AData);
end;

procedure TChatGPTSerialTransport.SetOnData(AEvent: TTransportDataEvent);
begin
  FOnData := AEvent;
end;

procedure TChatGPTSerialTransport.SetOnState(AEvent: TTransportStateEvent);
begin
  FOnState := AEvent;
end;

function TChatGPTSerialTransport.GetName: string;
begin
  Result := 'CHATGPT/TAISerialModem';
end;

procedure TChatGPTSerialTransport.Poll;
begin
  FSerial.Poll;
end;

end.
