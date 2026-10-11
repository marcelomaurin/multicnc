unit laserpcb_layertable;

{ Tabela "Cortes / Camadas" do LaserPCB (estilo LightBurn/RDWorks):
  cor e numero da camada, nome, modo, velocidade/potencia e as chaves
  Saida e Mostrar. Mesmo desenho da lista de camadas do LaserArt.

  O componente so desenha e avisa: quem altera o projeto e a tela. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Types, Controls, Graphics, LCLType,
  laserpcb_project, laserart_model;

type
  TLPLayerEvent = procedure(Sender: TObject; Index: Integer) of object;

  TLPLayerTable = class(TCustomControl)
  private
    FProject: TLaserPCBProject;
    FSelected, FHover, FScroll: Integer;
    FOnSelect, FOnToggle: TLPLayerEvent;
    function RowAt(Y: Integer): Integer;
    function VisibleRows: Integer;
    procedure ClampScroll;
    function ColOutput: Integer;
    function ColShow: Integer;
    procedure SetSelected(Value: Integer);
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure EnsureVisible(Index: Integer);
    property Project: TLaserPCBProject read FProject write FProject;
    property Selected: Integer read FSelected write SetSelected;
    property OnSelectLayer: TLPLayerEvent read FOnSelect write FOnSelect;
    { Saida ou Mostrar trocados pelo clique (o projeto ja foi alterado) }
    property OnToggle: TLPLayerEvent read FOnToggle write FOnToggle;
  end;

function LPContrastText(C: TColor): TColor;

implementation

const
  ROW_H = 28;
  HEAD_H = 24;

function LPContrastText(C: TColor): TColor;
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
  if On then C.Brush.Color := RGBToColor(34, 197, 94)
  else C.Brush.Color := RGBToColor(203, 213, 225);
  C.RoundRect(X, Y, X + 30, Y + 16, 16, 16);
  C.Brush.Color := clWhite;
  if On then C.Ellipse(X + 16, Y + 2, X + 28, Y + 14)
  else C.Ellipse(X + 2, Y + 2, X + 14, Y + 14);
  C.Pen.Style := psSolid;
end;

constructor TLPLayerTable.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FSelected := -1;
  FHover := -1;
  DoubleBuffered := True;
  Color := clWhite;
end;

function TLPLayerTable.ColOutput: Integer;
begin
  Result := ClientWidth - 82;
end;

function TLPLayerTable.ColShow: Integer;
begin
  Result := ClientWidth - 42;
end;

function TLPLayerTable.VisibleRows: Integer;
begin
  Result := Max(1, (ClientHeight - HEAD_H) div ROW_H);
end;

procedure TLPLayerTable.ClampScroll;
begin
  if FProject = nil then FScroll := 0
  else FScroll := EnsureRange(FScroll, 0, Max(0, FProject.OperationCount - VisibleRows));
end;

procedure TLPLayerTable.SetSelected(Value: Integer);
begin
  if FProject = nil then Value := -1
  else if Value >= FProject.OperationCount then Value := FProject.OperationCount - 1;
  FSelected := Value;
  EnsureVisible(Value);
end;

procedure TLPLayerTable.EnsureVisible(Index: Integer);
begin
  if Index >= 0 then
  begin
    if Index < FScroll then FScroll := Index
    else if Index >= FScroll + VisibleRows then FScroll := Index - VisibleRows + 1;
  end;
  ClampScroll;
  Invalidate;
end;

function TLPLayerTable.RowAt(Y: Integer): Integer;
begin
  Result := -1;
  if (FProject = nil) or (Y < HEAD_H) then Exit;
  Result := (Y - HEAD_H) div ROW_H + FScroll;
  if Result >= FProject.OperationCount then Result := -1;
end;

function TLPLayerTable.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  Result := True;
  if WheelDelta > 0 then Dec(FScroll) else Inc(FScroll);
  ClampScroll;
  Invalidate;
end;

procedure TLPLayerTable.Paint;
var
  C: TCanvas;
  I, Y, Row: Integer;
  Op: TLPOperation;
  R: TRect;
  S: string;
  Swatch: TColor;
begin
  C := Canvas;
  C.Brush.Style := bsSolid;
  C.Brush.Color := clWhite;
  C.FillRect(ClientRect);
  C.Font.Size := 8;
  C.Font.Style := [fsBold];
  C.Font.Color := RGBToColor(100, 116, 139);
  C.Brush.Color := RGBToColor(248, 250, 252);
  C.FillRect(0, 0, ClientWidth, HEAD_H);
  C.Brush.Style := bsClear;
  C.TextOut(8, 5, '#');
  C.TextOut(48, 5, 'Camada');
  C.TextOut(ColOutput - 74, 5, 'Vel/Pot');
  C.TextOut(ColOutput - 2, 5, 'Saida');
  C.TextOut(ColShow - 4, 5, 'Ver');
  C.Pen.Color := RGBToColor(226, 232, 240);
  C.Line(0, HEAD_H - 1, ClientWidth, HEAD_H - 1);
  C.Font.Style := [];
  if (FProject = nil) or (FProject.OperationCount = 0) then
  begin
    C.Font.Color := RGBToColor(148, 163, 184);
    C.TextOut(8, HEAD_H + 10, 'Importe a placa para criar as camadas.');
    Exit;
  end;
  ClampScroll;
  for Row := 0 to VisibleRows - 1 do
  begin
    I := Row + FScroll;
    if I >= FProject.OperationCount then Break;
    Op := FProject.Operation(I);
    Y := HEAD_H + Row * ROW_H;
    C.Brush.Style := bsSolid;
    if I = FSelected then C.Brush.Color := RGBToColor(219, 234, 254)
    else if I = FHover then C.Brush.Color := RGBToColor(241, 245, 249)
    else C.Brush.Color := clWhite;
    C.FillRect(0, Y, ClientWidth, Y + ROW_H);
    { cor + numero }
    Swatch := LayerColor(Op.ColorIndex);
    R := Rect(6, Y + 5, 40, Y + ROW_H - 5);
    C.Brush.Color := Swatch;
    C.Pen.Color := RGBToColor(148, 163, 184);
    C.Rectangle(R);
    C.Brush.Style := bsClear;
    C.Font.Size := 8;
    C.Font.Style := [fsBold];
    C.Font.Color := LPContrastText(Swatch);
    S := Format('%.2d', [Op.ColorIndex]);
    C.TextOut(R.Left + (R.Width - C.TextWidth(S)) div 2, R.Top + (R.Height - C.TextHeight(S)) div 2, S);
    { nome e modo }
    C.Font.Style := [];
    C.Font.Color := RGBToColor(15, 23, 42);
    S := Op.Name;
    while (S <> '') and (C.TextWidth(S) > ColOutput - 130) do Delete(S, Length(S), 1);
    C.TextOut(48, Y + 2, S);
    C.Font.Color := RGBToColor(100, 116, 139);
    C.Font.Size := 7;
    S := CamModeName(Op.Mode);
    if Op.Generated then S := S + '  ok';
    C.TextOut(48, Y + 15, S);
    { velocidade / potencia }
    C.Font.Size := 8;
    if (Op.Power <= 0) or (Op.Feed <= 0) or (FProject.Profile.SMax<=0) then
    begin
      C.Font.Color := RGBToColor(220, 38, 38);
      S := 'calibrar';
    end
    else
    begin
      C.Font.Color := RGBToColor(51, 65, 85);
      S := Format('%.0f/%.0f%%', [Op.Feed, 100*Op.Power/FProject.Profile.SMax]);
    end;
    C.TextOut(ColOutput - 74, Y + 7, S);
    DrawToggle(C, ColOutput, Y + 6, Op.Output);
    DrawToggle(C, ColShow, Y + 6, Op.Show);
    C.Pen.Color := RGBToColor(241, 245, 249);
    C.Line(0, Y + ROW_H - 1, ClientWidth, Y + ROW_H - 1);
  end;
  { barra de rolagem }
  if FProject.OperationCount > VisibleRows then
  begin
    C.Brush.Style := bsSolid;
    C.Brush.Color := RGBToColor(203, 213, 225);
    Y := (ClientHeight - HEAD_H) * VisibleRows div FProject.OperationCount;
    I := HEAD_H + (ClientHeight - HEAD_H - Y) * FScroll div Max(1, FProject.OperationCount - VisibleRows);
    C.FillRect(ClientWidth - 3, I, ClientWidth, I + Y);
  end;
end;

procedure TLPLayerTable.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  I: Integer;
  Op: TLPOperation;
begin
  inherited MouseDown(Button, Shift, X, Y);
  if CanFocus then SetFocus;
  I := RowAt(Y);
  if I < 0 then Exit;
  Op := FProject.Operation(I);
  if (X >= ColOutput) and (X < ColOutput + 32) then
  begin
    Op.Output := not Op.Output;
    if Assigned(FOnToggle) then FOnToggle(Self, I);
  end
  else if (X >= ColShow) and (X < ColShow + 32) then
  begin
    Op.Show := not Op.Show;
    if Assigned(FOnToggle) then FOnToggle(Self, I);
  end;
  FSelected := I;
  Invalidate;
  if Assigned(FOnSelect) then FOnSelect(Self, I);
end;

procedure TLPLayerTable.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  I: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  I := RowAt(Y);
  if I <> FHover then
  begin
    FHover := I;
    Invalidate;
  end;
end;

procedure TLPLayerTable.MouseLeave;
begin
  inherited MouseLeave;
  FHover := -1;
  Invalidate;
end;

end.
