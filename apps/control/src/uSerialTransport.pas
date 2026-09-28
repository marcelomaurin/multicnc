unit uSerialTransport;
{$mode objfpc}{$H+}{$codepage utf8}
interface
uses Classes, SysUtils, Windows, Registry, uDomain;
type
  TSerialTransport=class
  private FHandle:THandle;
  public
    constructor Create;
    destructor Destroy;override;
    procedure Open(const Config:TDeviceConfig);virtual;
    procedure Write(const S:RawByteString);virtual;
    function ReadAvailable:RawByteString;virtual;
  end;
procedure EnumeratePorts(Items:TStrings);
implementation
constructor TSerialTransport.Create;
begin inherited Create;FHandle:=INVALID_HANDLE_VALUE;end;
destructor TSerialTransport.Destroy;
begin if FHandle<>INVALID_HANDLE_VALUE then CloseHandle(FHandle);inherited Destroy;end;
procedure TSerialTransport.Open(const Config:TDeviceConfig);
var D: TDCB;T:TCommTimeouts;
begin
  ValidateConfig(Config);
  FHandle:=CreateFile(PChar('\\.\'+Config.Port),GENERIC_READ or GENERIC_WRITE,0,nil,OPEN_EXISTING,0,0);
  if FHandle=INVALID_HANDLE_VALUE then raise Exception.Create('Não foi possível abrir '+Config.Port+': '+SysErrorMessage(GetLastError));
  FillChar(D,SizeOf(D),0);D.DCBlength:=SizeOf(D);D.BaudRate:=Config.Baud;D.ByteSize:=8;D.Parity:=NOPARITY;D.StopBits:=ONESTOPBIT;D.Flags:=1;
  if Config.DTR then D.Flags:=D.Flags or $10;if Config.RTS then D.Flags:=D.Flags or $1000;
  if not SetCommState(FHandle,D) then RaiseLastOSError;
  FillChar(T,SizeOf(T),0);T.ReadIntervalTimeout:=MAXDWORD;T.WriteTotalTimeoutConstant:=500;
  if not SetCommTimeouts(FHandle,T) then RaiseLastOSError;
  if not SetupComm(FHandle,4096,4096) then RaiseLastOSError;
end;
procedure TSerialTransport.Write(const S:RawByteString);
var N:DWORD;
begin
  if S='' then Exit;
  if not WriteFile(FHandle,S[1],Length(S),N,nil) then RaiseLastOSError;
  if N<>DWORD(Length(S)) then raise Exception.Create('Escrita serial parcial; execução interrompida sem reenvio.');
end;
function TSerialTransport.ReadAvailable:RawByteString;
var B:array[0..1023] of Char;N,Errors:DWORD;Stat:TComStat;
begin
  if not ClearCommError(FHandle,Errors,@Stat) then RaiseLastOSError;
  if Errors<>0 then raise Exception.CreateFmt('Erro na comunicação serial: %d.',[Errors]);
  if not ReadFile(FHandle,B,SizeOf(B),N,nil) then RaiseLastOSError;
  SetString(Result,PChar(@B[0]),N);
end;
procedure EnumeratePorts(Items:TStrings);
var R:TRegistry;Names:TStringList;S:string;
begin
  Items.Clear;R:=TRegistry.Create(KEY_READ);Names:=TStringList.Create;
  try R.RootKey:=HKEY_LOCAL_MACHINE;if R.OpenKeyReadOnly('HARDWARE\DEVICEMAP\SERIALCOMM') then begin R.GetValueNames(Names);for S in Names do Items.Add(R.ReadString(S));end;
  finally Names.Free;R.Free;end;
end;
end.
