unit multicad_materialdlg;

{ MultiCAD - escolha do material (como "Editar material" do SolidWorks).

  Lista por categoria (Metais, Plasticos, Madeiras, Outros), amostra com a
  textura do material numa esfera iluminada, propriedades (densidade,
  modulo de elasticidade, Poisson) e, para os plasticos de impressao 3D
  (PLA, ABS, PETG...), a escolha da cor. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls, Graphics,
  Dialogs, multicad_types, multicad_materials, multicad_textures;

{ AMaterial/AColor entram com o atual e saem com o escolhido. AColor = -1:
  cor padrao do material. }
function CadChooseMaterial(AOwner: TComponent; var AMaterial: string;
  var AColor: Integer): Boolean;

{ Cria a janela sem mostrar (testes e capturas). }
function CadMaterialDialog(AOwner: TComponent; const AMaterial: string; AColor: Integer): TForm;

{ Desenha a amostra (esfera com a textura) num bitmap. }
procedure CadDrawMaterialSwatch(B: TBitmap; ASize: Integer; AColor: LongWord; ATexture: Integer);

implementation

const
  SWATCH_COLORS: array[0..11] of LongWord = ($F2F2F2, $1E1E20, $8C9096, $D22828,
    $E8742A, $F0C81E, $2E9E4A, $2A64C8, $7A3EB4, $E87AA8, $D9C9A0, $4A8C8C);
  SWATCH_NAMES: array[0..11] of string = ('Branco', 'Preto', 'Cinza', 'Vermelho',
    'Laranja', 'Amarelo', 'Verde', 'Azul', 'Roxo', 'Rosa', 'Natural', 'Turquesa');

type
  TMatForm = class(TForm)
  public
    Tree: TTreeView;
    Swatch: TImage;
    Info: TLabel;
    ColorBox: TGroupBox;
    Chips: array[0..11] of TPanel;
    OtherBtn: TButton;
    DefaultBtn: TButton;
    Mat: string;
    Col: Integer;
    procedure Build;
    procedure Refresh;
    procedure TreeChange(Sender: TObject; Node: TTreeNode);
    procedure ChipClick(Sender: TObject);
    procedure OtherClick(Sender: TObject);
    procedure DefaultClick(Sender: TObject);
    function Current(out M: TCadMaterial): Boolean;
  end;

function ToTColor(C: LongWord): TColor;
begin
  Result := RGBToColor((C shr 16) and $FF, (C shr 8) and $FF, C and $FF);
end;

function FromTColor(C: TColor): LongWord;
var
  R: LongInt;
begin
  R := ColorToRGB(C);
  Result := (LongWord(Red(R)) shl 16) or (LongWord(Green(R)) shl 8) or Blue(R);
end;

procedure CadDrawMaterialSwatch(B: TBitmap; ASize: Integer; AColor: LongWord; ATexture: Integer);
var
  X, Y: Integer;
  NX, NY, NZ, R2, L, F, Sp, S: Double;
  CR, CG, CB: Integer;
  Bg: TColor;
begin
  B.SetSize(ASize, ASize);
  Bg := RGBToColor(236, 240, 246);
  B.Canvas.Brush.Color := Bg;
  B.Canvas.FillRect(0, 0, ASize, ASize);
  S := ASize / 2 - 4;
  for Y := 0 to ASize - 1 do
    for X := 0 to ASize - 1 do
    begin
      NX := (X - ASize / 2) / S;
      NY := -(Y - ASize / 2) / S;
      R2 := NX * NX + NY * NY;
      if R2 > 1 then
        Continue;
      NZ := Sqrt(1 - R2);
      { luz de cima e da esquerda + brilho }
      L := 0.28 + 0.55 * Max(0, NX * -0.4 + NY * 0.6 + NZ * 0.7) + 0.25 * NZ;
      Sp := Power(Max(0, NX * -0.25 + NY * 0.35 + NZ * 0.9), 40) * 0.35;
      F := CadTexFactor(ATexture, V3(NX * 20, NY * 20, NZ * 20), V3(0, 0, 1));
      CR := EnsureRange(Round(((AColor shr 16) and $FF) * L * F + 255 * Sp), 0, 255);
      CG := EnsureRange(Round(((AColor shr 8) and $FF) * L * F + 255 * Sp), 0, 255);
      CB := EnsureRange(Round((AColor and $FF) * L * F + 255 * Sp), 0, 255);
      B.Canvas.Pixels[X, Y] := RGBToColor(CR, CG, CB);
    end;
end;

procedure TMatForm.Build;
var
  Cats: TStringList;
  I, K: Integer;
  M: TCadMaterial;
  Root, N: TTreeNode;
  Ok, Cancel: TButton;
  Lb: TLabel;
begin
  Caption := 'Material';
  Width := 620;
  Height := 440;
  Position := poOwnerFormCenter;
  BorderStyle := bsDialog;
  Tree := TTreeView.Create(Self);
  Tree.Parent := Self;
  Tree.SetBounds(10, 10, 240, 380);
  Tree.ReadOnly := True;
  Tree.HideSelection := False;
  Cats := TStringList.Create;
  try
    for I := 0 to CadMaterialCount - 1 do
      if Cats.IndexOf(CadMaterial(I).Category) < 0 then
        Cats.Add(CadMaterial(I).Category);
    for K := 0 to Cats.Count - 1 do
    begin
      Root := Tree.Items.Add(nil, Cats[K]);
      for I := 0 to CadMaterialCount - 1 do
      begin
        M := CadMaterial(I);
        if M.Category <> Cats[K] then
          Continue;
        N := Tree.Items.AddChild(Root, M.Name);
        if SameText(M.Name, Mat) then
          N.Selected := True;
      end;
      Root.Expand(False);
    end;
  finally
    Cats.Free;
  end;
  Tree.OnChange := @TreeChange;

  Swatch := TImage.Create(Self);
  Swatch.Parent := Self;
  Swatch.SetBounds(262, 10, 140, 140);
  Info := TLabel.Create(Self);
  Info.Parent := Self;
  Info.SetBounds(414, 14, 196, 136);
  Info.AutoSize := False;
  Info.WordWrap := True;

  ColorBox := TGroupBox.Create(Self);
  ColorBox.Parent := Self;
  ColorBox.SetBounds(262, 160, 348, 190);
  ColorBox.Caption := 'Cor (plásticos de impressão 3D)';
  for I := 0 to 11 do
  begin
    Chips[I] := TPanel.Create(Self);
    Chips[I].Parent := ColorBox;
    Chips[I].SetBounds(10 + (I mod 6) * 54, 8 + (I div 6) * 54, 46, 30);
    Chips[I].BevelOuter := bvLowered;
    Chips[I].Color := ToTColor(SWATCH_COLORS[I]);
    Chips[I].ParentBackground := False;
    Chips[I].Tag := I;
    Chips[I].Hint := SWATCH_NAMES[I];
    Chips[I].ShowHint := True;
    Chips[I].Cursor := crHandPoint;
    Chips[I].OnClick := @ChipClick;
    Lb := TLabel.Create(Self);
    Lb.Parent := ColorBox;
    Lb.SetBounds(10 + (I mod 6) * 54, 40 + (I div 6) * 54, 50, 14);
    Lb.Font.Height := -10;
    Lb.Caption := SWATCH_NAMES[I];
  end;
  OtherBtn := TButton.Create(Self);
  OtherBtn.Parent := ColorBox;
  OtherBtn.SetBounds(10, 122, 150, 30);
  OtherBtn.Caption := 'Outra cor...';
  OtherBtn.OnClick := @OtherClick;
  DefaultBtn := TButton.Create(Self);
  DefaultBtn.Parent := ColorBox;
  DefaultBtn.SetBounds(170, 122, 160, 30);
  DefaultBtn.Caption := 'Cor padrão';
  DefaultBtn.OnClick := @DefaultClick;

  Ok := TButton.Create(Self);
  Ok.Parent := Self;
  Ok.SetBounds(430, 362, 86, 30);
  Ok.Caption := 'Aplicar';
  Ok.Default := True;
  Ok.ModalResult := mrOK;
  Cancel := TButton.Create(Self);
  Cancel.Parent := Self;
  Cancel.SetBounds(524, 362, 86, 30);
  Cancel.Caption := 'Cancelar';
  Cancel.Cancel := True;
  Cancel.ModalResult := mrCancel;
  Refresh;
end;

function TMatForm.Current(out M: TCadMaterial): Boolean;
begin
  Result := CadFindMaterial(Mat, M);
end;

procedure TMatForm.Refresh;
var
  M: TCadMaterial;
  B: TBitmap;
  C: LongWord;
  I: Integer;
begin
  if not Current(M) then
  begin
    Info.Caption := 'Escolha um material na lista.';
    Exit;
  end;
  if M.ColorChoice and (Col >= 0) then
    C := LongWord(Col)
  else
    C := M.Color;
  B := TBitmap.Create;
  try
    CadDrawMaterialSwatch(B, 140, C, CadTextureIndex(M.Texture));
    Swatch.Picture.Assign(B);
  finally
    B.Free;
  end;
  Info.Caption := M.Name + LineEnding + LineEnding +
    'Densidade: ' + FormatFloat('0', M.Density) + ' kg/m³' + LineEnding +
    'Módulo de elasticidade: ' + FormatFloat('0.###', M.EModulus) + ' GPa' + LineEnding +
    'Poisson: ' + FormatFloat('0.00', M.Poisson) + LineEnding + LineEnding +
    'Categoria: ' + M.Category;
  ColorBox.Enabled := M.ColorChoice;
  for I := 0 to 11 do
  begin
    Chips[I].Enabled := M.ColorChoice;
    if M.ColorChoice and (Col >= 0) and (LongWord(Col) = SWATCH_COLORS[I]) then
      Chips[I].BevelOuter := bvRaised
    else
      Chips[I].BevelOuter := bvLowered;
  end;
  OtherBtn.Enabled := M.ColorChoice;
  DefaultBtn.Enabled := M.ColorChoice;
end;

procedure TMatForm.TreeChange(Sender: TObject; Node: TTreeNode);
begin
  if (Node = nil) or (Node.Parent = nil) then
    Exit;
  if not SameText(Mat, Node.Text) then
    Col := -1;
  Mat := Node.Text;
  Refresh;
end;

procedure TMatForm.ChipClick(Sender: TObject);
begin
  Col := Integer(SWATCH_COLORS[TComponent(Sender).Tag]);
  Refresh;
end;

procedure TMatForm.OtherClick(Sender: TObject);
var
  D: TColorDialog;
  M: TCadMaterial;
begin
  D := TColorDialog.Create(Self);
  try
    if Col >= 0 then
      D.Color := ToTColor(LongWord(Col))
    else if Current(M) then
      D.Color := ToTColor(M.Color);
    if D.Execute then
    begin
      Col := Integer(FromTColor(D.Color));
      Refresh;
    end;
  finally
    D.Free;
  end;
end;

procedure TMatForm.DefaultClick(Sender: TObject);
begin
  Col := -1;
  Refresh;
end;

function CadMaterialDialog(AOwner: TComponent; const AMaterial: string; AColor: Integer): TForm;
var
  F: TMatForm;
begin
  F := TMatForm.CreateNew(AOwner);
  F.Mat := AMaterial;
  F.Col := AColor;
  F.Build;
  Result := F;
end;

function CadChooseMaterial(AOwner: TComponent; var AMaterial: string;
  var AColor: Integer): Boolean;
var
  F: TMatForm;
begin
  F := TMatForm.CreateNew(AOwner);
  try
    F.Mat := AMaterial;
    F.Col := AColor;
    F.Build;
    Result := (F.ShowModal = mrOK) and (CadMaterialIndex(F.Mat) >= 0);
    if Result then
    begin
      AMaterial := F.Mat;
      AColor := F.Col;
    end;
  finally
    F.Free;
  end;
end;

end.
