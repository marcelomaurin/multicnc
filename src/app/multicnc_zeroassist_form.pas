unit multicnc_zeroassist_form;

{ MultiCNC - janela "Zero pelo bloco" (router).

  O operador mostra onde esta o bloco de madeira e o MultiCNC determina onde
  deve ficar o ponto zero do G-code:
    0. Espessura do bloco: o corte nao pode descer alem da espessura menos a
       folga (minimo 2 mm) - passar do bloco leva a fresa na mesa e quebra.
       Com o corte fundo demais, o zero nao e aplicado e o Iniciar fica
       bloqueado na janela principal;
    1. X/Y: leve a fresa (acima do bloco) ate um canto do bloco (ou o
       centro) e marque. A janela mostra onde fica o ponto zero X/Y do
       programa, aplica (G92) e pode levar a fresa ate o zero para conferir;
    2. Z: encoste a fresa no topo do bloco e marque. A janela mostra onde
       fica o ponto zero Z (topo do bloco ou mesa, pelo G-code) e aplica.
  A posicao marcada pode ser a atual ou digitada. Calculo em
  multicnc_zero_assist (testado sem tela).

  Janela nao modal: o jog da janela principal continua funcionando. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, StrUtils, Forms, Controls, StdCtrls, ExtCtrls, Spin, Graphics,
  multicnc_types, multicnc_session, multicnc_zero_assist,
  multisuite_controls, multisuite_icons;

type
  TZeroLogEvent = procedure(const AText: string) of object;

  TZeroAssistForm = class(TForm)
  private
    FSession: TSimulationSession;
    FOnLog: TZeroLogEvent;
    FBlock: TBlockPlacement;
    FXYApplied: Boolean;
    FLastCommand: string;
    FProgramText: string;
    FBuilding: Boolean;
    InfoLabel, PosLabel, DepthResult, XYResult, ZResult, StateLabel: TLabel;
    Thickness, Clearance: TFloatSpinEdit;
    PointBox: TComboBox;
    MarkX, MarkY, TouchZ: TFloatSpinEdit;
    BtnUseXY, BtnApplyXY, BtnShowZero, BtnBack, BtnUseZ, BtnApplyZ, BtnLift, BtnClose: TSuiteButton;
    Timer: TTimer;
    function Lbl(AParent: TWinControl; const AText: string; X, Y, W, H: Integer): TLabel;
    function Btn(AParent: TWinControl; const AText: string; X, Y, W: Integer; AIcon: TSuiteIconKind;
      AHandler: TNotifyEvent): TSuiteButton;
    function Spin(AParent: TWinControl; const AName: string; X, Y: Integer): TFloatSpinEdit;
    procedure Section(AParent: TWinControl; const AText: string; AIcon: TSuiteIconKind; Y: Integer);
    procedure Say(const AText: string; AColor: TColor);
    function Ready: Boolean;
    function Point: TBlockPoint;
    function TopZ: Double;
    function PlacedBlock: TBlockPlacement;
    procedure SendCmd(const ACmd: string);
    procedure TimerTick(Sender: TObject);
    procedure UseXYClick(Sender: TObject);
    procedure ApplyXYClick(Sender: TObject);
    procedure ShowZeroClick(Sender: TObject);
    procedure BackClick(Sender: TObject);
    procedure UseZClick(Sender: TObject);
    procedure ApplyZClick(Sender: TObject);
    procedure LiftClick(Sender: TObject);
    procedure CloseClick(Sender: TObject);
    procedure RefreshResults(Sender: TObject);
  public
    constructor CreateAssist(AOwner: TComponent; ASession: TSimulationSession; AProgram: TStrings;
      AOnLog: TZeroLogEvent);
    procedure ApplyXY;
    procedure ApplyZ;
    { profundidade do programa contra a espessura informada (folga >= 2 mm) }
    function DepthOK(out Msg: string): Boolean;
    property Block: TBlockPlacement read FBlock;
    property LastCommand: string read FLastCommand;
    { texto do programa para o qual a janela foi aberta }
    property ProgramText: string read FProgramText;
  end;

implementation

const
  SAFE_FEED = 1000;   { mm/min para mostrar o zero e voltar }

function TZeroAssistForm.Lbl(AParent: TWinControl; const AText: string; X, Y, W, H: Integer): TLabel;
begin
  Result := TLabel.Create(Self);
  Result.Parent := AParent;
  Result.AutoSize := False;
  Result.WordWrap := True;
  Result.SetBounds(X, Y, W, H);
  Result.Caption := AText;
  Result.Font.Color := clSuiteText;
end;

function TZeroAssistForm.Btn(AParent: TWinControl; const AText: string; X, Y, W: Integer;
  AIcon: TSuiteIconKind; AHandler: TNotifyEvent): TSuiteButton;
begin
  Result := TSuiteButton.Create(Self);
  Result.Parent := AParent;
  Result.Caption := AText;
  Result.SetBounds(X, Y, W, 34);
  Result.SetLook(sbsSoft, clSuitePrimary, AIcon);
  Result.OnClick := AHandler;
end;

function TZeroAssistForm.Spin(AParent: TWinControl; const AName: string; X, Y: Integer): TFloatSpinEdit;
begin
  Result := TFloatSpinEdit.Create(Self);
  Result.Parent := AParent;
  Result.Name := AName;
  Result.SetBounds(X, Y, 120, 28);
  Result.DecimalPlaces := 3;
  Result.MinValue := -5000; Result.MaxValue := 5000;
  Result.Increment := 0.1;
  Result.OnChange := @RefreshResults;
end;

procedure TZeroAssistForm.Section(AParent: TWinControl; const AText: string; AIcon: TSuiteIconKind; Y: Integer);
begin
  with TSuiteSectionTitle.CreateTitle(Self, AText, AIcon, clSuitePrimary) do
  begin
    Parent := AParent; SetBounds(16, Y, 520, 24);
  end;
end;

constructor TZeroAssistForm.CreateAssist(AOwner: TComponent; ASession: TSimulationSession;
  AProgram: TStrings; AOnLog: TZeroLogEvent);
var H: TSuiteHeader; Body: TScrollBox; Y: Integer; P: TBlockPoint;
begin
  inherited CreateNew(AOwner, 1);
  FBuilding := True;   { campos ainda sendo criados: nada de recalcular }
  FSession := ASession;
  FOnLog := AOnLog;
  Caption := 'Zero pelo bloco';
  Width := 580; Height := 760;
  Position := poOwnerFormCenter;
  BorderStyle := bsSizeToolWin;
  FormStyle := fsStayOnTop;
  Font.Name := SUITE_FONT; Font.Size := 10;
  Color := clSuiteSurface;
  FBlock := BlockPlacement(AProgram);
  FProgramText := AProgram.Text;

  H := TSuiteHeader.Create(Self);
  H.Parent := Self; H.Align := alTop; H.Height := 60;
  H.Setup('Zero pelo bloco', 'Mostre onde esta o bloco: o MultiCNC acha o ponto zero do G-code', sikOrigin);
  Body := TScrollBox.Create(Self);
  Body.Parent := Self; Body.Align := alClient; Body.BorderStyle := bsNone; Body.Color := clSuiteCard;
  Body.HorzScrollBar.Visible := False;

  if FBlock.Valid then
    InfoLabel := Lbl(Body, FBlock.Datum + '.', 16, 10, 520, 58)
  else
    InfoLabel := Lbl(Body, 'O programa carregado nao tem movimento de corte (G1/G2/G3).', 16, 10, 520, 40);
  PosLabel := Lbl(Body, 'Posicao atual: -', 16, 72, 520, 22);
  PosLabel.Font.Name := 'Consolas';
  PosLabel.Font.Style := [fsBold];

  { 0. espessura }
  Y := 100;
  Section(Body, 'ESPESSURA DO BLOCO', sikLayers, Y);
  Lbl(Body, 'Espessura (mm)', 16, Y + 30, 120, 18);
  Lbl(Body, 'Folga minima (mm)', 146, Y + 30, 140, 18);
  Thickness := Spin(Body, 'ZeroThickness', 16, Y + 50);
  Thickness.MinValue := 0; Thickness.MaxValue := 500;
  Thickness.Value := FBlock.Thickness;
  Clearance := Spin(Body, 'ZeroClearance', 146, Y + 50);
  Clearance.MinValue := MIN_DEPTH_CLEARANCE; Clearance.MaxValue := 100;
  Clearance.Value := MIN_DEPTH_CLEARANCE;
  Clearance.Hint := 'Distancia minima entre o fundo do corte e a face de baixo do bloco (no minimo 2 mm)';
  Clearance.ShowHint := True;
  DepthResult := Lbl(Body, '', 276, Y + 30, 260, 70);
  DepthResult.Font.Style := [fsBold];

  { 1. X/Y }
  Y := 196;
  Section(Body, '1  POSICAO DO BLOCO (X / Y)', sikTarget, Y);
  Lbl(Body, 'Leve a fresa (acima do bloco) ate o ponto escolhido do bloco e marque. Ou digite a posicao.',
    16, Y + 28, 520, 40);
  PointBox := TComboBox.Create(Self);
  PointBox.Parent := Body; PointBox.Name := 'ZeroBlockPoint';
  PointBox.Style := csDropDownList;
  PointBox.SetBounds(16, Y + 70, 260, 28);
  for P := Low(TBlockPoint) to High(TBlockPoint) do PointBox.Items.Add(BLOCK_POINT_NAMES[P]);
  PointBox.ItemIndex := 0;
  PointBox.OnChange := @RefreshResults;
  Lbl(Body, 'X marcado', 16, Y + 104, 120, 18);
  Lbl(Body, 'Y marcado', 146, Y + 104, 120, 18);
  MarkX := Spin(Body, 'ZeroMarkX', 16, Y + 124);
  MarkY := Spin(Body, 'ZeroMarkY', 146, Y + 124);
  BtnUseXY := Btn(Body, 'Usar posicao atual', 276, Y + 121, 260, sikTarget, @UseXYClick);
  BtnUseXY.Name := 'ZeroUseXY';
  XYResult := Lbl(Body, '', 16, Y + 160, 520, 40);
  XYResult.Font.Style := [fsBold];
  BtnApplyXY := Btn(Body, 'Aplicar zero X/Y', 16, Y + 204, 170, sikOrigin, @ApplyXYClick);
  BtnApplyXY.Name := 'ZeroApplyXY';
  BtnApplyXY.SetLook(sbsSolid, clSuitePrimary, sikOrigin);
  BtnShowZero := Btn(Body, 'Mostrar o zero', 194, Y + 204, 160, sikEye, @ShowZeroClick);
  BtnShowZero.Name := 'ZeroShow';
  BtnShowZero.Hint := 'Leva a fresa ate X0 Y0 na altura atual, para ver onde fica o zero no bloco';
  BtnShowZero.ShowHint := True;
  BtnBack := Btn(Body, 'Voltar ao ponto', 362, Y + 204, 174, sikArrowLeft, @BackClick);
  BtnBack.Name := 'ZeroBack';

  { 2. Z }
  Y := 456;
  Section(Body, '2  TOPO DO BLOCO (Z)', sikArrowDown, Y);
  Lbl(Body, 'Desca a fresa ate encostar no topo do bloco (use uma folha de papel) e marque.',
    16, Y + 28, 520, 40);
  Lbl(Body, 'Z ao encostar', 16, Y + 72, 120, 18);
  TouchZ := Spin(Body, 'ZeroTouchZ', 16, Y + 92);
  BtnUseZ := Btn(Body, 'Usar posicao atual', 146, Y + 89, 200, sikTarget, @UseZClick);
  BtnUseZ.Name := 'ZeroUseZ';
  BtnLift := Btn(Body, 'Subir 5 mm', 354, Y + 89, 182, sikArrowUp, @LiftClick);
  BtnLift.Name := 'ZeroLift';
  ZResult := Lbl(Body, '', 16, Y + 128, 520, 40);
  ZResult.Font.Style := [fsBold];
  BtnApplyZ := Btn(Body, 'Aplicar zero Z', 16, Y + 172, 170, sikOrigin, @ApplyZClick);
  BtnApplyZ.Name := 'ZeroApplyZ';
  BtnApplyZ.SetLook(sbsSolid, clSuitePrimary, sikOrigin);

  StateLabel := Lbl(Body, 'Depois das duas etapas, use Mostrar o zero e confira a aba Trajetoria e analise antes de cortar.',
    16, 680, 380, 50);
  StateLabel.Font.Color := clSuiteMuted;
  BtnClose := Btn(Body, 'Fechar', 416, 686, 120, sikClose, @CloseClick);

  FBuilding := False;
  Timer := TTimer.Create(Self);
  Timer.Interval := 250;
  Timer.OnTimer := @TimerTick;
  TimerTick(nil);
  UseXYClick(nil);
  UseZClick(nil);
end;

function TZeroAssistForm.Point: TBlockPoint;
begin
  Result := TBlockPoint(EnsureRange(PointBox.ItemIndex, 0, Ord(High(TBlockPoint))));
end;

function TZeroAssistForm.TopZ: Double;
begin
  Result := BlockTop(FBlock, Thickness.Value);
end;

function TZeroAssistForm.PlacedBlock: TBlockPlacement;
begin
  Result := FBlock;
  Result.Top := TopZ;
end;

function TZeroAssistForm.DepthOK(out Msg: string): Boolean;
var D, A: Double;
begin
  Result := CheckCutDepth(FBlock, Thickness.Value, Clearance.Value, D, A, Msg);
end;

procedure TZeroAssistForm.Say(const AText: string; AColor: TColor);
begin
  StateLabel.Caption := AText;
  StateLabel.Font.Color := AColor;
  if Assigned(FOnLog) then FOnLog('Zero pelo bloco: ' + AText);
end;

function TZeroAssistForm.Ready: Boolean;
begin
  Result := (FSession <> nil) and FSession.Connected and FSession.ControllerReady and
    not (FSession.State in [ssRunning, ssPaused]);
end;

procedure TZeroAssistForm.SendCmd(const ACmd: string);
begin
  FLastCommand := ACmd;
  if not FSession.Send(ACmd) then raise Exception.Create(FSession.LastError);
  if Assigned(FOnLog) then FOnLog('TX  ' + ACmd);
end;

procedure TZeroAssistForm.TimerTick(Sender: TObject);
var P: TMachinePosition; R, Deep: Boolean; Msg: string;
begin
  R := Ready;
  if R then
  begin
    P := FSession.Position;
    PosLabel.Caption := Format('Posicao atual: X %s  Y %s  Z %s', [FmtMM(P.X), FmtMM(P.Y), FmtMM(P.Z)]);
  end
  else
    PosLabel.Caption := 'Posicao atual: conecte a maquina';
  BtnUseXY.Enabled := R; BtnUseZ.Enabled := R;
  Deep := not DepthOK(Msg);
  BtnApplyXY.Enabled := R and FBlock.Valid and not Deep;
  BtnApplyZ.Enabled := R and FBlock.Valid and not Deep;
  BtnShowZero.Enabled := R and FXYApplied;
  BtnBack.Enabled := R and FXYApplied;
  BtnLift.Enabled := R;
end;

procedure TZeroAssistForm.RefreshResults(Sender: TObject);
var ZX, ZY, PX, PY: Double; Msg: string; OK: Boolean;
begin
  if FBuilding or not FBlock.Valid then Exit;
  OK := DepthOK(Msg);
  DepthResult.Caption := Msg;
  if not OK then DepthResult.Font.Color := clSuiteDanger
  else if Thickness.Value > 0 then DepthResult.Font.Color := clSuiteSuccess
  else DepthResult.Font.Color := clSuiteWarning;
  ZeroXYFromBlock(MarkX.Value, MarkY.Value, FBlock, Point, ZX, ZY);
  BlockPointInProgram(FBlock, Point, PX, PY);
  XYResult.Caption := Format('Ponto zero X/Y do G-code: X %s  Y %s  (coordenadas atuais). No programa, o %s e X %s Y %s.',
    [FmtMM(ZX), FmtMM(ZY), LowerCase(BLOCK_POINT_NAMES[Point]), FmtMM(PX), FmtMM(PY)]);
  ZResult.Caption := Format('Ponto zero Z do G-code: Z %s  (coordenadas atuais). %s.',
    [FmtMM(ZeroZFromTouch(TouchZ.Value, PlacedBlock)),
     IfThen(TopZ > 0, Format('Z0 na mesa, %s mm abaixo do topo', [FmtMM(TopZ)]), 'Z0 no topo do bloco')]);
end;

procedure TZeroAssistForm.UseXYClick(Sender: TObject);
var P: TMachinePosition;
begin
  if Ready then
  begin
    P := FSession.Position;
    MarkX.Value := P.X;
    MarkY.Value := P.Y;
  end;
  RefreshResults(nil);
end;

procedure TZeroAssistForm.UseZClick(Sender: TObject);
begin
  if Ready then TouchZ.Value := FSession.Position.Z;
  RefreshResults(nil);
end;

procedure TZeroAssistForm.ApplyXY;
var P: TMachinePosition; PX, PY: Double; Msg: string;
begin
  if not FBlock.Valid then raise Exception.Create('O programa nao tem movimento de corte.');
  if not DepthOK(Msg) then raise Exception.Create(Msg);
  if not Ready then raise Exception.Create('Conecte a maquina e aguarde a controladora.');
  P := FSession.Position;
  SendCmd(G92ForBlockXY(P.X, P.Y, MarkX.Value, MarkY.Value, FBlock, Point));
  FSession.Status;
  FXYApplied := True;
  BlockPointInProgram(FBlock, Point, PX, PY);
  Say(Format('zero X/Y aplicado: o %s agora e X %s Y %s do programa.',
    [LowerCase(BLOCK_POINT_NAMES[Point]), FmtMM(PX), FmtMM(PY)]), clSuiteSuccess);
  MarkX.Value := PX; MarkY.Value := PY;
  TimerTick(nil);
end;

procedure TZeroAssistForm.ApplyZ;
var P: TMachinePosition; Msg: string;
begin
  if not FBlock.Valid then raise Exception.Create('O programa nao tem movimento de corte.');
  if not DepthOK(Msg) then raise Exception.Create(Msg);
  if not Ready then raise Exception.Create('Conecte a maquina e aguarde a controladora.');
  P := FSession.Position;
  SendCmd(G92ForTop(P.Z, TouchZ.Value, PlacedBlock));
  FSession.Status;
  Say(Format('zero Z aplicado: o topo do bloco agora e Z %s. Suba a fresa antes de mover.', [FmtMM(TopZ)]),
    clSuiteSuccess);
  TouchZ.Value := TopZ;
end;

procedure TZeroAssistForm.ApplyXYClick(Sender: TObject);
begin
  try ApplyXY; except on E: Exception do Say(E.Message, clSuiteDanger); end;
end;

procedure TZeroAssistForm.ApplyZClick(Sender: TObject);
begin
  try ApplyZ; except on E: Exception do Say(E.Message, clSuiteDanger); end;
end;

procedure TZeroAssistForm.ShowZeroClick(Sender: TObject);
var P: TMachinePosition;
begin
  if not Ready then Exit;
  P := FSession.Position;
  { mesma altura: so desloca em X/Y ate o zero }
  if FSession.MoveTo(0, 0, P.Z, SAFE_FEED) then
    Say('fresa indo ao ponto zero X/Y (mesma altura).', clSuiteInfo)
  else
    Say(FSession.LastError, clSuiteDanger);
end;

procedure TZeroAssistForm.BackClick(Sender: TObject);
var P: TMachinePosition; PX, PY: Double;
begin
  if not Ready then Exit;
  P := FSession.Position;
  BlockPointInProgram(FBlock, Point, PX, PY);
  if FSession.MoveTo(PX, PY, P.Z, SAFE_FEED) then
    Say('fresa voltando ao ponto marcado do bloco (mesma altura).', clSuiteInfo)
  else
    Say(FSession.LastError, clSuiteDanger);
end;

procedure TZeroAssistForm.LiftClick(Sender: TObject);
var P: TMachinePosition;
begin
  if not Ready then Exit;
  P := FSession.Position;
  if not FSession.MoveTo(P.X, P.Y, P.Z + 5, SAFE_FEED) then Say(FSession.LastError, clSuiteDanger);
end;

procedure TZeroAssistForm.CloseClick(Sender: TObject);
begin
  Close;
end;

end.
