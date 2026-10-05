unit simu_table_config_form;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, Spin, Graphics;

type
  TTableConfigForm = class(TForm)
  private
    HeaderPanel: TPanel;
    TitleLabel: TLabel;
    SubTitleLabel: TLabel;
    ContentPanel: TPanel;
    PresetCombo: TComboBox;
    PresetLabel: TLabel;
    SpinX, SpinY, SpinZ: TFloatSpinEdit;
    LabelX, LabelY, LabelZ: TLabel;
    UnitX, UnitY, UnitZ: TLabel;
    BottomPanel: TPanel;
    BtnOK, BtnCancel: TButton;
    FUpdatingPreset: Boolean;
    procedure PresetChanged(Sender: TObject);
    procedure SpinChanged(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    class function Execute(var AX, AY, AZ: Double): Boolean;
  end;

implementation

constructor TTableConfigForm.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner);
  Caption := 'Configuracao da Mesa de Trabalho';
  Position := poScreenCenter;
  BorderStyle := bsDialog;
  ClientWidth := 430;
  ClientHeight := 310;
  KeyPreview := True;

  // Painel de cabecalho
  HeaderPanel := TPanel.Create(Self);
  HeaderPanel.Parent := Self;
  HeaderPanel.Align := alTop;
  HeaderPanel.Height := 58;
  HeaderPanel.BevelOuter := bvNone;
  HeaderPanel.Color := $00F5F5F5;

  TitleLabel := TLabel.Create(Self);
  TitleLabel.Parent := HeaderPanel;
  TitleLabel.Caption := 'Dimensoes da Area Util (Mesa)';
  TitleLabel.Font.Style := [fsBold];
  TitleLabel.Font.Size := 10;
  TitleLabel.SetBounds(20, 10, 390, 20);

  SubTitleLabel := TLabel.Create(Self);
  SubTitleLabel.Parent := HeaderPanel;
  SubTitleLabel.Caption := 'Defina os limites de movimento para os eixos X, Y e Z.';
  SubTitleLabel.Font.Color := clGrayText;
  SubTitleLabel.SetBounds(20, 32, 390, 18);

  // Painel central de conteudo
  ContentPanel := TPanel.Create(Self);
  ContentPanel.Parent := Self;
  ContentPanel.Align := alClient;
  ContentPanel.BevelOuter := bvNone;

  PresetLabel := TLabel.Create(Self);
  PresetLabel.Parent := ContentPanel;
  PresetLabel.Caption := 'Predefinicao rapida:';
  PresetLabel.SetBounds(20, 16, 130, 20);

  PresetCombo := TComboBox.Create(Self);
  PresetCombo.Parent := ContentPanel;
  PresetCombo.Style := csDropDownList;
  PresetCombo.SetBounds(160, 13, 240, 26);
  PresetCombo.Items.Add('Personalizado');
  PresetCombo.Items.Add('Impressora 3D Padrao (200 x 200 x 200 mm)');
  PresetCombo.Items.Add('Impressora 3D Media (300 x 300 x 400 mm)');
  PresetCombo.Items.Add('CNC Router 3018 (300 x 180 x 45 mm)');
  PresetCombo.Items.Add('Gravadora Laser 4040 (400 x 400 x 50 mm)');
  PresetCombo.Items.Add('CNC Router Grande (1000 x 1000 x 100 mm)');
  PresetCombo.ItemIndex := 0;
  PresetCombo.OnChange := @PresetChanged;

  // Eixo X
  LabelX := TLabel.Create(Self);
  LabelX.Parent := ContentPanel;
  LabelX.Caption := 'Eixo X (Largura):';
  LabelX.SetBounds(20, 56, 130, 20);

  SpinX := TFloatSpinEdit.Create(Self);
  SpinX.Parent := ContentPanel;
  SpinX.MinValue := 10.0;
  SpinX.MaxValue := 2000.0;
  SpinX.DecimalPlaces := 1;
  SpinX.Increment := 10.0;
  SpinX.SetBounds(160, 52, 190, 26);
  SpinX.OnChange := @SpinChanged;

  UnitX := TLabel.Create(Self);
  UnitX.Parent := ContentPanel;
  UnitX.Caption := 'mm';
  UnitX.SetBounds(358, 56, 40, 20);

  // Eixo Y
  LabelY := TLabel.Create(Self);
  LabelY.Parent := ContentPanel;
  LabelY.Caption := 'Eixo Y (Profundidade):';
  LabelY.SetBounds(20, 94, 130, 20);

  SpinY := TFloatSpinEdit.Create(Self);
  SpinY.Parent := ContentPanel;
  SpinY.MinValue := 10.0;
  SpinY.MaxValue := 2000.0;
  SpinY.DecimalPlaces := 1;
  SpinY.Increment := 10.0;
  SpinY.SetBounds(160, 90, 190, 26);
  SpinY.OnChange := @SpinChanged;

  UnitY := TLabel.Create(Self);
  UnitY.Parent := ContentPanel;
  UnitY.Caption := 'mm';
  UnitY.SetBounds(358, 94, 40, 20);

  // Eixo Z
  LabelZ := TLabel.Create(Self);
  LabelZ.Parent := ContentPanel;
  LabelZ.Caption := 'Eixo Z (Altura):';
  LabelZ.SetBounds(20, 132, 130, 20);

  SpinZ := TFloatSpinEdit.Create(Self);
  SpinZ.Parent := ContentPanel;
  SpinZ.MinValue := 10.0;
  SpinZ.MaxValue := 2000.0;
  SpinZ.DecimalPlaces := 1;
  SpinZ.Increment := 10.0;
  SpinZ.SetBounds(160, 128, 190, 26);
  SpinZ.OnChange := @SpinChanged;

  UnitZ := TLabel.Create(Self);
  UnitZ.Parent := ContentPanel;
  UnitZ.Caption := 'mm';
  UnitZ.SetBounds(358, 132, 40, 20);

  // Rodape com botoes
  BottomPanel := TPanel.Create(Self);
  BottomPanel.Parent := Self;
  BottomPanel.Align := alBottom;
  BottomPanel.Height := 50;
  BottomPanel.BevelOuter := bvNone;

  BtnOK := TButton.Create(Self);
  BtnOK.Parent := BottomPanel;
  BtnOK.Caption := 'Confirmar';
  BtnOK.ModalResult := mrOk;
  BtnOK.Default := True;
  BtnOK.SetBounds(210, 8, 95, 32);

  BtnCancel := TButton.Create(Self);
  BtnCancel.Parent := BottomPanel;
  BtnCancel.Caption := 'Cancelar';
  BtnCancel.ModalResult := mrCancel;
  BtnCancel.Cancel := True;
  BtnCancel.SetBounds(315, 8, 85, 32);
end;

procedure TTableConfigForm.PresetChanged(Sender: TObject);
begin
  if FUpdatingPreset then Exit;
  FUpdatingPreset := True;
  try
    case PresetCombo.ItemIndex of
      1: begin SpinX.Value := 200; SpinY.Value := 200; SpinZ.Value := 200; end;
      2: begin SpinX.Value := 300; SpinY.Value := 300; SpinZ.Value := 400; end;
      3: begin SpinX.Value := 300; SpinY.Value := 180; SpinZ.Value := 45; end;
      4: begin SpinX.Value := 400; SpinY.Value := 400; SpinZ.Value := 50; end;
      5: begin SpinX.Value := 1000; SpinY.Value := 1000; SpinZ.Value := 100; end;
    end;
  finally
    FUpdatingPreset := False;
  end;
end;

procedure TTableConfigForm.SpinChanged(Sender: TObject);
begin
  if FUpdatingPreset then Exit;
  FUpdatingPreset := True;
  try
    if (Abs(SpinX.Value - 200) < 0.1) and (Abs(SpinY.Value - 200) < 0.1) and (Abs(SpinZ.Value - 200) < 0.1) then
      PresetCombo.ItemIndex := 1
    else if (Abs(SpinX.Value - 300) < 0.1) and (Abs(SpinY.Value - 300) < 0.1) and (Abs(SpinZ.Value - 400) < 0.1) then
      PresetCombo.ItemIndex := 2
    else if (Abs(SpinX.Value - 300) < 0.1) and (Abs(SpinY.Value - 180) < 0.1) and (Abs(SpinZ.Value - 45) < 0.1) then
      PresetCombo.ItemIndex := 3
    else if (Abs(SpinX.Value - 400) < 0.1) and (Abs(SpinY.Value - 400) < 0.1) and (Abs(SpinZ.Value - 50) < 0.1) then
      PresetCombo.ItemIndex := 4
    else if (Abs(SpinX.Value - 1000) < 0.1) and (Abs(SpinY.Value - 1000) < 0.1) and (Abs(SpinZ.Value - 100) < 0.1) then
      PresetCombo.ItemIndex := 5
    else
      PresetCombo.ItemIndex := 0;
  finally
    FUpdatingPreset := False;
  end;
end;

class function TTableConfigForm.Execute(var AX, AY, AZ: Double): Boolean;
var
  Dlg: TTableConfigForm;
begin
  Dlg := TTableConfigForm.Create(nil);
  try
    Dlg.SpinX.Value := AX;
    Dlg.SpinY.Value := AY;
    Dlg.SpinZ.Value := AZ;
    Dlg.SpinChanged(nil);
    Result := (Dlg.ShowModal = mrOk);
    if Result then
    begin
      AX := Dlg.SpinX.Value;
      AY := Dlg.SpinY.Value;
      AZ := Dlg.SpinZ.Value;
    end;
  finally
    Dlg.Free;
  end;
end;

end.
