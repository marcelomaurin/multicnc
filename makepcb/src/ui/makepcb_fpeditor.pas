unit makepcb_fpeditor;

{ Editor de componentes (footprints) do MakePCB.

  Monta um footprint pad a pad (ou por fileiras, como num DIL/SIL), com
  prevea ao vivo nas vistas Normal e Mundo real. Furo 0 = pad SMD.
  "Gerar contorno" cria a serigrafia e o corpo em volta dos pads.
  O resultado vai para a biblioteca do usuario ("Meus componentes"),
  salva em JSON na pasta de configuracao, e embutida em cada .mpcb que
  usar o componente. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, StdCtrls, ExtCtrls, Grids, Dialogs,
  Graphics, makepcb_model, makepcb_render, multisuite_controls, multisuite_icons;

type
  TMPFootprintEditor = class(TForm)
  private
    FFP: TMPFootprint;
    FRender: TMPRenderer;
    Preview: TPaintBox;
    NameEdit, PrefixEdit, ValueEdit, DescEdit: TEdit;
    BodyBox: TComboBox;
    Grid: TStringGrid;
    Info: TLabel;
    RealWorld: TCheckBox;
    FUpdating: Boolean;
    FooterPanel: TPanel;
    SaveButton, CancelButton: TSuiteButton;
    procedure FormResized(Sender: TObject);
    function Button(AParent: TWinControl; const AText: string; X, Y, W: Integer;
      AIcon: TSuiteIconKind; Handler: TNotifyEvent): TSuiteButton;
    function Field(AParent: TWinControl; const AText: string; X, Y, W: Integer): TEdit;
    procedure LoadGrid;
    function ReadGrid(out Err: string): Boolean;
    procedure GridChanged(Sender: TObject);
    procedure PreviewPaint(Sender: TObject);
    procedure AddPadClick(Sender: TObject);
    procedure AddRowClick(Sender: TObject);
    procedure RemovePadClick(Sender: TObject);
    procedure OutlineClick(Sender: TObject);
    procedure SaveClick(Sender: TObject);
    procedure CancelClick(Sender: TObject);
    procedure ViewChanged(Sender: TObject);
  public
    constructor CreateFor(AOwner: TComponent; Template: TMPFootprint);
    destructor Destroy; override;
    { devolve o footprint editado (o chamador passa a ser o dono) ou nil }
    function Execute: TMPFootprint;
    property Footprint: TMPFootprint read FFP;
  end;

{ contorno retangular + marca do pino 1 + corpo em volta dos pads }
procedure MPAutoOutline(FP: TMPFootprint);

implementation

uses multisuite_numfmt, makepcb_library;

const
  SHAPE_NAMES: array[TMPPadShape] of string = ('Redondo', 'Quadrado', 'Oblongo');
  BODY_NAMES: array[TMPBodyKind] of string = ('Nenhum', 'Resistor', 'Capacitor ceramico',
    'Capacitor poliester', 'Eletrolitico', 'Diodo', 'LED', 'Transistor', 'Potencia (TO-220)',
    'Circuito integrado', 'Barra de pinos', 'Borne', 'Potenciometro', 'Cristal', 'Chave',
    'Buzzer', 'LDR', 'Pad', 'Chip SMD');

function FmtNum(V: Double): string;
var
  FS: TFormatSettings;
begin
  FS := DefaultFormatSettings;
  FS.DecimalSeparator := ',';
  Result := FormatFloat('0.###', V, FS);
end;

procedure MPAutoOutline(FP: TMPFootprint);
var
  I: Integer;
  MinX, MinY, MaxX, MaxY, M: Double;
begin
  if Length(FP.Pads) = 0 then Exit;
  MinX := 1e9; MinY := 1e9; MaxX := -1e9; MaxY := -1e9;
  for I := 0 to High(FP.Pads) do
  begin
    MinX := Min(MinX, FP.Pads[I].X - FP.Pads[I].W / 2);
    MaxX := Max(MaxX, FP.Pads[I].X + FP.Pads[I].W / 2);
    MinY := Min(MinY, FP.Pads[I].Y - FP.Pads[I].H / 2);
    MaxY := Max(MaxY, FP.Pads[I].Y + FP.Pads[I].H / 2);
  end;
  M := 0.4;
  SetLength(FP.Silk, 0);
  FP.AddRect(MinX - M, MinY - M, MaxX + M, MaxY + M);
  { pino 1: ponto fora do contorno, no canto mais proximo }
  if FP.Pads[0].X <= (MinX + MaxX) / 2 then
    FP.AddCircle(MinX - M - 0.6, FP.Pads[0].Y, 0.3)
  else
    FP.AddCircle(MaxX + M + 0.6, FP.Pads[0].Y, 0.3);
  if FP.Body = bkNone then FP.Body := bkIC;
  FP.BodyX1 := MinX - M; FP.BodyY1 := MinY - M; FP.BodyX2 := MaxX + M; FP.BodyY2 := MaxY + M;
end;

{ ---------------- formulario ---------------- }

function TMPFootprintEditor.Button(AParent: TWinControl; const AText: string;
  X, Y, W: Integer; AIcon: TSuiteIconKind; Handler: TNotifyEvent): TSuiteButton;
begin
  Result := TSuiteButton.Create(Self);
  Result.Parent := AParent;
  Result.SetBounds(X, Y, W, 34);
  Result.Caption := AText;
  Result.SetLook(sbsSoft, clSuitePrimary, AIcon);
  Result.OnClick := Handler;
end;

function TMPFootprintEditor.Field(AParent: TWinControl; const AText: string; X, Y, W: Integer): TEdit;
var
  L: TLabel;
begin
  L := TLabel.Create(Self);
  L.Parent := AParent; L.SetBounds(X, Y, W, 18); L.Caption := AText; L.Font.Color := clSuiteMuted;
  Result := TEdit.Create(Self);
  Result.Parent := AParent; Result.SetBounds(X, Y + 20, W, 28);
  Result.OnChange := @GridChanged;
end;

constructor TMPFootprintEditor.CreateFor(AOwner: TComponent; Template: TMPFootprint);
var
  Header: TSuiteHeader;
  Right, Footer: TPanel;
  K: TMPBodyKind;
  L: TLabel;
  B: TSuiteButton;
begin
  inherited CreateNew(AOwner, 1);
  Caption := 'Editor de componentes • MakePCB';
  Width := 1060; Height := 720; Position := poOwnerFormCenter;
  Font.Name := SUITE_FONT; Font.Size := 10; Color := clSuiteSurface;
  FRender := TMPRenderer.Create;
  FFP := TMPFootprint.Create;
  if Template <> nil then
  begin
    FFP.Assign(Template);
    if not Template.UserDefined then
    begin
      FFP.Name := Template.Name + ' (meu)';
      FFP.Category := MP_USER_CATEGORY;
    end;
  end
  else
  begin
    FFP.Name := 'Novo componente';
    FFP.Category := MP_USER_CATEGORY;
    FFP.RefPrefix := 'U';
    FFP.AddPad('1', -1.27, 0, psSquare, 1.8, 1.8, 0.8);
    FFP.AddPad('2', 1.27, 0, psRound, 1.8, 1.8, 0.8);
    MPAutoOutline(FFP);
  end;
  FFP.UserDefined := True;

  Header := TSuiteHeader.Create(Self);
  Header.Parent := Self; Header.Align := alTop; Header.Height := 64;
  Header.Setup('Editor de componentes', 'Pads, contorno e corpo  /  Meus componentes', sikPen);

  Footer := TPanel.Create(Self);
  Footer.Parent := Self; Footer.Align := alBottom; Footer.Height := 60;
  Footer.BevelOuter := bvNone; Footer.Color := clSuiteCard;
  Info := TLabel.Create(Self);
  Info.Parent := Footer; Info.SetBounds(18, 12, 560, 40); Info.WordWrap := True;
  Info.Font.Color := clSuiteMuted;
  CancelButton := Button(Footer, 'Cancelar', 0, 13, 150, sikClose, @CancelClick);
  SaveButton := Button(Footer, 'Salvar na biblioteca', 0, 13, 190, sikSave, @SaveClick);
  SaveButton.SetLook(sbsSolid, clSuitePrimary, sikSave);
  FooterPanel := Footer;
  OnResize := @FormResized;

  Right := TPanel.Create(Self);
  Right.Parent := Self; Right.Align := alRight; Right.Width := 560;
  Right.BevelOuter := bvNone; Right.Color := clSuiteCard;
  NameEdit := Field(Right, 'Nome', 16, 12, 330);
  PrefixEdit := Field(Right, 'Prefixo', 360, 12, 80);
  ValueEdit := Field(Right, 'Valor padrao', 452, 12, 92);
  DescEdit := Field(Right, 'Descricao', 16, 66, 330);
  L := TLabel.Create(Self);
  L.Parent := Right; L.SetBounds(360, 66, 184, 18); L.Caption := 'Corpo (mundo real)'; L.Font.Color := clSuiteMuted;
  BodyBox := TComboBox.Create(Self);
  BodyBox.Parent := Right; BodyBox.SetBounds(360, 86, 184, 30); BodyBox.Style := csDropDownList;
  for K := Low(TMPBodyKind) to High(TMPBodyKind) do BodyBox.Items.Add(BODY_NAMES[K]);
  BodyBox.OnChange := @GridChanged;
  L := TLabel.Create(Self);
  L.Parent := Right; L.SetBounds(16, 126, 528, 18);
  L.Caption := 'PADS  (mm; furo 0 = SMD; forma: Redondo, Quadrado ou Oblongo)';
  L.Font.Style := [fsBold];
  Grid := TStringGrid.Create(Self);
  Grid.Parent := Right; Grid.SetBounds(12, 148, 536, 330);
  Grid.ColCount := 7; Grid.FixedCols := 0; Grid.RowCount := 2;
  Grid.Options := Grid.Options + [goEditing, goTabs] - [goRangeSelect];
  Grid.Cells[0, 0] := 'Pino'; Grid.Cells[1, 0] := 'X'; Grid.Cells[2, 0] := 'Y';
  Grid.Cells[3, 0] := 'Forma'; Grid.Cells[4, 0] := 'Largura'; Grid.Cells[5, 0] := 'Altura';
  Grid.Cells[6, 0] := 'Furo';
  Grid.ColWidths[0] := 56; Grid.ColWidths[1] := 70; Grid.ColWidths[2] := 70;
  Grid.ColWidths[3] := 92; Grid.ColWidths[4] := 70; Grid.ColWidths[5] := 70; Grid.ColWidths[6] := 70;
  Grid.OnEditingDone := @GridChanged;
  Button(Right, 'Adicionar pad', 16, 488, 168, sikNew, @AddPadClick);
  Button(Right, 'Adicionar fileira', 194, 488, 168, sikLayers, @AddRowClick);
  Button(Right, 'Remover pad', 372, 488, 172, sikTrash, @RemovePadClick);
  Button(Right, 'Gerar contorno e corpo', 16, 530, 346, sikRect, @OutlineClick);
  RealWorld := TCheckBox.Create(Self);
  RealWorld.Parent := Right; RealWorld.SetBounds(372, 536, 172, 24);
  RealWorld.Caption := 'Ver mundo real'; RealWorld.OnChange := @ViewChanged;
  L := TLabel.Create(Self);
  L.Parent := Right; L.AutoSize := False; L.SetBounds(16, 574, 528, 44); L.WordWrap := True; L.Font.Color := clSuiteMuted;
  L.Caption := 'O pino 1 fica quadrado por convencao. Para a isolacao a laser, use pads de 1,8 mm ou mais nos furados e pelo menos 0,6 mm de largura nos SMD.';

  Preview := TPaintBox.Create(Self);
  Preview.Parent := Self; Preview.Align := alClient;
  Preview.OnPaint := @PreviewPaint;

  FUpdating := True;
  try
    NameEdit.Text := FFP.Name;
    PrefixEdit.Text := FFP.RefPrefix;
    ValueEdit.Text := FFP.DefaultValue;
    DescEdit.Text := FFP.Description;
    BodyBox.ItemIndex := Ord(FFP.Body);
    LoadGrid;
  finally
    FUpdating := False;
  end;
  GridChanged(nil);
  FormResized(nil);
end;

procedure TMPFootprintEditor.FormResized(Sender: TObject);
begin
  if FooterPanel = nil then Exit;
  SaveButton.Left := FooterPanel.ClientWidth - SaveButton.Width - 18;
  CancelButton.Left := SaveButton.Left - CancelButton.Width - 10;
  Info.Width := Max(100, CancelButton.Left - 30);
end;

destructor TMPFootprintEditor.Destroy;
begin
  FFP.Free;
  FRender.Free;
  inherited Destroy;
end;

procedure TMPFootprintEditor.LoadGrid;
var
  I: Integer;
begin
  Grid.RowCount := Max(2, Length(FFP.Pads) + 1);
  if Length(FFP.Pads) = 0 then Grid.Rows[1].Clear;
  for I := 0 to High(FFP.Pads) do
    with FFP.Pads[I] do
    begin
      Grid.Cells[0, I + 1] := Name;
      Grid.Cells[1, I + 1] := FmtNum(X);
      Grid.Cells[2, I + 1] := FmtNum(Y);
      Grid.Cells[3, I + 1] := SHAPE_NAMES[Shape];
      Grid.Cells[4, I + 1] := FmtNum(W);
      Grid.Cells[5, I + 1] := FmtNum(H);
      Grid.Cells[6, I + 1] := FmtNum(Drill);
    end;
end;

function TMPFootprintEditor.ReadGrid(out Err: string): Boolean;
var
  R: Integer;
  X, Y, W, H, D: Double;
  S: TMPPadShape;
  ShapeText: string;
  Pads: array of TMPPadDef;
  P: ^TMPPadDef;

  function Num(Col: Integer; out V: Double): Boolean;
  begin
    Result := TryParseFloat(Trim(Grid.Cells[Col, R]), V);
    if not Result then Err := Format('Linha %d: "%s" nao e numero', [R, Grid.Cells[Col, R]]);
  end;

begin
  Err := '';
  Result := False;
  SetLength(Pads, 0);
  for R := 1 to Grid.RowCount - 1 do
  begin
    if Trim(Grid.Cells[0, R] + Grid.Cells[1, R] + Grid.Cells[2, R]) = '' then Continue;
    if not (Num(1, X) and Num(2, Y) and Num(4, W) and Num(5, H) and Num(6, D)) then Exit;
    ShapeText := LowerCase(Trim(Grid.Cells[3, R]));
    if Pos('q', ShapeText) = 1 then S := psSquare
    else if Pos('o', ShapeText) = 1 then S := psOblong
    else S := psRound;
    if (W < 0.2) or (H < 0.2) or (W > 20) or (H > 20) then
    begin
      Err := Format('Linha %d: pad entre 0,2 e 20 mm', [R]);
      Exit;
    end;
    if (D < 0) or ((D > 0) and (D > Min(W, H) - 0.2) and not ((D >= Min(W, H) - 1e-9) and (S = psRound))) then
    begin
      Err := Format('Linha %d: o furo precisa ser menor que o pad (ou igual, para furo sem cobre)', [R]);
      Exit;
    end;
    SetLength(Pads, Length(Pads) + 1);
    P := @Pads[High(Pads)];
    P^.Name := Trim(Grid.Cells[0, R]);
    if P^.Name = '' then P^.Name := IntToStr(Length(Pads));
    P^.X := X; P^.Y := Y;
    P^.Shape := S;
    P^.W := W; P^.H := H;
    P^.Drill := D;
    { furo do tamanho do pad: furo de fixacao, sem cobre }
    P^.Plated := not ((D > 0) and (D >= Min(W, H) - 1e-9));
  end;
  if Length(Pads) = 0 then
  begin
    Err := 'O componente precisa de pelo menos um pad';
    Exit;
  end;
  FFP.Pads := Pads;
  Result := True;
end;

procedure TMPFootprintEditor.GridChanged(Sender: TObject);
var
  Err: string;
  Smd, Thru, I: Integer;
begin
  if FUpdating then Exit;
  FFP.Name := Trim(NameEdit.Text);
  FFP.RefPrefix := UpperCase(Trim(PrefixEdit.Text));
  FFP.DefaultValue := Trim(ValueEdit.Text);
  FFP.Description := Trim(DescEdit.Text);
  if BodyBox.ItemIndex >= 0 then FFP.Body := TMPBodyKind(BodyBox.ItemIndex);
  if ReadGrid(Err) then
  begin
    Smd := 0; Thru := 0;
    for I := 0 to High(FFP.Pads) do
      if FFP.Pads[I].Drill > 0 then Inc(Thru) else Inc(Smd);
    Info.Font.Color := clSuiteMuted;
    Info.Caption := Format('%d pads: %d furados, %d SMD.', [Length(FFP.Pads), Thru, Smd]);
  end
  else
  begin
    Info.Font.Color := clSuiteDanger;
    Info.Caption := Err;
  end;
  Preview.Invalidate;
end;

procedure TMPFootprintEditor.PreviewPaint(Sender: TObject);
var
  M: TMPViewMode;
begin
  if RealWorld.Checked then M := vmRealWorld else M := vmNormal;
  Preview.Canvas.Brush.Color := TColor($FBF8F6);
  Preview.Canvas.FillRect(0, 0, Preview.Width, Preview.Height);
  if Length(FFP.Pads) > 0 then
    FRender.PaintFootprint(Preview.Canvas, FFP, Rect(20, 20, Preview.Width - 20, Preview.Height - 20), M, 60);
end;

procedure TMPFootprintEditor.ViewChanged(Sender: TObject);
begin
  Preview.Invalidate;
end;

procedure TMPFootprintEditor.AddPadClick(Sender: TObject);
var
  R: Integer;
  X: Double;
begin
  R := Grid.RowCount;
  if (R = 2) and (Trim(Grid.Cells[0, 1]) = '') then R := 1
  else Grid.RowCount := R + 1;
  X := 0;
  if Length(FFP.Pads) > 0 then X := FFP.Pads[High(FFP.Pads)].X + 2.54;
  Grid.Cells[0, R] := IntToStr(R);
  Grid.Cells[1, R] := FmtNum(X);
  Grid.Cells[2, R] := '0';
  Grid.Cells[3, R] := 'Redondo';
  Grid.Cells[4, R] := '1,8';
  Grid.Cells[5, R] := '1,8';
  Grid.Cells[6, R] := '0,8';
  Grid.Row := R;
  GridChanged(nil);
end;

procedure TMPFootprintEditor.AddRowClick(Sender: TObject);
var
  S: string;
  Parts: TStringList;
  N, I, R, First: Integer;
  Pitch, X0, Y0, W, H, D: Double;
begin
  S := '8;2,54;0;0;1,8;1,8;0,8';
  if not InputQuery('Adicionar fileira',
    'Quantidade; passo (mm); X inicial; Y; largura; altura; furo (0 = SMD):', S) then Exit;
  Parts := TStringList.Create;
  try
    Parts.Delimiter := ';'; Parts.StrictDelimiter := True;
    Parts.DelimitedText := S;
    if (Parts.Count < 7) or not TryStrToInt(Trim(Parts[0]), N) or (N < 1) or (N > 100) or
       not TryParseFloat(Parts[1], Pitch) or not TryParseFloat(Parts[2], X0) or
       not TryParseFloat(Parts[3], Y0) or not TryParseFloat(Parts[4], W) or
       not TryParseFloat(Parts[5], H) or not TryParseFloat(Parts[6], D) then
    begin
      MessageDlg('Editor de componentes', 'Informe 7 valores separados por ";" (ex.: 8;2,54;0;0;1,8;1,8;0,8).',
        mtError, [mbOK], 0);
      Exit;
    end;
    First := Length(FFP.Pads) + 1;
    R := Grid.RowCount;
    if (Length(FFP.Pads) = 0) then R := 1;
    Grid.RowCount := R + N;
    for I := 0 to N - 1 do
    begin
      Grid.Cells[0, R + I] := IntToStr(First + I);
      Grid.Cells[1, R + I] := FmtNum(X0 + I * Pitch);
      Grid.Cells[2, R + I] := FmtNum(Y0);
      if First + I = 1 then Grid.Cells[3, R + I] := 'Quadrado'
      else if D > 0 then Grid.Cells[3, R + I] := 'Redondo'
      else Grid.Cells[3, R + I] := 'Quadrado';
      Grid.Cells[4, R + I] := FmtNum(W);
      Grid.Cells[5, R + I] := FmtNum(H);
      Grid.Cells[6, R + I] := FmtNum(D);
    end;
  finally
    Parts.Free;
  end;
  GridChanged(nil);
end;

procedure TMPFootprintEditor.RemovePadClick(Sender: TObject);
begin
  if Grid.RowCount <= 2 then
  begin
    Grid.Rows[1].Clear;
    GridChanged(nil);
    Exit;
  end;
  if Grid.Row >= 1 then Grid.DeleteRow(Grid.Row);
  GridChanged(nil);
end;

procedure TMPFootprintEditor.OutlineClick(Sender: TObject);
var
  Err: string;
begin
  if not ReadGrid(Err) then
  begin
    MessageDlg('Editor de componentes', Err, mtError, [mbOK], 0);
    Exit;
  end;
  if FFP.Body = bkNone then
  begin
    if FFP.HasSMD and (Length(FFP.Pads) = 2) then FFP.Body := bkChip else FFP.Body := bkIC;
    BodyBox.ItemIndex := Ord(FFP.Body);
  end;
  MPAutoOutline(FFP);
  Preview.Invalidate;
end;

procedure TMPFootprintEditor.SaveClick(Sender: TObject);
var
  Err: string;
  Lib: TMPLibrary;
  Existing: TMPFootprint;
begin
  GridChanged(nil);
  if not ReadGrid(Err) then
  begin
    MessageDlg('Editor de componentes', Err, mtError, [mbOK], 0);
    Exit;
  end;
  if FFP.Name = '' then
  begin
    MessageDlg('Editor de componentes', 'Informe o nome do componente.', mtError, [mbOK], 0);
    NameEdit.SetFocus;
    Exit;
  end;
  Lib := MakePCBLibrary;
  Existing := Lib.Find(FFP.Name);
  if (Existing <> nil) and not Existing.UserDefined then
  begin
    MessageDlg('Editor de componentes', 'Ja existe um componente da biblioteca com esse nome. Escolha outro.',
      mtError, [mbOK], 0);
    NameEdit.SetFocus;
    Exit;
  end;
  if FFP.RefPrefix = '' then FFP.RefPrefix := 'U';
  if Length(FFP.Silk) = 0 then MPAutoOutline(FFP);
  ModalResult := mrOk;
end;

procedure TMPFootprintEditor.CancelClick(Sender: TObject);
begin
  ModalResult := mrCancel;
end;

function TMPFootprintEditor.Execute: TMPFootprint;
begin
  Result := nil;
  if ShowModal = mrOk then
  begin
    Result := FFP;
    FFP := TMPFootprint.Create;   { o chamador fica com o editado }
  end;
end;

end.
