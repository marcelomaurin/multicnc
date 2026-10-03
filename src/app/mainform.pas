unit mainform;

{$mode objfpc}{$H+}

interface

uses Classes, SysUtils, Math, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls,
  Dialogs, Graphics, Spin, StrUtils, LazUTF8, LCLType, multicnc_types, multicnc_session, aimarlinsimulator, multicnc_print3d_view;

type
  TMainForm = class(TForm)
  private
    Session: TSimulationSession;
    MachineType, ProtocolType: TComboBox;
    BtnConnect, BtnOpen, BtnStart, BtnPause, BtnResume, BtnStop, BtnHome, BtnSend: TButton;
    JogButtons: array[0..5] of TButton;
    StepSize: TFloatSpinEdit;
    FeedRate: TSpinEdit;
    ProgramMemo, MemoLog: TMemo;
    EditCommand, SearchEdit: TEdit;
    Pages: TPageControl;
    ProgramTab: TTabSheet;
    SearchResult: TLabel;
    StateLabel, FileLabel, ProgressLabel: TLabel;
    Progress: TProgressBar;
    Timer: TTimer;
    Status: TStatusBar;
    Marlin: TAIMarlinSimulator;
    PrintView: TPrint3DView;
    PrinterLines: TStringList;
    PrinterIndex: Integer;
    PrinterConnected: Boolean;
    function Panel(ParentControl: TWinControl; Alignment: TAlign; Size: Integer): TPanel;
    function LabelAt(ParentControl: TWinControl; const AText: string; X, Y: Integer): TLabel;
    function ButtonAt(ParentControl: TWinControl; const AText: string;
      X, Y, W: Integer; Handler: TNotifyEvent): TButton;
    procedure SearchClick(Sender: TObject);
    procedure SearchChanged(Sender: TObject);
    procedure SaveLogClick(Sender: TObject);
    procedure ClearLogClick(Sender: TObject);
    procedure Shortcut(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure DropFiles(Sender: TObject; const FileNames: array of string);
    procedure LoadProgram(const AFileName: string);
    procedure ConnectClick(Sender: TObject);
    procedure OpenClick(Sender: TObject);
    procedure CommandClick(Sender: TObject);
    procedure JogClick(Sender: TObject);
    procedure Tick(Sender: TObject);
    procedure Log(const AText: string);
    procedure MarlinResponse(Sender: TObject; const AText: string);
    procedure MarlinMotion(Sender: TObject; const A, B: TAIMarlinPosition; Material: Double);
    procedure UpdateControls;
    procedure Closing(Sender: TObject; var CanClose: Boolean);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

implementation

function TMainForm.Panel(ParentControl: TWinControl; Alignment: TAlign; Size: Integer): TPanel;
begin
  Result := TPanel.Create(Self);
  Result.Parent := ParentControl;
  Result.BevelOuter := bvNone;
  Result.Align := Alignment;
  if Alignment in [alLeft, alRight] then Result.Width := Size else Result.Height := Size;
end;

function TMainForm.LabelAt(ParentControl: TWinControl; const AText: string; X, Y: Integer): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := ParentControl;
  Result.Caption := AText;
  Result.SetBounds(X, Y, 200, 24);
end;

function TMainForm.ButtonAt(ParentControl: TWinControl; const AText: string;
  X, Y, W: Integer; Handler: TNotifyEvent): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := ParentControl;
  Result.Caption := AText;
  Result.SetBounds(X, Y, W, 34);
  Result.OnClick := Handler;
end;

constructor TMainForm.Create(AOwner: TComponent);
var Header, Connection, Body, Side, Workspace, Actions, Footer, ConsoleBar, SearchBar, LogBar: TPanel;
  ConsoleTab: TTabSheet; L: TLabel; I: Integer;
const JogNames: array[0..5] of string = ('X -', 'X +', 'Y -', 'Y +', 'Z -', 'Z +');
begin
  inherited CreateNew(AOwner);
  Caption := 'MultiCNC | Painel de operacao';
  Position := poScreenCenter;
  SetBounds(0, 0, 1120, 760);
  Constraints.MinWidth := 980;
  Constraints.MinHeight := 680;
  Font.Name := 'Segoe UI';
  Font.Size := 10;
  Color := clBtnFace;
  OnCloseQuery := @Closing;
  KeyPreview := True;
  OnKeyDown := @Shortcut;
  AllowDropFiles := True;
  OnDropFiles := @DropFiles;
  Session := TSimulationSession.Create;
  Session.OnLog := @Log;

  Header := Panel(Self, alTop, 82);
  L := LabelAt(Header, 'MultiCNC', 20, 12);
  L.Font.Size := 20;
  L.Font.Style := [fsBold];
  LabelAt(Header, 'SIMULADOR  /  Preparacao e teste de comandos', 22, 51);
  StateLabel := LabelAt(Header, 'Desconectado', 620, 25);
  StateLabel.Font.Style := [fsBold];

  Connection := Panel(Self, alTop, 80);
  Connection.Top := 90;
  LabelAt(Connection, 'Maquina', 20, 5);
  MachineType := TComboBox.Create(Self);
  MachineType.Parent := Connection;
  MachineType.SetBounds(20, 29, 180, 30);
  MachineType.Style := csDropDownList;
  MachineType.Items.Add('CNC Router');
  MachineType.Items.Add('Laser');
  MachineType.Items.Add('Impressora 3D');
  MachineType.ItemIndex := 0;
  LabelAt(Connection, 'Protocolo', 220, 5);
  ProtocolType := TComboBox.Create(Self);
  ProtocolType.Parent := Connection;
  ProtocolType.SetBounds(220, 29, 150, 30);
  ProtocolType.Style := csDropDownList;
  ProtocolType.Items.Add('GRBL');
  ProtocolType.Items.Add('Marlin');
  ProtocolType.ItemIndex := 0;
  BtnConnect := ButtonAt(Connection, 'Conectar simulador', 390, 26, 185, @ConnectClick);
  LabelAt(Connection, 'Transporte: simulador local', 600, 32);

  Status := TStatusBar.Create(Self);
  Status.Parent := Self;
  Status.Align := alBottom;
  Status.SimplePanel := True;
  Status.SimpleText := 'Simulacao de envio. Sem telemetria ou controle de hardware.';
  Body := Panel(Self, alClient, 0);
  Side := Panel(Body, alLeft, 268);
  L := LabelAt(Side, 'Movimento manual', 20, 14);
  L.Font.Style := [fsBold];
  LabelAt(Side, 'Passo (mm)', 20, 51);
  StepSize := TFloatSpinEdit.Create(Self);
  StepSize.Parent := Side;
  StepSize.SetBounds(20, 75, 220, 30);
  StepSize.MinValue := 0.01;
  StepSize.MaxValue := 100;
  StepSize.DecimalPlaces := 2;
  StepSize.Increment := 0.1;
  StepSize.Value := 1;
  LabelAt(Side, 'Avanco (mm/min)', 20, 119);
  FeedRate := TSpinEdit.Create(Self);
  FeedRate.Parent := Side;
  FeedRate.SetBounds(20, 143, 220, 30);
  FeedRate.MinValue := 1;
  FeedRate.MaxValue := 10000;
  FeedRate.Value := 500;
  for I := 0 to 5 do begin
    JogButtons[I] := ButtonAt(Side, JogNames[I], 20 + (I mod 2) * 114,
      194 + (I div 2) * 44, 106, @JogClick);
    JogButtons[I].Tag := I;
  end;
  BtnHome := ButtonAt(Side, 'Referenciar (Home)', 20, 336, 220, @CommandClick);
  L := LabelAt(Side, 'Posicao: indisponivel' + LineEnding +
    'O simulador confirma comandos,' + LineEnding + 'mas nao calcula trajetorias.', 20, 392);
  L.Font.Color := clGrayText;

  Workspace := Panel(Body, alClient, 0);
  PrintView := TPrint3DView.Create(Self);
  PrintView.Parent := Workspace;
  PrintView.Align := alClient;
  PrintView.Visible := False;
  Actions := Panel(Workspace, alTop, 106);
  BtnOpen := ButtonAt(Actions, 'Abrir G-code...', 12, 10, 145, @OpenClick);
  BtnStart := ButtonAt(Actions, 'Iniciar', 168, 10, 100, @CommandClick);
  BtnPause := ButtonAt(Actions, 'Pausar', 278, 10, 100, @CommandClick);
  BtnResume := ButtonAt(Actions, 'Retomar', 388, 10, 100, @CommandClick);
  BtnStop := ButtonAt(Actions, 'PARAR', 500, 10, 132, @CommandClick);
  BtnStop.Font.Style := [fsBold];
  BtnStop.Hint := 'Interrompe a simulacao. Nao substitui uma parada de emergencia fisica.';
  BtnStop.ShowHint := True;
  FileLabel := LabelAt(Actions, 'Nenhum arquivo aberto', 14, 65);
  FileLabel.AutoSize := False;
  FileLabel.Width := 620;
  FileLabel.Anchors := [akLeft, akTop, akRight];
  FileLabel.ShowHint := True;

  Footer := Panel(Workspace, alBottom, 62);
  ProgressLabel := LabelAt(Footer, '0 / 0 comandos enviados', 12, 6);
  Progress := TProgressBar.Create(Self);
  Progress.Parent := Footer;
  Progress.SetBounds(12, 31, 610, 18);
  Progress.Anchors := [akLeft, akRight, akTop];

  Pages := TPageControl.Create(Self);
  Pages.Parent := Workspace;
  Pages.Align := alClient;
  ProgramTab := TTabSheet.Create(Self);
  ProgramTab.PageControl := Pages;
  ProgramTab.Caption := 'Programa';
  SearchBar := Panel(ProgramTab, alTop, 80);
  LabelAt(SearchBar, 'Buscar no programa (Ctrl+F)', 10, 4);
  SearchEdit := TEdit.Create(Self);
  SearchEdit.Name := 'ProgramSearch';
  SearchEdit.Parent := SearchBar;
  SearchEdit.SetBounds(10, 25, 300, 28);
  SearchEdit.TextHint := 'Ex.: G1, X10 ou M3';
  SearchEdit.OnChange := @SearchChanged;
  ButtonAt(SearchBar, 'Proximo (F3)', 324, 22, 132, @SearchClick).Name := 'FindNext';
  SearchResult := LabelAt(SearchBar, 'Busca sem diferenciar maiusculas e minusculas.', 10, 58);
  SearchResult.Name := 'SearchResult';
  ProgramMemo := TMemo.Create(Self);
  ProgramMemo.Name := 'ProgramText';
  ProgramMemo.Parent := ProgramTab;
  ProgramMemo.Align := alClient;
  ProgramMemo.ReadOnly := True;
  ProgramMemo.WordWrap := False;
  ProgramMemo.ScrollBars := ssAutoBoth;
  ProgramMemo.Font.Name := 'Consolas';
  ProgramMemo.Text := 'Abra um arquivo .nc, .gcode ou .tap para inspecionar e simular.';
  ConsoleTab := TTabSheet.Create(Self);
  ConsoleTab.PageControl := Pages;
  ConsoleTab.Caption := 'Console';
  LogBar := Panel(ConsoleTab, alTop, 50);
  ButtonAt(LogBar, 'Salvar registro...', 10, 8, 150, @SaveLogClick);
  ButtonAt(LogBar, 'Limpar console', 172, 8, 150, @ClearLogClick).Name := 'ClearConsole';
  ConsoleBar := Panel(ConsoleTab, alBottom, 50);
  BtnSend := ButtonAt(ConsoleBar, 'Enviar', 0, 8, 100, @CommandClick);
  BtnSend.Align := alRight;
  EditCommand := TEdit.Create(Self);
  EditCommand.Parent := ConsoleBar;
  EditCommand.Align := alClient;
  EditCommand.TextHint := 'Comando G-code manual';
  MemoLog := TMemo.Create(Self);
  MemoLog.Name := 'ConsoleLog';
  MemoLog.Parent := ConsoleTab;
  MemoLog.Align := alClient;
  MemoLog.ReadOnly := True;
  MemoLog.ScrollBars := ssAutoBoth;
  MemoLog.WordWrap := False;
  MemoLog.Font.Name := 'Consolas';
  Pages.ActivePage := ProgramTab;
  Timer := TTimer.Create(Self);
  Timer.Enabled := False;
  Timer.Interval := 100;
  Timer.OnTimer := @Tick;
  UpdateControls;
end;

destructor TMainForm.Destroy;
begin
  if Assigned(Timer) then Timer.Enabled := False;
  PrinterLines.Free;
  Session.Free;
  inherited Destroy;
end;

procedure TMainForm.Log(const AText: string);
begin
  MemoLog.Lines.BeginUpdate;
  try
    MemoLog.Lines.Add(FormatDateTime('hh:nn:ss', Now) + '  ' + Trim(AText));
    while MemoLog.Lines.Count > 1000 do MemoLog.Lines.Delete(0);
    MemoLog.SelStart := UTF8Length(MemoLog.Text);
  finally
    MemoLog.Lines.EndUpdate;
  end;
end;

procedure TMainForm.MarlinResponse(Sender: TObject; const AText: string);
begin
  if Trim(AText) <> '' then Log('Marlin: ' + Trim(AText));
end;
procedure TMainForm.MarlinMotion(Sender: TObject; const A, B: TAIMarlinPosition; Material: Double);
begin
  if Assigned(PrintView) then PrintView.AddMotion(Sender, A, B, Material);
end;

procedure TMainForm.UpdateControls;
var Busy, Manual: Boolean; I: Integer;
begin
  if MachineType.ItemIndex = Ord(mtPrinter3D) then begin
    Busy := PrinterConnected and (PrinterIndex < PrinterLines.Count); Manual := PrinterConnected and not Busy;
    StateLabel.Caption := IfThen(not PrinterConnected, 'Desconectado', IfThen(Busy, 'Imprimindo 3D', 'Pronto'));
    MachineType.Enabled := not PrinterConnected; ProtocolType.Enabled := not PrinterConnected;
    BtnConnect.Caption := IfThen(PrinterConnected, 'Desconectar', 'Conectar simulador'); BtnConnect.Enabled := not Busy;
    BtnOpen.Enabled := not Busy; BtnStart.Enabled := PrinterConnected and not Busy and (PrinterLines.Count > 0);
    BtnPause.Enabled := PrinterConnected and not Marlin.State.Paused and Busy; BtnResume.Enabled := PrinterConnected and Marlin.State.Paused;
    BtnStop.Enabled := PrinterConnected; BtnHome.Enabled := Manual; BtnSend.Enabled := Manual; EditCommand.Enabled := Manual; StepSize.Enabled := Manual; FeedRate.Enabled := Manual;
    PrintView.Visible := PrinterConnected; Pages.Visible := not PrinterConnected; Progress.Max := Max(1,PrinterLines.Count); Progress.Position := Min(PrinterIndex,Progress.Max); ProgressLabel.Caption := Format('%d / %d linhas processadas',[PrinterIndex,PrinterLines.Count]); Timer.Enabled := Busy; Exit;
  end;
  PrintView.Visible := False; Pages.Visible := True; Busy := Session.State in [ssRunning, ssPaused]; Manual := Session.Connected and not Busy and (Session.State <> ssError);
  case Session.State of ssDisconnected: StateLabel.Caption:='Desconectado'; ssIdle: StateLabel.Caption:='Pronto'; ssRunning: StateLabel.Caption:='Simulando'; ssPaused: StateLabel.Caption:='Pausado'; ssDone: StateLabel.Caption:='Envio concluido'; ssStopped: StateLabel.Caption:='Interrompido'; ssError: StateLabel.Caption:='Erro'; end; MachineType.Enabled := not Session.Connected; ProtocolType.Enabled := not Session.Connected; BtnConnect.Enabled := not Busy; BtnConnect.Caption := IfThen(Session.Connected,'Desconectar','Conectar simulador'); BtnOpen.Enabled := not Busy; BtnStart.Enabled := Session.Connected and not Busy and (Session.Count > 0); BtnPause.Enabled := Session.State=ssRunning; BtnResume.Enabled := Session.State=ssPaused; BtnStop.Enabled := Session.Connected; BtnHome.Enabled := Manual; BtnSend.Enabled := Manual; EditCommand.Enabled := Manual; StepSize.Enabled := Manual; FeedRate.Enabled := Manual;
  for I:=0 to 5 do JogButtons[I].Enabled := Manual and Session.SupportsAxis(TAxis(I div 2)); Progress.Max:=Max(1,Session.Count); Progress.Position:=Session.Completed; ProgressLabel.Caption:=Format('%d / %d comandos enviados',[Session.Completed,Session.Count]); Timer.Enabled:=Session.State=ssRunning;
end;
procedure TMainForm.ConnectClick(Sender: TObject);
begin
  if MachineType.ItemIndex = Ord(mtPrinter3D) then begin
    PrinterConnected := not PrinterConnected;
    if PrinterConnected then begin Marlin.Reset; Log('Simulador Marlin conectado.'); end else begin Marlin.Pause; Log('Simulador Marlin desconectado.'); end;
  end else if Session.Connected then begin Session.Disconnect; Log('Simulador desconectado.'); end
  else if Session.Connect(TMachineType(MachineType.ItemIndex), TProtocolKind(ProtocolType.ItemIndex)) then Log('Conectado: ' + MachineType.Text + ' / ' + ProtocolType.Text + ' / simulador');
  UpdateControls;
end;
procedure TMainForm.OpenClick(Sender: TObject);
var D: TOpenDialog;
begin
  D := TOpenDialog.Create(Self);
  try
    D.Title := 'Abrir programa para simulacao';
    D.Filter := 'G-code|*.nc;*.gcode;*.tap;*.ngc|Todos os arquivos|*.*';
    D.Options := [ofFileMustExist, ofEnableSizing];
    if not D.Execute then Exit;
    LoadProgram(D.FileName);
  finally
    D.Free;
    UpdateControls;
  end;
end;

procedure TMainForm.LoadProgram(const AFileName: string);
begin
  try
    if MachineType.ItemIndex = Ord(mtPrinter3D) then begin PrinterLines.LoadFromFile(AFileName); PrinterIndex:=0; ProgramMemo.Text:=PrinterLines.Text; end
    else begin Session.LoadFile(AFileName); ProgramMemo.Text:=Session.ProgramText; end;
    ProgramMemo.SelStart:=0; SearchEdit.Clear; FileLabel.Caption:=ExtractFileName(AFileName); FileLabel.Hint:=AFileName; Pages.ActivePage:=ProgramTab; Log('Programa carregado: '+AFileName);
  except on E: Exception do MessageDlg('Nao foi possivel abrir',E.Message,mtError,[mbOK],0); end;
  UpdateControls;
end;
procedure TMainForm.DropFiles(Sender: TObject; const FileNames: array of string);
begin
  if Length(FileNames) <> 1 then begin
    Status.SimpleText := 'Arraste apenas um arquivo de G-code por vez.';
    Exit;
  end;
  if Session.State in [ssRunning, ssPaused] then begin
    Status.SimpleText := 'Pare a simulacao antes de abrir outro arquivo.';
    Exit;
  end;
  LoadProgram(FileNames[0]);
end;

procedure TMainForm.SearchChanged(Sender: TObject);
begin
  ProgramMemo.SelStart := 0;
  ProgramMemo.SelLength := 0;
  SearchResult.Caption := 'Enter ou F3 para buscar. A busca retorna ao inicio.';
end;

procedure TMainForm.SearchClick(Sender: TObject);
var Source, Query: string; Offset, FoundAt, LineNo, I: Integer; Wrapped: Boolean;
begin
  Query := UpperCase(SearchEdit.Text);
  if Query = '' then begin SearchResult.Caption := 'Digite um texto para buscar.'; Exit; end;
  Source := UpperCase(ProgramMemo.Text);
  // Memo selection counts characters; PosEx counts UTF-8 bytes.
  Offset := Length(UTF8Copy(Source, 1, ProgramMemo.SelStart + ProgramMemo.SelLength)) + 1;
  FoundAt := PosEx(Query, Source, Offset);
  Wrapped := (FoundAt = 0) and (Offset > 1);
  if Wrapped then FoundAt := PosEx(Query, Source, 1);
  if FoundAt = 0 then begin SearchResult.Caption := 'Texto nao encontrado.'; Exit; end;
  Pages.ActivePage := ProgramTab;
  ProgramMemo.SelStart := UTF8Length(Copy(Source, 1, FoundAt - 1));
  ProgramMemo.SelLength := UTF8Length(Query);
  LineNo := 1;
  for I := 1 to FoundAt - 1 do if Source[I] = #10 then Inc(LineNo);
  SearchResult.Caption := Format('Comando %d da lista carregada', [LineNo]);
  if Wrapped then SearchResult.Caption := SearchResult.Caption + ' (voltou ao inicio)';
  ProgramMemo.HideSelection := False;
end;

procedure TMainForm.Shortcut(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Shift = [ssCtrl]) and (Key = Ord('O')) then begin
    if BtnOpen.Enabled then OpenClick(Sender);
    Key := 0;
  end else if (Shift = [ssCtrl]) and (Key = Ord('F')) then begin
    Pages.ActivePage := ProgramTab;
    SearchEdit.SetFocus;
    SearchEdit.SelectAll;
    Key := 0;
  end else if ((Shift = []) and (Key = VK_F3)) or
    ((Shift = []) and (Key = VK_RETURN) and (ActiveControl = SearchEdit)) then begin
    SearchClick(Sender);
    Key := 0;
  end;
end;

procedure TMainForm.SaveLogClick(Sender: TObject);
var D: TSaveDialog;
begin
  D := TSaveDialog.Create(Self);
  try
    D.Title := 'Salvar registro do simulador';
    D.Filter := 'Arquivo de texto|*.txt';
    D.DefaultExt := 'txt';
    D.FileName := 'multicnc-' + FormatDateTime('yyyymmdd-hhnnss', Now) + '.txt';
    D.Options := [ofOverwritePrompt, ofPathMustExist, ofEnableSizing];
    if D.Execute then
      try
        MemoLog.Lines.SaveToFile(D.FileName);
        Status.SimpleText := 'Registro salvo: ' + D.FileName;
      except
        on E: Exception do MessageDlg('Falha ao salvar registro', E.Message, mtError, [mbOK], 0);
      end;
  finally
    D.Free;
  end;
end;

procedure TMainForm.ClearLogClick(Sender: TObject);
begin
  MemoLog.Clear;
  Status.SimpleText := 'Console limpo. A simulacao permanece no estado atual.';
end;

procedure TMainForm.CommandClick(Sender: TObject);
var OK: Boolean;
begin
  OK:=False;
  if MachineType.ItemIndex=Ord(mtPrinter3D) then begin
    if Sender=BtnStart then begin PrinterIndex:=0; Marlin.Reset; PrintView.ClearPrint; OK:=True; end
    else if Sender=BtnPause then begin Marlin.Pause; OK:=True; end
    else if Sender=BtnResume then begin Marlin.Resume; OK:=True; end
    else if Sender=BtnStop then begin Marlin.EmergencyStop; PrinterIndex:=PrinterLines.Count; OK:=True; end
    else if Sender=BtnHome then OK:=Marlin.SubmitLine('G28')
    else if Sender=BtnSend then begin OK:=Marlin.SubmitLine(EditCommand.Text); if OK then begin Marlin.Advance(0.1); EditCommand.Clear; end; end;
  end else begin
    if Sender=BtnStart then OK:=Session.Start else if Sender=BtnPause then OK:=Session.Pause else if Sender=BtnResume then OK:=Session.Resume else if Sender=BtnStop then OK:=Session.Stop else if Sender=BtnHome then OK:=Session.Home else if Sender=BtnSend then begin OK:=Session.Send(EditCommand.Text); if OK then EditCommand.Clear; end;
  end;
  if OK then Log(TButton(Sender).Caption+': OK') else Log('Acao recusada. Verifique o estado e o comando.'); UpdateControls;
end;
procedure TMainForm.JogClick(Sender: TObject);
var Index: Integer; Distance: Double;
begin
  Index := TButton(Sender).Tag;
  Distance := StepSize.Value;
  if Index mod 2 = 0 then Distance := -Distance;
  if not Session.Jog(TAxis(Index div 2), Distance, FeedRate.Value) then Log('Movimento recusado.');
  UpdateControls;
end;

procedure TMainForm.Tick(Sender: TObject);
begin
  try
    if MachineType.ItemIndex=Ord(mtPrinter3D) then begin
      if PrinterIndex<PrinterLines.Count then begin Marlin.SubmitLine(PrinterLines[PrinterIndex]); Inc(PrinterIndex); end;
      Marlin.Advance(0.1);
      if (PrinterIndex>=PrinterLines.Count) and Marlin.IsIdle then Log('Impressao 3D concluida.');
    end else Session.Tick;
  except on E: Exception do begin if MachineType.ItemIndex=Ord(mtPrinter3D) then Marlin.EmergencyStop else Session.Stop; Log('Falha na simulacao: '+E.Message); end; end;
  UpdateControls;
end;
procedure TMainForm.Closing(Sender: TObject; var CanClose: Boolean);
begin
  CanClose := True;
  if Session.State in [ssRunning, ssPaused] then begin
    CanClose := MessageDlg('Simulacao em andamento',
      'Interromper a simulacao e fechar?', mtConfirmation, [mbYes, mbNo], 0) = mrYes;
    if CanClose then Session.Stop;
  end;
end;

end.
