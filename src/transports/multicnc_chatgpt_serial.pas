unit multicnc_chatgpt_serial;

{$mode objfpc}{$H+}
{$interfaces corba}

interface

uses
  Classes, SysUtils, aiserial, multicnc_interfaces
  {$ifdef windows}, Windows{$endif};

type
  { Adapter do componente TAISerialModem da suíte marcelomaurin/CHATGPT.
    O restante do MultiCNC depende apenas de IMultiCNCTransport. }
  TChatGPTSerialTransport = class(TInterfacedObject, IMultiCNCTransport)
  private
    FSerial: TAISerialModem;
    {$ifdef windows}
    FHandle: THandle;
    FLastError: string;
    function WindowsError(const Operation: string): Boolean;
    {$endif}
    function GetLastErrorText: string;
  private
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
    property LastError: string read GetLastErrorText;
  end;

{ Windows requires the device namespace for COM10 and higher. }
function SerialDevicePath(const Device: string): string;

implementation

function SerialDevicePath(const Device: string): string;
var S: string; N: Integer;
begin
  S := Trim(Device);
  {$ifdef windows}
  if (UpperCase(Copy(S, 1, 3)) = 'COM') and
     TryStrToInt(Copy(S, 4, MaxInt), N) and (N > 0) then
    Result := '\\.\COM' + IntToStr(N)
  else
  {$endif}
    Result := S;
end;

function TChatGPTSerialTransport.GetLastErrorText: string;
begin
  {$ifdef windows}Result := FLastError;
  {$else}Result := FSerial.LastError;{$endif}
end;

{$ifdef windows}
function TChatGPTSerialTransport.WindowsError(const Operation: string): Boolean;
var Code: DWORD;
begin
  Code := Windows.GetLastError;
  FLastError := Operation + ': ' + SysErrorMessage(Code) + ' (' + IntToStr(Code) + ')';
  Result := False;
end;
{$endif}

constructor TChatGPTSerialTransport.Create(const ADevice: string; ABaudRate: Integer);
begin
  inherited Create;
  {$ifdef windows}FHandle := INVALID_HANDLE_VALUE;{$endif}
  FSerial := TAISerialModem.Create(nil);
  FSerial.DeviceName := SerialDevicePath(ADevice);
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
  Disconnect;
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
{$ifdef windows}
var DCB: TDCB; Timeouts: TCommTimeouts;
{$endif}
begin
  {$ifdef windows}
  if IsConnected then Exit(True);
  FLastError := '';
  FHandle := CreateFile(PChar(FSerial.DeviceName), GENERIC_READ or GENERIC_WRITE,
    0, nil, OPEN_EXISTING, 0, 0);
  if FHandle = INVALID_HANDLE_VALUE then Exit(WindowsError('Open ' + FSerial.DeviceName));
  Result := False;
  try
    FillChar(DCB, SizeOf(DCB), 0); DCB.DCBlength := SizeOf(DCB);
    if not GetCommState(FHandle, DCB) then Exit(WindowsError('GetCommState'));
    DCB.BaudRate := FSerial.BaudRate;
    DCB.ByteSize := 8; DCB.Parity := NOPARITY; DCB.StopBits := ONESTOPBIT;
    { Binary, DTR and RTS enabled; no CTS/DSR or XON/XOFF handshaking.
      Do not inherit stale modem flow-control settings from another program. }
    DCB.Flags := $00000001 or $00000010 or $00001000;
    DCB.XonChar := #17; DCB.XoffChar := #19;
    if not SetCommState(FHandle, DCB) then Exit(WindowsError('SetCommState'));
    FillChar(Timeouts, SizeOf(Timeouts), 0);
    Timeouts.ReadIntervalTimeout := MAXDWORD;
    Timeouts.WriteTotalTimeoutConstant := 1000;
    if not SetCommTimeouts(FHandle, Timeouts) then Exit(WindowsError('SetCommTimeouts'));
    if not SetupComm(FHandle, 4096, 4096) then Exit(WindowsError('SetupComm'));
    { Preserve input: a GRBL startup banner may already be arriving. }
    Result := True;
  finally
    if not Result then begin CloseHandle(FHandle); FHandle := INVALID_HANDLE_VALUE; end;
  end;
  SerialConnect(Self);
  {$else}
  Result := FSerial.OpenPort;
  {$endif}
end;

procedure TChatGPTSerialTransport.Disconnect;
begin
  {$ifdef windows}
  if FHandle = INVALID_HANDLE_VALUE then Exit;
  CloseHandle(FHandle); FHandle := INVALID_HANDLE_VALUE;
  SerialDisconnect(Self);
  {$else}FSerial.ClosePort;{$endif}
end;

function TChatGPTSerialTransport.IsConnected: Boolean;
begin
  {$ifdef windows}Result := FHandle <> INVALID_HANDLE_VALUE;
  {$else}Result := FSerial.Active;{$endif}
end;

function TChatGPTSerialTransport.Send(const AData: string): Boolean;
{$ifdef windows}var Written: DWORD;{$endif}
begin
  {$ifdef windows}
  Result := False;
  if not IsConnected then Exit;
  if AData = '' then Exit(True);
  if not WriteFile(FHandle, AData[1], Length(AData), Written, nil) then
    Exit(WindowsError('Serial write'));
  Result := Written = DWORD(Length(AData));
  if not Result then FLastError := 'Serial write timed out before completing the command.'
  else if Assigned(FSerial.OnTXSend) then FSerial.OnTXSend(FSerial, AData);
  {$else}Result := FSerial.WriteText(AData);{$endif}
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
  {$ifdef windows}Result := 'Windows serial (8N1, DTR/RTS, no flow control)';
  {$else}Result := 'CHATGPT/TAISerialModem';{$endif}
end;

procedure TChatGPTSerialTransport.Poll;
{$ifdef windows}
var Buffer: array[0..1023] of Char; Count, Errors: DWORD;
    Status: TComStat; Data: string; I: Integer;
{$endif}
begin
  {$ifdef windows}
  if not IsConnected then Exit;
  for I := 1 to 32 do begin
    if not ClearCommError(FHandle, Errors, @Status) then begin
      WindowsError('Serial status'); Disconnect; Exit;
    end;
    if Errors <> 0 then FLastError := 'Serial receive errors: ' + IntToStr(Errors);
    if Status.cbInQue = 0 then Exit;
    Count := Status.cbInQue;
    if Count > SizeOf(Buffer) then Count := SizeOf(Buffer);
    if not ReadFile(FHandle, Buffer, Count, Count, nil) then begin
      WindowsError('Serial read'); Disconnect; Exit;
    end;
    if Count = 0 then Exit;
    SetString(Data, PChar(@Buffer[0]), Count);
    SerialReceive(Self, Data);
    if not IsConnected then Exit;
  end;
  {$else}FSerial.Poll;{$endif}
end;

end.
