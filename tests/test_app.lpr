program test_app;
{$mode objfpc}{$H+}
uses Interfaces, Forms, Controls, StdCtrls, SysUtils, Classes, LCLType, mainform,
  multicnc_gcode_analyzer;
var F: TMainForm; I, FirstMatch, SecondMatch: Integer;
  ConnectButton, StartButton, JogZ, PauseButton, StopButton: TButton;
  ProgramView, Console: TMemo; Search: TEdit; FindNext: TButton;
  Lines: TStringList; FN: string; Key: Word; Env: TMachineEnvelope; Raised: Boolean;
procedure Check(Value: Boolean; const Msg: string);
begin
  if not Value then raise Exception.Create(Msg);
end;
begin
  Application.Initialize;
  F := TMainForm.Create(nil);
  Lines := TStringList.Create;
  FN := GetTempFileName(GetTempDir, 'cnc');
  try
    ConnectButton := nil; StartButton := nil; JogZ := nil;
    PauseButton := nil; StopButton := nil;
    for I := 0 to F.ComponentCount - 1 do
      if F.Components[I] is TButton then
        with TButton(F.Components[I]) do begin
          if Caption = 'Conectar simulador' then ConnectButton := TButton(F.Components[I]);
          if Caption = 'Iniciar' then StartButton := TButton(F.Components[I]);
          if Caption = 'Z +' then JogZ := TButton(F.Components[I]);
          if Caption = 'Pausar' then PauseButton := TButton(F.Components[I]);
          if Caption = 'PARAR' then StopButton := TButton(F.Components[I]);
        end;
    Check(Assigned(ConnectButton) and Assigned(StartButton) and Assigned(JogZ), 'Controls exist');
    Check(not StartButton.Enabled and not JogZ.Enabled, 'Disconnected controls');
    ConnectButton.Click;
    Check(JogZ.Enabled and not StartButton.Enabled, 'Connected controls');
    ProgramView := TMemo(F.FindComponent('ProgramText'));
    Console := TMemo(F.FindComponent('ConsoleLog'));
    Search := TEdit(F.FindComponent('ProgramSearch'));
    FindNext := TButton(F.FindComponent('FindNext'));
    Lines.Text := '(arquivo original)' + LineEnding + 'M3 S1000' + LineEnding +
      'G0 X0' + LineEnding + 'G1 X10 F500' + LineEnding + 'G1 X20';
    Lines.SaveToFile(FN);
    F.OnDropFiles(F, [FN]);
    Check(StartButton.Enabled, 'Dropped program is ready');
    Check(Pos('X20', ProgramView.Text) > 0, 'Program loaded');
    Check(Pos('arquivo original', ProgramView.Text) > 0, 'Original comments preserved');
    Check((F.AnalysisReport.Errors = 0) and (F.ProgramTrace.Count = 2), 'Analysis and real path available');
    Search.Text := 'g1';
    FindNext.Click;
    Check(ProgramView.SelText = 'G1', 'Case insensitive match');
    FirstMatch := ProgramView.SelStart;
    Key := VK_F3;
    F.OnKeyDown(F, Key, []);
    SecondMatch := ProgramView.SelStart;
    Check((Key = 0) and (SecondMatch > FirstMatch), 'F3 finds next');
    FindNext.Click;
    Check(ProgramView.SelStart = FirstMatch, 'Search wraps');
    Search.Text := 'M999';
    FindNext.Click;
    Check(TLabel(F.FindComponent('SearchResult')).Caption = 'Texto nao encontrado.', 'Missing query feedback');
    // A UTF-8 character before a match must not offset the selection.
    ProgramView.Text := 'G0 ; ' + #$C3#$A7 + LineEnding + 'G1 X10';
    Search.Text := 'X10';
    FindNext.Click;
    Check(ProgramView.SelText = 'X10', 'UTF-8 selection offsets');
    F.OnDropFiles(F, [FN]);
    StartButton.Click;
    Lines.Text := 'G0 X999';
    Lines.SaveToFile(FN);
    F.OnDropFiles(F, [FN]);
    Check(Pos('X999', ProgramView.Text) = 0, 'Drop blocked while running');
    PauseButton.Click;
    F.OnDropFiles(F, [FN]);
    Check(Pos('X999', ProgramView.Text) = 0, 'Drop blocked while paused');
    StopButton.Click;
    F.OnDropFiles(F, [FN]);
    Check(Pos('X999', ProgramView.Text) > 0, 'Drop allowed after stop');
    Check(not StartButton.Enabled and (F.AnalysisReport.Errors > 0), 'Envelope errors block simulation');
    Env := DefaultEnvelope(1200, 300, 100);
    F.SetAnalysisEnvelope(Env);
    Check(StartButton.Enabled and (F.AnalysisReport.Errors = 0), 'Edited limits reanalyze the program');
    Env.MaxX := Env.MinX;
    Raised := False;
    try F.SetAnalysisEnvelope(Env); except on E: Exception do Raised := True; end;
    Check(Raised and StartButton.Enabled, 'Invalid limits preserve the valid configuration');
    Lines.Text := 'G21 G90' + LineEnding + 'M3' + LineEnding + 'G0 X60 Y50' + LineEnding + 'G2 I-10 J0 F500';
    Lines.SaveToFile(FN); F.OpenFile(FN);
    Check((F.AnalysisReport.Arcs = 1) and (F.ProgramTrace.Count > 20), 'Launcher entry uses arc analysis');
    F.Show; Application.ProcessMessages; // exercises drawing, including the discretized arc
    Check(TControl(F.FindComponent('TrajectoryPreview')).Height >= 200,
      'Trajectory has usable vertical space at the default window size');
    Check(Console.Lines.Count > 0, 'Console records operations');
    TButton(F.FindComponent('ClearConsole')).Click;
    Check(Console.Text = '', 'Clear console');
    ConnectButton.Click;
    Check(not JogZ.Enabled, 'Disconnected again');
    WriteLn('MultiCNC GUI: OK (connection, search, UTF-8, shortcuts, file drop guards, console)');
  finally
    F.Free;
    Lines.Free;
    DeleteFile(FN);
  end;
end.
