unit laserart_calibrationform;

{ Teste de material do LaserArt: matriz de quadrados variando a potencia
  (colunas) e a velocidade (linhas). Grave a matriz no material, escolha o
  melhor quadrado e salve os valores como material na aba Materiais.

  Usa TLaserCalibration.BuildMatrix e TLACalibJob (laserart_calibration).
  Potencia em valor S (0..S max do GRBL). }

{$mode objfpc}{$H+}

interface

uses
  multisuite_numfmt, Classes, SysUtils, Math, Forms, Controls, StdCtrls, ExtCtrls,
  Dialogs, Graphics, Spin, laserart_calibration,
  multisuite_icons, multisuite_controls;

type
  TLaserCalibrationForm = class(TForm)
  private
    EPowerMin, EPowerMax, EFeedMin, EFeedMax, EX0, EY0, ECell: TFloatSpinEdit;
    ECols, ERows: TSpinEdit;
    Preview: TPaintBox;
    Log: TLabel;
    J: TLACalibJob;
    function Field(AParent: TWinControl; const ACaption: string; X, Y: Integer;
      AMin, AMax, AValue: Double; ADec: Integer): TFloatSpinEdit;
    function Valid(out Msg: string): Boolean;
    procedure ParamChange(Sender: TObject);
    procedure PreviewPaint(Sender: TObject);
    procedure ExportClick(Sender: TObject);
    procedure CloseClick(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  end;

implementation

function TLaserCalibrationForm.Field(AParent: TWinControl; const ACaption: string;
  X, Y: Integer; AMin, AMax, AValue: Double; ADec: Integer): TFloatSpinEdit;
var
  L: TLabel;
begin
  L := TLabel.Create(Self);
  L.Parent := AParent;
  L.Caption := ACaption;
  L.SetBounds(X, Y, 160, 18);
  L.Font.Color := clSuiteMuted;
  Result := TFloatSpinEdit.Create(Self);
  Result.Parent := AParent;
  Result.SetBounds(X, Y + 18, 150, 26);
  Result.MinValue := AMin;
  Result.MaxValue := AMax;
  Result.DecimalPlaces := ADec;
  Result.Value := AValue;
  Result.OnChange := @ParamChange;
end;

constructor TLaserCalibrationForm.Create(AOwner: TComponent);
var
  H: TSuiteHeader;
  LeftP, Bottom: TPanel;
  ST: TSuiteSectionTitle;
  L: TLabel;
  B: TSuiteButton;
begin
  inherited CreateNew(AOwner);
  Caption := 'LaserArt - Teste de material';
  Position := poOwnerFormCenter;
  BorderStyle := bsDialog;
  ClientWidth := 900;
  ClientHeight := 600;
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  Color := clSuiteSurface;
  J := TLACalibJob.Create;

  H := TSuiteHeader.Create(Self);
  H.Parent := Self;
  H.Align := alTop;
  H.Height := 60;
  H.Setup('Teste de material', 'Matriz de potencia (colunas) x velocidade (linhas)', sikGauge);

  Bottom := TPanel.Create(Self);
  Bottom.Parent := Self;
  Bottom.Align := alBottom;
  Bottom.Height := 56;
  Bottom.BevelOuter := bvNone;
  Bottom.Color := clSuiteCard;
  B := TSuiteButton.Create(Self);
  B.Parent := Bottom;
  B.SetBounds(ClientWidth - 340, 11, 200, 34);
  B.Caption := 'Exportar G-code';
  B.SetLook(sbsSolid, clSuitePrimary, sikSave);
  B.OnClick := @ExportClick;
  B := TSuiteButton.Create(Self);
  B.Parent := Bottom;
  B.SetBounds(ClientWidth - 130, 11, 116, 34);
  B.Caption := 'Fechar';
  B.SetLook(sbsOutline, clSuiteMuted, sikClose);
  B.OnClick := @CloseClick;
  Log := TLabel.Create(Self);
  Log.Parent := Bottom;
  Log.SetBounds(16, 10, ClientWidth - 380, 40);
  Log.AutoSize := False;
  Log.WordWrap := True;
  Log.Font.Color := clSuiteMuted;

  LeftP := TPanel.Create(Self);
  LeftP.Parent := Self;
  LeftP.Align := alLeft;
  LeftP.Width := 360;
  LeftP.BevelOuter := bvNone;
  LeftP.Color := clSuiteCard;

  ST := TSuiteSectionTitle.CreateTitle(Self, 'POTENCIA (S)', sikFlame, clSuiteDanger);
  ST.Parent := LeftP; ST.SetBounds(16, 12, 300, 22);
  EPowerMin := Field(LeftP, 'Minima', 16, 38, 1, 100000, 100, 0);
  EPowerMax := Field(LeftP, 'Maxima', 186, 38, 1, 100000, 1000, 0);
  ST := TSuiteSectionTitle.CreateTitle(Self, 'VELOCIDADE (mm/min)', sikGauge, clSuitePrimary);
  ST.Parent := LeftP; ST.SetBounds(16, 96, 300, 22);
  EFeedMin := Field(LeftP, 'Minima', 16, 122, 1, 100000, 300, 0);
  EFeedMax := Field(LeftP, 'Maxima', 186, 122, 1, 100000, 3000, 0);
  ST := TSuiteSectionTitle.CreateTitle(Self, 'MATRIZ', sikLayers, clSuiteSuccess);
  ST.Parent := LeftP; ST.SetBounds(16, 180, 300, 22);
  L := TLabel.Create(Self); L.Parent := LeftP; L.Caption := 'Colunas'; L.SetBounds(16, 206, 100, 18);
  L.Font.Color := clSuiteMuted;
  ECols := TSpinEdit.Create(Self); ECols.Parent := LeftP; ECols.SetBounds(16, 224, 150, 26);
  ECols.MinValue := 2; ECols.MaxValue := 20; ECols.Value := 5; ECols.OnChange := @ParamChange;
  L := TLabel.Create(Self); L.Parent := LeftP; L.Caption := 'Linhas'; L.SetBounds(186, 206, 100, 18);
  L.Font.Color := clSuiteMuted;
  ERows := TSpinEdit.Create(Self); ERows.Parent := LeftP; ERows.SetBounds(186, 224, 150, 26);
  ERows.MinValue := 2; ERows.MaxValue := 20; ERows.Value := 5; ERows.OnChange := @ParamChange;
  ECell := Field(LeftP, 'Celula (mm)', 16, 260, 3, 100, 12, 1);
  EX0 := Field(LeftP, 'Inicio X (mm)', 16, 318, 0, 2000, 10, 1);
  EY0 := Field(LeftP, 'Inicio Y (mm)', 186, 318, 0, 2000, 10, 1);
  L := TLabel.Create(Self);
  L.Parent := LeftP;
  L.SetBounds(16, 382, 330, 120);
  L.AutoSize := False;
  L.WordWrap := True;
  L.Font.Color := clSuiteMuted;
  L.Caption := 'Comece com potencias baixas e aumente aos poucos. Use valores seguros para sua maquina ' +
    'e para o material. Grave, escolha o quadrado com o melhor resultado e salve a velocidade e a ' +
    'potencia correspondentes como material.';

  Preview := TPaintBox.Create(Self);
  Preview.Parent := Self;
  Preview.Align := alClient;
  Preview.BorderSpacing.Around := 12;
  Preview.OnPaint := @PreviewPaint;
  ParamChange(nil);
end;

destructor TLaserCalibrationForm.Destroy;
begin
  J.Free;
  inherited Destroy;
end;

function TLaserCalibrationForm.Valid(out Msg: string): Boolean;
begin
  Msg := '';
  if EPowerMax.Value < EPowerMin.Value then Msg := 'Potencia maxima menor que a minima.'
  else if EFeedMax.Value < EFeedMin.Value then Msg := 'Velocidade maxima menor que a minima.';
  Result := Msg = '';
end;

procedure TLaserCalibrationForm.ParamChange(Sender: TObject);
var
  Msg: string;
begin
  if (EPowerMin = nil) or (ERows = nil) or (EY0 = nil) then Exit;
  J.Clear;
  if Valid(Msg) then
  begin
    TLaserCalibration.BuildMatrix(J, EX0.Value, EY0.Value, ECell.Value, ECell.Value,
      EPowerMin.Value, EPowerMax.Value, EFeedMin.Value, EFeedMax.Value, ECols.Value, ERows.Value);
    Log.Font.Color := clSuiteMuted;
    Log.Caption := Format('Matriz %d x %d - area %.0f x %.0f mm a partir de (%.0f, %.0f) - %d movimentos.',
      [ECols.Value, ERows.Value, ECols.Value * ECell.Value, ERows.Value * ECell.Value,
       EX0.Value, EY0.Value, J.Count], InvariantFS);
  end
  else
  begin
    Log.Font.Color := clSuiteDanger;
    Log.Caption := Msg;
  end;
  if Preview <> nil then Preview.Invalidate;
end;

procedure TLaserCalibrationForm.PreviewPaint(Sender: TObject);
var
  C: TCanvas;
  Cols, Rows, X, Y, CW, CH, OX, OY: Integer;
  P, F, T: Double;
  R: TRect;
  S: string;
begin
  C := Preview.Canvas;
  C.Brush.Color := clWhite;
  C.FillRect(0, 0, Preview.Width, Preview.Height);
  Cols := ECols.Value;
  Rows := ERows.Value;
  OX := 70; OY := 36;
  CW := Max(10, (Preview.Width - OX - 16) div Cols);
  CH := Max(10, (Preview.Height - OY - 16) div Rows);
  CW := Min(CW, CH);
  CH := CW;
  C.Font.Size := 8;
  C.Font.Color := clSuiteMuted;
  C.Brush.Style := bsClear;
  C.TextOut(OX, 6, 'potencia S  >');
  C.TextOut(4, OY - 18, 'mm/min');
  for X := 0 to Cols - 1 do
  begin
    P := EPowerMin.Value + (EPowerMax.Value - EPowerMin.Value) * X / Max(1, Cols - 1);
    S := Format('%.0f', [P]);
    C.TextOut(OX + X * CW + (CW - C.TextWidth(S)) div 2, OY - 16, S);
  end;
  for Y := 0 to Rows - 1 do
  begin
    { a 1a linha (Y0) fica embaixo na mesa }
    F := EFeedMin.Value + (EFeedMax.Value - EFeedMin.Value) * (Rows - 1 - Y) / Max(1, Rows - 1);
    S := Format('%.0f', [F]);
    C.TextOut(OX - 8 - C.TextWidth(S), OY + Y * CH + (CH - C.TextHeight(S)) div 2, S);
  end;
  for Y := 0 to Rows - 1 do
    for X := 0 to Cols - 1 do
    begin
      { intensidade estimada: potencia alta e velocidade baixa = mais escuro }
      T := EnsureRange((X / Max(1, Cols - 1)) * 0.7 + (1 - (Rows - 1 - Y) / Max(1, Rows - 1)) * 0.3, 0, 1);
      R := Rect(OX + X * CW + 3, OY + Y * CH + 3, OX + (X + 1) * CW - 3, OY + (Y + 1) * CH - 3);
      C.Brush.Style := bsSolid;
      C.Brush.Color := RGBToColor(Round(232 - 190 * T), Round(198 - 170 * T), Round(150 - 135 * T));
      C.Pen.Color := RGBToColor(120, 80, 40);
      C.Rectangle(R);
    end;
end;

procedure TLaserCalibrationForm.ExportClick(Sender: TObject);
var
  D: TSaveDialog;
  Msg: string;
begin
  if not Valid(Msg) or (J.Count = 0) then
  begin
    MessageDlg('Teste de material', 'Ajuste os parametros: ' + Msg, mtWarning, [mbOK], 0);
    Exit;
  end;
  D := TSaveDialog.Create(Self);
  try
    D.Title := 'Exportar teste de material';
    D.Filter := 'G-code|*.gcode';
    D.DefaultExt := 'gcode';
    D.FileName := 'teste_material.gcode';
    D.Options := [ofOverwritePrompt, ofPathMustExist, ofEnableSizing];
    if D.Execute then
    begin
      J.SaveGCode(D.FileName);
      Log.Font.Color := clSuiteSuccess;
      Log.Caption := 'Arquivo gerado: ' + D.FileName + '. Revise limites e area util antes de executar no MultiCNC.';
    end;
  finally
    D.Free;
  end;
end;

procedure TLaserCalibrationForm.CloseClick(Sender: TObject);
begin
  ModalResult := mrClose;
end;

end.
