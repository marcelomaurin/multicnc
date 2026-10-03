program test_session;
{$mode objfpc}{$H+}
uses Classes, SysUtils, multicnc_types, multicnc_simulator, multicnc_session;
var S: TSimulationSession; Lines: TStringList; FN: string; Raised: Boolean;
procedure Check(Value: Boolean; const Msg: string);
begin
  if not Value then raise Exception.Create(Msg);
end;
function ConnectSim(Kind: TMachineType; P: TProtocolKind): Boolean;
var T: TSimulatorTransport;
begin
  T := TSimulatorTransport.Create;
  Result := S.ConnectTransport(Kind, P, T, T);
end;
begin
  FN := GetTempFileName(GetTempDir, 'cnc');
  Lines := TStringList.Create;
  S := TSimulationSession.Create;
  try
    Check(not S.Start, 'Cannot start disconnected');
    Check(not S.Send('G0 X1'), 'Cannot send disconnected');
    Lines.Text := '; comment' + LineEnding + '(comment)' + LineEnding + '%' + LineEnding +
      'G0 X1' + LineEnding + 'G0 Y2';
    Lines.SaveToFile(FN);
    S.LoadFile(FN);
    Check(S.Count = 2, 'Comments are excluded');
    Check(ConnectSim(mtLaser, pkGRBL), 'Connect laser');
    Check(not S.SupportsAxis(axZ), 'Laser has no Z');
    Check(not S.Jog(axZ, 1, 500), 'Reject unsupported jog');
    Check(not S.Jog(axX, 101, 500), 'Reject invalid jog');
    Check(S.Jog(axX, -0.1, 500), 'Allow valid jog');
    Check(not S.Send('G0 X1,5'), 'Reject decimal comma');
    Check(S.Start, 'Start');
    { O simulador confirma cada linha na hora: o programa termina no Start. }
    Check(S.State = ssDone, 'Job completed after acknowledgements');
    Check(S.Completed = 2, 'All lines confirmed');
    Check(not S.Start or (S.State = ssDone), 'Restart completed job');
    Check(S.Stop, 'Stop');
    Raised := False;
    Lines.Text := '; empty';
    Lines.SaveToFile(FN);
    try S.LoadFile(FN); except on E: Exception do Raised := True; end;
    Check(Raised and (S.Count = 2), 'Invalid file preserves prior program');
    S.Disconnect;
    Check(not S.Connected, 'Disconnect');
    Check(ConnectSim(mtPrinter3D, pkMarlin), 'Reconnect with Marlin');
    Check(S.SupportsAxis(axZ), 'Printer has Z');
    Check(S.Home, 'Marlin home');
    S.Disconnect;
    S.Tick;
    Check(S.State = ssDisconnected, 'Disconnect');
    WriteLn('MultiCNC session: OK (state transitions, guards, file loading, reconnect)');
  finally
    S.Free;
    Lines.Free;
    DeleteFile(FN);
  end;
end.
