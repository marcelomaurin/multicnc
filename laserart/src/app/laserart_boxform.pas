unit laserart_boxform;

{ Janela "Caixa com encaixes": medidas, material, dente, kerf e tampa. A
  geometria fica em laserart_box; aqui so os campos e o resumo ao vivo. }

{$mode objfpc}{$H+}

interface

uses Classes, SysUtils, Math, Forms, Controls, StdCtrls, ExtCtrls, Spin,
  multisuite_controls, multisuite_icons, laserart_box;

type
  TLaserBoxForm = class(TForm)
  private
    WidthField, DepthField, HeightField, ThickField, FingerField, KerfField: TFloatSpinEdit;
    InnerRadio, OuterRadio: TRadioButton;
    LidCheck: TCheckBox;
    Info: TLabel;
    function Field(const AName, ACaption: string; X, Y: Integer;
      AMin, AMax: Double; ADecimals: Integer): TFloatSpinEdit;
    procedure FieldChange(Sender: TObject);
    procedure ApplyClick(Sender: TObject);
    procedure CancelClick(Sender: TObject);
    function GetParams: TLABoxParams;
  public
    constructor Create(AOwner: TComponent); override;
    procedure Configure(const P: TLABoxParams);
    property Params: TLABoxParams read GetParams;
  end;

implementation

function TLaserBoxForm.Field(const AName, ACaption: string; X, Y: Integer;
  AMin, AMax: Double; ADecimals: Integer): TFloatSpinEdit;
var L: TLabel;
begin
  L := TLabel.Create(Self); L.Parent := Self;
  L.Caption := ACaption; L.SetBounds(X, Y, 180, 20);
  L.Font.Color := clSuiteMuted;
  Result := TFloatSpinEdit.Create(Self); Result.Parent := Self;
  Result.Name := AName; Result.SetBounds(X, Y + 22, 170, 28);
  Result.MinValue := AMin; Result.MaxValue := AMax;
  Result.DecimalPlaces := ADecimals;
  Result.Increment := IfThen(ADecimals > 1, 0.05, 1);
  Result.OnChange := @FieldChange;
end;

constructor TLaserBoxForm.Create(AOwner: TComponent);
var H: TSuiteHeader; L: TLabel; Bottom: TPanel; B: TSuiteButton;
begin
  inherited CreateNew(AOwner);
  Caption := 'LaserArt - Caixa com encaixes';
  Position := poOwnerFormCenter; BorderStyle := bsDialog;
  ClientWidth := 610; ClientHeight := 440;
  Font.Name := 'Segoe UI'; Font.Size := 9; Color := clSuiteSurface;
  H := TSuiteHeader.Create(Self); H.Parent := Self; H.Align := alTop; H.Height := 60;
  H.Setup('Caixa com encaixes', 'Faces com dentes (finger joint) prontas para cortar', sikRect);

  L := TLabel.Create(Self); L.Parent := Self;
  L.Caption := 'Medidas:'; L.SetBounds(20, 78, 70, 20);
  InnerRadio := TRadioButton.Create(Self); InnerRadio.Parent := Self;
  InnerRadio.Name := 'BoxInner'; InnerRadio.Caption := 'Internas (espaco util)';
  InnerRadio.SetBounds(90, 76, 170, 22); InnerRadio.Checked := True;
  InnerRadio.OnClick := @FieldChange;
  OuterRadio := TRadioButton.Create(Self); OuterRadio.Parent := Self;
  OuterRadio.Name := 'BoxOuter'; OuterRadio.Caption := 'Externas';
  OuterRadio.SetBounds(270, 76, 120, 22); OuterRadio.OnClick := @FieldChange;

  WidthField := Field('BoxWidth', 'Largura (mm)', 20, 108, 1, 5000, 2);
  DepthField := Field('BoxDepth', 'Profundidade (mm)', 220, 108, 1, 5000, 2);
  HeightField := Field('BoxHeight', 'Altura (mm)', 420, 108, 1, 5000, 2);
  ThickField := Field('BoxThickness', 'Espessura do material (mm)', 20, 172, 0.1, 100, 2);
  FingerField := Field('BoxFinger', 'Largura do dente (mm)', 220, 172, 0.5, 1000, 2);
  KerfField := Field('BoxKerf', 'Kerf - largura do corte (mm)', 420, 172, 0, 5, 3);

  LidCheck := TCheckBox.Create(Self); LidCheck.Parent := Self;
  LidCheck.Name := 'BoxLid'; LidCheck.Caption := 'Com tampa (6 faces; sem tampa sao 5)';
  LidCheck.SetBounds(20, 238, 400, 22); LidCheck.OnClick := @FieldChange;

  Info := TLabel.Create(Self); Info.Parent := Self; Info.Name := 'BoxInfo';
  Info.AutoSize := False; Info.WordWrap := True;
  Info.SetBounds(20, 270, 570, 100); Info.Font.Color := clSuiteMuted;

  Bottom := TPanel.Create(Self); Bottom.Parent := Self; Bottom.Align := alBottom;
  Bottom.Height := 55; Bottom.BevelOuter := bvNone; Bottom.Color := clSuiteCard;
  B := TSuiteButton.Create(Self); B.Parent := Bottom; B.Name := 'ApplyBox';
  B.SetBounds(350, 10, 115, 34); B.Caption := 'Gerar';
  B.SetLook(sbsSolid, clSuitePrimary, sikSave); B.OnClick := @ApplyClick;
  B := TSuiteButton.Create(Self); B.Parent := Bottom; B.Name := 'CancelBox';
  B.SetBounds(475, 10, 115, 34); B.Caption := 'Cancelar';
  B.SetLook(sbsOutline, clSuiteMuted, sikClose); B.OnClick := @CancelClick;

  Configure(DefaultBoxParams);
end;

procedure TLaserBoxForm.Configure(const P: TLABoxParams);
begin
  WidthField.Value := P.Width; DepthField.Value := P.Depth; HeightField.Value := P.Height;
  ThickField.Value := P.Thickness; FingerField.Value := P.Finger; KerfField.Value := P.Kerf;
  InnerRadio.Checked := P.Inner; OuterRadio.Checked := not P.Inner;
  LidCheck.Checked := P.Lid;
  FieldChange(nil);
end;

function TLaserBoxForm.GetParams: TLABoxParams;
begin
  Result.Width := WidthField.Value;
  Result.Depth := DepthField.Value;
  Result.Height := HeightField.Value;
  Result.Inner := InnerRadio.Checked;
  Result.Thickness := ThickField.Value;
  Result.Finger := FingerField.Value;
  Result.Kerf := KerfField.Value;
  Result.Lid := LidCheck.Checked;
end;

procedure TLaserBoxForm.FieldChange(Sender: TObject);
var P: TLABoxParams; Err: string; W, D, H: Double;
begin
  if Info = nil then Exit;
  P := Params;
  if not ValidateBox(P, Err) then begin Info.Caption := Err; Exit; end;
  BoxOuterSize(P, W, D, H);
  Info.Caption := Format('Externa %.1f x %.1f x %.1f mm. Dentes: %d na largura, %d na profundidade, ' +
    '%d na altura (numero impar de segmentos, ajustado a medida). O kerf alarga os dentes e ' +
    'estreita as fendas em %.3f mm. As faces vao lado a lado na camada atual, em modo Linha.',
    [W, D, H, BoxSegments(W, P.Finger, P.Thickness), BoxSegments(D, P.Finger, P.Thickness),
     BoxSegments(H, P.Finger, P.Thickness), P.Kerf]);
end;

procedure TLaserBoxForm.CancelClick(Sender: TObject);
begin ModalResult := mrCancel; end;

procedure TLaserBoxForm.ApplyClick(Sender: TObject);
var Err: string;
begin
  if not ValidateBox(Params, Err) then begin Info.Caption := Err; Exit; end;
  ModalResult := mrOK;
end;

end.
