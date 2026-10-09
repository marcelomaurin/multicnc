program test_app;
{$mode objfpc}{$H+}
uses Interfaces, Forms, Controls, StdCtrls, SysUtils, Classes, LCLType, mainform,
  multisuite_controls, multicnc_gcode_analyzer;
var F: TMainForm; I, FirstMatch, SecondMatch: Integer;
  ConnectButton, StartButton, JogZ, PauseButton, StopButton: TSuiteButton;
  ProgramView, Console: TMemo; Search: TEdit; FindNext: TSuiteButton;
  Brand, Model, Protocol: TComboBox;
  Lines: TStringList; FN: string; Key: Word; Env: TMachineEnvelope;
procedure Check(Value: Boolean; const Msg: string);
begin
  if not Value then raise Exception.Create(Msg);
end;
begin
  try
  Application.Initialize;
  F := TMainForm.Create(nil);
  Lines := TStringList.Create;
  FN := GetTempFileName(GetTempDir, 'cnc');
  try
    ConnectButton := nil; StartButton := nil; JogZ := nil;
    PauseButton := nil; StopButton := nil;
    for I := 0 to F.ComponentCount - 1 do
      if F.Components[I] is TSuiteButton then
        with TSuiteButton(F.Components[I]) do begin
          if (Caption = 'Connect Device') or (Caption = 'Conectar simulador') or (Caption = 'Conectar equipamento') then ConnectButton := TSuiteButton(F.Components[I]);
          if (Caption = 'Start') or (Caption = 'Iniciar') then StartButton := TSuiteButton(F.Components[I]);
          if (Caption = 'Z +') or (Caption = 'Z+') then JogZ := TSuiteButton(F.Components[I]);
          if (Caption = 'Pause') or (Caption = 'Pausar') then PauseButton := TSuiteButton(F.Components[I]);
          if (Caption = 'Emergency Stop') or (Caption = 'PARAR') or (Caption = 'Parar') then StopButton := TSuiteButton(F.Components[I]);
        end;
    Check(Assigned(ConnectButton) and Assigned(StartButton) and Assigned(JogZ), 'Controls exist');
    Check(not StartButton.Enabled and not JogZ.Enabled, 'Disconnected controls');
    Brand := TComboBox(F.FindComponent('RouterBrand'));
    Model := TComboBox(F.FindComponent('RouterModel'));
    Protocol := TComboBox(F.FindComponent('ProtocolType'));
    Brand.ItemIndex := Brand.Items.IndexOf('TwoTrees');
    Brand.OnChange(Brand);
    Check(Model.Items.IndexOf('TTC3018') >= 0, 'TTC3018 listed in TwoTrees');
    Protocol.ItemIndex := 1;
    Model.ItemIndex := Model.Items.IndexOf('TTC3018');
    Model.Text := 'TTC3018';
    Model.OnChange(Model);
    Check(Protocol.ItemIndex = 0, 'TTC3018 selects GRBL instead of stale Marlin');
    TComboBox(F.FindComponent('CommunicationMode')).ItemIndex := 2;
    ConnectButton.Click;
    Check(JogZ.Enabled and not StartButton.Enabled, 'Connected controls');
    Check(not TSuiteButton(F.FindComponent('PhysicalHoming')).Enabled, 'TTC3018 physical homing disabled');
    ProgramView := TMemo(F.FindComponent('ProgramText'));
    Console := TMemo(F.FindComponent('ConsoleLog'));
    Search := TEdit(F.FindComponent('ProgramSearch'));
    FindNext := TSuiteButton(F.FindComponent('FindNext'));
    Lines.Text := 'M3 S1000' + LineEnding + 'G0 X0' + LineEnding + 'G1 X10 F500' + LineEnding + 'G1 X20';
    Lines.SaveToFile(FN);
    F.OnDropFiles(F, [FN]);
    Check(StartButton.Enabled, 'Dropped program is ready');
    Check(Pos('X20', ProgramView.Text) > 0, 'Program loaded');
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
    Check((TLabel(F.FindComponent('SearchResult')).Caption = 'Text not found.') or (TLabel(F.FindComponent('SearchResult')).Caption = 'Texto nao encontrado.'), 'Missing query feedback');
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
    Check(Console.Lines.Count > 0, 'Console records operations');
    TSuiteButton(F.FindComponent('ClearConsole')).Click;
    Check(Console.Text = '', 'Clear console');
    ConnectButton.Click;
    Check(not JogZ.Enabled, 'Disconnected again');
    WriteLn('MultiCNC GUI: OK (connection, search, UTF-8, shortcuts, file drop guards, console)');
  finally
    F.Free;
    Lines.Free;
    DeleteFile(FN);
  end;
  except on E: Exception do begin Writeln('FAIL: ', E.Message); Halt(1); end; end;
end.
