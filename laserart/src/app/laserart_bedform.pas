unit laserart_bedform;

{$mode objfpc}{$H+}
{$codepage utf8}

interface

uses Classes, SysUtils, Math, Forms, Controls, StdCtrls, ExtCtrls, Spin,
  multicnc_equipment, multicnc_types, multisuite_controls, multisuite_icons;

type
  TLaserBedForm = class(TForm)
  private
    Equipment: TComboBox;
    WidthField, HeightField, SField: TFloatSpinEdit;
    Info: TLabel;
    Profiles: TEquipmentProfiles;
    ManualW, ManualH: Double;
    procedure EquipmentChanged(Sender: TObject);
    procedure ApplyClick(Sender: TObject);
    procedure CancelClick(Sender: TObject);
    function Field(const AName, ACaption: string; X: Integer;
      AMax: Double): TFloatSpinEdit;
    function GetWidthMM: Double;
    function GetHeightMM: Double;
    function GetSMax: Double;
    function GetOpticalPowerW: Double;
  public
    constructor Create(AOwner: TComponent); override;
    procedure Configure(AWidth, AHeight, ASMax: Double; const AFileName: string = '');
    property WidthMM: Double read GetWidthMM;
    property HeightMM: Double read GetHeightMM;
    property SMax: Double read GetSMax;
    property OpticalPowerW: Double read GetOpticalPowerW;
  end;

implementation

function TLaserBedForm.Field(const AName, ACaption: string; X: Integer;
  AMax: Double): TFloatSpinEdit;
var L: TLabel;
begin
  L := TLabel.Create(Self); L.Parent := Self;
  L.Caption := ACaption; L.SetBounds(X, 148, 180, 20);
  L.Font.Color := clSuiteMuted;
  Result := TFloatSpinEdit.Create(Self); Result.Parent := Self;
  Result.Name := AName; Result.SetBounds(X, 174, 170, 28);
  Result.MinValue := 0.01; Result.MaxValue := AMax;
  Result.DecimalPlaces := 2;
end;

constructor TLaserBedForm.Create(AOwner: TComponent);
var H: TSuiteHeader; L: TLabel; Bottom: TPanel; B: TSuiteButton;
begin
  inherited CreateNew(AOwner);
  Caption := 'LaserArt - Mesa';
  Position := poOwnerFormCenter; BorderStyle := bsDialog;
  ClientWidth := 610; ClientHeight := 340;
  Font.Name := 'Segoe UI'; Font.Size := 9; Color := clSuiteSurface;
  H := TSuiteHeader.Create(Self); H.Parent := Self; H.Align := alTop; H.Height := 60;
  H.Setup('Mesa', 'Área de trabalho do laser', sikGear);
  L := TLabel.Create(Self); L.Parent := Self;
  L.Caption := 'Laser salvo no MultiCNC:'; L.SetBounds(20, 76, 560, 20);
  Equipment := TComboBox.Create(Self); Equipment.Parent := Self;
  Equipment.Name := 'BedEquipment'; Equipment.SetBounds(20, 102, 570, 30);
  Equipment.Style := csDropDownList; Equipment.OnChange := @EquipmentChanged;
  WidthField := Field('BedWidth', 'Largura X (mm)', 20, 100000);
  HeightField := Field('BedHeight', 'Altura Y (mm)', 220, 100000);
  SField := Field('BedSMax', 'S máximo GRBL ($30)', 420, 100000);
  Info := TLabel.Create(Self); Info.Parent := Self; Info.Name := 'BedEquipmentInfo';
  Info.AutoSize := False; Info.WordWrap := True;
  Info.SetBounds(20, 218, 570, 60); Info.Font.Color := clSuiteMuted;
  Bottom := TPanel.Create(Self); Bottom.Parent := Self; Bottom.Align := alBottom;
  Bottom.Height := 55; Bottom.BevelOuter := bvNone; Bottom.Color := clSuiteCard;
  B := TSuiteButton.Create(Self); B.Parent := Bottom; B.Name := 'ApplyBed';
  B.SetBounds(350, 10, 115, 34); B.Caption := 'Aplicar';
  B.SetLook(sbsSolid, clSuitePrimary, sikSave); B.OnClick := @ApplyClick;
  B := TSuiteButton.Create(Self); B.Parent := Bottom; B.Name := 'CancelBed';
  B.SetBounds(475, 10, 115, 34); B.Caption := 'Cancelar';
  B.SetLook(sbsOutline, clSuiteMuted, sikClose); B.OnClick := @CancelClick;
end;

procedure TLaserBedForm.Configure(AWidth, AHeight, ASMax: Double; const AFileName: string);
var Store: TEquipmentStore; P: TEquipmentProfile; FN: string; I, N: Integer;
begin
  ManualW := AWidth; ManualH := AHeight;
  WidthField.Value := AWidth; HeightField.Value := AHeight; SField.Value := ASMax;
  SetLength(Profiles, 0);
  Equipment.Items.Clear; Equipment.Items.Add('Ajuste manual');
  Equipment.ItemIndex := 0;
  FN := AFileName; if FN = '' then FN := EquipmentFileName;
  Store := TEquipmentStore.Create(FN);
  try
    try
      Store.Load;
      for I := 0 to Store.Count - 1 do
      begin
        P := Store.Item(I);
        if (P.MachineType <> mtLaser) or (P.WorkX <= 0) or (P.WorkY <= 0) then Continue;
        N := Length(Profiles); SetLength(Profiles, N + 1); Profiles[N] := P;
        Equipment.Items.Add(P.Name);
      end;
      if Length(Profiles) = 0 then
        Info.Caption := 'Nenhum laser com área válida salvo no MultiCNC. Cadastre e salve seu laser no MultiCNC ou ajuste a mesa manualmente.'
      else Info.Caption := 'Selecione um laser para carregar sua área X/Y. O S máximo não consta no cadastro: confirme o valor de $30 na controladora.';
    except
      on E: Exception do
      begin
        SetLength(Profiles, 0);
        Equipment.Items.Clear; Equipment.Items.Add('Ajuste manual'); Equipment.ItemIndex := 0;
        Info.Caption := Format('Não foi possível ler o cadastro do MultiCNC. Ajuste manual disponível. %s', [E.Message]);
      end;
    end;
  finally Store.Free; end;
end;

procedure TLaserBedForm.EquipmentChanged(Sender: TObject);
var I: Integer; P: TEquipmentProfile;
begin
  I := Equipment.ItemIndex - 1;
  if (I >= 0) and (I < Length(Profiles)) then
  begin
    P := Profiles[I];
    WidthField.Value := P.WorkX; HeightField.Value := P.WorkY;
    Info.Caption := Format('Área carregada de %s. Clique em Aplicar para ajustar a mesa do desenho. S máximo permanece como informado.', [P.Name]);
  end
  else
  begin
    WidthField.Value := ManualW; HeightField.Value := ManualH;
    Info.Caption := 'Ajuste manual da mesa. Confirme o S máximo conforme $30 da controladora.';
  end;
end;

procedure TLaserBedForm.CancelClick(Sender: TObject);
begin ModalResult := mrCancel; end;

procedure TLaserBedForm.ApplyClick(Sender: TObject);
  function Valid(V: Double): Boolean;
  begin Result := not IsNan(V) and not IsInfinite(V) and (V > 0); end;
begin
  if not Valid(WidthMM) or not Valid(HeightMM) or not Valid(SMax) then
  begin Info.Caption := 'Informe dimensões e S máximo maiores que zero.'; Exit; end;
  ModalResult := mrOK;
end;

function TLaserBedForm.GetOpticalPowerW: Double;
var I: Integer;
begin
  I:=Equipment.ItemIndex-1; Result:=0;
  if (I>=0) and (I<Length(Profiles)) then Result:=Profiles[I].LaserOpticalPowerW;
end;

function TLaserBedForm.GetWidthMM: Double;
begin Result := WidthField.Value; end;
function TLaserBedForm.GetHeightMM: Double;
begin Result := HeightField.Value; end;
function TLaserBedForm.GetSMax: Double;
begin Result := SField.Value; end;
end.
