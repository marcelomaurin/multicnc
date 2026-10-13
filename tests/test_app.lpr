program test_app;
{$mode objfpc}{$H+}
uses Interfaces, Forms, Controls, StdCtrls, ComCtrls, Spin, multicnc_zeroassist_form, SysUtils, Classes, LCLType, mainform,
  multisuite_controls, multicnc_gcode_analyzer;
var F: TMainForm; I, FirstMatch, SecondMatch: Integer;
  ConnectButton, StartButton, JogZ, PauseButton, StopButton: TSuiteButton;
  ProgramView, Console: TMemo; Search: TEdit; FindNext: TSuiteButton;
  Brand, Model, Protocol: TComboBox;
  Lines: TStringList; FN: string; Key: Word; Env: TMachineEnvelope; ZA: TZeroAssistForm; T0: QWord; Msg: string; Raised: Boolean;
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
    { zero pelo bloco (router): canto do bloco em X/Y, topo em Z, espessura com folga }
    Lines.Text := 'G21' + LineEnding + 'G90' + LineEnding + 'G0 Z5' + LineEnding + 'M3 S10000' + LineEnding +
      'G0 X12.5 Y8' + LineEnding + 'G1 Z-15 F200' + LineEnding + 'G1 X40 F800' + LineEnding + 'G1 Y30' + LineEnding +
      'G0 Z5' + LineEnding + 'M5';
    Lines.SaveToFile(FN);
    F.OnDropFiles(F, [FN]);
    Check(TSuiteButton(F.FindComponent('ZeroAssist')).Visible and TSuiteButton(F.FindComponent('ZeroAssist')).Enabled,
      'zero-from-block assistant available for the router');
    TSuiteButton(F.FindComponent('ZeroAssist')).Click;
    ZA := nil;
    for I := 0 to Screen.FormCount - 1 do
      if Screen.Forms[I] is TZeroAssistForm then ZA := TZeroAssistForm(Screen.Forms[I]);
    Check((ZA <> nil) and ZA.Block.Valid and (ZA.Block.X0 = 0) and (ZA.Block.Y0 = 0), 'positive program: zero at the block corner');
    T0 := GetTickCount64;
    while not TSuiteButton(ZA.FindComponent('ZeroApplyXY')).Enabled and (GetTickCount64 - T0 < 5000) do
    begin Application.ProcessMessages; Sleep(20); end;
    TFloatSpinEdit(ZA.FindComponent('ZeroThickness')).Value := 16.5;
    Check(not ZA.DepthOK(Msg) and (Pos('quebrar', Msg) > 0), 'cut of 15 mm in a 16.5 mm block (2 mm clearance) is refused');
    Raised := False;
    try ZA.ApplyXY; except Raised := True; end;
    Check(Raised and (ZA.LastCommand = ''), 'zero not applied while the cut is too deep');
    TFloatSpinEdit(ZA.FindComponent('ZeroThickness')).Value := 18;
    Check(ZA.DepthOK(Msg), 'cut of 15 mm in an 18 mm block is allowed');
    ZA.ApplyXY;
    Check(ZA.LastCommand = 'G92 X0 Y0', 'XY zero at the marked block corner: ' + ZA.LastCommand);
    ZA.ApplyZ;
    Check(ZA.LastCommand = 'G92 Z0', 'Z zero at the block top: ' + ZA.LastCommand);
    ZA.Close;
    { A renamed printer file must not start under the selected GRBL profile. }
    Lines.Text:='; disguised printer program'+LineEnding+'G21'+LineEnding+'M82'+LineEnding+'G1 X10 F500';
    Lines.SaveToFile(FN);F.OnDropFiles(F,[FN]);
    TSuiteButton(F.FindComponent('ClearConsole')).Click;
    StartButton.Click;
    Check((Pos('M82',Console.Text)>0) and (Pos('Linha 3:',Console.Text)>0),'Start explains incompatible command and original source line');
    Check(Pos('TX  G21',Console.Text)=0,'Rejected program sends no initial commands');
    Check(Console.Lines.Count > 0, 'Console records operations');
    TSuiteButton(F.FindComponent('ClearConsole')).Click;
    Check(Console.Text = '', 'Clear console');
    ConnectButton.Click;
    Check(not JogZ.Enabled, 'Disconnected again');
    { G-code do MultiSlicer: contrato da suite seleciona Impressora 3D e confere o volume }
    Lines.Text := '; MultiSlicer -> MultiCNC (Impressora 3D)' + LineEnding +
      '; MS-CONTRACT: 1' + LineEnding + '; MS-MACHINE: printer3d' + LineEnding +
      '; MS-BOUNDS: X0=95 X1=125 Y0=100 Y1=120 Z0=0 Z1=26' + LineEnding +
      '; MS-PRINTER: Creality Ender-3' + LineEnding + '; MS-MATERIAL: PLA' + LineEnding +
      '; MS-TEMP: HOTEND=200 BED=60 FIRST_HOTEND=205 FIRST_BED=65' + LineEnding +
      '; MS-PRINT: TIME=1490 LAYERS=130 FILAMENT_M=1.840 FILAMENT_G=5.49' + LineEnding +
      ';FLAVOR:Marlin' + LineEnding + 'G21' + LineEnding + 'G90' + LineEnding + 'M83' + LineEnding +
      'M104 S205' + LineEnding + 'G28' + LineEnding + 'G0 X100 Y100 Z0.2 F9000' + LineEnding + 'G1 X120 Y100 E1.2 F1800' +
      LineEnding + 'G2 X125 Y105 I0 J5 E0.4' + LineEnding + 'M486 S-1' + LineEnding + 'M84 X Y E';
    Lines.SaveToFile(FN);
    TSuiteButton(F.FindComponent('ClearConsole')).Click;
    F.OnDropFiles(F, [FN]);
    Check(TComboBox(F.FindComponent('MachineType')).ItemIndex = 2, 'MultiSlicer G-code selects 3D Printer');
    Check(Protocol.ItemIndex = 1, '3D Printer uses Marlin');
    Check((Pos('Impressora 3D', Console.Text) > 0) and (Pos('Material: PLA', Console.Text) > 0) and
      (Pos('bico 200 C', Console.Text) > 0) and (Pos('130 camadas', Console.Text) > 0), 'printer job summary in the log');
    Check(Pos('Cabe no volume', Console.Text) > 0, 'job fits the printer volume');
    Check(Pos('X120', ProgramView.Text) > 0, 'printer program loaded');
    for I := 0 to F.ComponentCount - 1 do
      if F.Components[I] is TStatusBar then
        Check(Pos('Erros', TStatusBar(F.Components[I]).SimpleText) = 0,
          'printer G-code analyzed without errors (M84 X Y E, F9000): ' + TStatusBar(F.Components[I]).SimpleText);
    Lines[3] := '; MS-BOUNDS: X0=10 X1=400 Y0=10 Y1=120 Z0=0 Z1=26';
    Lines.SaveToFile(FN);
    TSuiteButton(F.FindComponent('ClearConsole')).Click;
    F.OnDropFiles(F, [FN]);
    Check(Pos('nao cabem no volume', Console.Text) > 0, 'oversized job warned');
    WriteLn('MultiCNC GUI: OK (connection, search, UTF-8, shortcuts, file drop guards, console, GRBL compatibility warning, MultiSlicer printer jobs, zero from block and depth check)');
  finally
    F.Free;
    Lines.Free;
    DeleteFile(FN);
  end;
  except on E: Exception do begin Writeln('FAIL: ', E.Message); Halt(1); end; end;
end.
