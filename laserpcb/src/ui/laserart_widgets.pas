unit laserart_widgets;

{ Componentes do painel do LaserArt:

  TLALayerList    - lista de camadas em uso (estilo "Cuts / Layers"):
                    cor/numero, modo, velocidade/potencia, Saida e Mostrar.
  TLAOriginPicker - origem do trabalho em 9 pontos (3 x 3).
  TLAPalette      - paleta de 30 cores de camada (rodape). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Types, Controls, Graphics, LCLType, multisuite_numfmt,
  laserart_model;

type
  TLALayerEvent = procedure(Sender: TObject; Layer: Integer) of object;

  TLALayerList = class(TCustomControl)
  private
    FDoc: TLADocument;
    FSelected: Integer;
    FHover: Integer;
    FScroll: Integer;
    FOnSelect, FOnToggle: TLALayerEvent;
    function RowAt(Y: Integer): Integer;
    function VisibleRows: Integer;
    procedure ClampScroll;
    function ColOutput: Integer;
    function ColShow: Integer;
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure EnsureVisible(Layer: Integer);
    property Document: TLADocument read FDoc write FDoc;
    property SelectedLayer: Integer read FSelected write FSelected;
    property OnSelectLayer: TLALayerEvent read FOnSelect write FOnSelect;
    property OnToggle: TLALayerEvent read FOnToggle write FOnToggle;
  end;

  TLAOriginPicker = class(TCustomControl)
  private
    FValue: Integer;
    FOnChange: TNotifyEvent;
    procedure SetValue(V: Integer);
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    property Value: Integer read FValue write SetValue;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;

  TLAPalette = class(TCustomControl)
  private
    FCurrent: Integer;
    FOnPick: TLALayerEvent;
    function CellRect(I: Integer): TRect;
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    property Current: Integer read FCurrent write FCurrent;
    property OnPick: TLALayerEvent read FOnPick write FOnPick;
  end;

function ContrastText(C: TColor): TColor;

implementation

const
  ROW_H = 28;
  HEAD_H = 24;

function ContrastText(C: TColor): TColor;
var
  X: TColor;
begin
  X := ColorToRGB(C);
  if 0.299 * Red(X) + 0.587 * Green(X) + 0.114 * Blue(X) > 150 then
    Result := RGBToColor(15, 23, 42)
  else
    Result := clWhite;
end;

procedure DrawToggle(C: TCanvas; X, Y: Integer; On: Boolean);
begin
  C.Pen.Style := psClear;
  if On then
    C.Brush.Color := RGBToColor(34, 197, 94)
  else
    C.Brush.Color := RGBToColor(203, 213, 225);
  C.RoundRect(X, Y, X + 30, Y + 16, 16, 16);
  C.Brush.Color := clWhite;
  if On then
    C.Ellipse(X + 16, Y + 2, X + 28, Y + 14)
  else
    C.Ellipse(X + 2, Y + 2, X + 14, Y + 14);
  C.Pen.Style := psSolid;
end;

{ ---------------------------------------------------------------------------- }

constructor TLALayerList.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FSelected := -1;
  FHover := -1;
  DoubleBuffered := True;
  Color := clWhite;
end;

function TLALayerList.ColOutput: Integer;
begin
  Result := ClientWidth - 98;
end;

function TLALayerList.ColShow: Integer;
begin
  Result := ClientWidth - 52;
end;

function TLALayerList.VisibleRows: Integer;
begin
  Result := Max(1, (ClientHeight - HEAD_H) div ROW_H);
end;

procedure TLALayerList.ClampScroll;
begin
  if FDoc = nil then
    FScroll := 0
  else
    FScroll := EnsureRange(FScroll, 0, Max(0, Length(FDoc.LayerOrder) - VisibleRows));
end;

procedure TLALayerList.EnsureVisible(Layer: Integer);
var
  I: Integer;
begin
  if FDoc = nil then Exit;
  for I := 0 to High(FDoc.LayerOrder) do
    if FDoc.LayerOrder[I] = Layer then
    begin
      if I < FScroll then FScroll := I
      else if I >= FScroll + VisibleRows then FScroll := I - VisibleRows + 1;
      Break;
    end;
  ClampScroll;
  Invalidate;
end;

function TLALayerList.RowAt(Y: Integer): Integer;
begin
  Result := -1;
  if (FDoc = nil) or (Y < HEAD_H) then Exit;
  Result := (Y - HEAD_H) div ROW_H + FScroll;
  if Result > High(FDoc.LayerOrder) then Result := -1;
end;

function TLALayerList.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  Result := True;
  if WheelDelta > 0 then Dec(FScroll) else Inc(FScroll);
  ClampScroll;
  Invalidate;
end;

procedure TLALayerList.Paint;
var
  C: TCanvas;
  I, Y, L: Integer;
  Ly: TLALayer;
  R: TRect;
  S: string;
begin
  C := Canvas;
  C.Brush.Color := clWhite;
  C.FillRect(ClientRect);
  C.Font.Size := 8;
  C.Font.Style := [fsBold];
  C.Font.Color := RGBToColor(100, 116, 139);
  C.Brush.Color := RGBToColor(248, 250, 252);
  C.FillRect(0, 0, ClientWidth, HEAD_H);
  C.Brush.Style := bsClear;
  C.TextOut(8, 5, '#');
  C.TextOut(52, 5, 'Modo');
  C.TextOut(128, 5, 'Vel. / Pot.');
  C.TextOut(ColOutput - 6, 5, 'Saida');
  C.TextOut(ColShow - 8, 5, 'Mostrar');
  C.Pen.Color := RGBToColor(226, 232, 240);
  C.Line(0, HEAD_H - 1, ClientWidth, HEAD_H - 1);
  C.Font.Style := [];
  if FDoc = nil then Exit;
  if Length(FDoc.LayerOrder) = 0 then
  begin
    C.Font.Color := RGBToColor(148, 163, 184);
    C.TextOut(10, HEAD_H + 10, 'Nenhuma camada em uso. Desenhe ou importe um objeto.');
    Exit;
  end;
  ClampScroll;
  for I := FScroll to High(FDoc.LayerOrder) do
  begin
    L := FDoc.LayerOrder[I];
    Ly := FDoc.Layers[L];
    Y := HEAD_H + (I - FScroll) * ROW_H;
    if Y > ClientHeight then Break;
    R := Rect(0, Y, ClientWidth, Y + ROW_H);
    C.Brush.Style := bsSolid;
    if L = FSelected then
      C.Brush.Color := RGBToColor(219, 234, 254)
    else if I = FHover then
      C.Brush.Color := RGBToColor(241, 245, 249)
    else
      C.Brush.Color := clWhite;
    C.FillRect(R);
    { cor + numero }
    C.Brush.Color := LayerColor(L);
    C.Pen.Color := LayerColor(L);
    C.RoundRect(6, Y + 4, 42, Y + ROW_H - 4, 6, 6);
    C.Brush.Style := bsClear;
    C.Font.Style := [fsBold];
    C.Font.Color := ContrastText(LayerColor(L));
    S := Format('%.2d', [L]);
    C.TextOut(24 - C.TextWidth(S) div 2, Y + (ROW_H - C.TextHeight(S)) div 2, S);
    C.Font.Style := [];
    C.Font.Color := RGBToColor(15, 23, 42);
    C.TextOut(52, Y + 7, LayerModeName(Ly.Mode));
    if Ly.Calibrated then
    begin
      S := Format('%.0f / %.0f%%', [Ly.Speed, Ly.PowerMax], InvariantFS);
      if Ly.Passes > 1 then S := S + Format('  x%d', [Ly.Passes]);
      C.Font.Color := RGBToColor(51, 65, 85);
    end
    else
    begin
      S := 'calibrar';
      C.Font.Color := RGBToColor(220, 38, 38);
      C.Font.Style := [fsBold];
    end;
    C.TextOut(128, Y + 7, S);
    C.Font.Style := [];
    DrawToggle(C, ColOutput, Y + 6, Ly.Output);
    DrawToggle(C, ColShow, Y + 6, Ly.Show);
    C.Pen.Color := RGBToColor(241, 245, 249);
    C.Line(0, Y + ROW_H - 1, ClientWidth, Y + ROW_H - 1);
  end;
  { barra de rolagem }
  if Length(FDoc.LayerOrder) > VisibleRows then
  begin
    R := Rect(ClientWidth - 6, HEAD_H + 2, ClientWidth - 2, ClientHeight - 2);
    C.Brush.Style := bsSolid;
    C.Brush.Color := RGBToColor(241, 245, 249);
    C.Pen.Style := psClear;
    C.Rectangle(R);
    Y := R.Bottom - R.Top;
    C.Brush.Color := RGBToColor(148, 163, 184);
    C.RoundRect(R.Left, R.Top + Y * FScroll div Length(FDoc.LayerOrder),
      R.Right, R.Top + Y * (FScroll + VisibleRows) div Length(FDoc.LayerOrder), 4, 4);
    C.Pen.Style := psSolid;
  end;
end;

procedure TLALayerList.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  R, L: Integer;
begin
  inherited MouseDown(Button, Shift, X, Y);
  R := RowAt(Y);
  if R < 0 then Exit;
  L := FDoc.LayerOrder[R];
  if (X >= ColOutput - 4) and (X < ColOutput + 34) then
  begin
    FDoc.Layers[L].Output := not FDoc.Layers[L].Output;
    if Assigned(FOnToggle) then FOnToggle(Self, L);
  end
  else if (X >= ColShow - 4) and (X < ColShow + 34) then
  begin
    FDoc.Layers[L].Show := not FDoc.Layers[L].Show;
    if Assigned(FOnToggle) then FOnToggle(Self, L);
  end;
  FSelected := L;
  if Assigned(FOnSelect) then FOnSelect(Self, L);
  Invalidate;
end;

procedure TLALayerList.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  R: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  R := RowAt(Y);
  if R <> FHover then
  begin
    FHover := R;
    Invalidate;
  end;
end;

procedure TLALayerList.MouseLeave;
begin
  inherited MouseLeave;
  FHover := -1;
  Invalidate;
end;

{ ---------------------------------------------------------------------------- }

constructor TLAOriginPicker.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FValue := 6;
  Width := 66;
  Height := 54;
  Cursor := crHandPoint;
end;

procedure TLAOriginPicker.SetValue(V: Integer);
begin
  FValue := EnsureRange(V, 0, 8);
  Invalidate;
end;

procedure TLAOriginPicker.Paint;
var
  I, CX, CY: Integer;
  C: TCanvas;
begin
  C := Canvas;
  C.Brush.Color := Color;
  C.FillRect(ClientRect);
  if Enabled then
    C.Pen.Color := RGBToColor(148, 163, 184)
  else
    C.Pen.Color := RGBToColor(226, 232, 240);
  C.Brush.Style := bsClear;
  C.Rectangle(8, 7, ClientWidth - 8, ClientHeight - 7);
  for I := 0 to 8 do
  begin
    CX := 8 + (I mod 3) * ((ClientWidth - 16) div 2);
    CY := 7 + (I div 3) * ((ClientHeight - 14) div 2);
    C.Brush.Style := bsSolid;
    if (I = FValue) and Enabled then
    begin
      C.Brush.Color := RGBToColor(37, 99, 235);
      C.Pen.Color := RGBToColor(37, 99, 235);
      C.Ellipse(CX - 6, CY - 6, CX + 7, CY + 7);
    end
    else
    begin
      C.Brush.Color := clWhite;
      if Enabled then C.Pen.Color := RGBToColor(148, 163, 184)
      else C.Pen.Color := RGBToColor(226, 232, 240);
      C.Ellipse(CX - 5, CY - 5, CX + 6, CY + 6);
    end;
  end;
end;

procedure TLAOriginPicker.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Col, Row: Integer;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if not Enabled then Exit;
  Col := EnsureRange(Round((X - 8) / ((ClientWidth - 16) / 2)), 0, 2);
  Row := EnsureRange(Round((Y - 7) / ((ClientHeight - 14) / 2)), 0, 2);
  FValue := Row * 3 + Col;
  Invalidate;
  if Assigned(FOnChange) then FOnChange(Self);
end;

{ ---------------------------------------------------------------------------- }

constructor TLAPalette.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  DoubleBuffered := True;
  Cursor := crHandPoint;
end;

function TLAPalette.CellRect(I: Integer): TRect;
var
  W: Integer;
begin
  W := Max(18, Min(30, (ClientWidth - 16) div LA_LAYER_COUNT));
  Result := Rect(8 + I * W, 5, 8 + I * W + W - 3, ClientHeight - 5);
end;

procedure TLAPalette.Paint;
var
  I: Integer;
  R: TRect;
  S: string;
  C: TCanvas;
begin
  C := Canvas;
  C.Brush.Color := Color;
  C.FillRect(ClientRect);
  C.Font.Size := 7;
  for I := 0 to LA_LAYER_COUNT - 1 do
  begin
    R := CellRect(I);
    C.Brush.Style := bsSolid;
    C.Brush.Color := LayerColor(I);
    if I = FCurrent then
    begin
      C.Pen.Color := RGBToColor(15, 23, 42);
      C.Pen.Width := 2;
    end
    else
    begin
      C.Pen.Color := LayerColor(I);
      C.Pen.Width := 1;
    end;
    C.RoundRect(R.Left, R.Top, R.Right, R.Bottom, 5, 5);
    C.Pen.Width := 1;
    C.Brush.Style := bsClear;
    C.Font.Color := ContrastText(LayerColor(I));
    S := Format('%.2d', [I]);
    C.TextOut((R.Left + R.Right - C.TextWidth(S)) div 2, (R.Top + R.Bottom - C.TextHeight(S)) div 2, S);
  end;
end;

procedure TLAPalette.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  I: Integer;
begin
  inherited MouseDown(Button, Shift, X, Y);
  for I := 0 to LA_LAYER_COUNT - 1 do
    if PtInRect(CellRect(I), Point(X, Y)) then
    begin
      FCurrent := I;
      Invalidate;
      if Assigned(FOnPick) then FOnPick(Self, I);
      Exit;
    end;
end;

end.
