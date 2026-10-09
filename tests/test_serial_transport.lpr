program test_serial_transport;
{$mode objfpc}{$H+}
uses Classes, SysUtils, multicnc_chatgpt_serial;
procedure Check(Value: Boolean; const Msg: string);
begin if not Value then raise Exception.Create(Msg); end;
var T: TChatGPTSerialTransport; FN: string;
begin
  {$ifdef windows}
  Check(SerialDevicePath('COM23') = '\\.\COM23', 'COM23 device namespace');
  Check(SerialDevicePath(' com1 ') = '\\.\COM1', 'COM1 normalization');
  Check(SerialDevicePath('\\.\COM23') = '\\.\COM23', 'No double prefix');
  {$else}
  Check(SerialDevicePath('/dev/ttyUSB0') = '/dev/ttyUSB0', 'Unix path');
  {$endif}
  FN := GetTempFileName(GetTempDir, 'serial');
  with TFileStream.Create(FN, fmCreate) do Free;
  T := TChatGPTSerialTransport.Create(FN, 115200);
  try
    Check(not T.IsConnected, 'Initially disconnected');
    Check(not T.Send('G0 X1'), 'Disconnected send rejected');
    {$ifdef windows}
    { A regular temporary file cannot be a COM port: no hardware is opened. }
    Check(not T.Connect, 'Non-serial resource rejected');
    Check(not T.IsConnected, 'Failed configuration releases handle');
    Check(Pos('GetCommState', T.LastError) > 0, 'Windows diagnostic retained');
    Check(not T.Connect, 'Retry remains safe');
    {$endif}
    T.Disconnect; T.Poll;
  finally T.Free; DeleteFile(FN); end;
  WriteLn('Serial transport: OK (COM23 path, failed setup, retry and disconnected send; no hardware)');
end.
