program test_session;
{$mode objfpc}{$H+}
uses Classes, SysUtils, multicnc_types, multicnc_session;
var S: TSimulationSession; Lines: TStringList; FN: string; Raised: Boolean;
procedure Check(Value: Boolean; const Msg: string);
begin
  if not Value then raise Exception.Create(Msg);
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
    Check(S.Connect(mtLaser, pkGRBL), 'Connect laser');
    Check(not S.SupportsAxis(axZ), 'Laser has no Z');
    Check(not S.Jog(axZ, 1, 500), 'Reject unsupported jog');
    Check(not S.Jog(axX, 101, 500), 'Reject invalid jog');
    Check(S.Jog(axX, -0.1, 500), 'Allow valid jog');
    Check(S.Start, 'Start');
    Check(not S.Start, 'Cannot restart active job');
    Check(not S.Send('G0 X20'), 'Manual command blocked during job');
    Check(not S.Home, 'Home blocked during job');
    Check(not S.Jog(axX, 1, 500), 'Jog blocked during job');
    Raised := False;
    try S.LoadFile(FN); except on E: Exception do Raised := True; end;
    Check(Raised, 'Cannot replace active job');
    S.Tick;
    Check(S.Completed = 1, 'One command per tick');
    Check(S.Pause, 'Pause');
    S.Tick;
    Check(S.Completed = 1, 'No progress while paused');
    Check(not S.Send('G0 X30'), 'Manual command blocked while paused');
    Check(S.Resume, 'Resume');
    S.Tick;
    Check(S.State = ssDone, 'Job completed');
    S.Tick;
    Check(S.Completed = 2, 'No progress after completion');
    Check(S.Start, 'Restart completed job');
    Check(S.Completed = 0, 'Restart resets progress');
    Check(S.Stop, 'Stop');
    S.Tick;
    Check(S.Completed = 0, 'Stop prevents further sends');
    Lines.Text := '; empty';
    Lines.SaveToFile(FN);
    Raised := False;
    try S.LoadFile(FN); except on E: Exception do Raised := True; end;
    Check(Raised and (S.Count = 2), 'Invalid file preserves prior program');
    S.Disconnect;
    Check(not S.Connected, 'Disconnect');
    Check(S.Connect(mtPrinter3D, pkMarlin), 'Reconnect with Marlin');
    Check(S.SupportsAxis(axZ), 'Printer has Z');
    Check(S.Home, 'Marlin home');
    Check(S.Start, 'Start before disconnect');
    S.Disconnect;
    S.Tick;
    Check(S.State = ssDisconnected, 'Disconnect cancels running job');
    WriteLn('MultiCNC session: OK (state transitions, guards, file loading, reconnect)');
  finally
    S.Free;
    Lines.Free;
    DeleteFile(FN);
  end;
end.
