unit mainform;

{$mode objfpc}{$H+}

interface

uses Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls,
  Dialogs, Graphics, Spin, StrUtils, LazUTF8, LCLType, multicnc_types,
  multicnc_session, multicnc_gcode_analyzer, multicnc_preview;

type
  TMainForm = class(TForm)
  private
    Session: TSimulationSession;
    MachineType, ProtocolType: TComboBox;
    BtnConnect, BtnOpen, BtnStart, BtnPause, BtnResume, BtnStop, BtnHome, BtnSend: TButton;
    JogButtons: array[0..5] of TButton;
    StepSize: TFloatSpinEdit;
    FeedRate: TSpinEdit;
    ProgramMemo, MemoLog, AnalysisWarnings: TMemo;
    EditCommand, SearchEdit: TEdit;
    Pages: TPageControl;
    ProgramTab, PreviewTab: TTabSheet;
    Preview: TGCodePreview;
    Trace: TGCodeTrace;
    Envelope: TMachineEnvelope;
    Report: TGCodeReport;
    AnalysisLabel: TLabel;
    PlaneChoice: TComboBox;
    BtnEnvelope, BtnReport: TButton;
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
    procedure ConnectClick(Sender: TObject);
    procedure OpenClick(Sender: TObject);
    procedure CommandClick(Sender: TObject);
    procedure JogClick(Sender: TObject);
    procedure Tick(Sender: TObject);
    procedure Log(const AText: string);
    procedure UpdateControls;
    procedure Closing(Sender: TObject; var CanClose: Boolean);
    procedure AnalyzeProgram;
    procedure AnalysisSettingsClick(Sender: TObject);
    procedure ExportAnalysisClick(Sender: TObject);
    procedure PlaneChanged(Sender: TObject);
    procedure MachineChanged(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure OpenFile(const AFileName: string);
    procedure SetAnalysisEnvelope(const Value: TMachineEnvelope);
    property AnalysisReport: TGCodeReport read Report;
    property ProgramTrace: TGCodeTrace read Trace;
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
var Header, Connection, Body, Side, Workspace, Actions, Footer, ConsoleBar, SearchBar, LogBar, PreviewBar: TPanel;
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
  Trace := TGCodeTrace.Create;
  Envelope := DefaultEnvelope(300, 300, 100);

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
    'Use a previa para revisar o' + LineEnding + 'G-code antes de simular.', 20, 392);
  L.Font.Color := clGrayText;

  Workspace := Panel(Body, alClient, 0);
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
  PreviewTab := TTabSheet.Create(Self);
  PreviewTab.PageControl := Pages;
  PreviewTab.Caption := 'Trajetoria e analise';
  PreviewBar := Panel(PreviewTab, alTop, 48);
  PlaneChoice := TComboBox.Create(Self);
  PlaneChoice.Name := 'PreviewPlane'; PlaneChoice.Parent := PreviewBar;
  PlaneChoice.SetBounds(10, 10, 110, 28); PlaneChoice.Style := csDropDownList;
  PlaneChoice.Items.Add('XY'); PlaneChoice.Items.Add('XZ'); PlaneChoice.Items.Add('YZ');
  PlaneChoice.ItemIndex := 0; PlaneChoice.OnChange := @PlaneChanged;
  BtnEnvelope := ButtonAt(PreviewBar, 'Limites da analise...', 132, 6, 190, @AnalysisSettingsClick);
  BtnEnvelope.Name := 'AnalysisSettings';
  BtnReport := ButtonAt(PreviewBar, 'Exportar relatorio...', 334, 6, 190, @ExportAnalysisClick);
  AnalysisLabel := TLabel.Create(Self); AnalysisLabel.Name := 'AnalysisSummary';
  AnalysisLabel.Parent := PreviewTab; AnalysisLabel.Align := alTop;
  AnalysisLabel.AutoSize := False; AnalysisLabel.Height := 116;
  AnalysisLabel.WordWrap := True; AnalysisLabel.BorderSpacing.Around := 8;
  AnalysisLabel.Caption := 'Analise a partir da origem de trabalho X0 Y0 Z0. Configure os limites antes de simular.';
  AnalysisWarnings := TMemo.Create(Self); AnalysisWarnings.Name := 'AnalysisWarnings';
  AnalysisWarnings.Parent := PreviewTab; AnalysisWarnings.Align := alBottom;
  AnalysisWarnings.Height := 105; AnalysisWarnings.ReadOnly := True;
  AnalysisWarnings.ScrollBars := ssAutoVertical;
  Preview := TGCodePreview.Create(Self); Preview.Parent := PreviewTab;
  Preview.Align := alClient; Preview.SetProgram(Trace, Envelope);
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
  MachineType.OnChange := @MachineChanged;
  UpdateControls;
end;

destructor TMainForm.Destroy;
begin
  if Assigned(Timer) then Timer.Enabled := False;
  Session.Free;
  Trace.Free;
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
  if Session.Connected then BtnConnect.Caption := 'Desconectar' else BtnConnect.Caption := 'Conectar simulador';
  BtnConnect.Enabled := not Busy;
  BtnOpen.Enabled := not Busy;
  BtnStart.Enabled := Session.Connected and not Busy and (Session.Count > 0) and (Report.Errors = 0);
  BtnEnvelope.Enabled := not Busy;
  BtnReport.Enabled := Session.Count > 0;
  BtnPause.Enabled := Session.State = ssRunning;
  BtnResume.Enabled := Session.State = ssPaused;
  BtnStop.Enabled := Session.Connected;
  BtnHome.Enabled := Manual;
  BtnSend.Enabled := Manual;
  EditCommand.Enabled := Manual;
  StepSize.Enabled := Manual;
  FeedRate.Enabled := Manual;
  for I := 0 to 5 do JogButtons[I].Enabled := Manual and Session.SupportsAxis(TAxis(I div 2));
  Progress.Max := Session.Count;
  if Progress.Max = 0 then Progress.Max := 1;
  Progress.Position := Session.Completed;
  ProgressLabel.Caption := Format('%d / %d comandos enviados', [Session.Completed, Session.Count]);
  Timer.Enabled := Session.State = ssRunning;
end;

procedure TMainForm.ConnectClick(Sender: TObject);
begin
  if Session.Connected then begin Session.Disconnect; Log('Simulador desconectado.'); end
  else if Session.Connect(TMachineType(MachineType.ItemIndex), TProtocolKind(ProtocolType.ItemIndex)) then
    Log('Conectado: ' + MachineType.Text + ' / ' + ProtocolType.Text + ' / simulador');
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
    OpenFile(AFileName);
  except
    on E: Exception do MessageDlg('Nao foi possivel abrir', E.Message, mtError, [mbOK], 0);
  end;
  UpdateControls;
end;

procedure TMainForm.OpenFile(const AFileName: string);
begin
  // O mesmo fluxo atende ao dialogo, drag/drop e --file do launcher.
  Session.LoadFile(AFileName);
  ProgramMemo.Text := Session.ProgramText; ProgramMemo.SelStart := 0;
  SearchEdit.Clear;
  FileLabel.Caption := ExtractFileName(Session.FileName); FileLabel.Hint := Session.FileName;
  AnalyzeProgram;
  Pages.ActivePage := PreviewTab;
  Log('Programa carregado: ' + Session.FileName);
  UpdateControls;
end;

procedure TMainForm.SetAnalysisEnvelope(const Value: TMachineEnvelope);
begin
  if Session.State in [ssRunning, ssPaused] then
    raise Exception.Create('Pare a simulacao antes de alterar os limites.');
  ValidateEnvelope(Value);
  Envelope := Value; AnalyzeProgram; UpdateControls;
end;

procedure TMainForm.AnalyzeProgram;
var W: TStringList;
begin
  if Session.Count = 0 then begin Preview.SetProgram(Trace, Envelope); Exit; end;
  W := TStringList.Create;
  try
    Report := TGCodeAnalyzer.Analyze(ProgramMemo.Lines, Envelope, W, Trace);
    AnalysisWarnings.Lines.Assign(W);
    AnalysisLabel.Caption := Format('%d movimentos | %d arcos | %d erros | %d avisos',
      [Report.Motions, Report.Arcs, Report.Errors, W.Count]) + LineEnding +
      Format('Corte: %.1f mm | Rapido: %.1f mm | Tempo estimado: %s',
      [Report.CutLength, Report.RapidLength, FormatDuration(Report.EstimatedSeconds)]) + LineEnding +
      Format('Trajetoria: X %.2f..%.2f | Y %.2f..%.2f | Z %.2f..%.2f mm',
      [Report.MinX, Report.MaxX, Report.MinY, Report.MaxY, Report.MinZ, Report.MaxZ]) + LineEnding +
      Format('Limites: X %.1f..%.1f | Y %.1f..%.1f | Z %.1f..%.1f mm',
      [Envelope.MinX, Envelope.MaxX, Envelope.MinY, Envelope.MaxY, Envelope.MinZ, Envelope.MaxZ]) + LineEnding +
      'Origem de trabalho assumida: X0 Y0 Z0. Tempo e trajetoria sao estimativas.';
    if Report.Incomplete and not Report.LimitReached then AnalysisWarnings.Lines.Insert(0,
      'Analise parcial: coordenadas de maquina, homing ou probe dependem do controlador.');
    if Trace.Truncated then AnalysisWarnings.Lines.Add('Previa limitada aos primeiros 200000 segmentos. Consulte os avisos para limites da analise.');
    Preview.SetProgram(Trace, Envelope);
    if Report.Errors > 0 then
      Status.SimpleText := 'Erros na analise: confira a aba Trajetoria e analise antes de simular.'
    else if Report.Incomplete then Status.SimpleText := 'Analise parcial. Confira os avisos.'
    else Status.SimpleText := 'Analise concluida. Revise limites, trajetoria e avisos antes de simular.';
  finally W.Free; end;
end;

procedure TMainForm.MachineChanged(Sender: TObject);
begin
  Envelope.RequireSpindleForCut := MachineType.ItemIndex <> Ord(mtPrinter3D);
  AnalyzeProgram; UpdateControls;
end;

procedure TMainForm.PlaneChanged(Sender: TObject);
begin Preview.Plane := TPreviewPlane(PlaneChoice.ItemIndex); end;

procedure TMainForm.AnalysisSettingsClick(Sender: TObject);
const Names: array[0..9] of string = ('X minimo (mm)', 'X maximo (mm)', 'Y minimo (mm)',
  'Y maximo (mm)', 'Z minimo (mm)', 'Z maximo (mm)', 'Avanco maximo (mm/min)',
  'Avanco rapido (mm/min)', 'Aceleracao XY (mm/s2)', 'Aceleracao Z (mm/s2)');
var D: TForm; Edits: array[0..9] of TFloatSpinEdit; Values: array[0..9] of Double;
  I: Integer; L: TLabel; B: TButton; E: TMachineEnvelope;
begin
  D := TForm.CreateNew(Self);
  try
    D.Caption := 'Limites para analise e simulacao'; D.Position := poOwnerFormCenter;
    D.SetBounds(0, 0, 430, 500); D.BorderStyle := bsDialog;
    Values[0] := Envelope.MinX; Values[1] := Envelope.MaxX;
    Values[2] := Envelope.MinY; Values[3] := Envelope.MaxY;
    Values[4] := Envelope.MinZ; Values[5] := Envelope.MaxZ;
    Values[6] := Envelope.MaxFeed; Values[7] := Envelope.RapidFeed;
    Values[8] := Envelope.Acceleration; Values[9] := Envelope.AccelerationZ;
    for I := 0 to 9 do begin
      L := TLabel.Create(D); L.Parent := D; L.SetBounds(12, 14 + I * 38, 225, 25); L.Caption := Names[I];
      Edits[I] := TFloatSpinEdit.Create(D); Edits[I].Parent := D;
      Edits[I].SetBounds(244, 10 + I * 38, 170, 30); Edits[I].MinValue := -1000000;
      Edits[I].MaxValue := 1000000; Edits[I].DecimalPlaces := 3; Edits[I].Value := Values[I];
    end;
    L := TLabel.Create(D); L.Parent := D; L.SetBounds(12, 396, 402, 32);
    L.Caption := 'Informe limites no sistema de coordenadas do programa.';
    B := TButton.Create(D); B.Parent := D; B.SetBounds(190, 442, 105, 32);
    B.Caption := 'Aplicar'; B.ModalResult := mrOK; B.Default := True;
    B := TButton.Create(D); B.Parent := D; B.SetBounds(309, 442, 105, 32);
    B.Caption := 'Cancelar'; B.ModalResult := mrCancel; B.Cancel := True;
    if D.ShowModal <> mrOK then Exit;
    E := Envelope; E.MinX := Edits[0].Value; E.MaxX := Edits[1].Value;
    E.MinY := Edits[2].Value; E.MaxY := Edits[3].Value;
    E.MinZ := Edits[4].Value; E.MaxZ := Edits[5].Value;
    E.MaxFeed := Edits[6].Value; E.RapidFeed := Edits[7].Value;
    E.Acceleration := Edits[8].Value; E.AccelerationZ := Edits[9].Value;
    try SetAnalysisEnvelope(E);
    except on Ex: Exception do MessageDlg('Limites invalidos', Ex.Message, mtError, [mbOK], 0); end;
  finally D.Free; end;
end;

procedure TMainForm.ExportAnalysisClick(Sender: TObject);
var D: TSaveDialog; Lines: TStringList;
begin
  D := TSaveDialog.Create(Self); Lines := TStringList.Create;
  try
    D.Filter := 'Relatorio de texto|*.txt'; D.DefaultExt := 'txt';
    D.FileName := ChangeFileExt(ExtractFileName(Session.FileName), '-analise.txt');
    D.Options := [ofOverwritePrompt, ofPathMustExist, ofEnableSizing];
    if not D.Execute then Exit;
    Lines.Add('MultiCNC - Analise de G-code'); Lines.Add('Arquivo: ' + Session.FileName);
    Lines.Add(AnalysisLabel.Caption); Lines.Add(''); Lines.AddStrings(AnalysisWarnings.Lines);
    try Lines.SaveToFile(D.FileName); Status.SimpleText := 'Relatorio salvo: ' + D.FileName;
    except on E: Exception do MessageDlg('Falha ao salvar', E.Message, mtError, [mbOK], 0); end;
  finally Lines.Free; D.Free; end;
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
  SearchResult.Caption := Format('Linha %d do arquivo', [LineNo]);
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
  if Sender = BtnStart then begin
    if Report.Errors = 0 then OK := Session.Start
    else Log('Corrija os erros da analise antes de iniciar a simulacao.');
  end
  else if Sender = BtnPause then OK := Session.Pause
  else if Sender = BtnResume then OK := Session.Resume
  else if Sender = BtnStop then OK := Session.Stop
  else if Sender = BtnHome then OK := Session.Home
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
