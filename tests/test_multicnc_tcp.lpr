program test_multicnc_tcp;
{$mode objfpc}{$H+}
uses SysUtils, multicnc_session, multicnc_types;
type
  TProbe = class
    Data: string;
    procedure Receive(const S: string);
    procedure Expect(Session: TSimulationSession; const Token: string);
  end;
procedure TProbe.Receive(const S: string);
begin Data := Data + S; end;
procedure TProbe.Expect(Session: TSimulationSession; const Token: string);
var Deadline: QWord;
begin
  Deadline := GetTickCount64 + 5000;
  repeat Session.Poll; Sleep(20); until (Pos(Token, Data)>0) or (GetTickCount64>Deadline);
  if Pos(Token, Data)=0 then raise Exception.Create('Missing '+Token+': '+Data);
  Data := '';
end;
var Session: TSimulationSession; Probe: TProbe; I: Integer;
begin
  Session := TSimulationSession.Create; Probe := TProbe.Create;
  try
    Session.OnLog := @Probe.Receive;
    for I := 1 to 2 do begin
      if not Session.Connect(mtPrinter3D, pkMarlin, '127.0.0.1:9000', 115200) then
        raise Exception.Create('Connection failed');
      Probe.Expect(Session, 'start');
      if not Session.Send('M115') then raise Exception.Create('Send failed');
      Probe.Expect(Session, 'FIRMWARE_NAME');
      Session.Send('G90'); Probe.Expect(Session, 'ok');
      Session.Send('G1 X12 Y15 F6000'); Probe.Expect(Session, 'ok');
      Sleep(800);
      Session.Send('M114'); Probe.Expect(Session, 'X:12.000 Y:15.000');
      Session.Send('M105'); Probe.Expect(Session, 'T:');
      Session.Disconnect; Sleep(300);
    end;
    if Session.Connect(mtPrinter3D, pkMarlin, '127.0.0.1:0', 115200) then
      raise Exception.Create('Invalid port accepted');
    Writeln('PASS: MultiCNC session to SimuCNC: firmware, G-code framing, movement, replies while idle, reconnect, invalid port');
  finally Session.Free; Probe.Free; end;
end.
