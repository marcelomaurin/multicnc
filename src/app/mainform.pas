unit mainform;

{$mode objfpc}{$H+}

interface

uses Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls,
  Dialogs, Graphics, Spin, StrUtils, LazUTF8, LCLType, multicnc_types, multicnc_session;

type
  TMainForm = class(TForm)
  private
    Session: TSimulationSession;
    MachineType, ProtocolType: TComboBox;
    DeviceEdit, BaudEdit, HostEdit, PortEdit: TEdit;
    CommunicationMode: TComboBox;
    SerialPanel, TCPPanel: TPanel;
    BtnConnect, BtnOpen, BtnStart, BtnPause, BtnResume, BtnStop, BtnHome,
      BtnZero, BtnStatus, BtnUnlock, BtnSend: TButton;
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
    procedure CommunicationChanged(Sender: TObject);
    procedure SelectionChanged(Sender: TObject);
    procedure ConnectClick(Sender: TObject);
    procedure OpenClick(Sender: TObject);
    procedure CommandClick(Sender: TObject);
    procedure JogClick(Sender: TObject);
    procedure Tick(Sender: TObject);
    procedure Log(const AText: string);
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

  Connection := Panel(Self, alTop, 105);
  Connection.Top := 90;
  LabelAt(Connection, 'Maquina', 20, 5);
  MachineType := TComboBox.Create(Self);
  MachineType.Parent := Connection;
  MachineType.SetBounds(20, 29, 150, 30);
  MachineType.Style := csDropDownList;
  MachineType.Items.Add('CNC Router');
  MachineType.Items.Add('Laser');
  MachineType.Items.Add('Impressora 3D');
  MachineType.ItemIndex := 0;
  MachineType.OnChange := @SelectionChanged;
  LabelAt(Connection, 'Protocolo', 185, 5);
  ProtocolType := TComboBox.Create(Self);
  ProtocolType.Parent := Connection;
  ProtocolType.SetBounds(185, 29, 125, 30);
  ProtocolType.Style := csDropDownList;
  ProtocolType.Items.Add('GRBL');
  ProtocolType.Items.Add('Marlin');
  ProtocolType.ItemIndex := 0;
  ProtocolType.OnChange := @SelectionChanged;
  LabelAt(Connection, 'Comunicação', 325, 5);
  CommunicationMode := TComboBox.Create(Self);
  CommunicationMode.Parent := Connection;
  CommunicationMode.SetBounds(325, 29, 100, 28);
  CommunicationMode.Items.Add('Serial');
  CommunicationMode.Items.Add('TCP');
  CommunicationMode.ItemIndex := 0;
  CommunicationMode.Style := csDropDownList;
  CommunicationMode.OnChange := @CommunicationChanged;

  SerialPanel := TPanel.Create(Self);
  SerialPanel.Parent := Connection;
  SerialPanel.SetBounds(440, 0, 260, 90);
  SerialPanel.BevelOuter := bvNone;
  TCPPanel := TPanel.Create(Self);
  TCPPanel.Parent := Connection;
  TCPPanel.SetBounds(440, 0, 260, 90);
  TCPPanel.BevelOuter := bvNone;

  LabelAt(SerialPanel, 'Porta COM', 0, 5);
  DeviceEdit := TEdit.Create(Self);
  DeviceEdit.Parent := SerialPanel;
  DeviceEdit.SetBounds(0, 29, 120, 30);
  DeviceEdit.Text := 'COM3';
  LabelAt(SerialPanel, 'Baud', 135, 5);
  BaudEdit := TEdit.Create(Self);
  BaudEdit.Parent := SerialPanel;
  BaudEdit.SetBounds(135, 29, 110, 30);
  BaudEdit.Text := '115200';

  LabelAt(TCPPanel, 'IP do equipamento', 0, 5);
  HostEdit := TEdit.Create(Self);
  HostEdit.Parent := TCPPanel;
  HostEdit.SetBounds(0, 29, 155, 30);
  HostEdit.Text := '127.0.0.1';
  LabelAt(TCPPanel, 'Porta TCP', 165, 5);
  PortEdit := TEdit.Create(Self);
  PortEdit.Parent := TCPPanel;
  PortEdit.SetBounds(165, 29, 80, 30);
  PortEdit.Text := '9000';
  BtnConnect := ButtonAt(Connection, 'Conectar equipamento', 715, 26, 205, @ConnectClick);
  CommunicationChanged(Self);

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
  BtnZero := ButtonAt(Side, 'Zerar coordenadas (G92)', 20, 380, 220, @CommandClick);
  BtnStatus := ButtonAt(Side, 'Consultar posição/status', 20, 424, 220, @CommandClick);
  BtnUnlock := ButtonAt(Side, 'Desbloquear / reset', 20, 468, 220, @CommandClick);
  L := LabelAt(Side, 'Posição: consulte no equipamento' + LineEnding +
    'Os comandos são enviados conforme o protocolo selecionado.', 20, 520);
  L.Font.Color := clGrayText;

  Workspace := Panel(Body, alClient, 0);
  Actions := Panel(Workspace, alTop, 106);
  BtnOpen := ButtonAt(Actions, 'Abrir programa CNC...', 12, 10, 170, @OpenClick);
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

procedure TMainForm.UpdateControls;
const StateNames: array[TSessionState] of string = ('Desconectado', 'Pronto',
  'Simulando', 'Pausado', 'Envio simulado concluido', 'Interrompido', 'Erro');
var Busy, Manual: Boolean; I: Integer;
begin
  Busy := Session.State in [ssRunning, ssPaused];
  Manual := Session.Connected and not Busy and (Session.State <> ssError);
  StateLabel.Caption := StateNames[Session.State];
  MachineType.Enabled := not Session.Connected;
  ProtocolType.Enabled := not Session.Connected;
  CommunicationMode.Enabled := not Session.Connected;
  HostEdit.Enabled := not Session.Connected;
  PortEdit.Enabled := not Session.Connected;
  DeviceEdit.Enabled := not Session.Connected;
  BaudEdit.Enabled := not Session.Connected;
  if Session.Connected then BtnConnect.Caption := 'Desconectar' else BtnConnect.Caption := 'Conectar equipamento';
  BtnConnect.Enabled := not Busy;
  BtnOpen.Enabled := not Busy;
  BtnStart.Enabled := Session.Connected and not Busy and (Session.Count > 0);
  BtnPause.Enabled := Session.State = ssRunning;
  BtnResume.Enabled := Session.State = ssPaused;
  BtnStop.Enabled := Session.Connected;
  BtnHome.Enabled := Manual;
  BtnZero.Enabled := Manual;
  BtnStatus.Enabled := Session.Connected;
  BtnUnlock.Enabled := Manual;
  BtnSend.Enabled := Manual;
  EditCommand.Enabled := Manual;
  StepSize.Enabled := Manual;
  FeedRate.Enabled := Manual;
  for I := 0 to 5 do JogButtons[I].Enabled := Manual and Session.SupportsAxis(TAxis(I div 2));
  Progress.Max := Session.Count;
  if Progress.Max = 0 then Progress.Max := 1;
  Progress.Position := Session.Completed;
  ProgressLabel.Caption := Format('%d / %d comandos enviados', [Session.Completed, Session.Count]);
  Timer.Enabled := Session.Connected;
end;

procedure TMainForm.SelectionChanged(Sender: TObject);
begin
  if MachineType.ItemIndex = 2 then begin
    BtnOpen.Caption := 'Abrir G-code...';
    if Sender = MachineType then ProtocolType.ItemIndex := 1;
  end else begin
    BtnOpen.Caption := 'Abrir programa CNC...';
    if Sender = MachineType then ProtocolType.ItemIndex := 0;
  end;
end;

procedure TMainForm.CommunicationChanged(Sender: TObject);
begin
  SerialPanel.Visible := CommunicationMode.ItemIndex = 0;
  TCPPanel.Visible := CommunicationMode.ItemIndex = 1;
end;

procedure TMainForm.ConnectClick(Sender: TObject);
var Endpoint: string; Baud, PortNumber: Integer;
begin
  if Session.Connected then begin
    Session.Disconnect;
    Log('Equipamento desconectado.');
  end else begin
    Baud := 115200;
    if CommunicationMode.ItemIndex = 0 then begin
      Endpoint := Trim(DeviceEdit.Text);
      if (Endpoint = '') or (Pos(':', Endpoint) > 0) then begin
        Log('Informe uma porta serial válida, por exemplo COM3.'); Exit;
      end;
      if not TryStrToInt(Trim(BaudEdit.Text), Baud) or (Baud <= 0) then begin
        Log('Informe um baud rate positivo.'); Exit;
      end;
    end else begin
      if (Trim(HostEdit.Text) = '') or (Pos(':', HostEdit.Text) > 0) then begin
        Log('Informe o IPv4 do equipamento no campo IP.'); Exit;
      end;
      if not TryStrToInt(Trim(PortEdit.Text), PortNumber) or
         (PortNumber < 1) or (PortNumber > 65535) then begin
        Log('A porta TCP deve estar entre 1 e 65535.'); Exit;
      end;
      Endpoint := Trim(HostEdit.Text) + ':' + IntToStr(PortNumber);
    end;
    try
      if Session.Connect(TMachineType(MachineType.ItemIndex),
        TProtocolKind(ProtocolType.ItemIndex), Endpoint, Baud) then
        Log('Conectado: ' + MachineType.Text + ' / ' + ProtocolType.Text + ' em ' + Endpoint)
      else Log('Falha ao conectar em ' + Endpoint + '. Confira a porta e o equipamento.');
    except
      on E: Exception do Log('Falha na conexão: ' + E.Message);
    end;
  end;
  UpdateControls;
end;

procedure TMainForm.OpenClick(Sender: TObject);
var D: TOpenDialog;
begin
  D := TOpenDialog.Create(Self);
  try
    D.Title := 'Abrir programa para simulacao';
    if MachineType.ItemIndex = 2 then begin
      D.Title := 'Abrir G-code da impressora 3D';
      D.Filter := 'G-code|*.gcode;*.gco;*.nc;*.ngc|Todos os arquivos|*.*';
    end else begin
      D.Title := 'Abrir programa CNC';
      D.Filter := 'Programas CNC|*.nc;*.tap;*.cnc;*.ngc;*.gcode|Todos os arquivos|*.*';
    end;
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
    Session.LoadFile(AFileName);
    ProgramMemo.Text := Session.ProgramText;
    ProgramMemo.SelStart := 0;
    SearchEdit.Clear;
    FileLabel.Caption := ExtractFileName(Session.FileName);
    FileLabel.Hint := Session.FileName;
    Pages.ActivePage := ProgramTab;
    Log('Programa carregado: ' + Session.FileName);
  except
    on E: Exception do MessageDlg('Nao foi possivel abrir', E.Message, mtError, [mbOK], 0);
  end;
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
  OK := False;
  if Sender = BtnStart then OK := Session.Start
  else if Sender = BtnPause then OK := Session.Pause
  else if Sender = BtnResume then OK := Session.Resume
  else if Sender = BtnStop then OK := Session.Stop
  else if Sender = BtnHome then OK := Session.Home
  else if Sender = BtnZero then OK := Session.Zero
  else if Sender = BtnStatus then OK := Session.Status
  else if Sender = BtnUnlock then OK := Session.Unlock
  else if Sender = BtnSend then begin
    OK := Session.Send(EditCommand.Text);
    if OK then EditCommand.Clear;
  end;
  if OK then Log(TButton(Sender).Caption + ': OK')
  else Log('Acao recusada. Verifique a conexao, o estado e o comando.');
  UpdateControls;
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
    Session.Poll;
    Session.Tick;
  except
    on E: Exception do begin Session.Stop; Log('Falha na simulacao: ' + E.Message); end;
  end;
  if Session.State = ssDone then Log('Envio simulado concluido. Nao representa usinagem fisica.');
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

